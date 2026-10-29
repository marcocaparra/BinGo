"""Fronteira de capacidade: única portadora da chave de máquina, sem API econômica."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
import httpx2 as httpx

from app.clients.supabase import CentralError
from app.dev_integration import (
    ALLOWED,
    KEY_FILE,
    POLICY_FILE,
    DevCentralClient,
    FunctionTransport,
    load_machine_key,
    load_policy,
    validate_environment,
)
from app.routes.dev import DevPin


def create_broker_app(*, policy_path=POLICY_FILE, key_path=KEY_FILE, transport=None):
    validate_environment()
    policy = load_policy(policy_path)
    key = load_machine_key(key_path)

    @asynccontextmanager
    async def lifespan(app):
        validate_environment()
        async with httpx.AsyncClient(
            transport=FunctionTransport(native=True, inner=transport),
            follow_redirects=False,
            trust_env=False,
        ) as http:
            app.state.central = DevCentralClient(http, policy, machine_key=key)
            yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.exception_handler(CentralError)
    @app.exception_handler(RequestValidationError)
    async def error(request, exc):
        return JSONResponse(
            {
                "error": {
                    "code": exc.code
                    if isinstance(exc, CentralError)
                    else "INVALID_LOCAL_CONTRACT",
                    "message": "Operação DEV recusada.",
                }
            },
            status_code=exc.http_status if isinstance(exc, CentralError) else 422,
            headers={"Cache-Control": "no-store"},
        )

    @app.middleware("http")
    async def boundary(request: Request, next_call):
        path = request.url.path
        if path == "/health" and request.method == "GET" and not request.url.query:
            return await next_call(request)
        if (
            (request.method, path) not in ALLOWED
            or request.scope["raw_path"] != path.encode("ascii")
            or request.url.query
            or request.headers.get("X-Totem-Dev") != "1"
            or any(
                name in request.headers
                for name in ("authorization", "x-api-key", "x-machine-id")
            )
            or request.method == "POST"
            and request.headers.get("content-type", "").split(";")[0]
            != "application/json"
        ):
            return JSONResponse(
                {
                    "error": {
                        "code": "DEV_CAPABILITY_DENIED",
                        "message": "Operação DEV recusada.",
                    }
                },
                status_code=403,
                headers={"Cache-Control": "no-store"},
            )
        response = await next_call(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/health")
    async def liveness():
        return {"status": "ok"}

    @app.get("/functions/v1/health-v1")
    async def health(request: Request):
        outcome = await request.app.state.central.check_health()
        from datetime import datetime, timezone

        status = (
            200
            if outcome.available
            else 401
            if outcome.outcome == "AUTHENTICATION_FAILED"
            else 503
        )
        return JSONResponse(
            {
                "status": "AVAILABLE" if outcome.available else "UNAVAILABLE",
                "can_start_deposit": outcome.available,
                "scope": "CENTRAL_BACKEND",
                "checked_at": datetime.now(timezone.utc).isoformat(),
            },
            status_code=status,
        )

    @app.get("/functions/v1/totem-context-v1")
    async def context(request: Request):
        return await request.app.state.central.context()

    @app.post("/functions/v1/totem-student-pin-v1")
    async def pin(request: Request, body: DevPin):
        return await request.app.state.central.verify_pin(
            body.class_id, body.student_id, body.pin
        )

    return app
