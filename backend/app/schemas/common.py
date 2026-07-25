from pydantic import BaseModel


class APIError(BaseModel):
    code: str
    message: str
    request_id: str | None = None


class ErrorEnvelope(BaseModel):
    error: APIError

