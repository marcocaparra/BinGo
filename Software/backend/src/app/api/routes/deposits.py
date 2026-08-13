from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_edge_headers
from app.api.schemas.deposits import DepositCreateRequest, DepositResponse
from domain.deposits.service import register_deposit
from domain.machines.service import authenticate_machine

router = APIRouter()


@router.post("", response_model=DepositResponse, status_code=status.HTTP_201_CREATED)
@router.post("/sync", response_model=DepositResponse, status_code=status.HTTP_201_CREATED)
def create_deposit(
    payload: DepositCreateRequest,
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> DepositResponse:
    machine_id, api_key = edge_headers
    machine = authenticate_machine(session, machine_id, api_key)
    deposit = register_deposit(
        session,
        payload,
        school_id=machine.school_id,
        machine_id=machine.id,
    )
    return DepositResponse(
        id=deposit.id,
        event_id=deposit.event_id,
        waste_category_code=deposit.waste_category.code if deposit.waste_category is not None else None,
        category_source=deposit.category_source,
        bonus_rate_applied=deposit.bonus_rate_applied,
        bonus_bincoins_awarded=deposit.bonus_bincoins_awarded,
        points_awarded_student=deposit.points_awarded_student,
        points_awarded_class=deposit.points_awarded_class,
        created_at=deposit.created_at,
    )

