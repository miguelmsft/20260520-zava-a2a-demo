# Mutual A2A Discovery — making the Foundry agent and the AKS agent discoverable to each other

> **Audience:** an engineer who already has the Zava demo's one-way flow
> (Foundry → AKS) working and wants to **enable the reverse direction**
> (AKS → Foundry) so both agents can discover and call each other.
>
> **Status in this repo:** only the Foundry→AKS direction is wired up
> today. This guide is the actionable cookbook to add the reverse
> direction. The work is small (~½ day) and entirely additive.

---

## TL;DR

A2A has **no symmetric handshake.** Discovery is **one-way per call**: the
*caller* fetches the *callee's* agent card before sending the JSON-RPC.
To make discovery bidirectional, **each side has to publish a card and the
other side has to know how to find it** — which means doing the
one-way setup *twice*, in opposite directions.

To enable the missing direction (**AKS → Foundry**) you do **three
things**:

1. **Foundry side:** enable the incoming A2A endpoint on the
   `zava-customer-service` agent (one PATCH call via REST or the Python
   SDK). Foundry then publishes its card at a platform-managed URL.
2. **AKS side:** grant the Ops Agent's workload identity the **Foundry
   User** role on the Foundry project (one role assignment).
3. **AKS side:** add ~30 lines that build an `A2AClient`, fetch the
   Foundry card with a bearer token, and send `message/send` calls.

After that, both sides have each other's URL hard-wired at deploy time,
and each one fetches the other's card on first delegation.

---

## The mental model

```
                      DISCOVERY (one-way, per call)

Foundry → AKS                                    AKS → Foundry
─────────────────                                ─────────────────
GET http://<aks>/                                GET https://<foundry>/.../
    .well-known/                                     agentCard/v0.3
    agent-card.json                                  (Authorization: Bearer ...)
                                                                                
no auth on card fetch                            Entra token required
auth on POST / (API key)                         Entra token required
                                                                                
✅ done in this demo                             ⬜ this guide enables this
```

Key asymmetries to internalise before you write any code:

|                              | Foundry → AKS (already working)             | AKS → Foundry (this guide enables)               |
|------------------------------|---------------------------------------------|--------------------------------------------------|
| Card URL                     | `/.well-known/agent-card.json`              | `agentCard/v0.3`  *(non-default path)*           |
| Auth on **card fetch**       | None (public bypass)                        | **Required** — Entra Bearer token                |
| Auth on **JSON-RPC `POST /`**| Pre-shared API key (`x-api-key`)            | **Required** — Entra Bearer token                |
| Endpoint URL                 | You choose                                  | Platform-managed (`/protocols/a2a`)              |
| RBAC                         | None (just key knowledge)                   | **Foundry User** on project                       |
| Transports supported         | JSON-RPC (also HTTP+JSON in the SDK)        | **HTTP+JSON ✓, JSON-RPC ✓, gRPC ✗**              |

> ⚠️ The single most-missed detail: **Foundry's card is NOT at
> `/.well-known/agent-card.json`.** It's at `…/protocols/a2a/agentCard/v0.3`.
> Your A2A client must be told the custom path or discovery will 404.
> ([Microsoft Learn — Connect to a Foundry A2A agent with the Python A2A SDK](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint))

---

## Step 1 — Enable the Foundry agent's incoming A2A endpoint

This is the step that makes the Foundry agent **publishable**. You PATCH
the agent to attach an agent card and turn on the A2A protocol on its
endpoint. It's not yet available in the Foundry portal UI — use the REST
API or the Python SDK.

### Python SDK (recommended — fits this repo's existing scripts)

Add a small follow-up step to [`apps/foundry-agent/setup_agent.py`](../apps/foundry-agent/setup_agent.py)
right after `project.agents.create_version(...)`:

```python
# Existing: create / update the prompt agent.
agent = project.agents.create_version(
    agent_name=agent_name,
    definition=definition,
)

# NEW: enable incoming A2A on the agent. Adds an agent card + flips the
# A2A protocol on the platform-managed endpoint.
from azure.ai.projects.models import AgentCard as FoundryAgentCard, AgentSkill

inbound_card = FoundryAgentCard(
    name="zava-customer-service",
    description=(
        "Customer-facing Zava sales agent. Accepts natural-language order "
        "requests (SKU, qty, target date, customer ID) and returns a "
        "feasibility verdict with chart."
    ),
    version="1.0.0",
    skills=[
        AgentSkill(
            id="order-feasibility-frontend",
            name="Order Feasibility (customer-facing)",
            description=(
                "Top-level entry point for sales-led feasibility questions; "
                "delegates to the manufacturing Ops Agent over A2A."
            ),
            tags=["sales", "feasibility", "customer-service"],
        ),
    ],
)

project.agents.enable_a2a_endpoint(
    agent_name=agent_name,
    agent_card=inbound_card,
)
```

> **Note:** the exact Python SDK method name above (`enable_a2a_endpoint`)
> matches the parameter shape exposed by `azure-ai-projects` 2.1.x+; if
> the method has been renamed by the time you read this, the REST PATCH
> below is the canonical wire format.

### REST API (canonical, language-agnostic)

```bash
SUB="<subscription-id>"
RG="<resource-group>"
ACCOUNT="foundry-zava-a2a-smartorder"
PROJECT="smart-order-feasibility"
AGENT="zava-customer-service"

TOKEN=$(az account get-access-token --scope https://management.azure.com/.default --query accessToken -o tsv)

curl -X PATCH \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCOUNT/projects/$PROJECT/agents/$AGENT?api-version=2025-06-01" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<'JSON'
{
  "properties": {
    "endpoint": {
      "protocols": {
        "a2a": {
          "enabled": true,
          "agentCard": {
            "name": "zava-customer-service",
            "description": "Customer-facing Zava sales agent.",
            "version": "1.0.0",
            "skills": [
              {
                "id": "order-feasibility-frontend",
                "name": "Order Feasibility (customer-facing)",
                "description": "Entry point for sales-led feasibility questions.",
                "tags": ["sales", "feasibility"]
              }
            ]
          }
        }
      }
    }
  }
}
JSON
```

→ Full docs: [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint).

### What this gives you

After the PATCH succeeds, Foundry publishes two URLs:

```
A2A base   : https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a
Agent card : https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a/agentCard/v0.3
```

For this demo's resource names:

```
A2A base   : https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility/agents/zava-customer-service/endpoint/protocols/a2a
Agent card : https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility/agents/zava-customer-service/endpoint/protocols/a2a/agentCard/v0.3
```

Both URLs require Microsoft Entra ID authentication. The card endpoint
is **not** anonymous (unlike our AKS side, which is). The caller must
present a Bearer token whose identity has the **Foundry User** role on
the Foundry project.

### Verify it from your laptop

```powershell
$BASE = "https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility/agents/zava-customer-service/endpoint/protocols/a2a"
$TOKEN = (az account get-access-token --scope https://ai.azure.com/.default --query accessToken -o tsv)
curl -H "Authorization: Bearer $TOKEN" "$BASE/agentCard/v0.3"
```

Expect a JSON `AgentCard` matching what you PATCHed. If you get **401**,
you're missing the **Foundry User** role on the project. If you get
**404**, the PATCH didn't apply (or the path is wrong — note `agentCard/v0.3`,
not `.well-known/agent-card.json`).

---

## Step 2 — Grant the AKS Ops Agent's identity Foundry-User on the project

The AKS pod already has a **workload identity** (federated to a
user-assigned managed identity in the same RG, used today only to pull
the API key out of Key Vault for Foundry→AKS). To enable AKS→Foundry,
that managed identity also needs `Foundry User` on the **project**.

### Bicep (add to `infra/modules/identity.bicep`)

```bicep
@description('Grant the Ops Agent UAMI Foundry User on the project so it can call Foundry agents over A2A.')
resource opsAgentFoundryUserOnProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, opsAgentUami.id, 'foundry-user')
  scope: project                  // <-- scope is the *project*, not the account
  properties: {
    // 'Foundry User' (formerly 'Azure AI User'). Role IDs are unchanged by the rename.
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '53ca6127-db72-4b80-b1b0-d745d6d5456d'           // <-- replace with the actual Foundry User role ID
    )
    principalId: opsAgentUami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

> Look up the current role ID with
> `az role definition list --name "Foundry User" --query "[].id" -o tsv`
> before deploying — Microsoft re-issued role IDs during the
> Azure AI Foundry → Microsoft Foundry rename. The placeholder above is
> for illustration only.

### Why the project scope (not the account)?

The data-plane authorization for the agent's A2A endpoint is evaluated
against the **project** that owns the agent. A role on the parent
Foundry account does NOT propagate; you must assign it on the project
directly. ([Role-based access control in the Foundry portal](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry))

---

## Step 3 — Make the AKS agent fetch the Foundry card and call back

Add a new module to the Ops Agent — for example
`apps/ops-agent/app/foundry_client.py` — that uses the open-source
`a2a-sdk` to discover and call the Foundry agent. The official docs
publish the exact pattern; the code below is adapted from
[Microsoft Learn — Connect to a Foundry A2A agent with the Python A2A SDK](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint).

### Add the dependencies

In `apps/ops-agent/pyproject.toml`:

```toml
dependencies = [
    # existing deps...
    "azure-identity>=1.25.3",
    "httpx>=0.28.1",
    # a2a-sdk is already a dependency — confirm it's pinned >=1.0.2
]
```

### The client module

```python
# apps/ops-agent/app/foundry_client.py
import os
import httpx

from azure.identity import DefaultAzureCredential
from a2a.client import A2ACardResolver, ClientConfig, create_client
from a2a.helpers import new_text_message
from a2a.types.a2a_pb2 import Role, SendMessageRequest

# Env vars (write these in deploy-k8s.ps1 after the Foundry agent is provisioned).
FOUNDRY_A2A_BASE_URL = os.environ["FOUNDRY_A2A_BASE_URL"]
# Foundry's card is at a non-default path. DO NOT use .well-known/agent-card.json.
FOUNDRY_AGENT_CARD_PATH = "agentCard/v0.3"
# Entra scope for Foundry data plane.
FOUNDRY_TOKEN_SCOPE = "https://ai.azure.com/.default"


async def call_foundry_agent(message: str) -> list[str]:
    """Send `message` to the Foundry zava-customer-service agent and
    return its response text(s)."""
    credential = DefaultAzureCredential()
    token = credential.get_token(FOUNDRY_TOKEN_SCOPE).token

    async with httpx.AsyncClient(
        headers={"Authorization": f"Bearer {token}"},
        timeout=httpx.Timeout(120.0),
    ) as http:
        # 1. Discovery — fetch the Foundry agent's card from the custom path.
        resolver = A2ACardResolver(
            httpx_client=http,
            base_url=FOUNDRY_A2A_BASE_URL,
            agent_card_path=FOUNDRY_AGENT_CARD_PATH,
        )
        card = await resolver.get_agent_card()

        # 2. Build a non-streaming A2A client targeted at the resolved card.
        client = await create_client(
            agent=card,
            client_config=ClientConfig(streaming=False, httpx_client=http),
        )

        # 3. Send the message.
        request = SendMessageRequest(
            message=new_text_message(message, role=Role.ROLE_USER),
        )
        responses: list[str] = []
        async for resp in client.send_message(request):
            # Each response has parts; collect any text payloads.
            for part in (resp.message.parts if resp.message else []):
                if part.HasField("text"):
                    responses.append(part.text)
        await client.close()
        return responses
```

### Why this looks slightly different from the AKS server-side code

The AKS Ops Agent's *server* (`server.py`) implements an `AgentExecutor`
to be called by Foundry. The code above is the *client* side — used
when the Ops Agent wants to call Foundry. Both come from the same
`a2a-sdk` library; you just use different submodules.

### Wire it into the LangGraph graph as a tool

In `apps/ops-agent/app/agent.py`, expose `call_foundry_agent` as a tool
so the LangGraph LLM can decide when to delegate. A minimal binding:

```python
from langchain_core.tools import tool
from .foundry_client import call_foundry_agent

@tool
async def ask_customer_service_agent(question: str) -> str:
    """Ask the Zava customer-service agent on Foundry for context that
    only the customer-facing system would know (e.g., recent order
    notes for this customer)."""
    answers = await call_foundry_agent(question)
    return "\n".join(answers) if answers else "(no response)"

# ... bind ask_customer_service_agent into the LLM's tools list.
```

The system prompt should explain when to call this tool (and when **not**
to — otherwise you'll get infinite delegation loops between the two
agents).

### Pod environment variables to add

In your K8s manifest (`apps/ops-agent/k8s/deployment.yaml`):

```yaml
env:
  # existing A2A_API_KEY, OPS_AGENT_PUBLIC_URL, etc.
  - name: FOUNDRY_A2A_BASE_URL
    value: "https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility/agents/zava-customer-service/endpoint/protocols/a2a"
  - name: AZURE_CLIENT_ID
    value: "<ops-agent UAMI client id>"          # workload-identity hint for DefaultAzureCredential
```

Make sure the pod has the workload-identity annotations already in
place (added in the existing demo) so `DefaultAzureCredential` finds the
managed identity.

---

## Step 4 — End-to-end verification

After deploying:

1. **AKS side — confirm the Ops Agent can fetch the Foundry card.**
   ```powershell
   kubectl exec deploy/ops-agent -- python -c "
   import asyncio
   from app.foundry_client import call_foundry_agent
   print(asyncio.run(call_foundry_agent('What can you do?')))
   "
   ```
   Expect a non-empty list of text responses describing the Foundry
   agent's skills.

2. **Foundry side — confirm the trace shows up.** Foundry portal →
   project → Agents → `zava-customer-service` → **Traces**. You should
   see a new invocation initiated by the **Ops Agent's managed
   identity** (not by your interactive user). In App Insights KQL:
   ```kusto
   requests
   | where timestamp > ago(10m)
   | where customDimensions["gen_ai.agent.name"] == "zava-customer-service"
   | where cloud_RoleName != "ops-agent"   // i.e. server-side requests, not outbound
   | take 5
   ```

3. **Demo it in the UI.** Modify the LangGraph system prompt to call
   `ask_customer_service_agent` for any *customer history* question
   that arrives in the ops-agent's prompt (e.g., "What did this
   customer order last quarter?"). When the React UI's conversation
   panel shows the round-trip, you'll have a **bidirectional** A2A
   hop chain visible on screen.

---

## Common gotchas

| Symptom | Likely cause | Fix |
|---|---|---|
| `404 Not Found` when fetching the Foundry card | Used `/.well-known/agent-card.json` (the AKS path) instead of `agentCard/v0.3` | Pass `agent_card_path="agentCard/v0.3"` to `A2ACardResolver` |
| `401 Unauthorized` on card fetch | Caller identity is missing **Foundry User** on the project, OR token scope wrong | (1) Check role assignment is on the **project**, not the account. (2) Token scope must be `https://ai.azure.com/.default`, not `https://management.azure.com/.default`. |
| `401 Unauthorized` only after the card fetch succeeds | Card fetch and JSON-RPC use the SAME token but you cached the card and the token expired | Re-fetch the token on every call (a short-lived token is fine for A2A) or use `DefaultAzureCredential().get_token` per-request. |
| Foundry returns 400 with no body | A2A v1.0 wire format hitting a v0.3-only server | `a2a-sdk` 1.0.x auto-negotiates v0.3 from the card's `protocol_version`; double-check Foundry's card declares `"protocol_version": "0.3"`. |
| Agents call each other in a loop | System prompts on both sides delegate by default for the same question | Add explicit *non-delegation* instructions in the prompt: "Only call the other agent when X. NEVER call back if you were the one delegated to." |
| AKS side gets `ManagedIdentityCredential authentication unavailable` | Workload identity not wired up | Confirm the pod has `azure.workload.identity/use: "true"`, the ServiceAccount has `azure.workload.identity/client-id` matching your UAMI, and the federated credential exists. |
| Foundry portal shows traces only from one direction | Only one direction's traces flow through Foundry (the Foundry-side runtime). AKS-side traces go to App Insights. | Use App Insights KQL for cross-direction visibility — `dependencies` table will show both. |

---

## RBAC + auth summary (cheat sheet)

```
                        WHO     →  WHAT                  →  AUTH                      →  ROLE
                        ───────    ─────────────────────    ──────────────────────────    ───────────────
Foundry → AKS card      Foundry    GET aks/.well-known/      none (public bypass)          n/a
                                   agent-card.json
Foundry → AKS POST /    Foundry    POST aks/                 x-api-key (pre-shared)         n/a
                                                             from project connection
AKS → Foundry card      AKS UAMI   GET foundry/agentCard     Bearer token                   Foundry User
                                   /v0.3                     (scope=ai.azure.com/.default)  on project
AKS → Foundry POST      AKS UAMI   POST foundry/protocols/   Bearer token (same)            Foundry User
                                   a2a                                                      on project
```

---

## References (official Microsoft documentation)

- [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) — the canonical page for Step 1 + Step 3 (REST + Python SDK + the exact Python A2A client snippet this guide adapts).
- [Connect to an A2A agent endpoint from Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent) — the other-direction reference (Foundry → remote A2A); useful for understanding the symmetric setup.
- [Role-based access control in the Foundry portal](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry) — RBAC roles and the recent rename to "Foundry User / Foundry Owner / Foundry Account Owner / Foundry Project Manager."
- [Foundry Agents — Hosted agents (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) — relevant if you go the hosted-agents route instead of prompt agents.
- [a2a-protocol.org](https://a2a-protocol.org/latest/) — the open A2A protocol specification.

## In this repo

- [`docs/a2a-foundry-walkthrough.md`](./a2a-foundry-walkthrough.md) — the
  beginner's guide to the Foundry → AKS direction (publishing a card,
  setting up an A2A connection, binding `A2APreviewTool`).
- [`docs/a2a-implementation.md`](./a2a-implementation.md) — wire-level
  reference covering both directions (currently only the Foundry → AKS
  half is exercised in code; this guide is the to-do list for closing
  the loop).
- [`apps/foundry-agent/setup_agent.py`](../apps/foundry-agent/setup_agent.py) —
  where Step 1's `enable_a2a_endpoint` call would go.
- [`apps/ops-agent/app/`](../apps/ops-agent/app/) — where the new
  `foundry_client.py` from Step 3 would live.

---

*Last updated: 2026-05-22.*
