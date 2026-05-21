"""FastAPI entry point for the Zava Smart Order Feasibility backend.

Exposes:

* ``GET /api/health`` — liveness probe + agent name echo.
* ``POST /api/chat`` — Server-Sent Events stream of :class:`AgentEvent`
  objects produced by :func:`app.agent_client.invoke_agent`.
* ``GET /api/files/{container_id}/{file_id}`` — proxy that serves
  Code Interpreter chart bytes from the Foundry project's container files
  API. Access is gated by the in-memory allowlist populated when
  ``invoke_agent`` observes a ``container_file_citation`` annotation.

The SSE response sets ``Cache-Control: no-cache``, ``X-Accel-Buffering: no``,
and ``Connection: keep-alive`` to disable proxy buffering and keep the
stream interactive end-to-end (mitigation R11 in the plan).
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import AsyncGenerator

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse

from .agent_client import invoke_agent
from .artifacts import artifact_allowlist
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


def _download_container_file(container_id: str, file_id: str) -> tuple[bytes, str]:
    """Pull a single container-file's bytes from Foundry.

    Synchronous — designed to be invoked from a worker thread via
    :func:`asyncio.to_thread`. Returns ``(bytes, content_type)``.
    """
    project = AIProjectClient(
        endpoint=settings.foundry_project_endpoint,
        credential=DefaultAzureCredential(),
    )
    client = project.get_openai_client()
    resp = client.containers.files.content.retrieve(
        file_id, container_id=container_id
    )
    content_type = resp.headers.get("content-type") if hasattr(resp, "headers") else None
    return resp.content, content_type or "application/octet-stream"


@app.get("/api/files/{container_id}/{file_id}")
async def get_container_file(container_id: str, file_id: str) -> Response:
    """Proxy a Foundry container file's content for the React UI.

    Only ``(container_id, file_id)`` pairs the backend itself emitted
    during a recent ``/api/chat`` stream are served (see
    :mod:`app.artifacts`). This makes the endpoint a no-op for an
    attacker who fishes for random container IDs.
    """

    if not artifact_allowlist.is_allowed(container_id, file_id):
        # Same 404 whether the IDs are malformed or simply unknown — do
        # not leak whether a specific file exists.
        raise HTTPException(status_code=404, detail="not found")

    try:
        data, ctype_from_foundry = await asyncio.to_thread(
            _download_container_file, container_id, file_id
        )
    except Exception as exc:  # noqa: BLE001 — never surface raw SDK errors
        logger.exception("Failed to download container file %s/%s", container_id, file_id)
        raise HTTPException(status_code=502, detail="upstream fetch failed") from exc

    # Foundry sometimes returns ``application/octet-stream`` for PNGs;
    # detect a PNG by magic bytes and override so the browser renders it.
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        media_type = "image/png"
    elif data[:3] == b"\xff\xd8\xff":
        media_type = "image/jpeg"
    elif data[:4] == b"GIF8":
        media_type = "image/gif"
    elif data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        media_type = "image/webp"
    elif ctype_from_foundry and ctype_from_foundry.startswith("image/"):
        media_type = ctype_from_foundry
    else:
        media_type = "application/octet-stream"

    # Browser-only caching (``private``) — these files are derived from
    # the user's order context and should never be cached by shared
    # proxies. 1h aligns with the artifact-allowlist TTL.
    return Response(
        content=data,
        media_type=media_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )
