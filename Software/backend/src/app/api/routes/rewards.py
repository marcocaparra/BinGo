from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.api.schemas.rewards import RewardItemResponse
from domain.rewards.service import list_rewards

router = APIRouter()


@router.get("", response_model=list[RewardItemResponse])
def read_rewards(school_id: UUID = Query(...), session: Session = Depends(get_session)) -> list[RewardItemResponse]:
    rewards = list_rewards(session, school_id)
    return [
        RewardItemResponse(
            id=item.id,
            name=item.name,
            description=item.description,
            cost_points=item.cost_points,
            category=item.category,
            status=item.status,
            stock_qty=item.stock_qty,
        )
        for item in rewards
    ]

