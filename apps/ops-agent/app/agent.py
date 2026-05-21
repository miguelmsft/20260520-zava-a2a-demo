"""LangGraph orchestration for the Zava Manufacturing Ops Agent.

Deterministic graph (Phase 4 fix — addresses audit blockers B1/B2/B3):

    START
      -> parse_request       # extract SKU / quantity / target_date / customer_id
      -> gather_data         # invoke all 4 lookup tools deterministically
      -> compute_feasibility # call the pure feasibility computer
      -> summarize           # LLM writes a customer-friendly summary
      -> END

Rationale:
    The previous LLM-driven tool-calling design risked the LLM hallucinating
    the feasibility JSON (the system prompt said the executor would compute
    canonical numbers via `compute_feasibility`, but the executor never did).
    With a sequential, deterministic graph:
      * Tool inputs come from a tolerant regex parser of the inbound request.
      * Every tool is invoked exactly once.
      * `compute_feasibility()` produces the canonical structured artifact.
      * The LLM is only used for the human-readable summary text.

The Azure OpenAI client is constructed lazily on first invocation so that
`from app.agent import graph` succeeds in environments without Azure
credentials (CI, local unit tests).
"""

from __future__ import annotations

import json
import logging
import re
from datetime import date
from functools import lru_cache
from typing import Any, NotRequired

from langchain_core.messages import (
    AIMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langgraph.graph import END, START, MessagesState, StateGraph

from .config import require_azure
from .tools import (
    ALL_TOOLS,
    lookup_customer,
    lookup_inventory,
    lookup_order_book,
    lookup_production_schedule,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------


class AgentState(MessagesState):
    """LangGraph state for the Zava Ops Agent.

    Extends `MessagesState` (which carries the chat messages with an additive
    reducer) with the structured fields that flow through the deterministic
    pipeline. All extension fields are `NotRequired` so the graph can be
    invoked with just `{"messages": [...]}` (as the A2A executor does).
    """

    sku: NotRequired[str | None]
    quantity: NotRequired[int | None]
    target_date: NotRequired[str | None]
    customer_id: NotRequired[str | None]
    parse_error: NotRequired[str | None]
    inventory: NotRequired[dict[str, Any] | None]
    schedule: NotRequired[dict[str, Any] | None]
    orders: NotRequired[dict[str, Any] | None]
    customer: NotRequired[dict[str, Any] | None]
    feasibility: NotRequired[dict[str, Any] | None]


# ---------------------------------------------------------------------------
# Prompts (the summarise step is the only LLM call)
# ---------------------------------------------------------------------------


SUMMARIZE_PROMPT = """You are the Zava Manufacturing Ops Agent.

Zava is a precision-components manufacturer (pumps, motors, valves, seals).
You answer order-feasibility questions for customer-service agents and sales
engineers.

You will be given a feasibility result that was computed deterministically
from the synthetic Zava operational data (inventory, production schedule,
order book, customer profile). The result schema includes:

  - feasibility_score (float, 0.0-1.0)
  - can_fulfill (bool)
  - requested_quantity, available_inventory, production_capacity_by_date,
    supplier_pipeline, total_fulfillable (int)
  - earliest_promise_date, requested_date (ISO YYYY-MM-DD)
  - days_late (int)
  - risk_factors (list of strings)
  - recommendation_text (string)

Your job is to write a SHORT, professional, customer-friendly summary that:
  1. Opens with a one-sentence headline (yes/no plus the key date).
  2. Names the key drivers (inventory level, scheduled production, supplier
     pipeline) using the actual numbers from the result.
  3. Surfaces any risks (drawn from `risk_factors`).
  4. Closes with the recommendation.

Do NOT invent any numbers; only use values present in the feasibility
result. Do NOT emit JSON — the structured payload is already attached as a
separate artifact part. Write 3-5 sentences in plain prose.
"""


# Backward-compat alias (some tests / docs reference SYSTEM_PROMPT directly).
SYSTEM_PROMPT = SUMMARIZE_PROMPT


# ---------------------------------------------------------------------------
# Lazy LLM construction
# ---------------------------------------------------------------------------


@lru_cache(maxsize=1)
def get_model():  # pragma: no cover - exercised by integration tests
    """Build the AzureChatOpenAI client (no tool binding in the new design).

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
    return AzureChatOpenAI(
        azure_deployment=settings.azure_openai_deployment,
        api_version=settings.azure_openai_api_version,
        azure_endpoint=settings.azure_openai_endpoint,
        azure_ad_token_provider=token_provider,
    )


# Backward-compat alias. Returns a tool-bound model (used by no current code
# path but kept so external imports do not break).
@lru_cache(maxsize=1)
def get_model_with_tools():  # pragma: no cover
    return get_model().bind_tools(ALL_TOOLS)


# ---------------------------------------------------------------------------
# Request parsing (tolerant)
# ---------------------------------------------------------------------------


_SKU_RE = re.compile(r"(?i)\bsku\s*[:=]\s*\"?([A-Za-z0-9][\w-]*)\"?")
_QTY_RE = re.compile(r"(?i)\b(?:quantity|qty|units?)\s*[:=]\s*\"?(\d+)\"?")
_DATE_RE = re.compile(
    r"(?i)\b(?:target_date|target|deliver(?:y)?_date|by|date)\s*[:=]?\s*\"?(\d{4}-\d{2}-\d{2})\"?"
)
_CUST_RE = re.compile(
    r"(?i)\bcustomer(?:_id)?\s*[:=]\s*\"?(CUST-[A-Za-z0-9-]+)\"?"
)


def _tolerant_parse(text: str) -> dict[str, Any]:
    """Best-effort extraction of (sku, quantity, target_date, customer_id).

    Accepts variations like:
      * "SKU=ZP-7000, quantity=10, target_date=2026-08-15, customer_id=CUST-001"
      * "sku: ZP-7000  qty: 10  target: 2026-08-15  customer: CUST-001"
      * "Check feasibility of 10 ZP-7000 by 2026-08-15 for CUST-001"
    Missing fields come back as None so the compute step can produce an
    explicit "input missing" failure artifact rather than silently defaulting.
    """
    if not text:
        return {"sku": None, "quantity": None, "target_date": None, "customer_id": None}
    sku_m = _SKU_RE.search(text)
    qty_m = _QTY_RE.search(text)
    date_m = _DATE_RE.search(text)
    cust_m = _CUST_RE.search(text)
    return {
        "sku": sku_m.group(1) if sku_m else None,
        "quantity": int(qty_m.group(1)) if qty_m else None,
        "target_date": date_m.group(1) if date_m else None,
        "customer_id": cust_m.group(1) if cust_m else None,
    }


def _extract_user_text(messages: list[Any]) -> str:
    """Concatenate text from the first user message in the message list."""
    if not messages:
        return ""
    first = messages[0]
    if isinstance(first, dict):
        return str(first.get("content", "") or "")
    content = getattr(first, "content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks: list[str] = []
        for item in content:
            if isinstance(item, dict) and "text" in item:
                chunks.append(str(item["text"]))
            elif isinstance(item, str):
                chunks.append(item)
        return "\n".join(chunks)
    return str(content or "")


# ---------------------------------------------------------------------------
# Graph nodes
# ---------------------------------------------------------------------------


def parse_request(state: AgentState) -> dict[str, Any]:
    """Extract structured order fields from the inbound user message."""
    user_text = _extract_user_text(state["messages"])
    parsed = _tolerant_parse(user_text)
    missing = [k for k, v in parsed.items() if v is None]
    if missing:
        parsed["parse_error"] = (
            "Missing required request field(s): " + ", ".join(missing)
        )
        logger.info("ops-agent.parse_request: missing=%s", missing)
    else:
        logger.info(
            "ops-agent.parse_request: sku=%s qty=%s date=%s customer=%s",
            parsed["sku"],
            parsed["quantity"],
            parsed["target_date"],
            parsed["customer_id"],
        )
    return parsed


def gather_data(state: AgentState) -> dict[str, Any]:
    """Deterministically invoke all 4 lookup tools.

    Emits each tool result as a `ToolMessage` (so Foundry tracing / message
    log reflects the lookups) and also stores the raw dicts in state for the
    compute step.
    """
    sku = state.get("sku")
    target_date = state.get("target_date")
    customer_id = state.get("customer_id")

    if not sku or not target_date or not customer_id:
        logger.info("ops-agent.gather_data: skipping — required fields missing")
        return {}

    today = date.today().isoformat()
    inventory = lookup_inventory.invoke({"sku": sku})
    schedule = lookup_production_schedule.invoke(
        {"sku": sku, "start_date": today, "end_date": target_date}
    )
    orders = lookup_order_book.invoke({"sku": sku})
    customer = lookup_customer.invoke({"customer_id": customer_id})

    # Synthetic AIMessage with tool_calls + matching ToolMessages keep the
    # transcript well-formed (some LLM providers reject ToolMessages without
    # a preceding tool_call). This also makes the Foundry trace readable.
    ai_msg = AIMessage(
        content="",
        tool_calls=[
            {
                "id": "lookup_inventory:1",
                "name": "lookup_inventory",
                "args": {"sku": sku},
            },
            {
                "id": "lookup_production_schedule:1",
                "name": "lookup_production_schedule",
                "args": {"sku": sku, "start_date": today, "end_date": target_date},
            },
            {
                "id": "lookup_order_book:1",
                "name": "lookup_order_book",
                "args": {"sku": sku},
            },
            {
                "id": "lookup_customer:1",
                "name": "lookup_customer",
                "args": {"customer_id": customer_id},
            },
        ],
    )
    tool_msgs = [
        ToolMessage(
            content=json.dumps(inventory),
            tool_call_id="lookup_inventory:1",
            name="lookup_inventory",
        ),
        ToolMessage(
            content=json.dumps(schedule),
            tool_call_id="lookup_production_schedule:1",
            name="lookup_production_schedule",
        ),
        ToolMessage(
            content=json.dumps(orders),
            tool_call_id="lookup_order_book:1",
            name="lookup_order_book",
        ),
        ToolMessage(
            content=json.dumps(customer),
            tool_call_id="lookup_customer:1",
            name="lookup_customer",
        ),
    ]

    return {
        "inventory": inventory,
        "schedule": schedule,
        "orders": orders,
        "customer": customer,
        "messages": [ai_msg, *tool_msgs],
    }


def _input_missing_feasibility(
    state: AgentState, reason: str
) -> dict[str, Any]:
    """Build a degraded-but-well-formed feasibility result when inputs are
    incomplete. Surfaces the reason in `risk_factors` so the upstream Foundry
    agent can explain it to the user.
    """
    target_date = state.get("target_date") or "unknown"
    return {
        "feasibility_score": 0.0,
        "can_fulfill": False,
        "requested_quantity": state.get("quantity") or 0,
        "available_inventory": 0,
        "production_capacity_by_date": 0,
        "supplier_pipeline": 0,
        "total_fulfillable": 0,
        "earliest_promise_date": target_date,
        "requested_date": target_date,
        "days_late": 0,
        "risk_factors": [reason],
        "recommendation_text": (
            "Could not run feasibility computation: " + reason
        ),
    }


def compute_feasibility_node(state: AgentState) -> dict[str, Any]:
    """Call the deterministic feasibility computer on the gathered tool data."""
    sku = state.get("sku")
    qty = state.get("quantity")
    target_date = state.get("target_date")

    if not sku or qty is None or not target_date:
        return {
            "feasibility": _input_missing_feasibility(
                state,
                state.get("parse_error")
                or "Required request fields missing from inbound message",
            )
        }

    inventory = state.get("inventory") or {}
    schedule = state.get("schedule") or {}
    orders_data = state.get("orders") or {}
    customer = state.get("customer") or {}

    if not (inventory and schedule is not None and orders_data is not None):
        return {
            "feasibility": _input_missing_feasibility(
                state, "One or more lookup tools did not return data"
            )
        }

    # Flatten production slots from schedule.machines[].slots[]
    slots: list[dict[str, Any]] = []
    machines = schedule.get("machines", []) if isinstance(schedule, dict) else []
    for m in machines:
        for s in (m.get("slots") or []):
            slots.append(s)

    orders_list = (
        orders_data.get("orders", []) if isinstance(orders_data, dict) else []
    )

    # Import here to keep import-time cheap.
    from .feasibility import compute_feasibility as _compute

    feasibility = _compute(
        inventory=inventory,
        production_slots=slots,
        orders=orders_list,
        customer=customer,
        quantity=qty,
        target_date=target_date,
    )
    logger.info(
        "ops-agent.compute_feasibility: score=%s can_fulfill=%s",
        feasibility.get("feasibility_score"),
        feasibility.get("can_fulfill"),
    )
    return {"feasibility": feasibility}


def summarize(state: AgentState) -> dict[str, Any]:
    """LLM step: produce a customer-friendly summary of the feasibility result."""
    feasibility = state.get("feasibility") or {}
    summary_input = (
        "Feasibility result (canonical, computed deterministically):\n\n"
        f"```json\n{json.dumps(feasibility, indent=2)}\n```\n\n"
        "Now write the customer-friendly summary."
    )
    model = get_model()
    response = model.invoke(
        [SystemMessage(content=SUMMARIZE_PROMPT), HumanMessage(content=summary_input)]
    )
    return {"messages": [response]}


# ---------------------------------------------------------------------------
# Compile graph (no Azure calls at import time)
# ---------------------------------------------------------------------------


def _build_graph():
    workflow = StateGraph(AgentState)
    workflow.add_node("parse_request", parse_request)
    workflow.add_node("gather_data", gather_data)
    workflow.add_node("compute_feasibility", compute_feasibility_node)
    workflow.add_node("summarize", summarize)
    workflow.add_edge(START, "parse_request")
    workflow.add_edge("parse_request", "gather_data")
    workflow.add_edge("gather_data", "compute_feasibility")
    workflow.add_edge("compute_feasibility", "summarize")
    workflow.add_edge("summarize", END)
    return workflow.compile()


graph = _build_graph()


__all__ = [
    "graph",
    "AgentState",
    "SYSTEM_PROMPT",
    "SUMMARIZE_PROMPT",
    "parse_request",
    "gather_data",
    "compute_feasibility_node",
    "summarize",
    "get_model",
    "get_model_with_tools",
    "_tolerant_parse",
]
