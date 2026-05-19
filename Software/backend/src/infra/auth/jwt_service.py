from datetime import timedelta

import jwt

from app.config.settings import settings
from shared.utils.time import utcnow


def create_access_token(subject: str, principal_type: str, school_id: str, extra: dict | None = None) -> str:
    payload = {
        "sub": subject,
        "principal_type": principal_type,
        "school_id": school_id,
        "exp": utcnow() + timedelta(minutes=settings.token_ttl_minutes),
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])

