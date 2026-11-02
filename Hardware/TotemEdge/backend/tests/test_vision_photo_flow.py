"""One photo, explicit analysis, read-only DEV broker and durable recovery."""

import json
from uuid import uuid4

import httpx2 as httpx
import pytest
from fastapi.testclient import TestClient

from app.vision_lab import create_vision_dev_app
from app.dev_integration import ALLOWED
from app.services.vision import InternalVision
from app.simulation import (
    reject_simulation_in_operational,
    SimulationConfigurationError,
)
from test_vision import ControlledProvider, result
from test_vision_lab import lab, post, poll, identified, BASE, HEADERS
from test_dev_integration import dev_environment
from dev_data import CONTEXT, PIN


def test_photo_is_shown_once_and_only_explicit_action_analyzes(lab):
    client, driver, provider, data = lab
    client.app.state.simulation_flow.vision.deferred_analysis = True
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    snap = poll(client, event, {"CAPTURING"})
    # Capture can still be pending while the snapshot is already CAPTURING.
    import time

    for _ in range(100):
        snap = client.get(f"{BASE}/{event}").json()
        if snap["vision"]["image_available"]:
            break
        time.sleep(0.01)
    assert snap["allowed_actions"] == ["vision-analyze"]
    identifier = snap["vision"]["capture_id"]
    image = f"{BASE}/{event}/vision-image/{identifier}"
    assert client.get(image).status_code == 403
    for _ in range(3):
        response = client.get(image, headers=HEADERS)
        assert response.status_code == 200 and response.content == driver.content
        assert response.headers["cache-control"] == "no-store"
        assert client.get(f"{BASE}/{event}").json() == snap
    assert driver.calls == 1 and not provider.calls
    assert (
        client.get(
            image, headers={**HEADERS, "Origin": "https://untrusted.invalid"}
        ).status_code
        == 403
    )
    assert (
        client.post(
            f"{BASE}/{event}/vision-analyze",
            headers=HEADERS,
            json={"capture_id": str(uuid4())},
        ).status_code
        == 409
    )
    for _ in range(2):
        post(client, f"{BASE}/{event}/vision-analyze", {"capture_id": identifier})
    reviewed = poll(client, event, {"REVIEW"})
    assert len(provider.calls) == 1 and driver.calls == driver.released == 1
    assert client.get(image, headers=HEADERS).status_code == 410
    assert reviewed["session"]["receipt"] is None
    with client.app.state.simulation_flow.store.transaction() as conn:
        assert tuple(
            conn.execute(
                "SELECT physical_confirmed,payload,receipt FROM cycles"
            ).fetchone()
        ) == (0, None, None)


def test_vision_dev_uses_existing_broker_without_synthetic_identity_fallback(
    dev_environment, monkeypatch
):
    directory, policy, key = dev_environment
    monkeypatch.setenv("BINGO_DEV_CONTEXT", "")
    monkeypatch.setenv("BINGO_DEV_PLANS", "")
    monkeypatch.setenv("BINGO_VISION_LAB_CONTEXT", "test")
    requests = []
    unavailable = False

    def broker(request):
        nonlocal unavailable
        requests.append((request.method, request.url.path))
        assert (request.method, request.url.path) in ALLOWED
        assert str(request.url).startswith("http://dev-central:8000/")
        assert request.headers["X-Totem-Dev"] == "1"
        assert "X-Api-Key" not in request.headers
        if unavailable:
            return httpx.Response(503, json={})
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200,
                json=dict(
                    status="AVAILABLE",
                    can_start_deposit=True,
                    scope="CENTRAL_BACKEND",
                    checked_at="2026-11-01T00:00:00Z",
                ),
            )
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=CONTEXT)
        assert json.loads(request.content) == PIN
        return httpx.Response(
            200,
            json=dict(
                confirmed=True,
                student={
                    k: CONTEXT["students"][0][k]
                    for k in ("id", "name", "class_id", "class_name")
                },
            ),
        )

    app = create_vision_dev_app(
        data_directory=directory,
        policy_path=policy,
        transport=httpx.MockTransport(broker),
        vision=InternalVision(ControlledProvider(result()), None),
    )
    with TestClient(app, base_url="http://127.0.0.1") as client:
        assert client.get("/local/dev/context").json() == CONTEXT
        event = post(client, BASE, {"command_id": str(uuid4())})["session"]["event_id"]
        identified = post(client, f"/local/dev/sessions/{event}/identity", PIN)
        assert identified["session"]["student_name"] == CONTEXT["students"][0]["name"]
        assert identified["session"]["state"] == "SAFETY"
        before = len(requests)
        unavailable = True
        assert client.get(f"{BASE}/{event}").json() == identified
        assert len(requests) == before
        assert client.get("/local/dev/context").status_code == 503
        assert (
            client.post("/local/sessions", json={}, headers=HEADERS).status_code == 404
        )
        assert identified["session"]["receipt"] is None
    with pytest.raises(SimulationConfigurationError):
        reject_simulation_in_operational(directory / "simulation.sqlite3")


def test_startup_recovery_of_unanalyzed_photo_blocks_without_recapture(lab):
    client, driver, provider, data = lab
    workflow = client.app.state.simulation_flow.vision
    workflow.deferred_analysis = True
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    import time

    for _ in range(100):
        snap = client.get(f"{BASE}/{event}").json()
        if (snap.get("vision") or {}).get("image_available"):
            break
        time.sleep(0.01)
    assert snap["vision"]["image_available"]
    capture_id = snap["vision"]["capture_id"]
    # Exercise the same SQLite recovery used by a restarted process. RAM pixels
    # are deliberately gone; the already consumed camera intent stays durable.
    workflow.frames.clear()
    workflow.store._recover()
    recovered = client.get(f"{BASE}/{event}").json()
    assert recovered["session"]["state"] == "TECHNICAL_FAILURE"
    assert recovered["vision"]["error_code"] == "PROCESS_INTERRUPTED"
    assert not recovered["vision"]["image_available"]
    assert recovered["allowed_actions"] == ["cancel"]
    assert (
        client.get(
            f"{BASE}/{event}/vision-image/{capture_id}", headers=HEADERS
        ).status_code
        == 410
    )
    post(client, f"{BASE}/{event}/vision-analyze", {"capture_id": capture_id})
    assert client.get(f"{BASE}/{event}").json() == recovered
    assert driver.calls == driver.released == 1 and not provider.calls


def test_automatic_analysis_keeps_exact_photo_for_confirmation(lab):
    client, driver, provider, data = lab
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    snap = poll(client, event, {"REVIEW"})
    capture = snap["vision"]["capture_id"]
    assert snap["vision"]["image_available"]
    for _ in range(3):
        photo = client.get(f"{BASE}/{event}/vision-image/{capture}", headers=HEADERS)
        assert photo.status_code == 200 and photo.content == driver.content
        assert client.get(f"{BASE}/{event}").json() == snap
    assert driver.calls == driver.released == len(provider.calls) == 1
    assert provider.calls[0][0].content == photo.content
    post(client, f"{BASE}/{event}/vision-analyze", {"capture_id": capture})
    assert len(provider.calls) == 1
    post(
        client,
        f"{BASE}/{event}/vision-review",
        {"capture_id": capture, "item_id": "cable", "action": "confirm"},
    )
    post(
        client,
        f"{BASE}/{event}/hatch",
        {"mechanical_command_id": str(uuid4()), "pin": "0012"},
    )
    done = poll(client, event, {"COMPLETED"})
    assert done["session"]["receipt"] is None
    assert str(event) not in client.app.state.simulation_flow.vision.frames
