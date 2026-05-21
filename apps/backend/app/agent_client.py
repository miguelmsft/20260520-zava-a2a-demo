"""Foundry V2 agent invocation + SSE event mapping.

The :func:`invoke_agent` async generator is the bridge between the FastAPI
SSE endpoint and the Foundry V2 Responses API. It:

1. Builds a Foundry-compatible OpenAI client from the project endpoint
   using ``AIProjectClient.get_openai_client(...)``.
2. Calls ``openai.responses.create(stream=True, ...)`` with the
   ``agent_reference`` extra-body that targets a deployed Foundry Agent
   (V2). The agent itself owns the system prompt, tools (Code Interpreter,
   A2APreviewTool to the Ops agent), and model deployment.
3. Iterates the streaming response and translates Responses API stream
   events into our smaller :class:`~app.models.AgentEvent` taxonomy.

Streaming bridge
----------------
``azure-ai-projects`` 2.1.0 returns a **synchronous** ``openai.OpenAI``
instance from :meth:`AIProjectClient.get_openai_client`. To keep the
FastAPI request handler non-blocking, the synchronous stream iterator is
driven from a background thread via :func:`asyncio.to_thread`. We pull
one event at a time using ``next()`` so we can interleave yields back to
the SSE consumer without buffering the whole response.

Defensive event handling
------------------------
The exact attribute / type names emitted by ``openai.responses.create``
have shifted between SDK versions. Rather than hard-code attribute paths,
we duck-type each event: we look for the ``type`` attribute, then for
common payload fields (``delta``, ``item``, ``response``, etc.). Anything
we don't recognize is forwarded as a ``status`` event so the demo can
surface unknown types in the UI / logs for diagnosis.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, AsyncGenerator

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

from .config import settings
from .models import AgentEvent, ChatRequest

logger = logging.getLogger(__name__)

# Sentinel returned from the worker thread to signal end-of-stream without
# raising ``StopIteration`` across the thread boundary (which asyncio cannot
# propagate cleanly).
_STREAM_END = object()


def _build_user_message(request: ChatRequest) -> str:
    """Render the ChatRequest as a single natural-language user message.

    The Foundry agent's system prompt (defined in Step 11) instructs it on
    how to parse this structured-but-textual input.
    """

    return (
        "Check feasibility for the following order:\n"
        f"- SKU: {request.sku}\n"
        f"- Quantity: {request.quantity}\n"
        f"- Target date: {request.target_date}\n"
        f"- Customer ID: {request.customer_id}"
    )


def _safe_getattr(obj: Any, *names: str, default: Any = None) -> Any:
    """Return the first present attribute (or dict key) from ``names``."""

    for name in names:
        if obj is None:
            return default
        if isinstance(obj, dict):
            if name in obj:
                return obj[name]
        elif hasattr(obj, name):
            value = getattr(obj, name)
            if value is not None:
                return value
    return default


def _classify_event(event: Any) -> AgentEvent:
    """Translate one Responses API stream event into an :class:`AgentEvent`.

    Unknown event shapes degrade gracefully into ``status`` events.
    """

    event_type = _safe_getattr(event, "type", default="") or ""

    # ---- Incremental assistant text -----------------------------------
    # ``response.output_text.delta`` carries a ``delta`` string field.
    if event_type.endswith("output_text.delta"):
        delta = _safe_getattr(event, "delta", default="") or ""
        return AgentEvent(type="text_delta", data={"text": delta})

    # ---- Output items (tool calls, A2A hops, file artifacts) ----------
    # Both ``response.output_item.added`` and ``...done`` carry an ``item``
    # whose ``type`` distinguishes the sub-kind.
    if "output_item" in event_type:
        item = _safe_getattr(event, "item", default=None)
        item_type = _safe_getattr(item, "type", default="") or ""
        status = "started" if event_type.endswith("added") else "completed"

        # A2A invocation — Foundry surfaces these as ``remote_function_call``
        # output items when the agent calls another agent via A2APreviewTool.
        if item_type == "remote_function_call":
            return AgentEvent(
                type="a2a_hop",
                data={
                    "tool": _safe_getattr(item, "name", "label", default="a2a"),
                    "call_id": _safe_getattr(item, "id", "call_id", default=""),
                    "status": status,
                    "arguments": _safe_getattr(item, "arguments", default=None),
                },
            )

        # Code Interpreter / generic tool call.
        if item_type in {"tool_call", "code_interpreter_call"}:
            return AgentEvent(
                type="tool_call",
                data={
                    "tool": _safe_getattr(item, "name", default=item_type),
                    "call_id": _safe_getattr(item, "id", "call_id", default=""),
                    "status": status,
                },
            )

        # File / image artifact produced by Code Interpreter.
        if item_type in {"image_file", "image", "file"}:
            return AgentEvent(
                type="chart",
                data={
                    "mime_type": _safe_getattr(item, "mime_type", default="image/png"),
                    "file_id": _safe_getattr(item, "file_id", "id", default=""),
                    "url": _safe_getattr(item, "url", default=None),
                    "data_b64": _safe_getattr(item, "data_b64", "b64_json", default=None),
                },
            )

        # Unknown item kind — surface as status for debugging.
        return AgentEvent(
            type="status",
            data={"event": event_type, "item_type": item_type},
        )

    # ---- Lifecycle markers --------------------------------------------
    if event_type in {"response.created", "response.in_progress"}:
        return AgentEvent(type="status", data={"event": event_type})

    if event_type in {"response.completed", "response.done"}:
        return AgentEvent(type="done", data={"event": event_type})

    if "error" in event_type:
        message = _safe_getattr(event, "message", default=None)
        if message is None:
            err = _safe_getattr(event, "error", default=None)
            message = _safe_getattr(err, "message", default=str(err) if err else "unknown error")
        return AgentEvent(type="error", data={"message": str(message)})

    # ---- Anything else -------------------------------------------------
    logger.debug("Unmapped Responses API event: %s", event_type)
    return AgentEvent(type="status", data={"event": event_type or "unknown"})


def _open_stream(request: ChatRequest):
    """Open a synchronous Foundry Responses stream and return its iterator.

    Runs in a worker thread (see :func:`invoke_agent`) because both the
    ``azure-ai-projects`` client and the returned ``openai.OpenAI`` are
    synchronous.
    """

    user_message = _build_user_message(request)
    project = AIProjectClient(
        endpoint=settings.foundry_project_endpoint,
        credential=DefaultAzureCredential(),
    )
    # ``get_openai_client`` returns a fully-configured ``openai.OpenAI``
    # (not ``AzureOpenAI``) whose ``base_url`` and bearer-token auth target
    # the Foundry project's ``/openai/v1`` endpoint.
    #
    # Foundry V2 GA rejects an explicit ``api-version`` query parameter on
    # the ``/v1`` path (returns 400 "api-version query parameter is not
    # allowed when using /v1 path"). Only pass it when the operator
    # explicitly sets ``FOUNDRY_OPENAI_API_VERSION``; otherwise omit it and
    # rely on the GA defaults.
    if settings.foundry_openai_api_version:
        openai_client = project.get_openai_client(
            default_query={"api-version": settings.foundry_openai_api_version},
        )
    else:
        openai_client = project.get_openai_client()

    create_kwargs: dict[str, Any] = {
        "model": settings.foundry_orchestrator_deployment,
        "input": user_message,
        "stream": True,
        "extra_body": {
            "agent_reference": {
                "type": "agent_reference",
                "name": settings.foundry_agent_name,
            },
        },
    }
    if request.conversation_id:
        create_kwargs["conversation"] = request.conversation_id

    stream = openai_client.responses.create(**create_kwargs)
    return iter(stream)


async def invoke_agent(request: ChatRequest) -> AsyncGenerator[AgentEvent, None]:
    """Yield :class:`AgentEvent` instances for one Foundry agent invocation.

    Always yields a terminal ``done`` or ``error`` event before returning,
    so SSE consumers can reliably detect end-of-stream.
    """

    # Open the stream in a worker thread so the synchronous SDK does not
    # block the event loop.
    try:
        stream_iter = await asyncio.to_thread(_open_stream, request)
    except Exception as exc:  # noqa: BLE001 — surface any startup failure
        logger.exception("Failed to open Foundry response stream")
        yield AgentEvent(type="error", data={"message": f"open_stream: {exc}"})
        return

    def _next_event() -> Any:
        """Pull a single event; return ``_STREAM_END`` on exhaustion."""
        try:
            return next(stream_iter)
        except StopIteration:
            return _STREAM_END

    saw_done = False
    try:
        while True:
            event = await asyncio.to_thread(_next_event)
            if event is _STREAM_END:
                break
            mapped = _classify_event(event)
            if mapped.type == "done":
                saw_done = True
            yield mapped
            if mapped.type == "error":
                # Treat error as terminal — don't keep pulling.
                return
    except Exception as exc:  # noqa: BLE001
        logger.exception("Foundry response stream raised")
        yield AgentEvent(type="error", data={"message": f"stream: {exc}"})
        return

    if not saw_done:
        # Synthesize a terminal marker so the client can finalize the UI.
        yield AgentEvent(type="done", data={"event": "stream_closed"})
