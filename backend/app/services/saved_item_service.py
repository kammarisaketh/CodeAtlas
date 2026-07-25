from uuid import UUID, uuid4

from app.schemas.saved_items import SavedItemCreate, SavedItemRead


class SavedItemService:
    def __init__(self) -> None:
        self._items: dict[UUID, SavedItemRead] = {}

    def list_items(self) -> list[SavedItemRead]:
        return list(self._items.values())

    def create_item(self, request: SavedItemCreate) -> SavedItemRead:
        item = SavedItemRead(id=uuid4(), **request.model_dump())
        self._items[item.id] = item
        return item

    def delete_item(self, item_id: UUID) -> bool:
        return self._items.pop(item_id, None) is not None


saved_item_service = SavedItemService()

