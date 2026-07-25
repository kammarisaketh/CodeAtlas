from __future__ import annotations

from collections import defaultdict, deque
from time import monotonic
from uuid import uuid4

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import JSONResponse, Response

from app.core.config import settings


class SecurityMiddleware(BaseHTTPMiddleware):
    def __init__(self, app) -> None:  # type: ignore[no-untyped-def]
        super().__init__(app)
        self._requests: dict[str, deque[float]] = defaultdict(deque)

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("x-request-id", str(uuid4()))
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > settings.max_request_bytes:
            return self._json_error("Request body is too large.", 413, request_id)

        client_key = request.client.host if request.client else "unknown"
        if self._is_rate_limited(client_key):
            return self._json_error("Rate limit exceeded. Try again shortly.", 429, request_id)

        response = await call_next(request)
        self._apply_security_headers(response, request_id)
        return response

    def _is_rate_limited(self, client_key: str) -> bool:
        now = monotonic()
        window_start = now - 60
        timestamps = self._requests[client_key]
        while timestamps and timestamps[0] < window_start:
            timestamps.popleft()
        if len(timestamps) >= settings.rate_limit_requests_per_minute:
            return True
        timestamps.append(now)
        return False

    def _json_error(self, detail: str, status_code: int, request_id: str) -> JSONResponse:
        response = JSONResponse({"detail": detail, "request_id": request_id}, status_code=status_code)
        self._apply_security_headers(response, request_id)
        return response

    def _apply_security_headers(self, response: Response, request_id: str) -> None:
        response.headers["x-request-id"] = request_id
        response.headers["x-content-type-options"] = "nosniff"
        response.headers["referrer-policy"] = "no-referrer"
        response.headers["cache-control"] = "no-store"
        response.headers["permissions-policy"] = "camera=(), microphone=(), geolocation=()"
