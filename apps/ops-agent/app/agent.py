"""LangGraph orchestration for the Zava Manufacturing Ops Agent.

Graph shape (per plan §C Step 8 and research §3, §5):

    START -> call_model -> (tool_calls?) --yes--> call_tools -> call_model
                              \\--no--> END

The Azure OpenAI client is constructed lazily on first invocation so that
`from app.agent import graph` succeeds in environments without Azure
credentials (CI, local unit tests).
"""

from __future__ import annotations

from functools import lru_cache
from typing import Any

from langchain_core.messages import SystemMessage, ToolMessage
from langgraph.graph import END, START, MessagesState, StateGraph

from .config import require_azure
from .tools import ALL_TOOLS

SYSTEM_PROMPT = """You are the Zava Manufacturing Ops Agent.

You serve order-feasibility queries for Zava (precision components manufacturer:
pumps, motors, valves, seals). For each request you receive — typically of the
form "Check order feasibility: SKU=..., quantity=..., target_date=..., customer_id=..." —
do the following:

1. Call `lookup_inventory(sku)` to get current stock.
2. Call `lookup_production_schedule(sku, start_date, end_date)` for the window
   from today through the requested target_date (and a little after).
3. Call `lookup_order_book(sku)` to see competing open orders.
4. Call `lookup_customer(customer_id)` to learn the customer's priority tier.
5. Synthesize a feasibility result as a SINGLE JSON object with exactly the
   following keys (no markdown, no prose around it):

   {
     "feasibility_score": float (0.0-1.0),
     "can_fulfill": bool,
     "requested_quantity": int,
     "available_inventory": int,
     "production_capacity_by_date": int,
     "supplier_pipeline": int,
     "total_fulfillable": int,
     "earliest_promise_date": "YYYY-MM-DD",
     "requested_date": "YYYY-MM-DD",
     "days_late": int,
     "risk_factors": [string, ...],
     "recommendation_text": string
   }

The downstream A2A executor will compute the canonical numbers via the
`compute_feasibility` helper; your role is to gather the inputs and produce a
human-meaningful recommendation. If a SKU or customer is not found, surface
that clearly in `risk_factors` and `recommendation_text`. Do not invent SKUs.
"""


# ---------------------------------------------------------------------------
# Lazy LLM construction (so import-time has no Azure dependency)
# ---------------------------------------------------------------------------


@lru_cache(maxsize=1)
def get_model_with_tools():  # pragma: no cover - exercised by integration tests
    """Build the AzureChatOpenAI client and bind tools. Cached singleton.

    Imports the Azure SDK pieces lazily so that environments without
    `azure-identity` configured can still import this module.
    """
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from langchain_openai import AzureChatOpenAI

    settings = require_azure()
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(),
        "https://cognitiveservices.azure.com/.default",
    )
    llm = AzureChatOpenAI(
        azure_deployment=settings.azure_openai_deployment,
        api_version=settings.azure_openai_api_version,
        azure_endpoint=settings.azure_openai_endpoint,
        azure_ad_token_provider=token_provider,
    )
    return llm.bind_tools(ALL_TOOLS)


_TOOLS_BY_NAME = {t.name: t for t in ALL_TOOLS}


# ---------------------------------------------------------------------------
# Graph nodes
# ---------------------------------------------------------------------------


def _ensure_system_prompt(messages: list[Any]) -> list[Any]:
    """Prepend the system prompt if not already present."""
    if messages and isinstance(messages[0], SystemMessage):
        return messages
    return [SystemMessage(content=SYSTEM_PROMPT), *messages]


def call_model(state: MessagesState) -> dict[str, list[Any]]:
    """LLM step: decide whether to call a tool or emit the final answer."""
    model = get_model_with_tools()
    messages = _ensure_system_prompt(list(state["messages"]))
    response = model.invoke(messages)
    return {"messages": [response]}


def call_tools(state: MessagesState) -> dict[str, list[Any]]:
    """Execute every tool call from the most recent AI message."""
    last = state["messages"][-1]
    tool_calls = getattr(last, "tool_calls", None) or []
    results: list[Any] = []
    for tc in tool_calls:
        name = tc["name"]
        args = tc.get("args", {}) or {}
        tool_id = tc.get("id") or tc.get("tool_call_id")
        fn = _TOOLS_BY_NAME.get(name)
        if fn is None:
            content = {"error": f"unknown tool: {name}"}
        else:
            try:
                content = fn.invoke(args)
            except Exception as exc:  # pragma: no cover - defensive
                content = {"error": str(exc), "tool": name}
        results.append(
            ToolMessage(content=str(content), tool_call_id=tool_id, name=name)
        )
    return {"messages": results}


def should_continue(state: MessagesState) -> str:
    """Route to tools if the last AI message has tool_calls, else end."""
    last = state["messages"][-1]
    if getattr(last, "tool_calls", None):
        return "call_tools"
    return END


# ---------------------------------------------------------------------------
# Compile graph (no Azure calls at import time)
# ---------------------------------------------------------------------------


def _build_graph():
    workflow = StateGraph(MessagesState)
    workflow.add_node("call_model", call_model)
    workflow.add_node("call_tools", call_tools)
    workflow.add_edge(START, "call_model")
    workflow.add_conditional_edges(
        "call_model", should_continue, ["call_tools", END]
    )
    workflow.add_edge("call_tools", "call_model")
    return workflow.compile()


graph = _build_graph()

__all__ = [
    "graph",
    "SYSTEM_PROMPT",
    "call_model",
    "call_tools",
    "should_continue",
    "get_model_with_tools",
]
