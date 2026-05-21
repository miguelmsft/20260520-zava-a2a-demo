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

from app.agent_client import (  # noqa: E402
    _build_user_message,
    _classify_event,
    _coerce_payload,
    _extract_a2a_previews,
    _redact,
)
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
    # Phase-8 enrichment: every A2A hop carries direction + peer name.
    assert evt.data["direction"] == "outbound"
    assert evt.data["peer_agent"] == "LangGraph Ops Agent"


def test_classify_a2a_preview_call_outbound_text_preview() -> None:
    """``a2a_preview_call`` (input) yields outbound + text preview of args."""

    item = _Obj(
        type="a2a_preview_call",
        id="call_outbound_1",
        name="ops_agent",
        arguments='{"message": "Check feasibility for SKU ZP-7000, qty 150."}',
    )
    evt = _classify_event(_Obj(type="response.output_item.done", item=item))
    assert evt.type == "a2a_hop"
    assert evt.data["status"] == "completed"
    assert evt.data["direction"] == "outbound"
    assert evt.data["kind"] == "a2a_preview_call"
    # Coerce stringified-JSON args back into a dict for the frontend.
    assert isinstance(evt.data["arguments"], dict)
    assert evt.data["arguments"]["message"].startswith("Check feasibility")
    # Text preview is extracted from the ``message`` field of the args.
    assert "Check feasibility" in (evt.data["text_preview"] or "")
    assert evt.data["data_preview"] is None


def test_classify_a2a_preview_call_output_inbound_dual_part() -> None:
    """``a2a_preview_call_output`` (output) emits inbound + text + data preview."""

    artifact = {
        "result": {
            "artifacts": [
                {
                    "parts": [
                        {"kind": "text", "text": "We can fulfill 120 of 150 units."},
                        {
                            "kind": "data",
                            "data": {
                                "feasibility_score": 0.8,
                                "can_fulfill": False,
                                "total_fulfillable": 120,
                                "requested_quantity": 150,
                            },
                        },
                    ]
                }
            ]
        }
    }
    item = _Obj(
        type="a2a_preview_call_output",
        id="call_inbound_1",
        name="ops_agent",
        output=artifact,
    )
    evt = _classify_event(_Obj(type="response.output_item.done", item=item))
    assert evt.type == "a2a_hop"
    assert evt.data["direction"] == "inbound"
    assert evt.data["kind"] == "a2a_preview_call_output"
    assert evt.data["text_preview"] == "We can fulfill 120 of 150 units."
    assert isinstance(evt.data["data_preview"], dict)
    assert evt.data["data_preview"]["feasibility_score"] == 0.8
    assert evt.data["data_preview"]["total_fulfillable"] == 120


def test_redact_scrubs_sensitive_keys_recursively() -> None:
    payload = {
        "message": "ok",
        "Authorization": "Bearer secret-abc",
        "headers": {"x-api-key": "xyz", "Cookie": "sid=1"},
        "items": [{"api_key": "k1"}, {"safe": "value"}],
    }
    redacted = _redact(payload)
    assert redacted["message"] == "ok"
    assert redacted["Authorization"] == "***REDACTED***"
    assert redacted["headers"]["x-api-key"] == "***REDACTED***"
    assert redacted["headers"]["Cookie"] == "***REDACTED***"
    assert redacted["items"][0]["api_key"] == "***REDACTED***"
    assert redacted["items"][1]["safe"] == "value"


def test_coerce_payload_parses_json_strings() -> None:
    assert _coerce_payload('{"a": 1}') == {"a": 1}
    assert _coerce_payload("[1, 2, 3]") == [1, 2, 3]
    # Plain strings survive.
    assert _coerce_payload("hello") == "hello"
    # None / primitives pass through.
    assert _coerce_payload(None) is None
    assert _coerce_payload(42) == 42


def test_extract_a2a_previews_outbound_plain_string() -> None:
    text, data = _extract_a2a_previews("Forward this to ops.", None)
    assert text == "Forward this to ops."
    assert data is None


def test_classify_a2a_hop_redacts_secrets_in_arguments() -> None:
    """Sensitive keys in arguments must be scrubbed before reaching the wire."""

    item = _Obj(
        type="a2a_preview_call",
        id="call_redact_1",
        name="ops_agent",
        arguments={
            "message": "Check feasibility for SKU ZP-7000.",
            "headers": {"authorization": "Bearer top-secret"},
        },
    )
    evt = _classify_event(_Obj(type="response.output_item.done", item=item))
    assert evt.type == "a2a_hop"
    assert evt.data["arguments"]["headers"]["authorization"] == "***REDACTED***"
    # Public message survives redaction.
    assert "ZP-7000" in evt.data["arguments"]["message"]


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
