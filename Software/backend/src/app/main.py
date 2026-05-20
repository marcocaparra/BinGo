from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router
from app.config.settings import settings
from shared.errors.handlers import UnexpectedErrorMiddleware, register_error_handlers

app = FastAPI(title=settings.api_title, version="1.0.0")

app.add_middleware(UnexpectedErrorMiddleware)

# CORS restrito a origens locais usadas pelo simulador de desenvolvimento.
# Não ampliar para "*" em produção.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5500",
        "http://127.0.0.1:5500",
        "http://localhost:8001",
        "http://127.0.0.1:8001",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Machine-Id", "X-Api-Key"],
)

register_error_handlers(app)
app.include_router(router, prefix=settings.api_prefix)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
