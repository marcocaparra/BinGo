"""Existing C IPC, with a durable but execution-blocked operational channel."""

import asyncio
import math
from pathlib import Path
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.mechanical import ControllerError, MechanicalCommand, MechanicalResponse
from app.services.controller import UnavailableController
from app.services.controller_config import (
    CControllerSettings,
    ControllerReadiness,
    PhysicalConfigDiagnostic,
)


class _PreflightModel(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)


class HatchReference(_PreflightModel):
    pwm_label: Literal["PWM3", "PWM4"] | None
    closed_degrees: int
    open_degrees: int
    sysfs_channel: None
    closed_pulse_ns: None
    open_pulse_ns: None


class AssemblyReference(_PreflightModel):
    right: HatchReference
    left: HatchReference


class LegacyPWMEvidence(_PreflightModel):
    commit: Literal["dafc9ab"]
    sysfs_chip: int
    left_channel: int
    right_channel: int
    period_ns: int
    nominal_pulses_ns: tuple[int, int, int]
    drop_seconds: int


class PhysicalPreflight(_PreflightModel):
    """Repository evidence only; cannot authorize dispatch or confirm motion."""

    protocol: Literal["bingo-physical-preflight-v1"]
    build: Literal["PHYSICAL_BLOCKED"]
    ready: Literal[False]
    source: Literal["UNAVAILABLE"]
    physical_confirmed: Literal[False]
    assembly: AssemblyReference
    legacy_evidence: LegacyPWMEvidence
    blockers: tuple[
        Literal["PWM_MAPPING_UNVERIFIED"],
        Literal["PULSE_CALIBRATION_UNVERIFIED"],
        Literal["SAFETY_RECOVERY_UNVERIFIED"],
        Literal["MOTION_CONFIRMATION_UNDEFINED"],
        Literal["PHYSICAL_DISPATCH_DISABLED"],
    ]


class CProcessController:
    """Private stdio capability; reconnect means a new explicit instance, no resend.

    connect() remains laboratory-only. open_operational() requires an explicit
    config and a PHYSICAL_BLOCKED handshake: it can only receive rejections.
    get() is a local snapshot; query(command) consults the retained device ID.
    doorless-v1 is the default and requires an explicit capability handshake;
    legacy-v1 is available only for historical laboratory sequences.
    """

    def __init__(self, process, *, io_timeout_seconds: float, source="SIMULATED"):
        self._process = process
        self._io_timeout = io_timeout_seconds
        self._lock = asyncio.Lock()
        self._responses: dict[UUID, MechanicalResponse] = {}
        self._closed = False
        self._source = source
        self._readiness: ControllerReadiness | None = None

    @property
    def readiness(self) -> ControllerReadiness | None:
        if self._readiness is not None and (
            self._closed or self._process.returncode is not None
        ):
            return self._readiness.model_copy(
                update={
                    "transport": "FAILED",
                    "blockers": self._readiness.blockers + ("CONTROLLER_DISCONNECTED",),
                }
            )
        return self._readiness

    @classmethod
    async def diagnose_operational(cls, config: Path | None, *, backend_journal=None):
        """Read-only assessment; declarations are not homologation or a permit."""
        if config is None:
            return None, ControllerReadiness(
                configuration="NOT_CONFIGURED",
                transport="NOT_CONNECTED",
                blockers=("CONTROLLER_NOT_CONFIGURED",),
            )
        try:
            settings = CControllerSettings.from_file(
                config, backend_journal=backend_journal
            )
        except (OSError, ValueError):
            return None, ControllerReadiness(
                configuration="INVALID",
                transport="NOT_CONNECTED",
                blockers=("INVALID_CONTROLLER_CONFIGURATION",),
            )
        blockers = settings.physical.blockers()
        configuration = "INCOMPLETE" if blockers else "DECLARED"
        try:
            report = await cls.physical_preflight(
                settings.executable, io_timeout_seconds=settings.io_timeout_seconds
            )
            configured = await cls._read_diagnostic(
                settings.executable,
                ["--physical-config", str(config.resolve())],
                schema=PhysicalConfigDiagnostic,
                io_timeout_seconds=settings.io_timeout_seconds,
                error_code="PWM_CONFIGURATION_FAILED",
            )
            if (
                configured.mapping != settings.physical.diagnostic_mapping()
                or configured.period_ns != settings.physical.period_ns
                or configured.polarity != settings.physical.polarity
                or configured.cycle_plan != settings.physical.cycle.plan()
                or configured.configuration != configuration
            ):
                raise ControllerError("PWM_CONFIGURATION_MISMATCH")
        except ControllerError as error:
            return settings, ControllerReadiness(
                configuration=configuration,
                transport="FAILED",
                blockers=blockers + (error.code,),
            )
        return settings, ControllerReadiness(
            configuration=configuration,
            transport="DIAGNOSTIC_OK",
            blockers=tuple(
                dict.fromkeys(
                    (
                        *blockers,
                        *report.blockers,
                        *(
                            ("CYCLE_POLICY_UNVERIFIED",)
                            if not configured.cycle_plan
                            else ()
                        ),
                    )
                )
            ),
            configured_physical=settings.physical,
            cycle_plan=configured.cycle_plan,
        )

    @classmethod
    async def open_operational(cls, config: Path | None, *, backend_journal: Path):
        """Compose the existing controller contract; failures stay UNAVAILABLE.

        The C journal is separate from the Python journal. No fallback to the
        simulated executable, reconnect, replay or startup command is allowed.
        """
        settings, readiness = await cls.diagnose_operational(
            config, backend_journal=backend_journal
        )
        if settings is None or readiness.transport != "DIAGNOSTIC_OK":
            return UnavailableController(), readiness
        try:
            controller = await cls._launch(
                [
                    str(settings.executable.resolve()),
                    "--ipc-physical",
                    str(settings.journal.resolve()),
                    "--profile",
                    settings.profile,
                    "--config",
                    str(config.resolve()),
                ],
                expected=b"V1 READY UNAVAILABLE DOORLESS_V1 PHYSICAL_BLOCKED\n",
                io_timeout_seconds=settings.io_timeout_seconds,
                source="UNAVAILABLE",
            )
        except (OSError, ControllerError, TimeoutError, ValueError) as error:
            return UnavailableController(), readiness.model_copy(
                update={
                    "transport": "FAILED",
                    "blockers": readiness.blockers
                    + (
                        error.code
                        if isinstance(error, ControllerError)
                        else "CONTROLLER_CONNECTION_FAILED",
                    ),
                }
            )
        controller._readiness = readiness.model_copy(
            update={"transport": "CONNECTED_BLOCKED"}
        )
        return controller, controller.readiness

    @staticmethod
    async def physical_preflight(
        executable: Path, *, io_timeout_seconds: float = 2.0
    ) -> PhysicalPreflight:
        """Inspect a blocked physical build without opening either journal.

        This creates no MechanicalController and sends no SUBMIT/GET. It never
        falls back to the laboratory or retries. A successful diagnostic still
        reports ready=False; connect() remains strictly SIMULATED.
        """
        return await CProcessController._read_diagnostic(
            executable,
            ["--physical-preflight"],
            schema=PhysicalPreflight,
            io_timeout_seconds=io_timeout_seconds,
            error_code="PHYSICAL_PREFLIGHT_FAILED",
        )

    @staticmethod
    async def _read_diagnostic(
        executable, arguments, *, schema, io_timeout_seconds, error_code
    ):
        """Shared bounded JSON reader; diagnostics never open operational journals."""
        if not math.isfinite(io_timeout_seconds) or io_timeout_seconds <= 0:
            raise ValueError("Invalid IPC timeout.")
        process = None
        try:
            async with asyncio.timeout(io_timeout_seconds):
                process = await asyncio.create_subprocess_exec(
                    str(executable.resolve()),
                    *arguments,
                    stdin=asyncio.subprocess.DEVNULL,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.DEVNULL,
                    limit=8192,
                )
                raw = b""
                while len(raw) <= 8192:
                    chunk = await process.stdout.read(8193 - len(raw))
                    if not chunk:
                        break
                    raw += chunk
                if len(raw) > 8192 or await process.wait() != 0:
                    raise ValueError("Invalid preflight response.")
                return schema.model_validate_json(raw)
        except (OSError, ValueError, TimeoutError):
            raise ControllerError(error_code) from None
        finally:
            if process is not None:
                if process.returncode is None:
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                await process.wait()

    @classmethod
    async def connect(
        cls,
        executable: Path,
        journal: Path,
        *,
        context: Literal["test", "development"],
        profile: Literal["doorless-v1", "legacy-v1"] = "doorless-v1",
        io_timeout_seconds: float = 2.0,
        delay_ms: int = 0,
        fail_after: int | None = None,
    ):
        if context not in {"test", "development"}:
            raise ValueError("C IPC requires an isolated test/development context.")
        if profile not in {"doorless-v1", "legacy-v1"}:
            raise ValueError("Invalid simulated controller profile.")
        if not math.isfinite(io_timeout_seconds) or io_timeout_seconds <= 0:
            raise ValueError("Invalid IPC timeout.")
        for value in (delay_ms, fail_after):
            if value is not None and (
                type(value) is not int or not 0 <= value <= 60000
            ):
                raise ValueError("Invalid simulated fault option.")
        args = [str(executable.resolve()), "--ipc-simulated", str(journal.resolve())]
        args += ["--profile", profile]
        if delay_ms:
            args += ["--delay-ms", str(delay_ms)]
        if fail_after is not None:
            args += ["--fail-after", str(fail_after)]
        expected = (
            b"V1 READY SIMULATED DOORLESS_V1\n"
            if profile == "doorless-v1"
            else b"V1 READY SIMULATED\n"
        )
        return await cls._launch(
            args,
            expected=expected,
            io_timeout_seconds=io_timeout_seconds,
            source="SIMULATED",
        )

    @classmethod
    async def _launch(cls, args, *, expected, io_timeout_seconds, source):
        process = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
            limit=512,
        )
        self = cls(process, io_timeout_seconds=io_timeout_seconds, source=source)
        try:
            async with asyncio.timeout(io_timeout_seconds):
                if await process.stdout.readline() != expected:
                    raise ControllerError("CONTROLLER_HANDSHAKE_FAILED")
        except BaseException:
            await self.aclose()
            raise
        return self

    async def _rpc(self, line: str) -> list[str]:
        async with self._lock:
            if self._closed:
                raise ControllerError("CONTROLLER_CLOSED")
            try:
                async with asyncio.timeout(self._io_timeout):
                    self._process.stdin.write(line.encode("ascii") + b"\n")
                    await self._process.stdin.drain()
                    raw = await self._process.stdout.readline()
                    if not raw.endswith(b"\n") or len(raw) > 511:
                        raise ControllerError("INCONSISTENT_RESPONSE")
                    parts = raw.decode("ascii").split()
                    if not parts or parts[0] != "V1":
                        raise ControllerError("INCONSISTENT_RESPONSE")
                    return parts
            except BaseException:
                # Poison the stream after a lost response/cancelled read. Never
                # let a late response satisfy another command on this channel.
                await self.aclose()
                raise

    def _decode(self, command: MechanicalCommand, parts: list[str]):
        if len(parts) == 3 and parts[:2] == ["V1", "ERROR"]:
            raise ControllerError(f"C_{parts[2]}")
        try:
            if len(parts) != 10 or parts[:2] != ["V1", "RESULT"]:
                raise ValueError
            received = MechanicalCommand(
                mechanical_command_id=UUID(parts[2]),
                event_id=UUID(parts[3]),
                operation=parts[4],
                timeout_seconds=float(parts[5]),
            )
            if received != command or parts[9] != self._source:
                raise ValueError
            result = MechanicalResponse(
                command=received,
                state=parts[6],
                result=parts[7],
                error_code=None if parts[8] == "-" else parts[8],
                source=self._source,
            )
        except (ValueError, TypeError):
            raise ControllerError("INCONSISTENT_RESPONSE") from None
        previous = self._responses.get(command.mechanical_command_id)
        if previous is not None and previous.command != command:
            raise ControllerError("MECHANICAL_COMMAND_ID_CONFLICT")
        self._responses[command.mechanical_command_id] = result
        return result

    async def submit(self, command: MechanicalCommand) -> MechanicalResponse:
        command = MechanicalCommand.model_validate(command.model_dump())
        previous = self._responses.get(command.mechanical_command_id)
        if previous is not None:
            if previous.command != command:
                raise ControllerError("MECHANICAL_COMMAND_ID_CONFLICT")
            return previous
        parts = await self._rpc(
            f"V1 SUBMIT {command.mechanical_command_id} {command.event_id} "
            f"{command.operation} {format(command.timeout_seconds, '.17g')}"
        )
        if parts == ["V1", "ERROR", "DUPLICATE"]:
            return await self.query(command)
        return await self._checked_decode(command, parts)

    async def _checked_decode(self, command, parts):
        try:
            return self._decode(command, parts)
        except ControllerError as error:
            if error.code == "INCONSISTENT_RESPONSE":
                # A syntactically valid but uncorrelated/false result also
                # poisons this connection. Never consume it on a later command.
                await self.aclose()
            raise

    def get(self, mechanical_command_id: UUID) -> MechanicalResponse:
        try:
            return self._responses[mechanical_command_id]
        except KeyError:
            raise ControllerError("MECHANICAL_COMMAND_NOT_FOUND") from None

    async def query(self, command: MechanicalCommand) -> MechanicalResponse:
        """Explicit read-only device lookup; never restores journal eligibility."""
        command = MechanicalCommand.model_validate(command.model_dump())
        parts = await self._rpc(f"V1 GET {command.mechanical_command_id}")
        return await self._checked_decode(command, parts)

    async def wait(self, mechanical_command_id: UUID) -> MechanicalResponse:
        response = self.get(mechanical_command_id)
        if response.state != "ACCEPTED":
            return response
        # The sequential C process finishes an accepted order before reading GET.
        return await self.query(response.command)

    async def cancel(self, mechanical_command_id: UUID) -> MechanicalResponse:
        response = self.get(mechanical_command_id)
        if response.state == "ACCEPTED":
            # Logical cancellation only. No stop or corrective command is sent.
            await self.aclose()
            response = MechanicalResponse(
                command=response.command,
                state="CANCELLED",
                result="UNKNOWN",
                error_code="EXECUTION_CANCELLED",
                source=self._source,
            )
            self._responses[mechanical_command_id] = response
        return response

    async def aclose(self):
        self._closed = True
        if self._process.returncode is None:
            # Only simulated or execution-blocked children can pass a handshake.
            # Killing this process is not a physical safe-stop protocol.
            try:
                self._process.kill()
            except ProcessLookupError:
                pass
        await self._process.wait()
