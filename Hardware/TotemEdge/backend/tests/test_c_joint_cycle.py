"""Versioned joint plan and timing, real C diagnostics/journals, no motor executor."""

import json
import sqlite3
import subprocess
import sys

import pytest

from app.mechanical import ControllerError
from app.services.c_controller import CProcessController
from app.services.controller import UnavailableController
from app.services.controller_config import CControllerSettings
from test_c_controller import binaries, command, frame
from test_c_project_mapping import project_configuration
from test_c_pwm_driver import native, config_file, check
import test_c_controller_operational as operational_tests

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")

POLICY = {
    "mode": "joint-v1",
    "hold_open_ms": 5000,
    "hold_start": "after_both_open_commands",
    "hold_clock": "monotonic",
}
PLAN = (
    "REQUIRE_INITIAL_CLOSED",
    "OPEN_BOTH",
    "HOLD_OPEN",
    "CLOSE_BOTH",
    "AWAIT_INITIAL_EVIDENCE",
)


@pytest.mark.anyio
async def test_joint_plan_timing_and_diagnostics_agree_and_never_enable_dispatch(
    binaries, native, tmp_path
):
    path, _ = project_configuration(binaries, tmp_path)
    settings, readiness = await CProcessController.diagnose_operational(path)
    assert settings.physical.cycle.plan() == readiness.cycle_plan == PLAN
    assert readiness.cycle_policy.model_dump(exclude_none=True) == POLICY
    assert readiness.transport == "DIAGNOSTIC_OK" and not readiness.execution_ready
    assert "CYCLE_POLICY_UNVERIFIED" in readiness.blockers
    assert not (tmp_path / "c.db").exists()
    controller, connected = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    try:
        assert connected.cycle_policy == readiness.cycle_policy
        result = await controller.submit(command(operation="CYCLE_LOWER_HATCH"))
        assert (result.state, result.result, result.source) == (
            "REJECTED",
            "UNAVAILABLE",
            "UNAVAILABLE",
        )
    finally:
        await controller.aclose()
    # Reuse the native syscall-injection harness: constructing the plan must
    # perform zero PWM writes/opens and no timed wait. Unit inputs aren't calibration.
    complete = tmp_path / "complete"
    complete.mkdir()
    path, data = config_file(complete)
    data["physical"]["cycle"] = POLICY
    path.write_text(json.dumps(data))
    result = subprocess.run(
        [str(native), str(path), "plan", "0", "1"],
        capture_output=True,
        text=True,
        timeout=3,
        check=True,
    )
    assert tuple(result.stdout.splitlines()) == PLAN


@pytest.mark.parametrize(
    "field,value",
    [
        ("mode", "__missing__"),
        ("mode", None),
        ("mode", "joint"),
        ("mode", "joint-v2"),
        ("mode", True),
        ("hold_open_ms", "__missing__"),
        ("hold_open_ms", None),
        ("hold_open_ms", True),
        ("hold_open_ms", 5000.0),
        ("hold_open_ms", "5000"),
        ("hold_open_ms", 5),
        ("hold_open_ms", 0),
        ("hold_open_ms", -5000),
        ("hold_open_ms", 4999),
        ("hold_open_ms", 5001),
        ("hold_open_ms", 10**30),
        ("hold_start", "__missing__"),
        ("hold_start", None),
        ("hold_start", "after_first_open_command"),
        ("hold_start", "after_open_evidence"),
        ("hold_clock", "__missing__"),
        ("hold_clock", None),
        ("hold_clock", "wall_clock"),
        ("open_order", "left_then_right"),
        ("close_order", "right_then_left"),
        ("enable_physical", True),
    ],
)
def test_joint_policy_rejects_ambiguous_or_wrong_timing_in_both_parsers(
    binaries, tmp_path, field, value
):
    path, data = project_configuration(binaries, tmp_path)
    if value == "__missing__":
        data["physical"]["cycle"].pop(field)
    else:
        data["physical"]["cycle"][field] = value
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        CControllerSettings.from_file(path)
    assert check(binaries["physical"], path).returncode == 2
    assert not list(tmp_path.glob("c.db*"))


@pytest.mark.parametrize(
    "kind", ["absent", "empty", "partial", "sequential", "explicit_null_mode"]
)
@pytest.mark.anyio
async def test_legacy_configs_keep_their_original_plan_and_no_joint_timing(
    binaries, tmp_path, kind
):
    path, data = config_file(tmp_path)
    data["executable"] = str(binaries["physical"])
    if kind != "absent":
        old = {}
        if kind not in {"empty"}:
            old = {
                "open_order": "right_then_left",
                "drop_reference": "unit-only",
                "homologation_reference": "unit-only",
            }
        if kind in {"sequential", "explicit_null_mode"}:
            old["close_order"] = "left_then_right"
        if kind == "explicit_null_mode":
            old.update(mode=None, hold_open_ms=None, hold_clock=None, hold_start=None)
        data["physical"]["cycle"] = old
    path.write_text(json.dumps(data))
    settings, readiness = await CProcessController.diagnose_operational(path)
    assert readiness.transport == "DIAGNOSTIC_OK" and readiness.cycle_policy is None
    expected = (
        ()
        if kind in {"absent", "empty", "partial"}
        else (
            "OPEN_RIGHT",
            "OPEN_LEFT",
            "AWAIT_OPEN_EVIDENCE",
            "AWAIT_DROP_EVIDENCE",
            "CLOSE_LEFT",
            "CLOSE_RIGHT",
            "AWAIT_INITIAL_EVIDENCE",
        )
    )
    assert readiness.cycle_plan == settings.physical.cycle.plan() == expected
    raw = json.loads(check(binaries["physical"], path).stdout)
    assert "cycle_policy" not in raw  # Original diagnostic shape remains valid.


@pytest.mark.anyio
async def test_existing_ids_and_snapshots_cannot_be_promoted_to_joint_mode(
    binaries, tmp_path
):
    path, data = config_file(tmp_path)
    data["executable"] = str(binaries["physical"])
    data["physical"]["cycle"] = {
        "open_order": "left_then_right",
        "close_order": "right_then_left",
        "drop_reference": "unit-only",
        "homologation_reference": "unit-only",
    }
    path.write_text(json.dumps(data))
    old_bytes = path.read_bytes()
    request = command(operation="CYCLE_LOWER_HATCH")
    controller, _ = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    try:
        retained = await controller.submit(request)
    finally:
        await controller.aclose()
    data["physical"]["cycle"] = POLICY
    path.write_text(json.dumps(data))
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    try:
        assert readiness.cycle_plan == PLAN
        with pytest.raises(ControllerError) as error:
            await controller.submit(request)
        assert error.value.code == "C_ID_CONFLICT"
    finally:
        await controller.aclose()
    with sqlite3.connect(tmp_path / "c.db") as db:
        assert db.execute("PRAGMA user_version").fetchone()[0] == 4
        assert (
            db.execute("SELECT configuration FROM orders").fetchone()[0].encode()
            == old_bytes
        )
        assert db.execute("SELECT count(*) FROM orders").fetchone()[0] == 1
    path.write_bytes(old_bytes)
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    try:
        assert readiness.cycle_policy is None and len(readiness.cycle_plan) == 7
        assert await controller.submit(request) == retained
    finally:
        await controller.aclose()


@pytest.mark.parametrize("side", [0, 1])
@pytest.mark.parametrize("failure", [1, 2, 3, 4, 5])
def test_partial_channel_failures_remain_unknown_with_joint_config(
    native, tmp_path, side, failure
):
    path, data = config_file(tmp_path)
    data["physical"]["cycle"] = POLICY
    path.write_text(json.dumps(data))
    output = subprocess.run(
        [str(native), str(path), f"fail-{failure}", str(side), "1"],
        capture_output=True,
        text=True,
        timeout=3,
        check=True,
    )
    # Harness asserts PWM_UNKNOWN, inhibited driver and no second actuation.
    assert output.stdout.endswith("WRITE enable 0\n")
    assert "SUCCEEDED" not in output.stdout


def test_joint_restart_converts_unproven_intent_to_unknown_without_actuation(
    binaries, tmp_path
):
    path, _ = project_configuration(binaries, tmp_path)
    journal = tmp_path / "c.db"
    start = operational_tests.physical(
        binaries["physical"], journal, "", "--config", str(path)
    )
    assert start.returncode == 0
    request = command(operation="CYCLE_LOWER_HATCH")
    with sqlite3.connect(journal) as db:
        db.execute(
            "INSERT INTO orders VALUES(?,?,?,?,?,?,?,?,?,?)",
            (
                str(request.mechanical_command_id),
                str(request.event_id),
                request.operation,
                "10",
                "ACCEPTED",
                "PENDING",
                "-",
                "doorless-v1",
                "PHYSICAL",
                path.read_text(),
            ),
        )
    output = operational_tests.physical(
        binaries["physical"],
        journal,
        f"V1 GET {request.mechanical_command_id}\n"
        + frame(request)
        + frame(command(operation="CYCLE_LOWER_HATCH")),
        "--config",
        str(path),
    )
    assert output.returncode == 0 and output.stderr == ""
    assert "FAILED UNKNOWN EXECUTION_ERROR PHYSICAL" in output.stdout
    assert "V1 ERROR DUPLICATE" in output.stdout
    assert "REJECTED UNAVAILABLE CONTROLLER_BUSY UNAVAILABLE" in output.stdout
    assert "COMPLETED" not in output.stdout and "SUCCEEDED" not in output.stdout
    with sqlite3.connect(journal) as db:
        assert db.execute(
            "SELECT state,result FROM orders WHERE source='PHYSICAL'"
        ).fetchone() == ("FAILED", "UNKNOWN")


@pytest.mark.parametrize("failure", ["timeout", "lost_response", "disconnect"])
@pytest.mark.anyio
async def test_joint_transport_failures_keep_python_journal_indeterminate(
    binaries, tmp_path, monkeypatch, failure
):
    # Reuse the established service/journal failure tests under the new mode.
    original = operational_tests.configuration

    def configured(*args, **kwargs):
        path = original(*args, **kwargs)
        data = json.loads(path.read_text())
        data.setdefault("physical", {})["cycle"] = POLICY
        path.write_text(json.dumps(data))
        return path

    monkeypatch.setattr(operational_tests, "configuration", configured)
    await operational_tests.test_transport_uncertainty_blocks_python_journal_without_resend(
        binaries, tmp_path, failure
    )


@pytest.mark.parametrize("bad_policy", ["wrong_duration", "missing"])
@pytest.mark.anyio
async def test_matching_steps_with_wrong_timing_report_are_rejected(
    binaries, tmp_path, monkeypatch, bad_policy
):
    path, _ = project_configuration(binaries, tmp_path)
    original = CProcessController._read_diagnostic

    async def altered(executable, arguments, **kwargs):
        result = await original(executable, arguments, **kwargs)
        if arguments[0] == "--physical-config":
            policy = (
                None
                if bad_policy == "missing"
                else result.cycle_policy.model_copy(update={"hold_open_ms": 5001})
            )
            result = result.model_copy(update={"cycle_policy": policy})
        return result

    monkeypatch.setattr(CProcessController, "_read_diagnostic", staticmethod(altered))
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    assert isinstance(controller, UnavailableController)
    assert "PWM_CONFIGURATION_MISMATCH" in readiness.blockers and not list(
        tmp_path.glob("c.db*")
    )
    await controller.aclose()
