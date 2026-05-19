import base64
import hashlib
import hmac
import os

from shared.errors.exceptions import AppError


def _normalize_secret(value: str, *, digits_only: bool = False) -> str:
    normalized = value.strip()
    if digits_only and (len(normalized) != 4 or not normalized.isdigit()):
        raise AppError("O PIN deve conter exatamente 4 dígitos.")
    if not normalized:
        raise AppError("Credencial inválida.")
    return normalized


def hash_secret(secret: str, *, digits_only: bool = False) -> str:
    normalized = _normalize_secret(secret, digits_only=digits_only)
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", normalized.encode("utf-8"), salt, 120_000)
    return f"{base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_secret(secret: str, stored_hash: str, *, digits_only: bool = False) -> bool:
    normalized = _normalize_secret(secret, digits_only=digits_only)
    encoded_salt, encoded_digest = stored_hash.split("$", maxsplit=1)
    salt = base64.b64decode(encoded_salt.encode())
    expected = base64.b64decode(encoded_digest.encode())
    current = hashlib.pbkdf2_hmac("sha256", normalized.encode("utf-8"), salt, 120_000)
    return hmac.compare_digest(current, expected)

