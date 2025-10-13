from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from sqlalchemy.dialects.mysql import JSON as MySQLJSON
from base_class import Base

class Achievement(Base):
    __tablename__ = 'achievements'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False)
    description = Column(Text, nullable=False)
    criteria_json = Column(MySQLJSON, nullable=False)
    points_reward = Column(Integer, nullable=False)
    badge_image_url = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    user_achievements = relationship('UserAchievement', back_populates='achievement')

    def __repr__(self):
        return f"<Achievement(id={self.id}, name='{self.name}')>"

class UserAchievement(Base):
    __tablename__ = 'user_achievements'

    user_id = Column(Integer, ForeignKey('users.id'), primary_key=True)
    achievement_id = Column(Integer, ForeignKey('achievements.id'), primary_key=True)
    unlocked_at = Column(DateTime, nullable=False, default=func.now())

    user = relationship('User', back_populates='user_achievements')
    achievement = relationship('Achievement', back_populates='user_achievements')

    def __repr__(self):
        return f"<UserAchievement(user_id={self.user_id}, achievement_id={self.achievement_id})>"