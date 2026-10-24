from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response

from app.models import LocalStatus
from app.services.status import LocalStatusService

router = APIRouter(prefix="/local")


def get_status_service(request: Request) -> LocalStatusService:
    return request.app.state.status_service


@router.get("/status", response_model=LocalStatus)
async def local_status(
    response: Response,
    service: Annotated[LocalStatusService, Depends(get_status_service)],
) -> LocalStatus:
    """Estado operacional local, bloqueado até existir verificação real."""
    response.headers["Cache-Control"] = "no-store"
    snapshot = await service.check_status()
    return snapshot.local
