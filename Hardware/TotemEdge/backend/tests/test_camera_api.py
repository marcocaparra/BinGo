"""Authenticated host protocol over ASGI; fictitious camera, no external I/O."""

import asyncio
import socket
import threading
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx2 as httpx
import pytest
import uvicorn

from app.camera_api import RemoteCamera, create_host_app, load_token
from app.main import create_app
from app.services.camera import CameraError
from test_camera import prepared
from test_dev_integration import (
    dev_environment,
)  # Register the existing isolated fixture.

TOKEN = "synthetic-camera-token-for-isolated-tests-only"
HEADERS = {"Authorization": "Bearer " + TOKEN}
pytestmark = pytest.mark.anyio


async def test_private_host_and_remote_client_roundtrip(tmp_path):
    manager, driver = await prepared(tmp_path)
    app = create_host_app(manager=manager, token=TOKEN)
    app.state.camera, app.state.camera_token = manager, TOKEN
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), trust_env=False
        ) as http:
            remote = RemoteCamera(http, "http://127.0.0.1:8766", TOKEN)
            assert await remote.discover() == driver.devices
            assert (
                await remote.select(driver.devices[0].device_id) == manager.selection()
            )
            assert (await remote.status())["present"]
            await remote.activate()
            identifier = uuid4()
            frame = await remote.capture(identifier)
            assert (
                frame.content == driver.content
                and frame.simulated
                and driver.calls == 1
            )
            assert (await remote.capture_status(identifier))["phase"] == "COMPLETED"
            await remote.deactivate()
            with pytest.raises(CameraError) as error:
                await remote.capture(identifier)
            assert error.value.code == "CAPTURE_ALREADY_ATTEMPTED"
    finally:
        await manager.aclose()


async def test_host_requires_token_rejects_browser_and_sanitizes_errors(tmp_path):
    manager, driver = await prepared(tmp_path)
    app = create_host_app(manager=manager, token=TOKEN)
    with TestClient(app) as client:
        for path in ("/devices", "/selection", "/status"):
            assert client.get("/camera/v1" + path).status_code == 401
            assert (
                client.get(
                    "/camera/v1" + path,
                    headers={**HEADERS, "Origin": "http://localhost"},
                ).status_code
                == 403
            )
        response = client.post(
            "/camera/v1/probe",
            headers=HEADERS,
            json={"capture_id": str(uuid4()), "allow_real_camera": False},
        )
        assert response.status_code == 422 and driver.calls == 0
        response = client.post(
            "/camera/v1/probe",
            headers=HEADERS,
            json={"capture_id": TOKEN, "allow_real_camera": True, "secret": TOKEN},
        )
        assert response.status_code == 422 and TOKEN not in response.text
        assert response.headers["cache-control"] == "no-store"
        assert (
            client.get("/camera/v1/status?capture=true", headers=HEADERS).status_code
            == 403
        )
        driver.error = RuntimeError("private SDK information")
        response = client.post(
            "/camera/v1/probe",
            headers=HEADERS,
            json={"capture_id": str(uuid4()), "allow_real_camera": True},
        )
        assert response.status_code == 503 and "private SDK" not in response.text


@pytest.mark.parametrize(
    "url",
    [
        "https://example.com",
        "http://example.com",
        "http://127.0.0.1/x",
        "http://secret@localhost",
        "http://localhost?token=x",
    ],
)
async def test_remote_url_rejects_external_destinations(url):
    with pytest.raises(CameraError):
        RemoteCamera(None, url, TOKEN)


async def test_token_and_configuration_do_not_open_camera(tmp_path, monkeypatch):
    path = tmp_path / "token"
    path.write_text(TOKEN)
    assert load_token(path) == TOKEN
    path.write_text("short")
    with pytest.raises(CameraError):
        load_token(path)
    with TestClient(create_app(), base_url="http://127.0.0.1") as client:
        assert client.get("/local/camera/devices").status_code == 404
        assert client.get("/health").status_code == 200


async def test_backend_uses_authenticated_bridge_without_capture_on_get(
    tmp_path, monkeypatch
):
    manager, driver = await prepared(tmp_path)
    bridge = create_host_app(manager=manager, token=TOKEN)
    # ASGITransport doesn't enter lifespan; inject only the test composition.
    bridge.state.camera, bridge.state.camera_token = manager, TOKEN
    token_path = tmp_path / "camera.token"
    token_path.write_text(TOKEN)
    monkeypatch.setenv("BINGO_CAMERA_MODE", "remote")
    monkeypatch.setenv("BINGO_CAMERA_URL", "http://127.0.0.1:8766")
    monkeypatch.setenv("BINGO_CAMERA_TOKEN_FILE", str(token_path))
    try:
        with TestClient(
            create_app(camera_transport=httpx.ASGITransport(app=bridge)),
            base_url="http://127.0.0.1",
        ) as client:
            assert (
                client.get("/local/camera/devices", headers=HEADERS).status_code == 200
            )
            for _ in range(3):
                assert (
                    client.get("/local/camera/status", headers=HEADERS).status_code
                    == 200
                )
            assert driver.calls == 0
            assert (
                client.post(
                    "/local/camera/captures",
                    headers={**HEADERS, "X-Totem-Request": "1"},
                    json={"capture_id": str(uuid4())},
                ).status_code
                == 404
            )
            response = client.post(
                "/local/camera/probe",
                headers={**HEADERS, "X-Totem-Request": "1"},
                json={"capture_id": str(uuid4()), "allow_real_camera": True},
            )
            assert response.status_code == 200 and driver.calls == 1
    finally:
        await manager.aclose()


async def test_remote_rejects_mismatched_capture_and_invalid_image():
    async def upstream(request):
        return httpx.Response(
            200,
            content=b"invalid",
            headers={"Content-Type": "image/jpeg", "X-Capture-Id": str(uuid4())},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as client:
        with pytest.raises(CameraError) as error:
            await RemoteCamera(client, "http://localhost", TOKEN).capture(uuid4())
        assert error.value.code == "CAMERA_INCONSISTENT_RESPONSE"


async def test_real_loopback_http_host_roundtrip_and_resource_cleanup(tmp_path):
    manager, driver = await prepared(tmp_path)
    app = create_host_app(manager=manager, token=TOKEN)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    server = uvicorn.Server(
        uvicorn.Config(app, log_level="critical", access_log=False, proxy_headers=False)
    )
    thread = threading.Thread(
        target=server.run, kwargs={"sockets": [listener]}, daemon=True
    )
    thread.start()
    try:
        for _ in range(100):
            if server.started:
                break
            await asyncio.sleep(0.05)
        assert server.started
        async with httpx.AsyncClient(trust_env=False) as http:
            remote = RemoteCamera(http, f"http://127.0.0.1:{port}", TOKEN)
            assert await remote.discover() == driver.devices and driver.calls == 0
            identifier = uuid4()
            frame = await remote.capture(identifier)
            assert frame.content == driver.content and frame.simulated
            assert (await remote.capture_status(identifier))["phase"] == "COMPLETED"
        assert driver.released == 1
    finally:
        server.should_exit = True
        await asyncio.to_thread(thread.join, 5)
        listener.close()
        assert not thread.is_alive()


async def test_dev_camera_capability_does_not_use_or_expand_central_transport(
    tmp_path, monkeypatch, dev_environment
):
    from test_dev_integration import create_dev_app

    directory, policy, _ = dev_environment
    manager, driver = await prepared(tmp_path)
    bridge = create_host_app(manager=manager, token=TOKEN)
    bridge.state.camera, bridge.state.camera_token = manager, TOKEN
    token_path = tmp_path / "camera.token"
    token_path.write_text(TOKEN)
    monkeypatch.setenv("BINGO_CAMERA_MODE", "remote")
    monkeypatch.setenv("BINGO_CAMERA_URL", "http://127.0.0.1:8766")
    monkeypatch.setenv("BINGO_CAMERA_TOKEN_FILE", str(token_path))
    calls = []

    def unavailable(request):
        calls.append(request.url.path)
        return httpx.Response(503)

    app = create_dev_app(
        data_directory=directory,
        policy_path=policy,
        transport=httpx.MockTransport(unavailable),
        camera_transport=httpx.ASGITransport(app=bridge),
    )
    try:
        with TestClient(
            app,
            base_url="http://127.0.0.1",
            headers={**HEADERS, "X-Totem-Request": "1"},
        ) as client:
            assert client.get("/local/camera/status").json()["present"]
            assert (
                client.post(
                    "/local/camera/probe",
                    json={"capture_id": str(uuid4()), "allow_real_camera": True},
                ).status_code
                == 200
            )
            assert calls == [] and driver.calls == 1
            assert client.get("/local/dev/health").status_code == 503
            assert calls == ["/functions/v1/health-v1"]
            assert (
                client.post(
                    "/local/simulation/sessions", json={"command_id": str(uuid4())}
                ).json()["session"]["receipt"]
                is None
            )
    finally:
        await manager.aclose()
