from pydantic import BaseModel, Field

class MaterialTypeBase(BaseModel):
    name: str = Field(..., max_length=255)
    points_per_unit: float = Field(..., gt=0)

class MaterialTypeCreate(MaterialTypeBase):
    pass

class MaterialTypeResponse(MaterialTypeBase):
    id: int

    class Config:
        from_attributes = True  