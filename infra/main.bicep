// =============================================================================
// Zava A2A Multi-Agent Demo — Infrastructure Orchestrator
// =============================================================================
// This is the initial main.bicep introduced in Step 3. It currently deploys:
//   - The Foundry V2 account + project (modules/foundry.bicep)
//   - A 'Foundry Account Owner' RBAC assignment for the deployer principal
//
// Subsequent steps will extend this file by adding additional modules:
//   - Step 4: model deployments (foundry-models.bicep)
//   - Step 5: App Insights + Log Analytics (appinsights.bicep)
//   - Step 6: AKS + ACR (aks.bicep, acr.bicep)
//   - Step 7: Key Vault, DNS, Workload Identity (keyvault.bicep, dns.bicep, identity.bicep)
//
// Target scope: resourceGroup (default).
// =============================================================================

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Azure region for all resources. Default eastus2 — supports all candidate models.')
param location string = 'eastus2'

@description('Foundry V2 account name (globally unique within Cognitive Services namespace).')
param foundryName string = 'foundry-zava-demo'

@description('Foundry V2 project name (child of the Foundry account).')
param projectName string = 'zava-project'

@description('Azure AD object ID (principal ID) of the deployer to grant Foundry Account Owner role on the Foundry resource. REQUIRED. Pass via deploy script: --parameters deployerPrincipalId=<oid>.')
param deployerPrincipalId string

@description('Principal type for the deployer RBAC assignment. Use "User" for a human deployer, or "ServicePrincipal" for an SP / managed identity.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

@description('Tags applied to all resources.')
param tags object = {
  project: 'zava-a2a-demo'
  environment: 'demo'
  managedBy: 'bicep'
}

// -----------------------------------------------------------------------------
// Constants — Built-in role definition GUIDs
// -----------------------------------------------------------------------------
// Foundry Account Owner: full management of the Foundry account and its projects.
// GUID per research/2026-05-20-foundry-v2.md §4 (verified built-in role).
var foundryAccountOwnerRoleId = 'e47c6f54-e4a2-4754-9501-8e0985b135e1'

// -----------------------------------------------------------------------------
// Modules
// -----------------------------------------------------------------------------

module foundry 'modules/foundry.bicep' = {
  name: 'foundry-deploy'
  params: {
    foundryName: foundryName
    projectName: projectName
    location: location
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// RBAC — grant the deployer 'Foundry Account Owner' on the Foundry account
// -----------------------------------------------------------------------------
// Scoped to the Foundry account resource so the role applies to the account
// and (by inheritance) its child project + future model deployments.

resource foundryAccountResource 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: foundryName
  dependsOn: [
    foundry
  ]
}

resource deployerFoundryOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccountResource
  name: guid(resourceGroup().id, foundryName, deployerPrincipalId, foundryAccountOwnerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryAccountOwnerRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
    description: 'Foundry Account Owner for the demo deployer (granted by main.bicep Step 3).'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Foundry V2 project endpoint — set as PROJECT_ENDPOINT in agent configs.')
output projectEndpoint string = foundry.outputs.projectEndpoint

@description('Foundry account ARM resource ID.')
output foundryResourceId string = foundry.outputs.foundryResourceId

@description('Foundry account name.')
output foundryAccountName string = foundry.outputs.foundryAccountName

@description('Foundry V2 project name.')
output projectName string = foundry.outputs.projectName

@description('Resource group location used for the deployment.')
output deploymentLocation string = location
