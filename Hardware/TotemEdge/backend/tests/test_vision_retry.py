"""Explicit analysis intents reuse RAM pixels; no camera/cloud/economy calls."""

import asyncio
import json
from uuid import uuid4

import pytest
from app.services.vision import VisionError
from test_vision import result, ControlledProvider
from test_vision_lab import lab, identified, post, poll, BASE, HEADERS


def failed_analysis(lab, code="PRIMARY_UNAVAILABLE"):
    client, driver, provider, _ = lab
    provider.answer = VisionError(code)
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {
            "mechanical_command_id": str(uuid4()),
            "hand_removed": True,
        },
    )
    failed = poll(client, event, {"TECHNICAL_FAILURE"})
    return event, failed


@pytest.mark.parametrize("code", ["PRIMARY_UNAVAILABLE", "VISION_BUSY"])
def test_same_photo_retry_audits_failures_and_preserves_pin_gate(lab, code):
    client, driver, provider, _ = lab
    event, failed = failed_analysis(lab, code)
    capture = failed["vision"]["capture_id"]
    image = client.get(
        f"{BASE}/{event}/vision-image/{capture}", headers=HEADERS
    ).content
    retry = {"capture_id": capture, "analysis_attempt_id": str(uuid4())}
    post(client, f"{BASE}/{event}/vision-analyze", retry)
    again = poll(client, event, {"TECHNICAL_FAILURE"})
    assert len(provider.calls) == 2
    # A lost response/repeated request never repeats a consumed intent.
    post(client, f"{BASE}/{event}/vision-analyze", retry)
    assert len(provider.calls) == 2
    assert (
        again["vision"]["analysis_history"][0]["previous_attempt"]["error_code"] == code
    )
    provider.answer = {
        **result(),
        "itemId": "small",
        "candidateIds": ["small"],
        "detected_types": {"small": "Headphones"},
    }
    second = {**retry, "analysis_attempt_id": str(uuid4())}
    post(client, f"{BASE}/{event}/vision-analyze", second)
    ready = poll(client, event, {"REVIEW"})
    post(client, f"{BASE}/{event}/vision-analyze", second)
    assert len(provider.calls) == 3 and driver.calls == 1
    assert all(call[0].content == image for call in provider.calls)
    assert ready["vision"]["capture_id"] == capture
    assert ready["commands"] == failed["commands"]
    assert ready["identity"] == failed["identity"]
    assert len(ready["vision"]["analysis_history"]) == 2
    assert ready["vision"]["provenance"]["analysis_id"] == second["analysis_attempt_id"]
    decision = post(
        client,
        f"{BASE}/{event}/vision-review",
        {"capture_id": capture, "item_id": "small", "action": "confirm"},
    )
    assert decision["vision"]["decision"]["detected_type"] == "Headphones"
    assert "hatch" in decision["allowed_actions"] and len(decision["commands"]) == 2
    for pin, status in [(None, 401), ("9999", 401)]:
        body = {"mechanical_command_id": str(uuid4())}
        if pin is not None:
            body["pin"] = pin
        assert (
            client.post(f"{BASE}/{event}/hatch", json=body, headers=HEADERS).status_code
            == status
        )
    assert len(client.get(f"{BASE}/{event}").json()["commands"]) == 2
    assert decision["session"]["receipt"] is None


@pytest.mark.parametrize(
    "unsafe", ["missing_photo", "pending_motion", "physical", "wrong_close"]
)
def test_retry_blocks_missing_pixels_or_unsafe_mechanics(lab, unsafe):
    client, _, provider, _ = lab
    event, failed = failed_analysis(lab)
    flow = client.app.state.simulation_flow
    if unsafe == "missing_photo":
        flow.vision.frames.clear()
    else:
        with flow.store.transaction() as conn:
            if unsafe == "pending_motion":
                conn.execute(
                    "UPDATE mechanical_commands SET phase='ACCEPTED',result='PENDING',active_slot=1 WHERE operation='CLOSE_INSERTION_DOOR'"
                )
            elif unsafe == "physical":
                conn.execute(
                    "UPDATE cycles SET physical_confirmed=1 WHERE event_id=?", (event,)
                )
            else:
                conn.execute(
                    "UPDATE vision_attempts SET close_command_id=(SELECT mechanical_command_id FROM mechanical_commands WHERE event_id=? AND operation='OPEN_INSERTION_DOOR') WHERE event_id=?",
                    (event, event),
                )
    current = client.get(f"{BASE}/{event}").json()
    assert "vision-analyze" not in current["allowed_actions"]
    response = client.post(
        f"{BASE}/{event}/vision-analyze",
        headers=HEADERS,
        json={
            "capture_id": failed["vision"]["capture_id"],
            "analysis_attempt_id": str(uuid4()),
        },
    )
    assert response.status_code == 409
    assert len(provider.calls) == 1
    if unsafe == "missing_photo":
        ended = post(client, f"{BASE}/{event}/cancel", {})
        assert ended["session"]["state"] == "CANCELLED"
        fresh = post(client, BASE, {"command_id": str(uuid4())})
        assert fresh["session"]["event_id"] != event


def test_concurrent_retry_reserves_once_and_restart_never_reclassifies(lab):
    client, driver, provider, _ = lab
    event, failed = failed_analysis(lab)

    async def blocked(frame, candidates):
        provider.calls.append((frame, candidates))
        await asyncio.Event().wait()

    provider.analyze = blocked
    body = {
        "capture_id": failed["vision"]["capture_id"],
        "analysis_attempt_id": str(uuid4()),
    }
    post(client, f"{BASE}/{event}/vision-analyze", body)
    assert client.get(f"{BASE}/{event}").json()["session"]["state"] == "CLASSIFYING"
    post(client, f"{BASE}/{event}/vision-analyze", body)
    assert (
        client.post(
            f"{BASE}/{event}/vision-analyze",
            headers=HEADERS,
            json={**body, "analysis_attempt_id": str(uuid4())},
        ).status_code
        == 409
    )
    flow = client.app.state.simulation_flow
    # Simulate process loss at a persisted reservation, then startup recovery.
    client.portal.call(flow.vision.aclose)
    flow.vision.frames.clear()
    with flow.store.transaction() as conn:
        # Abrupt death can leave the reservation pending instead of aclose's error.
        conn.execute(
            "UPDATE vision_attempts SET phase='CLASSIFYING' WHERE event_id=?", (event,)
        )
        conn.execute("UPDATE cycles SET state='CLASSIFYING' WHERE event_id=?", (event,))
    flow.store._recover()
    snapshot = client.get(f"{BASE}/{event}").json()
    assert snapshot["session"]["state"] == "TECHNICAL_FAILURE"
    assert "vision-analyze" not in snapshot["allowed_actions"]
    post(client, f"{BASE}/{event}/vision-analyze", body)
    assert len(provider.calls) == 2 and driver.calls == 1
    assert len(snapshot["vision"]["analysis_history"]) == 1


def test_secondary_timeout_keeps_primary_observation_in_archived_attempt(lab):
    client, driver, provider, _ = lab
    provider.answer = result("needs-secondary")
    client.app.state.simulation_flow.vision.capture.vision.secondary = (
        ControlledProvider(VisionError("VISION_TIMEOUT"))
    )
    event = identified(client)
    post(
        client,
        f"{BASE}/{event}/close",
        {
            "mechanical_command_id": str(uuid4()),
            "hand_removed": True,
        },
    )
    failed = poll(client, event, {"TECHNICAL_FAILURE"})
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
    previous = ready["vision"]["analysis_history"][0]["previous_attempt"]
    assert previous["error_code"] == "VISION_TIMEOUT"
    assert (
        json.loads(previous["provenance"])["observations"]
        == failed["vision"]["provenance"]["observations"]
    )
    assert driver.calls == 1 and len(provider.calls) == 2


def test_retry_identifier_cannot_be_reused_for_another_event(lab):
    client, driver, provider, _ = lab
    event, failed = failed_analysis(lab)
    intent = str(uuid4())
    post(
        client,
        f"{BASE}/{event}/vision-analyze",
        {
            "capture_id": failed["vision"]["capture_id"],
            "analysis_attempt_id": intent,
        },
    )
    poll(client, event, {"TECHNICAL_FAILURE"})
    post(client, f"{BASE}/{event}/cancel", {})
    fresh, failed = failed_analysis(lab)
    response = client.post(
        f"{BASE}/{fresh}/vision-analyze",
        headers=HEADERS,
        json={
            "capture_id": failed["vision"]["capture_id"],
            "analysis_attempt_id": intent,
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "ANALYSIS_ID_CONFLICT"
    assert len(provider.calls) == 3 and driver.calls == 2
