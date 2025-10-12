from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import List, Optional

from .user_schema import UserResponse
from .material_type_schema import MaterialTypeResponse
from .unique_code_schema import UniqueCodeResponse
from .achievement_schema import UnlockedAchievementDetail
from .user_mission_schemas import MissionUpdateResponse

class DiscardBase(BaseModel):
    user_id: int
    material_type_id: int
    unique_code_id: int
    points_awarded: float

class DiscardCreate(DiscardBase):
    pass

class DiscardRequestByApp(BaseModel):
    unique_code: str = Field(..., description="O código único obtido da lixeira inteligente.")

class DiscardCreatedResponse(BaseModel):
    message: str
    user_total_points: float
    user_current_level: int
    discard_id: str
    mission_updates: List[MissionUpdateResponse] = Field(default_factory=list, description="Lista de missões do usuário que foram atualizadas ou concluídas.")
    unlocked_achievements: List[UnlockedAchievementDetail] = Field(default_factory=list, description="Lista de conquistas recém-desbloqueadas pelo usuário.")

class DiscardResponse(BaseModel):
    id: int
    user_id: int
    material_type_id: int
    unique_code_id: int
    timestamp: datetime
    points_awarded: float
    user: UserResponse
    material_type: MaterialTypeResponse
    unique_code: UniqueCodeResponse

    model_config = ConfigDict(from_attributes=True)