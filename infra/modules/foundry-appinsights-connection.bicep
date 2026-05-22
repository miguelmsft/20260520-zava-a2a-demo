// =============================================================================
// Module: foundry-appinsights-connection.bicep
// =============================================================================
// Connects an existing Application Insights resource to a Foundry V2 account
// as a connected resource of category 'AppInsights'. This is the bridge that
// makes the Foundry portal Traces tab (Agents → Traces) populate with
// server-side traces emitted by Foundry prompt agents.
//
// IMPORTANT: The connection is created on the FOUNDRY ACCOUNT (not the
// project). Setting isSharedToAll: true makes it available to all projects
// under the account. Prompt agents auto-emit server-side traces once this
// connection exists — no SDK / code instrumentation is required for the
// portal Traces tab to populate.
//
// API version: 2025-04-01-preview (required for AppInsights category support
// on accounts/connections; the 2026-03-01 GA API used elsewhere does not yet
// expose the connection sub-resource).
//
// References:
//   - research/2026-05-21-foundry-agent-traces.md §2.1, §5
//   - https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/trace-agent-setup
//   - https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/connection-application-insights.bicep
// =============================================================================

@description('Foundry V2 account name (parent of the connection). Must already exist.')
param foundryAccountName string

@description('App Insights resource ID — full ARM resource ID. Used as both connection target and metadata.ResourceId.')
param appInsightsResourceId string

@description('App Insights connection string (sensitive). Stored as the connection credentials.key value.')
@secure()
param appInsightsConnectionString string

@description('Connection name suffix. The full connection name will be "<foundryAccountName>-<suffix>".')
param connectionNameSuffix string = 'appinsights'

// Reference the existing Foundry account so we can attach the connection.
resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

// Create the App Insights connection on the Foundry account.
// Properties mirror the official microsoft-foundry/foundry-samples reference
// exactly — only target/credentials are bound to our App Insights resource.
resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  name: '${foundryAccountName}-${connectionNameSuffix}'
  parent: foundry
  properties: {
    category: 'AppInsights'
    target: appInsightsResourceId
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: appInsightsConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsightsResourceId
    }
  }
}

@description('Full connection name on the Foundry account.')
output connectionName string = appInsightsConnection.name

@description('Connection ARM resource ID.')
output connectionId string = appInsightsConnection.id
