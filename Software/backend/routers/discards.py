from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Dict, Any
from datetime import datetime

from database import get_db
from models.discard_model import Discard
from models.unique_code_model import UniqueCode
from models.user_model import User
from models.material_type_model import MaterialType
from models.achievement_model import UserAchievement
# --- ADIÇÃO 1: Importar os modelos de Missão ---
from models.mission_model import Mission, UserMission 

from schemas.discard_schema import DiscardRequestByApp, DiscardResponse, DiscardCreatedResponse
from schemas.achievement_schema import UnlockedAchievementDetail
# --- ADIÇÃO 2: Importar o schema de atualização de Missão ---
from schemas.user_mission_schemas import MissionUpdateResponse
from auth import get_current_user
from schemas.user_schema import UserResponse

from services.achievement_service import check_and_unlock_achievements, AchievementConditionType

router = APIRouter(prefix="/discards", tags=["Descartes"])


# --- ADIÇÃO 3: Nova função para processar o progresso das missões ---
def update_mission_progress(db: Session, user: User, event_data: Dict[str, Any]) -> List[UserMission]:
    """
    Verifica as missões ativas de um usuário e atualiza o progresso com base em um evento (ex: descarte).
    """
    updated_missions = []
    
    # Busca todas as missões ativas (Em Progresso) do usuário
    active_user_missions = db.query(UserMission).options(joinedload(UserMission.mission))\
        .filter(UserMission.user_id == user.id, UserMission.status == "Em Progresso").all()

    if not active_user_missions:
        return []

    material_type_id_of_discard = event_data.get("material_type_id")

    for user_mission in active_user_missions:
        mission = user_mission.mission
        mission_updated = False

        # Lógica para diferentes tipos de missão
        # Missão: Descartar X itens de qualquer tipo
        if mission.type == "discard_count":
            user_mission.progress += 1
            mission_updated = True
        
        # Missão: Descartar X itens de um tipo específico
        elif mission.type == "discard_specific_material":
            # O objetivo da missão deve conter o ID do material alvo
            mission_objective = mission.objective_as_dict or {}
            target_material_id = mission_objective.get("material_type_id")
            if target_material_id and material_type_id_of_discard == target_material_id:
                user_mission.progress += 1
                mission_updated = True
        
        # Missão: Acumular X pontos
        elif mission.type == "accumulate_points":
             # Esta lógica é mais complexa e pode ser implementada depois,
             # pois depende do total de pontos do usuário, não de um único evento.
             pass

        if mission_updated:
            # Verifica se a missão foi concluída
            if user_mission.progress >= mission.target_quantity:
                user_mission.status = "Concluída"
                user_mission.completed_at = datetime.utcnow()
                # Adiciona os pontos da missão ao total do usuário
                user.total_points += mission.reward_points

            db.add(user_mission)
            updated_missions.append(user_mission)

    return updated_missions


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

    if not unique_code_db or unique_code_db.is_used:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Código único inválido ou já utilizado."
        )

    if not unique_code_db.material_type:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Código único sem tipo de material associado."
        )

    # Lógica de descarte e pontos (seu código original)
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

    # Carrega o usuário para atualizar seus dados
    db_user = db.query(User).filter(User.id == user_id).first()
    db_user.total_points += calculated_points
    db_user.discard_count += 1
    
    # --- ADIÇÃO 4: Chamar a nova função de atualização de missões ---
    mission_event_data = {"material_type_id": unique_code_db.material_type_id}
    updated_user_missions = update_mission_progress(db, db_user, mission_event_data)
    
    # Lógica de atualização de nível (seu código original)
    if db_user.total_points >= 1000: db_user.level = 5
    elif db_user.total_points >= 500: db_user.level = 4
    elif db_user.total_points >= 200: db_user.level = 3
    elif db_user.total_points >= 50: db_user.level = 2
    else: db_user.level = 1
    
    # Lógica de conquistas (seu código original)
    newly_unlocked_user_achievements = check_and_unlock_achievements(
        db=db, user=db_user, event_type="DISCARD_PROCESSED",
        event_data={"material_type_id": unique_code_db.material_type_id}
    )
    
    db.commit()
    db.refresh(db_user)

    # --- ADIÇÃO 5: Preparar a resposta com as missões atualizadas ---
    mission_updates_for_response = [
        MissionUpdateResponse(
            mission_id=um.mission_id,
            new_progress=um.progress,
            new_status=um.status
        ) for um in updated_user_missions
    ]
    
    unlocked_achievements_for_response = [
        UnlockedAchievementDetail(
            id=ua.achievement.id, name=ua.achievement.name, description=ua.achievement.description,
            points_reward=ua.achievement.points_reward, badge_image_url=ua.achievement.badge_image_url,
            unlocked_at=ua.unlocked_at
        ) for ua in newly_unlocked_user_achievements
    ]

    return DiscardCreatedResponse(
        message="Descarte registrado com sucesso!",
        user_total_points=db_user.total_points,
        user_current_level=db_user.level,
        discard_id=str(db_discard.id),
        # A resposta agora inclui as atualizações das missões
        mission_updates=mission_updates_for_response,
        unlocked_achievements=unlocked_achievements_for_response
    )