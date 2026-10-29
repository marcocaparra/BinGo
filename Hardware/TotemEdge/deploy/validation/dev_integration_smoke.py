"""Compose/TLS reais com Functions sintéticas; nunca conecta ao Supabase hospedado."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener
from uuid import uuid4

DEPLOY = Path(__file__).resolve().parents[1]
HOST = "ddxmohrjcxuibswmrtla.supabase.co"
SERVICE = "totem-edge-dev"
IDS = [f"00000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    project = "bingo-dev-integration-test-" + uuid4().hex[:12]
    output = DEPLOY / ".validation" / project
    output.mkdir(parents=True)
    fixture = Path(tempfile.mkdtemp(prefix="bingo-dev-integration-"))
    # Diretório externo ao build/repositório. Somente credenciais sintéticas.
    policy = fixture / "policy.json"
    policy.write_text(
        json.dumps(
            {
                "project_ref": HOST.split(".")[0],
                "test_data_only": True,
                "machine_id": IDS[0],
                "school_id": IDS[1],
                "class_ids": [IDS[2]],
                "student_ids": [IDS[3]],
            }
        )
    )
    key = fixture / "machine-key"
    key.write_text("synthetic-machine-credential-only")
    env = dict(
        os.environ,
        BINGO_DEV_POLICY_FILE=str(policy),
        BINGO_DEV_MACHINE_KEY_FILE=str(key),
        BINGO_SUPABASE_URL="https://must-not-be-forwarded.invalid",
        BINGO_MACHINE_API_KEY="host-bait-not-forwarded",
        SUPABASE_SERVICE_ROLE_KEY="host-bait-not-forwarded",
    )
    report = {"project": project, "remote_supabase": False, "checks": []}
    override = output / "override.json"
    image = "bingo-dev-validation:" + project.rsplit("-", 1)[1]

    def run(command, check=True):
        result = subprocess.run(
            command,
            cwd=DEPLOY,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=180,
        )
        if check and result.returncode:
            raise RuntimeError(
                f"Comando de validação falhou: {result.stdout}\n{result.stderr}"
            )
        return result

    def compose(*arguments, check=True):
        assert project.startswith("bingo-dev-integration-test-")
        return run(
            [
                "docker",
                "compose",
                "--project-name",
                project,
                "--env-file",
                "dev-integration.env",
                "-f",
                "compose.dev-integration.yaml",
                "-f",
                str(override),
                *arguments,
            ],
            check,
        )

    def exec_code(service, code):
        return compose("exec", "-T", service, "python", "-c", code).stdout.strip()

    def probe():
        return json.loads(
            exec_code(
                "functions-fixture",
                "import ssl,json; from urllib.request import urlopen; print(urlopen('https://localhost/_probe',context=ssl.create_default_context(cafile='/fixture/ca.crt')).read().decode())",
            )
        )

    def database():
        return json.loads(
            exec_code(
                SERVICE,
                "import os,sqlite3,json; c=sqlite3.connect('file:'+os.environ['BINGO_SQLITE_PATH']+'?mode=ro',uri=True); print(json.dumps({'cycles':c.execute('SELECT event_id,state,simulated,physical_confirmed,payload,receipt,central_scope FROM cycles ORDER BY created_at').fetchall(),'commands':c.execute('SELECT mechanical_command_id,phase,result,source,version FROM mechanical_commands ORDER BY created_at').fetchall(),'history':c.execute('SELECT count(*) FROM mechanical_history').fetchone()[0]}))",
            )
        )

    def check_economy(stage):
        state = probe()
        assert (state["deposits"], state["student_balance"], state["class_xp"]) == (
            0,
            800,
            1900,
        )
        assert all(
            call["path"]
            in {
                "/functions/v1/health-v1",
                "/functions/v1/totem-context-v1",
                "/functions/v1/totem-student-pin-v1",
            }
            for call in state["calls"]
        )
        report.setdefault("economic_checkpoints", []).append(
            {
                "stage": stage,
                "deposits": 0,
                "student_balance": 800,
                "class_xp": 1900,
                "permitted_calls": len(state["calls"]),
            }
        )

    opener = build_opener(ProxyHandler({}))

    def http(path, body=None, headers=None):
        data = None if body is None else json.dumps(body).encode()
        request = Request(
            "http://127.0.0.1:8002" + path,
            data=data,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "X-Totem-Request": "1",
                "Origin": "http://127.0.0.1:8002",
                **(headers or {}),
            },
        )
        try:
            response = opener.open(request, timeout=10)
        except HTTPError as error:
            response = error
        with response:
            payload = response.read()
            return response.status, json.loads(payload) if payload else None

    try:
        if not args.skip_build:
            run(
                [
                    "docker",
                    "build",
                    "--target",
                    "dev_integration",
                    "-t",
                    "bingo-totem-edge:dev-integration",
                    "-f",
                    "Dockerfile",
                    "..",
                ]
            )
        # CA exclusiva da imagem de validação. TLS permanece verificado; não há
        # opção verify=false no perfil real. DNS do hostname DEV aponta ao fixture.
        run(
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "none",
                "--user",
                "0",
                "--mount",
                f"type=bind,source={fixture},target=/fixture",
                "bingo-totem-edge:dev-integration",
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-keyout",
                "/fixture/tls.key",
                "-out",
                "/fixture/ca.crt",
                "-subj",
                "/CN=" + HOST,
                "-addext",
                "subjectAltName=DNS:" + HOST + ",DNS:localhost,IP:127.0.0.1",
            ]
        )
        # Chave TLS de fixture apenas; root emite arquivos legíveis pelo UID 10001.
        run(
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "none",
                "--user",
                "0",
                "--mount",
                f"type=bind,source={fixture},target=/fixture",
                "bingo-totem-edge:dev-integration",
                "chmod",
                "644",
                "/fixture/tls.key",
            ]
        )
        (fixture / "Dockerfile").write_text(
            "FROM bingo-totem-edge:dev-integration\nUSER root\nCOPY ca.crt /usr/local/share/ca-certificates/bingo-validation.crt\nRUN update-ca-certificates\nUSER 10001:10001\n"
        )
        run(["docker", "build", "-t", image, str(fixture)])
        (fixture / "mock.py").write_text(
            (DEPLOY / "validation/dev_mock.py").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        override_data = {
            "services": {
                name: {"image": image, "restart": "no"}
                for name in (SERVICE, "dev-central", "dev-http")
            },
            "networks": {"dev-egress": {"internal": True}},
        }
        override_data["services"][SERVICE]["environment"] = {
            "BINGO_DEV_PLANS": json.dumps(
                {
                    operation: {"duration_seconds": 0.05}
                    for operation in (
                        "OPEN_INSERTION_DOOR",
                        "CLOSE_INSERTION_DOOR",
                        "CYCLE_LOWER_HATCH",
                        "CONFIRM_INITIAL_STATE",
                    )
                }
            )
        }
        override_data["services"]["functions-fixture"] = {
            "image": image,
            "command": ["python", "/fixture/mock.py"],
            "user": "10001:10001",
            "read_only": True,
            "cap_drop": ["ALL"],
            "security_opt": ["no-new-privileges:true"],
            "sysctls": {"net.ipv4.ip_unprivileged_port_start": "0"},
            "volumes": [str(fixture).replace("\\", "/") + ":/fixture:ro"],
            "networks": {"dev-egress": {"aliases": [HOST]}},
            "healthcheck": {
                "test": [
                    "CMD",
                    "python",
                    "-c",
                    "import ssl; from urllib.request import urlopen; urlopen('https://localhost/_probe',context=ssl.create_default_context(cafile='/fixture/ca.crt'))",
                ]
            },
        }
        override.write_text(json.dumps(override_data))
        config = json.loads(compose("config", "--format", "json").stdout)
        services = config["services"]
        assert not services[SERVICE].get("ports") and not services[SERVICE].get(
            "secrets"
        )
        assert set(services[SERVICE]["networks"]) == {"dev-private", "central-private"}
        assert not services["dev-central"].get("ports") and not services[
            "dev-central"
        ].get("volumes")
        assert set(services["dev-http"]["networks"]) == {"dev-private", "dev-ingress"}
        assert services["dev-http"]["ports"][0]["host_ip"] == "127.0.0.1"
        for service in services.values():
            assert not service.get("devices") and not service.get("privileged")
            assert "host-bait-not-forwarded" not in json.dumps(
                service.get("environment", {})
            )
        report["checks"].append(
            "Volumes/redes/segredos separados; host/env operacional não herdados; TLS verificado com fixture sintético"
        )
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")
        assert (
            exec_code(
                SERVICE,
                "import os,json; assert os.getuid()==10001; assert not os.path.exists('/run/secrets/dev-machine-key'); r=open('/proc/net/route').read().splitlines()[1:]; assert not any(line.split()[1]=='00000000' for line in r); print('ok')",
            )
            == "ok"
        )
        assert http("/local/dev/health")[1]["economic_registration"] is False
        assert http("/local/status")[1]["can_start_deposit"] is False
        assert http("/local/dev/context")[1]["machine"]["id"] == IDS[0]
        pin = {"class_id": IDS[2], "student_id": IDS[3], "pin": "0012"}
        assert http("/local/dev/student-pin", pin)[1]["confirmed"] is True
        assert http("/local/dev/student-pin", {**pin, "pin": "9999"})[0] == 401
        report["checks"].append(
            "Contexto/PIN/health via broker e HTTPS real sintético; PIN incorreto negado; operacional OFFLINE/false"
        )
        for path, body in (
            ("/local/sessions/active", None),
            ("/local/sessions", {}),
            ("/local/dev/register", {}),
        ):
            assert http(path, body)[0] == 404
        assert (
            http("/local/dev/context", headers={"Origin": "http://foreign.invalid"})[0]
            == 403
        )
        denied = exec_code(
            SERVICE,
            "from urllib.request import Request,urlopen; from urllib.error import HTTPError; r=Request('http://dev-central:8000/functions/v1/register-deposit-v1',data=b'{}',headers={'Content-Type':'application/json','X-Totem-Dev':'1'});\ntry: urlopen(r); raise AssertionError('economic route reachable')\nexcept HTTPError as e: assert e.code==403\nprint('ok')",
        )
        assert denied == "ok"
        assert (
            exec_code(
                SERVICE,
                "import socket;\ntry: socket.create_connection(('ddxmohrjcxuibswmrtla.supabase.co',443),timeout=1); raise AssertionError('direct egress reachable')\nexcept OSError: pass\nprint('ok')",
            )
            == "ok"
        )
        report["checks"].append(
            "Rotas cruzadas ausentes; Origin preservado; chamada econômica direta ao broker negada"
        )
        base = "/local/simulation/sessions"
        event = http(base, {"command_id": str(uuid4())})[1]["session"]["event_id"]
        assert http(f"{base}/{event}/safety", {"has_risk": False})[0] == 200
        for action, extra in [
            ("open", {}),
            ("close", {"hand_removed": True}),
            ("hatch", {}),
            ("confirm-initial", {}),
        ]:
            if action == "hatch":
                assert http(f"{base}/{event}/review-fixture", {})[0] == 200
            identifier = str(uuid4())
            body = {"mechanical_command_id": identifier, **extra}
            assert http(f"{base}/{event}/{action}", body)[0] in (200, 202)
            for attempt in range(100):
                snapshot = http(f"{base}/{event}")[1]
                if snapshot["commands"][-1]["phase"] == "COMPLETED":
                    break
                time.sleep(0.05)
            else:
                raise AssertionError("Operação não concluiu no fixture")
            assert http(f"{base}/{event}/{action}", body)[0] == 200
        assert (
            snapshot["session"]["state"] == "COMPLETED"
            and snapshot["session"]["receipt"] is None
        )
        before = database()
        assert all(row[2:] == [1, 0, None, None, None] for row in before["cycles"])
        check_economy("before-restart")
        compose("restart")
        # Não perder a sentinela ao reiniciar/recriar o próprio fixture.
        for attempt in range(100):
            try:
                check_economy("after-restart-before-recreate")
                break
            except RuntimeError:
                time.sleep(0.1)
        else:
            raise AssertionError("Fixture não voltou após restart")
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
        )
        assert http(f"{base}/{event}")[1] == snapshot and database() == before
        report["checks"].append(
            "Máquina/journal existentes: quatro operações, replay, conclusão sem recibo, restart/recreate duráveis"
        )
        unsafe = compose(
            "run",
            "--rm",
            "--no-deps",
            "-e",
            "BINGO_DEV_CONTEXT=production",
            SERVICE,
            check=False,
        )
        assert (
            unsafe.returncode != 0
            and "DEV_UNSAFE_CONFIGURATION" in unsafe.stdout + unsafe.stderr
        )
        assert database() == before
        # Arquivo sintético somente; a chave ampla hospedada nunca participa.
        key.write_text("not.a.machine-key")
        try:
            unsafe_key = compose("run", "--rm", "--no-deps", "dev-central", check=False)
            assert (
                unsafe_key.returncode != 0
                and "DEV_UNSAFE_CONFIGURATION" in unsafe_key.stdout + unsafe_key.stderr
            )
            assert "not.a.machine-key" not in unsafe_key.stdout + unsafe_key.stderr
        finally:
            key.write_text("synthetic-machine-credential-only")
        report["checks"].append(
            "Contexto production e chave JWT recusados no container sem alterar histórico ou expor o segredo"
        )
        # Operação longa para interromper depois de aceitação durável.
        override_data["services"][SERVICE]["environment"]["BINGO_DEV_PLANS"] = (
            json.dumps({"OPEN_INSERTION_DOOR": {"duration_seconds": 60}})
        )
        override.write_text(json.dumps(override_data))
        check_economy("before-long-operation-recreate")
        compose(
            "up",
            "-d",
            "--no-build",
            "--force-recreate",
            "--wait",
            "--wait-timeout",
            "90",
        )
        event = http(base, {"command_id": str(uuid4())})[1]["session"]["event_id"]
        http(f"{base}/{event}/safety", {"has_risk": False})
        command = {"mechanical_command_id": str(uuid4()), "timeout_seconds": 120.0}
        assert http(f"{base}/{event}/open", command)[0] == 202
        compose("kill", "--signal", "SIGKILL", SERVICE)
        compose("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")
        recovered = http(f"{base}/{event}")[1]
        assert (
            recovered["session"]["state"] == "INDETERMINATE"
            and recovered["commands"][0]["result"] == "UNKNOWN"
        )
        assert http(f"{base}/{event}/open", command)[1] == recovered
        assert http(f"{base}/{event}/cancel", {})[0] == 409
        report["checks"].append(
            "SIGKILL após aceitação: UNKNOWN/INDETERMINATE, slot bloqueado e replay sem redisparo"
        )
        check_economy("after-interruption")
        report["checks"].append(
            "Sentinela econômica sintética inalterada: zero depósitos, saldo 800, XP 1900; apenas três Functions chamadas"
        )
        report["ok"] = True
    except BaseException as error:
        report["ok"] = False
        report["error"] = str(error)
        if override.exists():
            (output / "containers.log").write_text(
                compose("logs", "--no-color", "--tail", "60", check=False).stdout,
                encoding="utf-8",
            )
        raise
    finally:
        (output / "report.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        if override.exists():
            compose("down", "--volumes", "--remove-orphans", check=False)
        run(["docker", "image", "rm", image], check=False)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
