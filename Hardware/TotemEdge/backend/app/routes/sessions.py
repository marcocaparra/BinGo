from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, ConfigDict, Field, StrictBool

from app.central_contracts import TotemContext
from app.cycles import CycleError, Session
from app.services.sessions import SessionService

router = APIRouter(prefix="/local")
physical_router = APIRouter(prefix="/local")


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


class Hand(StrictRequest):
    hand_removed: StrictBool = False


class Review(StrictRequest):
    capture_id: UUID
    item_id: str
    action: Literal["confirm", "correct"]


class Active(BaseModel):
    session: Session | None


@router.get("/context", response_model=TotemContext)
async def context(sessions: Service):
    return await sessions.context()


@router.get("/sessions/active", response_model=Active)
def active(sessions: Service):
    session = sessions.store.active()
    return Active(session=sessions.snapshot(session.event_id) if session else None)


@router.post("/sessions", response_model=Session)
async def start(body: Start, sessions: Service):
    return await sessions.start(body.command_id, body.mode, body.class_id)


@router.get("/sessions/{event_id}", response_model=Session)
def get(event_id: UUID, sessions: Service):
    return sessions.snapshot(event_id)


@router.post("/sessions/{event_id}/pin", response_model=Session)
async def identify(event_id: UUID, body: Pin, sessions: Service):
    return await sessions.identify(event_id, body.student_id, body.pin)


@router.post("/sessions/{event_id}/safety", response_model=Session)
async def safety(event_id: UUID, body: Safety, sessions: Service):
    if (
        sessions.mechanical is not None
        and not body.has_risk
        and sessions.store.get(event_id).state == "SAFETY"
    ):
        try:
            await sessions.require_available()
        except CycleError:
            sessions.store.change(
                event_id,
                "SAFETY",
                "CANCELLED",
                code="TOTEM_UNAVAILABLE_BEFORE_INSERTION",
                active_slot=None,
            )
            return sessions.snapshot(event_id)
    return sessions.safety(event_id, body.has_risk)


@router.post("/sessions/{event_id}/hand-removed", response_model=Session)
async def hand(event_id: UUID, body: Hand, sessions: Service):
    return sessions.hand_removed(event_id, body.hand_removed)


@physical_router.post("/sessions/{event_id}/vision-review", response_model=Session)
def review(event_id: UUID, body: Review, sessions: Service):
    sessions.physical_ready()
    sessions.vision.review(event_id, body.capture_id, body.item_id, body.action)
    return sessions.snapshot(event_id)


@physical_router.post("/sessions/{event_id}/hatch", response_model=Session)
async def hatch(event_id: UUID, body: StrictRequest, sessions: Service):
    return await sessions.hatch(event_id)


@physical_router.get("/sessions/{event_id}/vision-image/{capture_id}")
def image(event_id: UUID, capture_id: UUID, request: Request, sessions: Service):
    if request.headers.get("X-Totem-Request") != "1" or sessions.vision is None:
        raise CycleError("VISION_IMAGE_UNAVAILABLE", 403)
    frame = sessions.vision.image(event_id, capture_id)
    return Response(
        frame.content,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )


@router.post("/sessions/{event_id}/cancel", response_model=Session)
def cancel(event_id: UUID, body: StrictRequest, sessions: Service):
    return sessions.cancel(event_id)


@router.post("/sessions/{event_id}/retry-registration", response_model=Session)
async def retry(event_id: UUID, body: StrictRequest, sessions: Service):
    return await sessions.retry_registration(event_id)


@router.post("/sessions/{event_id}/finish", response_model=Session)
def finish(event_id: UUID, body: StrictRequest, sessions: Service):
    return sessions.finish(event_id)
