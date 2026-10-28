"""Contrato mecânico privado: relógio manual, nenhum hardware ou serviço real."""

import asyncio
import builtins
import socket
import sqlite3
from uuid import uuid4

import httpx2 as httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.cycles import CycleError
from app.main import create_app
from app.mechanical import (
    ControllerError,
    MechanicalCommand,
    MechanicalController,
    MechanicalResponse,
    checked_response,
)
from app.services.controller import (
    DEFAULT_PLANS,
    SimulatedController,
    SimulationPlan,
    UnavailableController,
)
from test_sessions import CLASS, seed_persisted_state


class ManualClock:
    def __init__(self):
        self.now = 0.0
        self.calls = []
        self.pending = []

    async def sleep(self, seconds):
        self.calls.append(seconds)
        future = asyncio.get_running_loop().create_future()
        self.pending.append((self.now + seconds, future))
        try:
            await future
        finally:
            self.pending = [(at, f) for at, f in self.pending if f is not future]

    async def advance(self, seconds):
        # Inicia tarefas recém aceitas antes de avançar o relógio virtual.
        await asyncio.sleep(0)
        self.now += seconds
        for at, future in tuple(self.pending):
            if at <= self.now and not future.done():
                future.set_result(None)
        await asyncio.sleep(0)


@pytest.fixture
async def simulation(anyio_backend):
    clock = ManualClock()
    controller = SimulatedController(context="test", sleep=clock.sleep)
    try:
        yield controller, clock
    finally:
        await controller.aclose()
        assert not clock.pending


def command(operation="OPEN_INSERTION_DOOR", **kwargs):
    return MechanicalCommand(
        event_id=kwargs.pop("event_id", uuid4()), operation=operation, **kwargs
    )


def test_requested_contract_has_separate_identity_and_is_immutable():
    event_id = uuid4()
    first = MechanicalCommand(event_id=event_id, operation="OPEN_INSERTION_DOOR")
    second = MechanicalCommand(event_id=event_id, operation="CLOSE_INSERTION_DOOR")
    assert first.state == second.state == "REQUESTED"
    assert first.mechanical_command_id != second.mechanical_command_id
    assert first.event_id == second.event_id
    with pytest.raises(ValidationError):
        first.event_id = uuid4()
    with pytest.raises(ValidationError):
        MechanicalCommand(**first.model_dump(), command_id=uuid4())
    with pytest.raises(ValidationError):
        MechanicalCommand(**first.model_dump(), physical_confirmed=True)


@pytest.mark.parametrize("seconds", [0, -1, float("inf"), float("nan"), True, "3"])
def test_invalid_command_timeout_is_rejected(seconds):
    with pytest.raises(ValidationError):
        command(timeout_seconds=seconds)


@pytest.mark.parametrize("operation", ["GPIO", "RETURN_OBJECT", "", None])
def test_undocumented_operations_are_rejected(operation):
    with pytest.raises(ValidationError):
        command(operation)


@pytest.mark.parametrize("context", ["operational", "production", "", None])
def test_simulator_requires_explicit_isolated_context(context):
    with pytest.raises(ValueError):
        SimulatedController(context=context)


@pytest.mark.parametrize("seconds", [-1, float("inf"), float("nan"), True, "3"])
def test_invalid_simulated_duration_is_rejected(seconds):
    with pytest.raises(ValidationError):
        SimulationPlan(duration_seconds=seconds)


@pytest.mark.anyio
@pytest.mark.parametrize("operation", list(DEFAULT_PLANS))
async def test_unavailable_implements_same_contract_without_acceptance(operation):
    controller: MechanicalController = UnavailableController()
    request = command(operation)
    try:
        response = await controller.submit(request)
        assert response.command == request
        assert (response.state, response.result, response.source) == (
            "REJECTED",
            "UNAVAILABLE",
            "UNAVAILABLE",
        )
        assert response.error_code == "CONTROLLER_UNAVAILABLE"
        assert await controller.submit(request) == response
        assert controller.get(request.mechanical_command_id) == response
        assert await controller.wait(request.mechanical_command_id) == response
        assert await controller.cancel(request.mechanical_command_id) == response
        with pytest.raises(ControllerError) as error:
            await controller.submit(request.model_copy(update={"event_id": uuid4()}))
        assert error.value.code == "MECHANICAL_COMMAND_ID_CONFLICT"
    finally:
        await controller.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("operation", list(DEFAULT_PLANS))
async def test_acceptance_precedes_configured_completion(simulation, operation):
    controller, clock = simulation
    request = command(operation)
    accepted = await controller.submit(request)
    assert accepted.command.state == "REQUESTED"
    assert (accepted.state, accepted.result) == ("ACCEPTED", "PENDING")
    assert not clock.calls  # submit retorna antes de começar a espera.
    duration = DEFAULT_PLANS[operation].duration_seconds
    await clock.advance(duration - 0.25)
    assert controller.get(request.mechanical_command_id) == accepted
    await clock.advance(0.25)
    final = await controller.wait(request.mechanical_command_id)
    assert final.command == request
    assert (final.state, final.result, final.source) == (
        "COMPLETED",
        "SUCCEEDED",
        "SIMULATED",
    )
    assert clock.calls == [duration]
    assert accepted.state == "ACCEPTED"  # Snapshot anterior não é mutado.
    assert await controller.cancel(request.mechanical_command_id) == final
    assert await controller.submit(request) == final
    assert clock.calls == [duration]  # Replay terminal não repete o movimento.


@pytest.mark.anyio
async def test_durations_are_configurable_per_operation():
    clock = ManualClock()
    plans = {
        "OPEN_INSERTION_DOOR": SimulationPlan(duration_seconds=0.125),
        "CLOSE_INSERTION_DOOR": SimulationPlan(duration_seconds=0.5),
    }
    controller = SimulatedController(
        context="development", plans=plans, sleep=clock.sleep
    )
    plans.clear()  # Configuração foi copiada.
    try:
        for operation, duration in [
            ("OPEN_INSERTION_DOOR", 0.125),
            ("CLOSE_INSERTION_DOOR", 0.5),
        ]:
            request = command(operation)
            await controller.submit(request)
            await clock.advance(duration)
            assert (
                await controller.wait(request.mechanical_command_id)
            ).state == "COMPLETED"
        assert clock.calls == [0.125, 0.5]
    finally:
        await controller.aclose()


@pytest.mark.anyio
async def test_real_asyncio_timer_is_nonblocking_with_zero_duration():
    controller = SimulatedController(
        context="test",
        plans={"OPEN_INSERTION_DOOR": SimulationPlan(duration_seconds=0.0)},
    )
    request = command()
    try:
        assert (await controller.submit(request)).state == "ACCEPTED"
        assert (
            await controller.wait(request.mechanical_command_id)
        ).state == "COMPLETED"
    finally:
        await controller.aclose()


@pytest.mark.anyio
async def test_duplicate_concurrent_submit_and_conflicting_identity(simulation):
    controller, clock = simulation
    request = command()
    results = await asyncio.gather(*(controller.submit(request) for _ in range(10)))
    assert all(response == results[0] for response in results)
    for update in [
        {"event_id": uuid4()},
        {"operation": "CLOSE_INSERTION_DOOR"},
        {"timeout_seconds": 20.0},
    ]:
        with pytest.raises(ControllerError) as error:
            await controller.submit(request.model_copy(update=update))
        assert error.value.code == "MECHANICAL_COMMAND_ID_CONFLICT"
    await clock.advance(3.0)
    assert clock.calls == [3.0]


@pytest.mark.anyio
async def test_distinct_operations_keep_cycle_correlation_and_refuse_overlap(
    simulation,
):
    controller, clock = simulation
    opening = command()
    closing = MechanicalCommand(
        event_id=opening.event_id, operation="CLOSE_INSERTION_DOOR"
    )
    assert closing.mechanical_command_id != opening.mechanical_command_id
    await controller.submit(opening)
    busy = await controller.submit(closing)
    assert (busy.state, busy.error_code) == ("REJECTED", "CONTROLLER_BUSY")
    await clock.advance(3.0)
    assert await controller.submit(closing) == busy  # Recusa é estável por ID.
    closing = command("CLOSE_INSERTION_DOOR", event_id=opening.event_id)
    # Novo ID é decisão explícita do chamador, nunca retry automático.
    await controller.submit(closing)
    await clock.advance(3.0)
    assert (
        await controller.wait(closing.mechanical_command_id)
    ).command.event_id == opening.event_id
    assert clock.calls == [3.0, 3.0]


@pytest.mark.anyio
@pytest.mark.parametrize(
    "outcome,duration,timeout,state,result,code,elapsed",
    [
        ("FAILURE", 2.0, 10.0, "FAILED", "FAILURE", "OPERATION_FAILED", 2.0),
        (
            "UNAVAILABLE",
            3.0,
            10.0,
            "REJECTED",
            "UNAVAILABLE",
            "CONTROLLER_UNAVAILABLE",
            0.0,
        ),
        ("TIMEOUT", 1.0, 5.0, "TIMED_OUT", "UNKNOWN", "EXECUTION_TIMEOUT", 5.0),
        ("SUCCEEDED", 3.0, 2.0, "TIMED_OUT", "UNKNOWN", "EXECUTION_TIMEOUT", 2.0),
        ("SUCCEEDED", 3.0, 3.0, "TIMED_OUT", "UNKNOWN", "EXECUTION_TIMEOUT", 3.0),
    ],
)
async def test_failure_unavailability_and_timeout_are_controlled(
    outcome, duration, timeout, state, result, code, elapsed
):
    clock = ManualClock()
    controller = SimulatedController(
        context="test",
        sleep=clock.sleep,
        plans={
            "OPEN_INSERTION_DOOR": SimulationPlan(
                duration_seconds=duration, outcome=outcome
            )
        },
    )
    request = command(timeout_seconds=timeout)
    try:
        accepted = await controller.submit(request)
        assert accepted.state == (
            "REJECTED" if outcome == "UNAVAILABLE" else "ACCEPTED"
        )
        await clock.advance(elapsed)
        final = await controller.wait(request.mechanical_command_id)
        assert (final.state, final.result, final.error_code) == (state, result, code)
        assert final.source == "SIMULATED"
        assert clock.calls == ([] if outcome == "UNAVAILABLE" else [elapsed])
        await clock.advance(100.0)
        assert await controller.submit(request) == final
        assert controller.get(request.mechanical_command_id) == final
    finally:
        await controller.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("started", [False, True])
async def test_cancel_before_or_during_execution_drains_tasks(simulation, started):
    controller, clock = simulation
    request = command()
    await controller.submit(request)
    if started:
        await clock.advance(1.0)
    final = await controller.cancel(request.mechanical_command_id)
    assert (final.state, final.result) == ("CANCELLED", "UNKNOWN")
    assert await controller.wait(request.mechanical_command_id) == final
    assert await controller.cancel(request.mechanical_command_id) == final
    assert not clock.pending
    assert not controller._tasks
    await clock.advance(10.0)
    assert await controller.submit(request) == final


@pytest.mark.anyio
async def test_cancelling_waiter_does_not_cancel_accepted_operation(simulation):
    controller, clock = simulation
    request = command()
    await controller.submit(request)
    waiter = asyncio.create_task(controller.wait(request.mechanical_command_id))
    await clock.advance(1.0)
    waiter.cancel()
    with pytest.raises(asyncio.CancelledError):
        await waiter
    assert controller.get(request.mechanical_command_id).state == "ACCEPTED"
    await clock.advance(2.0)
    assert (await controller.wait(request.mechanical_command_id)).state == "COMPLETED"


@pytest.mark.anyio
async def test_concurrent_waiters_observe_the_same_cancellation(simulation):
    controller, clock = simulation
    request = command()
    await controller.submit(request)
    waiters = [
        asyncio.create_task(controller.wait(request.mechanical_command_id))
        for _ in range(3)
    ]
    await clock.advance(1.0)
    cancelled = await controller.cancel(request.mechanical_command_id)
    assert await asyncio.gather(*waiters) == [cancelled] * 3
    assert cancelled.result == "UNKNOWN"


@pytest.mark.anyio
async def test_shutdown_closes_and_preserves_replay(simulation):
    controller, clock = simulation
    request = command()
    await controller.submit(request)
    await clock.advance(1.0)
    await controller.aclose()
    await controller.aclose()
    assert not clock.pending and not controller._tasks
    assert (await controller.submit(request)).result == "UNKNOWN"
    with pytest.raises(ControllerError) as error:
        await controller.submit(command())
    assert error.value.code == "CONTROLLER_CLOSED"


@pytest.mark.anyio
async def test_unexpected_execution_error_is_unknown_and_does_not_leak_details():
    async def broken_sleep(_):
        raise RuntimeError("private-device-detail")

    controller = SimulatedController(context="test", sleep=broken_sleep)
    request = command()
    try:
        await controller.submit(request)
        final = await controller.wait(request.mechanical_command_id)
        assert (final.state, final.result, final.error_code) == (
            "FAILED",
            "UNKNOWN",
            "EXECUTION_ERROR",
        )
        assert "private-device-detail" not in final.model_dump_json()
    finally:
        await controller.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("kind", ["unavailable", "simulated"])
async def test_registry_capacity_does_not_evict_ids_or_dispatch(kind):
    controller = (
        UnavailableController(max_commands=1)
        if kind == "unavailable"
        else SimulatedController(context="test", max_commands=1)
    )
    request = command()
    try:
        response = await controller.submit(request)
        with pytest.raises(ControllerError) as error:
            await controller.submit(command())
        assert error.value.code == "COMMAND_CAPACITY_REACHED"
        assert await controller.submit(request) == response
        with pytest.raises(ControllerError) as error:
            controller.get(uuid4())
        assert error.value.code == "MECHANICAL_COMMAND_NOT_FOUND"
    finally:
        await controller.aclose()


@pytest.mark.parametrize(
    "update",
    [
        {"state": "ACCEPTED"},
        {"result": "PENDING"},
        {"source": "UNAVAILABLE"},
        {"error_code": "EXECUTION_TIMEOUT"},
    ],
)
def test_inconsistent_typed_responses_are_rejected(update):
    data = dict(
        command=command(), state="COMPLETED", result="SUCCEEDED", source="SIMULATED"
    )
    with pytest.raises(ValidationError):
        MechanicalResponse(**{**data, **update})


@pytest.mark.parametrize(
    "case",
    ["id", "cycle", "operation", "timeout", "source", "pending", "malformed", "object"],
)
def test_inconsistent_completions_become_unknown(case):
    request = command()
    response = MechanicalResponse(
        command=request, state="COMPLETED", result="SUCCEEDED"
    )
    updates = {
        "id": {"mechanical_command_id": uuid4()},
        "cycle": {"event_id": uuid4()},
        "operation": {"operation": "CLOSE_INSERTION_DOOR"},
        "timeout": {"timeout_seconds": 20.0},
    }
    if case in updates:
        response = response.model_copy(
            update={"command": request.model_copy(update=updates[case])}
        )
    elif case == "source":
        response = response.model_copy(update={"source": "PHYSICAL"})
    elif case == "pending":
        response = MechanicalResponse(
            command=request, state="ACCEPTED", result="PENDING"
        )
    elif case == "malformed":
        response = response.model_copy(update={"result": "PENDING"})
    else:
        response = object()
    final = checked_response(request, response, source="SIMULATED")
    assert final.command == request
    assert (final.state, final.result, final.error_code) == (
        "FAILED",
        "UNKNOWN",
        "INCONSISTENT_RESPONSE",
    )


@pytest.mark.anyio
async def test_simulation_uses_no_physical_io_or_network(monkeypatch):
    original_import = builtins.__import__

    def guarded_import(name, *args, **kwargs):
        if name.split(".")[0] in {"serial", "RPi", "gpiod", "gpiozero", "OPi"}:
            pytest.fail("Import físico proibido no simulador.")
        return original_import(name, *args, **kwargs)

    def reject_io(*args, **kwargs):
        pytest.fail("Simulador não pode acessar arquivos, dispositivos ou rede.")

    monkeypatch.setattr(builtins, "__import__", guarded_import)
    from app.services.controller import SimulatedController as Controller

    with monkeypatch.context() as guard:
        guard.setattr(builtins, "open", reject_io)
        guard.setattr(socket.socket, "connect", reject_io)
        controller = Controller(
            context="test",
            plans={op: SimulationPlan(duration_seconds=0.0) for op in DEFAULT_PLANS},
        )
        try:
            for operation in DEFAULT_PLANS:
                request = command(operation)
                await controller.submit(request)
                assert (
                    await controller.wait(request.mechanical_command_id)
                ).source == "SIMULATED"
        finally:
            await controller.aclose()


def test_default_composition_is_unavailable_and_internal_only():
    with TestClient(create_app(), base_url="http://127.0.0.1") as client:
        assert isinstance(client.app.state.controller, UnavailableController)
        response = client.portal.call(client.app.state.controller.submit, command())
        assert response.result == "UNAVAILABLE"
        for path in ["/local/controller", "/local/mechanical", "/local/movements"]:
            assert client.post(path, json={}).status_code == 404
        assert client.get("/local/status").json()["can_start_deposit"] is False


def test_injected_simulation_cannot_confirm_physics_or_register_points(
    configured_environment, healthy_body
):
    calls = []

    def upstream(request):
        calls.append(request.url.path)
        return httpx.Response(200, json=healthy_body)

    clock = ManualClock()
    application = create_app(
        transport=httpx.MockTransport(upstream),
        controller_factory=lambda: SimulatedController(
            context="test", sleep=clock.sleep
        ),
    )
    headers = {"X-Totem-Request": "1"}
    with TestClient(
        application, base_url="http://127.0.0.1", headers=headers
    ) as client:
        service = application.state.sessions
        store = service.store
        session_command_id = uuid4()
        session = store.create(
            session_command_id,
            "class_only",
            CLASS,
            "Turma",
            central_scope=service.central.configuration_scope,
        )
        for operation in DEFAULT_PLANS:
            request = MechanicalCommand(event_id=session.event_id, operation=operation)
            assert request.mechanical_command_id != session_command_id
            client.portal.call(application.state.controller.submit, request)
            client.portal.call(clock.advance, DEFAULT_PLANS[operation].duration_seconds)
            final = client.portal.call(
                application.state.controller.wait, request.mechanical_command_id
            )
            assert (final.result, final.source) == ("SUCCEEDED", "SIMULATED")
        assert calls == []  # Nenhuma comunicação central por operação simulada.
        response = client.post(
            f"/local/sessions/{session.event_id}/safety", json={"has_risk": False}
        )
        assert response.json()["state"] == "PHYSICAL_BLOCKED"
        assert (
            client.post(
                f"/local/sessions/{session.event_id}/hand-removed", json={}
            ).status_code
            == 409
        )
        assert (
            client.post(
                f"/local/sessions/{session.event_id}/retry-registration", json={}
            ).status_code
            == 409
        )
        assert (
            client.post(
                f"/local/sessions/{session.event_id}/retry-registration",
                json=final.model_dump(mode="json"),
            ).status_code
            == 422
        )
        status = client.get("/local/status").json()
        assert status["status"] == "OFFLINE" and status["can_start_deposit"] is False
        assert (
            client.post(
                "/local/sessions",
                json={
                    "command_id": str(uuid4()),
                    "mode": "class_only",
                    "class_id": str(CLASS),
                },
            ).status_code
            == 409
        )
        assert store.by_command(session_command_id).event_id == session.event_id
        with store.transaction() as conn:
            assert conn.execute("PRAGMA user_version").fetchone()[0] == 3
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt FROM cycles"
                ).fetchone()
            ) == (0, None, None)
            assert conn.execute("SELECT count(*) FROM cycles").fetchone()[0] == 1
        # Mesmo uma linha pending sem evidência não ganha autorização por simulação.
        service.cancel(session.event_id)
        pending_id, _ = seed_persisted_state(
            store, "REGISTRATION_PENDING", scope=service.central.configuration_scope
        )
        pending_request = MechanicalCommand(
            event_id=pending_id, operation="CYCLE_LOWER_HATCH"
        )
        client.portal.call(application.state.controller.submit, pending_request)
        client.portal.call(clock.advance, 4.0)
        assert (
            client.portal.call(
                application.state.controller.wait, pending_request.mechanical_command_id
            ).result
            == "SUCCEEDED"
        )
        with pytest.raises(CycleError) as error:
            client.portal.call(service.retry_registration, pending_id)
        assert error.value.code == "MISSING_PHYSICAL_EVIDENCE"
        assert all(path.endswith("health-v1") for path in calls)
        assert store.get(pending_id).receipt is None
        with sqlite3.connect(store.path) as conn:
            assert (
                conn.execute("SELECT max(physical_confirmed) FROM cycles").fetchone()[0]
                == 0
            )


@pytest.mark.parametrize("started", [False, True])
def test_lifespan_drains_injected_operation_on_shutdown(started):
    clock = ManualClock()
    application = create_app(
        controller_factory=lambda: SimulatedController(
            context="test", sleep=clock.sleep
        )
    )
    request = command()
    with TestClient(application) as client:
        controller = application.state.controller
        client.portal.call(controller.submit, request)
        if started:
            client.portal.call(clock.advance, 1.0)
        assert controller.get(request.mechanical_command_id).state == "ACCEPTED"
    assert controller.get(request.mechanical_command_id).result == "UNKNOWN"
    assert not controller._tasks and not clock.pending
