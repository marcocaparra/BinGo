"""Doorless DEV: explicit hand removal replaces both door operations."""

from uuid import uuid4

import pytest

from app.storage import CycleStore
import app.storage as storage
from test_vision_lab import lab, post, poll, BASE, CLASS, STUDENT, HEADERS


def ready(client):
    client.app.state.simulation_flow.doorless = True
    event = post(client, BASE, {"command_id": str(uuid4())})["session"]["event_id"]
    post(client, f"/local/dev/sessions/{event}/identity", {"class_id": CLASS, "student_id": STUDENT, "pin": "0012"})
    snap = post(client, f"{BASE}/{event}/safety", {"has_risk": False})
    assert snap["session"]["state"] == "INSERTION_READY"
    assert snap["allowed_actions"] == ["hand-removed"]
    assert snap["commands"] == []
    assert post(client, f"{BASE}/{event}/safety", {"has_risk": False}) == snap
    return event


def test_no_door_commands_and_no_capture_before_hand_confirmation(lab):
    client, driver, provider, _ = lab
    event = ready(client)
    assert driver.calls == 0 and not provider.calls
    for operation in ("open", "close"):
        body = {"mechanical_command_id": str(uuid4())}
        if operation == "close":
            body["hand_removed"] = True
        response = client.post(f"{BASE}/{event}/{operation}", headers=HEADERS, json=body)
        assert response.status_code == 410
    body = {"mechanical_command_id": str(uuid4()), "hand_removed": False}
    assert client.post(f"{BASE}/{event}/hand-removed", headers=HEADERS, json=body).status_code == 422
    assert driver.calls == 0
    body["hand_removed"] = True
    post(client, f"{BASE}/{event}/hand-removed", body)
    snap = poll(client, event, {"REVIEW"})
    assert driver.calls == driver.released == len(provider.calls) == 1
    assert snap["session"]["hand_removed"] is True
    assert [c["command"]["operation"] for c in snap["commands"]] == ["CONFIRM_HAND_REMOVED"]
    # Replayed POSTs do not recapture or simulate another movement.
    post(client, f"{BASE}/{event}/hand-removed", body)
    assert driver.calls == len(provider.calls) == 1
    assert "vision-recapture" in snap["allowed_actions"]
    new = post(client, f"{BASE}/{event}/vision-recapture", {"capture_id": snap["vision"]["capture_id"], "recapture_id": str(uuid4())})
    poll(client, event, {"REVIEW"})
    assert driver.calls == 2


def test_risky_item_never_reaches_insertion(lab):
    client, driver, _, _ = lab
    flow = client.app.state.simulation_flow
    flow.doorless = True
    event = post(client, BASE, {"command_id": str(uuid4())})["session"]["event_id"]
    post(client, f"/local/dev/sessions/{event}/identity", {"class_id": CLASS, "student_id": STUDENT, "pin": "0012"})
    snap = post(client, f"{BASE}/{event}/safety", {"has_risk": True})
    assert snap["session"]["state"] == "CANCELLED"
    assert client.post(f"{BASE}/{event}/hand-removed", headers=HEADERS, json={"mechanical_command_id": str(uuid4()), "hand_removed": True}).status_code == 409
    assert driver.calls == 0


def test_existing_database_is_upgraded_without_losing_history(tmp_path, monkeypatch):
    from app.mechanical import MechanicalCommand
    from app.services.simulation_flow import SimulationFlow
    from app.services.mechanical import MechanicalService
    from app.services.controller import SimulatedController
    schema = storage.MECHANICAL_SCHEMA
    with monkeypatch.context() as patch:
        patch.setattr(storage, "MECHANICAL_SCHEMA", tuple(s.replace(",'CONFIRM_HAND_REMOVED'", "") for s in schema))
        old = CycleStore(tmp_path / "cycles.sqlite3", simulation_enabled=True)
    # Preserve an immutable old journal entry and its history across migration.
    service = MechanicalService(old, SimulatedController(context="test"), source="SIMULATED")
    flow = SimulationFlow(old, service)
    event = flow.start(uuid4()).session.event_id
    flow.safety(event, False)
    command = MechanicalCommand(event_id=event, operation="OPEN_INSERTION_DOOR")
    old.mechanical.request(command, source="SIMULATED")
    with old.transaction() as conn:
        history = [tuple(r) for r in conn.execute("SELECT * FROM mechanical_history")]
    old.close()
    upgraded = CycleStore(tmp_path / "cycles.sqlite3", simulation_enabled=True)
    try:
        with upgraded.transaction() as conn:
            assert conn.execute("PRAGMA foreign_key_check").fetchone() is None
            assert "CONFIRM_HAND_REMOVED" in conn.execute("SELECT sql FROM sqlite_master WHERE name='mechanical_commands'").fetchone()[0]
            assert [tuple(r) for r in conn.execute("SELECT * FROM mechanical_history ORDER BY version")][:len(history)] == history
            assert conn.execute("SELECT mechanical_command_id FROM mechanical_commands").fetchone()[0] == str(command.mechanical_command_id)
    finally:
        upgraded.close()
