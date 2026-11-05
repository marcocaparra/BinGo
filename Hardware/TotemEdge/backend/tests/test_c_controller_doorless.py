"""Doorless Python/C laboratory. All PWM is compiled as simulated only."""

from contextlib import asynccontextmanager
import sqlite3
import subprocess
import sys
from uuid import UUID, uuid4

import pytest

from app.cycles import CycleError
from app.mechanical import ControllerError
from app.services.c_controller import CProcessController
from app.services.capture import CaptureService
from app.services.mechanical import MechanicalService
from app.services.session_vision import SessionVision
from app.services.simulation_flow import SimulationFlow
from app.services.vision import InternalVision
from app.storage import CycleStore
from test_c_controller import binaries, command, frame, raw
from test_camera import prepared
from test_vision import ControlledProvider, result

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")
PROFILE = ("--profile", "doorless-v1")
OPERATIONS = ("CONFIRM_HAND_REMOVED", "CYCLE_LOWER_HATCH", "CONFIRM_INITIAL_STATE")


def cycle_frames(event):
    return "".join(frame(command(event, op)) for op in OPERATIONS)


def pwm_lines(output):
    return [line for line in output.splitlines() if line.startswith("SIMULATED_PWM")]


def test_only_two_logical_hatches_and_explicit_virtual_drop_interval(
    binaries, tmp_path
):
    event = uuid4()
    output = raw(
        binaries["simulated"], tmp_path / "c.db", cycle_frames(event), *PROFILE
    )
    assert output.stdout.startswith("V1 READY SIMULATED DOORLESS_V1\n")
    assert output.stdout.count("ACCEPTED PENDING") == 3
    assert pwm_lines(output.stderr) == [
        "SIMULATED_PWM RIGHT PWM3 ANGLE_DEG 175 TICK_MS 0",
        "SIMULATED_PWM LEFT PWM4 ANGLE_DEG 5 TICK_MS 0",
        "SIMULATED_PWM RIGHT PWM3 ANGLE_DEG 70 TICK_MS 6000",
        "SIMULATED_PWM LEFT PWM4 ANGLE_DEG 113 TICK_MS 6000",
    ]
    lines = output.stderr.splitlines()
    assert lines[2] == "SIMULATED_DROP_INTERVAL_MS 6000"
    assert "/sys" not in output.stderr and "porta" not in output.stderr.lower()


def test_logical_hand_and_initial_confirmation_emit_no_pwm(binaries, tmp_path):
    path = tmp_path / "c.db"
    event = uuid4()
    hand = command(event, OPERATIONS[0])
    output = raw(binaries["simulated"], path, frame(hand), *PROFILE)
    assert "ACCEPTED PENDING" in output.stdout and output.stderr == ""
    hatch = command(event, OPERATIONS[1])
    raw(binaries["simulated"], path, frame(hatch), *PROFILE)
    confirm = command(event, OPERATIONS[2])
    output = raw(binaries["simulated"], path, frame(confirm), *PROFILE)
    assert "ACCEPTED PENDING" in output.stdout and output.stderr == ""


@pytest.mark.parametrize(
    "op", ["OPEN_INSERTION_DOOR", "CLOSE_INSERTION_DOOR", *OPERATIONS[1:]]
)
def test_door_operations_and_out_of_order_commands_have_no_pwm(binaries, tmp_path, op):
    output = raw(
        binaries["simulated"], tmp_path / "c.db", frame(command(operation=op)), *PROFILE
    )
    assert "REJECTED UNAVAILABLE CONTROLLER_BUSY SIMULATED" in output.stdout
    assert output.stderr == ""


def test_repeat_conflict_cross_event_and_restart_never_repeat_pwm(binaries, tmp_path):
    path = tmp_path / "c.db"
    event = uuid4()
    hand, hatch, confirm = [command(event, op) for op in OPERATIONS]
    output = raw(
        binaries["simulated"],
        path,
        frame(hand)
        + frame(hand)
        + frame(hatch)
        + frame(hatch.model_copy(update={"timeout_seconds": 20.0}))
        + frame(command(uuid4(), OPERATIONS[2]))
        + frame(confirm),
        *PROFILE,
    )
    assert "V1 ERROR DUPLICATE" in output.stdout
    assert "V1 ERROR ID_CONFLICT" in output.stdout
    assert "REJECTED UNAVAILABLE" in output.stdout
    assert len(pwm_lines(output.stderr)) == 4
    output = raw(
        binaries["simulated"],
        path,
        frame(hatch) + f"V1 GET {hatch.mechanical_command_id}\n",
        *PROFILE,
    )
    assert "DUPLICATE" in output.stdout and "COMPLETED SUCCEEDED" in output.stdout
    assert output.stderr == ""
    # A completed event cannot be reused, even after another complete cycle.
    output = raw(
        binaries["simulated"],
        path,
        cycle_frames(uuid4()) + frame(command(event, OPERATIONS[0])),
        *PROFILE,
    )
    assert output.stdout.count("ACCEPTED PENDING") == 3
    assert output.stdout.endswith("REJECTED UNAVAILABLE CONTROLLER_BUSY SIMULATED\n")


@pytest.mark.parametrize("successful_writes", [0, 1, 2, 3])
def test_partial_open_and_close_failure_preserve_block_without_corrective_pwm(
    binaries, tmp_path, successful_writes
):
    path = tmp_path / "c.db"
    event = uuid4()
    hand, hatch = [command(event, op) for op in OPERATIONS[:2]]
    output = raw(
        binaries["simulated"],
        path,
        frame(hand)
        + frame(hatch)
        + f"V1 GET {hatch.mechanical_command_id}\n"
        + frame(command(event, OPERATIONS[2])),
        *PROFILE,
        "--fail-after",
        str(successful_writes),
    )
    assert len(pwm_lines(output.stderr)) == successful_writes
    assert "FAILED FAILURE OPERATION_FAILED SIMULATED" in output.stdout
    assert output.stdout.endswith("REJECTED UNAVAILABLE CONTROLLER_BUSY SIMULATED\n")
    assert ("SIMULATED_DROP_INTERVAL_MS" in output.stderr) == (successful_writes >= 2)
    replay = raw(
        binaries["simulated"],
        path,
        frame(hatch) + f"V1 GET {hatch.mechanical_command_id}\n",
        *PROFILE,
    )
    assert replay.stderr == "" and "FAILED FAILURE" in replay.stdout


@asynccontextmanager
async def reviewed_cycle(binaries, tmp_path):
    controller = await CProcessController.connect(
        binaries["simulated"], tmp_path / "c.db", context="test"
    )
    store = CycleStore(tmp_path / "python.db", simulation_enabled=True)
    service = MechanicalService(store, controller, source="SIMULATED")
    flow = SimulationFlow(store, service, doorless=True)
    manager, driver = await prepared(tmp_path)
    provider = ControlledProvider(result())
    vision = SessionVision(
        CaptureService(store, manager, InternalVision(provider, None)),
        service,
        model="test",
    )
    flow.vision = vision
    try:
        event = flow.start(uuid4()).session.event_id
        assert flow.safety(event, False).session.state == "INSERTION_READY"
        hand = command(event, OPERATIONS[0])
        await flow.act(
            event,
            hand.operation,
            hand.mechanical_command_id,
            hand.timeout_seconds,
            hand_removed=True,
        )
        await service.wait(hand.mechanical_command_id)
        await vision.tasks[str(hand.mechanical_command_id)]
        observation = flow.get(event).vision
        vision.review(event, UUID(observation["capture_id"]), "cable", "confirm")
        assert driver.calls == driver.released == len(provider.calls) == 1
        yield event, hand, controller, store, service, flow
    finally:
        await vision.aclose()
        await manager.aclose()
        await service.aclose()
        store.close()


@pytest.mark.anyio
async def test_doorless_full_pipeline_uses_existing_python_journals_without_economy(
    binaries, tmp_path
):
    async with reviewed_cycle(binaries, tmp_path) as (
        event,
        hand,
        controller,
        store,
        service,
        flow,
    ):
        for op in OPERATIONS[1:]:
            request = command(event, op)
            accepted, _ = await flow.act(
                event, op, request.mechanical_command_id, request.timeout_seconds
            )
            assert (accepted.phase, accepted.result) == ("ACCEPTED", "PENDING")
            final = await service.wait(request.mechanical_command_id)
            assert (final.phase, final.result, final.source) == (
                "COMPLETED",
                "SUCCEEDED",
                "SIMULATED",
            )
            assert await service.submit(request) == final
        assert flow.get(event).session.state == "COMPLETED"
        assert flow.get(event).session.receipt is None
        with store.transaction() as conn:
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt,central_scope FROM cycles"
                ).fetchone()
            ) == (0, None, None, None)
        with sqlite3.connect(tmp_path / "c.db") as conn:
            assert conn.execute(
                "SELECT operation,profile FROM orders ORDER BY rowid"
            ).fetchall() == [(op, "doorless-v1") for op in OPERATIONS]


@pytest.mark.anyio
@pytest.mark.parametrize(
    "fault", ["backend_timeout", "ipc_timeout", "disconnect", "lost_result"]
)
async def test_hatch_timeout_or_lost_response_keeps_same_ids_blocked_after_restart(
    binaries, tmp_path, fault
):
    async with reviewed_cycle(binaries, tmp_path) as (
        event,
        hand,
        controller,
        store,
        service,
        flow,
    ):
        await service.aclose()
        controller = await CProcessController.connect(
            binaries["simulated"],
            tmp_path / "c.db",
            context="test",
            io_timeout_seconds=0.1 if fault == "ipc_timeout" else 2.0,
            delay_ms=0 if fault == "lost_result" else 1000,
        )
        service = MechanicalService(store, controller, source="SIMULATED")
        if fault == "lost_result":
            wait = controller.wait

            async def lose_result(identifier):
                assert (await wait(identifier)).state == "COMPLETED"
                raise ControllerError("LOST_RESULT")

            controller.wait = lose_result
        request = command(
            event, OPERATIONS[1], timeout=0.1 if fault == "backend_timeout" else 10.0
        )
        try:
            await service.submit(request)
            if fault == "disconnect":
                controller._process.kill()
            final = await service.wait(request.mechanical_command_id)
            assert final.phase == (
                "TIMED_OUT"
                if fault in {"backend_timeout", "ipc_timeout"}
                else "INDETERMINATE"
            )
            assert store.active().state == "INDETERMINATE"
            assert await service.submit(request) == final
            with pytest.raises((ControllerError, CycleError)):
                await service.submit(command(event, OPERATIONS[1]))
        finally:
            await service.aclose()
    # Both stores reopen with the same identifiers. A completed device query
    # after a lost response must NOT promote the Python journal to success.
    controller = await CProcessController.connect(
        binaries["simulated"], tmp_path / "c.db", context="test"
    )
    store = CycleStore(tmp_path / "python.db", simulation_enabled=True)
    service = MechanicalService(store, controller, source="SIMULATED")
    try:
        assert await service.submit(request) == final
        device = await controller.query(request)
        assert (device.state, device.result) == (
            ("COMPLETED", "SUCCEEDED")
            if fault == "lost_result"
            else ("FAILED", "UNKNOWN")
        )
        assert service.get(request.mechanical_command_id) == final
        assert store.active().state == "INDETERMINATE"
        with store.transaction() as conn:
            assert tuple(
                conn.execute(
                    "SELECT physical_confirmed,payload,receipt FROM cycles"
                ).fetchone()
            ) == (0, None, None)
    finally:
        await service.aclose()
        store.close()


def legacy_database(path, request, *, state="COMPLETED"):
    """Actual V1 shape/constraints, independently of the new C schema."""
    result, error = ("SUCCEEDED", "-") if state == "COMPLETED" else ("PENDING", "-")
    with sqlite3.connect(path) as conn:
        conn.executescript("""
          CREATE TABLE orders(id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
          event TEXT NOT NULL CHECK(length(event)=36),
          operation TEXT NOT NULL CHECK(operation IN ('OPEN_INSERTION_DOOR','CLOSE_INSERTION_DOOR','CYCLE_LOWER_HATCH','CONFIRM_INITIAL_STATE')),
          timeout TEXT NOT NULL,state TEXT NOT NULL,result TEXT NOT NULL,error TEXT NOT NULL,
          CHECK((state='ACCEPTED' AND result='PENDING' AND error='-') OR
          (state='COMPLETED' AND result='SUCCEEDED' AND error='-') OR
          (state='REJECTED' AND result='UNAVAILABLE' AND error='CONTROLLER_BUSY') OR
          (state='FAILED' AND ((result='FAILURE' AND error='OPERATION_FAILED') OR (result='UNKNOWN' AND error='EXECUTION_ERROR')))));
          CREATE TRIGGER order_identity BEFORE UPDATE OF id,event,operation,timeout ON orders BEGIN SELECT RAISE(ABORT,'Immutable order identity'); END;
          CREATE TRIGGER order_retention BEFORE DELETE ON orders BEGIN SELECT RAISE(ABORT,'Retained order identity'); END;
          PRAGMA user_version=1; PRAGMA application_id=1112098627;
        """)
        conn.execute(
            "INSERT INTO orders(rowid,id,event,operation,timeout,state,result,error) VALUES(37,?,?,?,?,?,?,?)",
            (
                str(request.mechanical_command_id),
                str(request.event_id),
                request.operation,
                format(request.timeout_seconds, ".17g"),
                state,
                result,
                error,
            ),
        )


@pytest.mark.parametrize("state", ["COMPLETED", "ACCEPTED"])
def test_v1_migration_preserves_ids_results_and_pending_uncertainty(
    binaries, tmp_path, state
):
    path = tmp_path / "legacy.db"
    old = command(operation="OPEN_INSERTION_DOOR")
    legacy_database(path, old, state=state)
    query = f"V1 GET {old.mechanical_command_id}\n"
    output = raw(binaries["simulated"], path, query, *PROFILE)
    assert output.stderr == ""
    assert (
        "COMPLETED SUCCEEDED" if state == "COMPLETED" else "FAILED UNKNOWN"
    ) in output.stdout
    with sqlite3.connect(path) as conn:
        assert conn.execute("PRAGMA user_version").fetchone()[0] == 2
        row = conn.execute(
            "SELECT rowid,id,event,operation,timeout,profile FROM orders"
        ).fetchone()
        assert row == (
            37,
            str(old.mechanical_command_id),
            str(old.event_id),
            old.operation,
            "10",
            "legacy-v1",
        )
        for sql in (
            "DELETE FROM orders",
            "UPDATE orders SET profile='doorless-v1'",
            "UPDATE orders SET timeout='5'",
        ):
            with pytest.raises(sqlite3.IntegrityError):
                conn.execute(sql)
    # Historical replay retains legacy semantics and never emits PWM.
    replay = raw(binaries["simulated"], path, frame(old), "--profile", "legacy-v1")
    assert "DUPLICATE" in replay.stdout and replay.stderr == ""
    # A different profile cannot reinterpret that immutable identity.
    conflict = raw(binaries["simulated"], path, frame(old), *PROFILE)
    assert "ID_CONFLICT" in conflict.stdout and conflict.stderr == ""


def test_legacy_event_can_finish_but_cannot_change_profile_mid_cycle(
    binaries, tmp_path
):
    path = tmp_path / "legacy.db"
    event = uuid4()
    old = command(event, "CLOSE_INSERTION_DOOR")
    legacy_database(path, old)
    request = command(event, "CYCLE_LOWER_HATCH")
    output = raw(binaries["simulated"], path, frame(request), *PROFILE)
    assert "REJECTED UNAVAILABLE" in output.stdout and output.stderr == ""
    output = raw(
        binaries["simulated"],
        path,
        frame(command(event, "CYCLE_LOWER_HATCH"))
        + frame(command(event, "CONFIRM_INITIAL_STATE")),
        "--profile",
        "legacy-v1",
    )
    assert output.stdout.count("ACCEPTED PENDING") == 2
    output = raw(binaries["simulated"], path, cycle_frames(uuid4()), *PROFILE)
    assert output.stdout.count("ACCEPTED PENDING") == 3
    assert len(pwm_lines(output.stderr)) == 4


def test_physical_entrypoint_refuses_even_doorless_arguments(binaries, tmp_path):
    path = tmp_path / "must-not-exist.db"
    output = subprocess.run(
        [str(binaries["physical"]), "--ipc-simulated", str(path), *PROFILE],
        capture_output=True,
        timeout=2,
    )
    assert output.returncode == 2 and not path.exists()
    assert b"READY" not in output.stdout and b"SIMULATED_PWM" not in output.stderr


@pytest.mark.anyio
async def test_default_adapter_refuses_legacy_only_handshake(tmp_path):
    executable = tmp_path / "legacy-only"
    executable.write_text(
        "#!/usr/bin/env python3\nprint('V1 READY SIMULATED', flush=True)\n"
    )
    executable.chmod(0o700)
    path = tmp_path / "must-not-exist.db"
    with pytest.raises(ControllerError, match="handshake|intern|permitida"):
        await CProcessController.connect(executable, path, context="test")
    assert not path.exists()


def test_invalid_simulated_profile_refuses_startup_before_journal(binaries, tmp_path):
    path = tmp_path / "must-not-exist.db"
    output = subprocess.run(
        [
            str(binaries["simulated"]),
            "--ipc-simulated",
            str(path),
            "--profile",
            "physical",
        ],
        capture_output=True,
        timeout=2,
    )
    assert output.returncode == 2 and not path.exists()
    assert output.stdout == output.stderr == b""
