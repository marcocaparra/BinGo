"""Project convention, shared C/Python configuration and blocked cycle plan."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys

import pytest

from app.mechanical import ControllerError
from app.services.c_controller import CProcessController
from app.services.controller import UnavailableController
from app.services.controller_config import CControllerSettings
from app.services.mechanical import MechanicalService
from app.storage import CycleStore
from test_c_controller import binaries, command
from test_c_pwm_driver import native, config_file, check
from test_mechanical_journal import blocked

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")


def project_configuration(binaries, tmp_path, *, historical=True):
    source = Path(__file__).resolve().parents[2] / "controller/operational.example.json"
    data = json.loads(source.read_text())
    if historical:
        # Retain the prior planning-only snapshot for its compatibility tests.
        # Executor tests explicitly use historical=False (the current example).
        for key in ("completion_policy", "close_settle_ms", "initial_condition"):
            data["physical"]["cycle"].pop(key)
        data["physical"].update(calibration_reference=None, completion_reference=None)
        data["physical"]["cycle"]["homologation_reference"] = None
    data.update(executable=str(binaries["physical"]), journal=str(tmp_path / "c.db"))
    path = tmp_path / "project.json"
    path.write_text(json.dumps(data))
    return path, data


@pytest.mark.anyio
async def test_project_mapping_is_explicit_without_pinmux_or_pulse_inference(
    binaries, tmp_path
):
    path, _ = project_configuration(binaries, tmp_path)
    settings, readiness = await CProcessController.diagnose_operational(path)
    assert readiness.transport == "DIAGNOSTIC_OK" and not readiness.execution_ready
    assert readiness.configured_physical == settings.physical
    right, left = settings.physical.right, settings.physical.left
    assert (
        left.pwm_channel,
        left.closed_degrees,
        left.open_degrees,
        left.intended_signal,
    ) == (4, 113, 5, None)
    assert (
        right.pwm_channel,
        right.closed_degrees,
        right.open_degrees,
        right.intended_signal,
    ) == (3, 70, 175, None)
    assert left.pwm_chip == right.pwm_chip == 0
    assert settings.physical.period_ns == 20_000_000
    assert settings.physical.polarity == "normal"
    assert "2026-11-10" in settings.physical.mapping_reference
    assert (left.closed_pulse_ns, left.open_pulse_ns) == (1_350_000, 2_300_000)
    assert (right.closed_pulse_ns, right.open_pulse_ns) == (1_750_000, 600_000)
    assert (
        settings.physical.cycle.open_order
        is settings.physical.cycle.close_order
        is None
    )
    assert (
        left.soc_pad
        is right.soc_pad
        is left.connector_pin
        is right.connector_pin
        is None
    )
    assert "PWM_MAPPING_UNVERIFIED" in readiness.blockers
    assert "PULSE_CALIBRATION_UNVERIFIED" in readiness.blockers
    assert "CYCLE_POLICY_UNVERIFIED" in readiness.blockers
    assert readiness.cycle_plan == (
        "REQUIRE_INITIAL_CLOSED",
        "OPEN_BOTH",
        "HOLD_OPEN",
        "CLOSE_BOTH",
        "AWAIT_INITIAL_EVIDENCE",
    )
    assert readiness.cycle_policy.hold_open_ms == 5000
    assert not (tmp_path / "c.db").exists()


@pytest.mark.anyio
async def test_backend_passes_same_json_explicitly_and_retains_rejected_cycle(
    binaries, tmp_path, monkeypatch
):
    path, data = project_configuration(binaries, tmp_path)
    # Programmatic callers must not depend on a matching inherited environment.
    monkeypatch.setenv("BINGO_C_CONTROLLER_CONFIG", str(tmp_path / "wrong.json"))
    store = CycleStore(tmp_path / "python.db")
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=store.path
    )
    assert readiness.transport == "CONNECTED_BLOCKED"
    service = MechanicalService(store, controller, source="UNAVAILABLE")
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH")
    try:
        final = await service.submit(request)
        assert (final.phase, final.result, final.source) == (
            "REJECTED",
            "UNAVAILABLE",
            "UNAVAILABLE",
        )
        assert await service.submit(request) == final
    finally:
        await service.aclose()
    with sqlite3.connect(tmp_path / "c.db") as db:
        row = db.execute("SELECT id,configuration FROM orders").fetchone()
        assert (
            row[0] == str(request.mechanical_command_id) and json.loads(row[1]) == data
        )
    # A changed config does not reinterpret the retained C order identity.
    # Synthetic configuration drift only; never alter the proven wiring/map.
    data["physical"]["right"]["pwm_channel"] = 9
    path.write_text(json.dumps(data))
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=store.path
    )
    assert (
        readiness.configured_physical.right.pwm_channel == 9
    )  # Retained IDs must not be reinterpreted even under a valid new config.
    try:
        with pytest.raises(ControllerError) as error:
            await controller.submit(request)
        assert error.value.code == "C_ID_CONFLICT"
        with sqlite3.connect(tmp_path / "c.db") as db:
            retained = json.loads(
                db.execute("SELECT configuration FROM orders").fetchone()[0]
            )
            assert retained["physical"]["right"]["pwm_channel"] == 3
            assert retained["physical"]["left"]["pwm_channel"] == 4
    finally:
        await controller.aclose()
        store.close()


@pytest.mark.parametrize(
    "opening,closing",
    [
        ("left_then_right", "right_then_left"),
        ("right_then_left", "left_then_right"),
    ],
)
@pytest.mark.anyio
async def test_cycle_plan_agrees_between_c_python_and_native_without_actuation(
    binaries, native, tmp_path, opening, closing
):
    path, data = config_file(tmp_path)
    data["executable"] = str(binaries["physical"])
    data["physical"]["cycle"] = {
        "open_order": opening,
        "close_order": closing,
        "drop_reference": "unit-only",
        "homologation_reference": "unit-only",
    }
    path.write_text(json.dumps(data))
    settings, readiness = await CProcessController.diagnose_operational(path)
    assert readiness.transport == "DIAGNOSTIC_OK" and not readiness.execution_ready
    plan = readiness.cycle_plan
    assert plan == settings.physical.cycle.plan() and len(plan) == 7
    assert plan[2:4] == ("AWAIT_OPEN_EVIDENCE", "AWAIT_DROP_EVIDENCE")
    assert plan[-1] == "AWAIT_INITIAL_EVIDENCE"
    output = subprocess.run(
        [str(native), str(path), "plan", "0", "1"],
        capture_output=True,
        text=True,
        timeout=3,
        check=True,
    )
    assert tuple(output.stdout.splitlines()) == plan
    assert not (tmp_path / "c.db").exists()  # Planning never creates an intent.
    controller, _ = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    try:
        final = await controller.submit(command(operation="CYCLE_LOWER_HATCH"))
        assert final.state == "REJECTED"  # Declared plan is not homologation/evidence.
    finally:
        await controller.aclose()


def test_absent_cycle_order_cannot_gain_an_implicit_sequence(native, tmp_path):
    path, _ = config_file(tmp_path)
    output = subprocess.run(
        [str(native), str(path), "plan-blocked", "0", "1"],
        capture_output=True,
        text=True,
        timeout=3,
        check=True,
    )
    assert output.stdout == ""


@pytest.mark.parametrize(
    "field,value",
    [
        ("open_order", "simultaneous"),
        ("open_order", 0),
        ("drop_reference", ""),
        ("enable_physical", True),
    ],
)
def test_cycle_invalid_or_enable_options_are_rejected_by_both_parsers(
    binaries, tmp_path, field, value
):
    path, data = project_configuration(binaries, tmp_path)
    data["physical"]["cycle"][field] = value
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        CControllerSettings.from_file(path)
    assert check(binaries["physical"], path).returncode == 2
    assert not (tmp_path / "c.db").exists()


@pytest.mark.anyio
async def test_c_python_configuration_disagreement_closes_preparation(
    binaries, tmp_path, monkeypatch
):
    path, _ = project_configuration(binaries, tmp_path)
    read = CProcessController._read_diagnostic

    async def diverge(executable, arguments, **options):
        result = await read(executable, arguments, **options)
        if arguments[0] == "--physical-config":
            right = result.mapping.right.model_copy(update={"pwm_channel": 999})
            result = result.model_copy(
                update={"mapping": result.mapping.model_copy(update={"right": right})}
            )
        return result

    monkeypatch.setattr(CProcessController, "_read_diagnostic", staticmethod(diverge))
    controller, readiness = await CProcessController.open_operational(
        path, backend_journal=tmp_path / "python.db"
    )
    assert (
        isinstance(controller, UnavailableController)
        and readiness.transport == "FAILED"
    )
    assert "PWM_CONFIGURATION_MISMATCH" in readiness.blockers
    assert not (tmp_path / "c.db").exists()
    await controller.aclose()
