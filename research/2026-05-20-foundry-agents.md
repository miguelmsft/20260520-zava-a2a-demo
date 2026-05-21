# Research Report: Microsoft Foundry Agents V2

**Date:** 2026-05-20
**Researcher:** Copilot MS Docs Researcher Agent
**Topic slug:** foundry-agents
**Sources consulted:** 32 Microsoft Learn pages, 3 GitHub repositories, 1 code sample/template

> **Note on source count categorization:** The "32 Microsoft Learn pages" total combines all `learn.microsoft.com` references across the categorized subsections below (Microsoft Learn Documentation = 27, Python SDK Documentation = 2, Microsoft Agent Framework & Training = 3). Access date for all sources: 2026-05-20.

---

## Executive Summary

Microsoft Foundry Agent Service (the "new" or "V2" agents) is the current-generation agent platform within Microsoft Foundry (project-based, not Foundry Classic/Hubs). It replaces the older Assistants API with a modernized developer experience built on the **Responses API**. The new agents support named/versioned agent definitions, conversations (replacing threads), and a rich tool ecosystem including Code Interpreter, File Search, Web Search, Function Calling, MCP, OpenAPI, and — critically for this demo — **Agent-to-Agent (A2A) protocol support in public preview**.

**Service and feature GA/preview status (precise):**

| Component | Status |
|---|---|
| Foundry Agent Service | **GA** |
| A2A protocol tool | **Public Preview** |
| Hosted agents | **Preview** |
| Toolbox | **Preview** |
| Foundry IQ | **Preview** |
| `azure-ai-projects` Python SDK (v2.1.0) | **Preview** (the SDK package, not the service) |
| `azure-ai-agents` Python SDK (v1.1.0) | **Preview** |

> "The AI Projects client library (in preview) is part of the Microsoft Foundry SDK."
> — Source: [Azure AI Projects client library for Python — version 2.1.0](https://learn.microsoft.com/en-us/python/api/overview/azure/ai-projects-readme)

A2A support is native and bidirectional: a Foundry agent can **call remote A2A endpoints** (A2A as a custom tool) and can **expose itself as an A2A endpoint** (incoming A2A). Foundry's A2A endpoint uses **A2A protocol version 0.3** (not 1.0). This is the single most critical finding for the Zava demo: Foundry Agents V2 natively supports A2A both as a client and a server, no shim required. Private VNet support is also available — A2A traffic flows through the customer's VNet subnet when network isolation is enabled. The combination of A2A + private VNet is **explicitly supported** per the official tool support matrix.

> "Foundry Agent Service supports A2A protocol version 0.3 only."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

**⚠️ A2A protocol version 0.3 interop note:** The LangGraph side of the demo must also speak A2A 0.3. If the A2A Python server library targets a different protocol version, a compatibility layer or version pin will be needed.

### Per-Model Demo Feasibility Verdict

**`gpt-5.5-mini` does not exist** in the Azure model catalog as of 2026-05-20. The three valid candidate models are `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`. All three support A2A and Code Interpreter on Foundry Agent Service.

| Model ID | In Catalog | Global Std Regions (US) | A2A Support | Code Interpreter | Access Gating | Default Quota (Tier 1) | Demo Role |
|---|---|---|---|---|---|---|---|
| `gpt-5.5` | ✅ Yes | East US 2, South Central US | ✅ Yes | ✅ Yes | Open (quota request needed below Tier 5) | 0 RPM / 0 TPM (Tiers 1–4) | **Orchestrator (recommended)** |
| `gpt-5.4` | ✅ Yes | All 10 Americas regions | ✅ Yes | ✅ Yes | **Limited access application required** | 10,000 RPM / 1M TPM | Not recommended (access friction) |
| `gpt-5.4-mini` | ✅ Yes | All 10 Americas regions | ✅ Yes | ✅ Yes | Open (no request needed) | 1,000 RPM / 1M TPM | **Worker (recommended)** |
| `gpt-5.5-mini` | ❌ **Does not exist** | N/A | N/A | N/A | N/A | N/A | **Not available** |

> — Sources: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure), [Region availability](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability), [Tool best practices](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice), [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits)

**Recommendation:** Use **`gpt-5.5`** (orchestrator / Foundry Agent) + **`gpt-5.4-mini`** (worker / LangGraph on AKS), both as Global Standard deployments in **East US 2** — the only US region where `gpt-5.5` Global Standard is available AND Code Interpreter is supported. If `gpt-5.5` quota is unavailable (subscription below Tier 5), fall back to `gpt-5.4-mini` for both agents.

**Demo feasibility: ✅ CONFIRMED.** All required capabilities (A2A preview, Code Interpreter, Responses API) are supported by both recommended models. The only prerequisites are: (1) ensure the subscription has `gpt-5.5` quota (Tier 5+ or submit quota request), and (2) create the Foundry project in East US 2.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Key Concepts](#2-key-concepts)
- [3. Getting Started](#3-getting-started)
- [4. Core Usage](#4-core-usage)
- [5. A2A Support — Critical for Demo](#5-a2a-support--critical-for-demo)
- [6. Private VNet Support](#6-private-vnet-support)
- [7. A2A + Private VNet Simultaneously](#7-a2a--private-vnet-simultaneously)
- [8. Per-Model Considerations](#8-per-model-considerations)
- [9. Configuration & Best Practices](#9-configuration--best-practices)
- [10. Pricing, Limits & Quotas](#10-pricing-limits--quotas)
- [11. Research Limitations](#11-research-limitations)
- [12. Complete Reference List](#12-complete-reference-list)

---

## 1. Overview

### What It Is

Foundry Agent Service is the agent runtime within Microsoft Foundry (the new, project-based experience — NOT Foundry Classic / Hubs). It provides a platform for building, versioning, deploying, and operating AI agents that combine Foundry models with tools and instructions.

> "Foundry Agent Service provides an upgraded developer experience for building intelligent agents that are easy to build, version, operate, and observe. The new agents API introduces a modernized SDK, new enterprise-grade capabilities, and preserves the identity, governance, and observability features you rely on today."
> — Source: [Migrate to the new agents developer experience](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate)

The service is built on three core runtime components:

> "Microsoft Foundry Agent Service uses three core runtime components—agents, conversations, and responses—to power stateful, multi-turn interactions. An agent uses a model from the Foundry model catalog, along with instructions and tools. A conversation persists history across turns. A response is the output the agent produces when it processes input."
> — Source: [Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components)

### Why It Matters

For the Zava demo, Foundry Agent Service is the platform that runs Agent A (Customer Service Agent). It provides:
- Native A2A protocol support (both client and server)
- Code Interpreter for chart/summary generation
- Enterprise-grade identity, RBAC, and networking
- Versioned agent definitions for reproducible deployments

### Key Features

- **Responses API** — Modern API primitive replacing the older Assistants API ([Migrate to the new agents developer experience](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate))
- **Named, versioned agents** — Agents are identified by name + version, not GUIDs ([Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components))
- **Rich tool ecosystem** — Web Search, Code Interpreter, File Search, Function Calling, MCP, OpenAPI, A2A ([Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog))
- **Agent-to-Agent (A2A)** — Native A2A protocol support, public preview ([Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent))
- **Workflows** — Declarative multi-agent orchestration (sequential, group chat, human-in-the-loop) ([Build a workflow in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow))
- **Hosted agents** — Containerized agents deployed to Foundry, preview ([Deploy a hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent))
- **Agent Applications** — Publish agents as standalone Azure resources with stable endpoints ([Publish your agent as an Agent Application](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/agent-applications))
- **Toolbox** — Bundle multiple tools into a single MCP-compatible endpoint, preview ([Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog))
- **Foundry IQ** — Knowledge base with agentic retrieval for grounding, preview ([What is Foundry IQ?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq))
- **Private networking** — VNet injection and private endpoints for network isolation ([How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link))

---

## 2. Key Concepts

### Agent Types

Foundry Agent Service supports multiple agent types:

1. **Prompt agents** — The primary type. Define model, instructions, and tools declaratively. Support the Responses protocol by default. **All prompt agents can be exposed as A2A endpoints.** ([Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint))

2. **Workflow agents** — Declarative orchestration of multiple agents in sequential, group chat, or human-in-the-loop patterns. Created in the Foundry portal visual builder. ([Build a workflow in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow))

3. **Hosted agents (preview)** — Containerized agents deployed to Foundry. Support incoming A2A only if built to handle the Responses protocol. The A2A endpoint for a hosted agent is: `{project_endpoint}/agents/{name}/endpoint/protocols/a2a`. ([Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents))

> "The A2A protocol supports agent-to-agent delegation. All four protocols—Responses, Invocations, Activity, and A2A—can be combined in a single agent."
> — Source: [Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)

### Responses API vs Assistants API

The new agents are built on the **Responses API**, replacing the older Assistants API:

| Before (Classic) | After (New) | Details |
|---|---|---|
| Threads | Conversations | Supports streams of items, not just messages |
| Runs | Responses | Tool call loops are explicitly managed |
| Assistants / agents | Agents (new) | Named, versioned, enterprise-ready |

> "Modern API primitive. Built on the Responses API instead of the older Assistants API."
> — Source: [Migrate to the new agents developer experience](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate)

### Tool Ecosystem

> "Tools extend what your agents can do in Microsoft Foundry Agent Service. An agent on its own uses a Foundry model to generate text, but tools let it take action - searching the web, running code, querying your data, or calling your own APIs."
> — Source: [Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog)

**Built-in tools (GA unless noted):**
| Tool | Status | Description |
|---|---|---|
| Web Search | GA | Real-time web information with inline citations |
| Code Interpreter | GA | Sandboxed Python execution for data analysis, math, charts |
| File Search | GA | Vector search over uploaded files/documents |
| Function Calling | GA | Custom functions executed by your application |
| Azure AI Search | GA | Ground agents with Azure AI Search index data |
| Azure Functions | GA | Call Azure Functions for custom actions |
| MCP | GA | Connect to Model Context Protocol server endpoints |
| OpenAPI | GA | Connect to HTTP APIs via OpenAPI 3.0/3.1 spec |
| Image Generation | Preview | Generate images in conversations |
| Browser Automation | Preview | Browser tasks via natural language |
| Computer Use | Preview | Interact with computer UIs |
| Microsoft Fabric | Preview | Connect to Fabric data agents |
| SharePoint | Preview | Chat with SharePoint documents |

**Custom tools:**
| Tool | Status | Description |
|---|---|---|
| Agent-to-Agent (A2A) | **Public Preview** | Connect to A2A-compatible agent endpoints |
| OpenAPI tool | GA | External APIs via OpenAPI spec |
| MCP | GA | MCP server endpoints |
| Toolbox | Preview | Bundle tools into single MCP endpoint |

> "The Foundry tool catalog and the core tools framework are generally available. Some individual tools are still in preview, as noted in the tool listings throughout this article."
> — Source: [Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog)

### Migration from Classic (V1)

The migration path from classic agents to new agents is documented. Key tool changes relevant to A2A:

| Tool | Classic | New |
|---|---|---|
| Agent to Agent (A2A) | No | Yes (Public Preview) |
| Connected Agents | Yes (Public Preview) | No (Recommendation: Workflow and A2A tool) |

> "The Connected Agents tool from the previous (classic) Agents API isn't available in the new Foundry Agent Service. To use one Foundry agent from another, choose one of the following replacements: A2A tool [...] or Workflows."
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent)

### RBAC Roles

The Foundry RBAC roles were recently renamed:

| New Name | Old Name | Key Permissions |
|---|---|---|
| **Foundry User** | Azure AI User | Read access + data actions (build/develop) |
| **Foundry Project Manager** | Azure AI Project Manager | Manage projects, assign Foundry User role |
| **Foundry Account Owner** | Azure AI Account Owner | Full access, assign Foundry User/ACR/monitoring roles |
| **Foundry Owner** | Azure AI Owner | Full access, highly privileged self-serve role |

> "The Foundry RBAC roles were recently renamed. Foundry User, Foundry Owner, Foundry Account Owner, and Foundry Project Manager were previously named Azure AI User, Azure AI Owner, Azure AI Account Owner, and Azure AI Project Manager. You might still see the previous names in some places while the rename rolls out. The role IDs and core permissions are unchanged by the rename."
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)

For the Zava demo, the user needs:
- **Foundry User** on the Foundry resource (minimum to build agents and invoke A2A)
- **Foundry Project Manager** on the Foundry resource scope (required to publish agents)
- **Contributor or Owner** on the Foundry resource (for management operations)

---

## 3. Getting Started

### Prerequisites

- Azure subscription
- Microsoft Foundry project (new experience, not Classic)
- Model deployment (e.g., `gpt-5.5`, `gpt-5.4-mini`, or any supported Foundry model)
- Python 3.9+
- Azure CLI installed and logged in

### Installation & Setup

#### Terminal Commands

```bash
# Log in to Azure
az login

# Install the Foundry Agents SDK (recommended: azure-ai-projects, currently in preview)
pip install "azure-ai-projects>=2.0.0"
pip install azure-identity

# Alternative: lower-level agents client (also in preview)
pip install azure-ai-agents

# Verify installation
pip show azure-ai-projects
```

#### Python Setup

```python
# Complete setup for Foundry Agent Service
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components
# Provenance: adapted (simplified from tabbed SDK examples on the page)

import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

# Project endpoint format: "https://{resource_name}.services.ai.azure.com/api/projects/{project_name}"
# Can also use: "https://{resource_name}.ai.azure.com/api/projects/{project_name}"
PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"]

# Create the project client (for agent management)
with AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
) as project:
    # Get the OpenAI client (for conversations and responses)
    openai = project.get_openai_client()
    print("Foundry Agent Service client initialized successfully")
```
> — Source: [Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components) | Provenance: adapted

---

## 4. Core Usage

### Python Examples

#### Creating a Prompt Agent with Code Interpreter

```python
# Example: Create a prompt agent with Code Interpreter tool
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components
# Provenance: adapted (based on SDK patterns from runtime-components page; model name and instructions customized)

import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition, CodeInterpreterTool

PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"]

with AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
) as project:
    openai = project.get_openai_client()

    # Create the agent with Code Interpreter
    agent = project.agents.create_version(
        agent_name="zava-customer-agent",
        definition=PromptAgentDefinition(
            model="gpt-5.5",  # or gpt-5.4-mini for lower cost
            instructions="You are a helpful customer service agent for Zava, a precision-components manufacturer.",
            tools=[CodeInterpreterTool()],
        ),
    )
    print(f"Agent created: {agent.name}, Version: {agent.version}")

    # Send a query using the Responses API
    response = openai.responses.create(
        input="Analyze our Q2 production data and create a summary chart.",
        extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
    )
    print(response.output_text)
```
> — Source: [Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components) | Provenance: adapted

#### Creating an Agent with Web Search

```python
# Example: Create an agent with Web Search
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog
# Provenance: adapted (based on tool catalog page patterns; variable names and instructions customized)

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition, WebSearchTool

PROJECT_ENDPOINT = "your_project_endpoint"

with AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
) as project:
    openai = project.get_openai_client()

    agent = project.agents.create_version(
        agent_name="web-search-agent",
        definition=PromptAgentDefinition(
            model="gpt-5.4-mini",
            instructions="You are a helpful assistant that can search the web.",
            tools=[WebSearchTool()],
        ),
    )

    response = openai.responses.create(
        input="What are the latest updates to Microsoft Foundry?",
        extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
    )
    print(response.output_text)
```
> — Source: [Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog) | Provenance: adapted

### Terminal / CLI Commands

```bash
# Get an access token for Foundry API calls
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# Create a versioned prompt agent via REST API
# Endpoint pattern: /agents/{agent_name}/versions?api-version=v1
ENDPOINT="https://{resource_name}.services.ai.azure.com/api/projects/{project_name}"
AGENT_NAME="zava-customer-agent"

curl -X POST "${ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "definition": {
      "kind": "prompt",
      "model": "gpt-5.5",
      "instructions": "You are a helpful customer service agent for Zava."
    }
  }'
```
> — Source: [Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components) | Provenance: adapted (endpoint pattern `/agents/{agent_name}/versions` from the documented SDK method `create_version`)

---

## 5. A2A Support — Critical for Demo

### ⭐ Key Finding: A2A is Natively Supported

**Foundry Agent Service natively supports the A2A protocol in both directions — as an A2A client (outbound) and as an A2A server (inbound).** This is in **public preview**.

> "Agent-to-Agent (A2A) (preview) — Connect your agent to other agents through A2A-compatible endpoints for cross-agent communication."
> — Source: [Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog)

### A2A Protocol Version

Foundry's A2A endpoint uses **A2A protocol version 0.3 only** — not 1.0.

> "Foundry Agent Service supports A2A protocol version 0.3 only."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

**Interop implication for the Zava demo:** The LangGraph agent on AKS must implement an A2A 0.3–compatible server. If the A2A Python library targets a different version, compatibility must be verified or pinned.

### A2A as Client (Outbound — Foundry Agent Calls External A2A Endpoint)

This is the primary pattern for the Zava demo: the Foundry Customer Service Agent calls the LangGraph Manufacturing Ops Agent via A2A.

> "You can extend the capabilities of your Microsoft Foundry agent by connecting to a remote Agent2Agent (A2A) endpoint that supports the A2A protocol. The A2A tool enables agent-to-agent communication, making it easier to share context between Foundry-model-powered agents and external agent endpoints through a standardized protocol."
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent)

**How it works:**
> "Using the A2A tool: When Agent A calls Agent B through the A2A tool, Agent B's answer goes back to Agent A. Agent A then summarizes the answer and generates a response for the user. Agent A keeps control and continues to handle future user input."
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent)

**SDK support:** Python SDK ✔️, C# SDK ✔️, JavaScript SDK ✔️, Java SDK ✔️, REST API ✔️, Basic agent setup ✔️, Standard agent setup ✔️ ([Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent))

**Prerequisites for the A2A tool:**
- A model deployment (e.g., `gpt-5.5`) in your Foundry project
- Required Azure role: **Contributor or Owner** on the Foundry resource for management, **Foundry User** for building the agent
- SDK: `pip install "azure-ai-projects>=2.0.0"` (preview)
- An A2A connection configured in the Foundry portal

#### Python Code — Creating an Agent with A2A Tool (Outbound)

```python
# Example: Create a Foundry agent that calls an external A2A endpoint
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent
# Provenance: adapted (closely follows the Python tab on the A2A tool page;
#   comments and variable naming adjusted, but structure matches the official sample)

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    A2APreviewTool,
)

# Format: "https://resource_name.ai.azure.com/api/projects/project_name"
PROJECT_ENDPOINT = "your_project_endpoint"
A2A_CONNECTION_NAME = "my-a2a-connection"
AGENT_NAME = "my-agent"

# Create clients to call Foundry API
with AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
) as project:
    openai = project.get_openai_client()

    a2a_connection = project.connections.get(A2A_CONNECTION_NAME)

    tool = A2APreviewTool(
        project_connection_id=a2a_connection.id,
    )

    agent = project.agents.create_version(
        agent_name=AGENT_NAME,
        definition=PromptAgentDefinition(
            model="gpt-5.5",
            instructions="You are a helpful assistant.",
            tools=[tool],
        ),
    )

    print(f"Agent created (id: {agent.id}, name: {agent.name}, version: {agent.version})")

    user_input = input("Enter your question (e.g., 'What can the secondary agent do?'): \n")

    stream_response = openai.responses.create(
        stream=True,
        tool_choice="required",
        input=user_input,
        extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
    )

    for event in stream_response:
        if event.type == "response.created":
            print(f"Follow-up response created with ID: {event.response.id}")
        elif event.type == "response.output_text.delta":
            print(f"Delta: {event.delta}")
        elif event.type == "response.text.done":
            print(f"\nFollow-up response done!")
        elif event.type == "response.output_item.done":
            item = event.item
            if item.type == "remote_function_call":
                print(f"Call ID: {getattr(item, 'call_id')}")
                print(f"Label: {getattr(item, 'label')}")
        elif event.type == "response.completed":
            print(f"\nFollow-up completed!")
            print(f"Full response: {event.response.output_text}")

    # Clean up the created agent version
    project.agents.delete_version(agent_name=agent.name, agent_version=agent.version)
```
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent) | Provenance: adapted

#### Creating an A2A Connection

A2A connections are created in the Foundry portal:

1. Sign in to Microsoft Foundry (ensure "New Foundry" toggle is on)
2. Select **Tools** → **Connect tool** → **Custom** tab → **Agent2Agent (A2A)** → **Create**
3. Enter a **Name** and **A2A Agent Endpoint**
4. Under **Authentication**, select a method (key-based: set credential name like `x-api-key` and secret value)

In code, reference the connection by name:
```python
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent
# Provenance: adapted
a2a_connection = project.connections.get("my-a2a-connection")
# Access connection.id for the A2A tool
```
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent) | Provenance: adapted

### A2A as Server (Inbound — Foundry Agent Exposes an A2A Endpoint)

> "You can expose your Foundry Agent Service agent as an Agent2Agent (A2A) endpoint so that other agents can discover and call it through the A2A protocol. When incoming A2A is enabled, Foundry publishes an agent card for your agent and accepts inbound A2A requests from external callers."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

**Supported agent types for incoming A2A:**
> "Incoming A2A requires the responses protocol. The following agent types support it: Prompt agents — support the responses protocol by default. All prompt agents can be exposed as A2A endpoints. Hosted agents — support incoming A2A only if the Hosted agent is built to handle the responses protocol."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

#### Enabling Incoming A2A via REST API

```bash
# Set up variables
BASE_URL="https://{account}.services.ai.azure.com/api/projects/{project}"
AGENT_NAME="your-agent-name"
TOKEN=$(az account get-access-token --resource https://ai.azure.com \
  --query accessToken -o tsv)

# Enable A2A with agent card via PATCH
curl -X PATCH "$BASE_URL/agents/$AGENT_NAME?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_card": {
      "description": "A helpful assistant that answers questions",
      "version": "1.0",
      "skills": [
        {
          "id": "general-qa",
          "name": "General Q&A",
          "description": "Answers general questions"
        }
      ]
    },
    "agent_endpoint": {
      "protocols": ["responses", "a2a"]
    }
  }'
```
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) | Provenance: adapted (follows the REST tab on the incoming A2A page; JSON structure matches the documented PATCH pattern)

#### Enabling Incoming A2A via Python SDK

```python
# Example: Enable incoming A2A on a Foundry agent
# Source: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint
# Provenance: adapted (follows the Python tab on the incoming A2A page;
#   wrapped in context manager and variables renamed for clarity)

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AgentEndpoint,
    AgentEndpointProtocol,
)

PROJECT_ENDPOINT = "your_project_endpoint"
AGENT_NAME = "your_agent_name"

with AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
) as project_client:
    endpoint_config = AgentEndpoint(
        protocols=[
            AgentEndpointProtocol.RESPONSES,
            AgentEndpointProtocol.A2A,
        ],
    )

    patched_agent = project_client.beta.agents.patch_agent_details(
        agent_name=AGENT_NAME,
        agent_endpoint=endpoint_config,
    )
```
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) | Provenance: adapted

**Note:** Setting the agent card through the Python SDK isn't supported yet — use the REST API to configure the agent card. ([Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint))

#### A2A Endpoint URLs

After enabling incoming A2A, the agent exposes two URLs:

- **A2A base path:** `https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a`
- **Agent card URL:** `https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a/agentCard/v0.3`

For **hosted agents**, the endpoint format is:

- **Hosted agent A2A endpoint:** `{project_endpoint}/agents/{name}/endpoint/protocols/a2a`

> — Source: [Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)

> "Both URLs require Microsoft Entra ID authentication. Anonymous access to the agent card isn't supported. The calling agent must present a valid token with the Foundry User role on the Foundry project."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

### A2A Authentication

> "The Agent2Agent (A2A) protocol enables your agents to invoke other agents. Most A2A endpoints require authentication to access the endpoint and its underlying service."
> — Source: [Agent2Agent (A2A) authentication](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-to-agent-authentication)

**Supported authentication methods for A2A connections:**

| Method | User context persists | Description |
|---|---|---|
| Key-based | No | API key or access token |
| Microsoft Entra ID - agent identity | No | Agent's managed identity |
| Microsoft Entra ID - project managed identity | No | Project's managed identity |
| OAuth identity passthrough | Yes | Per-user sign-in and authorization |
| Unauthenticated access | No | For publicly accessible endpoints |

**For the Zava demo (Foundry agent calling LangGraph agent on AKS):** Key-based authentication is the simplest option. The LangGraph A2A server on AKS would expose an API key, stored as a Foundry project connection. Alternatively, for a more production-ready approach, use Microsoft Entra ID with a service principal.

**For incoming A2A (other agents calling the Foundry agent):**
> "Incoming A2A requests require Microsoft Entra ID authentication. Key-based and unauthenticated access aren't supported. The calling agent must present a valid Microsoft Entra token, and the identity behind that token must have the Foundry User role (or higher) on the Foundry project that hosts your agent."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint)

### Zava Demo Architecture Implications

For the Zava demo, the architecture is:
1. **Foundry Agent (Agent A)** uses the **A2A tool (outbound)** to call the LangGraph agent
2. **LangGraph Agent (Agent B)** on AKS exposes an A2A endpoint (implemented with an A2A-compatible Python server library)
3. The Foundry agent references the LangGraph A2A endpoint via a **project connection** with key-based auth
4. No shim or adapter layer needed — the `A2APreviewTool` in `azure-ai-projects` handles the A2A protocol natively
5. **Both sides must speak A2A protocol version 0.3** — verify the LangGraph A2A library version

**This architecture is directly supported by official documentation and code samples.**

---

## 6. Private VNet Support

### Overview

Foundry supports network isolation in three areas:
1. **Inbound access** — Private endpoints to the Foundry resource (controlled by public network access flag)
2. **Outbound access** — VNet injection of the Agent client into a customer-managed subnet
3. **Agent tool traffic** — Tool-specific routing through VNet, private endpoints, or public endpoints

> "Microsoft Foundry's network isolation spans both Platform as a Service (PaaS) and platform-managed infrastructure components. PaaS resources—such as the Microsoft Foundry project, storage, Key Vault, container registry, and monitoring—are isolated using Private Link. Rather than customers managing IaaS compute resources for training or online endpoints, Foundry uses virtual network (VNet) injection of the Agent client."
> — Source: [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link)

### Setting Up Private Endpoints (Inbound)

1. Create or update a Foundry resource with **public network access disabled**
2. Add a private endpoint to the Foundry resource in the same region as your VNet
3. Configure DNS (Azure creates a private DNS zone with `privatelink` subdomain)

### Setting Up VNet Injection (Outbound — Agent Service)

VNet injection requires:
- **Bring-your-own (BYO) resources**: Azure Storage, Azure AI Search, Azure Cosmos DB
- A **dedicated subnet** delegated to `Microsoft.App/environments` with size **/27 or larger** (recommended: /24)
- Public network access set to **Disabled**

> "The ability to create a Foundry resource with virtual network injection in the Azure portal only appears if you have first selected bring-your-own resources for Storage, Search, and CosmosDB AND if you have selected public network access as disabled."
> — Source: [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link)

### Agent Tool Support with Network Isolation

This is the critical matrix from official documentation:

| Tool | Support Status | Traffic Flow |
|---|---|---|
| **Agent-to-Agent (A2A)** | **✅ Supported** | **Through your VNet subnet** |
| MCP Tool (Private MCP) | ✅ Supported | Through your VNet subnet |
| Azure AI Search | ✅ Supported | Through private endpoint |
| Code Interpreter | ✅ Supported | Microsoft backbone network |
| Function Calling | ✅ Supported | Microsoft backbone network |
| Bing Grounding | ✅ Supported | Public endpoint |
| Web Search | ✅ Supported | Public endpoint |
| SharePoint Grounding | ✅ Supported | Public endpoint |
| Foundry IQ (preview) | ✅ Supported | Via MCP |
| OpenAPI tool | ✅ Supported | Through your VNet subnet |
| Azure Functions | ✅ Supported | Through your VNet subnet |
| Fabric Data Agent | ❌ Not supported | Fabric public access required |
| Logic Apps | ❌ Not supported | Under development |
| File Search | ❌ Not supported | Under development |
| Browser Automation | ❌ Not supported | Under development |
| Computer Use | ❌ Not supported | Under development |
| Image Generation | ❌ Not supported | Under development |

> — Source: [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link)

### Key VNet Considerations from FAQ

- **Subnet delegation:** Agent Service networking uses Azure Container Apps. The dedicated subnet must be delegated to `Microsoft.App/environments`. ([Foundry Agent Service FAQ](https://learn.microsoft.com/en-us/azure/foundry/agents/faq))
- **Minimum subnet size:** /27 (recommended /24). ([Foundry Agent Service FAQ](https://learn.microsoft.com/en-us/azure/foundry/agents/faq))
- **Private IP ranges only:** 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16. Public IP ranges not supported. ([Foundry Agent Service FAQ](https://learn.microsoft.com/en-us/azure/foundry/agents/faq))
- **VNet peering:** Supported but not recommended (data transfer costs). All resources must be in the same region as the Foundry resource. ([Foundry Agent Service FAQ](https://learn.microsoft.com/en-us/azure/foundry/agents/faq))
- **Azure Firewall:** Allow required FQDNs for managed identity (AzureActiveDirectory service tag). ([Foundry Agent Service FAQ](https://learn.microsoft.com/en-us/azure/foundry/agents/faq))

---

## 7. A2A + Private VNet Simultaneously

### ⭐ Key Finding: Explicitly Supported

**A2A and private VNet are explicitly supported together.** The official tool support matrix in the network isolation documentation lists A2A as "✅ Supported" with traffic flowing "Through your VNet subnet" when network isolation is enabled.

> Tool: Agent-to-Agent (A2A) — Support Status: ✅ Supported — Traffic Flow: Through your VNet subnet
> — Source: [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link)

### Reference Architecture for A2A + Private VNet

When a customer wants both A2A and private networking:

1. **Foundry Resource:** Created with public network access disabled, private endpoint enabled
2. **BYO Resources:** Azure Storage, Azure AI Search, Azure Cosmos DB — all with private endpoints
3. **VNet Injection:** Dedicated subnet (/24 recommended) delegated to `Microsoft.App/environments`
4. **A2A Traffic:** Flows through the customer's VNet subnet to reach the A2A endpoint
5. **The A2A target endpoint** (e.g., LangGraph on AKS) would need to be reachable from the VNet subnet — either in the same VNet, a peered VNet, or via private endpoint

An official sample template exists for this architecture: [microsoft-foundry/foundry-samples/.../19-hybrid-private-resources-agent-setup](https://github.com/microsoft-foundry/foundry-samples) — referenced in the network isolation documentation for setting up private resources with agents. ([How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link))

**For the Zava demo:** The demo uses public endpoints (per project requirements), but the docs show that a customer deployment with both A2A and private VNet is fully supported. The only caveats are:
- **File Search is NOT supported** behind VNet (under development)
- **Code Interpreter IS supported** behind VNet (traffic goes through Microsoft backbone)
- The A2A target must be reachable from the injected subnet

### Feature Gaps with Private Networking

When private networking is enabled, the following tools are **NOT available**: File Search, Browser Automation, Computer Use, Image Generation, Logic Apps, Fabric Data Agent. These are documented as "Under development" or unsupported. ([How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link))

---

## 8. Per-Model Considerations

### ⚠️ Critical Finding: `gpt-5.5-mini` Does Not Exist

The project brief listed four candidate models: GPT-5.5, GPT-5.4, GPT-5.5-mini, and GPT-5.4-mini. **`gpt-5.5-mini` does not exist in the Azure model catalog as of 2026-05-20.** The GPT-5.5 series contains only `gpt-5.5`. There is no mini variant.

> The models page lists GPT-5.5 series with only `gpt-5.5` (marked **NEW**), and GPT-5.4 series with `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4`, `gpt-5.4-pro`.
> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

### Model Availability for Foundry Agent Service

The new Foundry Agent Service works with **any Foundry model** from the model catalog:

> "⭐ More models. Generate responses by using any Foundry model either in your agent or directly as a response generation call."
> — Source: [Migrate to the new agents developer experience](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate)

### Per-Model Compatibility Table

| Attribute | `gpt-5.5` | `gpt-5.4` | `gpt-5.4-mini` |
|---|---|---|---|
| **Exists in catalog** | ✅ Yes — marked "NEW" | ✅ Yes | ✅ Yes |
| **Global Standard regions (US)** | East US 2, South Central US | All 10 Americas regions | All 10 Americas regions |
| **Responses API support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Foundry Agent Service A2A support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Code Interpreter support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Access gating** | Open (no access request; quota request needed below Tier 5) | **Limited access** application required | Open (no request needed) |
| **Default quota — Tier 1** | 0 RPM / 0 TPM | 10,000 RPM / 1M TPM | 1,000 RPM / 1M TPM |
| **Default quota — Tier 5** | 10,000 RPM / 10M TPM | 100,000 RPM / 10M TPM | 10,000 RPM / 10M TPM |
| **Context window** | 1,050,000 tokens | 1,050,000 tokens | 400,000 tokens |
| **Training data cutoff** | December 2025 | August 2025 | August 2025 |
| **Demo recommendation** | **Orchestrator (recommended)** | Not recommended (access friction) | **Worker (recommended)** |

> — Sources: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure), [Region availability](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability), [Tool best practices](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice), [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits), [Azure OpenAI reasoning models — GPT-5 series](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning)

### A2A Tool Support — Per-Model Matrix

The official tool-by-model support matrix on the Foundry Agent Service docs confirms that **all three candidate models support A2A (Agent2Agent)**:

| Model ID | Agent2Agent (A2A) | Code Interpreter | File Search | Function Calling | Web Search | MCP | OpenAPI |
|---|---|---|---|---|---|---|---|
| `gpt-5.5` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4-mini` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

### Code Interpreter Region Constraint (Critical)

Code Interpreter availability varies by region. Critically, **South Central US does not support Code Interpreter**:

> "Code interpreter doesn't run in regions that show 'no' for Code Interpreter (such as `southcentralus` and `spaincentral`), regardless of which model you use."
> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

| Region | Code Interpreter | A2A |
|---|---|---|
| `eastus` | ✅ yes | ✅ yes |
| `eastus2` | ✅ yes | ✅ yes |
| `northcentralus` | ✅ yes | ✅ yes |
| **`southcentralus`** | **❌ no** | ✅ yes |
| `westus` | ✅ yes | ✅ yes |
| `westus3` | ✅ yes | ✅ yes |

> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

Since the Foundry Customer Service Agent needs Code Interpreter, and `gpt-5.5` Global Standard is only available in `eastus2` and `southcentralus` for the Americas, **the project must be created in East US 2** — the only US region where `gpt-5.5` Global Standard is available AND Code Interpreter is supported. ([Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability))

### Recommendation for the Demo

| Role | Model | Deployment SKU | Region | Justification |
|---|---|---|---|---|
| **Foundry Customer Service Agent (orchestrator)** | `gpt-5.5` | Global Standard | East US 2 | Best reasoning; newest model; no access gate (just quota); supports A2A + Code Interpreter |
| **LangGraph Ops Agent (worker)** | `gpt-5.4-mini` | Global Standard | East US 2 | Cost-efficient; open access; generous quota at all tiers; 400K context sufficient for ops queries |

**Fallback:** If `gpt-5.5` quota is unavailable (subscription below Tier 5 and quota request delayed), use `gpt-5.4-mini` for both agents with different deployment names. Alternatively, `gpt-5.4` could replace `gpt-5.5` as orchestrator but requires a limited access application.

### Quota Prerequisite

> "Some quota tiers will require quota requests for gpt-5.5 to be able to deploy this model. Tier 5 and Tier 6 subscriptions have quota by default."
> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

**If the subscription is below Tier 5, a quota increase request for `gpt-5.5` must be submitted before deployment.**

---

## 9. Configuration & Best Practices

### Recommended Configuration

**Environment variables for the Zava demo:**
```bash
# Foundry project endpoint
export FOUNDRY_PROJECT_ENDPOINT="https://{account}.services.ai.azure.com/api/projects/{project}"

# Model deployment names (two separate deployments)
export FOUNDRY_MODEL_NAME="gpt-5.5"
export OPS_MODEL_NAME="gpt-5.4-mini"

# A2A connection name (configured in Foundry portal)
export A2A_CONNECTION_NAME="ops-agent-a2a"
```

### Best Practices

Official Microsoft recommendations for tools:

> "For information on optimizing tool usage, see best practices."
> — Source: [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent)

Key practices from the tool best practices page ([Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)):
- Use clear, descriptive tool definitions so the model can decide when to call them
- Keep agent instructions focused and specific
- Use `tool_choice="required"` when you want to force a tool call

For A2A authentication:
> "Use least-privilege credentials: Request only the minimum permissions needed for the agent's tasks. Rotate tokens regularly: Set a reminder to regenerate tokens before they expire. Restrict project access: Limit who can access projects that contain shared secrets. Audit credential usage: Monitor project connection access in your Azure activity logs."
> — Source: [Agent2Agent (A2A) authentication](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-to-agent-authentication)

### Common Pitfalls & Anti-Patterns

1. **Don't use Connected Agents (classic)** — This tool is deprecated in new Foundry Agent Service. Use A2A tool or Workflows instead. ([Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent))

2. **Don't confuse A2A tool with Workflow** — A2A tool keeps Agent A in control; Workflow hands off entirely to Agent B. ([Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent))

3. **Agent identity changes on publish** — When you publish an agent as an Agent Application, it gets a new dedicated identity. RBAC permissions must be reassigned. ([Publish your agent as an Agent Application](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/agent-applications))

4. **VNet injection requires BYO resources** — You cannot use VNet injection with Microsoft-managed (Basic) storage. Standard setup with BYO Storage, AI Search, and Cosmos DB is required. ([How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link))

5. **Incoming A2A requires Entra ID** — Key-based and unauthenticated access are NOT supported for incoming A2A requests. ([Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint))

6. **Code Interpreter region constraint** — Code Interpreter does not run in South Central US or Spain Central, regardless of model. Verify the project region supports Code Interpreter before deploying. ([Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice))

---

## 10. Pricing, Limits & Quotas

### Billing Model

> "You're charged for inference cost (input and output) of the base model that you're using for each agent (for example, gpt-4-0125). If you created multiple agents, you're charged for the base model attached to each agent."
> — Source: [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq)

> "If you enabled the Code Interpreter tool, you're charged for its use per session. For example, if your agent calls Code Interpreter simultaneously in two threads, this activity creates two Code Interpreter sessions. Each of those sessions is charged."
> — Source: [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq)

> "By default, each session is active for one hour. If your user keeps giving instructions to Code Interpreter in the same thread for up to one hour, you pay this fee only once."
> — Source: [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq)

> "File search is billed based on the vector storage that you use."
> — Source: [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq)

### No Additional Agent Service Fees

> "Is there any additional pricing or quota for using Foundry Agent Service? No. All quotas apply to using models with Foundry Agent Service."
> — Source: [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq)

### Agent Service Fixed Limits

| Limit | Value |
|---|---|
| Maximum tools per agent | 128 |
| Maximum files per agent/thread | 10,000 |
| Maximum file size | 512 MB |
| Maximum messages per thread | 100,000 |
| Maximum text per message | 1,500,000 characters |

> "Agent Service doesn't impose separate rate limits on API calls. Rate limiting is applied at the model deployment level."
> — Source: [Quotas and limits for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions)

### Model Quotas (Global Standard)

Quota for the recommended models:

| Model ID | Deployment Type | Tier 1 RPM / TPM | Tier 2 RPM / TPM | Tier 3 RPM / TPM | Tier 5 RPM / TPM | Tier 6 RPM / TPM |
|---|---|---|---|---|---|---|
| `gpt-5.5` | GlobalStandard | **0 / 0** | **0 / 0** | **0 / 0** | 10,000 / 10M | 15,000 / 15M |
| `gpt-5.4` | GlobalStandard | 10,000 / 1M | 20,000 / 2M | 40,000 / 4M | 100,000 / 10M | 150,000 / 15M |
| `gpt-5.4-mini` | GlobalStandard | 1,000 / 1M | 2,000 / 2M | 4,000 / 4M | 10,000 / 10M | 15,000 / 15M |

> — Source: [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits)

Check quota availability in the Foundry portal: **Operate → Quota** (toggle "Show all" to see all models and regions). ([Feature availability across cloud regions](https://learn.microsoft.com/en-us/azure/foundry/reference/region-support))

### Data Storage

- **Basic setup:** Microsoft-managed storage, logically separated
- **Standard setup:** Customer's own Azure Storage, Cosmos DB, and AI Search
- Data persists unless explicitly deleted

---

## 11. Research Limitations

1. **`gpt-5.5-mini` does not exist** — The project brief listed this model as a candidate. It is not in the official model catalog as of 2026-05-20. The demo plan should remove it from consideration.

2. **A2A is in public preview** — No SLA, features may change. The docs explicitly warn: "This preview is provided without a service-level agreement, and we don't recommend it for production workloads." However, for a demo this is acceptable.

3. **A2A protocol version 0.3** — Foundry supports only A2A protocol version 0.3. The LangGraph side must be verified against this version. If the A2A Python library targets 1.0+, a compatibility layer may be needed.

4. **`azure-ai-projects` SDK is in preview** — Despite being at version 2.1.0, the SDK page states it is "in preview." APIs may change between versions.

5. **Agent card via Python SDK** — Setting the agent card through the Python SDK "isn't supported yet" per docs. REST API must be used for agent card configuration.

6. **Incoming A2A portal support** — "Enabling incoming A2A isn't yet configurable in the Foundry portal. Use the REST API or Python SDK."

7. **Pricing for A2A** — There is no specific mention of A2A-related charges. It's reasonable to infer that A2A tool calls are billed as regular model inference (the agent processes A2A responses through the model), but this isn't explicitly documented.

8. **VNet + A2A detailed architecture** — While A2A is confirmed as "✅ Supported" behind VNet with traffic through the customer subnet, there is no step-by-step reference architecture specifically for A2A + VNet. The general VNet setup docs apply.

9. **`gpt-5.5` quota risk** — Subscriptions below Tier 5 have 0 default quota for `gpt-5.5`. A quota request must be submitted and approved before deploying. Turnaround time for quota requests is not documented.

---

## 12. Complete Reference List

### Microsoft Learn Documentation

- [Agent tools overview for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog) — Complete tool catalog with built-in and custom tools, authentication guidance
- [Connect to an A2A agent endpoint from Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent) — How to use A2A as outbound tool, Python/REST code, connection setup
- [Enable incoming A2A on a Foundry agent (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) — How to expose Foundry agent as A2A server, agent card, endpoint URLs, A2A protocol v0.3
- [Agent2Agent (A2A) authentication](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-to-agent-authentication) — All auth methods for A2A connections (key, Entra, OAuth, unauthenticated)
- [Build with agents, conversations, and responses](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components) — Core runtime components, agent creation, conversations, responses API
- [Migrate to the new agents developer experience](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate) — Classic→New migration, tool availability comparison, key changes
- [How to configure network isolation for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link) — Private endpoints, VNet injection, tool support matrix behind VNet
- [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry) — RBAC roles (Foundry User, Owner, Account Owner, Project Manager)
- [Foundry Agent Service frequently asked questions](https://learn.microsoft.com/en-us/azure/foundry/agents/faq) — Pricing, data storage, VNet FAQ, quotas
- [Quotas and limits for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions) — Agent Service fixed limits (tools, files, messages, file size)
- [Feature availability across cloud regions](https://learn.microsoft.com/en-us/azure/foundry/reference/region-support) — Regional availability for Foundry features
- [Build a workflow in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/workflow) — Workflow-based multi-agent orchestration
- [Quickstart: Deploy your first hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/quickstart-hosted-agent) — Hosted agent deployment with azd
- [Deploy a hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent) — SDK/REST deployment of containerized agents
- [Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) — Hosted agent architecture, A2A endpoint format, protocols
- [Publish your agent as an Agent Application](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/agent-applications) — Publishing agents as Azure resources with stable endpoints
- [What is Foundry IQ?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/what-is-foundry-iq) — Knowledge base with agentic retrieval for agent grounding
- [Tool best practices for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice) — Per-model tool support matrix, region tool availability, optimization guidance
- [Agent identity concepts in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-identity) — Agent identity lifecycle (shared vs. published)
- [Connect to MCP Server Endpoints for agents](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol) — MCP tool configuration
- [Quickstart: Set up Microsoft Foundry resources](https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources) — Initial Foundry resource/project setup
- [Baseline Microsoft Foundry Chat Reference Architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat) — Enterprise reference architecture
- [What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview) — Agent Service overview, supported protocols including A2A preview
- [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure) — Model catalog (GPT-5.5, GPT-5.4 series), capabilities, access gating
- [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability) — Per-model region matrices by deployment type
- [Azure OpenAI reasoning models — GPT-5 series](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning) — GPT-5 series details, access requirements (open vs. limited access)
- [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits) — Default RPM/TPM quotas per model and subscription tier

### Python SDK Documentation

- [Azure AI Projects client library for Python — version 2.1.0](https://learn.microsoft.com/en-us/python/api/overview/azure/ai-projects-readme) — Primary SDK (in preview): `azure-ai-projects`, agent management, connections, OpenAI client
- [Azure AI Agents client library for Python — version 1.1.0](https://learn.microsoft.com/en-us/python/api/overview/azure/ai-agents-readme) — Lower-level SDK (in preview): `azure-ai-agents`, direct agent operations

### Microsoft Agent Framework & Training

- [A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a) — Microsoft Agent Framework A2A hosting with ASP.NET Core
- [Microsoft Agent Framework Agent Types](https://learn.microsoft.com/en-us/agent-framework/agents/) — Agent type overview for Agent Framework
- [Discover Azure AI Agents with A2A (Training)](https://learn.microsoft.com/en-us/training/modules/discover-agents-with-a2a/) — MS Learn training module on A2A protocol implementation

### GitHub Repositories

- [Azure-Samples/app-service-agentic-langgraph-foundry-python](https://github.com/Azure-Samples/app-service-agentic-langgraph-foundry-python) — Python web app integrating Azure AI Foundry Agents and LangGraph Agents
- [Azure-Samples/foundry-hosted-agentframework-demos](https://github.com/Azure-Samples/foundry-hosted-agentframework-demos) — Agent Framework agent deployed to Foundry Hosted Agents
- [Azure-Samples/AI-Gateway](https://github.com/Azure-Samples/AI-Gateway) — Labs exploring AI Models, MCP servers, and Agents with API Management and Foundry

### Code Samples / Templates

- [microsoft-foundry/foundry-samples — 19-hybrid-private-resources-agent-setup](https://github.com/microsoft-foundry/foundry-samples) — Official sample template for hybrid private resources agent setup, referenced in network isolation documentation
