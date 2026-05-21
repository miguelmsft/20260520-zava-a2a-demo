# Research Report: A2A (Agent-to-Agent) Protocol

**Date:** 2026-05-20
**Researcher:** Copilot Web Researcher Agent
**Topic slug:** a2a-protocol
**Sources consulted:** 40 total references: 24 documentation & articles, 12 GitHub repositories, 4 code samples

---

## Executive Summary

The Agent-to-Agent (A2A) Protocol is an open standard for enabling communication and interoperability between independent AI agent systems. Originally developed by Google and now donated to the Linux Foundation, A2A v1.0 provides a production-ready specification for agents to discover each other's capabilities, negotiate interaction modalities, and collaborate on tasks — all without exposing internal state, memory, or tools.

A2A uses familiar web standards: HTTP(S) for transport, JSON-RPC 2.0 (plus gRPC and HTTP+JSON/REST) for the wire protocol, and Server-Sent Events (SSE) for streaming. Agent discovery is accomplished via "Agent Cards" — JSON metadata documents served at well-known URIs. The protocol supports synchronous request/response, streaming, and asynchronous push notifications via webhooks, making it suitable for both quick queries and long-running, human-in-the-loop workflows. The protocol is at v1.0 (released mid-2025), with official SDKs in Python, JavaScript, Java, .NET, Go, and Rust. Framework support from LangGraph, CrewAI, Semantic Kernel, Microsoft Agent Framework, and others is already available.

### Foundry Agents V2 — A2A Compatibility Matrix (Zava Demo Critical Path)

The table below summarizes the current state of A2A support for Microsoft Foundry Agents V2, based on official documentation and samples as of 2026-05-20. **A2A is explicitly labeled "preview" by Microsoft for Foundry Agent Service.**

> "Foundry Agent Service supports the OpenResponses and Activity Protocols for Microsoft 365 publishing, an Invocations protocol for flexible endpoint integration with custom apps and services, and the A2A protocol (preview) for agent-to-agent communication."
> — Source: [Azure AI Foundry Agents Overview](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview)

| Capability | Protocol Version | Status | Mechanism | Evidence |
| :--- | :---: | :--- | :--- | :--- |
| **A2A Server (incoming — expose Foundry agent as A2A endpoint)** | **0.3** | ✅ Native (preview) | Foundry Agent Service exposes the agent as an A2A 0.3 server at a platform-managed URL. Entra ID auth required for callers. | [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint); [Foundry Agents research](research/2026-05-20-foundry-agents.md) |
| **A2A Server (Python adapter — custom hosting)** | 0.3 / 1.0 | ✅ Demonstrated | **Adapter pattern** — Python `a2a-sdk` + `azure-ai-projects` SDK. Three samples in `a2a-samples/python/agents/azureaifoundry_sdk`. | [Azure AI Foundry SDK A2A Samples](https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/azureaifoundry_sdk/README.md) (sample repo) |
| **A2A Server (.NET adapter — custom hosting)** | 0.3 / 1.0 | ✅ Demonstrated | **Adapter pattern** — Microsoft Agent Framework (`Microsoft.Agents.AI.Hosting.A2A.AspNetCore`) wraps a Foundry-backed agent as an A2A HTTP endpoint. Packages are `--prerelease`. | [MS Agent Framework A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a) (official docs) |
| **A2A Client (outbound — Foundry agent calls external A2A endpoints)** | **0.3** | ✅ Native (preview) | `A2APreviewTool` in `azure-ai-projects` SDK. Foundry agent calls any remote A2A endpoint via a configured project connection. | [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent); [Foundry Agents research](research/2026-05-20-foundry-agents.md) |
| **Foundry Hosted Agents + A2A** | 0.3 | 🔶 Preview | Hosted agents (code-based, containerized) are themselves in "preview" and are the most natural fit for running an A2A adapter. | [Foundry Agents Overview — Hosted agents](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview) |

**🎯 Zava-recommended path:** Foundry Agent (V2) acts as an **A2A 0.3 client** (outbound) using the native `A2APreviewTool`. The LangGraph agent on AKS acts as the **A2A server**, built with Python `a2a-sdk` 1.0.x in **0.3-compatibility mode**. No adapter/shim is required on the Foundry side. See [§3.8 A2A Version Interop for the Zava Demo](#38-a2a-version-interop-for-the-zava-demo) for detailed guidance.

**Key finding for Zava demo:** Foundry Agents V2 natively supports A2A **protocol version 0.3** — both as a server (incoming) and as a client (outbound via `A2APreviewTool`). This is a *platform-level* capability, not just an adapter pattern. The Python `a2a-sdk` 1.0.x provides a **compatibility mode for v0.3**, so the LangGraph server on AKS can be built with the latest SDK while still serving v0.3-compatible responses to Foundry's outbound A2A calls.

> "Foundry Agent Service supports A2A protocol version 0.3 only."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint), quoted in [Foundry Agents research](research/2026-05-20-foundry-agents.md)

### OpenAI Agents SDK — No A2A Support

The [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) (`openai-agents`) does **not** have built-in A2A support. The SDK's [README](https://github.com/openai/openai-agents-python/blob/main/README.md) lists Agents, Tools, Handoffs, Guardrails, Sessions, Tracing, and Realtime Agents as core concepts — A2A is not mentioned. The [official documentation](https://openai.github.io/openai-agents-python/) contains no reference to A2A. The [A2A Community Hub integrations list](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) does not include OpenAI Agents SDK. However, it would be possible to wrap an OpenAI Agents SDK agent in the Python `a2a-sdk` manually.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Origin & Governance](#2-origin--governance)
- [3. Wire-Level Protocol](#3-wire-level-protocol)
  - [3.8 A2A Version Interop for the Zava Demo](#38-a2a-version-interop-for-the-zava-demo)
- [4. Reference SDKs](#4-reference-sdks)
- [5. Authentication & Transport Security](#5-authentication--transport-security)
- [6. A2A vs MCP](#6-a2a-vs-mcp)
- [7. Framework Support (2025–2026)](#7-framework-support-20252026)
- [8. Public Examples & Resources](#8-public-examples--resources)
- [9. Caveats & Known Issues](#9-caveats--known-issues)
- [10. Research Limitations](#10-research-limitations)
- [11. Complete Reference List](#11-complete-reference-list)

---

## 1. Overview

### What It Is

A2A is an open standard designed to facilitate communication and interoperability between independent, potentially opaque AI agent systems.

> "The Agent2Agent (A2A) Protocol is an open standard designed to facilitate communication and interoperability between independent, potentially opaque AI agent systems. In an ecosystem where agents might be built using different frameworks, languages, or by different vendors, A2A provides a common language and interaction model."
> — Source: [A2A Protocol Specification](https://a2a-protocol.org/latest/specification/) ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md))

### Why It Matters

As AI agents proliferate across different vendors and frameworks, they need a common way to communicate. A2A enables:

- **Breaking down silos** — Connect agents across different ecosystems ([A2A Specification §1](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md))
- **Complex collaboration** — Specialized agents work together on tasks no single agent can handle alone
- **Preserved opacity** — Agents collaborate without sharing internal memory, proprietary logic, or tool implementations
- **Enterprise readiness** — Built-in support for authentication, authorization, security, and observability ([Enterprise Implementation](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/enterprise-ready.md))

### Key Features

- **Standardized Communication:** JSON-RPC 2.0 over HTTP(S), plus gRPC and HTTP+JSON/REST protocol bindings
- **Agent Discovery:** Via "Agent Cards" — JSON metadata documents detailing capabilities and connection info
- **Flexible Interaction:** Supports synchronous request/response, streaming (SSE), and asynchronous push notifications (webhooks)
- **Rich Data Exchange:** Handles text, files (inline or by URL), and structured JSON data via "Parts"
- **Task Lifecycle:** Stateful tasks with defined state machine (submitted → working → completed/failed/canceled/rejected)
- **Extensions:** Mechanism for agents to declare custom protocol extensions

> "With A2A, agents can: Discover each other's capabilities. Negotiate interaction modalities (text, forms, media). Securely collaborate on long-running tasks. Operate without exposing their internal state, memory, or tools."
> — Source: [A2A README](https://github.com/a2aproject/A2A)

---

## 2. Origin & Governance

### Origin

A2A was originally developed by **Google** and has since been donated to the **Linux Foundation** under the **LF AI & Data** umbrella.

> "Originally developed by Google and now donated to the Linux Foundation, A2A provides the definitive common language for agent interoperability in a world where agents are built using diverse frameworks and by different vendors."
> — Source: [A2A Documentation Index](https://a2a-protocol.org/latest/) ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/index.md))

IBM Research's ACP (Agent Communication Protocol) also merged into the A2A project under the Linux Foundation:

> "ACP Joins Forces with A2A Under the Linux Foundation's LF AI & Data"
> — Source: [IBM Research / LF AI blog](https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/) (linked from [A2A Partners page](https://github.com/a2aproject/A2A/blob/main/docs/partners.md))

### Current Spec Version

**v1.0.0** (latest released version, production-ready).

Previous versions: `0.3.0`, `0.2.6`, `0.1.0`.

> "Latest Released Version 1.0.0"
> — Source: [A2A Protocol Specification](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### What's New in v1.0

The v1.0 release focused on four themes:

1. **Protocol Maturity and Standardization** — `a2a.proto` elevated to the universal normative source of truth; multi-protocol bindings (JSON-RPC, gRPC, HTTP+JSON/REST); enhanced versioning.
2. **Enhanced Type Safety and Clarity** — Enum values changed from `kebab-case` to `SCREAMING_SNAKE_CASE` (breaking); removal of `kind` discriminator fields; stricter timestamp specs.
3. **Improved Developer Experience** — Renamed operations (e.g., `message/send` → `SendMessage`); simplified ID format (UUIDs instead of compound IDs); protocol versioning per interface.
4. **Enterprise-Ready Features** — Signed Agent Cards (JWS + RFC 8785 canonicalization); modern OAuth 2.0 flows (Device Code, PKCE); cursor-based pagination; multi-tenancy support.

> "The v1.0 release represents a significant maturation of the protocol with enhanced clarity, stronger specifications, and important structural improvements."
> — Source: [What's New in A2A Protocol v1.0](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/whats-new-v1.md)

### Official Repos and Docs

| Resource | URL |
| :--- | :--- |
| Spec + Docs site | [https://a2a-protocol.org](https://a2a-protocol.org) |
| GitHub org | [https://github.com/a2aproject](https://github.com/a2aproject) |
| Main spec repo | [https://github.com/a2aproject/A2A](https://github.com/a2aproject/A2A) |
| Python SDK | [https://github.com/a2aproject/a2a-python](https://github.com/a2aproject/a2a-python) |
| JS SDK | [https://github.com/a2aproject/a2a-js](https://github.com/a2aproject/a2a-js) |
| .NET SDK | [https://github.com/a2aproject/a2a-dotnet](https://github.com/a2aproject/a2a-dotnet) |
| Java SDK | [https://github.com/a2aproject/a2a-java](https://github.com/a2aproject/a2a-java) |
| Go SDK | [https://github.com/a2aproject/a2a-go](https://github.com/a2aproject/a2a-go) |
| Rust SDK | [https://github.com/a2aproject/a2a-rs](https://github.com/a2aproject/a2a-rs) |
| Samples | [https://github.com/a2aproject/a2a-samples](https://github.com/a2aproject/a2a-samples) |
| Inspector | [https://github.com/a2aproject/a2a-inspector](https://github.com/a2aproject/a2a-inspector) |

### Who Maintains It

The protocol is now governed by a **technical steering committee** under the Linux Foundation's LF AI & Data, with representatives from major technology companies. Google remains a primary contributor alongside partners including Microsoft, IBM, AWS, Salesforce, SAP, and 150+ other organizations listed on the [partners page](https://github.com/a2aproject/A2A/blob/main/docs/partners.md).

> "The protocol is guided by a technical steering committee with representatives from eight major technology companies."
> — Source: [A2A Protocol Ships v1.0](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/announcing-1.0.md)

---

## 3. Wire-Level Protocol

### 3.1 Architecture Layers

The A2A spec is organized into three layers:

```
┌─────────────────────────────────────────────────────┐
│  Layer 3: Protocol Bindings                         │
│  JSON-RPC  |  gRPC  |  HTTP+JSON/REST  |  Custom   │
├─────────────────────────────────────────────────────┤
│  Layer 2: Abstract Operations                       │
│  SendMessage | GetTask | CancelTask | ListTasks ... │
├─────────────────────────────────────────────────────┤
│  Layer 1: Canonical Data Model (a2a.proto)          │
│  Task | Message | Part | Artifact | AgentCard ...   │
└─────────────────────────────────────────────────────┘
```

- **Layer 1 (Data Model):** Defined in Protocol Buffers (`specification/a2a.proto`) — this is the single normative source of truth.
- **Layer 2 (Operations):** Binding-independent operations: `SendMessage`, `SendStreamingMessage`, `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, push notification CRUD, `GetExtendedAgentCard`.
- **Layer 3 (Bindings):** Concrete mappings to JSON-RPC 2.0, gRPC, and HTTP+JSON/REST.

> "The file `spec/a2a.proto` is the single authoritative normative definition of all protocol data objects and request/response messages."
> — Source: [A2A Protocol Specification §1.4](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 3.2 Transport

- **HTTP(S)** is the transport for JSON-RPC and HTTP+JSON/REST bindings
- **gRPC** (over HTTP/2 with TLS) is also supported as a first-class binding
- Production deployments **MUST** use HTTPS / TLS

### 3.3 JSON-RPC 2.0 Binding (Primary)

The JSON-RPC binding is the most commonly used. Key protocol details:

- **Content-Type:** `application/json` for requests/responses
- **Method naming:** PascalCase (e.g., `SendMessage`, `GetTask`)
- **Streaming:** Server-Sent Events (`text/event-stream`)
- **Service parameters:** Transmitted as HTTP headers (e.g., `A2A-Version`, `A2A-Extensions`)

#### Versioning

The `A2A-Version` header is how clients declare which protocol version they are using. Per the spec:

> "Clients MUST send the `A2A-Version` header with each request to maintain compatibility after an agent upgrades to a new version of the protocol (except for 0.3 Clients - 0.3 will be assumed for empty header)."
> — Source: [A2A Specification §3.6.1](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

> "Agents MUST interpret empty value as 0.3 version."
> — Source: [A2A Specification §3.6.2](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

This means: if you are building a **v1.0 client**, you **must** send `A2A-Version: 1.0`. Omitting the header causes the server to assume v0.3 semantics.

**Example JSON-RPC v1.0 request:**

```http
POST /rpc HTTP/1.1
Host: agent.example.com
Content-Type: application/json
Authorization: Bearer token
A2A-Version: 1.0

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "SendMessage",
  "params": {
    "message": {
      "role": "ROLE_USER",
      "parts": [{"text": "What is the exchange rate from USD to EUR?"}],
      "messageId": "msg-uuid-123"
    }
  }
}
```
— Source: [A2A Specification §9](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md) | Provenance: adapted from spec examples with corrected `A2A-Version: 1.0` header for v1.0 semantics

Note: v1.0 uses `ROLE_USER` (SCREAMING_SNAKE_CASE) and does not include `kind` discriminator fields. The v0.3 equivalents would be `"role": "user"` and `"kind": "message"` / `"kind": "text"` on parts.

### 3.4 Streaming (SSE)

For `SendStreamingMessage` and `SubscribeToTask`, the server returns `Content-Type: text/event-stream`:

```text
data: {"jsonrpc": "2.0", "id": 1, "result": {"task": { ... }}}

data: {"jsonrpc": "2.0", "id": 1, "result": {"statusUpdate": { ... }}}

data: {"jsonrpc": "2.0", "id": 1, "result": {"artifactUpdate": { ... }}}
```

Two stream patterns exist:
1. **Message-only stream:** Single `Message` object, then stream closes.
2. **Task lifecycle stream:** Starts with `Task` object, followed by zero or more `TaskStatusUpdateEvent` / `TaskArtifactUpdateEvent`, closes when task reaches a terminal state.

> "The specific version of the A2A protocol in use is identified using the `Major.Minor` elements (e.g. `1.0`) of the corresponding A2A specification version."
> — Source: [A2A Specification §3.6](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 3.5 Task Lifecycle & States

Tasks progress through a defined state machine. The normative states are defined in `a2a.proto` (transcribed verbatim from the enum):

> ```protobuf
> enum TaskState {
>   TASK_STATE_UNSPECIFIED = 0;
>   TASK_STATE_SUBMITTED = 1;
>   TASK_STATE_WORKING = 2;
>   TASK_STATE_COMPLETED = 3;
>   TASK_STATE_FAILED = 4;
>   TASK_STATE_CANCELED = 5;
>   TASK_STATE_INPUT_REQUIRED = 6;
>   TASK_STATE_REJECTED = 7;
>   TASK_STATE_AUTH_REQUIRED = 8;
> }
> ```
> — Source: [specification/a2a.proto](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto) (verbatim transcription)

| State | Value | Description (from proto comments) | Terminal? |
| :--- | :---: | :--- | :---: |
| `TASK_STATE_UNSPECIFIED` | 0 | "The task is in an unknown or indeterminate state." | — |
| `TASK_STATE_SUBMITTED` | 1 | "a task has been successfully submitted and acknowledged." | No |
| `TASK_STATE_WORKING` | 2 | "a task is actively being processed by the agent." | No |
| `TASK_STATE_COMPLETED` | 3 | "a task has finished successfully. This is a terminal state." | **Yes** |
| `TASK_STATE_FAILED` | 4 | "a task has finished with an error. This is a terminal state." | **Yes** |
| `TASK_STATE_CANCELED` | 5 | "a task was canceled before completion. This is a terminal state." | **Yes** |
| `TASK_STATE_INPUT_REQUIRED` | 6 | "the agent requires additional user input to proceed. This is an interrupted state." | Interrupted |
| `TASK_STATE_REJECTED` | 7 | "the agent has decided to not perform the task." | **Yes** |
| `TASK_STATE_AUTH_REQUIRED` | 8 | "authentication is required to proceed. This is an interrupted state." | Interrupted |

**Key behavior:** Once a task reaches a terminal state, it is **immutable** — subsequent interactions must initiate a new task within the same `contextId`.

> "Once a task reaches a terminal state (completed, canceled, rejected, or failed), it cannot restart. Any subsequent interaction related to that task, such as a refinement, must initiate a new task within the same contextId."
> — Source: [Life of a Task](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/life-of-a-task.md)

### 3.6 Agent Card Discovery

An **Agent Card** is a JSON metadata document describing an agent's identity, capabilities, skills, service endpoint, and authentication requirements.

**Discovery methods:**

1. **Well-Known URI:** `https://{domain}/.well-known/agent-card.json` (following RFC 8615)
2. **Curated Registries:** Central catalog/marketplace queried by skill, tags, etc.
3. **Direct Configuration:** Hardcoded URLs, environment variables, config files

— Source: [Agent Discovery](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/agent-discovery.md)

**Agent Card structure (key fields):**

- `name`, `description`, `version` — identity
- `supportedInterfaces[]` — array of `AgentInterface` objects, each with `url`, `protocolBinding` (e.g., `"JSONRPC"`, `"GRPC"`, `"HTTP+JSON"`), and `protocolVersion`
- `capabilities` — streaming, push notifications, extended agent card support
- `skills[]` — array of `AgentSkill` objects (id, name, description, tags, examples, input/output modes)
- `securitySchemes`, `security` — authentication requirements
- `extensions[]` — custom protocol extensions

> "The Agent Card is a JSON metadata document published by an A2A Server, describing its identity, capabilities, skills, service endpoint, and authentication requirements."
> — Source: [A2A Specification §2.2](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 3.7 Content & Part Types

The `Part` object is the atomic content container. From `a2a.proto` (verbatim):

> ```protobuf
> message Part {
>   oneof content {
>     // The string content of the `text` part.
>     string text = 1;
>     // The `raw` byte content of a file. In JSON serialization, this is encoded as a base64 string.
>     bytes raw = 2;
>     // A `url` pointing to the file's content.
>     string url = 3;
>     // Arbitrary structured `data` as a JSON value (object, array, string, number, boolean, or null).
>     google.protobuf.Value data = 4;
>   }
>   // Optional. metadata associated with this part.
>   google.protobuf.Struct metadata = 5;
>   // An optional `filename` for the file (e.g., "document.pdf").
>   string filename = 6;
>   // The `media_type` (MIME type) of the part content (e.g., "text/plain", "application/json", "image/png").
>   // This field is available for all part types.
>   string media_type = 7;
> }
> ```
> — Source: [specification/a2a.proto](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto) (verbatim transcription, fetched 2026-05-20)

| Part field | Content type |
| :--- | :--- |
| `text` | Plain text string |
| `raw` | Inline binary data (byte array; base64 in JSON) |
| `url` | URI reference to external content |
| `data` | Arbitrary structured JSON (`google.protobuf.Value` — object, array, string, number, boolean, or null) |

Each `Part` also supports `media_type` (MIME type), `filename`, and `metadata` (a `google.protobuf.Struct` for additional key-value metadata separate from the content itself).

Note: In v0.3, structured data was carried in a separate `DataPart` type. In v1.0, the unified `Part` message includes `data` as field 4 within the `oneof content` block, alongside `text`, `raw`, and `url`. The `metadata` field (field 5) serves a different purpose — it carries optional metadata *about* the part, not the primary structured content. Both `data` and `metadata` coexist in the v1.0 `Part` message. — Source: [specification/a2a.proto](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto); [What's New in v1.0](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/whats-new-v1.md)

### 3.8 A2A Version Interop for the Zava Demo

This subsection addresses the **critical version-interop question** for the Zava Smart Order Feasibility demo: how does the Foundry Agent (V2) using A2A 0.3 communicate with a LangGraph server built with the Python `a2a-sdk` 1.0.x?

#### Foundry's A2A endpoint uses protocol 0.3

The Foundry Agents research confirms that Foundry Agent Service supports **A2A protocol version 0.3 only** — both for incoming A2A (exposing Foundry as a server) and outbound A2A (Foundry as a client calling external endpoints via `A2APreviewTool`).

> "Foundry Agent Service supports A2A protocol version 0.3 only."
> — Source: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint), quoted in [Foundry Agents research](research/2026-05-20-foundry-agents.md)

The Foundry agent's A2A client will send requests using **v0.3 method names** (`message/send`, `tasks/get`, etc.) and will **not** send an `A2A-Version` header (or will send it empty). Per the A2A spec (§3.6.2), servers MUST interpret an empty `A2A-Version` header as v0.3.

#### Python `a2a-sdk` 1.0.x has compatibility mode for 0.3

The official Python SDK implements A2A spec v1.0 but explicitly provides a **compatibility mode for v0.3**:

> "This SDK implements the A2A Protocol Specification `1.0`, with compatibility mode for `0.3`."
> — Source: [a2a-python README — Compatibility](https://github.com/a2aproject/a2a-python)

The compatibility matrix from the README confirms full v0.3 support across all transports (JSON-RPC, HTTP+JSON/REST, gRPC) for both client and server roles. — Source: [a2a-python README](https://github.com/a2aproject/a2a-python)

#### Zava demo direction: Foundry (client) → LangGraph (server)

In the Zava demo architecture:

1. **Foundry Agent (V2)** acts as the **A2A client** — it uses the native `A2APreviewTool` to call the LangGraph agent's A2A endpoint on AKS.
2. **LangGraph Agent on AKS** acts as the **A2A server** — it exposes a v0.3-compatible A2A endpoint.

The Foundry agent's outbound A2A call will use v0.3 wire format:
- Method names: `message/send`, `message/stream`, `tasks/get` (v0.3 naming)
- No `A2A-Version` header (Foundry uses 0.3, which is the default when the header is absent)
- Enum values: `kebab-case` (`"role": "user"`, `"state": "completed"`)
- `kind` discriminator fields present on parts and messages

#### Implementation requirements for the LangGraph A2A server

The LangGraph A2A server on AKS **SHOULD NOT** require `A2A-Version: 1.0` header semantics from Foundry's client. Specifically:

- **Build with `a2a-sdk` 1.0.x in 0.3-compatibility mode.** The SDK automatically handles v0.3 wire format when the client omits the `A2A-Version` header or sends it empty.
- **Use v0.3-style method names** in the Agent Card and server routing: `message/send`, `tasks/get`, etc.
- **Accept v0.3 enum values** (`kebab-case`): `"role": "user"`, `"state": "completed"`, etc.
- **Accept `kind` discriminator fields** on parts and messages (v0.3 uses `"kind": "text"`, `"kind": "message"`).

#### Practical recommendation

1. Install `a2a-sdk` 1.0.x with HTTP server extras: `pip install "a2a-sdk[http-server]"`
2. Build the LangGraph A2A server following the pattern in the [LangGraph sample](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/langgraph), which already uses v0.3-style wire format on the wire even though it imports from the v1.0 SDK.
3. **Test by sending a v0.3 JSON-RPC payload** before integrating with Foundry:

```bash
# Test v0.3 compatibility — send a message/send request without A2A-Version header
curl -X POST http://localhost:9999/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "message/send",
    "params": {
      "message": {
        "role": "user",
        "kind": "message",
        "parts": [{"kind": "text", "text": "Can we fulfill 500 units of ZP-7000 by July 15?"}],
        "messageId": "test-msg-001"
      }
    }
  }'
```
> — Source: Synthesized from [A2A Specification](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md) v0.3 method naming and [a2a-python README](https://github.com/a2aproject/a2a-python) compatibility mode | Provenance: synthesized

4. Verify the response uses v0.3 format (`"state": "completed"`, `"kind": "message"`, etc.).
5. Once the v0.3 test passes, configure the Foundry agent's A2A connection to point to the AKS endpoint.

#### Summary

| Component | Role | A2A Version | Implementation |
| :--- | :--- | :---: | :--- |
| Foundry Agent (V2) | A2A Client (outbound) | **0.3** | Native `A2APreviewTool` — no code needed |
| LangGraph Agent (AKS) | A2A Server | **0.3** (compat) | Python `a2a-sdk` 1.0.x in 0.3-compatibility mode |

---

## 4. Reference SDKs

### 4.1 Python SDK (`a2a-sdk`)

The official Python SDK is the most mature. It implements A2A spec v1.0 with backward compatibility for v0.3.

**Installation:**

```bash
# Core SDK
pip install a2a-sdk

# With HTTP server support (FastAPI/Starlette)
pip install "a2a-sdk[http-server]"

# With gRPC support
pip install "a2a-sdk[grpc]"

# All extras
pip install "a2a-sdk[all]"
```
— Source: [a2a-python README](https://github.com/a2aproject/a2a-python) | Provenance: verbatim

**Compatibility matrix:**

> The Python SDK supports both v1.0 and v0.3 across all transports:

| Spec Version | Transport | Client | Server |
| :--- | :--- | :---: | :---: |
| **1.0** | JSON-RPC | ✅ | ✅ |
| **1.0** | HTTP+JSON/REST | ✅ | ✅ |
| **1.0** | gRPC | ✅ | ✅ |
| **0.3** (compat) | JSON-RPC | ✅ | ✅ |
| **0.3** (compat) | HTTP+JSON/REST | ✅ | ✅ |
| **0.3** (compat) | gRPC | ✅ | ✅ |

— Source: [a2a-python README](https://github.com/a2aproject/a2a-python) | Provenance: verbatim from compatibility matrix in README

**Minimal A2A Server (Python) — skeleton excerpt:**

The following is adapted from the official helloworld sample. It is a **skeleton excerpt** — the `HelloWorldAgentExecutor` class is defined in a separate file (`agent_executor.py`) in the [full sample](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld). See the full sample for the complete runnable code.

```python
# Source: https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/__main__.py
import uvicorn
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill
from starlette.applications import Starlette

# Import your agent executor (implements AgentExecutor interface)
# See: https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/agent_executor.py
from agent_executor import HelloWorldAgentExecutor

skill = AgentSkill(
    id='hello_world',
    name='Returns hello world',
    description='just returns hello world',
    tags=['hello world'],
    examples=['hi', 'hello world'],
)

agent_card = AgentCard(
    name='Hello World Agent',
    description='Just a hello world agent',
    version='0.0.1',
    default_input_modes=['text/plain'],
    default_output_modes=['text/plain'],
    capabilities=AgentCapabilities(streaming=True, extended_agent_card=True),
    supported_interfaces=[
        AgentInterface(protocol_binding='JSONRPC', url='http://127.0.0.1:9999')
    ],
    skills=[skill],
)

request_handler = DefaultRequestHandler(
    agent_executor=HelloWorldAgentExecutor(),
    task_store=InMemoryTaskStore(),
    agent_card=agent_card,
)

routes = []
routes.extend(create_agent_card_routes(agent_card))
routes.extend(create_jsonrpc_routes(request_handler, '/'))

app = Starlette(routes=routes)
uvicorn.run(app, host='127.0.0.1', port=9999)
```
— Source: [helloworld sample `__main__.py`](https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/__main__.py) | Provenance: adapted (simplified extended card) | Label: **skeleton excerpt** — requires `agent_executor.py` from [full sample](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld)

**Minimal A2A Client (Python):**

```python
# Source: https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/test_client.py
import asyncio
import httpx
from a2a.client import A2ACardResolver, ClientConfig, create_client
from a2a.helpers import new_text_message
from a2a.types.a2a_pb2 import Role, SendMessageRequest

async def main() -> None:
    base_url = 'http://127.0.0.1:9999'

    async with httpx.AsyncClient() as httpx_client:
        # 1. Discover the agent card
        resolver = A2ACardResolver(httpx_client=httpx_client, base_url=base_url)
        agent_card = await resolver.get_agent_card()
        print(f'Discovered agent: {agent_card.name}')

        # 2. Create a non-streaming client
        config = ClientConfig(streaming=False)
        client = await create_client(agent=agent_card, client_config=config)

        # 3. Send a message
        message = new_text_message('Say hello.', role=Role.ROLE_USER)
        request = SendMessageRequest(message=message)

        async for chunk in client.send_message(request):
            print(chunk)

        await client.close()

if __name__ == '__main__':
    asyncio.run(main())
```
— Source: [helloworld test_client.py](https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/test_client.py) | Provenance: adapted

### 4.2 JavaScript/TypeScript SDK (`@a2a-js/sdk`)

```bash
npm install @a2a-js/sdk

# For Express server integration
npm install express

# For gRPC support
npm install @grpc/grpc-js @bufbuild/protobuf
```

The JS SDK currently implements **spec v0.3** on stable, with a v1.0 **alpha** available:

```bash
npm install @a2a-js/sdk@next
```

> "There is an alpha version available with support for v1.0 version. Development for this version is taking place in the epic/1.0_breaking_changes branch."
> — Source: [a2a-js README](https://github.com/a2aproject/a2a-js)

### 4.3 Other SDKs

| SDK | Package | Status |
| :--- | :--- | :--- |
| **.NET** | `dotnet add package A2A` ([NuGet](https://www.nuget.org/packages/A2A)) | Available |
| **Java** | Maven | Available |
| **Go** | `go get github.com/a2aproject/a2a-go` | Available |
| **Rust** | [a2a-rs](https://github.com/a2aproject/a2a-rs) (official) | Available |

— Source: [A2A README](https://github.com/a2aproject/A2A); [a2a-rs GitHub](https://github.com/a2aproject/a2a-rs)

---

## 5. Authentication & Transport Security

A2A delegates authentication to standard web mechanisms. The key principle:

> "A2A protocol payloads, such as JSON-RPC messages, don't carry user or client identity information directly. Identity is established at the transport/HTTP layer."
> — Source: [Enterprise Implementation of A2A](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/enterprise-ready.md)

### 5.1 Transport Security

- Production deployments **MUST** use HTTPS (TLS 1.2+ recommended, TLS 1.3+ preferred)
- HSTS headers **SHOULD** be enforced
- Server TLS certificates **SHOULD** be validated against trusted CAs

> "Production deployments MUST use encrypted communication (HTTPS for HTTP-based bindings, TLS for gRPC)."
> — Source: [A2A Specification §13.4](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 5.2 Supported Authentication Schemes

The Agent Card's `securitySchemes` field declares supported auth mechanisms. The `SecurityScheme` message in `a2a.proto` defines these as a `oneof`:

> ```protobuf
> message SecurityScheme {
>   oneof scheme {
>     APIKeySecurityScheme api_key_security_scheme = 1;
>     HTTPAuthSecurityScheme http_auth_security_scheme = 2;
>     OAuth2SecurityScheme oauth2_security_scheme = 3;
>     OpenIdConnectSecurityScheme open_id_connect_security_scheme = 4;
>     MutualTlsSecurityScheme mtls_security_scheme = 5;
>   }
> }
> ```
> — Source: [specification/a2a.proto](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto) (verbatim transcription)

| Scheme | Spec Object | Description |
| :--- | :--- | :--- |
| **API Key** | `APIKeySecurityScheme` | Key in header, query, or cookie |
| **HTTP Auth** | `HTTPAuthSecurityScheme` | Bearer tokens, Basic auth, etc. |
| **OAuth 2.0** | `OAuth2SecurityScheme` | Authorization Code (w/ PKCE), Client Credentials, Device Code |
| **OpenID Connect** | `OpenIdConnectSecurityScheme` | OIDC discovery-based auth |
| **Mutual TLS** | `MutualTlsSecurityScheme` | Client certificate authentication |

— Source: [A2A Specification §4.5](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md); [specification/a2a.proto](https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto)

### 5.3 What's Mandatory vs Optional

| Requirement | Status |
| :--- | :--- |
| HTTPS in production | **MUST** |
| Auth scheme declaration in Agent Card | **MUST** (if auth required) |
| Credential transmission via HTTP headers | **MUST** |
| Server-side validation of every request | **MUST** |
| OAuth 2.0 support | **OPTIONAL** (per agent) |
| Mutual TLS | **OPTIONAL** (per agent) |
| Signed Agent Cards (JWS) | **OPTIONAL** (new in v1.0) |
| PKCE for Authorization Code flow | Declared via `pkce_required` field |
| Deprecated flows (implicit, password) | **REMOVED in v1.0** |

> "Modern OAuth 2.0 flows — Added Device Code flow (RFC 8628), removed deprecated implicit/password flows."
> — Source: [What's New in v1.0](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/whats-new-v1.md)

### 5.4 Message Integrity & CORS

A2A v1.0 introduces **Agent Card signatures** using JWS (JSON Web Signatures) with RFC 8785 (JSON Canonicalization Scheme) for cryptographic verification of agent identity and metadata.

**CORS (Cross-Origin Resource Sharing):** The A2A protocol specification does **not** mention CORS. A full-text search of the [A2A Specification](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md) and the [Enterprise Implementation guide](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/enterprise-ready.md) for "CORS", "cors", "Cross-Origin", and "cross-origin" returned zero matches (verified 2026-05-20). CORS is therefore left to standard HTTP server configuration, consistent with A2A's principle of building on existing web infrastructure. For the Zava demo (browser-based React UI calling A2A endpoints), CORS headers will need to be configured on the A2A server — this is an implementation concern, not a protocol concern.

---

## 6. A2A vs MCP

A2A and MCP (Model Context Protocol) are **complementary, not competing** protocols.

> "MCP and A2A solve different layers of the problem. MCP is commonly used for tool and context integration at the individual agent level. A2A focuses on communication and coordination between agents. In practice, many systems will use both: MCP inside agents, A2A between agents."
> — Source: [A2A Protocol Ships v1.0](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/announcing-1.0.md)

| Dimension | A2A | MCP |
| :--- | :--- | :--- |
| **Scope** | Agent-to-agent communication | Agent-to-tool/resource connection |
| **Interaction model** | Multi-turn, stateful conversations | Structured function calls |
| **Participants** | Autonomous, opaque agents | Tools with defined inputs/outputs |
| **State management** | Tasks with lifecycle, context tracking | Typically stateless |
| **Use case** | Agent delegation, collaboration | Database queries, API calls, function invocation |

> "A2A focuses on agents partnering on tasks, whereas MCP focuses on agents using capabilities."
> — Source: [A2A and MCP: Detailed Comparison](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/a2a-and-mcp.md)

**Typical architecture:** A user talks to Agent A via A2A. Agent A delegates to Agent B via A2A. Each agent internally uses MCP to access its own tools (databases, APIs, file systems).

---

## 7. Framework Support (2025–2026)

### 7.1 Microsoft Foundry Agents V2 / Azure AI Foundry

**Status: A2A supported via adapter pattern; labeled "preview" by Microsoft.**

See the [Foundry Agents V2 Compatibility Matrix](#foundry-agents-v2--a2a-compatibility-matrix-zava-demo-critical-path) in the Executive Summary for the full breakdown.

Azure AI Foundry Agent Service can be exposed as an A2A server using the `Microsoft.Agents.AI.Hosting.A2A.AspNetCore` NuGet package (currently `--prerelease`). The official A2A samples repository contains a dedicated `azureaifoundry_sdk` directory with three examples:

1. **Calendar Agent** — Core Foundry + A2A integration
2. **Currency Agent** — Foundry + MCP + A2A with Azure Functions
3. **Multi-Agent System** — Foundry + A2A + Semantic Kernel orchestration

> "This directory contains three comprehensive examples demonstrating how to integrate Azure AI Foundry Agent Service with Google's Agent-to-Agent (A2A) Protocol."
> — Source: [Azure AI Foundry SDK A2A Samples README](https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/azureaifoundry_sdk/README.md)

The Microsoft Agent Framework (.NET) provides A2A integration (excerpt — see [full example on Microsoft Learn](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a) for the complete `Program.cs`):

```csharp
// Expose an agent via A2A protocol (C# / ASP.NET Core) — EXCERPT
// Source: https://learn.microsoft.com/en-us/agent-framework/integrations/a2a
app.MapA2A(pirateAgent, path: "/a2a/pirate", agentCard: new()
{
    Name = "Pirate Agent",
    Description = "An agent that speaks like a pirate.",
    Version = "1.0"
});
```
— Source: [Microsoft Agent Framework A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a) | Provenance: adapted | Label: **excerpt** — see linked page for complete `Program.cs`

**Note on native vs. adapter:** Foundry Agents V2 supports A2A natively at the platform level for both **incoming** (exposing the agent as an A2A 0.3 server) and **outbound** (calling external A2A endpoints via `A2APreviewTool`). This is documented in the [Foundry Agents research](research/2026-05-20-foundry-agents.md). Additionally, adapter/wrapper patterns exist for custom hosting scenarios:
- **.NET path:** The **Microsoft Agent Framework** provides the `Microsoft.Agents.AI.Hosting.A2A` library that wraps any Foundry-backed agent as an A2A-compliant HTTP endpoint.
- **Python path:** The Python samples in `a2a-samples` use the Azure AI Projects SDK (`azure-ai-projects`) to create the agent, then wrap it with the Python `a2a-sdk` as an A2A server.

The adapter patterns offer more flexibility (e.g., supporting both v0.3 and v1.0) but are not required for the Zava demo's primary use case (Foundry as A2A client calling LangGraph on AKS).

### 7.2 LangGraph / LangSmith

**Status: Built-in A2A support via LangSmith Agent Server (v0.3); standalone sample available via Python `a2a-sdk`.**

LangGraph agents deployed via LangSmith Agent Server automatically get an A2A endpoint at `/a2a/{assistant_id}`.

> "Agent2Agent (A2A) is Google's protocol for enabling communication between conversational AI agents. LangSmith implements A2A support, allowing your agents to communicate with other A2A-compatible agents through a standardized protocol."
> — Source: [LangSmith A2A Endpoint Docs](https://docs.langchain.com/langsmith/server-a2a)

Supported A2A RPC methods in LangSmith:
- `message/send` — Send message, receive complete response
- `message/stream` — Send message, stream SSE responses
- `tasks/get` — Retrieve task status/results

**⚠️ v0.3 vs v1.0 implications for the Zava demo:** These method names (`message/send`, `message/stream`, `tasks/get`) are the **v0.3** spec naming convention. The v1.0 equivalents are `SendMessage`, `SendStreamingMessage`, `GetTask`. The LangSmith A2A endpoint documentation does not reference v1.0 method names as of this research date.

The **official standalone LangGraph sample** in `a2a-samples/python/agents/langgraph` uses the **Python `a2a-sdk`** (which supports both v0.3 and v1.0). The sample's `__main__.py` imports from `a2a.server.apps`, `a2a.server.request_handlers`, and `a2a.types` — all v1.0 SDK types. However, the sample's README shows wire-format examples using **v0.3 conventions** (`"method": "message/send"`, `"kind": "message"`, `"role": "user"`, `"state": "completed"`), indicating the sample was written targeting v0.3 on the wire even while using the v1.0-compatible SDK.

> The sample README states: "Full compliance with A2A specifications" and demonstrates both synchronous and streaming interactions.
> — Source: [LangGraph Currency Agent README](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/langgraph)

**Interop recommendation for Zava demo:** Since the Python `a2a-sdk` supports both v0.3 and v1.0, a LangGraph agent wrapped with `a2a-sdk` can serve either version. **For the Zava demo, the LangGraph server must target v0.3** because Foundry's outbound A2A client uses protocol 0.3 only. Build with `a2a-sdk` 1.0.x in 0.3-compatibility mode and use v0.3-style method names (`message/send`, `tasks/get`). See [§3.8](#38-a2a-version-interop-for-the-zava-demo) for full interop guidance.

### 7.3 LangChain

LangChain itself is the foundational library; A2A integration comes through **LangGraph** (for agent orchestration) and **LangSmith Agent Server** (for deployment with A2A endpoints). LangChain is listed as an official A2A integration:

> The A2A Community Hub lists "LangGraph" under "A2A Integrations" with a link to the LangSmith server A2A docs.
> — Source: [A2A Community Hub](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) (verbatim entry: `[LangGraph](https://docs.langchain.com/langsmith/server-a2a)`)

### 7.4 Microsoft Agent Framework

**Status: A2A integration available.**

The Microsoft Agent Framework provides `Microsoft.Agents.AI.Hosting.A2A` and `Microsoft.Agents.AI.Hosting.A2A.AspNetCore` NuGet packages for exposing agents as A2A servers.

> "The Microsoft.Agents.AI.Hosting.A2A.AspNetCore library provides ASP.NET Core integration for exposing your agents via the A2A protocol."
> — Source: [Microsoft Agent Framework A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a)

It is also listed as an official A2A integration on the community page:

> The A2A Community Hub lists "Microsoft Agent Framework" under "A2A Integrations."
> — Source: [A2A Community Hub](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) (verbatim entry: `[Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/agent-types/a2a-agent)`)

### 7.5 OpenAI Agents SDK

**Status: No built-in A2A support found as of this research date (2026-05-20).**

Evidence for this negative finding:
- **GitHub repo:** [openai/openai-agents-python](https://github.com/openai/openai-agents-python) — The [README](https://github.com/openai/openai-agents-python/blob/main/README.md) lists core concepts (Agents, Sandbox Agents, Tools, Handoffs, Guardrails, Sessions, Tracing, Realtime Agents) with no mention of A2A.
- **Official docs:** [openai.github.io/openai-agents-python](https://openai.github.io/openai-agents-python/) — No reference to A2A found.
- **A2A community page:** The [A2A Community Hub integrations list](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) does not include OpenAI Agents SDK among frameworks with built-in A2A support.
- **A2A samples repo:** No dedicated sample exists in [a2a-samples](https://github.com/a2aproject/a2a-samples) for OpenAI Agents SDK.

However, it would be possible to wrap an OpenAI Agents SDK agent in the Python `a2a-sdk` manually — the same pattern used for LangGraph standalone samples.

### 7.6 Other Frameworks with A2A Support

Per the official community page, these frameworks have **built-in A2A integration** (verbatim list):

> - [Agent Development Kit (ADK)](https://google.github.io/adk-docs/a2a/)
> - [Agno](https://docs.agno.com/agent-os/interfaces/a2a/introduction)
> - [AG2](https://docs.ag2.ai/latest/docs/user-guide/a2a/)
> - [BeeAI Framework](https://framework.beeai.dev/integrations/a2a)
> - [CrewAI](https://docs.crewai.com/en/learn/a2a-agent-delegation)
> - [Hector](https://github.com/kadirpekel/hector)
> - [LangGraph](https://docs.langchain.com/langsmith/server-a2a)
> - [LiteLLM](https://docs.litellm.ai/docs/a2a)
> - [Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/user-guide/agents/agent-types/a2a-agent)
> - [Pydantic AI](https://ai.pydantic.dev/a2a/)
> - [Slide (Tyler)](https://slide.mintlify.app/guides/a2a-integration)
> - [Strands Agents](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/multi-agent/agent-to-agent/)
> — Source: [A2A Community Hub](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) (verbatim)

Semantic Kernel also supports A2A (in .NET), as cited by the A2A Community Hub:

> "Semantic Kernel now speaks A2A" — Asha Sharma, Head of AI Platform Product at Microsoft
> — Source: [LinkedIn post](https://www.linkedin.com/posts/aboutasha_a2a-ugcPost-7318649411704602624-0C_8), cited in [A2A Community Hub](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md). Note: This is a social media source (LinkedIn); no official Microsoft Learn or Semantic Kernel repo documentation was found to corroborate this claim independently.

---

## 8. Public Examples & Resources

### 8.1 Official Samples Repository

The [a2a-samples](https://github.com/a2aproject/a2a-samples) repository contains examples in Python, JavaScript, Go, .NET, and Java:

**Python agent samples:**
- `helloworld` — Minimal A2A server returning a message
- `langgraph` — LangGraph currency agent with streaming + push notifications
- `azureaifoundry_sdk` — Three Azure AI Foundry + A2A demos (calendar, currency, multi-agent)
- `ag2` — AG2 framework integration
- `crewai` — CrewAI integration

**.NET samples:**
- `BasicA2ADemo` — Simple A2A demo
- `A2ASemanticKernelDemo` — Semantic Kernel + A2A
- `A2ACliDemo` — CLI-based A2A demo

— Source: [a2a-samples](https://github.com/a2aproject/a2a-samples)

### 8.2 DeepLearning.AI Course

A short course on A2A built in partnership with Google Cloud and IBM Research:

> "Join this short course on A2A: The Agent2Agent Protocol, built in partnership with Google Cloud and IBM Research"
> — Source: [A2A README](https://github.com/a2aproject/A2A) | Link: [https://goo.gle/dlai-a2a](https://goo.gle/dlai-a2a)

### 8.3 Notable Blog Posts & Announcements (Past 12 Months)

- **[A2A Protocol Ships v1.0](https://a2a-protocol.org/latest/announcing-1.0/)** — Official v1.0 announcement
- **[Agent2Agent protocol is getting an upgrade](https://cloud.google.com/blog/products/ai-machine-learning/agent2agent-protocol-is-getting-an-upgrade)** — Google Cloud blog, July 2025
- **[A2A Extensions Empowering Custom Agent Functionality](https://developers.googleblog.com/en/a2a-extensions-empowering-custom-agent-functionality/)** — Google Developers blog, September 2025
- **[Microsoft: Empowering multi-agent apps with the open Agent2Agent (A2A) protocol](https://www.microsoft.com/en-us/microsoft-cloud/blog/2025/05/07/empowering-multi-agent-apps-with-the-open-agent2agent-a2a-protocol/)** — Microsoft Cloud blog, May 2025 (**unverified during research** — URL was unreachable due to HTTP throttling; cited from A2A partners list; content was not independently verified; dated >12 months from research date)
- **[ACP joins forces with A2A under Linux Foundation](https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/)** — LF AI blog, August 2025

### 8.4 Tooling

- **[A2A Inspector](https://github.com/a2aproject/a2a-inspector)** — UI tool for validating and inspecting A2A agents
- **[A2A TCK](https://github.com/a2aproject/a2a-tck)** — Test Compatibility Kit for protocol compliance
- **[A2A ITK](https://github.com/a2aproject/a2a-itk)** — Integration Testing Kit for cross-SDK compatibility

---

## 9. Caveats & Known Issues

### 9.1 Spec Churn Between v0.3 and v1.0

The v1.0 release includes **breaking changes**:
- Enum values changed from `kebab-case` to `SCREAMING_SNAKE_CASE`
- `kind` discriminator fields removed in favor of JSON member-based polymorphism
- Operation names changed (e.g., `message/send` → `SendMessage`)
- `protocolVersion` moved from AgentCard top level to individual `AgentInterface` objects
- `preferredTransport` and `additionalInterfaces` consolidated into `supportedInterfaces[]`

> "Version 1.0 introduces a breaking change in how polymorphic objects are represented in the protocol. This affects `Part` types and streaming event types."
> — Source: [A2A Specification Appendix A.2.1](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

The Python SDK provides v0.3 backward compatibility, but the JS SDK's v1.0 support is still in **alpha**. Teams building today should be aware that framework integrations (e.g., LangSmith) may still use v0.3 method naming.

### 9.2 Versioning Concerns

- The v0.3 → v1.0 migration guide exists for the Python SDK (`docs/migrations/v1_0/README.md`)
- Agent Cards now allow agents to advertise support for both v0.3 and v1.0 via `supportedInterfaces[]`, enabling progressive migration
- Not all SDKs are at v1.0 parity — check per-SDK compatibility before building

> "Tooling libraries and SDKs that implement the A2A protocol MUST provide mechanisms to help clients manage protocol versioning, such as negotiation of the transport and protocol version used."
> — Source: [A2A Specification §3.6.3](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 9.3 Common Interop Pitfalls

- **Agent Card caching:** Clients should respect cache headers; stale cards can cause auth failures or method mismatches. — Source: [A2A Specification §8.6](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)
- **Streaming lifecycle:** Stream MUST close when task reaches a terminal state — improperly held connections cause resource leaks
- **Push notification security:** Webhook URLs should use HTTPS; SSRF protections must be implemented on the server side
- **Task immutability:** Once terminal, a task cannot be restarted — clients must create new tasks in the same context. — Source: [Life of a Task](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/life-of-a-task.md)

### 9.4 Error Handling Gotchas

- JSON-RPC errors use standard numeric codes (e.g., `-32700` for parse errors, `-32601` for method not found) plus A2A-specific codes for task/capability errors
- Not all agents implement `CancelTask` or push notifications — clients should check `capabilities` in the Agent Card before calling
- The `A2A-Version` header should be sent by clients; if unsupported, the server returns `VersionNotSupportedError` (JSON-RPC code `-32009`). — Source: [A2A Specification §3.3.2](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md)

### 9.5 Security Disclaimer

The official samples include an important security warning:

> "When building production applications, it is critical to treat any agent operating outside of your direct control as a potentially untrusted entity. All data received from an external agent—including but not limited to its AgentCard, messages, artifacts, and task statuses—should be handled as untrusted input."
> — Source: [Helloworld Sample README](https://github.com/a2aproject/a2a-samples/blob/main/samples/python/agents/helloworld/README.md)

---

## 10. Research Limitations

- **Microsoft Foundry V2 A2A support:** Foundry Agents V2 natively supports A2A protocol v0.3 both as a server (incoming) and as a client (outbound via `A2APreviewTool`). This is documented in the [Foundry Agents research](research/2026-05-20-foundry-agents.md) and corroborated by official Microsoft Learn pages. The feature is labeled "(preview)" and there is no portal UI toggle — configuration is done via SDK/API. Adapter/wrapper patterns (Microsoft Agent Framework, Python `a2a-sdk`) provide additional flexibility for custom hosting.
- **OpenAI Agents SDK:** No A2A documentation or integration was found. Evidence: the [GitHub repo](https://github.com/openai/openai-agents-python), [official docs](https://openai.github.io/openai-agents-python/), and [A2A Community Hub](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md) all lack A2A references. This is a negative finding — absence of evidence is documented but cannot be stated with 100% certainty.
- **Microsoft Cloud blog on A2A:** The blog post at `microsoft.com/en-us/microsoft-cloud/blog/2025/05/07/...` was unreachable during research (HTTP throttling). The URL is cited from the A2A partners list but the content was not independently verified. Additionally, the post is dated May 2025, which is >12 months from this research date.
- **Task state diagram:** The proto file was the normative source; the rendered spec page uses Jinja macros (`{{ proto_to_table(...) }}`) that cannot be rendered outside mkdocs, so table content was transcribed verbatim from `a2a.proto`.
- **SDK version parity:** The exact v1.0 support status for Go, Rust, .NET, and Java SDKs was not individually verified; the report relies on the main README claims.
- **LangSmith/LangGraph v1.0 support:** The LangSmith A2A endpoint uses v0.3 method names; the standalone LangGraph sample's README shows v0.3 wire format. The Python `a2a-sdk` supports both, but v1.0 wire-level interop with LangSmith's hosted endpoint has not been verified.
- **Semantic Kernel A2A claim:** The only source found is a LinkedIn post by Asha Sharma (Microsoft), cited in the A2A Community Hub. No official Microsoft Learn or Semantic Kernel repo documentation was found to corroborate this independently.
- **Source freshness:** Some cited announcements (Microsoft Cloud blog, May 2025) are close to or outside a strict 12-month window from the research date. These are marked accordingly.
- **Scope boundaries:** Model availability per region, RBAC requirements, and private VNet architecture are out of scope for this A2A protocol report. These topics are covered in separate research documents.

---

## 11. Complete Reference List

### Documentation & Articles

- [A2A Protocol Specification](https://a2a-protocol.org/latest/specification/) — Full technical specification (v1.0) ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/specification.md))
- [A2A Protocol Documentation Site](https://a2a-protocol.org) — Official docs home
- [A2A Documentation Index](https://a2a-protocol.org/latest/) — Docs landing page ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/index.md))
- [What's New in A2A Protocol v1.0](https://a2a-protocol.org/latest/whats-new-v1/) — Comprehensive v0.3 → v1.0 changelog ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/whats-new-v1.md))
- [A2A Protocol Ships v1.0](https://a2a-protocol.org/latest/announcing-1.0/) — Official v1.0 announcement ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/announcing-1.0.md))
- [Key Concepts](https://a2a-protocol.org/latest/topics/key-concepts/) — Core A2A concepts explained ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/key-concepts.md))
- [Life of a Task](https://a2a-protocol.org/latest/topics/life-of-a-task/) — Task lifecycle and state machine ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/life-of-a-task.md))
- [Agent Discovery](https://a2a-protocol.org/latest/topics/agent-discovery/) — Discovery strategies and Agent Card details ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/agent-discovery.md))
- [A2A and MCP: Detailed Comparison](https://a2a-protocol.org/latest/topics/a2a-and-mcp/) — How A2A and MCP complement each other ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/a2a-and-mcp.md))
- [Enterprise Implementation of A2A](https://a2a-protocol.org/latest/topics/enterprise-ready/) — Auth, TLS, authorization guidance ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/topics/enterprise-ready.md))
- [A2A Community Hub](https://a2a-protocol.org/latest/community/) — Integrations, news, community resources ([raw](https://raw.githubusercontent.com/a2aproject/A2A/main/docs/community.md))
- [A2A Partners](https://a2a-protocol.org/latest/partners/) — 150+ partner organizations ([raw](https://github.com/a2aproject/A2A/blob/main/docs/partners.md))
- [Microsoft Agent Framework A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a) — Official MS docs for A2A via Microsoft Agent Framework
- [Azure AI Foundry Agents Overview](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview) — Foundry Agent Service overview, mentions A2A protocol (preview)
- [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) — How to expose Foundry agent as A2A server, agent card, endpoint URLs, A2A protocol v0.3
- [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent) — How to use A2A as outbound tool from Foundry, Python/REST code, connection setup
- [LangSmith A2A Endpoint Docs](https://docs.langchain.com/langsmith/server-a2a) — LangGraph/LangSmith A2A integration
- [ACP Joins Forces with A2A](https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/) — IBM/LF AI announcement
- [Agent2Agent protocol is getting an upgrade](https://cloud.google.com/blog/products/ai-machine-learning/agent2agent-protocol-is-getting-an-upgrade) — Google Cloud blog, July 2025
- [A2A Extensions Empowering Custom Agent Functionality](https://developers.googleblog.com/en/a2a-extensions-empowering-custom-agent-functionality/) — Google Developers blog, September 2025
- [Microsoft: Empowering multi-agent apps with A2A](https://www.microsoft.com/en-us/microsoft-cloud/blog/2025/05/07/empowering-multi-agent-apps-with-the-open-agent2agent-a2a-protocol/) — Microsoft Cloud blog, May 2025 (**unverified during research** — URL unreachable; >12 months old)
- [DeepLearning.AI A2A Course](https://goo.gle/dlai-a2a) — Short course on A2A protocol
- [OpenAI Agents SDK Documentation](https://openai.github.io/openai-agents-python/) — Official docs (no A2A references found)
- [Semantic Kernel speaks A2A — LinkedIn post](https://www.linkedin.com/posts/aboutasha_a2a-ugcPost-7318649411704602624-0C_8) — Social media source; cited by A2A Community Hub

### GitHub Repositories

- [a2aproject/A2A](https://github.com/a2aproject/A2A) — Main spec repository (formerly google/A2A)
- [a2aproject/a2a-python](https://github.com/a2aproject/a2a-python) — Official Python SDK (`a2a-sdk`)
- [a2aproject/a2a-js](https://github.com/a2aproject/a2a-js) — Official JavaScript SDK (`@a2a-js/sdk`)
- [a2aproject/a2a-dotnet](https://github.com/a2aproject/a2a-dotnet) — Official .NET SDK
- [a2aproject/a2a-java](https://github.com/a2aproject/a2a-java) — Official Java SDK
- [a2aproject/a2a-go](https://github.com/a2aproject/a2a-go) — Official Go SDK
- [a2aproject/a2a-rs](https://github.com/a2aproject/a2a-rs) — Official Rust SDK
- [a2aproject/a2a-samples](https://github.com/a2aproject/a2a-samples) — Official code samples (Python, JS, Go, .NET, Java)
- [a2aproject/a2a-inspector](https://github.com/a2aproject/a2a-inspector) — A2A agent validation tool
- [a2aproject/a2a-tck](https://github.com/a2aproject/a2a-tck) — Test Compatibility Kit
- [a2aproject/a2a-itk](https://github.com/a2aproject/a2a-itk) — Integration Testing Kit
- [openai/openai-agents-python](https://github.com/openai/openai-agents-python) — OpenAI Agents SDK (no A2A support)

### Code Samples

- [Helloworld Agent (Python)](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/helloworld) — Minimal A2A server + client
- [LangGraph Currency Agent](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/langgraph) — LangGraph + A2A with streaming (wire examples use v0.3 format)
- [Azure AI Foundry SDK Samples](https://github.com/a2aproject/a2a-samples/tree/main/samples/python/agents/azureaifoundry_sdk) — Foundry + A2A (calendar, currency, multi-agent)
- [Semantic Kernel A2A Demo (.NET)](https://github.com/a2aproject/a2a-samples/tree/main/samples/dotnet/A2ASemanticKernelDemo) — .NET Semantic Kernel + A2A
