from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from shared.errors.exceptions import AppError


class UnexpectedErrorMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        try:
            await self.app(scope, receive, send)
        except AppError as exc:
            response = JSONResponse(
                status_code=exc.status_code,
                content={"detail": exc.message},
            )
            await response(scope, receive, send)
        except Exception:
            response = JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={"detail": "Erro interno do servidor."},
            )
            await response(scope, receive, send)


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.message},
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(_: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"detail": "Erro interno do servidor."},
        )
