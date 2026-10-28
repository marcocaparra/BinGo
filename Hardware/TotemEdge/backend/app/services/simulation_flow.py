"""Ações de desenvolvimento sobre a mesma sessão/journal; sem economia ou visão."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.cycles import CycleError, MECHANICAL_STEPS, Session
from app.mechanical import MechanicalCommand, Operation
from app.mechanical_journal import JournalEntry, JournalEvent
from app.services.mechanical import MechanicalService
from app.storage import CycleStore

SIMULATION_CLASS = UUID("00000000-0000-4000-8000-000000000010")


class SimulationSnapshot(BaseModel):
    source: Literal["SIMULATED"] = "SIMULATED"
    session: Session
    commands: list[JournalEntry]
    allowed_actions: list[str]


class SimulationCommandSnapshot(BaseModel):
    source: Literal["SIMULATED"] = "SIMULATED"
    command: JournalEntry
    history: tuple[JournalEvent, ...]


class SimulationFlow:
    def __init__(self, store: CycleStore, mechanical: MechanicalService):
        if not store.simulation_enabled or mechanical.source != "SIMULATED":
            raise ValueError("Fluxo simulado exige runtime isolado.")
        self.store = store
        self.mechanical = mechanical

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
        elif row["state"] == "PHYSICAL_BLOCKED":
            actions.append("cancel")
        elif row["state"] == "DOOR_CLOSED":
            actions = ["review-fixture"]
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
            session=self.store._snapshot(row), commands=entries, allowed_actions=actions
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
            "class_only",
            SIMULATION_CLASS,
            "Simulação isolada",
            simulated=True,
        )
        return self.get(session.event_id)

    def safety(self, event_id: UUID, has_risk: bool) -> SimulationSnapshot:
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event_id)
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
    ):
        # A checagem definitiva de estado e a transição ocorrem na transação
        # de intenção do journal. Esta leitura apenas valida escopo/procedência.
        self.get(event_id)
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
