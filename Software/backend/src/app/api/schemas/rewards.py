from uuid import UUID

from pydantic import BaseModel

from shared.constants.enums import RewardStatus


class RewardItemResponse(BaseModel):
    id: UUID
    name: str
    description: str | None
    cost_points: int
    category: str | None
    status: RewardStatus
    stock_qty: int | None


class RewardUpdateRequest(BaseModel):
    is_active: bool | None = None
    status: RewardStatus | None = None
    stock_qty: int | None = None

