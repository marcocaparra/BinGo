"""Journal local: identidade imutável, reserva única e histórico transacional."""

from datetime import datetime, timezone
import sqlite3
from typing import Literal, TYPE_CHECKING
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.mechanical import (
    ControllerError,
    MechanicalCommand,
    MechanicalResponse,
    Result,
    Source,
)

if TYPE_CHECKING:
    from app.storage import CycleStore

JournalPhase = Literal[
    "INTENT",
    "DISPATCHING",
    "ACCEPTED",
    "COMPLETED",
    "REJECTED",
    "FAILED",
    "TIMED_OUT",
    "CANCELLED",
    "INDETERMINATE",
    "ABORTED",
]
UNRESOLVED = {
    "INTENT",
    "DISPATCHING",
    "ACCEPTED",
    "FAILED",
    "TIMED_OUT",
    "CANCELLED",
    "INDETERMINATE",
}
RESPONSE_PHASES = {
    "ACCEPTED",
    "COMPLETED",
    "REJECTED",
    "FAILED",
    "TIMED_OUT",
    "CANCELLED",
}


class JournalEntry(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    command: MechanicalCommand
    source: Source
    phase: JournalPhase
    result: Result
    error_code: str | None
    version: int
    created_at: str
    updated_at: str


class JournalEvent(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    version: int
    phase: JournalPhase
    result: Result
    error_code: str | None
    at: str


SCHEMA = (
    """CREATE TABLE mechanical_commands (
        mechanical_command_id TEXT PRIMARY KEY NOT NULL,
        event_id TEXT NOT NULL REFERENCES cycles(event_id),
        operation TEXT NOT NULL CHECK(operation IN ('OPEN_INSERTION_DOOR','CLOSE_INSERTION_DOOR','CYCLE_LOWER_HATCH','CONFIRM_INITIAL_STATE')),
        timeout_seconds REAL NOT NULL CHECK(timeout_seconds > 0),
        source TEXT NOT NULL CHECK(source IN ('UNAVAILABLE','SIMULATED','PHYSICAL')),
        phase TEXT NOT NULL CHECK(phase IN ('INTENT','DISPATCHING','ACCEPTED','COMPLETED','REJECTED','FAILED','TIMED_OUT','CANCELLED','INDETERMINATE','ABORTED')),
        result TEXT NOT NULL CHECK(result IN ('PENDING','SUCCEEDED','FAILURE','UNAVAILABLE','UNKNOWN')),
        error_code TEXT,
        active_slot INTEGER UNIQUE CHECK(active_slot IS NULL OR active_slot=1),
        version INTEGER NOT NULL CHECK(version >= 0),
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        CHECK((phase IN ('INTENT','DISPATCHING','ACCEPTED','FAILED','TIMED_OUT','CANCELLED','INDETERMINATE') AND active_slot IS 1)
           OR (phase IN ('COMPLETED','REJECTED','ABORTED') AND active_slot IS NULL))
    )""",
    "CREATE INDEX mechanical_by_event ON mechanical_commands(event_id)",
    """CREATE TABLE mechanical_history (
        mechanical_command_id TEXT NOT NULL REFERENCES mechanical_commands(mechanical_command_id),
        version INTEGER NOT NULL CHECK(version >= 0),
        phase TEXT NOT NULL, result TEXT NOT NULL, error_code TEXT, at TEXT NOT NULL,
        PRIMARY KEY(mechanical_command_id,version)
    )""",
    """CREATE TRIGGER mechanical_identity_immutable
        BEFORE UPDATE OF mechanical_command_id,event_id,operation,timeout_seconds,source,created_at
        ON mechanical_commands BEGIN SELECT RAISE(ABORT,'Immutable mechanical identity'); END""",
    """CREATE TRIGGER mechanical_history_no_update BEFORE UPDATE ON mechanical_history
        BEGIN SELECT RAISE(ABORT,'Append-only mechanical history'); END""",
    """CREATE TRIGGER mechanical_history_no_delete BEFORE DELETE ON mechanical_history
        BEGIN SELECT RAISE(ABORT,'Append-only mechanical history'); END""",
)


class MechanicalJournal:
    def __init__(self, store: "CycleStore"):
        self.store = store

    @staticmethod
    def _row(conn, identifier):
        row = conn.execute(
            "SELECT * FROM mechanical_commands WHERE mechanical_command_id=?",
            (str(identifier),),
        ).fetchone()
        if row is None:
            raise ControllerError("MECHANICAL_COMMAND_NOT_FOUND")
        return row

    @staticmethod
    def _entry(row) -> JournalEntry:
        return JournalEntry(
            command=MechanicalCommand(
                mechanical_command_id=UUID(row["mechanical_command_id"]),
                event_id=UUID(row["event_id"]),
                operation=row["operation"],
                timeout_seconds=row["timeout_seconds"],
            ),
            **{
                key: row[key]
                for key in (
                    "source",
                    "phase",
                    "result",
                    "error_code",
                    "version",
                    "created_at",
                    "updated_at",
                )
            },
        )

    @staticmethod
    def validate_schema(conn):
        required = {
            "mechanical_commands": {
                "mechanical_command_id",
                "event_id",
                "operation",
                "timeout_seconds",
                "source",
                "phase",
                "result",
                "error_code",
                "active_slot",
                "version",
                "created_at",
                "updated_at",
            },
            "mechanical_history": {
                "mechanical_command_id",
                "version",
                "phase",
                "result",
                "error_code",
                "at",
            },
        }
        for table, columns in required.items():
            actual = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
            if actual != columns:
                raise RuntimeError("Journal mecânico incompatível; operação bloqueada.")
        objects = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('trigger','index')"
            )
        }
        if (
            not {
                "mechanical_by_event",
                "mechanical_identity_immutable",
                "mechanical_history_no_update",
                "mechanical_history_no_delete",
            }
            <= objects
        ):
            raise RuntimeError("Proteções do journal mecânico ausentes.")
        for row in conn.execute("SELECT * FROM mechanical_commands"):
            entry = MechanicalJournal._entry(row)
            history = conn.execute(
                "SELECT * FROM mechanical_history WHERE mechanical_command_id=? ORDER BY version",
                (row["mechanical_command_id"],),
            ).fetchall()
            if len(history) != entry.version + 1 or [
                h["version"] for h in history
            ] != list(range(entry.version + 1)):
                raise RuntimeError("Histórico mecânico incompleto; operação bloqueada.")
            last = history[-1]
            if (
                any(last[key] != row[key] for key in ("phase", "result", "error_code"))
                or last["at"] != row["updated_at"]
            ):
                raise RuntimeError("Histórico mecânico divergente; operação bloqueada.")
            if entry.phase in RESPONSE_PHASES:
                MechanicalResponse(
                    command=entry.command,
                    source=entry.source,
                    state=entry.phase,
                    result=entry.result,
                    error_code=entry.error_code,
                )
            elif entry.result != (
                "UNKNOWN"
                if entry.phase == "INDETERMINATE"
                else "UNAVAILABLE"
                if entry.phase == "ABORTED"
                else "PENDING"
            ):
                raise RuntimeError(
                    "Resultado mecânico inconsistente; operação bloqueada."
                )

    def get(self, identifier: UUID) -> JournalEntry:
        with self.store.transaction() as conn:
            return self._entry(self._row(conn, identifier))

    def history(self, identifier: UUID) -> tuple[JournalEvent, ...]:
        with self.store.transaction() as conn:
            self._row(conn, identifier)
            rows = conn.execute(
                "SELECT version,phase,result,error_code,at FROM mechanical_history WHERE mechanical_command_id=? ORDER BY version",
                (str(identifier),),
            ).fetchall()
            return tuple(JournalEvent(**dict(row)) for row in rows)

    def request(
        self, command: MechanicalCommand, *, source: Source
    ) -> tuple[JournalEntry, bool]:
        command = MechanicalCommand.model_validate(command.model_dump())
        if source not in {"UNAVAILABLE", "SIMULATED", "PHYSICAL"}:
            raise ValueError("Origem mecânica inválida.")
        with self.store.transaction() as conn:
            previous = conn.execute(
                "SELECT * FROM mechanical_commands WHERE mechanical_command_id=?",
                (str(command.mechanical_command_id),),
            ).fetchone()
            if previous is not None:
                entry = self._entry(previous)
                if entry.command != command:
                    raise ControllerError("MECHANICAL_COMMAND_ID_CONFLICT")
                return entry, False
            cycle = self.store._row(conn, command.event_id)
            if (
                cycle["active_slot"] != 1
                or cycle["state"] != "PHYSICAL_BLOCKED"
                or cycle["physical_confirmed"]
            ):
                raise ControllerError("MECHANICAL_CYCLE_NOT_BLOCKED")
            if conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE active_slot=1"
            ).fetchone():
                raise ControllerError("MECHANICAL_OPERATION_IN_PROGRESS")
            at = datetime.now(timezone.utc).isoformat()
            conn.execute(
                "INSERT INTO mechanical_commands VALUES(?,?,?,?,?,?,'PENDING',NULL,1,0,?,?)",
                (
                    str(command.mechanical_command_id),
                    str(command.event_id),
                    command.operation,
                    command.timeout_seconds,
                    source,
                    "INTENT",
                    at,
                    at,
                ),
            )
            conn.execute(
                "INSERT INTO mechanical_history VALUES(?,0,'INTENT','PENDING',NULL,?)",
                (str(command.mechanical_command_id), at),
            )
            return self._entry(self._row(conn, command.mechanical_command_id)), True

    def _transition(self, conn, row, phase, result, code) -> JournalEntry:
        at = datetime.now(timezone.utc).isoformat()
        version = row["version"] + 1
        cursor = conn.execute(
            "UPDATE mechanical_commands SET phase=?,result=?,error_code=?,active_slot=?,version=?,updated_at=? WHERE mechanical_command_id=? AND phase=? AND version=?",
            (
                phase,
                result,
                code,
                1 if phase in UNRESOLVED else None,
                version,
                at,
                row["mechanical_command_id"],
                row["phase"],
                row["version"],
            ),
        )
        if cursor.rowcount != 1:
            raise ControllerError("MECHANICAL_CONCURRENT_UPDATE")
        conn.execute(
            "INSERT INTO mechanical_history VALUES(?,?,?,?,?,?)",
            (row["mechanical_command_id"], version, phase, result, code, at),
        )
        return self._entry(self._row(conn, row["mechanical_command_id"]))

    def claim(self, identifier: UUID, *, version: int) -> JournalEntry:
        with self.store.transaction() as conn:
            row = self._row(conn, identifier)
            if row["phase"] != "INTENT" or row["version"] != version:
                raise ControllerError("MECHANICAL_STALE_STATE")
            cycle = self.store._row(conn, row["event_id"])
            if cycle["active_slot"] != 1 or cycle["state"] != "PHYSICAL_BLOCKED":
                raise ControllerError("MECHANICAL_CYCLE_NOT_BLOCKED")
            return self._transition(conn, row, "DISPATCHING", "PENDING", None)

    def observe(
        self, identifier: UUID, response: MechanicalResponse, *, version: int
    ) -> JournalEntry:
        response = MechanicalResponse.model_validate(response.model_dump())
        with self.store.transaction() as conn:
            row = self._row(conn, identifier)
            entry = self._entry(row)
            if response.command != entry.command or response.source != entry.source:
                raise ControllerError("MECHANICAL_RESPONSE_MISMATCH")
            # Replay exato não cria versão/histórico, inclusive após conclusão.
            if (entry.phase, entry.result, entry.error_code) == (
                response.state,
                response.result,
                response.error_code,
            ):
                return entry
            allowed = {
                "DISPATCHING": {"ACCEPTED", "REJECTED"},
                "ACCEPTED": {"COMPLETED", "FAILED", "TIMED_OUT", "CANCELLED"},
            }
            if entry.version != version or response.state not in allowed.get(
                entry.phase, set()
            ):
                raise ControllerError("MECHANICAL_STALE_RESPONSE")
            entry = self._transition(
                conn, row, response.state, response.result, response.error_code
            )
            if (
                entry.phase in {"FAILED", "TIMED_OUT", "CANCELLED"}
                or entry.source == "PHYSICAL"
                and entry.phase == "COMPLETED"
            ):
                self._block_cycle(conn, entry.command.event_id)
            return entry

    def unknown(self, identifier: UUID, *, version: int, code: str) -> JournalEntry:
        with self.store.transaction() as conn:
            row = self._row(conn, identifier)
            if row["phase"] == "INDETERMINATE":
                return self._entry(row)
            if row["version"] != version or row["phase"] not in {
                "DISPATCHING",
                "ACCEPTED",
            }:
                raise ControllerError("MECHANICAL_STALE_STATE")
            entry = self._transition(conn, row, "INDETERMINATE", "UNKNOWN", code)
            self._block_cycle(conn, entry.command.event_id)
            return entry

    def _block_cycle(self, conn, event_id):
        cycle = self.store._row(conn, event_id)
        if cycle["state"] != "INDETERMINATE":
            self.store._record(
                conn,
                cycle,
                "INDETERMINATE",
                code="MECHANICAL_RESULT_UNKNOWN",
                updates={"active_slot": 1},
            )

    @staticmethod
    def has_risk(conn, event_id) -> bool:
        return (
            conn.execute(
                """SELECT 1 FROM mechanical_commands WHERE event_id=? AND
               (phase IN ('DISPATCHING','ACCEPTED','FAILED','TIMED_OUT','CANCELLED','INDETERMINATE')
                OR (source='PHYSICAL' AND phase='COMPLETED')) LIMIT 1""",
                (str(event_id),),
            ).fetchone()
            is not None
        )

    @staticmethod
    def has_simulated_completion(conn, event_id) -> bool:
        return (
            conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE event_id=? AND source='SIMULATED' AND phase='COMPLETED' LIMIT 1",
                (str(event_id),),
            ).fetchone()
            is not None
        )

    def recover(self, conn):
        rows = conn.execute(
            "SELECT * FROM mechanical_commands WHERE phase IN ('INTENT','DISPATCHING','ACCEPTED')"
        ).fetchall()
        for row in rows:
            if row["phase"] == "INTENT":
                self._transition(
                    conn, row, "ABORTED", "UNAVAILABLE", "RESTART_BEFORE_DISPATCH"
                )
            else:
                self._transition(
                    conn,
                    row,
                    "INDETERMINATE",
                    "UNKNOWN",
                    "RESTART_DURING_MECHANICAL_COMMAND",
                )

    def abort_intents(self, conn, event_id):
        rows = conn.execute(
            "SELECT * FROM mechanical_commands WHERE event_id=? AND phase='INTENT'",
            (str(event_id),),
        ).fetchall()
        for row in rows:
            self._transition(
                conn, row, "ABORTED", "UNAVAILABLE", "CYCLE_CANCELLED_BEFORE_DISPATCH"
            )
