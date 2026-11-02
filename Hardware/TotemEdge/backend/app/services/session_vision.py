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
            for intent in conn.execute(
                "SELECT * FROM vision_recaptures WHERE result_attempt IS NULL"
            ).fetchall():
                current = conn.execute(
                    "SELECT phase FROM vision_attempts WHERE event_id=?",
                    (intent["event_id"],),
                ).fetchone()
                if current and current["phase"] in {"FAILED", "COMPLETED"}:
                    self._finish_recapture(conn, intent, None)
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
        # Read-only projection of pre-upgrade, unreviewed grouped observations.
        if (
            result
            and not value["decision"]
            and result["status"] == "recognized"
            and result["itemId"] == "small"
            and not result.get("detected_types", {}).get("small")
        ):
            result = {
                **result,
                "itemId": "unknown",
                "candidateIds": list(
                    dict.fromkeys(
                        [
                            "unknown",
                            *[i for i in result["candidateIds"] if i != "small"],
                        ]
                    )
                ),
            }
            value["observation"] = result
        value["allowed_candidates"] = (
            list(
                dict.fromkeys(
                    [
                        *[
                            i
                            for i in result["candidateIds"]
                            if i != "small" or result.get("detected_types", {}).get(i)
                        ],
                        "unknown",
                    ]
                )
            )
            if result
            and result["status"] == "recognized"
            and value["phase"] == "COMPLETED"
            else []
        )
        # Preserve immutable historical decisions made before specific types existed.
        if (
            value["decision"]
            and value["decision"]["item_id"] not in value["allowed_candidates"]
        ):
            value["allowed_candidates"].append(value["decision"]["item_id"])
        value["image_available"] = str(event) in self.frames and value["phase"] in {
            "CAPTURING",
            "CLASSIFYING",
            "COMPLETED",
            "FAILED",
        }
        history = conn.execute(
            "SELECT analysis_id,previous_attempt,created_at FROM vision_analysis_retries WHERE event_id=? ORDER BY created_at",
            (str(event),),
        ).fetchall()
        if history:
            value["analysis_history"] = [
                {
                    "analysis_id": r["analysis_id"],
                    "previous_attempt": json.loads(r["previous_attempt"]),
                    "created_at": r["created_at"],
                }
                for r in history
            ]
        captures = conn.execute(
            "SELECT * FROM vision_recaptures WHERE event_id=? ORDER BY created_at, rowid",
            (str(event),),
        ).fetchall()
        if captures:
            value["capture_history"] = [
                {
                    **dict(r),
                    "previous_attempt": json.loads(r["previous_attempt"]),
                    "result_attempt": json.loads(r["result_attempt"])
                    if r["result_attempt"]
                    else None,
                }
                for r in captures
            ]
            last = captures[-1]
            if last["result_attempt"] and last["capture_id"] != value["capture_id"]:
                value["recapture_error"] = json.loads(last["result_attempt"]).get(
                    "error_code"
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
                if previous["close_command_id"] != str(close_id):
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
        return await self._acquire_and_classify(event, identifier)

    async def _acquire_and_classify(self, event, identifier):
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
                    self.frames.clear()
                    self.frames[str(event)] = frame
                    return self.snapshot(conn, event)
            self.frames.clear()  # Bound retention: the next valid photo replaces the last.
            self.frames[str(event)] = frame
            return await self._classify(event, identifier, frame, audit)
        except BaseException as error:
            # Keep the last validated photo in RAM for private diagnostics.
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
                audit["observations"].append(result.model_dump(exclude_defaults=True))
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
            # A legacy grouping without a specific observed type is not a class.
            # The provider observation remains intact in provenance.observations.
            if (
                result.status == "recognized"
                and result.itemId == "small"
                and not result.detected_types.get("small")
            ):
                result = result.model_copy(
                    update={
                        "itemId": "unknown",
                        "candidateIds": list(
                            dict.fromkeys(
                                [
                                    "unknown",
                                    *[i for i in result.candidateIds if i != "small"],
                                ]
                            )
                        ),
                    }
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
            # Keep the last validated photo in RAM for private diagnostics.
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
            frame = self.frames.get(str(event))
            if (
                not attempt
                or attempt["capture_id"] != str(identifier)
                or (row["active_slot"] != 1 and row["state"] != "CANCELLED")
                or row["state"]
                not in {
                    "CAPTURING",
                    "CLASSIFYING",
                    "REVIEW",
                    "TECHNICAL_FAILURE",
                    "RETURN_REQUIRED",
                    "CANCELLED",
                }
                or frame is None
            ):
                raise CycleError("VISION_IMAGE_UNAVAILABLE", 410)
            return frame

    def can_retry(self, conn, row, attempt):
        """Explicit analysis retry only: retained pixels and durable simulated closure."""
        if not (
            attempt
            and attempt["phase"] == "FAILED"
            and attempt["error_code"]
            in {
                "PRIMARY_UNAVAILABLE",
                "PRIMARY_TIMEOUT",
                "SECONDARY_UNAVAILABLE",
                "SECONDARY_TIMEOUT",
                "VISION_TIMEOUT",
                "INVALID_PRIMARY_RESPONSE",
                "INVALID_SECONDARY_RESPONSE",
                "INVALID_PROVIDER_RESPONSE",
                "VISION_PROVIDER_FAILED",
                "VISION_BUSY",
            }
            and str(row["event_id"]) in self.frames
            and row["state"] == "TECHNICAL_FAILURE"
            and row["active_slot"] == 1
            and row["simulated"] == 1
            and self.mechanical.source == "SIMULATED"
            and not row["physical_confirmed"]
            and all(row[k] is None for k in ("payload", "receipt", "central_scope"))
        ):
            return False
        closed = conn.execute(
            "SELECT 1 FROM mechanical_commands WHERE mechanical_command_id=? AND event_id=? AND operation='CLOSE_INSERTION_DOOR' AND source='SIMULATED' AND phase='COMPLETED' AND result='SUCCEEDED'",
            (attempt["close_command_id"], row["event_id"]),
        ).fetchone()
        unsafe = conn.execute(
            "SELECT 1 FROM mechanical_commands WHERE event_id=? AND (source!='SIMULATED' OR phase!='COMPLETED' OR result!='SUCCEEDED')",
            (row["event_id"],),
        ).fetchone()
        return bool(closed and not unsafe) and self.can_recapture(conn, row, attempt)

    def can_recapture(self, conn, row, attempt):
        if not (
            attempt
            and row["state"] in {"REVIEW", "RETURN_REQUIRED", "TECHNICAL_FAILURE"}
            and row["active_slot"] == 1
            and row["simulated"] == 1
            and self.mechanical.source == "SIMULATED"
            and not row["physical_confirmed"]
            and attempt["phase"] in {"COMPLETED", "FAILED"}
            and not attempt["decision"]
            and (
                (row["state"] == "TECHNICAL_FAILURE" and attempt["phase"] == "FAILED")
                or (
                    row["state"] == "RETURN_REQUIRED"
                    and attempt["phase"] == "COMPLETED"
                    and (attempt["observation"] or {}).get("status") == "rejected"
                )
                or (
                    row["state"] == "REVIEW"
                    and attempt["phase"] == "COMPLETED"
                    and (attempt["observation"] or {}).get("status") == "recognized"
                )
            )
            and all(row[k] is None for k in ("payload", "receipt", "central_scope"))
        ):
            return False
        if self.store.identity_scope:
            self.store.require_simulation_identity(conn, row["event_id"])
        if (
            conn.execute(
                "SELECT 1 FROM sqlite_master WHERE name='dev_economic_outbox'"
            ).fetchone()
            and conn.execute(
                "SELECT 1 FROM dev_economic_outbox WHERE event_id=?", (row["event_id"],)
            ).fetchone()
        ):
            return False
        closed = conn.execute(
            "SELECT 1 FROM mechanical_commands WHERE mechanical_command_id=? AND event_id=? AND operation='CLOSE_INSERTION_DOOR' AND source='SIMULATED' AND phase='COMPLETED' AND result='SUCCEEDED'",
            (attempt["close_command_id"], row["event_id"]),
        ).fetchone()
        unsafe = conn.execute(
            "SELECT 1 FROM mechanical_commands WHERE event_id=? AND (operation NOT IN ('OPEN_INSERTION_DOOR','CLOSE_INSERTION_DOOR') OR source!='SIMULATED' OR phase!='COMPLETED' OR result!='SUCCEEDED')",
            (row["event_id"],),
        ).fetchone()
        return bool(closed and not unsafe)

    def recapture(self, event, previous_capture, intent_id):
        identifier = uuid5(NAMESPACE_URL, f"bingo:recapture:v1:{event}:{intent_id}")
        with self.store.transaction() as conn:
            replay = conn.execute(
                "SELECT * FROM vision_recaptures WHERE recapture_id=?",
                (str(intent_id),),
            ).fetchone()
            if replay:
                if replay["event_id"] != str(event) or replay[
                    "previous_capture_id"
                ] != str(previous_capture):
                    raise CycleError("RECAPTURE_ID_CONFLICT")
                return
            row = self.store.simulation_row(conn, event)
            attempt = self.snapshot(conn, event)
            if not attempt or attempt["capture_id"] != str(previous_capture):
                raise CycleError("CAPTURE_ID_CONFLICT")
            if not self.can_recapture(conn, row, attempt):
                raise CycleError("VISION_RECAPTURE_NOT_ALLOWED")
            previous = dict(
                conn.execute(
                    "SELECT * FROM vision_attempts WHERE event_id=?", (str(event),)
                ).fetchone()
            )
            conn.execute(
                "INSERT INTO vision_recaptures VALUES(?,?,?,?,?,NULL,?)",
                (
                    str(intent_id),
                    str(event),
                    str(previous_capture),
                    str(identifier),
                    json.dumps(previous),
                    now(),
                ),
            )
            conn.execute(
                "UPDATE vision_attempts SET capture_id=?,phase='CAPTURING',observation=NULL,decision=NULL,provenance=NULL,error_code=NULL,created_at=?,updated_at=? WHERE event_id=?",
                (str(identifier), now(), now(), str(event)),
            )
            self.store._record(
                conn, row, "CAPTURING", code="VISION_RECAPTURE_REQUESTED"
            )
        old_frame = self.frames.pop(str(event), None)
        self.tasks["recapture:" + str(intent_id)] = asyncio.create_task(
            self._run_recapture(event, identifier, intent_id, old_frame)
        )

    def _finish_recapture(self, conn, intent, old_frame):
        current = dict(
            conn.execute(
                "SELECT * FROM vision_attempts WHERE event_id=?", (intent["event_id"],)
            ).fetchone()
        )
        if intent["result_attempt"] is not None:
            return
        conn.execute(
            "UPDATE vision_recaptures SET result_attempt=? WHERE recapture_id=?",
            (json.dumps(current), intent["recapture_id"]),
        )
        row = self.store._row(conn, intent["event_id"])
        if current["phase"] == "FAILED" and row["state"] == "TECHNICAL_FAILURE":
            previous = json.loads(intent["previous_attempt"])
            columns = [
                "capture_id",
                "phase",
                "observation",
                "decision",
                "provenance",
                "error_code",
                "created_at",
                "updated_at",
            ]
            conn.execute(
                "UPDATE vision_attempts SET "
                + ",".join(k + "=?" for k in columns)
                + " WHERE event_id=?",
                [*[previous[k] for k in columns], intent["event_id"]],
            )
            self.frames.pop(intent["event_id"], None)
            if old_frame is not None:
                self.frames[intent["event_id"]] = old_frame
            self.store._record(
                conn,
                row,
                "REVIEW"
                if (json.loads(previous["observation"] or "{}")).get("status")
                == "recognized"
                else "RETURN_REQUIRED"
                if (json.loads(previous["observation"] or "{}")).get("status")
                == "rejected"
                else "TECHNICAL_FAILURE",
                code="VISION_RECAPTURE_FAILED_PREVIOUS_RETAINED",
                updates={"vision_result": previous["observation"]},
            )

    async def _run_recapture(self, event, identifier, intent_id, old_frame):
        try:
            # Refotografia sempre analisa automaticamente; não usa o modo manual histórico.
            await self._acquire_and_classify(event, identifier)
            with self.store.transaction() as conn:
                attempt = self.snapshot(conn, event)
            if attempt["phase"] == "CAPTURING" and attempt["provenance"].get(
                "capture_ready"
            ):
                await self._classify(
                    event,
                    identifier,
                    self.frames[str(event)],
                    {**attempt["provenance"], "capture_ready": False},
                )
        except CycleError:
            pass
        finally:
            with self.store.transaction() as conn:
                intent = conn.execute(
                    "SELECT * FROM vision_recaptures WHERE recapture_id=?",
                    (str(intent_id),),
                ).fetchone()
                self._finish_recapture(conn, intent, old_frame)

    def retry_analysis(self, event, capture_id, analysis_id):
        with self.store.transaction() as conn:
            row = self.store.simulation_row(conn, event)
            attempt = self.snapshot(conn, event)
            if not attempt or attempt["capture_id"] != str(capture_id):
                raise CycleError("CAPTURE_ID_CONFLICT")
            replay = conn.execute(
                "SELECT event_id,capture_id FROM vision_analysis_retries WHERE analysis_id=?",
                (str(analysis_id),),
            ).fetchone()
            if replay:
                if replay["event_id"] != str(event) or replay["capture_id"] != str(
                    capture_id
                ):
                    raise CycleError("ANALYSIS_ID_CONFLICT")
                return
            if not self.can_retry(conn, row, attempt):
                raise CycleError("VISION_RETRY_NOT_ALLOWED")
            previous = dict(
                conn.execute(
                    "SELECT * FROM vision_attempts WHERE event_id=?", (str(event),)
                ).fetchone()
            )
            conn.execute(
                "INSERT INTO vision_analysis_retries VALUES(?,?,?,?,?)",
                (
                    str(analysis_id),
                    str(event),
                    str(capture_id),
                    json.dumps(previous),
                    now(),
                ),
            )
            audit = {
                k: v
                for k, v in (attempt["provenance"] or {}).items()
                if k in {"camera", "mechanical", "policy", "capture"}
            }
            audit.update(observations=[], analysis_id=str(analysis_id))
            conn.execute(
                "UPDATE vision_attempts SET phase='CLASSIFYING',observation=NULL,decision=NULL,error_code=NULL,provenance=?,updated_at=? WHERE event_id=?",
                (json.dumps(audit), now(), str(event)),
            )
            self.store._record(
                conn, row, "CLASSIFYING", code="VISION_ANALYSIS_RETRY_REQUESTED"
            )
            frame = self.frames[str(event)]
        self.tasks["retry:" + str(analysis_id)] = asyncio.create_task(
            self._run_classification(event, capture_id, frame, audit)
        )

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
            decision["detected_type"] = original.get("detected_types", {}).get(item_id)
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
