"""Test-only HTTP composition: real DEV app/SQLite, in-process synthetic broker.

Reuses the backend's public fixtures. No hosted credentials, private test routes,
physical I/O, PIN files or SQLite access from the browser.
"""

import argparse
from contextlib import asynccontextmanager
from copy import deepcopy
import json
import os
from pathlib import Path
import sys
import asyncio

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import httpx2 as httpx
import uvicorn

from app.dev_broker import create_broker_app
from app.dev_integration import ALLOWED, create_dev_app
from test_dev_integration import CONTEXT, KEY, MACHINE, SCHOOL, PIN


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    data = root / "dev-data"
    for name in tuple(os.environ):
        if name.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_")):
            os.environ.pop(name)
    os.environ.update(
        BINGO_DEV_CONTEXT="test", BINGO_SQLITE_PATH=str(data / "simulation.sqlite3")
    )
    policy, key = root / "policy.json", root / "machine-key"
    policy.write_text(
        json.dumps(
            {
                "project_ref": "ddxmohrjcxuibswmrtla",
                "machine_id": str(MACHINE),
                "school_id": str(SCHOOL),
            }
        )
    )
    key.write_text(KEY)
    context = deepcopy(CONTEXT)
    # Exercise the existing segment/year controls with synthetic context metadata.
    context["classes"][0].update(segment="Fundamental II", grade="7º Ano")
    other = {
        **context["students"][0],
        "id": "00000000-0000-4000-8000-000000000005",
        "name": "Outro aluno sintético",
    }
    context["students"].append(other)
    (root / "public.json").write_text(
        json.dumps(
            {
                "class_id": PIN["class_id"],
                "student_id": PIN["student_id"],
                "other_id": other["id"],
            }
        )
    )
    stats = {"calls": []}
    stats_path = root / "stats.json"
    stats_path.write_text(json.dumps(stats))

    async def remote(request):
        assert (request.method, request.url.path) in ALLOWED
        stats["calls"].append({"method": request.method, "path": request.url.path})
        stats_path.write_text(json.dumps(stats))
        control = json.loads((root / "control.json").read_text())
        if control.get("offline"):
            return httpx.Response(503, json={})
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200,
                json={
                    "status": "AVAILABLE",
                    "can_start_deposit": True,
                    "scope": "CENTRAL_BACKEND",
                    "checked_at": "2026-10-30T12:00:00Z",
                },
            )
        if request.url.path.endswith("totem-context-v1"):
            body = deepcopy(context)
            if control.get("empty"):
                body["classes"], body["students"] = [], []
            if control.get("unsafe_labels"):
                body["classes"][0]["grade"] = (
                    "</span></button></div><img src=/label-test>"
                )
                body["classes"][0]["name"] = "<Turma sintética>"
                body["students"][0]["name"] = "<Aluno sintético>"
            return httpx.Response(200, json=body)
        if control.get("slow_pin"):
            await asyncio.sleep(0.2)
        body = json.loads(request.content)
        student = next(
            (
                s
                for s in context["students"]
                if s["id"] == body["student_id"] and s["class_id"] == body["class_id"]
            ),
            None,
        )
        if body["pin"] != PIN["pin"] or student is None:
            return httpx.Response(401, json={"error": {"code": "STUDENT_PIN_INVALID"}})
        return httpx.Response(
            200,
            json={
                "confirmed": True,
                "student": {
                    k: student[k] for k in ("id", "name", "class_id", "class_name")
                },
            },
        )

    broker = create_broker_app(
        policy_path=policy, key_path=key, transport=httpx.MockTransport(remote)
    )
    app = create_dev_app(
        data_directory=data,
        policy_path=policy,
        transport=httpx.ASGITransport(app=broker),
    )
    original = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(application):
        async with broker.router.lifespan_context(broker):
            async with original(application):
                yield

    app.router.lifespan_context = lifespan
    server = uvicorn.Server(
        uvicorn.Config(
            app, host="127.0.0.1", port=args.port, access_log=False, proxy_headers=False
        )
    )

    async def serve():
        async def stop_requested():
            # Test-only local control, not an HTTP capability. Let lifespan close
            # SQLite and its Windows byte-range lease before removing this root.
            while not (root / "stop").exists():
                await asyncio.sleep(0.1)
            server.should_exit = True

        watcher = asyncio.create_task(stop_requested())
        try:
            await server.serve()
        finally:
            watcher.cancel()

    asyncio.run(serve())


if __name__ == "__main__":
    main()
