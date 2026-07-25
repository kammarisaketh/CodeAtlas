from uuid import UUID

from fastapi import APIRouter, HTTPException

from app.schemas.saved_items import SavedItemCreate, SavedItemRead
from app.services.saved_item_service import saved_item_service

router = APIRouter()


@router.get("", response_model=list[SavedItemRead])
async def list_saved_items() -> list[SavedItemRead]:
    return saved_item_service.list_items()


@router.post("", response_model=SavedItemRead, status_code=201)
async def create_saved_item(request: SavedItemCreate) -> SavedItemRead:
    return saved_item_service.create_item(request)


@router.delete("/{item_id}", status_code=204)
async def delete_saved_item(item_id: UUID) -> None:
    if not saved_item_service.delete_item(item_id):
        raise HTTPException(status_code=404, detail="Saved item not found")

