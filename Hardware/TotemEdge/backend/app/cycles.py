"""Máquina única de sessão; o journal autoriza transições mecânicas."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.central_contracts import DepositReceipt

State = Literal[
    "IDENTIFYING",
    "AUTHENTICATING",
    "SAFETY",
    "PHYSICAL_BLOCKED",
    "INSERTION_READY",
    "READY_TO_CAPTURE",
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
    # Logical user declaration, with no motor movement or simulated door.
    "CONFIRM_HAND_REMOVED": ("INSERTION_READY", "READY_TO_CAPTURE", "READY_TO_CAPTURE"),
    "OPEN_INSERTION_DOOR": ("PHYSICAL_BLOCKED", "OPENING", "DOOR_OPEN"),
    "CLOSE_INSERTION_DOOR": ("DOOR_OPEN", "CLOSING", "DOOR_CLOSED"),
    "CYCLE_LOWER_HATCH": ("REVIEW", "HATCH_IN_PROGRESS", "HATCH_IN_PROGRESS"),
    "CONFIRM_INITIAL_STATE": ("HATCH_IN_PROGRESS", "HATCH_IN_PROGRESS", "COMPLETED"),
}
SIMULATION_EDGES = {("DOOR_CLOSED", "REVIEW"), ("READY_TO_CAPTURE", "REVIEW"), ("SAFETY", "INSERTION_READY")}
TRANSITIONS["READY_TO_CAPTURE"] = {"CAPTURING", "TECHNICAL_FAILURE"}
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
    operational: dict | None = None


class SimulationIdentity(BaseModel):
    """Confirmação de identidade central; nunca evidência física/econômica."""

    model_config = ConfigDict(frozen=True, extra="forbid")
    event_id: UUID
    project_ref: str
    machine_id: UUID
    school_id: UUID
    class_id: UUID
    student_id: UUID
    validated_at: datetime
    source: Literal["SUPABASE_DEV_PIN_V1"] = "SUPABASE_DEV_PIN_V1"
