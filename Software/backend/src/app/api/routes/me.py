from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_student
from app.api.schemas.students import MeProfileResponse, StudentDepositItem, StudentRedemptionItem
from domain.students.service import get_profile, list_my_deposits, list_my_redemptions

router = APIRouter()


@router.get("/profile", response_model=MeProfileResponse)
def read_profile(principal: dict = Depends(require_student), session: Session = Depends(get_session)) -> MeProfileResponse:
    return get_profile(session, UUID(principal["sub"]))


@router.get("/deposits", response_model=list[StudentDepositItem])
def read_my_deposits(principal: dict = Depends(require_student), session: Session = Depends(get_session)) -> list[StudentDepositItem]:
    return list_my_deposits(session, UUID(principal["sub"]))


@router.get("/redemptions", response_model=list[StudentRedemptionItem])
def read_my_redemptions(principal: dict = Depends(require_student), session: Session = Depends(get_session)) -> list[StudentRedemptionItem]:
    return list_my_redemptions(session, UUID(principal["sub"]))

