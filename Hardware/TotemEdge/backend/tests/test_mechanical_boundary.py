"""Contrato do futuro driver com doubles sem transporte, PWM ou hardware."""

import asyncio

import pytest

from app.mechanical import ControllerError, MechanicalCommand, MechanicalResponse
from app.services.mechanical import MechanicalService
from app.storage import CycleStore
from test_mechanical_journal import blocked, request_for, response


class ControlledController:
    """Double independente do simulador; não implementa driver de produção."""

    def __init__(self, *, hanging_submit=False, suppress_cancel=False):
        self.hanging_submit = hanging_submit
        self.suppress_cancel = suppress_cancel
        self.calls = []
        self.result = asyncio.get_running_loop().create_future()
        self.cancel_calls = 0

    async def submit(self, command):
        self.calls.append(command)
        if self.hanging_submit:
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                if not self.suppress_cancel:
                    raise
        return response(command)

    def get(self, identifier):
        assert identifier == self.calls[0].mechanical_command_id
        return self.result.result() if self.result.done() else response(self.calls[0])

    async def wait(self, identifier):
        assert identifier == self.calls[0].mechanical_command_id
        try:
            return await asyncio.shield(self.result)
        except asyncio.CancelledError:
            if not self.suppress_cancel:
                raise
            return response(self.calls[0], "COMPLETED")

    async def cancel(self, identifier):
        self.cancel_calls += 1
        raise AssertionError("Timeout não pode solicitar parada/movimento físico.")

    async def aclose(self):
        if not self.result.done():
            self.result.cancel()


@pytest.fixture
def store(tmp_path):
    value = CycleStore(tmp_path / "boundary.sqlite3")
    yield value
    value.close()


def assert_no_physical_or_economic_evidence(store):
    with store.transaction() as conn:
        row = conn.execute("SELECT * FROM cycles WHERE active_slot=1").fetchone()
        assert row["physical_confirmed"] == 0
        assert row["payload"] is None and row["receipt"] is None


@pytest.mark.anyio
@pytest.mark.parametrize("hanging_submit", [False, True])
@pytest.mark.parametrize("suppress_cancel", [False, True])
async def test_backend_deadline_blocks_late_results_and_restart_replay(
    store, hanging_submit, suppress_cancel
):
    controller = ControlledController(
        hanging_submit=hanging_submit, suppress_cancel=suppress_cancel
    )
    service = MechanicalService(store, controller, source="SIMULATED")
    command = request_for(blocked(store), timeout_seconds=0.05)
    try:
        await asyncio.wait_for(service.submit(command), 2.0)
        final = await asyncio.wait_for(service.wait(command.mechanical_command_id), 2.0)
        assert (final.phase, final.result) == (
            "INDETERMINATE" if hanging_submit else "TIMED_OUT",
            "UNKNOWN",
        )
        assert final.error_code == (
            "DISPATCH_TIMEOUT" if hanging_submit else "EXECUTION_TIMEOUT"
        )
        assert final.command == command
        history = store.mechanical.history(command.mechanical_command_id)
        assert [event.phase for event in history] == (
            ["INTENT", "DISPATCHING", "INDETERMINATE"]
            if hanging_submit
            else ["INTENT", "DISPATCHING", "ACCEPTED", "TIMED_OUT"]
        )
        # O dispositivo pode terminar depois da expiração da consulta Python.
        controller.result.set_result(response(command, "COMPLETED"))
        assert controller.get(command.mechanical_command_id).state == "COMPLETED"
        assert await service.submit(command) == final
        with pytest.raises(ControllerError):
            store.mechanical.observe(
                command.mechanical_command_id,
                controller.result.result(),
                version=final.version,
            )
        with pytest.raises(ControllerError):
            await service.submit(request_for(store.active()))
        assert store.mechanical.history(command.mechanical_command_id) == history
        assert controller.calls == [command] and controller.cancel_calls == 0
        assert store.active().state == "INDETERMINATE"
        assert_no_physical_or_economic_evidence(store)
    finally:
        await service.aclose()

    store.close()
    recovered = CycleStore(store.path)
    fresh_controller = ControlledController()
    fresh_service = MechanicalService(recovered, fresh_controller, source="SIMULATED")
    try:
        assert await fresh_service.submit(command) == final
        assert recovered.mechanical.history(command.mechanical_command_id) == history
        assert recovered.active().state == "INDETERMINATE"
        assert not fresh_controller.calls
    finally:
        await fresh_service.aclose()
        recovered.close()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "operation",
    [
        "OPEN_INSERTION_DOOR",
        "CLOSE_INSERTION_DOOR",
        "CYCLE_LOWER_HATCH",
        "CONFIRM_INITIAL_STATE",
    ],
)
async def test_existing_boundary_preserves_identity_and_one_deadline(
    store, monkeypatch, operation
):
    deadlines = []
    original_timeout = asyncio.timeout_at

    def record_deadline(deadline):
        deadlines.append(deadline)
        return original_timeout(deadline)

    monkeypatch.setattr(asyncio, "timeout_at", record_deadline)
    controller = ControlledController()
    service = MechanicalService(store, controller, source="SIMULATED")
    command = MechanicalCommand(event_id=blocked(store).event_id, operation=operation)
    try:
        accepted = await service.submit(command)
        assert (accepted.phase, accepted.result) == ("ACCEPTED", "PENDING")
        assert await service.submit(command) == accepted
        controller.result.set_result(response(command, "COMPLETED"))
        final = await service.wait(command.mechanical_command_id)
        assert final.command == command
        assert (final.phase, final.result) == ("COMPLETED", "SUCCEEDED")
        assert len(deadlines) == 2 and deadlines[0] == deadlines[1]
        history = store.mechanical.history(command.mechanical_command_id)
        assert (
            store.mechanical.observe(
                command.mechanical_command_id, controller.result.result(), version=0
            )
            == final
        )
        assert store.mechanical.history(command.mechanical_command_id) == history
        assert controller.calls == [command]
        assert store.active().state == "PHYSICAL_BLOCKED"
        assert_no_physical_or_economic_evidence(store)
    finally:
        await service.aclose()


@pytest.mark.anyio
async def test_partial_failure_keeps_reservation_and_never_dispatches_again(store):
    controller = ControlledController()
    service = MechanicalService(store, controller, source="SIMULATED")
    command = request_for(blocked(store))
    try:
        await service.submit(command)
        # Falha após possível efeito parcial não informa posição final segura.
        controller.result.set_result(
            MechanicalResponse(
                command=command,
                state="FAILED",
                result="FAILURE",
                error_code="OPERATION_FAILED",
            )
        )
        final = await service.wait(command.mechanical_command_id)
        assert (final.phase, final.result) == ("FAILED", "FAILURE")
        assert store.active().state == "INDETERMINATE"
        assert await service.submit(command) == final
        with pytest.raises(ControllerError):
            await service.submit(request_for(store.active()))
        assert controller.calls == [command]
        assert_no_physical_or_economic_evidence(store)
    finally:
        await service.aclose()


@pytest.mark.anyio
async def test_wait_returning_only_acceptance_becomes_unknown(store):
    controller = ControlledController()
    service = MechanicalService(store, controller, source="SIMULATED")
    command = request_for(blocked(store))
    try:
        await service.submit(command)
        controller.result.set_result(response(command))
        final = await service.wait(command.mechanical_command_id)
        assert (final.phase, final.result) == ("INDETERMINATE", "UNKNOWN")
        assert final.error_code == "INCONSISTENT_RESPONSE"
        assert store.active().state == "INDETERMINATE"
        assert await service.submit(command) == final
        assert controller.calls == [command]
        assert_no_physical_or_economic_evidence(store)
    finally:
        await service.aclose()
