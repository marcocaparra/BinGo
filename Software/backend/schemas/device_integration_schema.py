from pydantic import BaseModel, Field
from typing import Optional

class ImageClassificationRequest(BaseModel):
    image_base64: str = Field(..., description='Dados da imagem codificados em base64.')

class ImageClassificationResponse(BaseModel):
    is_e_waste: bool = Field(..., description='True se classificado como lixo eletrônico, False caso contrário.')
    material_type_name: Optional[str] = Field(None, description="Nome do tipo de material inferido (ex: 'Plástico', 'Metal', 'Eletrônico').")
    confidence: Optional[float] = Field(None, ge=0.0, le=1.0, description="Pontuação de confiança da classificação (0.0 a 1.0).")
    message: str = Field('Imagem classificada com sucesso!', description='Uma mensagem descritiva do resultado da classificação.')
