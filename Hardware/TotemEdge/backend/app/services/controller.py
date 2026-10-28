"""Controllers lógicos em memória. Nenhum import/acionamento de hardware.

Somente para o loop assíncrono da aplicação. O controller real precisará do
journal durável do Incremento 2 antes de qualquer despacho físico.
"""

import asyncio
from collections.abc import Awaitable, Callable, Mapping
from types import MappingProxyType
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.mechanical import (
    ControllerError,
    MechanicalCommand,
    MechanicalResponse,
    Operation,
    checked_response,
)


class SimulationPlan(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)

    duration_seconds: float = Field(ge=0, allow_inf_nan=False)
    outcome: Literal["SUCCEEDED", "FAILURE", "UNAVAILABLE", "TIMEOUT"] = "SUCCEEDED"


DEFAULT_PLANS: Mapping[Operation, SimulationPlan] = MappingProxyType(
    {
        "OPEN_INSERTION_DOOR": SimulationPlan(duration_seconds=3.0),
        "CLOSE_INSERTION_DOOR": SimulationPlan(duration_seconds=3.0),
        "CYCLE_LOWER_HATCH": SimulationPlan(duration_seconds=4.0),
        "CONFIRM_INITIAL_STATE": SimulationPlan(duration_seconds=1.0),
    }
)


class _MemoryController:
    """Retenção limitada sem eviction: replay não pode executar novamente.

    Métodos sem await entre leitura/escrita são atômicos no mesmo event loop.
    Não é um journal nem base para despacho de hardware real.
    """

    def __init__(self, *, max_commands: int = 1024):
        if type(max_commands) is not int or max_commands <= 0:
            raise ValueError("Capacidade mecânica inválida.")
        self._max_commands = max_commands
        self._responses: dict[UUID, MechanicalResponse] = {}
        self._tasks: dict[UUID, asyncio.Task[None]] = {}
        self._closed = False

    def _previous(self, command: MechanicalCommand) -> MechanicalResponse | None:
        # Não confiar em instâncias construídas sem validação pelo chamador.
        MechanicalCommand.model_validate(command.model_dump())
        previous = self._responses.get(command.mechanical_command_id)
        if previous is not None:
            if previous.command != command:
                raise ControllerError("MECHANICAL_COMMAND_ID_CONFLICT")
            return previous
        if self._closed:
            raise ControllerError("CONTROLLER_CLOSED")
        if len(self._responses) >= self._max_commands:
            raise ControllerError("COMMAND_CAPACITY_REACHED")
        return None

    def get(self, mechanical_command_id: UUID) -> MechanicalResponse:
        try:
            return self._responses[mechanical_command_id]
        except KeyError:
            raise ControllerError("MECHANICAL_COMMAND_NOT_FOUND") from None

    async def wait(self, mechanical_command_id: UUID) -> MechanicalResponse:
        self.get(mechanical_command_id)
        task = self._tasks.get(mechanical_command_id)
        if task is not None:
            # Abandonar uma consulta não cancela a operação aceita.
            try:
                await asyncio.shield(task)
            except asyncio.CancelledError:
                if asyncio.current_task().cancelling():
                    raise
                # cancel() também pode ocorrer antes do início da coroutine.
        return self.get(mechanical_command_id)

    async def cancel(self, mechanical_command_id: UUID) -> MechanicalResponse:
        response = self.get(mechanical_command_id)
        task = self._tasks.get(mechanical_command_id)
        if task is not None:
            # Inclusive se a coroutine ainda não iniciou. Cancelar não comprova
            # que um comando aceito deixou de executar no dispositivo futuro.
            self._responses[mechanical_command_id] = MechanicalResponse(
                command=response.command,
                state="CANCELLED",
                result="UNKNOWN",
                source="SIMULATED",
                error_code="EXECUTION_CANCELLED",
            )
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            self._tasks.pop(mechanical_command_id, None)
        return self.get(mechanical_command_id)

    async def aclose(self) -> None:
        self._closed = True
        # Marcar todos antes de aguardar; nenhum novo submit entra no shutdown.
        identifiers = tuple(self._tasks)
        for identifier in identifiers:
            await self.cancel(identifier)


class UnavailableController(_MemoryController):
    """Padrão operacional: recusa sem aceitação ou confirmação fictícia."""

    async def submit(self, command: MechanicalCommand) -> MechanicalResponse:
        previous = self._previous(command)
        if previous is not None:
            return previous
        response = MechanicalResponse(
            command=command,
            state="REJECTED",
            result="UNAVAILABLE",
            source="UNAVAILABLE",
            error_code="CONTROLLER_UNAVAILABLE",
        )
        self._responses[command.mechanical_command_id] = response
        return response


class SimulatedController(_MemoryController):
    """Simulador explicitamente isolado, uma execução por vez, sem fila/retry."""

    def __init__(
        self,
        *,
        context: Literal["development", "test"],
        plans: Mapping[Operation, SimulationPlan] | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        max_commands: int = 1024,
    ):
        if context not in {"development", "test"}:
            raise ValueError(
                "Simulação exige contexto isolado de desenvolvimento/teste."
            )
        super().__init__(max_commands=max_commands)
        self._plans = dict(DEFAULT_PLANS)
        if plans is not None:
            for operation, plan in plans.items():
                if operation not in DEFAULT_PLANS or not isinstance(
                    plan, SimulationPlan
                ):
                    raise ValueError("Plano de simulação inválido.")
                self._plans[operation] = SimulationPlan.model_validate(
                    plan.model_dump()
                )
        self._sleep = sleep

    async def submit(self, command: MechanicalCommand) -> MechanicalResponse:
        previous = self._previous(command)
        if previous is not None:
            return previous
        plan = self._plans[command.operation]
        if self._tasks or plan.outcome == "UNAVAILABLE":
            response = MechanicalResponse(
                command=command,
                state="REJECTED",
                result="UNAVAILABLE",
                source="SIMULATED",
                error_code="CONTROLLER_BUSY"
                if self._tasks
                else "CONTROLLER_UNAVAILABLE",
            )
        else:
            response = MechanicalResponse(
                command=command, state="ACCEPTED", result="PENDING", source="SIMULATED"
            )
            self._tasks[command.mechanical_command_id] = asyncio.create_task(
                self._execute(command, plan),
                name=f"simulated-mechanical-{command.mechanical_command_id}",
            )
        self._responses[command.mechanical_command_id] = response
        return response

    async def _execute(self, command: MechanicalCommand, plan: SimulationPlan) -> None:
        identifier = command.mechanical_command_id
        try:
            timeout = (
                plan.outcome == "TIMEOUT"
                or plan.duration_seconds >= command.timeout_seconds
            )
            await self._sleep(
                command.timeout_seconds if timeout else plan.duration_seconds
            )
            if timeout:
                response = MechanicalResponse(
                    command=command,
                    state="TIMED_OUT",
                    result="UNKNOWN",
                    error_code="EXECUTION_TIMEOUT",
                )
            else:
                response = MechanicalResponse(
                    command=command,
                    state="FAILED" if plan.outcome == "FAILURE" else "COMPLETED",
                    result=plan.outcome,
                    error_code="OPERATION_FAILED"
                    if plan.outcome == "FAILURE"
                    else None,
                )
            self._responses[identifier] = checked_response(
                command, response, source="SIMULATED"
            )
        except asyncio.CancelledError:
            self._responses[identifier] = MechanicalResponse(
                command=command,
                state="CANCELLED",
                result="UNKNOWN",
                error_code="EXECUTION_CANCELLED",
            )
        except Exception:
            # Não expor exceções brutas ou converter falha interna em sucesso.
            self._responses[identifier] = MechanicalResponse(
                command=command,
                state="FAILED",
                result="UNKNOWN",
                error_code="EXECUTION_ERROR",
            )
        finally:
            self._tasks.pop(identifier, None)
