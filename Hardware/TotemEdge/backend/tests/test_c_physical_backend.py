"""Python lifecycle + actual C IPC/journal/executor through the existing harness.

Only sysfs/clock fault-injection and child launch routing are test-controlled.
No real PWM, alternate protocol, simulator, service or operational unlock flag.
"""

import asyncio
import json
import sqlite3
import sys
from uuid import uuid4

import httpx2 as httpx
import pytest

from app.main import create_app
from app.mechanical import ControllerError
from app.services.c_controller import CProcessController
from app.services.controller import UnavailableController
from app.services.controller_config import JOINT_COMMAND_TIMEOUT_SECONDS
from app.services.mechanical import MechanicalService
from app.storage import CycleStore
from test_c_controller import binaries, command
from test_c_project_mapping import project_configuration
from test_c_pwm_driver import native
from test_mechanical_journal import blocked

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")


@pytest.fixture
async def setup(binaries, native, tmp_path, monkeypatch):
    config, data = project_configuration(binaries, tmp_path, historical=False)
    data["io_timeout_seconds"] = 0.5
    config.write_text(json.dumps(data))
    env = {"config": config, "data": data, "python": tmp_path / "python.db",
           "c": tmp_path / "c.db", "mode": "execute", "frames": []}
    real_spawn = asyncio.create_subprocess_exec
    real_rpc = CProcessController._rpc
    controllers, stores, services = [], [], []

    async def spawn(*args, **kwargs):
        if "--ipc-physical" in args:
            if env.get("mutate_original"):
                changed = json.loads(config.read_text())
                changed["physical"]["right"]["open_pulse_ns"] += 1
                config.write_text(json.dumps(changed))
            # Keep --config's inherited FD: the same frozen JSON reaches C.
            return await real_spawn(str(native), args[-1], env["mode"], "0", "1", "ipc", **kwargs)
        return await real_spawn(*args, **kwargs)

    async def rpc(controller, line, **kwargs):
        env["frames"].append(line)
        if line.startswith("V1 SUBMIT") and controller.source == "PHYSICAL":
            # Independent connection sees committed intent + exact snapshot,
            # and can acquire a write transaction before any IPC write.
            with sqlite3.connect(env["python"], timeout=0, isolation_level=None) as db:
                db.execute("BEGIN IMMEDIATE")
                phase, snapshot = db.execute("""SELECT phase,configuration FROM mechanical_commands
                    JOIN mechanical_controller_bindings USING(mechanical_command_id)""").fetchone()
                assert phase == "DISPATCHING"
                assert snapshot == controller.physical_configuration
                assert db.execute("SELECT count(*) FROM mechanical_history").fetchone() == (2,)
                db.rollback()
        return await real_rpc(controller, line, **kwargs)

    monkeypatch.setattr(asyncio, "create_subprocess_exec", spawn)
    monkeypatch.setattr(CProcessController, "_rpc", rpc)

    async def connect(store=None):
        if store is None:
            store = CycleStore(env["python"])
            stores.append(store)
        controller = await CProcessController._connect_joint(config, backend_journal=env["python"])
        controllers.append(controller)

        def forbidden_kill():
            pytest.fail("Physical lifecycle must never SIGKILL the executor")

        monkeypatch.setattr(controller._process, "kill", forbidden_kill)
        service = MechanicalService(store, controller, source="PHYSICAL")
        services.append(service)
        return store, controller, service

    env["connect"] = connect
    try:
        yield env
    finally:
        for service in services:
            await service.aclose()
        for controller in controllers:
            await controller.aclose()
        for store in stores:
            store.close()


def c_rows(env):
    with sqlite3.connect(env["c"]) as db:
        assert db.execute("PRAGMA user_version").fetchone() == (4,)
        return db.execute("SELECT id,event,state,result,error,source,configuration FROM orders").fetchall()


def no_deposit_completion(store):
    with store.transaction() as db:
        row = db.execute("SELECT * FROM cycles").fetchone()
        assert row["state"] in {"PHYSICAL_BLOCKED", "INDETERMINATE"}
        assert row["active_slot"] == 1 and row["physical_confirmed"] == 0
        assert all(row[key] is None for key in ("payload", "receipt", "central_scope"))


def submits(env):
    return [f for f in env["frames"] if f.startswith("V1 SUBMIT")]


@pytest.mark.anyio
async def test_joint_success_is_operational_and_budget_outlasts_short_ipc_timeout(setup):
    env = setup
    env["mode"] = "execute-pause"
    store, controller, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", JOINT_COMMAND_TIMEOUT_SECONDS)
    start = asyncio.get_running_loop().time()
    accepted = await service.submit(request)
    assert accepted.phase == "ACCEPTED"
    final = await service.wait(request.mechanical_command_id)
    assert asyncio.get_running_loop().time() - start >= 0.7  # > configured 0.5 s IPC ack budget
    assert (final.phase, final.result, final.source) == ("COMPLETED", "SUCCEEDED", "PHYSICAL")
    assert [e.phase for e in store.mechanical.history(request.mechanical_command_id)] == [
        "INTENT", "DISPATCHING", "ACCEPTED", "COMPLETED"]
    assert await service.submit(request) == final and len(submits(env)) == 1
    row = c_rows(env)[0]
    assert row[:4] == (str(request.mechanical_command_id), str(request.event_id), "COMPLETED", "SUCCEEDED")
    assert row[6] == store.mechanical.controller_configuration(request.mechanical_command_id)
    no_deposit_completion(store)
    assert request.timeout_seconds == 30 and controller.readiness.execution_ready is False


@pytest.mark.anyio
@pytest.mark.parametrize("mode", ["execute-open-2", "execute-close-2", "execute-interrupt-hold", "execute-interrupt-settle", "execute-timeout"])
async def test_c_partial_failure_interruption_and_timeout_block_without_retry(setup, mode):
    env = setup
    env["mode"] = mode
    store, controller, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    await service.submit(request)
    final = await service.wait(request.mechanical_command_id)
    assert final.result == "UNKNOWN" and final.phase in {"FAILED", "INDETERMINATE"}
    assert c_rows(env)[0][2:4] == ("FAILED", "UNKNOWN")
    assert await service.submit(request) == final
    assert len(submits(env)) == 1
    with pytest.raises(ControllerError):
        await service.submit(command(request.event_id, "CYCLE_LOWER_HATCH", 30))
    no_deposit_completion(store)


@pytest.mark.anyio
@pytest.mark.parametrize("action", ["timeout", "cancel", "shutdown", "disconnect"])
async def test_python_uncertainty_inhibits_without_force_kill_or_redispatch(setup, action):
    env = setup
    env["mode"] = "execute-pause"
    store, controller, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    await service.submit(request)
    if action == "timeout":
        # Fault-inject the adapter's remaining monotonic GET deadline only;
        # never change persisted identity or approved mechanical durations.
        controller._deadlines[request.mechanical_command_id] = asyncio.get_running_loop().time() + 0.01
    elif action == "cancel":
        await service.cancel(request.mechanical_command_id)
    elif action == "shutdown":
        await service.aclose()
    else:
        await controller.aclose()
    final = await service.wait(request.mechanical_command_id)
    assert final.result == "UNKNOWN" and final.phase in {"INDETERMINATE", "TIMED_OUT", "CANCELLED"}
    assert c_rows(env)[0][2:4] == ("FAILED", "UNKNOWN")
    assert len(submits(env)) == 1
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_concurrent_repeated_id_has_one_intent_snapshot_and_submit(setup):
    env = setup
    env["mode"] = "execute-pause"
    store, _, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    await asyncio.gather(service.submit(request), service.submit(request))
    final = await service.wait(request.mechanical_command_id)
    assert final.phase == "COMPLETED" and len(submits(env)) == 1 and len(c_rows(env)) == 1
    with pytest.raises(ControllerError):
        await service.submit(request.model_copy(update={"event_id": uuid4()}))
    assert len(store.mechanical.history(request.mechanical_command_id)) == 4


@pytest.mark.anyio
@pytest.mark.parametrize("case", ["completed_without_python_observation", "crashed_c", "never_dispatched"])
async def test_restart_recovers_by_get_only_and_keeps_indeterminate_history(setup, case):
    env = setup
    if case == "crashed_c":
        env["mode"] = "execute-crash"
    store, controller, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    entry, _ = store.mechanical.request(request, source="PHYSICAL", configuration=controller.physical_configuration)
    entry = store.mechanical.claim(request.mechanical_command_id, version=entry.version)
    if case == "completed_without_python_observation":
        accepted = await controller.submit(request)
        store.mechanical.observe(request.mechanical_command_id, accepted, version=entry.version)
        assert (await controller.wait(request.mechanical_command_id)).state == "COMPLETED"
    elif case == "crashed_c":
        try:
            await controller.submit(request)
            await controller.wait(request.mechanical_command_id)
        except (ControllerError, BrokenPipeError, ConnectionResetError):
            pass
    await service.aclose()
    store.close()
    env["mode"] = "execute"
    store2, _, service2 = await env["connect"]()
    recovered = service2.get(request.mechanical_command_id)
    assert recovered.phase == "INDETERMINATE" and recovered.result == "UNKNOWN"
    old_history = store2.mechanical.history(request.mechanical_command_id)
    final = await service2.reconcile(request.mechanical_command_id)
    assert final.phase == "INDETERMINATE" and final.result == "UNKNOWN"
    expected = {"completed_without_python_observation": "RECOVERY_C_COMPLETED_SUCCEEDED",
                "crashed_c": "RECOVERY_C_FAILED_UNKNOWN", "never_dispatched": "RECOVERY_C_NOT_FOUND"}
    assert final.error_code == expected[case]
    assert store2.mechanical.history(request.mechanical_command_id)[:-1] == old_history
    assert await service2.reconcile(request.mechanical_command_id) == final
    assert await service2.submit(request) == final
    assert len(submits(env)) == (0 if case == "never_dispatched" else 1)
    no_deposit_completion(store2)


@pytest.mark.anyio
async def test_frozen_configuration_and_immutable_bindings_prevent_snapshot_drift(setup):
    env = setup
    env["mutate_original"] = True
    store, controller, service = await env["connect"]()
    original_snapshot = controller.physical_configuration
    assert json.loads(original_snapshot) != json.loads(env["config"].read_text())
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    await service.submit(request)
    await service.wait(request.mechanical_command_id)
    assert c_rows(env)[0][6] == original_snapshot
    with store.transaction() as db:
        for sql in ("UPDATE mechanical_controller_bindings SET configuration='changed'", "DELETE FROM mechanical_controller_bindings"):
            with pytest.raises(sqlite3.IntegrityError):
                db.execute(sql)
    await service.aclose()
    env["mutate_original"] = False
    _, _, service2 = await env["connect"](store)
    with pytest.raises(ControllerError) as error:
        await service2.submit(request)
    assert error.value.code == "MECHANICAL_CONFIG_SNAPSHOT_CONFLICT"
    assert len(submits(env)) == 1


@pytest.mark.anyio
@pytest.mark.parametrize("operation,timeout", [("CYCLE_LOWER_HATCH", 10), ("CYCLE_LOWER_HATCH", 29), ("CONFIRM_INITIAL_STATE", 30), ("OPEN_INSERTION_DOOR", 30)])
async def test_invalid_physical_budget_or_operation_never_creates_intent_or_dispatch(setup, operation, timeout):
    env = setup
    store, _, service = await env["connect"]()
    request = command(blocked(store).event_id, operation, timeout)
    with pytest.raises(ControllerError) as error:
        await service.submit(request)
    assert error.value.code == "INVALID_PHYSICAL_COMMAND_POLICY"
    assert submits(env) == [] and c_rows(env) == []
    with store.transaction() as db:
        assert db.execute("SELECT count(*) FROM mechanical_commands").fetchone()[0] == 0


@pytest.mark.anyio
async def test_unbound_physical_adapter_cannot_submit_without_durable_python_intent(setup):
    env = setup
    store, controller, _ = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    with pytest.raises(ControllerError):
        await controller.submit(request)
    assert submits(env) == [] and c_rows(env) == []


@pytest.mark.anyio
@pytest.mark.parametrize("broken", ["request", "claim"])
async def test_persistence_failure_prevents_c_dispatch(setup, monkeypatch, broken):
    env = setup
    store, _, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)

    def fail(*args, **kwargs):
        raise sqlite3.OperationalError("injected persistence failure")

    monkeypatch.setattr(store.mechanical, broken, fail)
    with pytest.raises(sqlite3.OperationalError):
        await service.submit(request)
    assert submits(env) == [] and c_rows(env) == []


@pytest.mark.anyio
async def test_wrong_source_response_is_unknown_and_never_confirms_deposit(setup, monkeypatch):
    env = setup
    store, controller, service = await env["connect"]()
    real = controller._rpc

    async def wrong_source(line, **kwargs):
        parts = await real(line, **kwargs)
        if line.startswith("V1 SUBMIT"):
            parts[-1] = "SIMULATED"
        return parts

    monkeypatch.setattr(controller, "_rpc", wrong_source)
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    result = await service.submit(request)
    assert result.phase == "INDETERMINATE" and result.result == "UNKNOWN"
    assert await service.submit(request) == result and len(submits(env)) == 1
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_c_busy_rejection_keeps_its_unavailable_source_without_forging_physical_success(setup):
    env = setup
    store, controller, service = await env["connect"]()
    with sqlite3.connect(env["c"]) as db:
        db.execute("INSERT INTO orders VALUES(?,?,'CYCLE_LOWER_HATCH','30','FAILED','UNKNOWN','EXECUTION_ERROR','doorless-v1','PHYSICAL',?)",
            (str(uuid4()), str(uuid4()), controller.physical_configuration))
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    final = await service.submit(request)
    assert final.phase == "REJECTED" and final.result == "UNAVAILABLE"
    assert final.source == "PHYSICAL"  # immutable intent/capability source
    assert controller.get(request.mechanical_command_id).source == "UNAVAILABLE"  # actual V1 response
    assert final.error_code == "CONTROLLER_BUSY" and len(submits(env)) == 1
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_cancelled_dispatch_persists_unknown_before_returning_cancellation(setup, monkeypatch):
    env = setup
    env["mode"] = "execute-pause"
    store, controller, service = await env["connect"]()
    reading = asyncio.Event()

    async def blocked_read():
        reading.set()
        await asyncio.Event().wait()

    monkeypatch.setattr(controller._process.stdout, "readline", blocked_read)
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    task = asyncio.create_task(service.submit(request))
    await asyncio.wait_for(reading.wait(), 2)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    final = service.get(request.mechanical_command_id)
    assert (final.phase, final.result) == ("INDETERMINATE", "UNKNOWN")
    assert await service.submit(request) == final and len(submits(env)) == 1
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_fastapi_lifecycle_uses_existing_service_for_controlled_physical_capability(setup, monkeypatch):
    env = setup
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(env["python"]))
    controller = await CProcessController._connect_joint(env["config"], backend_journal=env["python"])
    app = create_app(controller_factory=lambda: controller)
    async with app.router.lifespan_context(app):
        assert app.state.mechanical.source == "PHYSICAL"
        store = app.state.sessions.store
        request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
        await app.state.mechanical.submit(request)
        assert (await app.state.mechanical.wait(request.mechanical_command_id)).phase == "COMPLETED"
        no_deposit_completion(store)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            assert (await client.get("/health")).json() == {"status": "ok"}
    assert controller._process.returncode == 0 and len(submits(env)) == 1


@pytest.mark.anyio
async def test_production_fastapi_gate_does_not_launch_physical_executor(setup, monkeypatch):
    env = setup
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(env["python"]))
    monkeypatch.setenv("BINGO_C_CONTROLLER_CONFIG", str(env["config"]))
    app = create_app()
    async with app.router.lifespan_context(app):
        assert isinstance(app.state.controller, UnavailableController)
        assert app.state.mechanical.source == "UNAVAILABLE"
        assert not app.state.controller_readiness.execution_ready
        assert app.state.controller_readiness.physical_command_timeout_seconds == 30
        assert "PHYSICAL_SUPERVISION_PENDING" in app.state.controller_readiness.blockers
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            assert (await client.get("/health")).json() == {"status": "ok"}
    assert not env["c"].exists() and env["frames"] == []


@pytest.mark.anyio
async def test_legacy_python_v4_adds_no_inferred_binding_or_reexecution(setup):
    env = setup
    old = CycleStore(env["python"])
    request = command(blocked(old).event_id, "CYCLE_LOWER_HATCH", 10)
    entry, _ = old.mechanical.request(request, source="PHYSICAL")  # historical, unbound ID
    old.mechanical.claim(request.mechanical_command_id, version=entry.version)
    prior = old.mechanical.history(request.mechanical_command_id)
    old.close()
    with sqlite3.connect(env["python"]) as db:
        db.execute("DROP TABLE mechanical_controller_bindings")
    store, _, service = await env["connect"]()
    assert service.get(request.mechanical_command_id).command == request
    assert service.get(request.mechanical_command_id).phase == "INDETERMINATE"
    assert store.mechanical.history(request.mechanical_command_id)[:-1] == prior
    assert store.mechanical.controller_configuration(request.mechanical_command_id) is None
    with pytest.raises(ControllerError) as error:
        await service.reconcile(request.mechanical_command_id)
    assert error.value.code == "MECHANICAL_CONFIG_SNAPSHOT_CONFLICT"
    assert env["frames"] == [] and c_rows(env) == []
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_get_refuses_same_identity_from_another_c_configuration_snapshot(setup):
    env = setup
    store, controller, service = await env["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    entry, _ = store.mechanical.request(request, source="PHYSICAL", configuration=controller.physical_configuration)
    entry = store.mechanical.claim(request.mechanical_command_id, version=entry.version)
    store.mechanical.unknown(request.mechanical_command_id, version=entry.version, code="INJECTED_LOST_ACK")
    other = json.loads(controller.physical_configuration)
    other["physical"]["left"]["open_pulse_ns"] += 1
    with sqlite3.connect(env["c"]) as db:
        db.execute("INSERT INTO orders VALUES(?,?,'CYCLE_LOWER_HATCH','30','COMPLETED','SUCCEEDED','-','doorless-v1','PHYSICAL',?)",
            (str(request.mechanical_command_id), str(request.event_id), json.dumps(other)))
    recovered = await service.reconcile(request.mechanical_command_id)
    assert recovered.phase == "INDETERMINATE" and recovered.error_code == "RECOVERY_CONFIG_SNAPSHOT_CONFLICT"
    assert submits(env) == []
    assert json.loads(c_rows(env)[0][6]) == other
    no_deposit_completion(store)


@pytest.mark.anyio
async def test_failed_fastapi_composition_closes_the_child_cooperatively(setup, monkeypatch):
    env = setup
    controller = await CProcessController._connect_joint(env["config"], backend_journal=env["python"])
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(env["python"].with_name("different-python.db")))
    app = create_app(controller_factory=lambda: controller)
    with pytest.raises(ValueError, match="bound Python journal"):
        async with app.router.lifespan_context(app):
            pytest.fail("Mismatched journal must block composition")
    assert controller._process.returncode == 0
    assert c_rows(env) == [] and env["frames"] == []
