"""Composição de simulação: clientes bloqueados, dados separados e harness interno."""

import asyncio
import json
import os
import sqlite3
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest

from app.central_contracts import DepositPayload
from app.clients.supabase import CentralError
from app.cycles import CycleError
from app.main import create_app
import app.main as main_module
from app.mechanical import MechanicalCommand
from app.services.controller import SimulatedController, UnavailableController
from app.simulation import (
    BlockedCentralClient,
    DATABASE_NAME,
    DenyExternalTransport,
    EXTERNAL_PREFIXES,
    MARKER,
    MARKER_CONTENT,
    PROXY_VARIABLES,
    SimulationConfigurationError,
    SimulationSettings,
    create_simulation_app,
)
from app.simulation_harness import execute, parser
from app.storage import CycleStore


@pytest.fixture
def simulation_environment(monkeypatch, tmp_path):
    for name in tuple(os.environ):
        if (
            name.startswith(EXTERNAL_PREFIXES)
            or name in PROXY_VARIABLES
            or name.startswith("BINGO_SIMULATION_")
        ):
            monkeypatch.delenv(name, raising=False)
    directory = tmp_path / "isolated-simulation"
    monkeypatch.setenv("BINGO_SIMULATION_CONTEXT", "development")
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(directory / DATABASE_NAME))
    monkeypatch.setenv(
        "BINGO_SIMULATION_PLANS",
        json.dumps(
            {
                name: {"duration_seconds": 0.0}
                for name in (
                    "OPEN_INSERTION_DOOR",
                    "CLOSE_INSERTION_DOOR",
                    "CYCLE_LOWER_HATCH",
                    "CONFIRM_INITIAL_STATE",
                )
            }
        ),
    )
    return directory


def test_simulation_initializes_with_blocked_central_and_no_vision(
    simulation_environment, monkeypatch
):
    def forbidden(*args, **kwargs):
        pytest.fail("Simulação não deve construir clientes externos.")

    monkeypatch.setattr(main_module, "SupabaseEdgeClient", forbidden)
    monkeypatch.setattr(main_module, "build_internal_vision", forbidden)
    application = create_simulation_app(data_directory=simulation_environment)
    with TestClient(application, base_url="http://127.0.0.1") as client:
        assert isinstance(application.state.controller, SimulatedController)
        assert isinstance(application.state.sessions.central, BlockedCentralClient)
        assert application.state.sessions.central.configuration_scope is None
        assert application.state.vision is None
        assert application.state.capture.camera is None
        assert (
            application.state.sessions.store.path
            == simulation_environment / DATABASE_NAME
        )
        assert (simulation_environment / MARKER).read_text() == MARKER_CONTENT
        assert client.get("/health").json() == {"status": "ok"}
        status = client.get("/local/status").json()
        assert status["status"] == "OFFLINE" and status["can_start_deposit"] is False
        assert application.openapi()["paths"] == create_app().openapi()["paths"]


def test_operational_default_stays_unavailable_without_simulation_flags():
    with TestClient(create_app()) as client:
        assert isinstance(client.app.state.controller, UnavailableController)
        assert not isinstance(client.app.state.sessions.central, BlockedCentralClient)
        assert client.get("/local/status").json()["can_start_deposit"] is False


@pytest.mark.parametrize("context", [None, "", "production", "operational", "demo"])
def test_simulation_requires_authorized_context(
    simulation_environment, monkeypatch, context
):
    if context is None:
        monkeypatch.delenv("BINGO_SIMULATION_CONTEXT")
    else:
        monkeypatch.setenv("BINGO_SIMULATION_CONTEXT", context)
    with pytest.raises(SimulationConfigurationError):
        create_simulation_app(data_directory=simulation_environment)
    assert not simulation_environment.exists()


@pytest.mark.parametrize(
    "name",
    [
        "BINGO_SUPABASE_URL",
        "BINGO_MACHINE_API_KEY",
        "BINGO_MACHINE_ID",
        "SUPABASE_SERVICE_ROLE_KEY",
        "AWS_PROFILE",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "GEMINI_API_KEY",
        "BINGO_GEMINI_TIMEOUT_SECONDS",
        "HTTPS_PROXY",
        "http_proxy",
    ],
)
def test_credentials_or_external_configuration_fail_before_storage(
    simulation_environment, monkeypatch, name
):
    monkeypatch.setenv(name, "private-host-fixture")
    with pytest.raises(SimulationConfigurationError) as error:
        create_simulation_app(data_directory=simulation_environment)
    assert "private-host-fixture" not in str(error.value)
    assert not simulation_environment.exists()


def test_environment_revalidated_at_lifespan(simulation_environment, monkeypatch):
    application = create_simulation_app(data_directory=simulation_environment)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "private-after-factory")
    with pytest.raises(SimulationConfigurationError):
        with TestClient(application):
            pytest.fail("Startup perigoso não pode completar.")
    assert not simulation_environment.exists()


@pytest.mark.parametrize(
    "value",
    [
        "not-json",
        "[]",
        '{"GPIO":{}}',
        '{"OPEN_INSERTION_DOOR":{"duration_seconds":-1}}',
        '{"OPEN_INSERTION_DOOR":{"duration_seconds":"3"}}',
        '{"OPEN_INSERTION_DOOR":{"duration_seconds":0,"outcome":"REAL"}}',
    ],
)
def test_invalid_plans_fail_closed(simulation_environment, monkeypatch, value):
    monkeypatch.setenv("BINGO_SIMULATION_PLANS", value)
    with pytest.raises(SimulationConfigurationError):
        create_simulation_app(data_directory=simulation_environment)


def test_duration_and_fault_overrides_reuse_existing_plan(
    simulation_environment, monkeypatch
):
    monkeypatch.setenv(
        "BINGO_SIMULATION_PLANS",
        '{"OPEN_INSERTION_DOOR":{"duration_seconds":0.125,"outcome":"FAILURE"}}',
    )
    settings = SimulationSettings.from_environment(
        data_directory=simulation_environment
    )
    assert settings.plans["OPEN_INSERTION_DOOR"].duration_seconds == 0.125
    assert settings.plans["OPEN_INSERTION_DOOR"].outcome == "FAILURE"
    assert settings.plans["CLOSE_INSERTION_DOOR"].duration_seconds == 3.0
    assert settings.plans["CYCLE_LOWER_HATCH"].duration_seconds == 4.0


@pytest.mark.parametrize(
    "value",
    ["totem.sqlite3", "/var/lib/bingo/totem.sqlite3", "/tmp/simulation.sqlite3"],
)
def test_incorrect_sqlite_path_is_rejected(simulation_environment, monkeypatch, value):
    monkeypatch.setenv("BINGO_SQLITE_PATH", value)
    with pytest.raises(SimulationConfigurationError):
        create_simulation_app(data_directory=simulation_environment)
    assert not simulation_environment.exists()


def test_foreign_volume_is_never_adopted(simulation_environment):
    simulation_environment.mkdir()
    foreign = simulation_environment / "totem.sqlite3"
    foreign.write_bytes(b"operational-bank-must-remain-untouched")
    application = create_simulation_app(data_directory=simulation_environment)
    with pytest.raises(SimulationConfigurationError):
        with TestClient(application):
            pass
    assert foreign.read_bytes() == b"operational-bank-must-remain-untouched"
    assert not (simulation_environment / MARKER).exists()


@pytest.mark.parametrize(
    "case",
    [
        "missing_marker",
        "wrong_marker",
        "central_scope",
        "physical_flag",
        "physical_journal",
        "payload",
    ],
)
def test_incompatible_simulation_data_is_rejected_before_recovery(
    simulation_environment, case
):
    application = create_simulation_app(data_directory=simulation_environment)
    with TestClient(application):
        store = application.state.sessions.store
        session = store.create(uuid4(), "class_only", uuid4(), "Simulation")
        store.change(session.event_id, "SAFETY", "PHYSICAL_BLOCKED")
        if case == "physical_journal":
            store.mechanical.request(
                MechanicalCommand(
                    event_id=session.event_id, operation="OPEN_INSERTION_DOOR"
                ),
                source="PHYSICAL",
            )
    marker = simulation_environment / MARKER
    if case == "missing_marker":
        marker.unlink()
    elif case == "wrong_marker":
        marker.write_text("foreign data")
    elif case != "physical_journal":
        column, value = {
            "central_scope": ("central_scope", "foreign-scope"),
            "physical_flag": ("physical_confirmed", 1),
            "payload": ("payload", "{}"),
        }[case]
        with sqlite3.connect(simulation_environment / DATABASE_NAME) as conn:
            conn.execute(f"UPDATE cycles SET {column}=?", (value,))
    with pytest.raises(SimulationConfigurationError):
        with TestClient(create_simulation_app(data_directory=simulation_environment)):
            pass
    with sqlite3.connect(simulation_environment / DATABASE_NAME) as conn:
        assert (
            conn.execute("SELECT state FROM cycles").fetchone()[0] == "PHYSICAL_BLOCKED"
        )


def test_operational_runtime_refuses_simulation_flags(simulation_environment):
    with pytest.raises(SimulationConfigurationError):
        with TestClient(create_app()):
            pass
    assert not simulation_environment.exists()


def test_operational_runtime_refuses_marked_database(
    simulation_environment, monkeypatch
):
    with TestClient(create_simulation_app(data_directory=simulation_environment)):
        pass
    monkeypatch.delenv("BINGO_SIMULATION_CONTEXT")
    monkeypatch.delenv("BINGO_SIMULATION_PLANS")
    with pytest.raises(SimulationConfigurationError):
        with TestClient(create_app()):
            pass


@pytest.mark.anyio
async def test_central_and_http_transport_remain_blocked_even_after_env_changes(
    simulation_environment, monkeypatch
):
    client = BlockedCentralClient()
    monkeypatch.setenv("BINGO_SUPABASE_URL", "https://must-not-be-called.invalid")
    monkeypatch.setenv("BINGO_MACHINE_API_KEY", "private-fixture")
    assert not (await client.check_health()).available
    for call in (
        client.register(object()),
        client.context(),
        client.verify_pin(uuid4(), uuid4(), "0012"),
    ):
        with pytest.raises(CentralError) as error:
            await call
        assert error.value.code == "SIMULATION_CENTRAL_DISABLED"
    async with httpx.AsyncClient(transport=DenyExternalTransport()) as http:
        with pytest.raises(CentralError) as error:
            await http.get("https://must-not-be-called.invalid")
        assert error.value.code == "SIMULATION_NETWORK_DISABLED"


@pytest.mark.anyio
async def test_harness_persists_replays_and_uses_same_journal(simulation_environment):
    arguments = parser()
    identifier = str(uuid4())
    first = await execute(
        arguments.parse_args(["run", "OPEN_INSERTION_DOOR", "--id", identifier]),
        data_directory=simulation_environment,
    )
    assert first["accepted"]["phase"] == "ACCEPTED"
    assert (
        first["result"]["phase"] == "COMPLETED"
        and first["result"]["source"] == "SIMULATED"
    )
    replay = await execute(
        arguments.parse_args(["replay", identifier]),
        data_directory=simulation_environment,
    )
    assert replay["result"] == first["result"]
    shown = await execute(
        arguments.parse_args(["show", identifier]),
        data_directory=simulation_environment,
    )
    assert len(shown["history"]) == 4
    with sqlite3.connect(simulation_environment / DATABASE_NAME) as conn:
        assert (
            conn.execute("SELECT count(*) FROM mechanical_commands").fetchone()[0] == 1
        )
        assert conn.execute(
            "SELECT state,physical_confirmed,payload,receipt FROM cycles"
        ).fetchone() == ("PHYSICAL_BLOCKED", 0, None, None)


@pytest.mark.anyio
@pytest.mark.parametrize(
    "outcome,phase",
    [("FAILURE", "FAILED"), ("TIMEOUT", "TIMED_OUT"), ("UNAVAILABLE", "REJECTED")],
)
async def test_harness_handles_faults_without_real_effects(
    simulation_environment, monkeypatch, outcome, phase
):
    monkeypatch.setenv(
        "BINGO_SIMULATION_PLANS",
        json.dumps(
            {"OPEN_INSERTION_DOOR": {"duration_seconds": 0.0, "outcome": outcome}}
        ),
    )
    result = await execute(
        parser().parse_args(["run", "OPEN_INSERTION_DOOR", "--timeout", "0.01"]),
        data_directory=simulation_environment,
    )
    assert result["result"]["phase"] == phase
    assert result["result"]["source"] == "SIMULATED"


@pytest.mark.anyio
async def test_harness_recovers_unknown_without_redispatch(simulation_environment):
    with TestClient(
        create_simulation_app(data_directory=simulation_environment)
    ) as client:
        store = client.app.state.sessions.store
        session = store.create(uuid4(), "class_only", uuid4(), "Simulation")
        store.change(session.event_id, "SAFETY", "PHYSICAL_BLOCKED")
        request = MechanicalCommand(
            event_id=session.event_id, operation="OPEN_INSERTION_DOOR"
        )
        entry, _ = store.mechanical.request(request, source="SIMULATED")
        store.mechanical.claim(request.mechanical_command_id, version=entry.version)
    result = await execute(
        parser().parse_args(["replay", str(request.mechanical_command_id)]),
        data_directory=simulation_environment,
    )
    assert result["result"]["phase"] == "INDETERMINATE"
    assert result["result"]["result"] == "UNKNOWN"
    with TestClient(
        create_simulation_app(data_directory=simulation_environment)
    ) as client:
        assert not client.app.state.controller._responses
        assert client.app.state.sessions.store.active().state == "INDETERMINATE"


def test_simulated_success_does_not_enable_registration_or_physical_confirmation(
    simulation_environment,
):
    application = create_simulation_app(data_directory=simulation_environment)
    with TestClient(
        application, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        store = application.state.sessions.store
        session = store.create(uuid4(), "class_only", uuid4(), "Simulation")
        store.change(session.event_id, "SAFETY", "PHYSICAL_BLOCKED")
        request = MechanicalCommand(
            event_id=session.event_id, operation="CYCLE_LOWER_HATCH"
        )
        client.portal.call(application.state.mechanical.submit, request)
        final = client.portal.call(
            application.state.mechanical.wait, request.mechanical_command_id
        )
        assert final.phase == "COMPLETED" and final.source == "SIMULATED"
        assert (
            client.post(
                f"/local/sessions/{session.event_id}/retry-registration", json={}
            ).status_code
            == 409
        )
        for path in ("/local/controller", f"/local/sessions/{session.event_id}/open"):
            assert client.post(path, json={}).status_code == 404
        with store.transaction() as conn:
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt FROM cycles"
                ).fetchone()
            ) == (0, None, None)
        # Mesmo uma fixture elegível forjada não tem destino econômico nesse perfil.
        payload = DepositPayload(
            event_id=session.event_id,
            class_id=session.class_id,
            student_id=None,
            is_valid=True,
            detected_type="cable",
            waste_category_code="CABLE_WIRE",
            category_source="AI_CONFIRMED",
        )
        with store.transaction() as conn:
            conn.execute(
                "UPDATE cycles SET state='REGISTRATION_PENDING',physical_confirmed=1,payload=?,central_scope='foreign'",
                (payload.model_dump_json(),),
            )
        with pytest.raises(CycleError):
            client.portal.call(
                application.state.sessions.retry_registration, session.event_id
            )


def test_simulation_and_operational_files_do_not_share_state(
    simulation_environment, monkeypatch, tmp_path
):
    operational = tmp_path / "operational.sqlite3"
    store = CycleStore(operational)
    original = store.create(uuid4(), "class_only", uuid4(), "Operational fixture")
    store.close()
    before = operational.read_bytes()
    with TestClient(create_simulation_app(data_directory=simulation_environment)):
        pass
    assert operational.read_bytes() == before
    assert operational != simulation_environment / DATABASE_NAME
    with sqlite3.connect(operational) as conn:
        assert conn.execute("SELECT event_id,state FROM cycles").fetchone() == (
            str(original.event_id),
            "SAFETY",
        )
