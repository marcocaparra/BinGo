"""Actual C executor/IPC/journal with link-time syscall faults; no hardware."""

import json
import sqlite3
import subprocess
import sys
from uuid import uuid4

import pytest

from app.services.c_controller import CProcessController
from app.services.controller import UnavailableController
from app.services.controller_config import CControllerSettings
from test_c_controller import binaries, command, frame
from test_c_project_mapping import project_configuration
from test_c_pwm_driver import native, check
from test_c_controller_operational import physical

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")

PLAN = ("REQUIRE_CLOSED_PWM", "OPEN_BOTH", "HOLD_OPEN", "CLOSE_BOTH", "SETTLE_CLOSED")


def run(native, config, frames, mode="execute"):
    return subprocess.run(
        [str(native), str(config), mode, "0", "1"],
        input=frames, capture_output=True, text=True, timeout=3,
    )


def rows(path):
    with sqlite3.connect(path) as db:
        return db.execute(
            "SELECT id,event,state,result,error,source,configuration FROM orders ORDER BY rowid"
        ).fetchall()


@pytest.mark.anyio
async def test_operational_policy_agrees_but_python_cannot_launch_active_executor(binaries, tmp_path, monkeypatch):
    path, _ = project_configuration(binaries, tmp_path, historical=False)
    settings, readiness = await CProcessController.diagnose_operational(path)
    assert readiness.transport == "DIAGNOSTIC_OK"
    assert settings.physical.cycle.plan() == readiness.cycle_plan == PLAN
    assert readiness.cycle_policy.close_settle_ms == 5000
    assert readiness.cycle_policy.hold_open_ms == 5000
    assert readiness.c_executor_configured and not readiness.execution_ready
    assert "PHYSICAL_SUPERVISION_PENDING" in readiness.blockers

    async def forbidden(*args, **kwargs):
        pytest.fail("Python must not launch an active physical capability")

    monkeypatch.setattr(CProcessController, "_launch", forbidden)
    controller, readiness = await CProcessController.open_operational(path, backend_journal=tmp_path / "python.db")
    assert isinstance(controller, UnavailableController)
    assert not list(tmp_path.glob("c.db*"))
    await controller.aclose()


@pytest.mark.parametrize("field,value", [
    ("completion_policy", "sensor"), ("completion_policy", None),
    ("completion_policy", True), ("close_settle_ms", None),
    ("close_settle_ms", True), ("close_settle_ms", "5000"),
    ("close_settle_ms", 5000.0), ("close_settle_ms", 0),
    ("close_settle_ms", 4999), ("close_settle_ms", 5001),
    ("initial_condition", None), ("initial_condition", "measured_closed"),
    ("mode", None), ("open_order", "right_then_left"),
])
def test_invalid_operational_policy_is_rejected_by_c_and_python(binaries, tmp_path, field, value):
    path, data = project_configuration(binaries, tmp_path, historical=False)
    data["physical"]["cycle"][field] = value
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        CControllerSettings.from_file(path)
    assert check(binaries["physical"], path).returncode == 2
    assert not list(tmp_path.glob("c.db*"))


def test_joint_executor_writes_pairs_then_waits_full_approved_durations(native, binaries, tmp_path):
    path, data = project_configuration(binaries, tmp_path, historical=False)
    request = command(operation="CYCLE_LOWER_HATCH", timeout=30)
    output = run(native, path, frame(request) + f"V1 GET {request.mechanical_command_id}\n")
    assert output.returncode == 0, output.stderr
    assert "V1 READY PHYSICAL DOORLESS_V1 OPERATIONAL_SEQUENCE_V1" in output.stdout
    assert "ACCEPTED PENDING - PHYSICAL" in output.stdout
    assert "COMPLETED SUCCEEDED - PHYSICAL" in output.stdout
    assert [line for line in output.stdout.splitlines() if line.startswith("WRITE")] == [
        "WRITE duty_cycle 600000 AT 1000000000",
        "WRITE duty_cycle 2300000 AT 1000000000",
        "WRITE duty_cycle 1750000 AT 6000000000",
        "WRITE duty_cycle 1350000 AT 6000000000",
    ]
    assert "ELAPSED_NS 10000000000" in output.stdout
    retained = rows(tmp_path / "c.db")
    assert len(retained) == 1
    assert retained[0][2:6] == ("COMPLETED", "SUCCEEDED", "-", "PHYSICAL")
    assert json.loads(retained[0][6]) == data


@pytest.mark.parametrize("mode,writes", [
    ("execute-open-1", 1), ("execute-open-2", 2),
    ("execute-close-1", 3), ("execute-close-2", 4),
    ("execute-short", 2), ("execute-close-error", 1),
    ("execute-interrupt-hold", 2), ("execute-interrupt-settle", 4),
    ("execute-lost-peer", 2), ("execute-timeout", 2), ("execute-initial", 0),
    ("execute-timeout-settle", 4), ("execute-signal-pair", 1),
    ("execute-period", 0), ("execute-polarity", 0), ("execute-disabled", 0),
    ("execute-missing", 0), ("execute-clock", 2),
])
def test_partial_failures_never_complete_or_correctively_move(native, binaries, tmp_path, mode, writes):
    path, _ = project_configuration(binaries, tmp_path, historical=False)
    request = command(operation="CYCLE_LOWER_HATCH", timeout=30)
    output = run(native, path, frame(request), mode)
    assert output.returncode == 0, output.stderr
    assert output.stdout.count("WRITE ") == writes
    retained = rows(tmp_path / "c.db")
    assert retained[0][2:6] == ("FAILED", "UNKNOWN", "EXECUTION_ERROR", "PHYSICAL")
    assert "COMPLETED" not in output.stdout
    # Restart, GET and both replayed/new IDs cannot cause more output writes.
    retry = run(native, path, f"V1 GET {request.mechanical_command_id}\n" + frame(request) +
                frame(command(operation="CYCLE_LOWER_HATCH", timeout=30)))
    assert retry.returncode == 0 and "WRITE " not in retry.stdout, retry.stderr
    assert "FAILED UNKNOWN EXECUTION_ERROR PHYSICAL" in retry.stdout
    assert "V1 ERROR DUPLICATE" in retry.stdout
    assert "CONTROLLER_BUSY" in retry.stdout


def test_crash_after_durable_intent_recovers_unknown_without_redispatch(native, binaries, tmp_path):
    path, _ = project_configuration(binaries, tmp_path, historical=False)
    request = command(operation="CYCLE_LOWER_HATCH", timeout=30)
    crashed = run(native, path, frame(request), "execute-crash")
    assert crashed.returncode == 77
    assert rows(tmp_path / "c.db")[0][2:4] == ("ACCEPTED", "PENDING")
    output = run(native, path, f"V1 GET {request.mechanical_command_id}\n" + frame(request))
    assert output.returncode == 0 and "WRITE " not in output.stdout
    assert "UNKNOWN" in output.stdout and "DUPLICATE" in output.stdout
    assert rows(tmp_path / "c.db")[0][2:4] == ("FAILED", "UNKNOWN")


def test_completed_identity_and_event_cannot_repeat_cycle(native, binaries, tmp_path):
    path, data = project_configuration(binaries, tmp_path, historical=False)
    request = command(operation="CYCLE_LOWER_HATCH", timeout=30)
    repeated_event = command(request.event_id, "CYCLE_LOWER_HATCH", timeout=30)
    output = run(native, path, frame(request) + frame(request) + frame(repeated_event))
    assert output.returncode == 0 and output.stdout.count("WRITE ") == 4
    assert "DUPLICATE" in output.stdout and "CONTROLLER_BUSY" in output.stdout
    # Durable operational result remains readable on restart, without writes.
    replay = run(native, path, f"V1 GET {request.mechanical_command_id}\n" + frame(request))
    assert replay.returncode == 0 and "WRITE " not in replay.stdout
    assert "COMPLETED SUCCEEDED" in replay.stdout and "DUPLICATE" in replay.stdout
    data["physical"]["right"]["open_pulse_ns"] += 1
    path.write_text(json.dumps(data))
    conflict = run(native, path, frame(request))
    assert "ID_CONFLICT" in conflict.stdout and "WRITE " not in conflict.stdout


@pytest.mark.parametrize("timeout,operation", [(10, "CYCLE_LOWER_HATCH"), (5, "CYCLE_LOWER_HATCH"), (30, "CONFIRM_INITIAL_STATE"), (30, "OPEN_INSERTION_DOOR")])
def test_insufficient_budget_and_other_operations_are_rejected_without_io(native, binaries, tmp_path, timeout, operation):
    path, _ = project_configuration(binaries, tmp_path, historical=False)
    output = run(native, path, frame(command(operation=operation, timeout=timeout)))
    assert output.returncode == 0 and "WRITE " not in output.stdout
    assert rows(tmp_path / "c.db")[0][2:6] == ("REJECTED", "UNAVAILABLE", "CONTROLLER_UNAVAILABLE", "UNAVAILABLE")


def test_no_policy_and_missing_approval_references_cannot_dispatch(native, binaries, tmp_path):
    path, data = project_configuration(binaries, tmp_path)  # Earlier joint plan.
    output = run(native, path, frame(command(operation="CYCLE_LOWER_HATCH", timeout=30)))
    assert output.returncode == 0 and "PHYSICAL_BLOCKED" in output.stdout
    assert "WRITE " not in output.stdout
    assert rows(tmp_path / "c.db")[0][2] == "REJECTED"


@pytest.mark.parametrize("missing", ["mapping_reference", "calibration_reference", "completion_reference", "homologation_reference"])
def test_approval_reference_is_required_beside_the_semantic_policy(native, binaries, tmp_path, missing):
    path, data = project_configuration(binaries, tmp_path, historical=False)
    target = data["physical"]["cycle"] if missing == "homologation_reference" else data["physical"]
    target[missing] = None
    path.write_text(json.dumps(data))
    assert not CControllerSettings.from_file(path).physical.c_executor_configured()
    diagnostic = json.loads(check(binaries["physical"], path).stdout)
    assert not diagnostic["c_executor_configured"]
    output = run(native, path, frame(command(operation="CYCLE_LOWER_HATCH", timeout=30)))
    assert output.returncode == 0 and "WRITE " not in output.stdout
    assert rows(tmp_path / "c.db")[0][2] == "REJECTED"


def test_real_c_pipe_loss_blocks_before_any_hardware_access(binaries, tmp_path):
    path, _ = project_configuration(binaries, tmp_path, historical=False)
    output = physical(binaries["physical"], tmp_path / "c.db",
                      frame(command(operation="CYCLE_LOWER_HATCH", timeout=30)), "--config", str(path))
    assert output.returncode == 0
    assert rows(tmp_path / "c.db")[0][2:4] == ("FAILED", "UNKNOWN")


def test_v3_migration_preserves_old_snapshot_unknown_and_rowid(native, binaries, tmp_path):
    path, data = project_configuration(binaries, tmp_path, historical=False)
    db_path = tmp_path / "c.db"
    old_id, old_event = str(uuid4()), str(uuid4())
    old_snapshot = '{"physical":{"cycle":{"mode":"joint-v1"}}}'
    with sqlite3.connect(db_path) as db:
        db.executescript("""
            CREATE TABLE orders(id TEXT PRIMARY KEY,event TEXT,operation TEXT,timeout TEXT,
              state TEXT,result TEXT,error TEXT,profile TEXT,source TEXT,configuration TEXT);
            CREATE TRIGGER order_identity BEFORE UPDATE OF id,event,operation,timeout,profile,source,configuration ON orders
              BEGIN SELECT RAISE(ABORT,'Immutable order identity'); END;
            CREATE TRIGGER order_retention BEFORE DELETE ON orders
              BEGIN SELECT RAISE(ABORT,'Retained order identity'); END;
            PRAGMA application_id=1112098640; PRAGMA user_version=3;
        """)
        db.execute("INSERT INTO orders(rowid,id,event,operation,timeout,state,result,error,profile,source,configuration) VALUES(37,?,?,'CYCLE_LOWER_HATCH','10','ACCEPTED','PENDING','-','doorless-v1','PHYSICAL',?)", (old_id, old_event, old_snapshot))
    output = run(native, path, f"V1 GET {old_id}\n" + frame(command(operation="CYCLE_LOWER_HATCH", timeout=30)))
    assert output.returncode == 0 and "WRITE " not in output.stdout
    assert "CONTROLLER_BUSY" in output.stdout
    with sqlite3.connect(db_path) as db:
        assert db.execute("PRAGMA user_version").fetchone() == (4,)
        assert db.execute("SELECT rowid,id,event,configuration,state,result FROM orders WHERE id=?", (old_id,)).fetchone() == (37, old_id, old_event, old_snapshot, "FAILED", "UNKNOWN")
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("UPDATE orders SET state='COMPLETED',result='SUCCEEDED',error='-' WHERE id=?", (old_id,))
        with pytest.raises(sqlite3.IntegrityError):
            db.execute("DELETE FROM orders WHERE id=?", (old_id,))
