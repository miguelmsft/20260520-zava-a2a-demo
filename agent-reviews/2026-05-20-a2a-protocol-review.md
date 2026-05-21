---
reviewer: web-research-reviewer
subject: A2A (Agent-to-Agent) protocol research report
companion: web-researcher
date: 2026-05-20
verdict: APPROVED
---

## Review Round 1 — 2026-05-20

## Reference Validation

Checked 25 of approximately 36 cited URLs, prioritizing protocol, SDK, Foundry, LangGraph, security, and governance sources.

- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md` — reachable; verifies the open-standard definition, v1.0.0, normative `spec/a2a.proto`, task streaming patterns, versioning, and security requirements.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/specification/a2a.proto` — reachable; verifies task states, `AgentInterface`, `AgentCard`, `Part`, `Message`, and HTTP+JSON endpoint mappings.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/index.md` — reachable; verifies “Originally developed by Google and now donated to the Linux Foundation.”
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/announcing-1.0.md` — reachable; verifies v1.0 release, TSC, and A2A/MCP quote.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/whats-new-v1.md` — reachable; verifies v1.0 breaking changes, `SendMessage`, `SendStreamingMessage`, OAuth changes, Agent Card changes.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/enterprise-ready.md` — reachable; verifies TLS, HTTP-layer identity, headers, and server-side validation.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/agent-discovery.md` — reachable; verifies well-known URI discovery.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/life-of-a-task.md` — reachable; verifies terminal task immutability.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/a2a-and-mcp.md` — reachable; verifies complementarity with MCP.
- `https://github.com/a2aproject/a2a-python` — reachable; verifies `a2a-sdk`, extras, and v1.0/v0.3 compatibility matrix.
- `https://github.com/a2aproject/a2a-js` — reachable; verifies `@a2a-js/sdk`, stable v0.3, and v1.0 alpha via `@next`.
- `https://github.com/a2aproject/a2a-go`, `a2a-dotnet`, `a2a-java`, `a2a-rs` — reachable; verify SDK existence, but the report’s reference list omits `a2a-rs`.
- `https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/agent-types/a2a-agent` — reachable; verifies Microsoft Agent Framework A2A server exposure and Python `agent-framework-a2a` client/expose examples.
- `https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/azureaifoundry_sdk/README.md` — reachable; verifies Azure AI Foundry Agent Service samples with A2A.
- `https://docs.langchain.com/langsmith/server-a2a` — reachable; verifies LangSmith `/a2a/{assistant_id}` and v0.3-style methods.
- `https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/` — reachable; verifies ACP merging into A2A under the Linux Foundation umbrella.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md` and `partners.md` — reachable; verify integrations and partners.

Findings:

- 🟡 Important (must-fix) — Reference List Integrity / body citations: several cited resources are absent from the Complete Reference List, including `a2a-rs`, A2A TCK, A2A ITK, Google Cloud blog, Google Developers blog, Microsoft Cloud blog, DeepLearning.AI course link, LinkedIn Semantic Kernel citation, and some raw-topic pages. This weakens traceability.
- 🟢 Minor (nice-to-have) — The report cites the Microsoft Cloud blog while also stating it was unreachable during research. That uncertainty is disclosed, so it is acceptable, but the reference list should label it “unverified during research” if retained.

## Claim Citation Coverage

Most major A2A spec, SDK, and governance claims have citations. However, several high-stakes claims need stronger source treatment.

Findings:

- 🟡 Important (must-fix) — Framework support / OpenAI Agents SDK: Section 7.5 says no built-in A2A support was found, but provides no clickable source URLs for the OpenAI Agents SDK package/docs, the searched repository, or search evidence. Negative framework-support claims are important for architecture decisions and need explicit evidence.
- 🟡 Important (must-fix) — Auth/security / CORS: Section 5.4 says “CORS is not explicitly specified in the A2A protocol” with no source quote or source URL. Because CORS is explicitly listed in the review brief, the report must either quote the spec/enterprise docs showing the absence/scope, or clearly mark it as reviewer inference from the current spec.
- 🟡 Important (must-fix) — Foundry Agents V2 support: The Executive Summary states that “Microsoft Foundry Agents V2 can expose A2A endpoints via the Microsoft Agent Framework” as a settled fact, while Section 10 says no dedicated Foundry V2 A2A docs were found and portal-native support is unclear. The body does cite Microsoft Agent Framework and a2a-samples, but the report needs tighter wording: A2A is supported via adapter/wrapper libraries and samples, not verified as native Foundry V2 platform A2A unless an official Foundry service page says so.
- 🟢 Minor (nice-to-have) — Some bullets in “Why It Matters,” “Common Interop Pitfalls,” and “Error Handling Gotchas” are plausible and mostly derived from the cited spec, but they would be more auditable with inline links on each bullet.

## Quote Verification

Verified key quotes against fetched sources:

- A2A definition quote — verified in the spec.
- “Originally developed by Google…” — verified in docs index.
- “Latest Released Version 1.0.0” — verified in spec.
- “v1.0 release represents…” — verified in `whats-new-v1.md`.
- TSC quote — verified in `announcing-1.0.md`.
- Normative proto quote — verified in spec §1.4.
- Task immutability quote — verified in `life-of-a-task.md`.
- Agent Card definition quote — verified in spec terminology.
- HTTP-layer identity quote — verified in `enterprise-ready.md`.
- Production HTTPS/TLS quote — verified in spec and enterprise docs.
- A2A/MCP quotes — verified in announcement and A2A/MCP topic page.
- Azure AI Foundry sample quote — verified in sample README.
- Microsoft Agent Framework quote — verified in Learn page.
- LangSmith quote — verified in LangSmith docs.
- Helloworld security disclaimer quote — verified in sample README.

Findings:

- 🟡 Important (must-fix) — Some key technical sections provide only “Source:” lines with no verbatim quote, notably task-state table, security schemes table, content/part types, LangGraph sample, LangChain support, and community integration list. The user explicitly required every key claim to have a verbatim quote and clickable URL. Add short inline quotes for these high-value technical claims or clarify that tables are directly transcribed from `a2a.proto`.
- 🟢 Minor (nice-to-have) — Several source-only blockquotes (`> — Source: ...`) are formatted as blockquotes but are not quotes. Prefer normal citation lines or add quoted text.

## Source Authority Compliance

The report relies primarily on authoritative sources: A2A official docs/spec/proto, `a2aproject` repositories, Microsoft Learn, LangChain docs, LF AI blog, and official samples. Community/social sources are limited and mostly supplemental.

Findings:

- 🟢 Minor (nice-to-have) — The Semantic Kernel support citation relies on LinkedIn via the A2A community page. Since Semantic Kernel is Microsoft-owned, an official Microsoft Learn, GitHub, or Semantic Kernel repo source would be stronger if this claim matters.

## Conflict & Uncertainty Disclosure

The report includes a useful Research Limitations section and correctly flags uncertainty around Foundry V2 native A2A support and OpenAI Agents SDK support.

Findings:

- 🟡 Important (must-fix) — Foundry support uncertainty is disclosed too late and conflicts with stronger wording in the Executive Summary and Section 7.1. For this project, whether Foundry Agents V2 can be an A2A server/client natively or only through adapter code is a potential blocker. The uncertainty must be surfaced in the Executive Summary and the framework table, with explicit “server/client/both” and “native/platform vs adapter/wrapper” labels.
- 🟡 Important (must-fix) — LangSmith/LangGraph support uses v0.3 method names; the report notes this, but should more clearly state interoperability implications for a v1.0 demo and whether the official LangGraph standalone sample is v0.3 or v1.0.

## Source Freshness & Currency

Most sources are current official docs or 2025 A2A project materials and are appropriate for a 2026-05-20 research report. The report correctly notes JS v1.0 alpha status and SDK parity limitations.

Findings:

- 🟢 Minor (nice-to-have) — Microsoft Cloud blog dated 2025-05-07 is just outside a strict “past 12 months” window as of 2026-05-20 and was not independently verified. It should be marked stale/unverified if used.
- 🟢 Minor (nice-to-have) — Repository pages do not always expose publication dates. For version-sensitive SDK claims, include release/tag/package dates where available.

## Topic Coverage Assessment

The report covers origin/governance, wire protocol, SDKs, auth/security, A2A vs MCP, framework support, examples, caveats, and limitations. It is broadly useful for the Zava A2A demo.

Findings:

- 🟡 Important (must-fix) — Foundry Agents V2 coverage is not sufficient for the project decision. It must clearly answer: can Foundry-backed agents act as A2A servers, A2A clients, or both; is support native to Foundry Agents V2 or provided by Microsoft Agent Framework / Python `a2a-sdk` wrappers; and what is officially documented versus sample-demonstrated.
- 🟢 Minor (nice-to-have) — The project context also requires model availability/RBAC/private VNet research elsewhere. If this report is intended to be the only A2A/Foundry source, add explicit scope boundaries saying those topics are out of scope here.

## Research Limitations Review

The Research Limitations section exists and is mostly honest. It acknowledges Foundry V2 native A2A uncertainty, OpenAI negative-evidence limits, Microsoft blog reachability, task-state source constraints, and SDK parity gaps.

Findings:

- 🟡 Important (must-fix) — The Foundry limitation must be promoted from limitations into the Executive Summary and Section 7.1 because it directly affects the architecture.
- 🟢 Minor (nice-to-have) — Add a limitation for strict source freshness: some cited announcements are close to or outside the past-12-month window.

## Code & CLI Validation

Static validation performed:

- Parsed both Python code blocks with `python` `ast.parse`; both are syntactically valid.
- Verified Python package/import paths against the official `a2a-python` README and helloworld sample: `a2a-sdk`, `a2a.client`, `a2a.server.request_handlers`, `a2a.server.routes`, `a2a.server.tasks`, `a2a.types`, and `a2a.types.a2a_pb2` are current in the cited samples.
- Verified JS package name `@a2a-js/sdk` and `@a2a-js/sdk@next` against the official JS README.
- Verified Microsoft Agent Framework package names and `MapA2A` example against Microsoft Learn.

Findings:

- 🟢 Minor (nice-to-have) — The “Minimal A2A Server” Python snippet imports `HelloWorldAgentExecutor` from a local file that is not included, so it is syntactically valid but not fully copy-paste runnable. Add a note that it is a skeleton excerpt and link to the full sample.
- 🟢 Minor (nice-to-have) — The C# snippet is a fragment, not a complete compilable example. The Learn page contains the full `Program.cs`; the report should either show the full sample or label the snippet as an excerpt.
- 🟡 Important (must-fix) — The JSON-RPC request example mixes v1.0 fields/method names (`SendMessage`, `ROLE_USER`, no `kind`) with `A2A-Version: 0.3`. The spec says clients should send `A2A-Version: 1.0` for v1.0 semantics, and empty/missing is interpreted as 0.3. This example should be corrected.

## Reference List Integrity

The report has a Complete Reference List organized by Documentation & Articles, GitHub Repositories, and Code Samples.

Findings:

- 🟡 Important (must-fix) — The header says “22 web pages, 8 GitHub repositories,” but the reference list contains 14 Documentation & Articles, 8 GitHub Repositories, and 4 Code Samples, while the body cites additional URLs not listed. Reconcile the count and list all cited sources.
- 🟡 Important (must-fix) — Body-cited sources missing from the reference list include A2A TCK, A2A ITK, `a2a-rs`, Google Cloud blog, Google Developers blog, Microsoft Cloud blog, DeepLearning.AI course, LinkedIn Semantic Kernel citation, A2A raw community/partners pages, and multiple raw topic pages.
- 🟢 Minor (nice-to-have) — The Rust SDK is mentioned in the SDK table and Executive Summary, but the GitHub reference list omits it. Add `a2aproject/a2a-rs` and package name `a2a-lf` if Rust remains in scope.

## Report Structure & Readability

The report is well-organized, readable, and has a useful table of contents. The major sections are in a logical order and support the intended demo planning work.

Findings:

- 🟢 Minor (nice-to-have) — Some source-only blockquotes should be changed to normal citation lines unless they include verbatim quoted content.
- 🟢 Minor (nice-to-have) — The Executive Summary is too confident about Foundry V2 support compared with the limitations. Align the wording.

## Suggested Improvements (Prioritized)

1. Correct the v1.0 JSON-RPC example (`A2A-Version: 1.0`) and add a short quote from the spec’s versioning section.
2. Rewrite Foundry Agents V2 support as a precise compatibility matrix: server/client/both, native/platform vs adapter/wrapper, official docs vs samples, and remaining uncertainty.
3. Add citations/evidence for the OpenAI Agents SDK negative finding.
4. Add verbatim quotes for task states, security schemes, Agent Card discovery, LangGraph/LangSmith support, and framework integration claims.
5. Reconcile the reference list and source count with all body citations.
6. Mark stale/unverified sources explicitly, especially the Microsoft Cloud blog.
7. Label code snippets as complete examples or excerpts; link to full runnable samples where snippets are abbreviated.

## Readiness verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

The report is strong overall and uses many authoritative sources, but it has unresolved must-fix issues: a mixed-version JSON-RPC example, overconfident Foundry Agents V2 claims relative to the evidence, missing evidence for OpenAI Agents SDK negative support, missing verbatim quotes for several key technical claims, and reference-list/count inconsistencies. These issues affect trustworthiness for the Zava A2A demo architecture.
## Review Round 2 — 2026-05-20

### Fix Verification

- **JSON-RPC version mismatch** — RESOLVED — ✅ fixed. The v1.0 JSON-RPC example now sends `A2A-Version: 1.0`, and Section 3.3 quotes the spec versioning rules: clients MUST send the header, and empty values are interpreted as 0.3.
- **Foundry Agents V2 compatibility matrix** — PARTIALLY RESOLVED — ⚠️ partially fixed. The Executive Summary now distinguishes A2A server, possible client, adapter/wrapper, native toggle absence, official docs vs samples, and preview status. However, it does not incorporate the project-critical constraint that Foundry's incoming A2A endpoint uses protocol 0.3, nor does it map that to the recommended Zava direction.
- **OpenAI Agents SDK negative finding** — RESOLVED — ✅ fixed. Section 7.5 now cites the OpenAI GitHub README, official docs, A2A Community Hub, and samples repo as clickable negative evidence.
- **CORS coverage** — RESOLVED — ✅ fixed. Section 5.4 clearly marks CORS as an inference from full-text searches of the A2A spec and enterprise guide, and treats CORS as HTTP server configuration.
- **Missing verbatim quotes** — PARTIALLY RESOLVED — ⚠️ partially fixed. Task states, security schemes, LangGraph/LangSmith, LangChain, and community integration evidence were added, but the Part quote/transcription is materially wrong because it omits the `data = 4` field that exists in the current normative proto.
- **Reference list integrity** — PARTIALLY RESOLVED — ⚠️ partially fixed. Many missing sources were added, but the header count still says `30 web pages, 10 GitHub repositories` while the reference list contains 22 Documentation & Articles, 12 GitHub Repositories, and 4 Code Samples.
- **LangGraph/LangSmith A2A sample version** — RESOLVED — ✅ fixed. Section 7.2 explicitly states LangSmith uses v0.3 method names and the standalone sample README shows v0.3 wire format.
- **Code snippet labeling** — RESOLVED — ✅ fixed. The Python server is labeled a skeleton excerpt and the C# sample is labeled an excerpt.
- **C# / formatting** — RESOLVED — ✅ fixed. The C# excerpt is now formatted and sourced clearly.

## Reference Validation

Checked 10 high-value URLs. Results:

- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md` — reachable; verifies v1.0.0, normative proto, operation names, A2A-Version semantics, and `VersionNotSupportedError`.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/specification/a2a.proto` — reachable; verifies TaskState, AgentInterface, AgentCard, SecurityScheme, and Part. It contradicts the report's Part transcription by including `google.protobuf.Value data = 4`.
- `https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview` — reachable; verifies Foundry Agent Service overview and the `A2A protocol (preview)` mention.
- `https://learn.microsoft.com/en-us/agent-framework/integrations/a2a` — reachable; verifies `Microsoft.Agents.AI.Hosting.A2A.AspNetCore`, prerelease package commands, Foundry package usage, `MapA2A`, and Python `agent-framework-a2a` client/server support.
- `https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/azureaifoundry_sdk/README.md` — reachable; verifies Azure AI Foundry Agent Service + A2A sample claims.
- `https://docs.langchain.com/langsmith/server-a2a` — reachable; verifies `/a2a/{assistant_id}`, `message/send`, `message/stream`, and `tasks/get` v0.3-style method names.
- `https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/langgraph` — reachable; verifies the LangGraph sample and v0.3-style wire examples.
- `https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md` — reachable; verifies LangGraph and Microsoft Agent Framework integration listings; OpenAI Agents SDK is absent.
- `https://github.com/openai/openai-agents-python/blob/main/README.md` and `https://openai.github.io/openai-agents-python/` — reachable; verify OpenAI Agents SDK concepts and no A2A mention in fetched content.
- `https://github.com/a2aproject/a2a-python` and `https://github.com/a2aproject/a2a-js` — reachable; verify Python v1.0 + v0.3 compatibility and JS stable v0.3 / v1.0 alpha status.

## Claim Citation Coverage

Most core claims are now cited. No material issue for OpenAI, CORS, or general protocol versioning. Remaining blocker:

- 🔴 Critical (must-fix) — Location: Sections 3.7 and 9.1. The report claims v1.0 replaced the `data` field with `metadata`; the current normative proto and What's New page show v1.0 `Part` still includes `data` for structured JSON. This is a cited but incorrect claim and would mislead implementation.

## Quote Verification

Spot-checked key quotes. Versioning, task-state, Foundry overview, Foundry sample, Microsoft Agent Framework, LangSmith, OpenAI negative evidence, and community integration quotes are supported by fetched sources. Blocker:

- 🔴 Critical (must-fix) — Location: Section 3.7, `message Part` blockquote. The report labels the proto transcription as verbatim but omits `google.protobuf.Value data = 4;`. Because `a2a.proto` is the normative source, this is a misquote/mistranscription.

## Source Officialness

No material issues. The report relies primarily on official A2A docs/proto, Microsoft Learn, official A2A GitHub repositories, LangChain/LangSmith docs, and OpenAI docs. The Semantic Kernel LinkedIn source is properly labeled as social media and weakly corroborated.

## Technical Accuracy

- 🔴 Critical (must-fix) — Part/content data model is wrong. v1.0 supports `text`, `raw`, `url`, and `data`; structured JSON is not only via `metadata`.
- 🟡 Important (must-fix) — Critical cross-check for Zava is not answered. The report does not clearly explain how a LangGraph A2A 1.0 server interoperates with Foundry's A2A 0.3 incoming endpoint, or the reverse where Foundry acts as the client. It should state the implementation choice: expose/consume a 0.3-compatible interface, rely on Python `a2a-sdk` compatibility mode/adapter, advertise both versions where possible, and avoid sending `A2A-Version: 1.0` to a 0.3-only Foundry endpoint.
- 🟡 Important (must-fix) — Location: Section 7.2. The recommendation says the Zava demo should target v1.0 and set `A2A-Version: 1.0`, which conflicts with the project context that Foundry's incoming A2A endpoint uses A2A protocol 0.3.

## Source Freshness & Currency

No material new freshness issues. The report appropriately marks Hosted Agents and Foundry A2A as preview, JS v1.0 as alpha, the Microsoft Cloud blog as unverified and older than 12 months, and LangSmith/LangGraph support as v0.3-style.

## Topic Coverage Assessment

Coverage is broad and substantially improved. The remaining gap is project-critical: version interop strategy for Foundry 0.3 and LangGraph/a2a-sdk 1.0/0.3 must be explicit enough to drive implementation.

## Code & CLI Validation

No execution performed; static review only. Snippet labeling is improved. The Python and C# examples are now clearly excerpts/skeletons. The main code-related blocker is not syntax but schema accuracy: the Part model example omits `data`.

## Reference List Integrity

- 🟡 Important (must-fix) — The header count still does not match the reference list. Header: `30 web pages, 10 GitHub repositories`. Listed: 22 Documentation & Articles, 12 GitHub Repositories, 4 Code Samples. Reconcile or reword the header (for example, `Sources consulted: 38 total references: 22 docs/articles, 12 repositories, 4 code samples`) if accurate.

## Report Structure & Completeness

No material structural issue. The report is well organized and significantly more useful than Round 1. The Executive Summary matrix is helpful, but must include the 0.3 Foundry endpoint constraint and the resulting interop recommendation.

## Consistency & Contradictions

- 🟡 Important (must-fix) — The report says v1.0 removes/replaces structured `data`, while the fetched v1.0 proto and What's New page include `data` in the unified Part model.
- 🟡 Important (must-fix) — The report recommends v1.0 for Zava while the project context states Foundry incoming A2A uses 0.3. This contradiction must be resolved before implementation planning.

## Suggested Improvements

1. Correct Section 3.7 to include `data = 4` and update all text saying structured data moved only to `metadata`.
2. Add a short Zava-specific interop subsection: Foundry incoming endpoint = A2A 0.3; LangGraph server can use Python `a2a-sdk` compatibility mode; specify who is client/server and which `A2A-Version` header/method names are used.
3. Update the Foundry compatibility matrix with protocol version columns and a recommended demo path.
4. Reconcile source counts in the header and reference list.

## Readiness Verdict: NEEDS REWORK

**Verdict:** NEEDS REWORK

Round 2 resolves many Round 1 issues, but still has must-fix blockers: an incorrect/misquoted v1.0 Part schema, unresolved Zava 0.3/1.0 interop guidance, and reference-count mismatch.


## Review Round 3 — 2026-05-20

### Fix Verification

- **🔴 Critical Section 3.7 Part schema (HIGH)** — RESOLVED — ✅ fixed. Section 3.7 now transcribes `message Part` with `google.protobuf.Value data = 4;` in the `oneof content` block, matching the fetched normative `a2a.proto`. The prose now correctly states that v1.0 keeps `data` for structured content and uses `metadata` separately for metadata about the part.
- **🔴 Critical Zava A2A 0.3 ↔ 1.0 interop subsection (HIGH)** — RESOLVED — ✅ fixed. Section 3.8 explicitly states that Foundry Agent Service supports A2A protocol 0.3 only, that Python `a2a-sdk` 1.0.x has 0.3 compatibility mode, that the LangGraph A2A server on AKS should be built in 0.3-compatibility mode, and that the Zava path is Foundry Agent as A2A client calling the LangGraph server.
- **🟡 Important Reference count header (MEDIUM)** — RESOLVED — ✅ fixed. The header now says `40 total references: 24 documentation & articles, 12 GitHub repositories, 4 code samples`, which matches the three reference-list categories.
- **🟡 Important Foundry compatibility matrix (MEDIUM)** — RESOLVED — ✅ fixed. The Executive Summary compatibility matrix now includes a `Protocol Version` column and shows `0.3` for the native Foundry incoming A2A server endpoint.

## Reference Validation

Checked 5 high-value URLs for the Round 3 fixes:

- `https://raw.githubusercontent.com/a2aproject/A2A/main/specification/a2a.proto` — reachable; verifies `message Part` includes `google.protobuf.Value data = 4;`, plus `metadata = 5`, `filename = 6`, and `media_type = 7`.
- `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint` — reachable; verifies incoming Foundry A2A is preview, supports A2A protocol version 0.3 only, exposes `agentCard/v0.3`, and supports HTTP+JSON and JSONRPC transports.
- `https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent` — reachable; verifies Foundry agents can call remote A2A endpoints via the A2A tool / `A2APreviewTool`.
- `https://github.com/a2aproject/a2a-python` — reachable; verifies Python `a2a-sdk` implements A2A specification 1.0 with compatibility mode for 0.3, with client and server support across transports.
- `https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview` — previously checked and still consistent with the report's Foundry A2A preview framing.

## Claim Citation Coverage

No material issues. The previously blocking Part schema and Zava interop claims are now backed by official A2A proto, Microsoft Learn, and the official Python SDK README. The Foundry 0.3 constraint is surfaced in the Executive Summary and in the Zava-specific Section 3.8.

## Quote Verification

No material issues. The Round 3 `message Part` blockquote matches the fetched `a2a.proto` for the fields relevant to the prior blocker, including `data = 4`. The Python SDK compatibility quote matches the README text: compatibility mode for `0.3`.

## Source Authority Compliance

No material issues. The resolved blockers rely on primary or official sources: A2A normative proto, Microsoft Learn Foundry docs, and the official `a2a-python` repository.

## Conflict & Uncertainty Disclosure

No material issues. The report now distinguishes Foundry's platform-native A2A 0.3 support from adapter/wrapper paths and explains the 0.3/1.0 compatibility boundary for the Zava implementation.

## Source Freshness & Currency

No material issues for the Round 3 fixes. The report date is 2026-05-20, and the key version-sensitive claims are tied to current official documentation and repository pages fetched during review.

## Topic Coverage Assessment

No material issues. The report now gives implementation-ready guidance for the Zava demo: Foundry V2 as A2A 0.3 client via `A2APreviewTool`, LangGraph on AKS as the A2A server using `a2a-sdk` 1.0.x in 0.3 compatibility mode.

## Research Limitations Review

No material issues. The limitations section now correctly scopes Foundry A2A preview support, SDK parity, LangSmith/LangGraph v0.3 concerns, and out-of-scope model/RBAC/private VNet topics.

## Code & CLI Validation

No execution performed; static review only. The v0.3 curl example in Section 3.8 is directionally appropriate for testing Foundry-compatible wire format: `message/send`, no `A2A-Version` header, v0.3 role strings, and `kind` discriminators.

## Reference List Integrity

No material issues. The header count now matches the listed categories: 24 Documentation & Articles, 12 GitHub Repositories, and 4 Code Samples, for 40 total references.

## Report Structure & Readability

No material issues. The new Section 3.8 is placed logically after wire-level Part details and before SDKs, and the Executive Summary matrix now highlights the Foundry protocol version constraint early enough for implementation planning.

## Suggested Improvements (Prioritized)

1. Optional: when implementation begins, validate the exact `a2a-sdk` compatibility-mode configuration with a local v0.3 request/response test against the LangGraph server.
2. Optional: keep Microsoft Learn links under watch because Foundry A2A is preview and protocol-version support may change.

## Readiness Verdict: APPROVED

All prior 🔴 Critical and 🟡 Important must-fix issues are resolved. Remaining suggestions are optional implementation follow-ups and do not block use of the research artifact.