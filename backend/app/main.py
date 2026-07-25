from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import api_router
from app.core.config import settings
from app.core.security import SecurityMiddleware


def create_app() -> FastAPI:
    app = FastAPI(
        title="CodeAtlas API",
        version="0.1.0",
        description="Repository-aware codebase memory and navigation API.",
    )
    app.add_middleware(SecurityMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["authorization", "content-type", "x-request-id"],
    )
    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health", tags=["system"])
    async def health() -> dict[str, str]:
        return {"status": "ok", "environment": settings.environment}

    @app.get("/health/ready", tags=["system"])
    async def readiness() -> dict[str, str]:
        return {
            "status": "ready",
            "environment": settings.environment,
            "storage": "in-memory" if settings.environment == "development" else "configured",
        }

    return app


app = create_app()
