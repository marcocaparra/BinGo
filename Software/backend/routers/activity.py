from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime
from typing import List

from database import get_db
from auth import get_current_user
from models.user_model import User
from models.discard_model import Discard
from models.achievement_model import UserAchievement
from models.mission_model import UserMission

router = APIRouter(prefix="/activity", tags=["Activity"])

@router.get("/me")
def my_activity(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user)
):
    items: List[dict] = []

    # usa o campo correto do model: timestamp
    discards = (
        db.query(Discard)
          .filter(Discard.user_id == user.id)
          .order_by(Discard.timestamp.desc())
          .limit(20)
          .all()
    )
    for d in discards:
        items.append({
            "date": d.timestamp or datetime.utcnow(),
            "text": f"Fez um descarte de {d.material_type.name}"
        })

    achievements = (
        db.query(UserAchievement)
          .filter(UserAchievement.user_id == user.id)
          .order_by(UserAchievement.unlocked_at.desc())
          .limit(20)
          .all()
    )
    for a in achievements:
        items.append({
            "date": a.unlocked_at,
            "text": f"Desbloqueou conquista {a.achievement.name}"
        })

    missions = (
        db.query(UserMission)
          .filter(UserMission.user_id == user.id, UserMission.status == "completed")
          .order_by(UserMission.completed_at.desc())
          .limit(20)
          .all()
    )
    for m in missions:
        items.append({
            "date": m.completed_at,
            "text": f"Concluiu missão {m.mission.name}"
        })

    items = [i for i in items if i["date"]]
    items.sort(key=lambda x: x["date"], reverse=True)
    return items[:20]
