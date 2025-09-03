from pydantic import BaseModel, Field
from datetime import datetime

class UniqueCodeBase(BaseModel):
    code: str = Field(..., max_length=50)

class UniqueCodeCreate(UniqueCodeBase):
    pass

class UniqueCodeResponse(UniqueCodeBase):
    id: int
    is_used: bool
    generated_at: datetime

    class Config:
        from_attributes = True