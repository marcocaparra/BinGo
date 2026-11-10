from typing import Literal

from pydantic import BaseModel, StrictBool, model_validator


class LocalStatus(BaseModel):
    """Central readiness plus local commissioning; never economic confirmation."""

    status: Literal["OFFLINE", "ONLINE"]
    can_start_deposit: StrictBool
    message: str | None

    @model_validator(mode="after")
    def consistent(self):
        if ((self.status == "ONLINE") != self.can_start_deposit
                or (self.message is None) != self.can_start_deposit):
            raise ValueError("Inconsistent local readiness")
        return self
