"""Session orchestration over CaptureService and the existing provider cascade."""

import asyncio
import json
from uuid import UUID, uuid5, NAMESPACE_URL

from app.cycles import CycleError
from app.services.capture import CaptureService
from app.services.camera import CameraError
from app.services.vision import (
    validate_frame,
    validate_result,
    VisionError,
    InternalVision,
)
from app.storage import now

POLICY = "bingo-labels-pr48-0.75-v1"
# Same business mapping as Software/apps/totem_simulator/app.js (operator approved).
# No size multiplier, points or central payload is computed here.
CATEGORIES = {
    "battery": "BATTERY",
    "cable": "CABLE_WIRE",
    "phone": "MOBILE_DEVICE",
    "small": "PERIPHERAL",
    "unknown": "UNKNOWN",
}


class SessionVision:
    def __init__(
        self,
        capture: CaptureService,
        mechanical,
        *,
        model: str,
        deferred_analysis=False,
    ):
        self.capture, self.store = capture, capture.store
        self.mechanical, self.model = mechanical, model
        self.tasks = {}
        self.deferred_analysis = deferred_analysis
        self.frames = {}

    @staticmethod
    def identifier(close_id):
        return uuid5(NAMESPACE_URL, f"bingo:session-vision:v1:{close_id}")

    def recover_unstarted(self):
        """Startup may record a lost intent, never silently acquire new pixels."""
        with self.store.transaction() as conn:
            rows = conn.execute(
                "SELECT * FROM cycles WHERE active_slot=1 AND simulated=1 AND state='DOOR_CLOSED' AND NOT EXISTS (SELECT 1 FROM vision_attempts WHERE vision_attempts.event_id=cycles.event_id)"
            ).fetchall()
            for row in rows:
                command = conn.execute(
                    "SELECT mechanical_command_id FROM mechanical_commands WHERE event_id=? AND operation='CLOSE_INSERTION_DOOR' AND source='SIMULATED' AND phase='COMPLETED' AND result='SUCCEEDED'",
                    (row["event_id"],),
                ).fetchone()
                if command:
                    close_id = command["mechanical_command_id"]
                    code = "CAPTURE_NOT_STARTED_AFTER_RESTART"
                    conn.execute(
                        "INSERT INTO vision_attempts(capture_id,event_id,close_command_id,phase,error_code,created_at,updated_at) VALUES(?,?,?,'FAILED',?,?,?)",
                        (
                            str(self.identifier(close_id)),
                            row["event_id"],
                            close_id,
                            code,
                            now(),
                            now(),
                        ),
                    )
                    self.store._record(conn, row, "TECHNICAL_FAILURE", code=code)

    def snapshot(self, conn, event):
        row = conn.execute(
            "SELECT * FROM vision_attempts WHERE event_id=?", (str(event),)
        ).fetchone()
        if row is None:
            return None
        value = dict(row)
        for name in ("observation", "decision", "provenance"):
            value[name] = json.loads(value[name]) if value[name] else None
        result = value["observation"]
        value["allowed_candidates"] = (
            list(dict.fromkeys([*result["candidateIds"], "unknown"]))
            if result
            and result["status"] == "recognized"
            and value["phase"] == "COMPLETED"
            else []
        )
        value["image_available"] = (
            str(event) in self.frames and value["phase"] == "CAPTURING"
        )
        return value

    def after_close(self, entry):
        key = str(entry.command.mechanical_command_id)
        if key not in self.tasks:
            self.tasks[key] = asyncio.create_task(self._after_close(entry.command))

    async def _after_close(self, command):
        try:
            entry = await self.mechanical.wait(command.mechanical_command_id)
            if entry.phase == "COMPLETED" and entry.result == "SUCCEEDED":
                await self.analyze(command.event_id, command.mechanical_command_id)
        except CycleError:
            pass  # Durable attempt/state already records controlled failure.

    async def analyze(self, event: UUID, close_id: UUID):
        identifier = self.identifier(close_id)
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event)
            previous = self.snapshot(conn, event)
            if previous:
                if previous["capture_id"] != str(identifier):
                    raise CycleError("CAPTURE_ID_CONFLICT")
                return previous
            if self.store.identity_scope:
                self.store.require_simulation_identity(conn, event)
            closed = conn.execute(
                "SELECT 1 FROM mechanical_commands WHERE mechanical_command_id=? AND event_id=? AND operation='CLOSE_INSERTION_DOOR' AND source='SIMULATED' AND phase='COMPLETED' AND result='SUCCEEDED'",
                (str(close_id), str(event)),
            ).fetchone()
            if row["state"] != "DOOR_CLOSED" or row["active_slot"] != 1 or not closed:
                raise CycleError("DOOR_CLOSED_CONFIRMATION_REQUIRED")
            if self.store.mechanical.has_risk(conn, event):
                raise CycleError("MECHANICAL_RESULT_UNKNOWN", 503)
            conn.execute(
                "INSERT INTO vision_attempts(capture_id,event_id,close_command_id,phase,created_at,updated_at) VALUES(?,?,?,'CAPTURING',?,?)",
                (str(identifier), str(event), str(close_id), now(), now()),
            )
            self.store._record(conn, row, "CAPTURING", code="VISION_CAPTURE_REQUESTED")
        try:
            # Pixels remain separate from the simulated mechanical provenance.
            frame = await self.capture.acquire(identifier)
            validate_frame(frame)
            if frame.media_type != "image/jpeg":
                raise VisionError("UNSUPPORTED_IMAGE_TYPE")
            audit = dict(
                camera="SIMULATED" if frame.simulated else "DEVICE",
                mechanical="SIMULATED",
                policy=POLICY,
                capture=dict(media_type=frame.media_type, bytes=len(frame.content)),
                observations=[],
            )
            if self.deferred_analysis:
                audit["capture_ready"] = True
                with self.store.transaction() as conn:
                    conn.execute(
                        "UPDATE vision_attempts SET provenance=?,updated_at=? WHERE capture_id=? AND phase='CAPTURING'",
                        (json.dumps(audit), now(), str(identifier)),
                    )
                    self.frames[str(event)] = frame
                    return self.snapshot(conn, event)
            return await self._classify(event, identifier, frame, audit)
        except BaseException as error:
            self.frames.pop(str(event), None)
            # Never persist repr/message from a device, HTTP client or provider.
            code = (
                error.code
                if isinstance(error, (VisionError, CameraError, CycleError))
                else "PROCESS_INTERRUPTED"
                if isinstance(error, asyncio.CancelledError)
                else "CAPTURE_OR_CLASSIFICATION_FAILED"
            )
            with self.store.transaction() as conn:
                row = self.store._row(conn, event)
                conn.execute(
                    "UPDATE vision_attempts SET phase='FAILED',error_code=?,provenance=?,updated_at=? WHERE capture_id=? AND phase IN ('CAPTURING','CLASSIFYING')",
                    (
                        code,
                        json.dumps(
                            self.snapshot(conn, event)["provenance"]
                            or {
                                "mechanical": "SIMULATED",
                                "policy": POLICY,
                                "observations": [],
                            }
                        ),
                        now(),
                        str(identifier),
                    ),
                )
                if row["state"] in {"CAPTURING", "CLASSIFYING"}:
                    self.store._record(conn, row, "TECHNICAL_FAILURE", code=code)
            if isinstance(error, asyncio.CancelledError):
                raise
            raise CycleError(code, 503) from None

    async def _classify(self, event, identifier, frame, audit):
        try:
            with self.store.transaction() as conn:
                row = self.store._row(conn, event)
                if row["state"] not in {"CAPTURING", "CLASSIFYING"}:
                    raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                conn.execute(
                    "UPDATE vision_attempts SET phase='CLASSIFYING',provenance=?,updated_at=? WHERE capture_id=?",
                    (json.dumps(audit), now(), str(identifier)),
                )
                if row["state"] == "CAPTURING":
                    self.store._record(conn, row, "CLASSIFYING")
            if not isinstance(self.capture.vision, InternalVision):
                raise VisionError("PRIMARY_UNAVAILABLE")

            def observe(result):
                # The primary observation is durable before secondary network I/O.
                audit["observations"].append(result.model_dump())
                try:
                    with self.store.transaction() as conn:
                        updated = conn.execute(
                            "UPDATE vision_attempts SET provenance=?,updated_at=? WHERE capture_id=? AND phase='CLASSIFYING'",
                            (json.dumps(audit), now(), str(identifier)),
                        )
                        if updated.rowcount != 1:
                            raise ValueError()
                except Exception:
                    raise VisionError("VISION_AUDIT_FAILED") from None

            observation = await self.capture.vision.classify(frame, observe=observe)
            result = validate_result(
                observation.result.model_dump(), observation.result.origin
            )
            provenance = dict(
                **audit,
                inference="SIMULATED" if observation.simulated else "PROVIDER",
                provider=result.origin,
                model=self.model
                if result.origin == "GEMINI_FALLBACK"
                else "Rekognition DetectLabels",
            )
            state = {
                "recognized": "REVIEW",
                "rejected": "RETURN_REQUIRED",
                "needs-secondary": "TECHNICAL_FAILURE",
            }[result.status]
            error = (
                "CLASSIFICATION_INCONCLUSIVE" if state == "TECHNICAL_FAILURE" else None
            )
            with self.store.transaction() as conn:
                row = self.store._row(conn, event)
                if row["state"] != "CLASSIFYING":
                    raise CycleError("COMMAND_OUT_OF_SEQUENCE")
                conn.execute(
                    "UPDATE vision_attempts SET phase=?,observation=?,provenance=?,error_code=?,updated_at=? WHERE capture_id=?",
                    (
                        "FAILED" if error else "COMPLETED",
                        result.model_dump_json(),
                        json.dumps(provenance),
                        error,
                        now(),
                        str(identifier),
                    ),
                )
                self.store._record(
                    conn,
                    row,
                    state,
                    code=error,
                    updates={"vision_result": result.model_dump_json()},
                )
        except BaseException as error:
            self.frames.pop(str(event), None)
            # Never persist repr/message from a device, HTTP client or provider.
            code = (
                error.code
                if isinstance(error, (VisionError, CameraError, CycleError))
                else "PROCESS_INTERRUPTED"
                if isinstance(error, asyncio.CancelledError)
                else "CAPTURE_OR_CLASSIFICATION_FAILED"
            )
            with self.store.transaction() as conn:
                row = self.store._row(conn, event)
                conn.execute(
                    "UPDATE vision_attempts SET phase='FAILED',error_code=?,provenance=?,updated_at=? WHERE capture_id=? AND phase IN ('CAPTURING','CLASSIFYING')",
                    (
                        code,
                        json.dumps(
                            self.snapshot(conn, event)["provenance"]
                            or {
                                "mechanical": "SIMULATED",
                                "policy": POLICY,
                                "observations": [],
                            }
                        ),
                        now(),
                        str(identifier),
                    ),
                )
                if row["state"] in {"CAPTURING", "CLASSIFYING"}:
                    self.store._record(conn, row, "TECHNICAL_FAILURE", code=code)
            if isinstance(error, asyncio.CancelledError):
                raise
            raise CycleError(code, 503) from None
        with self.store.transaction() as conn:
            return self.snapshot(conn, event)

    def image(self, event, identifier):
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event)
            attempt = self.snapshot(conn, event)
            if (
                not attempt
                or attempt["capture_id"] != str(identifier)
                or row["active_slot"] != 1
                or row["state"] != "CAPTURING"
                or str(event) not in self.frames
            ):
                raise CycleError("VISION_IMAGE_UNAVAILABLE", 410)
            return self.frames[str(event)]

    def request_analysis(self, event, identifier):
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event)
            attempt = self.snapshot(conn, event)
            if not attempt or attempt["capture_id"] != str(identifier):
                raise CycleError("CAPTURE_ID_CONFLICT")
            if attempt["phase"] != "CAPTURING":
                return  # A consumed classification intent is never repeated.
            if (
                row["state"] != "CAPTURING"
                or row["active_slot"] != 1
                or self.store.mechanical.has_risk(conn, event)
                or not attempt["image_available"]
                or not attempt["provenance"].get("capture_ready")
            ):
                raise CycleError("VISION_IMAGE_UNAVAILABLE", 409)
            audit = attempt["provenance"]
            audit["capture_ready"] = False
            conn.execute(
                "UPDATE vision_attempts SET phase='CLASSIFYING',provenance=?,updated_at=? WHERE capture_id=?",
                (json.dumps(audit), now(), str(identifier)),
            )
            self.store._record(conn, row, "CLASSIFYING")
            frame = self.frames[str(event)]
        self.frames.pop(str(event))
        self.tasks["analysis:" + str(identifier)] = asyncio.create_task(
            self._run_classification(event, identifier, frame, audit)
        )

    async def _run_classification(self, event, identifier, frame, audit):
        try:
            await self._classify(event, identifier, frame, audit)
        except CycleError:
            pass  # The controlled failure is already durable.

    def review(self, event, capture_id, item_id, action):
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event)
            attempt = self.snapshot(conn, event)
            if not attempt or attempt["capture_id"] != str(capture_id):
                raise CycleError("CAPTURE_ID_CONFLICT")
            original = attempt["observation"]
            decision = dict(item_id=item_id, action=action)
            if attempt["decision"]:
                if any(
                    attempt["decision"][key] != value for key, value in decision.items()
                ):
                    raise CycleError("VISION_REVIEW_CONFLICT")
                return
            if (
                row["state"] != "REVIEW"
                or attempt["phase"] != "COMPLETED"
                or original["status"] != "recognized"
            ):
                raise CycleError("VISION_REVIEW_NOT_ALLOWED")
            if (
                (action == "confirm" and item_id != original["itemId"])
                or item_id not in attempt["allowed_candidates"]
                or item_id not in CATEGORIES
                or action not in {"confirm", "correct"}
            ):
                raise CycleError("VISION_CANDIDATE_NOT_ALLOWED", 422)
            decision.update(
                at=now(),
                category=CATEGORIES[item_id],
                source="UNIDENTIFIED"
                if item_id == "unknown"
                else "AI_CONFIRMED"
                if action == "confirm"
                else "USER_CORRECTED",
            )
            conn.execute(
                "UPDATE vision_attempts SET decision=?,updated_at=? WHERE capture_id=?",
                (json.dumps(decision), now(), str(capture_id)),
            )
            self.store._record(conn, row, "REVIEW", code="VISION_REVIEW_PERSISTED")

    async def aclose(self):
        for task in self.tasks.values():
            task.cancel()
        await asyncio.gather(*self.tasks.values(), return_exceptions=True)
        self.frames.clear()
