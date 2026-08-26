from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import DepositCategorySource, WasteCategoryCode


class MeProfileResponse(BaseModel):
    id: UUID
    name: str
    school_id: UUID
    class_id: UUID
    points_student_balance: int
    points_class_balance: int


class StudentDepositItem(BaseModel):
    event_id: UUID
    is_valid: bool
    detected_type: str | None
    waste_category_code: WasteCategoryCode | None
    category_source: DepositCategorySource | None
    bonus_rate_applied: Decimal
    bonus_bincoins_awarded: int
    points_awarded_student: int
    points_awarded_class: int
    created_at: datetime


class StudentRedemptionItem(BaseModel):
    id: UUID
    code: str
    status: str
    created_at: datetime
