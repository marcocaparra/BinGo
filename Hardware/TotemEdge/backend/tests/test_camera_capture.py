"""Session capture needs durable closure, not screen state or client assertions."""

import asyncio
from uuid import uuid4

import pytest

from app.cycles import CycleError
from app.services.capture import CaptureService
from app.storage import CycleStore
from test_auto_initial import Rig
from test_camera import prepared
from test_sessions import seed_persisted_state
from app.mechanical import MechanicalCommand

pytestmark = pytest.mark.anyio


async def closed(rig):
    event = rig.flow.start(uuid4()).session.event_id
    rig.flow.safety(event, False)
    for operation in ("OPEN_INSERTION_DOOR", "CLOSE_INSERTION_DOOR"):
        command = MechanicalCommand(event_id=event, operation=operation)
        await rig.service.submit(
            command, hand_removed=operation == "CLOSE_INSERTION_DOOR"
        )
        await rig.clock.advance(1)
        await rig.service.wait(command.mechanical_command_id)
    return event


async def test_capture_after_journal_closure_once_and_no_classification(tmp_path):
    rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
    manager, driver = await prepared(tmp_path)
    driver.simulated = False  # Device pixels with a simulated door remain simulated.
    try:
        event = await closed(rig)
        service = CaptureService(rig.store, manager)
        frame = await service.capture_only(event, uuid4())
        assert frame.simulated  # Real pixels never upgrade simulated door evidence.
        assert rig.flow.get(event).session.state == "CAPTURING"
        assert rig.flow.get(event).session.receipt is None
        for _ in range(2):
            with pytest.raises(CycleError):
                await service.capture_only(event, uuid4())
        assert driver.calls == driver.released == 1
        assert len(rig.flow.get(event).commands) == 2
        with rig.store.transaction() as conn:
            row = conn.execute(
                "SELECT vision_result,receipt,physical_confirmed,payload FROM cycles"
            ).fetchone()
            assert tuple(row) == (None, None, 0, None)
    finally:
        await manager.aclose()
        await rig.close()


@pytest.mark.parametrize(
    "state",
    [
        "IDENTIFYING",
        "SAFETY",
        "PHYSICAL_BLOCKED",
        "DOOR_OPEN",
        "CLOSING",
        "DOOR_CLOSED",
    ],
)
async def test_state_without_journal_never_opens_camera(tmp_path, state):
    store = CycleStore(tmp_path / "cycles.sqlite3")
    event, _ = seed_persisted_state(store, state)
    manager, driver = await prepared(tmp_path)
    try:
        with pytest.raises(CycleError) as error:
            await CaptureService(store, manager).capture_only(event, uuid4())
        assert error.value.code == "DOOR_CLOSED_CONFIRMATION_REQUIRED"
        assert driver.calls == 0
    finally:
        await manager.aclose()
        store.close()


async def test_concurrent_session_capture_is_reserved_before_device_access(tmp_path):
    rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
    manager, driver = await prepared(tmp_path)
    driver.gate = asyncio.Event()
    try:
        event = await closed(rig)
        service = CaptureService(rig.store, manager)
        first = asyncio.create_task(service.capture_only(event, uuid4()))
        await driver.started.wait()
        with pytest.raises(CycleError):
            await service.capture_only(event, uuid4())
        driver.gate.set()
        await first
        assert driver.calls == 1
    finally:
        await manager.aclose()
        await rig.close()


async def test_restart_during_capture_blocks_recapture(tmp_path):
    rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
    manager, driver = await prepared(tmp_path)
    try:
        event = await closed(rig)
        await CaptureService(rig.store, manager).capture_only(event, uuid4())
        await rig.close()
        rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
        assert rig.flow.get(event).session.state == "INDETERMINATE"
        with pytest.raises(CycleError):
            await CaptureService(rig.store, manager).capture_only(event, uuid4())
        assert driver.calls == 1
    finally:
        await manager.aclose()
        await rig.close()


async def test_session_capture_failure_keeps_safe_failure_and_no_second_capture(
    tmp_path,
):
    rig = Rig(tmp_path / "cycles.sqlite3", auto=False)
    manager, driver = await prepared(tmp_path)
    driver.error = RuntimeError("synthetic camera disconnected")
    try:
        event = await closed(rig)
        service = CaptureService(rig.store, manager)
        from app.services.camera import CameraError

        with pytest.raises(CameraError):
            await service.capture_only(event, uuid4())
        assert rig.flow.get(event).session.state == "TECHNICAL_FAILURE"
        with pytest.raises(CycleError):
            await service.capture_only(event, uuid4())
        assert driver.calls == driver.released == 1
        assert rig.flow.get(event).session.receipt is None
    finally:
        await manager.aclose()
        await rig.close()
