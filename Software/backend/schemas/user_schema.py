from pydantic import BaseModel, EmailStr, Field
from datetime import datetime

class UserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr

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

class MaterialTypeBase(BaseModel):
    name: str
    points_per_unit: int

class MaterialTypeCreate(MaterialTypeBase):
    pass

class MaterialTypeResponse(MaterialTypeBase):
    id: int
    class Config:
        from_attributes = True

class DiscardBase(BaseModel):
    user_id: int
    material_type_id: int
    unique_code: str
    points_awarded: int
    
class DiscardCreate(DiscardBase):
    pass

class DiscardResponse(DiscardBase):
    id: int
    timestamp: datetime
    class Config:
        from_attributes = True