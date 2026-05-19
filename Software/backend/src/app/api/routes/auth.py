from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_admin
from app.api.schemas.auth import AdminLoginRequest, AdminResetPinRequest, AuthTokenResponse, StudentActivateRequest, StudentLoginRequest
from domain.auth.service import activate_student, login_admin, login_student, reset_student_pin

router = APIRouter()


@router.post("/students/activate", response_model=AuthTokenResponse, status_code=status.HTTP_201_CREATED)
def activate_student_account(payload: StudentActivateRequest, session: Session = Depends(get_session)) -> AuthTokenResponse:
    token = activate_student(session, payload.school_id, payload.class_id, payload.student_id, payload.pin)
    return AuthTokenResponse(access_token=token)


@router.post("/students/login", response_model=AuthTokenResponse)
def login_student_account(payload: StudentLoginRequest, session: Session = Depends(get_session)) -> AuthTokenResponse:
    token = login_student(session, payload.school_id, payload.class_id, payload.student_id, payload.pin)
    return AuthTokenResponse(access_token=token)


@router.post("/admins/login", response_model=AuthTokenResponse)
def login_admin_account(payload: AdminLoginRequest, session: Session = Depends(get_session)) -> AuthTokenResponse:
    token = login_admin(session, payload.email, payload.password)
    return AuthTokenResponse(access_token=token)


@router.post("/students/{student_id}/reset-pin", status_code=status.HTTP_204_NO_CONTENT)
def reset_pin(
    student_id: UUID,
    payload: AdminResetPinRequest,
    principal: dict = Depends(require_admin),
    session: Session = Depends(get_session),
) -> None:
    reset_student_pin(session, UUID(principal["sub"]), student_id, payload.new_pin)

