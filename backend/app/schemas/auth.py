from pydantic import BaseModel, Field


class AppleAuthRequest(BaseModel):
    identity_token: str = Field(min_length=10)
    authorization_code: str | None = None
    full_name: str | None = None


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20)

