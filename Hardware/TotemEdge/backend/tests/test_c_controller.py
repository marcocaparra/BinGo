"""Real Python↔C subprocess communication; Linux toolchain, simulated PWM only."""

import asyncio
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
from uuid import uuid4

import pytest

from app.cycles import CycleError
from app.mechanical import ControllerError, MechanicalCommand
from app.services.c_controller import CProcessController
from app.services.mechanical import MechanicalService
from app.services.simulation_flow import SimulationFlow
from app.storage import CycleStore

pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="Linux C toolchain: run controller/Dockerfile.test"
)


@pytest.fixture(scope="module")
def binaries(tmp_path_factory):
    compiler = shutil.which("cc")
    assert compiler, "Install gcc/libc6-dev/libsqlite3-dev or use Dockerfile.test"
    directory = tmp_path_factory.mktemp("c-binaries")
    source = Path(__file__).resolve().parents[2] / "controller/bingo_controller.c"
    result = {}
    for mode in ("simulated", "physical"):
        target = directory / mode
        args = [
            compiler,
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unused-function",
        ]
        if mode == "simulated":
            args += ["-DBINGO_PWM_SIMULATED"]
        subprocess.run(args + [str(source), "-lsqlite3", "-o", str(target)], check=True)
        result[mode] = target
    return result


def command(event=None, operation="OPEN_INSERTION_DOOR", timeout=10.0):
    return MechanicalCommand(
        event_id=event or uuid4(), operation=operation, timeout_seconds=timeout
    )


def frame(request):
    return (
        f"V1 SUBMIT {request.mechanical_command_id} {request.event_id} "
        f"{request.operation} {format(request.timeout_seconds, '.17g')}\n"
    )


def raw(binary, journal, lines="", *options):
    return subprocess.run(
        [str(binary), "--ipc-simulated", str(journal), *options],
        input=lines,
        text=True,
        capture_output=True,
        timeout=5,
        check=True,
    )


@pytest.mark.parametrize("mode", ["simulated", "physical"])
@pytest.mark.parametrize("args", [[], ["--teste"]])
def test_startup_does_not_move_or_run_legacy_demo(binaries, mode, args):
    result = subprocess.run(
        [str(binaries[mode]), *args], capture_output=True, timeout=2
    )
    assert result.returncode == 2
    assert result.stdout == b"" and b"SIMULATED_PWM" not in result.stderr


def test_durable_duplicate_and_conflicting_id_do_not_repeat_pwm(binaries, tmp_path):
    request = command()
    conflict = request.model_copy(update={"event_id": uuid4()})
    journal = tmp_path / "c.sqlite3"
    result = raw(
        binaries["simulated"],
        journal,
        frame(request)
        + frame(request)
        + frame(conflict)
        + f"V1 GET {request.mechanical_command_id}\n",
    )
    assert "V1 ERROR DUPLICATE" in result.stdout
    assert "V1 ERROR ID_CONFLICT" in result.stdout
    assert "COMPLETED SUCCEEDED - SIMULATED" in result.stdout
    assert result.stderr.count("SIMULATED_PWM") == 2
    again = raw(
        binaries["simulated"],
        journal,
        frame(request) + f"V1 GET {request.mechanical_command_id}\n",
    )
    assert "V1 ERROR DUPLICATE" in again.stdout
    assert "COMPLETED SUCCEEDED - SIMULATED" in again.stdout
    assert "SIMULATED_PWM" not in again.stderr
    with sqlite3.connect(journal) as conn:
        assert conn.execute("SELECT count(*) FROM orders").fetchone()[0] == 1


@pytest.mark.parametrize(
    "line",
    [
        "wrong protocol\n",
        "V1 GET not-an-id\n",
        "X" * 600 + "\n",
        "V1 SUBMIT {id} {event} NOT_AN_OPERATION 10\n",
        "V1 SUBMIT {id} {event} OPEN_INSERTION_DOOR nan\n",
        "V1 SUBMIT {id} {event} OPEN_INSERTION_DOOR -1\n",
        "V1 SUBMIT {id} {event} OPEN_INSERTION_DOOR 10 extra\n",
    ],
)
def test_invalid_frames_have_no_effect(binaries, tmp_path, line):
    result = raw(
        binaries["simulated"],
        tmp_path / "c.sqlite3",
        line.format(id=uuid4(), event=uuid4()),
    )
    assert "V1 ERROR INVALID_" in result.stdout
    assert "SIMULATED_PWM" not in result.stderr


@pytest.mark.parametrize(
    "operation", ["CLOSE_INSERTION_DOOR", "CYCLE_LOWER_HATCH", "CONFIRM_INITIAL_STATE"]
)
def test_c_rejects_incompatible_initial_sequence(binaries, tmp_path, operation):
    result = raw(
        binaries["simulated"],
        tmp_path / "c.sqlite3",
        frame(command(operation=operation)),
    )
    assert "REJECTED UNAVAILABLE CONTROLLER_BUSY SIMULATED" in result.stdout
    assert "SIMULATED_PWM" not in result.stderr


@pytest.mark.anyio
async def test_full_flow_uses_existing_python_service_and_journal(binaries, tmp_path):
    controller = await CProcessController.connect(
        binaries["simulated"], tmp_path / "c.sqlite3", context="test"
    )
    store = CycleStore(tmp_path / "python.sqlite3", simulation_enabled=True)
    service = MechanicalService(store, controller, source="SIMULATED")
    flow = SimulationFlow(store, service)
    event = flow.start(uuid4()).session.event_id
    flow.safety(event, False)
    try:
        for operation in (
            "OPEN_INSERTION_DOOR",
            "CLOSE_INSERTION_DOOR",
            "CYCLE_LOWER_HATCH",
            "CONFIRM_INITIAL_STATE",
        ):
            if operation == "CYCLE_LOWER_HATCH":
                flow.review_fixture(event)
            request = command(event, operation)
            accepted = await service.submit(
                request, hand_removed=operation == "CLOSE_INSERTION_DOOR"
            )
            assert (accepted.phase, accepted.result) == ("ACCEPTED", "PENDING")
            final = await service.wait(request.mechanical_command_id)
            assert (final.phase, final.result, final.source) == (
                "COMPLETED",
                "SUCCEEDED",
                "SIMULATED",
            )
            assert await service.submit(request) == final
            assert [
                h.phase for h in store.mechanical.history(request.mechanical_command_id)
            ] == ["INTENT", "DISPATCHING", "ACCEPTED", "COMPLETED"]
        assert flow.get(event).session.state == "COMPLETED"
        with store.transaction() as conn:
            row = conn.execute(
                "SELECT physical_confirmed,payload,receipt,central_scope FROM cycles"
            ).fetchone()
            assert tuple(row) == (0, None, None, None)
        with sqlite3.connect(tmp_path / "c.sqlite3") as conn:
            assert conn.execute("SELECT count(*) FROM orders").fetchone()[0] == 4
    finally:
        await service.aclose()
        store.close()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "fault", ["backend_timeout", "ipc_timeout", "disconnect", "partial_failure"]
)
async def test_uncertainty_blocks_replay_and_survives_both_restarts(
    binaries, tmp_path, fault
):
    c_path, python_path = tmp_path / "c.sqlite3", tmp_path / "python.sqlite3"
    controller = await CProcessController.connect(
        binaries["simulated"],
        c_path,
        context="test",
        io_timeout_seconds=0.05 if fault == "ipc_timeout" else 2.0,
        delay_ms=0 if fault == "partial_failure" else 1000,
        fail_after=1 if fault == "partial_failure" else None,
    )
    store = CycleStore(python_path, simulation_enabled=True)
    service = MechanicalService(store, controller, source="SIMULATED")
    flow = SimulationFlow(store, service)
    event = flow.start(uuid4()).session.event_id
    flow.safety(event, False)
    request = command(event, timeout=0.05 if fault == "backend_timeout" else 10.0)
    try:
        await service.submit(request)
        if fault == "disconnect":
            controller._process.kill()
        final = await service.wait(request.mechanical_command_id)
        assert (
            final.phase
            == {
                "backend_timeout": "TIMED_OUT",
                "ipc_timeout": "TIMED_OUT",
                "disconnect": "INDETERMINATE",
                "partial_failure": "FAILED",
            }[fault]
        )
        assert store.active().state == "INDETERMINATE"
        assert await service.submit(request) == final
        with pytest.raises((ControllerError, CycleError)):
            await service.submit(command(event))
    finally:
        await service.aclose()
        store.close()

    controller = await CProcessController.connect(
        binaries["simulated"], c_path, context="test"
    )
    store = CycleStore(python_path, simulation_enabled=True)
    service = MechanicalService(store, controller, source="SIMULATED")
    try:
        assert await service.submit(request) == final
        # An explicit device query is diagnostic, never a recovery promotion.
        observed = await controller.query(request)
        assert observed.state == "FAILED"
        assert observed.result == (
            "FAILURE" if fault == "partial_failure" else "UNKNOWN"
        )
        assert service.get(request.mechanical_command_id) == final
        rejected = await controller.submit(command(event))
        assert rejected.state == "REJECTED"
        with sqlite3.connect(c_path) as conn:
            assert (
                conn.execute(
                    "SELECT count(*) FROM orders WHERE state='COMPLETED'"
                ).fetchone()[0]
                == 0
            )
    finally:
        await service.aclose()
        store.close()


@pytest.mark.anyio
async def test_explicit_reconnect_queries_completed_order_without_resubmitting(
    binaries, tmp_path
):
    path = tmp_path / "c.sqlite3"
    request = command()
    controller = await CProcessController.connect(
        binaries["simulated"], path, context="test"
    )
    try:
        assert (await controller.submit(request)).state == "ACCEPTED"
        assert (
            await controller.wait(request.mechanical_command_id)
        ).state == "COMPLETED"
    finally:
        await controller.aclose()
    controller = await CProcessController.connect(
        binaries["simulated"], path, context="test"
    )
    try:
        assert (await controller.query(request)).state == "COMPLETED"
        assert (await controller.submit(request)).state == "COMPLETED"
        with sqlite3.connect(path) as conn:
            assert conn.execute("SELECT count(*) FROM orders").fetchone()[0] == 1
    finally:
        await controller.aclose()


@pytest.mark.anyio
async def test_device_journal_has_exclusive_process_owner(binaries, tmp_path):
    path = tmp_path / "c.sqlite3"
    controller = await CProcessController.connect(
        binaries["simulated"], path, context="test"
    )
    try:
        with pytest.raises(ControllerError):
            await CProcessController.connect(
                binaries["simulated"], path, context="test"
            )
    finally:
        await controller.aclose()


@pytest.mark.parametrize("damage", [b"not sqlite", None])
def test_device_refuses_corrupt_or_future_journal(binaries, tmp_path, damage):
    path = tmp_path / "c.sqlite3"
    if damage:
        path.write_bytes(damage)
    else:
        with sqlite3.connect(path) as conn:
            conn.execute("PRAGMA user_version=99")
    result = subprocess.run(
        [str(binaries["simulated"]), "--ipc-simulated", str(path)],
        capture_output=True,
        timeout=2,
    )
    assert result.returncode == 2
    assert b"READY" not in result.stdout and b"SIMULATED_PWM" not in result.stderr


def test_order_identity_and_retention_are_protected(binaries, tmp_path):
    path = tmp_path / "c.sqlite3"
    raw(binaries["simulated"], path, frame(command()))
    with sqlite3.connect(path) as conn:
        for sql in ("UPDATE orders SET timeout='20'", "DELETE FROM orders"):
            with pytest.raises(sqlite3.IntegrityError):
                conn.execute(sql)
    assert path.stat().st_mode & 0o077 == 0


def test_missing_journal_protection_blocks_startup(binaries, tmp_path):
    path = tmp_path / "c.sqlite3"
    raw(binaries["simulated"], path)
    with sqlite3.connect(path) as conn:
        conn.execute("DROP TRIGGER order_identity")
    result = subprocess.run(
        [str(binaries["simulated"]), "--ipc-simulated", str(path)],
        capture_output=True,
        timeout=2,
    )
    assert result.returncode == 2
    assert b"READY" not in result.stdout and b"SIMULATED_PWM" not in result.stderr


@pytest.mark.anyio
async def test_physical_binary_cannot_be_labeled_simulated(binaries, tmp_path):
    path = tmp_path / "c.sqlite3"
    with pytest.raises(ControllerError):
        await CProcessController.connect(binaries["physical"], path, context="test")
    assert not path.exists()


def test_previously_completed_event_cannot_start_again(binaries, tmp_path):
    event = uuid4()
    other = uuid4()
    operations = (
        "OPEN_INSERTION_DOOR",
        "CLOSE_INSERTION_DOOR",
        "CYCLE_LOWER_HATCH",
        "CONFIRM_INITIAL_STATE",
    )
    frames = "".join(
        frame(command(cycle, op)) for cycle in (event, other) for op in operations
    )
    result = raw(
        binaries["simulated"], tmp_path / "c.sqlite3", frames + frame(command(event))
    )
    assert result.stdout.count("ACCEPTED PENDING") == 8
    assert result.stdout.endswith("REJECTED UNAVAILABLE CONTROLLER_BUSY SIMULATED\n")
    assert result.stderr.count("SIMULATED_PWM") == 16
