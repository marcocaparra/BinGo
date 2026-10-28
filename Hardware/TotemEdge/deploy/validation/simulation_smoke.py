"""Smoke Docker isolado. Cria e remove somente projetos/volumes UUID deste teste."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener
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
    override_files = {}
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
                *(["-f", str(override_files[name])] if name in override_files else []),
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
        assert snapshot["schema"] == 3
        assert all(row[4] == "SIMULATED" for row in snapshot["commands"])
        assert all(row[2:] == [0, None, None, None] for row in snapshot["cycles"])

    def check(name):
        report["checks"].append(name)
        print("PASS:", name, flush=True)

    try:
        config = json.loads(compose("config", "--format", "json").stdout)
        service = config["services"][SERVICE]
        assert set(config["services"]) == {SERVICE, "simulation-http"}
        assert service["build"]["target"] == "simulation"
        assert service["environment"]["BINGO_SIMULATION_CONTEXT"] == "development"
        assert service["environment"]["BINGO_SQLITE_PATH"] == DATABASE
        assert service["environment"]["BINGO_MACHINE_API_KEY"] == ""
        assert service["environment"]["BINGO_SUPABASE_URL"] == ""
        assert "AWS_PROFILE" not in service["environment"]
        assert config["networks"]["simulation-private"]["internal"]
        assert set(service["networks"]) == {"simulation-private"}
        ingress = config["services"]["simulation-http"]
        assert ingress["ports"][0]["host_ip"] == "127.0.0.1"
        assert not ingress.get("volumes")
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
                if records and all(
                    record.get("Health") == "healthy" for record in records
                ):
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
        # Volume novo para a máquina integrada. O harness 3A anterior é preservado
        # como legado e nunca é adotado silenciosamente pelas novas rotas.
        http_project = project + "-http"
        projects.append(http_project)
        override = output / "http.override.json"
        plans = {
            operation: {"duration_seconds": 0.05}
            for operation in (
                "OPEN_INSERTION_DOOR",
                "CLOSE_INSERTION_DOOR",
                "CYCLE_LOWER_HATCH",
                "CONFIRM_INITIAL_STATE",
            )
        }

        def write_plans():
            override.write_text(
                json.dumps(
                    {
                        "services": {
                            SERVICE: {
                                "environment": {
                                    "BINGO_SIMULATION_PLANS": json.dumps(plans)
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )

        write_plans()
        override_files[http_project] = override
        compose(
            "up",
            "-d",
            "--no-build",
            "--wait",
            "--wait-timeout",
            "90",
            name=http_project,
        )
        origin = "http://127.0.0.1:" + str(ingress["ports"][0]["published"])
        opener = build_opener(ProxyHandler({}))
        base = "/local/simulation/sessions"

        def request(path, body=None, *, headers=None):
            fields = {"X-Totem-Request": "1", "Origin": origin}
            if body is not None:
                fields["Content-Type"] = "application/json"
            fields.update(headers or {})
            req = Request(
                origin + path,
                data=json.dumps(body).encode() if body is not None else None,
                headers=fields,
            )
            try:
                with opener.open(req, timeout=5) as response:
                    return response.status, json.load(response)
            except HTTPError as error:
                return error.code, json.load(error)

        def stable(event, state):
            for _ in range(100):
                status, body = request(base + "/" + event)
                if status == 200 and body["session"]["state"] == state:
                    return body
                time.sleep(0.05)
            raise AssertionError("Persisted state not reached: " + state)

        assert request("/local/status")[1]["can_start_deposit"] is False
        for headers in (
            {"Origin": "https://foreign.invalid"},
            {"Host": "foreign.invalid"},
            {"X-Totem-Request": ""},
        ):
            assert (
                request(base, {"command_id": str(uuid4())}, headers=headers)[0] == 403
            )
        key = str(uuid4())
        status, snapshot = request(base, {"command_id": key})
        assert status == 200 and snapshot["source"] == "SIMULATED"
        event = snapshot["session"]["event_id"]
        assert request(base, {"command_id": key})[1] == snapshot
        assert request(f"{base}/{event}/safety", {"has_risk": False})[0] == 200
        identifiers = []
        for action, target in (
            ("open", "DOOR_OPEN"),
            ("close", "DOOR_CLOSED"),
            ("hatch", "HATCH_IN_PROGRESS"),
            ("confirm-initial", "COMPLETED"),
        ):
            if action == "hatch":
                assert (
                    request(
                        f"{base}/{event}/hatch", {"mechanical_command_id": str(uuid4())}
                    )[0]
                    == 409
                )
                assert request(f"{base}/{event}/review-fixture", {})[0] == 200
            identifier = str(uuid4())
            identifiers.append(identifier)
            body = {"mechanical_command_id": identifier}
            if action == "close":
                body["hand_removed"] = True
            status, accepted = request(f"{base}/{event}/{action}", body)
            assert status == 202
            assert accepted["commands"][-1]["phase"] == "ACCEPTED"
            final = stable(event, target)
            # Alçapão mantém estado enquanto aguarda confirmação inicial.
            for _ in range(100):
                if final["commands"][-1]["phase"] == "COMPLETED":
                    break
                time.sleep(0.05)
                final = request(f"{base}/{event}")[1]
            assert final["commands"][-1]["phase"] == "COMPLETED"
            assert request(f"{base}/{event}/{action}", body)[1] == final
        assert request(base + "/active")[1] == {"snapshot": None}
        assert (
            request(f"{base}/{event}/commands/{identifiers[0]}")[1]["command"]["phase"]
            == "COMPLETED"
        )
        assert final["session"]["receipt"] is None
        before_http = read_database(name=http_project)
        assert_no_economy(before_http)
        assert before_http["history_count"] == 16
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
            name=http_project,
        )
        assert request(f"{base}/{event}")[1] == final
        assert read_database(name=http_project) == before_http
        # Tempo longo permite matar o backend antes da conclusão lógica.
        plans["OPEN_INSERTION_DOOR"]["duration_seconds"] = 60.0
        write_plans()
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
            name=http_project,
        )
        second = request(base, {"command_id": str(uuid4())})[1]["session"]["event_id"]
        request(f"{base}/{second}/safety", {"has_risk": False})
        identifier = str(uuid4())
        body = {"mechanical_command_id": identifier, "timeout_seconds": 120.0}
        assert (
            request(f"{base}/{second}/open", body)[1]["session"]["state"] == "OPENING"
        )
        compose("kill", "--signal", "SIGKILL", SERVICE, name=http_project)
        assert (
            read_database(running=False, name=http_project)["commands"][-1][2]
            == "ACCEPTED"
        )
        compose(
            "up",
            "-d",
            "--no-build",
            "--wait",
            "--wait-timeout",
            "90",
            name=http_project,
        )
        uncertain = stable(second, "INDETERMINATE")
        assert uncertain["allowed_actions"] == []
        assert request(f"{base}/{second}/open", body)[1] == uncertain
        assert request(f"{base}/{second}/cancel", {})[0] == 409
        assert_no_economy(read_database(name=http_project))
        check(
            "Host loopback HTTP: protected actions, full state machine, atomic journal, reload/recreate and SIGKILL recovery without redispatch"
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
