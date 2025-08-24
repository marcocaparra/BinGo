from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from ..database import Base

class UniqueCode(Base):
    __tablename__ = 'unique_codes'

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(6), unique=True, nullable=False)
    is_used = Column(Boolean, default=False, nullable=False)
    generated_at = Column(DateTime(timezone=True), server_default=func.now())

    discard = relationship('Discard', back_populates='unique_code', uselist=False)

    def __repr__(self):
        return f"<UniqueCode(id={self.id}, code='{self.code}', is_used={self.is_used}, generated_at='{self.generated_at}')>"