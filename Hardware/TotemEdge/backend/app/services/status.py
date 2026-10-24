from dataclasses import dataclass

from app.clients.supabase import CentralReadiness, SupabaseEdgeClient
from app.models import LocalStatus


@dataclass(frozen=True)
class StatusSnapshot:
    central_backend: CentralReadiness
    local: LocalStatus


class LocalStatusService:
    def __init__(self, central_backend: SupabaseEdgeClient):
        self._central_backend = central_backend

    async def check_status(self) -> StatusSnapshot:
        central = await self._central_backend.check_health()
        # Readiness central isolada não comprova controller, câmera ou visão.
        # Não armazenar nem reutilizar este snapshot para autorizar operações.
        return StatusSnapshot(
            central_backend=central,
            local=LocalStatus(
                status="OFFLINE",
                can_start_deposit=False,
                message=(
                    "Totem temporariamente indisponível. "
                    "Estamos sem conexão no momento."
                ),
            ),
        )
