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
param foundryName string = 'foundry-zava-a2a-smartorder'

@description('Foundry V2 project name (child of the Foundry account).')
param projectName string = 'smart-order-feasibility'

@description('Application Insights component name.')
param appInsightsName string = 'appi-zava-a2a-smart-order'

@description('Log Analytics workspace name backing Application Insights.')
param logAnalyticsName string = 'log-zava-a2a-smart-order'

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
  project: 'zava-a2a-smart-order-demo'
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

// --- Step 6: AKS + ACR parameters ---

@description('AKS cluster resource name.')
param aksClusterName string = 'aks-zava-a2a-smart-order'

@description('Globally-unique ACR name. Must be alphanumeric only, 5–50 chars. Defaults to a name derived from uniqueString(resourceGroup().id) to avoid collisions.')
param acrName string = 'acrzavaa2asmartorder${uniqueString(resourceGroup().id)}'

// --- Step 7: Key Vault + DNS + Workload Identity parameters ---

@description('Globally-unique Key Vault name. Max 24 chars, alphanumeric + hyphen, must start with a letter. Default "kv-zava-a2a<13-char hash>" lands exactly at 24 chars (11 + 13).')
param keyVaultName string = 'kv-zava-a2a${uniqueString(resourceGroup().id)}'

@description('Public DNS zone name for the demo (e.g., "zava-demo.example.com"). The default is a placeholder — override with a domain you control. Delegation to Azure DNS is a manual post-deploy step (see deployment script).')
param dnsZoneName string = 'zava-a2a-smart-order.example.com'

@description('User-Assigned Managed Identity name for the LangGraph Ops Agent pod (Workload Identity).')
param uamiName string = 'id-zava-a2a-ops-agent'

// -----------------------------------------------------------------------------
// Constants — Built-in role definition GUIDs
// -----------------------------------------------------------------------------
// Foundry Account Owner: full management of the Foundry account and its projects.
// GUID per research/2026-05-20-foundry-v2.md §4 (verified built-in role).
var foundryAccountOwnerRoleId = 'e47c6f54-e4a2-4754-9501-8e0985b135e1'

// AcrPull: read-only access to ACR images. Granted to the AKS kubelet identity
// at the ACR scope so the cluster can pull container images without secrets.
// GUID per research/2026-05-20-aks.md §3.2 + Azure built-in roles documentation.
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// Log Analytics Reader: read access to App Insights / Log Analytics traces.
// Required for the deployer (or any demo user) to see the Foundry portal
// Agents → Traces tab populate — the portal queries App Insights on behalf
// of the user, so without this role the tab appears empty even if traces
// are flowing into App Insights.
// GUID per research/2026-05-21-foundry-agent-traces.md §2.2.
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'

// Foundry User (a.k.a. "Azure AI User"): data-plane access to Foundry projects.
// Includes the data action `Microsoft.CognitiveServices/*` which covers reading
// project connections, listing/getting/creating/invoking agents, and similar
// data-plane operations the Foundry SDK performs. Foundry Account Owner is a
// control-plane role only — without this role, the SDK calls
// project.connections.get(...) and project.agents.list(...) return
// PermissionDenied with the missing-data-action message and freshly-deployed
// agents/connections appear "not found" to the deployer.
// GUID per research/2026-05-20-foundry-v2.md §4 + identity.bicep (where the
// same role is granted to the workload-identity UAMI).
var foundryUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

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

// Connect App Insights to the Foundry account so the portal Traces tab
// (Agents → Traces in the Foundry portal) populates with server-side traces
// emitted by Foundry prompt agents. The connection is scoped to the account
// with isSharedToAll: true so all projects (current and future) under the
// account inherit it. Per research/2026-05-21-foundry-agent-traces.md §2/§5,
// this single connection is the only configuration required for prompt-agent
// server-side traces (GA) to appear in the portal — no SDK changes needed.
module foundryAppInsightsConnection 'modules/foundry-appinsights-connection.bicep' = {
  name: 'foundry-appinsights-connection-deploy'
  params: {
    foundryAccountName: foundry.outputs.foundryAccountName
    appInsightsResourceId: appInsights.outputs.appInsightsId
    appInsightsConnectionString: appInsights.outputs.appInsightsConnectionString
  }
}

// Step 6 — Azure Container Registry (Basic SKU, no admin user). Hosts the
// LangGraph Ops Agent container image consumed by the AKS cluster below.
module acr 'modules/acr.bicep' = {
  name: 'acr-deploy'
  params: {
    location: location
    acrName: acrName
    tags: tags
  }
}

// Step 6 — AKS cluster (Free tier, OIDC + Workload Identity + App Routing,
// Container Insights via the Log Analytics workspace from Step 5).
module aks 'modules/aks.bicep' = {
  name: 'aks-deploy'
  params: {
    location: location
    clusterName: aksClusterName
    dnsPrefix: aksClusterName
    logAnalyticsWorkspaceId: appInsights.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// Step 7 — Key Vault for the ingress TLS certificate. RBAC-only auth; no
// access policies. Application Routing add-on identity is granted Certificate
// User + Secrets User on this vault (in identity.bicep).
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deploy'
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: tags
  }
}

// Step 7 — Public Azure DNS zone for the Ops Agent ingress hostname. The
// Application Routing add-on identity is granted DNS Zone Contributor on this
// zone (in identity.bicep) so the managed NGINX can manage record sets.
module dns 'modules/dns.bicep' = {
  name: 'dns-deploy'
  params: {
    dnsZoneName: dnsZoneName
    tags: tags
  }
}

// Step 7 — User-Assigned Managed Identity + federated credential for the
// LangGraph Ops Agent K8s service account, plus all the role assignments
// described in identity.bicep header. Depends implicitly on foundry, aks,
// keyVault, and dns via parameter inputs (existing-resource lookups inside
// identity.bicep need those resources to exist first — so we declare the
// module-level dependsOn explicitly to be safe).
module identity 'modules/identity.bicep' = {
  name: 'identity-deploy'
  params: {
    location: location
    uamiName: uamiName
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    foundryAccountName: foundry.outputs.foundryAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    dnsZoneName: dns.outputs.dnsZoneName
    webAppRoutingIdentityObjectId: aks.outputs.webAppRoutingIdentityObjectId
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
// RBAC — grant the deployer 'Foundry User' (data-plane) on the Foundry account
// -----------------------------------------------------------------------------
// Foundry Account Owner is a control-plane role. The Foundry SDK calls used by
// scripts/setup-foundry-agent.ps1 (`projects.connections.get`,
// `projects.agents.list`, `projects.agents.create`) and by the front-end / test
// scripts at demo time are data-plane operations that require the
// `Microsoft.CognitiveServices/*` data action. Without this assignment a
// freshly-deployed Foundry shows existing connections / agents as "not found"
// to the deployer and create_a2a_connection.py --verify fails with a
// PermissionDenied error referencing the missing
// `Microsoft.CognitiveServices/accounts/AIServices/agents/read` data action.

resource deployerFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccountResource
  name: guid(resourceGroup().id, foundryName, deployerPrincipalId, foundryUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
    description: 'Foundry User (data plane) for the demo deployer — required for the Foundry SDK to read connections / list / create agents on behalf of the deployer.'
  }
}

// -----------------------------------------------------------------------------
// RBAC — grant the AKS kubelet (node) identity 'AcrPull' on the ACR
// -----------------------------------------------------------------------------
// Required so the cluster can pull container images from the registry without
// any stored secret. Scoped to the ACR resource. The kubelet identity is a
// system-assigned managed identity, hence principalType: ServicePrincipal.

resource acrResource 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' existing = {
  name: acrName
  dependsOn: [
    acr
  ]
}

resource aksResource 'Microsoft.ContainerService/managedClusters@2026-02-01' existing = {
  name: aksClusterName
  dependsOn: [
    aks
  ]
}

resource aksKubeletAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acrResource
  name: guid(acrResource.id, aksResource.id, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aks.outputs.kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
    description: 'AcrPull for the AKS kubelet identity (granted by main.bicep Step 6).'
  }
}

// -----------------------------------------------------------------------------
// RBAC — grant the deployer 'Log Analytics Reader' on App Insights
// -----------------------------------------------------------------------------
// Required so the Foundry portal's Agents → Traces tab can render traces on
// behalf of the user. Foundry Account Owner does NOT inherit to App Insights
// (separate resource provider — Microsoft.Insights/components), so we must
// grant the read role explicitly. Per research/2026-05-21-foundry-agent-traces.md
// §2.2 "Developer viewing traces → Application Insights → Log Analytics Reader".

resource appInsightsResource 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
  dependsOn: [
    appInsights
  ]
}

resource deployerLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appInsightsResource
  name: guid(resourceGroup().id, appInsightsName, deployerPrincipalId, logAnalyticsReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
    description: 'Log Analytics Reader for the demo deployer — required to view Foundry agent traces in the portal Traces tab.'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Foundry V2 project endpoint — set as PROJECT_ENDPOINT in agent configs.')
output projectEndpoint string = foundry.outputs.projectEndpoint

@description('Foundry account inference endpoint — Azure OpenAI-compatible base URL. Pass to deploy-k8s.ps1 as -FoundryAccountEndpoint; used inside the ops-agent pod as AZURE_OPENAI_ENDPOINT.')
output accountInferenceEndpoint string = foundry.outputs.accountInferenceEndpoint

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

@description('Name of the Foundry → App Insights connection on the Foundry account. Verifies the Traces tab wiring is in place.')
output foundryAppInsightsConnectionName string = foundryAppInsightsConnection.outputs.connectionName

@description('Log Analytics workspace ARM resource ID (used by AKS Container Insights addon in Step 6).')
output logAnalyticsWorkspaceId string = appInsights.outputs.logAnalyticsWorkspaceId

@description('Log Analytics workspace name.')
output logAnalyticsName string = appInsights.outputs.logAnalyticsName

// -- AKS + ACR outputs (Step 6) -----------------------------------------------

@description('AKS cluster resource name.')
output aksClusterName string = aks.outputs.clusterName

@description('AKS OIDC issuer URL — consumed by Step 7 to create the federated identity credential for the LangGraph Ops Agent service account.')
output aksOidcIssuerUrl string = aks.outputs.oidcIssuerUrl

@description('Object ID of the AKS Application Routing (managed NGINX) add-on identity. Step 7 grants it Key Vault Certificate User + DNS Zone Contributor.')
output aksWebAppRoutingIdentityObjectId string = aks.outputs.webAppRoutingIdentityObjectId

@description('ACR login server hostname (e.g., myregistry.azurecr.io). Used by container build / push / pull and by the Kubernetes Deployment image reference.')
output acrLoginServer string = acr.outputs.acrLoginServer

// -- Key Vault + DNS + Workload Identity outputs (Step 7) ---------------------

@description('Key Vault DNS endpoint URI (https://<name>.vault.azure.net/). Set as kubernetes.azure.com/tls-cert-keyvault-uri-prefix on the ingress.')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Public DNS zone name. Configure A/CNAME records here for the Ops Agent ingress hostname.')
output dnsZoneName string = dns.outputs.dnsZoneName

@description('Authoritative name servers Azure assigned to the DNS zone — configure these at the domain registrar to delegate the zone.')
output dnsZoneNameServers array = dns.outputs.dnsZoneNameServers

@description('UAMI client ID — set as azure.workload.identity/client-id on the Ops Agent K8s service account.')
output uamiClientId string = identity.outputs.uamiClientId

@description('UAMI principal (object) ID — useful for ad-hoc RBAC operations outside identity.bicep.')
output uamiPrincipalId string = identity.outputs.uamiPrincipalId
