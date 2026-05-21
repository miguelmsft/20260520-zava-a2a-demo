# Demo Creation Status

## Current Phase
Intake (awaiting Post-Intake checkpoint approval)

## User Preferences
- **Topic:** Zava Smart Order Feasibility — two AI agents communicating via A2A.
- **Audience:** External customer — technical stakeholder (architect / decision-maker).
- **Company:** Zava (fictional, manufacturing — precision components: industrial pumps & motors).
- **Use case:** User asks if Zava can fulfill an order by a target date; Foundry Customer Service Agent collaborates via A2A with a LangGraph Manufacturing Ops Agent (on AKS) to compute feasibility (inventory, lead time, production capacity) and returns a chart/summary.
- **Azure resources:** Microsoft Foundry V2 (project-based, new experience), AKS cluster, supporting resources (storage, networking, monitoring) as needed.
- **Model preference:** **GPT-5.4-mini** primary, **GPT-5.5-mini** fallback. **Global deployment** acceptable. Each agent on a **different deployment**.
- **Networking:** Simple public endpoints for the demo. Private VNet architecture is **documented only** (not implemented).
- **Frontend:** React (local).
- **Backend:** Light backend (local) bridging UI to agents.
- **IaC:** Bicep.
- **Repo:** Public GitHub repo under `miguelmsft`. Suggested name: `20260520-zava-a2a-demo`.
- **Constraints:** No rush — quality over speed. Documentation is a first-class deliverable. Both agents must have ≥1 explicit action. Front end must clearly visualize the A2A interaction.

## Research Topics
| # | Topic | Agent | Status | Rounds | Verdict | Report Path | Review Path | Blocker | Last Updated |
|---|---|---|---|---|---|---|---|---|---|
| 1 | A2A protocol — how it works, how it's implemented | web-researcher | Not Started | 0 | — | research/2026-05-20-a2a-protocol.md | agent-reviews/2026-05-20-a2a-protocol-review.md | — | 2026-05-20 |
| 2 | A2A use cases & patterns | web-researcher | Not Started | 0 | — | research/2026-05-20-a2a-use-cases.md | agent-reviews/2026-05-20-a2a-use-cases-review.md | — | 2026-05-20 |
| 3 | Microsoft Foundry V2 — components, Bicep deployment, RBAC (Azure AI Account Owner) | ms-docs-researcher | Not Started | 0 | — | research/2026-05-20-foundry-v2.md | agent-reviews/2026-05-20-foundry-v2-review.md | — | 2026-05-20 |
| 4 | Microsoft Foundry Agents V2 — capabilities, A2A support, private VNet support, both together | ms-docs-researcher | Not Started | 0 | — | research/2026-05-20-foundry-agents.md | agent-reviews/2026-05-20-foundry-agents-review.md | — | 2026-05-20 |
| 5 | Microsoft Foundry Control Plane — governance, monitoring, evaluation | ms-docs-researcher | Not Started | 0 | — | research/2026-05-20-foundry-control-plane.md | agent-reviews/2026-05-20-foundry-control-plane-review.md | — | 2026-05-20 |
| 6 | AKS clusters — best practices for hosting an agent workload | ms-docs-researcher | Not Started | 0 | — | research/2026-05-20-aks.md | agent-reviews/2026-05-20-aks-review.md | — | 2026-05-20 |
| 7 | LangGraph vs LangChain — which to use for an agent, A2A support | web-researcher | Not Started | 0 | — | research/2026-05-20-langgraph-langchain.md | agent-reviews/2026-05-20-langgraph-langchain-review.md | — | 2026-05-20 |
| 8 | GPT-5.4-mini & GPT-5.5-mini — region & global-deployment availability in Foundry V2 | ms-docs-researcher | Not Started | 0 | — | research/2026-05-20-model-availability.md | agent-reviews/2026-05-20-model-availability-review.md | — | 2026-05-20 |

## Planning
- Status: Not Started
- Rounds: 0
- Verdict: —
- Plan path: plan.md
- Review path: agent-reviews/2026-05-20-plan-review.md
- Blocker: —
- Last updated: 2026-05-20

## Implementation
[Tracked in plan.md once created.]

## Test Plan
- Status: Not Started
- Rounds: 0
- Verdict: —
- Plan path: agent-reviews/YYYY-MM-DD-test-plan.md
- Review path: agent-reviews/YYYY-MM-DD-test-plan-review.md
- Last updated: —

## Live Testing
| # | Test Mode | Status | Rounds | Verdict | Issues Found | Issues Fixed | Report Path | Review Path | Last Updated |
|---|---|---|---|---|---|---|---|---|---|

## User Checkpoints
| Gate | Status | Date |
|---|---|---|
| Post-Intake | Pending user approval | 2026-05-20 |
| Post-Research | Pending | — |
| Post-Plan | Pending | — |
| Post-Implementation | Pending | — |
| E2E Review | Pending | — |
| Pre-Deployment | Pending | — |
| Final Validation | Pending | — |
| Post-Live-Testing | Pending | — |
