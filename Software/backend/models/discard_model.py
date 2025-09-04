from sqlalchemy import Column, Integer, ForeignKey, String, DateTime, Float
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from backend.database import Base

class Discard(Base):
    __tablename__ = "discards"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    material_type_id = Column(Integer, ForeignKey("material_types.id"), nullable=False)
    unique_code_id = Column(Integer, ForeignKey("unique_codes.id"), unique=True, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    points_awarded = Column(Float, nullable=False)
    user = relationship("User", back_populates="discards")
    material_type = relationship("MaterialType", back_populates="discards")
    unique_code = relationship("UniqueCode", back_populates="discard", uselist=False)

    def __repr__(self):
        return (f"<Discard(id={self.id}, user_id={self.user_id}, "
                f"material_type_id={self.material_type_id}, unique_code_id={self.unique_code_id}, "
                f"timestamp='{self.timestamp}', points_awarded={self.points_awarded})>")