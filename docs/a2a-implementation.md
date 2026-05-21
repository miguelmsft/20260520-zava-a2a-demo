# A2A Implementation in the Zava Smart Order Feasibility Demo

> Companion document to [`docs/technology.md`](./technology.md) (system-wide tech overview)
> and [`docs/use-case.md`](./use-case.md) (business narrative). Where `technology.md`
> describes the whole stack at a single level of detail, **this document is the
> A2A-specific deep dive**: every claim it makes about how Agent-to-Agent
> traffic flows between the Foundry V2 customer-service agent and the AKS
> LangGraph ops agent is grounded in code or in
> [`research/2026-05-20-a2a-protocol.md`](../research/2026-05-20-a2a-protocol.md).

---

## 1. Executive summary

**A2A (Agent-to-Agent)** is an open protocol — originally proposed by Google
in April 2025, contributed to the Linux Foundation in June 2025, and now at
spec version **1.0** with widespread v0.3 deployments still in production —
that defines a JSON-RPC-over-HTTPS contract between autonomous agents
(research §2). It standardizes three things:

1. **Discovery** — every agent publishes a JSON *Agent Card* at a
   well-known URL describing its skills, supported modalities, and transport
   bindings.
2. **Task lifecycle** — a client sends a `message/send` JSON-RPC call; the
   server returns a `Task` whose `status.state` transitions through
   `submitted → working → completed | failed | canceled`.
3. **Content model** — messages and task artifacts are arrays of *parts*
   (`TextPart`, `DataPart`, `FilePart`) so an agent can return both a
   structured JSON payload and a human-readable summary in one response.

**Why we use it in this demo.** The Zava demo's whole reason for existing is
to show a *technical stakeholder* that two agents on two different platforms
(Foundry V2 Agent Service + LangGraph on AKS) can collaborate without a
shared SDK, a shared queue, or a custom REST contract. A2A is the only open
standard supported natively by Foundry Agents V2 today — Foundry exposes
outbound A2A through its built-in `A2APreviewTool`, and inbound A2A through
its enable-agent-to-agent endpoint feature (research §7.1; see also
[`research/2026-05-20-foundry-agents.md`](../research/2026-05-20-foundry-agents.md)
§5). Picking A2A makes the integration *defensible*: a customer can swap
either side for their own agent without redesigning the wire.

**What this document covers.** §2 recaps the protocol. §3 walks the
end-to-end trace of one feasibility request, with a Mermaid sequence
diagram. §4 shows real wire payloads — the Agent Card we serve, the
outbound JSON-RPC body, the inbound task response. §5 documents the
authentication and security posture. §6 explains the v0.3 ↔ 1.0
compatibility story. §7 explains the dual-part artifact pattern that lets
the Foundry orchestrator consume structured fields without re-parsing
prose. §8 enumerates the tests that lock the contract in. §9 lists what
the demo intentionally does **not** implement, so the reader knows where
the boundaries are.

---

## 2. A2A protocol primer

This section is a brief recap. For the full treatment — versioning, gRPC
binding, push-notification config, OAuth flows, and the v1.0 changes —
see [`research/2026-05-20-a2a-protocol.md`](../research/2026-05-20-a2a-protocol.md)
§3 (wire format) and §3.8 (v0.3 ↔ 1.0 interop).

| Concept | What it is | Where it shows up in this demo |
|---|---|---|
| **Transport** | HTTPS, content type `application/json` (research §3.2) | AKS ingress → Starlette `POST /` |
| **Binding** | JSON-RPC 2.0 (research §3.3); gRPC and HTTP+JSON are alternate bindings | All requests are JSON-RPC; method names `message/send`, `tasks/get` |
| **Discovery** | `GET /.well-known/agent-card.json` returns an `AgentCard` JSON document (research §3.6) | Served by `apps/ops-agent/app/agent_card.py` via `a2a-sdk`'s `create_agent_card_routes` |
| **Task lifecycle** | `submitted → working → input-required* → completed \| failed \| canceled` (research §3.5) | Driven by `TaskUpdater` in `apps/ops-agent/app/executor.py` |
| **Parts** | `TextPart` (string), `DataPart` (JSON object), `FilePart` (bytes/URI) (research §3.7) | Ops agent emits `DataPart` (feasibility dict) + `TextPart` (summary) |
| **Artifacts** | Named, ID'd bundles of parts attached to a task | One artifact per request, `name="order-feasibility"` |
| **Auth** | API key, OAuth2, mTLS, or service-specific (research §5.2); declared on the Agent Card | API key in the `x-api-key` header, enforced by Starlette middleware |
| **Versioning** | Spec versions `0.3` and `1.0`; servers that omit `A2A-Version` header are treated as v0.3 (research §3.6.2, §3.8) | We accept v0.3 wire format via the `a2a-sdk` 1.0.x compatibility mode |

The wire format is intentionally small. A complete `message/send` round-trip
is ~1 KB of JSON in each direction; everything bigger goes into a
referenced file part. The cost of A2A interop is therefore *one well-known
discovery fetch + one JSON-RPC call per task*, plus whatever streaming the
agents opt into.

---

## 3. End-to-end flow in this demo

This section traces a single user request — "Can we fulfill 150 ZP-7000
pumps for CUST-001 by 2026-07-15?" — through every hop. File and function
references are absolute.

### 3.1 Sequence diagram

```mermaid
sequenceDiagram
    autonumber
    participant U as User (browser)
    participant R as React UI<br/>(apps/frontend)
    participant B as FastAPI backend<br/>(apps/backend)
    participant F as Foundry V2 Agent<br/>(zava-customer-service)
    participant AT as A2APreviewTool<br/>(in Foundry runtime)
    participant CI as CodeInterpreterTool<br/>(in Foundry runtime)
    participant OA as AKS Ops Agent<br/>(Starlette + a2a-sdk)
    participant LG as LangGraph<br/>(AzureChatOpenAI + tools)

    U->>R: Submits feasibility form
    R->>B: POST /api/chat (SSE)
    B->>F: responses.create(stream=True,<br/>extra_body={agent_reference:...})
    F->>F: LLM decides to call A2APreviewTool<br/>with feasibility query text
    F->>AT: invoke(connection="ops-agent-a2a", text=...)
    AT->>OA: GET /.well-known/agent-card.json
    OA-->>AT: 200 AgentCard JSON
    AT->>OA: POST / (JSON-RPC message/send)<br/>x-api-key: ***
    activate OA
    OA->>OA: ApiKeyAuthMiddleware<br/>(hmac.compare_digest) → 200 path
    OA->>OA: DefaultRequestHandler routes to<br/>ZavaOpsAgentExecutor.execute()
    OA->>OA: enqueue Task(SUBMITTED) +<br/>TaskStatusUpdateEvent(WORKING)
    OA->>LG: graph.ainvoke({messages:[user]})
    LG->>LG: AzureChatOpenAI (gpt-5.4-mini)<br/>decides tool calls
    LG->>LG: ToolNode runs lookup_inventory,<br/>lookup_production_schedule, ...
    LG->>LG: Model synthesizes feasibility JSON
    LG-->>OA: final assistant message (JSON in text)
    OA->>OA: parse JSON → DataPart;<br/>raw text → TextPart
    OA->>OA: TaskArtifactUpdateEvent<br/>(parts=[DataPart, TextPart])
    OA->>OA: TaskStatusUpdateEvent(COMPLETED)
    OA-->>AT: 200 JSON-RPC result = Task<br/>(state=completed, 1 artifact)
    deactivate OA
    AT-->>F: tool result = task artifact
    F->>CI: invoke(code="plot feasibility ...")
    CI-->>F: image + numeric summary
    F-->>B: SSE: tool calls, text, image deltas
    B-->>R: SSE: timeline events + chat tokens
    R-->>U: Renders timeline, chat reply, chart
```

### 3.2 Narrative trace

1. **Browser → React → backend.** The user submits the feasibility form in
   `apps/frontend`. React posts the rendered prompt to `POST /api/chat` on the
   FastAPI backend (`apps/backend`), which opens a Server-Sent Events stream.
2. **Backend → Foundry orchestrator.** The backend issues
   `client.responses.create(stream=True, extra_body={"agent_reference": {
   "agent_name": "zava-customer-service", "agent_version": "<n>"}})`. This is
   the Foundry V2 Responses API path; the `agent_reference` selects the
   prompt agent that `setup_agent.py` registered (see
   [`apps/foundry-agent/setup_agent.py`](../apps/foundry-agent/setup_agent.py),
   lines 158–173).
3. **Foundry agent decides to delegate.** The agent's system prompt teaches
   it that for any feasibility check it should call the `A2APreviewTool`
   bound to connection `ops-agent-a2a`. The LLM emits a tool call whose
   single argument is the natural-language brief, e.g. `"Check feasibility
   for SKU ZP-7000, quantity 150, customer CUST-001, target_date
   2026-07-15"`.
4. **Foundry-side A2A client work.** Inside the Foundry runtime the
   `A2APreviewTool` (a) looks up the project connection `ops-agent-a2a`
   created via [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py),
   (b) fetches the Agent Card from
   `https://ops-agent.zava.example.com/.well-known/agent-card.json` to
   discover the JSON-RPC endpoint and capabilities (research §3.6), and
   (c) POSTs a JSON-RPC `message/send` request body to the discovered
   endpoint, attaching the `x-api-key` header stored on the connection. No
   `A2A-Version` header is sent — Foundry's client is v0.3 (research §3.8).
5. **Ops agent ingress.** The Starlette app built by
   [`apps/ops-agent/app/server.py`](../apps/ops-agent/app/server.py)
   (`build_app`, lines 119–149) routes the request through
   `ApiKeyAuthMiddleware`. Because the path is `/` (not in `PUBLIC_PATHS`)
   the middleware compares the header against the expected key with
   `hmac.compare_digest` (line 77) for constant-time semantics. On
   mismatch it returns `401 {"error":"unauthorized"}`; on match the
   request proceeds to `DefaultRequestHandler` from `a2a-sdk`.
6. **Executor lifecycle.** `DefaultRequestHandler` invokes
   `ZavaOpsAgentExecutor.execute(context, event_queue)` exactly once per
   request ([`apps/ops-agent/app/executor.py`](../apps/ops-agent/app/executor.py),
   lines 121–199). The executor:
   - enqueues a `Task` in state `SUBMITTED` if this is a new task (lines
     139–146);
   - calls `updater.start_work(...)` to publish
     `TaskStatusUpdateEvent(state=WORKING)` plus a status message (lines
     149–155);
   - extracts the user text from the inbound message via
     `a2a.helpers.get_message_text` (line 54);
   - awaits `graph.ainvoke({"messages": [{"role": "user", "content":
     user_text}]})` (lines 166–168).
7. **LangGraph processing.** The graph is built in
   [`apps/ops-agent/app/agent.py`](../apps/ops-agent/app/agent.py). It is a
   **deterministic sequential graph**: `parse_request → gather_data →
   compute_feasibility → summarize → END`. `gather_data` unconditionally
   invokes the four `@tool`-decorated functions — `lookup_inventory`,
   `lookup_production_schedule`, `lookup_order_book`, `lookup_customer` —
   against the fake Zava JSON data. `compute_feasibility` then calls the
   pure function `feasibility.compute_feasibility(...)` (canonical schema
   source: [`apps/ops-agent/app/feasibility.py`](../apps/ops-agent/app/feasibility.py))
   to produce the 12-field feasibility result deterministically. The
   `AzureChatOpenAI` model (deployment `gpt-54mini-worker`) is only
   invoked in the `summarize` node, which writes the prose
   `recommendation_text` over the already-computed feasibility dict. The
   JSON schema includes `feasibility_score`, `can_fulfill`,
   `requested_quantity`, `available_inventory`,
   `production_capacity_by_date`, `supplier_pipeline`,
   `total_fulfillable`, `earliest_promise_date`, `requested_date`,
   `days_late`, `risk_factors`, and `recommendation_text`.
8. **Artifact emission.** The executor reads
   `result["feasibility"]` directly from the graph state
   (`executor.py` line ~180; falls back to `_try_parse_feasibility` on
   the final assistant text only if the state field is missing). It
   builds an artifact with *both* a `DataPart` carrying the computed
   feasibility dict and a `TextPart` carrying the prose summary. It
   publishes `TaskArtifactUpdateEvent(last_chunk=True)` and then
   `TaskStatusUpdateEvent(state=COMPLETED)` via `updater.complete()`.
9. **Back to Foundry.** The `A2APreviewTool` receives the completed
   `Task` as its tool result. Because Foundry deserializes parts by kind,
   the orchestrator sees a structured object (the feasibility dict) and a
   string (the recommendation) — it does *not* have to re-parse prose.
10. **Code Interpreter step.** The orchestrator's system prompt tells it
    to render a small bar chart of `feasibility_score` vs. `risk_factors`
    using the `CodeInterpreterTool` (also bound in `setup_agent.py` line
    159). The tool returns an image plus a short numeric summary.
11. **Stream to UI.** The backend forwards Foundry's SSE deltas to React,
    annotated with hop metadata so the timeline component can render
    `Foundry → A2A → Ops Agent → tools → Foundry → Code Interpreter →
    user`. React displays the chat reply, the rendered chart, and the
    full hop timeline. The user sees both the answer and the protocol
    machinery that produced it.

The entire round-trip is one A2A `message/send` call. There is no polling,
no callback, and no shared state between the two agents — exactly the
loose-coupling story A2A was designed to enable.

---

## 4. Wire format examples

The payloads below are the exact shapes exchanged over the network. JSON
keys are `camelCase` because A2A v0.3 uses JSON-RPC convention for
parameter naming (research §3.3, §3.7).

### 4.1 The Agent Card served at `/.well-known/agent-card.json`

Produced by `build_agent_card()` in
[`apps/ops-agent/app/agent_card.py`](../apps/ops-agent/app/agent_card.py)
and serialized by `a2a-sdk`'s `create_agent_card_routes`. The actual
served JSON when `OPS_AGENT_PUBLIC_URL=https://ops-agent.zava.example.com/`:

```json
{
  "name": "Zava Manufacturing Ops Agent",
  "description": "Queries inventory, production capacity, lead times, and competing orders to compute fulfillment feasibility for Zava precision components (pumps, motors, valves, seals).",
  "version": "1.0.0",
  "defaultInputModes": ["text/plain"],
  "defaultOutputModes": ["application/json", "text/plain"],
  "capabilities": {
    "streaming": false
  },
  "skills": [
    {
      "id": "order-feasibility",
      "name": "Order Feasibility Check",
      "description": "Given an SKU, quantity, target date, and customer ID, returns a feasibility_score (0.0-1.0), can_fulfill flag, earliest_promise_date, risk_factors, and a human-readable recommendation.",
      "tags": ["manufacturing", "inventory", "supply-chain", "feasibility"],
      "examples": [
        "Can we fulfill 150 ZP-7000 pumps for CUST-001 by 2026-07-15?",
        "Check feasibility: SKU ZM-3200, quantity 25, customer CUST-003, target 2026-06-30"
      ]
    }
  ],
  "supportedInterfaces": [
    {
      "url": "https://ops-agent.zava.example.com/",
      "protocolBinding": "jsonrpc",
      "protocolVersion": "0.3"
    }
  ]
}
```

Notes:

- `capabilities.streaming = false` because the executor emits the full
  result in one artifact (see §9 — no SSE streaming on this side).
- `supportedInterfaces[].protocolVersion = "0.3"` is the explicit
  declaration that callers should use v0.3 wire format (research §3.6,
  §3.8). The Python `a2a-sdk` 1.0.x types do not expose a top-level
  `url` field on `AgentCard`; the endpoint URL is advertised via
  `supportedInterfaces` instead (see `agent_card.py` docstring).

### 4.2 The outbound A2A request (Foundry → Ops Agent)

This is the body Foundry's `A2APreviewTool` POSTs to
`https://ops-agent.zava.example.com/`. No `A2A-Version` header is set,
which the server interprets as v0.3 (research §3.6.2).

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "message/send",
  "params": {
    "message": {
      "messageId": "msg-7e3f9c2a",
      "role": "user",
      "kind": "message",
      "parts": [
        {
          "kind": "text",
          "text": "Check feasibility for SKU ZP-7000, quantity 150, customer CUST-001, target_date 2026-07-15"
        }
      ]
    }
  }
}
```

HTTP headers on the same request (only the ones that matter):

```
POST / HTTP/1.1
Host: ops-agent.zava.example.com
Content-Type: application/json
x-api-key: <32-byte base64 secret>
```

### 4.3 The inbound A2A response (Ops Agent → Foundry)

In v0.3 the JSON-RPC `result` *is* the `Task` object (research §3.5). The
test in
[`apps/ops-agent/tests/test_a2a_server.py`](../apps/ops-agent/tests/test_a2a_server.py)
(`test_message_send_v03_happy_path`, lines 183–246) asserts this exact
shape against the live in-process app. A representative response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "id": "task-9b1f4e",
    "contextId": "ctx-2a7c10",
    "status": {
      "state": "completed",
      "timestamp": "2026-05-20T14:31:08.412Z"
    },
    "artifacts": [
      {
        "artifactId": "art-fea-1a2b3c4d5e6f",
        "name": "order-feasibility",
        "parts": [
          {
            "kind": "data",
            "mediaType": "application/json",
            "data": {
              "feasibility_score": 0.85,
              "can_fulfill": true,
              "earliest_promise_date": "2026-07-12",
              "risk_factors": ["competing rush order CUST-004"],
              "recommendation": "We can fulfill 150 ZP-7000 by 2026-07-12, three days ahead of the requested date. One risk factor: CUST-004 has a competing rush order for 80 units on 2026-07-09; mitigate by scheduling our run on line 2."
            }
          },
          {
            "kind": "text",
            "text": "We can fulfill 150 ZP-7000 by 2026-07-12, three days ahead of the requested date. One risk factor: CUST-004 has a competing rush order for 80 units on 2026-07-09; mitigate by scheduling our run on line 2."
          }
        ]
      }
    ]
  }
}
```

The terminal state value `"completed"` is the lowercase v0.3 enum
spelling (research §3.5, §3.8). When `enable_v0_3_compat=True` the
`a2a-sdk` rewrites the v1.0 internal enum
(`TASK_STATE_COMPLETED`) to the v0.3 string on the wire.

---

## 5. Authentication & security

### 5.1 The contract

- **Header:** `x-api-key`
- **Comparison:** constant-time, via Python's `hmac.compare_digest`
- **Bootstrap:** key sourced from the `A2A_API_KEY` environment variable
  at server start
- **Fail-secure:** if `A2A_API_KEY` is unset or empty at startup, the
  process exits with code 2 *before* binding the listener
- **Bypass list:** only `/health` (K8s probes) and
  `/.well-known/agent-card.json` (A2A discovery) bypass auth

These choices are encoded in
[`apps/ops-agent/app/server.py`](../apps/ops-agent/app/server.py). The
middleware:

```python
class ApiKeyAuthMiddleware(BaseHTTPMiddleware):
    """Constant-time API-key check on every non-public request."""

    def __init__(self, app, expected_key: str, public_paths):
        super().__init__(app)
        self._expected_key_bytes = expected_key.encode("utf-8")
        self._public_paths = frozenset(public_paths)

    async def dispatch(self, request, call_next):
        if request.url.path in self._public_paths:
            return await call_next(request)
        provided = request.headers.get("x-api-key", "")
        if not provided or not hmac.compare_digest(
            provided.encode("utf-8"), self._expected_key_bytes
        ):
            return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)
```

And the fail-secure bootstrap:

```python
def _require_api_key() -> str:
    key = os.environ.get("A2A_API_KEY", "").strip()
    if not key:
        print(
            "FATAL: A2A_API_KEY environment variable is unset or empty. "
            "Refusing to start (fail-secure).",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(2)
    return key
```

### 5.2 Why constant-time?

A naïve `provided == expected` comparison short-circuits on the first
mismatching byte and leaks length and content via timing. `hmac.compare_digest`
runs in time proportional to the *longer* of the two operands without
short-circuiting, which is the standard mitigation (research §5.4
discusses transport-layer security guarantees; constant-time string
compare is a Python-side complement). The test
`test_post_with_wrong_api_key_is_unauthorized` exercises the negative
path so we cannot regress the check accidentally.

### 5.3 Key generation and rotation

Operators generate the API key with:

```bash
openssl rand -base64 32
```

The value is stored in three places:

1. A Kubernetes `Secret` mounted as the `A2A_API_KEY` env var on the
   ops-agent Deployment (see `infra/aks.bicep` / the manifests in
   `apps/ops-agent/deploy/`).
2. The Foundry V2 project connection `ops-agent-a2a` (entered once in
   the Foundry portal — A2A connections are portal-created in current
   V2 Preview per [`research/2026-05-20-foundry-agents.md`](../research/2026-05-20-foundry-agents.md)
   §5; see also [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py)
   which prints the portal instructions and boxes the secret for
   one-shot paste).
3. Locally, in `apps/foundry-agent/.env` as `OPS_AGENT_API_KEY`, never
   committed.

Rotation is: regenerate, `kubectl create secret generic ... --dry-run=client
-o yaml | kubectl apply -f -`, then update the Foundry portal connection.
Both sides accept old + new during a short overlap if the operator briefly
runs two ingress paths — the demo does not implement that, but the design
allows it because the comparison is value-based, not signed.

### 5.4 Open-relay mitigation (plan risk R17)

Without the fail-secure check, a misconfigured deployment that simply
forgot to set `A2A_API_KEY` would have started an unauthenticated A2A
endpoint reachable from the public internet — anyone could POST to it and
trigger LangGraph runs against Zava data. The risk is mitigated three
ways:

1. **Server refuses to start without a key.** `_require_api_key()` exits
   2 before `uvicorn.run` is called.
2. **All `POST /` paths require the key.** `PUBLIC_PATHS` is explicitly
   `{"/health", "/.well-known/agent-card.json"}` — no wildcard.
3. **Verification.** Step 9's deployment smoke test runs:

   ```bash
   curl -i -X POST https://ops-agent.zava.example.com/ \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{}}'
   # → HTTP/1.1 401 Unauthorized
   # → {"error":"unauthorized"}
   ```

   The 401 is the expected and recorded result. The corresponding unit
   tests (`test_post_without_api_key_is_unauthorized`,
   `test_post_with_wrong_api_key_is_unauthorized`) lock this in for CI.

---

## 6. Version compatibility (v0.3 ↔ 1.0)

This is the single most subtle point of the design. The short version:

- **Server side: `a2a-sdk` 1.0.3** (`apps/ops-agent/pyproject.toml`),
  which implements A2A spec 1.0 *with explicit compatibility for 0.3*
  (research §3.8 and §4.1).
- **Client side: Foundry Agent Service** `A2APreviewTool`. Its
  underlying SDK version is opaque to us, but per
  [`research/2026-05-20-foundry-agents.md`](../research/2026-05-20-foundry-agents.md)
  §5 and the Microsoft "Enable agent-to-agent endpoint" docs quoted in
  research §3.8, Foundry Agent Service supports **A2A protocol version
  0.3 only** for both inbound and outbound traffic. It sends v0.3
  payloads with **no `A2A-Version` header**.
- **Interop rule** (A2A spec §3.6.2, quoted in research §3.8): a server
  that receives a request with the `A2A-Version` header absent or empty
  MUST treat it as v0.3.

We enable this in `server.py`:

```python
# enable_v0_3_compat=True lets the SDK auto-detect A2A v0.3 wire format
# (when the A2A-Version header is absent) per research §3.8.
routes.extend(
    create_jsonrpc_routes(handler, "/", enable_v0_3_compat=True)
)
```

The single flag does three things:

1. Routes JSON-RPC method names in v0.3 style (`message/send`,
   `tasks/get`) instead of the v1.0 namespaced equivalents.
2. Accepts `kind` discriminator fields on parts (`"kind": "text"`,
   `"kind": "data"`) rather than requiring the v1.0 oneof shape.
3. Serializes terminal state values as lowercase v0.3 enums
   (`"completed"`, `"failed"`) on the wire even though the SDK uses the
   v1.0 enum (`TASK_STATE_COMPLETED`) internally.

The test `test_message_send_v03_happy_path` is the regression guard: it
sends a v0.3-shape body, asserts `result.status.state` is either
`"completed"` or `"TASK_STATE_COMPLETED"` (defensive: tolerates either
serialization), and asserts both `DataPart` and `TextPart` are present.
If Microsoft ever ships a Foundry V2 build that *does* send
`A2A-Version: 1.0`, the SDK switches itself; nothing on our side
changes.

---

## 7. Artifact passthrough — why we emit both a DataPart and a TextPart

This is the demo's mitigation for what
[`docs/technology.md`](./technology.md) §5.4 calls the *opaque-string
failure mode* (plan risk R16).

### 7.1 The problem

If the ops agent returned only a `TextPart` containing prose like
`"We can fulfill 150 ZP-7000 by 2026-07-12, three days ahead..."`, the
Foundry orchestrator would receive an opaque string. To plot the
feasibility score with the Code Interpreter tool, the orchestrator would
have to re-parse that prose — fragile and model-dependent. A bad
re-parse (`feasibility_score: null`) silently produces an empty chart.

### 7.2 The fix

The executor emits *both* a `DataPart` (carrying the structured
feasibility dict, `mediaType: application/json`) and a `TextPart`
(carrying the human-readable recommendation) in the same artifact. The
orchestrator picks whichever shape it needs:

- For `CodeInterpreterTool`: parse `parts[0].data` directly — a dict
  with numeric fields.
- For the final chat reply: use `parts[1].text` verbatim.

The relevant executor code
([`apps/ops-agent/app/executor.py`](../apps/ops-agent/app/executor.py)
lines 179–197):

```python
assistant_text = _final_assistant_text(result)
feasibility = _try_parse_feasibility(assistant_text) or {}

artifact_parts = []
if feasibility:
    artifact_parts.append(
        new_data_part(feasibility, media_type="application/json")
    )
# Always include a text part so even non-JSON-aware clients see a
# human-readable summary.
artifact_parts.append(new_text_part(assistant_text or ""))

artifact_id = f"art-fea-{uuid.uuid4().hex[:12]}"
await updater.add_artifact(
    parts=artifact_parts,
    artifact_id=artifact_id,
    name="order-feasibility",
    last_chunk=True,
)
```

A2A's `parts` array is heterogeneous by design (research §3.7), so this
costs nothing on the wire and avoids the most likely class of integration
bug. The unit test asserts both parts are present and that
`data["feasibility_score"]` round-trips with the right value.

### 7.3 Why this is more than a "nice to have"

In Foundry V2 the orchestrator's downstream tools (`CodeInterpreterTool`,
custom function tools) consume the A2A tool result as a Python-ish
object. When a `DataPart` is present, the dict is directly addressable
by the orchestrator — no JSON-from-prose extraction step. This is what
makes the chart in the React UI *defensibly correct*: the number being
plotted is the number the ops agent computed, not a regex's best guess.

---

## 8. Testing strategy

A2A behavior is locked in by both unit and integration tests.

### 8.1 Unit tests — `apps/ops-agent/tests/test_a2a_server.py`

Seven cases, all running against the in-process Starlette app with a
mocked `graph.ainvoke`. No Azure credentials needed; runs under
`pytest -m "not integration"`. The cases (per the file header):

1. **Agent Card discovery** — `GET /.well-known/agent-card.json` is
   unauthenticated, returns 200, and includes every required A2A field
   (`name`, `version`, `skills`, `capabilities`, `defaultInputModes`,
   `defaultOutputModes`).
2. **Health probe** — `GET /health` is unauthenticated and returns
   `{"status": "ok"}`.
3. **Auth: missing key → 401** — POST without `x-api-key` is rejected.
4. **Auth: wrong key → 401** — POST with a non-matching key is rejected.
5. **A2A v0.3 `message/send` happy path** — no `A2A-Version` header;
   asserts the SDK auto-detects v0.3, the executor runs, the task
   terminates in `completed`, and the artifact contains *both* a
   `DataPart` (with `feasibility_score`, `can_fulfill`) and a
   `TextPart`.
6. **Malformed JSON-RPC body** — must produce a JSON-RPC error
   envelope (or HTTP 4xx), never a `200 + result`.
7. **Unknown method** — JSON-RPC error `code == -32601`
   ("Method not found").

Together these pin every wire-level behavior this document describes.

### 8.2 Integration verification path

Manual end-to-end verification (the path used during Step 9 and Step 11
sign-off):

1. **Provision** the AKS deployment via `infra/` Bicep + the ops-agent
   manifests; confirm `kubectl get pods` is healthy and `curl
   https://ops-agent.zava.example.com/health` returns `{"status":"ok"}`.
2. **Create the Foundry A2A connection** by following the portal
   instructions printed by
   [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py),
   then run `python create_a2a_connection.py --verify` to confirm.
3. **Register the orchestrator** with `python setup_agent.py` — this
   creates a new version of `zava-customer-service` with the
   `A2APreviewTool` and `CodeInterpreterTool` bound.
4. **Smoke-test** with `python test_agent.py`, which submits a
   feasibility query and asserts both that the agent calls A2A and that
   the returned artifact contains a `DataPart` (the R16 passthrough
   assertion).
5. **End-to-end** through React → backend → Foundry → A2A → AKS → back,
   visually confirming the timeline component renders every hop and
   the chart reflects the feasibility number from the structured part.

---

## 9. Known limitations & things we did NOT do

This list is intentional. Each item is documented so a reviewer can ask
"why?" and get the answer here, rather than discovering the gap in
production.

- **No A2A v1.0 wire format.** We accept and emit v0.3 because Foundry
  Agent Service only speaks v0.3 today (research §3.8 and
  [`research/2026-05-20-foundry-agents.md`](../research/2026-05-20-foundry-agents.md)
  §5). When Foundry adopts v1.0, the `a2a-sdk` 1.0.x compatibility
  mode will negotiate automatically via the `A2A-Version` header —
  no code change required.
- **No streaming.** `capabilities.streaming = false` on the Agent
  Card. The ops agent emits one artifact with the full result rather
  than incremental deltas. SSE streaming is supported by `a2a-sdk`
  (research §3.4) but adds non-trivial state management on the
  Foundry orchestrator side and isn't required for the use case —
  the LangGraph runs typically finish in 2–5 seconds.
- **No multi-turn conversation continuation on the A2A leg.** Each
  request is independent; the executor enqueues a fresh `Task` if
  `context.current_task is None`. The orchestrator (Foundry) is what
  holds session state across user turns, not the ops agent. A2A
  supports `contextId` continuation (research §3.5) — wiring it up is
  a follow-on if a use case appears.
- **Single replica on AKS.** The Deployment has `replicas: 1`. The
  `InMemoryTaskStore` from `a2a-sdk` is process-local, so horizontal
  scale-out would need a shared task store (Redis or Postgres).
  Acceptable for a demo; documented so a customer doesn't copy the
  pattern blindly into production.
- **Public endpoints.** Both Foundry and the ops agent are reachable
  on the public internet; the only thing keeping traffic out is the
  API key. The private-VNet alternative — Foundry with
  `publicNetworkAccess: Disabled`, private endpoints, AKS internal
  load balancer — is fully designed in
  [`docs/private-vnet-considerations.md`](./private-vnet-considerations.md)
  but not implemented in this build.
- **Portal-created A2A connection on the Foundry side.** As of the
  current Foundry V2 Preview the `A2APreviewTool` connection cannot be
  created reliably via SDK — see
  [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py),
  which attempts an SDK fallback but expects it to fail. When the SDK
  path stabilizes, the script will succeed and the manual portal step
  goes away with no other code change.
- **No A2A push-notification config.** Long-running tasks on the ops
  agent could in principle deliver completion via webhook (research
  §3 push-notification mechanism). The current `message/send` synchronous
  pattern is simpler and sufficient.

---

## 10. Where to look next

- [`docs/technology.md`](./technology.md) — full system tech overview,
  including model selection, observability, and security posture.
- [`docs/use-case.md`](./use-case.md) — the business story; what a
  feasibility check is and why it matters.
- [`docs/private-vnet-considerations.md`](./private-vnet-considerations.md) —
  how to take this design private.
- [`research/2026-05-20-a2a-protocol.md`](../research/2026-05-20-a2a-protocol.md) —
  authoritative protocol reference; cite this when you need to defend
  a wire-level design decision.
- [`research/2026-05-20-foundry-agents.md`](../research/2026-05-20-foundry-agents.md) —
  the Foundry-side compatibility matrix and known constraints.
- [`apps/ops-agent/app/server.py`](../apps/ops-agent/app/server.py),
  [`apps/ops-agent/app/executor.py`](../apps/ops-agent/app/executor.py),
  [`apps/ops-agent/app/agent_card.py`](../apps/ops-agent/app/agent_card.py) —
  the entire server-side A2A implementation; ~350 lines combined.
- [`apps/foundry-agent/setup_agent.py`](../apps/foundry-agent/setup_agent.py),
  [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py) —
  the Foundry-side client wiring.
- [`apps/ops-agent/tests/test_a2a_server.py`](../apps/ops-agent/tests/test_a2a_server.py) —
  the executable spec for this document.
