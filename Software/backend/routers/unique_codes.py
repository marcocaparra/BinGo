from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import secrets 
from typing import Optional 
from backend.database import get_db
from backend.models.unique_code_model import UniqueCode
from backend.models.material_type_model import MaterialType
from backend.schemas.unique_code_schema import UniqueCodeGenerateRequest, UniqueCodeGenerateResponse, UniqueCodeResponse


router = APIRouter(prefix="/unique_codes", tags=["Códigos Únicos"])

@router.post("/generate", response_model=UniqueCodeGenerateResponse, status_code=status.HTTP_201_CREATED)
def generate_unique_code(
    request: UniqueCodeGenerateRequest,
    db: Session = Depends(get_db) 
):
    material_type = db.query(MaterialType).filter(MaterialType.name == request.material_type_name).first()
    if not material_type:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tipo de material '{request.material_type_name}' não encontrado. Por favor, certifique-se de que ele esteja registrado."
        )

    generated_code = None
    while True: 
       
        generated_code = secrets.token_urlsafe(8).upper() 
        existing_code = db.query(UniqueCode).filter(UniqueCode.code == generated_code).first()
        if not existing_code:
            break 

    db_unique_code = UniqueCode(
        code=generated_code,
        is_used=False,
        material_type_id=material_type.id
    )
    db.add(db_unique_code)
    db.commit()
    db.refresh(db_unique_code)

    return UniqueCodeGenerateResponse(
        code=db_unique_code.code,
        material_type_id=material_type.id,
        material_type_name=material_type.name,
        message="Código único gerado com sucesso."
    )

@router.get("/{code}", response_model=UniqueCodeResponse)
def get_unique_code_status(
    code: str,
    db: Session = Depends(get_db)
):
    unique_code = db.query(UniqueCode).filter(UniqueCode.code == code).first()
    if not unique_code:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Código único não encontrado."
        )
    return unique_code