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
from dev_data import CONTEXT, KEY, MACHINE, SCHOOL, PIN


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--vision", action="store_true")
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

    if not args.vision:
        broker = create_broker_app(
            policy_path=policy, key_path=key, transport=httpx.MockTransport(remote)
        )
        app = create_dev_app(
            data_directory=data,
            policy_path=policy,
            transport=httpx.ASGITransport(app=broker),
        )
    if args.vision:
        from app.vision_lab import create_vision_dev_app
        from app.services.vision import InternalVision, VisionError
        from app.services.vision_policy import classify_labels
        from app.services.camera import device
        from io import BytesIO
        from PIL import Image

        os.environ.pop("BINGO_DEV_CONTEXT")
        os.environ["BINGO_VISION_LAB_CONTEXT"] = "test"
        token = root / "camera.token"
        token.write_text("synthetic-camera-capability-for-browser-tests")
        os.environ.update(
            BINGO_CAMERA_MODE="remote",
            BINGO_CAMERA_URL="http://127.0.0.1:8766",
            BINGO_CAMERA_TOKEN_FILE=str(token),
        )
        image = BytesIO()
        Image.new("RGB", (24, 18), "green").save(image, format="JPEG")
        pixels = image.getvalue()
        stats.update(camera=[], primary=0, secondary=0, jpeg_delivered=False)
        selected = device("Synthetic camera", "synthetic:browser", "device")

        def controls():
            return json.loads((root / "control.json").read_text())

        def save():
            stats_path.write_text(json.dumps(stats))

        async def camera(request):
            assert (
                request.headers["authorization"]
                == "Bearer synthetic-camera-capability-for-browser-tests"
            )
            if request.url.path.endswith("/selection"):
                return httpx.Response(200, json=selected.model_dump())
            assert request.url.path.endswith("/captures")
            identifier = json.loads(request.content)["capture_id"]
            assert identifier not in stats["camera"], "Never recapture the same intent"
            stats["camera"].append(identifier)
            save()
            while controls().get("hold_capture"):
                await asyncio.sleep(0.05)
            await asyncio.sleep(0.25)
            if controls().get("camera_failure"):
                return httpx.Response(
                    503, json={"error": {"code": "CAMERA_DISCONNECTED"}}
                )
            return httpx.Response(
                200,
                content=pixels,
                headers={
                    "Content-Type": "image/jpeg",
                    "X-Capture-Id": identifier,
                    "X-Camera-Source": "SIMULATED",
                },
            )

        class Primary:
            simulated = True

            async def analyze(self, frame, candidates):
                stats["primary"] += 1
                stats["jpeg_delivered"] = frame.content == pixels
                save()
                while controls().get("hold_classification"):
                    await asyncio.sleep(0.05)
                await asyncio.sleep(0.25)
                control = controls()
                if control.get("vision_failure"):
                    raise VisionError("PRIMARY_UNAVAILABLE")
                if control.get("fallback"):
                    return dict(
                        status="needs-secondary",
                        itemId=None,
                        candidateIds=["cable"],
                        confidence=0.5,
                        origin="AWS_REKOGNITION",
                    )
                return (
                    classify_labels([{"Name": "Water Bottle", "Confidence": 99}])
                    if control.get("reject")
                    else classify_labels(
                        [
                            {"Name": "Cable", "Confidence": 98},
                            {"Name": "Battery", "Confidence": 80},
                        ]
                    )
                )

        class Secondary:
            simulated = True

            async def analyze(self, frame, candidates):
                stats["secondary"] += 1
                save()
                while controls().get("hold_secondary"):
                    await asyncio.sleep(0.05)
                return dict(
                    status="recognized",
                    itemId="small",
                    candidateIds=["small", "cable"],
                    detected_types={"small": "Fone de ouvido"},
                    confidence=0.95,
                    origin="GEMINI_FALLBACK",
                )

        save()
        app = create_vision_dev_app(
            data_directory=data,
            policy_path=policy,
            transport=httpx.MockTransport(remote),
            camera_transport=httpx.MockTransport(camera),
            vision=InternalVision(Primary(), Secondary()),
        )
    original = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(application):
        if args.vision:
            async with original(application):
                yield
            return
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
