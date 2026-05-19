from uuid import UUID

from fastapi import Depends, Header
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config.settings import settings
from infra.auth.jwt_service import decode_access_token
from infra.db.session import get_db_session
from shared.constants.enums import PrincipalType
from shared.errors.exceptions import ForbiddenError, UnauthorizedError

bearer_scheme = HTTPBearer(auto_error=False)


def get_session(session: Session = Depends(get_db_session)) -> Session:
    return session


def get_current_principal(credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme)) -> dict:
    if credentials is None:
        raise UnauthorizedError("Token ausente.")
    try:
        return decode_access_token(credentials.credentials)
    except Exception as exc:  # pragma: no cover
        raise UnauthorizedError("Token inválido.") from exc


def require_student(principal: dict = Depends(get_current_principal)) -> dict:
    if principal["principal_type"] != PrincipalType.STUDENT.value:
        raise ForbiddenError("Escopo de aluno obrigatório.")
    return principal


def require_admin(principal: dict = Depends(get_current_principal)) -> dict:
    if principal["principal_type"] not in {PrincipalType.ADMIN_SCHOOL.value, PrincipalType.BINGO_ADMIN.value}:
        raise ForbiddenError("Escopo administrativo obrigatório.")
    return principal


def require_edge_headers(
    x_machine_id: UUID = Header(..., alias="X-Machine-Id"),
    x_api_key: str = Header(..., alias="X-Api-Key"),
) -> tuple[UUID, str]:
    return x_machine_id, x_api_key
