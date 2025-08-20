from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from ..database import Base
from .user_model import User
from .material_type_model import MaterialType

class Discard(Base):
    __tablename__ = 'discards'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    material_type_id = Column(Integer, ForeignKey('material_types.id'), nullable=False)
    unique_code = Column(String(255), unique=True, index=True, nullable=False)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False)
    points_awarded = Column(Integer, nullable=False)

    user = relationship('User', backref='discards')
    material_type = relationship('MaterialType', backref='discards')

    def __repr__(self):
        return f"<Discard(id={self.id}, user_id={self.user_id}, material_type_id={self.material_type_id}, points_awarded={self.points_awarded}, timestamp='{self.timestamp}')>"