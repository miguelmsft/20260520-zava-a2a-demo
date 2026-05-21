// =============================================================================
// Module: keyvault.bicep
// =============================================================================
// Provisions an Azure Key Vault used by the Zava A2A demo to hold the TLS
// certificate served by the AKS Application Routing (managed NGINX) ingress
// for the LangGraph Ops Agent endpoint.
//
// Resource: Microsoft.KeyVault/vaults
// API:      2024-11-01 (latest GA at planning time)
//
// Configuration (per plan §C Step 7):
//   - SKU: Standard (sufficient for demo TLS certs; no HSM-backed keys needed).
//   - enableRbacAuthorization: true — RBAC instead of legacy access policies so
//     role assignments (Step 7) are the only path that grants vault access.
//   - tenantId: subscription().tenantId — bound to the deployer's home tenant.
//   - enableSoftDelete: true with retention 7 days (minimum allowed) — friendly
//     for demo cleanup while still preserving the ARM property contract.
//   - enablePurgeProtection: false — the demo is intended to be torn down and
//     recreated; purge protection would block redeploys for 90 days.
//
// References:
//   - plan.md §C Step 7
//   - https://learn.microsoft.com/azure/templates/microsoft.keyvault/2024-11-01/vaults
// =============================================================================

@description('Azure region for the Key Vault.')
param location string = resourceGroup().location

@description('Key Vault resource name. Must be 3–24 alphanumeric+hyphen characters and globally unique.')
param keyVaultName string

@description('Tags applied to the Key Vault.')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Key Vault ARM resource ID — used as scope for downstream RBAC role assignments.')
output keyVaultId string = keyVault.id

@description('Key Vault resource name (echoed back for downstream modules).')
output keyVaultName string = keyVault.name

@description('Key Vault DNS endpoint URI (e.g., https://kv-zava-demo.vault.azure.net/). Consumed by the ingress annotation kubernetes.azure.com/tls-cert-keyvault-uri.')
output keyVaultUri string = keyVault.properties.vaultUri
