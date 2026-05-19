from sqlalchemy import select
from sqlalchemy.orm import Session

from infra.db.models import ClassRoom, Redemption, SchoolSetting, Student


class StudentRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_id(self, student_id):
        return self.session.get(Student, student_id)

    def get_classroom(self, class_id):
        return self.session.get(ClassRoom, class_id)

    def get_school_settings(self, school_id):
        return self.session.get(SchoolSetting, school_id)

    def list_redemptions(self, student_id):
        return list(
            self.session.scalars(
                select(Redemption).where(Redemption.student_id == student_id).order_by(Redemption.created_at.desc())
            )
        )
