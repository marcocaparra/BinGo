"""HTTP lab: synthetic central, actual private camera protocol and AI cascade."""

import asyncio
import json
import time
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest

from app.camera_api import create_host_app
from app.vision_lab import create_vision_lab_app, CLASS, STUDENT
from app.services.vision import InternalVision
from test_camera import prepared
from test_camera_api import TOKEN
from test_vision import ControlledProvider, result
from app.services.controller import SimulationPlan
from app.dev_integration import DevConfigurationError

HEADERS = {"X-Totem-Request": "1"}
BASE = "/local/simulation/sessions"


@pytest.fixture
def lab(monkeypatch, tmp_path):
    data = tmp_path / "vision-data"
    token = tmp_path / "camera-token"
    token.write_text(TOKEN)
    monkeypatch.setenv("BINGO_VISION_LAB_CONTEXT", "test")
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(data / "simulation.sqlite3"))
    monkeypatch.setenv("BINGO_CAMERA_MODE", "remote")
    monkeypatch.setenv("BINGO_CAMERA_URL", "http://127.0.0.1:8766")
    monkeypatch.setenv("BINGO_CAMERA_TOKEN_FILE", str(token))
    manager, driver = asyncio.run(prepared(tmp_path))
    host = create_host_app(manager=manager, token=TOKEN)
    host.state.camera, host.state.camera_token = manager, TOKEN
    primary = ControlledProvider(result())
    app = create_vision_lab_app(
        data_directory=data,
        camera_transport=httpx.ASGITransport(app=host),
        vision=InternalVision(primary, None),
    )
    with TestClient(app, base_url="http://127.0.0.1") as client:
        client.app.state.controller._plans = {
            op: SimulationPlan(duration_seconds=0.01)
            for op in client.app.state.controller._plans
        }
        yield client, driver, primary, data
    asyncio.run(manager.aclose())


def post(client, path, body):
    response = client.post(path, json=body, headers=HEADERS)
    assert response.status_code in {200, 202}, response.text
    return response.json()


def poll(client, event, states):
    for _ in range(100):
        value = client.get(f"{BASE}/{event}").json()
        if value["session"]["state"] in states:
            return value
        time.sleep(0.01)
    raise AssertionError("Expected durable state not reached")


def identified(client):
    value = post(client, BASE, {"command_id": str(uuid4())})
    event = value["session"]["event_id"]
    post(
        client,
        f"/local/dev/sessions/{event}/identity",
        {"class_id": CLASS, "student_id": STUDENT, "pin": "0012"},
    )
    post(client, f"{BASE}/{event}/safety", {"has_risk": False})
    post(
        client,
        f"{BASE}/{event}/open",
        {"mechanical_command_id": str(uuid4()), "pin": "0012"},
    )
    poll(client, event, {"DOOR_OPEN"})
    return event


def test_close_explicitly_coordinates_capture_and_review_without_browser_get(lab):
    client, driver, provider, data = lab
    event = identified(client)
    assert not provider.calls and driver.calls == 0
    command = str(uuid4())
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": command, "hand_removed": True},
    )
    # No browser polling is required to initiate or complete analysis.
    time.sleep(0.15)
    snap = poll(client, event, {"REVIEW"})
    assert snap["vision"]["close_command_id"] == command
    assert driver.calls == driver.released == len(provider.calls) == 1
    assert provider.calls[0][0].content == driver.content
    for _ in range(3):
        assert client.get(f"{BASE}/{event}").json() == snap
    body = {
        "capture_id": snap["vision"]["capture_id"],
        "item_id": "cable",
        "action": "confirm",
    }
    reviewed = post(client, f"{BASE}/{event}/vision-review", body)
    assert post(client, f"{BASE}/{event}/vision-review", body) == reviewed
    assert "hatch" in reviewed["allowed_actions"]
    # Even a mechanically complete simulated cycle cannot create an economic event.
    hatch_id = str(uuid4())
    post(
        client,
        f"{BASE}/{event}/hatch",
        {"mechanical_command_id": hatch_id, "pin": "0012"},
    )
    final = poll(client, event, {"COMPLETED"})
    assert final["session"]["receipt"] is None
    assert len(final["commands"]) == 4
    assert len(provider.calls) == driver.calls == 1
    assert all(c["source"] == "SIMULATED" for c in final["commands"])
    # Durable review permits an authenticated replay after completion, while the
    # existing mechanical journal prevents another movement/initial confirmation.
    assert (
        post(
            client,
            f"{BASE}/{event}/hatch",
            {"mechanical_command_id": hatch_id, "pin": "0012"},
        )
        == final
    )
    assert len(provider.calls) == driver.calls == 1


@pytest.mark.parametrize("item", ["arbitrary", "phone"])
def test_http_review_rejects_unoffered_candidates(lab, item):
    client, driver, provider, data = lab
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    snap = poll(client, event, {"REVIEW"})
    response = client.post(
        f"{BASE}/{event}/vision-review",
        json=dict(
            capture_id=snap["vision"]["capture_id"], item_id=item, action="correct"
        ),
        headers=HEADERS,
    )
    assert response.status_code == 422
    assert client.get(f"{BASE}/{event}").json()["vision"]["decision"] is None
    assert (
        client.post(
            f"{BASE}/{event}/hatch",
            json=dict(mechanical_command_id=str(uuid4()), pin="0012"),
            headers=HEADERS,
        ).status_code
        == 409
    )


@pytest.mark.parametrize(
    "prefix", ["AWS_ACCESS_KEY_ID", "GEMINI_API_KEY", "BINGO_SUPABASE_URL"]
)
def test_lab_refuses_ambient_credentials(monkeypatch, tmp_path, prefix):
    monkeypatch.setenv("BINGO_VISION_LAB_CONTEXT", "test")
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(tmp_path / "simulation.sqlite3"))
    monkeypatch.setenv(prefix, "not-a-real-credential")
    with pytest.raises(DevConfigurationError):
        create_vision_lab_app(data_directory=tmp_path)
