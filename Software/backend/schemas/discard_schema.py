# backend/schemas/discard_schema.py

from pydantic import BaseModel, Field
from datetime import datetime
from ..schemas.user_schema import UserResponse
from ..schemas.material_type_schema import MaterialTypeResponse
from ..schemas.unique_code_schema import UniqueCodeResponse

class DiscardBase(BaseModel):
    user_id: int
    material_type_id: int
    unique_code_id: int
    points_awarded: float = Field(..., gt=0)

class DiscardCreate(DiscardBase): 
    pass

class DiscardResponse(DiscardBase):
    id: int
    timestamp: datetime
    user: UserResponse
    material_type: MaterialTypeResponse
    unique_code: UniqueCodeResponse

    class Config:
        from_attributes = True