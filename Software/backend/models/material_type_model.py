from sqlalchemy import Column, String, Integer, Float
from sqlalchemy.orm import relationship
from backend.database import Base

class MaterialType(Base):
    __tablename__ = 'material_types'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), unique=True, index=True, nullable=False)
    points_per_unit = Column(Float, nullable=False)

    discards = relationship('Discard', back_populates='material_type')

    def __repr__(self):
        return f"<MaterialType(id={self.id}, name='{self.name}', points_per_unit={self.points_per_unit})>"