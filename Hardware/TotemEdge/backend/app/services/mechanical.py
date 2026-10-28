"""Coordenação privada journal/controller; sem transições operacionais positivas."""

import asyncio
from typing import Literal
from uuid import UUID

from pydantic import ValidationError

from app.mechanical import ControllerError, MechanicalCommand, MechanicalController
from app.cycles import CycleError
from app.mechanical_journal import JournalEntry
from app.storage import CycleStore


class MechanicalService:
    def __init__(
        self,
        store: CycleStore,
        controller: MechanicalController,
        *,
        source: Literal["UNAVAILABLE", "SIMULATED"],
    ):
        # PHYSICAL continua sem despacho autorizado neste incremento.
        if source not in {"UNAVAILABLE", "SIMULATED"}:
            raise ValueError("Controller físico ainda não homologado.")
        self.store = store
        self.controller = controller
        self.source = source
        self._tasks: dict[UUID, asyncio.Task[None]] = {}
        self._dispatches: dict[UUID, asyncio.Task] = {}
        self._closed = False

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
        try:
            response = await self.controller.submit(command)
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
                self._finish(entry),
                name=f"mechanical-journal-{command.mechanical_command_id}",
            )
            self._tasks[command.mechanical_command_id] = task
            task.add_done_callback(
                lambda completed: self._finished(
                    command.mechanical_command_id, completed
                )
            )
        return entry

    def _finished(self, identifier, task):
        # Guardar tarefas que falharam em persistir para wait() expor o erro;
        # consumir a exceção também evita warning se ninguém estiver aguardando.
        if not task.cancelled() and task.exception() is None:
            self._tasks.pop(identifier, None)

    async def _finish(self, entry: JournalEntry):
        identifier = entry.command.mechanical_command_id
        try:
            response = await self.controller.wait(identifier)
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
            self.store.mechanical.observe(identifier, response, version=entry.version)
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
