from sqlalchemy.orm import Session
from typing import List, Dict, Any, Optional
from datetime import datetime

from models.achievement_model import Achievement, UserAchievement
from models.user_model import User
from models.discard_model import Discard

class AchievementConditionType:
    FIRST_DISCARD = "first_discard"
    TOTAL_POINTS_REACHED = "total_points_reached"
    TOTAL_DISCARDS_COUNT = "total_discards_count"
    MISSIONS_COMPLETED_COUNT = "missions_completed_count"
    SPECIFIC_MATERIAL_DISCARD_COUNT = "specific_material_discard_count"

def check_and_unlock_achievements(
    db: Session, 
    user: User,
    event_type: str, 
    event_data: Optional[Dict[str, Any]] = None
) -> List[UserAchievement]:

    event_data = event_data or {}
    newly_unlocked_achievements: List[UserAchievement] = []

    unlocked_achievement_ids = {ua.achievement_id for ua in user.user_achievements}
    
    potential_achievements = db.query(Achievement).filter(
        Achievement.is_active == True,
        Achievement.id.notin_(unlocked_achievement_ids)
    ).all()

    for achievement in potential_achievements:
        is_unlocked = False
        criteria = achievement.criteria_json
        
        condition_type = criteria.get("type")
        target_value = criteria.get("target")

        if condition_type == AchievementConditionType.FIRST_DISCARD:
            if event_type == "DISCARD_PROCESSED" and user.discard_count == 1:
                is_unlocked = True
        
        elif condition_type == AchievementConditionType.TOTAL_POINTS_REACHED:
            if user.total_points >= target_value:
                is_unlocked = True

        elif condition_type == AchievementConditionType.TOTAL_DISCARDS_COUNT:
            if user.discard_count >= target_value:
                is_unlocked = True
        
        elif condition_type == AchievementConditionType.MISSIONS_COMPLETED_COUNT:
            if user.mission_completed_count >= target_value:
                is_unlocked = True
        
        elif condition_type == AchievementConditionType.SPECIFIC_MATERIAL_DISCARD_COUNT:
            if event_type == "DISCARD_PROCESSED" and event_data.get("material_type_id") == criteria.get("material_type_id"):
                specific_material_discards_count = db.query(Discard).filter(
                    Discard.user_id == user.id,
                    Discard.material_type_id == criteria.get("material_type_id")
                ).count()
                if specific_material_discards_count >= target_value:
                    is_unlocked = True

        if is_unlocked:
            user_achievement = UserAchievement(
                user_id=user.id,
                achievement_id=achievement.id,
                unlocked_at=datetime.utcnow()
            )
            db.add(user_achievement)
            
            if achievement.points_reward > 0:
                user.total_points += achievement.points_reward
            
            newly_unlocked_achievements.append(user_achievement)
            
    return newly_unlocked_achievements