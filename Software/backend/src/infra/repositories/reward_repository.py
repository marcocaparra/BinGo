from sqlalchemy import select
from sqlalchemy.orm import Session

from infra.db.models import Reward


class RewardRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def list_by_school(self, school_id):
        return list(
            self.session.scalars(
                select(Reward).where(Reward.school_id == school_id).order_by(Reward.cost_points.asc(), Reward.name.asc())
            )
        )

    def get_by_id(self, reward_id):
        return self.session.get(Reward, reward_id)

