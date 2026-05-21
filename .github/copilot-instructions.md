# Project: Zava Smart Order Feasibility — A2A Multi-Agent Demo

This file is the canonical project context. All Copilot and subagents must read and follow this.

## What this project is

An **external customer demo** for a **technical stakeholder** showing **two AI agents communicating via the A2A (Agent-to-Agent) protocol**:

- **Agent A — Customer Service Agent** — runs on **Microsoft Foundry V2** (new Foundry, project-based, NOT Foundry Classic / Hubs). User-facing.
- **Agent B — Manufacturing Ops Agent** — runs on **AKS** as a **LangGraph** application. Internal-facing, queries fake operations data.

The two agents communicate via **A2A**. The React UI shows each A2A hop and each agent action in real time.

**Fictional company:** Zava — a precision-components manufacturer (industrial pumps & motors).
**Use case:** "Smart Order Feasibility" — user asks if Zava can fulfill an order by a target date; the agents collaborate to compute feasibility (inventory, lead time, production capacity) and respond with a chart/summary.

## Audience and quality bar

- **Audience:** External customer — technical decision-maker / architect.
- **Bar:** Production-quality clarity. Code must be readable; architecture must be defensible; documentation must be explicit.
- **Timeline:** No rush. Prioritize correctness and review depth over speed.

## Execution mode

- **Autopilot through Phase 7** is approved. The orchestrator should proceed end-to-end without pausing at scheduled checkpoints **unless** there is a genuine blocker it cannot resolve (e.g., A2A not supported on Foundry Agents V2; no acceptable model available in any US region; hard deployment failure after retries; quota that cannot be raised). All doer-reviewer round limits (5) still apply.

## Documentation is a first-class deliverable

The demo must ship with clear, easy-to-understand Markdown documentation. At minimum:

1. **`README.md`** with three sections:
   - **Use Case** — the Zava Smart Order Feasibility story and business value.
   - **Technology / How it's implemented** — architecture, components, **how A2A is implemented in this project** (wire-level details, message flow, libraries).
   - **How to Run the Demo** — step-by-step setup and execution instructions.
2. **`docs/a2a-implementation.md`** — deep dive on A2A wiring (protocol, message schema, transport, auth, error handling) specific to this project.
3. **`docs/private-vnet-considerations.md`** — covers:
   - Is **A2A with Foundry Agents + private VNets** supported today? (Cite official sources.)
   - If yes: how to architect it (Bicep snippets, network diagrams, private endpoints, DNS).
   - If no or partial: what is and isn't supported, and what workarounds exist.

Other docs may be added as the plan dictates.

## Technology choices

### Required / locked in by the user
- **Cloud:** Azure
- **IaC:** Bicep (not ARM JSON, not Terraform)
- **AI platform:** **Microsoft Foundry V2 (project-based, new experience)** — NOT Foundry Classic, NOT Hubs, NOT Foundry V1 Assistants API. Use Responses API and Foundry Agents (V2).
- **Foundry agent:** uses the new Foundry Agents (V2). Must support A2A.
- **Second agent:** **LangGraph** application running on **AKS**.
- **Inter-agent communication:** **A2A protocol** (open Agent-to-Agent protocol).
- **Frontend:** **React** (runs locally for the demo).
- **Backend:** light backend (runs locally) that mediates between the React UI and the agents.
- **Models:** Any of **GPT-5.5**, **GPT-5.4**, **GPT-5.5-mini**, **GPT-5.4-mini** is acceptable, **provided each model supports A2A on Foundry Agents V2** (research must verify per-model). Preference: **GPT-5.5** or **GPT-5.4-mini** if all support A2A. **Global deployment** is acceptable. Each agent uses a **different model deployment** (two separate deployments).
- **Networking for the demo:** **simple — public endpoints** (with sensible auth). Private VNet architecture is documented but NOT implemented in this build.
- **Company:** Zava (manufacturing — precision components).
- **Repo visibility:** **Public** GitHub repo under `miguelmsft`.

### Default suggestions (subagents may propose alternatives in research/planning if justified)
- **Foundry agent SDK:** prefer the official Foundry Agents SDK / Responses API. Microsoft Agent Framework is the default agent framework, but for this demo the Foundry-side agent uses Foundry Agents directly so we can exercise its A2A capability cleanly.
- **AKS agent runtime:** Python + LangGraph + an A2A-compatible server library.
- **Front-end UX:** show every A2A hop (sender, receiver, message), every tool/action call, and final response with whatever artifact the Foundry agent's code interpreter produced.
- **Each agent has ≥1 explicit action:**
  - Foundry agent: **Code Interpreter** (e.g., render a chart or compute a summary).
  - LangGraph agent: **read fake operations data** (inventory CSV, production schedule, quality metrics) and compute feasibility.

## Region & availability rules

- **Prefer US regions:** East US, East US 2, West US, West US 2, West US 3.
- Research must verify which of **GPT-5.5**, **GPT-5.4**, **GPT-5.5-mini**, **GPT-5.4-mini** are available as **global deployments** in Foundry V2 and **which of them support A2A on Foundry Agents V2**. Final model choice is locked in during planning based on research findings — prefer GPT-5.5 or GPT-5.4-mini.
- All other services (Foundry, AKS, networking) must be available in the same region.

## RBAC requirements

- The user (`miguelmsft`) must have a role that allows **full use of the Foundry resource** — research must confirm the correct built-in role (the user mentioned **Azure AI Account Owner** / "Azure AI Owner" — verify exact name) and any additional RBAC for Foundry projects, Foundry Agents, and AKS.

## What this demo is NOT
- NOT a private-VNet implementation (documented only).
- NOT a Foundry Classic / Hubs project.
- NOT Microsoft Agent Framework on both sides (LangGraph on the AKS side is intentional).
- NOT Semantic Kernel or AutoGen.
- NOT a generic chatbot — the A2A interaction must be visible and central.

## Repository hygiene
- Documentation in `docs/`. Top-level `README.md` is the primary entry point.
- Bicep in `infra/`.
- Source in clearly-named app folders (e.g., `apps/web/`, `apps/api/`, `apps/foundry-agent/`, `apps/ops-agent/`).
- Fake Zava data in `data/` (CSV or similar, fake/manufactured, no real PII).
- All secrets via environment variables. Never commit secrets.
