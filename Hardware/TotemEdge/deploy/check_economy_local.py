"""HTTP econômico controlado, exclusivamente no Supabase LOCAL já existente.

Sem reset, deploy, novo projeto Docker ou credenciais hospedadas. Registros de
teste identificados por CONTROLLED_LOCAL_ECONOMY_TEST são preservados no local.
"""

import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

EDGE = Path(__file__).resolve().parents[1]
SOFTWARE = EDGE.parents[1] / "Software"


def main():
    cli = SOFTWARE / "node_modules/@supabase/cli-windows-x64/bin/supabase.exe"
    command = [str(cli)] if cli.exists() else ["supabase"]
    status = subprocess.run(
        [*command, "status", "-o", "json"],
        cwd=SOFTWARE,
        capture_output=True,
        text=True,
        check=True,
    )
    local = json.loads(status.stdout)
    if local["API_URL"] != "http://127.0.0.1:54321" or not local[
        "SECRET_KEY"
    ].startswith("sb_secret_"):
        raise RuntimeError("Somente Supabase local em 127.0.0.1:54321 é permitido.")
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.upper().startswith(
            ("BINGO_", "SUPABASE_", "AWS_", "GEMINI_", "GOOGLE_")
        )
    }
    env.update(
        SUPABASE_URL=local["API_URL"],
        SUPABASE_SECRET_KEY=local["SECRET_KEY"],
        PYTHONDONTWRITEBYTECODE="1",
    )
    deno = shutil.which("deno")
    runtime = (
        [deno]
        if deno
        else [shutil.which("npx.cmd") or "npx", "--yes", "--package=deno", "deno"]
    )
    handler = (SOFTWARE / "supabase/functions/register-deposit-v1/handler.ts").as_uri()
    with tempfile.TemporaryDirectory(prefix="bingo-local-economy-") as temp:
        server = Path(temp) / "serve.ts"
        server.write_text(
            f"import {{ handler }} from {json.dumps(handler)};\n"
            'if (Deno.env.get("SUPABASE_URL") !== "http://127.0.0.1:54321") throw new Error("Local only");\n'
            'Deno.serve({hostname:"127.0.0.1",port:0,onListen:({port})=>console.log("PORT="+port)}, handler);\n',
            encoding="utf-8",
        )
        process = subprocess.Popen(
            [
                *runtime,
                "run",
                "--config",
                str(SOFTWARE / "supabase/functions/deno.json"),
                "--allow-env",
                "--allow-net=127.0.0.1,localhost",
                str(server),
            ],
            cwd=SOFTWARE,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            # onListen is emitted only after the loopback listener is ready.
            output = queue.Queue()
            threading.Thread(
                target=lambda: output.put(process.stdout.readline()), daemon=True
            ).start()
            line = output.get(timeout=45).strip()
            if not line.startswith("PORT="):
                raise RuntimeError("Não foi possível iniciar o handler Deno local.")
            port = int(line.removeprefix("PORT="))
            env["TOTEM_TEST_EDGE_PORT"] = str(port)
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "pytest",
                    "integration/test_economy_local.py",
                    "-q",
                ],
                cwd=EDGE / "backend",
                env=env,
                check=False,
            )
            return result.returncode
        finally:
            # Deno is invoked directly when available. On Windows npx owns a
            # child tree; stop exactly this test process tree, never services.
            if os.name == "nt":
                subprocess.run(
                    ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    capture_output=True,
                    check=False,
                )
            else:
                process.terminate()
            process.communicate(timeout=15)


if __name__ == "__main__":
    raise SystemExit(main())
