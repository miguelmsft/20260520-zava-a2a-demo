# Demo Creation Status

## Current Phase
✅ **COMPLETE** — demo built, deployed, validated end-to-end, and documented. Repository is at https://github.com/miguelmsft/20260520-zava-a2a-demo (public).

The active engineering log is now [`plan.md`](./plan.md) (planning history) and [`docs/deployment-learnings.md`](./docs/deployment-learnings.md) (deployed-state operational notes). This file is retained as the project-creation summary only.

## What was shipped

- **Two AI agents collaborating over A2A:** a Foundry V2 Customer Service Agent (`zava-customer-service`) and a LangGraph Manufacturing Ops Agent on AKS, communicating via the open A2A protocol (v0.3-compat) over HTTPS with API-key auth.
- **One-command deploy:** `./scripts/deploy-all.ps1` provisions infra (Bicep), builds the image, deploys to AKS, creates the Foundry agent + A2A connection, and smoke-tests — no portal clicks.
- **React + FastAPI frontend:** visualises every A2A hop, every Foundry tool call, and the final Code-Interpreter chart, with a raw-JSON toggle for the A2A envelope.
- **Foundry traces:** App Insights linkage is automated; traces appear in the Foundry portal's `Agents → zava-customer-service → Traces` tab within ~5 min of any invocation.
- **Documentation:** every doc in [`docs/`](./docs/) is current as of 2026-05-22, including a new beginner-friendly [`docs/a2a-foundry-walkthrough.md`](./docs/a2a-foundry-walkthrough.md).

## User Preferences (carried through)
- **Topic:** Zava Smart Order Feasibility — two AI agents communicating via A2A.
- **Audience:** External customer — technical stakeholder (architect / decision-maker).
- **Company:** Zava (fictional, manufacturing — precision components: industrial pumps & motors).
- **Use case:** User asks if Zava can fulfill an order by a target date; Foundry Customer Service Agent collaborates via A2A with a LangGraph Manufacturing Ops Agent (on AKS) to compute feasibility (inventory, lead time, production capacity) and returns a chart/summary.
- **Azure resources:** Microsoft Foundry V2 (project-based, new experience), AKS cluster, supporting resources (storage, networking, monitoring) as needed.
- **Model preference:** Any of **GPT-5.5**, **GPT-5.4**, **GPT-5.5-mini**, **GPT-5.4-mini**. **Shipped with `gpt-5.5` (primary) + `gpt-5.4-mini` (fallback)**, automatically downgraded on Tier 1–4 subscriptions by `scripts/verify-quota.ps1`.
- **Networking:** Simple public endpoints for the demo. Private VNet architecture documented in [`docs/private-vnet-considerations.md`](./docs/private-vnet-considerations.md) (not implemented).
- **Frontend:** React (local).
- **Backend:** Light FastAPI backend (local) bridging UI to agents.
- **IaC:** Bicep ([`infra/`](./infra/)).
- **Repo:** Public GitHub repo under `miguelmsft` — [`miguelmsft/20260520-zava-a2a-demo`](https://github.com/miguelmsft/20260520-zava-a2a-demo).

## Research Topics (all approved)
| # | Topic | Agent | Status | Report Path | Review Path |
|---|---|---|---|---|---|
| 1 | A2A protocol — how it works, how it's implemented | web-researcher | ✅ Approved | research/2026-05-20-a2a-protocol.md | agent-reviews/2026-05-20-a2a-protocol-review.md |
| 2 | A2A use cases & patterns | web-researcher | ✅ Approved | research/2026-05-20-a2a-use-cases.md | agent-reviews/2026-05-20-a2a-use-cases-review.md |
| 3 | Microsoft Foundry V2 — components, Bicep deployment, RBAC | ms-docs-researcher | ✅ Approved | research/2026-05-20-foundry-v2.md | agent-reviews/2026-05-20-foundry-v2-review.md |
| 4 | Microsoft Foundry Agents V2 — capabilities, A2A support, private VNet | ms-docs-researcher | ✅ Approved | research/2026-05-20-foundry-agents.md | agent-reviews/2026-05-20-foundry-agents-review.md |
| 5 | Microsoft Foundry Control Plane — governance, monitoring, evaluation | ms-docs-researcher | ✅ Approved | research/2026-05-20-foundry-control-plane.md | agent-reviews/2026-05-20-foundry-control-plane-review.md |
| 6 | AKS clusters — best practices for hosting an agent workload | ms-docs-researcher | ✅ Approved | research/2026-05-20-aks.md | agent-reviews/2026-05-20-aks-review.md |
| 7 | LangGraph vs LangChain — which to use for an agent, A2A support | web-researcher | ✅ Approved | research/2026-05-20-langgraph-langchain.md | agent-reviews/2026-05-20-langgraph-langchain-review.md |
| 8 | Model availability + A2A support — GPT-5.5, GPT-5.4, GPT-5.5-mini, GPT-5.4-mini | ms-docs-researcher | ✅ Approved | research/2026-05-20-model-availability.md | agent-reviews/2026-05-20-model-availability-review.md |
| 9 | Foundry Agent Traces capability (added 2026-05-21) | ms-docs-researcher | ✅ Approved | research/2026-05-21-foundry-agent-traces.md | — |

## Planning
- **Status:** ✅ Approved
- **Plan path:** [`plan.md`](./plan.md)

## Implementation
- **Status:** ✅ Complete
- **Approach:** Parallel waves per plan.md §D.2; each step driven by step-implementer + step-reviewer loops.
- **Deploy automation:** [`scripts/deploy-all.ps1`](./scripts/deploy-all.ps1) — single-command end-to-end deploy.
- **Validation:** clean-room redeploy validated to a fresh RG (tag `last-known-good-pre-automation` for rollback).

## Testing
- **Status:** ✅ Complete
- **Test plan:** [`agent-reports/test-plan.md`](./agent-reports/test-plan.md)
- **Live test report:** [`agent-reports/live-test-report.md`](./agent-reports/live-test-report.md)
- **Live fixes:** [`agent-reports/live-fix-summary-r1.md`](./agent-reports/live-fix-summary-r1.md)
- **Playwright e2e:** [`apps/frontend/e2e/agent-conversation.spec.ts`](./apps/frontend/e2e/agent-conversation.spec.ts) — passes end-to-end against the live stack.

## User Checkpoints
| Gate | Status | Date |
|---|---|---|
| Post-Intake | ✅ Approved by user | 2026-05-20 |
| Post-Research | ✅ Auto-cleared (autopilot) | 2026-05-20 |
| Post-Plan | ✅ Auto-cleared (autopilot) | 2026-05-20 |
| Post-Implementation | ✅ Auto-cleared (autopilot) | 2026-05-20 |
| Pre-Deployment | ✅ Auto-cleared (autopilot) | 2026-05-21 |
| Post-Live-Testing | ✅ Auto-cleared (autopilot) | 2026-05-21 |
| E2E Review | ✅ Complete | 2026-05-22 |
| Final Validation | ✅ Complete (Playwright + Foundry traces verified) | 2026-05-22 |
