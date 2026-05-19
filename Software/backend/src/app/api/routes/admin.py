from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_admin
from app.api.schemas.redemptions import RedemptionResponse
from app.api.schemas.rewards import RewardItemResponse, RewardUpdateRequest
from domain.redemptions.service import list_today_redemptions
from domain.rewards.service import update_reward

router = APIRouter()


@router.get("/redemptions/today", response_model=list[RedemptionResponse])
def read_today_redemptions(principal: dict = Depends(require_admin), session: Session = Depends(get_session)) -> list[RedemptionResponse]:
    items = list_today_redemptions(session, UUID(principal["school_id"]))
    return [
        RedemptionResponse(
            id=item.id,
            code=item.code,
            status=item.status,
            created_at=item.created_at,
            expires_at=item.expires_at,
            delivered_at=item.delivered_at,
        )
        for item in items
    ]


@router.patch("/rewards/{reward_id}", response_model=RewardItemResponse)
def patch_reward(
    reward_id: UUID,
    payload: RewardUpdateRequest,
    _: dict = Depends(require_admin),
    session: Session = Depends(get_session),
) -> RewardItemResponse:
    reward = update_reward(session, reward_id, is_active=payload.is_active, status=payload.status, stock_qty=payload.stock_qty)
    return RewardItemResponse(
        id=reward.id,
        name=reward.name,
        description=reward.description,
        cost_points=reward.cost_points,
        category=reward.category,
        status=reward.status,
        stock_qty=reward.stock_qty,
    )
