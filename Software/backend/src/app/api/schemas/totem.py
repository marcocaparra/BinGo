from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import DepositCategorySource, MachineStatus, StudentStatus, WasteCategoryCode


class TotemSchoolResponse(BaseModel):
    id: UUID
    name: str


class TotemMachineResponse(BaseModel):
    id: UUID
    name: str
    status: MachineStatus


class TotemClassResponse(BaseModel):
    id: UUID
    name: str
    segment: str
    grade: str
    points_class_balance: int


class TotemStudentResponse(BaseModel):
    id: UUID
    name: str
    class_id: UUID
    class_name: str
    points_student_balance: int
    status: StudentStatus


class TotemContextResponse(BaseModel):
    school: TotemSchoolResponse
    machine: TotemMachineResponse
    classes: list[TotemClassResponse]
    students: list[TotemStudentResponse]


class TotemStudentStatsResponse(BaseModel):
    valid_deposits_count: int
    invalid_deposits_count: int
    total_bins_generated: int


class TotemDepositResponse(BaseModel):
    id: UUID
    event_id: UUID
    detected_type: str | None
    waste_category_code: WasteCategoryCode | None
    category_source: DepositCategorySource | None
    bonus_rate_applied: Decimal
    bonus_bincoins_awarded: int
    is_valid: bool
    points_awarded_student: int
    points_awarded_class: int
    created_at: datetime


class TotemStudentSummaryResponse(BaseModel):
    student: TotemStudentResponse
    stats: TotemStudentStatsResponse
    recent_deposits: list[TotemDepositResponse]


class TotemStudentLoginRequest(BaseModel):
    class_id: UUID
    student_id: UUID
    pin: str


class TotemStudentLoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    student: TotemStudentResponse


class TotemStudentRankingItem(BaseModel):
    id: UUID
    name: str
    class_name: str
    points_student_balance: int


class TotemClassRankingItem(BaseModel):
    id: UUID
    name: str
    points_class_balance: int


class TotemRankingsResponse(BaseModel):
    students: list[TotemStudentRankingItem]
    classes: list[TotemClassRankingItem]
