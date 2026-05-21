---
reviewer: ms-docs-research-reviewer
subject: GPT-5.5 / GPT-5.4 / GPT-5.4-mini Model Availability in Microsoft Foundry V2
companion: ms-docs-researcher
date: 2026-05-20
verdict: APPROVED
---

## Review Round 1 — 2026-05-20

## Reference Validation

Checked 8 of 9 Microsoft Learn reference-list entries, prioritizing the demo-critical model catalog, region availability, A2A/tool matrix, quota, and preview-status claims.

1. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure` — reachable. It supports the report's core model-existence claim: the model highlights list `GPT-5.5 series` as `gpt-5.5` only and `GPT-5.4 series` as `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4`, and `gpt-5.4-pro`. It does not contain `gpt-5.5-mini`.
2. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability` — reachable. The Global Standard Americas table supports `gpt-5.5` only in `eastus2` and `southcentralus`, and `gpt-5.4-mini` in all listed Americas regions. It does not contain `gpt-5.5-mini`.
3. `https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning` — reachable via search/fetch pattern; supports GPT-5 reasoning model access distinctions at a high level. Not exhaustively revalidated because the model catalog and quota pages are more authoritative for this report's critical claims.
4. `https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits` — reachable. It supports `gpt-5.5` GlobalStandard quota of `0 / 0` for Tier 1 through Tier 4 and nonzero quota beginning at Tier 5.
5. `https://learn.microsoft.com/en-us/azure/foundry/agents/overview` — reachable. It supports Agent Service protocol status: “A2A protocol (preview)” and “Hosted agents (preview).”
6. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice` — reachable. It directly supports per-model Agent2Agent and Code Interpreter support for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, and regional Code Interpreter support/no-support.
7. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions` — not deeply spot-checked in this round; the report uses it only for Agent Service limits, not the model-choice foundation.
8. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents` — reachable. It supports Hosted agents preview status, A2A endpoint format, and protocol combination claims.
9. `https://learn.microsoft.com/en-us/azure/foundry/reference/region-support` — listed but not cited in the body in a material way; no blocker.

No fabricated URLs found. The requested companion research files `research/2026-05-20-foundry-v2.md`, `research/2026-05-20-foundry-agents.md`, and `research/2026-05-20-a2a-protocol.md` were not present in the repository at review time; only their review files were present, so cross-checking was limited to those existing review artifacts.

## Claim Citation Coverage

Most high-stakes claims are cited to official Microsoft Learn pages, and the report has unusually strong source coverage for model availability, A2A/tool support, region choice, and quota.

Findings:

- 🟡 Important (must-fix) — Location: Sections 6 and 8, tool capability claims. Issue: The report attributes “Function calling / tools,” “Structured outputs,” and “vision/multimodal” capability to the Tool best practices page, but that page's model/tool table does not contain Structured outputs or vision columns and shows the `Functions` tool as `No` for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`. Why it matters: The report should distinguish base model API capabilities from Foundry Agent Service tool support. A reader could otherwise assume Foundry Agent Service function tools are supported for these deployments when the checked tool matrix says otherwise.
- 🟢 Minor (nice-to-have) — Location: Header and reference list. Issue: Header says “8 Microsoft Learn pages,” but the Complete Reference List includes 9 Microsoft Learn documentation entries. Why it matters: Source counts should match the reference list for auditability.

## Quote Verification

Verified 7 high-impact quote/table-derived claims.

- Verified — Model existence: official model highlights list `GPT-5.5 series` with `gpt-5.5` only, and `GPT-5.4 series` with `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4`, `gpt-5.4-pro`. `gpt-5.5-mini` was absent from both the model catalog page text and all parsed catalog tables.
- Verified — Region availability: official Global Standard Americas table shows `gpt-5.5` as available only in `eastus2` and `southcentralus`; `gpt-5.4-mini` is available in all listed Americas regions. `gpt-5.5-mini` was absent from the page text and all parsed region tables.
- Verified — A2A/tool support rows from Tool best practices. Verbatim table rows checked:
  - `gpt-5.5 | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
  - `gpt-5.4 | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
  - `gpt-5.4-mini | Yes | Yes | No | Yes | Yes | Yes | Yes | No | Yes | Yes | No | No | Yes | Yes | Yes | Yes | Yes`
  These rows verify Agent2Agent and Code Interpreter are `Yes` for all three existing candidate models, but also show `Functions` as `No`.
- Verified — Tool best practices troubleshooting quote: “Tool availability requires support from both the model and the region. Check the region availability table for your region and the model support table for your model. If either shows `No`, the tool can't run, even if the other shows `Yes`.”
- Verified — Tool best practices troubleshooting quote: “For example, code interpreter doesn't run in regions that show `no` for Code Interpreter (such as `southcentralus` and `spaincentral`), regardless of which model you use.”
- Verified — Quota warning from model catalog: “Some quota tiers will require quota requests for `gpt-5.5` to be able to deploy this model. Tier 5 and Tier 6 subscriptions have quota by default.”
- Verified — Hosted agents endpoint quote: Hosted agents lists `A2A (preview): {project_endpoint}/agents/{name}/endpoint/protocols/a2a` and says all four protocols—Responses, Invocations, Activity, and A2A—can be combined in a single agent.

No fabricated quotes found. The A2A per-model support would be stronger if the report included the exact checked table rows inline rather than only a summarized table.

## Source Officialness

No material issues. All report sources are official Microsoft properties: Microsoft Learn pages for Foundry Models, Azure OpenAI quotas, Foundry Agent Service, Hosted agents, and region/tool matrices. No unofficial blogs, Stack Overflow, or community tutorials are cited.

## Technical Accuracy

Core model-choice conclusions are technically sound: `gpt-5.5-mini` is not in the checked official catalog/region pages; `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` all show Agent2Agent support; East US 2 is the only US region combining `gpt-5.5` Global Standard availability and Code Interpreter support; and `gpt-5.5` is quota-gated below Tier 5.

Findings:

- 🟡 Important (must-fix) — Location: Section 6 “Complete Tool Support Matrix” and Section 8 “Both models are fully compatible.” Issue: The report says Function calling is supported by all candidate models and cites Tool best practices, but the checked Foundry Agent Service tool matrix has `Functions = No` for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`. If the report means base-model API function/tool calling from the model catalog, it must cite the model catalog and clearly separate that from Agent Service tools. Why it matters: The Zava plan may need precise tool semantics for Bicep/agent configuration; conflating API capability with Agent Service tool availability can cause implementation errors.
- 🟡 Important (must-fix) — Location: Section 5 “Per-Model Gotchas,” especially “A2A support is independent of model — all GPT-5.x models that support function calling also support A2A.” Issue: This is overbroad and contradicted by the same Tool best practices table: examples such as `gpt-5.1`/`gpt-5.2` show tool-support differences, and the report itself notes older GPT-5.x variants do not support A2A. Why it matters: The report should only claim A2A support for the specifically verified models (`gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, optionally `gpt-5.4-nano/pro`) rather than generalizing across all GPT-5.x models.
- 🟢 Minor (nice-to-have) — Location: Section 2 “GA vs Preview Status.” Issue: The report reasonably says `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` have no Preview tag, but “indicates GA” is still an inference. Why it matters: Safer wording would be “not marked Preview on the checked catalog page,” while separately saying A2A and Hosted agents are preview.

Verified technical points:

- `gpt-5.5-mini` absence: confirmed on both the model catalog page and region availability page.
- Per-model A2A: confirmed for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` via Tool best practices rows.
- East US 2 recommendation: confirmed. Global Standard Americas table gives `gpt-5.5` only in `eastus2` and `southcentralus`; Tool best practices region table gives Code Interpreter `yes` in `eastus2` and `no` in `southcentralus`.
- Quota claim: confirmed. Parsed quota tables show `gpt-5.5` GlobalStandard `0 RPM / 0 TPM` for Tiers 1-4, `10,000 RPM / 10,000,000 TPM` at Tier 5, and `15,000 RPM / 15,000,000 TPM` at Tier 6.
- Recommendation soundness: mostly sound. `gpt-5.5` + `gpt-5.4-mini` is the best capability/cost pairing if Tier 5+ quota or an approved quota increase is available. The fallback to two separate `gpt-5.4-mini` deployments is pragmatic for demo time pressure.

## Source Freshness & Currency

Sources are current Microsoft Learn pages for Foundry V2 / Agent Service / Azure OpenAI model availability. The report correctly separates platform preview status from model catalog status in most places: A2A is preview; Hosted agents are preview; candidate models are not marked Preview in the checked model catalog.

Findings:

- 🟢 Minor (nice-to-have) — Location: Report-wide. Issue: No source last-updated dates or access dates are recorded. Why it matters: Model availability and quota tables change frequently; recording access dates would make the decision trail more defensible.
- 🟢 Minor (nice-to-have) — Location: Section 7 quota table. Issue: Tier 4 is omitted from the displayed table even though the narrative says Tiers 1-4 have `0 / 0` for `gpt-5.5`. Why it matters: The claim is correct, but including Tier 4 would remove any ambiguity.

## Topic Coverage Assessment

The report covers the required decision areas well: model existence/naming, Global Standard deployment availability, per-model A2A support, Code Interpreter region constraints, quotas, access gating, GA/preview status, and a recommendation/fallback.

Findings:

- 🟡 Important (must-fix) — Location: Sections 6 and 8. Issue: The report's tool matrix overreaches beyond the verified focus areas. A2A and Code Interpreter are correctly covered, but Function calling, Structured outputs, and vision/multimodal need either separate model-catalog citations or removal from the Agent Service tool matrix. Why it matters: This report is intended to drive architecture and Bicep decisions; unsupported or mis-sourced capability rows are risky.
- 🟢 Minor (nice-to-have) — Location: Section 8 fallback. Issue: The fallback says use `gpt-5.4-mini` for both agents with different deployment names, which is technically sound, but it could state whether using the same model twice still satisfies the “different model deployment” requirement from project context. Why it matters: It prevents confusion between “different models” and “different deployments.”

## Code & CLI Validation

No Python, Azure CLI, PowerShell, or Bicep examples are present in this model-availability report. That is acceptable for this topic because the report is a model/region/quota decision document rather than an implementation guide. No code or CLI syntax issues found.

## Reference List Integrity

Findings:

- 🟢 Minor (nice-to-have) — Header count mismatch: the header says 8 Microsoft Learn pages consulted, while the Microsoft Learn Documentation reference list contains 9 entries. Update either the count or the list.
- 🟢 Minor (nice-to-have) — `Feature availability across cloud regions` appears in the reference list but is not materially cited in the body. Keep it only if it supports a specific claim, or remove it as an orphaned reference.
- No unofficial references found.
- GitHub Repositories and Code Samples categories correctly say none consulted.

## Report Structure & Completeness

The report has a clear title/header, executive summary, table of contents, concept/region/tool/quota sections, recommendation, research limitations, and organized references. Inline blockquotes are used near relevant claims rather than collected at the end.

Findings:

- 🟢 Minor (nice-to-have) — The report does not use the generic ms-docs-researcher template section names exactly (for example, no “Getting Started” or “Core Usage”), but the custom structure is appropriate for a model-availability decision report.
- 🟢 Minor (nice-to-have) — The A2A support section says “all four existing candidate models” while the requested candidate set has only three existing models after excluding nonexistent `gpt-5.5-mini`; clean up the wording.

## Consistency & Contradictions

Internal consistency is generally strong for the central recommendation: the executive summary, region matrix, quota section, and recommendation all align on `gpt-5.5` + `gpt-5.4-mini` in East US 2, with `gpt-5.4-mini`-for-both fallback if quota is blocked.

Cross-check notes:

- The companion research files requested by the user were not present in `research/` at review time. Existing review artifacts for Foundry V2 and Foundry Agents previously flagged the same issue that `gpt-5.5-mini` was not found / was overclaimed. This model-availability report resolves that contradiction by explicitly stating `gpt-5.5-mini` does not exist in the checked official catalog.
- No contradiction found with the existing review artifacts on A2A preview status or Hosted agents preview status.

Findings:

- 🟡 Important (must-fix) — Location: Section 5 and Section 6. Issue: The report first says A2A has “no per-model restrictions” / is independent of model, but then gives examples of models that do not support A2A. Why it matters: The correct conclusion is narrower: the checked candidate models support A2A according to the current Tool best practices matrix.

## Suggested Improvements (Prioritized)

1. Fix the Section 6 tool matrix: keep A2A and Code Interpreter as verified Agent Service tools; move Function calling, Structured outputs, and vision/multimodal into a separate “base model/API capabilities” table with model-catalog citations, or remove them.
2. Replace the overbroad “A2A support is independent of model” claim with “A2A support is confirmed for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` by the Tool best practices model matrix.”
3. Add the exact Tool best practices table rows for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` or quote them as evidence for per-model A2A support.
4. Add Tier 4 to the quota table so the “Tiers 1-4 = 0/0” claim is visible in table form.
5. Update the source count from 8 to 9 Microsoft Learn pages or remove the orphaned region-support reference.
6. Change GA wording to “not marked Preview in the checked model catalog” unless an official page explicitly labels the model IDs GA.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

The report gets the most important model-decision conclusions right: `gpt-5.5-mini` is absent from official catalog/region pages; `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` support Agent2Agent; East US 2 is the correct `gpt-5.5` + Code Interpreter US region; and `gpt-5.5` is quota-gated below Tier 5. However, it has unresolved 🟡 Important (must-fix) issues because it conflates base model capabilities with Foundry Agent Service tool support and makes an overbroad A2A generalization across GPT-5.x models. Fix those precision issues before using this as the locked model-choice foundation.


## Review Round 2 — 2026-05-20

### Fix Verification

1. **RESOLVED — ✅ fixed: 🟡 Important Section 6 tool matrix split into two tables.** Section 6 now explicitly separates **Table A — Foundry Agent Service Tool Support per Model** from **Table B — Base Model API Capabilities per Model**. Table A is sourced to Tool best practices and includes `Functions = No`; Table B is sourced to the model catalog. The report explains that Agent Service `Functions: No` is distinct from base-model function/tool calling and is not needed for this demo's Foundry agent configuration.
2. **RESOLVED — ✅ fixed: 🟡 Important overbroad A2A generalization replaced.** Section 5 now scopes the claim to `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`, plus notes that older models such as `gpt-5.1-chat` and `gpt-5.1-codex` show Agent2Agent = No. The previous broad “all GPT-5.x” implication is gone.
3. **RESOLVED — ✅ fixed: 🟡 Important inline verbatim tool-best-practices rows added.** Section 6 includes the Tool best practices column headers and three explicit verbatim rows for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.
4. **RESOLVED — ✅ fixed: 🟡 Important / 🟢 Minor “Both models are fully compatible” wording.** Section 8 now says “Both models are compatible with the demo's requirements” and lists Agent Service A2A/Code Interpreter separately from base-model function calling. It also explicitly says the Foundry Agent Service `Functions` tool is not supported and not needed.
5. **RESOLVED — ✅ fixed: 🟢 Minor quota table includes Tier 4.** Section 7 includes a Tier 4 RPM/TPM column, including `gpt-5.5` as `0 / 0`.
6. **RESOLVED — ✅ fixed: 🟢 Minor reference count fixed.** Header says 9 Microsoft Learn pages, matching the 9 Microsoft Learn entries in the reference list.
7. **RESOLVED — ✅ fixed: 🟢 Minor GA wording softened.** Section 2 now says the checked model IDs are “not marked Preview in the checked model catalog,” and Research Limitations explicitly notes this is not an explicit GA declaration.
8. **RESOLVED — ✅ fixed: 🟢 Minor “four candidate models” wording fixed where it mattered.** Executive Summary and Section 5 now consistently identify the three existing candidate models after excluding nonexistent `gpt-5.5-mini`. Section 1 still describes the original four user-provided candidates, which is accurate context rather than a defect.
9. **RESOLVED — ✅ fixed: 🟢 Minor access dates added.** Header includes `Access date: 2026-05-20 (all sources accessed on this date)`.
10. **RESOLVED — ✅ fixed: 🟢 Minor fallback clarity.** Section 8 now states that two `gpt-5.4-mini` deployments with different deployment names satisfy the project requirement for different model deployments, not necessarily different model IDs.

## Reference Validation

Checked 6 of 9 Microsoft Learn URLs, focusing on Round 1 blockers and model-choice-critical claims:

1. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice` — reachable. It contains the model support table with the exact `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` rows now quoted in Section 6; it also confirms `Agent2Agent = Yes`, `Code Interpreter = Yes`, `Functions = No`, and the region table showing `southcentralus` Code Interpreter = `no`.
2. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure` — reachable. It remains the correct official source for model existence and base model capabilities.
3. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability` — reachable. It remains the correct official source for Global Standard regional availability and supports the East US 2 recommendation.
4. `https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits` — reachable. It remains the correct official source for per-tier RPM/TPM quota tables, including the Tier 4 row now represented in the report.
5. `https://learn.microsoft.com/en-us/azure/foundry/agents/overview` — reachable. It supports the A2A protocol preview wording.
6. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents` — reachable. It supports the hosted-agent protocol combination and A2A endpoint claims.

No fabricated or unofficial URLs found.

## Claim Citation Coverage

No material issues. The previously problematic capability claims are now properly divided by source: Agent Service tool support cites Tool best practices, while base-model capabilities cite the model catalog. The report's model pairing and fallback claims are sufficiently sourced for decision-making.

## Quote Verification

Verified the high-impact Round 2 quoted/table-derived evidence:

- The three inline Tool best practices rows match the official model support table for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.
- The Tool best practices quote about tool availability requiring both model and region support is present and correctly used.
- The Code Interpreter region caveat mentioning `southcentralus` and `spaincentral` is present and correctly used.
- The Hosted agents quote about combining Responses, Invocations, Activity, and A2A is present and correctly used.
- The Foundry Agent Service overview quote identifying A2A as preview is present and correctly used.

No misattributed or fabricated quotes found.

## Source Officialness

No material issues. All cited sources are Microsoft Learn pages. GitHub repositories and code samples are correctly listed as none consulted.

## Technical Accuracy

No material issues. The Round 1 technical blockers are resolved:

- The report no longer conflates Foundry Agent Service `Functions` tool support with base-model function/tool calling.
- A2A support is stated only for the verified candidate models and optional nearby `gpt-5.4` variants shown in the same official table.
- East US 2 remains technically justified because `gpt-5.5` Global Standard is available there and the Tool best practices region matrix shows Code Interpreter support there.
- The fallback to two separate `gpt-5.4-mini` deployments is aligned with the project instruction requiring different model deployments.

## Source Freshness & Currency

No material issues. The report now records an access date and avoids overclaiming model GA status. A2A and Hosted agents are still accurately described as preview.

## Topic Coverage Assessment

No material issues. The report covers model existence, naming, deployment SKU, region selection, A2A support, Code Interpreter support, Agent Service-vs-base-model tool semantics, quota/access constraints, and a clear recommended pairing/fallback. This is sufficient as the model-choice foundation for the Zava A2A demo.

## Code & CLI Validation

No material issues. The report contains no Python, Azure CLI, PowerShell, or Bicep examples. That is acceptable for this model-availability decision document.

## Reference List Integrity

No material issues. Header count now matches the 9 Microsoft Learn documentation entries. Reference categories are present and correctly state no GitHub repositories or code samples were consulted.

## Report Structure & Completeness

No material issues. The report is structured as a decision-focused research document rather than the generic tutorial template, which is appropriate for this topic. The new Section 6 split materially improves auditability.

## Consistency & Contradictions

No material issues. The executive summary, Section 5, Section 6, and Section 8 now align: three existing candidate models are verified for Agent2Agent; `gpt-5.5-mini` is excluded; Agent Service `Functions` is unsupported but not required; and base-model function calling remains available for the LangGraph worker.

## Suggested Improvements (Prioritized)

1. Optional: add source last-updated dates beside the access date if available from the Microsoft Learn pages.
2. Optional: if implementation later requires the Foundry Agent Service `Functions` tool specifically, re-check the Tool best practices matrix before configuring the Foundry agent.

## Readiness Verdict: APPROVED

**Verdict:** APPROVED

All prior 🟡 Important must-fix findings are resolved, and the remaining 🟢 Minor items from Round 1 have either been fixed or are safely waived. The report is ready to use as the model-choice foundation for the Zava Smart Order Feasibility A2A demo.
