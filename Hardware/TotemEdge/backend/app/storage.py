"""SQLite local: transações curtas, slot único e journal sem dados secretos."""

from contextlib import contextmanager
from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3
from uuid import UUID, uuid4

from app.central_contracts import DepositPayload, DepositReceipt
from app.cycles import CycleError, PRE_PHYSICAL, Session, TRANSITIONS


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class CycleStore:
    def __init__(self, path: Path):
        self.path = path.resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Uma instância por arquivo: startup não reconcilia operação de outro worker.
        self._lease = self.path.with_suffix(self.path.suffix + ".lock").open("a+b")
        try:
            if os.name == "nt":
                import msvcrt

                if self._lease.tell() == 0:
                    self._lease.write(b"\0")
                    self._lease.flush()
                self._lease.seek(0)
                msvcrt.locking(self._lease.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(self._lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self._initialize()
            self._recover()
        except BaseException:
            self._lease.close()
            raise

    def close(self):
        self._lease.close()  # O SO libera a trava mesmo após encerramento abrupto.

    @contextmanager
    def transaction(self):
        connection = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        try:
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self):
        with sqlite3.connect(self.path) as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            version = conn.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1):
                raise RuntimeError("Versão SQLite local não suportada.")
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS cycles (
                    event_id TEXT PRIMARY KEY, command_id TEXT NOT NULL UNIQUE,
                    state TEXT NOT NULL, mode TEXT NOT NULL,
                    class_id TEXT NOT NULL, student_id TEXT,
                    class_name TEXT NOT NULL, student_name TEXT,
                    hand_removed INTEGER NOT NULL DEFAULT 0 CHECK(hand_removed IN (0,1)),
                    physical_confirmed INTEGER NOT NULL DEFAULT 0 CHECK(physical_confirmed IN (0,1)),
                    payload TEXT, receipt TEXT, failure_code TEXT, central_scope TEXT,
                    vision_result TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    version INTEGER NOT NULL DEFAULT 0,
                    active_slot INTEGER UNIQUE CHECK(active_slot IS NULL OR active_slot=1)
                );
                CREATE TABLE IF NOT EXISTS transitions (
                    id INTEGER PRIMARY KEY, event_id TEXT NOT NULL REFERENCES cycles(event_id),
                    from_state TEXT, to_state TEXT NOT NULL,
                    code TEXT, at TEXT NOT NULL
                );
                PRAGMA user_version=1;
            """)
            required = {
                "event_id",
                "command_id",
                "state",
                "mode",
                "class_id",
                "student_id",
                "class_name",
                "student_name",
                "hand_removed",
                "physical_confirmed",
                "payload",
                "receipt",
                "failure_code",
                "central_scope",
                "vision_result",
                "created_at",
                "updated_at",
                "version",
                "active_slot",
            }
            columns = {
                column[1] for column in conn.execute("PRAGMA table_info(cycles)")
            }
            if (
                not required <= columns
                or conn.execute("PRAGMA quick_check").fetchone()[0] != "ok"
            ):
                raise RuntimeError(
                    "SQLite local incompatível ou corrompido; operação bloqueada."
                )

    @staticmethod
    def _record(conn, row, state, *, code=None, updates=None):
        values = {
            "state": state,
            "updated_at": now(),
            "failure_code": code,
            **(updates or {}),
        }
        assignments = ",".join(f"{key}=?" for key in values)
        conn.execute(
            f"UPDATE cycles SET {assignments},version=version+1 WHERE event_id=? AND version=?",
            [*values.values(), row["event_id"], row["version"]],
        )
        conn.execute(
            "INSERT INTO transitions(event_id,from_state,to_state,code,at) VALUES(?,?,?,?,?)",
            (row["event_id"], row["state"], state, code, values["updated_at"]),
        )

    def _recover(self):
        with self.transaction() as conn:
            rows = conn.execute("SELECT * FROM cycles WHERE active_slot=1").fetchall()
            for row in rows:
                state = row["state"]
                if state in PRE_PHYSICAL:
                    self._record(
                        conn,
                        row,
                        "CANCELLED",
                        code="RESTART_BEFORE_PHYSICAL",
                        updates={"active_slot": None},
                    )
                elif state in {"REGISTERING", "REGISTRATION_PENDING"}:
                    if self._ready_payload(row) is None:
                        self._record(
                            conn, row, "INDETERMINATE", code="MISSING_PHYSICAL_EVIDENCE"
                        )
                    elif state == "REGISTERING":
                        self._record(
                            conn,
                            row,
                            "REGISTRATION_PENDING",
                            code="REGISTRATION_RESULT_UNKNOWN",
                        )
                elif state == "REGISTERED":
                    try:
                        if self._ready_payload(row) is None:
                            raise ValueError()
                        receipt = DepositReceipt.model_validate_json(
                            row["receipt"] or "null"
                        )
                        if str(receipt.event_id) != row["event_id"]:
                            raise ValueError()
                    except ValueError:
                        self._record(
                            conn, row, "INDETERMINATE", code="INVALID_STORED_RECEIPT"
                        )
                elif state != "INDETERMINATE":
                    # Inclui reinício no meio da escotilha: comando não comprova queda.
                    self._record(
                        conn,
                        row,
                        "INDETERMINATE",
                        code="PHYSICAL_STATE_UNKNOWN_AFTER_RESTART",
                    )

    @staticmethod
    def _ready_payload(row) -> DepositPayload | None:
        if row["physical_confirmed"] != 1 or row["payload"] is None:
            return None
        try:
            payload = DepositPayload.model_validate_json(row["payload"])
            if (
                str(payload.event_id) != row["event_id"]
                or str(payload.class_id) != row["class_id"]
                or (str(payload.student_id) if payload.student_id else None)
                != row["student_id"]
                or not payload.is_valid
            ):
                return None
            return payload
        except ValueError:
            return None

    def _row(self, conn, event_id):
        row = conn.execute(
            "SELECT * FROM cycles WHERE event_id=?", (str(event_id),)
        ).fetchone()
        if row is None:
            raise CycleError("SESSION_NOT_FOUND", 404)
        return row

    @staticmethod
    def _snapshot(row) -> Session:
        receipt = (
            DepositReceipt.model_validate_json(row["receipt"])
            if row["receipt"] and row["state"] in {"REGISTERED", "COMPLETED"}
            else None
        )
        if receipt is not None:
            payload = CycleStore._ready_payload(row)
            if (
                payload is None
                or receipt.event_id != payload.event_id
                or receipt.waste_category_code != payload.waste_category_code
                or receipt.category_source != payload.category_source
            ):
                raise CycleError("INVALID_STORED_RECEIPT", 503)
        return Session.model_validate(
            {**dict(row), "hand_removed": bool(row["hand_removed"]), "receipt": receipt}
        )

    def get(self, event_id: UUID) -> Session:
        with self.transaction() as conn:
            return self._snapshot(self._row(conn, event_id))

    def active(self) -> Session | None:
        with self.transaction() as conn:
            row = conn.execute("SELECT * FROM cycles WHERE active_slot=1").fetchone()
            return self._snapshot(row) if row else None

    def by_command(self, command_id: UUID) -> Session | None:
        with self.transaction() as conn:
            row = conn.execute(
                "SELECT * FROM cycles WHERE command_id=?", (str(command_id),)
            ).fetchone()
            return self._snapshot(row) if row else None

    def create(
        self,
        command_id: UUID,
        mode: str,
        class_id: UUID,
        class_name: str,
        *,
        central_scope: str | None = None,
    ) -> Session:
        with self.transaction() as conn:
            existing = conn.execute(
                "SELECT * FROM cycles WHERE command_id=?", (str(command_id),)
            ).fetchone()
            if existing:
                if existing["mode"] != mode or existing["class_id"] != str(class_id):
                    raise CycleError("COMMAND_ID_CONFLICT")
                return self._snapshot(existing)
            if conn.execute("SELECT 1 FROM cycles WHERE active_slot=1").fetchone():
                raise CycleError("SESSION_ALREADY_ACTIVE")
            event_id = str(uuid4())
            state = "IDENTIFYING" if mode == "student" else "SAFETY"
            timestamp = now()
            conn.execute(
                "INSERT INTO cycles(event_id,command_id,state,mode,class_id,class_name,created_at,updated_at,active_slot,central_scope) VALUES(?,?,?,?,?,?,?,?,1,?)",
                (
                    event_id,
                    str(command_id),
                    state,
                    mode,
                    str(class_id),
                    class_name,
                    timestamp,
                    timestamp,
                    central_scope,
                ),
            )
            conn.execute(
                "INSERT INTO transitions(event_id,to_state,at) VALUES(?,?,?)",
                (event_id, state, timestamp),
            )
            return self._snapshot(self._row(conn, event_id))

    def change(
        self, event_id: UUID, expected: str, state: str, *, code=None, **updates
    ) -> Session:
        allowed_fields = {
            "student_id",
            "student_name",
            "hand_removed",
            "receipt",
            "active_slot",
            "vision_result",
        }
        if not set(updates) <= allowed_fields:
            raise ValueError("Atualização local não permitida")
        if state not in TRANSITIONS.get(expected, set()):
            raise CycleError("INVALID_TRANSITION")
        with self.transaction() as conn:
            row = self._row(conn, event_id)
            if row["state"] != expected:
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            self._record(conn, row, state, code=code, updates=updates)
            return self._snapshot(self._row(conn, event_id))

    def declare_hand_removed(self, event_id: UUID):
        with self.transaction() as conn:
            row = self._row(conn, event_id)
            if row["state"] != "DOOR_OPEN" or row["hand_removed"]:
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            self._record(
                conn,
                row,
                "DOOR_OPEN",
                code="PHYSICAL_INTEGRATION_REQUIRED",
                updates={"hand_removed": 1},
            )

    def claim_registration(
        self, event_id: UUID, central_scope: str | None
    ) -> DepositPayload:
        with self.transaction() as conn:
            row = self._row(conn, event_id)
            if row["state"] != "REGISTRATION_PENDING":
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            if central_scope is None or row["central_scope"] != central_scope:
                raise CycleError("CENTRAL_SCOPE_NOT_CONFIRMED", 503)
            payload = self._ready_payload(row)
            if payload is None:
                raise CycleError("MISSING_PHYSICAL_EVIDENCE", 503)
            self._record(conn, row, "REGISTERING")
            return payload

    def prepare_payload(self, event_id: UUID, payload: DepositPayload):
        # Fundação para o futuro orquestrador: só congela contrato, não move equipamento.
        with self.transaction() as conn:
            row = self._row(conn, event_id)
            if (
                row["state"] != "REVIEW"
                or str(payload.event_id) != row["event_id"]
                or str(payload.class_id) != row["class_id"]
                or (str(payload.student_id) if payload.student_id else None)
                != row["student_id"]
                or not payload.is_valid
            ):
                raise CycleError("INVALID_TRANSITION")
            serialized = payload.model_dump_json()
            if row["payload"] is not None and row["payload"] != serialized:
                raise CycleError("EVENT_ID_CONFLICT")
            conn.execute(
                "UPDATE cycles SET payload=?,updated_at=? WHERE event_id=?",
                (serialized, now(), str(event_id)),
            )
            conn.execute(
                "INSERT INTO transitions(event_id,from_state,to_state,code,at) VALUES(?,?,?,?,?)",
                (str(event_id), "REVIEW", "REVIEW", "PAYLOAD_PERSISTED", now()),
            )
