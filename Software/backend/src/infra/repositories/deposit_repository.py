from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from infra.db.models import Deposit
from shared.constants.enums import DepositSize


class DepositRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_event_id(self, event_id: UUID) -> Deposit | None:
        return self.session.scalar(select(Deposit).where(Deposit.event_id == event_id))

    def count_student_small_items_on_day(self, student_id: UUID, day: datetime) -> int:
        return self.session.scalar(
            select(func.count(Deposit.id)).where(
                Deposit.student_id == student_id,
                Deposit.size == DepositSize.SMALL,
                Deposit.is_valid.is_(True),
                func.date(Deposit.created_at) == day.date(),
            )
        ) or 0

    def list_for_student(self, student_id: UUID) -> list[Deposit]:
        return list(
            self.session.scalars(
                select(Deposit).where(Deposit.student_id == student_id).order_by(Deposit.created_at.desc())
            )
        )

