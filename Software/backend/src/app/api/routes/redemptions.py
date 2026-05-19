from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_admin, require_student
from app.api.schemas.redemptions import RedemptionCreateRequest, RedemptionResponse
from domain.redemptions.service import create_redemption, deliver_redemption, get_redemption_by_code

router = APIRouter()


@router.post("", response_model=RedemptionResponse)
def create_student_redemption(
    payload: RedemptionCreateRequest,
    principal: dict = Depends(require_student),
    session: Session = Depends(get_session),
) -> RedemptionResponse:
    redemption = create_redemption(session, UUID(principal["school_id"]), UUID(principal["sub"]), payload.reward_id)
    return RedemptionResponse(
        id=redemption.id,
        code=redemption.code,
        status=redemption.status,
        created_at=redemption.created_at,
        expires_at=redemption.expires_at,
        delivered_at=redemption.delivered_at,
    )


@router.get("/code/{code}", response_model=RedemptionResponse)
def read_redemption_by_code(code: str, session: Session = Depends(get_session)) -> RedemptionResponse:
    redemption = get_redemption_by_code(session, code)
    return RedemptionResponse(
        id=redemption.id,
        code=redemption.code,
        status=redemption.status,
        created_at=redemption.created_at,
        expires_at=redemption.expires_at,
        delivered_at=redemption.delivered_at,
    )


@router.post("/{redemption_id}/deliver", response_model=RedemptionResponse)
def deliver_student_redemption(
    redemption_id: UUID,
    principal: dict = Depends(require_admin),
    session: Session = Depends(get_session),
) -> RedemptionResponse:
    redemption = deliver_redemption(session, redemption_id, UUID(principal["sub"]))
    return RedemptionResponse(
        id=redemption.id,
        code=redemption.code,
        status=redemption.status,
        created_at=redemption.created_at,
        expires_at=redemption.expires_at,
        delivered_at=redemption.delivered_at,
    )

