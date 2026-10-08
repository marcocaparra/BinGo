from typing import Literal

from pydantic import BaseModel


class LocalStatus(BaseModel):
    """Recorte seguro do contrato V1; ONLINE ainda não está implementado."""

    status: Literal["OFFLINE"]
    can_start_deposit: Literal[False]
    message: str
