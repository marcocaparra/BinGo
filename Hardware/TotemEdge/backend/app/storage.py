"""SQLite local: transações curtas, slot único e journal sem dados secretos."""

from contextlib import closing, contextmanager
from datetime import datetime, timezone
import os
from pathlib import Path
import sqlite3
from uuid import UUID, uuid4

from app.central_contracts import ConfirmedStudent, DepositPayload, DepositReceipt
from app.cycles import (
    CycleError,
    MECHANICAL_STEPS,
    PRE_PHYSICAL,
    Session,
    SimulationIdentity,
    SIMULATION_EDGES,
    TRANSITIONS,
)
from app.mechanical_journal import MechanicalJournal, SCHEMA as MECHANICAL_SCHEMA


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class CycleStore:
    def __init__(
        self,
        path: Path,
        *,
        simulation_enabled: bool = False,
        identity_scope: tuple[str, UUID, UUID] | None = None,
    ):
        if identity_scope is not None and not simulation_enabled:
            raise ValueError("Identidade DEV exige simulação.")
        self.identity_scope = identity_scope
        self.simulation_enabled = simulation_enabled
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
            self.mechanical = MechanicalJournal(self)
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
        with closing(sqlite3.connect(self.path, isolation_level=None)) as setup:
            setup.execute("PRAGMA journal_mode=WAL")
        with self.transaction() as conn:
            version = conn.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1, 2, 3, 4):
                raise RuntimeError("Versão SQLite local não suportada.")
            if version == 0:
                conn.execute("""CREATE TABLE IF NOT EXISTS cycles (
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
                )""")
                conn.execute("""CREATE TABLE IF NOT EXISTS transitions (
                    id INTEGER PRIMARY KEY, event_id TEXT NOT NULL REFERENCES cycles(event_id),
                    from_state TEXT, to_state TEXT NOT NULL,
                    code TEXT, at TEXT NOT NULL
                )""")
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
                or not {"id", "event_id", "from_state", "to_state", "code", "at"}
                <= {row[1] for row in conn.execute("PRAGMA table_info(transitions)")}
            ):
                raise RuntimeError(
                    "SQLite local incompatível ou corrompido; operação bloqueada."
                )
            if version < 2:
                for statement in MECHANICAL_SCHEMA:
                    conn.execute(statement)
            if version < 3 and "simulated" not in columns:
                conn.execute(
                    "ALTER TABLE cycles ADD COLUMN simulated INTEGER NOT NULL DEFAULT 0 CHECK(simulated IN (0,1))"
                )
            if version < 3:
                conn.execute(
                    "CREATE TRIGGER IF NOT EXISTS cycle_simulation_source_immutable BEFORE UPDATE OF simulated ON cycles BEGIN SELECT RAISE(ABORT,'Immutable session provenance'); END"
                )
            if "simulated" not in {
                row[1] for row in conn.execute("PRAGMA table_info(cycles)")
            }:
                raise RuntimeError("Procedência de sessão ausente; operação bloqueada.")
            if not conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='cycle_simulation_source_immutable'"
            ).fetchone():
                raise RuntimeError(
                    "Proteção de procedência ausente; operação bloqueada."
                )
            if (
                not self.simulation_enabled
                and conn.execute(
                    "SELECT 1 FROM cycles WHERE simulated=1 LIMIT 1"
                ).fetchone()
            ):
                raise RuntimeError(
                    "Sessões simuladas não pertencem ao runtime operacional."
                )
            self.mechanical.validate_schema(conn)
            if version < 4:
                conn.execute("""CREATE TABLE simulation_identities (
                    event_id TEXT PRIMARY KEY NOT NULL REFERENCES cycles(event_id),
                    project_ref TEXT NOT NULL, machine_id TEXT NOT NULL,
                    school_id TEXT NOT NULL, class_id TEXT NOT NULL, student_id TEXT NOT NULL,
                    validated_at TEXT NOT NULL,
                    source TEXT NOT NULL CHECK(source='SUPABASE_DEV_PIN_V1')
                )""")
                for action in ("UPDATE", "DELETE"):
                    conn.execute(
                        f"CREATE TRIGGER simulation_identity_no_{action.lower()} BEFORE {action} ON simulation_identities BEGIN SELECT RAISE(ABORT,'Immutable simulation identity'); END"
                    )
                conn.execute("""CREATE TRIGGER simulation_identity_cycle_immutable
                    BEFORE UPDATE OF mode,class_id,student_id ON cycles
                    WHEN EXISTS(SELECT 1 FROM simulation_identities WHERE event_id=OLD.event_id)
                    AND (NEW.mode IS NOT OLD.mode OR NEW.class_id IS NOT OLD.class_id OR NEW.student_id IS NOT OLD.student_id)
                    BEGIN SELECT RAISE(ABORT,'Immutable associated session identity'); END""")
            if {
                r[1] for r in conn.execute("PRAGMA table_info(simulation_identities)")
            } != {
                "event_id",
                "project_ref",
                "machine_id",
                "school_id",
                "class_id",
                "student_id",
                "validated_at",
                "source",
            } or not {
                "simulation_identity_no_update",
                "simulation_identity_no_delete",
                "simulation_identity_cycle_immutable",
            } <= {
                r[0]
                for r in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='trigger'"
                )
            }:
                raise RuntimeError(
                    "Associação de identidade incompatível; operação bloqueada."
                )
            for binding in conn.execute("SELECT * FROM simulation_identities"):
                identity = SimulationIdentity(**dict(binding))
                row = self._row(conn, identity.event_id)
                if (
                    not row["simulated"]
                    or row["mode"] != "student"
                    or row["class_id"] != str(identity.class_id)
                    or row["student_id"] != str(identity.student_id)
                    or identity.validated_at.utcoffset() is None
                    or not conn.execute(
                        "SELECT 1 FROM transitions WHERE event_id=? AND code='DEV_IDENTITY_CONFIRMED' AND to_state='SAFETY'",
                        (row["event_id"],),
                    ).fetchone()
                ):
                    raise RuntimeError(
                        "Associação de identidade divergente; operação bloqueada."
                    )
                self._check_identity_scope(identity)
            if conn.execute("PRAGMA foreign_key_check").fetchone() is not None:
                raise RuntimeError("Referências SQLite inválidas; operação bloqueada.")
            conn.execute("PRAGMA user_version=4")

    @staticmethod
    def _record(conn, row, state, *, code=None, updates=None):
        values = {
            "state": state,
            "updated_at": now(),
            "failure_code": code,
            **(updates or {}),
        }
        assignments = ",".join(f"{key}=?" for key in values)
        cursor = conn.execute(
            f"UPDATE cycles SET {assignments},version=version+1 WHERE event_id=? AND version=?",
            [*values.values(), row["event_id"], row["version"]],
        )
        if cursor.rowcount != 1:
            raise CycleError("COMMAND_OUT_OF_SEQUENCE")
        conn.execute(
            "INSERT INTO transitions(event_id,from_state,to_state,code,at) VALUES(?,?,?,?,?)",
            (row["event_id"], row["state"], state, code, values["updated_at"]),
        )

    def _recover(self):
        with self.transaction() as conn:
            self.mechanical.recover(conn)
            rows = conn.execute("SELECT * FROM cycles WHERE active_slot=1").fetchall()
            for row in rows:
                state = row["state"]
                if row["simulated"]:
                    self._recover_simulation_cycle(conn, row)
                elif self.mechanical.has_risk(conn, row["event_id"]):
                    self.mechanical._block_cycle(conn, row["event_id"])
                elif self.mechanical.has_simulated_completion(conn, row["event_id"]):
                    # Conclusão simulada persiste, sem avanço físico/econômico.
                    if state != "PHYSICAL_BLOCKED":
                        self.mechanical._block_cycle(conn, row["event_id"])
                elif state in PRE_PHYSICAL:
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
        simulated: bool = False,
    ) -> Session:
        if simulated and (
            not self.simulation_enabled
            or central_scope is not None
            or mode != ("student" if self.identity_scope else "class_only")
        ):
            raise CycleError("SIMULATION_RUNTIME_REQUIRED", 403)
        with self.transaction() as conn:
            existing = conn.execute(
                "SELECT * FROM cycles WHERE command_id=?", (str(command_id),)
            ).fetchone()
            if existing:
                if (
                    existing["mode"] != mode
                    or (
                        existing["class_id"] != str(class_id)
                        and not (
                            # No DEV a turma só é escolhida ao associar identidade;
                            # POST de criação aceita apenas command_id, sem turma.
                            simulated and self.identity_scope and mode == "student"
                        )
                    )
                    or existing["simulated"] != int(simulated)
                ):
                    raise CycleError("COMMAND_ID_CONFLICT")
                return self._snapshot(existing)
            if conn.execute("SELECT 1 FROM cycles WHERE active_slot=1").fetchone():
                raise CycleError("SESSION_ALREADY_ACTIVE")
            event_id = str(uuid4())
            state = "IDENTIFYING" if mode == "student" else "SAFETY"
            timestamp = now()
            conn.execute(
                "INSERT INTO cycles(event_id,command_id,state,mode,class_id,class_name,created_at,updated_at,active_slot,central_scope,simulated) VALUES(?,?,?,?,?,?,?,?,1,?,?)",
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
                    int(simulated),
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
            if (expected, state) in SIMULATION_EDGES:
                raise CycleError("MECHANICAL_JOURNAL_REQUIRED", 503)
            if row["state"] != expected:
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            if self.mechanical.has_risk(conn, event_id):
                raise CycleError("MECHANICAL_RESULT_UNKNOWN", 503)
            if state == "CANCELLED":
                self.mechanical.abort_intents(conn, event_id)
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
            if row["simulated"]:
                raise CycleError("SIMULATION_NOT_ECONOMICALLY_ELIGIBLE", 503)
            if central_scope is None or row["central_scope"] != central_scope:
                raise CycleError("CENTRAL_SCOPE_NOT_CONFIRMED", 503)
            payload = self._ready_payload(row)
            if (
                payload is None
                or self.mechanical.has_risk(conn, event_id)
                or self.mechanical.has_simulated_completion(conn, event_id)
            ):
                raise CycleError("MISSING_PHYSICAL_EVIDENCE", 503)
            self._record(conn, row, "REGISTERING")
            return payload

    def prepare_payload(self, event_id: UUID, payload: DepositPayload):
        # Fundação para o futuro orquestrador: só congela contrato, não move equipamento.
        with self.transaction() as conn:
            row = self._row(conn, event_id)
            if (
                row["simulated"]
                or row["state"] != "REVIEW"
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

    def simulation_row(self, conn, event_id):
        row = self._row(conn, event_id)
        if not self.simulation_enabled or row["simulated"] != 1:
            raise CycleError("SIMULATION_SESSION_NOT_FOUND", 404)
        return row

    def begin_simulated_motion(self, conn, entry, *, hand_removed=False):
        row = self._row(conn, entry.command.event_id)
        if not row["simulated"]:
            return
        self.simulation_row(conn, entry.command.event_id)
        if self.identity_scope and entry.command.operation not in {
            "CLOSE_INSERTION_DOOR",
            "CONFIRM_INITIAL_STATE",
        }:
            self.require_simulation_identity(conn, row["event_id"])
        before, moving, _ = MECHANICAL_STEPS[entry.command.operation]
        if (
            row["state"] != before
            or row["active_slot"] != 1
            or entry.source != "SIMULATED"
        ):
            raise CycleError("COMMAND_OUT_OF_SEQUENCE")
        if (
            entry.command.operation == "CLOSE_INSERTION_DOOR"
            and hand_removed is not True
        ):
            raise CycleError("HAND_REMOVAL_DECLARATION_REQUIRED", 422)
        if (
            entry.command.operation == "CONFIRM_INITIAL_STATE"
            and not self._simulated_hatch_completed(conn, row["event_id"])
        ):
            raise CycleError("HATCH_COMPLETION_REQUIRED")
        if moving != before:
            self._record(
                conn,
                row,
                moving,
                code="SIMULATION_MECHANICAL_REQUESTED",
                updates={"hand_removed": 1}
                if entry.command.operation == "CLOSE_INSERTION_DOOR"
                else None,
            )

    def check_simulated_claim(self, conn, entry):
        row = self._row(conn, entry.command.event_id)
        if not row["simulated"]:
            return row["active_slot"] == 1 and row["state"] == "PHYSICAL_BLOCKED"
        self.simulation_row(conn, entry.command.event_id)
        return (
            row["active_slot"] == 1
            and row["state"] == MECHANICAL_STEPS[entry.command.operation][1]
            and entry.source == "SIMULATED"
        )

    def apply_simulated_response(self, conn, entry):
        row = self._row(conn, entry.command.event_id)
        if not row["simulated"]:
            return
        self.simulation_row(conn, entry.command.event_id)
        before, moving, after = MECHANICAL_STEPS[entry.command.operation]
        if (
            row["state"] != moving
            or row["active_slot"] != 1
            or entry.source != "SIMULATED"
        ):
            raise CycleError("MECHANICAL_SESSION_MISMATCH")
        if entry.phase == "COMPLETED":
            if after != moving:
                self._record(
                    conn,
                    row,
                    after,
                    code="SIMULATED_MECHANICAL_COMPLETION",
                    updates={"active_slot": None} if after == "COMPLETED" else None,
                )
        elif entry.phase == "REJECTED":
            if before != moving:
                self._record(conn, row, before, code=entry.error_code)

    def restore_simulated_intent(self, conn, entry):
        row = self._row(conn, entry.command.event_id)
        if row["simulated"]:
            before, moving, _ = MECHANICAL_STEPS[entry.command.operation]
            if row["state"] != moving:
                self.mechanical._block_cycle(conn, row["event_id"])
            elif before != moving:
                self._record(conn, row, before, code="SIMULATION_INTENT_NOT_DISPATCHED")

    @staticmethod
    def _simulated_hatch_completed(conn, event_id):
        return (
            conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE event_id=? AND operation='CYCLE_LOWER_HATCH' AND source='SIMULATED' AND phase='COMPLETED' LIMIT 1",
                (str(event_id),),
            ).fetchone()
            is not None
        )

    def _recover_simulation_cycle(self, conn, row):
        event_id = row["event_id"]
        if self.mechanical.has_risk(conn, event_id):
            self.mechanical._block_cycle(conn, event_id)
            return
        needed = {
            "DOOR_OPEN": "OPEN_INSERTION_DOOR",
            "DOOR_CLOSED": "CLOSE_INSERTION_DOOR",
            "REVIEW": "CLOSE_INSERTION_DOOR",
            "HATCH_IN_PROGRESS": "CYCLE_LOWER_HATCH",
        }
        if row["state"] in needed:
            if conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE event_id=? AND operation=? AND source='SIMULATED' AND phase='COMPLETED'",
                (event_id, needed[row["state"]]),
            ).fetchone():
                return
        elif row["state"] in {
            "IDENTIFYING",
            "SAFETY",
            "PHYSICAL_BLOCKED",
            "INDETERMINATE",
        }:
            return
        self.mechanical._block_cycle(conn, event_id)

    def _check_identity_scope(self, identity: SimulationIdentity) -> None:
        if (
            self.identity_scope is not None
            and (identity.project_ref, identity.machine_id, identity.school_id)
            != self.identity_scope
        ):
            raise CycleError("DEV_IDENTITY_SCOPE_MISMATCH", 403)

    def simulation_identity(self, conn, event_id) -> SimulationIdentity | None:
        binding = conn.execute(
            "SELECT * FROM simulation_identities WHERE event_id=?", (str(event_id),)
        ).fetchone()
        identity = SimulationIdentity(**dict(binding)) if binding else None
        if identity:
            self._check_identity_scope(identity)
        return identity

    def require_simulation_identity(self, conn, event_id) -> SimulationIdentity:
        identity = self.simulation_identity(conn, event_id)
        if identity is None:
            raise CycleError("DEV_IDENTITY_REQUIRED")
        return identity

    def identity_attempt(
        self,
        event_id: UUID,
        class_id: UUID,
        student_id: UUID,
    ) -> tuple[SimulationIdentity | None, int]:
        """Pré-checagem sem reserva/segredo; o commit revalida estado e versão."""
        with self.transaction() as conn:
            row = self.simulation_row(conn, event_id)
            identity = self.simulation_identity(conn, event_id)
            if identity:
                if (identity.class_id, identity.student_id) != (class_id, student_id):
                    raise CycleError("DEV_IDENTITY_CONFLICT")
                return identity, row["version"]
            if (
                self.identity_scope is None
                or row["mode"] != "student"
                or row["state"] != "IDENTIFYING"
                or row["active_slot"] != 1
                or conn.execute(
                    "SELECT 1 FROM mechanical_commands WHERE event_id=?",
                    (str(event_id),),
                ).fetchone()
            ):
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            return None, row["version"]

    def bind_simulation_identity(
        self,
        identity: SimulationIdentity,
        student: ConfirmedStudent,
        expected_version: int,
    ) -> None:
        with self.transaction() as conn:
            row = self.simulation_row(conn, identity.event_id)
            self._check_identity_scope(identity)
            previous = self.simulation_identity(conn, identity.event_id)
            if previous:
                if (previous.class_id, previous.student_id) != (
                    identity.class_id,
                    identity.student_id,
                ):
                    raise CycleError("DEV_IDENTITY_CONFLICT")
                return  # Outro request já confirmou a mesma identidade.
            if (
                self.identity_scope is None
                or row["state"] != "IDENTIFYING"
                or row["mode"] != "student"
                or row["active_slot"] != 1
                or row["version"] != expected_version
                or conn.execute(
                    "SELECT 1 FROM mechanical_commands WHERE event_id=?",
                    (row["event_id"],),
                ).fetchone()
            ):
                raise CycleError("COMMAND_OUT_OF_SEQUENCE")
            if (
                student.id != identity.student_id
                or student.class_id != identity.class_id
            ):
                raise CycleError("DEV_IDENTITY_CONFLICT")
            self._record(conn, row, "AUTHENTICATING", code="DEV_IDENTITY_VALIDATED")
            self._record(
                conn,
                self._row(conn, identity.event_id),
                "SAFETY",
                code="DEV_IDENTITY_CONFIRMED",
                updates={
                    "class_id": str(identity.class_id),
                    "student_id": str(identity.student_id),
                    "class_name": student.class_name,
                    "student_name": student.name,
                },
            )
            conn.execute(
                "INSERT INTO simulation_identities(event_id,project_ref,machine_id,school_id,class_id,student_id,validated_at,source) VALUES(?,?,?,?,?,?,?,?)",
                tuple(identity.model_dump(mode="json").values()),
            )
