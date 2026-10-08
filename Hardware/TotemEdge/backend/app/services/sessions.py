import asyncio
from uuid import UUID

from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import CycleError, PRE_PHYSICAL, Session
from app.services.status import LocalStatusService
from app.storage import CycleStore


class SessionService:
    def __init__(
        self, store: CycleStore, central: SupabaseEdgeClient, status: LocalStatusService
    ):
        self.store = store
        self.central = central
        self.status = status
        self._lock = asyncio.Lock()

    async def require_available(self):
        if not (await self.status.check_status()).local.can_start_deposit:
            raise CycleError("TOTEM_UNAVAILABLE", 503)

    async def context(self):
        await self.require_available()
        return await self.central.context()

    async def start(self, command_id: UUID, mode: str, class_id: UUID) -> Session:
        async with self._lock:
            previous = self.store.by_command(command_id)
            if previous:
                if previous.mode != mode or previous.class_id != class_id:
                    raise CycleError("COMMAND_ID_CONFLICT")
                return previous
            if self.store.active():
                raise CycleError("SESSION_ALREADY_ACTIVE")
            await self.require_available()
            context = await self.central.context()
            selected = next((c for c in context.classes if c.id == class_id), None)
            if selected is None:
                raise CycleError("CLASS_NOT_IN_CONTEXT", 404)
            return self.store.create(
                command_id,
                mode,
                class_id,
                selected.name,
                central_scope=self.central.configuration_scope,
            )

    async def identify(self, event_id: UUID, student_id: UUID, pin: str) -> Session:
        async with self._lock:
            session = self.store.get(event_id)
            if session.state != "IDENTIFYING" or session.mode != "student":
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            await self.require_available()
            self.store.change(event_id, "IDENTIFYING", "AUTHENTICATING")
            try:
                confirmation = await self.central.verify_pin(
                    session.class_id, student_id, pin
                )
            except CentralError as error:
                self.store.change(
                    event_id, "AUTHENTICATING", "IDENTIFYING", code=error.code
                )
                raise
            return self.store.change(
                event_id,
                "AUTHENTICATING",
                "SAFETY",
                student_id=str(confirmation.student.id),
                student_name=confirmation.student.name,
            )

    def safety(self, event_id: UUID, has_risk: bool) -> Session:
        if has_risk:
            return self.store.change(
                event_id, "SAFETY", "CANCELLED", code="SAFETY_RISK", active_slot=None
            )
        # Apenas ponto futuro: não chama nem simula controller, LED ou abertura.
        return self.store.change(
            event_id, "SAFETY", "PHYSICAL_BLOCKED", code="PHYSICAL_INTEGRATION_REQUIRED"
        )

    def hand_removed(self, event_id: UUID):
        self.store.declare_hand_removed(event_id)
        raise CycleError("PHYSICAL_INTEGRATION_REQUIRED", 503)

    def cancel(self, event_id: UUID) -> Session:
        session = self.store.get(event_id)
        if session.state == "CANCELLED":
            return session
        if session.state not in PRE_PHYSICAL - {"AUTHENTICATING"}:
            raise CycleError("CANCELLATION_NOT_SAFE")
        return self.store.change(
            event_id,
            session.state,
            "CANCELLED",
            code="USER_CANCELLED",
            active_slot=None,
        )

    async def retry_registration(self, event_id: UUID) -> Session:
        async with self._lock:
            session = self.store.get(event_id)
            if session.state in {"REGISTERED", "COMPLETED"}:
                return session
            payload = self.store.claim_registration(
                event_id, self.central.configuration_scope
            )
            try:
                receipt = await self.central.register(payload)
            except CentralError as error:
                self.store.change(
                    event_id, "REGISTERING", "REGISTRATION_PENDING", code=error.code
                )
                raise
            return self.store.change(
                event_id, "REGISTERING", "REGISTERED", receipt=receipt.model_dump_json()
            )

    def finish(self, event_id: UUID) -> Session:
        session = self.store.get(event_id)
        if session.state == "COMPLETED":
            return session
        return self.store.change(event_id, "REGISTERED", "COMPLETED", active_slot=None)
