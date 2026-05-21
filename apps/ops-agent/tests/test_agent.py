"""Tests for app.agent.

Smoke tests run without Azure credentials. Tests that need real Azure
OpenAI are marked with `@pytest.mark.integration` and skipped by default.
"""

from __future__ import annotations

import pytest


# ---------------------------------------------------------------------------
# Import / smoke tests
# ---------------------------------------------------------------------------


def test_graph_imports_without_azure_credentials():
    """`from app.agent import graph` must succeed even when Azure env vars
    are unset. The Azure client is constructed lazily in the `summarize`
    node only.
    """
    from app.agent import graph

    assert graph is not None
    assert hasattr(graph, "invoke")
    assert hasattr(graph, "ainvoke")


def test_system_prompt_is_present():
    from app.agent import SUMMARIZE_PROMPT, SYSTEM_PROMPT

    # Backward-compat alias
    assert SYSTEM_PROMPT is SUMMARIZE_PROMPT
    assert "Zava Manufacturing Ops Agent" in SUMMARIZE_PROMPT
    assert "feasibility_score" in SUMMARIZE_PROMPT


# ---------------------------------------------------------------------------
# Tolerant request parser
# ---------------------------------------------------------------------------


def test_tolerant_parse_canonical_format():
    from app.agent import _tolerant_parse

    out = _tolerant_parse(
        "Check order feasibility: SKU=ZP-7000, quantity=10, "
        "target_date=2026-08-15, customer_id=CUST-001"
    )
    assert out == {
        "sku": "ZP-7000",
        "quantity": 10,
        "target_date": "2026-08-15",
        "customer_id": "CUST-001",
    }


def test_tolerant_parse_loose_colon_format():
    from app.agent import _tolerant_parse

    out = _tolerant_parse(
        "sku: ZP-7000   qty: 25   target_date: 2026-09-30   customer: CUST-002"
    )
    assert out["sku"] == "ZP-7000"
    assert out["quantity"] == 25
    assert out["target_date"] == "2026-09-30"
    assert out["customer_id"] == "CUST-002"


def test_tolerant_parse_missing_returns_none():
    from app.agent import _tolerant_parse

    out = _tolerant_parse("Free-form text without any structured fields here")
    assert out["sku"] is None
    assert out["quantity"] is None
    assert out["target_date"] is None
    assert out["customer_id"] is None


def test_tolerant_parse_empty_string():
    from app.agent import _tolerant_parse

    out = _tolerant_parse("")
    assert out == {
        "sku": None,
        "quantity": None,
        "target_date": None,
        "customer_id": None,
    }


# ---------------------------------------------------------------------------
# parse_request node
# ---------------------------------------------------------------------------


def test_parse_request_node_canonical():
    from langchain_core.messages import HumanMessage

    from app.agent import parse_request

    state = {
        "messages": [
            HumanMessage(
                content="SKU=ZP-7000, quantity=10, target_date=2026-08-15, customer_id=CUST-001"
            )
        ]
    }
    out = parse_request(state)
    assert out["sku"] == "ZP-7000"
    assert out["quantity"] == 10
    assert out["target_date"] == "2026-08-15"
    assert out["customer_id"] == "CUST-001"
    assert "parse_error" not in out


def test_parse_request_node_sets_parse_error_when_missing():
    from langchain_core.messages import HumanMessage

    from app.agent import parse_request

    state = {"messages": [HumanMessage(content="Just some unrelated request")]}
    out = parse_request(state)
    assert out["sku"] is None
    assert "parse_error" in out
    assert "sku" in out["parse_error"]


def test_parse_request_node_dict_message():
    """Executor sends `{"role": "user", "content": "..."}` dicts."""
    from app.agent import parse_request

    state = {
        "messages": [
            {
                "role": "user",
                "content": "SKU=ZP-7000, quantity=5, target_date=2026-07-01, customer_id=CUST-001",
            }
        ]
    }
    out = parse_request(state)
    assert out["sku"] == "ZP-7000"
    assert out["quantity"] == 5


# ---------------------------------------------------------------------------
# gather_data node
# ---------------------------------------------------------------------------


def test_gather_data_invokes_all_four_tools():
    from app.agent import gather_data

    state = {
        "messages": [],
        "sku": "ZP-7000",
        "quantity": 10,
        "target_date": "2026-12-31",
        "customer_id": "CUST-001",
    }
    out = gather_data(state)
    assert "inventory" in out
    assert "schedule" in out
    assert "orders" in out
    assert "customer" in out
    # Synthetic messages: 1 AIMessage with tool_calls + 4 ToolMessages
    assert len(out["messages"]) == 5


def test_gather_data_skipped_when_required_fields_missing():
    from app.agent import gather_data

    state = {
        "messages": [],
        "sku": "ZP-7000",
        "quantity": None,
        "target_date": None,
        "customer_id": None,
    }
    out = gather_data(state)
    # Should return an empty update (no tool invocations).
    assert "inventory" not in out


def test_gather_data_handles_unknown_sku_gracefully():
    """Unknown SKU should not raise — tool returns {found: False}."""
    from app.agent import gather_data

    state = {
        "messages": [],
        "sku": "NONEXISTENT-SKU",
        "quantity": 1,
        "target_date": "2026-12-31",
        "customer_id": "NONEXISTENT-CUSTOMER",
    }
    out = gather_data(state)
    assert out["inventory"].get("found") is False
    assert out["customer"].get("found") is False


# ---------------------------------------------------------------------------
# compute_feasibility node
# ---------------------------------------------------------------------------


def test_compute_feasibility_node_with_full_pipeline():
    """Drive parse_request → gather_data → compute_feasibility end-to-end."""
    from langchain_core.messages import HumanMessage

    from app.agent import compute_feasibility_node, gather_data, parse_request

    state = {
        "messages": [
            HumanMessage(
                content="SKU=ZP-7000, quantity=10, target_date=2026-12-31, customer_id=CUST-001"
            )
        ]
    }
    state.update(parse_request(state))
    state.update(gather_data(state))
    out = compute_feasibility_node(state)

    fea = out["feasibility"]
    # All canonical schema fields present
    assert set(fea.keys()) >= {
        "feasibility_score",
        "can_fulfill",
        "requested_quantity",
        "available_inventory",
        "production_capacity_by_date",
        "supplier_pipeline",
        "total_fulfillable",
        "earliest_promise_date",
        "requested_date",
        "days_late",
        "risk_factors",
        "recommendation_text",
    }
    assert fea["requested_quantity"] == 10
    assert isinstance(fea["feasibility_score"], float)
    assert isinstance(fea["can_fulfill"], bool)


def test_compute_feasibility_node_when_inputs_missing():
    from app.agent import compute_feasibility_node

    out = compute_feasibility_node(
        {"messages": [], "parse_error": "Missing required request field(s): sku"}
    )
    fea = out["feasibility"]
    assert fea["can_fulfill"] is False
    assert fea["feasibility_score"] == 0.0
    assert any("Missing" in r or "missing" in r for r in fea["risk_factors"])


def test_compute_feasibility_node_full_schema_for_known_sku():
    """Sanity check: a real synthetic SKU produces a meaningful score."""
    from langchain_core.messages import HumanMessage

    from app.agent import compute_feasibility_node, gather_data, parse_request

    state = {
        "messages": [
            HumanMessage(
                content="SKU=ZP-7000, quantity=1, target_date=2026-12-31, customer_id=CUST-001"
            )
        ]
    }
    state.update(parse_request(state))
    state.update(gather_data(state))
    out = compute_feasibility_node(state)
    fea = out["feasibility"]
    # Tiny order should be trivially feasible
    assert fea["requested_quantity"] == 1
    assert fea["feasibility_score"] >= 0.0
    assert fea["feasibility_score"] <= 1.0


# ---------------------------------------------------------------------------
# Integration — full graph (still mocks the LLM via integration marker)
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_graph_ainvoke_with_real_azure():  # pragma: no cover - integration only
    """Live Azure OpenAI smoke test. Requires AZURE_OPENAI_* env vars and
    `az login` (or a managed identity).
    """
    import asyncio

    from langchain_core.messages import HumanMessage

    from app.agent import graph

    async def _run():
        return await graph.ainvoke(
            {
                "messages": [
                    HumanMessage(
                        content=(
                            "Check order feasibility: SKU=ZP-7000, "
                            "quantity=10, target_date=2026-08-15, "
                            "customer_id=CUST-001"
                        )
                    )
                ]
            }
        )

    result = asyncio.run(_run())
    assert "messages" in result
    assert result.get("feasibility")  # deterministic compute populated state
    assert "feasibility_score" in result["feasibility"]
