"""On-demand device access. No vision calls, GPIO or student navigation."""

import asyncio
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
from typing import Literal, Protocol
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.services.capture import Frame
from app.services.camera_worker import ProcessGuard
from app.services.vision import MAX_IMAGE_BYTES, VisionError, validate_frame


class CameraError(Exception):
    def __init__(self, code: str, status: int = 503, *, diagnostic=None):
        self.code, self.status = code, status
        self.diagnostic = diagnostic
        super().__init__("Operação de câmera não concluída.")


class Device(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")
    device_id: str
    name: str
    locator: str
    identity_kind: Literal["device", "port", "unstable"]


def device(name, locator, kind, fingerprint=""):
    identifier = hashlib.sha256(f"{locator}\0{fingerprint}".encode()).hexdigest()
    return Device(device_id=identifier, name=name, locator=locator, identity_kind=kind)


class Driver(Protocol):
    async def discover(self) -> list[Device]: ...
    async def capture(self, selected: Device) -> Frame: ...


class Illumination(Protocol):
    async def on(self) -> None: ...
    async def off(self) -> None: ...


class NoGPIOIllumination:
    async def on(self):
        pass

    async def off(self):
        pass


async def execute(executable, args, *, timeout=12):
    """Bound pipes and lifetime, including cancellation. Never expose stderr."""
    process = None
    tasks = []
    guard = None

    async def read(stream, limit):
        data = bytearray()
        while chunk := await stream.read(65536):
            data.extend(chunk)
            if len(data) > limit:
                raise CameraError("CAMERA_OUTPUT_LIMIT")
        return bytes(data)

    env = {
        k: v
        for k, v in os.environ.items()
        if not k.upper().startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_"))
    }
    try:
        resolved = shutil.which(executable)
        if resolved is None:
            raise CameraError("CAMERA_DRIVER_NOT_INSTALLED")
        executable = resolved
        try:
            guard = ProcessGuard()
        except OSError:
            raise CameraError("CAMERA_PROCESS_GUARD_UNAVAILABLE") from None
        spawning = asyncio.create_task(
            asyncio.create_subprocess_exec(
                sys._base_executable,
                "-B",
                str(Path(__file__).with_name("camera_worker.py")),
                str(os.getpid()),
                guard.name,
                executable,
                *args,
                stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
                **({"creationflags": 0x08000000} if os.name == "nt" else {}),
            )
        )
        try:
            process = await asyncio.shield(spawning)
        except asyncio.CancelledError:
            # Retain ownership even if cancellation races process creation.
            process = await spawning
            raise
        tasks = [
            asyncio.create_task(read(process.stdout, MAX_IMAGE_BYTES)),
            asyncio.create_task(read(process.stderr, 262144)),
        ]
        async with asyncio.timeout(timeout):
            out, err = await asyncio.gather(*tasks)
            code = await process.wait()
        return code, out, err
    except FileNotFoundError:
        raise CameraError("CAMERA_DRIVER_NOT_INSTALLED") from None
    except PermissionError:
        raise CameraError("CAMERA_PERMISSION_DENIED") from None
    except TimeoutError:
        raise CameraError("CAMERA_TIMEOUT") from None
    finally:
        if process is not None and process.returncode is None:
            try:
                process.kill()
            except ProcessLookupError:
                pass
        if guard is not None:
            guard.close()  # Kill descendants before draining their inherited pipes.
        for task in tasks:
            if not task.done():
                task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        if process is not None:
            # A pipe reader may have hit its limit. Drain/discard after killing;
            # wait() alone can deadlock on a full asyncio subprocess pipe.
            async def discard(stream):
                while await stream.read(65536):
                    pass

            await asyncio.gather(
                discard(process.stdout), discard(process.stderr), process.wait()
            )


class FFmpegDriver:
    def __init__(
        self,
        executable="ffmpeg",
        *,
        platform=sys.platform,
        dev=Path("/dev"),
        sysfs=Path("/sys"),
        runner=execute,
    ):
        self.executable, self.platform = executable, platform
        self.dev, self.sysfs, self.runner = dev, sysfs, runner

    @staticmethod
    def directshow_devices(text):
        result, name = [], None
        for line in text.splitlines():
            match = re.search(r'"(.*)" \(video\)\s*$', line)
            if match:
                name = match[1]
            elif re.search(r'".*" \(audio\)', line):
                name = None
            elif name and (match := re.search(r'Alternative name "(.*)"', line)):
                result.append(device(name, match[1], "device"))
                name = None
        if len({d.device_id for d in result}) != len(result):
            raise CameraError("CAMERA_AMBIGUOUS_IDENTITY")
        return result

    async def discover(self):
        if self.platform == "win32":
            _, _, err = await self.runner(
                self.executable,
                [
                    "-nostdin",
                    "-hide_banner",
                    "-list_devices",
                    "true",
                    "-f",
                    "dshow",
                    "-i",
                    "dummy",
                ],
            )
            return self.directshow_devices(err.decode("utf-8", errors="replace"))
        if not self.platform.startswith("linux"):
            raise CameraError("CAMERA_PLATFORM_UNSUPPORTED")
        result, seen = [], set()
        for folder, kind in (
            ("v4l/by-id", "device"),
            ("v4l/by-path", "port"),
            ("", "unstable"),
        ):
            for path in sorted((self.dev / folder).glob("*" if folder else "video*")):
                target = path.resolve()
                if (
                    target in seen
                    or not target.exists()
                    or not (
                        re.fullmatch(r"video\d+", target.name)
                        or folder
                        and target.is_char_device()
                    )
                ):
                    continue
                seen.add(target)
                try:
                    info = self.sysfs / "class/video4linux" / target.name
                    if target.is_char_device():
                        stat = target.stat()
                        info = (
                            self.sysfs
                            / "dev/char"
                            / f"{os.major(stat.st_rdev)}:{os.minor(stat.st_rdev)}"
                        )
                    name = (info / "name").read_text().strip()
                except OSError:
                    name = target.name
                result.append(device(name, str(path), kind, name))
        return result

    async def capture(self, selected):
        backend = "dshow" if self.platform == "win32" else "v4l2"
        source = f"video={selected.locator}" if backend == "dshow" else selected.locator
        code, out, err = await self.runner(
            self.executable,
            [
                "-nostdin",
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                backend,
                "-i",
                source,
                "-an",
                "-frames:v",
                "1",
                "-vf",
                "scale=w='min(1280,iw)':h='min(960,ih)':force_original_aspect_ratio=decrease",
                "-c:v",
                "mjpeg",
                "-threads",
                "1",
                "-q:v",
                "3",
                "-f",
                "image2pipe",
                "pipe:1",
            ],
        )
        if code or not out:
            diagnostic = {
                "stage": "FFMPEG",
                "exit_code": code,
                "output_bytes": len(out),
                "stderr_sha256": hashlib.sha256(err).hexdigest(),
                "dshow_io_error": b"Error during demuxing: I/O error" in err,
                "mjpeg_range_error": b"Non full-range YUV" in err,
                "encoder_open_error": b"Error while opening encoder" in err,
            }
            message = err.lower()
            code = (
                "CAMERA_PERMISSION_DENIED"
                if any(t in message for t in (b"permission denied", b"access denied"))
                else "CAMERA_BUSY"
                if b"busy" in message
                else "CAMERA_DISCONNECTED"
                if any(
                    t in message
                    for t in (
                        b"no such device",
                        b"no such file",
                        b"device disconnected",
                    )
                )
                else "CAMERA_CAPTURE_FAILED"
            )
            raise CameraError(code, diagnostic=diagnostic)
        return Frame(out, "image/jpeg", simulated=False)


class CameraManager:
    """One process, one capture, durable intent; no image retained on disk."""

    def __init__(self, path: Path, driver: Driver, *, illumination=None):
        self.path, self.driver = path.resolve(), driver
        self.illumination = illumination or NoGPIOIllumination()
        self._running = None
        self._closed = False
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lease = self.path.with_suffix(self.path.suffix + ".lock").open("a+b")
        try:
            # Same OS lease pattern as CycleStore: recovery never touches another worker.
            if os.name == "nt":
                import msvcrt

                if self._lease.tell() == 0:
                    self._lease.write(b"\0")
                    self._lease.flush()
                self._lease.seek(0)
                msvcrt.locking(self._lease.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(self._lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.transaction() as conn:
                application = conn.execute("PRAGMA application_id").fetchone()[0]
                populated = conn.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' LIMIT 1"
                ).fetchone()
                if application != 0x4243414D and (application != 0 or populated):
                    raise CameraError("CAMERA_DATABASE_SCOPE")
                conn.execute("PRAGMA application_id=1111703885")
                conn.execute(
                    "CREATE TABLE IF NOT EXISTS selection (slot INTEGER PRIMARY KEY CHECK(slot=1), device TEXT NOT NULL)"
                )
                conn.execute(
                    "CREATE TABLE IF NOT EXISTS captures (capture_id TEXT PRIMARY KEY, device_id TEXT NOT NULL, phase TEXT NOT NULL, error_code TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"
                )
                conn.execute(
                    "CREATE TABLE IF NOT EXISTS capture_diagnostics (capture_id TEXT PRIMARY KEY REFERENCES captures(capture_id), diagnostic TEXT NOT NULL)"
                )
                conn.execute(
                    "UPDATE captures SET phase='INDETERMINATE', error_code='CAMERA_PROCESS_INTERRUPTED', updated_at=CURRENT_TIMESTAMP WHERE phase='STARTED'"
                )
        except BaseException:
            self._lease.close()
            raise

    @contextmanager
    def transaction(self):
        conn = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        try:
            conn.execute("PRAGMA synchronous=FULL")
            conn.execute("BEGIN IMMEDIATE")
            yield conn
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _idle(self):
        if self._closed:
            raise CameraError("CAMERA_MANAGER_CLOSED")
        if self._running is not None:
            raise CameraError("CAMERA_BUSY", 409)

    async def discover(self):
        self._idle()
        return await self.driver.discover()

    def selection(self):
        with self.transaction() as conn:
            row = conn.execute("SELECT device FROM selection WHERE slot=1").fetchone()
        return Device.model_validate_json(row[0]) if row else None

    async def selected(self):
        return self.selection()

    async def capture_status(self, identifier):
        with self.transaction() as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute(
                "SELECT * FROM captures WHERE capture_id=?", (str(identifier),)
            ).fetchone()
        if row is None:
            raise CameraError("CAPTURE_NOT_FOUND", 404)
        return dict(row)

    async def select(self, identifier):
        self._idle()
        found = next(
            (d for d in await self.discover() if d.device_id == identifier), None
        )
        self._idle()
        if found is None:
            raise CameraError("CAMERA_NOT_FOUND", 404)
        if found.identity_kind == "unstable":
            raise CameraError("CAMERA_STABLE_ID_REQUIRED", 409)
        with self.transaction() as conn:
            conn.execute(
                "INSERT INTO selection VALUES(1,?) ON CONFLICT(slot) DO UPDATE SET device=excluded.device",
                (found.model_dump_json(),),
            )
        return found

    async def status(self):
        selected = self.selection()
        if self._running is not None:
            return {"selection": selected, "present": None, "busy": True}
        devices = await self.discover()
        return {
            "selection": selected,
            "present": selected is not None and selected in devices,
            "busy": False,
        }

    async def activate(self):
        # Protocol compatibility: no stream or handle is retained between calls.
        self._idle()
        if not self.selection():
            raise CameraError("CAMERA_NOT_SELECTED", 409)

    async def deactivate(self):
        # FFmpeg lifetime is scoped to capture(), including errors/cancellation.
        pass

    async def capture(self, capture_id: UUID | None = None):
        self._idle()
        if capture_id is None:
            raise CameraError("CAPTURE_ID_REQUIRED", 422)
        selected = self.selection()
        if selected is None:
            raise CameraError("CAMERA_NOT_SELECTED", 409)
        with self.transaction() as conn:
            if conn.execute(
                "SELECT 1 FROM captures WHERE capture_id=?", (str(capture_id),)
            ).fetchone():
                raise CameraError("CAPTURE_ALREADY_ATTEMPTED", 409)
            conn.execute(
                "INSERT INTO captures(capture_id,device_id,phase) VALUES(?,?,'STARTED')",
                (str(capture_id), selected.device_id),
            )
        self._running = asyncio.current_task()
        phase, error = "FAILED", "CAMERA_CAPTURE_FAILED"
        diagnostic = None
        try:
            devices = await self.driver.discover()
            if selected not in devices:
                raise CameraError("CAMERA_DISCONNECTED")
            await self.illumination.on()
            frame = await self.driver.capture(selected)
            try:
                validate_frame(frame)
            except VisionError:
                raise CameraError("CAMERA_INVALID_IMAGE") from None
            phase, error = "COMPLETED", None
            return frame
        except asyncio.CancelledError:
            phase, error = "INDETERMINATE", "CAMERA_CAPTURE_CANCELLED"
            raise
        except CameraError as exc:
            error = exc.code
            diagnostic = exc.diagnostic or {
                "stage": "CAMERA_MANAGER",
                "exception_type": "CameraError",
                "code": exc.code,
            }
            raise
        except Exception as exc:
            diagnostic = {
                "stage": "CAMERA_MANAGER",
                "exception_type": type(exc).__name__,
            }
            raise CameraError("CAMERA_CAPTURE_FAILED") from None
        finally:
            try:
                await self.illumination.off()
            finally:
                try:
                    with self.transaction() as conn:
                        conn.execute(
                            "UPDATE captures SET phase=?,error_code=?,updated_at=CURRENT_TIMESTAMP WHERE capture_id=?",
                            (phase, error, str(capture_id)),
                        )
                        if diagnostic is not None:
                            conn.execute(
                                "INSERT INTO capture_diagnostics VALUES(?,?)",
                                (str(capture_id), json.dumps(diagnostic)),
                            )
                finally:
                    self._running = None

    async def aclose(self):
        self._closed = True
        task = self._running
        if task is not None and task is not asyncio.current_task():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        self._lease.close()
