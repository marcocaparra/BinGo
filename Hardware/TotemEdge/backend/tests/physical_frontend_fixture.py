"""Disposable UI/HTTP/native-C fixture. Never install or run on a hardware host."""

import argparse
import asyncio
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import httpx2 as httpx
import uvicorn
from app.main import create_app
from app.services import commissioning
from app.services.vision import InternalVision
from test_physical_activation import Camera, Provider, attest
from test_sessions import context_body, pin_body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    if os.name != "posix" or os.path.exists("/sys/class/pwm/pwmchip0/pwm3"):
        raise SystemExit(
            "Only a disposable Linux container WITHOUT physical PWM is permitted."
        )
    root = Path(tempfile.mkdtemp(prefix="bingo-physical-ui-"))
    source = Path(__file__).resolve().parents[2] / "controller"
    binary, harness = root / "physical", root / "harness"
    flags = ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function"]
    subprocess.run(
        [*flags, str(source / "bingo_controller.c"), "-lsqlite3", "-o", str(binary)],
        check=True,
    )
    subprocess.run(
        [
            *flags,
            str(source / "tests/pwm_driver_test.c"),
            "-lsqlite3",
            "-Wl,--wrap=open,--wrap=openat,--wrap=read,--wrap=write,--wrap=close,--wrap=clock_gettime,--wrap=clock_nanosleep,--wrap=poll",
            "-o",
            str(harness),
        ],
        check=True,
    )
    data = json.loads((source / "operational.example.json").read_text())
    data.update(executable=str(binary), journal=str(root / "controller.sqlite3"))
    data["physical"]["safety_recovery_reference"] = (
        "UI fixture only, not physical approval"
    )
    for side in ("right", "left"):
        data["physical"][side].update(
            connector_pin="fixture-only", soc_pad="fixture-only"
        )
    config, backend = root / "controller.json", root / "totem.sqlite3"
    config.write_text(json.dumps(data))
    attest(config, data, backend)
    commissioning.protected_file = lambda path: Path(
        path
    )  # /tmp fixture authority only.
    spawn = asyncio.create_subprocess_exec

    async def harness_spawn(*arguments, **kwargs):
        if "--ipc-physical" in arguments:
            return await spawn(
                str(harness), arguments[-1], "execute-pause", "0", "1", "ipc", **kwargs
            )
        if "--physical-initial-check" in arguments:
            return await spawn(
                str(harness), arguments[-1], "initial-check", "0", "1", **kwargs
            )
        return await spawn(*arguments, **kwargs)

    asyncio.create_subprocess_exec = harness_spawn
    for key in tuple(os.environ):
        if key.startswith(("BINGO_", "SUPABASE_", "AWS_", "GEMINI_")):
            os.environ.pop(key)
    os.environ.update(
        BINGO_SQLITE_PATH=str(backend),
        BINGO_C_CONTROLLER_CONFIG=str(config),
        BINGO_SUPABASE_URL="https://controlled-fixture.invalid",
        BINGO_MACHINE_ID="00000000-0000-4000-8000-000000000001",
        BINGO_MACHINE_API_KEY="fixture-not-a-credential",
    )

    def central(request):
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200,
                json={
                    "status": "AVAILABLE",
                    "can_start_deposit": True,
                    "scope": "CENTRAL_BACKEND",
                    "checked_at": "2026-11-10T12:00:00Z",
                },
            )
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=context_body())
        if request.url.path.endswith("totem-student-pin-v1"):
            assert json.loads(request.content)["pin"] == "0012"
            return httpx.Response(200, json=pin_body())
        raise AssertionError("Economic/unexpected central request in physical fixture")

    import app.main

    app.main.configured_camera = lambda client: (Camera(), None)
    app.main.build_internal_vision = lambda client: InternalVision(Provider(), None)
    application = create_app(transport=httpx.MockTransport(central))
    uvicorn.run(
        application,
        host="0.0.0.0",
        port=args.port,
        access_log=False,
        proxy_headers=False,
    )


if __name__ == "__main__":
    main()
