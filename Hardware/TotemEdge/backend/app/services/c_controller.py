"""Opt-in local C process, simulated PWM only. Never composed by app.main."""

import asyncio
import math
from pathlib import Path
from typing import Literal
from uuid import UUID

from app.mechanical import ControllerError, MechanicalCommand, MechanicalResponse


class CProcessController:
    """Private stdio capability; reconnect means a new explicit instance, no resend.

    The child must announce SIMULATED. Physical builds refuse startup. This
    adapter must not be attached to an economic DEV profile or production.
    get() is a local snapshot; query(command) consults the retained device ID.
    doorless-v1 is the default and requires an explicit capability handshake;
    legacy-v1 is available only for historical laboratory sequences.
    """

    def __init__(self, process, *, io_timeout_seconds: float):
        self._process = process
        self._io_timeout = io_timeout_seconds
        self._lock = asyncio.Lock()
        self._responses: dict[UUID, MechanicalResponse] = {}
        self._closed = False

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
        process = await asyncio.create_subprocess_exec(
            *args,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
            limit=512,
        )
        self = cls(process, io_timeout_seconds=io_timeout_seconds)
        try:
            async with asyncio.timeout(io_timeout_seconds):
                expected = (
                    b"V1 READY SIMULATED DOORLESS_V1\n"
                    if profile == "doorless-v1"
                    else b"V1 READY SIMULATED\n"
                )
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
            if received != command or parts[9] != "SIMULATED":
                raise ValueError
            result = MechanicalResponse(
                command=received,
                state=parts[6],
                result=parts[7],
                error_code=None if parts[8] == "-" else parts[8],
                source="SIMULATED",
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
        return self._decode(command, parts)

    def get(self, mechanical_command_id: UUID) -> MechanicalResponse:
        try:
            return self._responses[mechanical_command_id]
        except KeyError:
            raise ControllerError("MECHANICAL_COMMAND_NOT_FOUND") from None

    async def query(self, command: MechanicalCommand) -> MechanicalResponse:
        """Explicit read-only device lookup; never restores journal eligibility."""
        command = MechanicalCommand.model_validate(command.model_dump())
        parts = await self._rpc(f"V1 GET {command.mechanical_command_id}")
        return self._decode(command, parts)

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
                source="SIMULATED",
            )
            self._responses[mechanical_command_id] = response
        return response

    async def aclose(self):
        self._closed = True
        if self._process.returncode is None:
            # Only a simulated child can pass connect's handshake. Killing this
            # process is not a physical safe-stop protocol for future hardware.
            try:
                self._process.kill()
            except ProcessLookupError:
                pass
        await self._process.wait()
