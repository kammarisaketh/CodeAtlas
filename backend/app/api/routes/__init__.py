from fastapi import APIRouter

from app.api.routes import auth, repositories, saved_items

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(repositories.router, prefix="/repositories", tags=["repositories"])
api_router.include_router(saved_items.router, prefix="/saved-items", tags=["saved-items"])

