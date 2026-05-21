"""Starlette HTTP server that exposes the Zava Ops Agent over A2A.

Routes:
- ``GET  /health``                          — unauthenticated K8s liveness/readiness probe
- ``GET  /.well-known/agent-card.json``     — unauthenticated A2A discovery
- ``POST /``                                — authenticated A2A JSON-RPC endpoint

Authentication: a fail-secure ``ApiKeyAuthMiddleware`` reads the expected key
from the ``A2A_API_KEY`` environment variable at startup. If the variable is
unset or empty, the process exits non-zero (per plan R2 §F R17 — never run as
an open relay). All requests except ``/health`` and the agent-card discovery
endpoint must present a matching ``x-api-key`` header (compared with
``hmac.compare_digest`` for constant-time semantics).
"""

from __future__ import annotations

import hmac
import logging
import os
import sys
from typing import Iterable

import uvicorn
from a2a.server.agent_execution import SimpleRequestContextBuilder
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes.agent_card_routes import create_agent_card_routes
from a2a.server.routes.jsonrpc_routes import create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route

from .agent_card import build_agent_card
from .executor import ZavaOpsAgentExecutor

logger = logging.getLogger("zava.ops_agent.server")

API_KEY_ENV_VAR = "A2A_API_KEY"
API_KEY_HEADER = "x-api-key"

# Routes that bypass API-key auth: K8s probes need /health and A2A discovery
# clients (including Foundry) fetch the agent card before they hold a key.
# Foundry's A2A client probes the legacy ``/.well-known/agent.json`` path
# in addition to the newer ``agent-card.json`` — we serve both as aliases.
PUBLIC_PATHS: frozenset[str] = frozenset(
    {
        "/health",
        "/.well-known/agent-card.json",
        "/.well-known/agent.json",
    }
)


# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------


class ApiKeyAuthMiddleware(BaseHTTPMiddleware):
    """Constant-time API-key check on every non-public request.

    The expected key is captured at construction time; it must already have
    been validated as non-empty by the server boot path.
    """

    def __init__(self, app, expected_key: str, public_paths: Iterable[str]):
        super().__init__(app)
        self._expected_key_bytes = expected_key.encode("utf-8")
        self._public_paths = frozenset(public_paths)

    async def dispatch(self, request: Request, call_next):
        if request.url.path in self._public_paths:
            return await call_next(request)

        provided = request.headers.get(API_KEY_HEADER, "")
        if not provided or not hmac.compare_digest(
            provided.encode("utf-8"), self._expected_key_bytes
        ):
            return JSONResponse(
                {"error": "unauthorized"},
                status_code=401,
            )
        return await call_next(request)


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------


async def _health(_: Request) -> Response:
    return JSONResponse({"status": "ok"})


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------


def _require_api_key() -> str:
    """Fail-secure: refuse to start without ``A2A_API_KEY``."""
    key = os.environ.get(API_KEY_ENV_VAR, "").strip()
    if not key:
        # Use stderr explicitly so the message is visible even if logging
        # hasn't been configured yet.
        print(
            f"FATAL: {API_KEY_ENV_VAR} environment variable is unset or empty. "
            "Refusing to start (fail-secure). Set a non-empty API key and "
            "retry.",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(2)
    logger.info("%s configured, length=%d", API_KEY_ENV_VAR, len(key))
    return key


def build_app(api_key: str | None = None) -> Starlette:
    """Build the Starlette app with all routes and middleware wired."""
    if api_key is None:
        api_key = _require_api_key()

    agent_card = build_agent_card()
    handler = DefaultRequestHandler(
        agent_executor=ZavaOpsAgentExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
        request_context_builder=SimpleRequestContextBuilder(),
    )

    routes: list[Route] = []
    routes.extend(create_agent_card_routes(agent_card))
    # Foundry's A2A client probes the legacy ``/.well-known/agent.json``
    # path. Serve the same card at that URL too so discovery succeeds
    # regardless of which spec version the remote client implements.
    routes.extend(
        create_agent_card_routes(
            agent_card, card_url="/.well-known/agent.json"
        )
    )
    # ``enable_v0_3_compat=True`` lets the SDK auto-detect A2A v0.3 wire format
    # (when the ``A2A-Version`` header is absent) per research §3.8.
    routes.extend(
        create_jsonrpc_routes(handler, "/", enable_v0_3_compat=True)
    )
    routes.append(Route("/health", endpoint=_health, methods=["GET"]))

    middleware = [
        Middleware(
            ApiKeyAuthMiddleware,
            expected_key=api_key,
            public_paths=PUBLIC_PATHS,
        ),
    ]

    return Starlette(routes=routes, middleware=middleware)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    app = build_app()
    host = os.environ.get("OPS_AGENT_HOST", "0.0.0.0")  # nosec B104
    port = int(os.environ.get("OPS_AGENT_PORT", "9000"))
    logger.info("Starting Zava Ops Agent on %s:%d", host, port)
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":  # pragma: no cover
    main()


__all__ = ["build_app", "main", "ApiKeyAuthMiddleware"]
