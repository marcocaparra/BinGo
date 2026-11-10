"""Operational HTTP -> existing service -> native C; syscall harness, no PWM."""

import asyncio
import io
import json
import sys
import time
from pathlib import Path
from uuid import uuid4

import httpx2 as httpx
import pytest
from app.main import create_app
from app.services import commissioning
from app.services.capture import Frame
from app.services.controller import UnavailableController
from app.services.vision import InternalVision
from PIL import Image
from test_c_physical_backend import binaries as c_binaries
from test_c_physical_backend import native as c_native
from test_c_physical_backend import setup as c_setup
from test_c_physical_backend import submits
from test_sessions import CLASS, context_body
from test_vision import result

pytestmark = [
    pytest.mark.anyio,
    pytest.mark.skipif(sys.platform != "linux", reason="Linux native C harness"),
]
setup, binaries, native = c_setup, c_binaries, c_native


def attest(config, data, backend):
    # Test fixture evidence only. Production never generates a PASSED report.
    checksum = commissioning.digest(config)
    executable = commissioning.digest(data["executable"])
    reports = {}
    for criterion in commissioning.EVIDENCE:
        report = config.with_name(criterion + ".json")
        report.write_text(
            json.dumps(
                {
                    "schema": "bingo-commissioning-evidence-v1",
                    "criterion": criterion,
                    "outcome": "PASSED",
                    "approved_by": "test-fixture-only",
                    "approved_at": time.time() - 5,
                    "configuration_sha256": checksum,
                    "executable_sha256": executable,
                    "findings": "Controlled software test fixture; never an actual hardware commissioning approval.",
                }
            )
        )
        reports[criterion] = {
            "path": str(report),
            "sha256": commissioning.digest(report),
        }
    record = {
        "schema": "bingo-attended-commissioning-v1",
        "authorization_id": str(uuid4()),
        "audience": "attending-technicians-only",
        "purpose": "integrated-validation",
        "operator": "test-fixture-only",
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "issued_at": time.time() - 1,
        "issued_boottime": time.clock_gettime(time.CLOCK_BOOTTIME) - 1,
        "expires_at": time.time() + 120,
        "configuration_sha256": checksum,
        "executable_sha256": executable,
        "backend_journal": str(backend.resolve()),
        "controller_journal": data["journal"],
        "evidence": reports,
    }
    config.with_name("commissioning.json").write_text(json.dumps(record))
    return record


class Camera:
    calls = 0

    async def activate(self):
        pass

    async def deactivate(self):
        pass

    async def aclose(self):
        pass

    async def status(self):
        return {"present": True, "busy": False}

    async def capture(self, identifier):
        self.calls += 1
        output = io.BytesIO()
        Image.new("RGB", (16, 16)).save(output, format="JPEG")
        return Frame(output.getvalue(), "image/jpeg", simulated=False)


class Provider:
    simulated = False

    async def analyze(self, frame, candidates):
        return result()


@pytest.fixture
async def operational(setup, monkeypatch, configured_environment, healthy_body):
    env = setup
    config, data = env["config"], env["data"]
    for side in ("left", "right"):
        data["physical"][side].update(connector_pin="test-only", soc_pad="test-only")
    data["physical"]["safety_recovery_reference"] = "test-only"
    config.write_text(json.dumps(data))
    record = attest(config, data, env["python"])
    # /tmp cannot be a production authority directory. All other evidence,
    # hashes, boot, expiry, purpose and single-use checks remain real.
    monkeypatch.setattr(commissioning, "protected_file", lambda path: Path(path))
    spawn = asyncio.create_subprocess_exec

    async def initial_spawn(*args, **kwargs):
        if "--physical-initial-check" in args:
            return await spawn(
                str(env["native"]), args[-1], "initial-check", "0", "1", **kwargs
            )
        return await spawn(*args, **kwargs)

    # The imported fixture's native path is available as its own fixture argument
    # via env set below in the test fixture receiving native.
    env["record"] = record
    camera = Camera()
    online = {"value": True}
    calls = []

    def central(request):
        calls.append(request.url.path)
        if request.url.path.endswith("health-v1"):
            return httpx.Response(
                200 if online["value"] else 503,
                json=healthy_body if online["value"] else {},
            )
        if request.url.path.endswith("totem-context-v1"):
            return httpx.Response(200, json=context_body())
        pytest.fail("Unexpected central/economic request: " + request.url.path)

    monkeypatch.setattr("app.main.configured_camera", lambda client: (camera, None))
    monkeypatch.setattr(
        "app.main.build_internal_vision",
        lambda client: InternalVision(Provider(), None),
    )
    monkeypatch.setenv("BINGO_C_CONTROLLER_CONFIG", str(config))
    monkeypatch.setenv("BINGO_SQLITE_PATH", str(env["python"]))
    app = create_app(transport=httpx.MockTransport(central))
    # Initial driver check uses only the native syscall harness.
    env.update(camera=camera, online=online, central_calls=calls, app=app)
    yield env, initial_spawn


@pytest.fixture
async def running(operational, native, monkeypatch, request):
    env, spawn = operational
    env["native"] = native
    env["mode"] = getattr(request, "param", "execute")
    monkeypatch.setattr(asyncio, "create_subprocess_exec", spawn)
    app = env["app"]
    async with app.router.lifespan_context(app):
        assert app.state.controller.source == "PHYSICAL", app.state.controller_readiness
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://127.0.0.1",
            headers={"X-Totem-Request": "1"},
        ) as client:
            env["http"] = client
            yield env


async def reviewed(env):
    client = env["http"]
    assert (await client.get("/local/status")).json()["can_start_deposit"] is True
    start = await client.post(
        "/local/sessions",
        json={"command_id": str(uuid4()), "mode": "class_only", "class_id": str(CLASS)},
    )
    assert start.status_code == 200, start.text
    event = start.json()["event_id"]
    prefix = f"/local/sessions/{event}"
    assert (await client.post(prefix + "/safety", json={"has_risk": False})).json()[
        "state"
    ] == "INSERTION_READY"
    assert (
        await client.post(prefix + "/hand-removed", json={"hand_removed": True})
    ).status_code == 200
    for _ in range(100):
        current = (await client.get(prefix)).json()
        if current["state"] == "REVIEW":
            break
        await asyncio.sleep(0.01)
    assert current["state"] == "REVIEW", current
    vision = current["operational"]["vision"]
    review = await client.post(
        prefix + "/vision-review",
        json={
            "capture_id": vision["capture_id"],
            "item_id": vision["observation"]["itemId"],
            "action": "confirm",
        },
    )
    assert review.status_code == 200, review.text
    assert review.json()["operational"]["allowed_actions"] == ["hatch"]
    return prefix


async def test_http_to_native_c_duplicates_and_no_economy(running):
    env = running
    prefix = await reviewed(env)
    responses = await asyncio.gather(
        *(env["http"].post(prefix + "/hatch", json={}) for _ in range(3))
    )
    assert all(r.status_code == 200 for r in responses), [r.text for r in responses]
    for _ in range(100):
        current = (await env["http"].get(prefix)).json()
        if current["state"] == "INDETERMINATE":
            break
        await asyncio.sleep(0.01)
    assert current["state"] == "INDETERMINATE"
    hatch = [
        c
        for c in current["operational"]["commands"]
        if c["command"]["operation"] == "CYCLE_LOWER_HATCH"
    ]
    assert len(hatch) == len(submits(env)) == 1
    assert (hatch[0]["phase"], hatch[0]["result"]) == ("COMPLETED", "SUCCEEDED")
    assert env["camera"].calls == 1
    assert (
        await env["http"].post(prefix + "/hand-removed", json={"hand_removed": True})
    ).status_code == 200
    assert env["camera"].calls == 1
    with env["app"].state.sessions.store.transaction() as db:
        row = db.execute("SELECT * FROM cycles").fetchone()
        assert (
            row["physical_confirmed"] == 0
            and row["receipt"] is None
            and row["payload"] is None
        )
        assert (
            db.execute("SELECT count(*) FROM mechanical_commissioning").fetchone()[0]
            == 1
        )
    assert not any("register" in path for path in env["central_calls"])
    assert (await env["http"].get("/local/status")).json()["can_start_deposit"] is False


async def test_offline_after_review_cannot_dispatch(running):
    prefix = await reviewed(running)
    running["online"]["value"] = False
    assert (await running["http"].post(prefix + "/hatch", json={})).status_code == 503
    assert submits(running) == []


@pytest.mark.parametrize("dependency", ["camera", "primary"])
async def test_missing_camera_or_ai_blocks_new_session(running, dependency):
    capture = running["app"].state.sessions.vision.capture
    if dependency == "camera":
        capture.camera = None
    else:
        capture.vision.primary = None
    assert (await running["http"].get("/local/status")).json()[
        "can_start_deposit"
    ] is False
    response = await running["http"].post(
        "/local/sessions",
        json={"command_id": str(uuid4()), "mode": "class_only", "class_id": str(CLASS)},
    )
    assert response.status_code == 503 and submits(running) == []


@pytest.mark.parametrize("dependency", ["camera", "primary"])
async def test_device_or_provider_failure_after_insertion_never_moves(
    running, monkeypatch, dependency
):
    client = running["http"]
    session = (
        await client.post(
            "/local/sessions",
            json={
                "command_id": str(uuid4()),
                "mode": "class_only",
                "class_id": str(CLASS),
            },
        )
    ).json()
    prefix = "/local/sessions/" + session["event_id"]
    await client.post(prefix + "/safety", json={"has_risk": False})

    async def failed(*args, **kwargs):
        raise OSError("test-only device/provider failure")

    if dependency == "camera":
        monkeypatch.setattr(running["camera"], "capture", failed)
    else:
        monkeypatch.setattr(
            running["app"].state.sessions.vision.capture.vision.primary,
            "analyze",
            failed,
        )
    assert (
        await client.post(prefix + "/hand-removed", json={"hand_removed": True})
    ).status_code == 200
    for _ in range(100):
        current = (await client.get(prefix)).json()
        if current["state"] == "TECHNICAL_FAILURE":
            break
        await asyncio.sleep(0.01)
    assert current["state"] == "TECHNICAL_FAILURE"
    assert current["operational"]["vision"]["provenance"]["mechanical"] == "USER_DECLARATION"
    assert (await client.post(prefix + "/hatch", json={})).status_code in (409, 503)
    assert submits(running) == [] and current["receipt"] is None


async def test_expired_authorization_after_review_never_submits(running):
    prefix = await reviewed(running)
    record = running["record"]
    record["expires_at"] = time.time() - 1
    running["config"].with_name("commissioning.json").write_text(json.dumps(record))
    assert (await running["http"].post(prefix + "/hatch", json={})).status_code in (
        409,
        503,
    )
    assert submits(running) == []


async def test_disconnected_controller_cannot_dispatch(running):
    prefix = await reviewed(running)
    await running["app"].state.controller.aclose()
    response = await running["http"].post(prefix + "/hatch", json={})
    assert response.status_code in (409, 503)
    assert submits(running) == []


@pytest.mark.parametrize(
    "running", ["execute-open-2", "execute-timeout", "execute-lost-peer"], indirect=True
)
async def test_http_c_failure_retains_uncertainty(running):
    prefix = await reviewed(running)
    response = await running["http"].post(prefix + "/hatch", json={})
    assert response.status_code == 200, response.text
    for _ in range(100):
        current = (await running["http"].get(prefix)).json()
        if current["state"] == "INDETERMINATE":
            break
        await asyncio.sleep(0.01)
    assert current["state"] == "INDETERMINATE"
    assert current["operational"]["commands"][-1]["result"] == "UNKNOWN"
    assert len(submits(running)) == 1
    await running["http"].post(prefix + "/hatch", json={})
    assert len(submits(running)) == 1


@pytest.mark.parametrize(
    "field",
    [
        "expires_at",
        "issued_boottime",
        "boot_id",
        "configuration_sha256",
        "executable_sha256",
        "evidence",
    ],
)
async def test_commissioning_mismatch_keeps_physical_blocked(operational, field):
    env, _ = operational
    record = env["record"]
    record[field] = {
        "expires_at": 1.0,
        "issued_boottime": time.clock_gettime(time.CLOCK_BOOTTIME) - 601,
        "boot_id": str(uuid4()),
        "configuration_sha256": "0" * 64,
        "executable_sha256": "0" * 64,
        "evidence": {},
    }[field]
    env["config"].with_name("commissioning.json").write_text(json.dumps(record))
    from app.services.c_controller import CProcessController

    controller, readiness = await CProcessController.open_operational(
        env["config"], backend_journal=env["python"]
    )
    assert (
        isinstance(controller, UnavailableController) and not readiness.execution_ready
    )
    assert submits(env) == []


@pytest.mark.parametrize(
    "mode",
    [
        "initial-check",
        "initial-check-duty",
        "initial-check-disabled",
        "initial-check-period",
        "initial-check-polarity",
        "initial-check-missing",
        "initial-check-permission",
    ],
)
async def test_initial_driver_check_never_writes(setup, native, mode):
    process = await asyncio.create_subprocess_exec(
        str(native),
        str(setup["config"]),
        mode,
        "0",
        "1",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    async with asyncio.timeout(3):
        out, err = await process.communicate()
    assert process.returncode == (0 if mode == "initial-check" else 2), err
    assert b"WRITE" not in out


async def test_offline_before_insertion_cancels_safely(running):
    client = running["http"]
    response = await client.post(
        "/local/sessions",
        json={
            "command_id": str(uuid4()),
            "mode": "class_only",
            "class_id": str(CLASS),
        },
    )
    prefix = f"/local/sessions/{response.json()['event_id']}"
    assert (await client.post(prefix + "/hatch", json={})).status_code == 409
    running["online"]["value"] = False
    cancelled = await client.post(prefix + "/safety", json={"has_risk": False})
    assert cancelled.json()["state"] == "CANCELLED"
    assert (await client.get("/local/sessions/active")).json()["session"] is None
    assert submits(running) == []


async def test_maintenance_inspection_uses_only_get_and_preserves_unknown(
    setup, monkeypatch, tmp_path
):
    from app import controller_recovery
    from test_c_controller import command
    from test_mechanical_journal import blocked

    setup["mode"] = "execute-timeout"
    store, _, service = await setup["connect"]()
    request = command(blocked(store).event_id, "CYCLE_LOWER_HATCH", 30)
    await service.submit(request)
    entry = await service.wait(request.mechanical_command_id)
    assert entry.result == "UNKNOWN"
    await service.aclose()
    store.close()
    before = len(setup["frames"])
    report = tmp_path / "inspection.json"
    report.write_text(
        json.dumps(
            {
                "mechanical_command_id": str(request.mechanical_command_id),
                "inspector": "test-only",
                "power_isolation_reference": "controlled-test-fixture",
                "disposition": "RETAIN_BLOCKED",
                "findings": "Fault injection only; the controller must retain the unknown result.",
            }
        )
    )
    monkeypatch.setattr(controller_recovery, "protected_file", lambda path: Path(path))
    observed = json.loads(
        await controller_recovery.inspect(
            setup["config"],
            setup["python"],
            request.mechanical_command_id,
            report,
        )
    )
    assert observed["phase"] == "INDETERMINATE" and observed["result"] == "UNKNOWN"
    assert setup["frames"][before:] == [f"V1 GET {request.mechanical_command_id}"]
    from app.storage import CycleStore

    reopened = CycleStore(setup["python"])
    try:
        assert reopened.active().state == "INDETERMINATE"
        with reopened.transaction() as db:
            assert (
                db.execute("SELECT count(*) FROM mechanical_inspections").fetchone()[0]
                == 1
            )
    finally:
        reopened.close()
