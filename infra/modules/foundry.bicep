// =============================================================================
// Foundry V2 — Account + Project module
// =============================================================================
// Deploys a Microsoft Foundry V2 account (Microsoft.CognitiveServices/accounts,
// kind: 'AIServices') and a Foundry V2 project as a child resource.
//
// API version: 2026-03-01 (current GA)
//   - https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts
//   - https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects
//
// Notes:
//   - kind: 'AIServices' is what makes this a Foundry V2 resource (not 'FoundryServices').
//   - allowProjectManagement: true is required to enable project sub-resources.
//   - customSubDomainName is required and defines the endpoint subdomain.
//   - Model deployments are children of the account (not the project) and live
//     in a separate module (Step 4: foundry-models.bicep).
// =============================================================================

@description('Name of the Foundry account (must be globally unique within Cognitive Services namespace).')
param foundryName string

@description('Name of the Foundry V2 project (child of the Foundry account).')
param projectName string

@description('Azure region. Default eastus2 — supports all candidate models including gpt-5.5.')
param location string = 'eastus2'

@description('Tags applied to the Foundry account and project.')
param tags object = {}

// --- Foundry Account ---
resource foundry 'Microsoft.CognitiveServices/accounts@2026-03-01' = {
  name: foundryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
  }
}

// --- Foundry Project (child of the account) ---
resource project 'Microsoft.CognitiveServices/accounts/projects@2026-03-01' = {
  name: projectName
  parent: foundry
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// --- Outputs ---
@description('Foundry V2 project endpoint (Responses API / AIProjectClient).')
output projectEndpoint string = 'https://${foundryName}.services.ai.azure.com/api/projects/${projectName}'

@description('Foundry account inference endpoint — Azure OpenAI-compatible base URL (no /api/projects path). Use this for langchain_openai.AzureChatOpenAI(azure_endpoint=...).')
output accountInferenceEndpoint string = 'https://${foundryName}.services.ai.azure.com'

@description('Foundry account ARM resource ID — use as scope for RBAC and child deployments.')
output foundryResourceId string = foundry.id

@description('Foundry account name (echoed back for downstream modules).')
output foundryAccountName string = foundry.name

@description('Foundry V2 project name (echoed back for downstream modules).')
output projectName string = project.name

@description('Foundry account system-assigned managed identity principalId.')
output foundryPrincipalId string = foundry.identity.principalId
