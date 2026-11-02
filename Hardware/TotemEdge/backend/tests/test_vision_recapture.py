"""Recapture over existing camera manager/cascade; disposable DB, no real devices."""

import asyncio
import json
import sqlite3
from types import SimpleNamespace
from uuid import uuid4

import pytest
from test_vision import result
from test_vision_lab import BASE, HEADERS, identified, poll, post
from test_vision_lab import lab as lab_fixture

from app.services.camera import CameraError
from app.services.capture import CaptureService
from app.services.session_vision import SessionVision
from app.services.vision import VisionError
from app.storage import CycleStore

lab = lab_fixture


def recognized(lab):
    client, _, _, _ = lab
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    return event, poll(client, event, {"REVIEW"})


@pytest.mark.parametrize("camera_fails", [False, True])
def test_rejected_photo_can_be_replaced_without_accepting_old_rejection(
    lab, camera_fails
):
    client, driver, provider, _ = lab
    provider.answer = {**result("rejected"), "candidateIds": [], "confidence": 0}
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    first = poll(client, event, {"RETURN_REQUIRED"})
    assert (
        first["vision"]["error_code"] is None
        and "vision-recapture" in first["allowed_actions"]
    )
    assert "vision-analyze" not in first["allowed_actions"]
    body = request(first)
    provider.answer = result()
    if camera_fails:
        driver.error = CameraError("CAMERA_CAPTURE_FAILED")
    post(client, f"{BASE}/{event}/vision-recapture", body)
    new = poll(client, event, {"RETURN_REQUIRED" if camera_fails else "REVIEW"})
    post(client, f"{BASE}/{event}/vision-recapture", body)
    assert (
        driver.calls == 2
        and new["session"]["event_id"] == event
        and new["commands"] == first["commands"]
    )
    assert new["session"]["receipt"] is None
    assert (
        new["vision"]["capture_history"][0]["previous_attempt"]["capture_id"]
        == first["vision"]["capture_id"]
    )
    if camera_fails:
        assert (
            "hatch" not in new["allowed_actions"]
            and "vision-review" not in new["allowed_actions"]
        )
        assert new["vision"]["observation"]["status"] == "rejected"
    else:
        assert new["vision"]["capture_id"] != first["vision"]["capture_id"]
        assert new["vision"]["observation"]["status"] == "recognized"


def request(snapshot):
    return {
        "capture_id": snapshot["vision"]["capture_id"],
        "recapture_id": str(uuid4()),
    }


def test_analysis_history_migrates_and_keeps_original_capture_on_recapture(lab):
    from test_vision_retry import failed_analysis

    client, driver, provider, _ = lab
    event, failed = failed_analysis(lab)
    provider.answer = result()
    post(
        client,
        f"{BASE}/{event}/vision-analyze",
        {
            "capture_id": failed["vision"]["capture_id"],
            "analysis_attempt_id": str(uuid4()),
        },
    )
    ready = poll(client, event, {"REVIEW"})
    store = client.app.state.simulation_flow.store
    with store.transaction() as conn:
        # Model an installed database before the historical FK correction.
        conn.execute("ALTER TABLE vision_analysis_retries RENAME TO retry_saved")
        conn.execute(
            "CREATE TABLE vision_analysis_retries (analysis_id TEXT PRIMARY KEY,event_id TEXT NOT NULL REFERENCES cycles(event_id),capture_id TEXT NOT NULL REFERENCES vision_attempts(capture_id),previous_attempt TEXT NOT NULL,created_at TEXT NOT NULL)"
        )
        conn.execute("INSERT INTO vision_analysis_retries SELECT * FROM retry_saved")
        conn.execute("DROP TABLE retry_saved")
        before = [
            tuple(r) for r in conn.execute("SELECT * FROM vision_analysis_retries")
        ]
    store._initialize()
    post(client, f"{BASE}/{event}/vision-recapture", request(ready))
    fresh = poll(client, event, {"REVIEW"})
    assert fresh["vision"]["capture_id"] != ready["vision"]["capture_id"]
    assert driver.calls == 2 and len(provider.calls) == 3
    with store.transaction() as conn:
        assert [
            tuple(r) for r in conn.execute("SELECT * FROM vision_analysis_retries")
        ] == before
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
    store._initialize()  # Migration replay must preserve history too.


def test_new_capture_analysis_same_session_replay_and_audit(lab):
    client, driver, provider, _ = lab
    event, first = recognized(lab)
    provider.answer = {**result(), "itemId": "phone", "candidateIds": ["phone"]}
    body = request(first)
    post(client, f"{BASE}/{event}/vision-recapture", body)
    second = poll(client, event, {"REVIEW"})
    assert second["vision"]["capture_id"] != first["vision"]["capture_id"]
    assert second["vision"]["observation"]["itemId"] == "phone"
    assert second["session"]["event_id"] == event
    assert (
        second["commands"] == first["commands"]
        and second["identity"] == first["identity"]
    )
    assert driver.calls == len(provider.calls) == 2
    assert (
        json.loads(
            second["vision"]["capture_history"][0]["previous_attempt"]["observation"]
        )
        == first["vision"]["observation"]
    )
    assert second["session"]["receipt"] is None
    for _ in range(3):
        post(client, f"{BASE}/{event}/vision-recapture", body)
        client.get(f"{BASE}/{event}")
    assert driver.calls == len(provider.calls) == 2
    assert (
        client.post(
            f"{BASE}/{uuid4()}/vision-recapture", headers=HEADERS, json=body
        ).status_code
        == 409
    )
    review = {
        "capture_id": second["vision"]["capture_id"],
        "item_id": "phone",
        "action": "confirm",
    }
    post(client, f"{BASE}/{event}/vision-review", review)
    assert (
        client.post(
            f"{BASE}/{event}/vision-recapture", headers=HEADERS, json=request(second)
        ).status_code
        == 409
    )
    post(
        client,
        f"{BASE}/{event}/hatch",
        {"mechanical_command_id": str(uuid4()), "pin": "0012"},
    )
    final = poll(client, event, {"COMPLETED"})
    assert (
        client.post(
            f"{BASE}/{event}/vision-recapture", headers=HEADERS, json=request(second)
        ).status_code
        == 409
    )
    post(
        client, f"{BASE}/{event}/vision-recapture", body
    )  # replay consumed intent is read-only
    assert (
        driver.calls == len(provider.calls) == 2 and final["session"]["receipt"] is None
    )


@pytest.mark.parametrize("failure", ["camera", "provider"])
def test_failure_retains_previous_classification_and_all_attempts(lab, failure):
    client, driver, provider, _ = lab
    event, first = recognized(lab)
    old_image = client.get(
        f"{BASE}/{event}/vision-image/{first['vision']['capture_id']}", headers=HEADERS
    ).content
    if failure == "camera":
        driver.error = CameraError("CAMERA_CAPTURE_FAILED")
    else:
        provider.answer = VisionError("PRIMARY_UNAVAILABLE")
    body = request(first)
    post(client, f"{BASE}/{event}/vision-recapture", body)
    restored = poll(client, event, {"REVIEW"})
    assert restored["vision"]["capture_id"] == first["vision"]["capture_id"]
    assert restored["vision"]["observation"] == first["vision"]["observation"]
    assert restored["vision"]["recapture_error"]
    assert (
        restored["vision"]["capture_history"][0]["result_attempt"]["phase"] == "FAILED"
    )
    assert (
        client.get(
            f"{BASE}/{event}/vision-image/{first['vision']['capture_id']}",
            headers=HEADERS,
        ).content
        == old_image
    )
    post(client, f"{BASE}/{event}/vision-recapture", body)
    assert driver.calls == 2
    driver.error = None
    provider.answer = result()
    post(client, f"{BASE}/{event}/vision-recapture", request(restored))
    ready = poll(client, event, {"REVIEW"})
    assert len(ready["vision"]["capture_history"]) == 2 and driver.calls == 3


def test_concurrent_intents_and_restart_never_repeat_capture(lab, tmp_path):
    client, driver, provider, _ = lab
    event, first = recognized(lab)
    flow = client.app.state.simulation_flow
    driver.gate = asyncio.Event()
    body = request(first)
    post(client, f"{BASE}/{event}/vision-recapture", body)
    post(client, f"{BASE}/{event}/vision-recapture", body)
    assert (
        client.post(
            f"{BASE}/{event}/vision-recapture", headers=HEADERS, json=request(first)
        ).status_code
        == 409
    )
    copied = tmp_path / "restarted.sqlite3"
    with sqlite3.connect(flow.store.path) as source, sqlite3.connect(copied) as dest:
        source.backup(dest)
    recovered = CycleStore(
        copied, simulation_enabled=True, identity_scope=flow.store.identity_scope
    )
    try:
        vision = SessionVision(
            CaptureService(recovered), SimpleNamespace(source="SIMULATED"), model="test"
        )
        vision.recover_unstarted()
        with recovered.transaction() as conn:
            snap = vision.snapshot(conn, event)
            assert snap["capture_id"] == first["vision"]["capture_id"]
            assert (
                snap["capture_history"][0]["result_attempt"]["error_code"]
                == "PROCESS_INTERRUPTED"
            )
            assert not snap["image_available"]
        assert recovered.get(event).state == "REVIEW"
    finally:
        recovered.close()
        client.portal.call(driver.gate.set)
    poll(client, event, {"REVIEW"})
    assert driver.calls == 2 and len(provider.calls) == 2


@pytest.mark.parametrize(
    "unsafe", ["hatch_intent", "physical", "open_door", "economic"]
)
def test_recapture_rejects_unsafe_or_economic_session(lab, unsafe):
    client, driver, provider, _ = lab
    event, first = recognized(lab)
    store = client.app.state.simulation_flow.store
    with store.transaction() as conn:
        if unsafe == "physical":
            conn.execute(
                "UPDATE cycles SET physical_confirmed=1 WHERE event_id=?", (event,)
            )
        elif unsafe == "open_door":
            conn.execute(
                "UPDATE cycles SET state='DOOR_OPEN' WHERE event_id=?", (event,)
            )
        elif unsafe == "economic":
            conn.execute("UPDATE cycles SET payload='{}' WHERE event_id=?", (event,))
        else:
            conn.execute(
                "INSERT INTO mechanical_commands VALUES(?,?, 'CYCLE_LOWER_HATCH',10,'SIMULATED','ABORTED','UNAVAILABLE',NULL,NULL,0,?,?)",
                (str(uuid4()), event, "2026-11-02T00:00:00Z", "2026-11-02T00:00:00Z"),
            )
    response = client.post(
        f"{BASE}/{event}/vision-recapture", headers=HEADERS, json=request(first)
    )
    assert response.status_code == 409 and driver.calls == len(provider.calls) == 1
