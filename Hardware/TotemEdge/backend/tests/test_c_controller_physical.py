"""Actual blocked C build and Python diagnostic, with no hardware or new simulator."""

import json
from pathlib import Path
import subprocess
import sys

import pytest

from app.mechanical import ControllerError
from app.services.c_controller import CProcessController, PhysicalPreflight
from test_c_controller import binaries, command, frame, raw

pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="Linux C toolchain: run controller/Dockerfile.test"
)


def diagnostic(binary, *extra):
    return subprocess.run(
        [str(binary), "--physical-preflight", *map(str, extra)],
        capture_output=True,
        text=True,
        timeout=2,
    )


def test_physical_report_distinguishes_assembly_from_historical_sysfs(binaries):
    output = diagnostic(binaries["physical"])
    assert output.returncode == 0 and output.stderr == ""
    report = PhysicalPreflight.model_validate_json(output.stdout)
    assert report.ready is report.physical_confirmed is False
    assert report.source == "UNAVAILABLE"
    right, left = report.assembly.right, report.assembly.left
    assert (right.pwm_label, right.closed_degrees, right.open_degrees) == (
        None,
        70,
        175,
    )
    assert (left.pwm_label, left.closed_degrees, left.open_degrees) == (None, 113, 5)
    assert right.sysfs_channel is left.sysfs_channel is None
    assert right.closed_pulse_ns is right.open_pulse_ns is None
    assert left.closed_pulse_ns is left.open_pulse_ns is None
    old = report.legacy_evidence
    assert (old.sysfs_chip, old.left_channel, old.right_channel) == (0, 3, 4)
    assert old.period_ns == 20_000_000
    assert old.nominal_pulses_ns == (500_000, 1_500_000, 2_500_000)
    assert old.drop_seconds == 6


def test_preflight_cannot_create_or_modify_a_journal(binaries, tmp_path):
    missing = tmp_path / "must-not-exist.db"
    assert diagnostic(binaries["physical"], missing).returncode == 2
    assert list(tmp_path.iterdir()) == []
    journal = tmp_path / "existing.db"
    raw(binaries["simulated"], journal, frame(command()))
    before = {p.name: p.read_bytes() for p in tmp_path.iterdir()}
    assert diagnostic(binaries["physical"]).returncode == 0
    assert before == {p.name: p.read_bytes() for p in tmp_path.iterdir()}
    assert diagnostic(binaries["physical"], journal).returncode == 2
    assert before == {p.name: p.read_bytes() for p in tmp_path.iterdir()}


@pytest.mark.anyio
async def test_python_reads_physical_report_but_refuses_physical_dispatch(
    binaries, tmp_path
):
    report = await CProcessController.physical_preflight(binaries["physical"])
    assert not report.ready and report.blockers[-1] == "PHYSICAL_DISPATCH_DISABLED"
    with pytest.raises(ControllerError):
        await CProcessController.connect(
            binaries["physical"], tmp_path / "blocked.db", context="test"
        )
    assert list(tmp_path.iterdir()) == []


@pytest.mark.anyio
async def test_simulated_or_missing_executable_cannot_supply_physical_report(
    binaries, tmp_path
):
    for executable in (binaries["simulated"], tmp_path / "missing"):
        with pytest.raises(ControllerError) as error:
            await CProcessController.physical_preflight(executable)
        assert error.value.code == "PHYSICAL_PREFLIGHT_FAILED"


@pytest.mark.parametrize(
    "field,value",
    [
        ("ready", True),
        ("physical_confirmed", True),
        ("source", "PHYSICAL"),
        ("build", "SIMULATED"),
        ("blockers", []),
        ("unexpected", True),
    ],
)
def test_diagnostic_rejects_readiness_claims_or_missing_barriers(
    binaries, field, value
):
    data = json.loads(diagnostic(binaries["physical"]).stdout)
    data[field] = value
    with pytest.raises(ValueError):
        PhysicalPreflight.model_validate_json(json.dumps(data))


def test_python_cli_reports_blocked_and_touches_no_state(binaries, tmp_path):
    output = subprocess.run(
        [
            sys.executable,
            "-m",
            "app.controller_cli",
            "--executable",
            str(binaries["physical"]),
        ],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        # Cold Python imports have a separate budget from the 2-second C I/O.
        timeout=10,
    )
    assert output.returncode == 2 and output.stderr == ""
    assert not PhysicalPreflight.model_validate_json(output.stdout).ready
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("mode", ["physical", "simulated"])
def test_physical_ipc_option_stays_blocked_before_journal(binaries, tmp_path, mode):
    journal = tmp_path / "blocked.db"
    output = subprocess.run(
        [str(binaries[mode]), "--ipc-physical", str(journal)],
        input=frame(command()),
        capture_output=True,
        text=True,
        timeout=2,
    )
    assert output.returncode == 2
    assert "READY" not in output.stdout and "RESULT" not in output.stdout
    assert "SIMULATED_PWM" not in output.stderr
    assert list(tmp_path.iterdir()) == []
