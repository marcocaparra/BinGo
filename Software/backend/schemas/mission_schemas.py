from datetime import datetime
from pydantic import BaseModel, ConfigDict
from typing import Optional

class MissionResponse(BaseModel):
    id: int
    name: str
    description: str
    objective: str
    reward_points: int
    type: str
    is_active: bool
    start_date: datetime
    end_date: datetime
    target_quantity: int

    model_config = ConfigDict(from_attributes=True)