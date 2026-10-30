"""Contratos sintéticos: nenhuma credencial, aluno ou chamada hospedada real."""

import json
import os
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest

from test_simulation import simulation_environment

from app.clients.supabase import CentralError
from app.dev_broker import create_broker_app
from app.dev_integration import (
    ALLOWED,
    BROKER,
    DEV_URL,
    DevConfigurationError,
    DevPolicy,
    FunctionTransport,
    create_dev_app,
    load_machine_key,
    load_policy,
)
from app.main import create_app
from app.services.controller import SimulatedController, UnavailableController
from app.simulation import SimulationConfigurationError, create_simulation_app

MACHINE, SCHOOL, CLASS, STUDENT = [
    UUID(f"00000000-0000-4000-8000-{i:012d}") for i in range(1, 5)
]
CONTEXT = {
    "school": {"id": str(SCHOOL), "name": "Escola sintética"},
    "machine": {"id": str(MACHINE), "name": "Máquina de teste"},
    "classes": [
        {
            "id": str(CLASS),
            "name": "Turma de teste",
            "segment": None,
            "grade": None,
            "points_class_balance": 1900,
        }
    ],
    "students": [
        {
            "id": str(STUDENT),
            "name": "Aluno sintético",
            "class_id": str(CLASS),
            "class_name": "Turma de teste",
            "status": "ACTIVE",
            "points_student_balance": 800,
        }
    ],
}
PIN = {"class_id": str(CLASS), "student_id": str(STUDENT), "pin": "0012"}
BASE = "/local/simulation/sessions"
KEY = "synthetic-machine-credential-only"


@pytest.fixture
def dev_environment(monkeypatch, tmp_path):
    for name in tuple(os.environ):
        if name.startswith(
            ("BINGO_", "SUPABASE_", "AWS_", "GEMINI_")
        ) or name.lower() in {"http_proxy", "https_proxy", "all_proxy"}:
            monkeypatch.delenv(name, raising=False)
    directory = tmp_path / "dev-data"
    monkeypatch.setenv("BINGO_DEV_CONTEXT", "test")
    monkeypatch.setenv(
        "BINGO_DEV_PLANS",
        json.dumps(
            {
                op: {"duration_seconds": 0.0}
                for op in (
                    "OPEN_INSERTION_DOOR",
                    "CLOSE_INSERTION_DOOR",
                    "CYCLE_LOWER_HATCH",
                    "CONFIRM_INITIAL_STATE",
                )
            }
        ),
    )
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(directory / "simulation.sqlite3"))
    policy = tmp_path / "policy.json"
    policy.write_text(
        json.dumps(
            {
                "project_ref": "ddxmohrjcxuibswmrtla",
                "machine_id": str(MACHINE),
                "school_id": str(SCHOOL),
            }
        )
    )
    key = tmp_path / "machine-key"
    key.write_text(KEY)
    return directory, policy, key


@pytest.fixture
def connected(dev_environment):
    directory, policy, key = dev_environment
    calls = []

    def remote(request):
        calls.append(request)
        assert (request.method, request.url.path) in ALLOWED
        assert str(request.url).startswith(DEV_URL)
        assert request.headers["X-Machine-Id"] == str(MACHINE)
        assert request.headers["X-Api-Key"] == KEY
        assert "authorization" not in request.headers
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200,
                json={
                    "status": "AVAILABLE",
                    "can_start_deposit": True,
                    "scope": "CENTRAL_BACKEND",
                    "checked_at": "2026-10-28T12:00:00Z",
                },
            )
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=CONTEXT)
        body = json.loads(request.content)
        student = next(
            (
                s
                for s in CONTEXT["students"]
                if s["id"] == body["student_id"]
                and s["class_id"] == body["class_id"]
                and s["status"] == "ACTIVE"
            ),
            None,
        )
        if body["pin"] != "0012" or student is None:
            return httpx.Response(401, json={"error": {"code": "STUDENT_PIN_INVALID"}})
        return httpx.Response(
            200,
            json={
                "confirmed": True,
                "student": {
                    k: student[k] for k in ("id", "name", "class_id", "class_name")
                },
            },
        )

    broker = create_broker_app(
        policy_path=policy, key_path=key, transport=httpx.MockTransport(remote)
    )
    app = create_dev_app(
        data_directory=directory,
        policy_path=policy,
        transport=httpx.ASGITransport(app=broker),
    )
    with (
        TestClient(broker) as internal,
        TestClient(
            app, base_url="http://127.0.0.1:8002", headers={"X-Totem-Request": "1"}
        ) as client,
    ):
        yield client, app, internal, calls


def test_dev_health_context_pin_without_economic_or_physical_authority(connected):
    client, app, _, calls = connected
    assert isinstance(app.state.controller, SimulatedController)
    assert app.state.sessions.central.configuration_scope is None
    assert app.state.sessions.central._settings.machine_api_key != KEY
    assert client.get("/local/dev/health").json() == {
        "central": "AVAILABLE",
        "scope": "SUPABASE_DEV_READ_ONLY",
        "mechanical_source": "SIMULATED",
        "economic_registration": False,
    }
    assert client.get("/local/dev/context").json() == CONTEXT
    assert client.post("/local/dev/student-pin", json=PIN).json()["confirmed"] is True
    assert (
        client.post("/local/dev/student-pin", json={**PIN, "pin": "9999"}).status_code
        == 401
    )
    assert client.get("/local/status").json()["can_start_deposit"] is False
    assert app.state.sessions.store.active() is None
    assert all((r.method, r.url.path) in ALLOWED for r in calls)


@pytest.mark.parametrize(
    "path,body",
    [
        ("/local/context", None),
        ("/local/sessions/active", None),
        (
            "/local/sessions",
            {"command_id": str(uuid4()), "class_id": str(CLASS), "mode": "class_only"},
        ),
        ("/local/sessions/{event}", None),
        *[
            ("/local/sessions/{event}/" + action, {})
            for action in (
                "safety",
                "pin",
                "cancel",
                "hand-removed",
                "retry-registration",
                "finish",
            )
        ],
    ],
)
def test_operational_routes_absent_and_cannot_mutate_simulated_sessions(
    connected, path, body
):
    client, app, _, calls = connected
    event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
        "event_id"
    ]
    before = client.get(BASE + "/" + event).json()
    response = (
        client.get(path.format(event=event))
        if body is None
        else client.post(path.format(event=event), json=body)
    )
    assert response.status_code == 404
    assert client.get(BASE + "/" + event).json() == before
    assert calls == []


def test_dev_simulated_flow_requires_durable_central_identification(
    connected,
):
    client, app, _, calls = connected
    event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
        "event_id"
    ]
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 200
    assert client.get(BASE + "/" + event).json()["session"]["student_id"] is None
    assert (
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False}).status_code
        == 409
    )
    assert (
        client.post(f"/local/dev/sessions/{event}/identity", json=PIN).status_code
        == 200
    )
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    for action, extra in [
        ("open", {"pin": PIN["pin"]}),
        ("close", {"hand_removed": True}),
        ("hatch", {"pin": PIN["pin"]}),
        ("confirm-initial", {}),
    ]:
        if action == "hatch":
            assert (
                client.post(f"{BASE}/{event}/review-fixture", json={}).status_code
                == 200
            )
        identifier = uuid4()
        body = {"mechanical_command_id": str(identifier), **extra}
        assert client.post(f"{BASE}/{event}/{action}", json=body).status_code in (
            200,
            202,
        )
        client.portal.call(app.state.mechanical.wait, identifier)
        assert client.post(f"{BASE}/{event}/{action}", json=body).status_code == 200
    final = client.get(BASE + "/" + event).json()
    assert final["source"] == "SIMULATED" and final["session"]["state"] == "COMPLETED"
    assert final["session"]["receipt"] is None and len(final["commands"]) == 4
    number = len(calls)
    assert (
        client.post(f"/local/dev/sessions/{event}/identity", json=PIN).json() == final
    )
    assert len(calls) > number
    number = len(calls)
    assert (
        client.post(
            f"/local/dev/sessions/{event}/identity",
            json={**PIN, "student_id": str(uuid4())},
        ).status_code
        == 409
    )
    assert len(calls) == number
    with app.state.sessions.store.transaction() as conn:
        assert tuple(
            conn.execute(
                "SELECT simulated,physical_confirmed,payload,receipt,central_scope FROM cycles"
            ).fetchone()
        ) == (1, 0, None, None, None)
    before = len(calls)
    with pytest.raises(CentralError, match="central") as error:
        client.portal.call(app.state.dev_central.register, None)
    assert error.value.code == "DEV_CAPABILITY_DENIED"
    assert len(calls) == before


@pytest.mark.parametrize(
    "method,path",
    [
        ("POST", "/functions/v1/register-deposit-v1"),
        ("POST", "/rest/v1/rpc/register_deposit_v1"),
        ("GET", "/rest/v1/students"),
        ("GET", "/functions/v1/totem-rankings-v1"),
        ("GET", "/functions/v1/health-v1?x=1"),
        ("GET", "/functions/v1/%68ealth-v1"),
        ("POST", "/functions/v1/health-v1"),
        ("CONNECT", "/functions/v1/health-v1"),
    ],
)
def test_broker_rejects_capabilities_and_aliases_before_network(
    connected, method, path
):
    _, _, broker, calls = connected
    before = len(calls)
    assert broker.request(method, path, headers={"X-Totem-Dev": "1"}).status_code == 403
    assert len(calls) == before


@pytest.mark.parametrize("native", [False, True])
@pytest.mark.parametrize(
    "url",
    [
        "/functions/v1/register-deposit-v1",
        "/rest/v1/rpc/register_deposit_v1",
        "/functions/v1/health-v1?q=1",
        "/functions/v1/%68ealth-v1",
        "https://other.invalid/functions/v1/health-v1",
    ],
)
def test_transport_has_no_generic_http_or_rpc_capability(native, url):
    import asyncio

    calls = []
    origin = DEV_URL if native else "http://127.0.0.1"

    async def check():
        async with httpx.AsyncClient(
            transport=FunctionTransport(
                native=native, inner=httpx.MockTransport(lambda r: calls.append(r))
            )
        ) as client:
            with pytest.raises(CentralError) as error:
                await client.get(origin + url if url.startswith("/") else url)
            assert error.value.code == "DEV_CAPABILITY_DENIED"

    asyncio.run(check())
    assert calls == []


@pytest.mark.parametrize(
    "field,value",
    [
        ("project_ref", "production"),
        ("test_data_only", False),
        ("test_data_only", 1),
        ("class_ids", []),
        ("service_role", "forbidden"),
    ],
)
def test_policy_rejects_non_dev_unapproved_or_privileged_configuration(
    dev_environment, field, value
):
    _, policy, _ = dev_environment
    data = json.loads(policy.read_text())
    data[field] = value
    policy.write_text(json.dumps(data))
    with pytest.raises(DevConfigurationError):
        load_policy(policy)


@pytest.mark.parametrize(
    "key", ["", "eyJforbidden.jwt.signature", "sb_secret_forbidden", "line\nbreak"]
)
def test_privileged_or_invalid_secrets_rejected(dev_environment, key):
    _, _, path = dev_environment
    path.write_text(key)
    with pytest.raises(DevConfigurationError):
        load_machine_key(path)


@pytest.mark.parametrize(
    "name,value",
    [
        ("BINGO_DEV_CONTEXT", "production"),
        ("BINGO_SIMULATION_CONTEXT", "test"),
        ("BINGO_SUPABASE_URL", DEV_URL),
        ("BINGO_MACHINE_API_KEY", "must-not-be-here"),
        ("SUPABASE_SERVICE_ROLE_KEY", "forbidden"),
        ("HTTPS_PROXY", "http://forbidden.invalid"),
        ("BINGO_DEV_UNSAFE_FLAG", "true"),
        ("BINGO_SQLITE_PATH", "/var/lib/bingo/totem.sqlite3"),
    ],
)
def test_dev_factory_fails_closed_on_incompatible_environment(
    dev_environment, monkeypatch, name, value
):
    directory, policy, _ = dev_environment
    monkeypatch.setenv(name, value)
    with pytest.raises(DevConfigurationError):
        create_dev_app(data_directory=directory, policy_path=policy)
    assert not directory.exists()


def test_other_factories_reject_dev_environment(dev_environment):
    with pytest.raises(SimulationConfigurationError), TestClient(create_app()):
        pass
    with pytest.raises(SimulationConfigurationError):
        create_simulation_app(data_directory=dev_environment[0])


def test_host_origin_query_and_pin_contract_guards(connected):
    client, _, _, calls = connected
    assert (
        client.get("/local/dev/context", headers={"Host": "remote.invalid"}).status_code
        == 403
    )
    assert (
        client.get(
            "/local/dev/context", headers={"Origin": "http://remote.invalid"}
        ).status_code
        == 403
    )
    assert client.get("/local/dev/context?pin=secret").status_code == 422
    for body in (
        {**PIN, "pin": "bad-secret"},
        {**PIN, "physical_confirmed": True},
        {**PIN, "student_id": "bad"},
    ):
        response = client.post("/local/dev/student-pin", json=body)
        assert response.status_code == 422 and "bad-secret" not in response.text
    assert calls == []


def test_test_scope_denial_precedes_student_pin_request(connected):
    client, _, _, calls = connected
    response = client.post(
        "/local/dev/student-pin", json={**PIN, "student_id": str(uuid4())}
    )
    assert response.status_code == 403
    assert any(r.url.path.endswith("totem-context-v1") for r in calls)
    assert not any(r.url.path.endswith("totem-student-pin-v1") for r in calls)


def test_dev_recovery_preserves_journal_without_redispatch(dev_environment):
    directory, policy, _ = dev_environment
    app = create_dev_app(data_directory=directory, policy_path=policy)
    with TestClient(
        app, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
            "event_id"
        ]
        from app.cycles import SimulationIdentity
        from app.central_contracts import ConfirmedStudent
        from app.storage import now

        store = app.state.sessions.store
        store.bind_simulation_identity(
            SimulationIdentity(
                event_id=event,
                project_ref="ddxmohrjcxuibswmrtla",
                machine_id=MACHINE,
                school_id=SCHOOL,
                class_id=CLASS,
                student_id=STUDENT,
                validated_at=now(),
            ),
            ConfirmedStudent(
                **{
                    k: CONTEXT["students"][0][k]
                    for k in ("id", "name", "class_id", "class_name")
                }
            ),
            store.identity_attempt(UUID(event), CLASS, STUDENT)[1],
        )
        client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
        from app.mechanical import MechanicalCommand

        command = MechanicalCommand(
            event_id=UUID(event), operation="OPEN_INSERTION_DOOR"
        )
        entry, _ = app.state.sessions.store.mechanical.request(
            command, source="SIMULATED"
        )
        app.state.sessions.store.mechanical.claim(
            command.mechanical_command_id, version=entry.version
        )
    with TestClient(
        create_dev_app(data_directory=directory, policy_path=policy),
        base_url="http://127.0.0.1",
    ) as client:
        snapshot = client.get(f"{BASE}/{event}").json()
        assert snapshot["session"]["state"] == "INDETERMINATE"
        assert snapshot["commands"][0]["result"] == "UNKNOWN"
        assert snapshot["allowed_actions"] == []
        assert client.app.state.controller._responses == {}
        assert client.get(BASE + "/active").json()["snapshot"] == snapshot


@pytest.mark.parametrize(
    "code,body",
    [
        (401, {"error": {"code": "MACHINE_AUTHENTICATION_FAILED"}}),
        (403, {}),
        (500, {}),
        (503, {}),
        (200, {"status": "AVAILABLE"}),
        (302, {}),
    ],
)
def test_health_authentication_unavailability_and_redirects_fail_closed(
    connected, code, body
):
    client, _, broker, _ = connected
    requests = []

    def remote(request):
        requests.append(request)
        return httpx.Response(
            code,
            json=body,
            headers={"Location": DEV_URL + "/functions/v1/register-deposit-v1"},
        )

    broker.app.state.central._http._transport.inner = httpx.MockTransport(remote)
    response = client.get("/local/dev/health")
    assert response.status_code == (401 if code == 401 else 503)
    assert client.get("/local/dev/context").status_code >= 400
    assert client.post("/local/dev/student-pin", json=PIN).status_code >= 400
    assert all(request.url.path.endswith("health-v1") for request in requests)


def test_network_timeout_does_not_confirm_identity(connected):
    client, _, broker, _ = connected

    def timeout(request):
        raise httpx.ReadTimeout("synthetic", request=request)

    broker.app.state.central._http._transport.inner = httpx.MockTransport(timeout)
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 503


@pytest.mark.parametrize("field", ["machine", "school"])
def test_unapproved_context_never_reaches_local_consumer(connected, field):
    client, _, broker, _ = connected
    context = json.loads(json.dumps(CONTEXT))
    context[field]["id"] = str(uuid4())
    requests = []

    def remote(request):
        requests.append(request)
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200,
                json={
                    "status": "AVAILABLE",
                    "can_start_deposit": True,
                    "scope": "CENTRAL_BACKEND",
                    "checked_at": "2026-10-28T12:00:00Z",
                },
            )
        return httpx.Response(200, json=context)

    broker.app.state.central._http._transport.inner = httpx.MockTransport(remote)
    response = client.get("/local/dev/context")
    assert response.status_code >= 400
    assert "Aluno sintético" not in response.text
    assert any(request.url.path.endswith("totem-context-v1") for request in requests)


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"X-Totem-Dev": "1", "X-Api-Key": KEY},
        {"X-Totem-Dev": "1", "Authorization": "Bearer forbidden"},
    ],
)
def test_broker_does_not_accept_forwarded_credentials(connected, headers):
    _, _, broker, calls = connected
    assert (
        broker.get("/functions/v1/totem-context-v1", headers=headers).status_code == 403
    )
    assert calls == []


def test_missing_secret_and_policy_do_not_start_broker(dev_environment):
    directory, policy, key = dev_environment
    with pytest.raises(DevConfigurationError):
        create_broker_app(policy_path=policy, key_path=directory / "missing")
    with pytest.raises(DevConfigurationError):
        create_broker_app(policy_path=directory / "missing", key_path=key)
    assert not directory.exists()


def test_operational_rejects_dev_marker_even_without_dev_environment(
    dev_environment, monkeypatch
):
    directory, policy, _ = dev_environment
    with TestClient(create_dev_app(data_directory=directory, policy_path=policy)):
        pass
    for name in tuple(os.environ):
        if name.startswith("BINGO_DEV_"):
            monkeypatch.delenv(name)
    with pytest.raises(SimulationConfigurationError), TestClient(create_app()):
        pass


def test_isolated_api_also_prevents_cross_access(simulation_environment):
    # Reutiliza fixture original 3A para comprovar a outra fábrica simulada.
    app = create_simulation_app(data_directory=simulation_environment)
    with TestClient(
        app, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
            "event_id"
        ]
        before = client.get(f"{BASE}/{event}").json()
        assert client.get("/local/sessions/active").status_code == 404
        assert client.get(f"/local/sessions/{event}").status_code == 404
        assert (
            client.post(f"/local/sessions/{event}/cancel", json={}).status_code == 404
        )
        assert client.get("/local/dev/context").status_code == 404
        assert (
            client.post(f"/local/dev/sessions/{event}/identity", json=PIN).status_code
            == 404
        )
        assert client.get(f"{BASE}/{event}").json() == before


def test_minimal_policy_only_requires_installation_identity(dev_environment):
    _, path, _ = dev_environment
    policy = load_policy(path)
    assert set(json.loads(path.read_text())) == {
        "project_ref",
        "machine_id",
        "school_id",
    }
    assert policy.machine_id == MACHINE and policy.school_id == SCHOOL
    assert policy.class_ids is None and policy.student_ids is None


@pytest.mark.parametrize(
    "extra",
    [
        {"class_ids": []},
        {"student_ids": []},
        {"class_ids": None, "student_ids": None},
        {"class_ids": [], "student_ids": []},
        {"class_ids": [str(CLASS)] * 2, "student_ids": [str(STUDENT)]},
        {"class_ids": [str(CLASS)], "student_ids": [str(STUDENT)] * 2},
        {"class_ids": [str(CLASS)], "student_ids": None},
    ],
)
def test_incomplete_or_ambiguous_legacy_restrictions_fail_closed(
    dev_environment, extra
):
    _, path, _ = dev_environment
    path.write_text(json.dumps({**json.loads(path.read_text()), **extra}))
    with pytest.raises(DevConfigurationError):
        load_policy(path)


@pytest.mark.parametrize("field", ["project_ref", "machine_id", "school_id"])
def test_installation_identity_fields_remain_required(dev_environment, field):
    _, path, _ = dev_environment
    body = json.loads(path.read_text())
    del body[field]
    path.write_text(json.dumps(body))
    with pytest.raises(DevConfigurationError):
        load_policy(path)


@pytest.mark.parametrize("addition", ["class", "student"])
def test_legacy_policy_restrictions_are_preserved_not_silently_discarded(
    connected, addition
):
    client, app, broker, _ = connected
    values = {
        "project_ref": "ddxmohrjcxuibswmrtla",
        "test_data_only": True,
        "machine_id": MACHINE,
        "school_id": SCHOOL,
        "class_ids": [CLASS],
        "student_ids": [STUDENT],
    }
    policy = DevPolicy.model_validate(values)
    app.state.dev_central.policy = policy
    broker.app.state.central.policy = policy
    assert client.get("/local/dev/context").status_code == 200
    context = json.loads(json.dumps(CONTEXT))
    if addition == "class":
        context["classes"].append({**context["classes"][0], "id": str(uuid4())})
    else:
        context["students"].append({**context["students"][0], "id": str(uuid4())})
    # Chamada direta ao cliente tipado evita confundir falha de health com escopo.
    broker.app.state.central._http._transport.inner = httpx.MockTransport(
        lambda r: httpx.Response(200, json=context)
    )
    with pytest.raises(CentralError) as error:
        broker.portal.call(broker.app.state.central.context)
    assert error.value.code == "DEV_TEST_SCOPE_MISMATCH"


def test_classes_and_active_students_are_discovered_dynamically(connected, monkeypatch):
    client, _, _, calls = connected
    initial = client.get("/local/dev/context").json()
    new_class, new_student = str(uuid4()), str(uuid4())
    monkeypatch.setitem(
        CONTEXT,
        "classes",
        [
            *CONTEXT["classes"],
            {**CONTEXT["classes"][0], "id": new_class, "name": "Nova turma sintética"},
        ],
    )
    monkeypatch.setitem(
        CONTEXT,
        "students",
        [
            *CONTEXT["students"],
            {
                **CONTEXT["students"][0],
                "id": new_student,
                "class_id": new_class,
                "class_name": "Nova turma sintética",
                "name": "Novo aluno sintético",
            },
        ],
    )
    current = client.get("/local/dev/context").json()
    assert len(current["classes"]) == len(initial["classes"]) + 1
    assert len(current["students"]) == len(initial["students"]) + 1
    response = client.post(
        "/local/dev/student-pin",
        json={**PIN, "class_id": new_class, "student_id": new_student},
    )
    assert (
        response.status_code == 200 and response.json()["student"]["id"] == new_student
    )
    assert all((r.method, r.url.path) in ALLOWED for r in calls)


@pytest.mark.parametrize(
    "body",
    [
        {**PIN, "student_id": str(uuid4())},
        {**PIN, "class_id": str(uuid4())},
        {**PIN, "student_id": str(uuid4()), "class_id": str(uuid4())},
    ],
)
def test_foreign_school_identifiers_cannot_escape_authenticated_context(
    connected, body
):
    client, _, _, calls = connected
    assert client.post("/local/dev/student-pin", json=body).status_code == 403
    assert any(r.url.path.endswith("totem-context-v1") for r in calls)
    assert not any(r.url.path.endswith("totem-student-pin-v1") for r in calls)


def test_student_moved_to_another_authorized_class_requires_current_membership(
    connected, monkeypatch
):
    client, _, _, calls = connected
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 200
    other_class = str(uuid4())
    monkeypatch.setitem(
        CONTEXT,
        "classes",
        [*CONTEXT["classes"], {**CONTEXT["classes"][0], "id": other_class}],
    )
    monkeypatch.setitem(
        CONTEXT, "students", [{**CONTEXT["students"][0], "class_id": other_class}]
    )
    calls.clear()
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 403
    assert not any(r.url.path.endswith("totem-student-pin-v1") for r in calls)
    assert (
        client.post(
            "/local/dev/student-pin", json={**PIN, "class_id": other_class}
        ).status_code
        == 200
    )


def test_student_no_longer_in_active_context_cannot_be_confirmed(
    connected, monkeypatch
):
    client, _, _, calls = connected
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 200
    monkeypatch.setitem(CONTEXT, "students", [])
    calls.clear()
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 403
    assert not any(r.url.path.endswith("totem-student-pin-v1") for r in calls)


def test_central_denial_after_context_lookup_remains_authoritative(connected):
    client, _, broker, _ = connected
    original = broker.app.state.central._http._transport.inner
    pin_calls = []

    async def remote(request):
        if request.url.path.endswith("totem-student-pin-v1"):
            pin_calls.append(request)
            return httpx.Response(401, json={"error": {"code": "STUDENT_PIN_INVALID"}})
        return await original.handle_async_request(request)

    broker.app.state.central._http._transport.inner = httpx.MockTransport(remote)
    response = client.post("/local/dev/student-pin", json=PIN)
    assert response.status_code == 401 and len(pin_calls) == 1
    assert "confirmed" not in response.json()


@pytest.mark.parametrize("value", ["", "123", "12345", "１２３４", 1234, None])
def test_pin_contract_is_not_weakened_by_dynamic_context(connected, value):
    client, _, _, calls = connected
    assert (
        client.post("/local/dev/student-pin", json={**PIN, "pin": value}).status_code
        == 422
    )
    assert calls == []
