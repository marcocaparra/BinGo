from contextlib import asynccontextmanager
from collections.abc import Callable
import os
from pathlib import Path

import httpx2 as httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.clients.supabase import CentralError, SupabaseEdgeClient
from app.cycles import CycleError
from app.mechanical import ControllerError, MechanicalController
from app.routes import health, local, sessions
from app.services.capture import CaptureService
from app.services.controller import UnavailableController
from app.services.c_controller import CProcessController
from app.services.mechanical import MechanicalService
from app.services.simulation_flow import SimulationFlow
from app.services.sessions import SessionService
from app.services.status import LocalStatusService
from app.services.vision import build_internal_vision
from app.simulation import (
    SimulationSettings,
    reject_simulation_in_operational,
)
from app.storage import CycleStore
from app.camera_api import configured_camera, router as camera_router, camera_error
from app.services.camera import CameraError


def create_app(
    *,
    transport: httpx.AsyncBaseTransport | None = None,
    camera_transport: httpx.AsyncBaseTransport | None = None,
    controller_factory: Callable[[], MechanicalController] | None = None,
    _simulation: SimulationSettings | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(application: FastAPI):
        controller_config = os.getenv("BINGO_C_CONTROLLER_CONFIG")
        if controller_config is not None and (
            _simulation is not None or controller_factory is not None
        ):
            raise ValueError(
                "Configuração C operacional conflita com controller injetado/DEV."
            )
        sqlite_path = Path(
            os.getenv(
                "BINGO_SQLITE_PATH",
                str(Path(__file__).resolve().parents[1] / ".data/totem.sqlite3"),
            )
        )
        if _simulation is not None:
            _simulation.prepare_storage()
            sqlite_path = _simulation.sqlite_path
        else:
            reject_simulation_in_operational(sqlite_path)
        policy = getattr(_simulation, "policy", None)
        store = CycleStore(
            sqlite_path,
            simulation_enabled=_simulation is not None,
            identity_scope=(policy.project_ref, policy.machine_id, policy.school_id)
            if policy is not None
            else None,
        )
        try:
            readiness = None
            if controller_factory is not None:
                controller = controller_factory()
                source = (
                    "UNAVAILABLE"
                    if isinstance(controller, UnavailableController)
                    else "SIMULATED"
                )
            else:
                controller, readiness = await CProcessController.open_operational(
                    Path(controller_config) if controller_config is not None else None,
                    backend_journal=sqlite_path,
                )
                source = "UNAVAILABLE"
            mechanical = MechanicalService(
                store,
                controller,
                source=source,
                auto_initial=bool(getattr(_simulation, "dev_integration", False)),
            )
            try:
                application.state.controller = controller
                # Startup snapshot. A connected C controller also exposes its
                # current local readiness (including a later disconnect).
                application.state.controller_readiness = readiness
                application.state.mechanical = mechanical
                async with httpx.AsyncClient(
                    transport=_simulation.build_transport(transport)
                    if _simulation
                    else transport,
                    follow_redirects=False,
                    trust_env=False,
                ) as http_client:
                    central = (
                        _simulation.build_central(http_client)
                        if _simulation
                        else SupabaseEdgeClient(http_client)
                    )
                    status = LocalStatusService(central)
                    application.state.status_service = status
                    application.state.sessions = SessionService(store, central, status)
                    application.state.dev_central = central
                    if _simulation:
                        application.state.simulation_flow = SimulationFlow(
                            store,
                            mechanical,
                            central=central
                            if store.identity_scope is not None
                            else None,
                            doorless=bool(getattr(_simulation, "doorless", False)),
                        )
                    # Serviços privados, desconectados da autorização física.
                    application.state.vision = (
                        None if _simulation else build_internal_vision(http_client)
                    )
                    # Camera traffic has its own bounded local capability; it
                    # never shares/relaxes the central DEV broker's transport.
                    async with httpx.AsyncClient(
                        transport=camera_transport,
                        follow_redirects=False,
                        trust_env=False,
                    ) as camera_http:
                        camera, token = configured_camera(camera_http)
                        application.state.camera = camera
                        application.state.camera_token = token
                        application.state.capture = CaptureService(store, camera=camera)
                        session_vision = None
                        if getattr(_simulation, "vision_enabled", False):
                            from app.services.session_vision import SessionVision

                            # Separate client: AI traffic never relaxes the central
                            # broker transport, and carries no machine credentials.
                            vision = _simulation.build_vision(camera_http)
                            application.state.capture.vision = vision
                            session_vision = SessionVision(
                                application.state.capture,
                                mechanical,
                                model=_simulation.vision_settings.model,
                                deferred_analysis=bool(
                                    getattr(_simulation, "deferred_analysis", False)
                                ),
                            )
                            application.state.simulation_flow.vision = session_vision
                            session_vision.recover_unstarted()
                        try:
                            economy = None
                            if getattr(
                                _simulation, "vision_enabled", False
                            ) and getattr(policy, "economic_registration", False):
                                import asyncio
                                from app.services.dev_economy import DevEconomy

                                economy = DevEconomy(store, central)
                                store.dev_economy = economy
                                economy.task = asyncio.create_task(economy.run())
                            await mechanical.resume_initial()
                            yield
                        finally:
                            if economy is not None:
                                economy.task.cancel()
                                import contextlib

                                with contextlib.suppress(asyncio.CancelledError):
                                    await economy.task
                            if session_vision is not None:
                                await session_vision.aclose()
                            if camera is not None:
                                await camera.aclose()
            finally:
                await mechanical.aclose()
        finally:
            store.close()

    application = FastAPI(title="BinGo Totem Edge", lifespan=lifespan)
    application.include_router(health.router)
    application.include_router(local.router)
    if os.getenv("BINGO_CAMERA_MODE", "disabled") != "disabled":
        application.include_router(camera_router("/local/camera"))
    application.add_exception_handler(CameraError, camera_error)
    if _simulation is None:
        application.include_router(sessions.router)
    if _simulation:
        from app.routes.simulation import router as simulation_router

        application.include_router(simulation_router)
        if getattr(_simulation, "dev_integration", False):
            from app.routes.dev import router as dev_router

            application.include_router(dev_router)

    @application.exception_handler(CycleError)
    @application.exception_handler(CentralError)
    @application.exception_handler(ControllerError)
    async def safe_error(request: Request, error):
        if isinstance(error, ControllerError):
            status = (
                404
                if error.code == "MECHANICAL_COMMAND_NOT_FOUND"
                else 503
                if error.code in {"CONTROLLER_CLOSED", "COMMAND_CAPACITY_REACHED"}
                else 409
            )
        else:
            status = (
                error.status if isinstance(error, CycleError) else error.http_status
            )
        return JSONResponse(
            {"error": {"code": error.code, "message": str(error)}},
            status_code=status,
            headers={"Cache-Control": "no-store"},
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error(request: Request, error):
        # Não expor input/repr: a validação de PIN pode conter o próprio segredo.
        return JSONResponse(
            {
                "error": {
                    "code": "INVALID_LOCAL_CONTRACT",
                    "message": "Dados locais inválidos.",
                }
            },
            status_code=422,
            headers={"Cache-Control": "no-store"},
        )

    @application.middleware("http")
    async def local_boundary(request: Request, call_next):
        path = request.url.path
        protected = path.startswith(
            (
                "/local/sessions",
                "/local/context",
                "/local/simulation",
                "/local/dev",
                "/local/camera",
                "/assets/",
            )
        ) or path in {
            "/",
            "/styles.css",
            "/script.js",
            "/local_api.js",
            "/operational.js",
        }
        if protected:
            allowed_host = request.url.hostname in {"127.0.0.1", "localhost", "::1"}
            origin = request.headers.get("origin")
            allowed_origin = origin is None or origin == str(request.base_url).rstrip(
                "/"
            )
            writing = request.method not in {"GET", "HEAD"}
            if (
                not allowed_host
                or not allowed_origin
                or (
                    writing
                    and (
                        request.headers.get("X-Totem-Request") != "1"
                        or request.headers.get("content-type", "").split(";")[0]
                        != "application/json"
                    )
                )
            ):
                return JSONResponse(
                    {
                        "error": {
                            "code": "LOCAL_ORIGIN_REQUIRED",
                            "message": "Origem local inválida.",
                        }
                    },
                    status_code=403,
                )
        if protected and path.startswith("/local/") and request.url.query:
            return JSONResponse(
                {
                    "error": {
                        "code": "INVALID_LOCAL_CONTRACT",
                        "message": "Query não permitida.",
                    }
                },
                status_code=422,
            )
        response = await call_next(request)
        if path == "/health" and getattr(_simulation, "dev_integration", False):
            # Profile discovery is local liveness, independent of central readiness.
            response.headers["X-Totem-Runtime"] = "dev-integration"
        if request.url.path.startswith("/local/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    frontend = Path(__file__).resolve().parents[2] / "frontend"
    application.mount(
        "/assets", StaticFiles(directory=frontend / "assets"), name="assets"
    )

    @application.get("/", include_in_schema=False)
    async def index():
        return FileResponse(
            frontend / "index.html", headers={"Cache-Control": "no-store"}
        )

    for filename in ("styles.css", "script.js", "local_api.js", "operational.js"):

        def make_file_route(name):
            def file_route():
                return FileResponse(
                    frontend / name, headers={"Cache-Control": "no-store"}
                )

            return file_route

        application.add_api_route(
            f"/{filename}",
            make_file_route(filename),
            methods=["GET"],
            include_in_schema=False,
        )
    return application


app = create_app()
