from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, model_validator

from shared.constants.enums import DepositCategorySource, WasteCategoryCode


class DepositCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_id: UUID
    class_id: UUID
    student_id: UUID | None = None
    is_valid: bool
    detected_type: str | None = None
    waste_category_code: WasteCategoryCode | None = None
    category_source: DepositCategorySource | None = None

    @model_validator(mode="after")
    def validate_category(self) -> "DepositCreateRequest":
        if self.is_valid:
            if self.waste_category_code is None or self.category_source is None:
                raise ValueError("Categoria canônica e origem são obrigatórias para descarte válido.")
            if self.waste_category_code == WasteCategoryCode.UNKNOWN:
                if self.category_source != DepositCategorySource.UNIDENTIFIED:
                    raise ValueError("A categoria UNKNOWN exige origem UNIDENTIFIED.")
            elif self.category_source == DepositCategorySource.UNIDENTIFIED:
                raise ValueError("A origem UNIDENTIFIED exige categoria UNKNOWN.")
        elif self.waste_category_code is not None or self.category_source is not None:
            raise ValueError("Descarte inválido não aceita categoria canônica ou origem.")
        return self


class DepositResponse(BaseModel):
    id: UUID
    event_id: UUID
    waste_category_code: WasteCategoryCode | None
    category_source: DepositCategorySource | None
    bonus_rate_applied: Decimal
    bonus_bincoins_awarded: int
    points_awarded_student: int
    points_awarded_class: int
    created_at: datetime
