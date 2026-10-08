from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness do processo; não autoriza o início de um descarte."""
    return {"status": "ok"}
