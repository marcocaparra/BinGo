"""Projeções locais das três capacidades DEV existentes; nenhuma autorização física."""

from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import Field

from app.central_contracts import PinConfirmation, TotemContext
from app.clients.supabase import CentralError
from app.routes.sessions import StrictRequest

router = APIRouter(prefix="/local/dev")


class DevPin(StrictRequest):
    class_id: UUID
    student_id: UUID
    pin: str = Field(pattern=r"^[0-9]{4}$", repr=False)


async def available(request):
    client = request.app.state.dev_central
    health = await client.check_health()
    if not health.available:
        raise CentralError(
            "DEV_CENTRAL_" + health.outcome,
            401 if health.outcome == "AUTHENTICATION_FAILED" else 503,
        )
    return client


@router.get("/health")
async def health(request: Request):
    await available(request)
    return {
        "central": "AVAILABLE",
        "scope": "SUPABASE_DEV_READ_ONLY",
        "mechanical_source": "SIMULATED",
        "economic_registration": False,
    }


@router.get("/context", response_model=TotemContext)
async def context(request: Request):
    return await (await available(request)).context()


@router.post("/student-pin", response_model=PinConfirmation)
async def pin(request: Request, body: DevPin):
    # Contrato de identificação existente; não cria sessão nem confirma mecânica.
    return await (await available(request)).verify_pin(
        body.class_id, body.student_id, body.pin
    )
