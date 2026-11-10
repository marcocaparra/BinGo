import asyncio
from uuid import NAMESPACE_URL, UUID, uuid5

from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import PRE_PHYSICAL, CycleError, Session
from app.mechanical import ControllerError
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
        self.mechanical = None
        self.vision = None

    def physical_ready(self):
        if self.mechanical is None or self.mechanical.source != "PHYSICAL":
            raise CycleError("PHYSICAL_SUPERVISION_PENDING", 503)
        self.mechanical.controller.check_commissioning()
        if (
            self.vision is None
            or self.vision.capture.camera is None
            or self.vision.capture.vision.primary is None
        ):
            raise CycleError("VISION_NOT_INTEGRATED", 503)

    def snapshot(self, event_id):
        if self.mechanical is None:
            return self.store.get(event_id)
        with self.store.transaction() as conn:
            session = self.store._snapshot(self.store._row(conn, event_id))
            commands = [
                self.store.mechanical._entry(row).model_dump(mode="json")
                for row in conn.execute(
                    "SELECT * FROM mechanical_commands WHERE event_id=? ORDER BY created_at",
                    (str(event_id),),
                )
            ]
            vision = self.vision.snapshot(conn, event_id) if self.vision else None
        ready = True
        blocker = None
        try:
            self.physical_ready()
        except (CycleError, ControllerError) as error:
            ready, blocker = False, getattr(error, "code", "CONTROLLER_UNAVAILABLE")
        actions = []
        if ready and session.state == "INSERTION_READY":
            actions = ["hand-removed"]
        if (
            ready
            and session.state == "REVIEW"
            and vision
            and vision["phase"] == "COMPLETED"
        ):
            actions = ["hatch"] if vision["decision"] else ["vision-review"]
        return session.model_copy(
            update={
                "operational": {
                    "commands": commands,
                    "vision": vision,
                    "allowed_actions": actions,
                    "execution_ready": ready,
                    "blocker": blocker,
                    "audience": "attending-technicians-only",
                }
            }
        )

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
        if self.mechanical is not None:
            with self.store.transaction() as conn:
                row = self.store._row(conn, event_id)
                previous = conn.execute(
                    "SELECT code FROM transitions WHERE event_id=? AND from_state='SAFETY' AND code IN ('SAFETY_RISK','PHYSICAL_SAFETY_CLEARED')",
                    (str(event_id),),
                ).fetchone()
                code = "SAFETY_RISK" if has_risk else "PHYSICAL_SAFETY_CLEARED"
                if previous:
                    if previous[0] != code:
                        raise CycleError("SAFETY_DECISION_CONFLICT")
                else:
                    if row["state"] != "SAFETY":
                        raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                    if not has_risk:
                        self.physical_ready()
                    self.store._record(
                        conn,
                        row,
                        "CANCELLED" if has_risk else "INSERTION_READY",
                        code=code,
                        updates={"active_slot": None} if has_risk else None,
                    )
            return self.snapshot(event_id)
        if has_risk:
            return self.store.change(
                event_id, "SAFETY", "CANCELLED", code="SAFETY_RISK", active_slot=None
            )
        # Apenas ponto futuro: não chama nem simula controller, LED ou abertura.
        return self.store.change(
            event_id, "SAFETY", "PHYSICAL_BLOCKED", code="PHYSICAL_INTEGRATION_REQUIRED"
        )

    def hand_removed(self, event_id: UUID, declared=False):
        if self.mechanical is not None:
            if declared is not True:
                raise CycleError("HAND_REMOVAL_DECLARATION_REQUIRED", 422)
            identifier = uuid5(
                NAMESPACE_URL, f"bingo:physical:hand-declaration:v1:{event_id}"
            )
            created = False
            from app.storage import now

            with self.store.transaction() as conn:
                row = self.store._row(conn, event_id)
                previous = conn.execute(
                    "SELECT 1 FROM mechanical_commands WHERE mechanical_command_id=?",
                    (str(identifier),),
                ).fetchone()
                if not previous:
                    self.physical_ready()
                    if (
                        row["simulated"]
                        or row["state"] != "INSERTION_READY"
                        or row["active_slot"] != 1
                    ):
                        raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                    at = now()
                    # The official logical checkpoint is a USER declaration.
                    # No C command, sensor, PWM or mechanical confirmation.
                    conn.execute(
                        "INSERT INTO mechanical_commands VALUES(?,?, 'CONFIRM_HAND_REMOVED',30,'PHYSICAL','COMPLETED','SUCCEEDED',NULL,NULL,0,?,?)",
                        (str(identifier), str(event_id), at, at),
                    )
                    conn.execute(
                        "INSERT INTO mechanical_history VALUES(?,0,'COMPLETED','SUCCEEDED',NULL,?)",
                        (str(identifier), at),
                    )
                    self.store._record(
                        conn,
                        row,
                        "READY_TO_CAPTURE",
                        code="USER_HAND_REMOVAL_DECLARED",
                        updates={"hand_removed": 1},
                    )
                    created = True
            if created:
                # Durable reservation precedes camera I/O; HTTP cancellation does
                # not cancel the locally owned task. Replay never takes a photo.
                self.vision.tasks[str(identifier)] = asyncio.create_task(
                    self._capture(event_id, identifier)
                )
            return self.snapshot(event_id)
        self.store.declare_hand_removed(event_id)
        raise CycleError("PHYSICAL_INTEGRATION_REQUIRED", 503)

    async def _capture(self, event_id, identifier):
        try:
            await self.vision.analyze(event_id, identifier)
        except CycleError:
            pass  # Failure and intervention state are already durable.

    async def hatch(self, event_id):
        from app.mechanical import MechanicalCommand

        identifier = uuid5(NAMESPACE_URL, f"bingo:physical:joint-v1:{event_id}")
        # Recovery always consults the stable ID, even offline/after lease expiry.
        with self.store.transaction() as conn:
            previous = conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE mechanical_command_id=?",
                (str(identifier),),
            ).fetchone()
        if previous:
            return self.snapshot(event_id)
        await self.require_available()
        self.physical_ready()
        snapshot = self.snapshot(event_id)
        if (
            snapshot.state != "REVIEW"
            or "hatch" not in snapshot.operational["allowed_actions"]
        ):
            raise CycleError("VISION_REVIEW_REQUIRED")
        await self.mechanical.submit(
            MechanicalCommand(
                mechanical_command_id=identifier,
                event_id=event_id,
                operation="CYCLE_LOWER_HATCH",
                timeout_seconds=30,
            )
        )
        self.vision.frames.pop(str(event_id), None)
        return self.snapshot(event_id)

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

    async def register_completed(self, event_id: UUID) -> Session:
        # Chamado somente pelo orquestrador interno após confirmação durável.
        # O commit da fila precede qualquer I/O; não autoriza ou repete mecânica.
        self.store.queue_registration(event_id, self.central.configuration_scope)
        return await self.retry_registration(event_id)

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
            except (CentralError, asyncio.CancelledError) as error:
                self.store.change(
                    event_id,
                    "REGISTERING",
                    "REGISTRATION_PENDING",
                    code=error.code
                    if isinstance(error, CentralError)
                    else "REGISTRATION_RESULT_UNKNOWN",
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
