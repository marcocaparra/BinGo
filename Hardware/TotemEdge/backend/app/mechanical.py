"""Contrato interno mecânico; aceitação não é evidência de movimento físico."""

from typing import Literal, Protocol, Self
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, model_validator

Operation = Literal[
    "OPEN_INSERTION_DOOR",
    "CLOSE_INSERTION_DOOR",
    "CYCLE_LOWER_HATCH",
    "CONFIRM_INITIAL_STATE",
]
CommandState = Literal[
    "ACCEPTED", "COMPLETED", "REJECTED", "FAILED", "TIMED_OUT", "CANCELLED"
]
Result = Literal["PENDING", "SUCCEEDED", "FAILURE", "UNAVAILABLE", "UNKNOWN"]
Source = Literal["UNAVAILABLE", "SIMULATED", "PHYSICAL"]
ErrorCode = Literal[
    "CONTROLLER_UNAVAILABLE",
    "CONTROLLER_BUSY",
    "OPERATION_FAILED",
    "EXECUTION_TIMEOUT",
    "EXECUTION_CANCELLED",
    "INCONSISTENT_RESPONSE",
    "EXECUTION_ERROR",
]


class MechanicalCommand(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)

    mechanical_command_id: UUID = Field(default_factory=uuid4)
    event_id: UUID
    operation: Operation
    state: Literal["REQUESTED"] = "REQUESTED"
    timeout_seconds: float = Field(default=10.0, gt=0, allow_inf_nan=False)


class MechanicalResponse(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)

    command: MechanicalCommand
    state: CommandState
    result: Result
    # Origem conservadora também para doubles; não é confirmação física.
    source: Source = "SIMULATED"
    error_code: ErrorCode | None = None

    @model_validator(mode="after")
    def consistent(self) -> Self:
        pairs = {
            "ACCEPTED": ("PENDING", {None}),
            "COMPLETED": ("SUCCEEDED", {None}),
            "REJECTED": (
                "UNAVAILABLE",
                {"CONTROLLER_UNAVAILABLE", "CONTROLLER_BUSY"},
            ),
            "FAILED": ("FAILURE", {"OPERATION_FAILED"}),
            "TIMED_OUT": ("UNKNOWN", {"EXECUTION_TIMEOUT"}),
            "CANCELLED": ("UNKNOWN", {"EXECUTION_CANCELLED"}),
        }
        valid = pairs.get(self.state)
        if self.state == "FAILED" and self.result == "UNKNOWN":
            valid = ("UNKNOWN", {"INCONSISTENT_RESPONSE", "EXECUTION_ERROR"})
        if valid is None or self.result != valid[0] or self.error_code not in valid[1]:
            raise ValueError("Resposta mecânica inconsistente.")
        if self.source == "UNAVAILABLE" and self.state != "REJECTED":
            raise ValueError("Controller indisponível não confirma operações.")
        return self


class ControllerError(Exception):
    """Erro local anterior ao despacho/consulta; não descreve posição física."""

    def __init__(self, code: str):
        super().__init__("Solicitação mecânica interna não permitida.")
        self.code = code


def checked_response(
    command: MechanicalCommand,
    response: object,
    *,
    source: Literal["SIMULATED", "PHYSICAL"],
) -> MechanicalResponse:
    """Valida correlação, origem e conclusão; dados divergentes viram UNKNOWN."""
    try:
        # Revalidar mesmo instâncias: model_copy/model_construct não validam.
        if not isinstance(response, MechanicalResponse):
            raise ValueError()
        validated = MechanicalResponse.model_validate(response.model_dump())
        if (
            validated.command != command
            or validated.source != source
            or validated.state == "ACCEPTED"
        ):
            raise ValueError()
        return validated
    except (TypeError, ValueError):
        return MechanicalResponse(
            command=command,
            state="FAILED",
            result="UNKNOWN",
            source=source,
            error_code="INCONSISTENT_RESPONSE",
        )


class MechanicalController(Protocol):
    async def submit(self, command: MechanicalCommand) -> MechanicalResponse: ...
    def get(self, mechanical_command_id: UUID) -> MechanicalResponse: ...
    async def wait(self, mechanical_command_id: UUID) -> MechanicalResponse: ...
    async def cancel(self, mechanical_command_id: UUID) -> MechanicalResponse: ...
    async def aclose(self) -> None: ...
