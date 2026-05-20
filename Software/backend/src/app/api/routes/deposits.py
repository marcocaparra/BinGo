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
    payload = payload.model_copy(update={"school_id": machine.school_id, "machine_id": machine.id})
    deposit = register_deposit(session, payload)
    return DepositResponse(
        id=deposit.id,
        event_id=deposit.event_id,
        points_awarded_student=deposit.points_awarded_student,
        points_awarded_class=deposit.points_awarded_class,
        created_at=deposit.created_at,
    )

