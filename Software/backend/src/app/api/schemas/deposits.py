from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import DepositSize


class DepositCreateRequest(BaseModel):
    event_id: UUID
    school_id: UUID
    machine_id: UUID
    class_id: UUID
    student_id: UUID | None = None
    is_valid: bool
    detected_type: str | None = None
    size: DepositSize


class DepositResponse(BaseModel):
    id: UUID
    event_id: UUID
    points_awarded_student: int
    points_awarded_class: int
    created_at: datetime

