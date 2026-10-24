"""Somente câmera/visão e guardas de estado lógico; sem controller de teste."""

import pytest
from uuid import uuid4

from app.cycles import CycleError
from app.services.capture import CaptureService, Frame, Observation, VisionResult
from app.storage import CycleStore
from test_sessions import CLASS, seed_persisted_state


class CameraFixture:
    def __init__(self, result):
        self.result = result
        self.captures = 0

    async def activate(self):
        pass

    async def deactivate(self):
        pass

    async def capture(self):
        self.captures += 1
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


class VisionFixture:
    def __init__(self, result):
        self.result = result
        self.calls = 0

    async def classify(self, frame):
        self.calls += 1
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


@pytest.mark.anyio
async def test_capture_before_closed_state_is_blocked(tmp_path):
    store = CycleStore(tmp_path / "camera.sqlite3")
    camera = CameraFixture(Frame(b"controlled-image", "image/png"))
    try:
        session = store.create(uuid4(), "class_only", CLASS, "Turma")
        with pytest.raises(CycleError):
            await CaptureService(
                store, camera, VisionFixture(None), stabilization_seconds=0
            ).analyze(session.event_id)
        assert camera.captures == 0
    finally:
        store.close()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "case",
    [
        "missing",
        "capture_failure",
        "empty",
        "simulated",
        "vision_failure",
        "simulated_vision",
        "inconclusive",
        "rejected",
    ],
)
async def test_capture_and_vision_fail_closed(tmp_path, case):
    store = CycleStore(tmp_path / "cases.sqlite3")
    # Linha persistida controlada, não confirmação produzida por equipamento.
    event_id, _ = seed_persisted_state(store, "DOOR_CLOSED")
    frame = Frame(b"controlled-image", "image/png", simulated=False)
    camera = CameraFixture(frame)
    result = VisionResult(
        status="recognized",
        itemId="cable",
        candidateIds=["cable"],
        confidence=0.9,
        origin="contract-fixture",
    )
    vision = VisionFixture(Observation(result, simulated=False))
    expected = "TECHNICAL_FAILURE"
    if case == "missing":
        camera = None
    elif case == "capture_failure":
        camera.result = RuntimeError("private-camera-error")
    elif case == "empty":
        camera.result = Frame(b"", "image/png")
    elif case == "simulated":
        camera.result = Frame(b"controlled-image", "image/png")
    elif case == "vision_failure":
        vision.result = RuntimeError("private-provider-error")
    elif case == "simulated_vision":
        vision.result = Observation(result)
    elif case == "inconclusive":
        vision.result = Observation(
            result.model_copy(update={"status": "needs-secondary"}), simulated=False
        )
    elif case == "rejected":
        vision.result = Observation(
            result.model_copy(
                update={"status": "rejected", "itemId": None, "candidateIds": []}
            ),
            simulated=False,
        )
        expected = "RETURN_REQUIRED"
    try:
        service = CaptureService(store, camera, vision, stabilization_seconds=0)
        if case == "rejected":
            await service.analyze(event_id)
        else:
            with pytest.raises(CycleError):
                await service.analyze(event_id)
        assert store.get(event_id).state == expected
        assert store.get(event_id).receipt is None
        assert store.active() is not None
        if case == "simulated":
            assert vision.calls == 0
        # Nenhuma devolução física nem registro é implementado nesse serviço.
    finally:
        store.close()


def test_hand_declaration_is_not_a_sensor_or_movement(tmp_path):
    store = CycleStore(tmp_path / "hand.sqlite3")
    try:
        event_id, _ = seed_persisted_state(store, "DOOR_OPEN")
        store.declare_hand_removed(event_id)
        assert store.get(event_id).hand_removed is True
        assert store.get(event_id).state == "DOOR_OPEN"
        with pytest.raises(CycleError):
            store.declare_hand_removed(event_id)
    finally:
        store.close()
