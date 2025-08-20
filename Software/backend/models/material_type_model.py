from sqlalchemy import Column, String, Integer
from ..database import Base

class MaterialType(Base):
    __tablename__ = 'material_types'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, index=True, nullable=False)
    points_per_unit = Column(Integer, nullable=False, default=1)

    def __repr__(self):
        return f"<MaterialType(id={self.id}, name='{self.name}', points_per_unit={self.points_per_unit})>"