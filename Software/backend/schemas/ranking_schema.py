from pydantic import BaseModel, ConfigDict

class UserRanking(BaseModel):
    id: int
    username: str
    total_points: int

    model_config = ConfigDict(from_attributes=True)