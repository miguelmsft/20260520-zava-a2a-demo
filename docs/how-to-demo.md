# How to Run the Zava Smart Order Feasibility Demo

> Step-by-step demo script for presenters and customers cloning this repo.

---

## 1. Overview

This demo shows two AI agents collaborating over the open **A2A (Agent-to-Agent)** protocol to answer a single business question: *“Can Zava — a fictional precision-components manufacturer — fulfill this pump order by the target date?”*

- **Agent A — Customer Service Agent** runs on **Microsoft Foundry V2**. It is user-facing, parses the request, delegates the heavy lifting, and renders a chart with Code Interpreter.
- **Agent B — Manufacturing Ops Agent** runs on **AKS** as a **LangGraph** application. It reads fake inventory, production-schedule, order-book, and customer-tier data and computes a structured feasibility verdict.
- A local **React** front-end visualises every A2A hop, every tool call, and the final chart + customer-friendly answer.

**Time budget**

| Activity | Typical time |
| --- | --- |
| One-time setup (sections 4.1 – 4.6) | ~30 minutes |
| Starting the local apps (section 5) | ~2 minutes |
| Running the demo end-to-end (section 6) | ~5 minutes per run |
| Cleanup (section 8) | ~1 minute to start, ~10 minutes for Azure to finish |

For the use-case narrative, see [`docs/use-case.md`](./use-case.md). For the deployed architecture, see [`docs/architecture.md`](./architecture.md). For implementation details, see [`docs/technology.md`](./technology.md).

> **⚡ If you just want the demo to run** — and you do not own a DNS zone or have a TLS certificate — read [`docs/deployment-learnings.md`](./deployment-learnings.md) first. It documents the validated as-deployed path (sslip.io DNS + HTTP-only A2A target + ARM REST connection creation) and adds about 5 minutes total versus the full DNS/TLS path described below.

---

## 2. Prerequisites

### 2.1 Azure subscription

- An Azure subscription where you are **Owner**, or **Contributor + User Access Administrator**. Role assignments for the user-assigned managed identity (UAMI) and AKS workload identity require `Microsoft.Authorization/roleAssignments/write`, which Contributor alone does not grant.
- A **subscription tier that has `gpt-5.5` quota in your chosen region** (typically Tier 5) if you want the primary path. **Tier 1–4** subscriptions will be detected by `scripts/verify-quota.ps1` and the deployment will transparently fall back to `gpt-5.4-mini` for **both** the orchestrator and the ops-agent reasoning model. Both paths are fully demo-worthy; the primary path is only marginally smoother for free-form chat.

### 2.2 DNS — gating (see `plan.md` §F.1 Q1)

You **must** own a DNS zone where you can delegate a subdomain by adding NS records at your registrar. For example, if you own `example.com` you might delegate `zava.example.com` to Azure DNS. **Without DNS delegation the public HTTPS endpoint for the Ops Agent cannot be issued, the Foundry A2A connection cannot reach it, and the demo cannot run.** Plan to add NS records at your registrar partway through section 4.3.

### 2.3 TLS certificate — gating (see `plan.md` §F.1 Q2)

You **must** have a TLS certificate whose **CN or SAN matches `ops-agent.<your-domain>`** (for example `ops-agent.zava.example.com`). Acceptable forms:

1. A **PFX file** plus its password (recommended — the deploy script imports it into Key Vault automatically).
2. An existing **Key Vault certificate** you’ll reference by name.
3. **Azure Front Door / App Gateway managed cert** (more setup; out of scope for this script).

If you don’t already have one, you can mint a free 90-day cert from Let’s Encrypt against your delegated subdomain after section 4.3 and re-run section 4.3 with `-CertificatePfxPath`. The PFX path is the simplest option.

### 2.4 Local tools

Run these checks before starting. All commands must succeed.

```powershell
az --version            # Azure CLI 2.60 or newer
pwsh --version          # PowerShell 7.0 or newer
kubectl version --client # kubectl 1.30 or newer
python --version        # Python 3.13.x
node --version          # Node 22.x
npm --version           # npm 10.x (ships with Node 22)
```

Optional / situational:

- **Docker Desktop** — only required if you want to build the Ops Agent container image locally. The recommended path uses `az acr build` (cloud build), so **Docker is optional**.
- **OpenSSL** — used by `scripts/deploy-k8s.ps1` to generate the pre-shared API key. Windows users without OpenSSL can use the PowerShell `[System.Web.Security.Membership]::GeneratePassword` fallback that `deploy-k8s.ps1` falls back to automatically.

---

## 3. Cost estimate

Approximately **$15 – $25 per day** while the environment is deployed. The dominant line items are AKS (system + user node pool), the Foundry account, and Azure Monitor / App Insights ingestion. Idle GPT consumption is near-zero; per-demo-run token cost is well under $0.05.

**Cleanup at the end is mandatory** (section 8). A forgotten environment will accrue tens of dollars per day silently.

```powershell
az group delete --name rg-zava-a2a-smart-order-demo --yes --no-wait
```

See [`docs/architecture.md`](./architecture.md) (“Cost model” section) for the full per-component breakdown and for guidance on the hardened / private-VNet variant covered in [`docs/private-vnet-considerations.md`](./private-vnet-considerations.md).

---

## 4. One-time setup (~30 minutes)

> Everything in this section is done **once per environment**. After you finish 4.6, you do not need to re-run it unless you tear down the resource group.

> **⚡ Want the fastest path?** If you do not own a DNS zone and just want the demo to work end-to-end, skip sections 4.3 – 4.5 and use the single-command flow:
>
> ```powershell
> az login
> az account set --subscription "<subscription-id>"
> ./scripts/deploy-all.ps1                      # uses sslip.io — no DNS / TLS work needed
> ```
>
> `deploy-all.ps1` chains verify-quota → deploy-infra → build-and-push → deploy-k8s (sslip.io ingress, no TLS) → setup-foundry-agent → smoke-test, in roughly 30 – 45 minutes, with no manual gates between steps. Once it returns green, jump straight to **section 5** to start the local UI. The granular sections below are kept for the DNS+TLS path and for operators who want to understand each step.

### 4.1 Clone and authenticate

```powershell
git clone https://github.com/miguelmsft/20260520-zava-a2a-demo.git
cd 20260520-zava-a2a-demo
az login
az account set --subscription "<subscription-id>"
```

Confirm the right subscription is active:

```powershell
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
```

### 4.2 Verify quota

```powershell
./scripts/verify-quota.ps1 -Location eastus2
```

Interpret the output:

- `PRIMARY: OK` — your subscription has `gpt-5.5` quota in `eastus2`. Use the default (primary) path.
- `PRIMARY: FAIL` and `FALLBACK: OK` — pass `-UseGpt55:$false` to `./scripts/deploy-infra.ps1` in step 4.3 so both deployments use `gpt-5.4-mini`. The demo will look and behave essentially the same.
- `PRIMARY: FAIL` and `FALLBACK: FAIL` — you have neither model. Either change region (re-run with `-Location westus3`), request quota in the portal, or use a different subscription.

### 4.3 Deploy infrastructure (Bicep)

```powershell
$pfxPwd = Read-Host -AsSecureString -Prompt "PFX password"
./scripts/deploy-infra.ps1 `
  -ResourceGroupName rg-zava-a2a-smart-order-demo `
  -Location eastus2 `
  -DnsZoneName zava-a2a-smart-order.example.com `
  -CertificatePfxPath ./tls-cert.pfx `
  -CertificatePfxPassword $pfxPwd
```

What happens:

1. The script prints the estimated cost and **pauses for a confirmation**. Type `y` to continue.
2. Bicep provisions: Foundry account + project, two model deployments, AKS cluster with App Routing add-on, ACR, Key Vault, Log Analytics + App Insights, public DNS zone, UAMI, role assignments.
3. The Bicep output `dnsZoneNameServers` is printed. **Copy these four NS records to your domain registrar** (e.g., in your `example.com` parent zone, add an NS record for `zava` pointing at the four Azure name servers). Wait for propagation — usually 1–5 minutes; verify with `Resolve-DnsName -Name zava.example.com -Type NS`. The demo cannot work until DNS delegation is live.
4. The script imports your PFX into Key Vault as a Key Vault certificate. If you don’t have a PFX, re-run the script with `-CertificateKeyVaultName` and `-CertificateName` to reference an existing KV cert, or follow the three manual options documented in the script header.
5. Final output lists every value you’ll need downstream: **`acrLoginServer`**, **`keyVaultName`**, **`uamiClientId`**, **`foundryProjectEndpoint`**, **`workerDeploymentName`**, **`appInsightsName`**, **`opsAgentUrl`**, **`orchestratorDeploymentName`**.

**Capture these outputs into a scratch file.** Every subsequent script consumes one or more of them.

### 4.4 Build and push the Ops Agent container image

```powershell
./scripts/build-and-push.ps1 -AcrLoginServer "<acrLoginServer from 4.3>"
```

This runs `az acr build` against the Dockerfile in `apps/ops-agent/`. No local Docker needed. The image is tagged `ops-agent:latest` (and the commit SHA).

### 4.5 Deploy the Ops Agent to AKS

```powershell
./scripts/deploy-k8s.ps1 `
  -AcrLoginServer "<acrLoginServer from 4.3>" `
  -KvName "<keyVaultName from 4.3>" `
  -DnsZone zava.example.com `
  -UamiClientId "<uamiClientId from 4.3>" `
  -FoundryEndpoint "<foundryProjectEndpoint from 4.3>" `
  -WorkerDeploymentName "<workerDeploymentName from 4.3>"
```

What happens:

1. The script generates a 32-byte random pre-shared API key (the `x-api-key` value the Foundry A2A connection will send).
2. It stores the key in the `ops-agent-secrets` Kubernetes secret.
3. It applies the Deployment, Service, Ingress, and ServiceAccount (federated to the UAMI via workload identity).
4. App Routing provisions a public HTTPS endpoint at `https://ops-agent.zava.example.com/` using your imported TLS certificate.
5. The script polls `kubectl get ingress` until the `ADDRESS` field is populated, then curls `/.well-known/agent-card.json` to confirm the agent is live.
6. The script **prints the API key**. Copy it — you’ll paste it into the Foundry portal in 4.6. You can also retrieve it later with:

```powershell
kubectl get secret ops-agent-secrets -o jsonpath='{.data.A2A_API_KEY}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

### 4.6 Provision the Foundry agent + A2A connection

```powershell
./scripts/setup-foundry-agent.ps1 `
  -FoundryEndpoint "<foundryProjectEndpoint from 4.3>" `
  -OpsAgentEndpoint "https://ops-agent.zava.example.com/" `
  -OpsAgentApiKey "<apiKey from 4.5>" `
  -AppInsightsName "<appInsightsName from 4.3>"
```

What this orchestrates:

1. Runs `apps/foundry-agent/setup_agent.py` which creates the `zava-customer-service` prompt agent in your Foundry project, binds the orchestrator model deployment, attaches the Code Interpreter tool, and registers the `A2APreviewTool` referencing the connection you’re about to create.
2. Runs `apps/foundry-agent/create_a2a_connection.py` which prints **9 manual portal steps** you must perform to create the A2A connection (Foundry V2 currently requires this connection to be created in the portal — see [`docs/a2a-implementation.md`](./a2a-implementation.md#a2a-connection-setup)):
   - Open the Foundry portal → your project → **Connected resources** → **+ New connection** → **A2A (Preview)**.
   - **Connection name:** `ops-agent-a2a`.
   - **Endpoint URL:** `https://ops-agent.zava.example.com/` (trailing slash required).
   - **Auth header name:** `x-api-key`.
   - **Auth header value:** paste the API key from 4.5.
   - Save. Note the connection ID printed in the portal URL.
3. Re-run with `--verify` (the script does this automatically) to confirm the connection resolves and the Agent Card is fetched successfully.
4. Performs the App Insights linkage: portal → Foundry project → **Connected resources** → add your App Insights resource → toggle **Tracing** **ON**.
5. Runs `apps/foundry-agent/test_agent.py` which submits one end-to-end probe and checks for the R16 dual-part artifact and the A2A hop in the trace.
6. **KQL fallback**: if tracing in the portal hasn’t propagated yet (it can take 5–10 minutes), the script runs a KQL query against the App Insights workspace and prints the row count. A non-zero count confirms traces are flowing.

For the security model behind the `x-api-key` mitigation (R17), see [`docs/a2a-implementation.md`](./a2a-implementation.md#auth-and-r17-mitigation).

---

## 5. Start the local apps (~2 minutes — every time you demo)

### 5.1 Backend

The backend uses `uv` for dependency management (a `pyproject.toml` + `uv.lock`, no `requirements.txt`).

```powershell
cd apps/backend
uv sync                                # creates .venv/ and installs deps (first run only)
$env:FOUNDRY_PROJECT_ENDPOINT = "<foundryProjectEndpoint from 4.3>"
$env:FOUNDRY_AGENT_NAME = "zava-customer-service"
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

If you don't have `uv`, install it once via `pip install uv` (or `winget install astral-sh.uv`). Alternatively, you can use the venv directly:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Verify in another terminal:

```powershell
curl http://localhost:8000/api/health
```

Expect: `{"status":"ok","agent_name":"zava-customer-service"}`.

The backend uses `DefaultAzureCredential`, so make sure you’re still logged in (`az account show`). If you switched tenants since 4.1, re-run `az login`.

### 5.2 Frontend (separate terminal)

```powershell
cd apps/frontend
npm install
npm run dev
```

Open the printed URL — typically `http://localhost:5173`. The Vite dev server proxies `/api/*` to `http://localhost:8000`, so CORS should not be an issue.

---

## 6. Run the demo (~5 minutes per run)

### 6.1 Fill the feasibility form

In the browser at `http://localhost:5173`:

| Field | Value |
| --- | --- |
| SKU | `ZP-7000` (Centrifugal Pump 750 L/min) |
| Quantity | `150` |
| Target date | `2026-07-15` |
| Customer | `CUST-001` (Apex Hydraulics — Platinum tier) |

Click **Check Feasibility**. The right-hand pane will start streaming the A2A timeline within a second.

### 6.2 Watch the timeline (talking points)

Read these out loud as the corresponding rows appear in the timeline:

- *“The user just submitted a feasibility check. The orchestrator agent on Foundry V2 is now receiving the request.”*
- *“Notice the A2A delegation: the orchestrator just sent a structured JSON-RPC request over the open A2A protocol to the Ops Agent running on AKS.”*
- *“The Ops Agent — a LangGraph application — is now looking up inventory, production schedule, the order book, and the customer profile in parallel.”*
- *“It’s running the feasibility computation locally, then sending the structured result back over A2A as both a `DataPart` and a `TextPart` artifact — that dual-part shape is what lets the orchestrator parse the result programmatically while still having a human-readable fallback.”*
- *“The orchestrator parses the `DataPart` and uses **Code Interpreter** to generate a visual chart from the production-window data.”*
- *“Finally, the customer-friendly response — with the chart inline — streams back to the browser.”*

### 6.3 Inspect the Foundry control plane (talking points)

While the page still shows the response, open the Azure portal in a second tab:

- Navigate: **Foundry resource → Projects → Tracing**.
- *“Here’s the trace for the request you just saw. You can see the orchestrator decision, the A2A tool call, the Ops Agent response, the Code Interpreter call, and the final synthesis — all linked under a single root span.”*
- *“The same data is queryable in App Insights for advanced filtering and dashboards. The portal Tracing view is the friendly path; KQL is the power-user path.”*
- *“For the full identity model — UAMI for AKS, workload identity for the pod, RBAC for the Foundry data plane — see `docs/architecture.md`.”*

Reference: [`docs/architecture.md`](./architecture.md) for the deployed component diagram and identity flow, and [`docs/a2a-implementation.md`](./a2a-implementation.md) for the request/response wire format.

---

## 7. Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `verify-quota.ps1` reports `PRIMARY: FAIL` and `FALLBACK: FAIL` | gpt-5.5 quota at Tier 1–4 is 0, and gpt-5.4-mini quota also exhausted in this region | Re-run with `-Location westus3`, request quota in the portal, or use another subscription. If only PRIMARY fails, pass `-UseGpt55:$false` to `deploy-infra.ps1`. |
| `deploy-infra.ps1` finishes but `Resolve-DnsName zava.example.com` returns `SERVFAIL` | NS records not yet added at the parent registrar, or propagation incomplete | Copy the four name servers from the Bicep `dnsZoneNameServers` output to your registrar; wait 1–5 minutes; re-test. |
| `deploy-k8s.ps1` polling loop times out with empty ingress address | TLS certificate not imported into Key Vault, or App Routing identity lacks Key Vault Secrets User on the cert | Run `kubectl describe ingress ops-agent` and look for cert-related events; verify the role assignments documented in `plan.md` §C Step 7; re-run 4.3 with `-CertificatePfxPath` if the cert is missing. |
| Foundry portal A2A connection won’t save (“connection test failed”) | API key paste error, missing trailing slash on the endpoint URL, or DNS not yet propagated | Re-fetch the key with the `kubectl get secret` command in section 4.5 step 6; confirm the URL is exactly `https://ops-agent.<your-domain>/`; confirm `curl https://ops-agent.<your-domain>/.well-known/agent-card.json` returns 200 from your laptop. |
| `test_agent.py` prints `A2A hop missing` | `A2APreviewTool` not bound to the agent, or wrong `connection_id` | Re-run `setup_agent.py`; then `create_a2a_connection.py --verify` to confirm the connection resolves and the tool is bound. |
| `test_agent.py` prints `R16: opaque string` | The Ops Agent emitted only a `TextPart` (no `DataPart`), so the orchestrator can’t parse the result | Inspect `apps/ops-agent/app/executor.py` artifact emission — every response must include **both** a `DataPart` (structured JSON) and a `TextPart` (human-readable). See [`docs/a2a-implementation.md`](./a2a-implementation.md#r16-dual-part-artifact-pattern). |
| KQL fallback returns 0 rows after 10 minutes | App Insights → Foundry linkage broken, or wrong workspace targeted | In the Foundry portal, re-do **Connected resources → App Insights**; confirm the resource ID matches `appInsightsName` from 4.3; toggle **Tracing OFF/ON**. |
| Backend `/api/chat` returns 401 or 404 | `FOUNDRY_AGENT_NAME` env var doesn’t match the agent reference name set in `setup_agent.py`, or `DefaultAzureCredential` picked the wrong tenant | Confirm `$env:FOUNDRY_AGENT_NAME -eq "zava-customer-service"`; run `az account show` and re-`az login` if the tenant is wrong. |
| Frontend shows CORS error in dev tools | Backend not running on port 8000, or Vite proxy mis-pointed | Confirm `uvicorn` is listening on 8000 (section 5.1); restart `npm run dev` to reload the Vite proxy config. |
| `BadRequestError: api-version query parameter is not allowed when using /v1 path` | Foundry V2 GA rejects this param on `/openai/v1/...` | Unset `FOUNDRY_OPENAI_API_VERSION` in your env. The shipped code defaults to empty; see [`docs/deployment-learnings.md`](./deployment-learnings.md) §2.1. |
| `invalid_payload: Model must match the agent's model 'gpt-55-orchestrator'` | `responses.create(model=...)` was passed the agent name instead of the bound deployment | Set `FOUNDRY_ORCHESTRATOR_DEPLOYMENT=gpt-55-orchestrator` (or whatever the deployment is called). See [`docs/deployment-learnings.md`](./deployment-learnings.md) §2.3. |
| `invalid_payload: required: Required properties ["type"] are not present` on `/agent_reference` | GA requires `type: "agent_reference"` alongside `name` | Update your call site; the shipped backend and `test_agent.py` already include it. |
| AKS health probes/ingress unreachable after a day idle | AKS auto-stopped | `az aks start --name aks-zava-a2a-smart-order --resource-group rg-zava-a2a-smart-order-demo` then `kubectl rollout restart deployment/ops-agent`. See [`docs/deployment-learnings.md`](./deployment-learnings.md) §5.5. |
| `az aks start` returns `SkuNotAvailable: Standard_D2as_v6` and the node pool is in Failed state | Azure has a transient capacity restriction on `D2as_v6` in your region (commonly seen in MCAPS subscriptions in `eastus2`) | Don't tear down the cluster. Add a new system pool on a different SKU and delete the failed one — the ingress IP is preserved: `az aks nodepool add -g rg-zava-a2a-smart-order-demo --cluster-name aks-zava-a2a-smart-order --name sysv5 --node-count 2 --node-vm-size Standard_D2as_v5 --mode System` then `az aks nodepool delete -g rg-zava-a2a-smart-order-demo --cluster-name aks-zava-a2a-smart-order --name system`. The shipped Bicep already defaults to `Standard_D2as_v5` so future clean deploys avoid this. |
| `429 Too Many Requests` during a second demo run | Default 10K TPM is too low for repeated runs | Scale both deployments to capacity 50 via `az cognitiveservices account deployment create --sku-capacity 50` (idempotent upsert). See [`docs/deployment-learnings.md`](./deployment-learnings.md) §5.4. |
| `AttributeError: 'ConnectionsOperations' object has no attribute 'create'` | Data-plane SDK gap; `connections.create` does not exist | Use ARM REST PUT instead — `create_a2a_connection.py` now does this automatically. See [`docs/deployment-learnings.md`](./deployment-learnings.md) §3. |

---

## 8. Cleanup (mandatory)

When you’re finished — even if “just for the day” — tear down the Azure resources:

```powershell
az group delete --name rg-zava-a2a-smart-order-demo --yes --no-wait
```

This removes AKS, the Foundry account and project (including the agent and A2A connection), ACR, Key Vault (soft-deleted; purge separately if you want the name back immediately), DNS zone, Log Analytics, App Insights, and all role assignments scoped to the group.

Also:

- **Stop local processes:** press `Ctrl+C` in the `uvicorn` terminal and the `npm run dev` terminal.
- **Optional — delete the NS records** at your parent registrar so they no longer point at a non-existent Azure DNS zone.
- **Optional — purge the soft-deleted Key Vault** if you intend to reuse the same name within 90 days:

```powershell
az keyvault purge --name "<keyVaultName from 4.3>" --location eastus2
```

If your test_agent.py runs left orphan agents or A2A connections you want gone before the resource-group delete completes, you can delete them from the Foundry portal first — but `az group delete` will clean them up regardless.

---

## 9. References

- [`docs/use-case.md`](./use-case.md) — the Zava Smart Order Feasibility scenario and business value.
- [`docs/architecture.md`](./architecture.md) — the deployed Azure components, identity model, and cost breakdown.
- [`docs/technology.md`](./technology.md) — the implementation details (Foundry V2 + LangGraph + React + FastAPI).
- [`docs/a2a-foundry-walkthrough.md`](./a2a-foundry-walkthrough.md) — beginner-friendly, copy-paste walkthrough of A2A in a Foundry V2 agent.
- [`docs/a2a-implementation.md`](./a2a-implementation.md) — A2A protocol deep-dive: wire format, auth, dual-part artifact pattern, version interop.
- [`docs/private-vnet-considerations.md`](./private-vnet-considerations.md) — guidance for hardened / private-VNet deployments.
- [`docs/deployment-learnings.md`](./deployment-learnings.md) — As-deployed notes and GA-specific workarounds from a successful end-to-end run.
- [`plan.md`](../plan.md) §F.1 — gating risks (DNS delegation, TLS cert, gpt-5.5 quota).
