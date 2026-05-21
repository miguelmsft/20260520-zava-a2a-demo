---
reviewer: ms-docs-research-reviewer
subject: Microsoft Foundry Control Plane
companion: ms-docs-researcher
date: 2026-05-20
verdict: NEEDS REWORK
---

## Review Round 1 — 2026-05-20

## Reference Validation

13 of 13 Microsoft Learn URLs checked. All checked URLs are official Microsoft Learn pages and reachable:

1. `https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview` — reachable; supports the Control Plane definition, Operate panes, AI gateway prerequisite, cost/token/fleet-health claims, and portal-only availability.
2. `https://learn.microsoft.com/en-us/azure/foundry/observability/concepts/trace-agent-concept` — reachable; supports tracing status, OpenTelemetry semantic conventions, multi-agent span names, trace contents, cost note, and security best practices.
3. `https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup` — reachable; supports Application Insights connection flow, server-side vs client-side traces, 90-day portal trace visibility, conversation results, and Log Analytics Reader guidance.
4. `https://learn.microsoft.com/en-us/azure/foundry/concepts/observability` — reachable; supports evaluator overview, production monitoring, continuous evaluation, playground evaluations, and billing statements.
5. `https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent` — reachable; supports the agent evaluation SDK pattern, evaluator names in the sample, report URL, per-model token usage, and Foundry User prerequisite.
6. `https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators` — reachable; supports evaluator taxonomy and preview markings for Groundedness Pro, Response Completeness, Prohibited Actions, Sensitive Data Leakage, Task Adherence, Task Completion, Intent Resolution, and Custom evaluators.
7. `https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry` — reachable; supports renamed roles, role GUIDs, scopes, minimum role assignments, publish-agent role, and the warning not to use Cognitive Services roles or Azure AI Developer for Foundry work.
8. `https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture` — reachable; supports Foundry resource/project hierarchy, connected-resource boundaries, diagnostic logging, content safety/guardrails, and regional availability cautions.
9. `https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview` — reachable; supports default `Microsoft.DefaultV2`, agent guardrails preview, intervention points, risk applicability, severity levels, override/inheritance rules, and the statement that guardrails currently apply only to agents developed in Foundry Agent Service.
10. `https://learn.microsoft.com/en-us/azure/foundry/guardrails/how-to-create-guardrails` — reachable; supports guardrail creation/assignment/testing steps and "Annotate and block" trigger details.
11. `https://learn.microsoft.com/en-us/azure/foundry/responsible-use-of-ai-overview` — reachable; supports Risks + alerts / Defender for Cloud alert visibility.
12. `https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view` — reachable; supports Application Insights Agents (Preview), Foundry navigation to Azure Monitor, trace filters, token sorting, simple transaction view, and Grafana dashboard claims.
13. `https://learn.microsoft.com/en-us/azure/foundry/concepts/manage-costs` — reachable; supports Cost Management Reader / Foundry User requirements, no dedicated pricing-calculator entry, and cost-monitoring guidance.

No dead, fabricated, or unofficial references found.

## Claim Citation Coverage

The report has strong citation coverage in the main conceptual sections, but the highest-stakes demo guidance has citation/quote gaps.

- 🟡 Important (must-fix) — Location: Section 8, "Demo Wiring Guide — What to Configure for the Zava Demo." Issue: several demo-critical assertions are either uncited or only loosely cited elsewhere, including "These appear in Build → Models," "the agent appears in Build → Agents," "server-side traces are auto-captured for Foundry agents," "the Foundry agent's side of the A2A call will be traced automatically," "Playground evaluations are enabled by default," and "`Microsoft.DefaultV2` guardrail is active by default on all model deployments." Why it matters: the user's explicit requirement is that the demo must let a customer open the portal and see model deployments, agent, traces, and eval/safety insights; this section needs direct Microsoft Learn citations and preferably verbatim quotes for each operational claim.
- 🟡 Important (must-fix) — Location: Executive Summary and Section 8. Issue: the report says the minimal setup works "without additional infrastructure," but it also requires an Application Insights resource, and Control Plane overview lists an AI gateway as a prerequisite "for advanced governance features." Why it matters: the minimum demo checklist should distinguish "minimum to see Foundry project assets/traces/evals/safety controls" from "minimum to exercise advanced Control Plane governance/compliance features." Otherwise implementers might omit AI gateway and be surprised that governance features are limited.

## Quote Verification

20 of approximately 20 inline block quotes were spot-checked against fetched Microsoft Learn pages. Verified as present or materially verbatim:

- Control Plane definition and "centralized management" quote.
- "As your organization evolves..." quote.
- Foundry architecture hierarchy quote.
- Connected resources governance-boundary quote.
- Agent tracing "captures key details" quote.
- Tracing GA/preview status quote.
- Server-side trace auto-log quote.
- OpenTelemetry semantic conventions quote.
- Traces tab / 90-day search-filter-sort quote.
- Application Insights Agent details quote.
- Evaluators definition quote.
- Playground evaluations default/billing quote.
- Guardrails overview quote.
- Agent guardrail override quote.
- Risks + alerts quote.
- RBAC rename quote.
- Foundry User assignment quote.
- Log Analytics Reader quote.
- Cost visibility quote.
- Tracing/evaluation cost quotes.

No fabricated or paraphrased block quote found in the spot check.

## Source Officialness

All cited report sources are official Microsoft Learn pages. No third-party blogs, Stack Overflow, or unofficial community tutorials are cited. The report discusses OpenTelemetry and W3C Trace Context through Microsoft Learn citations, which is acceptable.

## Technical Accuracy

- 🟡 Important (must-fix) — Location: Executive Summary and Research Limitations. Issue: the report states "The Control Plane is currently in public preview" and "The entire Foundry Control Plane is marked as preview." The fetched Control Plane page says, "Items marked (preview) in this article are currently in public preview"; it does not clearly state that the entire Control Plane is public preview. Why it matters: the user explicitly asked for preview vs GA status to be accurate for each feature. This wording overstates the preview status and should be corrected to cite only the features/docs that are explicitly marked preview.
- 🟡 Important (must-fix) — Location: Sections 2.2 and 8(c). Issue: the report says "for Foundry Agents (V2) ... traces appear automatically for agent runs executed via the portal or API" and "the Foundry agent's side of the A2A call will be traced automatically." The tracing setup page specifically says Foundry automatically logs server-side traces for "Prompt agents, Host agents, and workflows," while client-side traces require instrumentation. Why it matters: the demo depends on portal-visible traces. The report should clarify exactly which Foundry agent type in this demo is covered by server-side auto-capture and which calls require SDK/OpenTelemetry instrumentation.
- 🟡 Important (must-fix) — Location: Section 8(d), "Safety/Guardrails." Issue: the report implies showing safety controls requires only the default guardrail, but the guardrails overview says the guardrail system currently applies only to agents developed in Foundry Agent Service, not other agents registered in the Control Plane. Why it matters: the demo includes a Foundry agent plus an external AKS LangGraph agent. The safety/control-plane wording should explicitly state that default Foundry guardrails cover the Foundry Agent Service agent/model deployment, while AKS-side safety visibility requires separate instrumentation/registration or is out of scope.

## Source Freshness & Currency

Most preview/GA statements are current relative to the fetched docs. Evaluator preview labels match the built-in evaluators reference. Guardrails correctly labels agent guardrails, tool call, tool response, Spotlighting, Groundedness, and PII as preview where applicable.

Must-fix freshness issue:

- 🟡 Important (must-fix) — Location: all Control Plane status references. Issue: the report should not blanket-label Control Plane as public preview unless the source explicitly does. Use feature-level status: Application Insights Agents blade is Preview, tracing is GA for prompt agents and preview for workflow/hosted/custom agents, agent guardrails are preview, selected evaluators are preview, and specific Control Plane page items marked "(preview)" are preview. Why it matters: external customer demos need precise maturity/status language.

## Topic Coverage Assessment

Coverage is broad and mostly aligned with the requested topic: tracing/observability, evaluations, guardrails/content safety, RBAC/governance, cost metering, and demo minimum checklist are all present.

Must-fix coverage gaps:

- 🟡 Important (must-fix) — Location: Section 8, demo checklist. Issue: the checklist omits the AI gateway prerequisite called out by the Control Plane overview for advanced governance features. Why it matters: the user specifically needs governance/compliance meaningful in the portal, not just traces. The checklist should either include AI gateway as required for advanced governance/compliance panes or explicitly mark it optional and explain which capabilities will not be visible without it.
- 🟡 Important (must-fix) — Location: Section 8(d). Issue: "Evaluation run" is marked optional, while the user asked the customer should ideally see eval insights. The report should define a concrete minimal eval artifact: a small JSONL dataset, a one-time eval run using Task Adherence + Coherence + one safety evaluator, and where the customer opens it in the Foundry portal. Why it matters: without running an eval, the portal may not show meaningful evaluation results during the demo.

## Code & CLI Validation

Python examples and Azure CLI commands were reviewed statically only.

- Python syntax appears structurally valid: imports are present, environment variables are explicit, `DefaultAzureCredential` is current, and the evaluation code matches the official evaluate-agent pattern.
- Code examples include post-block source attribution with provenance labels.
- Azure CLI role assignment examples are syntactically plausible and use role GUIDs as recommended during the RBAC rename rollout.

No material code/CLI syntax issue found.

## Reference List Integrity

- 🟡 Important (must-fix) — Location: report header and Complete Reference List. Issue: the header says "Sources consulted: 12 Microsoft Learn pages," but the Microsoft Learn reference list contains 13 pages. Why it matters: the reviewer instructions require the source count to match the reference list.
- 🟢 Minor (nice-to-have) — Location: Code Samples reference list. Issue: the header says 0 code samples, while the report includes SDK examples adapted from Learn pages and references the evaluation code pattern. This is acceptable if "code samples" means standalone sample repositories, but the report should clarify that embedded Learn code examples are counted under Microsoft Learn, not Code Samples.

## Report Structure & Completeness

All major expected template sections are present, and quotes are embedded inline rather than collected in a final quote dump.

- 🟢 Minor (nice-to-have) — Location: numbering and Table of Contents. Issue: there are two "## 8" sections: "Demo Wiring Guide" and "Research Limitations." The Table of Contents omits the Demo Wiring Guide and points "8" to Research Limitations. Why it matters: the demo section is one of the most important deliverables and should be directly discoverable.
- 🟢 Minor (nice-to-have) — Location: Section 3 "Getting Started." Issue: prerequisites list "Foundry User at minimum for building/viewing," but the RBAC source distinguishes project/resource scopes and notes Foundry User + Reader patterns for developers. Consider making scopes explicit in every prerequisite bullet.

## Consistency & Contradictions

- 🟡 Important (must-fix) — Location: Executive Summary, Section 8, and Research Limitations. Issue: the report simultaneously says the minimal demo works with no additional infrastructure, requires Application Insights, and notes an unresolved AI gateway prerequisite for advanced governance. Why it matters: this creates ambiguity for implementation planning.
- 🟡 Important (must-fix) — Location: Section 2.2 vs Section 8(c). Issue: Section 2.2 correctly distinguishes server-side and client-side traces, but Section 8(c) states more broadly that the Foundry side of A2A will be traced automatically. Why it matters: the implementation may rely on A2A/API calls from a local backend, so the report must be explicit about whether server-side traces are enough or client-side OTel is required.

## Suggested Improvements (Prioritized)

1. Rewrite the demo checklist into two tiers: "minimum for portal-visible assets/traces/eval/safety" and "optional/required for advanced Control Plane governance." Include AI gateway status explicitly.
2. Add direct citations and verbatim quotes to every bullet in Section 8 that tells implementers where something appears in the portal.
3. Correct preview/GA language to feature-level precision instead of saying the entire Control Plane is preview.
4. Clarify tracing assumptions for the exact Foundry agent type used in the Zava demo and for A2A calls initiated from the local backend/API.
5. Add a concrete one-time evaluation artifact to the minimum demo: dataset shape, evaluator set, required judge-model deployment, and portal navigation to results.
6. Fix source-count mismatch and Table of Contents / section numbering.

## Readiness Verdict: NEEDS REWORK

The report is well-researched and uses official Microsoft sources, but it has unresolved must-fix issues around demo-critical citation coverage, overbroad preview status wording, tracing auto-capture assumptions, AI gateway/governance minimum configuration, and source-count integrity.

**Verdict:** NEEDS REWORK

## Review Round 2 — 2026-05-20

### Fix Verification

1. **Preview vs GA feature-level precision (HIGH)** — **RESOLVED** / ✅ fixed. Section 1 now avoids blanket-preview wording and provides a feature-level table for prompt-agent tracing GA, workflow/hosted/custom tracing preview, Application Insights Agents blade preview, agent guardrails preview, and preview evaluators, all tied to Microsoft Learn citations.
2. **Two-tier demo checklist (HIGH)** — **RESOLVED** / ✅ fixed. Section 8 now separates Tier 1 portal-visible assets/traces/evaluation/safety from Tier 2 advanced governance with AI gateway.
3. **Tracing assumptions for Zava demo (HIGH)** — **RESOLVED** / ✅ fixed. Sections 2.2, 2.3, 6.3, and 8(c) explicitly classify the Zava Foundry Customer Service Agent as a prompt agent and distinguish server-side auto-captured Foundry traces from local backend / AKS LangGraph traces that require OpenTelemetry instrumentation.
4. **AI gateway prerequisite (HIGH)** — **RESOLVED** / ✅ fixed. Sections 6.2 and 8 Tier 2 name the AI gateway prerequisite and assign it to advanced governance rather than Tier 1 tracing/evaluation/safety.
5. **Guardrails clarification (HIGH)** — **RESOLVED** / ✅ fixed. Sections 2.5 and 8(e) state that Foundry guardrails apply to Foundry Agent Service agents and do not cover the AKS LangGraph Manufacturing Ops Agent.
6. **Minimum eval artifact (HIGH)** — **RESOLVED** / ✅ fixed. Section 4.2 and Section 8(d) specify a 5-row JSONL dataset shape, Task Adherence + Coherence + Violence evaluators, judge model deployment requirements, and the Foundry portal Evaluations path/report URL.
7. **Consistency / contradictions (HIGH)** — **RESOLVED** / ✅ fixed. Section 8 now reconciles the dependencies: Tier 1 requires Application Insights, not zero infrastructure; AI gateway is Tier 2 for advanced governance.
8. **Source count mismatch (MEDIUM)** — **PARTIALLY RESOLVED** / ⚠️ partially fixed. The header now matches the listed 13 Microsoft Learn references, but the report body cites 15 unique Microsoft Learn URLs. Two cited pages are missing from the Complete Reference List and source count: `https://learn.microsoft.com/en-us/azure/foundry/agents/overview` and `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents`.
9. **Section numbering (LOW)** — **RESOLVED** / ✅ fixed. The Demo Wiring Guide is now Section 8 and Research Limitations is Section 9; the table of contents matches.
10. **Code samples categorization (LOW)** — **RESOLVED** / ✅ fixed. The header note and Code Samples reference section clarify that embedded Learn code examples are counted under Microsoft Learn, not standalone code samples.

## Reference Validation

9 of 15 unique Microsoft Learn URLs were checked in Round 2. All checked URLs are official Microsoft Learn pages and support the cited claims:

1. `https://learn.microsoft.com/en-us/azure/foundry/control-plane/overview` — confirms Control Plane definition, Operate panes, preview-item wording, AI gateway prerequisite, Assets/Quota/Admin pane claims, and portal-only availability.
2. `https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup` — confirms Application Insights prerequisite, tracing setup path, server-side traces for Prompt agents/Host agents/workflows, 90-day trace view, prompt-agent GA vs workflow/hosted/custom preview, and Log Analytics Reader guidance.
3. `https://learn.microsoft.com/en-us/azure/foundry/guardrails/guardrails-overview` — confirms agent guardrails preview, `Microsoft.DefaultV2` default model guardrail, inheritance behavior, preview intervention points, and Foundry Agent Service scope limitation.
4. `https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluate-agent` — confirms JSONL query shape, Task Adherence/Coherence/Violence evaluator pattern, judge model deployment requirement, SDK run pattern, report URL, Evaluations tab, token usage, and row-level results.
5. `https://learn.microsoft.com/en-us/azure/azure-monitor/app/agents-view` — confirms Application Insights Agents (Preview), access path, trace drill-down, token sorting, simple transaction view, and Grafana dashboard claims.
6. `https://learn.microsoft.com/en-us/azure/foundry/concepts/built-in-evaluators` — confirms evaluator categories and preview markings.
7. `https://learn.microsoft.com/en-us/azure/foundry/concepts/observability` — confirms evaluators definition, playground evaluations enabled by default, billing statement, production monitoring, and LangGraph tracing support statement.
8. `https://learn.microsoft.com/en-us/azure/foundry/agents/overview` — confirms Agent Service description, prompt/workflow/hosted agent types, hosted preview status, and A2A protocol preview support.
9. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents` — confirms hosted agents are preview and supports the cited hosted-agent row.

No dead, fabricated, or unofficial sources were found among the checked URLs.

## Claim Citation Coverage

No material citation-coverage issues for the Round 1 must-fix areas. The demo-critical Tier 1/Tier 2 checklist now has direct citations for portal locations, tracing behavior, evaluation output, guardrail scope, and AI gateway prerequisite.

Remaining issue:

- 🟡 Important (must-fix) — Location: Section 2.2 / Section 1 preview table vs Complete Reference List. Issue: the report cites the Agent Service overview and Hosted agents pages in the body but omits them from the Complete Reference List and header count. Why it matters: the report now relies on those pages for the Zava prompt-agent classification and hosted-agent preview status, so they must be counted and listed.

## Quote Verification

Key Round 2 quotes were spot-checked against fetched Microsoft Learn pages and are present or materially verbatim, including:

- Control Plane definition and AI gateway prerequisite.
- Prompt-agent tracing GA / workflow-hosted-custom preview status.
- Server-side trace auto-capture for Prompt agents, Host agents, and workflows.
- Application Insights Agents (Preview) access path and monitoring claims.
- Agent guardrails scope limitation and `Microsoft.DefaultV2` inheritance behavior.
- Evaluation JSONL / evaluator / report URL guidance.

No fabricated or materially altered quote was found in the spot check.

## Source Officialness

All cited sources are official Microsoft Learn pages. No third-party blogs, Stack Overflow, or unofficial community sources are cited.

## Technical Accuracy

No new technical accuracy blocker found in the Round 2 must-fix areas. The revised report correctly distinguishes:

- Prompt-agent tracing GA from workflow/hosted/custom tracing preview.
- Foundry server-side agent traces from client-side/local backend and AKS LangGraph OpenTelemetry traces.
- Foundry Agent Service guardrail scope from external AKS LangGraph safety responsibility.
- Tier 1 App Insights requirement from Tier 2 AI gateway advanced-governance prerequisite.

## Source Freshness & Currency

No material freshness issue found. Preview/GA status claims checked in Round 2 match current Microsoft Learn pages for tracing, Application Insights Agents view, hosted agents, agent guardrails, and selected evaluators.

## Topic Coverage Assessment

The prior demo-readiness coverage gaps are resolved. The report now gives implementers a concrete path to satisfy the project requirement that the customer can open Foundry and see meaningful traces, evaluations, and safety/governance information.

Remaining coverage caveat is properly documented in Research Limitations: the exact boundary of AI-gateway-gated features is inferred from Control Plane prerequisite language because Microsoft Learn does not provide a single gateway-required comparison table.

## Code & CLI Validation

Python examples were statically parsed from the report: 2 Python code blocks found, both parse successfully with Python `ast.parse`. Azure CLI snippets are syntactically plausible and use current `az role assignment` / `az group create` patterns. Code blocks include post-block source attribution and provenance labels.

## Reference List Integrity

- 🟡 Important (must-fix) — Location: header line 6 and Complete Reference List lines 1067–1081. Issue: the header and reference list say 13 Microsoft Learn pages, but the body contains 15 unique Microsoft Learn URLs. Missing from the Complete Reference List: `What is Microsoft Foundry Agent Service?` and `What are hosted agents?`. Why it matters: the reviewer rubric requires cited-vs-listed consistency and accurate source counts. This is small but must be corrected before approval.

## Report Structure & Completeness

The report structure is otherwise complete. Section numbering and table of contents are corrected. Research Limitations are explicit and useful.

## Consistency & Contradictions

No material internal contradiction remains in the Round 1 must-fix areas. The report consistently states that Tier 1 needs Application Insights, Tier 2 needs AI gateway, and external AKS LangGraph traces/safety need separate instrumentation or are out of scope.

## Suggested Improvements (Prioritized)

1. Add the two cited Agent Service pages to the Complete Reference List and update the header source count from 13 to 15 Microsoft Learn pages.
2. Optionally add a one-sentence note in Section 8(d) that the chosen judge model for the actual Zava build should be one of the locked East US 2 deployments (`gpt-5.5` or `gpt-5.4-mini`) if it supports the evaluator's chat-completion requirement.
3. Optionally add a short note that A2A protocol support itself is covered by the Agent Service overview / hosted agents references, while this report is focused on Control Plane observability/governance rather than A2A implementation.

## Readiness Verdict: NEEDS REWORK

The substantive Round 1 demo-readiness issues are resolved, but the report still fails reference-list integrity because it cites 15 unique Microsoft Learn pages while listing/counting only 13. Fixing the source count and adding the two missing Microsoft Learn references should be sufficient for approval.
