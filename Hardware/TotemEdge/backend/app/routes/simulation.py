"""Contratos locais montados exclusivamente pela fábrica de simulação."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field, StrictBool, model_validator

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


class Close(Motion):
    hand_removed: StrictBool

    @model_validator(mode="after")
    def declared(self):
        if self.hand_removed is not True:
            raise ValueError("Declaração obrigatória.")
        return self


class SimulationActive(BaseModel):
    snapshot: SimulationSnapshot | None


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
    entry, snapshot = await flow.act(
        event_id,
        operation,
        body.mechanical_command_id,
        body.timeout_seconds,
        hand_removed=hand_removed,
    )
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


@router.post("/sessions/{event_id}/hatch", response_model=SimulationSnapshot)
async def hatch(event_id: UUID, body: Motion, response: Response, flow: Service):
    return await act(flow, event_id, "CYCLE_LOWER_HATCH", body, response)


@router.post("/sessions/{event_id}/confirm-initial", response_model=SimulationSnapshot)
async def confirm_initial(
    event_id: UUID, body: Motion, response: Response, flow: Service
):
    return await act(flow, event_id, "CONFIRM_INITIAL_STATE", body, response)
