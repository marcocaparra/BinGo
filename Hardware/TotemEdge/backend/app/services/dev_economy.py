"""Homologação econômica opt-in; nunca declara movimento físico real."""

import asyncio
import json
from hashlib import sha256
from uuid import UUID

from app.central_contracts import DepositPayload, DepositReceipt
from app.clients.supabase import CentralError
from app.cycles import CycleError
from app.dev_integration import DEV_PROJECT, DevCentralClient
from app.storage import now


class DevEconomy:
    def __init__(self, store, central):
        if (
            not isinstance(central, DevCentralClient)
            or not central.policy.economic_registration
            or central.policy.project_ref != DEV_PROJECT
            or not store.identity_scope
            or store.identity_scope
            != (DEV_PROJECT, central.policy.machine_id, central.policy.school_id)
        ):
            raise ValueError("DEV economic scope required")
        self.store, self.central = store, central
        self.scope = sha256(
            f"{DEV_PROJECT}|{central.policy.machine_id}|{central.policy.school_id}".encode()
        ).hexdigest()
        with store.transaction() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS dev_economic_outbox (
                event_id TEXT PRIMARY KEY REFERENCES cycles(event_id), scope TEXT NOT NULL,
                payload TEXT NOT NULL, receipt TEXT, failure_code TEXT,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
            conn.execute("""CREATE TRIGGER IF NOT EXISTS dev_economic_payload_immutable
                BEFORE UPDATE OF event_id,scope,payload ON dev_economic_outbox
                BEGIN SELECT RAISE(ABORT,'Immutable DEV economic event'); END""")
        self.task = None

    def queue(self, conn, event):
        row = self.store.simulation_row(conn, event)
        identity = self.store.require_simulation_identity(conn, event)
        commands = conn.execute(
            "SELECT * FROM mechanical_commands WHERE event_id=?", (str(event),)
        ).fetchall()
        vision = conn.execute(
            "SELECT * FROM vision_attempts WHERE event_id=?", (str(event),)
        ).fetchone()
        if (
            row["state"] != "COMPLETED"
            or row["physical_confirmed"]
            or not vision
            or vision["phase"] != "COMPLETED"
            or not vision["decision"]
            or not commands
            or any(
                c["source"] != "SIMULATED"
                or c["phase"] != "COMPLETED"
                or c["result"] != "SUCCEEDED"
                for c in commands
            )
            or {c["operation"] for c in commands}
            not in (
                {"OPEN_INSERTION_DOOR", "CLOSE_INSERTION_DOOR", "CYCLE_LOWER_HATCH", "CONFIRM_INITIAL_STATE"},
                {"CONFIRM_HAND_REMOVED", "CYCLE_LOWER_HATCH", "CONFIRM_INITIAL_STATE"},
            )
        ):
            raise CycleError("DEV_ECONOMIC_COMPLETION_REQUIRED")
        decision = json.loads(vision["decision"])
        provenance = json.loads(vision["provenance"] or "{}")
        if (
            provenance.get("camera") != "DEVICE"
            or provenance.get("inference") != "PROVIDER"
        ):
            raise CycleError("DEV_REAL_VISION_REQUIRED")
        body = DepositPayload(
            event_id=event,
            class_id=identity.class_id,
            student_id=identity.student_id,
            is_valid=True,
            detected_type=decision.get("detected_type"),
            waste_category_code=decision["category"],
            category_source=decision["source"],
        )
        old = conn.execute(
            "SELECT * FROM dev_economic_outbox WHERE event_id=?", (str(event),)
        ).fetchone()
        if old:
            if old["scope"] != self.scope or old["payload"] != body.model_dump_json():
                raise CycleError("EVENT_ID_CONFLICT")
            return
        conn.execute(
            "INSERT INTO dev_economic_outbox VALUES(?,?,?,NULL,NULL,?,?)",
            (str(event), self.scope, body.model_dump_json(), now(), now()),
        )
        self.store._record(
            conn,
            row,
            "COMPLETED",
            code="DEV_SIMULATED_ECONOMIC_QUEUED",
            updates={"active_slot": 1},
        )

    def snapshot(self, conn, event):
        row = conn.execute(
            "SELECT * FROM dev_economic_outbox WHERE event_id=?", (str(event),)
        ).fetchone()
        if not row:
            return {"status": "AWAITING_COMPLETION", "receipt": None}
        if row["scope"] != self.scope:
            raise CycleError("DEV_IDENTITY_SCOPE_MISMATCH", 403)
        receipt = (
            DepositReceipt.model_validate_json(row["receipt"])
            if row["receipt"]
            else None
        )
        if receipt and receipt.event_id != UUID(str(event)):
            raise CycleError("INVALID_STORED_RECEIPT", 503)
        return {
            "status": "CONFIRMED" if receipt else "PENDING",
            "receipt": receipt.model_dump(mode="json") if receipt else None,
        }

    async def process(self):
        with self.store.transaction() as conn:
            pending = conn.execute(
                "SELECT * FROM dev_economic_outbox WHERE receipt IS NULL AND scope=?",
                (self.scope,),
            ).fetchall()
        for row in pending:
            body = DepositPayload.model_validate_json(row["payload"])
            with self.store.transaction() as conn:
                self.queue(conn, body.event_id)
            try:
                receipt = await self.central.register(body)
            except CentralError as error:
                with self.store.transaction() as conn:
                    conn.execute(
                        "UPDATE dev_economic_outbox SET failure_code=?,updated_at=? WHERE event_id=?",
                        (error.code, now(), row["event_id"]),
                    )
                continue
            with self.store.transaction() as conn:
                current = conn.execute(
                    "SELECT receipt FROM dev_economic_outbox WHERE event_id=?",
                    (row["event_id"],),
                ).fetchone()
                if current["receipt"] is None:
                    conn.execute(
                        "UPDATE dev_economic_outbox SET receipt=?,failure_code=NULL,updated_at=? WHERE event_id=?",
                        (receipt.model_dump_json(), now(), row["event_id"]),
                    )
                    self.store._record(
                        conn,
                        self.store._row(conn, row["event_id"]),
                        "COMPLETED",
                        code="DEV_SIMULATED_ECONOMIC_CONFIRMED",
                    )

    async def run(self):
        while True:
            await self.process()
            await asyncio.sleep(5)

    def finish(self, event):
        with self.store.transaction() as conn:
            if self.snapshot(conn, event)["status"] != "CONFIRMED":
                raise CycleError("ECONOMIC_CONFIRMATION_REQUIRED")
            self.store._record(
                conn,
                self.store._row(conn, event),
                "COMPLETED",
                code="DEV_ECONOMIC_FINISHED",
                updates={"active_slot": None},
            )
