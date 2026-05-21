---
reviewer: web-research-reviewer
subject: A2A use cases and common multi-agent patterns
companion: web-researcher
date: 2026-05-20
verdict: APPROVED
---

## Review Round 1 — 2026-05-20

## Reference Validation

16 of 19 listed URLs were spot-checked. Most core A2A, Anthropic, LangChain, Google, Microsoft, and GitHub sources were reachable and relevant.

- `https://github.com/a2aproject/A2A` — reachable; supports the core A2A description, SDK list, and healthcare course mention.
- `https://a2a-protocol.org/latest/` — reachable; supports Linux Foundation donation, official SDK list, Cisco agntcy reference, and A2A/MCP positioning.
- `https://a2a-protocol.org/latest/specification/` — reachable; supports v1.0.0 and protocol goals.
- `https://a2a-protocol.org/latest/topics/what-is-a2a/` — reachable; supports A2A/MCP distinction, opacity, async, and request lifecycle.
- `https://a2a-protocol.org/latest/topics/key-concepts/` — reachable; supports Agent Card, Task, Message, Part, Artifact definitions.
- `https://a2a-protocol.org/latest/topics/agent-discovery/` — reachable; supports the three discovery strategies and registry quote.
- `https://a2a-protocol.org/latest/topics/enterprise-ready/` — reachable; supports governance, security, observability, tracing, and API management quotes.
- `https://a2a-protocol.org/latest/topics/a2a-and-mcp/` — reachable; supports customer service delegation and auto-repair scenario.
- `https://a2a-protocol.org/latest/topics/life-of-a-task/` — reachable; supports task/context lifecycle, though it is listed but not used much in the body.
- `https://a2a-protocol.org/latest/tutorials/python/1-introduction/` — reachable; listed but not materially cited in the body.
- `https://github.com/a2aproject/a2a-samples` — reachable; relevant as official samples, but not materially cited in the body.
- `https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/` — reachable; supports launch, partner list, candidate sourcing, enterprise workflow claims, and date (April 9, 2025).
- `https://www.anthropic.com/engineering/building-effective-agents` — reachable; supports orchestrator-workers, prompt chaining, customer support, and anti-pattern/caution guidance.
- `https://docs.langchain.com/oss/python/langchain/multi-agent/` — reachable; supports subagents/handoffs labels, decision table, and performance tradeoffs.
- `https://blog.langchain.dev/langgraph-multi-agent-workflows/` — reachable; supports supervisor and GPT-Newspaper examples.
- `https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/` — reachable; supports Magentic-One architecture and cautionary tale.
- `https://openai.com/index/new-tools-for-building-agents/` — ⚠️ unverifiable via fetch; returned HTTP 403, so the handoff quote could not be checked.
- `https://langchain-ai.github.io/langgraph/concepts/multi_agent/` — ⚠️ unverifiable as cited; it returns only a redirect in fetch, and the likely new `docs.langchain.com/oss/python/langgraph/concepts/multi_agent` path returned 404. This is not proven fabricated, but it is not currently verifiable.

## Claim Citation Coverage

🟡 Important (must-fix): Several high-level claims in the Executive Summary are not directly cited. Location: lines 12-14. Claims such as "de facto interoperability layer," "rapidly become," "most frequently observed," and "real-world A2A deployments cluster around..." are presented as established market facts but have no inline citation or evidence. These claims matter because the report is intended to guide architecture choices for an external customer demo.

🟡 Important (must-fix): Some pattern entries cite a source URL without a verbatim supporting quote. Locations: A2A trip planning example (line 117), GPT-Newspaper (line 196), Cisco agntcy (line 228), LangGraph interrupts (line 269), and Magentic-One SWE-bench summary (line 343). The user's requirement says every key claim should have a verbatim quote and clickable source URL.

🟢 Minor (nice-to-have): The Zava fit section is logically sound but mostly uncited except for the final lifecycle quote. Add direct citations back to the earlier orchestrator-worker/subagent sources near the label recommendation.

## Quote Verification

14 body quotes were spot-checked. Most checked quotes are verbatim or close enough with minor punctuation/formatting differences:

- A2A GitHub README quote at lines 45-46 — verified.
- A2A "What is A2A?" quote at lines 52-53 — verified.
- Google forum "A tool..." quote at lines 55-56 — verified.
- Magentic-One orchestrator quote at lines 102-103 — verified.
- LangGraph supervisor quote at lines 107-108 — verified.
- Anthropic orchestrator-workers quote at lines 112-113 — verified.
- LangChain subagents and handoffs quotes at lines 121-122 and 161-162 — verified.
- Anthropic prompt chaining quote at lines 191-192 — verified.
- A2A registry quote at lines 206-207 — verified.
- A2A opacity quote at lines 279-280 — verified.
- Google A2A partner-count quote at lines 301-302 — verified.
- A2A enterprise governance/tracing quotes at lines 432-438 — verified.
- Magentic-One risk quote at lines 475-476 — verified.

🟡 Important (must-fix): The OpenAI handoffs quote at lines 151-152 could not be verified because the cited URL returned 403 to the fetch tool. Either replace it with a verifiable source or explicitly mark it unverifiable.

🟡 Important (must-fix): The LangGraph Command-based handoff quote at lines 156-157 could not be verified from the cited URL because it redirects/does not expose content through fetch, and the likely new docs path returned 404. Replace or update the citation.

## Source Authority Compliance

No material issue for core protocol claims: the report relies heavily on official A2A documentation, A2A repositories, Google launch material, Anthropic engineering guidance, Microsoft Research, and LangChain docs/blogs.

🟢 Minor (nice-to-have): The Google Developer Forum "Agents are not tools" source is lower authority than the official A2A docs, but it is appropriately used as supplemental commentary rather than sole support.

## Conflict & Uncertainty Disclosure

🟡 Important (must-fix): The report acknowledges scarcity of production case studies, but the body still labels many items "real-world examples" even when they are demos, framework patterns, partner endorsements, or conceptual examples rather than production deployments. This weakens the distinction between observed production patterns and illustrative examples.

🟢 Minor (nice-to-have): The report should explicitly separate "production case studies," "vendor demos," "framework patterns," and "partner endorsements" so readers can judge evidence strength.

## Source Freshness & Currency

🟡 Important (must-fix): The user specifically requested real-world examples from the past 12 months and stale sources flagged explicitly. Several important examples are older than 12 months relative to the report date (2026-05-20) and are not flagged inline:

- Google A2A launch blog — 2025-04-09, about 13 months old.
- Microsoft Magentic-One — November 2024, about 18 months old.
- Anthropic "Building Effective Agents" — older than 12 months relative to 2026-05-20.
- LangGraph multi-agent workflows blog — 2024-era content, older than 12 months.

This matters because the report presents these as current real-world examples without visible freshness caveats.

🟢 Minor (nice-to-have): The A2A docs are clearly current around v1.0.0, but the report should distinguish living docs from dated blog posts.

## Topic Coverage Assessment

🟡 Important (must-fix): The pattern catalog is clear and includes the requested canonical patterns, but the "real-world examples" standard is not fully met. Many examples are not dated in the body, and several are not real deployments/case studies. Add publisher/date/link for each example and label its evidence type.

No material issue with the demo fit recommendation: "Orchestrator + Specialist Worker" is the right canonical label for Zava because Agent A stays user-facing and delegates a focused feasibility task to Agent B over A2A.

🟢 Minor (nice-to-have): The pattern selection heuristics include latency, observability, and governance, but security appears mostly in the later governance section rather than the decision matrix. Add a "Security boundary / auth complexity" row.

## Research Limitations Review

No material issue with existence or honesty. The limitations section exists and accurately notes scarce production case studies, anecdotal anti-pattern evidence, and Foundry-specific documentation gaps.

🟡 Important (must-fix): The limitations section is more candid than the body. The body should carry the same caveats inline where claims are made, especially around "real-world examples" and "past 12 months."

## Code & CLI Validation

This is a pattern/use-case research report, not a code-oriented tutorial. Code/CLI examples are appropriately omitted. No syntax validation required.

## Reference List Integrity

🟡 Important (must-fix): The header says "Sources consulted: 14 web pages, 2 GitHub repositories," but the reference list contains 17 documentation/articles plus 2 GitHub repositories. The count does not match.

🟢 Minor (nice-to-have): The reviewer instructions expect reference categories "Documentation & Articles, GitHub Repositories, Code Samples." The report has the first two but no "Code Samples" section, even though `a2a-samples` is a code sample repository.

🟢 Minor (nice-to-have): Some listed sources are barely or not materially used in the body (Python tutorial, Life of a Task, a2a-samples). Either cite them where relevant or remove them from the consulted count/list.

## Report Structure & Readability

No material issue with readability. The report is well organized, has a useful table of contents, and the Zava recommendation is easy to follow.

🟢 Minor (nice-to-have): Some source attributions are bare `> — Source:` lines without preceding quoted text. This looks like quote formatting but is not actually a quote.

## Suggested Improvements (Prioritized)

1. Add dates, publisher names, and evidence-type labels to every "real-world example"; explicitly flag all sources older than 12 months.
2. Replace or update unverifiable citations for OpenAI handoffs and LangGraph Command-based handoffs.
3. Add verbatim quotes for every key pattern/example claim that currently has only a source line.
4. Reconcile the source count and reference list, and categorize code samples separately if retained.
5. Move the limitations caveats inline into the pattern and example sections, especially where examples are demos or endorsements rather than production case studies.
6. Add a security/auth complexity row to the pattern-selection matrix.

## Readiness verdict: APPROVED

**Verdict:** NEEDS REWORK

The report has a strong structure and the Zava pattern recommendation is directionally correct, but it does not yet meet the requested evidence bar. Blockers are: stale sources not explicitly flagged, "real-world examples" that are often demos/endorsements rather than dated production examples, unverifiable citations, missing verbatim quotes for several key claims, and a mismatched source count.

## Review Round 2 — 2026-05-20

### Fix Verification

1. Round 1: "Executive Summary claims ... are presented as established market facts but have no inline citation or evidence." — **RESOLVED — ✅ fixed.** The Executive Summary now cites the Google A2A launch post and A2A "What is A2A?" docs, and adds an explicit caveat that the evidence base is mostly protocol docs, vendor demos, framework patterns, and partner endorsements rather than production case studies.
2. Round 1: "Some pattern entries cite a source URL without a verbatim supporting quote" for trip planning, GPT-Newspaper, Cisco agntcy, LangGraph interrupts, and Magentic-One benchmark summary. — **RESOLVED — ✅ fixed.** Each named section now includes an inline blockquote and source line. The trip-planning quote condenses source bullet formatting, but the cited content is present.
3. Round 1: "OpenAI handoffs quote ... could not be verified because the cited URL returned 403." — **RESOLVED — ✅ fixed.** The report now flags the original OpenAI URL as 403/unverifiable and adds a Wayback snapshot; the archived page contains "Handoffs: Intelligently transfer control between agents."
4. Round 1: "LangGraph Command-based handoff quote ... could not be verified from the cited URL." — **RESOLVED — ✅ fixed.** The report updates the citation to the current LangGraph Graph API page. The page verifies `Command` parameters `goto` and `graph`, includes `graph=Command.PARENT`, and explicitly links this usage to multi-agent handoffs.
5. Round 1: "The body still labels many items 'real-world examples' even when they are demos, framework patterns, partner endorsements, or conceptual examples." — **RESOLVED — ✅ fixed.** Sections now include publisher/date/evidence-type labels and an upfront evidence-quality note.
6. Round 1: "Sources older than 12 months ... are not flagged inline." — **RESOLVED — ✅ fixed.** Google A2A launch, Microsoft Magentic-One, Anthropic, and LangGraph blog citations are now flagged inline as older than 12 months where used.
7. Round 1: "The pattern catalog ... real-world examples standard is not fully met. Add publisher/date/link for each example and label its evidence type." — **RESOLVED — ✅ fixed.** Examples now carry publisher, date, and evidence-type labels. The report also states that no detailed production case studies were found.
8. Round 1: "The limitations section is more candid than the body." — **RESOLVED — ✅ fixed.** The same caveats now appear in the Executive Summary, Section 3, and individual example entries.
9. Round 1: "The header says ... 14 web pages, 2 GitHub repositories, but the reference list contains 17 documentation/articles plus 2 GitHub repositories." — **RESOLVED — ✅ fixed.** The header now says 17 web pages and 2 GitHub repositories. The reference list contains 16 Documentation & Articles entries plus an archived Wayback page URL nested under the OpenAI entry, totaling 17 web page URLs, and 2 GitHub repository entries.

## Reference Validation

13 of 19 listed source URLs were spot-checked in Round 2, focusing on changed or previously problematic sources.

- `https://a2a-protocol.org/latest/topics/what-is-a2a/` — reachable; supports trip-planning orchestration, A2A/MCP distinction, long-running tasks, opacity, and the demo interaction-flow quote.
- `https://a2a-protocol.org/latest/topics/agent-discovery/` — reachable; supports curated registry quote and three discovery strategies.
- `https://a2a-protocol.org/latest/topics/enterprise-ready/` — reachable; supports API management, policy enforcement, and OpenTelemetry tracing quotes.
- `https://a2a-protocol.org/latest/topics/a2a-and-mcp/` — reachable; supports customer-service delegation and auto-repair-shop HITL scenario.
- `https://a2a-protocol.org/latest/topics/key-concepts/` — reachable; supports Task/Message/Part/Artifact concepts.
- `https://a2a-protocol.org/latest/specification/` — reachable; supports v1.0.0 and core protocol goals.
- `https://a2a-protocol.org/latest/` — reachable; supports Linux Foundation donation, official SDK list, sample links, and Cisco agntcy description.
- `https://github.com/a2aproject/A2A` — reachable; supports README quote, SDK list, and healthcare-course mention.
- `https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/` — reachable; supports partner count, enterprise workflow quote, candidate-sourcing demo, and partner endorsements.
- `https://www.anthropic.com/engineering/building-effective-agents` — reachable; supports orchestrator-workers, prompt chaining, support/coding examples, and anti-pattern guidance.
- `https://docs.langchain.com/oss/python/langchain/multi-agent/` — reachable; supports subagents, handoffs, pattern selection, and performance comparison.
- `https://docs.langchain.com/oss/python/langgraph/graph-api` — reachable; supports `Command`, `goto`, `graph=Command.PARENT`, and handoff guidance.
- `https://openai.com/index/new-tools-for-building-agents/` — still returns 403 to fetch, but the report now clearly marks this. The cited Wayback snapshot is reachable and relevant.

No fabricated references found.

## Claim Citation Coverage

No material issues. The high-stakes architectural and evidence-strength claims now carry citations or caveats. The Zava fit section cites Anthropic, LangChain, Microsoft Research, and A2A docs for the orchestrator/specialist-worker topology.

🟢 Minor (nice-to-have): The phrase "leading open interoperability standard" in the Executive Summary remains a judgment call rather than a directly measurable market claim, but it is softened by "in our reading of public material" and supported by A2A v1.0.0, Linux Foundation stewardship, SDK breadth, and partner-list citations. This does not block approval.

## Quote Verification

9 quotes were re-verified, prioritizing Round 1 failures and newly added quotes:

- A2A trip-planning quote, Section 2.1 — verified with minor bullet/line-break compression; source content exists on the A2A "What is A2A?" page.
- GPT-Newspaper quote, Section 2.3 — verified verbatim on the LangGraph multi-agent workflows blog.
- Cisco agntcy quote, Section 2.4 — verified verbatim on the A2A homepage.
- LangGraph interrupts quote, Section 2.5 — verified verbatim on the LangGraph Interrupts page.
- OpenAI handoffs quote, Section 2.2 — verified verbatim in the Wayback snapshot; original URL remains 403 and is properly labeled.
- LangGraph `Command` quote, Section 2.2 — verified on the LangGraph Graph API page; the page also supports `goto` and `graph=Command.PARENT` for handoffs.
- Magentic-One orchestrator quote, Section 2.1 — verified verbatim on Microsoft Research.
- Google candidate-sourcing quote, Section 3.6 — verified verbatim on the Google Developers Blog.
- A2A enterprise tracing quote, Section 4 — verified verbatim on A2A Enterprise Features.

No material quote-verification blockers remain.

## Source Authority Compliance

No material issues. Core protocol claims use official A2A docs/spec/repositories. Pattern claims use first-party framework/vendor sources from LangChain, Anthropic, Microsoft Research, Google, and OpenAI. The Google Developer Forum source is still community/forum content, but it is explicitly labeled and only used as supplemental commentary corroborated by official A2A docs.

## Conflict & Uncertainty Disclosure

No material issues. The report now distinguishes production case studies, vendor demos, framework patterns, partner endorsements, and conceptual examples. It explicitly states that detailed production A2A case studies with metrics were not found.

## Source Freshness & Currency

No material issues. Stale sources older than 12 months are flagged inline and again in Research Limitations. Current A2A living docs and v1.0.0 specification are distinguished from dated blog posts.

## Topic Coverage Assessment

No material issues. The report covers the major A2A/multi-agent patterns relevant to the Zava demo: orchestrator + specialist worker, handoffs, pipeline/chain, registry discovery, HITL relay, and cross-org federation. It convincingly justifies the Zava pattern: Foundry V2 Customer Service Agent as A2A client/orchestrator and LangGraph-on-AKS Manufacturing Ops Agent as specialist A2A server.

The cited use cases are real public examples or documented patterns from official A2A, Google, Microsoft Research, Anthropic, LangChain, and OpenAI sources. The report no longer overstates them as production deployments; it labels evidence types appropriately.

## Research Limitations Review

No material issues. The limitations section is candid and now matches the body: Foundry-specific A2A documentation gaps, scarce production case studies, stale dated sources, unverifiable/redirected citations, anecdotal anti-pattern evidence, and A2A v1.0.0 ecosystem maturity are all disclosed.

## Code & CLI Validation

No material issues. This is a pattern/use-case research report, not a code tutorial. There are no executable Python or CLI snippets requiring syntax validation. Inline API names and the simple ASCII interaction flow are supported by cited A2A and LangGraph documentation.

## Reference List Integrity

No material blocking issues. The header count is acceptable if counted by URL: 17 web page URLs including the Wayback URL nested in the OpenAI reference, plus 2 GitHub repositories. The reference list categories contain Documentation & Articles and GitHub Repositories.

🟢 Minor (nice-to-have): The expected "Code Samples" category is still absent, and `a2aproject/a2a-samples` is listed under GitHub Repositories while not materially cited in the body. This was a Round 1 nice-to-have and is waived for approval.

## Report Structure & Readability

No material issues. The report is well-structured, readable, and more honest about evidence quality than Round 1. Inline quotes are embedded near the claims they support.

## Suggested Improvements (Prioritized)

1. 🟢 Minor (nice-to-have): Add a separate "Code Samples" reference category or remove `a2aproject/a2a-samples` if it remains unused in the body.
2. 🟢 Minor (nice-to-have): Reformat the A2A trip-planning quote to preserve the source bullet list exactly, rather than compressing it into one sentence.
3. 🟢 Minor (nice-to-have): Consider softening "leading open interoperability standard" further unless future research finds independent adoption/market-share evidence.

## Readiness Verdict: APPROVED

All Round 1 must-fix findings are resolved, no new must-fix issues were found, and remaining items are 🟢 Minor nice-to-haves. The report is ready for use in planning the Zava Foundry V2 ⇄ LangGraph-on-AKS A2A demo.
