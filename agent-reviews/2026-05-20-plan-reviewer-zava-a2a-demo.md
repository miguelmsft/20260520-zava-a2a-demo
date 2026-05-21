---
reviewer: plan-reviewer
subject: Zava Smart Order Feasibility — A2A Multi-Agent Demo (plan.md)
companion: plan-creator
date: 2026-05-20
verdict: NEEDS REWORK
---

## Review Round 1 — 2026-05-20

This is a substantial, generally high-quality plan. The research foundation is well-cited, the A2A wire format is correct, the dependency graph is meaningful, and the risk register is honest. The blockers below are concentrated in a handful of areas: a duplicated/garbled tail of the document, an under-specified `useGpt55` fallback, an unauthenticated public A2A endpoint, and a Step 11 / Step 16 handoff that quietly contains a portal-only step the implementer will hit at runtime.

---

## Plan Contract Compliance

All required sections are present and well-developed:

- System Overview (§A.1), Architecture (§A.2), Tech Stack (§A.3), Data Model (§A.4), Interaction Contract (§A.5), Foundry Agent Design (§A.6), Observability (§A.7), Security (§A.8) — ✅ present.
- Repo Structure (Part B), Implementation Steps (Part C, 26 steps), Dependency Graph (Part D), Verification & Acceptance (Part E), Risks (Part F), Open Questions, Package Deps, Design Decisions, Assumptions — ✅ present.
- Every step has Files / Depends-on / Tasks / Verification — ✅.
- Final step (Step 26) is an end-to-end smoke test — ✅.
- Rollback for destructive ops: `az group delete` is the demo-grade rollback and is called out — ✅ acceptable for scope.
- Security-relevant steps cover auth (WI), secrets (env vars), and RBAC (Foundry User / Foundry Account Owner / AcrPull) — ✅ at the design level (gaps noted below).

**Structural defect — `🟡 Important` (must-fix):** The plan has a **duplicated and partially garbled tail** starting around line 1356. After "Plan Round 1 — Self-Assessment" (line 1344) the document re-emits a raw Mermaid graph (lines 1360–1446) without an enclosing heading or code-fence opener, then a **second** "Part E — Verification Criteria" (line 1457) with Phase 4/5/6/8 tables that overlap §E (line 1274), then a **second** "Part F — Open Questions / Risks" (line 1508) containing a shorter, divergent risk list (7 items vs. 15 in §F at line 1306). Implementers and step-implementer subagents reading top-to-bottom will hit inconsistent guidance (e.g., R3 fallback SKU is `Standard_D2as_v5` in §F line 1310 but `Standard_D2s_v3` in the second §F line 1526). Clean up: remove the orphan mermaid block, merge the two §E sections, and reconcile the two risk registers into one. Cite: lines ~1356–1530.

---

## 1. Tech Stack Evaluation

No material issues. Versions match research (Foundry API `2026-03-01`, AKS API `2026-02-01`, K8s 1.34/1.35, LangGraph 1.2.0, langchain-openai 1.2.1, a2a-sdk 1.0.3, azure-ai-projects 2.1.0). Region choice (East US 2) is the only US region with `gpt-5.5` Global Standard per `model-availability.md` §4 — correct and necessary.

- `🟢 Minor` (nice-to-have): No backend pin for `openai` Python client even though §12 calls `openai.responses.create(stream=True)`. Add `openai>=1.x` to the backend dependency table to make the SSE path reproducible.
- `🟢 Minor` (nice-to-have): Frontend dep table omits Vite plugins (`@vitejs/plugin-react`), Tailwind (mentioned in §A.13/§13 styling), `eventsource`/polyfill. These are fixable at implementation time but the table will look incomplete to a reviewer.

## 2. Data / Interface / Contract Design

The A2A request/response in §A.5 lines 198–268 is correct A2A 0.3 wire shape (parts have `kind` discriminators, `data` part for structured payload, `state: "completed"` kebab-case). Matches `a2a-protocol.md` §3.8 — ✅. The synthetic data schemas (§A.4) are internally consistent and verifiable.

- `🟡 Important` (must-fix): The artifact in §A.5 lines 238–266 lacks `artifactId` and `parts[].kind` is shown only for `data`. Per A2A 0.3, artifacts have an `artifactId` (or `id`) and a `name`; if the implementer copies the sample verbatim into tests, the JSON-RPC envelope will pass but the artifact deserialization in `a2a-sdk` may emit a warning or fail strict validation. Add `artifactId` and confirm the field names match `a2a_sdk.types.Artifact` in 1.0.3 (research/2026-05-20-langgraph-langchain.md §3 references this type).
- `🟢 Minor` (nice-to-have): The `AgentEvent` envelope in Step 12 enumerates types (`status`, `text_delta`, `tool_call`, `a2a_hop`, `chart`, `done`) but doesn't define the `data` shape per type. The frontend in Step 13 will need to invent the shape; specify it once in §A.5 or in Step 12 to prevent drift.

## 3. Architecture Concerns

- `🟡 Important` (must-fix): **The LangGraph A2A endpoint is public and unauthenticated as specified.** §A.8 line 351 says "A2A auth: Foundry A2A connection uses key-based auth (x-api-key) or Entra ID bearer token", but **Step 9** (`server.py`) describes no auth middleware: `DefaultRequestHandler` + Starlette routes are wired without an `x-api-key` check. For a **public** Internet-exposed endpoint advertising an Agent Card on a public DNS name, this is unacceptable even for a demo — anyone on the Internet can submit `message/send` and burn Azure OpenAI quota. Add to Step 9 tasks: a Starlette middleware that validates `x-api-key` against a deployment secret (env var, K8s Secret), and add a corresponding verification curl in §9 that expects 401 without the header and 200 with it. Then have Step 11's `create_a2a_connection.py` document the matching key configured on the Foundry connection side. Without this, R10 ("network egress blocked") inverts into the more likely "open relay" problem.
- `🟢 Minor` (nice-to-have): Single AKS replica (Step 10 tasks: `1 replica`) is a single point of failure for the demo. For a 30-minute customer demo this is fine, but bump to 2 if the cluster has the headroom — pod restart during a live A2A call (R10 / Phase 8 "Recovery from error") is the failure mode in §E.3 Phase 8.

## 4. Security & Access Control

- (covered above, §3) `🟡 Important` (must-fix): Auth middleware on the A2A server.
- `🟢 Minor` (nice-to-have): The backend (Step 12) sets CORS to `http://localhost:5173` only — good — but doesn't set `Access-Control-Allow-Credentials` policy or document the SSE Cache-Control header (R11 mentions `Cache-Control: no-buffer`, which is non-standard; the correct value is `Cache-Control: no-cache` plus `X-Accel-Buffering: no` for nginx-style proxies). Tighten this in Step 12 task list to prevent the buffering issue called out in R11.
- `🟢 Minor` (nice-to-have): Workload Identity federated credential in Step 7 (lines 612–619) is specified correctly (`subject: system:serviceaccount:default:ops-agent-sa`, `audience: api://AzureADTokenExchange`). Verification step is "module creates federated credential with correct issuer (AKS OIDC URL), subject, and audience" — this is a string check but doesn't test the actual token exchange. R8 covers detection at pod runtime. Acceptable.

## 5. Implementation Gaps

- `🟡 Important` (must-fix): **`useGpt55=false` fallback path is under-specified.** Step 4 tasks (lines 539–544) say "Deployment 1: `gpt-55-orchestrator`, model `gpt-5.5`" and "Deployment 2: `gpt-54mini-worker`, model `gpt-5.4-mini`", then "When false, orchestrator deployment uses `gpt-5.4-mini` instead". Open questions to resolve in the plan:
  1. In the fallback branch, does the orchestrator deployment keep the *name* `gpt-55-orchestrator` (referencing a `gpt-5.4-mini` model) or rename to e.g. `gpt-54mini-orchestrator`? The Foundry agent setup (Step 11) hard-codes `model="gpt-55-orchestrator"`, so the deployment name must stay constant OR Step 11 must parameterize it. Pick one and document.
  2. R1 mitigation (line 1308) claims "different deployment names still satisfies 'different deployment per agent' requirement" — confirm Step 4 actually emits **two** deployments of `gpt-5.4-mini` (one per agent) in the fallback, not one shared deployment. Today Step 4 reads as if the worker keeps its `gpt-54mini-worker` deployment and the orchestrator is *also* `gpt-5.4-mini` — this works but only if the Bicep explicitly creates two deployments with different names. Spell that out as a bullet in §4.

- `🟡 Important` (must-fix): **Step 11 contains a portal-only step disguised as a script.** The research is clear (`foundry-agents.md` lines 481–493): outbound A2A connections are created in the Foundry portal; the SDK only `.get()`s them. Step 11's task "OR use SDK if `project.connections.create()` supports A2A connection type" sets the implementer up to discover this at the worst possible moment (mid-demo prep). Rewrite Step 11 to (a) make the portal step the canonical path, (b) have `create_a2a_connection.py` *print explicit click-through instructions* (Portal → Project → Connections → Add → A2A → endpoint URL + key), and (c) keep the SDK attempt as a `try/except` fallback that logs a clear message if the SDK creates fails. Then thread this into Step 16's script. Right now Step 16 (line 907) silently inherits the ambiguity.

- `🟡 Important` (must-fix): **App Insights → Foundry project link is a manual step buried in Step 16.** Step 16 (lines 910–911) says "Connect App Insights to Foundry project (print portal instructions or use SDK)" and "Enable tracing on the project". R13 acknowledges this. The verification in Step 16 (line 917) — "Traces visible in Foundry portal → Agents → Traces tab" — depends on this manual step completing AND on trace propagation (typically 2–5 minutes). Add to Step 16 verification: explicit wait/poll instruction ("wait up to 5 minutes for first trace to appear") and a fallback diagnostic (KQL query on the App Insights resource directly) so a missing portal click doesn't get misdiagnosed as a broken Foundry tracing pipeline.

- `🟢 Minor` (nice-to-have): No explicit step covers **provisioning a TLS certificate into Key Vault**. Step 7 creates the empty KV; Step 15 implementation notes (line 894–895) mention "TLS certificate must be provisioned in Key Vault" but no step *does it*. For an external customer demo, add a short Step 7.5 (or fold into Step 14 deploy script) that documents the manual cert import (`az keyvault certificate import`) with the expected secret name matching the Ingress annotation `kubernetes.azure.com/tls-cert-keyvault-uri` from Step 10.

- `🟢 Minor` (nice-to-have): No backend or frontend tests. Step 17 covers ops-agent unit tests, Step 18 covers A2A compliance. For a customer-quality bar, at minimum add a happy-path test for `agent_client.py` (mocked AIProjectClient) and a Vitest component test for `useChat.ts` SSE parsing. Acceptable to skip for a demo, but the §A.1 quality bar ("production-quality clarity") implies otherwise.

## 6. Assumptions & Open Questions

- Assumption table (lines 1597–1605) is honest and validation methods are listed.
- `🟡 Important` (must-fix): Open Questions Q1 ("What DNS zone/domain") and Q2 ("How to obtain CA-issued TLS cert") are **gating** for Step 15 but appear only in the second §F (line 1514) — the duplicate that's flagged for cleanup above. They should be promoted to the primary §F.1 ("Pre-Implementation Gating Risks") at line 1326 and into the Open Questions section *before* the implementer reads §F.1, so a doer-reviewer pair doesn't skip past them.

## 7. Testability & Verification

- Per-step verifications are concrete and runnable (curl, kubectl, pytest, bicep build). ✅
- Step 18 mocks `AzureChatOpenAI` for protocol compliance testing — correct separation of concerns.
- `🟢 Minor` (nice-to-have): Step 18 verification (line 961) "v0.3 compatibility: ensure no `A2A-Version` header → server processes as v0.3" should explicitly send a `message/send` with `A2A-Version: 1.0` header *and* one without, asserting the same task is returned in both cases. That covers the actual R2 risk surface. Otherwise the test is only verifying the default path.
- `🟢 Minor` (nice-to-have): Step 26 smoke test (line 1149) says "Verify Foundry traces: print instructions to check portal (automated trace check is not feasible)". It actually *is* feasible: an App Insights KQL query (`requests | where timestamp > ago(5m) | where customDimensions.gen_ai_agent_name == "zava-customer-service"`) via `az monitor app-insights query` is automatable. Add as an optional check.

## 8. Edge Cases & Failure Modes

- Risk register (§F lines 1306–1322) is comprehensive and well-rated.
- `🟢 Minor` (nice-to-have): No risk covers **`A2APreviewTool` returning the LangGraph result as an opaque string vs. structured data**. The Foundry agent's instructions (§A.6) assume it can read the structured artifact directly. If `A2APreviewTool` collapses A2A artifacts into the agent's tool output as a string, the orchestrator may need explicit JSON parsing in its instructions. Worth adding as R16 with mitigation "verify in Step 11 test_agent that artifact data reaches model context as JSON".
- `🟢 Minor` (nice-to-have): No risk covers **Code Interpreter timeout / token budget exhaustion** on `gpt-5.5`. Briefly covered by R9 (Code Interpreter rate limits) but not timeout specifically.

## 9. Things Done Well

- A2A 0.3 wire format is correct and rigorously cited (§A.5).
- Dependency graph (Part D) is acyclic, parallel waves are realistic, critical path identified.
- Risk register is honest — R1 (quota), R2 (A2A interop), R4 (TLS), R10 (egress), R13 (App Insights wiring) are exactly the demo-day fail modes.
- `useGpt55` Bicep parameter is a sensible mitigation lever (even if it needs the cleanup noted above).
- Pinning preview SDKs (`azure-ai-projects==2.1.0`, `a2a-sdk==1.0.3`) is the right call for Preview APIs.
- Federated credential subject + audience are specified correctly (Step 7 lines 614, 627).
- Documentation deliverables (6 docs + README) are explicit, sequenced after implementation so they describe what actually exists, and have verification criteria.
- The synthetic data cross-referential integrity check (Step 2 verification) is the kind of detail that catches real test-time bugs.

## Suggested Improvements (Prioritized)

1. **Clean up the duplicated tail (lines ~1356–1530).** Remove the orphan Mermaid block, merge the two §E sections, and reconcile the two §F risk registers into a single authoritative list. This is the highest-leverage fix because it removes contradictory guidance.
2. **Add A2A server authentication to Step 9.** Static `x-api-key` middleware + K8s Secret + verification curl. Mirror the key in Step 11's connection script. Otherwise the public endpoint is an open relay.
3. **Make the `useGpt55=false` Bicep branch explicit in Step 4.** Spell out: deployment names in both branches, what the orchestrator vs. worker actually resolve to, and confirm Step 11 reads the deployment name from an env var (not hard-coded `gpt-55-orchestrator`).
4. **Rewrite Step 11 to make the portal-created A2A connection the canonical path.** Add explicit portal click-through instructions, downgrade SDK creation to a documented fallback attempt.
5. **Tighten Step 16's App Insights linkage verification.** Wait/poll for first trace; fall back to App Insights KQL if portal Traces tab is empty.
6. **Add a TLS cert provisioning sub-step** (between Step 7 and Step 15) with the `az keyvault certificate import` command and the exact `secretName` / `tls-cert-keyvault-uri` linkage.
7. **Add `artifactId` to the A2A response sample in §A.5** so it round-trips through `a2a_sdk.types.Artifact` cleanly.
8. **Add R16 — `A2APreviewTool` artifact passthrough** to the risk register and verify in Step 11's smoke test that the structured data reaches the orchestrator as parseable JSON (not opaque string).
9. (nice-to-have) Add Vitest tests for `useChat.ts` SSE parsing and a mocked `agent_client.py` test in Step 12/13.

---

## Implementation Readiness: NEEDS REWORK

**Blocking findings (must-fix):**

1. `🟡 Important` Plan structure — duplicated `§E`, duplicated `§F` with divergent risk content, orphan Mermaid block at lines ~1356–1530.
2. `🟡 Important` A2A server in Step 9 is public and unauthenticated; add `x-api-key` middleware + secret + verification curl.
3. `🟡 Important` `useGpt55=false` fallback in Step 4 doesn't pin deployment names across both branches; Step 11 hard-codes `gpt-55-orchestrator` and will break in fallback.
4. `🟡 Important` Step 11 A2A connection step ambiguously offers SDK-or-portal; research confirms outbound A2A connections are portal-only — make portal the canonical path.
5. `🟡 Important` Step 16 App Insights → Foundry link is manual; verification must wait/poll and provide a KQL fallback diagnostic.
6. `🟡 Important` A2A artifact sample in §A.5 missing `artifactId`; tests/clients copying it verbatim may fail strict deserialization.
7. `🟡 Important` Open Questions Q1 (DNS) and Q2 (TLS cert) must be promoted into the primary §F.1 "Pre-Implementation Gating Risks" section so they're not lost when the duplicate §F is removed.

**No `🔴 Critical` findings** — all blockers are `🟡 Important`. Once these seven are addressed, the plan should reach `APPROVED` quickly. The 🟢 Minor items can be deferred.

**Recommended next step:** Re-run `plan-creator` with this review attached. Focus the round-2 edit on findings 1–7 above; the rest of the plan is solid and should not need substantive change.
