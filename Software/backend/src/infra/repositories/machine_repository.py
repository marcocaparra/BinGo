from sqlalchemy.orm import Session

from infra.db.models import Machine


class MachineRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_id(self, machine_id):
        return self.session.get(Machine, machine_id)

