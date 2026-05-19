from sqlalchemy import select
from sqlalchemy.orm import Session

from infra.db.models import Admin


class AdminRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_email(self, email: str) -> Admin | None:
        return self.session.scalar(select(Admin).where(Admin.email == email))

    def get_by_id(self, admin_id):
        return self.session.get(Admin, admin_id)

