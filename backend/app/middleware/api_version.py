"""API versioning middleware — adds version headers to all responses.

Helps clients detect when the API version changes (for backward compatibility
management) and provides request tracing via a correlation ID.
"""

import uuid
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

API_VERSION = "1.0.0"


class ApiVersionMiddleware(BaseHTTPMiddleware):
    """Adds standard API headers to every response.

    Headers added:
    - X-API-Version: the current API version
    - X-Request-Id: unique ID for this request (for tracing/debugging)
    - X-Response-Time: processing time in milliseconds
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = str(uuid.uuid4())[:8]
        start = time.time()

        response = await call_next(request)

        elapsed_ms = round((time.time() - start) * 1000, 1)
        response.headers["X-API-Version"] = API_VERSION
        response.headers["X-Request-Id"] = request_id
        response.headers["X-Response-Time"] = f"{elapsed_ms}ms"

        return response
