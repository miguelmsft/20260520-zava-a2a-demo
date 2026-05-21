"""Pydantic v2 models for the Zava backend HTTP / SSE contract.

These models define the wire format between the React frontend and the
FastAPI backend. They are intentionally permissive on the ``data`` payload
of :class:`AgentEvent` (a free-form ``dict``) so that we can evolve the
streaming event taxonomy without breaking older clients.
"""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Event-type taxonomy
# ---------------------------------------------------------------------------
# These literals are duplicated in the React types module (Step 13). Keep in
# sync. Adding a new type here is a non-breaking change for clients that
# treat unknown types defensively.
EventType = Literal[
    "status",      # informational / lifecycle (e.g., "connected", unknown SDK event)
    "text_delta",  # incremental assistant text token(s)
    "tool_call",   # local tool invocation (Code Interpreter, etc.)
    "a2a_hop",     # cross-agent A2A invocation lifecycle
    "chart",       # binary/image artifact produced by Code Interpreter
    "done",        # terminal success marker
    "error",       # terminal failure marker
]


class ChatRequest(BaseModel):
    """Inbound request body for ``POST /api/chat``.

    Mirrors the order-feasibility form fields rendered by the React UI.
    """

    sku: str = Field(..., description="Product SKU, e.g. 'ZP-7000'.")
    quantity: int = Field(..., ge=1, description="Units requested.")
    target_date: str = Field(
        ...,
        description="ISO-8601 date (YYYY-MM-DD) the customer wants the order by.",
    )
    customer_id: str = Field(..., description="Zava customer identifier.")
    conversation_id: Optional[str] = Field(
        default=None,
        description=(
            "Optional Foundry conversation id for multi-turn continuity. "
            "When omitted, the backend lets the Responses API mint a new one."
        ),
    )


class AgentEvent(BaseModel):
    """One event in the SSE stream emitted by ``POST /api/chat``.

    Serialized as JSON in the SSE ``data:`` field, one event per
    ``data: ...\\n\\n`` frame.
    """

    type: EventType
    data: dict[str, Any] = Field(default_factory=dict)


class HealthResponse(BaseModel):
    """Response body for ``GET /api/health``."""

    status: str = "ok"
    agent_name: str
