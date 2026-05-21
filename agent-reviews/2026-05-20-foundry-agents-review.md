---
reviewer: ms-docs-research-reviewer
subject: Microsoft Foundry Agents V2
companion: ms-docs-researcher
date: 2026-05-20
verdict: NEEDS REWORK
---

## Review Round 1 — 2026-05-20

## Reference Validation

Checked 12 of 29 listed URLs / major source URLs, prioritizing A2A, SDK, VNet, model availability, pricing, and migration claims.

1. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent` — reachable and directly supports outbound A2A as a Foundry Agent Service tool, public preview status, supported SDKs, connection setup, and the quoted A2A tool behavior.
2. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint` — reachable and directly supports incoming A2A, A2A protocol 0.3, prompt/hosted agent support, Entra-only auth, endpoint URLs, and limitations.
3. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link` — reachable and directly supports Foundry private endpoints, VNet injection, BYO resources, subnet requirements, and the A2A network-isolation matrix.
4. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate` — reachable and supports the Responses API vs Assistants API distinction, new-vs-classic tool availability, and the “any Foundry model” quote.
5. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog` — reachable and supports the tool catalog overview and A2A as a preview custom tool.
6. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components` — reachable and supports named/versioned agents, conversations, responses, and `azure-ai-projects>=2.0.0` examples.
7. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agent-to-agent-authentication` — reachable and supports the A2A auth method table and key-based / Entra / OAuth patterns.
8. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/faq` — reachable and supports pricing quotes, data storage, and VNet FAQ claims.
9. Reachable — `https://learn.microsoft.com/en-us/python/api/overview/azure/ai-projects-readme` — reachable; confirms `azure-ai-projects` 2.1.0 page and A2A support, but states the client library is “in preview,” contradicting the report’s GA claim.
10. Reachable — `https://learn.microsoft.com/en-us/python/api/overview/azure/ai-agents-readme` — reachable; confirms `azure-ai-agents` 1.1.0 page and recommends `azure-ai-projects` for enhanced experience.
11. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure` — reachable; confirms `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, but does not list `gpt-5.5-mini`.
12. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability` — reachable; confirms deployment-type/region matrices and shows `gpt-5.5` and `gpt-5.4-mini` availability is deployment-type and region-specific, not universally “global.”

No fabricated URLs found in the checked set. However, several critical claims are either over-broadened beyond what the checked sources say or contradicted by those sources.

## Claim Citation Coverage

- 🔴 Critical (must-fix) — Location: Executive Summary lines 14-16 and Section 8 lines 678-683. The report claims GPT-5.5, GPT-5.4, GPT-5.5-mini, and GPT-5.4-mini “should all work” / work “via global deployments,” but the report provides no per-model citation and official model docs checked do not list `gpt-5.5-mini` at all. The region-availability matrix confirms `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` have specific model/version/deployment-type constraints; it does not support the blanket statement. This directly affects demo feasibility.
- 🟡 Important (must-fix) — Location: Executive Summary line 16 and SDK discussion. The report states `azure-ai-projects` 2.1.0 and `azure-ai-agents` 1.1.0 are “GA.” The checked `azure-ai-projects` Learn page says “The AI Projects client library (in preview) is part of the Microsoft Foundry SDK.” This needs correction or a more precise source distinguishing package version from service/tool GA status.
- 🟡 Important (must-fix) — Location: Section 4 REST API example lines 306-325. The report cites runtime-components for `POST ${ENDPOINT}/agents?api-version=v1`; the checked A2A REST examples use agent-version endpoints such as `/agents/{{agent_name}}/versions?api-version=v1`. The report must cite an official source for this exact endpoint or replace it with a documented REST pattern.
- 🟢 Minor (nice-to-have) — Location: Key Features lines 64-69. “Workflows,” “Hosted agents,” “Agent Applications,” “Toolbox,” and “Foundry IQ” are listed without inline quotes in that section. They are in the reference list, but key feature claims would be stronger with inline citations.

## Quote Verification

Verified 18 high-impact quotes across the fetched pages.

- Verified — A2A outbound quotes at lines 347-352 match the outbound A2A Learn page materially/verbatim.
- Verified — A2A incoming quotes at lines 453-458, protocol 0.3 at lines 340-341, endpoint/auth claims at lines 537-559 match the incoming A2A Learn page materially/verbatim.
- Verified — VNet/network isolation quotes at lines 582-599 and A2A matrix quote at lines 643-644 match the network isolation page.
- Verified — Migration quotes at lines 43-49, 96-97, 141-142, and 673-674 match the migration/runtime pages materially/verbatim.
- Verified — Pricing quotes at lines 744-759 match the FAQ.
- Code provenance caution: code blocks marked “Provenance: verbatim” are not all obviously verbatim from fetched markdown because some tabbed code is not exposed in the simplified fetch output. Do not mark code as verbatim unless it exactly matches a fetched source; otherwise label as adapted.

No fabricated verbatim quote found among the checked high-impact quotes.

## Source Officialness

No material officialness blockers. The report uses Microsoft Learn, Azure SDK documentation hosted on Learn, and official Microsoft/Azure GitHub organizations. The A2A protocol link itself is external, but it is referenced by Microsoft Learn and not used as an authority for Azure feature availability.

## Technical Accuracy

- 🔴 Critical (must-fix) — Location: Section 8 and Executive Summary. Per-model treatment is not technically sufficient. Official model docs checked list `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, but not `gpt-5.5-mini`; Agent Service limits/regions docs say model and region availability can vary and should be verified. The report must not claim all four requested models work with Foundry Agent Service + A2A unless official docs explicitly support each one.
- 🟡 Important (must-fix) — Location: SDK package status. `azure-ai-projects` page confirms version 2.1.0 but describes the library as “in preview.” The report’s “GA” label is inaccurate as written.
- 🟡 Important (must-fix) — Location: REST examples. The generic agent creation REST endpoint in Section 4 appears inconsistent with the official versioned-agent REST examples checked. Replace with documented `/agents/{agent_name}/versions?api-version=v1` style or cite an exact source.
- Verified — A2A client/server capability itself is well-supported by official docs: outbound A2A tool and incoming A2A endpoint pages explicitly cover the two directions, preview status, auth, and protocol limitations.
- Verified — Private VNet and A2A+VNet support are technically supported by the checked network isolation matrix: A2A is listed as supported with traffic through the VNet subnet.

## Source Freshness & Currency

- 🟡 Important (must-fix) — Preview vs GA is not consistently accurate. A2A is correctly marked public preview, but the SDK status is misstated. The report should separate: Foundry Agent Service GA, A2A preview, Hosted agents preview, Toolbox preview, Foundry IQ preview, `azure-ai-projects` preview/2.1.0 package page, and individual model preview/GA status.
- 🟡 Important (must-fix) — Model currency is under-researched. The report omits the current official model availability matrix details for the requested models. It should explicitly state that `gpt-5.5-mini` is not found in the checked official model list, and list exact deployment types/regions for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.

## Topic Coverage Assessment

- Verified — Strong coverage: V1/classic distinction, Responses API migration, A2A outbound, incoming A2A, A2A authentication, private networking, A2A+VNet, pricing basics, and core limits are all covered.
- 🔴 Critical (must-fix) — The requested “per-model considerations for GPT-5.5 / GPT-5.4 / GPT-5.5-mini / GPT-5.4-mini” are not adequately answered. The report explicitly admits no per-model matrix, but still claims all four should work. For this project, that uncertainty must be surfaced loudly in the executive summary and demo-feasibility conclusion.
- 🟡 Important (must-fix) — Pricing/limits section is useful but does not include the fixed Agent Service limits from the checked limits page (max files, max tools, message size, etc.) and does not tie model quotas to the requested GPT-5.x models.

## Code & CLI Validation

- 🟡 Important (must-fix) — Section 4 REST command likely uses an undocumented/stale endpoint. Replace or cite exactly.
- 🟡 Important (must-fix) — Code provenance labels need cleanup. “verbatim” should only be used where exact fetched code is reproduced. The Web Search code appears close to the tool catalog, but incoming A2A SDK/PATCH snippets should be checked against the tab-specific Learn content and relabeled as adapted if not exact.
- Verified — Python syntax is broadly plausible in the visible examples: imports, client construction, `DefaultAzureCredential`, and `AIProjectClient` patterns match current docs. No obvious syntax-only errors found in the visible Python examples.
- 🟢 Minor (nice-to-have) — The setup example prints success but does not close clients with context managers, whereas SDK docs often show context-manager usage. This is acceptable for a research report but could be improved.

## Reference List Integrity

- 🟡 Important (must-fix) — Header counts and reference categories do not match the actual structure. The header says “20 Microsoft Learn pages, 3 GitHub repositories, 1 code sample, 1 MS Learn training module,” but the reference list also includes 2 Python SDK Learn pages and 2 Agent Framework Learn pages outside “Microsoft Learn Documentation.” There is no separate “Code Samples” category despite the claimed code sample count.
- 🟡 Important (must-fix) — A body-cited official sample template `microsoft-foundry/foundry-samples/.../19-hybrid-private-resources-agent-setup` from the network isolation page is not represented in the reference list.
- 🟢 Minor (nice-to-have) — The required categories from the reviewer template are Microsoft Learn Documentation, GitHub Repositories, and Code Samples. Current categories add “Python SDK Documentation” and “Microsoft Agent Framework,” which is understandable but should be reconciled with the header counts.

## Report Structure & Completeness

All major sections are present: overview, concepts, getting started, core usage, A2A, private VNet, A2A+VNet, models, best practices, pricing/limits, limitations, and references.

- 🟡 Important (must-fix) — The Executive Summary overstates confidence on the model and SDK status. The body’s “Research Gap” acknowledges uncertainty, but the executive summary says the requested models work. This contradiction must be resolved.
- 🟢 Minor (nice-to-have) — Research limitations are useful and honest, but the most demo-critical limitation (model-specific Agent Service/A2A validation) should be elevated to the top and mirrored in the Executive Summary.

## Consistency & Contradictions

- 🔴 Critical (must-fix) — The report contradicts itself on model certainty: Executive Summary says GPT-5.5/GPT-5.4/GPT-5.5-mini/GPT-5.4-mini work via global deployments; Section 8/11 says there is no per-model compatibility matrix and exact availability must be verified at deployment time. Given the project requirement that each acceptable model must support A2A on Foundry Agents V2, this contradiction blocks approval.
- 🟡 Important (must-fix) — SDK status is inconsistent with checked documentation: report says GA, SDK page says preview for `azure-ai-projects`.
- Verified — A2A + VNet consistency is good: the Executive Summary, Section 6, and Section 7 align with the official network isolation matrix.

## Suggested Improvements (Prioritized)

1. Fix the model section and executive summary. Add a table for `gpt-5.5`, `gpt-5.4`, `gpt-5.5-mini`, and `gpt-5.4-mini` with official citations for: exists in model catalog, deployment types/regions, Responses API support, Agent Service support, A2A/tool support inference, and uncertainty. State explicitly that `gpt-5.5-mini` was not found in the official checked model docs unless a newer official source proves otherwise.
2. Correct SDK package status. Keep package names and versions, but distinguish package version from GA/preview status. Cite the `azure-ai-projects` Learn page language that the library is “in preview.”
3. Replace or precisely cite the Section 4 REST create-agent example. Prefer current documented agent-version endpoints from official Learn examples.
4. Reconcile reference counts and categories. Include all body-cited sources in the reference list and add a true Code Samples section if claiming code samples.
5. Tighten provenance labels for code examples: verbatim only when exact; otherwise adapted or synthesized.
6. Add fixed Agent Service limits from the limits/quotas page and connect quotas to model deployment type/region choices for the Zava demo.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

The A2A and private VNet findings are strong and well-supported, but the report is not publishable because it overclaims the demo-critical per-model support, includes an apparently nonexistent/requested model variant (`gpt-5.5-mini`) without official support, and mislabels the `azure-ai-projects` SDK status as GA despite the checked Learn page describing it as preview. These are must-fix issues before this research can guide the demo architecture.



## Review Round 2 — 2026-05-20

### Fix Verification

| Round 1 must-fix | Status | Evidence |
|---|---|---|
| Per-model treatment | RESOLVED — ✅ fixed | Executive Summary and Section 8 now state `gpt-5.5-mini` does not exist, provide per-model rows for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, and recommend `gpt-5.5` + `gpt-5.4-mini` in East US 2. |
| `azure-ai-projects` GA vs Preview | RESOLVED — ✅ fixed | Executive Summary table separates Foundry Agent Service GA from A2A/Hosted Agents preview and labels `azure-ai-projects` v2.1.0 and `azure-ai-agents` v1.1.0 as preview SDK packages. |
| REST endpoint example | RESOLVED — ✅ fixed | Section 4 now uses `POST ${ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1`, matching the requested `/agents/{agent_name}/versions?api-version=v1` style. |
| A2A protocol version | RESOLVED — ✅ fixed | Executive Summary and Section 5 quote: “Foundry Agent Service supports A2A protocol version 0.3 only.” |
| Hosted agents A2A endpoint URL | RESOLVED — ✅ fixed | Section 2 and Section 5 include `{project_endpoint}/agents/{name}/endpoint/protocols/a2a` for hosted agents. |
| Code provenance labels | RESOLVED — ✅ fixed | Code blocks reviewed are now labeled `Provenance: adapted`, with source URLs after the code fences. |
| Agent Service limits | RESOLVED — ✅ fixed | Section 10 adds fixed Agent Service limits and cites the limits/quotas page. |
| Reference list integrity | PARTIALLY RESOLVED — ⚠️ partially fixed | The missing `microsoft-foundry/foundry-samples` sample is now listed, but the header still says “24 Microsoft Learn pages, 3 GitHub repositories, 1 MS Learn training module” while the reference list contains more than 24 Microsoft Learn documentation/SDK/Agent Framework pages plus a separate code sample section. Counts and categories still do not match. |
| Inline citations / context managers | RESOLVED — ✅ fixed | Key feature bullets now include inline citations; setup code uses a context manager. |

## Reference Validation

Checked 11 high-impact sources / source-derived claims, prioritizing the Round 1 blockers.

1. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint` — directly verifies incoming A2A preview status, protocol **version 0.3**, supported agent types, PATCH example, A2A endpoint URLs, Entra-only incoming auth, and limitations.
2. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent` — supports outbound A2A as a Foundry Agent Service tool and the `A2APreviewTool` pattern.
3. Reachable — `https://learn.microsoft.com/en-us/python/api/overview/azure/ai-projects-readme` — confirms `azure-ai-projects` v2.1.0 and states the client library is “in preview.”
4. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice` — verifies A2A and Code Interpreter support for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, plus East US 2 Code Interpreter support and South Central US Code Interpreter non-support.
5. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions` — verifies Agent Service GA status and fixed service limits.
6. Reachable via Microsoft Learn search/fetch — model catalog page verifies `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, and no `gpt-5.5-mini` listing.
7. Reachable via Microsoft Learn search/fetch — model region availability verifies `gpt-5.5` Global Standard in East US 2 and South Central US, with `gpt-5.4` / `gpt-5.4-mini` broadly available in Americas regions.
8. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning` search result supports access-gating distinctions for `gpt-5.5` and `gpt-5.4-mini`.
9. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits` search/fetch evidence supports the quota table values for the recommended models.
10. Reachable — `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents` citation supports the hosted-agent A2A endpoint format.
11. Reachable — `https://github.com/microsoft-foundry/foundry-samples` is now present in the reference list as the previously missing code sample/template reference.

No fabricated URLs found in the checked set. One auditability issue remains: the source-count header does not match the final reference list.

## Claim Citation Coverage

The substantive claims that previously blocked approval are now cited: model existence/absence, per-model A2A and Code Interpreter support, East US 2 recommendation, SDK preview status, A2A 0.3, hosted-agent endpoint format, and Agent Service limits all have inline citations or immediately adjacent source notes.

No new material citation blocker found.

## Quote Verification

Verified the high-impact quotes most relevant to the Round 1 fixes:

- Verified — “The AI Projects client library (in preview) is part of the Microsoft Foundry SDK.”
- Verified — “Foundry Agent Service supports A2A protocol version 0.3 only.”
- Verified — incoming A2A endpoint URLs and Entra ID authentication language materially match the incoming A2A page.
- Verified — Tool best-practices tables support A2A and Code Interpreter for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.
- Verified — Agent Service fixed limits table supports the added limits section.

No fabricated or materially altered high-impact quote found.

## Source Officialness

No material officialness issues. Sources are Microsoft Learn, Azure SDK docs on Microsoft Learn, Azure-Samples/Microsoft GitHub organizations, and the `microsoft-foundry/foundry-samples` repository. The report also references the public A2A protocol, but Azure capability claims are grounded in Microsoft Learn.

## Technical Accuracy

Most Round 1 technical blockers are resolved:

- Model decision is technically aligned with official sources: `gpt-5.5-mini` is excluded; `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` are treated individually; `gpt-5.5` + `gpt-5.4-mini` in East US 2 is consistent with the region/tool constraints.
- Preview/GA status is now precise enough for implementation planning: Agent Service core GA; A2A, hosted agents, and SDKs preview.
- A2A protocol interop risk is correctly called out as **A2A 0.3** for the LangGraph side.
- REST and Python snippets have plausible current SDK/REST patterns and source/provenance labels.

No new technical must-fix finding.

## Source Freshness & Currency

No freshness blocker found. The report uses current Microsoft Learn pages for Foundry Agent Service, A2A preview, SDK package status, model availability, quotas, and tool support. Preview features are now clearly labeled.

## Topic Coverage Assessment

Coverage is now sufficient for the Zava demo decision path: Foundry Agents V2, A2A outbound/inbound, public endpoint demo implications, private VNet considerations, model selection, quotas, SDK status, REST/Python patterns, and Agent Service limits are covered.

The only remaining issue is not coverage depth but reference-list auditability.

## Code & CLI Validation

Python examples are syntactically plausible on inspection and use current Azure Identity patterns. Code blocks include visible post-block source/provenance attribution. CLI/REST examples use current `az account get-access-token` patterns and the requested versioned-agent endpoint style.

No code/CLI blocker found.

## Reference List Integrity

🟡 Important (must-fix) — Location: Header line 6 and Section 12. Issue: the header says “Sources consulted: 24 Microsoft Learn pages, 3 GitHub repositories, 1 MS Learn training module,” but Section 12 lists 27 entries under “Microsoft Learn Documentation,” 2 more Python SDK Learn pages, 3 “Microsoft Agent Framework & Training” Learn entries, 3 GitHub repositories, and 1 code sample/template. Why it matters: Round 1 explicitly required counts to match. This is an auditability requirement in the reviewer rubric and remains unresolved even though the missing `foundry-samples` reference was added.

## Report Structure & Completeness

The report structure is complete and readable: Executive Summary, overview, key concepts, setup, core usage, A2A, networking, model considerations, best practices, pricing/limits/quotas, limitations, and references are present. Inline quotes are embedded in relevant sections.

No structure blocker beyond the reference-list count/category mismatch.

## Consistency & Contradictions

No high-impact contradiction with the project context or companion findings:

- Consistent with the locked model pairing: `gpt-5.5` + `gpt-5.4-mini` in East US 2.
- Consistent with the model-availability review artifact: no `gpt-5.5-mini`; A2A confirmed for the three existing models; East US 2 is the recommended region.
- Consistent with Foundry V2 research: project-based Foundry V2, Responses API, and East US 2 recommendation.
- Consistent with A2A protocol research where it matters for implementation: general A2A may be newer, but Foundry incoming A2A is explicitly **0.3**, so LangGraph interoperability must target/bridge 0.3.

Note: the requested companion file `research/2026-05-20-model-availability.md` was not present in the repository; cross-checking used the available `agent-reviews/2026-05-20-model-availability-review.md` plus official Microsoft Learn sources.

## Suggested Improvements

1. Fix the source-count header and categories so they match Section 12 exactly. Suggested wording: “Sources consulted: 32 Microsoft Learn pages, 3 GitHub repositories, 1 code sample/template” if retaining all current Learn entries, or move SDK/Agent Framework pages into the Microsoft Learn count explicitly.
2. Consider adding the exact model/tool-support rows for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` inline for easier auditability.
3. Add access dates or “accessed 2026-05-20” to model availability and quota references because these pages change frequently.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

The substantive demo-feasibility issues are resolved, including model selection, `gpt-5.5-mini` removal, A2A 0.3, SDK preview status, endpoint examples, provenance labels, and limits. However, Round 1 explicitly marked reference-list count integrity as a must-fix, and the header/reference-list counts still do not match. Fix that auditability issue and this report should be ready for approval.
