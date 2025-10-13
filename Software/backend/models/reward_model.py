from sqlalchemy import Column, Integer, String, DateTime
from base_class import Base

class Reward(Base):
    __tablename__ = "rewards"
    
    id = Column(Integer, primary_key=True, index=True)
    
    name = Column(String(100), nullable=False)
    description = Column(String(255))
    location = Column(String(100))
    
    cost = Column(Integer, nullable=False)
    expires_at = Column(DateTime)