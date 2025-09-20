# backend/schemas/discard_schema.py (CORRIGIDO)
from pydantic import BaseModel, Field
from datetime import datetime
from typing import List, Optional

# Importações de outros schemas são relativas, pois estão no mesmo pacote `schemas`.
from .user_schema import UserResponse
from .material_type_schema import MaterialTypeResponse
from .unique_code_schema import UniqueCodeResponse

class DiscardBase(BaseModel):
    user_id: int
    material_type_id: int
    unique_code_id: int
    points_awarded: float

class DiscardCreate(DiscardBase): 
    pass

class DiscardRequestByApp(BaseModel):
    unique_code: str = Field(..., description="O código único obtido da lixeira inteligente.")

# NOVO: Schema para detalhes de atualização de missão
class MissionUpdateDetails(BaseModel):
    mission_id: int
    mission_name: str
    progress: int
    status: str 
    completed: bool
    reward_points_added: float

class DiscardCreatedResponse(BaseModel):
    message: str
    user_total_points: float
    user_current_level: int
    discard_id: str
    mission_updates: List[MissionUpdateDetails] = Field(default_factory=list, description="Lista de missões do usuário que foram atualizadas ou concluídas.") # ADICIONADO

class DiscardResponse(BaseModel):
    id: int
    user_id: int
    material_type_id: int
    unique_code_id: int
    timestamp: datetime
    points_awarded: float
    # REMOVIDO: message, user_total_points, user_current_level (pertencem a DiscardCreatedResponse)
    user: UserResponse
    material_type: MaterialTypeResponse
    unique_code: UniqueCodeResponse

    class Config:
        from_attributes = True