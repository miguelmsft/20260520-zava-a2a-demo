---
reviewer: ms-docs-research-reviewer
subject: Microsoft Foundry V2 — Architecture, Bicep Deployment, and RBAC
companion: ms-docs-researcher
date: 2026-05-20
verdict: APPROVED
---

## Review Round 1 — 2026-05-20

## Reference Validation

Checked 12 of 17 reference-list entries, plus 3 ARM/Bicep template reference pages for the critical IaC claims.

Checked sources:

1. `https://learn.microsoft.com/en-us/azure/foundry/what-is-foundry` — reachable; supports unified platform, current vs classic mapping, new portal toggle, pricing statement, and project endpoint code pattern.
2. `https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture` — reachable; supports `Microsoft.CognitiveServices/accounts`, `kind: AIServices`, projects as `Microsoft.CognitiveServices/accounts/projects`, managed storage, deployment types, and VNet models.
3. `https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry` — reachable; supports renamed Foundry roles, role definition GUIDs, permissions matrix, Entra ID vs key warning, and minimum role assignments.
4. `https://learn.microsoft.com/en-us/azure/foundry/how-to/create-resource-template` — reachable; supports Bicep quickstart and official samples link, but it states the quickstart template creates Foundry resource and project; the model deployment comes from the linked sample, not the Learn quickstart body.
5. `https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources` — reachable; supports CLI creation, `--allow-project-management`, `az cognitiveservices account project create`, and deployment create syntax.
6. `https://learn.microsoft.com/en-us/azure/foundry/concepts/general-availability` — reachable; supports new portal GA, feature readiness, and Agents v2 support in new UI.
7. `https://learn.microsoft.com/en-us/azure/foundry/reference/region-support` — reachable; supports Foundry project region list and explicitly does not list West US 2.
8. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions` — reachable; supports Agent Service GA status, dependency on Responses API regions, and limits table.
9. `https://learn.microsoft.com/en-us/azure/foundry/how-to/navigate-from-classic` — reachable; supports classic/current terminology, Responses API, Agents v2 GA, Assistants API sunset, and A2A protocol Preview in the feature comparison.
10. `https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/responses` — reachable; supports Responses API regions and model support list, including `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`; does not list `gpt-5.5-mini`.
11. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability` — reachable; supports global/data-zone/regional deployment availability for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`.
12. `https://raw.githubusercontent.com/microsoft-foundry/foundry-samples/main/infrastructure/infrastructure-setup-bicep/00-basic/main.bicep` — reachable via raw GitHub; GitHub MCP access to the `microsoft-foundry` organization was blocked by SAML, but the public raw file was accessible and matches the report's Bicep snippet in substance.

Additional Bicep reference checks:

- `Microsoft.CognitiveServices/accounts` template reference is reachable and lists latest GA `2026-03-01`.
- `Microsoft.CognitiveServices/accounts/projects` template reference is reachable and lists latest GA `2026-03-01`.
- `Microsoft.CognitiveServices/accounts/deployments` template reference is reachable and lists latest GA `2026-03-01`.

No fabricated source URLs found among checked sources. Some body-cited pages were not spot-checked: upgrade Azure OpenAI to Foundry, hosted agent quickstart, workflow, planning, and MicrosoftDocs repo root.

## Claim Citation Coverage

The core architecture and RBAC sections are well cited, but there are material citation gaps.

- 🟡 Important (must-fix) — Location: Executive Summary and Section 6, model/region claims. Issue: The report says the required models are supported by Responses API and says Foundry V2 is available in all target US regions, but it does not cite the dedicated Foundry model regional availability matrix for the candidate demo models and deployment types. Why it matters: The project context requires selecting from `GPT-5.5`, `GPT-5.4`, `GPT-5.5-mini`, and `GPT-5.4-mini` based on Foundry V2/global deployment availability; the report currently cannot safely support that decision.
- �� Important (must-fix) — Location: Section 8, "Key Concepts for Decision-Makers." Issue: Several high-impact claims are unsourced or only implicitly sourced, including "preserves your existing endpoint, API keys, network configuration, and all state," "production-ready Bicep templates ... covering 25+ scenarios," and "takes under a minute to deploy." Why it matters: The user explicitly required every key claim to have a verbatim quote and clickable official source.
- 🟢 Minor (nice-to-have) — Location: Section 5, best-practice bullets. Issue: Some bullets are reasonable syntheses but are not individually cited. Why it matters: They are lower risk than deployment/RBAC/model claims, but explicit citations would improve traceability.

## Quote Verification

Spot-checked 13 of 54 blockquote/source attributions. Verified quotes from architecture, RBAC, GA, region support, Responses API, limits, pricing, and Bicep sample sources. Most checked quotes were accurate or acceptable with minor formatting differences.

Findings:

- 🟡 Important (must-fix) — Location: Section 3, "Bicep Template — Account + Project + Model Deployment." Issue: The report labels the Bicep snippet as "official basic Bicep template" and `Provenance: verbatim (with minor comment additions)`. The raw sample is substantively the same, but comments and spacing are changed and the report omits the second commented model deployment block. Why it matters: This is not a blocking technical error, but provenance should be `adapted` or the snippet should be truly verbatim. The report's own provenance standard requires accurate labeling.
- 🟢 Minor (nice-to-have) — Location: Section 1 terminology table. Issue: The table appears closer to the `what-is-foundry` evolution table than the cited `navigate-from-classic` page, although both pages support the general mapping. Why it matters: Source attribution should point to the exact page containing the quoted/table content.

## Source Officialness

No unofficial sources found. Microsoft Learn, Microsoft-owned GitHub organizations, `ai.azure.com`, Azure portal, and Azure pricing/infrastructure URLs are official Microsoft properties.

## Technical Accuracy

The report is directionally strong on Foundry V2 vs Classic and RBAC, but several technical issues block approval.

- 🟡 Important (must-fix) — Location: Section 3 Bicep and lines 103, 119, 284. Issue: The report states/uses API version `2025-06-01` as the deployment API version. That version is GA and appears in official samples, but it is not the current/latest GA API version. The current Microsoft template reference for `Microsoft.CognitiveServices/accounts`, `accounts/projects`, and `accounts/deployments` lists `2026-03-01` as latest. Why it matters: The review request specifically requires current GA API versions for the Foundry account and project sub-resources.
- 🟡 Important (must-fix) — Location: Executive Summary line 14 and Section 6 model support. Issue: The report claims the candidate models are supported by Responses API, but it omits `gpt-5.5-mini` from the supported-model table and only notes it later as a limitation. It also does not clearly separate Responses API support from Foundry model deployment availability and Agent/A2A compatibility. Why it matters: The project model choice depends on per-model support; unsupported or unverified `gpt-5.5-mini` must be explicit in the main matrix, not only in limitations.
- 🟡 Important (must-fix) — Location: Executive Summary line 14 vs Section 6 lines 470-480. Issue: The executive summary says Foundry V2 is available in all target US regions, but the project context includes West US 2 and the report later says West US 2 is not listed in Foundry project region support. Why it matters: This contradiction can lead planners to choose an unsupported region.
- 🟡 Important (must-fix) — Location: Section 6 "Responses API Model Support". Issue: The report uses Responses API model support as a proxy for Agent Service and A2A compatibility. The checked Agent Service limits/regions page says Agent Service requires a deployed model compatible with Agent Service and model/region availability can vary; the classic migration page lists A2A protocol as Preview. Why it matters: The Zava project requires Foundry Agents V2 with A2A. If A2A support is out of scope, the report should explicitly avoid implying model support equals A2A support and point to separate A2A research.
- 🟢 Minor (nice-to-have) — Location: Python setup example. Issue: The synthesized direct `OpenAI` example manually obtains a token once and passes `default_headers`, while current official samples commonly use `AIProjectClient.get_openai_client()` or a bearer token provider. Why it matters: The example may work short-term but is less robust for token refresh; consider aligning it with the current official quickstart pattern.

## Source Freshness & Currency

- 🟡 Important (must-fix) — Location: Bicep section. Issue: API versions are not current/latest GA despite current template docs listing `2026-03-01`. Why it matters: This directly conflicts with the review requirement for current GA API versions.
- 🟡 Important (must-fix) — Location: Region/model availability. Issue: The report cites current region and Responses API docs but omits the dedicated current model regional availability page from the reference list and from the matrix. Why it matters: Model availability changes frequently and the report must support current model selection.
- 🟢 Minor (nice-to-have) — Location: Report-wide. Issue: The report does not record source last-updated dates or access dates. Why it matters: The request prefers sources from the past 12 months; Learn pages are current in content, but the report should make recency auditable.

## Topic Coverage Assessment

Coverage is good for Foundry V2 topology, RBAC, portal control plane, and basic Bicep. Coverage is insufficient for the user-specific critical checks.

- 🟡 Important (must-fix) — Location: Section 6. Issue: The region matrix focuses on Foundry project regions and Responses API regions, but it does not provide a US-focused candidate model deployment matrix for `gpt-5.5`, `gpt-5.4`, `gpt-5.5-mini`, and `gpt-5.4-mini` across Global Standard / Global Provisioned / Data Zone / Regional where relevant. Why it matters: The project requires choosing a supported model and region.
- 🟡 Important (must-fix) — Location: Section 9 limitations. Issue: A2A support is deferred to separate research, but the main body still says Foundry V2 supports Agents V2 and lists model support in a way a planner could treat as sufficient for A2A. Why it matters: The project is specifically an A2A demo; the report must state the boundary more prominently or include the official A2A Preview status and support constraints.
- 🟢 Minor (nice-to-have) — Location: Pricing/Limits. Issue: Pricing section is brief and points only to platform-level pricing, not model/deployment-level pricing pages. Why it matters: Acceptable for architecture research, but cost planning would need more detail.

## Code & CLI Validation

Static review only; no Azure calls executed.

- Bicep syntax: The sample is structurally valid Bicep and matches the public raw GitHub sample. It would create a Foundry account, project, and model deployment using `gpt-4.1-mini` in `eastus2` under the official sample assumptions.
- Azure CLI syntax: `az group create`, `az deployment group create`, `az cognitiveservices account deployment create/show`, project create/show, and `az role assignment create` patterns match Microsoft Learn examples.
- PowerShell syntax: `New-AzResourceGroup`, `New-AzResourceGroupDeployment`, `Get-AzResource`, and `Remove-AzResourceGroup` are plausible and match Learn quickstart patterns.
- Python syntax: The visible Python example has no obvious syntax errors and uses current packages (`azure.identity`, `openai`), but the auth pattern should be modernized as noted above.

Findings:

- 🟡 Important (must-fix) — Location: Section 3 Bicep. Issue: Uses `gpt-4.1-mini` sample deployment, while the project candidate models are `gpt-5.5`, `gpt-5.4`, `gpt-5.5-mini`, and `gpt-5.4-mini`. Why it matters: The sample is valid, but the report should add a project-ready Bicep variant using a verified candidate model/version/deployment type and region, or clearly label the existing sample as a generic official sample only.
- 🟡 Important (must-fix) — Location: Section 3 CLI step 4. Issue: The CLI example deploys `gpt-5.4-mini` with `--sku-name GlobalStandard` and capacity 10, but the report does not cite the model regional availability page proving that exact model/version/deployment type is available in the chosen account region. Why it matters: A copied deployment command may fail if the chosen region/deployment type is unsupported.

## Reference List Integrity

- Header counts: 14 Microsoft Learn pages, 2 GitHub repositories, 1 code sample. These counts match the reference list categories.
- Body-cited sources mostly appear in the reference list.
- 🟡 Important (must-fix) — Location: Reference list. Issue: The body relies on Responses API model support for model decisions but does not list the official Foundry model regional availability page, which is necessary for region/deployment verification. Why it matters: The required model/region claims are incomplete without it.
- 🟢 Minor (nice-to-have) — Location: Reference list. Issue: `ai.azure.com`, Azure portal, Azure pricing, and Azure infrastructure links appear in body/context but are not all represented in the reference list. Why it matters: They are peripheral, but a complete reference list should include all cited sources or intentionally exclude non-research navigational links.

## Report Structure & Completeness

Required major sections are present: Overview, Key Concepts, Getting Started, Core Usage, Configuration & Best Practices, Advanced Topics, Pricing/Limits/Quotas, Research Limitations, and Complete Reference List. Inline quotes are used rather than an end-only quote dump.

- 🟢 Minor (nice-to-have) — Location: Table of Contents. Issue: Anchors use shortened names such as `#1-overview`, which may not match GitHub's generated anchors for headings like `## 1. Overview`. Why it matters: Navigation may be imperfect.
- 🟢 Minor (nice-to-have) — Location: Header. Issue: Source counts are present but access dates/source freshness metadata are absent. Why it matters: Recency is an explicit review criterion.

## Consistency & Contradictions

- 🟡 Important (must-fix) — Location: Executive Summary vs Section 6. Issue: The executive summary says all target US regions are available; Section 6 says West US 2 is not listed. Why it matters: This is a direct contradiction affecting deployment planning.
- 🟡 Important (must-fix) — Location: RBAC section vs user prompt. Issue: The report correctly explains renamed Foundry roles and previous Azure AI names, but the review prompt specifically asks for exact built-in roles including `Azure AI Account Owner` / `Azure AI User`. The report should make the old/new naming equivalence more visible in the summary and recommendations, because some docs/portals may still show previous names. Why it matters: The project owner asked to verify the exact role names they mentioned.
- 🟢 Minor (nice-to-have) — Location: Section 3. Issue: The text says the Bicep template is official basic and includes model deployment; the Learn quickstart says it creates account/project and points to samples. The raw sample does include an optional model deployment. Why it matters: Clarifying Learn quickstart vs GitHub sample provenance would avoid confusion.

## Suggested Improvements (Prioritized)

1. Update Bicep snippets to current/latest GA `2026-03-01` for `Microsoft.CognitiveServices/accounts`, `accounts/projects`, and `accounts/deployments`, or explicitly justify staying on `2025-06-01` despite it not being latest. Include citations to the Azure template reference pages.
2. Add a US-focused model deployment matrix for `gpt-5.5`, `gpt-5.4`, `gpt-5.5-mini`, and `gpt-5.4-mini`, separating Responses API support, Foundry model regional deployment availability, Agent Service compatibility, and A2A protocol support/status.
3. Fix the executive summary contradiction about West US 2 and make the recommended region(s) explicit based on Foundry project + Responses API + Agent Service + candidate model availability.
4. Add a project-ready Bicep example that deploys one verified candidate model (for example `gpt-5.4-mini` or `gpt-5.5`) in a verified US region/deployment type, while keeping the official `gpt-4.1-mini` sample clearly labeled as a generic sample.
5. Add citations/quotes to the decision-maker section or remove/soften unsupported claims such as non-breaking upgrade details, 25+ Bicep scenarios, and deployment time.
6. Add access dates or source last-updated metadata for the most critical Learn pages.
7. Modernize the Python example to match the official `AIProjectClient.get_openai_client()` or bearer token provider pattern.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

The report is promising and uses official sources, but it has unresolved 🟡 Important (must-fix) issues around current GA Bicep API versions, model/region verification for the project candidate models, a West US 2 region contradiction, and insufficient citation coverage for several key claims. These must be fixed before the research can safely support the Zava Foundry V2 deployment plan.

## Review Round 2 — 2026-05-20

### Fix Verification

1. **Bicep API versions updated to `2026-03-01` (HIGH): RESOLVED — ✅ fixed.** Section 3 now keeps the official sample as Template A with `2025-06-01` clearly labeled as the published sample, and adds Template B using `Microsoft.CognitiveServices/accounts@2026-03-01`, `accounts/projects@2026-03-01`, and `accounts/deployments@2026-03-01`. The Azure template references checked in this round list `2026-03-01` as the latest GA resource definition.
2. **West US 2 contradiction removed (HIGH): RESOLVED — ✅ fixed.** The Executive Summary and Section 6 now consistently say Foundry projects support East US, East US 2, West US, and West US 3, but **not West US 2**. East US 2 is consistently recommended.
3. **US-focused model deployment matrix for GPT-5.5/GPT-5.4/GPT-5.5-mini/GPT-5.4-mini (HIGH): RESOLVED — ✅ fixed.** Section 6 now includes a candidate matrix covering Responses API support, Global Standard regions, Data Zone Standard, Agent Service compatibility, and A2A preview status. It correctly marks `gpt-5.5-mini` as not listed.
4. **Project-ready Bicep variant (HIGH): RESOLVED — ✅ fixed.** Template B deploys both recommended project models, `gpt-5.4-mini` and `gpt-5.5`, as Global Standard deployments in `eastus2`. This matches the stated final pairing: `gpt-5.5` + `gpt-5.4-mini` in East US 2.
5. **Foundry model regional availability page in references (HIGH): RESOLVED — ✅ fixed.** The model regional deployment availability page is cited in the Executive Summary, CLI/Bicep sections, Section 6, limitations, and the reference list.
6. **Decision-maker section citations (HIGH): RESOLVED — ✅ fixed.** The prior unsupported claims about preserved endpoint/state/configuration now quote the official upgrade page. The earlier "25+ scenarios" and "under a minute" claims were removed or softened.
7. **Bicep provenance label (MEDIUM): RESOLVED — ✅ fixed.** Template A is now labeled `adapted`; Template B is labeled `synthesized`. This accurately distinguishes the official sample from the project-ready variant.
8. **RBAC name continuity (MEDIUM): RESOLVED — ✅ fixed.** The Executive Summary and RBAC section now show the old → new role-name mapping, including Azure AI Account Owner → Foundry Account Owner and Azure AI Owner → Foundry Owner, with role definition GUIDs.
9. **Python auth modernization (LOW): RESOLVED — ✅ fixed.** The Python setup now uses `AIProjectClient` with `DefaultAzureCredential()` and `project.get_openai_client()`, consistent with the current Microsoft Foundry quickstart pattern.
10. **Source freshness metadata (LOW): RESOLVED — ✅ fixed.** The report header and most reference entries now include access-date/current-version metadata. Two peripheral references lack explicit access dates, but this is a 🟢 Minor nice-to-have and does not block approval.

### Reference Validation

Checked 13 of 21 reference-list entries, focusing on the Round 1 blockers and high-impact claims.

Checked sources:

1. `https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts` — reachable; lists `2026-03-01` as the latest account resource API version.
2. `https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects` — reachable; lists `2026-03-01` and shows the current Bicep resource format.
3. `https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/deployments` — reachable; lists `2026-03-01` and supports the `sku` + `properties.model` shape used in Template B.
4. `https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability` — reachable; supports `gpt-5.5` Global Standard in East US 2 and South Central US, and `gpt-5.4` / `gpt-5.4-mini` Global Standard in all listed US regions.
5. `https://learn.microsoft.com/en-us/azure/foundry/reference/region-support` — reachable; lists Foundry project regions including East US, East US 2, West US, and West US 3, and does not list West US 2.
6. `https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/responses` — reachable; supports Responses API usage and the need for supported regions/models.
7. `https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions` — reachable; confirms Agent Service is GA, depends on Responses API regions, and model/region availability can vary.
8. `https://learn.microsoft.com/en-us/azure/foundry/how-to/navigate-from-classic` — reachable; supports classic/current terminology, Responses API/Agents v2, and A2A protocol Preview status.
9. `https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry` — reachable; confirms Foundry role names, previous Azure AI names, permissions matrix, and role definition GUIDs.
10. `https://learn.microsoft.com/en-us/azure/foundry/how-to/upgrade-azure-openai` — reachable; supports the preserved endpoint/API key/state/security-configuration claims in the decision-maker section.
11. `https://learn.microsoft.com/en-us/azure/foundry/what-is-foundry` — reachable; supports Foundry overview, unified platform claims, project endpoint example, and pricing framing.
12. `https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture` — reachable; supports resource topology, `kind: AIServices`, project child resources, managed storage, and governance boundaries.
13. `https://raw.githubusercontent.com/microsoft-foundry/foundry-samples/main/infrastructure/infrastructure-setup-bicep/00-basic/main.bicep` — reachable; confirms the official sample still uses `2025-06-01` and `gpt-4.1-mini`, matching Template A's adapted provenance.

No fabricated or unofficial references found. I also cross-checked the target report against `research/2026-05-20-model-availability.md` and `research/2026-05-20-foundry-agents.md`; the target report aligns with their core recommendation: `gpt-5.5` + `gpt-5.4-mini` in East US 2.

### Claim Citation Coverage

No material blocking issues. The previously sparse high-impact claims are now cited:

- The East US 2 recommendation cites Foundry project regions, Responses API/Agent Service dependencies, and the model regional availability page.
- The RBAC name continuity and GUID claims cite the RBAC page.
- The decision-maker upgrade-preservation claims quote the upgrade page.
- The Bicep API-version claim cites the Azure template references.

Remaining 🟢 Minor nice-to-have: two lower-impact reference-list entries, Workflow and Foundry Rollout planning, do not include explicit access dates even though the header says all Learn pages were accessed 2026-05-20. Waived for approval.

### Quote Verification

Spot-checked 12 quoted/source-attributed passages. The checked quotes and tables are accurate or acceptable with minor Markdown/table formatting differences:

- Foundry role rename quote: verified against RBAC page.
- Foundry role GUID list: verified against RBAC page.
- Foundry Owner / Foundry Account Owner permissions: verified against RBAC page.
- Minimum role assignments: verified against RBAC page.
- Do-not-use Cognitive Services roles warning: verified against RBAC page.
- Upgrade preservation bullets: verified against upgrade page.
- Foundry project region list: verified against region-support page.
- A2A Preview status: verified against classic migration feature comparison.
- Agent Service region dependency: verified against Agent Service limits/regions page.
- Foundry model availability rows for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini`: verified against the model regional availability page.
- `2026-03-01` template references: verified against the Azure template reference pages.
- Official Bicep sample: verified against the public raw GitHub sample.

No misattributed or fabricated quotes found in the checked set.

### Source Officialness

No material issues. Sources are Microsoft Learn, Azure template reference pages, official Microsoft-owned GitHub repositories, or Microsoft/Azure properties. No third-party sources were used.

### Technical Accuracy

The Round 1 technical blockers are resolved.

- Current GA Bicep API version is correctly documented as `2026-03-01` for the account, project, and deployment resources.
- The official sample's `2025-06-01` API version is now framed as a valid prior GA sample, not the project-ready recommendation.
- East US 2 is technically defensible for the Zava demo because it supports Foundry projects, Responses API/Agent Service dependency, `gpt-5.5` Global Standard, and `gpt-5.4-mini` Global Standard.
- The report no longer treats West US 2 as a supported Foundry project region.
- The A2A status is correctly identified as Preview and bounded by the companion Foundry Agents research.

🟢 Minor nice-to-have: Template B deployment resource names are `gpt-5-4-mini` and `gpt-5-5`, while nearby CLI/Python examples use deployment/model strings with dots (`gpt-5.4-mini`, `gpt-5.5`). This is not a Round 1 blocker because deployment name and model name can differ, but the report would be easier to copy-paste if it explicitly stated which string is the deployment name callers should pass.

### Source Freshness & Currency

No material blocking issues. The report now records 2026-05-20 access/freshness metadata and uses current docs for API versions, model availability, region support, RBAC names, and A2A status. Preview/GA status is clearer than Round 1: Agent Service/Agents v2 are treated as GA where supported, while A2A is Preview.

🟢 Minor nice-to-have: add explicit access dates to the two Microsoft Learn reference entries that still omit them.

### Topic Coverage Assessment

Coverage is now sufficient for the Zava planning decision. The report covers:

- Foundry V2 vs Classic / Hubs distinction.
- Foundry account + project resource topology.
- Verified Bicep with current API versions.
- RBAC role names, old-name continuity, and GUIDs.
- Region and model selection for the Zava candidate list.
- A2A Preview boundary and cross-reference to the A2A/Foundry Agents research.
- Pricing/limits at the appropriate architecture-research depth.

The report's recommendation aligns with the locked project context and the companion Foundry Agents research: **`gpt-5.5` + `gpt-5.4-mini` in East US 2 using Global Standard**.

### Code & CLI Validation

Static review only; no Azure calls executed.

- Bicep Template A matches the official sample in substance and is correctly labeled adapted.
- Bicep Template B is structurally valid Bicep and uses current API versions. The `sku.name: 'GlobalStandard'`, model names, and versions match the checked model availability page for East US 2.
- Azure CLI commands are well-formed for resource group creation, group deployment, Cognitive Services model deployment creation/show, role assignment, and cleanup.
- PowerShell examples are plausible Az cmdlet equivalents.
- Python setup now uses the official `AIProjectClient` + `DefaultAzureCredential` + `get_openai_client()` pattern. No obvious syntax errors found in the visible examples.

No blocking code or CLI issues found.

### Reference List Integrity

No blocking issues. The previously missing Foundry model regional availability reference is now present and used in the body.

🟢 Minor nice-to-have: the header says "16 Microsoft Learn pages," while the reference list appears to contain 15 standard Microsoft Learn documentation entries plus 3 Azure template reference entries in a separate section. This count/category ambiguity should be cleaned up in a future edit, but it does not affect the report's technical readiness.

### Report Structure & Completeness

No material issues. The report retains the expected template sections: Overview, Key Concepts, Getting Started, Core Usage, Configuration & Best Practices, Advanced Topics, Pricing/Limits/Quotas, Research Limitations, and Complete Reference List. Quotes and code/source attributions are inline rather than collected at the end.

### Consistency & Contradictions

No blocking contradictions found.

- Region/model recommendation is consistent across the Executive Summary, Section 3 Bicep, Section 6 matrix, and limitations.
- The report aligns with the stated project conclusion: **East US 2 + `gpt-5.5` + `gpt-5.4-mini`**.
- West US 2 is consistently excluded.
- A2A is consistently described as Preview.
- RBAC old/new names are consistently mapped.

The target report matches the model-availability companion's core conclusion and the Foundry Agents companion report's recommendation: **East US 2 + `gpt-5.5` + `gpt-5.4-mini`**.

### Suggested Improvements (Prioritized)

1. Add a one-line note beside Template B and Python/CLI examples clarifying that callers pass the **deployment name** to `model=...`; either align deployment names with model IDs or explain the intentional difference.
2. Fix the source-count/category ambiguity in the header: either count Azure template references as Microsoft Learn pages or list them separately.
3. Add explicit access dates to the Workflow and Foundry Rollout planning references.
4. Consider adding an explicit note that Global Standard is the deployment type used for the final Zava recommendation, so any Data Zone/Provisioned matrix details are advisory rather than part of the deployment decision.

## Readiness Verdict: APPROVED

**Verdict:** APPROVED

All Round 1 🔴 Critical / 🟡 Important must-fix issues are resolved. Remaining items are 🟢 Minor nice-to-have cleanup only and do not block use of the report for the Zava Foundry V2 deployment plan.
