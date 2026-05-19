from uuid import UUID

from pydantic import BaseModel


class StudentActivateRequest(BaseModel):
    school_id: UUID
    class_id: UUID
    student_id: UUID
    pin: str


class StudentLoginRequest(BaseModel):
    school_id: UUID
    class_id: UUID
    student_id: UUID
    pin: str


class AdminLoginRequest(BaseModel):
    email: str
    password: str


class AdminResetPinRequest(BaseModel):
    new_pin: str


class AuthTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
