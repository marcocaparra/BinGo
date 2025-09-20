from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload, selectinload
from typing import List, Optional
from datetime import datetime, UTC
import json

from database import get_db
from models.discard_model import Discard
from models.unique_code_model import UniqueCode
from models.user_model import User
from models.material_type_model import MaterialType
from models.mission_model import Mission, UserMission

from schemas.discard_schema import DiscardRequestByApp, DiscardCreatedResponse, MissionUpdateDetails, DiscardResponse # Adicionado MissionUpdateDetails e DiscardResponse
from auth import get_current_user
from schemas.user_schema import UserResponse


router = APIRouter(prefix="/discards", tags=["Descartes"])

async def _process_missions_after_discard(
    db: Session,
    user: User, 
    discarded_material_type_id: int
) -> List[MissionUpdateDetails]:
    """
    Processa as missões do usuário após um descarte bem-sucedido.
    Atualiza o progresso, marca missões como concluídas e retorna detalhes das atualizações.
    """
    
    updated_missions_details: List[MissionUpdateDetails] = []
    
    user_active_missions = (
        db.query(UserMission)
        .options(selectinload(UserMission.mission))
        .filter(UserMission.user_id == user.id, UserMission.status == "Em Progresso")
        .all()
    )

    for user_mission in user_active_missions:
        mission: Mission = user_mission.mission

        if not mission or not mission.is_active:
            continue

        objective_criteria = json.loads(mission.objective) if isinstance(mission.objective, str) else mission.objective

        if objective_criteria and objective_criteria.get("action_type") == "discard":
            target_material_type_id_for_mission = objective_criteria.get("material_type_id")

            if target_material_type_id_for_mission is not None and target_material_type_id_for_mission != discarded_material_type_id:
                continue

            user_mission.progress += 1

            mission_completed = False
            reward_points_added = 0.0

            if user_mission.progress >= mission.target_quantity:
                user_mission.status = "Concluída"
                user_mission.completed_at = datetime.now(UTC)
                mission_completed = True
                reward_points_added = float(mission.reward_points)
                user.total_points += reward_points_added
                
                print(f"🎉 [EVENTO] Missão '{mission.name}' (ID: {mission.id}) concluída pelo usuário {user.id}! +{reward_points_added} pontos.")

            db.add(user_mission)
            db.add(user)
            
            updated_missions_details.append(
                MissionUpdateDetails(
                    mission_id=mission.id,
                    mission_name=mission.name,
                    progress=user_mission.progress,
                    status=user_mission.status,
                    completed=mission_completed,
                    reward_points_added=reward_points_added
                )
            )
    
    return updated_missions_details


@router.post("/", response_model=DiscardCreatedResponse, status_code=status.HTTP_201_CREATED)
async def create_discard(
    discard_request: DiscardRequestByApp,
    db: Session = Depends(get_db),
    current_user: UserResponse = Depends(get_current_user)
):
    db_user = db.query(User).filter(User.id == current_user.id).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Erro ao carregar dados do usuário autenticado do banco de dados."
        )

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

    calculated_points = unique_code_db.material_type.points_per_unit
    
    db_discard = Discard(
        user_id=db_user.id,
        material_type_id=unique_code_db.material_type_id,
        unique_code_id=unique_code_db.id,
        points_awarded=calculated_points,
        timestamp=datetime.now(UTC)
    )
    db.add(db_discard)

    unique_code_db.is_used = True
    db.add(unique_code_db)

    db_user.total_points += calculated_points
    
    mission_updates_list = await _process_missions_after_discard(
        db=db,
        user=db_user,
        discarded_material_type_id=unique_code_db.material_type_id
    )
    
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

    try:
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erro ao salvar descarte e atualizar missões: {e}"
        )

    db.refresh(db_discard)
    db.refresh(unique_code_db)
    db.refresh(db_user)

    return DiscardCreatedResponse(
        message="Descarte registrado com sucesso!",
        user_total_points=db_user.total_points,
        user_current_level=db_user.level,
        discard_id=str(db_discard.id),
        mission_updates=mission_updates_list
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