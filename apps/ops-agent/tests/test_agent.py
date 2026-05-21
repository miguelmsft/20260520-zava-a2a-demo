"""Tests for app.agent.

Smoke tests run without Azure credentials. Tests that need real Azure
OpenAI are marked with `@pytest.mark.integration` and skipped by default.
"""

from __future__ import annotations

import pytest


def test_graph_imports_without_azure_credentials():
    """`from app.agent import graph` must succeed even when Azure env vars
    are unset. The Azure client is constructed lazily on first invoke.
    """
    from app.agent import graph

    assert graph is not None
    # The compiled graph should be callable / invocable.
    assert hasattr(graph, "invoke")
    assert hasattr(graph, "ainvoke")


def test_system_prompt_is_present():
    from app.agent import SYSTEM_PROMPT

    assert "Zava Manufacturing Ops Agent" in SYSTEM_PROMPT
    assert "feasibility_score" in SYSTEM_PROMPT


def test_should_continue_routes_correctly():
    """Conditional edge: tool_calls -> call_tools, else END."""
    from langgraph.graph import END

    from app.agent import should_continue

    class _Msg:
        def __init__(self, tool_calls):
            self.tool_calls = tool_calls

    state_with_tools = {"messages": [_Msg([{"name": "x", "args": {}, "id": "1"}])]}
    state_without_tools = {"messages": [_Msg([])]}

    assert should_continue(state_with_tools) == "call_tools"
    assert should_continue(state_without_tools) == END


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
    assert len(result["messages"]) >= 2
