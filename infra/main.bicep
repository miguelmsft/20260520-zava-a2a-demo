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

@description('Application Insights component name.')
param appInsightsName string = 'appi-zava-demo'

@description('Log Analytics workspace name backing Application Insights.')
param logAnalyticsName string = 'log-zava-demo'

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

// --- Step 4: Model deployment parameters ---

@description('Whether to deploy gpt-5.5 as the orchestrator model. true = primary path (gpt-5.5 + gpt-5.4-mini). false = fallback path (both deployments use gpt-5.4-mini, with distinct names). See plan §C Step 4 / §F R1 mitigation.')
param useGpt55 bool = true

@description('Deployment name for the orchestrator (Foundry Customer Service Agent). Stable across primary and fallback branches.')
param orchestratorDeploymentName string = 'gpt-55-orchestrator'

@description('Deployment name for the worker (LangGraph Ops Agent on AKS).')
param workerDeploymentName string = 'gpt-54mini-worker'

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

// Step 4 — Model deployments (children of the Foundry account).
// Always emits two distinct deployments (different name per agent), branching
// only on the orchestrator's underlying model per the useGpt55 fallback.
module foundryModels 'modules/foundry-models.bicep' = {
  name: 'foundry-models-deploy'
  params: {
    foundryAccountName: foundry.outputs.foundryAccountName
    useGpt55: useGpt55
    orchestratorDeploymentName: orchestratorDeploymentName
    workerDeploymentName: workerDeploymentName
  }
}

// Observability — Log Analytics workspace + workspace-based Application Insights.
// Outputs (connection string + workspace id) are consumed post-deploy to wire
// Foundry tracing (per research/2026-05-20-foundry-control-plane.md §4.1) and
// by future modules (AKS Container Insights addon — Step 6).
module appInsights 'modules/appinsights.bicep' = {
  name: 'appinsights-deploy'
  params: {
    location: location
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
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

// --- Step 4: Model deployment outputs ---

@description('Orchestrator deployment name (used by the Foundry Customer Service Agent — Step 11 reads this as FOUNDRY_ORCHESTRATOR_DEPLOYMENT).')
output orchestratorDeploymentName string = foundryModels.outputs.orchestratorDeploymentName

@description('Worker deployment name (used by the LangGraph Ops Agent on AKS).')
output workerDeploymentName string = foundryModels.outputs.workerDeploymentName

@description('Resolved orchestrator model (gpt-5.5 in primary branch, gpt-5.4-mini in fallback branch).')
output orchestratorModel string = foundryModels.outputs.orchestratorModel

@description('Resolved worker model (always gpt-5.4-mini).')
output workerModel string = foundryModels.outputs.workerModel

// -- Observability outputs (Step 5) -------------------------------------------

@description('Application Insights ARM resource ID.')
output appInsightsId string = appInsights.outputs.appInsightsId

@description('Application Insights resource name.')
output appInsightsName string = appInsights.outputs.appInsightsName

@description('Application Insights connection string. Used by app SDKs / OpenTelemetry exporters and to wire Foundry project tracing post-deploy.')
output appInsightsConnectionString string = appInsights.outputs.appInsightsConnectionString

@description('Log Analytics workspace ARM resource ID (used by AKS Container Insights addon in Step 6).')
output logAnalyticsWorkspaceId string = appInsights.outputs.logAnalyticsWorkspaceId

@description('Log Analytics workspace name.')
output logAnalyticsName string = appInsights.outputs.logAnalyticsName
