from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import RedemptionStatus


class RedemptionCreateRequest(BaseModel):
    reward_id: UUID


class RedemptionResponse(BaseModel):
    id: UUID
    code: str
    status: RedemptionStatus
    created_at: datetime
    expires_at: datetime | None
    delivered_at: datetime | None

