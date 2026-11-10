"""Operational Python/C transport and real temporary journals, without devices."""

import asyncio
import json
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest

from app.main import create_app
from app.mechanical import ControllerError
from app.services.c_controller import CProcessController
from app.services.controller import UnavailableController
from app.services.controller_config import CControllerSettings
from app.services.mechanical import MechanicalService
from app.storage import CycleStore
from test_c_controller import binaries, command, frame, raw
from test_mechanical_journal import blocked

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")


def configuration(binaries, tmp_path, **updates):
    data = {
        "schema": "bingo-c-controller-v1",
        "executable": str(binaries["physical"]),
        "journal": str(tmp_path / "c.db"),
        "profile": "doorless-v1",
        "io_timeout_seconds": 0.5,
    }
    data.update(updates)
    path = tmp_path / "controller.json"
    path.write_text(json.dumps(data))
    return path


def physical(binary, journal, frames="", *options):
    return subprocess.run(
        [
            str(binary),
            "--ipc-physical",
            str(journal),
            "--profile",
            "doorless-v1",
            *options,
        ],
        input=frames,
        capture_output=True,
        text=True,
        timeout=3,
    )


def orders(journal):
    with sqlite3.connect(journal) as conn:
        return conn.execute(
            "SELECT id,event,operation,state,result,error FROM orders"
        ).fetchall()


@pytest.mark.anyio
async def test_operational_channel_durably_rejects_without_motion_and_replays(
    binaries, tmp_path
):
    config = configuration(binaries, tmp_path)
    store = CycleStore(tmp_path / "python.db")
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH")
    controller, readiness = await CProcessController.open_operational(
        config, backend_journal=store.path
    )
    assert readiness.transport == "CONNECTED_BLOCKED" and not readiness.execution_ready
    assert readiness.configuration == "INCOMPLETE"
    service = MechanicalService(store, controller, source="UNAVAILABLE")
    try:
        final = await service.submit(request)
        assert (final.phase, final.result, final.source, final.error_code) == (
            "REJECTED",
            "UNAVAILABLE",
            "UNAVAILABLE",
            "CONTROLLER_UNAVAILABLE",
        )
        assert await service.submit(request) == final
        assert (await controller.query(request)).state == "REJECTED"
        with pytest.raises(ControllerError):
            await controller.submit(request.model_copy(update={"event_id": uuid4()}))
        history = store.mechanical.history(request.mechanical_command_id)
        assert [entry.phase for entry in history] == [
            "INTENT",
            "DISPATCHING",
            "REJECTED",
        ]
        with store.transaction() as conn:
            row = conn.execute(
                "SELECT physical_confirmed,payload,receipt FROM cycles"
            ).fetchone()
            assert tuple(row) == (0, None, None)
    finally:
        await service.aclose()
        store.close()
    assert len(orders(tmp_path / "c.db")) == 1
    # Both journals reopen with the original identity and result. No new row.
    controller, _ = await CProcessController.open_operational(
        config, backend_journal=store.path
    )
    store = CycleStore(store.path)
    service = MechanicalService(store, controller, source="UNAVAILABLE")
    try:
        assert await service.submit(request) == final
        assert store.mechanical.history(request.mechanical_command_id) == history
        assert (await controller.submit(request)).state == "REJECTED"
        assert len(orders(tmp_path / "c.db")) == 1
    finally:
        await service.aclose()
        store.close()


def test_c_physical_rejections_duplicates_conflicts_and_initial_confirmation(
    binaries, tmp_path
):
    request = command(operation="CONFIRM_INITIAL_STATE")
    other = request.model_copy(update={"timeout_seconds": 7.0})
    path = tmp_path / "c.db"
    output = physical(
        binaries["physical"],
        path,
        frame(request)
        + frame(request)
        + frame(other)
        + f"V1 GET {request.mechanical_command_id}\n",
    )
    assert output.returncode == 0 and output.stderr == ""
    assert output.stdout.startswith(
        "V1 READY UNAVAILABLE DOORLESS_V1 PHYSICAL_BLOCKED\n"
    )
    assert (
        "V1 ERROR DUPLICATE" in output.stdout
        and "V1 ERROR ID_CONFLICT" in output.stdout
    )
    assert (
        output.stdout.count("REJECTED UNAVAILABLE CONTROLLER_UNAVAILABLE UNAVAILABLE")
        == 2
    )
    assert "ACCEPTED" not in output.stdout and "SUCCEEDED" not in output.stdout
    assert len(orders(path)) == 1
    with sqlite3.connect(path) as conn:
        for sql in (
            "DELETE FROM orders",
            "UPDATE orders SET timeout='8'",
            "UPDATE orders SET state='COMPLETED',result='SUCCEEDED',error='-'",
        ):
            with pytest.raises(sqlite3.IntegrityError):
                conn.execute(sql)


@pytest.mark.parametrize("mode", ["simulated", "physical"])
def test_controller_roles_cannot_open_each_others_history(binaries, tmp_path, mode):
    path = tmp_path / "history.db"
    if mode == "simulated":
        raw(binaries[mode], path, frame(command()))
    else:
        assert physical(binaries[mode], path, frame(command())).returncode == 0
    before = path.read_bytes()
    if mode == "simulated":
        output = physical(binaries["physical"], path)
    else:
        output = subprocess.run(
            [str(binaries["simulated"]), "--ipc-simulated", str(path)],
            capture_output=True,
            text=True,
            timeout=3,
        )
    assert output.returncode == 2 and "READY" not in output.stdout
    assert path.read_bytes() == before


@pytest.mark.parametrize(
    "options",
    [
        ["--profile", "legacy-v1"],
        ["--delay-ms", "1"],
        ["--fail-after", "0"],
        ["--enable-physical", "1"],
    ],
)
def test_physical_channel_refuses_profile_overrides_and_fault_options(
    binaries, tmp_path, options
):
    path = tmp_path / "must-not-exist.db"
    output = physical(binaries["physical"], path, "", *options)
    assert output.returncode == 2 and "READY" not in output.stdout
    assert list(tmp_path.iterdir()) == []


@pytest.mark.anyio
async def test_occupied_or_corrupt_c_journal_reports_transport_failure(
    binaries, tmp_path
):
    config = configuration(binaries, tmp_path)
    backend = tmp_path / "python.db"
    first, _ = await CProcessController.open_operational(
        config, backend_journal=backend
    )
    try:
        other, readiness = await CProcessController.open_operational(
            config, backend_journal=backend
        )
        assert isinstance(other, UnavailableController)
        assert readiness.transport == "FAILED" and not readiness.execution_ready
        await other.aclose()
    finally:
        await first.aclose()
    corrupt = tmp_path / "corrupt.db"
    corrupt.write_bytes(b"not sqlite")
    configuration(binaries, tmp_path, journal=str(corrupt))
    other, readiness = await CProcessController.open_operational(
        config, backend_journal=backend
    )
    assert isinstance(other, UnavailableController) and readiness.transport == "FAILED"
    assert corrupt.read_bytes() == b"not sqlite"
    await other.aclose()


@pytest.mark.anyio
@pytest.mark.parametrize("failure", ["timeout", "lost_response", "disconnect"])
async def test_transport_uncertainty_blocks_python_journal_without_resend(
    binaries, tmp_path, failure
):
    config = configuration(binaries, tmp_path, io_timeout_seconds=0.1)
    store = CycleStore(tmp_path / "python.db")
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH")
    controller, _ = await CProcessController.open_operational(
        config, backend_journal=store.path
    )
    service = MechanicalService(store, controller, source="UNAVAILABLE")
    if failure == "timeout":
        # Stop only this non-actuating child to exercise the real IPC timeout.
        controller._process.send_signal(signal.SIGSTOP)
    elif failure == "disconnect":
        controller._process.kill()
        await controller._process.wait()
    else:
        original = controller._rpc

        async def lose_response(line):
            await original(line)  # C has durably rejected; Python loses that fact.
            raise ConnectionError("test: lost rejection")

        controller._rpc = lose_response
    try:
        final = await service.submit(request)
        assert (final.phase, final.result) == ("INDETERMINATE", "UNKNOWN")
        assert store.active().state == "INDETERMINATE"
        assert await service.submit(request) == final
        with pytest.raises(ControllerError):
            await service.submit(command(request.event_id, "CYCLE_LOWER_HATCH"))
    finally:
        await service.aclose()
        store.close()
    before = orders(tmp_path / "c.db")
    controller, _ = await CProcessController.open_operational(
        config, backend_journal=store.path
    )
    store = CycleStore(store.path)
    service = MechanicalService(store, controller, source="UNAVAILABLE")
    try:
        assert await service.submit(request) == final
        assert orders(tmp_path / "c.db") == before
        assert store.active().state == "INDETERMINATE"
    finally:
        await service.aclose()
        store.close()


@pytest.mark.anyio
async def test_inconsistent_response_closes_channel_and_readiness_tracks_disconnect(
    binaries, tmp_path
):
    config = configuration(binaries, tmp_path)
    controller, _ = await CProcessController.open_operational(
        config, backend_journal=tmp_path / "python.db"
    )
    request = command(operation="CONFIRM_HAND_REMOVED")
    parts = await controller._rpc(frame(request).strip())
    parts[-1] = "PHYSICAL"  # Inject a false source into an actual C response.
    with pytest.raises(ControllerError) as error:
        await controller._checked_decode(request, parts)
    assert error.value.code == "INCONSISTENT_RESPONSE"
    assert controller.readiness.transport == "FAILED"
    assert (
        not controller.readiness.execution_ready
        and controller._process.returncode is not None
    )


@pytest.mark.anyio
@pytest.mark.parametrize("case", ["missing", "invalid", "simulated", "no_binary"])
async def test_configuration_failure_stays_unavailable_without_creating_c_journal(
    binaries, tmp_path, case
):
    config = None if case == "missing" else configuration(binaries, tmp_path)
    if case == "invalid":
        config.write_text('{"enable":true}')
    elif case == "simulated":
        configuration(binaries, tmp_path, executable=str(binaries["simulated"]))
    elif case == "no_binary":
        configuration(binaries, tmp_path, executable=str(tmp_path / "missing"))
    controller, readiness = await CProcessController.open_operational(
        config, backend_journal=tmp_path / "python.db"
    )
    assert (
        isinstance(controller, UnavailableController) and not readiness.execution_ready
    )
    assert not (tmp_path / "c.db").exists()
    await controller.aclose()


@pytest.mark.parametrize(
    "updates",
    [
        {"profile": "legacy-v1"},
        {"journal": "relative.db"},
        {"enable_physical": True},
        {"io_timeout_seconds": 0},
        {
            "physical": {
                "right": {"pwm_chip": 71, "pwm_channel": 8},
                "left": {"pwm_chip": 71, "pwm_channel": 8},
            }
        },
        {"physical": {"period_ns": 10, "right": {"open_pulse_ns": 10}}},
    ],
)
def test_explicit_configuration_rejects_ambiguous_or_unsafe_values(
    binaries, tmp_path, updates
):
    config = configuration(binaries, tmp_path, **updates)
    with pytest.raises(ValueError):
        CControllerSettings.from_file(config)
    assert not (tmp_path / "c.db").exists()


@pytest.mark.anyio
async def test_fully_declared_values_cannot_enable_motion_or_fill_unknowns(
    binaries, tmp_path
):
    # Arbitrary test declarations, NOT Orange Pi mapping/calibration evidence.
    wiring = {
        "connector_pin": "test-only",
        "soc_pad": "test-only",
        "pwm_chip": 71,
        "pwm_channel": 8,
        "closed_pulse_ns": 2,
        "open_pulse_ns": 3,
    }
    config = configuration(
        binaries,
        tmp_path,
        physical={
            "right": wiring,
            "left": {**wiring, "pwm_channel": 9},
            "period_ns": 10,
            "polarity": "normal",
            "mapping_reference": "test-only",
            "calibration_reference": "test-only",
            "completion_reference": "test-only",
            "safety_recovery_reference": "test-only",
        },
    )
    settings, readiness = await CProcessController.diagnose_operational(config)
    assert settings.physical.right.pwm_channel == 8
    assert readiness.configuration == "DECLARED" and not readiness.execution_ready
    assert "PHYSICAL_DISPATCH_DISABLED" in readiness.blockers
    report = await CProcessController.physical_preflight(settings.executable)
    assert (
        report.assembly.right.sysfs_channel
        is report.assembly.left.sysfs_channel
        is None
    )
    assert not settings.journal.exists()  # CLI/read-only assessment never starts IPC.


@pytest.mark.anyio
@pytest.mark.parametrize("alias", ["same", "symlink", "hardlink", "wal", "lock"])
async def test_c_journal_cannot_alias_python_database(binaries, tmp_path, alias):
    backend = tmp_path / "python.db"
    with sqlite3.connect(backend) as conn:
        conn.execute("CREATE TABLE retained(value)")
    journal = backend
    if alias in {"wal", "lock"}:
        journal = Path(str(backend) + ("-wal" if alias == "wal" else ".lock"))
    elif alias != "same":
        journal = tmp_path / "alias.db"
        if alias == "symlink":
            journal.symlink_to(backend)
        else:
            import os

            os.link(backend, journal)
    config = configuration(binaries, tmp_path, journal=str(journal))
    before = backend.read_bytes()
    controller, readiness = await CProcessController.open_operational(
        config, backend_journal=backend
    )
    assert isinstance(controller, UnavailableController)
    assert readiness.configuration == "INVALID" and backend.read_bytes() == before
    await controller.aclose()


def test_operational_lifespan_wires_existing_service_with_blocked_source(
    binaries, tmp_path, monkeypatch
):
    config = configuration(binaries, tmp_path)
    monkeypatch.setenv("BINGO_C_CONTROLLER_CONFIG", str(config))
    app = create_app()
    with TestClient(app) as client:
        assert app.state.controller_readiness.transport == "CONNECTED_BLOCKED"
        assert isinstance(app.state.controller, CProcessController)
        assert app.state.mechanical.source == "UNAVAILABLE"
        request = command(
            blocked(app.state.sessions.store).event_id, "CYCLE_LOWER_HATCH"
        )
        final = client.portal.call(app.state.mechanical.submit, request)
        assert final.phase == "REJECTED" and final.source == "UNAVAILABLE"
        assert not client.get("/local/status").json()["can_start_deposit"]
        assert client.get("/health").json() == {"status": "ok"}
    assert app.state.controller._process.returncode is not None


def test_operational_configuration_cannot_override_injected_controller(
    binaries, tmp_path, monkeypatch
):
    config = configuration(binaries, tmp_path)
    monkeypatch.setenv("BINGO_C_CONTROLLER_CONFIG", str(config))
    with pytest.raises(ValueError, match="conflita"):
        with TestClient(create_app(controller_factory=UnavailableController)):
            pass
    assert not (tmp_path / "c.db").exists()


def test_configured_cli_is_read_only_and_returns_blocked(binaries, tmp_path):
    config = configuration(binaries, tmp_path)
    output = subprocess.run(
        [sys.executable, "-m", "app.controller_cli", "--config", str(config)],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        timeout=10,  # Cold Python imports; C I/O retains its configured deadline.
    )
    assert output.returncode == 2 and output.stderr == ""
    data = json.loads(output.stdout)
    assert data["transport"] == "DIAGNOSTIC_OK" and not data["execution_ready"]
    assert not (tmp_path / "c.db").exists()
