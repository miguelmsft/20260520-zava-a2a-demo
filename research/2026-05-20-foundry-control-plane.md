# Research Report: Microsoft Foundry Control Plane

**Date:** 2026-05-20
**Researcher:** Copilot MS Docs Researcher Agent
**Topic slug:** foundry-control-plane
**Sources consulted:** 15 Microsoft Learn pages, 0 GitHub repositories, 0 code samples

> **Note on code samples count:** The report includes Python code examples adapted from Microsoft Learn documentation pages. These are counted under "Microsoft Learn pages," not as standalone code samples. The "0 code samples" figure refers to standalone sample repositories from the Microsoft Learn Code Samples gallery. Access date for all sources: 2026-05-20.

---

## Executive Summary

Microsoft Foundry Control Plane is a unified management interface that provides visibility, governance, and control for AI agents, models, and tools across a Foundry enterprise. It centralizes fleet management, observability (tracing, evaluation, monitoring), compliance enforcement, and security capabilities into a single role-aware interface accessible via the **Operate** menu in the Foundry portal. Individual features within the Control Plane have varying maturity levels: tracing is generally available for prompt agents, while agent guardrails, several evaluators, the Application Insights Agents blade, and items explicitly marked "(preview)" in the Control Plane overview are in public preview.

For the Zava Smart Order Feasibility demo, the Control Plane is the primary surface where a customer can see meaningful information about agent runs. The Zava Foundry Customer Service Agent is a **prompt agent** (created via the Foundry Agent Service with instructions and tools like Code Interpreter). Because it is a prompt agent, **server-side traces are auto-captured** once Application Insights is connected and tracing is enabled — no additional OpenTelemetry instrumentation is required for the Foundry agent's execution traces to appear in the portal. Evaluation can be run against the agent using built-in evaluators (Task Adherence, Coherence, Violence), and the default `Microsoft.DefaultV2` guardrail provides content safety for the Foundry agent. The guardrail system applies only to agents in the Foundry Agent Service — the AKS-side LangGraph agent is out of scope for Foundry guardrails.

The minimal configuration for portal-visible traces, evaluations, and safety controls requires: (1) a Foundry project with Application Insights connected, (2) tracing enabled, (3) two model deployments, (4) a Foundry prompt agent created in the project, (5) at least one evaluation run executed via the SDK, and (6) the default guardrail policy active. This setup requires an Application Insights resource but no AI gateway. The AI gateway is a separate prerequisite listed by the Control Plane overview for **advanced governance features** (fleet-wide compliance enforcement, Defender/Purview integration, token limit enforcement). Section 8 provides a two-tier checklist separating these requirements.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Key Concepts](#2-key-concepts)
- [3. Getting Started](#3-getting-started)
- [4. Core Usage](#4-core-usage)
- [5. Configuration & Best Practices](#5-configuration--best-practices)
- [6. Advanced Topics](#6-advanced-topics)
- [7. Pricing, Limits & Quotas](#7-pricing-limits--quotas)
- [8. Demo Wiring Guide — What to Configure for the Zava Demo](#8-demo-wiring-guide--what-to-configure-for-the-zava-demo)
- [9. Research Limitations](#9-research-limitations)
- [10. Complete Reference List](#10-complete-reference-list)

---

## 1. Overview

### What It Is

Microsoft Foundry Control Plane is a centralized management interface for monitoring, governing, and optimizing AI agents, models, and deployments across a Foundry enterprise.

> "Microsoft Foundry Control Plane is a unified management interface that provides visibility, governance, and control for AI agents, models, and tools across your Foundry enterprise. Foundry Control Plane centralizes management for your AI agent fleet, from build to production."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

It is accessed via the **Operate** button on the upper-right toolbar of the Foundry workspace. All features are currently available through the Foundry portal only.

### Preview vs GA Status — Feature-Level Precision

The Control Plane overview page states:

> "Items marked (preview) in this article are currently in public preview. This preview is provided without a service-level agreement, and we don't recommend it for production workloads."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

This means the entire Control Plane is **not** blanket-labeled as preview. Individual features have the following statuses:

| Feature | Status | Source |
|---------|--------|--------|
| **Tracing (prompt agents)** | **GA** | [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) |
| **Tracing (workflow, hosted, custom agents)** | Preview | [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) |
| **Application Insights Agents blade** | Preview | [Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view) |
| **Agent guardrails** | Preview | [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview) |
| **Groundedness Pro evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Response Completeness evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Prohibited Actions evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Sensitive Data Leakage evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Task Adherence evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Task Completion evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Intent Resolution evaluator** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Custom evaluators** | Preview | [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) |
| **Tool call / Tool response intervention points** | Preview | [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview) |
| **Spotlighting, Groundedness, PII guardrail controls** | Preview | [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview) |
| **Hosted agents** | Preview | [Hosted agents in Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) |

Evaluators **not** marked preview (e.g., Coherence, Fluency, Relevance, Violence, Hate and Unfairness, Self-Harm, Sexual, Tool Call Accuracy, Tool Selection, Task Navigation Efficiency) are GA. ([Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators))

### Why It Matters

> "As your organization evolves from isolated copilots to autonomous multi-agent fleets, you need unified oversight. Foundry Control Plane provides the centralized management that you need to scale reliably."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

For the Zava demo, this is the surface that makes the demo "enterprise-ready" — a technical decision-maker can see not just the agent working, but the operational governance around it.

### Key Features

- **Overview pane**: Fleet health, active agents, cost trends, run completion rate, prevented behaviors
- **Assets pane**: Unified inventory of all agents, models, and tools across projects; drill-down into evaluation/monitoring
- **Compliance pane**: Define/enforce guardrail policies; integrations with Azure Policy, Defender, Microsoft Purview
- **Quota pane**: View model deployments and quota consumption
- **Admin pane**: Cross-project visibility of users, connected resources, and project configuration

([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))

---

## 2. Key Concepts

### 2.1 Foundry Resource Hierarchy

Microsoft Foundry uses a layered architecture:

> "Microsoft Foundry organizes AI workloads through a layered architecture: a top-level Foundry resource for governance, projects for development isolation, and connected Azure services for storage, search, and secrets management."
> — Source: [Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture)

```
Subscription
  └── Resource Group
        └── Foundry Resource (top-level governance, model deployments, security)
              ├── Project A (development boundary, agents, evaluations, files)
              │     ├── Agent 1
              │     ├── Agent 2
              │     └── Connected: Application Insights, Storage, Key Vault
              └── Project B
                    └── ...
```

> "Connected resources like Storage, Key Vault, and Azure AI Search are independent Azure resources with their own governance boundaries. You manage networking, access policies, and compliance settings for these resources separately from the Foundry resource."
> — Source: [Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture)

### 2.2 Agent Types in Foundry Agent Service

Foundry Agent Service supports three agent types, each with different tracing maturity:

> "Foundry Agent Service is a fully managed platform for building, deploying, and scaling AI agents."
> — Source: [What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview)

| Agent Type | Description | Tracing Status |
|------------|-------------|----------------|
| **Prompt agents** | Defined through configuration — instructions, model selection, and tools. Created in portal or via SDK. | **GA** |
| **Workflow agents** | Orchestrate sequences of actions or coordinate multiple agents using declarative definitions. | Preview |
| **Hosted agents** | Containerized agents deployed with Agent Framework, LangGraph, or custom code. | Preview |

**For the Zava demo:** The Foundry Customer Service Agent is a **prompt agent** — it is created via the Foundry Agent Service with instructions and tools (Code Interpreter). It is NOT a hosted agent (which would be a containerized application). This classification matters because:

1. **Tracing is GA** for prompt agents (not preview)
2. **Server-side traces are auto-captured** for prompt agents without additional instrumentation
3. **Guardrails apply** because the agent is developed in Foundry Agent Service

([What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview))

### 2.3 Tracing & Observability

#### What Is Tracing?

> "Microsoft Foundry provides an observability platform for monitoring and tracing AI agents. It captures key details during an agent run, such as inputs, outputs, tool usage, retries, latencies, and costs."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

**GA vs Preview status:**

> "Tracing is generally available for prompt agents only. Workflow, hosted, and custom agents are in preview."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

#### What Is Auto-Captured vs Opt-In?

**Server-side traces (auto-captured):**

> "Foundry automatically logs server-side traces for Prompt agents, Host agents, and workflows in the Foundry portal. Once tracing is enabled in your Foundry project, you'll have access to out-of-the-box traces for the past 90 days."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

**Implication for the Zava demo:** The Zava Foundry Customer Service Agent is a prompt agent. Server-side traces — covering the agent's model calls, tool calls (Code Interpreter), inputs, outputs, and latencies — are auto-captured whenever the agent runs, whether invoked from the portal playground or via the API from the local backend. **No additional OpenTelemetry instrumentation is needed for the Foundry agent's execution traces to appear in the portal.**

However, the *local backend's own processing* (e.g., the Python/Node code that receives the React UI request, calls the Foundry agent API, and handles the A2A protocol) is NOT covered by server-side traces. If you want traces of the local backend logic itself, you would need client-side OpenTelemetry instrumentation. For the demo's purposes, the Foundry agent's server-side traces are sufficient to show meaningful trace data to the customer.

**Client-side traces (opt-in):** If you need traces of your own application code calling the agent, install OpenTelemetry instrumentation packages:

```bash
pip install azure-ai-projects azure-identity opentelemetry-sdk azure-core-tracing-opentelemetry
```
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) | Provenance: verbatim

#### What's Captured in a Trace?

At a high level, tracing captures:
- User inputs and agent outputs
- Tool usage, including tool calls and results
- Token consumption
- Time signals such as duration and latency

([Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept))

#### OpenTelemetry Support

> "OpenTelemetry (OTel) provides standardized protocols for collecting and routing telemetry data. Foundry uses OpenTelemetry semantic conventions so traces are consistent across supported tools and integrations."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

**Multi-agent semantic conventions:** Microsoft, in collaboration with Cisco Outshift, has introduced new semantic conventions for multi-agent systems built on OpenTelemetry and W3C Trace Context. These conventions are integrated into:

- Foundry
- Microsoft Agent Framework
- LangChain
- LangGraph
- OpenAI Agents SDK

([Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept))

Key span types for multi-agent observability:

| Type | Span Name | Purpose |
|------|-----------|---------|
| Span | `execute_task` | Task planning and event propagation |
| Child Span | `agent_to_agent_interaction` | Traces communication between agents |
| Child Span | `agent.state.management` | Context, short/long-term memory management |
| Child Span | `agent_planning` | Agent's internal planning steps |
| Child Span | `agent orchestration` | Agent-to-agent orchestration |
| Attribute | `tool_definitions` | Tool purpose/configuration |
| Attribute | `llm_spans` | Model call spans |
| Attribute | `tool.call.arguments` | Arguments passed during tool invocation |
| Attribute | `tool.call.results` | Results returned by tool |

([Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept))

#### Viewing Traces

**In the Foundry portal:**

> "In your Foundry project, go to the Traces tab in your agents or workflows. You can search, filter, or sort ingested traces from the last 90 days. Select a trace to step through each span, identify issues, and observe how your application responds."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

You can also view **Conversation results** — the persistent context of an end-to-end dialogue — which shows conversation history, response information and tokens, ordered actions/run steps/tool calls, and inputs/outputs between user and agent. ([Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup))

**In Application Insights / Azure Monitor:**

> "The Agent details view in Application Insights provides a unified experience for monitoring AI agents across multiple sources, including Microsoft Foundry, Copilot Studio, and third-party agents."
> — Source: [Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view)

Access path: Azure portal → Application Insights resource → **Agents (Preview)** in the navigation menu. From Foundry, you can also navigate via the agent's **Monitoring tab → View in Azure Monitor**. ([Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view))

The Application Insights Agent details view supports:
- View Traces with Agent Runs (all executions)
- View Traces with Gen AI Errors (failed/problematic runs)
- Sort by "Most tokens used" to identify expensive operations
- End-to-end transaction details with a "simple view" showing agent steps in story-like fashion
- Pre-built **Grafana dashboards** for Agent Framework, Agent Framework workflow, and Foundry-specific metrics

([Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view))

### 2.4 Evaluation

#### What Are Evaluators?

> "Evaluators are specialized tools that measure the quality, safety, and reliability of AI responses throughout the development lifecycle."
> — Source: [Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability)

Microsoft Foundry provides built-in evaluators across several categories:

**General Purpose Evaluators:**
| Evaluator | Purpose | Status |
|-----------|---------|--------|
| Coherence | Measures logical consistency and flow | GA |
| Fluency | Measures natural language quality and readability | GA |

**RAG Evaluators:**
| Evaluator | Purpose | Status |
|-----------|---------|--------|
| Retrieval | Measures retrieval effectiveness | GA |
| Document Retrieval | Measures retrieval accuracy given ground truth | GA |
| Groundedness | How grounded the response is in context (1–5 score) | GA |
| Groundedness Pro | Binary pass/fail grounding check via Content Safety service | **Preview** |
| Relevance | How relevant response is to the query | GA |
| Response Completeness | Whether response is complete vs ground truth | **Preview** |

**Risk and Safety Evaluators:**
| Evaluator | Purpose | Status |
|-----------|---------|--------|
| Hate and Unfairness | Biased, discriminatory, or hateful content | GA |
| Sexual | Inappropriate sexual content | GA |
| Violence | Violent content or incitement | GA |
| Self-Harm | Content promoting self-harm | GA |
| Protected Materials | Unauthorized copyrighted content | GA |
| Indirect Attack (XPIA) | Indirect jailbreak attempts | GA |
| Code Vulnerability | Security issues in generated code | GA |
| Ungrounded Attributes | Fabricated/hallucinated information | GA |
| Prohibited Actions | Violations of disallowed actions | **Preview** |
| Sensitive Data Leakage | Exposure of sensitive information | **Preview** |

**Agent Evaluators:**
| Evaluator | Purpose | Status |
|-----------|---------|--------|
| Task Adherence | Follows system instructions | **Preview** |
| Task Completion | Completed requested task end-to-end | **Preview** |
| Intent Resolution | Accurately identifies user intentions | **Preview** |
| Task Navigation Efficiency | Steps match optimal path | GA |
| Tool Call Accuracy | Overall tool call quality | GA |
| Tool Selection | Selected appropriate tools | GA |
| Tool Input Accuracy | Parameter correctness | GA |
| Tool Output Utilization | Correct use of tool outputs | GA |
| Tool Call Success | All tool calls executed without failures | GA |

([Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators))

**Azure OpenAI Graders:**
| Evaluator | Purpose |
|-----------|---------|
| Model Labeler | Classifies content using custom guidelines |
| String Checker | Flexible text validations and pattern matching |
| Text Similarity | Semantic closeness evaluation |
| Model Scorer | Numerical scores based on custom guidelines |

([Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators))

#### Playground Evaluations

> "Evaluations in the agents playground are enabled by default for all Foundry projects and are included in consumption-based billing. To turn off playground evaluations, select metrics in the upper right of the agents playground and unselect all evaluators."
> — Source: [Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability)

### 2.5 Content Safety / Guardrails

#### Default Safety Filters

All Foundry models are assigned the `Microsoft.DefaultV2` guardrail by default. Guardrails consist of **controls** that define a risk to detect, intervention points to scan, and the response action.

> "Microsoft Foundry provides safety and security guardrails that you can apply to core models and agents. Agent guardrails are in preview."
> — Source: [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview)

#### Guardrails Scope — Foundry Agent Service Only

**This is critical for the Zava demo:**

> "The guardrail system currently applies only to agents developed in the Foundry Agent Service, not to other agents registered in the Foundry Control Plane."
> — Source: [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview)

**What this means for the Zava demo:**
- ✅ **Foundry Customer Service Agent (prompt agent):** Covered by the guardrail system. The `Microsoft.DefaultV2` guardrail applies to its model deployment and can be explicitly assigned to the agent.
- ❌ **AKS Manufacturing Ops Agent (LangGraph):** NOT covered by Foundry guardrails. This agent runs outside Foundry Agent Service. Its content safety must be handled separately (e.g., via Azure AI Content Safety API calls in the LangGraph code, or accepted as out of scope for the Foundry Control Plane demo).

#### Four Intervention Points

1. **User input** — the prompt sent to a model or agent
2. **Tool call (Preview)** — the action/data the agent proposes to send to a tool (agents only)
3. **Tool response (Preview)** — content returned from a tool to the agent (agents only)
4. **Output** — the final completion returned to the user

([Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview))

**Risk categories and applicability:**

| Risk | Models | Agents (Preview) |
|------|--------|-------------------|
| Hate | ✅ | ✅ |
| Sexual | ✅ | ✅ |
| Self-harm | ✅ | ✅ |
| Violence | ✅ | ✅ |
| User prompt attacks | ✅ | ✅ |
| Indirect attacks | ✅ | ✅ |
| Protected material (code) | ✅ | ✅ |
| Protected material (text) | ✅ | ✅ |
| Spotlighting (Preview) | ✅ | ❌ |
| Groundedness (Preview) | ✅ | ❌ |
| PII (Preview) | ✅ | ✅ |
| Task Adherence | ✅ | ✅ |

([Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview))

**Severity levels** for content risks (Hate, Sexual, Self-harm, Violence):
- **Off** — Detection disabled (approved customers only)
- **Low** — Flags low severity and above (most restrictive)
- **Medium** — Flags medium and above
- **High** — Flags only most severe content (least restrictive)

([Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview))

**Guardrail inheritance for agents:**

> "Risks are detected in an agent based on the guardrail it's assigned, not the guardrail of its underlying model. The agentic guardrail fully overrides the model's guardrail."
> — Source: [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview)

Default guardrail assignment for agents:
- If a custom guardrail is assigned to the agent, that guardrail is used
- If no custom guardrail is assigned, the agent inherits the guardrail of its underlying model deployment
- An agent only uses `Microsoft.DefaultV2` if its model deployment uses it, or if explicitly assigned

([Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview))

#### Viewing Safety Triggers

In the Foundry portal's **Risks + alerts** section:

> "You can view Defender for Cloud security alerts and recommendations to improve your security posture in the Risks + alerts section."
> — Source: [Responsible AI for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/responsible-use-of-ai-overview)

When a guardrail control triggers "Annotate and block," a message appears in the chat playground with details on which risk was detected and at which intervention point. ([How to configure guardrails and controls](https://learn.microsoft.com/en-us/azure/foundry/guardrails/how-to-create-guardrails))

### 2.6 Governance / RBAC

**Built-in Foundry roles** (recently renamed):

| Role | Key Capabilities |
|------|-----------------|
| **Foundry User** | Reader access + data actions (build/develop in project). Least-privilege role. |
| **Foundry Project Manager** | Create projects, build/develop, assign Foundry User role to others |
| **Foundry Account Owner** | Full resource management, deploy models, assign Foundry User/ACR/monitoring roles |
| **Foundry Owner** | Full access: manage + build + develop + assign roles. Highly privileged. |

> "The Foundry RBAC roles were recently renamed. Foundry User, Foundry Owner, Foundry Account Owner, and Foundry Project Manager were previously named Azure AI User, Azure AI Owner, Azure AI Account Owner, and Azure AI Project Manager."
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)

**Minimum role for the demo user:** Foundry User on the Foundry resource + Reader on the resource (if not already covered).

> "Assign the Foundry User role on your Foundry resource to your user principal."
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)

**To publish agents**, you need the **Foundry Project Manager** role (minimum) on the Foundry resource scope. ([Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry))

**Role GUIDs** (use these in code during rename rollout):
- Foundry User: `53ca6127-db72-4b80-b1b0-d745d6d5456d`
- Foundry Owner: `c883944f-8b7b-4483-af10-35834be79c4a`
- Foundry Account Owner: `e47c6f54-e4a2-4754-9501-8e0985b135e1`
- Foundry Project Manager: `eadc314b-1a2d-4efa-be10-5d325db5065e`

([Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry))

**Connected resources governance:** Storage, Key Vault, and Azure AI Search are independent Azure resources with their own governance boundaries. Their networking, access policies, and compliance are managed separately from Foundry. ([Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture))

**Role management paths:**
- Foundry portal: Operate → Admin → select project → Add user
- Azure portal: IAM blade on the Foundry resource or project
- Azure CLI: `az role assignment create`

([Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry))

---

## 3. Getting Started

### Prerequisites

- An Azure account with an active subscription
- A Foundry project (created via the Foundry portal or Bicep)
- An Application Insights resource (required for tracing — without it, no traces appear)
- Appropriate RBAC:
  - **Foundry User** (scope: Foundry resource) — minimum for building/viewing in a project
  - **Foundry Account Owner** or **Foundry Owner** (scope: Foundry resource) — for managing guardrails and model deployments
  - **Log Analytics Reader** (scope: Application Insights resource) — for viewing/querying traces
  - **Cost Management Reader** (scope: subscription or resource group) — for viewing cost data
- At least one model deployment in the project

([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview), [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup), [Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs))

### Installation & Setup

#### Terminal Commands

```bash
# 1. Sign in to Azure
az login

# 2. Create a resource group (if not already existing)
az group create --name rg-zava-demo --location eastus2

# 3. Assign Foundry User role to the demo user (use GUID during rename rollout)
az role assignment create \
  --role "53ca6127-db72-4b80-b1b0-d745d6d5456d" \
  --assignee "user@contoso.com" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-zava-demo

# 4. Assign Log Analytics Reader for trace viewing
az role assignment create \
  --role "Log Analytics Reader" \
  --assignee "user@contoso.com" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-zava-demo

# 5. Install Python SDK packages for tracing and evaluation
pip install "azure-ai-projects>=2.0.0" azure-identity opentelemetry-sdk azure-core-tracing-opentelemetry
```
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry), [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) | Provenance: adapted

#### Python Setup

```python
# Setup: Initialize the Foundry project client for evaluation and tracing
# Source: https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent
# Provenance: adapted

import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

endpoint = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
model_deployment = os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"]

credential = DefaultAzureCredential()
project_client = AIProjectClient(endpoint=endpoint, credential=credential)
client = project_client.get_openai_client()

print(f"Connected to project at: {endpoint}")
print(f"Using model deployment: {model_deployment}")
```
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent) | Provenance: adapted

---

## 4. Core Usage

### 4.1 Enabling Tracing (Portal Walkthrough)

Steps to connect Application Insights and enable tracing:

1. Sign in to [Microsoft Foundry portal](https://ai.azure.com)
2. Ensure the **New Foundry** toggle is on
3. Open your Foundry project
4. In the left navigation, select **Agents**
5. At the top, select **Traces**
6. On the right, select **Connect** to create or connect an Application Insights resource
7. To connect existing: select the resource → **Connect**
8. To create new: select **Create new** → complete the wizard

Alternative path: Project details dropdown → **Connected resources** tab → **Add connection** → select **Application Insights**.

([Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup))

> "Make sure you have the permissions you need to query telemetry. For log-based queries, start by assigning the Log Analytics Reader role."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

### 4.2 Running an Evaluation Against an Agent

#### Concrete Minimal Evaluation Artifact for the Zava Demo

To ensure the customer sees evaluation insights in the Foundry portal during the demo, run at least one evaluation. Here is the minimum concrete artifact:

**Step 1: Create a test dataset (`test-queries.jsonl`)**

The official documentation specifies a JSONL file where each line is a JSON object with a `query` field:

```jsonl
{"query": "Can Zava fulfill an order of 500 P-100 pump assemblies by June 15?"}
{"query": "What is the current inventory level for P-200 motor housings?"}
{"query": "Can we produce 1000 units of V-300 valves in the next 3 weeks?"}
{"query": "What is the lead time for ordering raw materials for P-100 pumps?"}
{"query": "Is there sufficient production capacity to handle a rush order of 200 M-500 motors by next Friday?"}
```
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent) | Provenance: adapted (format from official docs, content tailored to Zava demo)

**Step 2: Choose evaluators**

Use this set for the demo (one quality + one agent behavior + one safety):

| Evaluator | Builtin Name | Why | Judge Model Required? | Status |
|-----------|-------------|-----|----------------------|--------|
| **Task Adherence** | `builtin.task_adherence` | Shows the agent follows its instructions | Yes | Preview |
| **Coherence** | `builtin.coherence` | Shows response quality/readability | Yes | GA |
| **Violence** | `builtin.violence` | Shows safety evaluation | No (rule-based) | GA |

> "AI-assisted evaluators, like Task Adherence and Coherence, require a model deployment name in `initialization_parameters`. The value must match a GPT deployment name in your project — this is the judge model used to score responses."
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent)

**Required judge-model deployment:** An Azure OpenAI deployment with a GPT model that supports chat completion (e.g., `gpt-4o` or `gpt-4o-mini`). This can be the same model deployment used by the Foundry agent, or a separate one. The deployment name is passed as `initialization_parameters.deployment_name` to AI-assisted evaluators. ([Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent))

**Step 3: Run the evaluation (complete Python script)**

```python
# Example: Run a quality + safety evaluation against the Zava Foundry agent
# Source: https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent
# Provenance: adapted (condensed from official doc, added comments, Zava-specific names)

import os
import time
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

# --- Setup ---
endpoint = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
model_deployment = os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"]

credential = DefaultAzureCredential()
project_client = AIProjectClient(endpoint=endpoint, credential=credential)
client = project_client.get_openai_client()

# --- Step 1: Upload test dataset ---
dataset = project_client.datasets.upload_file(
    name="zava-agent-test-queries",
    version="1",
    file_path="./test-queries.jsonl",
)
print(f"Dataset uploaded: {dataset.id}")

# --- Step 2: Define evaluators ---
testing_criteria = [
    {
        "type": "azure_ai_evaluator",
        "name": "Task Adherence",
        "evaluator_name": "builtin.task_adherence",
        "data_mapping": {
            "query": "{{item.query}}",
            "response": "{{sample.output_items}}",
        },
        "initialization_parameters": {"deployment_name": model_deployment},
    },
    {
        "type": "azure_ai_evaluator",
        "name": "Coherence",
        "evaluator_name": "builtin.coherence",
        "data_mapping": {
            "query": "{{item.query}}",
            "response": "{{sample.output_text}}",
        },
        "initialization_parameters": {"deployment_name": model_deployment},
    },
    {
        "type": "azure_ai_evaluator",
        "name": "Violence",
        "evaluator_name": "builtin.violence",
        "data_mapping": {
            "query": "{{item.query}}",
            "response": "{{sample.output_text}}",
        },
    },
]

# --- Step 3: Create evaluation container ---
data_source_config = {
    "type": "custom",
    "item_schema": {
        "type": "object",
        "properties": {"query": {"type": "string"}},
        "required": ["query"],
    },
    "include_sample_schema": True,
}

evaluation = client.evals.create(
    name="Zava Agent Quality Evaluation",
    data_source_config=data_source_config,
    testing_criteria=testing_criteria,
)
print(f"Evaluation created: {evaluation.id}")

# --- Step 4: Run evaluation against the agent ---
eval_run = client.evals.runs.create(
    eval_id=evaluation.id,
    name="Zava Agent Eval Run 1",
    data_source={
        "type": "azure_ai_target_completions",
        "source": {"type": "file_id", "id": dataset.id},
        "input_messages": {
            "type": "template",
            "template": [
                {
                    "type": "message",
                    "role": "user",
                    "content": {"type": "input_text", "text": "{{item.query}}"},
                }
            ],
        },
        "target": {
            "type": "azure_ai_agent",
            "name": "zava-customer-service-agent",
            "version": "1",
        },
    },
)
print(f"Evaluation run started: {eval_run.id}")

# --- Step 5: Poll for results ---
while True:
    run = client.evals.runs.retrieve(run_id=eval_run.id, eval_id=evaluation.id)
    if run.status in ["completed", "failed"]:
        break
    time.sleep(5)

print(f"Status: {run.status}")
print(f"Report URL: {run.report_url}")
# Open the report_url in a browser to view results in the Foundry portal Evaluations tab
```
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent) | Provenance: adapted

**Step 4: View results in the portal**

> "Evaluations typically complete in a few minutes, depending on the number of queries. Poll for completion and retrieve the report URL to view the results in the Microsoft Foundry portal under the Evaluations tab."
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent)

Portal navigation: **Foundry portal → your project → Evaluations tab** (left navigation). The `report_url` returned by the SDK links directly to the evaluation results page showing aggregated pass/fail counts, per-evaluator scores, token usage per model, and row-level output details. ([Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent))

### 4.3 Creating Guardrails (Portal Walkthrough)

1. Go to Foundry portal → your project
2. Select **Build** in the top-right menu
3. Select **Guardrails** from the left navigation
4. Select **Create Guardrail**
5. **Step 1 — Add Controls**: Select risks, intervention points, actions, severity levels
6. **Step 2 — Assign**: Add agents and/or models
7. **Step 3 — Review & Name**: Review, name, and create

To test: Select a guardrail → **Try in Playground** → send queries to trigger safety filters.

([How to configure guardrails and controls](https://learn.microsoft.com/en-us/azure/foundry/guardrails/how-to-create-guardrails))

### Terminal / CLI Commands

```bash
# View current role assignments for the Foundry resource
az role assignment list \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-zava-demo/providers/Microsoft.CognitiveServices/accounts/<foundry-resource> \
  --output table

# Assign Foundry Owner role to the project managed identity
az role assignment create \
  --role "c883944f-8b7b-4483-af10-35834be79c4a" \
  --assignee-object-id <project-managed-identity-oid> \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-zava-demo
```
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry) | Provenance: adapted

---

## 5. Configuration & Best Practices

### Recommended Configuration for the Demo

| Configuration Item | Setting | Why |
|---|---|---|
| Application Insights | Connected to the Foundry project | Required for tracing — no App Insights = no traces |
| Tracing | Enabled (server-side auto-capture for prompt agents) | Auto-captures agent run telemetry (GA for prompt agents) |
| Log Analytics Reader | Assigned to demo user | Required to view/query traces |
| Default guardrail | `Microsoft.DefaultV2` (active by default on model deployments) | Content safety out of the box |
| Playground evaluations | Enabled (default) | Real-time quality metrics in the playground |
| RBAC | Foundry Owner for the demo admin; Foundry User for demo viewer | Full control vs read-only |

### Best Practices

**Tracing:**
> "Use consistent span attributes: Apply the same attribute names and formats across all agents and tools to simplify querying and analysis."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

> "Correlate evaluation run IDs: Link trace data with evaluation runs to analyze both quality and performance in a unified view."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

**Security:**
> "Redact sensitive content: Remove or mask personal data, secrets, and credentials from prompts, tool arguments, and span attributes before they reach telemetry."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

**RBAC:**
> "Don't assign built-in roles that start with Cognitive Services. These roles are designed for accessing AI Services resources directly and don't apply to Foundry scenarios. Similarly, don't use the Azure AI Developer role for Foundry work."
> — Source: [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)

### Common Pitfalls & Anti-Patterns

1. **Not connecting Application Insights** — Tracing won't work without it. No App Insights = no traces in the portal.
2. **Missing Log Analytics Reader role** — Users will see authorization errors when querying telemetry.
3. **Using Cognitive Services roles** — These don't apply to Foundry; use Foundry-specific roles instead.
4. **Assuming agent guardrails inherit from model** — If you assign a custom guardrail to the agent, it fully overrides the model's guardrail. An agent with no guardrail assigned inherits from its model deployment, not from `DefaultV2` directly.
5. **Not accounting for tracing costs** — Tracing stores data in Application Insights, which incurs costs based on data volume and retention settings.
6. **Assuming Foundry guardrails cover external agents** — The guardrail system applies only to agents in Foundry Agent Service. The AKS LangGraph agent is NOT covered.

---

## 6. Advanced Topics

### 6.1 Accessing the Control Plane Operate Panes

The Control Plane's key panes are accessed via **Operate** in the Foundry portal toolbar:

> "The capabilities described previously are organized into panes that you access by selecting Operate on the upper-right toolbar of the Foundry workspace. From Operate, you can monitor, govern, and optimize every agent, model, and deployment within your subscription."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

1. **Overview**: Fleet health KPIs — active agents, cost trends, run completion rate, prevented behaviors. Drill into anomalies via contextual charts.
2. **Assets**: Unified table of all AI assets across projects within a subscription. Filter/sort by version, tags, health score, cost, alerts, token usage. Drill into Evaluation or Monitoring tabs per asset.
3. **Compliance**: Define/enforce guardrail policies. Integrations with Azure Policy, Defender, Microsoft Purview. Track versioned policy assignments for auditability.
4. **Quota**: View model deployments and quota consumption. Toggle "Show all" to see available models and regions.
5. **Admin**: Cross-project visibility — all projects, users, connected resources. Add/remove users, attach connected resources, assign access at parent scope.

([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))

### 6.2 AI Gateway Prerequisite for Advanced Governance

The Control Plane overview explicitly lists an AI gateway as a prerequisite for advanced governance:

> "To explore Foundry Control Plane, you need: [...] An AI gateway configured for advanced governance features."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

The "Get started" section links to configuring an AI gateway:

> "Configure an AI gateway: Enable advanced governance features in your Foundry projects."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

**What the AI gateway enables** (beyond what is available without it):
- Token limit enforcement on model deployments
- Advanced compliance monitoring and policy enforcement at fleet scale
- Deeper integration with Defender and Purview for governance signals

**What works WITHOUT the AI gateway** (Tier 1 demo features):
- Tracing (server-side auto-capture for prompt agents)
- Evaluation (SDK-driven and playground evaluations)
- Guardrails (default `Microsoft.DefaultV2` on model deployments)
- Basic Operate pane visibility (Assets, Quota, Admin)
- Application Insights Agents blade

See Section 8 for the full two-tier breakdown.

### 6.3 Multi-Agent Tracing (A2A Context)

The OpenTelemetry semantic conventions for multi-agent systems include an `agent_to_agent_interaction` child span type, which traces communication between agents.

> "Microsoft, in collaboration with Cisco Outshift, has introduced new semantic conventions for multi-agent systems, built on OpenTelemetry and W3C Trace Context. These conventions standardize telemetry for multi-agent workflows, enabling consistent logging of metrics for quality, performance, safety, and cost, including tool invocations and collaboration."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

**For the Zava demo:**
- The **Foundry prompt agent's execution** (model calls, Code Interpreter tool calls, inputs/outputs) will appear as server-side traces in the Foundry portal automatically.
- The **AKS LangGraph agent's traces** will NOT appear in Foundry traces unless it exports OpenTelemetry traces to the same Application Insights resource.
- The LangGraph integration is listed as a supported framework in the OTel semantic conventions. If the AKS agent uses the OTel LangGraph integration and exports to the same Application Insights connection string, both sides could be visible in Application Insights (though not necessarily in the Foundry portal's Traces tab).
- **Cross-agent trace correlation** may require manual W3C trace context header propagation across the A2A HTTP calls.

### 6.4 Continuous Evaluation and CI/CD Integration

Post-deployment monitoring capabilities:
- **Continuous evaluation**: Quality and safety evaluation of production traffic at a sampled rate
- **Scheduled evaluation**: Using test datasets to detect system drift
- **Scheduled red teaming**: Adversarial testing via the AI Red Teaming Agent (uses Microsoft's PyRIT framework)
- **Azure Monitor alerts**: Notifications when outputs fail quality thresholds or produce harmful content
- **GitHub Actions integration**: Use evaluation as a quality gate in CI/CD pipelines

([Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability))

### 6.5 Defender and Purview Integration

From the Control Plane:

> "View Defender and Microsoft Purview alerts directly on the Foundry Control Plane dashboard. Track rate limits, token usage, and cost anomalies to prevent inefficiency or abuse."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

The Compliance pane integrates with Azure Policy, Defender, and Microsoft Purview for identity, data, and threat safeguards. ([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))

### 6.6 Audit Logs

The Foundry architecture supports **diagnostic logging** that can route logs to Log Analytics, Storage, or Event Hubs:

> "Diagnostic logging: Enable diagnostic settings to route logs to Log Analytics, Storage, or Event Hubs for analysis and retention."
> — Source: [Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture)

For Azure resource-level audit logging, standard Azure Activity Log captures control-plane operations (resource creation, deletion, role assignments). Foundry resources, as `Microsoft.CognitiveServices/accounts`, support Azure Monitor diagnostic settings for this purpose. ([Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture))

---

## 7. Pricing, Limits & Quotas

### Cost Visibility

> "Track your Foundry spending using cost analysis tools. You can view costs by day, month, or year, compare against budgets, and identify spending trends. Access cost information from the Microsoft Foundry portal or the Azure portal."
> — Source: [Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs)

Required roles for cost viewing:
- **Cost Management Reader** — View costs and usage data
- **Foundry User** — View Foundry resource data and usage context

([Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs))

### Token Usage and Model Costs

Token usage is visible in multiple places:
1. **Evaluation results**: Per-model token usage is returned in evaluation run results (model name, invocation count, total/prompt/completion tokens). ([Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent))
2. **Control Plane Overview pane**: Cost trends and token usage across the fleet. ([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))
3. **Control Plane Assets pane**: Token usage per asset, filterable. ([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))
4. **Application Insights Agent view**: Sort traces by "Most tokens used". ([Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view))
5. **Azure Cost Management**: Meter-level cost breakdowns by resource. ([Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs))

### Tracing Costs

> "Tracing stores telemetry data in Azure Monitor Application Insights, which may incur costs based on data volume and retention settings."
> — Source: [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept)

### Evaluation Costs

> "Observability features such as risk and safety evaluations and evaluations in the agent playground are billed based on consumption as listed in our Azure pricing page."
> — Source: [Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability)

### No Dedicated Pricing Calculator Entry

> "Foundry doesn't have a dedicated page in the Azure pricing calculator because Foundry is composed of several optional Azure services."
> — Source: [Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs)

### Quota Management

The Control Plane **Quota** pane shows model deployments and quota consumption. Use the "Show all" toggle to see all available models and regions, including undeployed ones. ([What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview))

---

## 8. Demo Wiring Guide — What to Configure for the Zava Demo

This section provides a two-tier checklist answering the demo question directly: what should be wired up so a customer demo user can open the Foundry portal and see meaningful operational information?

### Infrastructure Dependency Reconciliation

The demo requires **one additional Azure resource** beyond the Foundry project itself: **Application Insights**. This is a hard requirement — without it, no traces appear in the portal. The AI gateway is NOT required for Tier 1 demo features but IS required for advanced governance features (Tier 2). This reconciles the apparent contradiction between "minimal setup" and "requires infrastructure" — the minimum is small (App Insights only) but not zero.

---

### Tier 1 — Minimum for Portal-Visible Assets, Traces, Evaluation, and Safety

These are the items the customer sees by default once the Foundry project is set up with Application Insights. Every bullet has a direct citation and verbatim quote showing where in the portal the feature appears.

#### (a) Model Deployments Visible in the Portal

- Deploy two models in the Foundry project (e.g., GPT-5.5 and GPT-5.4-mini)
- **Where it appears:** Foundry portal → **Operate → Assets** pane

> "This pane provides a unified, searchable table of all AI assets across projects within a subscription. It brings together critical metadata and health indicators, so you can assess and act on your AI resources efficiently."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

- Also visible in the **Operate → Quota** pane:

> "The Quota pane shows your model deployments and how much quota each deployment consumes."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

#### (b) Foundry Agent Visible in the Portal

- Create the Foundry prompt agent in the project (via SDK or portal)
- **Where it appears:** Foundry portal → project → **Agents** (left navigation) and in **Operate → Assets** pane

> "Use the Assets pane to track, analyze, and manage every agent, model, and tool from one place."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

- To publish the agent for endpoint access, the user needs at minimum the **Foundry Project Manager** role. ([Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry))

#### (c) Traces of Agent Runs Visible in the Portal

**Configuration required:**
1. **Connect Application Insights** to the Foundry project (portal: Agents → Traces → Connect)
2. **Assign Log Analytics Reader** role to the demo viewer on the App Insights resource
3. **Run the agent at least once** — e.g., via the playground or the API

**What auto-appears (no instrumentation needed):**

The Zava Foundry Customer Service Agent is a **prompt agent**. Server-side traces are auto-captured:

> "Foundry automatically logs server-side traces for Prompt agents, Host agents, and workflows in the Foundry portal. Once tracing is enabled in your Foundry project, you'll have access to out-of-the-box traces for the past 90 days."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

This means the agent's model calls, tool calls (Code Interpreter), inputs, outputs, latencies, and token consumption appear automatically in the Foundry portal — **regardless of whether the agent is invoked from the playground or from the local backend via the API**.

**Where to view:**
- **Foundry portal:** Project → **Agents → Traces tab** (search, filter, 90-day retention)

> "In your Foundry project, go to the Traces tab in your agents or workflows. You can search, filter, or sort ingested traces from the last 90 days."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

- **Application Insights:** Agents (Preview) blade → drill into individual runs

> "The Agent details view in Application Insights provides a unified experience for monitoring AI agents across multiple sources, including Microsoft Foundry, Copilot Studio, and third-party agents."
> — Source: [Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view)

**Tracing status for this demo:** **GA** (tracing is generally available for prompt agents).

> "Tracing is generally available for prompt agents only. Workflow, hosted, and custom agents are in preview."
> — Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup)

**What is NOT auto-captured:**
- The local backend's own processing (React → backend → Foundry API call) requires client-side OpenTelemetry instrumentation if you want it in traces
- The AKS LangGraph agent's execution requires separate OTel export to the same Application Insights resource

#### (d) Evaluation Results Visible in the Portal

**This is NOT optional for the demo** — the customer should see eval insights.

**What to do:** Run the evaluation script in Section 4.2 at least once before the demo. This creates a completed evaluation run with results visible in the portal.

**Where it appears:** Foundry portal → project → **Evaluations** tab (left navigation). The `report_url` from the SDK links directly to the results page.

> "Evaluations typically complete in a few minutes, depending on the number of queries. Poll for completion and retrieve the report URL to view the results in the Microsoft Foundry portal under the Evaluations tab."
> — Source: [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent)

Additionally, **playground evaluations** provide real-time metrics when testing in the agents playground:

> "Evaluations in the agents playground are enabled by default for all Foundry projects and are included in consumption-based billing."
> — Source: [Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability)

**Minimum evaluation artifact:**
- **Dataset:** 5 rows in `test-queries.jsonl` (see Section 4.2 for the exact JSONL shape)
- **Evaluators:** Task Adherence (preview, AI-assisted) + Coherence (GA, AI-assisted) + Violence (GA, rule-based)
- **Judge model:** The same GPT deployment used by the agent (e.g., `gpt-5.5` or `gpt-5.4-mini`), or a separate `gpt-4o-mini` deployment
- **Portal path:** Foundry portal → project → **Evaluations** tab → select the completed run → view aggregated scores, per-row details, token usage

#### (e) Safety/Guardrails Visible in the Portal

**What auto-applies:**

The `Microsoft.DefaultV2` guardrail is active by default on all model deployments. When the Foundry prompt agent has no custom guardrail assigned, it inherits the guardrail from its underlying model deployment. This means content safety is active with no additional configuration.

> "An agent only uses the Microsoft.DefaultV2 guardrail if its model deployment uses that guardrail, or if you explicitly assign it."
> — Source: [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview)

**Where to view:**
- **Foundry portal:** Project → **Build → Guardrails** — shows the active guardrail, its controls, and assigned agents/models
- **Foundry portal:** Project → **Risks + alerts** (left navigation) — shows Defender for Cloud alerts

> "You can view Defender for Cloud security alerts and recommendations to improve your security posture in the Risks + alerts section."
> — Source: [Responsible AI for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/responsible-use-of-ai-overview)

**Scope limitation:** Foundry guardrails cover ONLY the Foundry prompt agent:

> "The guardrail system currently applies only to agents developed in the Foundry Agent Service, not to other agents registered in the Foundry Control Plane."
> — Source: [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview)

The AKS-side LangGraph Manufacturing Ops Agent is **not covered** by Foundry guardrails. If the customer asks about safety for the AKS agent, explain that it requires separate content safety instrumentation (e.g., Azure AI Content Safety API) or is out of scope for this Foundry Control Plane demo.

---

### Tier 2 — Optional / Required for Advanced Control Plane Governance

These features require the **AI gateway** to be configured and are NOT needed for the Tier 1 demo experience.

#### AI Gateway Prerequisite

> "To explore Foundry Control Plane, you need: [...] An AI gateway configured for advanced governance features."
> — Source: [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview)

**What the demo loses without the AI gateway:**

| Feature | Available Without AI Gateway? | Notes |
|---------|-------------------------------|-------|
| Token limit enforcement | ❌ No | Requires AI gateway to set/enforce per-deployment token rate limits |
| Advanced compliance monitoring | ❌ No | Fleet-scale compliance enforcement and remediation via the Compliance pane requires the gateway |
| Defender/Purview integration signals | Partial | Basic Risks + alerts visible; deeper integration may require the gateway |
| Tracing | ✅ Yes | Works with App Insights only |
| Evaluation | ✅ Yes | Works with SDK + model deployment only |
| Guardrails (default) | ✅ Yes | `Microsoft.DefaultV2` works without the gateway |
| Assets/Quota/Admin panes | ✅ Yes | Basic visibility works without the gateway |

#### When to Add the AI Gateway

For the Zava demo (external customer demo with public endpoints), the AI gateway is **not required** for Tier 1 portal-visible assets/traces/eval/safety. Add it only if the demo needs to show:
- Token rate limit enforcement
- Fleet-wide compliance policy management at scale
- Integrated governance signals from Defender and Purview in the Compliance pane

---

### Tier 1 Minimal Resource + Configuration Checklist

| Resource / Config | Required for Tier 1? | How to Create | Portal Visibility |
|---|---|---|---|
| Foundry resource + project | ✅ Yes | Bicep or portal | Operate → Admin |
| Model deployment 1 (e.g., GPT-5.5) | ✅ Yes | Bicep or portal | Operate → Assets, Operate → Quota |
| Model deployment 2 (e.g., GPT-5.4-mini) | ✅ Yes | Bicep or portal | Operate → Assets, Operate → Quota |
| Foundry prompt agent (V2) | ✅ Yes | SDK or portal | Project → Agents, Operate → Assets |
| Application Insights resource | ✅ Yes | Bicep or portal, then connect to project | Required for traces |
| Log Analytics Reader role for demo user | ✅ Yes | `az role assignment create` | Enables trace viewing |
| Foundry User role for demo user | ✅ Yes | Auto-assigned if user created the project, else manual | Enables portal access |
| Evaluation run (at least 1) | ✅ Yes | SDK script (Section 4.2) | Project → Evaluations tab |
| Custom guardrail | ❌ Optional | Default `Microsoft.DefaultV2` is sufficient | Build → Guardrails |
| AI gateway | ❌ Tier 2 only | See Tier 2 section | Enables advanced governance |
| OTel export from AKS agent | ❌ Optional | Configure LangGraph OTel → same App Insights | Adds AKS agent traces to App Insights |

---

## 9. Research Limitations

1. **Preview status varies by feature** — Individual features within the Control Plane have different maturity levels. The per-feature status table in Section 1 reflects the current documentation, but Microsoft may update these designations without notice.

2. **AI gateway configuration** — The Control Plane overview references "an AI gateway configured for advanced governance features" as a prerequisite, but the specific configuration page (`../configuration/enable-ai-api-management-gateway-portal`) was not fully explored in this research. The exact capabilities gated behind the AI gateway vs. available without it are documented based on the Control Plane overview text and may have additional nuances.

3. **Cross-agent trace correlation** — While the OpenTelemetry semantic conventions for multi-agent systems mention `agent_to_agent_interaction` spans and LangGraph is listed as a supported framework, there is no explicit documentation on how to correlate traces across a Foundry prompt agent and an external LangGraph agent communicating via A2A. This will likely require manual W3C trace context propagation.

4. **Tracing integrations page** — The agent tracing concept page references a "tracing integrations" page multiple times, but the URL could not be resolved (404). This page likely documents framework-specific setup for LangChain, LangGraph, OpenAI Agents SDK, etc.

5. **Audit logs** — The architecture page mentions diagnostic logging but does not provide Foundry-specific audit log schemas or categories. Standard Azure Activity Log and diagnostic settings apply, but Foundry-specific data-plane audit events are not explicitly documented.

6. **Agent-level RBAC** — RBAC is scoped at Foundry resource and project levels. There is no documented per-agent RBAC (e.g., restricting access to specific agents within a project).

7. **Content safety triggers visibility in Control Plane** — The guardrails documentation focuses on the Build experience (Guardrails page, Playground). The Control Plane's Compliance pane likely surfaces guardrail policy assignments and compliance posture, but the exact guardrail-trigger visibility in the Operate panes is not explicitly documented with screenshots or step-by-step instructions.

8. **Exact Tier 2 gateway-gated features** — The boundary between what works without the AI gateway and what requires it is inferred from the Control Plane overview's prerequisite language and "Get started" links. Microsoft does not provide a single comparison table of gateway-required vs. non-gateway features.

---

## 10. Complete Reference List

### Microsoft Learn Documentation

1. [What is Microsoft Foundry Control Plane?](https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview) — Overview of the Control Plane: capabilities, panes (Overview, Assets, Compliance, Quota, Admin), prerequisites, AI gateway
2. [Agent tracing in Microsoft Foundry (preview)](https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept) — Tracing concepts: OpenTelemetry, semantic conventions, multi-agent spans, security/privacy
3. [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup) — How to connect App Insights, enable tracing, server-side vs client-side traces, view traces in portal
4. [Observability in generative AI](https://learn.microsoft.com/en-us/azure/foundry/concepts/observability) — Overview of evaluation, monitoring, and tracing capabilities in Foundry
5. [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent) — How to run agent evaluations with the SDK: setup, evaluators, test data, interpret results
6. [Built-in Evaluators Reference](https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators) — Complete list of all built-in evaluators: general, RAG, safety, agent, and Azure OpenAI graders (with preview markings)
7. [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry) — RBAC concepts, built-in roles, role GUIDs, enterprise patterns, custom roles
8. [Microsoft Foundry architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture) — Resource hierarchy, connected resources, deployment types, monitoring, security
9. [Guardrails and controls overview](https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview) — Guardrails concepts: risks, intervention points, severity, inheritance, default guardrails, Foundry Agent Service scope limitation
10. [How to configure guardrails and controls](https://learn.microsoft.com/en-us/azure/foundry/guardrails/how-to-create-guardrails) — Step-by-step guardrail creation, assignment, testing, REST API
11. [Responsible AI for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/responsible-use-of-ai-overview) — Responsible AI overview: Discover/Protect/Govern framework, Defender alerts
12. [Monitor AI agents with Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view) — Application Insights Agent view (Preview): trace drill-down, Grafana dashboards, end-to-end transaction details
13. [Plan and manage costs for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs) — Cost estimation, billing models, Cost Management roles, monitoring spend
14. [What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview) — Agent Service overview; cited in this report to identify the Zava Foundry Customer Service Agent as a prompt agent (the agent-type classification that determines auto-captured server-side tracing).
15. [Hosted agents in Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) — Hosted agents reference; cited in this report's preview-status feature matrix to mark Hosted agents as Preview.

### GitHub Repositories

- No GitHub repositories were consulted for this topic (Control Plane is portal/documentation-focused).

### Code Samples

- No standalone code sample repositories were found for Control Plane specifically. The evaluation code pattern is adapted from the [Evaluate your AI agents](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent) Microsoft Learn documentation page. All embedded Python examples in this report are counted under Microsoft Learn Documentation references above, not as separate code samples.
