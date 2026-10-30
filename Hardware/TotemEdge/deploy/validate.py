"""Reproducible TotemEdge profiles. No hosted credentials or hardware by default."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, build_opener
from uuid import uuid4
import xml.etree.ElementTree as ET

DEPLOY = Path(__file__).resolve().parent
EDGE = DEPLOY.parent
BACKEND = EDGE / "backend"
FRONTEND = EDGE / "frontend"
INTEGRATION = (
    "test_dev_identity.py",
    "test_dev_integration.py",
    "test_mechanical_journal.py",
    "test_simulation_flow.py",
    "test_http_smoke.py",
    "test_sessions.py",
)
FAST = ("test_test_isolation.py", "test_routes.py", "test_central_business.py")


def safe_environment(source):
    prefixes = (
        "BINGO_",
        "SUPABASE_",
        "AWS_",
        "GEMINI_",
        "GOOGLE_",
        "AZURE_",
        "PYTEST_",
        "UV_",
        "PIP_",
    )
    omitted = {
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "PYTHONPATH",
        "PYTHONSTARTUP",
        "NODE_OPTIONS",
        "UV_ENV_FILE",
        "UV_PROJECT_ENVIRONMENT",
        "COMPOSE_FILE",
        "COMPOSE_PROJECT_NAME",
        "COMPOSE_ENV_FILES",
    }
    env = {
        key: value
        for key, value in source.items()
        if not key.upper().startswith(prefixes) and key.upper() not in omitted
    }
    env.update(
        PYTHONDONTWRITEBYTECODE="1",
        PYTHONIOENCODING="utf-8",
        UV_NO_ENV_FILE="1",
        UV_OFFLINE="1",
    )
    return env


def junit_counts(path):
    cases = list(ET.parse(path).getroot().iter("testcase"))
    if not cases:
        raise ValueError("Empty pytest collection")
    failed = sum(
        c.find("failure") is not None or c.find("error") is not None for c in cases
    )
    skipped = sum(c.find("skipped") is not None for c in cases)
    return {
        "passed": len(cases) - failed - skipped,
        "failed": failed,
        "skipped": skipped,
    }


def aggregate(groups):
    if any(g["status"] in ("failed", "interrupted") for g in groups):
        return 1
    if any(
        g["status"] in ("unavailable", "running")
        or g.get("tests", {}).get("skipped", 0)
        for g in groups
    ):
        return 2
    return 0


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def hosted_read_only(url, authorized, env):
    if not authorized or env.get("CI") or env.get("GITHUB_ACTIONS"):
        raise ValueError("HOSTED DEV requires --allow-hosted-dev outside CI")
    parsed = urlsplit(url)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in ("127.0.0.1", "localhost", "::1")
        or parsed.username
        or parsed.password
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Use the explicitly authorized local DEV broker ingress URL")
    opener = build_opener(ProxyHandler({}), NoRedirects())
    with opener.open(url.rstrip("/") + "/local/dev/health", timeout=10) as response:
        health = json.load(response)
    if not (
        health.get("central") == "AVAILABLE"
        and health.get("scope") == "SUPABASE_DEV_READ_ONLY"
        and health.get("mechanical_source") == "SIMULATED"
        and health.get("economic_registration") is False
    ):
        raise ValueError("DEV read-only health contract refused")
    with opener.open(url.rstrip("/") + "/local/dev/context", timeout=10) as response:
        context = json.load(response)
    if not all(key in context for key in ("machine", "school", "classes", "students")):
        raise ValueError("DEV context contract refused")
    # Do not return identities, credentials, PINs or response bodies to logs.
    return {"passed": 2, "failed": 0, "skipped": 0}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "profile", choices=("fast", "integration", "full", "hosted-dev")
    )
    parser.add_argument("--allow-hosted-dev", action="store_true")
    parser.add_argument("--url", default="http://127.0.0.1:8002")
    args = parser.parse_args(argv)
    if args.profile != "hosted-dev" and (
        args.allow_hosted_dev or args.url != parser.get_default("url")
    ):
        parser.error("Hosted options are exclusive to hosted-dev")
    output = DEPLOY / ".validation" / ("profiles-" + uuid4().hex[:12])
    output.mkdir(parents=True)
    report = {
        "profile": args.profile,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "hosted": args.profile == "hosted-dev",
        "groups": [],
    }
    env = safe_environment(os.environ)
    # Browser tool paths are explicit test tooling, never service configuration.
    for name in ("PLAYWRIGHT_MODULE", "BROWSER_EXECUTABLE"):
        if name in os.environ:
            env[name] = os.environ[name]

    def save():
        report["exit_code"] = aggregate(report["groups"])
        report["tests"] = {
            key: sum(g.get("tests", {}).get(key, 0) for g in report["groups"])
            for key in ("passed", "failed", "skipped")
        }
        (output / "report.json").write_text(
            json.dumps(report, indent=2), encoding="utf-8"
        )

    def run(name, command, cwd=DEPLOY, kind=None, timeout=900):
        group = {"name": name, "status": "running"}
        report["groups"].append(group)
        save()
        print(f"RUN {name}", flush=True)
        started = time.monotonic()
        existing = set((DEPLOY / ".validation").glob("bingo-*-test-*/report.json"))
        try:
            result = subprocess.run(
                command,
                cwd=cwd,
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
            )
            logs = result.stdout + result.stderr
            (output / (name + ".log")).write_text(logs, encoding="utf-8")
            group.update(
                status="passed" if result.returncode == 0 else "failed",
                returncode=result.returncode,
            )
            if kind == "pytest" and (output / "pytest.xml").exists():
                group["tests"] = junit_counts(output / "pytest.xml")
            elif kind == "node":
                counts = {
                    key: re.search(r"# " + label + r" (\d+)", logs)
                    for key, label in (
                        ("passed", "pass"),
                        ("failed", "fail"),
                        ("skipped", "skipped"),
                    )
                }
                if not all(counts.values()):
                    raise ValueError("Missing Node test counts")
                group["tests"] = {key: int(match[1]) for key, match in counts.items()}
            elif kind == "unittest":
                count = re.search(r"Ran (\d+) tests?", logs)
                if not count or int(count[1]) == 0:
                    raise ValueError("Missing unittest collection")
                skipped = re.search(r"skipped=(\d+)", logs)
                failures = re.search(r"failures=(\d+)", logs)
                errors = re.search(r"errors=(\d+)", logs)
                failed = sum(int(m[1]) for m in (failures, errors) if m)
                skip = int(skipped[1]) if skipped else 0
                group["tests"] = {
                    "passed": int(count[1]) - failed - skip,
                    "failed": failed,
                    "skipped": skip,
                }
            if (
                kind in ("node", "pytest")
                and group.get("tests", {}).get("passed", 0) == 0
            ):
                group["status"] = "failed"
            if result.returncode:
                print(f"  Details: {output / (name + '.log')}", flush=True)
            if name in ("dev_integration_smoke", "simulation_smoke"):
                evidence = (
                    set((DEPLOY / ".validation").glob("bingo-*-test-*/report.json"))
                    - existing
                )
                group["evidence"] = [str(path) for path in sorted(evidence)]
                for path in evidence:
                    smoke = json.loads(path.read_text(encoding="utf-8"))
                    group["checks_passed"] = len(smoke.get("checks", []))
                    if smoke.get("ok") is not True:
                        group["status"] = "failed"
            elif name in ("browser_smoke", "operational_smoke"):
                evidence = (
                    FRONTEND
                    / ".validation"
                    / (
                        "browser.json"
                        if name == "browser_smoke"
                        else "operational-browser.json"
                    )
                )
                if evidence.exists() and result.returncode == 0:
                    shutil.copyfile(evidence, output / evidence.name)
                    group["evidence"] = str(output / evidence.name)
        except FileNotFoundError:
            group.update(
                status="unavailable", reason="Required executable not installed"
            )
        except subprocess.TimeoutExpired:
            group.update(
                status="failed",
                reason="Group timeout; inspect owned resources before retry",
            )
        except KeyboardInterrupt:
            group.update(
                status="interrupted",
                reason="Interrupted; owned smoke projects may need cleanup",
            )
            raise
        except (ValueError, ET.ParseError) as error:
            group.update(status="failed", reason=str(error))
        finally:
            group["seconds"] = round(time.monotonic() - started, 2)
            save()
            print(f"{group['status'].upper()} {name}", flush=True)

    try:
        if args.profile == "hosted-dev":
            group = {"name": "hosted-read-only", "status": "failed"}
            report["groups"].append(group)
            try:
                group["tests"] = hosted_read_only(
                    args.url, args.allow_hosted_dev, os.environ
                )
                group["status"] = "passed"
            except Exception:
                group["reason"] = (
                    "Opt-in, local broker or authorized hosted DEV unavailable; no response body logged"
                )
        else:
            with tempfile.TemporaryDirectory(prefix="bingo-validation-") as temporary:
                env["BINGO_SQLITE_PATH"] = str(Path(temporary) / "collection.sqlite3")
                env["BINGO_TEST_PYTHON"] = str(
                    BACKEND
                    / (
                        ".venv/Scripts/python.exe"
                        if os.name == "nt"
                        else ".venv/bin/python"
                    )
                )
                # --offline disallows implicit dependency downloads; setup is explicit.
                selection = (
                    FAST
                    if args.profile == "fast"
                    else FAST + INTEGRATION
                    if args.profile == "integration"
                    else ()
                )
                run(
                    "backend",
                    [
                        "uv",
                        "run",
                        "--locked",
                        "--offline",
                        "--no-env-file",
                        "pytest",
                        "-q",
                        "--tb=short",
                        f"--basetemp={Path(temporary) / 'pytest'}",
                        f"--junitxml={output / 'pytest.xml'}",
                        *[f"tests/{name}" for name in selection],
                    ],
                    BACKEND,
                    "pytest",
                )
                run(
                    "runtime",
                    [
                        sys.executable,
                        "-B",
                        "-m",
                        "unittest",
                        "discover",
                        "-s",
                        "tests",
                        "-v",
                    ],
                    kind="unittest",
                )
                run(
                    "js-contracts",
                    [
                        "node",
                        "--test",
                        "--test-reporter=tap",
                        "validation/local_api.test.cjs",
                    ],
                    FRONTEND,
                    "node",
                )
                for name in ("script.js", "local_api.js", "operational.js"):
                    run("syntax-" + name, ["node", "--check", name], FRONTEND)
                run(
                    "format",
                    [
                        "uv",
                        "format",
                        "--version",
                        "0.15.22",
                        "--check",
                        "--",
                        "app",
                        "tests",
                        "../deploy/validate.py",
                        "../deploy/tests",
                        "../deploy/validation",
                        "../deploy/start.py",
                        "../deploy/start_simulation.py",
                        "../deploy/start_dev_integration.py",
                        "../deploy/healthcheck.py",
                    ],
                    BACKEND,
                )
                if args.profile == "full":
                    docker = shutil.which("docker")
                    available = (
                        docker
                        and subprocess.run(
                            [docker, "info", "--format", "{{.OSType}}"],
                            env=env,
                            capture_output=True,
                            timeout=20,
                        ).stdout.strip()
                        == b"linux"
                    )
                    for smoke in ("dev_integration_smoke", "simulation_smoke"):
                        if available:
                            run(
                                smoke,
                                [sys.executable, "-B", f"validation/{smoke}.py"],
                                timeout=1500,
                            )
                        else:
                            report["groups"].append(
                                {
                                    "name": smoke,
                                    "status": "unavailable",
                                    "reason": "Docker Linux engine required",
                                }
                            )
                    # Probe tooling without downloading a browser or packages.
                    probe = (
                        subprocess.run(
                            [
                                "node",
                                "-e",
                                "const {chromium,launchOptions}=require('./validation/browser_tools.cjs');const fs=require('node:fs');if(!fs.existsSync(launchOptions.executablePath||chromium.executablePath()))process.exit(2)",
                            ],
                            cwd=FRONTEND,
                            env=env,
                            capture_output=True,
                        )
                        if shutil.which("node")
                        else None
                    )
                    for smoke in ("browser_smoke", "operational_smoke"):
                        if probe and probe.returncode == 0:
                            run(smoke, ["node", f"validation/{smoke}.cjs"], FRONTEND)
                        else:
                            report["groups"].append(
                                {
                                    "name": smoke,
                                    "status": "unavailable",
                                    "reason": "Playwright module/browser missing; see TESTING.md",
                                }
                            )
            report["temporary_sqlite_removed"] = not Path(temporary).exists()
            report["groups"].append(
                {
                    "name": "frontend-3c2-e2e",
                    "status": "pending",
                    "reason": "3C.2.1/2/3 UI integration is not implemented",
                }
            )
    except KeyboardInterrupt:
        report["interrupted"] = True
        report["groups"].append({"name": "orchestrator", "status": "interrupted"})
    except Exception:
        report["groups"].append(
            {
                "name": "orchestrator",
                "status": "failed",
                "reason": "Infrastructure error; no external exception data logged",
            }
        )
    finally:
        save()
        print(
            json.dumps(
                {
                    "groups": [
                        {
                            "name": g["name"],
                            "status": g["status"],
                            "tests": g.get("tests"),
                        }
                        for g in report["groups"]
                    ],
                    "exit_code": report["exit_code"],
                    "report": str(output / "report.json"),
                },
                indent=2,
            ),
            flush=True,
        )
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
