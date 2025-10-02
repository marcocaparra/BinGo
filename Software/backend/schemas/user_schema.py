from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Optional

class UserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    total_points: float = 0.0

class UserCreate(UserBase):
    password: str = Field(..., min_length=3, max_length=100)
    name: str = Field(..., min_length=3, max_length=100)
    cpf: str = Field(..., min_length=11, max_length=11)
    phone_number: str = Field(..., min_length=8, max_length=20)

class UserResponse(UserBase):
    id: int
    is_active: bool
    name: str
    cpf: str
    phone_number: str
    discard_count: int
    mission_completed_count: int
    level: int

    class Config:
        from_attributes = True

class UserLogin(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str = 'bearer'

class TokenData(BaseModel):
    username: str | None = None