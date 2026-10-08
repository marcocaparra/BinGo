"""Projeções dos contratos existentes das Functions, sem regras econômicas."""

from datetime import datetime
from decimal import Decimal
from typing import Literal, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    model_validator,
)


class PublicRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")


class NamedRecord(PublicRecord):
    id: UUID
    name: str


class SchoolClass(NamedRecord):
    segment: str | None
    grade: str | None
    points_class_balance: StrictInt


class ContextStudent(NamedRecord):
    class_id: UUID
    class_name: str
    status: Literal["ACTIVE"]
    points_student_balance: StrictInt


class TotemContext(PublicRecord):
    school: NamedRecord
    machine: NamedRecord
    classes: list[SchoolClass]
    students: list[ContextStudent]

    @model_validator(mode="after")
    def consistent_ids(self) -> Self:
        ids = {item.id for item in self.classes}
        if len(ids) != len(self.classes) or len({s.id for s in self.students}) != len(
            self.students
        ):
            raise ValueError("Contexto duplicado")
        if any(s.class_id not in ids for s in self.students):
            raise ValueError("Contexto inconsistente")
        return self


class ConfirmedStudent(NamedRecord):
    class_id: UUID
    class_name: str


class PinConfirmation(PublicRecord):
    confirmed: Literal[True]
    student: ConfirmedStudent

    @model_validator(mode="before")
    @classmethod
    def exact_boolean(cls, value):
        if not isinstance(value, dict) or value.get("confirmed") is not True:
            raise ValueError("Confirmação inválida")
        return value


Category = Literal[
    "BATTERY", "MOBILE_DEVICE", "CABLE_WIRE", "PERIPHERAL", "OTHER_EWASTE", "UNKNOWN"
]
CategorySource = Literal["AI_CONFIRMED", "USER_CORRECTED", "UNIDENTIFIED"]


class DepositPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    event_id: UUID
    class_id: UUID
    student_id: UUID | None
    is_valid: StrictBool
    detected_type: str | None
    waste_category_code: Category | None
    category_source: CategorySource | None

    @model_validator(mode="after")
    def category_combination(self) -> Self:
        if not self.is_valid:
            valid = self.waste_category_code is None and self.category_source is None
        elif self.waste_category_code == "UNKNOWN":
            valid = self.category_source == "UNIDENTIFIED"
        else:
            valid = self.waste_category_code is not None and self.category_source in {
                "AI_CONFIRMED",
                "USER_CORRECTED",
            }
        if not valid:
            raise ValueError("Categoria/origem inválidas")
        return self


class DepositReceipt(PublicRecord):
    id: UUID
    event_id: UUID
    waste_category_code: Category | None
    category_source: CategorySource | None
    bonus_rate_applied: Decimal = Field(ge=0, allow_inf_nan=False)
    bonus_bincoins_awarded: StrictInt = Field(ge=0)
    points_awarded_student: StrictInt = Field(ge=0)
    points_awarded_class: StrictInt = Field(ge=0)
    created_at: datetime

    @model_validator(mode="after")
    def timestamp_with_timezone(self) -> Self:
        if self.created_at.utcoffset() is None:
            raise ValueError("Timestamp sem fuso")
        return self
