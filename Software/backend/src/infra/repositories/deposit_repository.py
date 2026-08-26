from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from infra.db.models import Deposit


class DepositRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_event_id(self, event_id: UUID) -> Deposit | None:
        return self.session.scalar(select(Deposit).where(Deposit.event_id == event_id))

    def list_for_student(self, student_id: UUID) -> list[Deposit]:
        return list(
            self.session.scalars(
                select(Deposit).where(Deposit.student_id == student_id).order_by(Deposit.created_at.desc())
            )
        )

