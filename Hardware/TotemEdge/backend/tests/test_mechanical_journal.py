"""Journal real em SQLite temporário; sem equipamento ou backend econômico real."""

import asyncio
from concurrent.futures import ThreadPoolExecutor
import sqlite3
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest

from app.cycles import CycleError
from app.central_contracts import DepositPayload
from app.main import create_app
from app.mechanical import ControllerError, MechanicalCommand, MechanicalResponse
from app.services.controller import (
    SimulatedController,
    SimulationPlan,
    UnavailableController,
)
from app.services.mechanical import MechanicalService
from app.storage import CycleStore
import app.storage as storage_module
from test_controller import ManualClock
from test_sessions import CLASS, seed_persisted_state


@pytest.fixture
def store(tmp_path):
    value = CycleStore(tmp_path / "mechanical.sqlite3")
    yield value
    value.close()


def blocked(store):
    session = store.create(uuid4(), "class_only", CLASS, "Turma")
    return store.change(session.event_id, "SAFETY", "PHYSICAL_BLOCKED")


def request_for(session, **kwargs):
    return MechanicalCommand(
        event_id=session.event_id, operation="OPEN_INSERTION_DOOR", **kwargs
    )


def response(command, state="ACCEPTED", source="SIMULATED"):
    pairs = {
        "ACCEPTED": ("PENDING", None),
        "COMPLETED": ("SUCCEEDED", None),
        "REJECTED": ("UNAVAILABLE", "CONTROLLER_UNAVAILABLE"),
    }
    result, error_code = pairs[state]
    return MechanicalResponse(
        command=command,
        state=state,
        result=result,
        source=source,
        error_code=error_code,
    )


def accepted(store, request, source="SIMULATED"):
    entry, created = store.mechanical.request(request, source=source)
    assert created
    entry = store.mechanical.claim(request.mechanical_command_id, version=entry.version)
    return store.mechanical.observe(
        request.mechanical_command_id,
        response(request, source=source),
        version=entry.version,
    )


def restart(store):
    store.close()
    return CycleStore(store.path)


def as_v1(store):
    """As tabelas originais não mudam em v2: remover só as adições produz v1."""
    store.close()
    with sqlite3.connect(store.path) as conn:
        conn.execute("DROP TABLE mechanical_history")
        conn.execute("DROP TABLE mechanical_commands")
        conn.execute("PRAGMA user_version=1")


def test_durable_identity_and_history_without_serialized_payload(store):
    session = blocked(store)
    request = request_for(session)
    entry, fresh = store.mechanical.request(request, source="SIMULATED")
    assert fresh and entry.phase == "INTENT" and entry.result == "PENDING"
    assert entry.command == request
    assert store.mechanical.request(request, source="SIMULATED") == (entry, False)
    assert len(store.mechanical.history(request.mechanical_command_id)) == 1
    with store.transaction() as conn:
        row = conn.execute("SELECT * FROM mechanical_commands").fetchone()
        assert row["event_id"] == str(session.event_id)
        assert (
            row["mechanical_command_id"]
            != conn.execute("SELECT command_id FROM cycles").fetchone()[0]
        )
        assert "payload" not in row.keys() and "fingerprint" not in row.keys()


@pytest.mark.parametrize(
    "update",
    [
        {"event_id": uuid4()},
        {"operation": "CLOSE_INSERTION_DOOR"},
        {"timeout_seconds": 6.0},
    ],
)
def test_semantic_conflict_does_not_add_history(store, update):
    request = request_for(blocked(store))
    original, _ = store.mechanical.request(request, source="SIMULATED")
    with pytest.raises(ControllerError) as error:
        store.mechanical.request(request.model_copy(update=update), source="SIMULATED")
    assert error.value.code == "MECHANICAL_COMMAND_ID_CONFLICT"
    assert store.mechanical.get(request.mechanical_command_id) == original
    assert len(store.mechanical.history(request.mechanical_command_id)) == 1


def test_invalid_or_inactive_cycle_cannot_reserve(store):
    session = store.create(uuid4(), "class_only", CLASS, "Turma")
    with pytest.raises(ControllerError):
        store.mechanical.request(request_for(session), source="SIMULATED")
    with pytest.raises(CycleError):
        store.mechanical.request(
            MechanicalCommand(event_id=uuid4(), operation="OPEN_INSERTION_DOOR"),
            source="SIMULATED",
        )
    store.change(session.event_id, "SAFETY", "CANCELLED", active_slot=None)
    with pytest.raises(ControllerError):
        store.mechanical.request(request_for(session), source="SIMULATED")


def test_database_protects_identity_and_append_only_history(store):
    request = request_for(blocked(store))
    store.mechanical.request(request, source="SIMULATED")
    for statement in [
        "UPDATE mechanical_commands SET timeout_seconds=20",
        "UPDATE mechanical_commands SET source='PHYSICAL'",
        "UPDATE mechanical_history SET phase='COMPLETED'",
        "DELETE FROM mechanical_history",
    ]:
        with pytest.raises(sqlite3.IntegrityError):
            with store.transaction() as conn:
                conn.execute(statement)
    assert store.mechanical.get(request.mechanical_command_id).phase == "INTENT"


@pytest.mark.parametrize("identical", [True, False])
def test_threaded_requests_have_one_identity_and_one_reservation(store, identical):
    session = blocked(store)
    request = request_for(session)

    def attempt(index):
        candidate = request if identical else request_for(session)
        try:
            return store.mechanical.request(candidate, source="SIMULATED")
        except ControllerError as error:
            return error.code

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(attempt, range(8)))
    assert sum(isinstance(item, tuple) and item[1] for item in results) == 1
    assert sum(item == "MECHANICAL_OPERATION_IN_PROGRESS" for item in results) == (
        0 if identical else 7
    )
    with store.transaction() as conn:
        assert (
            conn.execute("SELECT count(*) FROM mechanical_commands").fetchone()[0] == 1
        )
        assert (
            conn.execute("SELECT count(*) FROM mechanical_history").fetchone()[0] == 1
        )


def test_atomic_transition_and_history_rollback(store):
    request = request_for(blocked(store))
    store.mechanical.request(request, source="SIMULATED")
    # Falha no segundo write: UPDATE do estado precisa ser desfeito junto.
    with store.transaction() as conn:
        conn.execute(
            "CREATE TRIGGER fail_history BEFORE INSERT ON mechanical_history WHEN NEW.version=1 BEGIN SELECT RAISE(ABORT,'injected'); END"
        )
    with pytest.raises(sqlite3.IntegrityError):
        store.mechanical.claim(request.mechanical_command_id, version=0)
    assert store.mechanical.get(request.mechanical_command_id).phase == "INTENT"
    assert len(store.mechanical.history(request.mechanical_command_id)) == 1


def test_unknown_result_and_cycle_block_are_one_transaction(store):
    session = blocked(store)
    request = request_for(session)
    entry = accepted(store, request)
    with store.transaction() as conn:
        conn.execute(
            "CREATE TRIGGER fail_cycle_audit BEFORE INSERT ON transitions BEGIN SELECT RAISE(ABORT,'injected'); END"
        )
    with pytest.raises(sqlite3.IntegrityError):
        store.mechanical.unknown(
            request.mechanical_command_id,
            version=entry.version,
            code="DISPATCH_RESULT_UNKNOWN",
        )
    assert store.mechanical.get(request.mechanical_command_id) == entry
    assert len(store.mechanical.history(request.mechanical_command_id)) == 3
    assert store.get(session.event_id).state == "PHYSICAL_BLOCKED"


def test_stale_claim_and_duplicate_confirmation_do_not_reprocess(store):
    request = request_for(blocked(store))
    entry = accepted(store, request)
    with pytest.raises(ControllerError):
        store.mechanical.claim(request.mechanical_command_id, version=0)
    assert (
        store.mechanical.observe(
            request.mechanical_command_id, response(request), version=1
        )
        == entry
    )
    final = store.mechanical.observe(
        request.mechanical_command_id,
        response(request, "COMPLETED"),
        version=entry.version,
    )
    assert (
        store.mechanical.observe(
            request.mechanical_command_id,
            response(request, "COMPLETED"),
            version=entry.version,
        )
        == final
    )
    assert [
        item.phase for item in store.mechanical.history(request.mechanical_command_id)
    ] == ["INTENT", "DISPATCHING", "ACCEPTED", "COMPLETED"]
    with pytest.raises(ControllerError) as error:
        store.mechanical.observe(
            request.mechanical_command_id, response(request), version=1
        )
    assert error.value.code == "MECHANICAL_STALE_RESPONSE"


@pytest.mark.parametrize(
    "case", ["id", "event", "operation", "source", "version", "premature"]
)
def test_incorrect_or_out_of_order_response_is_rejected(store, case):
    request = request_for(blocked(store))
    entry = accepted(store, request)
    candidate = response(request, "COMPLETED")
    changes = {
        "id": {"mechanical_command_id": uuid4()},
        "event": {"event_id": uuid4()},
        "operation": {"operation": "CLOSE_INSERTION_DOOR"},
    }
    if case in changes:
        candidate = candidate.model_copy(
            update={"command": request.model_copy(update=changes[case])}
        )
    elif case == "source":
        candidate = candidate.model_copy(update={"source": "PHYSICAL"})
    elif case == "premature":
        # Conclusão não pode substituir aceitação persistida separadamente.
        other = request_for(store.get(request.event_id))
        store.mechanical.observe(
            request.mechanical_command_id, candidate, version=entry.version
        )
        intent, _ = store.mechanical.request(other, source="SIMULATED")
        entry = store.mechanical.claim(
            other.mechanical_command_id, version=intent.version
        )
        request = other
        candidate = response(other, "COMPLETED")
    with pytest.raises(ControllerError):
        store.mechanical.observe(
            request.mechanical_command_id,
            candidate,
            version=0 if case == "version" else entry.version,
        )
    assert store.mechanical.get(request.mechanical_command_id) == entry


@pytest.mark.parametrize(
    "window",
    ["intent", "dispatch", "accepted", "received_not_saved", "saved", "rejected"],
)
@pytest.mark.parametrize("source", ["SIMULATED", "PHYSICAL"])
def test_restart_at_each_command_boundary(store, window, source):
    session = blocked(store)
    request = request_for(session)
    entry, _ = store.mechanical.request(request, source=source)
    if window != "intent":
        entry = store.mechanical.claim(
            request.mechanical_command_id, version=entry.version
        )
    if window in {"accepted", "received_not_saved", "saved"}:
        entry = store.mechanical.observe(
            request.mechanical_command_id,
            response(request, source=source),
            version=entry.version,
        )
    if window == "saved":
        entry = store.mechanical.observe(
            request.mechanical_command_id,
            response(request, "COMPLETED", source),
            version=entry.version,
        )
    elif window == "received_not_saved":
        received = response(request, "COMPLETED", source)
        assert received.result == "SUCCEEDED"  # Ainda não é evidência durável.
    elif window == "rejected":
        entry = store.mechanical.observe(
            request.mechanical_command_id,
            response(request, "REJECTED", source),
            version=entry.version,
        )
    recovered = restart(store)
    try:
        final = recovered.mechanical.get(request.mechanical_command_id)
        cycle = recovered.get(session.event_id)
        assert final.command == request and final.source == source
        if window == "intent":
            assert (final.phase, final.result, cycle.state) == (
                "ABORTED",
                "UNAVAILABLE",
                "CANCELLED",
            )
            assert recovered.active() is None
        elif window == "rejected":
            assert final == entry and cycle.state == "CANCELLED"
        elif window == "saved":
            assert final == entry
            assert cycle.state == (
                "PHYSICAL_BLOCKED" if source == "SIMULATED" else "INDETERMINATE"
            )
            assert recovered.active().event_id == session.event_id
        else:
            assert (final.phase, final.result, cycle.state) == (
                "INDETERMINATE",
                "UNKNOWN",
                "INDETERMINATE",
            )
            with pytest.raises(CycleError):
                recovered.create(uuid4(), "class_only", CLASS, "Outra")
            with pytest.raises(ControllerError):
                recovered.mechanical.observe(
                    request.mechanical_command_id,
                    response(request, "COMPLETED", source),
                    version=entry.version,
                )
        assert recovered.get(session.event_id).receipt is None
        with recovered.transaction() as conn:
            assert (
                conn.execute("SELECT physical_confirmed FROM cycles").fetchone()[0] == 0
            )
        history = recovered.mechanical.history(request.mechanical_command_id)
    finally:
        recovered.close()
    # Segundo restart não duplica a recuperação nem muda resultado terminal.
    again = CycleStore(store.path)
    try:
        assert again.mechanical.history(request.mechanical_command_id) == history
    finally:
        again.close()


def test_cancel_before_claim_aborts_intent_atomically(store):
    session = blocked(store)
    request = request_for(session)
    store.mechanical.request(request, source="SIMULATED")
    store.change(session.event_id, "PHYSICAL_BLOCKED", "CANCELLED", active_slot=None)
    assert store.mechanical.get(request.mechanical_command_id).phase == "ABORTED"
    with pytest.raises(ControllerError):
        store.mechanical.claim(request.mechanical_command_id, version=0)
    next_session = blocked(store)
    assert store.mechanical.request(request_for(next_session), source="SIMULATED")[1]


def test_cancel_after_claim_cannot_release_session_slot(store):
    session = blocked(store)
    request = request_for(session)
    entry, _ = store.mechanical.request(request, source="SIMULATED")
    store.mechanical.claim(request.mechanical_command_id, version=entry.version)
    with pytest.raises(CycleError):
        store.change(
            session.event_id, "PHYSICAL_BLOCKED", "CANCELLED", active_slot=None
        )
    assert store.active().event_id == session.event_id


def test_concurrent_session_cancel_and_claim_have_one_winner(store):
    session = blocked(store)
    request = request_for(session)
    store.mechanical.request(request, source="SIMULATED")

    def attempt(action):
        try:
            if action == "claim":
                return store.mechanical.claim(request.mechanical_command_id, version=0)
            return store.change(
                session.event_id, "PHYSICAL_BLOCKED", "CANCELLED", active_slot=None
            )
        except (CycleError, ControllerError):
            return None

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(attempt, ["claim", "cancel"]))
    assert sum(item is not None for item in results) == 1
    entry = store.mechanical.get(request.mechanical_command_id)
    assert (entry.phase, store.get(session.event_id).state) in {
        ("DISPATCHING", "PHYSICAL_BLOCKED"),
        ("ABORTED", "CANCELLED"),
    }


def test_v1_migration_preserves_old_schema_history_and_pending_event(store):
    event_id, payload = seed_persisted_state(
        store, "REGISTRATION_PENDING", confirmed=True, scope="original-scope"
    )
    with store.transaction() as conn:
        cycles = [tuple(row) for row in conn.execute("SELECT * FROM cycles")]
        history = [tuple(row) for row in conn.execute("SELECT * FROM transitions")]
        definition = conn.execute(
            "SELECT sql FROM sqlite_master WHERE name='cycles'"
        ).fetchone()[0]
    as_v1(store)
    migrated = CycleStore(store.path)
    try:
        assert migrated.get(event_id).state == "REGISTRATION_PENDING"
        with migrated.transaction() as conn:
            assert conn.execute("PRAGMA user_version").fetchone()[0] == 2
            assert [
                tuple(row) for row in conn.execute("SELECT * FROM cycles")
            ] == cycles
            assert [
                tuple(row) for row in conn.execute("SELECT * FROM transitions")
            ] == history
            assert (
                conn.execute(
                    "SELECT sql FROM sqlite_master WHERE name='cycles'"
                ).fetchone()[0]
                == definition
            )
            assert (
                conn.execute("SELECT count(*) FROM mechanical_commands").fetchone()[0]
                == 0
            )
        assert migrated.claim_registration(event_id, "original-scope") == payload
    finally:
        migrated.close()


def test_migration_rollback_does_not_mark_version_or_leave_partial_tables(
    store, monkeypatch
):
    session = blocked(store)
    as_v1(store)
    monkeypatch.setattr(
        storage_module,
        "MECHANICAL_SCHEMA",
        (*storage_module.MECHANICAL_SCHEMA[:1], "INVALID SQL"),
    )
    with pytest.raises(sqlite3.OperationalError):
        CycleStore(store.path)
    with sqlite3.connect(store.path) as conn:
        assert conn.execute("PRAGMA user_version").fetchone()[0] == 1
        assert (
            conn.execute(
                "SELECT state FROM cycles WHERE event_id=?", (str(session.event_id),)
            ).fetchone()[0]
            == "PHYSICAL_BLOCKED"
        )
        assert (
            conn.execute(
                "SELECT name FROM sqlite_master WHERE name='mechanical_commands'"
            ).fetchone()
            is None
        )


@pytest.mark.parametrize(
    "damage", ["missing_table", "missing_trigger", "bad_history", "future_version"]
)
def test_incompatible_journal_is_not_silently_recreated(store, damage):
    request = request_for(blocked(store))
    store.mechanical.request(request, source="SIMULATED")
    store.close()
    with sqlite3.connect(store.path) as conn:
        if damage == "missing_table":
            conn.execute("DROP TABLE mechanical_history")
        elif damage == "missing_trigger":
            conn.execute("DROP TRIGGER mechanical_identity_immutable")
        elif damage == "bad_history":
            conn.execute("UPDATE mechanical_commands SET result='UNKNOWN'")
        else:
            conn.execute("PRAGMA user_version=99")
    with pytest.raises(RuntimeError):
        CycleStore(store.path)
    with sqlite3.connect(store.path) as conn:
        assert conn.execute(
            "SELECT mechanical_command_id FROM mechanical_commands"
        ).fetchone()[0] == str(request.mechanical_command_id)


@pytest.fixture
async def coordinated(store, anyio_backend):
    clock = ManualClock()
    controller = SimulatedController(context="test", sleep=clock.sleep)
    service = MechanicalService(store, controller, source="SIMULATED")
    try:
        yield service, clock
    finally:
        await service.aclose()
        assert not clock.pending and not service._tasks and not service._dispatches


@pytest.mark.anyio
async def test_coordinator_persists_before_dispatch_and_never_holds_transaction(store):
    clock = ManualClock()

    class CheckingController(SimulatedController):
        calls = 0

        async def submit(self, request):
            self.calls += 1
            with sqlite3.connect(store.path, isolation_level=None, timeout=0) as conn:
                conn.execute("BEGIN IMMEDIATE")
                assert (
                    conn.execute("SELECT phase FROM mechanical_commands").fetchone()[0]
                    == "DISPATCHING"
                )
                assert (
                    conn.execute("SELECT count(*) FROM mechanical_history").fetchone()[
                        0
                    ]
                    == 2
                )
                conn.rollback()
            return await super().submit(request)

    controller = CheckingController(context="test", sleep=clock.sleep)
    service = MechanicalService(store, controller, source="SIMULATED")
    request = request_for(blocked(store))
    try:
        entry = await service.submit(request)
        assert entry.phase == "ACCEPTED"
        assert await service.submit(request) == entry
        with store.transaction() as conn:
            assert (
                conn.execute("SELECT count(*) FROM mechanical_history").fetchone()[0]
                == 3
            )
        await clock.advance(3.0)
        final = await service.wait(request.mechanical_command_id)
        assert final.phase == "COMPLETED" and final.source == "SIMULATED"
        assert controller.calls == 1
        assert await service.submit(request) == final
        assert store.active().state == "PHYSICAL_BLOCKED"
    finally:
        await service.aclose()


@pytest.mark.anyio
async def test_no_dispatch_when_intent_or_claim_persistence_fails(store, monkeypatch):
    class NeverController(UnavailableController):
        async def submit(self, request):
            pytest.fail("Não pode despachar sem commit do journal.")

    service = MechanicalService(store, NeverController(), source="UNAVAILABLE")
    request = request_for(blocked(store))

    def fail(*args, **kwargs):
        raise sqlite3.OperationalError("injected")

    try:
        with monkeypatch.context() as m:
            m.setattr(store.mechanical, "request", fail)
            with pytest.raises(sqlite3.OperationalError):
                await service.submit(request)
        with monkeypatch.context() as m:
            m.setattr(store.mechanical, "claim", fail)
            with pytest.raises(sqlite3.OperationalError):
                await service.submit(request)
        assert service.get(request.mechanical_command_id).phase == "INTENT"
        # Replay não transforma intenção prévia em tentativa de despacho.
        assert (await service.submit(request)).phase == "INTENT"
    finally:
        await service.aclose()


@pytest.mark.anyio
async def test_concurrent_coordinators_do_not_dispatch_twice(store):
    clock = ManualClock()

    class Counter(SimulatedController):
        calls = 0

        async def submit(self, request):
            self.calls += 1
            return await super().submit(request)

    controller = Counter(context="test", sleep=clock.sleep)
    services = [
        MechanicalService(store, controller, source="SIMULATED") for _ in range(2)
    ]
    request = request_for(blocked(store))
    try:
        entries = await asyncio.gather(
            *(services[index % 2].submit(request) for index in range(8))
        )
        assert all(entry.command == request for entry in entries)
        assert controller.calls == 1
        with pytest.raises(ControllerError):
            await services[1].submit(request_for(store.active()))
        await clock.advance(3.0)
        await services[0].wait(request.mechanical_command_id)
    finally:
        for service in services:
            await service.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("outcome", ["TIMEOUT", "FAILURE", "UNAVAILABLE"])
async def test_controlled_errors_are_durable_and_keep_correct_block(store, outcome):
    clock = ManualClock()
    controller = SimulatedController(
        context="test",
        sleep=clock.sleep,
        plans={
            "OPEN_INSERTION_DOOR": SimulationPlan(duration_seconds=2.0, outcome=outcome)
        },
    )
    service = MechanicalService(store, controller, source="SIMULATED")
    request = request_for(
        blocked(store), timeout_seconds=1.0 if outcome == "TIMEOUT" else 10.0
    )
    try:
        await service.submit(request)
        await clock.advance(2.0)
        final = await service.wait(request.mechanical_command_id)
        assert (
            final.phase
            == {"TIMEOUT": "TIMED_OUT", "FAILURE": "FAILED", "UNAVAILABLE": "REJECTED"}[
                outcome
            ]
        )
        assert store.active().state == (
            "PHYSICAL_BLOCKED" if outcome == "UNAVAILABLE" else "INDETERMINATE"
        )
        assert await service.submit(request) == final
        await clock.advance(100.0)
        assert service.get(request.mechanical_command_id) == final
    finally:
        await service.aclose()
    recovered = restart(store)
    try:
        assert recovered.mechanical.get(request.mechanical_command_id) == final
    finally:
        recovered.close()


@pytest.mark.anyio
async def test_caller_wait_cancellation_does_not_lose_final_persistence(
    store, coordinated
):
    service, clock = coordinated
    request = request_for(blocked(store))
    await service.submit(request)
    waiter = asyncio.create_task(service.wait(request.mechanical_command_id))
    await clock.advance(1.0)
    waiter.cancel()
    with pytest.raises(asyncio.CancelledError):
        await waiter
    await clock.advance(2.0)
    assert (await service.wait(request.mechanical_command_id)).phase == "COMPLETED"


@pytest.mark.anyio
async def test_cancel_operation_persists_unknown_before_releasing_tasks(
    store, coordinated
):
    service, clock = coordinated
    request = request_for(blocked(store))
    await service.submit(request)
    await clock.advance(1.0)
    final = await service.cancel(request.mechanical_command_id)
    assert final.phase == "CANCELLED" and final.result == "UNKNOWN"
    assert store.active().state == "INDETERMINATE"
    with pytest.raises(ControllerError):
        await service.submit(request_for(store.active()))


@pytest.mark.anyio
@pytest.mark.parametrize(
    "fault",
    [
        "dispatch_error",
        "wrong_command",
        "wrong_source",
        "completion_before_acceptance",
        "bad_final",
        "execution_error",
    ],
)
async def test_adapter_faults_cannot_be_persisted_as_success(store, fault):
    class FaultyController(UnavailableController):
        async def submit(self, request):
            if fault == "dispatch_error":
                raise RuntimeError("private-driver-details")
            self.request = request
            if fault == "wrong_command":
                return response(request.model_copy(update={"event_id": uuid4()}))
            if fault == "wrong_source":
                return response(request, source="PHYSICAL")
            if fault == "completion_before_acceptance":
                return response(request, "COMPLETED")
            return response(request)

        async def wait(self, identifier):
            if fault == "execution_error":
                raise RuntimeError("private-driver-details")
            return response(
                self.request.model_copy(update={"mechanical_command_id": uuid4()}),
                "COMPLETED",
            )

    service = MechanicalService(store, FaultyController(), source="SIMULATED")
    request = request_for(blocked(store))
    try:
        await service.submit(request)
        final = await service.wait(request.mechanical_command_id)
        assert (final.phase, final.result) == ("INDETERMINATE", "UNKNOWN")
        assert "private-driver-details" not in final.model_dump_json()
        assert store.active().state == "INDETERMINATE"
    finally:
        await service.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("shutdown", [False, True])
async def test_cancel_or_shutdown_during_dispatch_drains_coroutines(store, shutdown):
    entered = asyncio.Event()

    class HangingSubmit(UnavailableController):
        async def submit(self, request):
            entered.set()
            await asyncio.Event().wait()

    service = MechanicalService(store, HangingSubmit(), source="UNAVAILABLE")
    request = request_for(blocked(store))
    pending = asyncio.create_task(service.submit(request))
    await entered.wait()
    if shutdown:
        await service.aclose()
    else:
        pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    assert service.get(request.mechanical_command_id).phase == "INDETERMINATE"
    assert not service._dispatches
    await service.aclose()


@pytest.mark.anyio
async def test_result_received_but_failed_commit_recovers_without_redispatch(
    store, monkeypatch
):
    request = request_for(blocked(store))
    clock = ManualClock()
    controller = SimulatedController(context="test", sleep=clock.sleep)
    service = MechanicalService(store, controller, source="SIMULATED")
    original = store.mechanical.observe

    def fail_final(identifier, received, **kwargs):
        if received.state == "COMPLETED":
            raise sqlite3.OperationalError("lost commit")
        return original(identifier, received, **kwargs)

    monkeypatch.setattr(store.mechanical, "observe", fail_final)
    await service.submit(request)
    await clock.advance(3.0)
    with pytest.raises(sqlite3.OperationalError):
        await service.wait(request.mechanical_command_id)
    assert controller.get(request.mechanical_command_id).state == "COMPLETED"
    assert service.get(request.mechanical_command_id).phase == "ACCEPTED"
    # Simula perda do processo: final em memória não é copiado para o novo store.
    await controller.aclose()
    assert all(task.done() for task in service._tasks.values())
    recovered = restart(store)
    new_controller = UnavailableController()
    new_service = MechanicalService(recovered, new_controller, source="UNAVAILABLE")
    try:
        final = await new_service.submit(request)
        assert (final.phase, final.result) == ("INDETERMINATE", "UNKNOWN")
        assert not new_controller._responses
        assert recovered.active().state == "INDETERMINATE"
    finally:
        await new_service.aclose()
        recovered.close()


def test_simulation_never_qualifies_for_economic_registration(store):
    session = blocked(store)
    request = request_for(session)
    entry = accepted(store, request)
    store.mechanical.observe(
        request.mechanical_command_id,
        response(request, "COMPLETED"),
        version=entry.version,
    )
    # Até uma confirmação flagrada incorretamente por código futuro é recusada
    # se o ciclo tiver conclusão simulada. Não existe setter de produção disso.
    payload = DepositPayload(
        event_id=session.event_id,
        class_id=CLASS,
        student_id=None,
        is_valid=True,
        detected_type="cable",
        waste_category_code="CABLE_WIRE",
        category_source="AI_CONFIRMED",
    )
    with store.transaction() as conn:
        conn.execute(
            "UPDATE cycles SET state='REGISTRATION_PENDING', physical_confirmed=1, central_scope='scope',payload=? WHERE event_id=?",
            (payload.model_dump_json(), str(session.event_id)),
        )
    with pytest.raises(CycleError) as error:
        store.claim_registration(session.event_id, "scope")
    assert error.value.code == "MISSING_PHYSICAL_EVIDENCE"


def test_physical_dispatch_cannot_be_enabled_by_service_argument(store):
    with pytest.raises(ValueError):
        MechanicalService(store, UnavailableController(), source="PHYSICAL")


def test_lifespan_composes_private_journal_without_unlocking_routes(
    healthy_body, configured_environment
):
    calls = []

    def upstream(request):
        calls.append(request.url.path)
        return httpx.Response(200, json=healthy_body)

    application = create_app(transport=httpx.MockTransport(upstream))
    with TestClient(
        application, base_url="http://127.0.0.1", headers={"X-Totem-Request": "1"}
    ) as client:
        session = blocked(application.state.sessions.store)
        request = request_for(session)
        final = client.portal.call(application.state.mechanical.submit, request)
        assert (final.phase, final.source) == ("REJECTED", "UNAVAILABLE")
        status = client.get("/local/status").json()
        assert status["status"] == "OFFLINE" and status["can_start_deposit"] is False
        for path in [
            "/local/mechanical",
            "/local/controller",
            f"/local/sessions/{session.event_id}/open",
        ]:
            assert client.post(path, json={}).status_code == 404
        assert (
            client.post(
                f"/local/sessions/{session.event_id}/retry-registration", json={}
            ).status_code
            == 409
        )
        assert all(path.endswith("health-v1") for path in calls)
        with application.state.sessions.store.transaction() as conn:
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt FROM cycles"
                ).fetchone()
            ) == (0, None, None)


def test_lifespan_persists_shutdown_of_simulated_operation():
    clock = ManualClock()
    application = create_app(
        controller_factory=lambda: SimulatedController(
            context="test", sleep=clock.sleep
        )
    )
    with TestClient(application) as client:
        store = application.state.sessions.store
        request = request_for(blocked(store))
        client.portal.call(application.state.mechanical.submit, request)
        client.portal.call(clock.advance, 1.0)
    assert not clock.pending and not application.state.mechanical._tasks
    reopened = CycleStore(store.path)
    try:
        entry = reopened.mechanical.get(request.mechanical_command_id)
        assert entry.result == "UNKNOWN" and entry.phase in {
            "CANCELLED",
            "INDETERMINATE",
        }
        assert reopened.active().state == "INDETERMINATE"
    finally:
        reopened.close()
