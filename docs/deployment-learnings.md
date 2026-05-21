# Deployment Learnings — Phase 6 Live Deployment Notes

> **Status:** The Zava A2A demo has been deployed end-to-end against a real
> Azure subscription and a complete Foundry V2 → A2A → LangGraph-on-AKS →
> Code-Interpreter-chart flow has been verified working. This document
> captures the workarounds and corrections that were applied to the
> as-shipped scripts and code while bringing the demo up live. All of these
> corrections are committed to the repository — this doc explains *why* they
> exist so future operators do not get tripped up by the same gaps.

Last updated: 2026-05-21

---

## 1. Quick demo path — no DNS delegation required

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
`Standard_D2s_v5` returns `NotAvailableForSubscription` in eastus2. The
fix (committed): `infra/modules/aks.bicep` and `scripts/verify-quota.ps1`
now default to `Standard_D2s_v6`. If neither is available in your
subscription/region, override with `-AksNodeSku` on both scripts.

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

**Recommended:** scale both deployments to **capacity = 50** (50K TPM)
immediately after `deploy-infra.ps1` finishes. The demo subscription used
for validation has 1000 TPM quota for `gpt-5.4-mini` in eastus2, plenty
of room.

```powershell
$ver = az cognitiveservices account deployment show `
  --resource-group rg-zava-a2a-smart-order-demo --name foundry-zava-a2a-smartorder `
  --deployment-name gpt-55-orchestrator --query 'properties.model.version' -o tsv

foreach ($d in @('gpt-55-orchestrator','gpt-54mini-worker')) {
  az cognitiveservices account deployment create `
    --resource-group rg-zava-a2a-smart-order-demo --name foundry-zava-a2a-smartorder `
    --deployment-name $d `
    --model-name gpt-5.4-mini --model-version $ver --model-format OpenAI `
    --sku-capacity 50 --sku-name GlobalStandard
}
```

(`deployment create` with an existing name is idempotent and effectively
scales in place.)

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

---

## 7. Where the corrections live in the codebase

| Concern | File | What was changed |
| --- | --- | --- |
| `api-version` removal | `apps/backend/app/agent_client.py`, `apps/backend/app/config.py`, `apps/foundry-agent/test_agent.py` | Conditional `default_query` only when env var is set; default api version = `""` |
| `agent_reference` `type` field | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Added `type: "agent_reference"` |
| `model` = bound deployment | `apps/backend/app/config.py`, `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | New `FOUNDRY_ORCHESTRATOR_DEPLOYMENT` env var |
| A2A event names | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Accept `a2a_preview_call*` AND `remote_function_call` |
| Sandbox chart detection | `apps/backend/app/agent_client.py`, `apps/foundry-agent/test_agent.py` | Scan `message` content for `sandbox:` markdown |
| Natural-language parser | `apps/ops-agent/app/agent.py` | NL fallback patterns for SKU/qty/customer/date when orchestrator forwards free-form text |
| Key Vault purge protection | `infra/modules/keyvault.bicep` | `enablePurgeProtection: true` |
| AKS SKU | `infra/modules/aks.bicep`, `scripts/verify-quota.ps1` | `Standard_D2s_v6` default |
| `-NonInteractive` deploy switch | `scripts/deploy-infra.ps1` | Skip Read-Host in autopilot |
| Cert auto-detect | `scripts/deploy-infra.ps1` | Skip cert prompt if cert already present in KV |
| StrictMode pipeline fix | `scripts/deploy-k8s.ps1` | Wrap `Select-Object -Unique` in `@(...)` |
| Foundry account endpoint plumbing | `scripts/deploy-infra.ps1`, `scripts/deploy-k8s.ps1` | Reads `accountInferenceEndpoint`, threads through to pod env |
