from fastapi import APIRouter, HTTPException

from app.schemas.auth import AppleAuthRequest, RefreshRequest, TokenPair
from app.services.auth_service import AuthError, auth_service

router = APIRouter()


@router.post("/apple", response_model=TokenPair)
async def apple_auth(request: AppleAuthRequest) -> TokenPair:
    try:
        return auth_service.issue_tokens_for_apple_identity(request)
    except AuthError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


@router.post("/refresh", response_model=TokenPair)
async def refresh(request: RefreshRequest) -> TokenPair:
    try:
        return auth_service.refresh_tokens(request.refresh_token)
    except AuthError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


@router.post("/logout")
async def logout() -> dict[str, str]:
    return {"status": "logged_out"}
