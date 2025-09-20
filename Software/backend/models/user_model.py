from sqlalchemy import Column, Integer, String, Boolean, Float, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from base_class import Base 

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)   
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=func.now())
    total_points = Column(Float, default=0.0)
    level = Column(Integer, default=1)
    name = Column(String(100), nullable=False)
    cpf = Column(String(11), unique=True, index=True, nullable=False)
    phone_number = Column(String(20), nullable=False)

    discards = relationship('Discard', back_populates='user')
    user_missions = relationship('UserMission', back_populates='user')
    user_achievements = relationship('UserAchievement', back_populates='user')

    def __repr__(self):
        return f"<User(id={self.id}, username='{self.username}', email='{self.email}')>"