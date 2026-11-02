"""Fictitious devices only. No webcam, FFmpeg binary or external services."""

import asyncio
from io import BytesIO
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
from uuid import uuid4

from PIL import Image
import pytest

from app.services.camera import (
    CameraError,
    CameraManager,
    FFmpegDriver,
    device,
    execute,
)
from app.services.capture import Frame

pytestmark = pytest.mark.anyio


def image():
    buffer = BytesIO()
    Image.new("RGB", (24, 18), "green").save(buffer, format="JPEG")
    return buffer.getvalue()


class DriverFixture:
    def __init__(self):
        self.devices = [device("Synthetic camera", "synthetic:serial-one", "device")]
        self.calls = 0
        self.error = None
        self.gate = None
        self.started = asyncio.Event()
        self.released = 0
        self.content = image()
        self.simulated = True

    async def discover(self):
        return list(self.devices)

    async def capture(self, selected):
        self.calls += 1
        self.started.set()
        try:
            if self.gate:
                await self.gate.wait()
            if self.error:
                raise self.error
            return Frame(self.content, "image/jpeg", simulated=self.simulated)
        finally:
            self.released += 1


class LightFixture:
    def __init__(self):
        self.states = []

    async def on(self):
        self.states.append("on")

    async def off(self):
        self.states.append("off")


async def prepared(tmp_path, **kwargs):
    driver = DriverFixture()
    manager = CameraManager(tmp_path / "camera.sqlite3", driver, **kwargs)
    await manager.select(driver.devices[0].device_id)
    return manager, driver


async def test_selection_and_reconnect_survive_restart_without_fallback(tmp_path):
    manager, driver = await prepared(tmp_path)
    selected = manager.selection()
    assert driver.calls == 0
    await manager.aclose()
    manager = CameraManager(tmp_path / "camera.sqlite3", driver)
    try:
        assert manager.selection() == selected
        driver.devices = [device("Other", "synthetic:serial-two", "device")]
        assert not (await manager.status())["present"]
        with pytest.raises(CameraError, match="Operação") as error:
            await manager.capture(uuid4())
        assert error.value.code == "CAMERA_DISCONNECTED"
        assert driver.calls == 0 and manager.selection() == selected
        driver.devices.append(selected)
        await manager.capture(uuid4())
        assert driver.calls == driver.released == 1
    finally:
        await manager.aclose()


async def test_capture_validates_and_releases_without_saving_image(tmp_path):
    light = LightFixture()
    manager, driver = await prepared(tmp_path, illumination=light)
    identifier = uuid4()
    try:
        frame = await manager.capture(identifier)
        assert frame.content == image() and frame.simulated
        assert light.states == ["on", "off"]
        with pytest.raises(CameraError) as error:
            await manager.capture(identifier)
        assert error.value.code == "CAPTURE_ALREADY_ATTEMPTED"
        assert driver.calls == 1
        with manager.transaction() as conn:
            assert (
                conn.execute("SELECT phase FROM captures").fetchone()[0] == "COMPLETED"
            )
        assert not any(
            p.suffix in {".jpg", ".png", ".jpeg"} for p in tmp_path.iterdir()
        )
        assert image() not in manager.path.read_bytes()
    finally:
        await manager.aclose()


@pytest.mark.parametrize(
    "failure", ["disconnected", "busy", "permission", "invalid", "exception", "timeout"]
)
async def test_failures_release_and_never_retry_same_intent(tmp_path, failure):
    light = LightFixture()
    manager, driver = await prepared(tmp_path, illumination=light)
    identifier = uuid4()
    if failure == "invalid":
        driver.content = b"not-an-image"
    else:
        driver.error = (
            CameraError("CAMERA_" + failure.upper())
            if failure != "exception"
            else RuntimeError("sensitive driver stderr")
        )
    try:
        with pytest.raises(CameraError):
            await manager.capture(identifier)
        with pytest.raises(CameraError) as error:
            await manager.capture(identifier)
        assert error.value.code == "CAPTURE_ALREADY_ATTEMPTED"
        assert light.states == ["on", "off"] and driver.released == 1
    finally:
        await manager.aclose()


async def test_concurrency_and_shutdown_release_owned_capture(tmp_path):
    manager, driver = await prepared(tmp_path)
    driver.gate = asyncio.Event()
    task = asyncio.create_task(manager.capture(uuid4()))
    await driver.started.wait()
    for operation in (
        manager.capture(uuid4()),
        manager.select(driver.devices[0].device_id),
    ):
        with pytest.raises(CameraError) as error:
            await operation
        assert error.value.code == "CAMERA_BUSY"
    assert (await manager.status())["busy"]
    await manager.aclose()
    assert task.cancelled() and driver.released == 1


async def test_restart_blocks_attempt_after_durable_started_intent(tmp_path):
    manager, driver = await prepared(tmp_path)
    identifier = uuid4()
    selected = manager.selection()
    with manager.transaction() as conn:
        conn.execute(
            "INSERT INTO captures(capture_id,device_id,phase) VALUES(?,?,'STARTED')",
            (str(identifier), selected.device_id),
        )
    await manager.aclose()
    manager = CameraManager(tmp_path / "camera.sqlite3", driver)
    try:
        with pytest.raises(CameraError):
            await manager.capture(identifier)
        with manager.transaction() as conn:
            assert (
                conn.execute("SELECT phase FROM captures").fetchone()[0]
                == "INDETERMINATE"
            )
        assert driver.calls == 0
    finally:
        await manager.aclose()


async def test_database_lease_and_scope(tmp_path):
    manager, _ = await prepared(tmp_path)
    try:
        with pytest.raises(OSError):
            CameraManager(manager.path, DriverFixture())
    finally:
        await manager.aclose()
    path = tmp_path / "unrelated.sqlite3"
    with sqlite3.connect(path) as conn:
        conn.execute("CREATE TABLE persistent_dev (value TEXT)")
    before = path.read_bytes()
    with pytest.raises(CameraError):
        CameraManager(path, DriverFixture())
    assert path.read_bytes() == before


async def test_selection_rejects_unknown_and_unstable_identity(tmp_path):
    manager, driver = await prepared(tmp_path)
    try:
        with pytest.raises(CameraError):
            await manager.select("f" * 64)
        driver.devices = [device("Camera 0", "/dev/video0", "unstable")]
        with pytest.raises(CameraError) as error:
            await manager.select(driver.devices[0].device_id)
        assert error.value.code == "CAMERA_STABLE_ID_REQUIRED"
    finally:
        await manager.aclose()


async def test_directshow_uses_alternative_names_not_numeric_indices():
    listing = "\n".join(
        [
            '[dshow] "Same name" (video)',
            '[dshow] Alternative name "@device_pnp_first"',
            '[dshow] "Same name" (video)',
            '[dshow] Alternative name "@device_pnp_second"',
            '[dshow] "Microphone" (audio)',
            '[dshow] Alternative name "@audio"',
        ]
    )
    calls = []

    async def runner(executable, args):
        calls.append(args)
        return (
            (1, b"", listing.encode()) if "-list_devices" in args else (0, image(), b"")
        )

    driver = FFmpegDriver(platform="win32", runner=runner)
    found = await driver.discover()
    assert len(found) == 2 and found[0].device_id != found[1].device_id
    frame = await driver.capture(found[1])
    assert not frame.simulated and "video=@device_pnp_second" in calls[-1]
    assert "-video_device_number" not in calls[-1]


async def test_empty_ffmpeg_success_is_diagnosed_privately(tmp_path):
    async def runner(executable, args):
        return 0, b"", b"Error during demuxing: I/O error secret-device-path"

    manager, fixture = await prepared(tmp_path)

    class FailingDriver:
        async def discover(self):
            return fixture.devices

        async def capture(self, selected):
            return await FFmpegDriver(platform="win32", runner=runner).capture(selected)

    manager.driver = FailingDriver()
    identifier = uuid4()
    try:
        with pytest.raises(CameraError) as error:
            await manager.capture(identifier)
        assert error.value.code == "CAMERA_CAPTURE_FAILED"
        assert not (await manager.status())["busy"]
        assert "diagnostic" not in await manager.capture_status(identifier)
        with manager.transaction() as conn:
            diagnostic = conn.execute(
                "SELECT diagnostic FROM capture_diagnostics WHERE capture_id=?",
                (str(identifier),),
            ).fetchone()[0]
        assert (
            "secret-device-path" not in diagnostic
            and '"dshow_io_error": true' in diagnostic
        )
        with pytest.raises(CameraError) as replay:
            await manager.capture(identifier)
        assert replay.value.code == "CAPTURE_ALREADY_ATTEMPTED"
    finally:
        await manager.aclose()


async def test_v4l2_discovers_stable_links_and_deduplicates_nodes(
    tmp_path, monkeypatch
):
    dev, sysfs = tmp_path / "dev", tmp_path / "sys"
    (dev / "v4l/by-id").mkdir(parents=True)
    (dev / "v4l/by-path").mkdir(parents=True)
    (dev / "video8").touch()
    info = sysfs / "class/video4linux/video8"
    info.mkdir(parents=True)
    (info / "name").write_text("Synthetic UVC")
    (dev / "v4l/by-id/usb-serial-one").touch()
    (dev / "v4l/by-path/port-one").touch()
    # Model udev links without requiring Windows symlink privileges.
    original = Path.resolve
    monkeypatch.setattr(
        Path,
        "resolve",
        lambda p: (
            original(dev / "video8")
            if p.name in {"usb-serial-one", "port-one"}
            else original(p)
        ),
    )
    found = await FFmpegDriver(platform="linux", dev=dev, sysfs=sysfs).discover()
    assert len(found) == 1 and found[0].identity_kind == "device"
    assert found[0].name == "Synthetic UVC" and "usb-serial-one" in found[0].locator


@pytest.mark.parametrize(
    "text,code",
    [
        (b"Device busy", "CAMERA_BUSY"),
        (b"Permission denied", "CAMERA_PERMISSION_DENIED"),
        (b"No such device", "CAMERA_DISCONNECTED"),
        (b"private driver error", "CAMERA_CAPTURE_FAILED"),
    ],
)
async def test_ffmpeg_errors_are_sanitized(text, code):
    async def runner(*args):
        return 1, b"", text

    with pytest.raises(CameraError) as error:
        await FFmpegDriver(runner=runner).capture(
            device("Camera", "/dev/video7", "device")
        )
    assert error.value.code == code and text.decode() not in str(error.value)


async def test_subprocess_timeout_and_output_limit_are_bounded():
    with pytest.raises(CameraError) as error:
        await execute(
            sys._base_executable,
            ["-B", "-c", "import time;time.sleep(30)"],
            timeout=0.2,
        )
    assert error.value.code == "CAMERA_TIMEOUT"
    with pytest.raises(CameraError) as error:
        await execute(
            sys._base_executable,
            ["-B", "-c", "import sys;sys.stdout.buffer.write(b'x'*6000000)"],
            timeout=5,
        )
    assert error.value.code == "CAMERA_OUTPUT_LIMIT"


async def test_missing_driver_reports_unavailable_without_launching_device():
    with pytest.raises(CameraError) as error:
        await execute("bingo-missing-executable-" + uuid4().hex, [])
    assert error.value.code == "CAMERA_DRIVER_NOT_INSTALLED"


async def test_process_crash_preserves_device_and_never_repeats_capture(tmp_path):
    manager, driver = await prepared(tmp_path)
    selection = manager.selection()
    await manager.aclose()
    identifier = uuid4()
    ready = tmp_path / "ready"
    script = """
import asyncio,sys
from pathlib import Path
from uuid import UUID
from app.services.camera import CameraManager, device
class BlockingDriver:
    async def discover(self):
        return [device('Synthetic camera', 'synthetic:serial-one', 'device')]
    async def capture(self, selected):
        Path(sys.argv[3]).write_text('ready')
        await asyncio.Event().wait()
async def run():
    driver=BlockingDriver()
    manager=CameraManager(Path(sys.argv[1]),driver)
    await manager.capture(UUID(sys.argv[2]))
asyncio.run(run())
"""
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_"))
    }
    env["PYTHONPATH"] = os.pathsep.join(
        [str(Path(__file__).parent), *[p for p in sys.path if p]]
    )
    process = subprocess.Popen(
        [
            sys._base_executable,
            "-B",
            "-c",
            script,
            str(tmp_path / "camera.sqlite3"),
            str(identifier),
            str(ready),
        ],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    try:
        for _ in range(100):
            if ready.exists() or process.poll() is not None:
                break
            await asyncio.sleep(0.1)
        assert ready.exists(), "Owned synthetic child did not reach durable capture"
        process.kill()
        process.wait(timeout=5)
        manager = CameraManager(tmp_path / "camera.sqlite3", driver)
        try:
            assert manager.selection() == selection
            assert (await manager.capture_status(identifier))[
                "phase"
            ] == "INDETERMINATE"
            with pytest.raises(CameraError) as error:
                await manager.capture(identifier)
            assert error.value.code == "CAPTURE_ALREADY_ATTEMPTED" and driver.calls == 0
        finally:
            await manager.aclose()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)


async def test_cancellation_kills_and_reaps_native_child(tmp_path):
    ready = tmp_path / "child-pid"
    script = "import os,pathlib,sys,time;p=pathlib.Path(sys.argv[1]);t=p.with_suffix('.tmp');t.write_text(str(os.getpid()));t.replace(p);time.sleep(30)"
    task = asyncio.create_task(
        execute(sys._base_executable, ["-B", "-c", script, str(ready)], timeout=10)
    )
    try:
        for _ in range(50):
            if ready.exists():
                break
            await asyncio.sleep(0.05)
        assert ready.exists()
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
    pid = int(ready.read_text())
    if os.name == "nt":
        import ctypes

        kernel = ctypes.windll.kernel32
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x100000, False, pid)
        if handle:
            try:
                assert kernel.WaitForSingleObject(handle, 0) == 0
            finally:
                kernel.CloseHandle(handle)
    else:
        with pytest.raises(ProcessLookupError):
            os.kill(pid, 0)
