from pydantic import BaseModel, ConfigDict
from datetime import datetime

class RewardResponse(BaseModel):
    id: int
    name: str
    description: str
    cost: int
    location: str
    expires_at: datetime

    model_config = ConfigDict(from_attributes=True)

class RedeemResponse(BaseModel):
    message: str
    new_total_points: int
    redemption_code: str