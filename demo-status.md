# Demo Creation Status

## Current Phase
Planning (Phase 2) — autopilot enabled through Phase 7. Research Phase 1 COMPLETE: all 8 topics ✅ Approved.

## User Preferences
- **Topic:** Zava Smart Order Feasibility — two AI agents communicating via A2A.
- **Audience:** External customer — technical stakeholder (architect / decision-maker).
- **Company:** Zava (fictional, manufacturing — precision components: industrial pumps & motors).
- **Use case:** User asks if Zava can fulfill an order by a target date; Foundry Customer Service Agent collaborates via A2A with a LangGraph Manufacturing Ops Agent (on AKS) to compute feasibility (inventory, lead time, production capacity) and returns a chart/summary.
- **Azure resources:** Microsoft Foundry V2 (project-based, new experience), AKS cluster, supporting resources (storage, networking, monitoring) as needed.
- **Model preference:** Any of **GPT-5.5**, **GPT-5.4**, **GPT-5.5-mini**, **GPT-5.4-mini** (research must verify per-model A2A support and global-deployment availability in Foundry V2). Preference: **GPT-5.5** or **GPT-5.4-mini** if all support A2A. **Global deployment** acceptable. Each agent on a **different deployment**.
- **Execution mode:** **Autopilot through Phase 7** — proceed end-to-end without pausing at scheduled checkpoints unless a genuine, unresolvable blocker arises. All doer-reviewer 5-round caps still apply.
- **Networking:** Simple public endpoints for the demo. Private VNet architecture is **documented only** (not implemented).
- **Frontend:** React (local).
- **Backend:** Light backend (local) bridging UI to agents.
- **IaC:** Bicep.
- **Repo:** Public GitHub repo under `miguelmsft`. Suggested name: `20260520-zava-a2a-demo`.
- **Constraints:** No rush — quality over speed. Documentation is a first-class deliverable. Both agents must have ≥1 explicit action. Front end must clearly visualize the A2A interaction.

## Research Topics
| # | Topic | Agent | Status | Rounds | Verdict | Report Path | Review Path | Blocker | Last Updated |
|---|---|---|---|---|---|---|---|---|---|
| 1 | A2A protocol — how it works, how it's implemented | web-researcher | ✅ Approved | 3 | APPROVED | research/2026-05-20-a2a-protocol.md | agent-reviews/2026-05-20-a2a-protocol-review.md | — | 2026-05-20 |
| 2 | A2A use cases & patterns | web-researcher | ✅ Approved | 2 | APPROVED | research/2026-05-20-a2a-use-cases.md | agent-reviews/2026-05-20-a2a-use-cases-review.md | — | 2026-05-20 |
| 3 | Microsoft Foundry V2 — components, Bicep deployment, RBAC (Azure AI Account Owner) | ms-docs-researcher | ✅ Approved | 2 | APPROVED | research/2026-05-20-foundry-v2.md | agent-reviews/2026-05-20-foundry-v2-review.md | — | 2026-05-20 |
| 4 | Microsoft Foundry Agents V2 — capabilities, A2A support, private VNet support, both together | ms-docs-researcher | ✅ Approved (orchestrator fix R3) | 3 | APPROVED (orchestrator surgical count fix) | research/2026-05-20-foundry-agents.md | agent-reviews/2026-05-20-foundry-agents-review.md | — | 2026-05-20 |
| 5 | Microsoft Foundry Control Plane — governance, monitoring, evaluation | ms-docs-researcher | ✅ Approved (orchestrator fix R3) | 3 | APPROVED (orchestrator surgical count fix + 2 ref adds) | research/2026-05-20-foundry-control-plane.md | agent-reviews/2026-05-20-foundry-control-plane-review.md | — | 2026-05-20 |
| 6 | AKS clusters — best practices for hosting an agent workload | ms-docs-researcher | ✅ Approved | 3 | APPROVED | research/2026-05-20-aks.md | agent-reviews/2026-05-20-aks-review.md | — | 2026-05-20 |
| 7 | LangGraph vs LangChain — which to use for an agent, A2A support | web-researcher | ✅ Approved | 3 | APPROVED | research/2026-05-20-langgraph-langchain.md | agent-reviews/2026-05-20-langgraph-langchain-review.md | — | 2026-05-20 |
| 8 | Model availability + A2A support — GPT-5.5, GPT-5.4, GPT-5.5-mini, GPT-5.4-mini in Foundry V2 | ms-docs-researcher | ✅ Approved | 2 | APPROVED | research/2026-05-20-model-availability.md | agent-reviews/2026-05-20-model-availability-review.md | — | 2026-05-20 |

## Planning
- Status: ✅ Approved (Round 2)
- Rounds: 2
- Verdict: APPROVED — all 7 R1 Important findings ✅ fixed; 0 Critical, 0 Important remaining
- Plan path: plan.md (1512 lines, 26 implementation steps + R16+R17 risks)
- Review path: agent-reviews/2026-05-20-plan-reviewer-zava-a2a-demo.md
- Blocker: —
- Last updated: 2026-05-20
- Reviewer quote: "The plan is ready to implement. Proceed to step-implementer / Phase 7 execution per the autopilot mandate."

## Implementation
- Status: In Progress (Phase 3 — autopilot)
- Plan owner: plan.md (authoritative step list, dependency graph, verification criteria)
- Total steps: 26
- Approach: Parallel waves per plan.md §D.2; each step uses step-implementer + step-reviewer loop (max 5 rounds)
- Last updated: 2026-05-20

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
| Post-Intake | ✅ Approved by user | 2026-05-20 |
| Post-Research | Auto-skipped (autopilot) — orchestrator self-clears unless blocker | — |
| Post-Plan | Auto-skipped (autopilot) — orchestrator self-clears unless blocker | — |
| Post-Implementation | Auto-skipped (autopilot) — orchestrator self-clears unless blocker | — |
| Pre-Deployment | Auto-skipped (autopilot, user pre-approved) — orchestrator will announce cost/resources before launching azd up | — |
| Post-Live-Testing | Auto-skipped (autopilot) — orchestrator self-clears unless blocker | — |
| E2E Review | Pending | — |
| Final Validation | Pending | — |
