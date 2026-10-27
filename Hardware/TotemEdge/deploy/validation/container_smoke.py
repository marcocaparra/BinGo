"""Isolated Docker/SQLite smoke. Never loads real credentials or deletes volumes."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import time
from urllib.parse import quote
from urllib.request import ProxyHandler, build_opener
from uuid import uuid4

DEPLOY = Path(__file__).resolve().parents[1]
EDGE = DEPLOY.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", default="bingo-totem-edge:v1")
    parser.add_argument(
        "--platform", default="linux/amd64", choices=("linux/amd64", "linux/arm64")
    )
    parser.add_argument(
        "--browser",
        action="store_true",
        help="Run optional host-side Node/Playwright smoke",
    )
    parser.add_argument(
        "--emulated",
        action="store_true",
        help="ARM64-on-x86 tests only: allow slower QEMU startup/healthcheck",
    )
    args = parser.parse_args()
    if args.emulated and args.platform != "linux/arm64":
        parser.error("--emulated requires --platform linux/arm64")
    wait_timeout = 600 if args.emulated else 90
    project = "bingo-container-test-" + uuid4().hex[:12]
    output = DEPLOY / ".validation" / project
    output.mkdir(parents=True)
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("BINGO_", "COMPOSE_", "AWS_", "GEMINI_"))
    }
    # Passing the example alone is insufficient: shell environment wins in Compose.
    env.update(
        {
            "BINGO_SUPABASE_URL": "",
            "BINGO_MACHINE_ID": "",
            "BINGO_MACHINE_API_KEY": "",
            "BINGO_BACKEND_TIMEOUT_SECONDS": "5",
            "BINGO_SQLITE_PATH": "/var/lib/bingo/controlled/totem.sqlite3",
        }
    )
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        env["BINGO_HTTP_PORT"] = str(reservation.getsockname()[1])
    origin = "http://127.0.0.1:" + env["BINGO_HTTP_PORT"]
    override = output / "compose.override.json"
    service_override = {"image": args.image, "platform": args.platform}
    if args.emulated:
        # QEMU Python startup exceeded both 3s and 30s probe budgets on this host.
        # This override affects test infrastructure only, never readiness/business.
        service_override["healthcheck"] = {"timeout": "90s", "start_period": "180s"}
    override.write_text(
        json.dumps({"services": {"totem-edge": service_override}}), encoding="utf-8"
    )
    base = [
        "docker",
        "compose",
        "--project-name",
        project,
        "--env-file",
        str(DEPLOY / ".env.example"),
        "-f",
        str(DEPLOY / "compose.yaml"),
        "-f",
        str(override),
    ]

    def run(command, *, input_text=None, check=True):
        result = subprocess.run(
            command,
            cwd=DEPLOY,
            env=env,
            input=input_text,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=wait_timeout + 60,
        )
        if check and result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout.strip()

    def compose(*arguments):
        return run([*base, *arguments])

    def python_in_container(code):
        return run([*base, "exec", "-T", "totem-edge", "python", "-B", "-c", code])

    def get(path):
        with build_opener(ProxyHandler({})).open(
            origin + quote(path, safe="/?=&"), timeout=8
        ) as response:
            assert response.status == 200
            return response.read()

    report = {
        "project": project,
        "platform": args.platform,
        "image": args.image,
        "emulation_health_override": args.emulated,
        "event_id": str(uuid4()),
        "checks": [],
    }
    try:
        compose("config", "--quiet")
        print(f"Starting isolated project {project}", flush=True)
        began = time.monotonic()
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", str(wait_timeout))
        report["start_to_healthy_seconds"] = round(time.monotonic() - began, 2)
        container = compose("ps", "-q", "totem-edge")
        info = json.loads(run(["docker", "inspect", container]))[0]
        report["volume"] = next(
            mount["Name"]
            for mount in info["Mounts"]
            if mount["Destination"] == "/var/lib/bingo"
        )
        assert info["Config"]["User"] == "10001:10001"
        assert info["HostConfig"]["ReadonlyRootfs"] is True
        assert info["HostConfig"]["Privileged"] is False
        assert not info["HostConfig"]["Devices"]
        assert info["NetworkSettings"]["Ports"]["8000/tcp"][0]["HostIp"] == "127.0.0.1"
        assert info["State"]["Health"]["Status"] == "healthy"
        assert json.loads(get("/health")) == {"status": "ok"}
        status = json.loads(get("/local/status"))
        assert status["status"] == "OFFLINE" and status["can_start_deposit"] is False
        assert json.loads(get("/local/sessions/active"))["session"] is None
        files = [
            EDGE / "frontend" / name
            for name in (
                "index.html",
                "styles.css",
                "script.js",
                "local_api.js",
                "operational.js",
            )
        ]
        files += sorted((EDGE / "frontend" / "assets").rglob("*"))
        for file in files:
            if file.is_file():
                relative = file.relative_to(EDGE / "frontend").as_posix()
                assert (
                    hashlib.sha256(
                        get("/" if relative == "index.html" else "/" + relative)
                    ).digest()
                    == hashlib.sha256(file.read_bytes()).digest()
                ), relative
        assert get("/?runtime=demo") == (EDGE / "frontend" / "index.html").read_bytes()
        report["checks"].append(
            "health/status, non-root/read-only/loopback, 50 static files byte-identical, demo entry"
        )
        if args.browser:
            env["BINGO_TEST_ORIGIN"] = origin
            # Explicitly preserve development browser overrides; never business settings.
            print(
                run(["node", str(DEPLOY / "validation" / "browser_smoke.cjs")]),
                flush=True,
            )
            report["checks"].append(
                "browser: safe real mode, isolated demo, zero loading errors"
            )

        # Software fixture in a NEW test volume, not a movement or real deposit.
        payload = {
            "event_id": report["event_id"],
            "class_id": str(uuid4()),
            "student_id": None,
            "is_valid": True,
            "detected_type": "controlled-fixture",
            "waste_category_code": "CABLE_WIRE",
            "category_source": "AI_CONFIRMED",
        }
        seed = f"""
import json, os, sqlite3
from pathlib import Path
payload = json.loads({json.dumps(json.dumps(payload))})
with sqlite3.connect(os.environ['BINGO_SQLITE_PATH']) as conn:
    conn.execute('INSERT INTO cycles(event_id,command_id,state,mode,class_id,class_name,physical_confirmed,payload,central_scope,created_at,updated_at,active_slot) VALUES(?,?,?,?,?,?,?,?,?,?,?,1)',
        (payload['event_id'], {str(uuid4())!r}, 'REGISTRATION_PENDING', 'class_only', payload['class_id'], 'Controlled fixture', 1, json.dumps(payload), 'container-test-only', '2026-10-08T12:00:00Z', '2026-10-08T12:00:00Z'))
    conn.execute('INSERT INTO transitions(event_id,to_state,code,at) VALUES(?,?,?,?)', (payload['event_id'], 'REGISTRATION_PENDING', 'CONTROLLED_TEST_FIXTURE', '2026-10-08T12:00:00Z'))
files = sorted(p.name for p in Path(os.environ['BINGO_SQLITE_PATH']).parent.iterdir())
assert all('totem.sqlite3' + suffix in files for suffix in ('', '-wal', '-shm', '.lock'))
print(json.dumps(files))
"""
        report["sqlite_files_during_fixture"] = json.loads(python_in_container(seed))

        def preserved():
            session = json.loads(get("/local/sessions/active"))["session"]
            assert (
                session["event_id"] == report["event_id"]
                and session["state"] == "REGISTRATION_PENDING"
            )
            assert session["receipt"] is None
            raw = python_in_container(
                "import os, sqlite3, json; c=sqlite3.connect(os.environ['BINGO_SQLITE_PATH']); r=c.execute('SELECT payload FROM cycles').fetchone(); print(json.dumps({'count':c.execute('SELECT count(*) FROM cycles').fetchone()[0], 'journal_count':c.execute('SELECT count(*) FROM transitions').fetchone()[0], 'payload':json.loads(r[0]), 'integrity':c.execute('PRAGMA integrity_check').fetchone()[0]}))"
            )
            data = json.loads(raw)
            assert (
                data["count"] == 1
                and data["journal_count"] == 1
                and data["payload"] == payload
                and data["integrity"] == "ok"
            )

        def wait_ready():
            deadline = time.monotonic() + wait_timeout
            while time.monotonic() < deadline:
                try:
                    if json.loads(get("/health")) == {"status": "ok"}:
                        return
                except OSError:
                    pass
                time.sleep(0.2)
            raise RuntimeError("Process did not become ready")

        preserved()
        print(
            "Checking restart and forced recreation with the same persistent volume",
            flush=True,
        )
        compose("restart", "totem-edge")
        wait_ready()
        preserved()
        report["restart_logs"] = compose("logs", "--no-color", "--tail", "30")
        assert "Application shutdown complete" in report["restart_logs"]
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            str(wait_timeout),
        )
        preserved()
        new_container = compose("ps", "-q", "totem-edge")
        assert new_container != container
        new_info = json.loads(run(["docker", "inspect", new_container]))[0]
        assert (
            next(
                m["Name"]
                for m in new_info["Mounts"]
                if m["Destination"] == "/var/lib/bingo"
            )
            == report["volume"]
        )
        report["checks"].append(
            "restart/recreate: same event_id, seven-field payload, pending state, journal and integrity; no duplicate row"
        )
        report["runtime"] = json.loads(
            python_in_container(
                "import json, os, platform, importlib.metadata; from pathlib import Path; print(json.dumps({'python':platform.python_version(), 'machine':platform.machine(), 'uid':os.getuid(), 'dependencies':sorted((d.metadata['Name'], d.version) for d in importlib.metadata.distributions(path=['/opt/venv/lib/python3.12/site-packages'])), 'data_files':sorted(p.name for p in Path(os.environ['BINGO_SQLITE_PATH']).parent.iterdir())}))"
            )
        )
        image_info = json.loads(run(["docker", "image", "inspect", args.image]))[0]
        report["image_size_bytes"] = image_info["Size"]
        report["image_architecture"] = image_info["Architecture"]
        report["image_storage_summary"] = run(["docker", "image", "ls", args.image])
        report["processes"] = run(
            ["docker", "top", new_container, "-eo", "pid,comm,args"]
        )
        report["idle_stats"] = []
        print("Collecting three idle samples (no browser active)", flush=True)
        for _ in range(3):
            time.sleep(5)
            report["idle_stats"].append(
                json.loads(
                    run(
                        [
                            "docker",
                            "stats",
                            "--no-stream",
                            "--format",
                            "{{json .}}",
                            new_container,
                        ]
                    )
                )
            )
        report["high_watermarks"] = json.loads(
            python_in_container(
                "import json; from pathlib import Path; p=Path('/sys/fs/cgroup/memory.peak'); print(json.dumps({'cgroup_memory_peak_bytes':int(p.read_text()) if p.exists() else None, 'pid1_memory': [line for line in Path('/proc/1/status').read_text().splitlines() if line.startswith(('VmRSS:', 'VmHWM:', 'Threads:'))]}))"
            )
        )
        report["logs"] = compose("logs", "--no-color", "--tail", "40")
        assert "Application startup complete" in report["logs"]
        report["recorded_at"] = datetime.now(timezone.utc).isoformat()
        (output / "report.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        print(json.dumps(report, indent=2), flush=True)
    except Exception as error:
        report["failure"] = str(error)
        report["logs"] = run([*base, "logs", "--no-color", "--tail", "80"], check=False)
        report["container_status"] = run(
            [*base, "ps", "--all", "--format", "json"], check=False
        )
        (output / "report.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )
        raise
    finally:
        # NEVER use down -v: the controlled data stays in this isolated volume.
        run([*base, "down", "--timeout", "30"], check=False)
        print(f"Test volume retained; report directory: {output}", flush=True)


if __name__ == "__main__":
    main()
