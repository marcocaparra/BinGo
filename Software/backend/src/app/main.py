from fastapi import FastAPI

from app.api.routes import router
from app.config.settings import settings
from shared.errors.handlers import register_error_handlers

app = FastAPI(title=settings.api_title, version="1.0.0")
register_error_handlers(app)
app.include_router(router, prefix=settings.api_prefix)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
