"""Private authenticated camera transport, reused by host and TotemEdge."""

from contextlib import asynccontextmanager
import hmac
import os
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import APIRouter, Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
import httpx2 as httpx
from pydantic import BaseModel, ConfigDict, Field

from app.services.camera import CameraError, CameraManager, Device, FFmpegDriver
from app.services.capture import Frame
from app.services.vision import MAX_IMAGE_BYTES, VisionError, validate_frame


def load_token(path):
    try:
        path = Path(path)
        if not path.is_absolute() or path.is_symlink() or path.stat().st_size > 256:
            raise ValueError()
        token = path.read_text(encoding="ascii").strip()
        if not 32 <= len(token) <= 128 or not all(33 <= ord(c) <= 126 for c in token):
            raise ValueError()
        return token
    except (OSError, ValueError, UnicodeError):
        raise CameraError("CAMERA_TOKEN_CONFIGURATION", 503) from None


def require_token(request: Request):
    expected = getattr(request.app.state, "camera_token", "")
    header = request.headers.get("authorization", "")
    if request.headers.get("origin") is not None or request.url.query:
        raise CameraError("CAMERA_REQUEST_DENIED", 403)
    if (
        not expected
        or not header.isascii()
        or not hmac.compare_digest(header, "Bearer " + expected)
    ):
        raise CameraError("CAMERA_AUTHENTICATION_REQUIRED", 401)


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Selection(Body):
    device_id: str = Field(min_length=64, max_length=64, pattern=r"^[a-f0-9]+$")


class Capture(Body):
    capture_id: UUID


class Probe(Capture):
    # Explicit acknowledgment, never truthy coercion of strings or integers.
    allow_real_camera: bool = Field(strict=True)


def metadata(frame, identifier):
    return {
        "capture_id": str(identifier),
        "media_type": frame.media_type,
        "bytes": len(frame.content),
        "simulated": frame.simulated,
    }


def router(prefix, *, host=False):
    routes = APIRouter(prefix=prefix, dependencies=[Depends(require_token)])

    def camera(request):
        manager = getattr(request.app.state, "camera", None)
        if manager is None:
            raise CameraError("CAMERA_NOT_CONFIGURED")
        return manager

    @routes.get("/devices")
    async def devices(request: Request):
        return await camera(request).discover()

    @routes.get("/selection")
    async def selected(request: Request):
        return camera(request).selection() if host else await camera(request).selected()

    @routes.put("/selection")
    async def select(body: Selection, request: Request):
        return await camera(request).select(body.device_id)

    @routes.get("/status")
    async def status(request: Request):
        return await camera(request).status()

    @routes.get("/captures/{capture_id}")
    async def capture_status(capture_id: UUID, request: Request):
        return await camera(request).capture_status(capture_id)

    @routes.post("/probe")
    async def probe(body: Probe, request: Request):
        if not body.allow_real_camera:
            raise CameraError("CAMERA_EXPLICIT_OPT_IN_REQUIRED", 422)
        frame = await camera(request).capture(body.capture_id)
        return metadata(frame, body.capture_id)

    if host:

        @routes.post("/captures")
        async def capture(body: Capture, request: Request):
            frame = await camera(request).capture(body.capture_id)
            return Response(
                frame.content,
                media_type=frame.media_type,
                headers={
                    "X-Capture-Id": str(body.capture_id),
                    "X-Camera-Source": "SIMULATED" if frame.simulated else "DEVICE",
                },
            )
    else:

        @routes.post("/sessions/{event_id}/capture")
        async def session_capture(event_id: UUID, body: Capture, request: Request):
            frame = await request.app.state.capture.capture_only(
                event_id, body.capture_id
            )
            return metadata(frame, body.capture_id)

    return routes


async def camera_error(request, error):
    code = error.code if isinstance(error, CameraError) else "INVALID_CAMERA_CONTRACT"
    status = error.status if isinstance(error, CameraError) else 422
    return JSONResponse(
        {"error": {"code": code, "message": "Operação de câmera não concluída."}},
        status_code=status,
        headers={"Cache-Control": "no-store"},
    )


class RemoteCamera:
    def __init__(self, client, url, token):
        parsed = urlsplit(url)
        if (
            parsed.scheme != "http"
            or parsed.hostname
            not in {"127.0.0.1", "localhost", "::1", "host.docker.internal"}
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.path not in {"", "/"}
        ):
            raise CameraError("CAMERA_URL_CONFIGURATION")
        self.client, self.url, self._token = client, url.rstrip("/"), token

    async def _request(self, method, path, body=None, *, image=False):
        try:
            async with self.client.stream(
                method,
                self.url + "/camera/v1" + path,
                json=body,
                headers={"Authorization": "Bearer " + self._token},
                timeout=18,
                follow_redirects=False,
            ) as response:
                content = bytearray()
                async for chunk in response.aiter_bytes():
                    content.extend(chunk)
                    if len(content) > (MAX_IMAGE_BYTES if image else 262144):
                        raise CameraError("CAMERA_OUTPUT_LIMIT")
                if response.status_code != 200:
                    # Controlled allowlist: never surface arbitrary remote text.
                    import json

                    try:
                        code = json.loads(content)["error"]["code"]
                    except Exception:
                        code = "CAMERA_BRIDGE_UNAVAILABLE"
                    if (
                        type(code) is not str
                        or not code.startswith(("CAMERA_", "CAPTURE_"))
                        or not code.replace("_", "").isalnum()
                        or len(code) > 80
                    ):
                        code = "CAMERA_BRIDGE_UNAVAILABLE"
                    raise CameraError(
                        code,
                        response.status_code
                        if response.status_code in {401, 403, 404, 409, 422, 503}
                        else 503,
                    )
                if image:
                    if response.headers.get("x-capture-id") != body[
                        "capture_id"
                    ] or response.headers.get("x-camera-source") not in {
                        "SIMULATED",
                        "DEVICE",
                    }:
                        raise CameraError("CAMERA_INCONSISTENT_RESPONSE")
                    frame = Frame(
                        bytes(content),
                        response.headers.get("content-type", ""),
                        simulated=response.headers["x-camera-source"] == "SIMULATED",
                    )
                    validate_frame(frame)
                    return frame
                import json

                return json.loads(content)
        except CameraError:
            raise
        except (Exception, VisionError):
            raise CameraError("CAMERA_BRIDGE_UNAVAILABLE") from None

    async def discover(self):
        return [
            Device.model_validate(d) for d in await self._request("GET", "/devices")
        ]

    async def selected(self):
        value = await self._request("GET", "/selection")
        return Device.model_validate(value) if value else None

    async def select(self, identifier):
        return Device.model_validate(
            await self._request("PUT", "/selection", {"device_id": identifier})
        )

    async def status(self):
        return await self._request("GET", "/status")

    async def capture_status(self, identifier):
        return await self._request("GET", f"/captures/{identifier}")

    async def activate(self):
        if not await self.selected():
            raise CameraError("CAMERA_NOT_SELECTED", 409)

    async def capture(self, capture_id=None):
        if capture_id is None:
            raise CameraError("CAPTURE_ID_REQUIRED", 422)
        return await self._request(
            "POST", "/captures", {"capture_id": str(capture_id)}, image=True
        )

    async def deactivate(self):
        pass

    async def aclose(self):
        pass


def configured_camera(client):
    mode = os.getenv("BINGO_CAMERA_MODE", "disabled")
    if mode == "disabled":
        return None, ""
    token = load_token(os.getenv("BINGO_CAMERA_TOKEN_FILE", ""))
    if mode == "remote":
        return RemoteCamera(client, os.getenv("BINGO_CAMERA_URL", ""), token), token
    if mode == "local":
        return CameraManager(
            Path(os.environ["BINGO_CAMERA_DB"]),
            FFmpegDriver(os.getenv("BINGO_CAMERA_FFMPEG", "ffmpeg")),
        ), token
    raise CameraError("CAMERA_MODE_CONFIGURATION")


def create_host_app(*, manager=None, token=None):
    @asynccontextmanager
    async def lifespan(app):
        app.state.camera_token = token or load_token(
            os.getenv("BINGO_CAMERA_TOKEN_FILE", "")
        )
        app.state.camera = manager or CameraManager(
            Path(os.environ["BINGO_CAMERA_DB"]),
            FFmpegDriver(os.getenv("BINGO_CAMERA_FFMPEG", "ffmpeg")),
        )
        try:
            yield
        finally:
            await app.state.camera.aclose()

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.include_router(router("/camera/v1", host=True))
    app.add_exception_handler(CameraError, camera_error)
    app.add_exception_handler(RequestValidationError, camera_error)

    @app.middleware("http")
    async def no_cache(request, next_call):
        response = await next_call(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    return app
