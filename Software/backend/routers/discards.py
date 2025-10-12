from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func, and_
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone, date

from database import get_db
from models.discard_model import Discard
from models.unique_code_model import UniqueCode
from models.user_model import User
from models.material_type_model import MaterialType
from models.achievement_model import UserAchievement
from models.mission_model import Mission, UserMission

from schemas.discard_schema import DiscardRequestByApp, DiscardResponse, DiscardCreatedResponse
from schemas.achievement_schema import UnlockedAchievementDetail
from schemas.user_mission_schemas import MissionUpdateResponse
from auth import get_current_user
from schemas.user_schema import UserResponse

from services.achievement_service import check_and_unlock_achievements

router = APIRouter(prefix="/discards", tags=["Descartes"])

IN_PROGRESS_STATUSES = {
    "in_progress", "em progresso", "em_progresso", "pending", "pendente"
}
COMPLETED_STATUSES = {"completed", "concluida", "concluída"}

def _now_utc() -> datetime:
    return datetime.utcnow().replace(tzinfo=None)

def _normalize_to_in_progress(s: str) -> str:
    if (s or "").lower() in COMPLETED_STATUSES:
        return "completed"
    return "in_progress"

def _weekday_token(dt: datetime) -> str:
    return ["mon","tue","wed","thu","fri","sat","sun"][dt.weekday()]

def _parse_objective(mission: Mission) -> Dict[str, Any]:
    try:
        return mission.objective_as_dict or {}
    except Exception:
        return {}

def _sum_discard_points(db: Session, user_id: int) -> float:
    total = db.query(func.coalesce(func.sum(Discard.points_awarded), 0.0))\
              .filter(Discard.user_id == user_id).scalar()
    return float(total or 0.0)

def _count_discards_within_days(
    db: Session, user_id: int, days: int, material_type_id: Optional[int] = None
) -> int:
    since = _now_utc() - timedelta(days=days)
    q = db.query(func.count(Discard.id)).filter(
        Discard.user_id == user_id,
        Discard.timestamp >= since
    )
    if material_type_id:
        q = q.filter(Discard.material_type_id == material_type_id)
    return int(q.scalar() or 0)

def _current_streak_days(
    db: Session, user_id: int, material_type_id: Optional[int] = None
) -> int:
    """
    Conta dias consecutivos (incluindo hoje se houve descarte hoje) com >=1 descarte.
    Se material_type_id for informado, conta apenas descartes desse tipo.
    """
    days_back = 120
    since = date.fromordinal((_now_utc() - timedelta(days=days_back)).date().toordinal())
    q = db.query(func.date(Discard.timestamp))\
         .filter(Discard.user_id == user_id, Discard.timestamp >= since)
    if material_type_id:
        q = q.filter(Discard.material_type_id == material_type_id)
    q = q.group_by(func.date(Discard.timestamp)).order_by(func.date(Discard.timestamp).desc())
    rows = [r[0] for r in q.all()]

    if not rows:
        return 0

    dayset = set(rows)
    streak = 0
    d = _now_utc().date()
    while d in dayset:
        streak += 1
        d = d - timedelta(days=1)
    return streak

def update_mission_progress(db: Session, user: User, event_data: Dict[str, Any]) -> List[UserMission]:
    """
    Atualiza progresso das missões do usuário com base em um evento (ex.: descarte).
    - Compatível com status PT/EN ao ler, grava sempre EN: 'in_progress' / 'completed'.
    - Suporte a:
        * type == 'discard_count'
        * type == 'discard_specific_material'
        * type == 'accumulate_points' (objective.points_target)
      E no objective:
        * weekday: ["fri","sat","sun"]
        * within_days: N   (conta desc. na janela N dias)
        * streak_days: N   (>= 1 por dia por N dias seguidos)
    """
    updated: List[UserMission] = []

    active_user_missions: List[UserMission] = (
        db.query(UserMission)
        .options(joinedload(UserMission.mission))
        .filter(
            UserMission.user_id == user.id,
            ~UserMission.status.in_(list(COMPLETED_STATUSES))
        )
        .all()
    )
    if not active_user_missions:
        return []

    material_type_id_of_discard: Optional[int] = event_data.get("material_type_id")
    points_awarded_from_event: float = float(event_data.get("points_awarded") or 0.0)
    event_dt: datetime = event_data.get("timestamp") or _now_utc()
    event_weekday = _weekday_token(event_dt)

    for um in active_user_missions:
        mission = um.mission
        if not mission:
            continue

        obj = _parse_objective(mission)
        target = int(mission.target_quantity or 0)
        current = int(um.progress or 0)
        changed = False

        allowed_weekdays = set([w.lower() for w in obj.get("weekday", [])]) if obj.get("weekday") else None
        if allowed_weekdays and event_weekday not in allowed_weekdays:
            pass
        else:
            if mission.type == "discard_count":
                if "within_days" in obj:
                    days = int(obj["within_days"])
                    count = _count_discards_within_days(db, user.id, days, None)
                    new_progress = min(count, target or count)
                    if new_progress != current:
                        um.progress = new_progress
                        changed = True
                elif "streak_days" in obj:
                    streak_target = int(obj["streak_days"])
                    streak = _current_streak_days(db, user.id, None)
                    new_progress = min(streak, streak_target)
                    if new_progress != current:
                        um.progress = new_progress
                        changed = True
                else:
                    um.progress = current + 1
                    changed = True

            elif mission.type == "discard_specific_material":
                target_mat = obj.get("material_type_id")
                if target_mat and material_type_id_of_discard and int(material_type_id_of_discard) == int(target_mat):
                    if "within_days" in obj:
                        days = int(obj["within_days"])
                        count = _count_discards_within_days(db, user.id, days, int(target_mat))
                        new_progress = min(count, target or count)
                        if new_progress != current:
                            um.progress = new_progress
                            changed = True
                    elif "streak_days" in obj:
                        streak_target = int(obj["streak_days"])
                        streak = _current_streak_days(db, user.id, int(target_mat))
                        new_progress = min(streak, streak_target)
                        if new_progress != current:
                            um.progress = new_progress
                            changed = True
                    else:
                        um.progress = current + 1
                        changed = True

            elif mission.type == "accumulate_points":
                points_target = int(obj.get("points_target") or target or 0)
                total_points_from_discards = _sum_discard_points(db, user.id)
                new_progress = min(int(total_points_from_discards), points_target or int(total_points_from_discards))
                if new_progress != current:
                    um.progress = new_progress
                    changed = True

        if changed:
            if str(um.status or "").lower() in COMPLETED_STATUSES:
                pass
            else:
                um.status = "in_progress"

            if target and int(um.progress or 0) >= target:
                um.progress = target
                um.status = "completed"
                um.completed_at = _now_utc()

                user.total_points = float(user.total_points or 0.0) + int(mission.reward_points or 0)
                user.mission_completed_count = int(user.mission_completed_count or 0) + 1

            db.add(um)
            updated.append(um)

    return updated

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

    calculated_points = float(unique_code_db.material_type.points_per_unit or 0.0)

    ts = _now_utc()
    db_discard = Discard(
        user_id=user_id,
        material_type_id=unique_code_db.material_type_id,
        unique_code_id=unique_code_db.id,
        points_awarded=calculated_points,
        timestamp=ts
    )
    db.add(db_discard)

    unique_code_db.is_used = True

    db_user: User = db.query(User).filter(User.id == user_id).first()
    db_user.total_points = float(db_user.total_points or 0.0) + calculated_points
    db_user.discard_count = int(db_user.discard_count or 0) + 1

    mission_event_data = {
        "material_type_id": unique_code_db.material_type_id,
        "points_awarded": calculated_points,
        "timestamp": ts,
    }
    updated_user_missions = update_mission_progress(db, db_user, mission_event_data)

    tp = float(db_user.total_points or 0.0)
    if tp >= 1000:
        db_user.level = 5
    elif tp >= 500:
        db_user.level = 4
    elif tp >= 200:
        db_user.level = 3
    elif tp >= 50:
        db_user.level = 2
    else:
        db_user.level = 1

    newly_unlocked_user_achievements: List[UserAchievement] = check_and_unlock_achievements(
        db=db, user=db_user, event_type="DISCARD_PROCESSED",
        event_data={"material_type_id": unique_code_db.material_type_id}
    )

    db.commit()
    db.refresh(db_user)
    db.refresh(db_discard)

    mission_updates_for_response = [
        MissionUpdateResponse(
            mission_id=um.mission_id,
            new_progress=int(um.progress or 0),
            new_status=um.status
        ) for um in updated_user_missions
    ]

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
        user_total_points=float(db_user.total_points or 0.0),
        user_current_level=int(db_user.level or 1),
        discard_id=str(db_discard.id),
        mission_updates=mission_updates_for_response,
        unlocked_achievements=unlocked_achievements_for_response
    )
