from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload 
from typing import List

from backend.database import get_db
from backend.models.discard_model import Discard
from backend.models.unique_code_model import UniqueCode
from backend.schemas.discard_schema import DiscardRequestByApp, DiscardResponse
from backend.auth import get_current_user 

router = APIRouter(prefix="/discards", tags=["Descartes"])

@router.post("/", response_model=DiscardResponse, status_code=status.HTTP_201_CREATED)
def create_discard(
    discard_request: DiscardRequestByApp, 
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user) 
):
    user_id = current_user["id"] 

    unique_code_db = (
        db.query(UniqueCode)
        .options(joinedload(UniqueCode.material_type))
        .filter(UniqueCode.code == discard_request.unique_code)
        .first()
    )

    if not unique_code_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Código único não encontrado."
        )

    if unique_code_db.is_used:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Código único já foi utilizado."
        )
    
    if not unique_code_db.material_type_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Código único não possui um tipo de material associado. Contate o suporte técnico."
        )

    calculated_points = 0.0 

    db_discard = Discard(
        user_id=user_id,
        material_type_id=unique_code_db.material_type_id,
        unique_code_id=unique_code_db.id,
        points_awarded=calculated_points
    )
    
    db.add(db_discard)
    db.commit()
    db.refresh(db_discard)

    db_discard_response = (
        db.query(Discard)
        .options(
            joinedload(Discard.user),
            joinedload(Discard.material_type),
            joinedload(Discard.unique_code).joinedload(UniqueCode.material_type) 
        )
        .filter(Discard.id == db_discard.id)
        .first()
    )

    return db_discard_response

@router.get("/", response_model=List[DiscardResponse])
def get_discards(
    skip: int = 0, limit: int = 100,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    user_id = current_user["id"]
    discards = (
        db.query(Discard)
        .options(
            joinedload(Discard.user),
            joinedload(Discard.material_type),
            joinedload(Discard.unique_code).joinedload(UniqueCode.material_type) 
        )
        .filter(Discard.user_id == user_id)
        .offset(skip)
        .limit(limit)
        .all()
    )
    return discards