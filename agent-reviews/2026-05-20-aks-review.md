---
reviewer: ms-docs-research-reviewer
subject: AKS — basics in 2026, Bicep deployment, ingress/public endpoint, workload identity, image build+push, observability, security defaults, cost estimate
companion: ms-docs-researcher
date: 2026-05-21
verdict: NEEDS REWORK
---

## Review Round 1 — 2026-05-21

## Reference Validation

10 of 22 listed URLs were checked: AKS pricing tiers, supported Kubernetes versions, managedClusters `2026-02-01`, application routing, ingress concepts, workload identity overview, workload identity deployment, ACR quick task, AKS monitoring enablement, and the AKS Bicep quickstart.

Results: all checked URLs were reachable and official Microsoft/Azure sources. The key citations are mostly relevant. The `2026-02-01` managedClusters page exists and documents `ingressProfile.webAppRouting`, `oidcIssuerProfile`, and `securityProfile.workloadIdentity`. The monitoring page explicitly has Bicep/ARM coverage for Prometheus and Container Insights, but the report only links to an external sample for Managed Prometheus rather than showing a Bicep snippet.

## Claim Citation Coverage

Several key claims lack adequate citation or verbatim quote support:

- 🟡 Important (must-fix) — Section 2.3 claims `Standard_D2s_v5` is the recommended current-generation starter SKU and costs about `$0.096/hour`; this is central to sizing/cost but has no verbatim pricing quote or direct SKU-specific official evidence.
- 🟡 Important (must-fix) — Section 4.2 says Application Routing is “free (no extra Azure resource cost)” while the architecture still creates/uses a Standard Load Balancer and likely a public IP. This needs a clearer source-backed statement and must not imply the public endpoint has no Azure networking cost.
- 🟡 Important (must-fix) — Section 9 cost values are sourced only by links/notes, not by quoted current pricing evidence. The report also acknowledges the VM price could not be extracted, which leaves a critical requested requirement unresolved.
- 🟡 Important (must-fix) — Section 10 states `kubenet (default)` and `Azure Linux 3.0` as defaults without a citation or quote. These defaults materially affect deployability and should be verified or removed.
- 🟡 Important (must-fix) — Section 8.5 recommends auto-upgrade but the command block lacks immediate post-block source attribution/provenance.

## Quote Verification

12 important quotes were spot-checked. Most checked quotes are present or close on the cited pages: AKS pricing tiers; AKS 12-month GA support; Azure Linux 2.0 end of support; application routing recommendation; application routing NGINX features; November 2026 support statement; workload identity overview; required pod label; DefaultAzureCredential usage; ACR Tasks; Dockerfile compatibility; monitoring overview.

Findings:

- 🟡 Important (must-fix) — Section 5.1 quote “Workload ID covers the pod-to-Azure identity scenario...” is not verbatim as written. The official page says pods authenticate to “Microsoft Entra–protected services”; the report changes wording to “other Azure services.” Fix or mark as paraphrase.
- 🟢 Minor (nice-to-have) — Section 5.5 quote about `DefaultAzureCredential` omits the official sentence’s Key Vault context. Not misleading, but should be exact if presented in quotation marks.

## Source Officialness

No unofficial sources were found. Microsoft Learn, Azure pricing pages, and the Azure-Samples GitHub repository are official enough for this report. The pricing pages are official Azure pages, but they are not Microsoft Learn pages and should be counted separately.

## Technical Accuracy

- 🔴 Critical (must-fix) — Section 4.5 says that for a demo with no custom domain, “you can skip TLS and use plain HTTP to the external IP (with a shared-secret header for auth).” A public endpoint carrying a shared secret over HTTP is not an appropriate security default. For this A2A demo, require HTTPS/TLS or a private/allow-listed path; do not recommend plaintext HTTP with secrets.
- 🟡 Important (must-fix) — Section 2.2 lists Kubernetes `1.32` as a supported GA version in mid-2026. The checked AKS version page shows `1.32` EOL in March 2026 with platform support only until `1.36` GA. By the report date, it should not be presented as a normal supported GA starter option.
- 🟡 Important (must-fix) — Executive Summary says the demo costs roughly `$3–6/day`, but Section 9 calculates `$8.14/day` for the recommended 2-node setup and `$5.83/day` for 1 node. Align the recommendation and cost math.
- 🟡 Important (must-fix) — Section 5.2 uses `Cognitive Services OpenAI User` as the role for Foundry access, while Section 11 says Foundry-specific RBAC was not verified. Because the project context requires AKS-to-Foundry communication, this must be clearly scoped as “Azure OpenAI example only” or verified for the actual Foundry Agents/Responses endpoint.
- 🟢 Minor (nice-to-have) — Section 4.4 includes `spec.ingressClassName` under Ingress annotations. The actual field is already correctly set under `spec.ingressClassName`; remove the misleading annotation.

## Source Freshness & Currency

The managedClusters API version and Application Routing retirement/support timeline were verified as current on checked Microsoft pages. However:

- 🟡 Important (must-fix) — Kubernetes version currency needs correction for `1.32` and clearer guidance to use `az aks get-versions` at deployment time.
- 🟡 Important (must-fix) — Observability guidance should reflect the current Azure Monitor page’s Bicep/ARM path for Prometheus and Container Insights instead of only using the older `omsagent` add-on snippet plus a sample link.

## Topic Coverage Assessment

The report covers the requested areas, but not all at the required depth:

- 🟡 Important (must-fix) — Observability requirement is incomplete. The user explicitly asked for Container Insights / managed Prometheus shown with Bicep snippet. Container Insights appears in the main Bicep, but Managed Prometheus is only a CLI command plus a sample link.
- 🟡 Important (must-fix) — Security defaults need stronger public endpoint guidance: require TLS, shared-secret/HMAC validation, and preferably source restriction where feasible. “Plain HTTP with shared secret” must be removed.
- 🟡 Important (must-fix) — Cost estimate must include source-backed math and reconcile control plane, node, Load Balancer/public IP, ACR, and Log Analytics assumptions.
- 🟢 Minor (nice-to-have) — Prerequisites are scattered; a short “minimum permissions/resource providers/tools” subsection would make deployment steps more actionable.

## Code & CLI Validation

Bicep, YAML, Python, KQL, Azure CLI, and PowerShell snippets are generally syntactically plausible by inspection. No code was executed.

Findings:

- 🟡 Important (must-fix) — The Managed Prometheus Bicep snippet is missing despite the requirement.
- 🟡 Important (must-fix) — The auto-upgrade CLI block lacks post-block source/provenance attribution.
- 🟢 Minor (nice-to-have) — The Python snippet is illustrative but commented-out for the Azure OpenAI/Foundry client. If retained, either provide a real current Python example or explicitly say SDK client construction is out of scope.

## Reference List Integrity

- 🟡 Important (must-fix) — Header source counts do not match the reference list. The header says “18 Microsoft Learn pages, 2 GitHub repositories, 1 code sample.” The list has 18 Microsoft Learn documentation items, 2 Azure pricing pages, and only 1 GitHub repository plus 1 Learn code sample. Correct the counts/categories.
- 🟢 Minor (nice-to-have) — The “Pricing Pages” section is useful, but the header should explicitly include pricing pages as official Azure sources.

## Report Structure & Completeness

The report has the expected major sections, inline quotes, source links, and a complete reference list. However, it does not fully meet the project-specific critical verification bar because several key claims are not supported by verbatim official quotes, and one security recommendation is unsafe.

## Consistency & Contradictions

- 🟡 Important (must-fix) — Cost estimates conflict between the Executive Summary (`$3–6/day`) and Section 9 (`$8.14/day` for 2 nodes).
- 🟡 Important (must-fix) — The report says Application Routing has no extra Azure resource cost while Section 9 correctly includes Load Balancer cost.
- 🟡 Important (must-fix) — Section 5 presents a Foundry/OpenAI role assignment pattern, but Section 11 says Foundry-specific RBAC was not verified.

## Suggested Improvements (Prioritized)

1. Remove the plaintext HTTP recommendation; require HTTPS/TLS for any public endpoint carrying shared secrets or HMAC material.
2. Fix Kubernetes version guidance: remove `1.32` as a normal supported GA option and cite the AKS release calendar/default-version behavior.
3. Rework the cost estimate with current official pricing references, quotes, and consistent 1-node/2-node math.
4. Add a Bicep snippet for Managed Prometheus/Azure Monitor profile or explicitly limit the demo to Container Insights with a reason.
5. Verify and source the actual role/RBAC pattern for the AKS workload calling the intended Foundry endpoint, or clearly label the Azure OpenAI role as an example only.
6. Correct reference counts/categories and quote/paraphrase formatting.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

Blockers: unsafe public HTTP guidance, stale/inaccurate Kubernetes version framing, incomplete observability Bicep coverage, unresolved current pricing evidence/math, insufficient citation/quote support for key claims, and reference count inconsistencies.

## Review Round 2 — 2026-05-20

### Fix Verification

1. **Unsafe HTTP recommendation removed (HIGH): PARTIALLY RESOLVED — ⚠️ partially fixed.** Section 4.4 and 8.1 now require HTTPS/TLS and the plaintext HTTP recommendation is gone. However, Section 4.4 recommends a self-signed certificate and says disabling certificate verification on the client is acceptable. That is not an acceptable public-endpoint demo posture for an external customer. The report also does not show the requested managed/automated certificate path (Application Routing + cert-manager/real domain, or Application Gateway for Containers + cert-manager/Let's Encrypt). Official docs support Application Routing TLS with Key Vault and Application Gateway for Containers with cert-manager/Let's Encrypt; the report should steer to a CA-issued cert path, not disabled verification.
2. **Kubernetes version (HIGH): RESOLVED — ✅ fixed.** Section 2.2 now clearly states 1.32 reached EOL in March 2026, recommends 1.34/1.35, and tells readers to run `az aks get-versions` at deployment time. This matches the AKS supported versions/release calendar guidance.
3. **Cost math reconciliation (HIGH): RESOLVED — ✅ fixed.** Executive Summary and Section 9 now use one coherent estimate: 1 node ≈ $4.21/day, 2 nodes ≈ $6.51/day, rounded in the summary to $5–8/day. Section 9 includes line items for nodes, Load Balancer, public IP, ACR, Log Analytics, and Key Vault.
4. **Standard_D2s_v5 sizing claim (HIGH): PARTIALLY RESOLVED — ⚠️ partially fixed.** Section 2.3 softened the claim from “recommended current-generation starter SKU” to “reasonable current-generation choice,” but the 2 vCPU/8 GiB and current-generation statements still lack a direct VM-size reference. The price remains approximate from the calculator and not directly cited to a SKU-specific official table.
5. **Application Routing “free” claim (HIGH): RESOLVED — ✅ fixed.** Section 4.1/4.2 now says “No add-on charge” and explicitly notes Standard Load Balancer and public IP are billed separately.
6. **Managed Prometheus Bicep snippet (HIGH): PARTIALLY RESOLVED — ⚠️ partially fixed.** Section 3.3 adds an `azureMonitorProfile.metrics` snippet and cites the managedClusters API reference. However, it also says full end-to-end Prometheus requires DCR/DCE/Azure Monitor workspace resources and only links out to a sample. For a project expectation of “Bicep + managed Prometheus,” this remains incomplete unless the report clearly marks Prometheus as optional and not part of the recommended deployment.
7. **Defaults claims (HIGH): RESOLVED — ✅ fixed.** The unsupported `kubenet`/Azure Linux 3.0 default claims were removed. Section 10 now cites Ubuntu default and Azure CNI Overlay default; both spot-check against Microsoft Learn.
8. **Foundry RBAC for AKS → Foundry calls (HIGH): PARTIALLY RESOLVED — ⚠️ partially fixed.** Section 5.2 now scopes `Cognitive Services OpenAI User` to Azure OpenAI direct calls and points readers to Foundry V2 research for Foundry Agents/Responses. The companion Foundry V2 report verifies **Foundry User** and explicitly says not to use Cognitive Services roles for Foundry scenarios. This AKS report should name that verified role or add a direct cross-reference, because the Zava project specifically calls Foundry Agents/Responses from AKS.
9. **Quote accuracy (HIGH): RESOLVED — ✅ fixed.** The Workload ID quote in Section 5.1 now matches the official wording about pod-to-Azure identity and Microsoft Entra-protected services.
10. **Auto-upgrade command provenance (MEDIUM): RESOLVED — ✅ fixed.** Section 8.6 now includes post-block source attribution to the AKS auto-upgrade documentation.
11. **`spec.ingressClassName` misplacement (LOW): RESOLVED — ✅ fixed.** The Ingress YAML now places `ingressClassName` under `spec`, not under annotations.
12. **Reference list integrity (LOW): UNRESOLVED — ❌ not fixed.** The header says “18 Microsoft Learn pages, 3 Azure pricing pages, 1 GitHub repository, 1 code sample.” The reference list has 20 Microsoft Learn documentation items, 5 Azure pricing pages, and 2 GitHub/code-sample entries grouped together. Counts and categories still do not match.
13. **Python snippet (LOW): RESOLVED — ✅ fixed.** Section 5.5 now provides a real `DefaultAzureCredential` token acquisition example and explicitly marks Foundry/Azure OpenAI SDK client construction out of scope.

## Reference Validation

12 of 27 listed URLs were spot-checked, prioritizing the Round 1 must-fixes: AKS supported versions, Application Routing TLS/custom domain, managedClusters `2026-02-01`, Azure Monitor AKS monitoring enablement, Azure CNI Overlay, AKS core concepts, AKS auto-upgrade, Workload Identity overview, Foundry RBAC, Application Gateway for Containers cert-manager search result, and Azure pricing pages for AKS/networking/monitoring. Checked sources are official Microsoft Learn, Azure pricing, or Azure-Samples/Microsoft properties. No fabricated sources found.

## Claim Citation Coverage

Most major revised claims are now cited. Remaining material gaps:

- 🟡 Important (must-fix) — Section 4.4’s “self-signed certificate warning … acceptable … when certificate verification is disabled” is unsupported and unsafe for the stated external-customer public endpoint.
- 🟡 Important (must-fix) — Section 2.3 still lacks direct official evidence for `Standard_D2s_v5` sizing/current-generation status.
- 🟡 Important (must-fix) — Section 5.2 does not directly cite the companion Foundry RBAC finding that Foundry scenarios should use Foundry roles, not Cognitive Services roles.

## Quote Verification

Key changed quotes were spot-checked. The Workload ID quote, AKS default version quote, Ubuntu default quote, Azure CNI Overlay default quote, Application Routing TLS/Key Vault text, and Foundry RBAC “don’t assign Cognitive Services roles” quote were present or substantially exact on official Microsoft Learn pages. No new quote fabrication found.

## Source Officialness

No unofficial sources were found. The report cites Microsoft Learn, Azure pricing pages, and Azure-Samples/Microsoft GitHub content. Azure pricing pages are official Azure sources but should be counted separately from Microsoft Learn documentation.

## Technical Accuracy

- 🔴 Critical (must-fix) — The report no longer recommends plain HTTP, but Section 4.4 still normalizes disabling certificate verification for a public A2A endpoint. For this Zava demo, HTTPS must mean trusted TLS with a real hostname/CA-issued or otherwise trusted certificate path.
- 🟡 Important (must-fix) — Managed Prometheus Bicep is only partial. `azureMonitorProfile.metrics.enabled` is accurate, but the report itself admits the full DCR/DCE/workspace wiring is omitted.
- 🟡 Important (must-fix) — Foundry RBAC remains too indirect for AKS-to-Foundry calls. The companion Foundry V2 research verifies `Foundry User` and warns against Cognitive Services roles for Foundry scenarios; this report should reflect that.

## Source Freshness & Currency

Kubernetes version guidance is current and now points to deployment-time verification. Auto-upgrade provenance is current. Application Routing NGINX support-through-November-2026 language remains consistent with the current AKS ingress docs.

## Topic Coverage Assessment

Coverage is substantially improved. The remaining coverage gap is public TLS architecture: the report should present a trusted certificate path suitable for a public endpoint, such as Application Routing with Key Vault + CA-issued certificate/real DNS, or Application Gateway for Containers with cert-manager/Let's Encrypt. The current self-signed/disable-verification path is not enough for an external technical stakeholder demo.

## Code & CLI Validation

Snippets are syntactically plausible by inspection. The Ingress `secretName` pattern now matches the Application Routing Key Vault TLS documentation. Azure CLI blocks have post-block source/provenance where most important. The Python snippet is syntactically valid and appropriately scoped.

## Reference List Integrity

🟡 Important (must-fix) — Still inaccurate. Actual listed references are 20 Microsoft Learn documentation items, 5 Azure pricing pages, and 2 GitHub/code-sample entries. The header says 18, 3, 1, and 1 respectively. Fix the header or split the final section into categories whose counts match.

## Report Structure & Completeness

The report has the expected sections, inline quotes, code snippets with attribution, limitations, and a complete reference list. Structure is acceptable apart from the reference count/category mismatch.

## Consistency & Contradictions

- 🟡 Important (must-fix) — “HTTPS/TLS mandatory” conflicts with the recommendation that certificate verification can be disabled for the self-signed certificate.
- 🟡 Important (must-fix) — The report title/Section 5 imply AKS-to-Foundry auth, while the only concrete role assignment remains Azure OpenAI-specific.

## Suggested Improvements (Prioritized)

1. Replace the self-signed/disable-verification guidance with a trusted TLS path: DNS hostname + CA-issued cert via Application Routing/Key Vault, or Application Gateway for Containers + cert-manager/Let's Encrypt.
2. Add a direct cross-reference to the companion Foundry V2 RBAC result and name `Foundry User` for Foundry Agents/Responses data-plane access; keep `Cognitive Services OpenAI User` only as an Azure OpenAI direct-call example.
3. Either add official VM-size evidence for `Standard_D2s_v5` or further soften the sizing language to “example SKU; verify with VM sizes/pricing calculator.”
4. Decide whether Managed Prometheus is in-scope for the recommended deployment. If yes, include the Azure Monitor workspace/DCR/DCE Bicep path; if no, mark it optional and explain Container Insights is the default.
5. Fix source counts/categories in the header and reference list.

## Readiness Verdict: NEEDS REWORK

Blockers: trusted TLS guidance remains incomplete/unsafe for a public endpoint, Foundry RBAC is still indirect for the actual AKS-to-Foundry scenario, Managed Prometheus Bicep remains partial, `Standard_D2s_v5` evidence is incomplete, and reference counts/categories are still inconsistent.

## Review Round 3 — 2026-05-20

### Fix Verification

1. **🔴 Critical — Trusted TLS architecture (HIGH): RESOLVED — ✅ fixed.** Sections 4.4 and 8.1 now require HTTPS with a trusted CA-issued certificate for public endpoints. The main path is Application Routing + Azure Key Vault + Azure DNS + CA-issued certificate, with Bicep resources for Key Vault/DNS and Kubernetes Ingress using `kubernetes.azure.com/tls-cert-keyvault-uri`. The remaining `verify=False` mention is explicitly framed as a security anti-pattern and not a recommendation; no `--insecure-skip-tls-verify` guidance remains.
2. **🟡 Important — Foundry RBAC for AKS→Foundry (HIGH): RESOLVED — ✅ fixed.** Section 5.2 now names `Foundry User` as the primary role for AKS Workload Identity calls to Foundry Agents V2 / Responses API, cites the Foundry RBAC page, uses the role GUID in CLI/Bicep, and scopes `Cognitive Services OpenAI User` only to the alternative direct Azure OpenAI v1 endpoint path.
3. **🟡 Important — Managed Prometheus Bicep (HIGH): RESOLVED — ✅ fixed.** Sections 3.3, 7.3, 10, and 11 explicitly mark Managed Prometheus as optional and excluded from the recommended demo deployment, with Container Insights + Log Analytics as the default Bicep-enabled observability path. This satisfies the Round 2 requirement to either provide complete Prometheus Bicep or make it optional with Container Insights as default.
4. **🟡 Important — Standard_D2s_v5 sizing evidence (HIGH): RESOLVED — ✅ fixed.** Section 2.3 now cites the official Dsv5 size-series page for `Standard_D2s_v5` 2 vCPU / 8 GiB evidence and clearly treats pricing as an approximate calculator estimate to verify before deployment. The unsourced cost claim has been softened enough for a feasibility research artifact.
5. **🟡 Important — Reference list integrity (HIGH): RESOLVED — ✅ fixed.** The header now states 23 Microsoft Learn pages, 5 Azure pricing pages, 1 GitHub repository, and 1 code sample. The reference list contains 23 Microsoft Learn documentation entries, 5 Azure pricing entries, and a combined GitHub/code-sample section with exactly one of each.
6. **🟡 Important — Consistency contradiction (HIGH): RESOLVED — ✅ fixed.** Section 5 is now consistently Foundry-scoped: the header, prose, CLI, Bicep, recommended configuration, and pitfalls all use `Foundry User` for Foundry Agents/Responses access.

## Reference Validation

8 of the most relevant URLs were spot-checked or rechecked for Round 3: Application Routing TLS/DNS/Key Vault, Foundry RBAC, AKS Workload Identity, managedClusters `2026-02-01`, AKS monitoring enablement, Dsv5 VM sizes, AKS ingress concepts, and Key Vault CA integration. Checked sources are official Microsoft Learn pages or official Azure pricing/sample pages. No fabricated or unofficial sources were found.

## Claim Citation Coverage

No material must-fix gaps remain. The high-stakes claims added for Round 3 — trusted TLS via Key Vault/DNS, Foundry User role guidance, optional Managed Prometheus, and Dsv5 sizing — now have direct source links near the relevant sections.

## Quote Verification

Key Round 3 quotes were spot-checked against official Microsoft Learn content. The Application Routing page contains the self-signed certificate warning and Key Vault/DNS ingress pattern. The Foundry RBAC page contains the `Foundry User` role, role rename note/GUID guidance, and warning not to use Cognitive Services roles for Foundry scenarios. The Dsv5 page contains the `Standard_D2s_v5` 2 vCPU / 8 GiB table. No quote fabrication found.

## Source Officialness

No material issues. The report uses Microsoft Learn, official Azure pricing pages, and Azure-Samples/Microsoft code sample sources.

## Technical Accuracy

No blocking technical accuracy issues remain. Trusted TLS is now the public-endpoint architecture, Foundry RBAC is aligned with the project context, and Managed Prometheus is no longer presented as partially implemented default Bicep.

## Source Freshness & Currency

No material issues. The report continues to note AKS version rotation and deployment-time verification with `az aks get-versions`. The Application Routing NGINX support-through-November-2026 caveat remains current in the cited AKS ingress docs.

## Topic Coverage Assessment

Coverage is sufficient for the Zava demo implementation. The report covers AKS basics, Bicep deployment, public HTTPS ingress, Workload Identity to Foundry, image build/push, observability, security defaults, and cost estimate. Managed Prometheus is intentionally out of the default path and documented as optional.

## Code & CLI Validation

Snippets are syntactically plausible by inspection. The TLS Ingress manifest matches the Application Routing Key Vault pattern. CLI role assignment uses the Foundry User GUID as recommended during the role rename rollout. No execution was performed.

## Reference List Integrity

No material issues. Header counts match the actual list contents: 23 Microsoft Learn documentation pages, 5 Azure pricing pages, 1 GitHub repository, and 1 code sample.

## Report Structure & Completeness

No material issues. The report has the expected sections, inline source attribution, code/CLI snippets, limitations, and a complete reference list.

## Consistency & Contradictions

No blocking contradictions remain. The public endpoint guidance is consistently trusted TLS; Foundry access is consistently `Foundry User`; Container Insights is consistently the default observability option with Managed Prometheus optional.

## Suggested Improvements (Prioritized)

1. 🟢 Minor (nice-to-have) — If this becomes the final deployment spec, convert the Foundry role-assignment Bicep `scope` string into an `existing` Foundry account resource reference to avoid deployment-language ambiguity.
2. 🟢 Minor (nice-to-have) — Consider splitting the combined “GitHub Repositories / Code Samples” reference section into two subsections for exact template alignment, though the counts are now correct.
3. 🟢 Minor (nice-to-have) — Add a short note that the real DNS domain must be registered/delegated before Azure DNS can serve `ops-agent.zava-demo.example.com` publicly.

## Readiness Verdict: APPROVED

All prior 🔴 Critical and 🟡 Important must-fix items are resolved. Remaining items are 🟢 Minor nice-to-haves and are waived for readiness.
