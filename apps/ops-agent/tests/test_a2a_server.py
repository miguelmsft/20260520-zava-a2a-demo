"""A2A protocol compliance tests for the Zava Ops Agent server.

These tests exercise the in-process Starlette app (no real network listener)
and mock out ``app.executor.graph`` so the LangGraph + AzureChatOpenAI stack
is never invoked. Tests run without Azure credentials and are marked as
non-integration so they execute under ``pytest -m "not integration"``.

Coverage (per plan §C Step 18, research §3 wire format and §3.8 v0.3 ↔ 1.0
interop):

1. Agent Card discovery (``GET /.well-known/agent-card.json``)
2. Health probe (``GET /health``)
3. Auth: missing ``x-api-key`` → 401
4. Auth: wrong ``x-api-key`` → 401
5. A2A v0.3 ``message/send`` happy path (no ``A2A-Version`` header,
   SDK auto-detects v0.3) → completed task with artifact carrying both a
   DataPart (parsed feasibility JSON) and a TextPart (recommendation)
6. Malformed JSON-RPC body → JSON-RPC error response
7. Unknown method → JSON-RPC error code -32601
"""

from __future__ import annotations

import json
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from starlette.testclient import TestClient

# The fail-secure check in app.server runs at build_app() time (not import
# time), but agent_card / executor imports must succeed regardless. We set
# the API key here so any code path that consults it sees a deterministic
# value.
API_KEY = "test-key-123"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_feasibility_payload() -> dict:
    """The structured JSON the mocked LLM "returns" via the graph."""
    return {
        "feasibility_score": 0.85,
        "can_fulfill": True,
        "earliest_promise_date": "2026-07-12",
        "risk_factors": ["competing rush order"],
        "recommendation": (
            "We can fulfill this order; promise date 2026-07-12."
        ),
    }


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch, fake_feasibility_payload: dict):
    """Build the Starlette app with a mocked graph and yield a TestClient.

    The mock replaces ``app.executor.graph`` (the name the executor binds
    via ``from .agent import graph``) so ``graph.ainvoke`` returns a
    deterministic feasibility response without contacting Azure OpenAI.
    """
    monkeypatch.setenv("A2A_API_KEY", API_KEY)
    # Make sure Azure env vars aren't relied on; force-clear any stragglers.
    for var in (
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_DEPLOYMENT",
    ):
        monkeypatch.delenv(var, raising=False)

    # Build the assistant's "final message" the way LangGraph would — a
    # message-like object exposing ``.content`` as a JSON string. The
    # executor's ``_final_assistant_text`` reads ``content`` directly.
    assistant_message = SimpleNamespace(
        content=json.dumps(fake_feasibility_payload)
    )
    fake_graph_result = {
        "messages": [assistant_message],
    }

    fake_graph = SimpleNamespace(ainvoke=AsyncMock(return_value=fake_graph_result))

    # Patch the binding inside app.executor (the name the executor uses).
    # Importing here (not at module top) ensures the env var is set first.
    from app import executor as executor_module

    monkeypatch.setattr(executor_module, "graph", fake_graph)

    from app.server import build_app

    app = build_app()
    with TestClient(app) as test_client:
        yield test_client


# ---------------------------------------------------------------------------
# Discovery & health
# ---------------------------------------------------------------------------


def test_agent_card_discovery(client: TestClient) -> None:
    """``GET /.well-known/agent-card.json`` is unauthenticated and returns a
    well-formed AgentCard with all A2A-required fields populated.
    """
    resp = client.get("/.well-known/agent-card.json")
    assert resp.status_code == 200, resp.text
    card = resp.json()

    # Required top-level fields per A2A spec §3 (and our agent_card.py).
    for field in (
        "name",
        "version",
        "skills",
        "capabilities",
        "defaultInputModes",
        "defaultOutputModes",
    ):
        assert field in card, f"Agent card missing required field: {field}"

    assert isinstance(card["skills"], list) and len(card["skills"]) >= 1
    skill = card["skills"][0]
    assert "id" in skill and "name" in skill
    assert card["name"] == "Zava Manufacturing Ops Agent"


def test_agent_card_legacy_alias(client: TestClient) -> None:
    """Foundry's A2A client probes the older ``/.well-known/agent.json``
    URL (no dash). The same card must be served from both paths so that
    discovery succeeds regardless of which A2A spec version the client
    implements.
    """

    new_resp = client.get("/.well-known/agent-card.json")
    legacy_resp = client.get("/.well-known/agent.json")
    assert legacy_resp.status_code == 200, legacy_resp.text
    # Both URLs must return the exact same card payload.
    assert legacy_resp.json() == new_resp.json()


def test_agent_card_legacy_alias_no_auth_required(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The legacy alias must NOT require ``x-api-key`` — public discovery."""

    # Build a fresh client with no x-api-key header set.
    monkeypatch.setenv("A2A_API_KEY", API_KEY)
    from app.server import build_app

    raw_client = TestClient(build_app(api_key=API_KEY))
    resp = raw_client.get("/.well-known/agent.json")
    assert resp.status_code == 200, resp.text


def test_health_probe(client: TestClient) -> None:
    """``GET /health`` is unauthenticated and returns 200."""
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


def _v03_message_send_body() -> dict:
    return {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "message/send",
        "params": {
            "message": {
                "messageId": "msg-1",
                "role": "user",
                "parts": [
                    {
                        "kind": "text",
                        "text": "Check feasibility for SKU ZP-7000 qty 150",
                    }
                ],
            }
        },
    }


def test_post_without_api_key_is_unauthorized(client: TestClient) -> None:
    resp = client.post("/", json=_v03_message_send_body())
    assert resp.status_code == 401
    assert resp.json() == {"error": "unauthorized"}


def test_post_with_wrong_api_key_is_unauthorized(client: TestClient) -> None:
    resp = client.post(
        "/",
        json=_v03_message_send_body(),
        headers={"x-api-key": "wrong-key"},
    )
    assert resp.status_code == 401
    assert resp.json() == {"error": "unauthorized"}


# ---------------------------------------------------------------------------
# A2A v0.3 happy path
# ---------------------------------------------------------------------------


def test_message_send_v03_happy_path(
    client: TestClient, fake_feasibility_payload: dict
) -> None:
    """End-to-end v0.3 ``message/send``: SDK auto-detects v0.3 (no
    ``A2A-Version`` header), routes to the executor, which drives the
    (mocked) graph and produces a completed task with an artifact carrying
    both a DataPart (parsed feasibility JSON) and a TextPart (recommendation).
    """
    resp = client.post(
        "/",
        json=_v03_message_send_body(),
        headers={"x-api-key": API_KEY},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body.get("jsonrpc") == "2.0"
    assert body.get("id") == 1
    assert "error" not in body, f"Unexpected JSON-RPC error: {body.get('error')}"
    assert "result" in body, body

    # In A2A v0.3 the JSON-RPC ``result`` *is* the Task (the SDK handles the
    # v1.0 → v0.3 envelope flattening when ``enable_v0_3_compat=True``).
    result = body["result"]
    # Be tolerant: some SDK builds wrap the task under ``result.task``.
    task = result.get("task") if isinstance(result, dict) and "task" in result else result
    assert isinstance(task, dict), f"Expected task object, got: {task!r}"

    # Status should be terminal (``completed``). v0.3 uses lowercase strings.
    status = task.get("status") or {}
    state = status.get("state") if isinstance(status, dict) else status
    assert state in ("completed", "TASK_STATE_COMPLETED"), (
        f"Expected completed task state, got {state!r}: task={task!r}"
    )

    artifacts = task.get("artifacts") or []
    assert len(artifacts) >= 1, f"Expected at least one artifact: task={task!r}"
    artifact = artifacts[0]
    parts = artifact.get("parts") or []
    assert len(parts) >= 2, (
        f"Expected both DataPart and TextPart, got parts={parts!r}"
    )

    # Identify part kinds across v0.3 ("kind") and v1.0 (oneof field) shapes.
    kinds = set()
    found_text = None
    found_data = None
    for part in parts:
        if not isinstance(part, dict):
            continue
        kind = part.get("kind")
        if kind:
            kinds.add(kind)
        if "text" in part and part.get("text"):
            found_text = part["text"]
        if "data" in part and part.get("data"):
            found_data = part["data"]

    assert found_text is not None, f"No text part in artifact: parts={parts!r}"
    assert found_data is not None, f"No data part in artifact: parts={parts!r}"
    # Data part should carry our parsed feasibility JSON.
    assert found_data.get("feasibility_score") == fake_feasibility_payload[
        "feasibility_score"
    ]
    assert found_data.get("can_fulfill") is True


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


def test_malformed_jsonrpc_returns_error(client: TestClient) -> None:
    """A POST with a non-JSON-RPC body must produce a JSON-RPC error
    response (HTTP 200 with ``error`` field per JSON-RPC 2.0) or HTTP 400.
    Either is spec-compliant; this test asserts we don't 200-with-result.
    """
    resp = client.post(
        "/",
        json={"not": "rpc"},
        headers={"x-api-key": API_KEY},
    )
    assert resp.status_code in (200, 400), resp.text
    if resp.status_code == 200:
        body = resp.json()
        assert "error" in body, f"Expected JSON-RPC error envelope, got: {body!r}"
        # Code should be one of the JSON-RPC standard error codes (negative).
        assert body["error"].get("code", 0) < 0


def test_unknown_method_returns_method_not_found(client: TestClient) -> None:
    """An unknown JSON-RPC method must return error code -32601."""
    resp = client.post(
        "/",
        json={
            "jsonrpc": "2.0",
            "id": 1,
            "method": "bogus/method",
            "params": {},
        },
        headers={"x-api-key": API_KEY},
    )
    # JSON-RPC 2.0 returns HTTP 200 with an ``error`` object; some servers
    # use 4xx. Accept either, but require error.code == -32601.
    assert resp.status_code in (200, 400, 404), resp.text
    body = resp.json()
    assert "error" in body, f"Expected error envelope, got: {body!r}"
    assert body["error"].get("code") == -32601, (
        f"Expected method-not-found (-32601), got: {body['error']!r}"
    )
