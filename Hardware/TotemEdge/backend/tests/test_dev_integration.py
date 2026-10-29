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
                "test_data_only": True,
                "machine_id": str(MACHINE),
                "school_id": str(SCHOOL),
                "class_ids": [str(CLASS)],
                "student_ids": [str(STUDENT)],
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
        if json.loads(request.content)["pin"] != "0012":
            return httpx.Response(401, json={"error": {"code": "STUDENT_PIN_INVALID"}})
        return httpx.Response(
            200,
            json={
                "confirmed": True,
                "student": {
                    k: CONTEXT["students"][0][k]
                    for k in ("id", "name", "class_id", "class_name")
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


def test_simulated_flow_and_journal_remain_independent_of_central_identification(
    connected,
):
    client, app, _, calls = connected
    event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
        "event_id"
    ]
    assert client.post("/local/dev/student-pin", json=PIN).status_code == 200
    assert client.get(BASE + "/" + event).json()["session"]["student_id"] is None
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    for action, extra in [
        ("open", {}),
        ("close", {"hand_removed": True}),
        ("hatch", {}),
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
    assert all(r.url.path.endswith("health-v1") for r in calls)


def test_dev_recovery_preserves_journal_without_redispatch(dev_environment):
    directory, policy, _ = dev_environment
    app = create_dev_app(data_directory=directory, policy_path=policy)
    with TestClient(
        app, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
            "event_id"
        ]
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


@pytest.mark.parametrize("field", ["machine", "school", "class", "student"])
def test_unapproved_context_never_reaches_local_consumer(connected, field):
    client, _, broker, _ = connected
    context = json.loads(json.dumps(CONTEXT))
    if field in {"machine", "school"}:
        context[field]["id"] = str(uuid4())
    elif field == "class":
        context["classes"].append({**context["classes"][0], "id": str(uuid4())})
    else:
        context["students"].append({**context["students"][0], "id": str(uuid4())})
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
        assert client.get(f"{BASE}/{event}").json() == before
