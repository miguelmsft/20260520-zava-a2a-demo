# Research Report: GPT-5.5 / GPT-5.4 / GPT-5.4-mini Model Availability in Microsoft Foundry V2

**Date:** 2026-05-20
**Access date:** 2026-05-20 (all sources accessed on this date)
**Researcher:** Copilot MS Docs Researcher Agent
**Topic slug:** model-availability
**Sources consulted:** 9 Microsoft Learn pages, 0 GitHub repositories, 0 code samples

---

## Executive Summary

This report answers whether **GPT-5.5**, **GPT-5.4**, **GPT-5.5-mini**, and **GPT-5.4-mini** are available in Microsoft Foundry V2 for use with Foundry Agents and the A2A (Agent-to-Agent) protocol. The key finding is that **GPT-5.5-mini does not exist** as a model in Azure OpenAI / Foundry V2. The three candidate models that do exist are `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.

All three existing candidate models support **A2A (Agent2Agent)** and **Code Interpreter** as Foundry Agent Service tools, as confirmed by the Tool best practices model matrix. However, the same matrix shows that the Agent Service **Functions** tool is **not supported** for these models (Functions = No). This does **not** affect the demo: base-model function/tool calling (via Chat Completions API or Responses API) is a separate, model-level capability that all three models support — the LangGraph agent calls the model API directly and gets full function calling regardless of the Agent Service tool matrix. Access and quota differ significantly: `gpt-5.4-mini` requires **no access request** and has generous default quota at all tiers, while `gpt-5.4` requires a **limited access application**, and `gpt-5.5` requires **quota requests for subscriptions below Tier 5**. For Global Standard deployment, `gpt-5.4-mini` is available in all Americas regions, while `gpt-5.5` is limited to **East US 2 and South Central US**.

The recommended pairing for this demo is **`gpt-5.5`** for the Foundry Customer Service Agent (orchestrator) and **`gpt-5.4-mini`** for the LangGraph Ops Agent (worker), deployed as **Global Standard** in a Foundry project in **East US 2** — the only US region where both models are available via Global Standard and all required Agent Service tools (Code Interpreter, A2A) are supported.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Key Concepts — Model Existence and Naming](#2-key-concepts--model-existence-and-naming)
- [3. Deployment SKUs](#3-deployment-skus)
- [4. Region Matrix](#4-region-matrix)
- [5. A2A on Foundry Agents V2 — Per-Model Support](#5-a2a-on-foundry-agents-v2--per-model-support)
- [6. Tool Support Per Model](#6-tool-support-per-model)
- [7. Quota & Access Requirements](#7-quota--access-requirements)
- [8. Recommendation](#8-recommendation)
- [9. Research Limitations](#9-research-limitations)
- [10. Complete Reference List](#10-complete-reference-list)

---

## 1. Overview

### What It Is

This research covers the availability, capabilities, deployment options, and A2A compatibility of four candidate models for the Zava Smart Order Feasibility demo: GPT-5.5, GPT-5.4, GPT-5.5-mini, and GPT-5.4-mini in Microsoft Foundry V2.

### Why It Matters

The demo requires **two separate model deployments** — one for a Foundry Agent (orchestrator) and one for a LangGraph agent (worker) — communicating via A2A. Model selection directly affects whether A2A works, which regions and SKUs are available, and whether additional access requests or quota increases are needed before deployment.

### Key Features Compared

- Model existence and exact IDs
- Global Standard deployment availability
- A2A and Code Interpreter support per model (Foundry Agent Service tools)
- Base model API capabilities (function calling, structured outputs, vision — separate from Agent Service tools)
- Access gating (open vs. limited access)
- Default quota (TPM/RPM) per subscription tier

---

## 2. Key Concepts — Model Existence and Naming

### ⚠️ Critical Finding: GPT-5.5-mini Does Not Exist

The user listed four candidate models. One of them — **GPT-5.5-mini** — **does not exist** in Azure OpenAI or Foundry V2 as of 2026-05-20. There is no model ID `gpt-5.5-mini` in the official model catalog.

The GPT-5.5 series currently contains only a single model:

| Model Series | Model IDs Available |
|---|---|
| GPT-5.5 | `gpt-5.5` |
| GPT-5.4 | `gpt-5.4`, `gpt-5.4-pro`, `gpt-5.4-mini`, `gpt-5.4-nano` |

> The models page lists GPT-5.5 series with only `gpt-5.5` (marked **NEW**), and GPT-5.4 series with `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4`, `gpt-5.4-pro`.
> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

**Nearest correctly-named equivalent for "GPT-5.5-mini":** There is none in the 5.5 series. The closest small model is **`gpt-5.4-mini`** (from the 5.4 series).

### Model Details

| Model ID | Version Date | Context Window | Max Output Tokens | Training Data (up to) |
|---|---|---|---|---|
| `gpt-5.5` | 2026-04-24 | 1,050,000 (Input: 922K, Output: 128K) | 128,000 | December 2025 |
| `gpt-5.4` | 2026-03-05 | 1,050,000 | 128,000 | August 2025 |
| `gpt-5.4-mini` | 2026-03-17 | 400,000 (Input: 272K, Output: 128K) | 128,000 | August 2025 |
| `gpt-5.4-nano` | 2026-03-17 | 400,000 (Input: 272K, Output: 128K) | 128,000 | August 2025 |

> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

### GA vs Preview Status

None of the GPT-5.5 or GPT-5.4 model IDs are explicitly marked as **Preview** on the models catalog page. For comparison, `gpt-5.2-chat` and `gpt-5.1-chat` are explicitly tagged as "**Preview**". The absence of a Preview tag on `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` means they are **not marked Preview in the checked model catalog** as of 2026-05-20, though `gpt-5.5` is marked as **NEW** and has very limited default quota (see [Section 7](#7-quota--access-requirements)).

**Important:** The **A2A protocol itself** is marked as **(preview)** on Foundry Agent Service, and **Hosted agents** are also **(preview)**, regardless of which model is used.

> "Foundry Agent Service supports the OpenResponses and Activity Protocols for Microsoft 365 publishing, an Invocations protocol for flexible endpoint integration with custom apps and services, and the **A2A protocol (preview)** for agent-to-agent communication."
> — Source: [What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview)

---

## 3. Deployment SKUs

### Available Deployment Types Per Model

Data sourced from the region availability tables:

| Model ID | Global Standard | Data Zone Standard | Global Provisioned Managed | Data Zone Provisioned Managed | Regional Provisioned Managed | Standard/Regional | Global Batch |
|---|---|---|---|---|---|---|---|
| `gpt-5.5` | ✅ | ✅ | ✅ | ✅ | ✅ (East US only) | ❌ | ❌ |
| `gpt-5.4` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| `gpt-5.4-mini` | ✅ | ❌ (not listed) | ✅ | ❌ (not listed) | ❌ (not listed) | ❌ (not listed) | ❌ |
| `gpt-5.4-nano` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

> — Source: [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability)

### Global Standard Confirmation

**All three existing candidate models (`gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`) support Global Standard deployment.** This is the user's preferred deployment type.

> "For Global deployments, prompts and responses can be processed in any Azure region where the model is deployed."
> — Source: [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability)

---

## 4. Region Matrix

### Global Standard — Americas Regions

Column headers: `brazilsouth | canadacentral | canadaeast | centralus | eastus | eastus2 | northcentralus | southcentralus | westus | westus3`

| Model ID | Version | brazilsouth | canadacentral | canadaeast | centralus | eastus | eastus2 | northcentralus | southcentralus | westus | westus3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `gpt-5.5` | 2026-04-24 | - | - | - | - | - | ✅ | - | ✅ | - | - |
| `gpt-5.4` | 2026-03-05 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4-mini` | 2026-03-17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4-nano` | 2026-03-17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4-pro` | 2026-03-05 | - | - | - | - | - | ✅ | - | ✅ | - | - |

> — Source: [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability)

### Global Standard — Europe Regions

| Model ID | Version | francecentral | germanywestcentral | italynorth | norwayeast | polandcentral | spaincentral | swedencentral | switzerlandnorth | switzerlandwest | uksouth | westeurope |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `gpt-5.5` | 2026-04-24 | - | - | - | - | ✅ | - | ✅ | - | - | - | - |
| `gpt-5.4` | 2026-03-05 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-5.4-mini` | 2026-03-17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Key Takeaway for Region Selection

- **`gpt-5.5` Global Standard** is available in only **4 regions globally**: `eastus2`, `southcentralus`, `polandcentral`, `swedencentral`.
- **`gpt-5.4-mini` Global Standard** is available in **all listed regions**.
- For Global Standard, the "region" is where the deployment is created, but **prompts and responses can be processed in any Azure region where the model is deployed**.
- **Critical constraint for the demo:** The Foundry project region determines tool availability. **South Central US does not support Code Interpreter** (see [Section 6](#6-tool-support-per-model)). Therefore, **East US 2 is the only US region** where both `gpt-5.5` Global Standard is available AND Code Interpreter is supported.

---

## 5. A2A on Foundry Agents V2 — Per-Model Support

### A2A Support Confirmed for All Three Candidate Models

The official tool-by-model support matrix on the Foundry Agent Service docs confirms that **all three existing candidate models support A2A (Agent2Agent)**:

| Model ID | Agent2Agent (A2A) |
|---|---|
| `gpt-5.5` | ✅ Yes |
| `gpt-5.4` | ✅ Yes |
| `gpt-5.4-mini` | ✅ Yes |

The matrix also shows A2A as supported for `gpt-5.4-nano` and `gpt-5.4-pro`.

> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

### A2A Protocol Status

A2A is in **preview** on Foundry Agent Service. The A2A endpoint for a Hosted agent is:

```
{project_endpoint}/agents/{name}/endpoint/protocols/a2a
```

> "The A2A protocol supports agent-to-agent delegation. All four protocols—Responses, Invocations, Activity, and A2A—can be combined in a single agent."
> — Source: [Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)

### Per-Model Observations

- **A2A support is confirmed for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`** by the Tool best practices model matrix. The matrix also shows A2A as supported for `gpt-5.4-nano` and `gpt-5.4-pro`.
- **Older models show A2A as No.** For example, `gpt-5.1-chat` and `gpt-5.1-codex` both show Agent2Agent = No in the same matrix.
- The **A2A protocol itself** is preview regardless of model choice. This is a platform-level status, not model-level.

---

## 6. Tool Support Per Model

This section separates two distinct capability layers that are easy to conflate:

1. **Foundry Agent Service tools** (Table A) — tools you can attach to a Foundry Agent via the Agent Service API. These are governed by the [Tool best practices](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice) model matrix.
2. **Base model API capabilities** (Table B) — capabilities of the model itself when called via Chat Completions API or Responses API. These are documented on the [model catalog page](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure).

**Why this distinction matters for the demo:** The Foundry Customer Service Agent (Agent A) uses Foundry Agent Service tools — it needs A2A and Code Interpreter from Table A. The LangGraph Ops Agent (Agent B) calls the model directly via Chat Completions or Responses API — it needs base-model function calling from Table B. Even though the Agent Service "Functions" tool shows **No** in Table A for all three candidate models, the LangGraph agent still gets full function/tool calling because it uses the model API directly, not the Agent Service Functions tool.

### Table A — Foundry Agent Service Tool Support per Model

Verbatim from the Tool best practices model support table. Column headers (in table order): Model | Agent2Agent | Azure AI Search | Azure Functions | Grounding Bing Custom | Grounding Bing Search | Browser Automation | Code Interpreter | Computer Use | Fabric Data Agent | File Search | **Functions** | Image Generation | MCP | OpenAPI | SharePoint | Web Search | Work IQ (preview).

> **Verbatim rows for the three candidate models:**
>
> `gpt-5.5 | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
>
> `gpt-5.4 | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
>
> `gpt-5.4-mini | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
>
> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

Simplified view of the demo-relevant Agent Service tools:

| Agent Service Tool | `gpt-5.5` | `gpt-5.4` | `gpt-5.4-mini` |
|---|---|---|---|
| **Agent2Agent (A2A)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Code Interpreter** | ✅ Yes | ✅ Yes | ✅ Yes |
| **File Search** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Functions** (Agent Service tool) | ❌ No | ❌ No | ❌ No |
| **Azure AI Search** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Web Search** | ✅ Yes | ✅ Yes | ✅ Yes |
| **MCP** | ✅ Yes | ✅ Yes | ✅ Yes |
| **OpenAPI** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Browser Automation** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Computer Use** | ❌ No | ❌ No | ❌ No |
| **Image Generation** | ❌ No | ❌ No | ❌ No |
| **Azure Functions** | ❌ No | ❌ No | ❌ No |
| **Grounding Bing Custom** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Grounding Bing Search** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Fabric Data Agent** | ✅ Yes | ✅ Yes | ✅ Yes |
| **SharePoint** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Work IQ (preview)** | ✅ Yes | ✅ Yes | ✅ Yes |

> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

**Note on the "Functions" tool:** The Agent Service **Functions** tool (column 11 in the matrix) is a specific Foundry Agent Service built-in tool — it shows **No** for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`. This means you cannot attach a built-in "Functions" tool to these models when configuring a Foundry Agent via the Agent Service API. This is distinct from base-model function/tool calling (see Table B below), which all three models fully support when called via Chat Completions API or Responses API.

### Table B — Base Model API Capabilities per Model

These are capabilities of the model itself, documented on the model catalog page. They apply whenever you call the model via Chat Completions API or Responses API — whether from a Foundry Agent, a LangGraph application, or any other client.

| Base Model Capability | `gpt-5.5` | `gpt-5.4` | `gpt-5.4-mini` |
|---|---|---|---|
| **Reasoning** | ✅ | ✅ | ✅ |
| **Responses API** | ✅ | ✅ | ✅ |
| **Chat Completions API** | ✅ | ✅ | ✅ |
| **Structured outputs** | ✅ | ✅ | ✅ |
| **Text and image processing (vision)** | ✅ | ✅ | ✅ |
| **Functions, tools, and parallel tool calling** | ✅ | ✅ | ✅ |
| **Computer use** | ✅ | ✅ | ✅ |

> The model catalog lists the following capabilities for `gpt-5.5`: "Reasoning, Responses API, Chat Completions API, Structured outputs, Text and image processing, Functions, tools, and parallel tool calling, Computer use." The same capabilities are listed for `gpt-5.4` and `gpt-5.4-mini`.
> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

**Key for this demo:** Both **Code Interpreter** and **A2A** are supported Agent Service tools for all three candidate models (Table A). The LangGraph agent's need for function calling is satisfied by base-model capabilities (Table B), not by the Agent Service Functions tool.

### Code Interpreter Region Availability (Critical)

> "Code interpreter doesn't run in regions that show 'no' for Code Interpreter (such as `southcentralus` and `spaincentral`), regardless of which model you use."
> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

> "Tool availability requires support from both the model and the region. Check the region availability table for your region and the model support table for your model. If either shows `No`, the tool can't run, even if the other shows `Yes`."
> — Source: [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)

| Region | Code Interpreter | A2A |
|---|---|---|
| `eastus` | ✅ yes | ✅ yes |
| `eastus2` | ✅ yes | ✅ yes |
| `northcentralus` | ✅ yes | ✅ yes |
| **`southcentralus`** | **❌ no** | ✅ yes |
| `westus` | ✅ yes | ✅ yes |
| `westus3` | ✅ yes | ✅ yes |

Since the Foundry Customer Service Agent needs Code Interpreter, and `gpt-5.5` Global Standard is only available in `eastus2` and `southcentralus` for the Americas, **the project must be created in East US 2**.

---

## 7. Quota & Access Requirements

### Access Gating Per Model

| Model ID | Access Requirement |
|---|---|
| `gpt-5.5` | **No access request needed.** Quota request required depending on quota tier. Tier 5 and Tier 6 subscriptions have quota by default. |
| `gpt-5.4` | **Limited access model application required.** If you already have access to a limited access model, no separate request is needed. |
| `gpt-5.4-mini` | **No access request needed.** |
| `gpt-5.4-nano` | **No access request needed.** |
| `gpt-5.4-pro` | **Limited access model application required.** |

> — Source: [Azure OpenAI reasoning models — GPT-5 series](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning)

### Default Quota Per Tier (Global Standard)

| Model ID | Deployment Type | Tier 1 RPM / TPM | Tier 2 RPM / TPM | Tier 3 RPM / TPM | Tier 4 RPM / TPM | Tier 5 RPM / TPM | Tier 6 RPM / TPM |
|---|---|---|---|---|---|---|---|
| `gpt-5.5` | GlobalStandard | **0 / 0** | **0 / 0** | **0 / 0** | **0 / 0** | 10,000 / 10M | 15,000 / 15M |
| `gpt-5.4` | GlobalStandard | 10,000 / 1M | 20,000 / 2M | 40,000 / 4M | 80,000 / 8M | 100,000 / 10M | 150,000 / 15M |
| `gpt-5.4-mini` | GlobalStandard | 1,000 / 1M | 2,000 / 2M | 4,000 / 4M | 8,000 / 8M | 10,000 / 10M | 15,000 / 15M |
| `gpt-5.4-nano` | GlobalStandard | 5,000 / 5M | 16,000 / 16M | 46,000 / 46M | 135,000 / 135M | 150,000 / 150M | 225,000 / 225M |

> — Source: [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits)

### ⚠️ GPT-5.5 Quota Warning

> "Some quota tiers will require quota requests for gpt-5.5 to be able to deploy this model. Tier 5 and Tier 6 subscriptions have quota by default."
> — Source: [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)

**If the subscription is below Tier 5, the user MUST submit a quota increase request for `gpt-5.5` before creating a deployment.** At Tiers 1–4, the default quota for `gpt-5.5` is **0 RPM / 0 TPM** — deployment will fail without a quota request.

### ⚠️ GPT-5.4 Limited Access Warning

`gpt-5.4` (the full model, not mini) requires a **limited access model application**. The user's subscription may already have access if they've previously been granted access to any limited-access model. If not, they must apply via the [Limited access model application](https://aka.ms/oai/access) before deploying.

### Foundry Agent Service Limits

| Limit | Value |
|---|---|
| Maximum tools per agent | 128 |
| Maximum files per agent/thread | 10,000 |
| Maximum file size | 512 MB |
| Maximum messages per thread | 100,000 |
| Maximum text per message | 1,500,000 characters |

> "Agent Service doesn't impose separate rate limits on API calls. Rate limiting is applied at the model deployment level."
> — Source: [Quotas and limits for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions)

---

## 8. Recommendation

### Recommended Model Pairing

| Role | Model | Deployment SKU | Justification |
|---|---|---|---|
| **Foundry Customer Service Agent (orchestrator)** | `gpt-5.5` | Global Standard | Best reasoning capability; newest model; supports A2A + Code Interpreter (Agent Service tools); no access request needed (just quota). |
| **LangGraph Ops Agent (worker)** | `gpt-5.4-mini` | Global Standard | Cost-efficient; no access request; generous default quota at all tiers; 400K context is more than sufficient for the ops agent; base-model function calling fully supported via API. |

### Why This Pairing

1. **Capability vs. cost trade-off.** The orchestrator agent benefits from `gpt-5.5`'s superior reasoning (1,050K context, training data up to Dec 2025) for understanding complex customer queries and coordinating multi-step feasibility analysis. The worker agent performs structured data lookups (inventory, production schedules) where `gpt-5.4-mini`'s 400K context is ample and its lower cost per token is advantageous.

2. **Access friction.** `gpt-5.4` (full) requires a limited access application — adding deployment friction. Both `gpt-5.5` (no access gate, just quota) and `gpt-5.4-mini` (fully open) minimize enrollment barriers.

3. **Quota pragmatics.** If the subscription is Tier 5+, `gpt-5.5` has 10,000 RPM / 10M TPM default quota — more than sufficient for a demo. If below Tier 5, a quota request must be submitted first. `gpt-5.4-mini` has 1,000 RPM / 1M TPM even at Tier 1 — adequate for the worker agent.

4. **Both models are compatible with the demo's requirements:**
   - ✅ A2A (preview) on Foundry Agent Service (Table A — Agent Service tool)
   - ✅ Code Interpreter (Table A — Agent Service tool)
   - ✅ Base-model function calling / tools (Table B — model API capability, used by LangGraph agent)
   - ✅ Structured outputs (Table B — model API capability)
   - ✅ Responses API and Chat Completions API (Table B — model API capability)
   - ❌ Foundry Agent Service "Functions" tool (Table A — shows No, but **not needed**: the LangGraph agent calls the model API directly for function calling, and the Foundry agent uses Code Interpreter and A2A as its Agent Service tools)

### Recommended Region

**East US 2 (`eastus2`)** — the only US region where:
- `gpt-5.5` Global Standard is available ✅
- `gpt-5.4-mini` Global Standard is available ✅
- Code Interpreter is supported ✅
- A2A is supported ✅

### Fallback Option

If `gpt-5.5` quota cannot be obtained (subscription below Tier 5 and quota request is delayed), use **`gpt-5.4-mini`** for both agents but with **different deployment names** to satisfy the two-deployment requirement. Using the same underlying model (`gpt-5.4-mini`) with two separate deployment names (e.g., `zava-cs-agent` and `zava-ops-agent`) satisfies the project requirement for "different model deployments" — the project context requires two separate deployments, not necessarily two different model IDs. This eliminates quota risk entirely but sacrifices the reasoning advantage of `gpt-5.5` for the orchestrator.

Alternatively, **`gpt-5.4`** could replace `gpt-5.5` as orchestrator — it has similar capabilities and generous default quota — but requires a **limited access application** which adds its own approval delay.

---

## 9. Research Limitations

- **Pricing per token** was not found on the models/quotas documentation pages. Azure OpenAI pricing is typically on the [Azure pricing page](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/), which was not fetched (it's not a Learn docs page). Cost comparison between `gpt-5.5` and `gpt-5.4-mini` is based on general model-tier expectations (larger models cost more per token).
- **GA vs Preview status for models:** The models catalog page does not explicitly tag `gpt-5.5`, `gpt-5.4`, or `gpt-5.4-mini` as "GA" or "Preview" — they lack a Preview label, which is interpreted as not being in Preview, but this is an inference from the absence of a tag rather than an explicit "GA" declaration.
- **Subscription tier identification:** The research cannot determine the user's current subscription tier (Tier 1–6). This affects whether `gpt-5.5` quota is available by default.
- **A2A on non-Foundry agents:** The tool support matrix covers Foundry Agent Service only. The LangGraph agent on AKS communicates via A2A at the protocol level, not via Foundry Agent Service's built-in A2A tool. A2A protocol compatibility on the AKS side depends on the A2A library used, not on the model — this is outside the scope of this model-availability research.
- **Agent Service Functions tool vs. base-model function calling:** The Tool best practices matrix shows Functions = No for all three candidate models. This report interprets "Functions" as the Agent Service built-in Functions tool (distinct from base-model API function calling). The model catalog page separately confirms base-model "Functions, tools, and parallel tool calling" for all three models. If the Agent Service Functions tool becomes needed for the Foundry agent, this would require re-evaluation.
- **`gpt-5.4-mini` deployment types:** The region availability table showed `gpt-5.4-mini` only under Global Standard and Global Provisioned Managed. It was not listed under Data Zone Standard, Standard/Regional, or other SKUs. This may indicate limited SKU options or simply that Global Standard is the primary deployment type for this model.
- **Tier 4 quota values for `gpt-5.4` and `gpt-5.4-mini`:** The Tier 4 values in the quota table are from the checked quotas page but were not individually re-verified against a second source. `gpt-5.5` Tier 4 = 0/0 is confirmed.

---

## 10. Complete Reference List

### Microsoft Learn Documentation

- [Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure) — Model catalog listing all Azure OpenAI models including GPT-5.5 and GPT-5.4 series with capabilities, context windows, training data dates, and base model API capabilities.
- [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability) — Per-model region availability tables for all deployment types (Global Standard, Data Zone Standard, Provisioned, etc.).
- [Azure OpenAI reasoning models — GPT-5 series](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning) — GPT-5 series model details, access requirements (open vs. limited access), and region availability summary.
- [Azure OpenAI quotas and limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits) — Default RPM/TPM quotas per model, deployment type, and subscription tier (Tiers 1–6).
- [What is Microsoft Foundry Agent Service?](https://learn.microsoft.com/en-us/azure/foundry/agents/overview) — Overview of Foundry Agent Service, supported protocols (Responses, Invocations, Activity, A2A preview).
- [Tool best practices for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice) — Tool-by-region and tool-by-model support matrices showing Agent Service tool availability (A2A, Code Interpreter, File Search, Functions, etc.) per model and per region.
- [Quotas and limits for Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions) — Agent Service-specific limits (files, messages, tools per agent) and supported model list for Foundry Agents.
- [Hosted agents in Foundry Agent Service (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) — Hosted agent architecture, A2A endpoint format, agent identity, and protocol configuration.
- [Feature availability across cloud regions](https://learn.microsoft.com/en-us/azure/foundry/reference/region-support) — Foundry feature availability by region, including Agent Service region support guidance (used to cross-check region tool availability claims).

### GitHub Repositories

None consulted for this model-availability research.

### Code Samples

None consulted for this model-availability research.
