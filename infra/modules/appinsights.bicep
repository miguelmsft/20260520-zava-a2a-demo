// =============================================================================
// Module: appinsights.bicep
// =============================================================================
// Provisions the observability stack for the Zava A2A demo:
//   - Log Analytics workspace (Microsoft.OperationalInsights/workspaces)
//   - Application Insights component (Microsoft.Insights/components), workspace-based
//
// The App Insights connection string is exported so that:
//   - The local FastAPI backend and the LangGraph Ops Agent (on AKS) can emit
//     telemetry via OpenTelemetry / the App Insights SDKs.
//   - The Foundry V2 project can be linked to this App Insights resource for
//     agent tracing. Per research/2026-05-20-foundry-control-plane.md §4.1,
//     this Foundry-side wiring is performed post-deployment via the portal or
//     SDK; this module only provisions the App Insights resource.
//
// References:
//   - plan.md §A.7 (observability)
//   - research/2026-05-20-foundry-control-plane.md §2.3 (tracing GA), §4.1
// =============================================================================

@description('Azure region for both the Log Analytics workspace and App Insights.')
param location string = 'eastus2'

@description('Application Insights component name.')
param appInsightsName string = 'appi-zava-demo'

@description('Log Analytics workspace name (workspace-based App Insights backend).')
param logAnalyticsName string = 'log-zava-demo'

@description('Tags applied to both resources.')
param tags object = {
  project: 'zava-a2a-demo'
  environment: 'demo'
  managedBy: 'bicep'
}

// -----------------------------------------------------------------------------
// Log Analytics workspace
// -----------------------------------------------------------------------------
// PerGB2018 is the standard pay-as-you-go SKU for new workspaces.
// 30-day retention keeps demo costs minimal while leaving room for review.

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Application Insights — workspace-based
// -----------------------------------------------------------------------------
// kind: 'web' is the conventional kind for application telemetry (used by both
// service-side Python SDKs and the OpenTelemetry exporter). Linking via
// WorkspaceResourceId makes this a workspace-based App Insights instance,
// which is the only mode supported for new resources.

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('Application Insights ARM resource ID.')
output appInsightsId string = appInsights.id

@description('Application Insights resource name.')
output appInsightsName string = appInsights.name

@description('Application Insights connection string. Required for SDK / OpenTelemetry exporters and for linking telemetry to the Foundry project (post-deploy).')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Log Analytics workspace ARM resource ID. Used by other modules (e.g., AKS Container Insights addon) to wire diagnostics into the same workspace.')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('Log Analytics workspace name.')
output logAnalyticsName string = logAnalytics.name
