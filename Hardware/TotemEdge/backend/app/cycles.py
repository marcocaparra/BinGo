"""Máquina única de sessão; movimentos conectados somente em sessões simuladas."""

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
    # Reservados no runtime operacional; a integração simulada está definida abaixo.
    "DOOR_OPEN": {"TECHNICAL_FAILURE"},
    "DOOR_CLOSED": {"CAPTURING", "TECHNICAL_FAILURE"},
    "CAPTURING": {"CLASSIFYING", "TECHNICAL_FAILURE"},
    "CLASSIFYING": {"REVIEW", "RETURN_REQUIRED", "TECHNICAL_FAILURE"},
    "REGISTRATION_PENDING": {"REGISTERING"},
    "REGISTERING": {"REGISTRATION_PENDING", "REGISTERED"},
    "REGISTERED": {"COMPLETED"},
}
PRE_PHYSICAL = {"IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED"}

# Pré-condição, movimento em andamento, resultado. Integração da mesma máquina,
# sem estados alternativos. As arestas só são escritas pelo journal em simulação.
MECHANICAL_STEPS = {
    "OPEN_INSERTION_DOOR": ("PHYSICAL_BLOCKED", "OPENING", "DOOR_OPEN"),
    "CLOSE_INSERTION_DOOR": ("DOOR_OPEN", "CLOSING", "DOOR_CLOSED"),
    "CYCLE_LOWER_HATCH": ("REVIEW", "HATCH_IN_PROGRESS", "HATCH_IN_PROGRESS"),
    "CONFIRM_INITIAL_STATE": ("HATCH_IN_PROGRESS", "HATCH_IN_PROGRESS", "COMPLETED"),
}
SIMULATION_EDGES = {("DOOR_CLOSED", "REVIEW")}
for before, moving, after in MECHANICAL_STEPS.values():
    SIMULATION_EDGES.update({(before, moving), (moving, after), (moving, before)})
for before, after in SIMULATION_EDGES:
    TRANSITIONS.setdefault(before, set()).add(after)


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
