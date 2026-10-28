"""Smoke Docker isolado. Cria e remove somente projetos/volumes UUID deste teste."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from uuid import uuid4

DEPLOY = Path(__file__).resolve().parents[1]
SERVICE = "totem-edge-simulation"
PREFIX = "bingo-simulation-test-"
DATABASE = "/var/lib/bingo-simulation/simulation.sqlite3"

PROBE = """
import json, os, sqlite3
with sqlite3.connect('file:' + os.environ['BINGO_SQLITE_PATH'] + '?mode=ro', uri=True) as c:
    print(json.dumps({
      'commands': c.execute('SELECT mechanical_command_id,event_id,phase,result,source,version FROM mechanical_commands ORDER BY created_at').fetchall(),
      'history_count': c.execute('SELECT count(*) FROM mechanical_history').fetchone()[0],
      'cycles': c.execute('SELECT event_id,state,physical_confirmed,payload,receipt,central_scope FROM cycles ORDER BY created_at').fetchall(),
      'schema': c.execute('PRAGMA user_version').fetchone()[0]
    }))
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    project = PREFIX + uuid4().hex[:12]
    projects = [project]
    output = DEPLOY / ".validation" / project
    output.mkdir(parents=True)
    env = dict(os.environ)
    # Iscas de teste: Compose precisa ignorar o ambiente operacional do shell.
    env.update(
        BINGO_SUPABASE_URL="https://must-not-be-forwarded.invalid",
        BINGO_MACHINE_API_KEY="host-credential-fixture",
        AWS_PROFILE="host-profile-fixture",
        BINGO_SQLITE_PATH="/var/lib/bingo/totem.sqlite3",
        BINGO_SIMULATION_CONTEXT="production",
    )
    report = {"project": project, "checks": []}

    def run(command, *, check=True):
        result = subprocess.run(
            command,
            cwd=DEPLOY,
            env=env,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=180,
        )
        if check and result.returncode:
            raise RuntimeError(
                f"Command failed ({result.returncode}): {result.stdout}\n{result.stderr}"
            )
        return result

    def compose(*arguments, name=project, check=True):
        assert name in projects and name.startswith(PREFIX)
        return run(
            [
                "docker",
                "compose",
                "--project-name",
                name,
                "--env-file",
                "simulation.env",
                "-f",
                "compose.simulation.yaml",
                *arguments,
            ],
            check=check,
        )

    def parsed(result):
        return json.loads(
            next(
                line
                for line in reversed(result.stdout.splitlines())
                if line.startswith("{")
            )
        )

    def harness(*arguments, extra_env=None, name=project, check=True):
        options = []
        for key, value in (extra_env or {}).items():
            options.extend(["-e", f"{key}={value}"])
        return compose(
            "run",
            "--rm",
            "--no-deps",
            *options,
            SERVICE,
            "python",
            "-m",
            "app.simulation_harness",
            *arguments,
            name=name,
            check=check,
        )

    def read_database(*, running=True, name=project):
        prefix = ["exec", "-T"] if running else ["run", "--rm", "--no-deps"]
        return parsed(compose(*prefix, SERVICE, "python", "-c", PROBE, name=name))

    def assert_no_economy(snapshot):
        assert snapshot["schema"] == 2
        assert all(row[4] == "SIMULATED" for row in snapshot["commands"])
        assert all(row[2:] == [0, None, None, None] for row in snapshot["cycles"])

    def check(name):
        report["checks"].append(name)
        print("PASS:", name, flush=True)

    try:
        config = json.loads(compose("config", "--format", "json").stdout)
        service = config["services"][SERVICE]
        assert set(config["services"]) == {SERVICE}
        assert service["build"]["target"] == "simulation"
        assert service["environment"]["BINGO_SIMULATION_CONTEXT"] == "development"
        assert service["environment"]["BINGO_SQLITE_PATH"] == DATABASE
        assert service["environment"]["BINGO_MACHINE_API_KEY"] == ""
        assert service["environment"]["BINGO_SUPABASE_URL"] == ""
        assert "AWS_PROFILE" not in service["environment"]
        assert all(network["internal"] for network in config["networks"].values())
        assert service["volumes"][0]["target"] == "/var/lib/bingo-simulation"
        assert service["volumes"][0]["source"] == "simulation-data"
        assert not service.get("devices") and not service.get("privileged")
        assert not service.get("ports")
        check(
            "Compose literals ignore host credentials; distinct volume/path; internal network; no devices"
        )
        if not args.skip_build:
            compose("build")
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")

        def http(path):
            code = "import json,sys; from urllib.request import ProxyHandler,build_opener; print(build_opener(ProxyHandler({})).open('http://127.0.0.1:8000'+sys.argv[1], timeout=3).read().decode())"
            return parsed(compose("exec", "-T", SERVICE, "python", "-c", code, path))

        def wait_healthy():
            for _ in range(90):
                state = compose("ps", "--format", "json").stdout
                records = [
                    json.loads(line)
                    for line in state.splitlines()
                    if line.startswith("{")
                ]
                if records and records[0].get("Health") == "healthy":
                    assert http("/health") == {"status": "ok"}
                    return
                time.sleep(0.5)
            raise AssertionError("Simulation did not become healthy")

        assert http("/health") == {"status": "ok"}
        status = http("/local/status")
        assert status["status"] == "OFFLINE" and status["can_start_deposit"] is False
        configured = parsed(
            compose(
                "exec",
                "-T",
                SERVICE,
                "python",
                "-m",
                "app.simulation_harness",
                "config",
            )
        )
        assert (
            configured["controller"] == "SimulatedController"
            and configured["central"] == "BLOCKED"
        )
        identifier = compose("ps", "-q", SERVICE).stdout.strip()
        assert (
            run(
                [
                    "docker",
                    "inspect",
                    "--format",
                    "{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Privileged}}",
                    identifier,
                ]
            ).stdout.strip()
            == "10001:10001 true false"
        )
        routes = compose(
            "exec",
            "-T",
            SERVICE,
            "python",
            "-c",
            "from pathlib import Path; r=Path('/proc/net/route').read_text().splitlines()[1:]; assert not any(x.split()[1]=='00000000' for x in r); print('no default route')",
        )
        assert "no default route" in routes.stdout
        check(
            "FastAPI healthy; simulator active; OFFLINE/false; UID 10001; readonly; no external default route"
        )
        compose("stop")
        command_id = str(uuid4())
        plans = json.dumps({"OPEN_INSERTION_DOOR": {"duration_seconds": 0.05}})
        first = parsed(
            harness(
                "run",
                "OPEN_INSERTION_DOOR",
                "--id",
                command_id,
                extra_env={"BINGO_SIMULATION_PLANS": plans},
            )
        )
        assert first["accepted"]["phase"] == "ACCEPTED"
        assert (
            first["result"]["phase"] == "COMPLETED"
            and first["result"]["source"] == "SIMULATED"
        )
        assert first["elapsed_seconds"] >= 0.04
        shown = parsed(harness("show", command_id))
        assert [item["phase"] for item in shown["history"]] == [
            "INTENT",
            "DISPATCHING",
            "ACCEPTED",
            "COMPLETED",
        ]
        assert parsed(harness("replay", command_id))["result"] == first["result"]
        divergent = harness(
            "run", "CLOSE_INSERTION_DOOR", "--id", command_id, check=False
        )
        assert (
            divergent.returncode != 0
            and parsed(divergent)["error"]["code"] == "MECHANICAL_COMMAND_ID_CONFLICT"
        )
        check(
            "Internal harness: accepted before timed completion; durable journal; idempotent replay; conflict"
        )
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")
        before = read_database()
        assert_no_economy(before)
        assert before["history_count"] == 4 and len(before["commands"]) == 1
        compose("restart")
        wait_healthy()
        assert read_database() == before
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
        )
        assert compose("ps", "-q", SERVICE).stdout.strip() != identifier
        assert read_database() == before
        check(
            "SQLite/journal unchanged after restart and force-recreate; no physical/economic confirmation"
        )
        compose("stop")
        for values in (
            {"BINGO_SIMULATION_CONTEXT": "production"},
            {"BINGO_MACHINE_API_KEY": "unsafe-fixture"},
            {"BINGO_SQLITE_PATH": "/var/lib/bingo/totem.sqlite3"},
        ):
            negative = harness("config", extra_env=values, check=False)
            assert (
                negative.returncode != 0
                and parsed(negative)["error"]["code"]
                == "SIMULATION_UNSAFE_CONFIGURATION"
            )
        assert read_database(running=False) == before
        check(
            "Unsafe context, credentials and operational path rejected without modifying data"
        )
        for outcome, phase in (("FAILURE", "FAILED"), ("TIMEOUT", "TIMED_OUT")):
            name = project + "-" + outcome.lower()
            projects.append(name)
            plans = json.dumps(
                {"OPEN_INSERTION_DOOR": {"duration_seconds": 0.0, "outcome": outcome}}
            )
            result = parsed(
                harness(
                    "run",
                    "OPEN_INSERTION_DOOR",
                    "--timeout",
                    "0.05",
                    extra_env={"BINGO_SIMULATION_PLANS": plans},
                    name=name,
                )
            )
            assert result["result"]["phase"] == phase
            assert_no_economy(read_database(running=False, name=name))
        check("Failure and timeout on independent simulation volumes; no economic data")
        interrupted_id = str(uuid4())
        interrupted = parsed(
            harness(
                "run",
                "CYCLE_LOWER_HATCH",
                "--id",
                interrupted_id,
                "--interrupt-after-accept",
            )
        )
        assert interrupted["interrupted_after_acceptance"]["phase"] == "ACCEPTED"
        accepted = read_database(running=False)
        assert accepted["commands"][-1][2] == "ACCEPTED"
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")
        recovered = read_database()
        assert_no_economy(recovered)
        assert recovered["commands"][-1][2:4] == ["INDETERMINATE", "UNKNOWN"]
        assert recovered["cycles"][-1][1] == "INDETERMINATE"
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
        )
        assert read_database() == recovered
        compose("stop")
        assert (
            parsed(harness("replay", interrupted_id))["result"]["phase"]
            == "INDETERMINATE"
        )
        assert read_database(running=False) == recovered
        check(
            "Abrupt interruption recovered as UNKNOWN; slot blocked; no redispatch across recreate/replay"
        )
        report["ok"] = True
    except Exception as error:
        report.update(ok=False, error=str(error))
        raise
    finally:
        for name in reversed(projects):
            compose("down", "--volumes", "--remove-orphans", name=name, check=False)
        (output / "report.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        print("Report:", output / "report.json", flush=True)


if __name__ == "__main__":
    main()
