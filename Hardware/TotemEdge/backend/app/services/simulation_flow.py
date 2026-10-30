"""Ações de desenvolvimento sobre a mesma sessão/journal; sem economia ou visão."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.central_contracts import TotemContext
from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import CycleError, MECHANICAL_STEPS, Session, SimulationIdentity
from app.mechanical import MechanicalCommand, Operation
from app.mechanical_journal import JournalEntry, JournalEvent
from app.services.mechanical import MechanicalService
from app.storage import CycleStore, now

SIMULATION_CLASS = UUID("00000000-0000-4000-8000-000000000010")


class SimulationSnapshot(BaseModel):
    source: Literal["SIMULATED"] = "SIMULATED"
    session: Session
    commands: list[JournalEntry]
    allowed_actions: list[str]
    identity: SimulationIdentity | None = None


class SimulationCommandSnapshot(BaseModel):
    source: Literal["SIMULATED"] = "SIMULATED"
    command: JournalEntry
    history: tuple[JournalEvent, ...]


class SimulationFlow:
    def __init__(
        self,
        store: CycleStore,
        mechanical: MechanicalService,
        *,
        central: SupabaseEdgeClient | None = None,
    ):
        if not store.simulation_enabled or mechanical.source != "SIMULATED":
            raise ValueError("Fluxo simulado exige runtime isolado.")
        self.store = store
        self.mechanical = mechanical
        self.central = central  # Injetado somente pela composição DEV.

    def _snapshot(self, conn, event_id) -> SimulationSnapshot:
        row = self.store.simulation_row(conn, event_id)
        entries = [
            self.store.mechanical._entry(command)
            for command in conn.execute(
                "SELECT * FROM mechanical_commands WHERE event_id=? ORDER BY created_at,mechanical_command_id",
                (str(event_id),),
            )
        ]
        names = dict(
            zip(MECHANICAL_STEPS, ("open", "close", "hatch", "confirm-initial"))
        )
        actions = [
            names[operation]
            for operation, (before, _, _) in MECHANICAL_STEPS.items()
            if before == row["state"]
            and (
                operation != "CONFIRM_INITIAL_STATE"
                or self.store._simulated_hatch_completed(conn, event_id)
            )
        ]
        if row["state"] == "SAFETY":
            actions = ["safety", "cancel"]
        elif row["state"] == "IDENTIFYING":
            actions = (
                ["identify", "cancel"] if self.store.identity_scope else ["cancel"]
            )
        elif row["state"] == "PHYSICAL_BLOCKED":
            actions.append("cancel")
        elif row["state"] == "DOOR_CLOSED":
            actions = ["review-fixture"]
        identity = self.store.simulation_identity(conn, event_id)
        if self.store.identity_scope and identity is None:
            actions = [
                a
                for a in actions
                if a in {"identify", "cancel", "close", "confirm-initial"}
            ]
        if any(
            entry.phase
            in {
                "INTENT",
                "DISPATCHING",
                "ACCEPTED",
                "FAILED",
                "TIMED_OUT",
                "CANCELLED",
                "INDETERMINATE",
            }
            for entry in entries
        ):
            actions = []
        return SimulationSnapshot(
            session=self.store._snapshot(row),
            commands=entries,
            allowed_actions=actions,
            identity=identity,
        )

    def get(self, event_id) -> SimulationSnapshot:
        with self.store.transaction() as conn:
            return self._snapshot(conn, event_id)

    def active(self) -> SimulationSnapshot | None:
        with self.store.transaction() as conn:
            row = conn.execute("SELECT * FROM cycles WHERE active_slot=1").fetchone()
            if row is None:
                return None
            if not row["simulated"]:
                raise CycleError("SIMULATION_LEGACY_SESSION_ACTIVE")
            return self._snapshot(conn, row["event_id"])

    def start(self, command_id: UUID) -> SimulationSnapshot:
        session = self.store.create(
            command_id,
            "student" if self.store.identity_scope else "class_only",
            SIMULATION_CLASS,
            "Identificação DEV pendente"
            if self.store.identity_scope
            else "Simulação isolada",
            simulated=True,
        )
        return self.get(session.event_id)

    def safety(self, event_id: UUID, has_risk: bool) -> SimulationSnapshot:
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event_id)
            if self.store.identity_scope:
                self.store.require_simulation_identity(conn, event_id)
            previous = conn.execute(
                "SELECT to_state FROM transitions WHERE event_id=? AND from_state='SAFETY' AND code IN ('SIMULATION_SAFETY_CLEARED','SAFETY_RISK')",
                (str(event_id),),
            ).fetchone()
            target = "CANCELLED" if has_risk else "PHYSICAL_BLOCKED"
            if previous:
                if previous["to_state"] != target:
                    raise CycleError("SAFETY_DECISION_CONFLICT")
            else:
                if row["state"] != "SAFETY":
                    raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                self.store._record(
                    conn,
                    row,
                    target,
                    code="SAFETY_RISK" if has_risk else "SIMULATION_SAFETY_CLEARED",
                    updates={"active_slot": None} if has_risk else None,
                )
            return self._snapshot(conn, event_id)

    def review_fixture(self, event_id: UUID) -> SimulationSnapshot:
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event_id)
            if self.store.identity_scope:
                self.store.require_simulation_identity(conn, event_id)
            previous = conn.execute(
                "SELECT 1 FROM transitions WHERE event_id=? AND code='SIMULATION_REVIEW_FIXTURE'",
                (str(event_id),),
            ).fetchone()
            if not previous:
                if row["state"] != "DOOR_CLOSED":
                    raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                # Checkpoint explicitamente fictício: nenhuma classificação,
                # categoria, auditoria de visão ou payload econômico é fabricado.
                self.store._record(
                    conn, row, "REVIEW", code="SIMULATION_REVIEW_FIXTURE"
                )
            return self._snapshot(conn, event_id)

    def cancel(self, event_id: UUID) -> SimulationSnapshot:
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event_id)
            if row["state"] == "CANCELLED":
                return self._snapshot(conn, event_id)
            if row["state"] not in {
                "IDENTIFYING",
                "SAFETY",
                "PHYSICAL_BLOCKED",
            } or self.store.mechanical.has_risk(conn, event_id):
                raise CycleError("CANCELLATION_NOT_SAFE")
            self.store.mechanical.abort_intents(conn, event_id)
            self.store._record(
                conn,
                row,
                "CANCELLED",
                code="USER_CANCELLED",
                updates={"active_slot": None},
            )
            return self._snapshot(conn, event_id)

    async def act(
        self,
        event_id: UUID,
        operation: Operation,
        identifier: UUID,
        timeout: float,
        *,
        hand_removed=False,
        pin: str | None = None,
    ):
        # A checagem definitiva de estado e a transição ocorrem na transação
        # de intenção do journal. Esta leitura apenas valida escopo/procedência.
        snapshot = self.get(event_id)
        try:
            if self.store.identity_scope and operation in {
                "OPEN_INSERTION_DOOR",
                "CYCLE_LOWER_HATCH",
            }:
                if snapshot.identity is None:
                    raise CycleError("DEV_IDENTITY_REQUIRED")
                if pin is None:
                    raise CycleError("DEV_ACTION_PIN_REQUIRED", 401)
                # event_id e o vínculo são públicos, não credenciais de atuação.
                # Também autentica POST repetido; recuperação offline usa GET.
                await self._available_context()
                await self.central.verify_pin(
                    snapshot.identity.class_id, snapshot.identity.student_id, pin
                )
            elif pin is not None:
                raise CycleError("INVALID_LOCAL_CONTRACT", 422)
        finally:
            pin = None
        entry = await self.mechanical.submit(
            MechanicalCommand(
                mechanical_command_id=identifier,
                event_id=event_id,
                operation=operation,
                timeout_seconds=timeout,
            ),
            hand_removed=hand_removed,
        )
        return entry, self.get(event_id)

    async def _available_context(self) -> TotemContext:
        if self.central is None:
            raise CycleError("DEV_IDENTITY_UNAVAILABLE", 503)
        health = await self.central.check_health()
        if not health.available:
            raise CentralError(
                "DEV_CENTRAL_" + health.outcome,
                401 if health.outcome == "AUTHENTICATION_FAILED" else 503,
            )
        return await self.central.context()

    async def identify(
        self, event_id: UUID, class_id: UUID, student_id: UUID, pin: str
    ) -> SimulationSnapshot:
        try:
            _, version = self.store.identity_attempt(event_id, class_id, student_id)
            # Todo POST representa uma tentativa real, mesmo com vínculo durável.
            # A idempotência pertence ao commit; GET recupera estado sem autenticar.
            context = await self._available_context()
            confirmation = await self.central.verify_pin(class_id, student_id, pin)
        finally:
            pin = ""  # Não reter PIN em atributos, tarefas ou histórico.
        identity = SimulationIdentity(
            event_id=event_id,
            project_ref=self.store.identity_scope[0],
            machine_id=context.machine.id,
            school_id=context.school.id,
            class_id=confirmation.student.class_id,
            student_id=confirmation.student.id,
            validated_at=now(),
        )
        self.store.bind_simulation_identity(identity, confirmation.student, version)
        return self.get(event_id)

    def command(self, event_id: UUID, identifier: UUID) -> SimulationCommandSnapshot:
        with self.store.transaction() as conn:
            self.store.simulation_row(conn, event_id)
            entry = self.store.mechanical._entry(
                self.store.mechanical._row(conn, identifier)
            )
            if entry.command.event_id != event_id:
                raise CycleError("MECHANICAL_COMMAND_NOT_FOUND", 404)
            history = tuple(
                JournalEvent(**dict(row))
                for row in conn.execute(
                    "SELECT version,phase,result,error_code,at FROM mechanical_history WHERE mechanical_command_id=? ORDER BY version",
                    (str(identifier),),
                )
            )
            return SimulationCommandSnapshot(command=entry, history=history)
