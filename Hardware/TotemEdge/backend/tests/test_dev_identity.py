"""Identidade DEV durável, com broker/Functions sintéticos e nenhum segredo real."""

import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import json
import sqlite3
import threading
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest

from app.cycles import CycleError
from app.dev_integration import create_dev_app
from app.mechanical import MechanicalCommand
from app.storage import CycleStore
from test_dev_integration import (
    BASE,
    CLASS,
    CONTEXT,
    KEY,
    MACHINE,
    PIN,
    SCHOOL,
    STUDENT,
    connected,
    dev_environment,
)


def start(client, command_id=None):
    response = client.post(BASE, json={"command_id": str(command_id or uuid4())})
    assert response.status_code == 200
    return response.json()["session"]["event_id"]


def associate(client, event, body=None):
    return client.post(
        f"/local/dev/sessions/{event}/identity", json=PIN if body is None else body
    )


def counts(store):
    with store.transaction() as conn:
        return tuple(
            conn.execute(
                "SELECT (SELECT count(*) FROM simulation_identities),"
                "(SELECT count(*) FROM transitions WHERE code='DEV_IDENTITY_CONFIRMED'),"
                "(SELECT count(*) FROM mechanical_commands)"
            ).fetchone()
        )


def intercept(broker, handler):
    original = broker.app.state.central._http._transport.inner

    async def remote(request):
        response = await handler(request)
        return (
            response
            if response is not None
            else await original.handle_async_request(request)
        )

    broker.app.state.central._http._transport.inner = httpx.MockTransport(remote)


def test_identity_is_atomic_audited_and_start_replay_preserves_ids(connected):
    client, app, _, calls = connected
    command = uuid4()
    event = start(client, command)
    before = client.get(f"{BASE}/{event}").json()
    assert before["identity"] is None
    assert before["session"]["state"] == "IDENTIFYING"
    assert before["allowed_actions"] == ["identify", "cancel"]
    response = associate(client, event)
    assert response.status_code == 200
    snapshot = response.json()
    assert snapshot["identity"] == {
        "event_id": event,
        "project_ref": "ddxmohrjcxuibswmrtla",
        "machine_id": str(MACHINE),
        "school_id": str(SCHOOL),
        "class_id": str(CLASS),
        "student_id": str(STUDENT),
        "source": "SUPABASE_DEV_PIN_V1",
        "validated_at": snapshot["identity"]["validated_at"],
    }
    assert snapshot["session"]["state"] == "SAFETY"
    assert snapshot["session"]["class_id"] == str(CLASS)
    assert snapshot["session"]["student_id"] == str(STUDENT)
    assert snapshot["session"]["mode"] == "student"
    assert snapshot["allowed_actions"] == ["safety", "cancel"]
    assert counts(app.state.sessions.store) == (1, 1, 0)
    assert client.post(BASE, json={"command_id": str(command)}).json() == snapshot
    number = len(calls)
    assert associate(client, event).json() == snapshot
    assert len(calls) > number
    assert associate(client, event, {**PIN, "pin": "9999"}).status_code == 401
    assert client.get(f"{BASE}/{event}").json() == snapshot
    assert counts(app.state.sessions.store) == (1, 1, 0)


@pytest.mark.parametrize(
    "body,status",
    [
        ({**PIN, "pin": "9999"}, 401),
        ({**PIN, "student_id": str(uuid4())}, 403),
        ({**PIN, "class_id": str(uuid4())}, 403),
        ({**PIN, "pin": "123"}, 422),
        ({**PIN, "pin": 12}, 422),
        ({**PIN, "confirmed": True}, 422),
        ({**PIN, "school_id": str(SCHOOL)}, 422),
        ({**PIN, "machine_id": str(MACHINE)}, 422),
        ({**PIN, "physical_confirmed": True}, 422),
    ],
)
def test_invalid_identity_never_changes_cycle_or_writes_evidence(
    connected, body, status
):
    client, app, _, _ = connected
    event = start(client)
    before = client.get(f"{BASE}/{event}").json()
    response = associate(client, event, body)
    assert response.status_code == status
    assert client.get(f"{BASE}/{event}").json() == before
    assert counts(app.state.sessions.store) == (0, 0, 0)


@pytest.mark.parametrize(
    "change", ["inactive", "removed", "other_class", "other_school", "other_machine"]
)
def test_authorized_context_is_required_for_identity(connected, monkeypatch, change):
    client, app, _, _ = connected
    event = start(client)
    if change == "inactive":
        monkeypatch.setitem(CONTEXT["students"][0], "status", "INACTIVE")
    elif change == "removed":
        monkeypatch.setitem(CONTEXT, "students", [])
    elif change == "other_class":
        monkeypatch.setitem(CONTEXT["students"][0], "class_id", str(uuid4()))
    else:
        monkeypatch.setitem(
            CONTEXT["school" if change == "other_school" else "machine"],
            "id",
            str(uuid4()),
        )
    assert associate(client, event).status_code in {403, 502, 503}
    assert counts(app.state.sessions.store) == (0, 0, 0)


@pytest.mark.parametrize(
    "body",
    [
        {"confirmed": False},
        {"confirmed": "true"},
        {"confirmed": True, "student": {**CONTEXT["students"][0], "id": str(uuid4())}},
        {
            "confirmed": True,
            "student": {**CONTEXT["students"][0], "class_id": str(uuid4())},
        },
        {"confirmed": True, "student": None},
    ],
)
def test_inconsistent_central_pin_confirmation_is_rejected(connected, body):
    client, app, broker, _ = connected

    async def handler(request):
        if request.url.path.endswith("totem-student-pin-v1"):
            return httpx.Response(200, json=body)

    intercept(broker, handler)
    event = start(client)
    assert associate(client, event).status_code == 503
    assert counts(app.state.sessions.store) == (0, 0, 0)


@pytest.mark.parametrize(
    "failure", ["timeout", "network", "machine_auth", "pin_rejected"]
)
def test_remote_failure_after_context_does_not_bind(connected, failure):
    client, app, broker, _ = connected

    async def handler(request):
        if request.url.path.endswith("totem-student-pin-v1"):
            if failure == "timeout":
                raise httpx.ReadTimeout("synthetic", request=request)
            if failure == "network":
                raise httpx.ConnectError("synthetic", request=request)
            return httpx.Response(
                401,
                json={
                    "error": {
                        "code": "STUDENT_PIN_INVALID"
                        if failure == "pin_rejected"
                        else "MACHINE_AUTHENTICATION_FAILED"
                    }
                },
            )

    intercept(broker, handler)
    event = start(client)
    assert associate(client, event).status_code == (
        401 if failure == "pin_rejected" else 503
    )
    assert client.get(f"{BASE}/{event}").json()["session"]["state"] == "IDENTIFYING"
    assert counts(app.state.sessions.store) == (0, 0, 0)


@pytest.mark.parametrize("different", [False, True])
def test_concurrent_remote_confirmations_have_one_atomic_winner(
    connected, monkeypatch, different
):
    client, app, broker, _ = connected
    other = str(uuid4())
    if different:
        monkeypatch.setitem(
            CONTEXT,
            "students",
            [*CONTEXT["students"], {**CONTEXT["students"][0], "id": other}],
        )
    arrived = 0
    barrier = asyncio.Event()

    async def handler(request):
        nonlocal arrived
        if request.url.path.endswith("totem-student-pin-v1"):
            arrived += 1
            if arrived == 2:
                barrier.set()
            await asyncio.wait_for(barrier.wait(), 5)

    intercept(broker, handler)
    event = start(client)
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(associate, client, event, body)
            for body in [PIN, {**PIN, "student_id": other} if different else PIN]
        ]
        responses = [future.result(timeout=10) for future in futures]
    assert sorted(r.status_code for r in responses) == (
        [200, 409] if different else [200, 200]
    )
    assert counts(app.state.sessions.store) == (1, 1, 0)
    winner = next(r for r in responses if r.status_code == 200).json()
    assert client.get(f"{BASE}/{event}").json() == winner


def test_cancel_while_remote_validates_prevents_late_association(connected):
    client, app, broker, _ = connected
    reached, release = threading.Event(), threading.Event()

    async def handler(request):
        if request.url.path.endswith("totem-student-pin-v1"):
            reached.set()
            assert await asyncio.to_thread(release.wait, 5)

    intercept(broker, handler)
    event = start(client)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(associate, client, event)
        try:
            assert reached.wait(5)
            # A transação não atravessa HTTP: outra conexão pode cancelar agora.
            assert client.post(f"{BASE}/{event}/cancel", json={}).status_code == 200
        finally:
            release.set()
        assert future.result(timeout=10).status_code == 409
    assert counts(app.state.sessions.store) == (0, 0, 0)
    assert associate(client, event).status_code == 409


@pytest.mark.parametrize("at", ["DEV_IDENTITY_VALIDATED", "DEV_IDENTITY_CONFIRMED"])
def test_local_commit_failure_rolls_back_binding_and_history(
    connected, monkeypatch, at
):
    client, app, _, _ = connected
    store = app.state.sessions.store
    original = store._record

    def interrupted(conn, row, state, **kw):
        original(conn, row, state, **kw)
        if kw.get("code") == at:
            raise RuntimeError("synthetic commit interruption")

    monkeypatch.setattr(store, "_record", interrupted)
    event = start(client)
    before = client.get(f"{BASE}/{event}").json()
    with pytest.raises(RuntimeError, match="synthetic"):
        associate(client, event)
    assert client.get(f"{BASE}/{event}").json() == before
    assert counts(store) == (0, 0, 0)
    monkeypatch.setattr(store, "_record", original)
    assert associate(client, event).status_code == 200
    assert counts(store) == (1, 1, 0)


def test_binding_and_cycle_identity_are_immutable_and_pin_is_not_persisted(
    connected, caplog
):
    client, app, _, _ = connected
    store = app.state.sessions.store
    event = start(client)
    snapshot = associate(client, event).json()
    for sql in [
        "UPDATE simulation_identities SET student_id='different'",
        "DELETE FROM simulation_identities",
        "UPDATE cycles SET student_id='different'",
    ]:
        with pytest.raises(sqlite3.IntegrityError), store.transaction() as conn:
            conn.execute(sql)
    with store.transaction() as conn:
        dump = "\n".join(conn.iterdump())
        assert tuple(
            conn.execute(
                "SELECT physical_confirmed,payload,receipt,central_scope FROM cycles"
            ).fetchone()
        ) == (0, None, None, None)
    for value in (dump, json.dumps(snapshot), caplog.text):
        assert KEY not in value and '"pin"' not in value and "pin_hash" not in value
        assert "'0012'" not in value and '": "0012"' not in value
    assert client.get("/local/status").json()["can_start_deposit"] is False


def test_no_movement_or_safety_before_identity_even_through_internal_journal(connected):
    client, app, _, calls = connected
    event = start(client)
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False}).status_code
        == 409
    )
    assert (
        client.post(
            f"{BASE}/{event}/open", json={"mechanical_command_id": str(uuid4())}
        ).status_code
        == 409
    )
    with pytest.raises(CycleError, match="Totem"):
        app.state.sessions.store.mechanical.request(
            MechanicalCommand(event_id=UUID(event), operation="OPEN_INSERTION_DOOR"),
            source="SIMULATED",
        )
    assert calls == [] and counts(app.state.sessions.store) == (0, 0, 0)


def test_offline_blocks_new_risky_motions_but_allows_safe_close_and_replay(connected):
    client, app, broker, _ = connected
    event = start(client)
    assert associate(client, event).status_code == 200
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    original = broker.app.state.central._http._transport.inner
    broker.app.state.central._http._transport.inner = httpx.MockTransport(
        lambda r: httpx.Response(503, json={})
    )
    command = {"mechanical_command_id": str(uuid4()), "pin": PIN["pin"]}
    assert client.post(f"{BASE}/{event}/open", json=command).status_code == 503
    assert counts(app.state.sessions.store) == (1, 1, 0)
    broker.app.state.central._http._transport.inner = original
    assert client.post(f"{BASE}/{event}/open", json=command).status_code in {200, 202}
    client.portal.call(
        app.state.mechanical.wait, UUID(command["mechanical_command_id"])
    )
    broker.app.state.central._http._transport.inner = httpx.MockTransport(
        lambda r: httpx.Response(503, json={})
    )
    recovered = client.get(f"{BASE}/{event}").json()
    assert recovered["session"]["state"] == "DOOR_OPEN"
    assert client.post(f"{BASE}/{event}/open", json=command).status_code == 503
    assert associate(client, event).status_code == 503
    assert client.get(f"{BASE}/{event}").json() == recovered
    assert (
        associate(client, event, {**PIN, "student_id": str(uuid4())}).status_code == 409
    )
    close = uuid4()
    assert client.post(
        f"{BASE}/{event}/close",
        json={"mechanical_command_id": str(close), "hand_removed": True},
    ).status_code in {200, 202}
    client.portal.call(app.state.mechanical.wait, close)
    client.post(f"{BASE}/{event}/review-fixture", json={})
    assert (
        client.post(
            f"{BASE}/{event}/hatch",
            json={"mechanical_command_id": str(uuid4()), "pin": PIN["pin"]},
        ).status_code
        == 503
    )
    assert (
        associate(client, event, {**PIN, "class_id": str(uuid4())}).status_code == 409
    )


@contextmanager
def local_dev(environment, transport=None):
    directory, policy, _ = environment
    app = create_dev_app(
        data_directory=directory, policy_path=policy, transport=transport
    )
    with TestClient(
        app, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        yield client, app


def synthetic(request):
    if request.url.path.endswith("health-v1"):
        return httpx.Response(
            200,
            json={
                "status": "AVAILABLE",
                "can_start_deposit": True,
                "scope": "CENTRAL_BACKEND",
                "checked_at": "2026-10-29T12:00:00Z",
            },
        )
    if request.url.path.endswith("totem-context-v1"):
        return httpx.Response(200, json=CONTEXT)
    return httpx.Response(
        200, json={"confirmed": True, "student": CONTEXT["students"][0]}
    )


@pytest.mark.parametrize("commit", [False, True])
def test_restart_on_either_side_of_identity_commit(
    dev_environment, monkeypatch, commit
):
    with local_dev(dev_environment, httpx.MockTransport(synthetic)) as (client, app):
        event = start(client)
        store = app.state.sessions.store
        original = store.bind_simulation_identity
        if not commit:

            def fail(*args):
                raise RuntimeError("synthetic crash after remote confirmation")

            monkeypatch.setattr(store, "bind_simulation_identity", fail)
            with pytest.raises(RuntimeError):
                associate(client, event)
        else:
            assert associate(client, event).status_code == 200
        snapshot = client.get(f"{BASE}/{event}").json()
    with local_dev(dev_environment, httpx.MockTransport(synthetic)) as (client, app):
        assert client.get(f"{BASE}/{event}").json() == snapshot
        assert snapshot["session"]["state"] == ("SAFETY" if commit else "IDENTIFYING")
        assert counts(app.state.sessions.store) == ((1, 1, 0) if commit else (0, 0, 0))
        assert associate(client, event).status_code == 200
        assert counts(app.state.sessions.store) == (1, 1, 0)


def test_v3_migration_preserves_old_sessions_and_does_not_adopt_fixture_identity(
    dev_environment,
):
    directory, _, _ = dev_environment
    # Banco real v3 sem a extensão de identidade, com histórico e sessão 3B.
    with local_dev(dev_environment):
        pass  # Marca o volume DEV pelo mesmo provisionamento oficial.
    path = directory / "simulation.sqlite3"
    store = CycleStore(path, simulation_enabled=True)
    old = store.create(uuid4(), "class_only", CLASS, "fixture", simulated=True)
    store.close()
    with sqlite3.connect(path) as conn:
        for name in (
            "simulation_identity_no_update",
            "simulation_identity_no_delete",
            "simulation_identity_cycle_immutable",
        ):
            conn.execute(f"DROP TRIGGER {name}")
        conn.execute("DROP TABLE simulation_identities")
        conn.execute("PRAGMA user_version=3")
        before = conn.execute("SELECT * FROM cycles").fetchall()
        history = conn.execute("SELECT * FROM transitions").fetchall()
    with local_dev(dev_environment) as (client, app):
        with app.state.sessions.store.transaction() as conn:
            assert conn.execute("PRAGMA user_version").fetchone()[0] == 4
            assert [tuple(r) for r in conn.execute("SELECT * FROM cycles")] == before
            assert [
                tuple(r) for r in conn.execute("SELECT * FROM transitions")
            ] == history
        assert associate(client, old.event_id).status_code == 409
        snapshot = client.get(f"{BASE}/{old.event_id}").json()
        assert snapshot["identity"] is None and snapshot["allowed_actions"] == [
            "cancel"
        ]
        assert client.post(f"{BASE}/{old.event_id}/cancel", json={}).status_code == 200
        assert (
            client.get(f"{BASE}/{start(client)}").json()["session"]["state"]
            == "IDENTIFYING"
        )


def test_new_identity_route_keeps_http_guards(connected):
    client, _, _, calls = connected
    event = start(client)
    path = f"/local/dev/sessions/{event}/identity"
    for headers in (
        {"Host": "lan.invalid"},
        {"Origin": "http://lan.invalid"},
        {"X-Totem-Request": "0"},
        {"Content-Type": "text/plain"},
    ):
        assert client.post(path, json=PIN, headers=headers).status_code == 403
    assert client.post(path + "?pin=redacted", json=PIN).status_code == 422
    assert associate(client, uuid4()).status_code == 404
    assert calls == []


def test_cancelled_binding_is_preserved_as_history_not_new_authorization(connected):
    client, app, _, calls = connected
    event = start(client)
    assert associate(client, event).status_code == 200
    snapshot = client.post(f"{BASE}/{event}/cancel", json={}).json()
    number = len(calls)
    assert associate(client, event).json() == snapshot
    assert len(calls) > number
    number = len(calls)
    assert (
        associate(client, event, {**PIN, "student_id": str(uuid4())}).status_code == 409
    )
    assert len(calls) == number
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False}).status_code
        == 409
    )
    assert counts(app.state.sessions.store) == (1, 1, 0)
    assert client.get(f"{BASE}/{start(client)}").json()["identity"] is None


def test_failure_in_identity_insert_rolls_back_already_written_transitions(connected):
    client, app, _, _ = connected
    store = app.state.sessions.store
    event = start(client)
    with store.transaction() as conn:
        conn.execute(
            "CREATE TRIGGER test_identity_insert_failure BEFORE INSERT ON simulation_identities BEGIN SELECT RAISE(ABORT,'synthetic insert interruption'); END"
        )
    with pytest.raises(sqlite3.IntegrityError, match="synthetic"):
        associate(client, event)
    assert counts(store) == (0, 0, 0)
    assert client.get(f"{BASE}/{event}").json()["session"]["state"] == "IDENTIFYING"


@pytest.mark.parametrize("field", ["school_id", "machine_id"])
def test_changed_installation_cannot_adopt_persisted_identity(dev_environment, field):
    with local_dev(dev_environment, httpx.MockTransport(synthetic)) as (client, _):
        assert associate(client, start(client)).status_code == 200
    policy = dev_environment[1]
    data = json.loads(policy.read_text())
    data[field] = str(uuid4())
    policy.write_text(json.dumps(data))
    with pytest.raises(CycleError) as error, local_dev(dev_environment):
        pass
    assert error.value.code == "DEV_IDENTITY_SCOPE_MISMATCH"


@pytest.mark.parametrize(
    "state",
    ["OPENING", "HATCH_IN_PROGRESS"],
)
def test_identity_cannot_be_attached_after_legacy_motion(dev_environment, state):
    with local_dev(dev_environment) as (_, app):
        store = app.state.sessions.store
        # Retrato legado 3B, sem identidade central: não pode ser adotado por PIN.
        scope = store.identity_scope
        store.identity_scope = None
        old = store.create(uuid4(), "class_only", CLASS, "fixture", simulated=True)
        store.identity_scope = scope
        with store.transaction() as conn:
            row = store._row(conn, old.event_id)
            store._record(conn, row, state)
        with pytest.raises(CycleError) as error:
            store.identity_attempt(old.event_id, CLASS, STUDENT)
        assert error.value.code == "COMMAND_OUT_OF_SEQUENCE"


def test_existing_binding_does_not_override_current_student_eligibility(
    connected, monkeypatch
):
    client, app, _, _ = connected
    event = start(client)
    assert associate(client, event).status_code == 200
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    monkeypatch.setitem(CONTEXT, "students", [])
    assert (
        client.post(
            f"{BASE}/{event}/open",
            json={"mechanical_command_id": str(uuid4()), "pin": PIN["pin"]},
        ).status_code
        == 403
    )
    assert counts(app.state.sessions.store) == (1, 1, 0)


def test_offline_initial_confirmation_keeps_safe_completion_available(connected):
    client, app, broker, _ = connected
    event = start(client)
    assert associate(client, event).status_code == 200
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    for action, extra in [
        ("open", {"pin": PIN["pin"]}),
        ("close", {"hand_removed": True}),
        ("hatch", {"pin": PIN["pin"]}),
    ]:
        if action == "hatch":
            client.post(f"{BASE}/{event}/review-fixture", json={})
        command = uuid4()
        assert client.post(
            f"{BASE}/{event}/{action}",
            json={"mechanical_command_id": str(command), **extra},
        ).status_code in {200, 202}
        client.portal.call(app.state.mechanical.wait, command)
    broker.app.state.central._http._transport.inner = httpx.MockTransport(
        lambda r: httpx.Response(503, json={})
    )
    command = uuid4()
    assert client.post(
        f"{BASE}/{event}/confirm-initial", json={"mechanical_command_id": str(command)}
    ).status_code in {200, 202}
    client.portal.call(app.state.mechanical.wait, command)
    final = client.get(f"{BASE}/{event}").json()
    assert final["session"]["state"] == "COMPLETED"
    assert final["session"]["receipt"] is None
    assert final["identity"]["student_id"] == str(STUDENT)


def test_v3_upgrade_preserves_journal_and_mechanical_history(dev_environment):
    with local_dev(dev_environment, httpx.MockTransport(synthetic)) as (client, app):
        # Retrato do fluxo sem identidade existente em 3B/3C.1.
        store = app.state.sessions.store
        scope = store.identity_scope
        store.identity_scope = None
        old = app.state.simulation_flow.start(uuid4())
        event = old.session.event_id
        app.state.simulation_flow.safety(event, False)
        command = MechanicalCommand(event_id=event, operation="OPEN_INSERTION_DOOR")
        client.portal.call(app.state.mechanical.submit, command)
        client.portal.call(app.state.mechanical.wait, command.mechanical_command_id)
        store.identity_scope = scope
        with store.transaction() as conn:
            for trigger in (
                "simulation_identity_no_update",
                "simulation_identity_no_delete",
                "simulation_identity_cycle_immutable",
            ):
                conn.execute(f"DROP TRIGGER {trigger}")
            conn.execute("DROP TABLE simulation_identities")
            conn.execute("PRAGMA user_version=3")
            before = {
                table: [tuple(r) for r in conn.execute(f"SELECT * FROM {table}")]
                for table in (
                    "cycles",
                    "transitions",
                    "mechanical_commands",
                    "mechanical_history",
                )
            }
    with local_dev(dev_environment) as (client, app):
        with app.state.sessions.store.transaction() as conn:
            assert conn.execute("PRAGMA user_version").fetchone()[0] == 4
            for table, rows in before.items():
                assert [
                    tuple(r) for r in conn.execute(f"SELECT * FROM {table}")
                ] == rows
        snapshot = client.get(f"{BASE}/{event}").json()
        assert snapshot["session"]["state"] == "DOOR_OPEN"
        assert snapshot["identity"] is None and snapshot["allowed_actions"] == ["close"]
        assert associate(client, event).status_code == 409
        assert client.post(f"{BASE}/{event}/cancel", json={}).status_code == 409


@pytest.mark.parametrize(
    "supplied,status", [("0012", 200), ("9999", 401), ("123", 422)]
)
def test_retry_reauthenticates_without_rewriting_binding(connected, supplied, status):
    client, app, _, calls = connected
    event = start(client)
    snapshot = associate(client, event).json()
    before = len(calls)
    assert associate(client, event, {**PIN, "pin": supplied}).status_code == status
    assert len(calls) > before if status != 422 else len(calls) == before
    assert client.get(f"{BASE}/{event}").json() == snapshot
    assert counts(app.state.sessions.store) == (1, 1, 0)


@pytest.mark.parametrize("failure", ["health", "timeout", "network", "inconsistent"])
def test_retry_central_failure_preserves_existing_identity(connected, failure):
    client, app, broker, _ = connected
    event = start(client)
    snapshot = associate(client, event).json()

    async def handler(request):
        if failure == "health":
            return httpx.Response(503, json={})
        if request.url.path.endswith("totem-student-pin-v1"):
            if failure == "timeout":
                raise httpx.ReadTimeout("synthetic", request=request)
            if failure == "network":
                raise httpx.ConnectError("synthetic", request=request)
            return httpx.Response(200, json={"confirmed": False})

    intercept(broker, handler)
    assert associate(client, event).status_code == 503
    assert client.get(f"{BASE}/{event}").json() == snapshot
    assert counts(app.state.sessions.store) == (1, 1, 0)


@pytest.mark.parametrize("bound", [False, True])
def test_correct_and_wrong_pin_concurrently_never_share_authentication(
    connected, bound
):
    client, app, broker, _ = connected
    event = start(client)
    snapshot = associate(client, event).json() if bound else None
    arrived = 0
    barrier = asyncio.Event()

    async def handler(request):
        nonlocal arrived
        if request.url.path.endswith("totem-student-pin-v1"):
            arrived += 1
            if arrived == 2:
                barrier.set()
            await asyncio.wait_for(barrier.wait(), 5)

    intercept(broker, handler)
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(associate, client, event, {**PIN, "pin": value})
            for value in ("0012", "9999")
        ]
        responses = [f.result(timeout=10) for f in futures]
    assert sorted(r.status_code for r in responses) == [200, 401]
    assert counts(app.state.sessions.store) == (1, 1, 0)
    if bound:
        assert client.get(f"{BASE}/{event}").json() == snapshot


def test_restart_get_recovers_without_auth_but_post_must_authenticate(dev_environment):
    with local_dev(dev_environment, httpx.MockTransport(synthetic)) as (client, _):
        event = start(client)
        snapshot = associate(client, event).json()
    calls = []

    def unavailable(request):
        calls.append(request.url.path)
        raise httpx.ConnectError("synthetic", request=request)

    with local_dev(dev_environment, httpx.MockTransport(unavailable)) as (client, app):
        assert client.get(f"{BASE}/{event}").json() == snapshot
        assert client.get(BASE + "/active").json()["snapshot"] == snapshot
        assert calls == []
        assert associate(client, event).status_code == 503
        assert calls and client.get(f"{BASE}/{event}").json() == snapshot
        assert counts(app.state.sessions.store) == (1, 1, 0)


@pytest.mark.parametrize("action", ["open", "hatch"])
@pytest.mark.parametrize(
    "supplied,status", [(None, 401), ("9999", 401), ("123", 422), ("0012", 200)]
)
def test_event_id_is_not_authorization_for_risky_dev_commands(
    connected, action, supplied, status, caplog
):
    client, app, _, _ = connected
    event = start(client)
    assert associate(client, event).status_code == 200
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    if action == "hatch":
        for step, extra in [
            ("open", {"pin": PIN["pin"]}),
            ("close", {"hand_removed": True}),
        ]:
            identifier = uuid4()
            assert client.post(
                f"{BASE}/{event}/{step}",
                json={"mechanical_command_id": str(identifier), **extra},
            ).status_code in {200, 202}
            client.portal.call(app.state.mechanical.wait, identifier)
        client.post(f"{BASE}/{event}/review-fixture", json={})
    before = client.get(f"{BASE}/{event}").json()
    before_counts = counts(app.state.sessions.store)
    identifier = uuid4()
    body = {"mechanical_command_id": str(identifier)}
    if supplied is not None:
        body["pin"] = supplied
    response = client.post(f"{BASE}/{event}/{action}", json=body)
    if status == 200:
        assert response.status_code in {200, 202}
        client.portal.call(app.state.mechanical.wait, identifier)
        assert client.post(f"{BASE}/{event}/{action}", json=body).status_code == 200
        assert (
            client.post(
                f"{BASE}/{event}/{action}", json={**body, "pin": "9999"}
            ).status_code
            == 401
        )
        assert counts(app.state.sessions.store)[2] == before_counts[2] + 1
    else:
        assert response.status_code == status
        assert client.get(f"{BASE}/{event}").json() == before
        assert counts(app.state.sessions.store) == before_counts
    with app.state.sessions.store.transaction() as conn:
        dump = "\n".join(conn.iterdump())
        assert tuple(
            conn.execute(
                "SELECT physical_confirmed,payload,receipt,central_scope FROM cycles"
            ).fetchone()
        ) == (0, None, None, None)
    for text in (dump, caplog.text, response.text):
        assert '"pin"' not in text and "pin_hash" not in text and KEY not in text
        assert "'0012'" not in text and '": "0012"' not in text
