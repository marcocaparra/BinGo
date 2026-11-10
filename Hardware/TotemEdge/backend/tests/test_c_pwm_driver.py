"""Native C base-driver tests; syscall fault injection, never motor simulation."""

import json
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
from uuid import uuid4

import pytest

from test_c_controller import binaries, command, frame
from test_c_controller_operational import physical

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux C toolchain")


@pytest.fixture(scope="module")
def native(tmp_path_factory):
    source = Path(__file__).resolve().parents[2] / "controller/tests/pwm_driver_test.c"
    target = tmp_path_factory.mktemp("pwm-native") / "unit"
    subprocess.run(
        [
            "cc",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unused-function",
            str(source),
            "-lsqlite3",
            "-Wl,--wrap=open,--wrap=openat,--wrap=read,--wrap=write,--wrap=close",
            "-o",
            str(target),
        ],
        check=True,
    )
    return target


def config_file(tmp_path, **updates):
    # Arbitrary unit inputs, NOT Orange Pi pin mapping/calibration.
    wiring = {
        "connector_pin": "unit-only",
        "soc_pad": "unit-only",
        "pwm_chip": 71,
        "pwm_channel": 8,
        "closed_pulse_ns": 10,
        "open_pulse_ns": 20,
    }
    data = {
        "schema": "bingo-c-controller-v1",
        "executable": "/unit-only/controller",
        "journal": str(tmp_path / "c.db"),
        "profile": "doorless-v1",
        "physical": {
            "right": wiring,
            "left": {**wiring, "pwm_chip": 72, "pwm_channel": 9},
            "period_ns": 100,
            "polarity": "inversed",
            "mapping_reference": "unit-only",
            "calibration_reference": "unit-only",
            "completion_reference": "unit-only",
            "safety_recovery_reference": "unit-only",
        },
    }
    data.update(updates)
    path = tmp_path / "controller.json"
    path.write_text(json.dumps(data))
    return path, data


def check(binary, path):
    return subprocess.run(
        [str(binary), "--physical-config", str(path)],
        capture_output=True,
        text=True,
        timeout=3,
    )


@pytest.mark.parametrize("side", [0, 1])
@pytest.mark.parametrize("pose", [0, 1])
def test_native_pose_uses_only_selected_side_and_configured_values(
    native, tmp_path, side, pose
):
    config, _ = config_file(tmp_path)
    output = subprocess.run(
        [str(native), str(config), "pose", str(side), str(pose)],
        capture_output=True,
        text=True,
        check=True,
        timeout=3,
    )
    assert output.stdout.splitlines() == [
        f"CHIP /sys/class/pwm/pwmchip{71 + side}",
        f"CHANNEL pwm{8 + side}",
        "WRITE duty_cycle 0",
        "WRITE period 100",
        "WRITE polarity inversed",
        f"WRITE duty_cycle {20 if pose else 10}",
        "WRITE enable 1",
    ]


@pytest.mark.parametrize(
    "mode",
    [
        "blocked",
        "active",
        "range",
        "export",
        "short",
        "close-error",
        "stop-unverified",
        "stop-two",
        "journal-pose",
        "journal-config",
        "signal",
        *[f"fail-{i}" for i in range(1, 6)],
    ],
)
def test_native_gates_failures_and_stop_never_claim_position(native, tmp_path, mode):
    config, _ = config_file(tmp_path)
    output = subprocess.run(
        [str(native), str(config), mode, "0", "1"],
        capture_output=True,
        text=True,
        check=True,
        timeout=3,
    )
    if mode == "blocked":
        assert output.stdout == ""
    elif mode in {"active", "range"}:
        assert "WRITE" not in output.stdout
    elif mode == "export":
        assert "WRITE export 8" in output.stdout
    elif mode.startswith("fail-") or mode in {"short", "close-error", "signal"}:
        assert output.stdout.endswith("WRITE enable 0\n")
        assert "WRITE duty_cycle 10" not in output.stdout  # No corrective close.


def test_json_configuration_complete_or_missing_still_cannot_commission(
    binaries, tmp_path
):
    path, data = config_file(tmp_path)
    output = check(binaries["physical"], path)
    assert output.returncode == 0
    diagnostic = json.loads(output.stdout)
    assert {
        key: diagnostic[key]
        for key in (
            "protocol",
            "configuration",
            "execution_ready",
            "completion_provider",
            "stop_policy",
        )
    } == {
        "protocol": "bingo-pwm-config-v1",
        "configuration": "DECLARED",
        "execution_ready": False,
        "completion_provider": False,
        "stop_policy": False,
    }
    assert diagnostic["mapping"]["right"]["pwm_channel"] == 8
    assert diagnostic["mapping"]["left"]["pwm_channel"] == 9
    assert diagnostic["cycle_plan"] == []
    request = command(operation="CYCLE_LOWER_HATCH")
    output = physical(
        binaries["physical"], tmp_path / "c.db", frame(request), "--config", str(path)
    )
    assert output.returncode == 0 and output.stderr == ""
    assert "REJECTED UNAVAILABLE" in output.stdout and "ACCEPTED" not in output.stdout
    assert list(tmp_path.glob("*.lock")) == [
        tmp_path / "c.db.lock"
    ]  # Only journal lock, no device access.
    with sqlite3.connect(tmp_path / "c.db") as conn:
        assert conn.execute("PRAGMA user_version").fetchone()[0] == 3
        assert (
            json.loads(conn.execute("SELECT configuration FROM orders").fetchone()[0])
            == data
        )
    data["physical"] = {}
    path.write_text(json.dumps(data))
    assert (
        json.loads(check(binaries["physical"], path).stdout)["configuration"]
        == "INCOMPLETE"
    )
    # An ID cannot be reinterpreted using different physical configuration bytes.
    output = physical(
        binaries["physical"], tmp_path / "c.db", frame(request), "--config", str(path)
    )
    assert "ID_CONFLICT" in output.stdout


@pytest.mark.parametrize(
    "case",
    [
        "duplicate",
        "unknown",
        "boolean",
        "float",
        "negative",
        "period",
        "pulse",
        "polarity",
        "shared",
        "profile",
        "nul",
        "nested",
        "oversize",
        "malformed",
        "journal",
    ],
)
def test_c_rejects_invalid_configuration_before_journal(binaries, tmp_path, case):
    path, data = config_file(tmp_path)
    if case == "unknown":
        data["enable_physical"] = True
    elif case == "boolean":
        data["physical"]["right"]["pwm_chip"] = True
    elif case == "float":
        data["physical"]["period_ns"] = 100.0
    elif case == "negative":
        data["physical"]["left"]["pwm_channel"] = -1
    elif case == "period":
        data["physical"]["period_ns"] = 0
    elif case == "pulse":
        data["physical"]["right"]["open_pulse_ns"] = 100
    elif case == "polarity":
        data["physical"]["polarity"] = "guessed"
    elif case == "shared":
        data["physical"]["left"] = data["physical"]["right"]
    elif case == "profile":
        data["profile"] = "legacy-v1"
    elif case == "nul":
        data["physical"]["mapping_reference"] = "a\x00b"
    elif case == "nested":
        data["physical"]["right"] = []
    elif case == "journal":
        data["journal"] = "/different.db"
    path.write_text(json.dumps(data))
    if case == "duplicate":
        path.write_text(
            path.read_text().replace('"pwm_chip": 71', '"pwm_chip": 70, "pwm_chip": 71')
        )
    elif case == "oversize":
        path.write_text(" " * 16385)
    elif case == "malformed":
        path.write_text("{")
    output = physical(
        binaries["physical"], tmp_path / "c.db", "", "--config", str(path)
    )
    assert output.returncode == 2 and "INVALID_PWM_CONFIGURATION" in output.stderr
    assert not (tmp_path / "c.db").exists() and not (tmp_path / "c.db.lock").exists()


def test_unproven_intent_recovers_as_unknown_and_blocks_new_ids(binaries, tmp_path):
    path = tmp_path / "c.db"
    request = command(operation="CYCLE_LOWER_HATCH")
    assert physical(binaries["physical"], path).returncode == 0
    # Seed a durable intent at the crash boundary; NO driver invocation occurs.
    with sqlite3.connect(path) as conn:
        conn.execute(
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
                "",
            ),
        )
    output = physical(
        binaries["physical"],
        path,
        f"V1 GET {request.mechanical_command_id}\n"
        + frame(request)
        + frame(command(uuid4(), "CYCLE_LOWER_HATCH")),
    )
    assert output.returncode == 0 and output.stderr == ""
    assert "FAILED UNKNOWN EXECUTION_ERROR PHYSICAL" in output.stdout
    assert "V1 ERROR DUPLICATE" in output.stdout
    assert "REJECTED UNAVAILABLE CONTROLLER_BUSY UNAVAILABLE" in output.stdout
    with sqlite3.connect(path) as conn:
        assert conn.execute(
            "SELECT state,result FROM orders WHERE source='PHYSICAL'"
        ).fetchall() == [("FAILED", "UNKNOWN")]
        with pytest.raises(sqlite3.IntegrityError):
            conn.execute("UPDATE orders SET configuration='changed'")


def test_physical_v2_migration_retains_ids_and_rejections(binaries, tmp_path):
    path = tmp_path / "old.db"
    request = command(operation="CONFIRM_INITIAL_STATE")
    with sqlite3.connect(path) as conn:
        conn.executescript("""
          CREATE TABLE orders(id TEXT PRIMARY KEY,event TEXT,operation TEXT,timeout TEXT,
          state TEXT,result TEXT,error TEXT,profile TEXT);
          CREATE TRIGGER order_identity BEFORE UPDATE OF id,event,operation,timeout,profile ON orders
          BEGIN SELECT RAISE(ABORT,'Immutable order identity'); END;
          CREATE TRIGGER order_retention BEFORE DELETE ON orders
          BEGIN SELECT RAISE(ABORT,'Retained order identity'); END;
          PRAGMA application_id=1112098640; PRAGMA user_version=2;
        """)
        conn.execute(
            "INSERT INTO orders(rowid,id,event,operation,timeout,state,result,error,profile) VALUES(37,?,?,?,?,?,?,?,?)",
            (
                str(request.mechanical_command_id),
                str(request.event_id),
                request.operation,
                "10",
                "REJECTED",
                "UNAVAILABLE",
                "CONTROLLER_UNAVAILABLE",
                "doorless-v1",
            ),
        )
    output = physical(binaries["physical"], path, frame(request))
    assert (
        output.returncode == 0 and "DUPLICATE" in output.stdout and output.stderr == ""
    )
    with sqlite3.connect(path) as conn:
        assert conn.execute(
            "SELECT rowid,id,source,configuration FROM orders"
        ).fetchone() == (37, str(request.mechanical_command_id), "UNAVAILABLE", "")


def test_sigterm_of_blocked_receiver_has_no_corrective_motion(binaries, tmp_path):
    process = subprocess.Popen(
        [
            str(binaries["physical"]),
            "--ipc-physical",
            str(tmp_path / "c.db"),
            "--profile",
            "doorless-v1",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        assert b"PHYSICAL_BLOCKED" in process.stdout.readline()
        process.send_signal(signal.SIGTERM)
        output, error = process.communicate(timeout=3)
        assert process.returncode == 0 and output == error == b""
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
