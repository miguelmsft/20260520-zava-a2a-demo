"""A2A Agent Card definition for the Zava Manufacturing Ops Agent.

The card is what remote A2A clients (e.g., the Foundry orchestrator) fetch from
``/.well-known/agent-card.json`` to discover capabilities and skills.

The ``a2a-sdk`` 1.0.x types are protobuf-generated. ``AgentCard`` does not have
a top-level ``url`` field; the public endpoint is advertised via
``supported_interfaces[].url`` instead. We populate it from the
``OPS_AGENT_PUBLIC_URL`` env var so deployments can override it without code
changes.
"""

from __future__ import annotations

import os

from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
)

DEFAULT_PUBLIC_URL = "http://localhost:9000/"


def build_agent_card() -> AgentCard:
    """Construct the AgentCard for this service.

    Reads ``OPS_AGENT_PUBLIC_URL`` from the environment so that the same image
    can be deployed locally (default ``http://localhost:9000/``) or behind an
    ingress (e.g., ``https://ops-agent.example.com/``).
    """
    public_url = os.environ.get("OPS_AGENT_PUBLIC_URL", DEFAULT_PUBLIC_URL)

    skill = AgentSkill(
        id="order-feasibility",
        name="Order Feasibility Check",
        description=(
            "Given an SKU, quantity, target date, and customer ID, returns a "
            "feasibility_score (0.0-1.0), can_fulfill flag, "
            "earliest_promise_date, risk_factors, and a human-readable "
            "recommendation."
        ),
        tags=["manufacturing", "inventory", "supply-chain", "feasibility"],
        examples=[
            "Can we fulfill 150 ZP-7000 pumps for CUST-001 by 2026-07-15?",
            "Check feasibility: SKU ZM-3200, quantity 25, customer CUST-003, "
            "target 2026-06-30",
        ],
    )

    return AgentCard(
        name="Zava Manufacturing Ops Agent",
        description=(
            "Queries inventory, production capacity, lead times, and "
            "competing orders to compute fulfillment feasibility for Zava "
            "precision components (pumps, motors, valves, seals)."
        ),
        version="1.0.0",
        default_input_modes=["text/plain"],
        default_output_modes=["application/json", "text/plain"],
        capabilities=AgentCapabilities(streaming=False),
        skills=[skill],
        supported_interfaces=[
            AgentInterface(
                url=public_url,
                protocol_binding="jsonrpc",
                protocol_version="0.3",
            ),
        ],
    )


__all__ = ["build_agent_card", "DEFAULT_PUBLIC_URL"]
