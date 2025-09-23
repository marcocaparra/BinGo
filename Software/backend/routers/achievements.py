from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List

from database import get_db
from models.achievement_model import Achievement, UserAchievement
from schemas.achievement_schema import AchievementResponse, UserAchievementResponse
from auth import get_current_user
from schemas.user_schema import UserResponse

router = APIRouter(prefix="/achievements", tags=["Achievements"])

@router.get("/", response_model=List[AchievementResponse], summary="Listar todas as conquistas ativas")
def get_all_active_achievements(db: Session = Depends(get_db)):
    """
    Retorna uma lista de todas as conquistas ativas configuradas no sistema.
    """
    achievements = db.query(Achievement).filter(Achievement.is_active == True).all()
    return achievements

@router.get("/me/", response_model=List[UserAchievementResponse], summary="Listar conquistas desbloqueadas pelo usuário atual")
def get_user_unlocked_achievements(
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Retorna uma lista das conquistas desbloqueadas pelo usuário autenticado,
    incluindo os detalhes de cada conquista e quando foi desbloqueada.
    """
    user_achievements = (
        db.query(UserAchievement)
        .options(joinedload(UserAchievement.achievement))
        .filter(UserAchievement.user_id == current_user.id)
        .all()
    )
    return user_achievements