"""Durable DEV orchestration: no HTTP GET, hosted service or physical device."""

import asyncio
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
from uuid import UUID, uuid4

import pytest

from app.mechanical import MechanicalCommand
from app.cycles import CycleError
from app.services.controller import SimulatedController, SimulationPlan
from app.services.mechanical import MechanicalService
from app.services.simulation_flow import SimulationFlow
from app.storage import CycleStore
from test_controller import ManualClock
from test_dev_integration import connected, dev_environment, BASE, PIN

pytestmark = pytest.mark.anyio


class Rig:
    def __init__(self, path, *, auto=True, outcome="SUCCEEDED"):
        self.clock = ManualClock()
        self.store = CycleStore(path, simulation_enabled=True)
        self.controller = SimulatedController(
            context="test",
            sleep=self.clock.sleep,
            plans={
                op: SimulationPlan(
                    duration_seconds=2 if op == "CONFIRM_INITIAL_STATE" else 1,
                    outcome=outcome if op == "CONFIRM_INITIAL_STATE" else "SUCCEEDED",
                )
                for op in (
                    "OPEN_INSERTION_DOOR",
                    "CLOSE_INSERTION_DOOR",
                    "CYCLE_LOWER_HATCH",
                    "CONFIRM_INITIAL_STATE",
                )
            },
        )
        self.service = MechanicalService(
            self.store, self.controller, source="SIMULATED", auto_initial=auto
        )
        self.flow = SimulationFlow(self.store, self.service)

    async def close(self):
        await self.service.aclose()
        self.store.close()

    async def hatch(self):
        event = self.flow.start(uuid4()).session.event_id
        self.flow.safety(event, False)
        for operation in (
            "OPEN_INSERTION_DOOR",
            "CLOSE_INSERTION_DOOR",
            "CYCLE_LOWER_HATCH",
        ):
            if operation == "CYCLE_LOWER_HATCH":
                self.flow.review_fixture(event)
            command = MechanicalCommand(event_id=event, operation=operation)
            await self.service.submit(
                command, hand_removed=operation == "CLOSE_INSERTION_DOOR"
            )
            await self.clock.advance(1)
            await self.service.wait(command.mechanical_command_id)
        return event


async def test_completed_requires_initial_controller_result_and_durable_commit(
    tmp_path,
):
    rig = Rig(tmp_path / "auto.db")
    try:
        event = await rig.hatch()
        identifier = rig.service.initial_identifier(event)
        initial = rig.service.get(identifier)
        assert (initial.phase, initial.result) == ("ACCEPTED", "PENDING")
        assert rig.flow.get(event).session.state == "HATCH_IN_PROGRESS"
        # Reading and duplicate submission do not simulate completion or redispatch.
        for _ in range(3):
            assert rig.flow.get(event).session.state == "HATCH_IN_PROGRESS"
            assert await rig.service.submit(initial.command) == initial
            await rig.service.resume_initial()
        assert len(rig.controller._responses) == 4
        await rig.clock.advance(2)
        completed = await rig.service.wait(identifier)
        assert (completed.phase, completed.result, completed.source) == (
            "COMPLETED",
            "SUCCEEDED",
            "SIMULATED",
        )
        final = rig.flow.get(event)
        assert final.session.state == "COMPLETED" and final.session.receipt is None
        assert len(final.commands) == 4 and rig.flow.active() is None
        with rig.store.transaction() as conn:
            row = conn.execute(
                "SELECT physical_confirmed,payload,receipt,central_scope FROM cycles WHERE event_id=?",
                (str(event),),
            ).fetchone()
            assert tuple(row) == (0, None, None, None)
            assert (
                conn.execute(
                    "SELECT count(*) FROM transitions WHERE event_id=? AND to_state='COMPLETED'",
                    (str(event),),
                ).fetchone()[0]
                == 1
            )
        assert (await rig.service.submit(initial.command)).phase == "COMPLETED"
        assert len(rig.controller._responses) == 4
    finally:
        await rig.close()


@pytest.mark.parametrize("outcome", ["FAILURE", "UNAVAILABLE", "TIMEOUT"])
async def test_initial_failure_never_completes_or_creates_another_attempt(
    tmp_path, outcome
):
    rig = Rig(tmp_path / "failure.db", outcome=outcome)
    try:
        event = await rig.hatch()
        identifier = rig.service.initial_identifier(event)
        await rig.clock.advance(10)
        entry = await rig.service.wait(identifier)
        assert entry.phase in {"FAILED", "REJECTED", "TIMED_OUT"}
        assert rig.flow.get(event).session.state != "COMPLETED"
        for _ in range(3):
            await rig.service.resume_initial()
        assert len(rig.flow.get(event).commands) == 4
        assert rig.flow.active() is not None
    finally:
        await rig.close()


async def test_restart_after_hatch_commit_resumes_from_journal_without_frontend(
    tmp_path,
):
    path = tmp_path / "restart.db"
    old = Rig(path, auto=False)
    event = await old.hatch()
    await old.close()
    new = Rig(path)
    try:
        assert len(new.flow.get(event).commands) == 3
        for _ in range(3):
            assert new.flow.get(event).session.state == "HATCH_IN_PROGRESS"
        await new.service.resume_initial()
        assert len(new.flow.get(event).commands) == 4
        await new.clock.advance(2)
        await new.service.wait(new.service.initial_identifier(event))
        assert new.flow.get(event).session.state == "COMPLETED"
        assert len(new.controller._responses) == 1
    finally:
        await new.close()


@pytest.mark.parametrize("point", ["INTENT", "DISPATCHING", "ACCEPTED"])
async def test_restart_preserves_existing_initial_attempt_without_redispatch(
    tmp_path, point
):
    path = tmp_path / "interrupted.db"
    old = Rig(path, auto=point == "ACCEPTED")
    event = await old.hatch()
    identifier = old.service.initial_identifier(event)
    if point != "ACCEPTED":
        entry, _ = old.store.mechanical.request(
            MechanicalCommand(
                event_id=event,
                mechanical_command_id=identifier,
                operation="CONFIRM_INITIAL_STATE",
            ),
            source="SIMULATED",
        )
        if point == "DISPATCHING":
            old.store.mechanical.claim(identifier, version=entry.version)
    await old.close()
    new = Rig(path)
    try:
        await new.service.resume_initial()
        assert new.flow.get(event).session.state != "COMPLETED"
        entry = new.service.get(identifier)
        assert entry.phase in {"ABORTED", "INDETERMINATE", "CANCELLED"}
        assert entry.result in {"UNKNOWN", "UNAVAILABLE"}
        assert len(new.flow.get(event).commands) == 4
        assert not new.controller._responses
    finally:
        await new.close()


async def test_result_not_persisted_does_not_complete(tmp_path, monkeypatch):
    rig = Rig(tmp_path / "commit.db")
    try:
        event = await rig.hatch()
        original = rig.store.mechanical.observe

        def fail_commit(identifier, response, **kwargs):
            if (
                response.command.operation == "CONFIRM_INITIAL_STATE"
                and response.state == "COMPLETED"
            ):
                raise sqlite3.OperationalError("synthetic commit failure")
            return original(identifier, response, **kwargs)

        monkeypatch.setattr(rig.store.mechanical, "observe", fail_commit)
        await rig.clock.advance(2)
        with pytest.raises(sqlite3.OperationalError):
            await rig.service.wait(rig.service.initial_identifier(event))
        assert rig.flow.get(event).session.state == "HATCH_IN_PROGRESS"
    finally:
        await rig.close()


async def test_auto_initial_rejects_operational_or_unavailable_scope(tmp_path):
    store = CycleStore(tmp_path / "operational.db")
    controller = SimulatedController(context="test")
    try:
        with pytest.raises(ValueError):
            MechanicalService(store, controller, source="SIMULATED", auto_initial=True)
    finally:
        await controller.aclose()
        store.close()


async def test_hatch_failure_never_requests_initial_confirmation(tmp_path):
    rig = Rig(tmp_path / "hatch-failure.db")
    try:
        rig.controller._plans["CYCLE_LOWER_HATCH"] = SimulationPlan(
            duration_seconds=1, outcome="FAILURE"
        )
        event = await rig.hatch()
        await rig.service.resume_initial()
        snapshot = rig.flow.get(event)
        assert snapshot.session.state != "COMPLETED"
        assert len(snapshot.commands) == 3
        assert not any(
            entry.command.operation == "CONFIRM_INITIAL_STATE"
            for entry in snapshot.commands
        )
    finally:
        await rig.close()


async def test_completed_without_succeeded_cannot_change_session(tmp_path):
    rig = Rig(tmp_path / "evidence.db", auto=False)
    try:
        event = await rig.hatch()
        entry, _ = rig.store.mechanical.request(
            MechanicalCommand(event_id=event, operation="CONFIRM_INITIAL_STATE"),
            source="SIMULATED",
        )
        with rig.store.transaction() as conn:
            with pytest.raises(CycleError):
                rig.store.apply_simulated_response(
                    conn,
                    entry.model_copy(
                        update={"phase": "COMPLETED", "result": "PENDING"}
                    ),
                )
        assert rig.flow.get(event).session.state == "HATCH_IN_PROGRESS"
    finally:
        await rig.close()


async def test_dev_initial_attempt_is_unique_even_after_rejection(connected):
    client, app, _, _ = connected
    app.state.controller._plans["CONFIRM_INITIAL_STATE"] = SimulationPlan(
        duration_seconds=0, outcome="UNAVAILABLE"
    )
    event = client.post(BASE, json={"command_id": str(uuid4())}).json()["session"][
        "event_id"
    ]
    client.post(f"/local/dev/sessions/{event}/identity", json=PIN)
    client.post(f"{BASE}/{event}/safety", json={"has_risk": False})
    for operation, body in [
        ("open", {"pin": PIN["pin"]}),
        ("close", {"hand_removed": True}),
        ("hatch", {"pin": PIN["pin"]}),
    ]:
        if operation == "hatch":
            client.post(f"{BASE}/{event}/review-fixture", json={})
        identifier = uuid4()
        assert client.post(
            f"{BASE}/{event}/{operation}",
            json={"mechanical_command_id": str(identifier), **body},
        ).status_code in {200, 202}
        client.portal.call(app.state.mechanical.wait, identifier)
    before = client.get(f"{BASE}/{event}").json()
    assert len(before["commands"]) == 4 and before["session"]["state"] != "COMPLETED"
    assert (
        client.post(
            f"{BASE}/{event}/confirm-initial",
            json={"mechanical_command_id": str(uuid4())},
        ).status_code
        == 409
    )
    assert client.get(f"{BASE}/{event}").json() == before


async def test_process_killed_during_initial_confirmation_is_not_redispatched(tmp_path):
    path = tmp_path / "killed.db"
    ready = tmp_path / "ready"
    # Fixture preparation is outside the child-startup handshake. The child
    # resumes only the initial confirmation, exactly as application startup does.
    old = Rig(path, auto=False)
    expected_event = await old.hatch()
    await old.close()
    script = """
import asyncio, sys
from pathlib import Path
from test_auto_initial import Rig
async def main():
    rig = Rig(Path(sys.argv[1]))
    event = rig.flow.active().session.event_id
    await rig.service.resume_initial()
    await rig.clock.advance(0)
    Path(sys.argv[2]).write_text(str(event))
    await asyncio.Event().wait()
asyncio.run(main())
"""
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_"))
    }
    env["PYTHONPATH"] = os.pathsep.join(
        [str(Path(__file__).resolve().parent), *[p for p in sys.path if p]]
    )
    # Use the interpreter itself, not the Windows venv launcher which can leave
    # a child alive holding SQLite after killing only the launcher.
    process = subprocess.Popen(
        [sys._base_executable, "-B", "-c", script, str(path), str(ready)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    try:
        for _ in range(80):
            if ready.exists() or process.poll() is not None:
                break
            await asyncio.sleep(0.1)
        assert ready.exists(), (
            "Owned subprocess did not reach durable initial acceptance"
        )
        event = UUID(ready.read_text())
        assert event == expected_event
        process.kill()
        process.wait(timeout=5)
        new = Rig(path)
        try:
            await new.service.resume_initial()
            assert new.flow.get(event).session.state == "INDETERMINATE"
            assert (
                new.service.get(new.service.initial_identifier(event)).result
                == "UNKNOWN"
            )
            assert len(new.flow.get(event).commands) == 4
            assert not new.controller._responses
        finally:
            await new.close()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        process.stderr.close()
