from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import MachineStatus


class HeartbeatRequest(BaseModel):
    firmware_version: str | None = None
    bin_full: bool = False
    camera_ok: bool = True
    net_ok: bool = True


class MachineStatusUpdateRequest(BaseModel):
    status: MachineStatus
    bin_full: bool | None = None
    camera_ok: bool | None = None
    net_ok: bool | None = None


class MachineResponse(BaseModel):
    id: UUID
    status: MachineStatus
    firmware_version: str | None
    bin_full: bool
    camera_ok: bool
    net_ok: bool

