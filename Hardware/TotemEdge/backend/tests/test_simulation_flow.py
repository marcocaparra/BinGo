"""Integração da máquina única: HTTP protegido, journal e sessão atômicos."""

import asyncio
import sqlite3
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
import pytest

from app.central_contracts import DepositPayload
from app.cycles import CycleError
from app.main import create_app
from app.mechanical import MechanicalCommand
from app.services.controller import SimulatedController, SimulationPlan
from app.simulation import SimulationSettings, create_simulation_app
from app.storage import CycleStore
from test_controller import ManualClock
from test_simulation import simulation_environment

BASE = "/local/simulation/sessions"
HEADERS = {"X-Totem-Request": "1"}


@pytest.fixture
def client_app(simulation_environment, monkeypatch):
    clock = ManualClock()
    monkeypatch.setenv("BINGO_SIMULATION_PLANS", "{}")
    monkeypatch.setattr(
        SimulationSettings,
        "build_controller",
        lambda self: SimulatedController(
            context="test", plans=self.plans, sleep=clock.sleep
        ),
    )
    app = create_simulation_app(data_directory=simulation_environment)
    with TestClient(app, base_url="http://127.0.0.1", headers=HEADERS) as client:
        yield client, app, clock
    assert not clock.pending


def start(client):
    key = str(uuid4())
    result = client.post(BASE, json={"command_id": key})
    assert result.status_code == 200
    body = result.json()
    assert body["source"] == "SIMULATED" and body["session"]["state"] == "SAFETY"
    event = body["session"]["event_id"]
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False}).status_code
        == 200
    )
    return event, key


def perform(client, app, clock, event, action, seconds, *, identifier=None):
    identifier = identifier or str(uuid4())
    payload = {"mechanical_command_id": identifier}
    if action == "close":
        payload["hand_removed"] = True
    result = client.post(f"{BASE}/{event}/{action}", json=payload)
    assert result.status_code == 202, result.text
    client.portal.call(clock.advance, seconds)
    client.portal.call(app.state.mechanical.wait, UUID(identifier))
    return client.get(f"{BASE}/{event}").json(), identifier, payload


def closed(client, app, clock):
    event, key = start(client)
    perform(client, app, clock, event, "open", 3.0)
    perform(client, app, clock, event, "close", 3.0)
    return event, key


def test_full_simulated_flow_has_no_economic_or_physical_confirmation(client_app):
    client, app, clock = client_app
    event, _ = start(client)
    snapshot, opening_id, _ = perform(client, app, clock, event, "open", 3.0)
    assert snapshot["session"]["state"] == "DOOR_OPEN"
    assert snapshot["allowed_actions"] == ["close"]
    snapshot, _, _ = perform(client, app, clock, event, "close", 3.0)
    assert snapshot["session"]["state"] == "DOOR_CLOSED"
    assert snapshot["session"]["hand_removed"] is True
    assert (
        client.post(f"{BASE}/{event}/review-fixture", json={}).json()["session"][
            "state"
        ]
        == "REVIEW"
    )
    snapshot, _, _ = perform(client, app, clock, event, "hatch", 4.0)
    assert snapshot["session"]["state"] == "HATCH_IN_PROGRESS"
    assert snapshot["allowed_actions"] == ["confirm-initial"]
    snapshot, _, _ = perform(client, app, clock, event, "confirm-initial", 1.0)
    assert snapshot["session"]["state"] == "COMPLETED"
    assert snapshot["session"]["receipt"] is None and snapshot["allowed_actions"] == []
    assert len(snapshot["commands"]) == 4
    assert all(
        c["source"] == "SIMULATED" and c["phase"] == "COMPLETED"
        for c in snapshot["commands"]
    )
    assert client.get(BASE + "/active").json() == {"snapshot": None}
    command = client.get(f"{BASE}/{event}/commands/{opening_id}").json()
    assert [h["phase"] for h in command["history"]] == [
        "INTENT",
        "DISPATCHING",
        "ACCEPTED",
        "COMPLETED",
    ]
    with app.state.sessions.store.transaction() as conn:
        assert tuple(
            conn.execute(
                "SELECT simulated,physical_confirmed,payload,receipt,central_scope,vision_result,active_slot FROM cycles"
            ).fetchone()
        ) == (1, 0, None, None, None, None, None)
        assert (
            conn.execute("SELECT count(*) FROM mechanical_history").fetchone()[0] == 16
        )
    assert client.get("/local/status").json()["can_start_deposit"] is False
    assert clock.calls == [3.0, 3.0, 4.0, 1.0]


@pytest.mark.parametrize(
    "action", ["open", "close", "hatch", "confirm-initial", "review-fixture"]
)
def test_invalid_stage_does_not_create_intent_or_move(client_app, action):
    client, app, _ = client_app
    event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
        "event_id"
    ]
    body = {} if action == "review-fixture" else {"mechanical_command_id": str(uuid4())}
    if action == "close":
        body["hand_removed"] = True
    assert client.post(f"{BASE}/{event}/{action}", json=body).status_code == 409
    assert not app.state.controller._responses
    assert client.get(f"{BASE}/{event}").json()["commands"] == []


def test_hatch_requires_explicit_review_fixture(client_app):
    client, app, clock = client_app
    event, _ = closed(client, app, clock)
    assert (
        client.post(
            f"{BASE}/{event}/hatch", json={"mechanical_command_id": str(uuid4())}
        ).status_code
        == 409
    )
    assert len(client.get(f"{BASE}/{event}").json()["commands"]) == 2


def test_acceptance_is_not_completion_and_refresh_does_not_dispatch(client_app):
    client, app, clock = client_app
    event, _ = start(client)
    identifier = str(uuid4())
    body = {"mechanical_command_id": identifier}
    snapshot = client.post(f"{BASE}/{event}/open", json=body).json()
    assert snapshot["session"]["state"] == "OPENING"
    assert snapshot["commands"][-1]["phase"] == "ACCEPTED"
    assert snapshot["allowed_actions"] == []
    for _ in range(3):
        assert client.get(f"{BASE}/{event}").json() == snapshot
        assert client.get(BASE + "/active").json()["snapshot"] == snapshot
        assert client.post(f"{BASE}/{event}/open", json=body).json() == snapshot
    assert len(app.state.controller._responses) == 1
    client.portal.call(clock.advance, 2.75)
    assert client.get(f"{BASE}/{event}").json()["session"]["state"] == "OPENING"
    client.portal.call(clock.advance, 0.25)
    client.portal.call(app.state.mechanical.wait, UUID(identifier))
    final = client.get(f"{BASE}/{event}").json()
    replay = client.post(f"{BASE}/{event}/open", json=body)
    assert replay.status_code == 200 and replay.json() == final
    assert (
        final["session"]["state"] == "DOOR_OPEN"
        and len(app.state.controller._responses) == 1
    )


def test_start_and_nonmechanical_decisions_are_idempotent(client_app):
    client, app, _ = client_app
    event, key = start(client)
    assert (
        client.post(BASE, json={"command_id": key}).json()["session"]["event_id"]
        == event
    )
    before = client.get(f"{BASE}/{event}").json()
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False}).json() == before
    )
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": True}).status_code
        == 409
    )
    assert client.post(BASE, json={"command_id": str(uuid4())}).status_code == 409
    with app.state.sessions.store.transaction() as conn:
        assert (
            conn.execute(
                "SELECT count(*) FROM transitions WHERE from_state='SAFETY'"
            ).fetchone()[0]
            == 1
        )


def test_conflicts_and_overlap_do_not_add_commands(client_app):
    client, app, _ = client_app
    event, _ = start(client)
    identifier = str(uuid4())
    assert (
        client.post(
            f"{BASE}/{event}/open", json={"mechanical_command_id": identifier}
        ).status_code
        == 202
    )
    for action, payload in [
        ("open", {"mechanical_command_id": identifier, "timeout_seconds": 20.0}),
        ("close", {"mechanical_command_id": identifier, "hand_removed": True}),
        ("open", {"mechanical_command_id": str(uuid4())}),
    ]:
        assert client.post(f"{BASE}/{event}/{action}", json=payload).status_code == 409
    assert len(app.state.controller._responses) == 1
    assert len(client.get(f"{BASE}/{event}").json()["commands"]) == 1


def test_concurrent_duplicate_actions_have_one_intent_and_one_transition(client_app):
    client, app, clock = client_app
    event, _ = start(client)
    identifier = uuid4()

    async def concurrent():
        return await asyncio.gather(
            *(
                app.state.simulation_flow.act(
                    UUID(event), "OPEN_INSERTION_DOOR", identifier, 10.0
                )
                for _ in range(8)
            )
        )

    entries = client.portal.call(concurrent)
    assert all(
        entry.command.mechanical_command_id == identifier for entry, _ in entries
    )
    assert len(app.state.controller._responses) == 1
    with app.state.sessions.store.transaction() as conn:
        assert (
            conn.execute("SELECT count(*) FROM mechanical_commands").fetchone()[0] == 1
        )
        assert (
            conn.execute("SELECT count(*) FROM mechanical_history").fetchone()[0] == 3
        )
        assert (
            conn.execute(
                "SELECT count(*) FROM transitions WHERE to_state='OPENING'"
            ).fetchone()[0]
            == 1
        )
    client.portal.call(clock.advance, 3.0)
    client.portal.call(app.state.mechanical.wait, identifier)


@pytest.mark.parametrize("value", [False, 1, "true", None])
def test_close_requires_strict_hand_declaration(client_app, value):
    client, _, _ = client_app
    event, _ = start(client)
    assert (
        client.post(
            f"{BASE}/{event}/close",
            json={"mechanical_command_id": str(uuid4()), "hand_removed": value},
        ).status_code
        == 422
    )


def test_journal_and_session_exist_before_dispatch_without_open_transaction(
    client_app, monkeypatch
):
    client, app, clock = client_app
    event, _ = start(client)
    original = app.state.controller.submit

    async def checked(command):
        with sqlite3.connect(
            app.state.sessions.store.path, isolation_level=None, timeout=0
        ) as conn:
            conn.execute("BEGIN IMMEDIATE")
            assert conn.execute("SELECT state FROM cycles").fetchone()[0] == "OPENING"
            assert (
                conn.execute("SELECT phase FROM mechanical_commands").fetchone()[0]
                == "DISPATCHING"
            )
            conn.rollback()
        return await original(command)

    monkeypatch.setattr(app.state.controller, "submit", checked)
    perform(client, app, clock, event, "open", 3.0)


def test_intent_and_moving_state_rollback_together(client_app):
    client, app, _ = client_app
    event, _ = start(client)
    with app.state.sessions.store.transaction() as conn:
        conn.execute(
            "CREATE TRIGGER break_cycle BEFORE INSERT ON transitions WHEN NEW.to_state='OPENING' BEGIN SELECT RAISE(ABORT,'injected'); END"
        )
    with pytest.raises(sqlite3.IntegrityError):
        client.post(
            f"{BASE}/{event}/open", json={"mechanical_command_id": str(uuid4())}
        )
    snapshot = client.get(f"{BASE}/{event}").json()
    assert (
        snapshot["session"]["state"] == "PHYSICAL_BLOCKED" and not snapshot["commands"]
    )
    assert not app.state.controller._responses


def test_completion_and_session_transition_rollback_together(client_app):
    client, app, clock = client_app
    event, _ = start(client)
    with app.state.sessions.store.transaction() as conn:
        conn.execute(
            "CREATE TRIGGER break_completion BEFORE INSERT ON transitions WHEN NEW.to_state='DOOR_OPEN' BEGIN SELECT RAISE(ABORT,'injected'); END"
        )
    identifier = str(uuid4())
    client.post(f"{BASE}/{event}/open", json={"mechanical_command_id": identifier})
    client.portal.call(clock.advance, 3.0)
    with pytest.raises(sqlite3.IntegrityError):
        client.portal.call(app.state.mechanical.wait, UUID(identifier))
    snapshot = client.get(f"{BASE}/{event}").json()
    assert (
        snapshot["session"]["state"] == "OPENING"
        and snapshot["commands"][-1]["phase"] == "ACCEPTED"
    )


@pytest.mark.parametrize(
    "outcome,phase", [("FAILURE", "FAILED"), ("TIMEOUT", "TIMED_OUT")]
)
@pytest.mark.parametrize(
    "action,operation",
    [("open", "OPEN_INSERTION_DOOR"), ("hatch", "CYCLE_LOWER_HATCH")],
)
def test_failures_unknown_block_and_never_retry(
    client_app, outcome, phase, action, operation
):
    client, app, clock = client_app
    if action == "hatch":
        event, _ = closed(client, app, clock)
        client.post(f"{BASE}/{event}/review-fixture", json={})
    else:
        event, _ = start(client)
    app.state.controller._plans[operation] = SimulationPlan(
        duration_seconds=1.0, outcome=outcome
    )
    identifier = str(uuid4())
    body = {"mechanical_command_id": identifier, "timeout_seconds": 2.0}
    assert client.post(f"{BASE}/{event}/{action}", json=body).status_code == 202
    client.portal.call(clock.advance, 2.0)
    client.portal.call(app.state.mechanical.wait, UUID(identifier))
    snapshot = client.get(f"{BASE}/{event}").json()
    assert (
        snapshot["session"]["state"] == "INDETERMINATE"
        and snapshot["allowed_actions"] == []
    )
    assert snapshot["commands"][-1]["phase"] == phase
    assert client.post(f"{BASE}/{event}/cancel", json={}).status_code == 409
    assert client.post(f"{BASE}/{event}/{action}", json=body).json() == snapshot
    assert (
        client.post(
            f"{BASE}/{event}/{action}", json={"mechanical_command_id": str(uuid4())}
        ).status_code
        == 409
    )
    assert (
        client.post(f"/local/sessions/{event}/retry-registration", json={}).status_code
        == 409
    )


def test_rejection_restores_stage_without_fabricating_completion(client_app):
    client, app, _ = client_app
    event, _ = start(client)
    app.state.controller._plans["OPEN_INSERTION_DOOR"] = SimulationPlan(
        duration_seconds=0.0, outcome="UNAVAILABLE"
    )
    result = client.post(
        f"{BASE}/{event}/open", json={"mechanical_command_id": str(uuid4())}
    )
    assert result.status_code == 200
    assert result.json()["session"]["state"] == "PHYSICAL_BLOCKED"
    assert result.json()["commands"][-1]["phase"] == "REJECTED"


@pytest.mark.parametrize("case", ["id", "event", "source"])
def test_inconsistent_completion_never_advances(client_app, monkeypatch, case):
    client, app, clock = client_app
    event, _ = start(client)
    original = app.state.controller.wait

    async def wrong(identifier):
        result = await original(identifier)
        if case == "source":
            return result.model_copy(update={"source": "PHYSICAL"})
        field = "mechanical_command_id" if case == "id" else "event_id"
        return result.model_copy(
            update={"command": result.command.model_copy(update={field: uuid4()})}
        )

    monkeypatch.setattr(app.state.controller, "wait", wrong)
    snapshot, _, _ = perform(client, app, clock, event, "open", 3.0)
    assert snapshot["session"]["state"] == "INDETERMINATE"
    assert snapshot["commands"][-1]["result"] == "UNKNOWN"


@pytest.mark.parametrize(
    "window", ["intent", "dispatch", "accepted", "received", "completed"]
)
def test_restart_boundaries_preserve_evidence_and_prevent_redispatch(
    simulation_environment, monkeypatch, window
):
    clock = ManualClock()
    monkeypatch.setenv("BINGO_SIMULATION_PLANS", "{}")
    monkeypatch.setattr(
        SimulationSettings,
        "build_controller",
        lambda self: SimulatedController(context="test", sleep=clock.sleep),
    )
    app = create_simulation_app(data_directory=simulation_environment)
    with TestClient(app, base_url="http://127.0.0.1", headers=HEADERS) as client:
        event, _ = start(client)
        command = MechanicalCommand(
            event_id=UUID(event), operation="OPEN_INSERTION_DOOR"
        )
        journal = app.state.sessions.store.mechanical
        entry, _ = journal.request(command, source="SIMULATED")
        if window != "intent":
            entry = journal.claim(command.mechanical_command_id, version=entry.version)
        if window in {"accepted", "received", "completed"}:
            response = client.portal.call(app.state.controller.submit, command)
            entry = journal.observe(
                command.mechanical_command_id, response, version=entry.version
            )
        if window in {"received", "completed"}:
            client.portal.call(clock.advance, 3.0)
            response = client.portal.call(
                app.state.controller.wait, command.mechanical_command_id
            )
            if window == "completed":
                journal.observe(
                    command.mechanical_command_id, response, version=entry.version
                )
    app2 = create_simulation_app(data_directory=simulation_environment)
    with TestClient(app2, base_url="http://127.0.0.1", headers=HEADERS) as client:
        snapshot = client.get(f"{BASE}/{event}").json()
        expected = (
            "PHYSICAL_BLOCKED"
            if window == "intent"
            else "DOOR_OPEN"
            if window == "completed"
            else "INDETERMINATE"
        )
        assert snapshot["session"]["state"] == expected
        assert snapshot["commands"][0]["phase"] == (
            "ABORTED"
            if window == "intent"
            else "COMPLETED"
            if window == "completed"
            else "INDETERMINATE"
        )
        assert (
            client.post(
                f"{BASE}/{event}/open",
                json={"mechanical_command_id": str(command.mechanical_command_id)},
            ).json()
            == snapshot
        )
        assert not app2.state.controller._responses


def test_closed_review_hatch_and_completed_survive_restart(
    client_app, simulation_environment
):
    client, app, clock = client_app
    event, _ = closed(client, app, clock)
    # A abertura de outro store seria recusada: testar recuperação sob a mesma
    # transação de startup sem fechar a lease controlada pelo TestClient.
    for state in ("DOOR_CLOSED", "REVIEW", "HATCH_IN_PROGRESS", "COMPLETED"):
        if state == "REVIEW":
            client.post(f"{BASE}/{event}/review-fixture", json={})
        elif state == "HATCH_IN_PROGRESS":
            perform(client, app, clock, event, "hatch", 4.0)
        elif state == "COMPLETED":
            perform(client, app, clock, event, "confirm-initial", 1.0)
        before = client.get(f"{BASE}/{event}").json()
        app.state.sessions.store._recover()
        assert client.get(f"{BASE}/{event}").json() == before


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"X-Totem-Request": "1", "Origin": "https://foreign.invalid"},
        {"X-Totem-Request": "1", "Host": "foreign.invalid"},
    ],
)
def test_mutations_preserve_local_boundary(client_app, headers):
    client, _, _ = client_app
    request = client.build_request("POST", BASE, json={"command_id": str(uuid4())})
    request.headers.pop("X-Totem-Request", None)
    request.headers.update(headers)
    assert client.send(request).status_code == 403


def test_http_input_host_origin_query_and_operational_absence(client_app):
    client, _, _ = client_app
    for headers in ({"Origin": "https://foreign.invalid"}, {"Host": "foreign.invalid"}):
        assert (
            client.post(
                BASE, json={"command_id": str(uuid4())}, headers=headers
            ).status_code
            == 403
        )
    assert client.get(BASE + "/active?pin=private-fixture").status_code == 422
    assert (
        client.post(
            BASE,
            json={
                "command_id": str(uuid4()),
                "physical_confirmed": True,
                "operation": "GPIO",
            },
        ).status_code
        == 422
    )
    assert not any(
        path.startswith("/local/simulation") for path in create_app().openapi()["paths"]
    )


def test_operational_runtime_does_not_mount_simulation_endpoints():
    with TestClient(
        create_app(), base_url="http://127.0.0.1", headers=HEADERS
    ) as client:
        assert client.post(BASE, json={"command_id": str(uuid4())}).status_code == 404
        assert client.get(BASE + "/active").status_code == 404
        assert client.get("/local/status").json()["can_start_deposit"] is False


def test_provenance_cannot_be_changed_and_simulated_payload_is_refused(client_app):
    client, app, clock = client_app
    event, _ = closed(client, app, clock)
    client.post(f"{BASE}/{event}/review-fixture", json={})
    store = app.state.sessions.store
    with pytest.raises(sqlite3.IntegrityError):
        with store.transaction() as conn:
            conn.execute("UPDATE cycles SET simulated=0")
    payload = DepositPayload(
        event_id=UUID(event),
        class_id=store.get(UUID(event)).class_id,
        student_id=None,
        is_valid=True,
        detected_type="cable",
        waste_category_code="CABLE_WIRE",
        category_source="AI_CONFIRMED",
    )
    with pytest.raises(CycleError):
        store.prepare_payload(UUID(event), payload)


def test_late_duplicate_and_cross_cycle_response_cannot_advance_session(client_app):
    from app.mechanical import ControllerError

    client, app, clock = client_app
    event, _ = start(client)
    _, identifier, _ = perform(client, app, clock, event, "open", 3.0)
    journal = app.state.sessions.store.mechanical
    final = journal.get(UUID(identifier))
    response = client.portal.call(app.state.controller.wait, UUID(identifier))
    snapshot = client.get(f"{BASE}/{event}").json()
    assert journal.observe(UUID(identifier), response, version=2) == final
    assert client.get(f"{BASE}/{event}").json() == snapshot
    wrong = response.model_copy(
        update={"command": response.command.model_copy(update={"event_id": uuid4()})}
    )
    with pytest.raises(ControllerError):
        journal.observe(UUID(identifier), wrong, version=2)
    assert client.get(f"{BASE}/{event}").json() == snapshot
    assert client.get(f"{BASE}/{uuid4()}/commands/{identifier}").status_code == 404


def test_unproven_hatch_cannot_be_confirmed(client_app):
    client, app, _ = client_app
    event, _ = start(client)
    with app.state.sessions.store.transaction() as conn:
        conn.execute("UPDATE cycles SET state='HATCH_IN_PROGRESS'")
    assert (
        client.post(
            f"{BASE}/{event}/confirm-initial",
            json={"mechanical_command_id": str(uuid4())},
        ).status_code
        == 409
    )
    assert not app.state.controller._responses


def test_cancellation_never_hides_moving_or_open_door(client_app):
    client, app, clock = client_app
    event, _ = start(client)
    identifier = str(uuid4())
    client.post(f"{BASE}/{event}/open", json={"mechanical_command_id": identifier})
    assert client.post(f"{BASE}/{event}/cancel", json={}).status_code == 409
    client.portal.call(clock.advance, 3.0)
    client.portal.call(app.state.mechanical.wait, UUID(identifier))
    assert client.post(f"{BASE}/{event}/cancel", json={}).status_code == 409
    assert (
        client.get(BASE + "/active").json()["snapshot"]["session"]["event_id"] == event
    )


def test_legacy_active_session_is_not_adopted_or_deleted(client_app):
    client, app, _ = client_app
    store = app.state.sessions.store
    legacy = store.create(uuid4(), "class_only", uuid4(), "Legacy 3A")
    assert client.get(BASE + "/active").status_code == 409
    assert client.get(f"{BASE}/{legacy.event_id}").status_code == 404
    assert client.post(BASE, json={"command_id": str(uuid4())}).status_code == 409
    assert store.get(legacy.event_id).state == "SAFETY"


@pytest.mark.anyio
async def test_ingress_preserves_host_origin_bytes():
    from app.simulation_proxy import pipe

    content = b"POST /local/simulation/sessions HTTP/1.1\r\nHost: foreign.invalid\r\nOrigin: https://foreign.invalid\r\n\r\n"
    reader = asyncio.StreamReader()
    reader.feed_data(content)
    reader.feed_eof()

    class Writer:
        def __init__(self):
            self.data = bytearray()

        def write(self, value):
            self.data.extend(value)

        async def drain(self):
            pass

        def can_write_eof(self):
            return True

        def write_eof(self):
            self.eof = True

    writer = Writer()
    await pipe(reader, writer)
    assert bytes(writer.data) == content and writer.eof


@pytest.mark.parametrize("old_version", [1, 2])
def test_real_legacy_schema_migrates_without_reclassifying_sessions(
    tmp_path, old_version
):
    path = tmp_path / "legacy.sqlite3"
    store = CycleStore(path)
    session = store.create(uuid4(), "class_only", uuid4(), "Legacy")
    store.close()
    with sqlite3.connect(path) as conn:
        conn.execute("DROP TRIGGER cycle_simulation_source_immutable")
        conn.execute("ALTER TABLE cycles DROP COLUMN simulated")
        if old_version == 1:
            conn.execute("DROP TABLE mechanical_history")
            conn.execute("DROP TABLE mechanical_commands")
        conn.execute(f"PRAGMA user_version={old_version}")
    migrated = CycleStore(path)
    try:
        with migrated.transaction() as conn:
            assert conn.execute("PRAGMA user_version").fetchone()[0] == 3
            assert conn.execute("SELECT simulated FROM cycles").fetchone()[0] == 0
        assert migrated.get(session.event_id).state == "CANCELLED"
    finally:
        migrated.close()
