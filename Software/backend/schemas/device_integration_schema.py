# backend/schemas/device_integration_schema.py
from pydantic import BaseModel, Field
from typing import Optional

class ImageClassificationRequest(BaseModel):
    image_base64: str = Field(..., description="Imagem do resíduo em formato Base64.")

class ImageClassificationResponse(BaseModel):
    is_e_waste: bool = Field(..., description="True se classificado como lixo eletrônico, False caso contrário.")
    material_type_name: str = Field(..., description="Nome do tipo de material classificado (Eletrônico ou Não Eletrônico).")
    confidence: float = Field(..., description="Nível de confiança da classificação (0.0 a 1.0).")
    message: str = Field(..., description="Mensagem descritiva da classificação e ação tomada.")
    action: str = Field(..., description="Ação a ser executada pela lixeira (OPEN_ELECTRONIC_BIN ou OPEN_RECOVER_BIN).")
    unique_code: Optional[str] = Field(None, description="Código único gerado para o descarte (apenas para lixo eletrônico).")

    class Config:
        from_attributes = True
