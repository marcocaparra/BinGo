from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session, require_admin, require_edge_headers
from app.api.schemas.machines import HeartbeatRequest, MachineResponse, MachineStatusUpdateRequest
from domain.machines.service import authenticate_machine, heartbeat, update_machine_status

router = APIRouter()


@router.post("/heartbeat", response_model=MachineResponse)
def machine_heartbeat(
    payload: HeartbeatRequest,
    edge_headers: tuple = Depends(require_edge_headers),
    session: Session = Depends(get_session),
) -> MachineResponse:
    machine_id, api_key = edge_headers
    authenticate_machine(session, machine_id, api_key)
    machine = heartbeat(
        session,
        machine_id,
        firmware_version=payload.firmware_version,
        bin_full=payload.bin_full,
        camera_ok=payload.camera_ok,
        net_ok=payload.net_ok,
    )
    return MachineResponse.model_validate(machine, from_attributes=True)


@router.patch("/{machine_id}/status", response_model=MachineResponse)
def patch_machine_status(
    machine_id: UUID,
    payload: MachineStatusUpdateRequest,
    _: dict = Depends(require_admin),
    session: Session = Depends(get_session),
) -> MachineResponse:
    machine = update_machine_status(
        session,
        machine_id,
        status=payload.status,
        bin_full=payload.bin_full,
        camera_ok=payload.camera_ok,
        net_ok=payload.net_ok,
    )
    return MachineResponse.model_validate(machine, from_attributes=True)

