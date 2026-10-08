import asyncio
from hashlib import sha256
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

import httpx2 as httpx
from pydantic import ValidationError
from uuid import UUID

from app.central_contracts import (
    DepositPayload,
    DepositReceipt,
    PinConfirmation,
    TotemContext,
)
from app.config import SupabaseConfigurationError, SupabaseSettings

ReadinessOutcome = Literal[
    "AVAILABLE",
    "UNAVAILABLE",
    "NOT_CONFIGURED",
    "INVALID_CONFIGURATION",
    "AUTHENTICATION_FAILED",
    "TIMEOUT",
    "CONNECTION_ERROR",
    "HTTP_ERROR",
    "UNEXPECTED_RESPONSE",
]


@dataclass(frozen=True)
class CentralReadiness:
    """Resultado interno; não é um contrato HTTP nem contém dados remotos brutos."""

    outcome: ReadinessOutcome
    http_status: int | None = None

    @property
    def available(self) -> bool:
        return self.outcome == "AVAILABLE"


class CentralError(Exception):
    """Nunca inclui URL, credenciais, PIN ou resposta remota bruta."""

    def __init__(self, code: str, http_status: int = 503):
        super().__init__("Não foi possível confirmar a operação central.")
        self.code = code
        self.http_status = http_status


def _matches_health_contract(body: object, available: bool) -> bool:
    if not isinstance(body, dict):
        return False
    if (
        body.get("status") != ("AVAILABLE" if available else "UNAVAILABLE")
        or body.get("can_start_deposit") is not available
        or body.get("scope") != "CENTRAL_BACKEND"
        or not isinstance(body.get("checked_at"), str)
    ):
        return False
    try:
        checked_at = datetime.fromisoformat(body["checked_at"])
        return checked_at.utcoffset() is not None
    except ValueError:
        return False


class SupabaseEdgeClient:
    def __init__(self, http_client: httpx.AsyncClient):
        self._http = http_client
        self._settings: SupabaseSettings | None = None
        self._configuration_outcome: ReadinessOutcome = "NOT_CONFIGURED"
        try:
            self._settings = SupabaseSettings.from_environment()
        except SupabaseConfigurationError as error:
            self._configuration_outcome = error.outcome

    @property
    def configuration_scope(self) -> str | None:
        if self._settings is None:
            return None
        # Fingerprint do destino/máquina, não da chave: permite rotação sem mudar evento.
        return sha256(
            f"{self._settings.base_url.rstrip('/')}|{self._settings.machine_id.lower()}".encode()
        ).hexdigest()

    async def check_health(self) -> CentralReadiness:
        if self._settings is None:
            return CentralReadiness(self._configuration_outcome)

        settings = self._settings
        try:
            async with asyncio.timeout(settings.timeout_seconds):
                response = await self._http.get(
                    f"{settings.base_url.rstrip('/')}/functions/v1/health-v1",
                    headers={
                        "Accept": "application/json",
                        "X-Machine-Id": settings.machine_id,
                        "X-Api-Key": settings.machine_api_key,
                    },
                    timeout=settings.timeout_seconds,
                    follow_redirects=False,
                )
        except (TimeoutError, httpx.TimeoutException):
            return CentralReadiness("TIMEOUT")
        except httpx.InvalidURL:
            return CentralReadiness("INVALID_CONFIGURATION")
        except httpx.NetworkError:
            return CentralReadiness("CONNECTION_ERROR")
        except (httpx.ProtocolError, httpx.DecodingError):
            return CentralReadiness("UNEXPECTED_RESPONSE")
        except httpx.HTTPError:
            return CentralReadiness("HTTP_ERROR")

        code = response.status_code
        if code == 401:
            return CentralReadiness("AUTHENTICATION_FAILED", code)
        if code not in (200, 503):
            return CentralReadiness("HTTP_ERROR", code)
        content_type = response.headers.get("content-type", "").split(";")[0].lower()
        if content_type != "application/json":
            return CentralReadiness("UNEXPECTED_RESPONSE", code)
        try:
            body = response.json()
        except (ValueError, RecursionError):
            return CentralReadiness("UNEXPECTED_RESPONSE", code)
        if not _matches_health_contract(body, available=code == 200):
            return CentralReadiness("UNEXPECTED_RESPONSE", code)
        return CentralReadiness("AVAILABLE" if code == 200 else "UNAVAILABLE", code)

    async def _call(
        self, function: str, *, body: dict | None = None, creation: bool = False
    ) -> dict:
        if self._settings is None:
            raise CentralError(self._configuration_outcome)
        settings = self._settings
        try:
            async with asyncio.timeout(settings.timeout_seconds):
                response = await self._http.request(
                    "POST" if body is not None else "GET",
                    f"{settings.base_url.rstrip('/')}/functions/v1/{function}",
                    headers={
                        "Accept": "application/json",
                        "X-Machine-Id": settings.machine_id,
                        "X-Api-Key": settings.machine_api_key,
                    },
                    json=body,
                    timeout=settings.timeout_seconds,
                    follow_redirects=False,
                )
        except (TimeoutError, httpx.TimeoutException):
            raise CentralError("CENTRAL_TIMEOUT") from None
        except httpx.NetworkError:
            raise CentralError("CENTRAL_CONNECTION_ERROR") from None
        except httpx.HTTPError:
            raise CentralError("CENTRAL_HTTP_ERROR") from None
        if (
            response.headers.get("content-type", "").split(";")[0].lower()
            != "application/json"
        ):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502)
        try:
            data = response.json()
        except (ValueError, RecursionError):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502) from None
        code = response.status_code
        if code not in ((200, 201) if creation else (200,)):
            remote_code = (
                data.get("error", {}).get("code")
                if isinstance(data, dict) and isinstance(data.get("error"), dict)
                else None
            )
            if (
                code == 401
                and function == "totem-student-pin-v1"
                and remote_code == "STUDENT_PIN_INVALID"
            ):
                raise CentralError("STUDENT_PIN_INVALID", 401)
            if code == 409 and creation:
                raise CentralError("EVENT_ID_CONFLICT", 409)
            if code in (404, 422):
                raise CentralError("CENTRAL_CONTRACT_REJECTED", code)
            raise CentralError(
                "MACHINE_AUTHENTICATION_FAILED"
                if code == 401
                else "CENTRAL_UNAVAILABLE"
            )
        if not isinstance(data, dict):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502)
        return data

    async def context(self) -> TotemContext:
        data = await self._call("totem-context-v1")
        try:
            result = TotemContext.model_validate(data)
            if (
                self._settings is None
                or str(result.machine.id) != self._settings.machine_id.lower()
            ):
                raise ValueError()
            return result
        except (ValueError, ValidationError):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502) from None

    async def verify_pin(
        self, class_id: UUID, student_id: UUID, pin: str
    ) -> PinConfirmation:
        # Mesmo contrato central; validação criptográfica pertence à Function.
        import re

        if re.fullmatch(r"[0-9]{4}", pin) is None:
            raise CentralError("INVALID_PIN_CONTRACT", 422)
        data = await self._call(
            "totem-student-pin-v1",
            body={"class_id": str(class_id), "student_id": str(student_id), "pin": pin},
        )
        try:
            result = PinConfirmation.model_validate(data)
            if result.student.id != student_id or result.student.class_id != class_id:
                raise ValueError()
            return result
        except (ValueError, ValidationError):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502) from None

    async def register(self, payload: DepositPayload) -> DepositReceipt:
        data = await self._call(
            "register-deposit-v1", body=payload.model_dump(mode="json"), creation=True
        )
        try:
            receipt = DepositReceipt.model_validate(data)
            if (
                receipt.event_id != payload.event_id
                or receipt.waste_category_code != payload.waste_category_code
                or receipt.category_source != payload.category_source
            ):
                raise ValueError()
            return receipt
        except (ValueError, ValidationError):
            raise CentralError("CENTRAL_UNEXPECTED_RESPONSE", 502) from None
