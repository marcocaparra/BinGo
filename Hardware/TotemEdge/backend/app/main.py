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
from app.mechanical import MechanicalController
from app.routes import health, local, sessions
from app.services.capture import CaptureService
from app.services.controller import UnavailableController
from app.services.mechanical import MechanicalService
from app.services.sessions import SessionService
from app.services.status import LocalStatusService
from app.services.vision import build_internal_vision
from app.storage import CycleStore


def create_app(
    *,
    transport: httpx.AsyncBaseTransport | None = None,
    controller_factory: Callable[[], MechanicalController] | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(application: FastAPI):
        sqlite_path = Path(
            os.getenv(
                "BINGO_SQLITE_PATH",
                str(Path(__file__).resolve().parents[1] / ".data/totem.sqlite3"),
            )
        )
        store = CycleStore(sqlite_path)
        try:
            controller = (
                controller_factory() if controller_factory else UnavailableController()
            )
            mechanical = MechanicalService(
                store,
                controller,
                source="UNAVAILABLE"
                if isinstance(controller, UnavailableController)
                else "SIMULATED",
            )
            try:
                application.state.controller = controller
                application.state.mechanical = mechanical
                async with httpx.AsyncClient(
                    transport=transport, follow_redirects=False, trust_env=False
                ) as http_client:
                    central = SupabaseEdgeClient(http_client)
                    status = LocalStatusService(central)
                    application.state.status_service = status
                    application.state.sessions = SessionService(store, central, status)
                    # Serviços privados, desconectados da autorização física.
                    application.state.vision = build_internal_vision(http_client)
                    application.state.capture = CaptureService(store)
                    yield
            finally:
                await mechanical.aclose()
        finally:
            store.close()

    application = FastAPI(title="BinGo Totem Edge", lifespan=lifespan)
    application.include_router(health.router)
    application.include_router(local.router)
    application.include_router(sessions.router)

    @application.exception_handler(CycleError)
    @application.exception_handler(CentralError)
    async def safe_error(request: Request, error):
        status = error.status if isinstance(error, CycleError) else error.http_status
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
            ("/local/sessions", "/local/context", "/assets/")
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
