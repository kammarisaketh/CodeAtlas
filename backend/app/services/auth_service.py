from datetime import UTC, datetime, timedelta

import httpx
from jose import JWTError, jwt

from app.core.config import settings
from app.schemas.auth import AppleAuthRequest, TokenPair


class AuthError(Exception):
    pass


class AuthService:
    _apple_keys: list[dict] | None = None

    def issue_tokens_for_apple_identity(self, request: AppleAuthRequest) -> TokenPair:
        payload = self._verify_apple_identity_token(request.identity_token)
        subject = f"apple:{payload['sub']}"
        return self._issue_token_pair(subject)

    def refresh_tokens(self, refresh_token: str) -> TokenPair:
        try:
            payload = jwt.decode(
                refresh_token,
                settings.jwt_secret,
                algorithms=["HS256"],
                issuer=settings.jwt_issuer,
                audience=settings.jwt_audience,
            )
        except JWTError as error:
            raise AuthError("Invalid refresh token.") from error

        if payload.get("typ") != "refresh":
            raise AuthError("Expected a refresh token.")
        subject = payload.get("sub")
        if not isinstance(subject, str) or not subject:
            raise AuthError("Refresh token is missing a subject.")
        return self._issue_token_pair(subject)

    def _issue_token_pair(self, subject: str) -> TokenPair:
        now = datetime.now(UTC)
        access_expires = now + timedelta(minutes=settings.access_token_minutes)
        refresh_expires = now + timedelta(days=settings.refresh_token_days)
        access_token = jwt.encode(
            {
                "sub": subject,
                "iss": settings.jwt_issuer,
                "aud": settings.jwt_audience,
                "exp": access_expires,
                "iat": now,
                "typ": "access",
            },
            settings.jwt_secret,
            algorithm="HS256",
        )
        refresh_token = jwt.encode(
            {
                "sub": subject,
                "iss": settings.jwt_issuer,
                "aud": settings.jwt_audience,
                "exp": refresh_expires,
                "iat": now,
                "typ": "refresh",
            },
            settings.jwt_secret,
            algorithm="HS256",
        )
        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=settings.access_token_minutes * 60,
        )

    def _verify_apple_identity_token(self, identity_token: str) -> dict:
        if settings.environment == "development" and identity_token.startswith("mock-"):
            return {"sub": identity_token[-12:], "email": "demo@codeatlas.local"}
        if not settings.apple_audience:
            raise AuthError("Apple Sign In is not configured. Set CODEATLAS_APPLE_AUDIENCE.")

        try:
            header = jwt.get_unverified_header(identity_token)
        except JWTError as error:
            raise AuthError("Invalid Apple identity token header.") from error

        key = self._apple_public_key(header.get("kid"))
        try:
            payload = jwt.decode(
                identity_token,
                key,
                algorithms=["RS256"],
                audience=settings.apple_audience,
                issuer="https://appleid.apple.com",
            )
        except JWTError as error:
            raise AuthError("Invalid Apple identity token.") from error

        if not isinstance(payload.get("sub"), str):
            raise AuthError("Apple identity token is missing a subject.")
        return payload

    def _apple_public_key(self, key_id: str | None) -> dict:
        if not key_id:
            raise AuthError("Apple identity token is missing a key id.")
        keys = self._apple_keys
        if keys is None:
            response = httpx.get("https://appleid.apple.com/auth/keys", timeout=10)
            response.raise_for_status()
            keys = response.json().get("keys", [])
            self._apple_keys = keys
        key = next((item for item in keys if item.get("kid") == key_id), None)
        if key is None:
            self._apple_keys = None
            response = httpx.get("https://appleid.apple.com/auth/keys", timeout=10)
            response.raise_for_status()
            keys = response.json().get("keys", [])
            self._apple_keys = keys
            key = next((item for item in keys if item.get("kid") == key_id), None)
        if key is None:
            raise AuthError("Apple public key was not found for this token.")
        return key


auth_service = AuthService()
