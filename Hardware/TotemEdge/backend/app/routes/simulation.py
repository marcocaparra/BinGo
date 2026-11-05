"""Contratos locais montados exclusivamente pela fábrica de simulação."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field, StrictBool, model_validator

from app.cycles import CycleError
from app.routes.sessions import StrictRequest, Safety
from app.services.simulation_flow import (
    SimulationCommandSnapshot,
    SimulationFlow,
    SimulationSnapshot,
)

router = APIRouter(prefix="/local/simulation")


def service(request: Request) -> SimulationFlow:
    return request.app.state.simulation_flow


Service = Annotated[SimulationFlow, Depends(service)]


class SimulationStart(StrictRequest):
    command_id: UUID


class Motion(StrictRequest):
    mechanical_command_id: UUID
    timeout_seconds: float = Field(default=10.0, gt=0, allow_inf_nan=False, strict=True)
    # Exigido em open/hatch somente no DEV conectado; nunca compõe o comando.
    pin: str | None = Field(default=None, pattern=r"^[0-9]{4}$", repr=False)


class Close(Motion):
    hand_removed: StrictBool

    @model_validator(mode="after")
    def declared(self):
        if self.hand_removed is not True:
            raise ValueError("Declaração obrigatória.")
        return self


class SimulationActive(BaseModel):
    snapshot: SimulationSnapshot | None


class VisionReview(StrictRequest):
    capture_id: UUID
    item_id: str = Field(pattern=r"^(battery|cable|phone|small|unknown)$")
    action: str = Field(pattern=r"^(confirm|correct)$")


class VisionAnalyze(StrictRequest):
    capture_id: UUID
    analysis_attempt_id: UUID | None = None


class VisionRecapture(StrictRequest):
    capture_id: UUID
    recapture_id: UUID


@router.post("/sessions/{event_id}/vision-recapture", response_model=SimulationSnapshot)
async def vision_recapture(event_id: UUID, body: VisionRecapture, flow: Service):
    if flow.vision is None:
        raise CycleError("VISION_NOT_INTEGRATED", 503)
    flow.vision.recapture(event_id, body.capture_id, body.recapture_id)
    return flow.get(event_id)


@router.post("/sessions/{event_id}/vision-analyze", response_model=SimulationSnapshot)
async def vision_analyze(event_id: UUID, body: VisionAnalyze, flow: Service):
    if flow.vision is None:
        raise CycleError("VISION_NOT_INTEGRATED", 503)
    if body.analysis_attempt_id is not None:
        flow.vision.retry_analysis(event_id, body.capture_id, body.analysis_attempt_id)
    else:
        flow.vision.request_analysis(event_id, body.capture_id)
    return flow.get(event_id)


@router.get("/sessions/{event_id}/vision-image/{capture_id}")
def vision_image(event_id: UUID, capture_id: UUID, request: Request, flow: Service):
    if request.headers.get("X-Totem-Request") != "1":
        raise CycleError("LOCAL_ORIGIN_REQUIRED", 403)
    if flow.vision is None:
        raise CycleError("VISION_NOT_INTEGRATED", 503)
    frame = flow.vision.image(event_id, capture_id)
    return Response(
        frame.content,
        media_type=frame.media_type,
        headers={
            "Cache-Control": "no-store",
            "X-Capture-Id": str(capture_id),
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.post("/sessions/{event_id}/vision-review", response_model=SimulationSnapshot)
def vision_review(event_id: UUID, body: VisionReview, flow: Service):
    if flow.vision is None:
        raise CycleError("VISION_NOT_INTEGRATED", 503)
    flow.vision.review(event_id, body.capture_id, body.item_id, body.action)
    return flow.get(event_id)


@router.post("/sessions", response_model=SimulationSnapshot)
def start(body: SimulationStart, flow: Service):
    return flow.start(body.command_id)


@router.get("/sessions/active", response_model=SimulationActive)
def active(flow: Service):
    return SimulationActive(snapshot=flow.active())


@router.get("/sessions/{event_id}", response_model=SimulationSnapshot)
def get(event_id: UUID, flow: Service):
    return flow.get(event_id)


@router.post("/sessions/{event_id}/safety", response_model=SimulationSnapshot)
def safety(event_id: UUID, body: Safety, flow: Service):
    return flow.safety(event_id, body.has_risk)


@router.post("/sessions/{event_id}/review-fixture", response_model=SimulationSnapshot)
def review_fixture(event_id: UUID, body: StrictRequest, flow: Service):
    return flow.review_fixture(event_id)


@router.post("/sessions/{event_id}/cancel", response_model=SimulationSnapshot)
def cancel(event_id: UUID, body: StrictRequest, flow: Service):
    return flow.cancel(event_id)


@router.get(
    "/sessions/{event_id}/commands/{identifier}",
    response_model=SimulationCommandSnapshot,
)
def command(event_id: UUID, identifier: UUID, flow: Service):
    return flow.command(event_id, identifier)


async def act(flow, event_id, operation, body, response, *, hand_removed=False):
    try:
        if "pin" in body.model_fields_set and (
            not flow.store.identity_scope
            or operation not in {"OPEN_INSERTION_DOOR", "CYCLE_LOWER_HATCH"}
        ):
            raise CycleError("INVALID_LOCAL_CONTRACT", 422)
        entry, snapshot = await flow.act(
            event_id,
            operation,
            body.mechanical_command_id,
            body.timeout_seconds,
            hand_removed=hand_removed,
            pin=body.pin,
        )
    finally:
        body.pin = None
    response.status_code = (
        202 if entry.phase in {"INTENT", "DISPATCHING", "ACCEPTED"} else 200
    )
    return snapshot


@router.post("/sessions/{event_id}/open", response_model=SimulationSnapshot)
async def open_door(event_id: UUID, body: Motion, response: Response, flow: Service):
    return await act(flow, event_id, "OPEN_INSERTION_DOOR", body, response)


@router.post("/sessions/{event_id}/close", response_model=SimulationSnapshot)
async def close_door(event_id: UUID, body: Close, response: Response, flow: Service):
    return await act(
        flow, event_id, "CLOSE_INSERTION_DOOR", body, response, hand_removed=True
    )


@router.post("/sessions/{event_id}/hand-removed", response_model=SimulationSnapshot)
async def hand_removed(event_id: UUID, body: Close, response: Response, flow: Service):
    return await act(
        flow, event_id, "CONFIRM_HAND_REMOVED", body, response, hand_removed=True
    )


@router.post("/sessions/{event_id}/hatch", response_model=SimulationSnapshot)
async def hatch(event_id: UUID, body: Motion, response: Response, flow: Service):
    return await act(flow, event_id, "CYCLE_LOWER_HATCH", body, response)


@router.post("/sessions/{event_id}/confirm-initial", response_model=SimulationSnapshot)
async def confirm_initial(
    event_id: UUID, body: Motion, response: Response, flow: Service
):
    return await act(flow, event_id, "CONFIRM_INITIAL_STATE", body, response)
