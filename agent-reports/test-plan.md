# End-to-End Test Plan

## Application Summary

The **Zava Smart Order Feasibility — A2A Multi-Agent Demo** shows a sales rep asking whether Zava can ship a customer order by a target date. The deployed stack is:

- **Frontend:** React + Vite at `http://localhost:5173`
- **Backend mediator:** FastAPI SSE API at `http://127.0.0.1:8000`
- **Orchestrator agent:** Microsoft Foundry V2 agent `zava-customer-service` v1
- **Worker agent:** LangGraph Manufacturing Ops Agent on AKS at `http://ops-agent.4-153-150-147.sslip.io/`
- **Inter-agent protocol:** A2A v0.3-compatible JSON-RPC `message/send`
- **Output:** realtime A2A timeline, tool-call timeline, Code Interpreter chart placeholder/event, and customer-friendly feasibility answer

The core end-to-end flow is:

`Browser → React → FastAPI /api/chat SSE → Foundry Responses API → A2APreviewTool → AKS Ops-Agent JSON-RPC → LangGraph tools/data → A2A DataPart + TextPart → Foundry Code Interpreter → SSE events → React rendering`

## Test Modes

| Mode | Applies | Rationale |
|---|---:|---|
| API | Yes | Backend `/api/health`, `/api/chat`, Ops-Agent `/`, `/.well-known/agent-card.json`, auth behavior |
| Frontend | Yes | React UI is the primary demo surface and must render timeline, chat, chart, and interactive controls |
| CLI | Yes | Operator uses `curl` / PowerShell / Python httpx / `kubectl logs` to validate deployed services |
| Pipeline | Partial | No CI/CD pipeline is under test; demo flow is a runtime pipeline across Foundry, A2A, AKS, Code Interpreter, SSE |

## Note on Scope

Step-level verification was completed during implementation. This plan covers deployed end-to-end behavior, user journeys, cross-component integration, and demo readiness.

Out of scope:
- Chaos/failure injection, pod kill tests
- Load testing
- Private VNet path
- Production hardening beyond documented public endpoint + API key controls

Secrets must be redacted in all evidence. Use `${OPS_AGENT_API_KEY}` instead of recording the actual key.

---

# Global Preconditions

Before executing any scenario:

1. Backend is running:
   - `http://127.0.0.1:8000`
2. Frontend is running:
   - `http://localhost:5173`
3. Ops-Agent is reachable:
   - `http://ops-agent.4-153-150-147.sslip.io/`
4. Operator has a valid A2A API key available as an environment variable:
   - PowerShell: `$env:OPS_AGENT_API_KEY = "<redacted>"`
5. Operator is logged into Azure for Foundry/backend tests:
   - `az account show`
6. Foundry agent exists:
   - `zava-customer-service` v1 in `foundry-zava-demo / zava-project`
7. Do not publish screenshots/logs containing secrets.

---

# User Journey Test Scenarios

## UJ-01 — Happy Path via Frontend

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Entry Point | `http://localhost:5173` |
| Tools | Playwright MCP, browser dev tools optional |
| Preconditions | Backend and frontend running; Foundry and Ops-Agent reachable |

### Steps

1. Open `http://localhost:5173`.
2. Enter or select:
   - SKU: `ZP-7000`
   - Quantity: `150`
   - Target date: `2026-07-15`
   - Customer: `CUST-001` / Apex Hydraulics
3. Submit the request.
4. Observe streaming UI state.
5. Wait for completion.
6. Capture screenshots at:
   - Initial loaded UI
   - Streaming timeline in progress
   - Final answer with timeline and chart placeholder/artifact

### Expected Outcomes / Pass Criteria

- Page loads without console-breaking errors.
- Submit button triggers one backend request to `/api/chat`.
- UI shows a loading/streaming state within 1–3 seconds.
- Timeline includes at least:
  - Foundry/orchestrator activity
  - At least one A2A hop
  - At least one tool call
  - Completion state
- Chat answer is customer-friendly and references:
  - `ZP-7000`
  - `150`
  - `CUST-001` or Apex Hydraulics
  - target date or promised date
  - feasibility/risk summary
- Chart area renders either the Code Interpreter chart or documented sandbox chart placeholder.
- Final state completes without an unhandled error banner.

### Fail Criteria

- UI cannot submit.
- No SSE activity appears.
- No A2A hop appears.
- Final answer is missing or unrelated to the order.
- Chart event/placeholder never appears.
- Browser console shows fatal React/runtime errors.

---

## UJ-02 — Direct A2A JSON-RPC Happy Path and R16 Dual-Part Artifact

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `POST http://ops-agent.4-153-150-147.sslip.io/` |
| Tools | curl / Invoke-WebRequest / Python httpx |
| Preconditions | `${OPS_AGENT_API_KEY}` set |

### Request

```powershell
$body = @{
  jsonrpc = "2.0"
  id = 1
  method = "message/send"
  params = @{
    message = @{
      role = "user"
      kind = "message"
      messageId = "test-r16-001"
      parts = @(
        @{
          kind = "text"
          text = "Check order feasibility: SKU=ZP-7000, quantity=150, target_date=2026-07-15, customer_id=CUST-001"
        }
      )
    }
  }
} | ConvertTo-Json -Depth 10

Invoke-WebRequest `
  -Uri "http://ops-agent.4-153-150-147.sslip.io/" `
  -Method POST `
  -Headers @{
    "Content-Type" = "application/json"
    "x-api-key" = $env:OPS_AGENT_API_KEY
  } `
  -Body $body
```

### Expected Outcomes / Pass Criteria

- HTTP status is 200.
- JSON-RPC response has:
  - `jsonrpc = "2.0"`
  - matching `id`
  - `result.status.state` is `completed` or equivalent accepted terminal success.
- `result.artifacts` contains at least one artifact.
- Artifact contains **both**:
  - `DataPart`: `kind = "data"` with structured feasibility JSON
  - `TextPart`: `kind = "text"` with human-readable summary
- DataPart contains at minimum:
  - `feasibility_score`
  - `can_fulfill`
  - `requested_quantity`
  - `available_inventory`
  - `production_capacity_by_date`
  - `supplier_pipeline`
  - `total_fulfillable`
  - `earliest_promise_date`
  - `requested_date`
  - `days_late`
  - `risk_factors`
  - `recommendation_text`
- `requested_quantity = 150`
- `requested_date = "2026-07-15"`
- TextPart is non-empty and understandable.

### Fail Criteria

- 401 with correct key.
- JSON-RPC error for valid request.
- Only TextPart is returned.
- Only DataPart is returned.
- Structured fields are missing or stringified as opaque prose only.

---

## UJ-03 — A2A Auth Negative: Missing API Key

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `POST http://ops-agent.4-153-150-147.sslip.io/` |
| Tools | curl / Invoke-WebRequest |

### Steps

1. Send a valid JSON-RPC body without `x-api-key`.

### Expected Outcomes / Pass Criteria

- HTTP status is `401`.
- Response body is an unauthorized error, e.g. `{"error":"unauthorized"}`.
- Request does not reach LangGraph processing.
- `kubectl logs deployment/ops-agent -n default --tail=50` should not show successful task execution for this request.

### Fail Criteria

- Missing key returns 200.
- Missing key triggers a task.
- Response leaks implementation secrets.

---

## UJ-04 — A2A Auth Negative: Wrong API Key

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `POST http://ops-agent.4-153-150-147.sslip.io/` |
| Tools | curl / Invoke-WebRequest |

### Steps

1. Send a valid JSON-RPC body with `x-api-key: wrong-key`.

### Expected Outcomes / Pass Criteria

- HTTP status is `401`.
- No task result is returned.
- No successful graph execution appears in logs.

### Fail Criteria

- Wrong key is accepted.
- Error response exposes expected key or sensitive details.

---

## UJ-05 — Agent Card Discovery

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `GET http://ops-agent.4-153-150-147.sslip.io/.well-known/agent-card.json` |
| Tools | curl / Python httpx |

### Steps

1. Fetch the Agent Card.
2. Validate JSON structure.

### Expected Outcomes / Pass Criteria

- HTTP 200.
- No auth required.
- Valid JSON.
- Contains:
  - `name`: expected to identify Zava Manufacturing Ops Agent
  - `version`: expected `1.0.0` or current deployed version
  - `description`
  - `defaultInputModes` includes text
  - `defaultOutputModes` includes JSON/text
  - `capabilities.streaming = false`
  - `skills` includes order feasibility skill
  - skill includes tags such as manufacturing/inventory/supply-chain/feasibility
  - supported JSON-RPC interface or equivalent endpoint metadata
- Does not expose secrets.

### Fail Criteria

- Non-JSON response.
- Missing skills/capabilities/version.
- Requires auth.
- Advertises wrong URL or wrong protocol in a way that would break Foundry discovery.

---

## UJ-06 — Backend Health Endpoint

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `GET http://127.0.0.1:8000/api/health` |
| Tools | curl / Invoke-WebRequest |

### Steps

```powershell
Invoke-WebRequest -Uri "http://127.0.0.1:8000/api/health"
```

### Expected Outcomes / Pass Criteria

- HTTP 200.
- JSON body:

```json
{"status":"ok","agent_name":"zava-customer-service"}
```

### Fail Criteria

- Backend unavailable.
- Wrong agent name.
- Response shape differs from backend contract.

---

## UJ-07 — Backend SSE Event Stream

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Endpoint | `POST http://127.0.0.1:8000/api/chat` |
| Tools | Python httpx preferred; curl acceptable |
| Preconditions | Backend has Foundry env vars and Azure login |

### Request Body

```json
{
  "sku": "ZP-7000",
  "quantity": 150,
  "target_date": "2026-07-15",
  "customer_id": "CUST-001"
}
```

### Expected SSE Event Counts / Pass Criteria

The stream must contain:

| Event Type | Required Count |
|---|---:|
| `status` | >= 1 |
| `a2a_hop` | >= 1 |
| `tool_call` | >= 1 |
| `text_delta` | >= 10 |
| `chart` | exactly 1 preferred; at least 1 acceptable if retried/deduped |
| `done` | exactly 1 |
| `error` | 0 |

Additional pass criteria:

- `content-type` includes `text/event-stream`.
- Response headers include no-buffer/no-cache behavior:
  - `Cache-Control: no-cache`
  - `X-Accel-Buffering: no`
- SSE frames use `data: {...}\n\n`.
- Final text is coherent and grounded in the request.
- Stream begins emitting before the final answer is complete.

### Fail Criteria

- Blocking response with no streaming.
- Missing A2A hop.
- Missing chart event.
- Ends with `error`.
- Event JSON malformed.

---

## UJ-08 — Foundry Portal Control Plane: Agent and Trace Visibility

| Field | Value |
|---|---|
| Severity | High |
| Required | true |
| Entry Point | Foundry portal |
| Tools | Operator-driven browser navigation; screenshots |
| Preconditions | A fresh demo run completed |

### Steps

1. Open Foundry portal.
2. Navigate to the `foundry-zava-demo` account and `zava-project`.
3. Open Agents.
4. Confirm `zava-customer-service` v1 exists.
5. Open the agent/run/traces area.
6. Locate the latest run from the test window.
7. Verify trace spans show:
   - orchestrator model call
   - A2A tool call
   - Ops-Agent response/tool output
   - Code Interpreter call
   - final response synthesis

### Expected Outcomes / Pass Criteria

- Agent is visible with correct name/version.
- A trace appears within 5–10 minutes of a run.
- Trace includes model/tool spans or equivalent portal-visible events.
- A2A and Code Interpreter activity is inspectable.
- No secrets appear in screenshots.

### Fail Criteria

- Agent missing.
- Tracing disabled.
- No trace after 10 minutes and App Insights KQL fallback also returns no rows.
- Trace lacks A2A/tool-call evidence.

---

## UJ-09 — Different Question Phrasings

| Field | Value |
|---|---|
| Severity | High |
| Required | true |
| Entry Points | Frontend if free-text supported; otherwise direct A2A text and backend structured request |
| Tools | Playwright MCP, curl/httpx |

### Test Inputs

| Case | Prompt |
|---|---|
| Natural language | `Can we ship 150 ZP-7000 pumps to CUST-001 by 2026-07-15?` |
| Structured | `Check order feasibility: SKU=ZP-7000, quantity=150, target_date=2026-07-15, customer_id=CUST-001` |
| Loose | `sku: ZP-7000 qty 150 cust CUST-001 need by July 15 2026` |

### Expected Outcomes / Pass Criteria

For each phrasing:

- Request is parsed successfully.
- Result references SKU `ZP-7000`, quantity `150`, customer `CUST-001`, and target date.
- A2A direct response includes completed task and dual-part artifact.
- End-to-end frontend/backend path returns a coherent answer.
- No hallucinated different SKU/customer/date.

### Fail Criteria

- Natural-language parser fails for loose/structured inputs.
- Result uses wrong customer/SKU/date.
- Agent asks for missing information when all fields are present.
- A2A hop is skipped for feasibility request.

---

## UJ-10 — Frontend Interactivity and Rendering

| Field | Value |
|---|---|
| Severity | High |
| Required | true |
| Entry Point | `http://localhost:5173` |
| Tools | Playwright MCP |

### Steps

1. Load the UI.
2. Verify the input controls are visible:
   - SKU field/dropdown or free-text input
   - Quantity field
   - Target date field
   - Customer field/dropdown
   - Send / Check Feasibility button
3. Verify initial empty state:
   - Chat panel empty or has expected intro
   - Timeline empty or has expected placeholder
   - Chart placeholder empty or instruction state
4. Submit happy path.
5. Verify controls disable or show loading while request is active.
6. Verify timeline rows append as events arrive.
7. Verify chart placeholder/artifact appears.
8. Verify final answer remains visible after completion.
9. Optional: submit a second request and verify previous state is either cleared or clearly separated.

### Expected Outcomes / Pass Criteria

- All primary controls usable.
- Button invokes request once per click.
- Timeline visually updates.
- Chart display handles sandbox placeholder correctly.
- UI recovers to non-loading state.
- No duplicate uncontrolled submissions.

### Fail Criteria

- Controls missing or non-functional.
- Submit does nothing.
- Timeline never updates.
- Chart placeholder missing after chart SSE event.
- UI stuck in loading after `done`.

---

## UJ-11 — GA Quirk: A2A Event Name Translation

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Backend event translator |
| Tools | Backend SSE capture, Foundry trace |

### Steps

1. Run backend `/api/chat`.
2. Capture SSE events.
3. Inspect Foundry trace if available for raw output item names.
4. Confirm raw `a2a_preview_call` and/or `a2a_preview_call_output` are represented to the frontend as `a2a_hop`.

### Expected Outcomes / Pass Criteria

- SSE contains `a2a_hop`.
- Frontend timeline renders A2A rows.
- No dependency on deprecated-only `remote_function_call`.
- If raw trace shows `a2a_preview_call*`, backend still succeeds.

### Fail Criteria

- A2A occurred in Foundry but no `a2a_hop` reached frontend.
- Backend emits unknown status only and timeline misses A2A.
- UI depends on old preview event names.

---

## UJ-12 — GA Quirk: Code Interpreter Sandbox Chart Detection

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Backend chart detector + frontend chart renderer |
| Tools | Backend SSE capture, frontend screenshot, Foundry trace |

### Steps

1. Run happy path.
2. Capture final assistant text and SSE.
3. Verify backend detects inline markdown reference similar to:
   - `![chart](sandbox:/mnt/data/*.png)`
4. Confirm a `chart` SSE event is emitted.
5. Confirm frontend renders chart placeholder/artifact.

### Expected Outcomes / Pass Criteria

- Exactly one chart event preferred.
- Chart event indicates sandbox reference or equivalent metadata.
- Frontend does not break because the image is not a separate `image_file` item.
- Final response still includes useful text if actual image bytes are not retrievable locally.

### Fail Criteria

- Chart markdown appears in text but no chart SSE event emitted.
- Frontend shows raw broken sandbox markdown only.
- Chart event emitted but UI cannot render any placeholder/artifact.

---

## UJ-13 — GA Quirk: Responses API Uses Deployment Name, Not Agent Name

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Backend Foundry call |
| Tools | Backend logs, `/api/chat`, optional env inspection |

### Steps

1. Ensure backend env uses:
   - `FOUNDRY_AGENT_NAME=zava-customer-service`
   - `FOUNDRY_ORCHESTRATOR_DEPLOYMENT=gpt-55-orchestrator`
2. Call `/api/chat`.
3. Monitor backend logs.

### Expected Outcomes / Pass Criteria

- Backend call succeeds.
- No error:
  - `Model must match the agent's model`
- `agent_reference` uses agent name.
- `responses.create(model=...)` uses deployment name.

### Fail Criteria

- Backend passes `zava-customer-service` as `model`.
- Foundry returns model/agent mismatch.
- Backend requires deprecated `api-version` by default.

---

## UJ-14 — GA Quirk: No Default `api-version` on `/openai/v1/...`

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Backend Foundry client construction |
| Tools | env inspection, `/api/chat`, backend logs |

### Preconditions

- `FOUNDRY_OPENAI_API_VERSION` is unset or empty (the shipped default).

### Steps

1. Confirm the env var is unset/empty: `Get-Item env:FOUNDRY_OPENAI_API_VERSION` returns nothing.
2. Inspect `apps/backend/app/agent_client.py` (or equivalent) to confirm the OpenAI client is created without `default_query={"api-version": ...}` unless the env var is set.
3. Run `/api/chat` happy-path request and confirm no `BadRequestError: api-version query parameter is not allowed when using /v1 path` appears in backend logs.

### Expected Outcomes / Pass Criteria

- No `api-version=` query parameter is appended to outbound `/openai/v1/...` requests by default.
- Backend `/api/chat` completes successfully.

### Fail Criteria

- Backend appends `?api-version=...` and Foundry returns 400 `BadRequest`.

---

## UJ-15 — GA Quirk: `agent_reference.type` Field Present

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Backend Foundry request payload |
| Tools | backend logs, `/api/chat`, optional payload capture |

### Preconditions

- Backend is running with `FOUNDRY_AGENT_NAME=zava-customer-service`.

### Steps

1. Inspect `apps/backend/app/agent_client.py` and confirm the `extra_body` payload includes:
   ```json
   {"agent_reference": {"type": "agent_reference", "name": "zava-customer-service"}}
   ```
2. Run `/api/chat` happy-path request.
3. Confirm Foundry accepts the request (no `invalid_payload: required: Required properties ["type"] are not present` error).

### Expected Outcomes / Pass Criteria

- `agent_reference` always contains both `type` and `name`.
- No `invalid_payload` GA error in backend logs.

### Fail Criteria

- `agent_reference` is sent without `type`.
- Foundry returns 422/400 indicating missing required property.

---

## UJ-16 — Agent Card Discovery Failure (Negative)

| Field | Value |
|---|---|
| Severity | Important |
| Required | true |
| Component | Ops-Agent ingress + Foundry A2A discovery |
| Tools | curl, Foundry portal (descriptive) |

### Preconditions

- Ops-Agent ingress is reachable.

### Steps

1. **Wrong path** — `curl http://ops-agent.4-153-150-147.sslip.io/.well-known/this-does-not-exist.json`. Expect 401 or 404. (Note: the a2a-sdk Starlette middleware checks API-key auth before routing, so unauthenticated requests to any path — including non-existent ones — return 401. This is by design and acceptable; the key point is no 500 is returned.)
2. **Wrong host** — `curl http://invalid-ops-agent.4-153-150-147.sslip.io/.well-known/agent-card.json`. Expect DNS error or 404 (ingress will not match the host).
3. **Card body validity** — fetch the real card and assert the advertised `url` matches the public ingress URL (`http://ops-agent.4-153-150-147.sslip.io/`).
4. **Surface check** — confirm `docs/deployment-learnings.md` §1 documents that the advertised URL must match the Foundry-visible ingress URL or Foundry's discovery will fail.

### Expected Outcomes / Pass Criteria

- Wrong-path requests return 401 or 404 (either is acceptable — no 500s).
- Agent Card's advertised `url` exactly matches the public ingress URL.

### Fail Criteria

- Agent Card advertises a host that Foundry cannot reach (e.g. a synthetic `*.example.com` placeholder still in the card after deployment).
- Discovery failure produces a 500 instead of a 404.

---

## UJ-17 — R16 Dual-Part Artifact: Re-verify Across All A2A Variants

| Field | Value |
|---|---|
| Severity | Critical |
| Required | true |
| Component | Ops-Agent executor + Foundry orchestrator |
| Tools | Python httpx, backend SSE inspection |

### Preconditions

- All A2A request variants from UJ-02, UJ-09, and API-04/API-05 pass individually.

### Steps

For **each** of the three direct A2A variants and the two backend-driven phrasings (i.e., 5 total runs):

1. Send the A2A `message/send` (or backend `/api/chat`) request.
2. Capture the full response artifact.
3. Assert the artifact contains **both**:
   - a `DataPart` with `data.feasibility_score` (or equivalent structured fields), AND
   - a `TextPart` with a non-empty human-readable summary.

### Expected Outcomes / Pass Criteria

- All 5 runs return artifacts containing **both** part kinds.
- The backend SSE stream's final `done` event still carries the structured feasibility payload.

### Fail Criteria

- Any variant returns only a `TextPart` (orchestrator cannot then parse structured fields — R16 violation).
- Any variant returns only a `DataPart` (no human-readable response — R16 violation).

---



| ID | Description | Required | Endpoint | Preconditions | Steps | Expected Outcome | Expected Evidence | Testing Approach |
|---|---|---:|---|---|---|---|---|---|
| API-01 | Backend health | true | `GET /api/health` | Backend running | Send GET | 200, `status=ok`, `agent_name=zava-customer-service` | JSON response | curl/httpx |
| API-02 | Backend SSE happy path | true | `POST /api/chat` | Backend + Foundry configured | Send structured order request | SSE event taxonomy complete; no error | Captured event counts | Python httpx |
| API-03 | Ops-Agent Agent Card | true | `GET /.well-known/agent-card.json` | Ops-Agent reachable | Fetch card | Valid AgentCard with skills/capabilities/version | JSON body | curl/httpx |
| API-04 | Direct A2A happy path | true | `POST /` | Valid API key | Send v0.3 `message/send` | Completed task + artifact | Response body | curl/httpx |
| API-05 | R16 dual-part artifact | true | `POST /` | Valid API key | Inspect A2A artifact parts | Both DataPart and TextPart present | Response body | Python assertions |
| API-06 | Missing API key rejected | true | `POST /` | None | Send without key | 401 | Status/body | curl |
| API-07 | Wrong API key rejected | true | `POST /` | None | Send wrong key | 401 | Status/body | curl |
| API-08 | Malformed JSON-RPC rejected | true | `POST /` | Valid API key | Send invalid method/body | JSON-RPC error or 4xx, not success | Response body | curl/httpx |
| API-09 | Unknown method rejected | false | `POST /` | Valid API key | Send `method=unknown/method` | JSON-RPC method-not-found | Response body | curl/httpx |
| API-10 | SSE headers prevent buffering | true | `POST /api/chat` | Backend running | Inspect headers | `text/event-stream`, no-cache/no-buffer | Headers | curl/httpx |

---

# Frontend Test Scenarios

| ID | Description | Required | Entry Point | Preconditions | Steps | Expected Outcome | Expected Evidence | Testing Approach |
|---|---|---:|---|---|---|---|---|---|
| FE-01 | Page load and layout | true | `/` | Vite running | Open page | Form/chat/timeline/chart areas visible | Screenshot | Playwright MCP |
| FE-02 | Happy path submit | true | `/` | Backend running | Submit ZP-7000 / 150 / date / CUST-001 | Streaming UI, final answer | Screenshots + network log | Playwright MCP |
| FE-03 | Timeline rendering | true | `/` | Happy path running | Observe timeline | A2A and tool-call rows appear | Screenshot | Playwright MCP |
| FE-04 | Chart placeholder/artifact | true | `/` | Happy path complete | Observe chart area | Chart placeholder/artifact displayed | Screenshot | Playwright MCP |
| FE-05 | Loading/disabled state | true | `/` | Slow/normal request | Submit once | Clear in-progress indication; no duplicate accidental submit | Screenshot | Playwright MCP |
| FE-06 | Second request behavior | false | `/` | First run complete | Submit another request | State resets or separates cleanly | Screenshot | Playwright MCP |
| FE-07 | Browser console sanity | true | `/` | UI loaded | Monitor console | No fatal runtime errors | Console log | Playwright MCP |
| FE-08 | Responsive layout smoke | false | `/` | UI loaded | Resize viewport | Main controls remain usable | Screenshots | Playwright MCP |

---

# CLI / Operator Test Scenarios

| ID | Description | Required | Command | Preconditions | Steps | Expected Outcome | Expected Evidence | Testing Approach |
|---|---|---:|---|---|---|---|---|---|
| CLI-01 | Backend health via curl | true | `curl http://127.0.0.1:8000/api/health` | Backend running | Run command | 200 JSON | Terminal output | Shell |
| CLI-02 | Agent Card via curl | true | `curl http://ops-agent.../.well-known/agent-card.json` | Ops-Agent reachable | Run command | 200 JSON | Terminal output | Shell |
| CLI-03 | Direct A2A via curl/httpx | true | POST JSON-RPC | API key available | Run command | Completed task | Redacted response | Shell/Python |
| CLI-04 | Kubernetes logs | true | `kubectl logs deployment/ops-agent -n default --tail=50` | kubectl configured | Run after happy path | Logs show request processing, no secret leakage | Logs | Shell |
| CLI-05 | Foundry smoke script | false | `python apps/foundry-agent/test_agent.py` | Env vars configured | Run script | Smoke test passes | Script output | Shell |
| CLI-06 | App Insights KQL fallback | false | `az monitor app-insights query ...` | App Insights configured | Query last 10 min | Trace rows found | KQL output | Shell |

---

# Runtime Pipeline / Cross-Component Integration Tests

| ID | Description | Required | Components | Steps | Expected Outcome | Pass/Fail Criteria |
|---|---|---:|---|---|---|---|
| INT-01 | Browser-to-backend integration | true | React → FastAPI | Submit UI request | `/api/chat` called and stream consumed | Pass if UI receives events; fail if network/CORS error |
| INT-02 | Backend-to-Foundry integration | true | FastAPI → Foundry | POST `/api/chat` | Foundry Responses API streams events | Pass if text/tool events arrive; fail on auth/model errors |
| INT-03 | Foundry-to-Ops A2A integration | true | Foundry → AKS | Run happy path | A2A hop appears and Ops task completes | Pass if `a2a_hop` and task output; fail if timeout/no hop |
| INT-04 | A2A protocol contract | true | Foundry/Ops-Agent | Direct JSON-RPC and traced call | v0.3 `message/send`, no A2A-Version required | Pass if completed task; fail on parse/protocol error |
| INT-05 | LangGraph tool/data flow | true | Ops-Agent → JSON data | Direct A2A request | Inventory/schedule/orders/customer reflected in result | Pass if structured fields populated; fail if empty/defaults |
| INT-06 | R16 structured artifact flow | true | Ops-Agent → Foundry → Code Interpreter | Happy path | DataPart drives chart; TextPart drives answer | Pass if both parts and chart/text appear |
| INT-07 | SSE event translation | true | Foundry stream → Backend → React | `/api/chat` capture | `a2a_preview_call*` translated to `a2a_hop` | Pass if timeline has A2A rows |
| INT-08 | Code Interpreter chart detection | true | Foundry → Backend → React | Happy path | Inline `sandbox:/mnt/data/*.png` detected as chart event | Pass if chart SSE + UI placeholder |
| INT-09 | Observability control plane | true | Foundry/App Insights | Portal trace review | Trace shows run with tool calls | Pass if trace visible within 10 min |
| INT-10 | Model deployment binding | true | Backend → Foundry | Happy path | Uses `gpt-55-orchestrator` deployment | Pass if no model mismatch error |

---

# Error and Edge Scenarios

| ID | Description | Required | Severity | Steps | Expected Outcome | Fail Criteria |
|---|---|---:|---|---|---|---|
| ERR-01 | Missing A2A API key | true | Critical | POST direct A2A without key | 401 | 200/task accepted |
| ERR-02 | Wrong A2A API key | true | Critical | POST direct A2A with bad key | 401 | 200/task accepted |
| ERR-03 | Invalid quantity via backend | true | High | POST `/api/chat` with `quantity=0` or negative | 422 validation error or graceful client-side validation | Unhandled 500 |
| ERR-04 | Missing required backend field | true | High | Omit `sku` or `target_date` | 422 validation error | Unhandled 500 |
| ERR-05 | Unknown SKU direct A2A | false | Medium | Use `SKU=UNKNOWN` | Graceful not-found/infeasible answer | Crash or unrelated answer |
| ERR-06 | Backend Foundry auth issue | false | High | If Azure login expired, call `/api/chat` | SSE `error` event; backend logs actionable auth error | Silent hang |
| ERR-07 | Ops-Agent unavailable | false | High | Do not inject chaos; only if naturally down | Frontend/backend shows graceful error | Infinite spinner |

---

# Performance / Responsiveness Criteria

| Check | Required | Target |
|---|---:|---|
| Frontend first paint | true | < 3 seconds locally |
| Backend `/api/health` | true | < 500 ms |
| Agent Card fetch | true | < 2 seconds |
| Direct A2A response | true | Typically < 15 seconds; hard fail > 60 seconds |
| First SSE event after `/api/chat` | true | < 3 seconds |
| First meaningful timeline event | true | < 10 seconds |
| Full happy-path completion | true | Target < 60 seconds; investigate > 90 seconds |
| UI remains responsive while streaming | true | No browser freeze |

---

# Evidence Collection

For each required test, capture:

- Test ID
- Timestamp
- Tool used
- Redacted command/request
- HTTP status
- Key response assertions
- Screenshot if UI/portal
- Logs only if needed, with secrets removed

Do not store:
- Raw API key
- Full connection strings
- Bearer tokens
- Subscription/tenant IDs unless already public-safe and required for internal evidence

---

# Validation Checklist Mapped to R1–R27

> Note: `plan.md` explicitly names risks R1–R17. This checklist maps the requested R1–R27 coverage across the documented risk register plus the major accepted runtime/demo requirements.

| Req | Validation | Test IDs | Pass Criteria |
|---|---|---|---|
| R1 | Model quota/fallback does not break runtime | UJ-13, INT-10 | Backend uses deployment name and completes |
| R2 | A2A v0.3 interop works | UJ-02, API-04, INT-04 | `message/send` completes with v0.3 shape |
| R3 | AKS endpoint is live on deployed SKU | API-03, API-04, CLI-04 | Agent Card and A2A reachable |
| R4 | HTTP/sslip.io deployed path is accepted for demo | API-03, API-04, UJ-01 | Foundry can reach Ops-Agent |
| R5 | Foundry A2A preview behavior handled | UJ-11, INT-07 | `a2a_preview_call*` translated |
| R6 | Foundry SDK / Responses API works in GA | UJ-13, API-02 | No `api-version` or model mismatch errors |
| R7 | Agent Card discovery works | UJ-05, API-03 | Valid card with skills/capabilities/version |
| R8 | Workload identity/auth to Azure works | UJ-01, API-02 | Worker/backend calls succeed without credential errors |
| R9 | Code Interpreter chart path works or degrades gracefully | UJ-12, FE-04 | Chart event/placeholder appears |
| R10 | Foundry egress to A2A endpoint works | INT-03 | A2A hop completes |
| R11 | SSE streaming not buffered | UJ-07, API-10, FE-02 | Events stream progressively |
| R12 | Synthetic data consistency supports meaningful answer | UJ-01, INT-05 | Result fields populated and grounded |
| R13 | Foundry traces/App Insights visible | UJ-08, INT-09 | Portal or KQL shows trace |
| R14 | LangGraph/runtime version drift not visible | UJ-02, CLI-04 | Ops-Agent processes request without runtime errors |
| R15 | Demo cost/cleanup documented, not a runtime blocker | CLI-06 optional | Operator confirms cleanup runbook available |
| R16 | Dual-part artifact DataPart + TextPart | UJ-02, API-05, INT-06 | Both parts present every successful A2A response |
| R17 | A2A endpoint is not an open relay | UJ-03, UJ-04, API-06, API-07 | Missing/wrong key returns 401 |
| R18 | Backend health contract | UJ-06, API-01 | Exact health JSON shape |
| R19 | Frontend primary journey | UJ-01, FE-02 | User can complete demo flow |
| R20 | Timeline visualization | UJ-01, FE-03 | A2A/tool rows render |
| R21 | Tool-call visibility | UJ-07, FE-03 | At least one `tool_call` event shown |
| R22 | Natural-language parsing | UJ-09 | All phrasing variants work |
| R23 | Structured input parsing | UJ-09 | `SKU=...` phrasing works |
| R24 | Loose input parsing | UJ-09 | `sku: ... qty ...` phrasing works |
| R25 | Portal control-plane demo | UJ-08 | Agent and traces visible |
| R26 | Sandbox chart GA quirk | UJ-12, INT-08 | `sandbox:/mnt/data/*.png` becomes chart event |
| R27 | End-to-end demo readiness | UJ-01 through UJ-13 | All critical/high required tests pass |

---

# Overall Release Pass/Fail Gate

The deployed demo is ready for live presentation only if:

1. All **Critical** required scenarios pass.
2. All **High** required scenarios pass or have documented, non-demo-blocking workarounds.
3. No secret appears in captured evidence.
4. Frontend happy path completes from user input to final answer.
5. Direct A2A R16 dual-part artifact verification passes.
6. Backend SSE includes A2A, tool, text, chart, and done events.
7. Foundry portal trace is visible or App Insights KQL proves trace ingestion.

