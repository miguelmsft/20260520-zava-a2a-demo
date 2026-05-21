"""FastAPI entry point for the Zava Smart Order Feasibility backend.

Exposes:

* ``GET /api/health`` — liveness probe + agent name echo.
* ``POST /api/chat`` — Server-Sent Events stream of :class:`AgentEvent`
  objects produced by :func:`app.agent_client.invoke_agent`.

The SSE response sets ``Cache-Control: no-cache``, ``X-Accel-Buffering: no``,
and ``Connection: keep-alive`` to disable proxy buffering and keep the
stream interactive end-to-end (mitigation R11 in the plan).
"""

from __future__ import annotations

import json
import logging
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from .agent_client import invoke_agent
from .config import settings
from .models import AgentEvent, ChatRequest, HealthResponse

logger = logging.getLogger(__name__)

app = FastAPI(title="Zava A2A Demo Backend", version="0.1.0")

# The React dev server runs on Vite's default 5173. Production CORS will
# be tightened when the frontend is deployed (out of scope for this step).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _format_sse(event: AgentEvent) -> str:
    """Render an :class:`AgentEvent` as a single SSE frame.

    SSE frames are ``data: <payload>\\n\\n``. We use compact JSON to keep
    the wire format predictable on the React side.
    """

    payload = json.dumps(event.model_dump(), separators=(",", ":"))
    return f"data: {payload}\n\n"


@app.get("/api/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Liveness probe; also echoes the configured agent name."""

    return HealthResponse(status="ok", agent_name=settings.foundry_agent_name)


@app.post("/api/chat")
async def chat(request: ChatRequest) -> StreamingResponse:
    """Stream agent events as SSE for a single order-feasibility request."""

    async def event_source() -> AsyncGenerator[bytes, None]:
        # Initial status frame — useful for the UI to confirm the SSE
        # connection is live before the agent produces tokens.
        yield _format_sse(
            AgentEvent(type="status", data={"event": "connected"})
        ).encode("utf-8")
        try:
            async for event in invoke_agent(request):
                yield _format_sse(event).encode("utf-8")
        except Exception as exc:  # noqa: BLE001 — last-resort guard
            logger.exception("Unhandled error in /api/chat stream")
            yield _format_sse(
                AgentEvent(type="error", data={"message": str(exc)})
            ).encode("utf-8")

    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Connection": "keep-alive",
    }
    return StreamingResponse(
        event_source(),
        media_type="text/event-stream",
        headers=headers,
    )
