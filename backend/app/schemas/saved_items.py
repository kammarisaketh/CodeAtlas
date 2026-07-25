from uuid import UUID

from pydantic import BaseModel, Field


class SavedItemCreate(BaseModel):
    repository_id: UUID | None = None
    kind: str = Field(pattern="^(answer|file|citation)$")
    title: str = Field(min_length=1, max_length=240)
    payload: dict = {}


class SavedItemRead(SavedItemCreate):
    id: UUID

