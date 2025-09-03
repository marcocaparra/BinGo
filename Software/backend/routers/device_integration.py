from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import base64
import random
from typing import Optional
from ..database import get_db
from ..schemas.device_integration_schema import ImageClassificationRequest, ImageClassificationResponse
from ..models.material_type_model import MaterialType

router = APIRouter(prefix='/device', tags=['Integração com Dispositivos'])

@router.post("/classify_image", response_model=ImageClassificationResponse)

def classify_image(request: ImageClassificationRequest, db: Session = Depends(get_db)):
    try:
        image_data = base64.b64decode(request.image_base64)
        print(f"Received image data of size: {len(image_data)} bytes")
        pass
    
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=f'Dados de imagem base64 inválidos: {e}'
        )

    mock_classification = [
        {"name": "Eletrônico", "is_e_waste": True, "confidence": 0.98}, 
        {"name": "Plástico", "is_e_waste": False, "confidence": 0.85},
        {"name": "Metal", "is_e_waste": False, "confidence": 0.80},
        {"name": "Vidro", "is_e_waste": False, "confidence": 0.70},
        {"name": "Papel", "is_e_waste": False, "confidence": 0.65},
    ]

    selected_classification = random.choice(mock_classifications)
    response_message = f"Classificado como '{selected_classification['name']}'."

    if selected_classification["is_e_waste"]:
        response_message += "É Lixo Eletrônico, prossiga com o descarte ideal."

    else:
        response_message += "Não é Lixo Eletrônico, será encaminhado para a caixa de descarte incorreto."

    return ImageClassificationResponse(
        is_e_waste=selected_classification["is_e_waste"],
        material_type_name=selected_classification["name"],
        confidence=selected_classification["confidence"],
        message=response_message
    )