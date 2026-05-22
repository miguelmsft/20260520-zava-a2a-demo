# A2A in Foundry Agents — a beginner-friendly walkthrough

> **Audience:** an engineer or architect who has heard of A2A, has used Foundry
> V2 once or twice, and wants to know **exactly what to do** to make a
> Foundry agent talk to another agent over the A2A protocol.
>
> **Format:** five concrete steps + the wire-level "what's actually happening"
> at each one. Every code snippet in this doc is grounded in real code that
> ships with this repo, so you can copy-paste and adapt.
>
> **Companion docs:**
> - [`a2a-implementation.md`](./a2a-implementation.md) — the dense reference (spec versions, all parts of the message envelope, error handling)
> - [`how-to-demo.md`](./how-to-demo.md) — the full deploy + run script

---

## TL;DR

To make a Foundry V2 agent call another agent over A2A you need **three
things** in place:

1. A **remote agent** that serves the **A2A protocol** — it publishes an
   *Agent Card* at `/.well-known/agent-card.json` and accepts `message/send`
   JSON-RPC calls at the root URL.
2. An **A2A connection** registered in your **Foundry project** — this is
   how Foundry knows the remote agent's URL and how to authenticate to it
   (the demo uses a pre-shared API key).
3. The Foundry agent itself, **created with the `A2APreviewTool`** bound to
   that connection — that is the one line that turns "I'm an LLM with a
   system prompt" into "I'm an LLM that can call another agent."

That's it. The rest of this document is just showing you, step by step,
exactly how to do each one.

---

## What A2A is, in one paragraph

**A2A (Agent-to-Agent)** is an open protocol — JSON-RPC 2.0 over HTTPS —
that lets two AI agents talk to each other without sharing code, a vendor
SDK, or a custom REST contract. A client agent fetches a JSON *Agent Card*
from a well-known URL to discover what the remote agent can do, then sends
a `message/send` request and receives back a structured `Task` whose
artifacts are typed *parts* (text, JSON data, files). Foundry V2 currently
emits **A2A version 0.3**. That's the version this demo also serves.

If you want the full spec, the canonical reference is
[`research/2026-05-20-a2a-protocol.md`](../research/2026-05-20-a2a-protocol.md).
For this walkthrough you do **not** need to memorise the spec — the SDKs
do the heavy lifting.

---

## Step 1 — Stand up the remote agent (the A2A server)

In this demo the remote agent is a LangGraph application that runs in a
container on AKS. The framework that exposes it over A2A is the open-source
[`a2a-sdk`](https://github.com/google-a2a/a2a-python) Python library. You
need three small pieces of code.

### 1a — Describe yourself in an Agent Card

The Agent Card is a JSON document at `/.well-known/agent-card.json` that
tells callers your agent's name, skills, supported modalities, and how to
reach it. Build it once at startup and let the SDK serve it for you:

```python
# apps/ops-agent/app/agent_card.py
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill

def build_agent_card() -> AgentCard:
    public_url = os.environ["OPS_AGENT_PUBLIC_URL"]   # e.g. http://ops-agent.<ip>.sslip.io/

    skill = AgentSkill(
        id="order-feasibility",
        name="Order Feasibility Check",
        description="Given SKU, qty, target date, customer — returns a feasibility report.",
        tags=["manufacturing", "inventory", "feasibility"],
        examples=["Can we ship 150 ZP-7000 pumps for CUST-001 by 2026-07-15?"],
    )

    return AgentCard(
        name="Zava Manufacturing Ops Agent",
        description="Computes order feasibility from inventory and capacity data.",
        version="1.0.0",
        default_input_modes=["text/plain"],
        default_output_modes=["application/json", "text/plain"],
        capabilities=AgentCapabilities(streaming=False),
        skills=[skill],
        supported_interfaces=[
            AgentInterface(url=public_url, protocol_binding="jsonrpc", protocol_version="0.3"),
        ],
    )
```

> **Why this matters:** Foundry hits `/.well-known/agent-card.json` *before*
> it ever sends a real request. If your card is wrong (404, malformed JSON,
> the wrong URL in `supported_interfaces`), the Foundry connection will
> appear to be created but **the first real call will fail with a
> discovery error**. Always serve the card before you wire up the
> connection.

### 1b — Translate one A2A request into one application result

A2A SDKs separate the *protocol* (what events go on the wire) from the
*application logic* (what the agent actually does). You provide an
`AgentExecutor` whose job is: read the inbound message, run your logic,
publish the result back as a `Task` with one or more *artifacts*.

```python
# apps/ops-agent/app/executor.py  (essential lines only)
from a2a.helpers import new_data_part, new_text_part, new_task
from a2a.server.agent_execution import AgentExecutor
from a2a.server.tasks import TaskUpdater
from a2a.types import TaskState

class ZavaOpsAgentExecutor(AgentExecutor):
    async def execute(self, context, event_queue):
        updater = TaskUpdater(event_queue=event_queue,
                              task_id=context.task_id, context_id=context.context_id)

        # Required: put a Task on the queue before any status / artifact events.
        if context.current_task is None:
            await event_queue.enqueue_event(new_task(
                task_id=context.task_id, context_id=context.context_id,
                state=TaskState.TASK_STATE_SUBMITTED,
            ))
        await updater.start_work(message=updater.new_agent_message(
            parts=[new_text_part("Querying inventory and capacity...")]
        ))

        # 1. Your actual application logic — here, invoke a LangGraph graph.
        result = await my_langgraph_graph.ainvoke({"messages": [{"role": "user", "content": context.message_text}]})
        feasibility_dict = result["feasibility"]   # structured result
        summary_text     = result["summary"]       # human-readable

        # 2. Emit a DUAL-PART artifact: the JSON for programmatic consumers
        #    (the Foundry orchestrator), and the text for everything else.
        await updater.add_artifact(
            parts=[
                new_data_part(feasibility_dict, media_type="application/json"),
                new_text_part(summary_text),
            ],
            artifact_id="art-feasibility-1",
            name="order-feasibility",
            last_chunk=True,
        )
        await updater.complete()
```

> **Why the dual-part artifact pattern matters:** Foundry's orchestrator
> agent doesn't natively re-parse JSON out of a free-text reply. If you
> only emit a `TextPart` you'll spend a lot of time prompt-engineering the
> orchestrator to extract numbers from prose. Emit a `DataPart` alongside
> the `TextPart` and the orchestrator can read the JSON directly. We call
> this the **dual-part artifact pattern**. [`a2a-implementation.md` §7](./a2a-implementation.md)
> goes deeper.

### 1c — Wire it all into a Starlette app with one auth middleware

A2A is just JSON-RPC over HTTPS, so any ASGI framework works. The SDK
generates the `/.well-known/agent-card.json` and `POST /` routes for you;
you just add an auth middleware so randoms can't call your agent:

```python
# apps/ops-agent/app/server.py  (essential lines only)
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes.agent_card_routes import create_agent_card_routes
from a2a.server.routes.jsonrpc_routes import create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore

handler = DefaultRequestHandler(
    agent_executor=ZavaOpsAgentExecutor(),
    task_store=InMemoryTaskStore(),
    agent_card=build_agent_card(),
)

routes = []
routes += create_agent_card_routes(build_agent_card())       # /.well-known/agent-card.json
routes += create_agent_card_routes(build_agent_card(),
                                   card_url="/.well-known/agent.json")  # legacy path
routes += create_jsonrpc_routes(handler, "/", enable_v0_3_compat=True)  # POST /
routes.append(Route("/health", endpoint=_health, methods=["GET"]))

app = Starlette(routes=routes, middleware=[Middleware(ApiKeyAuthMiddleware, ...)])
```

Two things to call out:

1. **`enable_v0_3_compat=True`** — Foundry currently sends A2A v0.3 (no
   `A2A-Version` header). Pass this flag so the SDK's v1.0 server accepts
   v0.3 calls. Without it you'll see a confused 400 from a v0.3 caller.
2. **Serve both `agent-card.json` AND legacy `agent.json`** — Foundry's
   discovery client probes both paths. Serving the same card at both
   URLs costs you nothing and saves a frustrating 30-min debug.

### 1d — Protect the endpoint with an API key

Foundry's A2A tool sends a configurable header (we use `x-api-key`) on
every outbound call. The remote agent must check it on every non-public
route, and **must refuse to start without a key** so nobody can deploy an
open relay by accident:

```python
class ApiKeyAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        if request.url.path in {"/health", "/.well-known/agent-card.json",
                                "/.well-known/agent.json"}:
            return await call_next(request)                  # bypass for probes & discovery
        provided = request.headers.get("x-api-key", "")
        if not provided or not hmac.compare_digest(
            provided.encode("utf-8"), self._expected_key_bytes
        ):
            return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)
```

Two non-obvious details:

- **Bypass the auth on the agent card** — Foundry has to read the card
  *before* it knows what auth scheme to use. (Some setups also let the
  card itself declare the auth scheme, which would be a chicken-and-egg
  problem if you blocked the card.)
- **`hmac.compare_digest`** — constant-time comparison so an attacker
  can't time-side-channel the key.

→ Full server file: [`apps/ops-agent/app/server.py`](../apps/ops-agent/app/server.py).

---

## Step 2 — Register an A2A connection in your Foundry project

Foundry agents call remote A2A endpoints via a **project connection** —
the same abstraction Foundry uses for App Insights, Storage, and other
external resources. The connection holds the remote agent's URL and the
auth header to send.

For an A2A connection you create a connection of category `CustomKeys`
with `metadata.a2a_subtype = "agent"`. There are three ways to do it,
listed best-to-worst:

### 2a — (Preferred) ARM REST PUT — fully automated

`PUT https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}/projects/{project}/connections/{name}?api-version=2025-06-01`

```jsonc
{
  "properties": {
    "category": "CustomKeys",
    "target":   "http://ops-agent.<ip>.sslip.io/",
    "authType": "CustomKeys",
    "credentials": { "keys": { "x-api-key": "<your-pre-shared-key>" } },
    "metadata":    { "a2a_subtype": "agent" }
  }
}
```

This is what `apps/foundry-agent/create_a2a_connection.py` does (and what
`scripts/create-a2a-connection.ps1` wraps for the one-command deploy).
Required RBAC on the calling principal: **Cognitive Services Contributor**
(or higher) on the Foundry account.

### 2b — Python SDK fallback — works on future SDK versions

```python
from azure.ai.projects import AIProjectClient
project.connections.create(                 # exists in future SDKs; missing in 2.1.x
    connection_type="A2A",
    name="ops-agent-a2a",
    endpoint="http://ops-agent.<ip>.sslip.io/",
    auth={"type": "api_key", "header_name": "x-api-key", "header_value": "..."},
)
```

The data-plane SDK (`azure-ai-projects` 2.1.x) does **not** expose
`connections.create` yet. The shipped script tries this path inside a
`try/except` for forward-compat; expect it to fail today and fall through
to the ARM path.

### 2c — Portal — for operators without ARM write access

Foundry portal → your project → **Connected resources** → **+ New
connection** → **Custom keys** → fill the form:

| Field            | Value                                                              |
|------------------|--------------------------------------------------------------------|
| Name             | `ops-agent-a2a`                                                    |
| Target URL       | `http://ops-agent.<ip>.sslip.io/`  (trailing slash required)        |
| Auth header name | `x-api-key`                                                        |
| Auth header value| your pre-shared key                                                |
| Metadata         | add a key `a2a_subtype` with value `agent`                          |

### Sanity-check the connection

Whichever path you used, verify the connection round-trips before
spending time on the agent itself:

```python
from azure.ai.projects import AIProjectClient
project = AIProjectClient(endpoint=FOUNDRY_PROJECT_ENDPOINT, credential=DefaultAzureCredential())
conn = project.connections.get(name="ops-agent-a2a")
print(conn.id, conn.endpoint or conn.target)
```

You should see a `/connections/ops-agent-a2a` ARM ID and your remote
agent's URL. If `connections.get` raises 404, your ARM resource group or
project name is wrong (the script auto-derives them — set
`AZ_RESOURCE_GROUP` / `AZ_SUBSCRIPTION_ID` to override).

→ Full script: [`apps/foundry-agent/create_a2a_connection.py`](../apps/foundry-agent/create_a2a_connection.py).

---

## Step 3 — Create the Foundry agent with the A2A tool bound

This is the line that makes everything click. When you create the Foundry
agent, you pass a list of `tools=[...]` to the agent definition. Include
an `A2APreviewTool` pointing at the connection you just created, and the
agent gains the ability to "call another agent" as if it were any other
tool.

```python
# apps/foundry-agent/setup_agent.py  (essential lines only)
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    A2APreviewTool,
    CodeInterpreterTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential

with AIProjectClient(endpoint=FOUNDRY_PROJECT_ENDPOINT,
                     credential=DefaultAzureCredential()) as project:

    # 1. Look up the connection we created in Step 2.
    connection = project.connections.get(name="ops-agent-a2a")

    # 2. Declare the tools the agent has. CodeInterpreter is optional;
    #    A2APreviewTool is the one that makes A2A possible.
    tools = [
        CodeInterpreterTool(),
        A2APreviewTool(project_connection_id=connection.id),
    ]

    # 3. Create (or version-bump) the agent.
    definition = PromptAgentDefinition(
        model=ORCHESTRATOR_DEPLOYMENT,             # e.g. "gpt-55-orchestrator"
        instructions=open("system_prompt.md").read(),
        tools=tools,
    )
    agent = project.agents.create_version(
        agent_name="zava-customer-service",
        definition=definition,
    )
```

Three things worth knowing:

1. **`A2APreviewTool` is a single line.** That's what you came here for.
   You don't need to declare the remote agent's schema, parameters, or
   skills in the Foundry agent — Foundry will introspect the Agent Card
   from the remote URL and let the LLM pick the right skill.
2. **`create_version` is idempotent.** Each call creates a **new
   immutable version** under the same logical `agent_name`. Re-running
   after a prompt edit doesn't break anything; older versions are still
   addressable.
3. **`PromptAgentDefinition.model` takes the *deployment name*** — not the
   model family. Use the name from your Bicep output
   (`orchestratorDeploymentName`), e.g. `gpt-55-orchestrator`.

→ Full script: [`apps/foundry-agent/setup_agent.py`](../apps/foundry-agent/setup_agent.py).

### Tell the LLM to actually use the tool

Bind-the-tool is half the job. The other half is your system prompt
instructing the model to delegate. A short, explicit instruction beats a
long, vague one:

```text
You have access to a delegate_to_ops tool (the A2A tool). You MUST call
delegate_to_ops for any feasibility question. Do NOT answer feasibility
questions without calling the tool first. Pass the user's request as the
message body; the tool returns a structured JSON result you can then quote.
```

The full system prompt the demo uses lives at
[`apps/foundry-agent/system_prompt.md`](../apps/foundry-agent/system_prompt.md).

---

## Step 4 — Invoke the Foundry agent and watch A2A happen

Invoke the agent from your application code (FastAPI, a console script,
anything that can call Foundry V2):

```python
# Simplified — see apps/backend/app/foundry_client.py for the real code
from openai import AzureOpenAI

client = AzureOpenAI(
    azure_endpoint=FOUNDRY_PROJECT_ENDPOINT.replace("/api/projects/...", ""),
    api_version="",                                    # explicitly empty for Foundry V2 GA
    azure_ad_token_provider=token_provider,
)

response = client.responses.create(
    model="gpt-55-orchestrator",                       # the bound deployment, NOT the agent name
    agent_reference={"type": "agent_reference", "name": "zava-customer-service"},
    input=[{"role": "user", "content": "Can we ship 150 ZP-7000 pumps by 2026-07-15?"}],
    stream=True,
)
```

When the LLM decides to delegate, you'll see a tool-call event in the
streaming response with `name=remote_a2a_ops-agent-a2a.SendMessage`. That
is your A2A hop. The Foundry runtime, on receiving that tool call:

1. Looks up the `ops-agent-a2a` connection (using the connection ID it
   has cached against your agent definition).
2. Fetches `/.well-known/agent-card.json` from the connection's `target`
   (once per agent version — cached afterwards).
3. Sends a JSON-RPC `message/send` request to the remote agent's URL with
   the `x-api-key` header populated from the connection credentials.
4. Waits for the `Task` response, extracts the artifact, and feeds the
   result back into the LLM context.
5. The LLM uses the result to compose the final user-facing answer.

The whole hop usually takes 1–3 seconds for a small payload.

### What you see when it works

The trace below is from a real run of this demo, captured from App
Insights (and visible in the Foundry portal's **Traces** tab):

```
[span] gen_ai.agent.invoke   agent=zava-customer-service:1  model=gpt-55-orchestrator
 └─ [span] execute_tool  remote_a2a_ops-agent-a2a.SendMessage
     │   gen_ai.tool.type          = extension
     │   gen_ai.tool.name          = remote_a2a_ops-agent-a2a.SendMessage
     │   gen_ai.tool.call.arguments = { "message": { "parts": [ { "kind": "text",
     │                                  "text": "Check feasibility for order: SKU
     │                                  ZP-7000, quantity 150, target date 2026-07-15,
     │                                  customer ID CUST-001. ..." } ] } }
     │   gen_ai.tool.call.result    = "Yes — this order can be fulfilled, earliest
     │                                  promise date 2026-06-23. ..."
     └─ [http] POST http://ops-agent.<ip>.sslip.io/  →  200  (1.4 s)
```

Two clicks to find this in the portal: **Foundry portal → your project →
Agents → `zava-customer-service` → Traces tab**.

---

## Step 5 — Observe and verify

Once it's working end-to-end, the things to check on a recurring basis:

1. **Discovery still resolves.** From any laptop:
   `curl http://<remote-host>/.well-known/agent-card.json` should return
   200 with your card.
2. **Auth still rejects unauthenticated calls.** Without the API key
   header you should get a 401 from `POST /`.
3. **Foundry can still reach the agent.** Re-run
   `apps/foundry-agent/test_agent.py` — it submits one feasibility
   request and asserts that the response contains the A2A hop and the
   structured `DataPart` artifact.
4. **Traces are flowing into App Insights.** If the portal's Traces tab is
   empty, run the KQL fallback:
   ```kusto
   dependencies
   | where timestamp > ago(30m)
   | where name contains "remote_a2a"
   | project timestamp, name, target, customDimensions
   ```
   A non-zero count confirms the link.

---

## Common pitfalls

| Symptom                                                        | Likely cause                                                                                        | Fix                                                                                                                  |
|----------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Connection saves but the first call fails with discovery error | Agent Card URL in `supported_interfaces[].url` doesn't match the connection's `target`              | Set `OPS_AGENT_PUBLIC_URL` env on the pod to the exact URL stored in the connection; restart the deployment           |
| 401 on every call from Foundry                                 | `x-api-key` header value out of sync                                                                | Re-read the key from `kubectl get secret ops-agent-secrets` and update the connection via ARM REST (or in the portal) |
| 400 from the remote agent with no body                         | A2A v0.3 client + a v1.0-only server                                                                 | Pass `enable_v0_3_compat=True` to `create_jsonrpc_routes`                                                            |
| Orchestrator answers in prose instead of using the JSON         | Remote agent only returned a `TextPart`                                                              | Emit a `DataPart` alongside the `TextPart` (the dual-part artifact pattern)                                            |
| `invalid_payload: api-version not allowed`                     | Foundry V2 GA rejects `api-version` on `/openai/v1/...`                                              | Don't set `api_version` (or set it to `""`) on the AzureOpenAI client                                                  |
| `BadRequestError: Model must match the agent's model 'foo'`    | You passed the agent name to `responses.create(model=...)` instead of the bound deployment name      | Pass the deployment name (e.g. `gpt-55-orchestrator`), not the agent name                                              |
| Traces tab is empty after 10 min                                | App Insights → Foundry linkage missing                                                              | Foundry portal → Connected resources → confirm App Insights is linked AND **Tracing** is toggled ON                  |

---

## What this walkthrough is *not* trying to teach you

This is the happy path. For a real production deployment you would also:

- Use a managed identity instead of a pre-shared key (when the A2A tool
  supports it — currently API-key-only at Foundry V2 GA).
- Sit both agents behind private endpoints (see
  [`private-vnet-considerations.md`](./private-vnet-considerations.md)).
- Emit signed Agent Cards and rotate the API key on a schedule.
- Add retry logic / circuit breakers between the agents (the SDK has
  hooks; this demo intentionally keeps the executor simple).

For all of that, [`a2a-implementation.md`](./a2a-implementation.md) is the
deeper reference.

---

## Where to look next

- **Try it yourself:** follow [`how-to-demo.md`](./how-to-demo.md) — one
  command (`./scripts/deploy-all.ps1`) provisions everything end-to-end.
- **Read the live wire format:** the JSON-RPC bodies and headers are
  spelled out in [`a2a-implementation.md`](./a2a-implementation.md) §4.
- **Adapt this to your own stack:** every script in `apps/foundry-agent/`
  and `apps/ops-agent/app/` is small enough to read in one sitting.

---

*Last updated: 2026-05-22.*
