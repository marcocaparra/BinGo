"""Real pipeline composition, deterministic devices/providers, disposable SQLite."""

import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
from uuid import UUID, uuid4

import pytest

from app.cycles import CycleError
from app.services.capture import CaptureService, Frame
from app.services.session_vision import SessionVision, CATEGORIES
from app.services.vision import InternalVision, VisionError
from test_auto_initial import Rig
from test_camera import prepared
from test_camera_capture import closed
from test_vision import ControlledProvider, result

pytestmark = pytest.mark.anyio


async def setup(tmp_path, answer=None, secondary=None):
    rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
    manager, driver = await prepared(tmp_path)
    provider = ControlledProvider(answer if answer is not None else result())
    vision = InternalVision(provider, secondary)
    workflow = SessionVision(
        CaptureService(rig.store, manager, vision), rig.service, model="test-model"
    )
    rig.flow.vision = workflow
    event = await closed(rig)
    command = next(
        c.command.mechanical_command_id
        for c in rig.flow.get(event).commands
        if c.command.operation == "CLOSE_INSERTION_DOOR"
    )
    return rig, manager, driver, provider, workflow, event, command


async def cleanup(rig, manager, workflow):
    await workflow.aclose()
    await manager.aclose()
    await rig.close()


async def test_jpeg_to_existing_cascade_and_immutable_review_restart(tmp_path):
    args = await setup(tmp_path)
    rig, manager, driver, primary, workflow, event, command = args
    try:
        driver.simulated = False
        observed = await workflow.analyze(event, command)
        assert primary.calls[0][0].content == driver.content
        assert primary.calls[0][0].media_type == "image/jpeg"
        assert observed["provenance"]["camera"] == "DEVICE"
        assert observed["provenance"]["mechanical"] == "SIMULATED"
        assert observed["provenance"]["inference"] == "SIMULATED"
        assert rig.flow.get(event).allowed_actions == ["vision-review"]
        for _ in range(3):
            assert await workflow.analyze(event, command) == observed
        assert driver.calls == driver.released == len(primary.calls) == 1
        identifier = UUID(observed["capture_id"])
        workflow.review(event, identifier, "cable", "confirm")
        decision = rig.flow.get(event).vision["decision"]
        workflow.review(event, identifier, "cable", "confirm")
        assert rig.flow.get(event).vision["decision"] == decision
        with pytest.raises(CycleError, match="Operação"):
            workflow.review(event, identifier, "unknown", "correct")
        assert rig.flow.get(event).allowed_actions == ["hatch"]
        await rig.close()
        rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
        workflow = SessionVision(
            CaptureService(rig.store, manager, workflow.capture.vision),
            rig.service,
            model="test-model",
        )
        rig.flow.vision = workflow
        assert rig.flow.get(event).session.state == "REVIEW"
        assert rig.flow.get(event).vision["decision"] == decision
        assert (await workflow.analyze(event, command))["decision"] == decision
        with rig.store.transaction() as conn:
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt FROM cycles"
                ).fetchone()
            ) == (0, None, None)
            serialized = json.dumps(
                dict(conn.execute("SELECT * FROM vision_attempts").fetchone())
            )
            assert "base64" not in serialized and "content" not in serialized
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize("item", ["battery", "cable", "phone", "small", "unknown"])
async def test_candidate_correction_and_simulator_mapping(tmp_path, item):
    answer = result()
    answer["candidateIds"] = ["cable", "battery", "phone", "small"]
    answer["detected_types"] = {"small": "Computer Mouse"}
    rig, manager, driver, primary, workflow, event, command = await setup(
        tmp_path, answer
    )
    try:
        observed = await workflow.analyze(event, command)
        workflow.review(event, UUID(observed["capture_id"]), item, "correct")
        decision = rig.flow.get(event).vision["decision"]
        assert decision["category"] == CATEGORIES[item]
        assert decision["source"] == (
            "UNIDENTIFIED" if item == "unknown" else "USER_CORRECTED"
        )
        assert rig.flow.get(event).session.receipt is None
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize(
    "answer,state,secondary_calls",
    [
        (result(), "REVIEW", 0),
        (result("rejected"), "RETURN_REQUIRED", 0),
        (result("needs-secondary"), "REVIEW", 1),
        (VisionError("PRIMARY_UNAVAILABLE"), "TECHNICAL_FAILURE", 0),
        (VisionError("PRIMARY_TIMEOUT"), "TECHNICAL_FAILURE", 0),
    ],
)
async def test_provider_policy_and_rejection_block_hatch(
    tmp_path, answer, state, secondary_calls
):
    secondary = ControlledProvider(result(origin="GEMINI_FALLBACK"))
    rig, manager, driver, primary, workflow, event, command = await setup(
        tmp_path, answer, secondary
    )
    try:
        try:
            await workflow.analyze(event, command)
        except CycleError:
            assert isinstance(answer, VisionError)
        assert rig.flow.get(event).session.state == state
        assert len(secondary.calls) == secondary_calls
        if state != "REVIEW":
            assert rig.flow.get(event).allowed_actions == (
                ["cancel", "vision-analyze"]
                if isinstance(answer, VisionError)
                else ["cancel"]
            )
            with pytest.raises(CycleError):
                workflow.review(
                    event, workflow.identifier(command), "unknown", "correct"
                )
        with pytest.raises(CycleError):
            await rig.flow.act(event, "CYCLE_LOWER_HATCH", uuid4(), 10)
        with pytest.raises(CycleError):
            rig.flow.review_fixture(event)
        assert len(rig.flow.get(event).commands) == 2
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize(
    "secondary",
    [
        None,
        ControlledProvider(result("needs-secondary", origin="GEMINI_FALLBACK")),
        ControlledProvider(VisionError("SECONDARY_UNAVAILABLE")),
    ],
)
async def test_inconclusive_never_becomes_unknown_success(tmp_path, secondary):
    rig, manager, driver, primary, workflow, event, command = await setup(
        tmp_path, result("needs-secondary"), secondary
    )
    try:
        try:
            await workflow.analyze(event, command)
        except CycleError:
            pass
        snap = rig.flow.get(event)
        assert (
            snap.session.state == "TECHNICAL_FAILURE"
            and snap.vision["phase"] == "FAILED"
        )
        assert (
            snap.allowed_actions
            == (
                ["cancel", "vision-analyze"]
                if snap.vision["error_code"] == "SECONDARY_UNAVAILABLE"
                else ["cancel"]
            )
            and not snap.vision["allowed_candidates"]
        )
    finally:
        await cleanup(rig, manager, workflow)


async def test_concurrency_wrong_event_and_refresh_are_side_effect_free(tmp_path):
    rig, manager, driver, primary, workflow, event, command = await setup(tmp_path)
    driver.gate = asyncio.Event()
    try:
        with pytest.raises(CycleError):
            await workflow.analyze(event, uuid4())
        with pytest.raises(CycleError):
            await workflow.analyze(uuid4(), command)
        first = asyncio.create_task(workflow.analyze(event, command))
        await driver.started.wait()
        for _ in range(5):
            assert rig.flow.get(event).session.state == "CAPTURING"
            duplicate = await workflow.analyze(event, command)
            assert duplicate["phase"] == "CAPTURING"
        assert driver.calls == 1 and not primary.calls
        driver.gate.set()
        await first
        assert driver.calls == len(primary.calls) == 1
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize("stage", ["CAPTURING", "CLASSIFYING"])
async def test_abrupt_restart_marks_failure_without_recapture(tmp_path, stage):
    rig, manager, driver, primary, workflow, event, command = await setup(tmp_path)
    try:
        with rig.store.transaction() as conn:
            conn.execute(
                "INSERT INTO vision_attempts(capture_id,event_id,close_command_id,phase,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                (
                    str(workflow.identifier(command)),
                    str(event),
                    str(command),
                    stage,
                    "test",
                    "test",
                ),
            )
            rig.store._record(conn, rig.store._row(conn, event), stage)
        await rig.close()
        rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
        workflow = SessionVision(
            CaptureService(rig.store, manager, workflow.capture.vision),
            rig.service,
            model="test-model",
        )
        rig.flow.vision = workflow
        snap = rig.flow.get(event)
        assert snap.session.state == "TECHNICAL_FAILURE"
        assert snap.vision["error_code"] == "PROCESS_INTERRUPTED"
        await workflow.analyze(event, command)
        assert not primary.calls and driver.calls == 0
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize(
    "content,mime",
    [
        (b"", "image/jpeg"),
        (b"corrupt", "image/jpeg"),
        (b"x" * (5 * 1024 * 1024 + 1), "image/jpeg"),
        (b"abc", "text/plain"),
    ],
    ids=["empty", "corrupt", "oversize", "mime"],
)
async def test_invalid_image_never_reaches_provider(tmp_path, content, mime):
    rig, manager, driver, primary, workflow, event, command = await setup(tmp_path)

    async def invalid(identifier):
        return Frame(content, mime)

    workflow.capture.acquire = invalid
    try:
        with pytest.raises(CycleError):
            await workflow.analyze(event, command)
        assert not primary.calls
        assert rig.flow.get(event).session.state == "TECHNICAL_FAILURE"
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize("stage", ["CAPTURING", "CLASSIFYING", "SECONDARY"])
async def test_process_killed_during_vision_does_not_repeat_external_work(
    tmp_path, stage
):
    path, ready = tmp_path / "killed.db", tmp_path / "ready"
    old = Rig(path, auto=False)
    event = await closed(old)
    close_id = next(
        c.command.mechanical_command_id
        for c in old.flow.get(event).commands
        if c.command.operation == "CLOSE_INSERTION_DOOR"
    )
    await old.close()
    script = """
import asyncio, sys
from pathlib import Path
from uuid import UUID
from io import BytesIO
from PIL import Image
from app.storage import CycleStore
from app.services.controller import SimulatedController
from app.services.mechanical import MechanicalService
from app.services.capture import CaptureService, Frame
from app.services.session_vision import SessionVision
from app.services.vision import InternalVision
async def block():
    Path(sys.argv[2]).write_text('ready')
    await asyncio.Event().wait()
class Camera:
    async def activate(self): pass
    async def deactivate(self): pass
    async def capture(self, identifier):
        if sys.argv[5] == 'CAPTURING': await block()
        content = BytesIO()
        Image.new('RGB', (24, 18), 'green').save(content, format='JPEG')
        return Frame(content.getvalue(), 'image/jpeg')
class Provider:
    simulated=True
    async def analyze(self, frame, candidates):
        if sys.argv[5] == 'SECONDARY':
            return dict(status='needs-secondary', itemId=None, candidateIds=['cable'], confidence=0.5, origin='AWS_REKOGNITION')
        await block()
class Secondary:
    simulated=True
    async def analyze(self, frame, candidates): await block()
async def main():
    store=CycleStore(Path(sys.argv[1]), simulation_enabled=True)
    mechanical=MechanicalService(store, SimulatedController(context='test'), source='SIMULATED')
    workflow=SessionVision(CaptureService(store, Camera(), InternalVision(Provider(), Secondary())), mechanical, model='test')
    await workflow.analyze(UUID(sys.argv[3]), UUID(sys.argv[4]))
asyncio.run(main())
"""
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_"))
    }
    env["PYTHONPATH"] = os.pathsep.join(
        [str(Path(__file__).resolve().parent), *[p for p in sys.path if p]]
    )
    process = subprocess.Popen(
        [
            sys._base_executable,
            "-B",
            "-c",
            script,
            str(path),
            str(ready),
            str(event),
            str(close_id),
            stage,
        ],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    try:
        for _ in range(80):
            if ready.exists() or process.poll() is not None:
                break
            await asyncio.sleep(0.1)
        assert ready.exists(), "Owned vision process did not reach expected phase"
        process.kill()
        process.wait(timeout=5)
        restarted = Rig(path, auto=False)
        try:
            workflow = SessionVision(
                CaptureService(restarted.store), restarted.service, model="test"
            )
            restarted.flow.vision = workflow
            snap = restarted.flow.get(event)
            assert snap.session.state == "TECHNICAL_FAILURE"
            assert snap.vision["error_code"] == "PROCESS_INTERRUPTED"
            if stage == "SECONDARY":
                assert (
                    snap.vision["provenance"]["observations"][0]["status"]
                    == "needs-secondary"
                )
            assert (await workflow.analyze(event, close_id))["phase"] == "FAILED"
            assert not restarted.controller._responses
        finally:
            await restarted.close()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stderr.close()


async def test_camera_failure_releases_resources_and_never_calls_ai(tmp_path):
    rig, manager, driver, primary, workflow, event, command = await setup(tmp_path)
    driver.error = RuntimeError("private driver response")
    try:
        with pytest.raises(CycleError):
            await workflow.analyze(event, command)
        snapshot = rig.flow.get(event)
        assert snapshot.session.state == "TECHNICAL_FAILURE"
        assert snapshot.vision["error_code"] == "CAMERA_CAPTURE_FAILED"
        assert driver.calls == driver.released == 1 and not primary.calls
        assert "private" not in snapshot.model_dump_json()
        assert await workflow.analyze(event, command) == snapshot.vision
        assert driver.calls == 1
    finally:
        await cleanup(rig, manager, workflow)


async def test_failed_fallback_preserves_normalized_primary_observation(tmp_path):
    secondary = ControlledProvider(VisionError("SECONDARY_UNAVAILABLE"))
    rig, manager, driver, primary, workflow, event, command = await setup(
        tmp_path, result("needs-secondary"), secondary
    )
    try:
        with pytest.raises(CycleError):
            await workflow.analyze(event, command)
        snapshot = rig.flow.get(event)
        assert snapshot.vision["provenance"]["observations"] == [
            result("needs-secondary")
        ]
        assert snapshot.vision["error_code"] == "SECONDARY_UNAVAILABLE"
        assert (
            snapshot.allowed_actions == ["cancel", "vision-analyze"]
            and snapshot.session.receipt is None
        )
    finally:
        await cleanup(rig, manager, workflow)


async def test_successful_closure_from_another_event_never_authorizes_capture(tmp_path):
    rig, manager, driver, primary, workflow, old_event, old_command = await setup(
        tmp_path
    )
    try:
        # Fixture only: keep an older real synthetic journal for correlation,
        # with precisely one active session. No browser/database coupling.
        with rig.store.transaction() as conn:
            conn.execute(
                "UPDATE cycles SET active_slot=NULL WHERE event_id=?", (str(old_event),)
            )
        active_event = await closed(rig)
        with pytest.raises(CycleError):
            await workflow.analyze(active_event, old_command)
        with pytest.raises(CycleError):
            await workflow.analyze(old_event, old_command)
        assert driver.calls == 0 and not primary.calls
        assert rig.flow.get(active_event).session.state == "DOOR_CLOSED"
    finally:
        await cleanup(rig, manager, workflow)


async def test_restart_between_closure_and_capture_intent_blocks_without_camera(
    tmp_path,
):
    rig, manager, driver, primary, workflow, event, command = await setup(tmp_path)
    try:
        workflow.recover_unstarted()
        first = rig.flow.get(event)
        assert first.session.state == "TECHNICAL_FAILURE"
        assert first.vision["error_code"] == "CAPTURE_NOT_STARTED_AFTER_RESTART"
        workflow.recover_unstarted()
        assert rig.flow.get(event) == first
        await workflow.analyze(event, command)
        assert driver.calls == 0 and not primary.calls
    finally:
        await cleanup(rig, manager, workflow)


@pytest.mark.parametrize("specific", [None, "Fone de ouvido"])
async def test_legacy_size_is_not_an_item_class_and_audit_is_preserved(
    tmp_path, specific
):
    answer = result()
    answer.update(
        itemId="small",
        candidateIds=["small"],
        detected_types={"small": specific} if specific else {},
    )
    rig, manager, driver, primary, workflow, event, command = await setup(
        tmp_path, answer
    )
    try:
        observed = await workflow.analyze(event, command)
        if not specific:
            # An older pending journal stores only the coarse group. GET projects
            # UNKNOWN without rewriting the historical provider observation.
            with rig.store.transaction() as conn:
                conn.execute(
                    "UPDATE vision_attempts SET observation=? WHERE event_id=?",
                    (json.dumps(answer), str(event)),
                )
            assert rig.flow.get(event).vision["observation"]["itemId"] == "unknown"
        expected = "small" if specific else "unknown"
        assert observed["observation"]["itemId"] == expected
        assert observed["provenance"]["observations"][0]["itemId"] == "small"
        assert observed["provenance"]["provider"] == "AWS_REKOGNITION"
        workflow.review(event, UUID(observed["capture_id"]), expected, "confirm")
        decision = rig.flow.get(event).vision["decision"]
        assert decision["detected_type"] == specific
        if not specific:
            assert (
                decision["category"] == "UNKNOWN"
                and decision["source"] == "UNIDENTIFIED"
            )
    finally:
        await cleanup(rig, manager, workflow)
