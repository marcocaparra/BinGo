"""Coordenação privada journal/controller; sem transições operacionais positivas."""

import asyncio
from typing import Literal
from uuid import UUID, uuid5, NAMESPACE_URL

from pydantic import ValidationError

from app.mechanical import (
    ControllerError,
    MechanicalCommand,
    MechanicalController,
    MechanicalResponse,
)
from app.cycles import CycleError
from app.mechanical_journal import JournalEntry
from app.storage import CycleStore
from app.services.controller import SimulatedController


class MechanicalService:
    def __init__(
        self,
        store: CycleStore,
        controller: MechanicalController,
        *,
        source: Literal["UNAVAILABLE", "SIMULATED"],
        auto_initial: bool = False,
    ):
        # PHYSICAL continua sem despacho autorizado neste incremento.
        if source not in {"UNAVAILABLE", "SIMULATED"}:
            raise ValueError("Controller físico ainda não homologado.")
        self.store = store
        self.controller = controller
        self.source = source
        if auto_initial and (source != "SIMULATED" or not store.simulation_enabled):
            raise ValueError("Confirmação automática exige simulação isolada.")
        self.auto_initial = auto_initial
        self._tasks: dict[UUID, asyncio.Task[None]] = {}
        self._dispatches: dict[UUID, asyncio.Task] = {}
        self._closed = False

    @staticmethod
    def initial_identifier(event_id: UUID) -> UUID:
        return uuid5(NAMESPACE_URL, f"bingo:dev:confirm-initial:{event_id}")

    async def resume_initial(self):
        """Startup/event orchestration only. GETs never invoke this method."""
        if not self.auto_initial or self._closed:
            return
        with self.store.transaction() as conn:
            events = [
                UUID(row[0])
                for row in conn.execute(
                    "SELECT event_id FROM cycles WHERE simulated=1 AND active_slot=1 AND state='HATCH_IN_PROGRESS' AND physical_confirmed=0 AND receipt IS NULL"
                )
            ]
        for event_id in events:
            await self._ensure_initial(event_id)

    async def _ensure_initial(self, event_id: UUID):
        if not self.auto_initial or self._closed:
            return
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event_id)
            if (
                row["state"] != "HATCH_IN_PROGRESS"
                or row["active_slot"] != 1
                or row["physical_confirmed"]
                or any(
                    row[field] is not None
                    for field in ("payload", "receipt", "central_scope")
                )
                or self.store.mechanical.has_risk(conn, event_id)
            ):
                return
            if not self.store._simulated_hatch_completed(conn, event_id):
                return
            # Any prior attempt, including rejected/aborted/unknown, is a durable
            # barrier. Startup must not turn uncertainty into a fresh dispatch.
            if conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE event_id=? AND operation='CONFIRM_INITIAL_STATE'",
                (str(event_id),),
            ).fetchone():
                return
        try:
            await self.submit(
                MechanicalCommand(
                    event_id=event_id,
                    mechanical_command_id=self.initial_identifier(event_id),
                    operation="CONFIRM_INITIAL_STATE",
                )
            )
        except (CycleError, ControllerError):
            # A concurrent explicit request may win. Its durable attempt is the
            # barrier, never a reason to generate another command identifier.
            with self.store.transaction() as conn:
                existing = conn.execute(
                    "SELECT 1 FROM mechanical_commands WHERE event_id=? AND operation='CONFIRM_INITIAL_STATE'",
                    (str(event_id),),
                ).fetchone()
            if not existing:
                raise

    async def _completed(self, entry: JournalEntry):
        if (
            entry.source == "SIMULATED"
            and entry.phase == "COMPLETED"
            and entry.result == "SUCCEEDED"
            and entry.command.operation == "CYCLE_LOWER_HATCH"
        ):
            await self._ensure_initial(entry.command.event_id)

    def get(self, identifier: UUID) -> JournalEntry:
        return self.store.mechanical.get(identifier)

    async def submit(
        self, command: MechanicalCommand, *, hand_removed: bool = False
    ) -> JournalEntry:
        if self._closed:
            raise ControllerError("CONTROLLER_CLOSED")
        entry, created = self.store.mechanical.request(
            command, source=self.source, hand_removed=hand_removed
        )
        if not created:
            # Inclusive INTENT: replay nunca reivindica despacho pendente.
            return entry
        entry = self.store.mechanical.claim(
            command.mechanical_command_id, version=entry.version
        )
        self._dispatches[command.mechanical_command_id] = asyncio.current_task()
        try:
            return await self._dispatch(entry)
        finally:
            self._dispatches.pop(command.mechanical_command_id, None)

    async def _dispatch(self, entry: JournalEntry) -> JournalEntry:
        command = entry.command
        # O simulador existente usa planos/relógio lógico próprios, inclusive
        # relógio manual em testes. Não competir com ele usando tempo de parede.
        deadline = (
            None
            if isinstance(self.controller, SimulatedController)
            else asyncio.get_running_loop().time() + command.timeout_seconds
        )
        try:
            async with asyncio.timeout_at(deadline) as timeout:
                response = await self.controller.submit(command)
            if timeout.expired() or (
                deadline is not None and asyncio.get_running_loop().time() >= deadline
            ):
                raise TimeoutError
        except TimeoutError:
            # Sem aceite durável, não fabricar ACCEPTED nem rejeição sem efeito.
            return self.store.mechanical.unknown(
                command.mechanical_command_id,
                version=entry.version,
                code="DISPATCH_TIMEOUT",
            )
        except asyncio.CancelledError:
            self.store.mechanical.unknown(
                command.mechanical_command_id,
                version=entry.version,
                code="DISPATCH_CANCELLED",
            )
            raise
        except Exception:
            return self.store.mechanical.unknown(
                command.mechanical_command_id,
                version=entry.version,
                code="DISPATCH_RESULT_UNKNOWN",
            )
        try:
            entry = self.store.mechanical.observe(
                command.mechanical_command_id, response, version=entry.version
            )
        except (
            ControllerError,
            CycleError,
            ValidationError,
            AttributeError,
            TypeError,
        ):
            return self.store.mechanical.unknown(
                command.mechanical_command_id,
                version=entry.version,
                code="INCONSISTENT_RESPONSE",
            )
        if entry.phase == "ACCEPTED":
            task = asyncio.create_task(
                self._finish(entry, deadline),
                name=f"mechanical-journal-{command.mechanical_command_id}",
            )
            self._tasks[command.mechanical_command_id] = task
            task.add_done_callback(
                lambda completed: self._finished(
                    command.mechanical_command_id, completed
                )
            )
        elif entry.phase == "COMPLETED":
            await self._completed(entry)
        return entry

    def _finished(self, identifier, task):
        # Guardar tarefas que falharam em persistir para wait() expor o erro;
        # consumir a exceção também evita warning se ninguém estiver aguardando.
        if not task.cancelled() and task.exception() is None:
            self._tasks.pop(identifier, None)

    async def _finish(self, entry: JournalEntry, deadline: float | None):
        identifier = entry.command.mechanical_command_id
        try:
            async with asyncio.timeout_at(deadline) as timeout:
                response = await self.controller.wait(identifier)
            if timeout.expired() or (
                deadline is not None and asyncio.get_running_loop().time() >= deadline
            ):
                raise TimeoutError
        except TimeoutError:
            # Expirar a consulta não para o mecanismo nem comprova sua posição.
            response = MechanicalResponse(
                command=entry.command,
                source=entry.source,
                state="TIMED_OUT",
                result="UNKNOWN",
                error_code="EXECUTION_TIMEOUT",
            )
        except asyncio.CancelledError:
            self.store.mechanical.unknown(
                identifier, version=entry.version, code="COORDINATOR_CANCELLED"
            )
            return
        except Exception:
            self.store.mechanical.unknown(
                identifier, version=entry.version, code="EXECUTION_RESULT_UNKNOWN"
            )
            return
        try:
            if response.state == "ACCEPTED":
                # wait deve concluir a observação, não repetir somente o aceite.
                raise ControllerError("MECHANICAL_STALE_RESPONSE")
            completed = self.store.mechanical.observe(
                identifier, response, version=entry.version
            )
        except (
            ControllerError,
            CycleError,
            ValidationError,
            AttributeError,
            TypeError,
        ):
            self.store.mechanical.unknown(
                identifier, version=entry.version, code="INCONSISTENT_RESPONSE"
            )
            return
        await self._completed(completed)

    async def wait(self, identifier: UUID) -> JournalEntry:
        task = self._tasks.get(identifier)
        if task is not None:
            await asyncio.shield(task)
        return self.get(identifier)

    async def cancel(self, identifier: UUID) -> JournalEntry:
        entry = self.get(identifier)
        if entry.phase != "ACCEPTED" or identifier not in self._tasks:
            return entry
        await self.controller.cancel(identifier)
        return await self.wait(identifier)

    async def aclose(self):
        self._closed = True
        try:
            await self.controller.aclose()
        finally:
            dispatches = tuple(self._dispatches.values())
            for task in dispatches:
                task.cancel()
            await asyncio.gather(*dispatches, return_exceptions=True)
            tasks = tuple(self._tasks.items())
            for _, task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*(task for _, task in tasks), return_exceptions=True)
            for identifier, _ in tasks:
                entry = self.get(identifier)
                if entry.phase in {"DISPATCHING", "ACCEPTED"}:
                    self.store.mechanical.unknown(
                        identifier,
                        version=entry.version,
                        code="SHUTDOWN_DURING_COMMAND",
                    )
            self._tasks.clear()
