import inspect
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
        self.operational_readiness = None

    async def check_status(self) -> StatusSnapshot:
        central = await self._central_backend.check_health()
        ready = False
        if central.available and self.operational_readiness is not None:
            try:
                result = self.operational_readiness()
                ready = (
                    await result if inspect.isawaitable(result) else result
                ) is True
            except Exception:  # noqa: BLE001 -- readiness must fail closed
                ready = False
        # Readiness central isolada não comprova controller, câmera ou visão.
        # Não armazenar nem reutilizar este snapshot para autorizar operações.
        return StatusSnapshot(
            central_backend=central,
            local=LocalStatus(
                status="ONLINE" if ready else "OFFLINE",
                can_start_deposit=ready,
                message=(
                    None
                    if ready
                    else "Totem temporariamente indisponível. Aguardando prontidão local e comissionamento presencial."
                    if central.available and self.operational_readiness is not None
                    else "Totem temporariamente indisponível. "
                    "Estamos sem conexão no momento."
                ),
            ),
        )
