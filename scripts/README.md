# scripts/ — deployment driver scripts

PowerShell 7+ scripts that drive the end-to-end Zava A2A demo deployment on
Azure. These scripts are the **canonical deployment path**; `azd up` against
`infra/azure.yaml` is offered for convenience but does not perform the
post-deployment steps (quota pre-flight, TLS cert import, AKS credential fetch,
Foundry portal pauses) that the scripts handle.

## Single-command path (recommended)

For a full clean-room deploy, use the orchestrator:

```powershell
./scripts/deploy-all.ps1                              # uses sslip.io (no DNS needed)
./scripts/deploy-all.ps1 -UseSslipIo:$false `         # real DNS + TLS path
                         -DnsZoneName zava.example.com
```

`deploy-all.ps1` chains `verify-quota.ps1` → `deploy-infra.ps1` →
`build-and-push.ps1` → `deploy-k8s.ps1` → `setup-foundry-agent.ps1` →
`smoke-test.ps1` with no manual gates and writes a transcript to
`artifacts/deploy-all-<timestamp>.log`. It automates the four manual
workarounds documented in `docs/deployment-learnings.md` §10:

- W1: sslip.io ingress (no TLS) — automatic via `deploy-k8s.ps1 -UseSslipIo`
- W2: `OPS_AGENT_PUBLIC_URL` set after LB IP is known — automatic
- W3: A2A connection ARM PUT — `create-a2a-connection.ps1`, called inline
- W4: model deployment capacity 100 → 200 — now the bicep default

## Execution order (granular path)

Run the scripts strictly in this order if you prefer not to use
`deploy-all.ps1`. Each step depends on outputs from the previous step.

1. **`verify-quota.ps1`** — Read-only Azure check. Confirms gpt-5.5 and/or
   gpt-5.4-mini Global Standard quota in the target region and that
   `Standard_D2s_v5` is available for AKS. Decides whether the primary path
   (`useGpt55=true`) or the fallback path (`useGpt55=false`) is viable.
2. **`deploy-infra.ps1`** — Creates the resource group and runs
   `infra/main.bicep`. Configures `kubectl` against the new AKS cluster and
   handles the TLS certificate provisioning into Key Vault (`tls-cert-ops-agent`).
   Accepts `-SkipCertProvisioning` for the sslip.io path and `-FoundryName`
   to override the Foundry account name (for fresh redeploys — see
   `docs/deployment-learnings.md` §9).
3. **`build-and-push.ps1`** — Builds and pushes the `ops-agent` container
   image to ACR via `az acr build`.
4. **`deploy-k8s.ps1`** — Applies the Deployment/Service/Ingress manifests
   under `apps/ops-agent/k8s/`. With `-UseSslipIo` (default `$true`), uses
   `ingress.sslip.yaml` (no TLS) and renders the host using the LB IP after
   the service is up. With `-UseSslipIo:$false`, uses `ingress.yaml` (TLS via
   `tls-cert-ops-agent`). When passed `-SubscriptionId`, `-ResourceGroupName`,
   `-FoundryAccountName`, `-ProjectName`, also calls
   `create-a2a-connection.ps1` automatically.
5. **`create-a2a-connection.ps1`** — Idempotent ARM PUT to create / update
   the A2A connection on the Foundry account. GET → compare target → PUT
   only if different (or `-Force` to rotate the key). Called inline by
   `deploy-k8s.ps1`; can also be run standalone if you need to repoint the
   connection to a different ops-agent URL.
6. **`setup-foundry-agent.ps1`** — Provisions the Foundry Customer Service
   Agent, runs end-to-end tests, and (when called with `-SkipManualGates`)
   skips the portal pauses for the A2A connection and App Insights links
   because both are now automated upstream by `create-a2a-connection.ps1`
   and `infra/modules/foundry-appinsights-connection.bicep`.
7. **`smoke-test.ps1`** — End-to-end probe. Accepts `-OpsAgentEndpoint` (full
   URL with scheme, including `http://...sslip.io/`) or derives the URL
   from `-DnsZone`.

## Prerequisites

Install before running any of the scripts above:

- **PowerShell 7+** (the scripts use `ConvertFrom-SecureString -AsPlainText`,
  which requires PS 7).
- **Azure CLI** (`az`) — logged in (`az login`) against a subscription that
  has Azure OpenAI access in the target region.
- **kubectl** — required from `deploy-infra.ps1` onward.
- **Docker** *(for Step 15)* — local image build before `az acr build` push.
- **openssl** *(for Step 15)* — generates the A2A API key.

## Required Azure permissions

The deployer principal needs the following on the subscription (or at least on
the resource group, for the role-assignment-creating bits):

- **Owner**, *or*
- **Contributor** **+** **User Access Administrator** *(role assignments in
  `infra/main.bicep` and `infra/modules/identity.bicep` require this combination
  when Contributor is used in place of Owner).*

In addition, the principal must be allowed to:

- Read Cognitive Services quota (`verify-quota.ps1` calls
  `az cognitiveservices usage list`).
- Manage Key Vault certificates on the deployed vault (the deploy script
  imports `tls-cert-ops-agent`).

## Cost estimate ⚠️

**Estimated cost: ~$15-25/day** for the demo footprint, comprised of:

- AKS Free tier control plane + one `Standard_D2s_v5` node.
- ACR Basic SKU.
- Standard Key Vault.
- Log Analytics workspace (pay-per-GB ingestion; small for a demo).
- Application Insights (workspace-based; small for a demo).
- Public DNS zone (per-month + per-million-queries).
- **Azure OpenAI tokens** — pay-as-you-go; depends on demo traffic.

`deploy-infra.ps1` prints this warning and pauses for confirmation before
creating anything. Tear down with `az group delete --name rg-zava-a2a-smart-order-demo --yes`
when finished.
