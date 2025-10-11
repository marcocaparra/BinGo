from datetime import datetime
from pydantic import BaseModel, ConfigDict
from typing import Optional

from schemas.mission_schemas import MissionResponse

class UserMissionResponse(BaseModel):
    user_id: int
    mission_id: int
    status: str
    progress: int
    completed_at: Optional[datetime] = None
    
    mission: MissionResponse

    model_config = ConfigDict(from_attributes=True)

class MissionUpdateResponse(BaseModel):
    mission_id: int
    new_progress: int
    new_status: str