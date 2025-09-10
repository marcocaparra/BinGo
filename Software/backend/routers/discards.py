from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List
from datetime import datetime

from database import get_db
from models.discard_model import Discard
from models.unique_code_model import UniqueCode
from models.user_model import User
from models.material_type_model import MaterialType

from schemas.discard_schema import DiscardRequestByApp, DiscardResponse
from auth import get_current_user
from schemas.user_schema import UserResponse

router = APIRouter(prefix="/discards", tags=["Descartes"])

@router.post("/", response_model=DiscardResponse, status_code=status.HTTP_201_CREATED)
def create_discard(
    discard_request: DiscardRequestByApp,
    db: Session = Depends(get_db),
    current_user: UserResponse = Depends(get_current_user)
):
    user_id = current_user.id

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

    if not unique_code_db.material_type:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Código único não possui um tipo de material associado válido. Contate o suporte técnico."
        )

    calculated_points = 0.0

    if unique_code_db.material_type.name.lower() == "eletrônico":
        calculated_points = unique_code_db.material_type.points_per_unit

    db_discard = Discard(
        user_id=user_id,
        material_type_id=unique_code_db.material_type_id,
        unique_code_id=unique_code_db.id,
        points_awarded=calculated_points,
        timestamp=datetime.utcnow()
    )
    db.add(db_discard)

    unique_code_db.is_used = True
    db.add(unique_code_db)

    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Erro ao carregar dados do usuário."
        )

    db_user.total_points += calculated_points
    db.add(db_user)

    if db_user.total_points >= 1000:
        db_user.level = 5
    elif db_user.total_points >= 500:
        db_user.level = 4
    elif db_user.total_points >= 200:
        db_user.level = 3
    elif db_user.total_points >= 50:
        db_user.level = 2
    else:
        db_user.level = 1

    db.add(db_user)

    db.commit()

    db.refresh(db_discard)
    db.refresh(unique_code_db)
    db.refresh(db_user)

    # Retorno da resposta
    return DiscardResponse(
        message="Descarte registrado com sucesso!",
        user_total_points=db_user.total_points,
        user_current_level=db_user.level,
        discard_id=str(db_discard.id)
    )


@router.get("/", response_model=List[DiscardResponse])
def get_discards(
    skip: int = 0, limit: int = 100,
    db: Session = Depends(get_db),
    current_user: UserResponse = Depends(get_current_user)
):
    user_id = current_user.id
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