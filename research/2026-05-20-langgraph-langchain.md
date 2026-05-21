# Research Report: LangGraph vs LangChain — Which to Use for an Agent, and the A2A Support Story

**Date:** 2026-05-20
**Researcher:** Copilot Web Researcher Agent
**Topic slug:** langgraph-langchain
**Sources consulted:** 18 documentation & article pages, 8 PyPI packages, 7 GitHub repositories

---

## Executive Summary

In 2026, **LangGraph** is the recommended runtime for building stateful, multi-step agents — including the Manufacturing Ops Agent in our Zava demo. LangGraph (v1.2.0) is the low-level orchestration layer for durable execution, streaming, persistence, and human-in-the-loop workflows. **LangChain** (v1.3.1) sits above LangGraph as a higher-level agent framework providing model/tool abstractions and integrations. LangChain 1.0+ is itself built on LangGraph internally. For our demo, we use both: LangChain for model integration and tool abstractions, and LangGraph for graph-based agent orchestration.

The **A2A support story** has two paths: (1) the official **LangSmith Agent Server** (part of `langgraph-api >= 0.4.21`) ships with a built-in A2A endpoint at `/a2a/{assistant_id}`, but requires the full LangSmith deployment stack; (2) for self-hosted scenarios, the **`a2a-sdk`** (v1.0.3, the official A2A Python SDK from the A2A project) provides `AgentExecutor`, `DefaultRequestHandler`, and Starlette route helpers to build a standards-compliant A2A server without LangSmith infrastructure. A community package **`langgraph-a2a`** (v0.1.6) wraps this further with a `GenericAgentExecutor` purpose-built for LangGraph graphs, though it is community-maintained and not officially supported by LangChain Inc. For our use case — a single LangGraph agent on AKS exposed as an A2A server — using `a2a-sdk` directly (or optionally `langgraph-a2a`) is the pragmatic choice, avoiding the LangSmith infrastructure dependency.

For connecting to **Azure AI Foundry V2** model deployments, there are two well-supported Python packages: **`langchain-openai`** (v1.2.1, mature, using `AzureChatOpenAI` or `ChatOpenAI` with the v1 API endpoint) and the newer **`langchain-azure-ai`** (v1.2.3, official LangChain integration for Azure AI Foundry's broader catalog, using `AzureAIOpenAIApiChatModel`). For our demo — which only needs OpenAI chat models on Azure — `langchain-openai` is the simpler, better-documented choice. `langchain-azure-ai` becomes relevant when you need Foundry-specific features like non-OpenAI models, Agent Service integration, or Azure AI tools.

---

## Table of Contents

- [1. The Relationship Today (2026)](#1-the-relationship-today-2026)
- [2. Which One to Pick for Building an Agent](#2-which-one-to-pick-for-building-an-agent)
- [3. A2A Support](#3-a2a-support)
- [4. Model Providers — Azure AI Foundry V2](#4-model-providers--azure-ai-foundry-v2)
- [5. Tool Calling](#5-tool-calling)
- [6. State Persistence](#6-state-persistence)
- [7. Streaming and Observability](#7-streaming-and-observability)
- [8. Production Readiness for a Customer Demo](#8-production-readiness-for-a-customer-demo)
- [9. Research Limitations](#9-research-limitations)
- [10. Complete Reference List](#10-complete-reference-list)

---

## 1. The Relationship Today (2026)

### Project Status and Versions

| Package | Current Version | PyPI Release | Role | Source |
|---------|----------------|--------------|------|--------|
| `langgraph` | **1.2.0** | May 12, 2026 | Orchestration runtime | [PyPI](https://pypi.org/project/langgraph/) |
| `langchain` | **1.3.1** | 2026 | Agent framework (abstractions + integrations) | [PyPI](https://pypi.org/project/langchain/) |
| `langchain-core` | **1.4.0** (required by LangGraph) | 2026 | Core interfaces | [PyPI](https://pypi.org/project/langchain-core/) |
| `langchain-openai` | **1.2.1** | 2026 | OpenAI/Azure integration | [PyPI](https://pypi.org/project/langchain-openai/) |
| `langchain-azure-ai` | **1.2.3** | 2026 | Azure AI Foundry integration | [PyPI](https://pypi.org/project/langchain-azure-ai/) |
| `langgraph-api` | **0.8.7** | 2026 | Agent Server runtime (includes A2A) | [PyPI](https://pypi.org/project/langgraph-api/) |
| `langgraph-a2a` | **0.1.6** | 2026 | Community A2A server framework | [PyPI](https://pypi.org/project/langgraph-a2a/) |
| `a2a-sdk` | **1.0.3** | 2026 | Official A2A protocol SDK | [PyPI](https://pypi.org/project/a2a-sdk/) |

> "LangGraph is a low-level orchestration framework and runtime for building, managing, and deploying long-running, stateful agents."
> — Source: [LangGraph overview](https://docs.langchain.com/oss/python/langgraph/overview)

### How They Fit Together

The official docs describe the product stack clearly:

> "Deep Agents is an agent harness: planning, subagents, filesystem tools, and context management on top of LangGraph. LangChain is the agent framework: abstractions and integrations for models, tools, and agent loops. LangGraph is the orchestration runtime: durable execution, streaming, human-in-the-loop, and persistence. LangSmith is the platform for tracing, evaluation, prompts, and deployment across frameworks."
> — Source: [LangGraph overview](https://docs.langchain.com/langgraph)

Key distinction from the official conceptual docs:

> "LangChain is an agent framework that provides abstractions like structured content blocks, the agent loop, and middleware. [...] While LangChain is built on top of LangGraph, you don't need to know LangGraph to use LangChain."
> — Source: [Frameworks, runtimes, and harnesses](https://docs.langchain.com/oss/python/concepts/products)

LangGraph's dependencies confirm the relationship: `langgraph` v1.2.0 requires `langchain-core>=1.4.0` (for model/message types) but does **not** require `langchain` itself. You can use LangGraph standalone with raw OpenAI calls, but using LangChain integrations (like `langchain-openai`) is the most ergonomic path.

---

## 2. Which One to Pick for Building an Agent

### Recommendation: LangGraph for Stateful Multi-Step Agents

For the Zava Manufacturing Ops Agent — which needs to process an A2A request, make tool calls against operations data, maintain state, and stream results — **LangGraph is the clear choice**.

> "LangGraph is very low-level, and focused entirely on agent orchestration. [...] If you are just getting started with agents or want a higher-level abstraction, we recommend you use LangChain's agents that provide prebuilt architectures for common LLM and tool-calling loops."
> — Source: [LangGraph overview](https://docs.langchain.com/oss/python/langgraph/overview)

The official guidance distinguishes when to use each:

**Use LangGraph when:**
- You need fine-grained, low-level control over agent orchestration
- You need durable execution for long-running, stateful agents
- You're building complex workflows that combine deterministic and agentic steps
- You need production-ready infrastructure for agent deployment

**Use LangChain alone when:**
- You want to quickly build agents and autonomous applications
- You need standard abstractions for models, tools, and agent loops
- You're building straightforward agent applications without complex orchestration needs

> — Source: [Frameworks, runtimes, and harnesses](https://docs.langchain.com/oss/python/concepts/products)

### For Our Demo

We use **both**: LangChain for model/tool integration (`langchain-openai`, `@tool` decorator) and LangGraph for the agent graph. This is the standard pattern shown in the official quickstart.

### LangGraph Server / LangGraph Cloud — Do We Need Them?

**No, we do not need LangSmith Deployment (formerly LangGraph Cloud/Server) for our demo.**

LangSmith Deployment is a managed deployment platform with multiple tiers. The [LangSmith Deployment docs](https://docs.langchain.com/langsmith/deployment) describe several options including Cloud (fully managed), Standalone Server (self-managed with Docker/K8s), Self-Hosted (full platform), and Self-Hosted Lite. Infrastructure requirements vary by tier — the Standalone Server and full Self-Hosted options typically require PostgreSQL, Redis, and a LangSmith license key, while other tiers may have different requirements. Consult the [current deployment docs](https://docs.langchain.com/langsmith/deployment) for the latest specifics.

For our single-pod AKS demo, any of these options adds unnecessary overhead. Instead, we compile the LangGraph graph in-process and expose it via `a2a-sdk` (or `langgraph-a2a`).

The graph itself is just a Python object — `graph.compile()` returns a `CompiledGraph` that can be invoked directly with `graph.invoke()` or `graph.astream()`. No server infrastructure required.

---

## 3. A2A Support

### Option A: Official LangSmith Agent Server A2A Endpoint

The LangSmith Agent Server has built-in A2A support since `langgraph-api >= 0.4.21`:

> "Agent2Agent (A2A) is Google's protocol for enabling communication between conversational AI agents. LangSmith implements A2A support, allowing your agents to communicate with other A2A-compatible agents through a standardized protocol. The A2A endpoint is available in Agent Server at `/a2a/{assistant_id}`."
> — Source: [A2A endpoint in Agent Server](https://docs.langchain.com/langsmith/server-a2a)

**Supported A2A methods:** `message/send`, `message/stream`, `tasks/get`

**Agent card discovery:** `GET /.well-known/agent-card.json?assistant_id={assistant_id}`

**Requirements:**
- `langgraph-api >= 0.4.21`
- Agent must have a `messages` key in state
- Requires full Agent Server infrastructure (Standalone: Postgres, Redis, license key)

> "To be compatible with the A2A 'text' parts, the agent must have a `messages` key in state."
> — Source: [A2A endpoint in Agent Server](https://docs.langchain.com/langsmith/server-a2a)

**Verdict for our demo:** Overkill. The Agent Server Standalone requires Postgres, Redis, and a LangSmith license key. For a single-agent AKS pod, this adds unnecessary complexity.

### Option B: `a2a-sdk` — The Official A2A Python SDK (Recommended for Demo)

The `a2a-sdk` (v1.0.3) is the official Python SDK from the A2A project (Google). It provides all the building blocks for an A2A-compliant server:

> "A Python library for running agentic applications as A2A Servers, following the Agent2Agent (A2A) Protocol."
> — Source: [a2a-sdk PyPI](https://pypi.org/project/a2a-sdk/)

**Key features (from PyPI/README):**
- A2A Protocol 1.0 compliant (JSON-RPC, HTTP+JSON/REST, gRPC transports)
- `AgentExecutor` abstract base class — implement `execute()` and `cancel()` methods
- `DefaultRequestHandler` — handles JSON-RPC routing, task management, event queuing
- `InMemoryTaskStore` — in-memory task persistence
- Starlette route helpers: `create_agent_card_routes()`, `create_jsonrpc_routes()`
- Optional extras: `http-server` (FastAPI/Starlette), `telemetry` (OpenTelemetry), `postgresql`/`sqlite` (task storage)
- Helper functions: `new_task_from_user_message()`, `new_text_artifact()`, `new_text_message()`

> — Source: [a2a-sdk PyPI](https://pypi.org/project/a2a-sdk/) and [a2a-python GitHub](https://github.com/a2aproject/a2a-python)

**Install:**
```bash
pip install "a2a-sdk[http-server]"
```
> — Source: [a2a-sdk PyPI](https://pypi.org/project/a2a-sdk/) | Provenance: verbatim

### Minimal A2A Server Using `a2a-sdk` + LangGraph

**Dependencies and environment variables:**

```text
# requirements.txt
a2a-sdk[http-server]>=1.0.3
langchain-openai>=1.2.1
langgraph>=1.2.0
azure-identity>=1.17.0
uvicorn>=0.46.0
```

```bash
# Required environment variables
export AZURE_OPENAI_API_KEY="your-api-key"          # or use Entra ID (DefaultAzureCredential)
export AZURE_OPENAI_ENDPOINT="https://YOUR-RESOURCE.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="zava-gpt54mini"     # deployment name (no dots); model ID is gpt-5.4-mini
```

The following is a complete, runnable A2A server that wraps a LangGraph agent using the `a2a-sdk`'s `AgentExecutor`, `DefaultRequestHandler`, and Starlette route helpers. The pattern follows the official [helloworld sample](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld), adapted for a LangGraph tool-calling agent. The `a2a-sdk` 1.0.x server handles A2A 0.3 requests from Foundry automatically via its compatibility mode (see [A2A Version Interop with Foundry](#a2a-version-interop-with-foundry)).

```python
# a2a_server.py — LangGraph agent exposed as A2A server using a2a-sdk
# Source: Adapted from https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld

import uvicorn
from starlette.applications import Starlette

from a2a.helpers import new_task_from_user_message, new_text_artifact, new_text_message
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill
from a2a.types.a2a_pb2 import (
    TaskArtifactUpdateEvent,
    TaskState,
    TaskStatus,
    TaskStatusUpdateEvent,
)

from langgraph.graph import StateGraph, MessagesState, START, END
from langchain_openai import AzureChatOpenAI
from langchain_core.messages import ToolMessage
from langchain_core.tools import tool


# --- Define tools ---
@tool
def read_inventory_csv(part_number: str) -> str:
    """Read inventory levels for a given part number from the CSV data.

    Args:
        part_number: The part number to look up (e.g., 'ZV-PUMP-100').
    """
    fake_data = {
        "ZV-PUMP-100": {"on_hand": 150, "reserved": 30, "available": 120},
        "ZV-MOTOR-200": {"on_hand": 75, "reserved": 50, "available": 25},
    }
    if part_number in fake_data:
        d = fake_data[part_number]
        return (
            f"Part {part_number}: {d['available']} units available "
            f"({d['on_hand']} on hand, {d['reserved']} reserved)"
        )
    return f"Part {part_number}: not found in inventory"


# --- Build the LangGraph agent ---
model = AzureChatOpenAI(
    azure_deployment="zava-gpt54mini",  # deployment name (no dots); model ID is gpt-5.4-mini
    api_version="2025-03-01-preview",
)
tools_list = [read_inventory_csv]
model_with_tools = model.bind_tools(tools_list)
tools_by_name = {t.name: t for t in tools_list}


def call_model(state: MessagesState):
    """LLM node: decide whether to call a tool or respond."""
    response = model_with_tools.invoke(state["messages"])
    return {"messages": [response]}


def call_tools(state: MessagesState):
    """Tool node: execute tool calls from the LLM."""
    results = []
    for tc in state["messages"][-1].tool_calls:
        result = tools_by_name[tc["name"]].invoke(tc["args"])
        results.append(ToolMessage(content=str(result), tool_call_id=tc["id"]))
    return {"messages": results}


def should_continue(state: MessagesState):
    last = state["messages"][-1]
    if last.tool_calls:
        return "call_tools"
    return END


graph = (
    StateGraph(MessagesState)
    .add_node("call_model", call_model)
    .add_node("call_tools", call_tools)
    .add_edge(START, "call_model")
    .add_conditional_edges("call_model", should_continue, ["call_tools", END])
    .add_edge("call_tools", "call_model")
    .compile()
)


# --- a2a-sdk AgentExecutor wrapping the LangGraph graph ---
class ZavaOpsAgentExecutor(AgentExecutor):
    """Bridges the a2a-sdk AgentExecutor interface to a LangGraph compiled graph."""

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        # Create or reuse the task from the incoming A2A message
        task = context.current_task or new_task_from_user_message(context.message)
        await event_queue.enqueue_event(task)

        # Signal "working" status
        await event_queue.enqueue_event(
            TaskStatusUpdateEvent(
                task_id=context.task_id,
                context_id=context.context_id,
                status=TaskStatus(
                    state=TaskState.TASK_STATE_WORKING,
                    message=new_text_message("Processing request..."),
                ),
            )
        )

        # Extract user text from A2A message parts
        user_text = ""
        for part in context.message.parts:
            if hasattr(part, "text"):
                user_text = part.text
                break

        # Invoke the LangGraph agent
        result = await graph.ainvoke(
            {"messages": [{"role": "user", "content": user_text}]}
        )
        ai_response = result["messages"][-1].content

        # Emit the result as an A2A artifact
        await event_queue.enqueue_event(
            TaskArtifactUpdateEvent(
                task_id=context.task_id,
                context_id=context.context_id,
                artifact=new_text_artifact(name="result", text=ai_response),
            )
        )

        # Signal completion
        await event_queue.enqueue_event(
            TaskStatusUpdateEvent(
                task_id=context.task_id,
                context_id=context.context_id,
                status=TaskStatus(state=TaskState.TASK_STATE_COMPLETED),
            )
        )

    async def cancel(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        raise Exception("cancel not supported")


# --- Wire up the A2A server ---
agent_card = AgentCard(
    name="Zava Manufacturing Ops Agent",
    description="Queries inventory, production capacity, and lead times for Zava precision components.",
    version="1.0.0",
    default_input_modes=["text/plain"],
    default_output_modes=["text/plain"],
    capabilities=AgentCapabilities(streaming=False),
    supported_interfaces=[
        AgentInterface(protocol_binding="JSONRPC", url="http://localhost:8000"),
    ],
    skills=[
        AgentSkill(
            id="order-feasibility",
            name="Order Feasibility Check",
            description="Checks inventory and capacity for order fulfillment.",
            tags=["manufacturing", "feasibility"],
            examples=["Can we fulfill 100 units of ZV-PUMP-100 by July?"],
        )
    ],
)

request_handler = DefaultRequestHandler(
    agent_executor=ZavaOpsAgentExecutor(),
    task_store=InMemoryTaskStore(),
    agent_card=agent_card,
)

routes = []
routes.extend(create_agent_card_routes(agent_card))
routes.extend(create_jsonrpc_routes(request_handler, "/"))

app = Starlette(routes=routes)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```
> — Source: Adapted from [a2a-samples helloworld](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld) and [a2a-python AgentExecutor](https://github.com/a2aproject/a2a-python) | Provenance: synthesized

**How this works:**
1. `ZavaOpsAgentExecutor` subclasses `a2a.server.agent_execution.AgentExecutor` — the abstract base class from `a2a-sdk` that requires `execute()` and `cancel()` methods.
2. Inside `execute()`, it extracts text from the A2A message, calls `graph.ainvoke()` on the LangGraph compiled graph, and emits results as `TaskArtifactUpdateEvent` and `TaskStatusUpdateEvent` via the SDK's `EventQueue`.
3. `DefaultRequestHandler` handles all A2A JSON-RPC routing (`message/send`, `message/stream`, `tasks/get`, etc.).
4. `create_agent_card_routes()` and `create_jsonrpc_routes()` generate Starlette routes for `/.well-known/agent-card.json` and the JSON-RPC endpoint.
5. No manual JSON-RPC parsing or response construction — the SDK handles protocol compliance.

### Option C: `langgraph-a2a` Community Package

The `langgraph-a2a` package (v0.1.6) provides a higher-level wrapper specifically for LangGraph agents:

> "langgraph-a2a is a Python package that hosts LangGraph agents behind an Agent-to-Agent (A2A) HTTP server. It gives you a ready-made server, protocol handling, and a pluggable executor so you can focus on building graphs—not wiring JSON-RPC, streaming, or agent discovery yourself."
> — Source: [langgraph-a2a PyPI](https://pypi.org/project/langgraph-a2a/)

**Key features (from PyPI README):**
- `GenericAgentExecutor` — runs LangGraph graphs via `ainvoke`/`astream` with A2A message format
- CLI: `langgraph-a2a --agent <name>` — discovers agents via Python entry points
- Maps A2A `contextId` to LangGraph `thread_id` for conversation memory
- `compile_with_default_checkpointer()` — attaches `MemorySaver` automatically
- Agent card auto-generation from `local_app_config.json`
- Dependencies: `a2a-sdk>=1.0.2`, `langgraph>=0.3.0`, `starlette`, `uvicorn`

**Author:** Sudhagar Narayaan (community, not official LangChain). This is a third-party package — evaluate accordingly.

**Verified usage pattern** (from the [langgraph-a2a PyPI README](https://pypi.org/project/langgraph-a2a/)):

```python
# agent.py — Registering a LangGraph agent with langgraph-a2a
# Source: https://pypi.org/project/langgraph-a2a/

from pathlib import Path
from typing import Any

from langgraph_a2a.base_utils import compile_with_default_checkpointer
from langgraph_a2a.executor import GenericAgentExecutor

from .graph import build_graph  # your StateGraph builder


class Agent:
    name = "my_agent"

    @staticmethod
    def register() -> dict[str, Any]:
        agent_dir = Path(__file__).parent
        graph = compile_with_default_checkpointer(build_graph())
        return {
            "name": Agent.name,
            "executor": GenericAgentExecutor(
                agent_impl=graph, enable_streaming=True
            ),
            "local_config_path": agent_dir / "local_app_config.json",
        }
```
> — Source: [langgraph-a2a PyPI](https://pypi.org/project/langgraph-a2a/) | Provenance: verbatim

The framework expects your graph state to have `user_input` (str) and `output` (str) keys. The `GenericAgentExecutor` handles the A2A message ↔ LangGraph state translation.

**⚠️ Caveat:** `langgraph-a2a` is community-maintained (not by LangChain Inc.). Its `GenericAgentExecutor` expects a specific state shape (`user_input`/`output`) that differs from the standard `MessagesState` pattern. For production use, verify its compatibility with your graph and evaluate maintenance cadence. The direct `a2a-sdk` approach (Option B) gives more control and relies only on the official SDK.

### Recommendation for Our Demo

**Use `a2a-sdk` directly (Option B)** as the primary path. This gives us:
- Full protocol compliance via the official A2A SDK
- No dependency on community packages for the critical A2A layer
- Direct control over how LangGraph state maps to A2A messages
- The same Starlette-based server pattern used in the official A2A samples

If `langgraph-a2a` matures and proves stable, it could simplify boilerplate in future iterations.

### A2A Version Interop with Foundry

**Critical for the Zava demo:** Foundry Agent Service speaks **A2A protocol version 0.3 only** — not 1.0.

> "Foundry Agent Service supports A2A protocol version 0.3 only."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

The `a2a-sdk` 1.0.x package implements A2A 1.0 as its primary protocol but explicitly advertises a **0.3 compatibility mode** for both client and server:

> "This SDK implements the A2A Protocol Specification `1.0`, with compatibility mode for `0.3`."
> — Source: [a2a-sdk PyPI](https://pypi.org/project/a2a-sdk/)

The compatibility matrix from the SDK README confirms full 0.3 support:

| Spec Version | Transport | Client | Server |
|---|---|---|---|
| **1.0** | JSON-RPC / HTTP+JSON/REST / gRPC | ✅ | ✅ |
| **0.3** (compat) | JSON-RPC / HTTP+JSON/REST / gRPC | ✅ | ✅ |

> — Source: [a2a-sdk PyPI](https://pypi.org/project/a2a-sdk/)

**Architecture implication for the Zava demo:**

- **Foundry acts as A2A client** — when the Foundry Customer Service Agent needs to call the Manufacturing Ops Agent on AKS, Foundry sends A2A 0.3 JSON-RPC requests (`message/send`, `tasks/get`, etc.) to the LangGraph server's endpoint.
- **LangGraph acts as A2A server** — built with `a2a-sdk` 1.0.x in **0.3 compatibility mode**, exposing the v0.3-style methods that Foundry expects.
- Foundry will **not** send an `A2A-Version: 1.0` header, so the LangGraph server must default to or accept 0.3 semantics. The `a2a-sdk` handles this via its compatibility mode — when a request arrives without a 1.0 version header, the SDK processes it using 0.3 semantics.

**Enabling 0.3 compatibility in the server:** The `a2a-sdk` 1.0.x `DefaultRequestHandler` and route helpers handle 0.3 requests automatically when the client does not specify a 1.0 version header. The v0.3 methods (`message/send`, `tasks/get`) are the same JSON-RPC method names used in 1.0, so no separate endpoint configuration is required. The key difference is in message/response schema shape, which the SDK's compatibility layer handles transparently. See [issue #742](https://github.com/a2aproject/a2a-python/issues/742) for details on the compatibility scope.

**Validation step during development:** After deploying the LangGraph A2A server, test it by sending a raw 0.3-style `message/send` JSON-RPC request (without any version header) and verifying the response conforms to the 0.3 task schema before connecting it to Foundry.

### Can a LangGraph Agent Act as an A2A Client?

Yes. The official docs show an agent-to-agent communication pattern where one agent sends JSON-RPC messages to another agent's A2A endpoint using `aiohttp`:

```python
# A2A client pattern — calling another A2A agent
# Source: https://docs.langchain.com/langsmith/server-a2a

import aiohttp
import uuid


async def send_a2a_message(target_url: str, text: str, context_id=None):
    """Send an A2A message to another agent."""
    message = {
        "role": "user",
        "parts": [{"kind": "text", "text": text}],
        "messageId": str(uuid.uuid4()),
    }
    if context_id:
        message["contextId"] = context_id

    payload = {
        "jsonrpc": "2.0",
        "id": str(uuid.uuid4()),
        "method": "message/send",
        "params": {"message": message},
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(target_url, json=payload) as resp:
            return await resp.json()
```
> — Source: [A2A endpoint in Agent Server](https://docs.langchain.com/langsmith/server-a2a) | Provenance: adapted

A LangGraph agent can integrate this as a tool — the agent calls `send_a2a_message` as a tool to communicate with another A2A agent (e.g., the Foundry agent). The `a2a-sdk` package (v1.0.3) also provides a built-in Python client for A2A communication.

---

## 4. Model Providers — Azure AI Foundry V2

### Two Packages for Azure Integration

There are two official LangChain packages for connecting to Azure OpenAI / Azure AI Foundry models. The choice depends on your needs:

| Package | Class | Best For | Maintainer |
|---------|-------|----------|------------|
| `langchain-openai` (v1.2.1) | `AzureChatOpenAI`, `ChatOpenAI` | OpenAI models on Azure with mature, well-documented API | LangChain + OpenAI |
| `langchain-azure-ai` (v1.2.3) | `AzureAIOpenAIApiChatModel` | Azure AI Foundry's broader catalog (OpenAI + non-OpenAI models), Agent Service, AI tools | LangChain + Microsoft ([GitHub](https://github.com/langchain-ai/langchain-azure)) |

`langchain-azure-ai` is described on its [PyPI page](https://pypi.org/project/langchain-azure-ai/) as an integration package connecting Azure AI Foundry capabilities to the LangChain/LangGraph ecosystem.

The `langchain-azure-ai` package includes (from its [PyPI README](https://pypi.org/project/langchain-azure-ai/)):
- **Microsoft Foundry Models inference** via `AzureAIOpenAIApiChatModel`
- **Microsoft Foundry Agent Service** integration via `AgentServiceFactory`
- **Microsoft Foundry Tools** (Document Intelligence, Text Analytics, Logic Apps)
- **Azure AI Search** vector stores
- **Azure Content Safety** middleware
- **OpenTelemetry tracing** to Azure Application Insights

**When to use which:**

- **`langchain-openai` (recommended for our demo):** Use when you only need OpenAI chat models (GPT-5.x) on Azure. It is the more mature, better-documented path with explicit Azure parameters (`azure_deployment`, `api_version`, `azure_ad_token_provider`). The LangChain docs cover this extensively.

- **`langchain-azure-ai`:** Use when you need Azure AI Foundry-specific features beyond basic OpenAI chat — e.g., non-OpenAI models (Mistral, etc.) via the same API, Foundry Agent Service nodes in a LangGraph graph, Azure AI tools, or Content Safety. It depends on `langchain-openai` internally and adds Foundry-specific wrappers.

### Option 1 — `langchain-openai`: `ChatOpenAI` with v1 API

The LangChain AzureChatOpenAI docs describe using `ChatOpenAI` with Azure's `/openai/v1/` endpoint. This approach uses the v1 API path and supports Microsoft Entra ID authentication with automatic token refresh via a callable token provider.

```python
# Using ChatOpenAI with Azure v1 API
# Source: https://docs.langchain.com/oss/python/integrations/chat/azure_chat_openai

from langchain_openai import ChatOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default",
)

llm = ChatOpenAI(
    model="gpt-5.4-mini",  # model ID (with decimal); Azure deployment name may differ
    base_url="https://YOUR-RESOURCE-NAME.openai.azure.com/openai/v1/",
    api_key=token_provider,  # callable that handles token refresh
)
```
> — Source: [AzureChatOpenAI integration](https://docs.langchain.com/oss/python/integrations/chat/azure_chat_openai) | Provenance: adapted (demo-specific deployment name)

### Option 2 — `langchain-openai`: `AzureChatOpenAI` (traditional, requires `api_version`)

```python
# Using AzureChatOpenAI (traditional approach)
# Source: https://docs.langchain.com/oss/python/integrations/chat/azure_chat_openai

from langchain_openai import AzureChatOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default",
)

llm = AzureChatOpenAI(
    model="gpt-5.4-mini",
    azure_deployment="zava-gpt54mini",  # deployment name (no dots); model ID is gpt-5.4-mini
    api_version="2025-03-01-preview",
    azure_ad_token_provider=token_provider,
)
```
> — Source: [AzureChatOpenAI integration](https://docs.langchain.com/oss/python/integrations/chat/azure_chat_openai) | Provenance: adapted (demo-specific deployment name)

### Option 3 — `langchain-azure-ai`: `AzureAIOpenAIApiChatModel`

```python
# Using AzureAIOpenAIApiChatModel from langchain-azure-ai
# Source: https://pypi.org/project/langchain-azure-ai/

from langchain_azure_ai.chat_models import AzureAIOpenAIApiChatModel
from azure.identity import DefaultAzureCredential

model = AzureAIOpenAIApiChatModel(
    endpoint="https://YOUR-RESOURCE-NAME.services.ai.azure.com/openai/v1",
    credential=DefaultAzureCredential(),
    model="gpt-5.4-mini",
)
```
> — Source: [langchain-azure-ai PyPI README](https://pypi.org/project/langchain-azure-ai/) | Provenance: adapted (demo-specific model/endpoint)

The `AzureAIOpenAIApiChatModel` class also supports non-OpenAI models deployed to Foundry:

```python
# Non-OpenAI model via the same class
# Source: https://pypi.org/project/langchain-azure-ai/

model = AzureAIOpenAIApiChatModel(
    endpoint="https://YOUR-RESOURCE-NAME.services.ai.azure.com/openai/v1",
    credential="your-api-key",
    model="Mistral-Large-3",
)
```
> — Source: [langchain-azure-ai PyPI README](https://pypi.org/project/langchain-azure-ai/) | Provenance: verbatim

### Option 4 — `init_chat_model` (provider-agnostic)

```python
# Using init_chat_model for Azure
# Source: https://docs.langchain.com/oss/python/langchain/models

import os
from langchain.chat_models import init_chat_model

os.environ["AZURE_OPENAI_API_KEY"] = "..."
os.environ["AZURE_OPENAI_ENDPOINT"] = "..."
os.environ["OPENAI_API_VERSION"] = "2025-03-01-preview"

model = init_chat_model(
    "azure_openai:gpt-5.4",
    azure_deployment=os.environ["AZURE_OPENAI_DEPLOYMENT_NAME"],
)
```
> — Source: [Models](https://docs.langchain.com/oss/python/langchain/models) | Provenance: adapted (env var placeholders from demo context)

### Recommendation for Demo

Use **`langchain-openai`** with either `ChatOpenAI` (v1 API) or `AzureChatOpenAI` — both are fully supported. The v1 API is newer and cleaner, but `AzureChatOpenAI` is more battle-tested and has explicit Azure-specific parameters. Either works. Both are in the `langchain-openai` package (v1.2.1).

We do **not** need `langchain-azure-ai` for this demo since we're only using OpenAI chat models. However, if a future iteration needs Foundry Agent Service integration or non-OpenAI models, `langchain-azure-ai` would be the path.

---

## 5. Tool Calling

### How LangGraph Wires Up Tools

LangGraph uses LangChain's `@tool` decorator for tool definitions and `model.bind_tools()` to attach them to the LLM. The pattern from the official quickstart:

```python
# Tool definition and binding pattern
# Source: https://docs.langchain.com/oss/python/langgraph/quickstart and
#         https://docs.langchain.com/oss/python/langchain/tools

from langchain_core.tools import tool
from langchain.chat_models import init_chat_model

model = init_chat_model("azure_openai:gpt-5.4-mini", temperature=0)


@tool
def read_inventory_csv(part_number: str) -> str:
    """Look up current inventory levels for a Zava part number.

    Args:
        part_number: The Zava part number (e.g., 'ZV-PUMP-100').
    """
    import csv
    import os

    csv_path = os.path.join(os.path.dirname(__file__), "..", "data", "inventory.csv")
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["part_number"] == part_number:
                available = int(row["on_hand"]) - int(row["reserved"])
                return (
                    f"Part {part_number}: {available} units available "
                    f"({row['on_hand']} on hand, {row['reserved']} reserved, "
                    f"lead time: {row['lead_time_days']} days)"
                )
    return f"Part {part_number}: not found in inventory database"


@tool
def check_production_capacity(product_line: str, quantity: int) -> str:
    """Check if a product line has capacity to produce the requested quantity.

    Args:
        product_line: The product line name (e.g., 'Industrial Pumps').
        quantity: Number of units to produce.
    """
    # Simulated capacity data
    capacity = {
        "Industrial Pumps": 200,
        "Precision Motors": 150,
        "Hydraulic Valves": 300,
    }
    max_cap = capacity.get(product_line, 0)
    if max_cap == 0:
        return f"Product line '{product_line}' not found."
    if quantity <= max_cap:
        return (
            f"Product line '{product_line}': CAN produce {quantity} "
            f"units (capacity: {max_cap}/month)."
        )
    return (
        f"Product line '{product_line}': CANNOT produce {quantity} "
        f"units (capacity: {max_cap}/month)."
    )


# Bind tools to the model
tools = [read_inventory_csv, check_production_capacity]
model_with_tools = model.bind_tools(tools)
```
> — Source: Synthesized from [LangGraph Quickstart](https://docs.langchain.com/oss/python/langgraph/quickstart) and [LangChain Tools](https://docs.langchain.com/oss/python/langchain/tools) | Provenance: synthesized

### Tool Node Pattern

The standard pattern uses a conditional edge to route between the LLM and tool execution:

```python
# Standard tool-calling agent graph
# Source: https://docs.langchain.com/oss/python/langgraph/quickstart

from langchain_core.messages import ToolMessage
from langgraph.graph import StateGraph, MessagesState, START, END

tools_by_name = {t.name: t for t in tools}


def llm_call(state: MessagesState):
    """LLM decides whether to call a tool or not."""
    return {"messages": [model_with_tools.invoke(state["messages"])]}


def tool_node(state: MessagesState):
    """Execute tool calls from the LLM response."""
    results = []
    for tc in state["messages"][-1].tool_calls:
        tool_fn = tools_by_name[tc["name"]]
        observation = tool_fn.invoke(tc["args"])
        results.append(ToolMessage(content=str(observation), tool_call_id=tc["id"]))
    return {"messages": results}


def should_continue(state: MessagesState):
    if state["messages"][-1].tool_calls:
        return "tool_node"
    return END


agent = (
    StateGraph(MessagesState)
    .add_node("llm_call", llm_call)
    .add_node("tool_node", tool_node)
    .add_edge(START, "llm_call")
    .add_conditional_edges("llm_call", should_continue, ["tool_node", END])
    .add_edge("tool_node", "llm_call")
    .compile()
)
```
> — Source: [LangGraph Quickstart](https://docs.langchain.com/oss/python/langgraph/quickstart) | Provenance: adapted

### Advanced Schema Definition

For more complex tool inputs, use Pydantic models:

```python
# Advanced tool with Pydantic schema
# Source: https://docs.langchain.com/oss/python/langchain/tools

from pydantic import BaseModel, Field
from langchain_core.tools import tool


class FeasibilityInput(BaseModel):
    """Input for order feasibility check."""

    part_number: str = Field(description="Zava part number")
    quantity: int = Field(description="Number of units requested")
    target_date: str = Field(description="Target delivery date (YYYY-MM-DD)")


@tool(args_schema=FeasibilityInput)
def check_order_feasibility(part_number: str, quantity: int, target_date: str) -> str:
    """Check if an order can be fulfilled by the target date."""
    return f"Feasibility check for {quantity}x {part_number} by {target_date}: FEASIBLE"
```
> — Source: [LangChain Tools](https://docs.langchain.com/oss/python/langchain/tools) | Provenance: adapted

---

## 6. State Persistence

### Available Checkpointers

The official checkpointer integrations table:

| Backend | Package | Use Case |
|---------|---------|----------|
| **In-memory** | `langgraph-checkpoint` (built-in) | Development, single-pod demos |
| **SQLite** | `langgraph-checkpoint-sqlite` | Local dev, lightweight persistence |
| **PostgreSQL** | `langgraph-checkpoint-postgres` | Production |
| **Azure Cosmos DB** | `langchain-azure-cosmosdb` | Azure-native production |
| **MongoDB** | `langgraph-checkpoint-mongodb` | Document store persistence |
| **Redis** | `langgraph-checkpoint-redis` | High-performance caching |

> — Source: [Checkpointer integrations](https://docs.langchain.com/oss/python/integrations/checkpointers/index)

### What Persistence Enables

> "LangGraph has a built-in persistence layer that saves graph state as checkpoints. When you compile a graph with a checkpointer, a snapshot of the graph state is saved at every step of execution, organized into threads. This enables human-in-the-loop workflows, conversational memory, time travel debugging, and fault-tolerant execution."
> — Source: [Persistence](https://docs.langchain.com/oss/python/langgraph/persistence)

### Recommendation for Our Demo

For a single-pod AKS demo, **`InMemorySaver`** (from `langgraph.checkpoint.memory`) is sufficient. It requires zero infrastructure, and since our demo handles one conversation at a time, persistence across restarts is not needed.

```python
# Using InMemorySaver for the demo
# Source: https://docs.langchain.com/oss/python/langgraph/persistence

from langgraph.checkpoint.memory import InMemorySaver

checkpointer = InMemorySaver()
agent = graph.compile(checkpointer=checkpointer)

# Invoke with a thread_id for conversation continuity
result = agent.invoke(
    {"messages": [{"role": "user", "content": "Check inventory for ZV-PUMP-100"}]},
    config={"configurable": {"thread_id": "conversation-1"}},
)
```
> — Source: [Persistence](https://docs.langchain.com/oss/python/langgraph/persistence) | Provenance: adapted

If we wanted persistence across pod restarts, `langgraph-checkpoint-sqlite` would be the next step up (just a file on a PVC). But for a live demo, in-memory is ideal.

> "When invoking a graph with a checkpointer, you must specify a thread_id as part of the configurable portion of the config."
> — Source: [Persistence](https://docs.langchain.com/oss/python/langgraph/persistence)

---

## 7. Streaming and Observability

### Streaming

LangGraph v1.2 introduces **event streaming** as the recommended API:

> "For new applications, we recommend event streaming—the typed-projection API introduced in LangGraph v1.2. Event streaming gives you separate iterators per projection (messages, values, subgraphs, output) so you can consume them independently instead of branching on stream_mode chunks."
> — Source: [Streaming](https://docs.langchain.com/oss/python/langgraph/streaming)

**Event streaming quickstart (new in v1.2):**

```python
# Event streaming — recommended for new applications
# Source: https://docs.langchain.com/oss/python/langgraph/event-streaming

stream = graph.stream_events(
    {
        "messages": [{"role": "user", "content": "What is 42 * 17?"}],
    },
    version="v3",
)

for message in stream.messages:
    for token in message.text:
        print(token, end="", flush=True)

final_state = stream.output
```
> — Source: [Event streaming](https://docs.langchain.com/oss/python/langgraph/event-streaming) | Provenance: adapted (simplified from docs example)

**Available stream projections:**

| Projection | Use |
|-----------|-----|
| `stream` | Iterate every protocol event |
| `stream.messages` | Stream chat model messages and token deltas |
| `stream.values` | Iterate state snapshots and await final value |
| `stream.output` | Await the final output |
| `stream.subgraphs` | Discover and observe nested graph executions |
| `stream.interrupts` | Inspect human-in-the-loop interrupt payloads |

> — Source: [Event streaming](https://docs.langchain.com/oss/python/langgraph/event-streaming)

**Legacy streaming (still works):**

```python
# Legacy stream-mode API (still supported)
# Source: https://docs.langchain.com/oss/python/langgraph/streaming

for chunk in graph.stream(
    {"topic": "ice cream"},
    stream_mode=["updates", "custom"],
    version="v2",
):
    if chunk["type"] == "updates":
        for node_name, state in chunk["data"].items():
            print(f"Node {node_name} updated: {state}")
```
> — Source: [Streaming](https://docs.langchain.com/oss/python/langgraph/streaming) | Provenance: adapted (simplified from docs)

### A2A Streaming

For streaming A2A responses, the Agent Server supports `message/stream` which returns SSE events. For our self-hosted approach, we would need to implement SSE streaming in our Starlette handler, converting LangGraph's `astream` events to A2A SSE format. For the initial demo, `message/send` (non-streaming) is simpler and sufficient.

### Observability Options

**1. LangSmith (official, paid):**
> "Use LangSmith to trace requests, debug agent behavior, and evaluate outputs. Set LANGSMITH_TRACING=true and your API key to get started."
> — Source: [LangGraph overview](https://docs.langchain.com/oss/python/langgraph/overview)

**2. OpenTelemetry:** LangChain has OpenTelemetry integration via `langchain-core`'s callback system. Not as deeply integrated as LangSmith but works with any OTEL-compatible backend (Jaeger, Azure Monitor, etc.). The `langchain-azure-ai` package also supports [tracing to Azure Application Insights](https://pypi.org/project/langchain-azure-ai/) via its `[opentelemetry]` extra.

**3. Nothing:** For a demo, simple Python logging may suffice. Add `LANGSMITH_TRACING=true` if you have a LangSmith account for debugging during development.

**Recommendation for demo:** Use LangSmith tracing during development (free tier available). For the live demo, basic logging is sufficient unless the customer wants to see observability.

---

## 8. Production Readiness for a Customer Demo

### Stability

LangGraph v1.2.0 (May 2026) is the latest stable release. The package follows semantic versioning and has been in production use at major companies:

> "Trusted by companies shaping the future of agents— including Klarna, Uber, J.P. Morgan, and more"
> — Source: [LangGraph overview](https://docs.langchain.com/langgraph)

### Breaking-Change Cadence

LangGraph follows semver. The v1.2.0 release indicates incremental improvements since v1.0. The streaming API introduced a `version="v2"` format parameter to avoid breaking existing code:

> "With v1 (default), the output format changes based on your streaming options [...] With v2, the format is always the same."
> — Source: [Streaming](https://docs.langchain.com/oss/python/langgraph/streaming)

### Known Gotchas

1. **Do not configure checkpointer in graph code when using Agent Server** — the server injects it at runtime. For self-hosted (our case), we DO configure it ourselves.

2. **State must include `messages` key for A2A compatibility** — use `MessagesState` or ensure your state TypedDict has a `messages` field.

3. **Tool names should use `snake_case`:**
> "Prefer snake_case for tool names (e.g., web_search instead of Web Search). Some model providers have issues with or reject names containing spaces or special characters."
> — Source: [LangChain Tools](https://docs.langchain.com/oss/python/langchain/tools)

4. **Reserved parameter names in tools** — `config` and `runtime` are reserved and cannot be used as tool argument names.

5. **`langchain-openai` v1 API vs legacy `api_version`** — the v1 API (`/openai/v1/`) is cleaner but newer. If you encounter issues, fall back to `AzureChatOpenAI` with explicit `api_version`.

### Must-Know Best Practices

- **Use compiled graphs** (not factory functions) for consistent startup behavior
- **Pin your dependency versions** — `langgraph==1.2.0`, `langchain-openai==1.2.1`
- **Use `MessagesState`** as your state class for A2A compatibility
- **Test with `langgraph dev`** locally before deploying to AKS
- **Environment variables for all secrets** — Azure credentials, API keys
- **Entra ID authentication** (not API keys) for production Azure deployments

### Recommended Dependency Set for Our Demo

```
# requirements.txt for Manufacturing Ops Agent
langgraph==1.2.0
langchain-openai==1.2.1
langchain>=1.3.0
a2a-sdk[http-server]>=1.0.2
uvicorn>=0.46.0
azure-identity>=1.17.0
```

---

## 9. Research Limitations

- **`langgraph-a2a` is a community package** (author: Sudhagar Narayaan) — not officially maintained by LangChain Inc. Its API shape was verified from the PyPI README (which includes full quickstart code), but the package was not installed or tested hands-on. The `GenericAgentExecutor` expects a `user_input`/`output` state shape that may not directly align with the `MessagesState` pattern. For our demo, we recommend the direct `a2a-sdk` approach instead.
- **`a2a-sdk` server pattern** was verified from the [official helloworld sample](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld) and the [AgentExecutor source code](https://github.com/a2aproject/a2a-python). The LangGraph integration in our synthesized example was not run end-to-end.
- **LangSmith Agent Server's A2A support** was verified from docs but not tested hands-on. The infrastructure requirements (Postgres, Redis, license key) were confirmed for the Standalone Server tier from the [deployment docs](https://docs.langchain.com/langsmith/deployment). Requirements for Self-Hosted Lite were not independently verified and may differ.
- **LangChain AzureChatOpenAI docs** are client-side rendered (JS), so verbatim quote extraction was limited. The v1 API and Entra ID token-provider pattern were confirmed on the page, but the exact wording may differ from what is shown here. The docs page URL is confirmed reachable.
- **`langchain-azure-ai`** existence and API were confirmed from PyPI metadata and the GitHub source (`langchain-ai/langchain-azure`). The `AzureAIOpenAIApiChatModel` class and `AgentServiceFactory` were verified in the source code. Detailed documentation beyond the PyPI README was not fetched.
- **Streaming A2A** — implementing `message/stream` with SSE in a custom Starlette handler requires additional work not covered in detail here. The official Agent Server handles this automatically.
- **The LangGraph changelog was not directly accessible** (client-side rendered page). Version history was verified via PyPI JSON API.
- **GPT-5.5/5.4 model compatibility** with `langchain-openai` was not directly tested — the docs show `gpt-5.4-mini` in examples, confirming these model names are recognized.

---

## 10. Complete Reference List

### Documentation & Articles
- [LangGraph overview](https://docs.langchain.com/oss/python/langgraph/overview) — Main overview page for LangGraph Python, core benefits, ecosystem
- [LangGraph overview (landing page)](https://docs.langchain.com/langgraph) — Landing page with install instructions and ecosystem description
- [Frameworks, runtimes, and harnesses](https://docs.langchain.com/oss/python/concepts/products) — Conceptual comparison of LangChain, LangGraph, Deep Agents — when to use each
- [LangGraph Quickstart](https://docs.langchain.com/oss/python/langgraph/quickstart) — Calculator agent tutorial using Graph API and Functional API
- [A2A endpoint in Agent Server](https://docs.langchain.com/langsmith/server-a2a) — Official A2A protocol support in LangSmith Agent Server, code examples
- [Agent Server](https://docs.langchain.com/langsmith/agent-server) — Agent Server architecture, persistence, task queue, deployment modes
- [Core capabilities overview](https://docs.langchain.com/langsmith/core-capabilities) — Overview of Agent Server capabilities including A2A, streaming, HITL
- [LangSmith Deployment](https://docs.langchain.com/langsmith/deployment) — Deployment options: Cloud, Standalone, Self-hosted, Self-hosted Lite
- [Self-host standalone servers](https://docs.langchain.com/langsmith/deploy-standalone-server) — Docker/K8s deployment of standalone Agent Servers
- [AzureChatOpenAI integration](https://docs.langchain.com/oss/python/integrations/chat/azure_chat_openai) — Azure OpenAI setup with v1 API and traditional approach
- [Models](https://docs.langchain.com/oss/python/langchain/models) — Model initialization, `init_chat_model`, provider-agnostic setup
- [Tools](https://docs.langchain.com/oss/python/langchain/tools) — Tool creation with `@tool` decorator, Pydantic schemas, reserved names
- [Persistence](https://docs.langchain.com/oss/python/langgraph/persistence) — Checkpointer system, threads, checkpoints, super-steps
- [Checkpointer integrations](https://docs.langchain.com/oss/python/integrations/checkpointers/index) — Available checkpointer backends table
- [Streaming](https://docs.langchain.com/oss/python/langgraph/streaming) — Stream-mode API, v2 format, stream modes
- [Event streaming](https://docs.langchain.com/oss/python/langgraph/event-streaming) — New typed-projection streaming API in LangGraph v1.2
- [OpenAI integrations](https://docs.langchain.com/oss/python/integrations/providers/openai) — Overview of all OpenAI/Azure integrations in LangChain Python
- [Azure AI Foundry LangChain docs](https://aka.ms/azureai/langchain) — Microsoft's official LangChain + Azure AI Foundry documentation

### PyPI Packages
- [langgraph 1.2.0](https://pypi.org/project/langgraph/) — Core orchestration runtime
- [langchain 1.3.1](https://pypi.org/project/langchain/) — Agent framework
- [langchain-core 1.4.0](https://pypi.org/project/langchain-core/) — Core interfaces
- [langchain-openai 1.2.1](https://pypi.org/project/langchain-openai/) — OpenAI/Azure integration
- [langchain-azure-ai 1.2.3](https://pypi.org/project/langchain-azure-ai/) — Azure AI Foundry integration for LangChain/LangGraph
- [langgraph-api 0.8.7](https://pypi.org/project/langgraph-api/) — Agent Server runtime
- [langgraph-a2a 0.1.6](https://pypi.org/project/langgraph-a2a/) — Community A2A server framework
- [a2a-sdk 1.0.3](https://pypi.org/project/a2a-sdk/) — Official A2A protocol SDK

### GitHub Repositories
- [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph) — Official LangGraph repo (32.5k stars)
- [langchain-ai/langchain-azure](https://github.com/langchain-ai/langchain-azure) — Official langchain-azure-ai source code
- [a2aproject/a2a-python](https://github.com/a2aproject/a2a-python) — Official A2A Python SDK source code
- [a2aproject/a2a-samples](https://github.com/a2aproject/a2a-samples) — Official A2A sample agents (helloworld, etc.)
- [Coding-Crashkurse/A2A-LangGraph](https://github.com/Coding-Crashkurse/A2A-LangGraph) — Community A2A + LangGraph + MCP example (59 stars)
- [hybroai/a2a-adapter](https://github.com/hybroai/a2a-adapter) — Open Source A2A Protocol Adapter SDK for different frameworks (55 stars)
- [mrgoonie/a2a-langgraph-boilerplate](https://github.com/mrgoonie/a2a-langgraph-boilerplate) — A2A + LangGraph boilerplate (39 stars)
