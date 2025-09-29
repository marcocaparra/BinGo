from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import secrets
import os
import base64
import google.generativeai as genai

from database import get_db
from schemas.device_integration_schema import ImageClassificationRequest, ImageClassificationResponse
from models.material_type_model import MaterialType
from models.unique_code_model import UniqueCode

router = APIRouter(prefix="/device", tags=["Integração com Dispositivos"])

genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
model = genai.GenerativeModel("models/gemini-flash-latest")


def classify_with_gemini(image_b64: str):
    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Erro ao decodificar imagem base64: {e}"
        )

    prompt = (
        "Você é um classificador de imagens para lixo eletrônico. "
        "Analise APENAS o objeto visível na imagem fornecida e responda com UM ÚNICO termo exato: "
        "'Eletrônico' ou 'Não Eletrônico'.\n\n"
        "Definição de eletrônico: qualquer dispositivo ou acessório que dependa de circuitos eletrônicos, "
        "energia elétrica ou baterias para funcionar. Exemplos: celulares, notebooks, tablets, fones de ouvido, "
        "controles remotos, TVs, cabos, carregadores, consoles, câmeras digitais, teclados, mouses.\n\n"
        "Definição de não eletrônico: objetos comuns do dia a dia sem eletrônica. Exemplos: móveis, roupas, "
        "alimentos, garrafas, papel, madeira, plástico, vidro, utensílios de cozinha, plantas, animais.\n\n"
        "IMPORTANTE: se houver QUALQUER dúvida ou se o objeto não for reconhecido claramente como eletrônico, "
        "responda 'Não Eletrônico'.\n\n"
        "Responda apenas com 'Eletrônico' ou 'Não Eletrônico'."
    )

    try:
        response = model.generate_content([
            prompt,
            {"mime_type": "image/jpeg", "data": image_bytes}
        ])
        raw_text = response.text.strip()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erro na classificação com Gemini: {e}"
        )

    if "eletrônico" in raw_text.lower():
        return "Eletrônico", True, 0.95, "OPEN_ELECTRONIC_BIN"
    else:
        return "Não Eletrônico", False, 0.90, "OPEN_RECOVER_BIN"


@router.post("/classify_image", response_model=ImageClassificationResponse)
def classify_image(
    request: ImageClassificationRequest,
    db: Session = Depends(get_db)
):
    selected_material_name, is_e_waste, confidence, action = classify_with_gemini(request.image_base64)

    material_type_db = db.query(MaterialType).filter(MaterialType.name == selected_material_name).first()
    if not material_type_db:
        points = 25.0 if is_e_waste else 5.0
        new_material_type = MaterialType(name=selected_material_name, points_per_unit=points)
        db.add(new_material_type)
        db.commit()
        db.refresh(new_material_type)
        material_type_db = new_material_type

    generated_unique_code = None
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

    response_message = f"Classificado como '{material_type_db.name}'. Ação: {action}."
    if generated_unique_code:
        response_message += f" Código único '{generated_unique_code}' gerado."

    return ImageClassificationResponse(
        is_e_waste=is_e_waste,
        material_type_name=material_type_db.name,
        confidence=confidence,
        message=response_message,
        action=action,
        unique_code=generated_unique_code
    )
