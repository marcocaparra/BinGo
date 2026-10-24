"""Estados lógicos e snapshot público. Estados físicos são reservas bloqueadas."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.central_contracts import DepositReceipt

State = Literal[
    "IDENTIFYING",
    "AUTHENTICATING",
    "SAFETY",
    "PHYSICAL_BLOCKED",
    "OPENING",
    "DOOR_OPEN",
    "CLOSING",
    "DOOR_CLOSED",
    "CAPTURING",
    "CLASSIFYING",
    "REVIEW",
    "RETURN_REQUIRED",
    "HATCH_IN_PROGRESS",
    "REGISTRATION_PENDING",
    "REGISTERING",
    "REGISTERED",
    "INDETERMINATE",
    "TECHNICAL_FAILURE",
    "CANCELLED",
    "COMPLETED",
]

TRANSITIONS = {
    "IDENTIFYING": {"AUTHENTICATING", "CANCELLED"},
    "AUTHENTICATING": {"IDENTIFYING", "SAFETY"},
    "SAFETY": {"PHYSICAL_BLOCKED", "CANCELLED"},
    "PHYSICAL_BLOCKED": {"CANCELLED"},
    # Pontos reservados: nenhuma implementação de movimento gera esses estados.
    "DOOR_OPEN": {"TECHNICAL_FAILURE"},
    "DOOR_CLOSED": {"CAPTURING", "TECHNICAL_FAILURE"},
    "CAPTURING": {"CLASSIFYING", "TECHNICAL_FAILURE"},
    "CLASSIFYING": {"REVIEW", "RETURN_REQUIRED", "TECHNICAL_FAILURE"},
    "REGISTRATION_PENDING": {"REGISTERING"},
    "REGISTERING": {"REGISTRATION_PENDING", "REGISTERED"},
    "REGISTERED": {"COMPLETED"},
}
PRE_PHYSICAL = {"IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED"}


class CycleError(Exception):
    def __init__(self, code: str, status: int = 409):
        super().__init__("Operação não permitida no estado atual do Totem.")
        self.code = code
        self.status = status


class Session(BaseModel):
    event_id: UUID
    state: State
    mode: Literal["student", "class_only"]
    class_id: UUID
    student_id: UUID | None
    class_name: str
    student_name: str | None
    hand_removed: bool
    failure_code: str | None
    receipt: DepositReceipt | None
    updated_at: str
