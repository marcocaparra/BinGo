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

@router.post(
    "/users/me/missions/{mission_id}/accept",
    response_model=UserMissionResponse,
    summary="Permite que o usuário autenticado aceite uma missão específica",
    tags=["Users", "Missions"],
    status_code=status.HTTP_201_CREATED
)
def accept_mission(
    mission_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Permite que o usuário autenticado aceite (inicie) uma missão.
    - Verifica se a missão existe e está ativa.
    - Verifica se o usuário já aceitou ou completou esta missão.
    - Cria uma nova entrada em UserMission com status 'in_progress' e progress '0'.
    - Retorna os detalhes da UserMission criada/atualizada.
    """
    print(f"DEBUG: Tentando aceitar missão para user_id={current_user.id}, mission_id={mission_id}") # Adicione esta linha
    mission = db.query(Mission).filter(Mission.id == mission_id).first()
    if not mission:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Missão não encontrada."
        )

    if not mission.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta missão não está ativa e não pode ser aceita."
        )

    existing_user_mission = (
        db.query(UserMission)
        .filter(
            UserMission.user_id == current_user.id,
            UserMission.mission_id == mission_id
        )
        .first()
    )
    print(f"DEBUG: existing_user_mission: {existing_user_mission}") # Adicione esta linha

    if existing_user_mission:
        print(f"DEBUG: Status da missão existente: {existing_user_mission.status}") # Adicione esta linha
        if existing_user_mission.status == "completed":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Você já completou esta missão."
            )
        elif existing_user_mission.status in ["in_progress", "pending"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Você já aceitou esta missão e ela está em progresso."
            )
            
    new_user_mission = UserMission(
        user_id=current_user.id,
        mission_id=mission.id,
        status="in_progress",
        progress=0
    )

    db.add(new_user_mission)
    print("DEBUG: Adicionando nova UserMission e tentando commit...") # Adicione esta linha
    db.commit()
    print("DEBUG: Commit realizado com sucesso!") # Adicione esta linha (não deve ser printada se o erro persistir)
    db.refresh(new_user_mission)

    user_mission_with_details = (
        db.query(UserMission)
        .options(joinedload(UserMission.mission))
        .filter(UserMission.user_id == current_user.id, UserMission.mission_id == mission_id)
        .first()
    )

    return user_mission_with_details