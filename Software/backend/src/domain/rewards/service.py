from uuid import UUID

from sqlalchemy.orm import Session

from infra.repositories.reward_repository import RewardRepository
from shared.constants.enums import RewardStatus
from shared.errors.exceptions import NotFoundError


def list_rewards(session: Session, school_id: UUID):
    rewards = RewardRepository(session).list_by_school(school_id)
    return [
        reward for reward in rewards
        if reward.is_active and reward.status != RewardStatus.DISABLED
    ]


def update_reward(session: Session, reward_id: UUID, *, is_active: bool | None, status: RewardStatus | None, stock_qty: int | None):
    reward = RewardRepository(session).get_by_id(reward_id)
    if reward is None:
        raise NotFoundError("Recompensa não encontrada.")

    try:
        if is_active is not None:
            reward.is_active = is_active
        if status is not None:
            reward.status = status
        if stock_qty is not None:
            reward.stock_qty = stock_qty
        session.commit()
    except Exception:
        session.rollback()
        raise
    return reward
