"""Failed DEV tests end durably; no device, provider or hosted service used."""

import json
from uuid import uuid4

import pytest
from app.services.camera import CameraError
from app.services.vision import VisionError
from test_vision import result, ControlledProvider
from test_vision_lab import lab, identified, post, poll, BASE, HEADERS


@pytest.mark.parametrize("failure", ["camera", "vision"])
def test_consecutive_failed_tests_end_without_moves_or_reusing_intents(lab, failure):
    client, driver, provider, directory = lab
    if failure == "camera":
        driver.error = CameraError("CAMERA_DISCONNECTED")
    else:
        provider.answer = result("needs-secondary")
        client.app.state.simulation_flow.vision.capture.vision.secondary = (
            ControlledProvider(VisionError("VISION_TIMEOUT"))
        )
    previous = set()
    for _ in range(2):
        event = identified(client)
        post(
            client,
            f"{BASE}/{event}/close",
            {"mechanical_command_id": str(uuid4()), "hand_removed": True},
        )
        failed = poll(client, event, {"TECHNICAL_FAILURE"})
        capture = failed["vision"]["capture_id"]
        assert event not in previous and capture not in previous
        previous.update([event, capture])
        assert failed["allowed_actions"] == (
            ["cancel", "vision-analyze"] if failure == "vision" else ["cancel"]
        )
        if failure == "vision":
            assert failed["vision"]["error_code"] == "VISION_TIMEOUT"
            assert (
                failed["vision"]["provenance"]["observations"][0]["status"]
                == "needs-secondary"
            )
            image = client.get(
                f"{BASE}/{event}/vision-image/{capture}", headers=HEADERS
            )
            assert image.status_code == 200 and image.content == driver.content
        ended = post(client, f"{BASE}/{event}/cancel", {})
        assert ended["session"]["state"] == "CANCELLED"
        assert ended["session"]["failure_code"] == failed["session"]["failure_code"]
        assert ended["commands"] == failed["commands"]
        assert ended["vision"] == failed["vision"]
        assert post(client, f"{BASE}/{event}/cancel", {}) == ended
        assert client.get(f"{BASE}/active").json()["snapshot"] is None
        if failure == "vision":
            assert (
                client.get(
                    f"{BASE}/{event}/vision-image/{capture}", headers=HEADERS
                ).content
                == driver.content
            )
        with client.app.state.simulation_flow.store.transaction() as conn:
            assert (
                conn.execute(
                    "SELECT count(*) FROM transitions WHERE event_id=? AND code='SIMULATION_TEST_ENDED'",
                    (event,),
                ).fetchone()[0]
                == 1
            )
            assert (
                conn.execute(
                    "SELECT count(*) FROM mechanical_commands WHERE event_id=?",
                    (event,),
                ).fetchone()[0]
                == 2
            )
    driver.error = None
    provider.answer = result()
    fresh = identified(client)
    post(
        client,
        f"{BASE}/{fresh}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    ready = poll(client, fresh, {"REVIEW"})
    assert ready["session"]["receipt"] is None
    assert ready["vision"]["capture_id"] not in previous
    assert (
        client.get(
            f"{BASE}/{event}/vision-image/{capture}", headers=HEADERS
        ).status_code
        == 410
    )
    assert client.get(f"{BASE}/{event}").json()["vision"]["phase"] == "FAILED"


@pytest.mark.parametrize(
    "unsafe",
    ["pending_motion", "physical_evidence", "pending_vision", "physical_runtime"],
)
def test_failed_simulation_never_overrides_unsafe_or_physical_conditions(lab, unsafe):
    client, driver, provider, directory = lab
    provider.answer = VisionError("PRIMARY_UNAVAILABLE")
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {"mechanical_command_id": str(uuid4()), "hand_removed": True},
    )
    poll(client, event, {"TECHNICAL_FAILURE"})
    flow = client.app.state.simulation_flow
    with flow.store.transaction() as conn:
        if unsafe == "pending_motion":
            conn.execute(
                "UPDATE mechanical_commands SET phase='ACCEPTED',result='PENDING',active_slot=1 WHERE event_id=? AND operation='CLOSE_INSERTION_DOOR'",
                (event,),
            )
        if unsafe == "physical_evidence":
            conn.execute(
                "UPDATE cycles SET physical_confirmed=1 WHERE event_id=?", (event,)
            )
        if unsafe == "pending_vision":
            conn.execute(
                "UPDATE vision_attempts SET phase='CLASSIFYING' WHERE event_id=?",
                (event,),
            )
    if unsafe == "physical_runtime":
        flow.store.simulation_enabled = False
    response = client.post(f"{BASE}/{event}/cancel", json={}, headers=HEADERS)
    assert response.status_code in {404, 409}
    with flow.store.transaction() as conn:
        assert (
            conn.execute(
                "SELECT state FROM cycles WHERE event_id=?", (event,)
            ).fetchone()[0]
            != "CANCELLED"
        )
