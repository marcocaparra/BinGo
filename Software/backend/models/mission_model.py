from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
import datetime

class Mission(Base):
    __tablename__ = 'missions'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False)
    description = Column(Text, nullable=False)
    objective = Column(Text, nullable=False)
    reward_points = Column(Integer, nullable=False)
    type = Column(String(50), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    start_date = Column(DateTime, nullable=False, default=func.now())
    end_date = Column(DateTime, nullable=False)

    user_mission = relationship('UserMission', back_populates='mission')

    def __repr__(self):
        return f"<Mission(id={self.id}, name='{self.name}', type='{self.type}')>"
    
class UserMission(Base):
    __tablename__ = 'user_missions'

    user_id = Column(Integer, ForeignKey('users.id'), primary_key=True)
    mission_id = Column(Integer, ForeignKey('missions.id'), primary_key=True)
    status = Column(String(50), nullable=False, default='pending')
    progress = Column(Integer, default=0, nullable=False)
    completed_at = Column(DateTime, nullable=True)
    
    user = relationship('User', back_populates='user_missions')
    mission = relationship('Mission', back_populates='user_missions')

    def __repr__(self):
        return f"<UserMission(user_id={self.user_id}, mission_id={self.mission_id}, status='{self.status}')>"