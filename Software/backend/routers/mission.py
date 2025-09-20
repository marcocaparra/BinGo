from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List

from database import get_db
from auth import get_current_user
from models.user_model import User
from models.mission_model import Mission
from models.mission_model import UserMission
from schemas.mission_schemas import MissionResponse
from schemas.user_mission_schemas import UserMissionResponse

router = APIRouter()

@router.get(
    "/missions",
    response_model=List[MissionResponse],
    summary="Listar todas as missões ativas disponíveis",
    tags=["Missions"]
)
def get_all_active_missions(db: Session = Depends(get_db)):
    """
    Recupera uma lista de todas as missões ativas disponíveis no sistema.
    """
    missions = db.query(Mission).filter(Mission.is_active == True).all()
    return missions

@router.get(
    "/users/me/missions",
    response_model=List[UserMissionResponse],
    summary="Listar missões para o usuário autenticado atual",
    tags=["Users", "Missions"]
)
def get_user_missions(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Recupera uma lista de missões associadas ao usuário autenticado atual,
    incluindo seu status e progresso.
    """

    user_missions = (
        db.query(UserMission)
        .filter(UserMission.user_id == current_user.id)
        .options(joinedload(UserMission.mission))
        .all()
    )

    return user_missions