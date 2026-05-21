// =============================================================================
// Module: identity.bicep
// =============================================================================
// Provisions the User-Assigned Managed Identity (UAMI) for the LangGraph Ops
// Agent pod on AKS, federates it to the K8s service account via OIDC, and
// wires all the role assignments needed for the demo to function:
//
//   1. UAMI → "Foundry User" on the Foundry account
//        — lets the pod call Azure OpenAI / Foundry Agents via Entra tokens
//          (no API keys), as the workload identity exchanges its K8s SA token
//          for an AAD token bound to this UAMI.
//
//   2. AKS App Routing add-on identity → "Key Vault Certificate User" on KV
//        — lets the managed NGINX ingress pull the TLS cert from Key Vault
//          via the kubernetes.azure.com/tls-cert-keyvault-uri annotation.
//
//   3. AKS App Routing add-on identity → "Key Vault Secrets User" on KV
//        — companion role for the cert-from-secret flow (App Routing fetches
//          the cert as a secret representation; both roles are recommended).
//
//   4. AKS App Routing add-on identity → "DNS Zone Contributor" on DNS zone
//        — lets the managed NGINX ingress create A/CNAME records for
//          host-based routing on the demo domain.
//
// Resources & APIs:
//   - Microsoft.ManagedIdentity/userAssignedIdentities                     2024-11-30
//   - Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials 2024-11-30
//   - Microsoft.Authorization/roleAssignments                              2022-04-01
//
// Federated credential (per research/2026-05-20-aks.md §5):
//   - issuer:    AKS OIDC issuer URL (passed in)
//   - subject:   system:serviceaccount:default:ops-agent-sa
//   - audiences: ['api://AzureADTokenExchange']
//
// References:
//   - plan.md §C Step 7 (role GUID list)
//   - research/2026-05-20-aks.md §4 (App Routing add-on), §5 (Workload Identity)
// =============================================================================

@description('Azure region for the User-Assigned Managed Identity.')
param location string = resourceGroup().location

@description('User-Assigned Managed Identity name for the LangGraph Ops Agent pod.')
param uamiName string = 'id-zava-a2a-ops-agent'

@description('AKS OIDC issuer URL — bind the federated credential to this issuer. Pass aks.outputs.oidcIssuerUrl from main.bicep.')
param aksOidcIssuerUrl string

@description('Foundry account resource name — used to scope the Foundry User role assignment for the UAMI.')
param foundryAccountName string

@description('Key Vault resource name — used to scope the Key Vault Certificate User and Secrets User role assignments for the App Routing identity.')
param keyVaultName string

@description('DNS zone name — used to scope the DNS Zone Contributor role assignment for the App Routing identity.')
param dnsZoneName string

@description('Object (principal) ID of the AKS Application Routing add-on managed identity. Pass aks.outputs.webAppRoutingIdentityObjectId from main.bicep.')
param webAppRoutingIdentityObjectId string

@description('Kubernetes namespace hosting the Ops Agent service account. Default "default" matches the demo manifests.')
param k8sNamespace string = 'default'

@description('Kubernetes service account name used by the Ops Agent pod.')
param k8sServiceAccountName string = 'ops-agent-sa'

@description('Tags applied to the UAMI.')
param tags object = {}

// -----------------------------------------------------------------------------
// Built-in role definition GUIDs
// -----------------------------------------------------------------------------
// All values verified against the Azure built-in roles documentation. See
// plan.md §C Step 7 for citations.

// Foundry User — read/use access to Foundry account models & projects.
var foundryUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

// Key Vault Certificate User — read certificate (incl. private-key cert
// representation) from a Key Vault that uses RBAC authorization.
var keyVaultCertificateUserRoleId = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'

// Key Vault Secrets User — read secret content; companion to Certificate User
// for the App Routing cert-from-secret flow.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// DNS Zone Contributor — create/update/delete record sets within a DNS zone.
var dnsZoneContributorRoleId = 'befefa01-2a29-4197-83a8-272ff33ce314'

// -----------------------------------------------------------------------------
// User-Assigned Managed Identity (UAMI) for the Ops Agent pod
// -----------------------------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: uamiName
  location: location
  tags: tags
}

// Federated identity credential — links the UAMI to the K8s service account
// 'system:serviceaccount:<namespace>:<sa-name>' via the AKS OIDC issuer.
// The audience must be 'api://AzureADTokenExchange' for AKS Workload Identity
// per research/2026-05-20-aks.md §5.
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: uami
  name: 'fc-ops-agent-sa'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// -----------------------------------------------------------------------------
// Existing-resource references for RBAC scoping
// -----------------------------------------------------------------------------
// Each role assignment is scoped to a specific Azure resource (Foundry, KV,
// DNS zone) so the principal only gets permissions where needed.

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: foundryAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource dnsZone 'Microsoft.Network/dnsZones@2023-07-01-preview' existing = {
  name: dnsZoneName
}

// -----------------------------------------------------------------------------
// RBAC — UAMI → Foundry User on the Foundry account
// -----------------------------------------------------------------------------

resource uamiFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, uami.id, foundryUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Foundry User for the Ops Agent UAMI (granted by identity.bicep Step 7).'
  }
}

// -----------------------------------------------------------------------------
// RBAC — App Routing identity → Key Vault Certificate User on Key Vault
// -----------------------------------------------------------------------------

resource appRoutingKvCertificateUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, webAppRoutingIdentityObjectId, keyVaultCertificateUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateUserRoleId)
    principalId: webAppRoutingIdentityObjectId
    principalType: 'ServicePrincipal'
    description: 'Key Vault Certificate User for the AKS App Routing add-on identity (granted by identity.bicep Step 7).'
  }
}

// -----------------------------------------------------------------------------
// RBAC — App Routing identity → Key Vault Secrets User on Key Vault
// -----------------------------------------------------------------------------

resource appRoutingKvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, webAppRoutingIdentityObjectId, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: webAppRoutingIdentityObjectId
    principalType: 'ServicePrincipal'
    description: 'Key Vault Secrets User for the AKS App Routing add-on identity (granted by identity.bicep Step 7).'
  }
}

// -----------------------------------------------------------------------------
// RBAC — App Routing identity → DNS Zone Contributor on DNS zone
// -----------------------------------------------------------------------------

resource appRoutingDnsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dnsZone
  name: guid(dnsZone.id, webAppRoutingIdentityObjectId, dnsZoneContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dnsZoneContributorRoleId)
    principalId: webAppRoutingIdentityObjectId
    principalType: 'ServicePrincipal'
    description: 'DNS Zone Contributor for the AKS App Routing add-on identity (granted by identity.bicep Step 7).'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('UAMI resource name (echoed back for downstream modules / Kubernetes manifests).')
output uamiName string = uami.name

@description('UAMI client (application) ID — set as the azure.workload.identity/client-id annotation on the K8s service account.')
output uamiClientId string = uami.properties.clientId

@description('UAMI principal (object) ID — useful for ad-hoc role assignments outside this module.')
output uamiPrincipalId string = uami.properties.principalId

@description('UAMI ARM resource ID.')
output uamiResourceId string = uami.id
