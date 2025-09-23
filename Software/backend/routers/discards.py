from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List
from datetime import datetime

from database import get_db
from models.discard_model import Discard
from models.unique_code_model import UniqueCode
from models.user_model import User
from models.material_type_model import MaterialType
from models.achievement_model import UserAchievement

from schemas.discard_schema import DiscardRequestByApp, DiscardResponse, DiscardCreatedResponse
from schemas.achievement_schema import UnlockedAchievementDetail
from auth import get_current_user
from schemas.user_schema import UserResponse

from services.achievement_service import check_and_unlock_achievements, AchievementConditionType

router = APIRouter(prefix="/discards", tags=["Descartes"])

@router.post("/", response_model=DiscardCreatedResponse, status_code=status.HTTP_201_CREATED)
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

    db_user = db.query(User).options(joinedload(User.user_achievements).joinedload(UserAchievement.achievement)).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Erro ao carregar dados do usuário."
        )

    db_user.total_points += calculated_points
    db_user.discard_count += 1

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

    newly_unlocked_user_achievements = check_and_unlock_achievements(
        db=db,
        user=db_user,
        event_type="DISCARD_PROCESSED",
        event_data={"material_type_id": unique_code_db.material_type_id}
    )
    
    db.commit()
    
    db.refresh(db_discard)
    db.refresh(unique_code_db)
    db.refresh(db_user)
    for ua in newly_unlocked_user_achievements:
         db.refresh(ua) 

    unlocked_achievements_for_response = [
        UnlockedAchievementDetail(
            id=ua.achievement.id,
            name=ua.achievement.name,
            description=ua.achievement.description,
            points_reward=ua.achievement.points_reward,
            badge_image_url=ua.achievement.badge_image_url,
            unlocked_at=ua.unlocked_at
        ) for ua in newly_unlocked_user_achievements
    ]

    return DiscardCreatedResponse(
        message="Descarte registrado com sucesso!",
        user_total_points=db_user.total_points,
        user_current_level=db_user.level,
        discard_id=str(db_discard.id),
        mission_updates=[],
        unlocked_achievements=unlocked_achievements_for_response
    )