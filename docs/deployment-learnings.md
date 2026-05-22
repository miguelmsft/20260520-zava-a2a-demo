# Deployment Learnings — Phase 6 Live Deployment Notes

> **Status:** The Zava A2A demo has been deployed end-to-end against a real
> Azure subscription and a complete Foundry V2 → A2A → LangGraph-on-AKS →
> Code-Interpreter-chart flow has been verified working. This document
> captures the workarounds and corrections that were applied to the
> as-shipped scripts and code while bringing the demo up live. All of these
> corrections are committed to the repository — this doc explains *why* they
> exist so future operators do not get tripped up by the same gaps.
>
> **2026-05-22 update — W1, W2, W3, W4 are now AUTOMATED.** The original
> manual steps that this document was written to capture have been folded
> into the shipped scripts; see §10 ("Out-of-the-box single-command deploy")
> for the new entry point and what each workaround was replaced with.
> The earlier sections are preserved verbatim as historical context.

Last updated: 2026-05-22

---

## 1. Quick demo path — no DNS delegation required

> **Status: AUTOMATED** ✅ — `scripts/deploy-all.ps1` (or `scripts/deploy-k8s.ps1
> -UseSslipIo:$true`, the default) now performs the sslip.io ingress patching
> and the `OPS_AGENT_PUBLIC_URL` env override automatically. The manual steps
> in this section are kept as reference for understanding *why* the automation
> exists. See §10 for the new flow.

The original [`docs/how-to-demo.md`](./how-to-demo.md) assumes the operator
owns a public DNS zone (e.g., `zava.example.com`) and can delegate it to
Azure DNS at their registrar. **You do not need that for the demo to work.**

Instead, you can use [**sslip.io**](https://sslip.io) — a free public DNS
service that resolves any subdomain of the form `<anything>.<ip-with-dashes>.sslip.io`
to that IP. For example, `ops-agent.4-153-150-147.sslip.io` resolves to
`4.153.150.147`. This means:

1. **DNS delegation is not needed** — sslip.io is already public DNS.
2. **TLS certificate is not strictly needed** for the demo — Foundry's A2A
   tool accepts HTTP (`http://...`) endpoints. The A2A protocol allows
   plain HTTP for non-production. **For a customer-facing production demo,
   issue a Let's Encrypt cert against the sslip.io name** (their DNS-01
   challenge works fine; see §4 below). For internal demos, HTTP is fine.

### Recommended demo flow (validated path)

```text
deploy-infra.ps1 (real DNS zone)  → provisions everything except cert
                                  ↓
build-and-push.ps1                → ACR build
                                  ↓
deploy-k8s.ps1                    → applies manifests, gets ingress IP
                                  ↓
[manual] patch ingress to drop    → ingress host = ops-agent.<ip-dashed>.sslip.io
TLS section + use sslip.io host     drop tls: section entirely
                                  ↓
[manual] update OPS_AGENT_PUBLIC_URL → kubectl set env so agent card
                                       advertises the sslip.io URL
                                  ↓
[manual or ARM] create A2A         → ARM REST PUT (see §3)
connection                         → category=CustomKeys, target=http://...
                                  ↓
setup-foundry-agent.ps1            → creates Foundry agent v1
                                  ↓
test_agent.py                      → smoke test PASSES ✅
```

After your first successful run, the **live demo state** to capture in your
demo-handoff doc is:

| Item | Example value |
| --- | --- |
| Ingress LoadBalancer IP | `4.153.150.147` |
| Public DNS hostname | `ops-agent.4-153-150-147.sslip.io` |
| Public URL (used by A2A and the agent card) | `http://ops-agent.4-153-150-147.sslip.io/` |
| A2A connection name | `ops-agent-a2a` |
| A2A connection category | `CustomKeys` (with `metadata.a2a_subtype = "agent"`) |
| Foundry agent name | `zava-customer-service` (version 1) |
| Orchestrator deployment | `gpt-55-orchestrator` (model: gpt-5.4-mini) |
| Worker deployment | `gpt-54mini-worker` (model: gpt-5.4-mini) |
| Auth header | `x-api-key: <32-byte base64>` |

---

## 2. Foundry V2 GA Responses API — what changed

The Foundry V2 GA Responses API has a small number of breaking differences
vs. the older Preview SDK that the plan was written against. The shipped
backend now handles all of them; this section is documentation so future
edits do not regress them.

### 2.1 `api-version` is rejected on `/openai/v1/...`

The error you will see:

```
BadRequestError: 400 - {"error":{"code":"BadRequest",
"message":"api-version query parameter is not allowed when using /v1 path"}}
```

**Fix (already applied):** The backend (`apps/backend/app/agent_client.py`)
and `apps/foundry-agent/test_agent.py` now construct the OpenAI client
without passing `default_query={"api-version": ...}` unless
`FOUNDRY_OPENAI_API_VERSION` is explicitly set (for environments still on
older Preview SDK builds).

```python
if settings.foundry_openai_api_version:
    openai_client = project.get_openai_client(
        default_query={"api-version": settings.foundry_openai_api_version},
    )
else:
    openai_client = project.get_openai_client()
```

### 2.2 `agent_reference` requires a `type` field

The error you will see:

```
invalid_payload: required: Required properties ["type"] are not present
[Request ID: ...]', 'param': '/agent_reference'
```

**Fix (already applied):** All `agent_reference` payloads now include
`type: "agent_reference"` alongside `name`:

```python
extra_body = {
    "agent_reference": {
        "type": "agent_reference",  # required in GA
        "name": agent_name,
    },
}
```

### 2.3 `responses.create(model=...)` must equal the **bound model
deployment** — not the agent name

The error you will see:

```
invalid_payload: Model must match the agent's model 'gpt-55-orchestrator'
when agent is specified
```

**Fix (already applied):** Added `FOUNDRY_ORCHESTRATOR_DEPLOYMENT` setting
(default `gpt-55-orchestrator`) and pass that to `responses.create(model=...)`
while passing the agent name only inside `agent_reference`. The backend
`Settings` dataclass now carries both `foundry_agent_name` and
`foundry_orchestrator_deployment` as separate fields.

### 2.4 A2A output items emit `a2a_preview_call` / `a2a_preview_call_output`,
**not** `remote_function_call`

The earlier Preview SDK named these output items `remote_function_call`;
the GA stream emits two items per A2A turn:

* `a2a_preview_call` — the input the agent sent to the worker.
* `a2a_preview_call_output` — the worker's response (with structured
  `output` payload).

**Fix (already applied):** Both the backend translator
(`apps/backend/app/agent_client.py::_classify_event`) and the smoke test
(`apps/foundry-agent/test_agent.py`) now treat all three names as
equivalent and surface them as `a2a_hop` events in the SSE stream.

### 2.5 Code Interpreter charts are **embedded as `sandbox:/mnt/data/*.png`
markdown** in the final message — not emitted as separate `image_file`
output items

The chart artifact does not appear as a standalone `output_item` of type
`image_file`. Instead, the agent writes
`![chart](sandbox:/mnt/data/zava_feasibility_report.png)` inside the final
message text.

**Fix (already applied):** The backend translator scans `message`
output items for inline `sandbox:` references and emits a `chart` SSE event
with `data.sandbox_reference = true`. The frontend renders a chart
placeholder when this event arrives; the underlying file (if you want to
serve it for production) lives in the agent's sandbox and can be fetched
via the Foundry portal's run-detail view.

---

## 3. A2A connection creation — Foundry SDK gap and the ARM REST workaround

> **Status: AUTOMATED** ✅ — `scripts/create-a2a-connection.ps1` wraps the ARM
> PUT idempotently (GET → compare target → PUT only if different).
> `scripts/deploy-k8s.ps1` calls it after the LB IP is known. The PowerShell
> snippet below remains the source of truth for the API call shape and is
> what `create-a2a-connection.ps1` implements. See §10.

### The gap

The current Foundry V2 Python SDK (`azure-ai-projects` 2.1.x) **does not
expose a `connections.create()` method.** Only `get`, `list`, and
`get_default` are available:

```python
>>> from azure.ai.projects import AIProjectClient
>>> with AIProjectClient(endpoint=..., credential=...) as p:
...     [m for m in dir(p.connections) if not m.startswith("_")]
['get', 'get_default', 'list']
```

`apps/foundry-agent/create_a2a_connection.py` therefore prints manual
portal steps as its primary path.

### The workaround — direct ARM REST PUT

The **management plane** does support creating project connections via the
`Microsoft.CognitiveServices/accounts/{account}/projects/{project}/connections`
endpoint at API version `2025-06-01`. The Foundry agent runtime
treats a `CustomKeys` connection with the right metadata as an A2A target.

```powershell
$apiKey = '<your 32-byte base64 A2A key from deploy-k8s.ps1>'
$sub    = '<subscription id>'
$rg     = 'rg-zava-a2a-smart-order-demo'
$acct   = 'foundry-zava-a2a-smartorder'
$proj   = 'smart-order-feasibility'
$conn   = 'ops-agent-a2a'

$url  = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acct/projects/$proj/connections/$conn?api-version=2025-06-01"
$body = @{
  properties = @{
    category    = 'CustomKeys'
    target      = 'http://ops-agent.4-153-150-147.sslip.io/'
    authType    = 'CustomKeys'
    credentials = @{
      keys = @{ 'x-api-key' = $apiKey }
    }
    metadata = @{ a2a_subtype = 'agent' }
  }
} | ConvertTo-Json -Depth 6

$token = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
Invoke-WebRequest -Uri $url -Method Put `
  -Headers @{ 'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body $body -UseBasicParsing
```

**Verify:**

```powershell
python apps/foundry-agent/create_a2a_connection.py --verify
# Expected: "✓ Connection 'ops-agent-a2a' found." with type ConnectionType.CUSTOM
```

After this, `apps/foundry-agent/setup_agent.py` will succeed in creating
the agent with `A2APreviewTool(project_connection_id=connection.id)`.

### When to use the portal path instead

If your subscription's RBAC does not let you write `connections` on the
account (e.g., you only have Foundry data-plane access), the portal path
still works — but it requires a logged-in user with the same write
permission. Both paths require the same role: `Azure AI Administrator` or
`Cognitive Services Contributor` on the Foundry account.

---

## 4. TLS — optional for the demo

The plan originally assumed a TLS certificate matching `ops-agent.<DNS_ZONE>`
would be available and imported into Key Vault. For the **default demo
path documented above (sslip.io + HTTP)** this is unnecessary.

If you do want HTTPS in front of the AKS pod for a polished demo:

1. **Easiest:** issue a Let's Encrypt cert against the sslip.io hostname
   via cert-manager's HTTP-01 challenge. Add cert-manager to the cluster,
   create a `ClusterIssuer` for Let's Encrypt, and add the standard
   `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation to the
   ingress. The ingress's `tls:` section then references a Secret that
   cert-manager will create automatically. This works because sslip.io
   serves an A record for the hostname so HTTP-01 succeeds.

2. **Quickest (lab-only):** generate a self-signed cert with the sslip.io
   CN, import it into Key Vault under the name the ingress expects
   (`tls-cert-ops-agent`), and let App Routing pick it up. Foundry's A2A
   tool will fail TLS verification against a self-signed cert, so this
   only works if you stay on HTTP in the connection target.

3. **CA-issued:** purchase / re-use an existing wildcard cert from a public
   CA and import it as a PFX. Use `-CertificatePfxPath` when running
   `deploy-infra.ps1` to import it automatically.

For the customer demo where you want the URL bar to show `https://`, option
1 is the practical choice and adds about 5 minutes to setup.

---

## 5. Tenant policies & SKU availability — what to expect

These are the subscription-specific learnings from the deployment. Your
subscription may differ; if so, the scripts will surface a clear error and
you can adjust.

### 5.1 Key Vault `enablePurgeProtection` is mandatory in some tenants

The shipped `infra/modules/keyvault.bicep` now sets
`enablePurgeProtection: true`. Setting it to `false` (the original plan)
fails with:

```
KeyVaultPropertyConflict: The current value of property 'enablePurgeProtection'
is 'False'. Setting it to 'False' is not allowed.
```

**Implication for re-runs:** Key Vault names are reserved for **90 days
after delete** with purge protection on. If you run the demo a second time
and want the same KV name back, you cannot — pick a different
`-ResourcePrefix` or wait the 90 days. To recover faster:

```powershell
az keyvault purge --name <kvName> --location eastus2
```

(But this is **only available** if the soft-delete retention has not been
turned into a hard delete by the same purge protection — i.e., before the
90-day window expires you may have to wait.)

### 5.2 `Standard_D2s_v5` may not be available in your subscription

In some subscriptions (including the one this was validated against),
`Standard_D2s_v5` returns `NotAvailableForSubscription` in eastus2. Likewise,
`Standard_D2s_v6` (the Intel v6 SKU) is **also unavailable in eastus2** as
of 2026-05-21 — fresh AKS deploys reject it with an `allowed-SKUs` error.
The fix (committed): `infra/modules/aks.bicep` now defaults to
`Standard_D2as_v6` (the AMD v6 equivalent), which is broadly available
in eastus2. If neither is available in your subscription/region, override
with `-AksNodeSku` on both scripts.

### 5.3 gpt-5.5 quota is often 0 in lab subscriptions

Lab subscriptions (Tier 1–4) typically have 0 TPM quota for `gpt-5.5`.
The `verify-quota.ps1` script handles this gracefully — it detects the
condition and reports the **fallback path** as the recommended option.
When PRIMARY is unavailable, simply run:

```powershell
./scripts/deploy-infra.ps1 ... -UseGpt55:$false
```

Both deployments will then be `gpt-5.4-mini` and the demo is fully
functional (the orchestrator's deployment name remains `gpt-55-orchestrator`
to keep downstream scripts/env vars consistent, but the underlying model is
`gpt-5.4-mini` — verify with `az cognitiveservices account deployment list`).

### 5.4 Default TPM (capacity = 10) is too low for the demo

A single end-to-end demo run includes ~5–10 Code Interpreter executions,
1–2 A2A hops, and 100–200 tokens of streamed text — well above 10K TPM
in burst. After the first run you will hit `429 Too Many Requests` for
several minutes.

**Status as of 2026-05-21:** The default `capacity` in
`infra/modules/foundry-models.bicep` has been raised to **100** for both
deployments (orchestrator + worker), which gives ~100K TPM — enough
headroom for repeated demo runs without throttling. The previous
default of 10 caused mid-stream 429s after just one Code Interpreter
+ A2A loop. The demo subscription used for validation has 1000 TPM
quota for `gpt-5.4-mini` in eastus2, plenty of room.

If you do need to scale an existing deployment in place after a deploy:

```powershell
$sub = az account show --query id -o tsv
foreach ($d in @('gpt-55-orchestrator','gpt-54mini-worker')) {
  $resId = "/subscriptions/$sub/resourceGroups/rg-zava-a2a-smart-order-demo/providers/Microsoft.CognitiveServices/accounts/foundry-zava-a2a-smartorder/deployments/$d"
  az resource update --ids $resId --api-version 2026-03-01 --set "sku.capacity=200"
}
```

(`az resource update --set sku.capacity=N` patches the deployment in
place without re-creating it — no impact on agents or connections.)

### 5.5 AKS auto-stops when idle

AKS managed clusters in this subscription auto-stop after some idle time,
even on non-test pricing tiers. Symptoms: pods 0/0, kubectl times out
resolving the API server's DNS name, ingress IP doesn't respond. Verify
and recover:

```powershell
az aks show --resource-group rg-zava-a2a-smart-order-demo --name aks-zava-a2a-smart-order `
  --query 'powerState.code' -o tsv
# If "Stopped":
az aks start --resource-group rg-zava-a2a-smart-order-demo --name aks-zava-a2a-smart-order
# Wait ~3-5 minutes
kubectl rollout restart deployment/ops-agent -n default
kubectl rollout status deployment/ops-agent -n default --timeout=180s
```

Note: the **ReplicaSet may need a manual restart** after AKS resumes
because the workload-identity mutating webhook is not always ready when the
pod creation request fires.

---

## 6. Verifying everything works — single smoke test

After all the steps above, this single command exercises every link in
the chain:

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT       = '<your project endpoint>'
$env:FOUNDRY_AGENT_NAME             = 'zava-customer-service'
$env:FOUNDRY_ORCHESTRATOR_DEPLOYMENT = 'gpt-55-orchestrator'
Remove-Item Env:FOUNDRY_OPENAI_API_VERSION -ErrorAction SilentlyContinue
& apps\foundry-agent\.venv\Scripts\python.exe apps\foundry-agent\test_agent.py
```

Expected output (last few lines):

```
✓ Text output received (~700 chars)
✓ Code Interpreter chart artifact (1 file(s): ['embedded-sandbox-image'])
✓ A2A delegation (remote_function_call) (2 payload(s))
✓ Smoke test PASSED.
```

If any line shows `✗`, refer back to §2–§5 — every published GA gap has a
known fix.

### 6.1 Python 3.14 + azure-ai-projects incompatibility (host venv)

If your **host machine** has Python 3.14 installed (Python 3.14 was just
released), the `test_agent.py` smoke test will fail mid-stream with:

```
AttributeError: 'typing.Union' object has no attribute '__discriminator__'
```

This is an SDK / typing compatibility issue between `azure-ai-projects`
(2.1.x) and Python 3.14's stricter typing model. The Docker image used
by the AKS Ops Agent is pinned to `python:3.13-slim`, so the deployed
side is unaffected — only the host venvs are.

**Fix:** create the host venvs with Python 3.13 (not 3.14). With `uv`:

```powershell
uv python install 3.13
$py = uv python find 3.13
foreach ($app in @('apps\backend','apps\foundry-agent')) {
  Remove-Item -Recurse -Force "$app\.venv" -ErrorAction SilentlyContinue
  & $py -m venv "$app\.venv"
  & "$app\.venv\Scripts\python.exe" -m pip install -e $app --quiet
}
```

### 6.2 Windows console + Unicode in setup helpers

`apps/foundry-agent/{create_a2a_connection,setup_agent,test_agent}.py`
print ✓ / ✗ glyphs. Windows consoles using `cp1252` will crash with
`UnicodeEncodeError: 'charmap' codec can't encode character '\u2713'`.

**Fix:** the scripts now call `sys.stdout.reconfigure(encoding='utf-8')`
on startup (Python 3.7+), so no env-var workaround is needed. If you
fork or copy these scripts, keep that snippet.

---

## 7. Where the corrections live in the codebase

| Concern | File | What was changed |
| --- | --- | --- |
| `api-version` removal | `apps/backend/app/agent_client.py`, `apps/backend/app/config.py`, `apps/foundry-agent/test_agent.py` | Conditional `default_query` only when env var is set; default api version = `""` |
| `agent_reference` `type` field | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Added `type: "agent_reference"` |
| `agent_reference` `id` field for portal Traces tab | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Added `id: <agent>:<version>` via new `_resolve_agent_reference()` helper; required to attribute spans to the agent in the portal |
| `model` = bound deployment | `apps/backend/app/config.py`, `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | New `FOUNDRY_ORCHESTRATOR_DEPLOYMENT` env var |
| A2A event names | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Accept `a2a_preview_call*` AND `remote_function_call` |
| Sandbox chart detection | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Scan `message` content for `sandbox:` markdown |
| Natural-language parser | `apps/ops-agent/app/agent.py` | NL fallback patterns for SKU/qty/customer/date when orchestrator forwards free-form text |
| App Insights → Foundry account connection (Traces tab) | `infra/main.bicep`, `infra/modules/foundry-appinsights-connection.bicep` | New connection module + role assignment; required for Foundry portal Traces tab to populate |
| Key Vault purge protection | `infra/modules/keyvault.bicep` | `enablePurgeProtection: true` |
| AKS SKU | `infra/modules/aks.bicep`, `scripts/verify-quota.ps1` | `Standard_D2s_v6` default |
| `-NonInteractive` deploy switch | `scripts/deploy-infra.ps1` | Skip Read-Host in autopilot |
| Cert auto-detect | `scripts/deploy-infra.ps1` | Skip cert prompt if cert already present in KV |
| StrictMode pipeline fix | `scripts/deploy-k8s.ps1` | Wrap `Select-Object -Unique` in `@(...)` |
| Foundry account endpoint plumbing | `scripts/deploy-infra.ps1`, `scripts/deploy-k8s.ps1` | Reads `accountInferenceEndpoint`, threads through to pod env |

---

## 8. Foundry Agent Traces — wiring App Insights to Foundry account

**Date added: 2026-05-22.** When the Zava demo was first deployed, the
Foundry portal's **Agents → `zava-customer-service` → Traces** tab was
empty even though the agent was being invoked successfully. The root cause
was a missing wiring step: prompt agents auto-emit server-side traces, but
**Foundry only forwards those traces to App Insights once an explicit
account-level connection exists**. Two changes were required.

### 8.1 Infra: App Insights connection on the Foundry account

A new Bicep module ([`infra/modules/foundry-appinsights-connection.bicep`](../infra/modules/foundry-appinsights-connection.bicep))
declares the connection on the Foundry **account** (not the project) using
the verbatim shape from `microsoft-foundry/foundry-samples`:

```bicep
resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  name: '${foundryAccount.name}-appinsights'
  parent: foundryAccount
  properties: {
    category: 'AppInsights'   // exact casing — not 'ApplicationInsights'
    target: appInsightsResourceId
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: { key: appInsightsConnectionString }
    metadata: { ApiType: 'Azure', ResourceId: appInsightsResourceId }
  }
}
```

Notes:
- The connection lives at **account scope**, not project scope. There is
  one Foundry account per region/RG; child projects inherit the connection
  thanks to `isSharedToAll: true`.
- `credentials.key` is the **connection string**, not the instrumentation
  key. Confusing these silently breaks ingestion.
- `category` is `AppInsights` (one word, both caps). Other casings cause
  the deploy to succeed but no telemetry flows.
- The connection is idempotent. Redeploying with the same `name` and
  parameters is a no-op.

The main template also grants the deployer **Log Analytics Reader**
(`73c42c96-874c-492b-b04d-ab87d138a893`) on the App Insights component so
the operator can read the traces in the portal Traces tab and via KQL.

### 8.2 Code: pass `agent_reference.id` on every `responses.create()`

Server-side traces only get attributed to a specific agent when the
**agent ID** is passed in the request. Without it, spans are named
generically (`chat <model>`) and the portal Traces tab cannot filter by
agent. With it, spans are named `invoke_agent <agent-id>` and the Traces
tab populates correctly.

`apps/backend/app/agent_client.py` resolves the latest agent version once
per process (cached at module scope) and includes the ID on every request:

```python
def _resolve_agent_reference(project, agent_name):
    versions = project.agents.list_versions(
        agent_name=agent_name, order="desc", limit=1
    )
    latest = next(iter(versions), None)
    if latest is not None and getattr(latest, "id", None):
        return {"type": "agent_reference", "name": agent_name, "id": latest.id}
    return {"type": "agent_reference", "name": agent_name}  # graceful fallback
```

The resolver is wrapped in a threading.Lock-protected cache so it runs at
most once per agent name per process. If the version lookup fails for any
reason, the request still goes through with name only (degraded — no
agent-level Traces filtering, but the agent still runs).

### 8.3 Verify: KQL one-liner

After a chat request, wait 2-5 minutes for ingestion, then:

```kql
dependencies
| where timestamp > ago(30m)
| where customDimensions has 'gen_ai' or customDimensions has 'foundry'
| project timestamp, name, success,
         agent_id=tostring(customDimensions['gen_ai.agent.id']),
         span_type=tostring(customDimensions['span_type'])
| order by timestamp desc | take 15
```

Or from PowerShell:

```powershell
az monitor app-insights query `
  -g rg-zava-a2a-smart-order-demo `
  --app appi-zava-a2a-smart-order `
  --analytics-query "<the KQL above>" -o table
```

A working trace looks like:

```
2026-05-22T12:27:09.754261Z  invoke_agent zava-customer-service:1  False  zava-customer-service:1  agent
```

Span name starts with `invoke_agent`, `agent_id` matches the agent, and
`span_type=agent`. (Here `success=False` because the downstream A2A call
to a stopped AKS service failed — but the trace itself is intact.)

### 8.4 Gotchas

- **Ingestion lag.** Traces take 2-5 minutes to appear in the portal. If
  KQL returns nothing, wait longer before assuming the wiring is wrong.
- **Sampling.** App Insights default-samples at 5 req/s. For demos with
  bursty traffic, this is fine; for high-volume probes it can drop spans.
- **The connection's `target` is the full ARM resource ID**, not the
  instrumentation key and not the connection string. Easy to mix up.
- **AKS being stopped does not break traces.** The Foundry agent still
  runs, the span is still emitted, and the trace shows `success=False`
  with the A2A timeout as the cause. Useful for debugging downstream
  failures.

---

## 9. Clean-room redeploy procedure (avoiding soft-delete collisions)

**Date added: 2026-05-22.** When validating script changes or onboarding a
new environment, redeploying into the **same** resource group can collide
with soft-deleted artifacts from a prior tear-down:

- **Key Vault** — `enablePurgeProtection: true` (intentionally — see §7).
  Deleting the RG soft-deletes the vault; the name is reserved for **90
  days** and cannot be re-used until purge. Workaround: the vault name
  uses `uniqueString(resourceGroup().id)` so a different RG name yields a
  different vault name automatically.
- **Foundry account** (`Microsoft.CognitiveServices/accounts`) — has a
  **48-hour soft-delete window**. `infra/main.bicep` hardcodes the
  `foundryName` parameter to `foundry-zava-a2a-smartorder`, so
  redeploying into the same RG within 48 hours either silently restores
  the soft-deleted account (often what you want — connections come back)
  or fails the deploy if the soft-deleted shape differs. To force a
  fresh account, pass `-FoundryName <new-name>` to
  `scripts/deploy-infra.ps1` / `scripts/deploy-all.ps1`.
- **DNS zone** — Azure DNS has no soft-delete, but the zone name must be
  globally unique within the operator's tenant. RFC 2606 reserved names
  (`*.example.com`, `*.invalid`) are safe defaults for non-production.
- **ACR** — Same as Key Vault: the registry name uses `uniqueString(resourceGroup().id)`
  so a different RG automatically yields a different ACR name.

### Recommended clean-room procedure

```powershell
# 1. Tag current good state for rollback safety.
git tag last-known-good-pre-redeploy
git push origin last-known-good-pre-redeploy

# 2. Pick a fresh RG + Foundry account name.
$stamp = Get-Date -Format yyyyMMddHHmm
$rg = "rg-zava-a2a-validate-$stamp"
$fa = "foundry-zava-a2a-v$stamp"

# 3. One-command deploy to fresh RG.
./scripts/deploy-all.ps1 -ResourceGroupName $rg -FoundryName $fa

# 4. Validate the deploy worked: smoke test, KQL traces, manual demo.

# 5. Tear down the validation RG.
az group delete --name $rg --yes --no-wait

# 6. (Optional) Purge soft-deleted Foundry account to free the name.
az cognitiveservices account purge -n $fa -l eastus2 -g $rg
```

The original (working) demo RG stays untouched throughout, so a botched
validation never blocks the live demo.

---

## 10. Out-of-the-box single-command deploy (W1, W2, W3, W4 automation)

**Date added: 2026-05-22.** Sections 1, 3, and 7 above document the manual
workarounds that were applied to bring the demo live the first time. The
shipped scripts now perform all of those steps automatically. This section
documents the new flow.

### 10.1 The new entry point

```powershell
./scripts/deploy-all.ps1
```

On a fresh RG, this runs verify-quota → deploy-infra → build-and-push →
deploy-k8s (with sslip.io ingress + A2A connection PUT) → setup-foundry-agent
(`-SkipManualGates`) → smoke-test, with no prompts in between.

### 10.2 What each workaround was replaced with

| # | Workaround (historical) | Replacement |
|---|---|---|
| W1 | `kubectl patch ingress` to drop TLS and use sslip host (§1) | `scripts/deploy-k8s.ps1` second pass: re-renders [`apps/ops-agent/k8s/ingress.sslip.yaml`](../apps/ops-agent/k8s/ingress.sslip.yaml) with the real LB IP after polling the ingress |
| W2 | `kubectl set env OPS_AGENT_PUBLIC_URL` after LB IP is known (§1) | `scripts/deploy-k8s.ps1` runs `kubectl set env deployment/ops-agent OPS_AGENT_PUBLIC_URL=http://<sslip>/` and waits for the pod rollout |
| W3 | Manual `az rest PUT` to create the A2A connection on Foundry (§3) | [`scripts/create-a2a-connection.ps1`](../scripts/create-a2a-connection.ps1) — GET existing → compare target → PUT only if different. Idempotent. Called automatically by `deploy-k8s.ps1` when the four Foundry params are present |
| W4 | Manual `az cognitiveservices account deployment update --capacity 200` | `infra/modules/foundry-models.bicep` now defaults capacity to 200 for gpt-5.4-mini (orchestrator + worker). Primary-path gpt-5.5 stays at 50 due to Tier 5 quota |
| W5 | (Already automated, see §8) Foundry account → App Insights connection | `infra/modules/foundry-appinsights-connection.bicep` deployed by `main.bicep` |

### 10.3 Mode choice (sslip.io vs DnsZone)

`deploy-all.ps1` defaults to `-UseSslipIo:$true`. The sslip.io path is the
recommended demo path because:
- No real DNS zone, no NS-record delegation, no TLS certificate workflow.
- The bicep still provisions an Azure DNS zone resource (it is essentially
  free at rest, and making it conditional in bicep would complicate the
  template significantly for negligible benefit).

To deploy with a real DNS zone + TLS:

```powershell
./scripts/deploy-all.ps1 -UseSslipIo:$false -DnsZoneName <your-zone>
```

The TLS cert workflow (cert into Key Vault under `tls-cert-ops-agent`)
still applies in that path; see §4.

### 10.4 What's deliberately *not* automated

- **`az login`** — the deployer must be signed in before running anything.
- **Cost confirmation** — `deploy-all.ps1` passes `-NonInteractive` to
  skip the cost-confirmation prompt. This is appropriate for repeat
  deploys where the deployer already understands the cost.
- **Tear-down** — destructive, deployer-discretion. The script does not
  delete anything.
- **Soft-delete purge** — see §9 for the procedure.

### 10.5 Files added / changed by the automation push

| File | Purpose |
|---|---|
| `scripts/deploy-all.ps1` | New orchestrator — chains all five scripts |
| `scripts/create-a2a-connection.ps1` | New helper — ARM PUT for A2A connection (replaces W3) |
| `scripts/deploy-k8s.ps1` | `-UseSslipIo` mode + 2-pass ingress + env override + A2A call (replaces W1, W2) |
| `scripts/deploy-infra.ps1` | `-SkipCertProvisioning` switch + optional `-DnsZoneName` + `-FoundryName` override |
| `scripts/setup-foundry-agent.ps1` | Doc-only: notes Phase 1/4 are now upstream-automated |
| `scripts/smoke-test.ps1` | `-OpsAgentEndpoint` parameter (accept full URL) |
| `infra/modules/foundry-models.bicep` | Capacity 100 → 200 for gpt-5.4-mini (replaces W4) |
| `apps/ops-agent/k8s/ingress.sslip.yaml` | New sslip-mode ingress template (no TLS, `${SSLIP_HOST}` placeholder) |
| `apps/ops-agent/k8s/deployment.yaml` | Replaced hardcoded URL with `${OPS_AGENT_PUBLIC_URL}` placeholder |

---

## 11. Azure CLI `az acr build` Unicode crash on Windows — `--no-logs` fix

**Date added: 2026-05-22.** Discovered during clean-room validation of
`deploy-all.ps1` in §12.

### 11.1 The symptom

`az acr build` on Windows (az CLI 2.83.0 from MSI installer) crashes with:

```
UnicodeEncodeError: 'charmap' codec can't encode characters in position …
```

…while streaming ACR build logs. The crash happens because pip's progress
bars include U+2501 box-drawing characters, the Azure CLI bundles its own
Python 3.x interpreter, and that bundled Python defaults to `cp1252`
stdout on Windows.

### 11.2 Why the usual environment fixes don't work

All of the following were tried and did **not** prevent the crash:

- `$env:PYTHONUTF8 = '1'`
- `$env:PYTHONIOENCODING = 'utf-8'`
- `[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)`
- `chcp 65001`
- `$env:NO_COLOR = '1'`
- `Start-Process … -RedirectStandardOutput`

The bundled Python is launched via `D:\a\_work\1\s\build_scripts\windows\artifacts\cli\Lib\…`
and **ignores** the environment variables on this code path. The
crash is in colorama's write to stdout, which happens before any of
the env vars take effect.

### 11.3 The fix

`az acr build` has a `--no-logs` flag that queues the build, waits for
it to complete, and **does not stream** the offending build logs.
[`scripts/build-and-push.ps1`](../scripts/build-and-push.ps1) now uses
`--no-logs` by default. The build still succeeds; only the live log
streaming is suppressed.

If a build fails, retrieve the logs with:

```powershell
az acr task logs --registry <acrName> --run-id <runId>
```

The run ID is printed by `az acr build` itself.

---

## 12. Single-command deploy validation (clean-room run 2026-05-22)

**Date added: 2026-05-22.** `deploy-all.ps1` was validated against a fresh
RG (`rg-zava-a2a-validate-202605220835`) to confirm the "out-of-the-box"
flow. This section captures the residual issues found during validation
and how they were resolved in code (not workarounds — fixes).

### 12.1 Deployer needs `Foundry User` (data plane), not just `Foundry Account Owner`

**Symptom.** After a clean bicep deploy, `python create_a2a_connection.py
--verify` reported `Connection 'ops-agent-a2a' NOT FOUND or inaccessible`,
and a direct data-plane query against the Foundry endpoint returned
`PermissionDenied — Principal does not have access to API/Operation`
with the missing data action
`Microsoft.CognitiveServices/accounts/AIServices/agents/read`.

**Root cause.** The bicep granted the deployer **Foundry Account Owner**
(control-plane CRUD on the account/projects) but **not** the **Foundry
User** role, which carries the `Microsoft.CognitiveServices/*` data
action. The Foundry SDK / portal Agents UI all use the data plane.

**Fix.** `infra/main.bicep` now grants both roles to `deployerPrincipalId`
at the Foundry account scope:

- `e47c6f54-e4a2-4754-9501-8e0985b135e1` — **Foundry Account Owner**
  (control plane)
- `53ca6127-db72-4b80-b1b0-d745d6d5456d` — **Foundry User** (data
  plane — required for SDK calls and portal Agents UI)

Note: Azure RBAC data-plane changes can take **up to ~30 min** to
propagate. If you see `PermissionDenied` immediately after a fresh
deploy, wait and retry.

### 12.2 Python 3.14 breaks the Foundry SDK — use the foundry-agent venv

**Symptom.** Phase 3 of `setup-foundry-agent.ps1` (the `test_agent.py`
streaming smoke test) crashed with:

```
AttributeError: 'typing.Union' object has no attribute '__discriminator__'
```

**Root cause.** `azure-ai-agents` uses pydantic discriminated-union models
that fail on Python 3.14. The repo's `apps/foundry-agent/pyproject.toml`
pins `requires-python = ">=3.13"` and the `.venv` was created with
Python 3.13, but `setup-foundry-agent.ps1` was calling `python` (the
system interpreter) instead of the venv.

**Fix.** `scripts/setup-foundry-agent.ps1`'s `Invoke-Python` now prefers
`apps/foundry-agent/.venv/Scripts/python.exe` (Windows) /
`apps/foundry-agent/.venv/bin/python` (Linux/macOS) when present, and
falls back to system `python` otherwise. `scripts/deploy-all.ps1` now
also auto-bootstraps the venv (via `uv sync` if `uv` is installed, else
`python -m venv .venv` + `pip install -e .`) before invoking
setup-foundry-agent.

### 12.3 KQL trace-verification diagnostic needs the App Insights RG

**Symptom.** Phase 5 of `setup-foundry-agent.ps1` (the trace-propagation
KQL probe) failed with:

```
The Application Insight is not found. Please check the app id again.
```

**Root cause.** `az monitor app-insights query --apps <name>` requires
either a matching RG context or the appId GUID. The deployer's active
`az` context may not align with the App Insights resource group when
deploying to a custom RG name.

**Fix.** `scripts/setup-foundry-agent.ps1` now accepts an optional
`-AppInsightsResourceGroup` parameter, falls back to
`az resource list --resource-type Microsoft.Insights/components` to
discover the RG, then resolves the appId GUID via `component show`
and uses the GUID for the KQL query. `deploy-all.ps1` passes the RG
through automatically.

### 12.4 `deploy-all.ps1` should not abort on a Phase-5 KQL hiccup

**Symptom.** When the KQL probe in setup-foundry-agent's Phase 5
returned an error (most often because traces had not yet propagated
into App Insights, which can take 5–10 min), the script's exit code
was non-zero. `deploy-all.ps1` had a `try/catch` around the call but
`Invoke-StepOrFail` used `exit 1` internally, which bypassed the
catch and killed the orchestrator — even though the agent, connection,
and demo plumbing had all been provisioned correctly.

**Fix.** `Invoke-StepOrFail` now takes a `-ContinueOnFailure` switch.
When set, it returns `$true`/`$false` instead of calling `exit`.
`deploy-all.ps1` Step 4 passes the switch so a transient
trace-verification miss doesn't abort the whole orchestrator.

### 12.5 MCAPS subscription quirks (eastus2)

These are subscription-policy issues, not codebase bugs, but the bicep
now defaults to values that work on MCAPS:

| Quirk | Default fix |
|---|---|
| `gpt-5.5` quota = 0 in MCAPS — `Bicep: InsufficientQuota` on the orchestrator deployment | Set `-UseGpt55:$false`; both agents use `gpt-5.4-mini` (the fallback path is already in `foundry-models.bicep`) |
| `Standard_D2as_v6` not allowed — `The VM size of Standard_D2as_v6 is not allowed in your subscription in location 'eastus2'` from AKS | `infra/modules/aks.bicep` now defaults to `Standard_D2as_v5` and `scripts/verify-quota.ps1` matches |
| `az vm list-skus` says `D2as_v5` is `NotAvailableForSubscription` | False positive — AKS preflight allows `D2as_v5` and the deploy succeeds. `verify-quota.ps1` treats this as a warning, not a failure |




