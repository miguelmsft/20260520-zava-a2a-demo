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
import json
import logging
import re
import threading
from typing import Any, AsyncGenerator

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

from .artifacts import artifact_allowlist
from .config import settings
from .models import AgentEvent, ChatRequest

logger = logging.getLogger(__name__)

# Sentinel returned from the worker thread to signal end-of-stream without
# raising ``StopIteration`` across the thread boundary (which asyncio cannot
# propagate cleanly).
_STREAM_END = object()

# Cache of the resolved Foundry agent_reference payload keyed by agent name.
# Populated lazily on the first ``_open_stream`` call so we look up the
# agent's ``id`` exactly once per process. The ``id`` (in addition to
# ``name``) is required for traces emitted by the Responses API to surface
# under the agent's Traces tab in the Foundry portal.
#
# Per the azure-ai-projects README — Tracing section: "In order to view the
# traces in the Microsoft Foundry portal, the agent ID should be passed in
# as part of the response generation request."
# See research/2026-05-21-foundry-agent-traces.md §3.4.
_AGENT_REFERENCE_CACHE: dict[str, dict[str, str]] = {}
_AGENT_REFERENCE_LOCK = threading.Lock()

# Regex matching dict keys that may carry secrets. Any matching key is
# replaced with ``"***REDACTED***"`` before the value reaches the SSE stream.
_SENSITIVE_KEY_RE = re.compile(
    r"(authorization|api[-_]?key|x[-_]api[-_]?key|secret|password|token|bearer|cookie)",
    re.IGNORECASE,
)

# Cap how much of a free-form preview string we emit. Foundry payloads can
# include a few KB of prose; we keep the bubble readable and avoid bloating
# the SSE stream.
_PREVIEW_MAX_CHARS = 2000

# How deep to walk a nested payload before giving up. Defensive guard so a
# pathological cycle or very deep tree cannot stall the translator.
_WALK_MAX_DEPTH = 8


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


def _redact(obj: Any, _depth: int = 0) -> Any:
    """Recursively scrub sensitive keys before payload reaches the SSE wire.

    Walks dicts/lists and replaces any value whose key matches
    :data:`_SENSITIVE_KEY_RE` with the string ``"***REDACTED***"``. Non-dict
    primitives and SDK objects (which we cannot safely introspect) are
    returned as-is. Recursion is depth-capped to keep pathological inputs
    cheap.
    """

    if _depth > _WALK_MAX_DEPTH:
        return obj
    if isinstance(obj, dict):
        result: dict[str, Any] = {}
        for k, v in obj.items():
            if isinstance(k, str) and _SENSITIVE_KEY_RE.search(k):
                result[k] = "***REDACTED***"
            else:
                result[k] = _redact(v, _depth + 1)
        return result
    if isinstance(obj, list):
        return [_redact(item, _depth + 1) for item in obj]
    return obj


def _coerce_payload(value: Any) -> Any:
    """Best-effort normalize an SDK value into JSON-friendly Python.

    Strings that look like JSON are parsed; SDK objects with a
    ``model_dump`` (Pydantic) or ``__dict__`` get flattened. Anything else
    is returned untouched. Used for the ``arguments`` and ``output`` fields
    on the ``a2a_hop`` event so the frontend always sees plain
    dict/list/str/number/bool/None.
    """

    if value is None:
        return None
    if isinstance(value, (dict, list, int, float, bool)):
        return value
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith("{") or stripped.startswith("["):
            try:
                return json.loads(stripped)
            except (ValueError, TypeError):
                return value
        return value
    # Pydantic / azure-ai-projects model — try a structured dump first.
    dump = getattr(value, "model_dump", None)
    if callable(dump):
        try:
            return dump()  # type: ignore[no-any-return]
        except Exception:  # pragma: no cover - defensive
            pass
    if hasattr(value, "__dict__"):
        return {k: v for k, v in vars(value).items() if not k.startswith("_")}
    return value


def _walk_parts(payload: Any, _depth: int = 0) -> list[Any]:
    """Find the first ``parts`` list inside a nested A2A artifact payload.

    A2A's dual-part artifact (R16) nests the payload like::

        {"result": {"artifacts": [{"parts": [{kind: "text", ...},
                                             {kind: "data", ...}]}]}}

    SDK shapes vary across versions, so we walk dicts and lists looking
    for the deepest ``parts`` list we can find. Returns ``[]`` if none.
    """

    if _depth > _WALK_MAX_DEPTH:
        return []
    if isinstance(payload, dict):
        parts = payload.get("parts")
        if isinstance(parts, list) and parts:
            return parts
        for v in payload.values():
            found = _walk_parts(v, _depth + 1)
            if found:
                return found
    elif isinstance(payload, list):
        for item in payload:
            found = _walk_parts(item, _depth + 1)
            if found:
                return found
    return []


def _extract_a2a_previews(
    arguments: Any, output: Any
) -> tuple[str | None, dict[str, Any] | None]:
    """Extract a human-readable text preview and a structured data preview.

    For an **outbound** call (``a2a_preview_call``), the orchestrator's
    message to the worker is in ``arguments``. We return that as the text
    preview; no data preview is attempted.

    For an **inbound** call (``a2a_preview_call_output``), we look for the
    A2A dual-part artifact in ``output``: ``TextPart`` text becomes the
    text preview and ``DataPart`` data becomes the data preview. Falls
    back to stringifying ``output`` if no parts are found.

    The text preview is truncated at :data:`_PREVIEW_MAX_CHARS` to keep
    bubbles bounded.
    """

    text_preview: str | None = None
    data_preview: dict[str, Any] | None = None

    # ---- Try to extract A2A parts from whichever payload has them ----
    parts = _walk_parts(output) or _walk_parts(arguments)
    for part in parts:
        if not isinstance(part, dict):
            continue
        kind = part.get("kind") or part.get("type")
        if kind == "text" and text_preview is None:
            text = part.get("text") or part.get("content")
            if isinstance(text, str) and text.strip():
                text_preview = text.strip()
        elif kind == "data" and data_preview is None:
            data = part.get("data") or part.get("content")
            if isinstance(data, dict):
                data_preview = data

    # ---- Fallbacks if no structured parts were found ----
    if text_preview is None:
        # Outbound: arguments is typically a dict {"message": "..."} or a
        # plain string with the forwarded prompt.
        if isinstance(arguments, dict):
            for key in ("message", "text", "input", "content", "prompt"):
                value = arguments.get(key)
                if isinstance(value, str) and value.strip():
                    text_preview = value.strip()
                    break
            if text_preview is None:
                try:
                    text_preview = json.dumps(arguments, ensure_ascii=False)
                except (TypeError, ValueError):
                    text_preview = str(arguments)
        elif isinstance(arguments, str) and arguments.strip():
            text_preview = arguments.strip()
        elif isinstance(output, str) and output.strip():
            text_preview = output.strip()
        elif isinstance(output, dict):
            try:
                text_preview = json.dumps(output, ensure_ascii=False)
            except (TypeError, ValueError):
                text_preview = str(output)

    if text_preview is not None and len(text_preview) > _PREVIEW_MAX_CHARS:
        text_preview = text_preview[: _PREVIEW_MAX_CHARS - 1] + "…"

    return text_preview, data_preview


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

    # ---- Container-file citation annotation ---------------------------
    # Code Interpreter outputs (PNG charts, etc.) are emitted as a
    # ``response.output_text.annotation.added`` event whose ``annotation``
    # field is a ``container_file_citation`` carrying the (container_id,
    # file_id, filename) triple. We turn that into a ``chart`` event
    # pointing at our /api/files proxy so the React frontend can render
    # the image inline.
    if event_type == "response.output_text.annotation.added":
        annotation = _safe_getattr(event, "annotation", default=None)
        ann_type = _safe_getattr(annotation, "type", default="") or ""
        if ann_type == "container_file_citation":
            container_id = _safe_getattr(annotation, "container_id", default="") or ""
            file_id = _safe_getattr(annotation, "file_id", default="") or ""
            filename = _safe_getattr(annotation, "filename", default="") or ""
            ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
            if ext in {"png", "jpg", "jpeg", "webp", "gif"} and artifact_allowlist.register(
                container_id, file_id
            ):
                mime_type = {
                    "png": "image/png",
                    "jpg": "image/jpeg",
                    "jpeg": "image/jpeg",
                    "webp": "image/webp",
                    "gif": "image/gif",
                }[ext]
                return AgentEvent(
                    type="chart",
                    data={
                        "mime_type": mime_type,
                        "file_id": file_id,
                        "container_id": container_id,
                        "filename": filename,
                        "url": f"/api/files/{container_id}/{file_id}",
                    },
                )
        # Non-image or malformed citation — surface as status for debugging.
        return AgentEvent(
            type="status",
            data={
                "event": event_type,
                "annotation_type": ann_type or "unknown",
            },
        )

    # ---- Output items (tool calls, A2A hops, file artifacts) ----------
    # Both ``response.output_item.added`` and ``...done`` carry an ``item``
    # whose ``type`` distinguishes the sub-kind.
    if "output_item" in event_type:
        item = _safe_getattr(event, "item", default=None)
        item_type = _safe_getattr(item, "type", default="") or ""
        status = "started" if event_type.endswith("added") else "completed"

        # A2A invocation — Foundry GA emits ``a2a_preview_call`` (input) and
        # ``a2a_preview_call_output`` (response) output items when the agent
        # delegates to another agent via A2APreviewTool. Older Preview SDK
        # builds used ``remote_function_call`` — accept both so the demo
        # works against either flavor.
        if item_type in {
            "remote_function_call",
            "a2a_preview_call",
            "a2a_preview_call_output",
        }:
            # Pull the structured tool output when present (input items do
            # not carry it; output items do). The A2A SDK typically wraps
            # the worker's reply in an ``output``/``content`` list.
            output_payload = _safe_getattr(
                item, "output", "result", "response", "content", default=None,
            )
            raw_arguments = _safe_getattr(item, "arguments", default=None)

            # Normalize SDK objects / JSON-string blobs into plain Python so
            # the frontend never has to know about Pydantic models, and so
            # redaction can walk the tree.
            arguments_obj = _coerce_payload(raw_arguments)
            output_obj = _coerce_payload(output_payload)

            arguments_redacted = _redact(arguments_obj)
            output_redacted = _redact(output_obj)

            # Direction: input items go *to* the worker (outbound); output
            # items carry the reply *from* the worker (inbound). The legacy
            # ``remote_function_call`` only appears on the input side.
            direction = (
                "inbound" if item_type == "a2a_preview_call_output" else "outbound"
            )

            text_preview, data_preview = _extract_a2a_previews(
                arguments_redacted, output_redacted
            )

            return AgentEvent(
                type="a2a_hop",
                data={
                    "tool": _safe_getattr(item, "name", "label", default="a2a"),
                    "call_id": _safe_getattr(item, "id", "call_id", default=""),
                    "status": status,
                    "kind": item_type,
                    "direction": direction,
                    "peer_agent": "LangGraph Ops Agent",
                    "arguments": arguments_redacted,
                    "output": output_redacted,
                    "text_preview": text_preview,
                    "data_preview": data_preview,
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

        # Final assistant message — Foundry GA's Code Interpreter embeds
        # the chart as a ``sandbox:/mnt/data/...png`` markdown reference in
        # the message text, but the actual chart is delivered via a parallel
        # ``response.output_text.annotation.added`` event (handled above).
        # The sandbox reference itself is **not browser-fetchable**, so we
        # do NOT emit a chart event here; the frontend strips the literal
        # markdown so users see only the working inline chart.

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


def _resolve_agent_reference(
    project: AIProjectClient, agent_name: str
) -> dict[str, str]:
    """Return the ``agent_reference`` payload for ``responses.create()``.

    Looks up the latest version of the named prompt agent so the agent's
    ``id`` can be included alongside ``name``. The ``id`` is required for
    Responses-API traces to surface under the agent's Traces tab in the
    Foundry portal (per the azure-ai-projects README — Tracing section).

    Falls back to a name-only payload if the lookup fails (transient network
    error, RBAC, SDK version mismatch). The agent invocation still works,
    but the trace may surface under a generic ``chat`` span instead of
    ``invoke_agent <name>``.

    Result is cached at module scope so the lookup runs exactly once per
    process / agent name.
    """

    cached = _AGENT_REFERENCE_CACHE.get(agent_name)
    if cached is not None:
        return cached

    with _AGENT_REFERENCE_LOCK:
        cached = _AGENT_REFERENCE_CACHE.get(agent_name)
        if cached is not None:
            return cached

        ref: dict[str, str] = {"type": "agent_reference", "name": agent_name}
        try:
            versions = project.agents.list_versions(
                agent_name=agent_name, order="desc", limit=1
            )
            latest = next(iter(versions), None)
            if latest is not None and getattr(latest, "id", None):
                ref["id"] = latest.id
                logger.info(
                    "Resolved Foundry agent id for %r: %s (version=%s)",
                    agent_name,
                    latest.id,
                    getattr(latest, "version", "?"),
                )
            else:
                logger.warning(
                    "No versions found for Foundry agent %r — passing name only.",
                    agent_name,
                )
        except Exception as exc:  # noqa: BLE001 — best-effort lookup
            logger.warning(
                "Failed to resolve agent id for %r (%s: %s) — passing name only.",
                agent_name,
                type(exc).__name__,
                exc,
            )

        _AGENT_REFERENCE_CACHE[agent_name] = ref
        return ref


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
            "agent_reference": _resolve_agent_reference(
                project, settings.foundry_agent_name
            ),
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
