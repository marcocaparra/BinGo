from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field, StrictBool

from app.central_contracts import TotemContext
from app.cycles import Session
from app.services.sessions import SessionService

router = APIRouter(prefix="/local")


def service(request: Request) -> SessionService:
    return request.app.state.sessions


Service = Annotated[SessionService, Depends(service)]


class StrictRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Start(StrictRequest):
    command_id: UUID
    mode: Literal["student", "class_only"]
    class_id: UUID


class Pin(StrictRequest):
    student_id: UUID
    pin: str = Field(pattern=r"^[0-9]{4}$", repr=False)


class Safety(StrictRequest):
    has_risk: StrictBool


class Active(BaseModel):
    session: Session | None


@router.get("/context", response_model=TotemContext)
async def context(sessions: Service):
    return await sessions.context()


@router.get("/sessions/active", response_model=Active)
def active(sessions: Service):
    return Active(session=sessions.store.active())


@router.post("/sessions", response_model=Session)
async def start(body: Start, sessions: Service):
    return await sessions.start(body.command_id, body.mode, body.class_id)


@router.get("/sessions/{event_id}", response_model=Session)
def get(event_id: UUID, sessions: Service):
    return sessions.store.get(event_id)


@router.post("/sessions/{event_id}/pin", response_model=Session)
async def identify(event_id: UUID, body: Pin, sessions: Service):
    return await sessions.identify(event_id, body.student_id, body.pin)


@router.post("/sessions/{event_id}/safety", response_model=Session)
def safety(event_id: UUID, body: Safety, sessions: Service):
    return sessions.safety(event_id, body.has_risk)


@router.post("/sessions/{event_id}/hand-removed", response_model=Session)
def hand(event_id: UUID, body: StrictRequest, sessions: Service):
    return sessions.hand_removed(event_id)


@router.post("/sessions/{event_id}/cancel", response_model=Session)
def cancel(event_id: UUID, body: StrictRequest, sessions: Service):
    return sessions.cancel(event_id)


@router.post("/sessions/{event_id}/retry-registration", response_model=Session)
async def retry(event_id: UUID, body: StrictRequest, sessions: Service):
    return await sessions.retry_registration(event_id)


@router.post("/sessions/{event_id}/finish", response_model=Session)
def finish(event_id: UUID, body: StrictRequest, sessions: Service):
    return sessions.finish(event_id)
