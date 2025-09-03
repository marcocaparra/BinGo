from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class UniqueCodeBase(BaseModel):
    code: str = Field(..., max_length=50)

class UniqueCodeCreate(UniqueCodeBase):
    pass

class UniqueCodeGenerateRequest(BaseModel):
    material_type_name: str = Field(..., description="Nome do tipo de material classificado pela IA (ex: 'Plástico', 'Eletrônico').")

class UniqueCodeGenerateResponse(BaseModel):
    code: str = Field(..., description="O código único recém-gerado para o descarte.")
    material_type_id: int = Field(..., description="ID do tipo de material associado.")
    material_type_name: str = Field(..., description="Nome do tipo de material associado.")
    message: str = "Código único gerado com sucesso."

class UniqueCodeResponse(UniqueCodeBase):
    id: int
    is_used: bool
    generated_at: datetime
    material_type_id: int

    class Config:
        from_attributes = True