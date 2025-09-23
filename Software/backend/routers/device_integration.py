from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import secrets
from typing import Optional

from database import get_db
from schemas.device_integration_schema import ImageClassificationRequest, ImageClassificationResponse
from models.material_type_model import MaterialType
from models.unique_code_model import UniqueCode
from services.ai_service import classify_image_with_gemini # --- NOVO IMPORT ---

router = APIRouter(prefix="/device", tags=["Integração com Dispositivos"])

@router.post("/classify_image", response_model=ImageClassificationResponse)
async def classify_image(
    request: ImageClassificationRequest,
    db: Session = Depends(get_db)
):

    selected_material_name, confidence, ia_description = await classify_image_with_gemini(request.image_base64)
    is_e_waste = (selected_material_name == "Eletrônico")
    action = "OPEN_ELECTRONIC_BIN" if is_e_waste else "OPEN_RECOVER_BIN"

    material_type_db = db.query(MaterialType).filter(MaterialType.name == selected_material_name).first()
    if not material_type_db:
        points = 25.0 if is_e_waste else 5.0
        new_material_type = MaterialType(name=selected_material_name, points_per_unit=points)
        db.add(new_material_type)
        db.commit()
        db.refresh(new_material_type)
        material_type_db = new_material_type


    generated_unique_code = None
    message_suffix = ""

    if is_e_waste:
        while True:
            generated_code_str = secrets.token_urlsafe(6).upper().replace('-', '').replace('_', '')[:6]
            existing_code = db.query(UniqueCode).filter(UniqueCode.code == generated_code_str).first()
            if not existing_code:
                generated_unique_code = generated_code_str
                break

        db_unique_code = UniqueCode(
            code=generated_unique_code,
            is_used=False,
            material_type_id=material_type_db.id
        )
        db.add(db_unique_code)
        db.commit()
        db.refresh(db_unique_code)
        message_suffix = f" Um código único '{generated_unique_code}' foi gerado para o descarte."
    else:
        message_suffix = " Nenhum código único será gerado."

    response_message = (
        f"Classificado como '{material_type_db.name}' (IA: '{ia_description}'). "
        f"Será acionada a {action.replace('_', ' ').lower()}." + message_suffix
    )

    return ImageClassificationResponse(
        is_e_waste=is_e_waste,
        material_type_name=material_type_db.name,
        confidence=confidence,
        message=response_message,
        action=action,
        unique_code=generated_unique_code
    )