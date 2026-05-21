// =============================================================================
// Module: acr.bicep
// =============================================================================
// Provisions an Azure Container Registry (ACR) used to host the LangGraph Ops
// Agent container image consumed by the AKS cluster (Step 6).
//
// Resource: Microsoft.ContainerRegistry/registries
// API:      2024-11-01-preview (current; supports Basic SKU and standard auth)
//   - https://learn.microsoft.com/azure/templates/microsoft.containerregistry/registries
//
// Design notes:
//   - SKU: Basic — sufficient for a single-image demo workload (cost-optimized).
//   - adminUserEnabled: false — admin user is disabled in favor of Entra ID +
//     RBAC. The AKS kubelet identity is granted AcrPull at the ACR scope by the
//     parent main.bicep (Step 6 wiring).
//   - ACR registry names must be globally unique and alphanumeric only; the
//     uniqueness is enforced by the caller via uniqueString() in main.bicep.
//
// References:
//   - plan.md §C Step 6
//   - research/2026-05-20-aks.md §3.2 (sample Bicep), §5 (AcrPull role binding)
// =============================================================================

@description('Azure region for the ACR.')
param location string = resourceGroup().location

@description('Globally-unique ACR name (alphanumeric only, 5–50 chars).')
param acrName string

@description('Tags applied to the registry.')
param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

@description('ACR ARM resource ID — used as the scope for the AcrPull role assignment to the AKS kubelet identity.')
output acrId string = acr.id

@description('ACR resource name.')
output acrName string = acr.name

@description('ACR login server hostname (e.g., myregistry.azurecr.io) — used by container build / push / pull.')
output acrLoginServer string = acr.properties.loginServer
