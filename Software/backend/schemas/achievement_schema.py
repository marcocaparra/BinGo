from pydantic import BaseModel, ConfigDict, Field
from datetime import datetime
from typing import Dict, Any, List, Optional

class AchievementBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: str
    criteria_json: Dict[str, Any]
    points_reward: int
    badge_image_url: str = Field(..., max_length=255)
    is_active: bool = True

class AchievementCreate(AchievementBase):
    pass

class AchievementResponse(AchievementBase):
    id: int

    model_config = ConfigDict(from_attributes=True)

class UserAchievementResponse(BaseModel):
    user_id: int
    achievement_id: int
    unlocked_at: datetime
    
    achievement: AchievementResponse

    model_config = ConfigDict(from_attributes=True)

class UnlockedAchievementDetail(BaseModel):
    id: int
    name: str
    description: str
    points_reward: int
    badge_image_url: str
    unlocked_at: datetime

    model_config = ConfigDict(from_attributes=True)