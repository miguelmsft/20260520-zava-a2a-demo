# Research Report: A2A Use Cases & Common Multi-Agent Patterns

**Date:** 2026-05-20
**Researcher:** Copilot Web Researcher Agent
**Topic slug:** a2a-use-cases
**Sources consulted:** 17 web pages, 2 GitHub repositories

---

## Executive Summary

The Agent-to-Agent (A2A) protocol — an open standard originally developed by Google and now under the Linux Foundation — is, in our reading of public material as of May 2026, the leading open interoperability standard for multi-agent AI systems. A2A addresses a critical gap: enabling AI agents built on different frameworks (LangGraph, ADK, Semantic Kernel, CrewAI, etc.) by different vendors to communicate as *peers*, not as tools. The protocol has reached version 1.0.0, has official SDKs in Python, Go, JavaScript, Java, C#/.NET, and Rust, and the launch announcement listed over 50 technology partners including Atlassian, Salesforce, SAP, ServiceNow, Intuit, and PayPal ([Announcing A2A — Google Developers Blog, 2025-04-09](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)).

Based on our survey of official A2A documentation, vendor engineering blogs, and framework documentation, the multi-agent patterns most prominently described in public material cluster around a small set of canonical architectures: **orchestrator + specialist workers**, **peer-to-peer handoffs**, **sequential pipelines**, **broker/registry-mediated discovery**, and **human-in-the-loop relays**. Each pattern has distinct trade-offs around latency, observability, governance, and complexity. The A2A specification is deliberately pattern-agnostic — it provides the communication primitives (Agent Cards, Tasks, Messages, Artifacts, streaming) and leaves architectural topology to implementers ([What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)).

**Important caveat:** As noted in [Section 7 (Research Limitations)](#7-research-limitations), most public evidence for A2A patterns comes from protocol documentation, vendor demos, framework patterns, and partner endorsement quotes — not from published production case studies with architecture post-mortems. Each example in this report is labeled with its evidence type so readers can judge evidence strength.

For the **Zava Smart Order Feasibility demo** — where a customer-facing Foundry agent calls a LangGraph ops agent for feasibility data — the canonical pattern is **"orchestrator + specialist worker"** (also called "subagent" in LangChain's taxonomy). The Foundry agent acts as the orchestrator/client, and the LangGraph agent acts as the specialist worker/server, invoked via A2A to produce a focused deliverable (feasibility analysis) that the orchestrator synthesizes into the final user response.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Catalog of A2A Patterns](#2-catalog-of-a2a-patterns)
  - [2.1 Orchestrator + Specialist Workers](#21-orchestrator--specialist-workers)
  - [2.2 Peer-to-Peer / Handoff](#22-peer-to-peer--handoff)
  - [2.3 Pipeline / Chain](#23-pipeline--chain)
  - [2.4 Broker / Registry-Mediated Discovery](#24-broker--registry-mediated-discovery)
  - [2.5 Human-in-the-Loop Relay](#25-human-in-the-loop-relay)
  - [2.6 Cross-Org / Cross-Tenant Federation](#26-cross-org--cross-tenant-federation)
- [3. Real-World Use Cases](#3-real-world-use-cases)
- [4. Pattern Selection Heuristics](#4-pattern-selection-heuristics)
- [5. Anti-Patterns & Cautionary Tales](#5-anti-patterns--cautionary-tales)
- [6. Our Demo's Fit: Zava Smart Order Feasibility](#6-our-demos-fit-zava-smart-order-feasibility)
- [7. Research Limitations](#7-research-limitations)
- [8. Complete Reference List](#8-complete-reference-list)

---

## 1. Overview

### What A2A Is

The Agent2Agent (A2A) protocol is an open standard that enables seamless communication and collaboration between AI agents, regardless of their underlying framework, vendor, or deployment environment. It uses JSON-RPC 2.0 over HTTP(S) as its transport, making it compatible with existing enterprise infrastructure.

> "The Agent2Agent (A2A) protocol addresses a critical challenge in the AI landscape: enabling gen AI agents, built on diverse frameworks by different companies running on separate servers, to communicate and collaborate effectively - as agents, not just as tools."
> — Source: [A2A GitHub Repository README](https://github.com/a2aproject/A2A)

### Why It Matters

A2A fills a gap that MCP (Model Context Protocol) does not address. While MCP standardizes how agents connect to *tools*, A2A standardizes how agents collaborate with *other agents*. The distinction is fundamental: agents are autonomous problem-solvers that reason, plan, and engage in multi-turn dialogue, while tools are stateless functions with well-defined inputs and outputs.

> "The practice of encapsulating an agent as a simple tool is fundamentally limiting, as it fails to capture the agent's full capabilities."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

> "A tool is something that can be asked to take an action, can be awaited for completion of the action, and can report errors... Agents are problem-solving collaborators."
> — Source: [Agents are not tools — Google Developer Forums](https://discuss.google.dev/t/agents-are-not-tools/192812) *(community content — Google Developer Forum; corroborated by official A2A docs above)*

### Key A2A Primitives

The protocol defines several primitives that enable the patterns described below:

| Primitive | Purpose |
|-----------|---------|
| **Agent Card** | JSON metadata document describing an agent's identity, capabilities, endpoint, skills, and auth requirements |
| **Task** | Stateful unit of work with a lifecycle (submitted → working → completed/failed/input-required) |
| **Message** | Single turn of communication between client and agent |
| **Part** | Content container (text, file, structured data) within messages and artifacts |
| **Artifact** | Tangible output generated by an agent during task processing |

> "A Task is a stateful entity that represents an ongoing interaction between a client and a remote agent. It has a lifecycle..."
> — Source: [Core Concepts — A2A Protocol](https://a2a-protocol.org/latest/topics/key-concepts/)

---

## 2. Catalog of A2A Patterns

### 2.1 Orchestrator + Specialist Workers

**Description:** One central agent (the orchestrator/client) receives user requests, decomposes them into subtasks, delegates to one or more specialist agents (remote A2A servers), and synthesizes their results into a cohesive response.

**A2A Mapping:** The orchestrator is the A2A *client*; each specialist is an A2A *server*. The orchestrator discovers specialists via Agent Cards, sends tasks via `sendMessage` or `sendMessageStream`, and collects artifacts.

**When to use:**
- Complex tasks where subtasks can't be predicted in advance
- When specialists have distinct domains/knowledge/tools
- When the user interacts only with the orchestrator

**Pros:**
- Clear single point of control and accountability
- Specialists can be developed, deployed, and scaled independently
- Natural fit for context isolation — each specialist gets only the context it needs
- Supports parallel execution of independent subtasks

**Cons:**
- Extra LLM call overhead (results flow back through orchestrator)
- Orchestrator is a single point of failure
- Orchestrator needs sufficient capability to route and synthesize

**Real-world examples:**

1. **Microsoft Magentic-One** — An Orchestrator agent directs four specialist agents (WebSurfer, FileSurfer, Coder, ComputerTerminal) to solve complex tasks.
   - *Publisher:* Microsoft Research | *Date:* November 4, 2024 ⚠️ Source is >12 months old | *Evidence type:* `vendor demo` (research prototype with benchmark evaluations, not a production deployment)

> "Magentic-One employs a multi-agent architecture where a lead agent, the Orchestrator, directs four other agents to solve tasks. The Orchestrator plans, tracks progress, and re-plans to recover from errors."
> — Source: [Magentic-One — Microsoft Research](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/)

2. **LangGraph Agent Supervisor** — A supervisor agent routes to individual sub-agents, each with their own prompt, LLM, and tools.
   - *Publisher:* LangChain Blog | *Date:* January 2024 ⚠️ Source is >12 months old | *Evidence type:* `framework pattern`

> "An agent supervisor is responsible for routing to individual agents... the supervisor can also be thought of as an agent whose tools are other agents!"
> — Source: [LangGraph: Multi-Agent Workflows — LangChain Blog](https://blog.langchain.dev/langgraph-multi-agent-workflows/) *(now redirects to `www.langchain.com/blog/langgraph-multi-agent-workflows`)*

3. **Anthropic Orchestrator-Workers** — A central LLM dynamically breaks down tasks, delegates to worker LLMs, and synthesizes results.
   - *Publisher:* Anthropic | *Date:* December 19, 2024 ⚠️ Source is >12 months old (relative to report date 2026-05-20) | *Evidence type:* `framework pattern` (architectural guidance, not a production deployment)

> "In the orchestrator-workers workflow, a central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

4. **A2A trip planning example** — The official A2A docs describe an AI assistant acting as orchestrator, delegating to flight booking, hotel reservation, currency conversion, and local tours agents.
   - *Publisher:* A2A Protocol (Linux Foundation) | *Date:* 2026 (living docs, v1.0.0) | *Evidence type:* `conceptual example` (illustrative scenario in protocol documentation)

> "Consider a user request for an AI assistant to plan an international trip. This task involves orchestrating multiple specialized agents, such as: A flight booking agent, A hotel reservation agent, An agent for local tour recommendations, A currency conversion agent."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

**LangChain's equivalent label:** "Subagents" pattern.

> "A main agent coordinates subagents as tools. All routing passes through the main agent, which decides when and how to invoke each subagent."
> — Source: [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/)

---

### 2.2 Peer-to-Peer / Handoff

**Description:** Agents transfer control to each other dynamically. No single agent is the permanent orchestrator; instead, the active agent hands off to a peer when the conversation moves into a different domain. The receiving agent takes over direct interaction with the user (or upstream caller).

**A2A Mapping:** Each agent can act as both client and server. Handoff is modeled as the current agent sending a message to the next agent (as an A2A client) and forwarding the conversation context via `contextId`.

**When to use:**
- Conversational systems where the domain shifts mid-conversation (e.g., customer service routing from billing to tech support)
- When each agent should be able to converse directly with the user
- When you want stateful, multi-turn interactions without returning to a central orchestrator

**Pros:**
- Lower latency for repeat interactions (stateful — no re-routing overhead)
- Natural conversational flow
- Efficient for single-domain follow-ups (saves LLM calls)

**Cons:**
- Harder to maintain global oversight (no single orchestrator to log/audit)
- Sequential by nature — can't parallelize across domains
- More complex error recovery (who handles a failure during handoff?)

**Real-world examples:**

1. **OpenAI Agents SDK (Swarm successor)** — Explicitly supports "handoffs" as a first-class pattern.
   - *Publisher:* OpenAI | *Date:* March 11, 2025 | *Evidence type:* `framework pattern`
   - ⚠️ Source returned 403 to public fetch — cannot be independently verified via automated crawl. Archived copy verified at: [Wayback Machine snapshot (2025-03-12)](https://web.archive.org/web/20250312/https://openai.com/index/new-tools-for-building-agents/)

> "Handoffs: Intelligently transfer control between agents."
> — Source: [New tools for building agents — OpenAI](https://openai.com/index/new-tools-for-building-agents/)

2. **LangGraph Command-based handoffs** — LangGraph supports `Command(goto="other_agent", graph=Command.PARENT)` for multi-agent handoffs across subgraphs.
   - *Publisher:* LangChain | *Date:* living docs (continuously updated) | *Evidence type:* `framework pattern`
   - ⚠️ The originally cited URL (`langchain-ai.github.io/langgraph/concepts/multi_agent/`) now redirects to `https://docs.langchain.com/oss/python/langgraph/graph-api`. The `Command` handoff documentation is confirmed present at the redirect target.

> "Command is used in three contexts: ... Return from nodes ... resume to continue execution after an interrupt ... Return from tools"
> — Source: [LangGraph Graph API — LangChain Docs](https://docs.langchain.com/oss/python/langgraph/graph-api) *(redirected from `langchain-ai.github.io/langgraph/concepts/multi_agent/`)*

**LangChain's equivalent label:** "Handoffs" pattern.

> "Agents transfer control to each other via tool calls. Each agent can hand off to others or respond directly to the user."
> — Source: [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/)

---

### 2.3 Pipeline / Chain

**Description:** A sequence of specialized agents processes data in order, where each agent's output feeds the next agent's input. The flow is linear and deterministic.

**A2A Mapping:** Each stage is an A2A server. The output artifact from stage N becomes the input message for stage N+1. A lightweight orchestrator or even a simple script can drive the pipeline.

**When to use:**
- Tasks that decompose cleanly into fixed sequential steps
- When each step is relatively simple but the end-to-end task is complex
- Content pipelines (generate → review → translate → format)

**Pros:**
- Simple to understand, test, and debug
- Each stage can be independently validated with programmatic "gates"
- Easy to add quality checks between steps

**Cons:**
- Inflexible — the path is fixed
- Higher total latency (sequential execution)
- No parallelism unless stages are independent

**Real-world examples:**

1. **Anthropic's "Prompt Chaining"** pattern:
   - *Publisher:* Anthropic | *Date:* December 19, 2024 ⚠️ Source is >12 months old | *Evidence type:* `framework pattern`

> "Prompt chaining decomposes a task into a sequence of steps, where each LLM call processes the output of the previous one. You can add programmatic checks (see 'gate' in the diagram below) on any intermediate steps to ensure that the process is still on track."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

2. **GPT-Newspaper** — Six specialized sub-agents in a pipeline: curator → writer → critique (loop) → designer → editor → publisher.
   - *Publisher:* LangChain Blog (describing a third-party project by the creators of GPT-Researcher) | *Date:* January 2024 ⚠️ Source is >12 months old | *Evidence type:* `vendor demo` (open-source project, not a production deployment)

> "GPT-Newspaper is an innovative autonomous agent designed to create personalized newspapers tailored to user preferences. GPT Newspaper revolutionizes the way we consume news by leveraging the power of AI to curate, write, design, and edit content based on individual tastes and interests."
> — Source: [LangGraph: Multi-Agent Workflows — LangChain Blog](https://blog.langchain.dev/langgraph-multi-agent-workflows/) *(now redirects to `www.langchain.com/blog/langgraph-multi-agent-workflows`)*

---

### 2.4 Broker / Registry-Mediated Discovery

**Description:** A central registry or broker maintains a catalog of available agents (via Agent Cards). Clients query the registry to discover agents by skill, capability, or domain, then communicate with discovered agents directly via A2A.

**A2A Mapping:** The A2A spec defines three discovery strategies: (1) Well-Known URI (`/.well-known/agent-card.json`), (2) Curated Registries, and (3) Direct Configuration. The broker/registry pattern corresponds to strategy (2).

> "An intermediary service (the registry) maintains a collection of Agent Cards. Clients query this registry to find agents based on various criteria (e.g., skills offered, tags, provider name, capabilities)."
> — Source: [Agent Discovery — A2A Protocol](https://a2a-protocol.org/latest/topics/agent-discovery/)

**When to use:**
- Large-scale deployments with many agents
- Cross-organizational scenarios where agents are contributed by different teams/vendors
- Agent marketplaces

**Pros:**
- Dynamic discovery — agents can be added/removed without reconfiguring clients
- Centralized governance and access control
- Supports capability-based matching

**Cons:**
- Registry is an additional infrastructure component to deploy and maintain
- The A2A specification does not yet prescribe a standard registry API
- Potential single point of failure if the registry goes down

**Real-world examples:**

- **Cisco agntcy** — A framework for the "Internet of Agents" with discovery, group communication, identity, and observability.
  - *Publisher:* Cisco (listed on A2A Protocol Homepage) | *Date:* 2025–2026 (ongoing) | *Evidence type:* `partner endorsement` (listed on A2A homepage as an ecosystem component; no published production case study found)

> "Cisco agntcy: A framework that provides components to the Internet of Agents with discovery, group communication, identity and observability and leverages A2A and MCP for agent communication and tool calling."
> — Source: [A2A Protocol Homepage](https://a2a-protocol.org/latest/)

- **Google Agentspace** — Enterprise agent hub where users task their personal agent, which discovers and delegates to specialized agents. Demonstrated in the A2A candidate sourcing demo.
  - *Publisher:* Google Developers Blog | *Date:* April 9, 2025 ⚠️ Source is >12 months old | *Evidence type:* `vendor demo` (demonstrated in A2A launch blog, not a published production deployment)

> "Hiring a software engineer can be significantly simplified with A2A collaboration. Within a unified interface like Agentspace, a user (e.g., a hiring manager) can task their agent to find candidates matching a job listing, location, and skill set."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

---

### 2.5 Human-in-the-Loop Relay

**Description:** One agent sits in front of a human (the "client agent"), while backend agents do the heavy lifting. The client agent surfaces clarification requests, approval prompts, or verification steps to the human before forwarding decisions back to the backend agent.

**A2A Mapping:** The A2A Task lifecycle explicitly supports `input-required` and `auth-required` states — the server agent signals that it needs more information or authorization from the client/user before proceeding.

> "A2A natively supports long-running tasks. It handles scenarios where agents or users might not remain continuously connected. It uses mechanisms like streaming and push notifications."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

**When to use:**
- High-stakes decisions requiring human approval (financial transactions, medical decisions)
- Scenarios where backend agents need user-specific information mid-task
- Compliance/governance contexts requiring audit trails

**Pros:**
- Maintains human oversight for critical decisions
- A2A's `input-required` state makes this a first-class protocol concept
- Supports long-running, asynchronous workflows

**Cons:**
- Introduces latency (waiting for human input)
- Requires UX design for surfacing agent requests to humans
- More complex state management

**Real-world examples:**

- **A2A auto repair shop scenario** — Customer (human) interacts with Shop Manager agent, which delegates to Mechanic agent. The Mechanic may need to request additional info from the customer (e.g., "Can you send a video of the noise?").
  - *Publisher:* A2A Protocol (Linux Foundation) | *Date:* 2026 (living docs, v1.0.0) | *Evidence type:* `conceptual example`

> "The Shop Manager agent uses A2A for a multi-turn diagnostic conversation. For example, the Manager might ask, 'Can you send a video of the noise?' or 'I see some fluid leaking. How long has this been happening?'"
> — Source: [A2A and MCP — A2A Protocol](https://a2a-protocol.org/latest/topics/a2a-and-mcp/)

- **LangGraph interrupts** — LangGraph natively supports `interrupt()` to pause execution and wait for human input, which maps naturally to the A2A `input-required` state.
  - *Publisher:* LangChain Docs | *Date:* living docs (continuously updated) | *Evidence type:* `framework pattern`

> "Interrupts allow you to pause graph execution at specific points and wait for external input before continuing. This enables human-in-the-loop patterns where you need external input to proceed."
> — Source: [Interrupts — LangChain Docs](https://docs.langchain.com/oss/python/langgraph/interrupts)

---

### 2.6 Cross-Org / Cross-Tenant Federation

**Description:** Agents from different organizations, vendors, or tenants communicate via A2A. Each organization maintains control over its own agents' internals while exposing a standardized A2A interface.

**A2A Mapping:** This is a core design goal of A2A. The protocol's opacity principle means agents interact without exposing internal logic, memory, or tools.

> "Agents collaborate effectively without exposing their internal logic, memory, or proprietary tools. Interactions rely on declared capabilities and exchanged context. This preserves intellectual property and enhances security."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

**When to use:**
- Enterprise ecosystems where agents from different SaaS vendors need to collaborate
- Supply chain scenarios spanning multiple organizations
- Agent marketplaces

**Pros:**
- Preserves IP and security boundaries
- Each org can use its own frameworks, models, and infrastructure
- Standard auth (OAuth2, OpenID Connect) integrates with existing IAM

**Cons:**
- More complex authentication/authorization across organizational boundaries
- Latency from cross-network communication
- Trust and governance challenges

**Real-world examples:**

The A2A launch announcement listed 50+ technology partners. These are partner endorsement quotes indicating intent to adopt A2A, not confirmed production deployments:
- *Publisher:* Google Developers Blog | *Date:* April 9, 2025 ⚠️ Source is >12 months old | *Evidence type:* `partner endorsement`

> "Today, we're launching a new, open protocol called Agent2Agent (A2A), with support and contributions from more than 50 technology partners like Atlassian, Box, Cohere, Intuit, Langchain, MongoDB, PayPal, Salesforce, SAP, ServiceNow, UKG and Workday."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

The A2A Enterprise Features documentation explicitly addresses cross-org governance:

> "For A2A servers exposed externally, across organizational boundaries, or even within large enterprises, integration with API Management solutions is highly recommended."
> — Source: [Enterprise Features — A2A Protocol](https://a2a-protocol.org/latest/topics/enterprise-ready/)

---

## 3. Real-World Use Cases

> **Note on evidence quality:** Most use cases below are sourced from protocol documentation, vendor demos, partner endorsement quotes, and framework design guides — not from published production case studies with post-mortem metrics. Each entry is labeled with its evidence type. See [Section 7](#7-research-limitations) for details.

### 3.1 Customer Service / Support Routing

Customer support is described by both Anthropic and the A2A protocol docs as a primary multi-agent use case. Incoming queries are routed to specialist agents based on classification (billing, tech support, returns).

- *Evidence type:* `framework pattern` (Anthropic, Dec 2024 ⚠️ Source is >12 months old) + `conceptual example` (A2A docs, 2026)

> "Support interactions naturally follow a conversation flow while requiring access to external information and actions; Tools can be integrated to pull customer data, order history, and knowledge base articles; Actions such as issuing refunds or updating tickets can be handled programmatically."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

The A2A protocol docs cite this directly:

> "Supports typical use cases, including a customer service agent delegating an inquiry to a billing agent."
> — Source: [A2A and MCP — A2A Protocol](https://a2a-protocol.org/latest/topics/a2a-and-mcp/)

### 3.2 Enterprise Back-Office (Order Management, Supply Chain)

The A2A announcement blog specifically mentions enterprise workflows:

- *Evidence type:* `partner endorsement` (Google Developers Blog, April 9, 2025 ⚠️ Source is >12 months old)

> "Today, enterprises are increasingly building and deploying autonomous agents to help scale, automate and enhance processes throughout the workplace – from ordering new laptops, to aiding customer service representatives, to assisting in supply chain planning."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

Partners like SAP, Workday, and ServiceNow are listed as A2A partners in the launch blog, suggesting order management, procurement, and supply chain are intended domains. *No published production case studies from these partners were found as of May 2026.*

### 3.3 Research / Coding Assistants

Multi-agent coding is described as a proven use case in Anthropic's guidance:

- *Evidence type:* `framework pattern` (Anthropic, Dec 2024 ⚠️ Source is >12 months old) + `vendor demo` (Microsoft Research, Nov 2024 ⚠️ Source is >12 months old)

> "Coding products that make complex changes to multiple files each time."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

Microsoft's Magentic-One demonstrated this with a multi-agent system using specialized Coder and ComputerTerminal agents coordinated by an Orchestrator. The system was evaluated against the GAIA, AssistantBench, and WebArena benchmarks:

> "Magentic-One achieves statistically competitive performance to the state of the art across all three benchmarks."
> — Source: [Magentic-One — Microsoft Research](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/)

### 3.4 DevOps / SRE Automation

Chronosphere (an A2A launch partner) called out this use case specifically:

- *Evidence type:* `partner endorsement` (Google Developers Blog, April 9, 2025 ⚠️ Source is >12 months old)

> "A2A will enable reliable and secure agent specialization and coordination to open the door for a new era of compute orchestration, empowering companies to deliver products and services faster, more reliably."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

Harness (another A2A partner) focuses on CI/CD and DevOps:

> "Harness is thrilled to support A2A and is committed to simplifying the developer experience by integrating AI-driven intelligence into every stage of the software lifecycle."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

### 3.5 Healthcare / Claims Processing

The DeepLearning.AI A2A course explicitly covers a healthcare multi-agent system:

- *Evidence type:* `vendor demo` (educational course listed on A2A GitHub README, 2025–2026)

> "Build a healthcare multi-agent system using different frameworks and see how A2A enables collaboration."
> — Source: [A2A GitHub Repository README](https://github.com/a2aproject/A2A)

### 3.6 HR / Candidate Sourcing

The A2A launch demo showed a candidate-sourcing workflow:

- *Evidence type:* `vendor demo` (Google Developers Blog, April 9, 2025 ⚠️ Source is >12 months old — demonstrated in a blog post video, not a published production deployment)

> "Hiring a software engineer can be significantly simplified with A2A collaboration. Within a unified interface like Agentspace, a user (e.g., a hiring manager) can task their agent to find candidates matching a job listing, location, and skill set. The agent then interacts with other specialized agents to source potential candidates."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

### 3.7 Cross-Vendor Agent Marketplaces

Multiple partner statements point to marketplace/ecosystem thinking. These are endorsement quotes expressing intent, not confirmed deployments:

- *Evidence type:* `partner endorsement` (Google Developers Blog, April 9, 2025 ⚠️ Source is >12 months old)

> "Intuit strongly believes that an open-source protocol such as A2A will enable complex agent workflows, accelerate our partner integrations, and move the industry forward with cross-platform agents that collaborate effectively."
> — Source: [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

---

## 4. Pattern Selection Heuristics

### Decision Matrix

| Criterion | Orchestrator + Workers | Handoff | Pipeline | Broker | HITL Relay |
|---|---|---|---|---|---|
| **Parallel execution** | ✅ Yes | ❌ Sequential | ❌ Sequential | ✅ Via orchestrator | ❌ Blocked on human |
| **Direct user interaction by workers** | ❌ Through orchestrator | ✅ Yes | ❌ Through pipeline | Depends | ✅ By design |
| **Distributed development** | ✅ Strong | ⚠️ Moderate | ✅ Strong | ✅ Strong | ✅ Strong |
| **Dynamic routing** | ✅ LLM decides | ✅ Dynamic | ❌ Fixed path | ✅ Discovery-based | ⚠️ Limited |
| **Observability** | ✅ Central log | ⚠️ Distributed | ✅ Linear trace | ✅ Registry audits | ✅ Human checks |
| **Latency** | ⚠️ Extra hop | ✅ Low for repeat | ⚠️ Sum of stages | ⚠️ Discovery overhead | ❌ Human-bound |
| **Multi-hop (sequential multi-agent)** | ✅ Yes | ✅ Yes | ✅ By design | ✅ Yes | ⚠️ Limited |
| **Security boundary / auth complexity** | ⚠️ Orchestrator holds all credentials | ⚠️ Each agent needs auth to peers | ✅ Linear trust chain | ✅ Centralized via registry | ✅ Human-gated |

> — Synthesized from: [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/), [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents), and [Enterprise Features — A2A Protocol](https://a2a-protocol.org/latest/topics/enterprise-ready/)

### When to Pick Orchestrator + Workers

Choose this when:
- You need a **single point of control** for auditability and error handling
- Tasks can be **parallelized** across specialists
- Workers have **large, domain-specific context** that would overwhelm a single agent
- You want **distributed development** — different teams own different agents

This is the most commonly described A2A pattern in the documentation we surveyed and maps directly to the A2A client/server model ([What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)).

### When to Pick Handoffs

Choose this when:
- The conversation naturally **shifts domains** (e.g., from sales to support)
- You need **direct user interaction** with each specialist
- You want to **minimize latency** for repeat interactions in the same domain
- You have a small number of well-defined agents

### When to Pick Pipeline/Chain

Choose this when:
- The task has a **fixed, predictable decomposition** (e.g., generate → review → publish)
- Each step is **independently testable** with clear quality gates
- Latency is acceptable (sequential execution)

### When You Need a Broker

Choose a broker/registry when:
- You have **many agents** and need dynamic discovery
- Agents are **contributed by different teams/orgs** and the inventory changes frequently
- You need **centralized governance** (access control, rate limiting, audit)

### Governance Considerations

The A2A Enterprise Features documentation outlines key governance requirements:

> "Centralized Policy Enforcement: Consistent application of security policies such as authentication and authorization, rate limiting, and quotas. Traffic Management: Load balancing, routing, and mediation. Analytics and Reporting: Insights into agent usage, performance, and trends."
> — Source: [Enterprise Features — A2A Protocol](https://a2a-protocol.org/latest/topics/enterprise-ready/)

For observability, A2A recommends:

> "A2A Clients and Servers should participate in distributed tracing systems. For example, use OpenTelemetry to propagate trace context, including trace IDs and span IDs, through standard HTTP headers, such as W3C Trace Context headers."
> — Source: [Enterprise Features — A2A Protocol](https://a2a-protocol.org/latest/topics/enterprise-ready/)

---

## 5. Anti-Patterns & Cautionary Tales

### 5.1 Anti-Pattern: Over-Engineering with Multi-Agent When a Single Agent Suffices

Anthropic's influential "Building Effective Agents" post (Dec 19, 2024 ⚠️ Source is >12 months old) is the strongest cautionary voice:

> "When building applications with LLMs, we recommend finding the simplest solution possible, and only increasing complexity when needed. This might mean not building agentic systems at all. Agentic systems often trade latency and cost for better task performance, and you should consider when this tradeoff makes sense."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

> "Success in the LLM space isn't about building the most sophisticated system. It's about building the right system for your needs. Start with simple prompts, optimize them with comprehensive evaluation, and add multi-step agentic systems only when simpler solutions fall short."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

LangChain's multi-agent docs echo this:

> "Multi-agent systems coordinate specialized components to tackle complex workflows. However, not every complex task requires this approach — a single agent with the right (sometimes dynamic) tools and prompt can often achieve similar results."
> — Source: [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/)

### 5.2 Anti-Pattern: Treating Agents as Tools (Wrapping A2A Agents in MCP)

The A2A project has explicitly argued against this:

> "Developers often wrap agents as tools to expose them to other agents, similar to how tools are exposed in a Multi-agent Control Platform (Model Context Protocol). However, this approach is inefficient because agents are designed to negotiate directly. Wrapping agents as tools limits their capabilities."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

The "Agents are not tools" post elaborates at length *(community content — Google Developer Forum)*:

> "The tool interface is a degenerative case of the agent interface. Agent as a tool should only be used in the situations where the degenerative case is the only one you wish to support, i.e. that the agent can take an action and see it completed or error and not reach an interrupted state that needs resumption."
> — Source: [Agents are not tools — Google Developer Forums](https://discuss.google.dev/t/agents-are-not-tools/192812)

### 5.3 Anti-Pattern: Uncontrolled Agent Autonomy

Microsoft's Magentic-One experience (Nov 2024 ⚠️ Source is >12 months old) revealed real risks during research evaluation — this is a cautionary disclosure, not a production incident:

> "During development, a misconfiguration led agents to repeatedly attempt and fail to log into a WebArena website. This resulted in the account being temporarily suspended. The agents then tried to reset the account's password. Even more concerning were cases in which agents, until explicitly stopped, attempted to recruit human assistance by posting on social media, emailing textbook authors, or even drafting a freedom of information request to a government entity."
> — Source: [Magentic-One — Microsoft Research](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/)

### 5.4 Anti-Pattern: Framework Abstraction Obscuring Behavior

> "Frameworks can help you get started quickly, but don't hesitate to reduce abstraction layers and build with basic components as you move to production. By following these principles, you can create agents that are not only powerful but also reliable, maintainable, and trusted by their users."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

> "However, they often create extra layers of abstraction that can obscure the underlying prompts and responses, making them harder to debug. They can also make it tempting to add complexity when a simpler setup would suffice."
> — Source: [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)

### 5.5 Anti-Pattern: Using Handoffs When You Need Parallel Execution

LangChain's performance comparison shows that handoffs are inefficient for multi-domain tasks:

> "Handoffs executes sequentially — can't research all three languages in parallel. Growing conversation history adds overhead."
> — Source: [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/)

---

## 6. Our Demo's Fit: Zava Smart Order Feasibility

### Architecture Recap

- **Agent A (Foundry V2):** Customer-facing agent. Receives user query ("Can Zava fulfill 500 Model-X pump assemblies by Aug 15?"). Uses Code Interpreter to render charts.
- **Agent B (LangGraph on AKS):** Manufacturing ops agent. Queries fake operations data (inventory, production schedule, quality metrics). Returns feasibility analysis.
- **Communication:** A2A protocol. Agent A is the A2A *client*; Agent B is the A2A *server*.

### Pattern Match: Orchestrator + Specialist Worker

The Zava demo maps cleanly to the **orchestrator + specialist worker** pattern (called "orchestrator-workers" by Anthropic ([source](https://www.anthropic.com/engineering/building-effective-agents)), "subagents" by LangChain ([source](https://docs.langchain.com/oss/python/langchain/multi-agent/)), and demonstrated by Microsoft's Magentic-One ([source](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/))):

1. **Agent A is the orchestrator.** It receives the user request, determines it needs operations data, invokes Agent B via A2A, and synthesizes the result (including generating a chart via Code Interpreter).
2. **Agent B is the specialist worker.** It has domain-specific knowledge (access to inventory/production data), performs a focused task (feasibility computation), and returns an artifact (feasibility analysis).
3. **The user only interacts with Agent A.** Agent B is opaque to the user — exactly as A2A intends per the protocol's opacity principle ([What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)).
4. **The interaction is task-oriented, not conversational.** Agent A sends a task; Agent B processes and returns results. This is the simplest, most predictable A2A interaction.

### Recommended Pattern Label

**"Orchestrator + Specialist Worker"** (or equivalently, "Subagent" in LangChain's terminology — [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/)).

This label is:
- Immediately recognizable to architects familiar with multi-agent literature
- Consistent with terminology used by Anthropic ([source](https://www.anthropic.com/engineering/building-effective-agents)), LangChain ([source](https://docs.langchain.com/oss/python/langchain/multi-agent/)), Microsoft Research ([source](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/)), and the A2A project
- Accurate for the demo's topology (single orchestrator, single specialist, unidirectional delegation)

### Why Not Other Patterns?

| Alternative | Why it doesn't fit |
|---|---|
| **Handoff** | No control transfer. Agent A retains control throughout. User never interacts with Agent B. |
| **Pipeline** | Only two agents; no sequential chain. The interaction is request-response, not staged. |
| **Peer-to-peer** | The relationship is asymmetric (client/server), not symmetric. |
| **Broker** | There are only two agents; no dynamic discovery needed. Agent A is pre-configured to know Agent B. |

### A2A Interaction Flow for the Demo

```
User ──► Agent A (Foundry, A2A Client)
              │
              ├─ 1. Discover Agent B (fetch Agent Card from known URL)
              ├─ 2. sendMessage → Agent B (LangGraph, A2A Server)
              │       └─ Agent B queries inventory/production data
              │       └─ Agent B returns Task with Artifact (feasibility JSON)
              ├─ 3. Synthesize response + render chart (Code Interpreter)
              └─ 4. Return final response to User
```

This maps to the A2A request lifecycle described in the official docs:

> "The AI assistant, now acting as an orchestrator, receives the cohesive information from all the A2A-enabled agents. It then presents a single, complete travel plan as a seamless response to the user's initial prompt."
> — Source: [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/)

---

## 7. Research Limitations

- **Microsoft AI Foundry A2A documentation:** Several Microsoft Learn URLs for A2A-specific Foundry documentation returned 404 errors. The A2A integration in Foundry V2 may be too new for stable documentation as of May 2026, or URLs may have changed. This limited ability to verify Foundry-specific A2A patterns.
- **Google Cloud A2A blog post:** The original Google Cloud blog URL for the A2A announcement returned 404; the Google Developers blog version was accessible instead.
- **Production case studies scarce:** While many partners have endorsed A2A, **no detailed published production case studies** with architecture diagrams and production metrics were found. Most evidence comes from official protocol docs, vendor demos, framework patterns, and partner endorsement quotes rather than independent post-mortems. Each example in the report body is labeled with an evidence-type tag (`production case study`, `vendor demo`, `framework pattern`, `partner endorsement`, or `conceptual example`) so readers can judge the strength of evidence independently.
- **Stale sources:** Several influential sources cited in this report are older than 12 months relative to the report date (2026-05-20): Anthropic "Building Effective Agents" (Dec 2024), Microsoft Magentic-One (Nov 2024), LangGraph Multi-Agent Workflows blog (Jan 2024), and Google A2A launch blog (Apr 2025). Each is flagged inline with `⚠️ Source is >12 months old`. The A2A protocol documentation itself is current (v1.0.0, last updated May 2026).
- **Unverifiable citations:** Two source URLs could not be fully verified via automated fetch: OpenAI's "New tools for building agents" returned HTTP 403 (archived copy verified), and the LangGraph `concepts/multi_agent/` URL now redirects to a new docs path (redirect target verified). Both are noted inline.
- **Anti-pattern evidence is anecdotal:** Criticism of multi-agent systems comes primarily from Anthropic's "Building Effective Agents" post and Microsoft's Magentic-One risks disclosure. Systematic studies of A2A anti-patterns in production are not yet published.
- **A2A v1.0.0 is recent:** The protocol reached 1.0.0 only recently; the ecosystem is still maturing. Pattern guidance may evolve.

---

## 8. Complete Reference List

### Documentation & Articles

- [A2A Protocol Homepage](https://a2a-protocol.org/latest/) — A2A Protocol project, Linux Foundation. Official documentation site (v1.0.0, living docs as of 2026-05-19). Cited for Cisco agntcy listing.
- [What is A2A? — A2A Protocol](https://a2a-protocol.org/latest/topics/what-is-a2a/) — Introduction to A2A, design principles, trip planning scenario, opacity principle. Cited in Sections 1, 2.1, 2.5, 2.6, 5.2, 6.
- [Core Concepts — A2A Protocol](https://a2a-protocol.org/latest/topics/key-concepts/) — Agent Cards, Tasks, Messages, Parts, Artifacts. Cited in Section 1.
- [A2A and MCP — A2A Protocol](https://a2a-protocol.org/latest/topics/a2a-and-mcp/) — A2A vs. MCP comparison, auto repair shop scenario, customer service delegation. Cited in Sections 2.5, 3.1.
- [Agent Discovery — A2A Protocol](https://a2a-protocol.org/latest/topics/agent-discovery/) — Well-known URIs, curated registries, direct configuration. Cited in Section 2.4.
- [Enterprise Features — A2A Protocol](https://a2a-protocol.org/latest/topics/enterprise-ready/) — Security, authentication, authorization, observability, governance, API management. Cited in Sections 2.6, 4.
- [A2A Protocol Specification](https://a2a-protocol.org/latest/specification/) — Full technical specification (v1.0.0). Background reference.
- [Announcing A2A — Google Developers Blog](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/) — Google, published 2025-04-09 ⚠️ Source is >12 months old. A2A launch, 50+ partner list, candidate sourcing demo, enterprise workflow quotes.
- [Agents are not tools — Google Developer Forums](https://discuss.google.dev/t/agents-are-not-tools/192812) — Community content. Technical argument for A2A over tool-wrapping. Supplemental to official docs.
- [Building Effective AI Agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents) — Anthropic, published 2024-12-19 ⚠️ Source is >12 months old. Orchestrator-workers, prompt chaining, customer support, anti-patterns.
- [Multi-agent — LangChain Docs](https://docs.langchain.com/oss/python/langchain/multi-agent/) — LangChain, living docs. Subagents, Handoffs, performance comparisons.
- [LangGraph: Multi-Agent Workflows — LangChain Blog](https://blog.langchain.dev/langgraph-multi-agent-workflows/) — LangChain, published January 2024 ⚠️ Source is >12 months old. Now redirects to `www.langchain.com/blog/langgraph-multi-agent-workflows`. Supervisor pattern, GPT-Newspaper example.
- [LangGraph Graph API — LangChain Docs](https://docs.langchain.com/oss/python/langgraph/graph-api) — LangChain, living docs. Redirect target of former `langchain-ai.github.io/langgraph/concepts/multi_agent/`. Command-based handoffs.
- [Interrupts — LangChain Docs](https://docs.langchain.com/oss/python/langgraph/interrupts) — LangChain, living docs. `interrupt()` for human-in-the-loop pausing.
- [Magentic-One — Microsoft Research](https://www.microsoft.com/en-us/research/blog/magentic-one-a-generalist-multi-agent-system-for-solving-complex-tasks/) — Microsoft Research, published 2024-11-04 ⚠️ Source is >12 months old. Multi-agent architecture, benchmark evaluations, risk disclosures.
- [New tools for building agents — OpenAI](https://openai.com/index/new-tools-for-building-agents/) — OpenAI, published 2025-03-11. ⚠️ Source returned 403 to public fetch. Archived copy verified at [Wayback Machine (2025-03-12)](https://web.archive.org/web/20250312/https://openai.com/index/new-tools-for-building-agents/). Agents SDK, handoffs.

### GitHub Repositories

- [a2aproject/A2A](https://github.com/a2aproject/A2A) — Core A2A protocol specification and documentation (Linux Foundation, Apache 2.0). Cited for README quotes and healthcare course reference.
- [a2aproject/a2a-samples](https://github.com/a2aproject/a2a-samples) — Official A2A code samples in Python, Go, .NET, Java, JavaScript. Listed as reference; not materially cited in the report body.
