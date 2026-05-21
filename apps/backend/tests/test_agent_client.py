"""Smoke tests for the backend models and SSE classification.

Integration tests that exercise the real Foundry endpoint are marked with
``@pytest.mark.integration`` and skipped by default. They require a deployed
Foundry agent and valid Azure credentials and are out of scope for this
unit-test pass.
"""

from __future__ import annotations

import os

# Allow the test process to import ``app.*`` without a real Foundry endpoint.
os.environ.setdefault("DEV_MODE", "true")

import pytest  # noqa: E402

from app.agent_client import _build_user_message, _classify_event  # noqa: E402
from app.models import AgentEvent, ChatRequest, HealthResponse  # noqa: E402


# ---------------------------------------------------------------------------
# Pydantic round-trip
# ---------------------------------------------------------------------------


def test_chat_request_model_roundtrip() -> None:
    payload = {
        "sku": "ZP-7000",
        "quantity": 50,
        "target_date": "2026-07-15",
        "customer_id": "CUST-001",
    }
    req = ChatRequest.model_validate(payload)
    assert req.sku == "ZP-7000"
    assert req.quantity == 50
    assert req.conversation_id is None
    # Round-trip preserves all fields.
    assert ChatRequest.model_validate(req.model_dump()) == req


def test_chat_request_quantity_must_be_positive() -> None:
    with pytest.raises(Exception):
        ChatRequest.model_validate(
            {
                "sku": "ZP-7000",
                "quantity": 0,
                "target_date": "2026-07-15",
                "customer_id": "CUST-001",
            }
        )


# ---------------------------------------------------------------------------
# Event-type taxonomy
# ---------------------------------------------------------------------------


def test_models_event_types() -> None:
    """Every documented Literal value must be accepted by AgentEvent."""

    for t in (
        "status",
        "text_delta",
        "tool_call",
        "a2a_hop",
        "chart",
        "done",
        "error",
    ):
        evt = AgentEvent(type=t, data={"k": "v"})
        assert evt.type == t
        assert evt.data == {"k": "v"}


def test_models_event_rejects_unknown_type() -> None:
    with pytest.raises(Exception):
        AgentEvent(type="not_a_real_type", data={})  # type: ignore[arg-type]


def test_health_response_default_status() -> None:
    h = HealthResponse(agent_name="zava-customer-service")
    assert h.status == "ok"
    assert h.agent_name == "zava-customer-service"


# ---------------------------------------------------------------------------
# User-message construction
# ---------------------------------------------------------------------------


def test_build_user_message_includes_all_fields() -> None:
    req = ChatRequest(
        sku="ZP-7000",
        quantity=50,
        target_date="2026-07-15",
        customer_id="CUST-001",
    )
    msg = _build_user_message(req)
    assert "ZP-7000" in msg
    assert "50" in msg
    assert "2026-07-15" in msg
    assert "CUST-001" in msg


# ---------------------------------------------------------------------------
# Stream-event classification (duck-typed input)
# ---------------------------------------------------------------------------


class _Obj:
    """Lightweight stand-in for SDK event objects (attribute-bag)."""

    def __init__(self, **kw: object) -> None:
        for k, v in kw.items():
            setattr(self, k, v)


def test_classify_text_delta() -> None:
    evt = _classify_event(_Obj(type="response.output_text.delta", delta="Hello"))
    assert evt.type == "text_delta"
    assert evt.data["text"] == "Hello"


def test_classify_a2a_hop() -> None:
    item = _Obj(type="remote_function_call", id="call_123", name="ops_agent")
    evt = _classify_event(_Obj(type="response.output_item.added", item=item))
    assert evt.type == "a2a_hop"
    assert evt.data["call_id"] == "call_123"
    assert evt.data["status"] == "started"


def test_classify_tool_call_done() -> None:
    item = _Obj(type="code_interpreter_call", id="ci_1")
    evt = _classify_event(_Obj(type="response.output_item.done", item=item))
    assert evt.type == "tool_call"
    assert evt.data["status"] == "completed"


def test_classify_chart_image() -> None:
    item = _Obj(type="image_file", file_id="file_abc", mime_type="image/png")
    evt = _classify_event(_Obj(type="response.output_item.done", item=item))
    assert evt.type == "chart"
    assert evt.data["file_id"] == "file_abc"
    assert evt.data["mime_type"] == "image/png"


def test_classify_done() -> None:
    evt = _classify_event(_Obj(type="response.completed"))
    assert evt.type == "done"


def test_classify_unknown_falls_back_to_status() -> None:
    evt = _classify_event(_Obj(type="response.some_future_event"))
    assert evt.type == "status"
    assert evt.data["event"] == "response.some_future_event"


# ---------------------------------------------------------------------------
# Integration-only (skipped by default; run with ``-m integration``)
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_invoke_agent_against_real_foundry() -> None:  # pragma: no cover
    """Placeholder for a future end-to-end test against a deployed agent."""
    pytest.skip("Requires deployed Foundry agent; out of scope for unit tests.")
