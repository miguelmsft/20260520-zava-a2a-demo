"""A2A AgentExecutor that bridges the Zava LangGraph graph to the A2A server.

The executor is invoked by ``DefaultRequestHandler`` once per incoming
``message/send`` request. Its job is:

1. Pull the user's text out of the inbound A2A message parts.
2. Drive the LangGraph graph (``app.agent.graph``).
3. Translate the graph's final assistant message into A2A events:
   - ``TaskStatusUpdateEvent(WORKING)`` while we work
   - ``TaskArtifactUpdateEvent`` with both a structured ``DataPart``
     (parsed feasibility JSON, if present) and a ``TextPart``
     (natural-language recommendation) so the orchestrator can consume either
     form (addresses plan R2 §F R16).
   - ``TaskStatusUpdateEvent(COMPLETED)`` to terminate the task.

If the graph raises, we publish ``TaskStatusUpdateEvent(FAILED)`` with the
error message and re-raise so the framework sees the failure.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Any

from a2a.helpers import (
    get_message_text,
    new_data_part,
    new_task,
    new_text_part,
)
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import TaskState

from .agent import graph

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _extract_user_text(context: RequestContext) -> str:
    """Concatenate all text parts from the inbound A2A message."""
    if context.message is None:
        return ""
    try:
        return get_message_text(context.message)
    except Exception:  # pragma: no cover - defensive
        # Fallback: walk parts manually
        parts = list(context.message.parts) if context.message.parts else []
        return "\n".join(p.text for p in parts if p.HasField("text"))


def _final_assistant_text(graph_result: dict[str, Any]) -> str:
    """Pull the last assistant message's textual content from the graph state."""
    messages = graph_result.get("messages") or []
    if not messages:
        return ""
    last = messages[-1]
    content = getattr(last, "content", None)
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        # LangChain content can be a list of dicts {type: text, text: ...}
        chunks = []
        for item in content:
            if isinstance(item, dict) and "text" in item:
                chunks.append(str(item["text"]))
            elif isinstance(item, str):
                chunks.append(item)
        return "\n".join(chunks)
    return str(content) if content is not None else ""


_JSON_OBJECT_RE = re.compile(r"\{.*\}", re.DOTALL)


def _try_parse_feasibility(text: str) -> dict[str, Any] | None:
    """Best-effort: extract a JSON object from the assistant's response.

    The system prompt instructs the LLM to emit a single JSON object describing
    the feasibility result. We try strict ``json.loads`` first, then fall back
    to a regex grab of the largest brace-delimited block.
    """
    if not text:
        return None
    stripped = text.strip()
    # Strip common ```json fences
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
        stripped = re.sub(r"\s*```$", "", stripped)
    try:
        candidate = json.loads(stripped)
        if isinstance(candidate, dict):
            return candidate
    except json.JSONDecodeError:
        pass
    match = _JSON_OBJECT_RE.search(stripped)
    if match:
        try:
            candidate = json.loads(match.group(0))
            if isinstance(candidate, dict):
                return candidate
        except json.JSONDecodeError:
            return None
    return None


# ---------------------------------------------------------------------------
# Executor
# ---------------------------------------------------------------------------


class ZavaOpsAgentExecutor(AgentExecutor):
    """Adapt the LangGraph graph to the A2A AgentExecutor contract."""

    async def execute(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        task_id = context.task_id or uuid.uuid4().hex
        context_id = context.context_id or uuid.uuid4().hex

        updater = TaskUpdater(
            event_queue=event_queue,
            task_id=task_id,
            context_id=context_id,
        )

        # The framework requires a Task object on the queue before any
        # TaskStatusUpdateEvent / TaskArtifactUpdateEvent. If this is the
        # first turn for this task, enqueue one.
        if context.current_task is None:
            await event_queue.enqueue_event(
                new_task(
                    task_id=task_id,
                    context_id=context_id,
                    state=TaskState.TASK_STATE_SUBMITTED,
                )
            )

        # Signal we've started working.
        await updater.start_work(
            message=updater.new_agent_message(
                parts=[
                    new_text_part("Querying inventory and capacity..."),
                ]
            )
        )

        user_text = _extract_user_text(context)
        logger.info(
            "ops-agent.execute: task_id=%s context_id=%s user_text_len=%d",
            task_id,
            context_id,
            len(user_text),
        )

        try:
            result = await graph.ainvoke(
                {"messages": [{"role": "user", "content": user_text}]}
            )
        except Exception as exc:
            logger.exception("ops-agent.graph_invocation_failed")
            await updater.update_status(
                state=TaskState.TASK_STATE_FAILED,
                message=updater.new_agent_message(
                    parts=[new_text_part(f"Agent error: {exc}")]
                ),
            )
            raise

        assistant_text = _final_assistant_text(result)
        # Prefer the canonical feasibility computed by the graph
        # (Phase 4 fix B2 — deterministic compute_feasibility node).
        # Fall back to parsing the assistant text if the graph state is
        # missing it (defensive for older code paths and tests).
        feasibility = result.get("feasibility") or {}
        if not feasibility:
            feasibility = _try_parse_feasibility(assistant_text) or {}

        artifact_parts = []
        if feasibility:
            artifact_parts.append(
                new_data_part(feasibility, media_type="application/json")
            )
        # Always include a text part so even non-JSON-aware clients see a
        # human-readable summary.
        artifact_parts.append(new_text_part(assistant_text or ""))

        artifact_id = f"art-fea-{uuid.uuid4().hex[:12]}"
        await updater.add_artifact(
            parts=artifact_parts,
            artifact_id=artifact_id,
            name="order-feasibility",
            last_chunk=True,
        )

        await updater.complete()

    async def cancel(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        raise NotImplementedError(
            "Cancellation is not supported by this agent."
        )


__all__ = ["ZavaOpsAgentExecutor"]
