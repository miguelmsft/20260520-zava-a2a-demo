# scripts/ — deployment driver scripts

PowerShell 7+ scripts that drive the end-to-end Zava A2A demo deployment on
Azure. These scripts are the **canonical deployment path**; `azd up` against
`infra/azure.yaml` is offered for convenience but does not perform the
post-deployment steps (quota pre-flight, TLS cert import, AKS credential fetch,
Foundry portal pauses) that the scripts handle.

## Execution order

Run the scripts strictly in this order. Each step depends on outputs from the
previous step.

1. **`verify-quota.ps1`** — Read-only Azure check. Confirms gpt-5.5 and/or
   gpt-5.4-mini Global Standard quota in the target region and that
   `Standard_D2s_v5` is available for AKS. Decides whether the primary path
   (`useGpt55=true`) or the fallback path (`useGpt55=false`) is viable.
2. **`deploy-infra.ps1`** — Creates the resource group and runs
   `infra/main.bicep`. Configures `kubectl` against the new AKS cluster and
   handles the TLS certificate provisioning into Key Vault (`tls-cert-ops-agent`).
3. **`deploy-k8s.ps1`** *(Step 15)* — Builds and pushes the `ops-agent`
   container image to ACR, generates the A2A API key, creates the K8s secret,
   and applies the Deployment/Service/Ingress manifests under
   `apps/ops-agent/k8s/`.
4. **`setup-foundry-agent.ps1`** *(Step 16)* — Creates the Foundry A2A
   connection (portal + SDK fallback), provisions the Foundry Customer Service
   Agent, runs end-to-end tests, and walks the deployer through the App
   Insights → Foundry tracing link.

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
