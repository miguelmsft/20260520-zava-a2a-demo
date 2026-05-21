// =============================================================================
// Module: aks.bicep
// =============================================================================
// Provisions the AKS cluster that hosts the LangGraph Manufacturing Ops Agent
// (Agent B) for the Zava A2A demo.
//
// Resource: Microsoft.ContainerService/managedClusters
// API:      2026-02-01 (latest GA at planning time)
//   - https://learn.microsoft.com/azure/templates/microsoft.containerservice/2026-02-01/managedclusters
//
// Cluster configuration (per plan §C Step 6 + research/2026-05-20-aks.md §§2–4):
//   - SKU: Base / Free tier — $0 control-plane cost (acceptable for a demo).
//   - Identity: SystemAssigned — control-plane identity. The AcrPull binding to
//     the *kubelet* identity is created by the parent main.bicep at the ACR
//     scope (kubeletIdentityObjectId is exported below).
//   - oidcIssuerProfile.enabled: true — required for AKS Workload Identity
//     federation (Step 7 federated credential will reference the issuerUrl).
//   - securityProfile.workloadIdentity.enabled: true — enables the workload
//     identity webhook so pods can exchange K8s SA tokens for AAD tokens.
//   - ingressProfile.webAppRouting.enabled: true — managed NGINX ingress
//     ("Application Routing add-on"). Its add-on identity object ID is exported
//     so Step 7 can grant it Key Vault Certificate User + DNS Zone Contributor.
//   - addonProfiles.omsagent — Container Insights, wired to the Log Analytics
//     workspace from Step 5.
//   - System node pool: 1 node default with autoscaler 1–2, Standard_D2s_v5
//     (2 vCPU / 8 GiB), Linux, 30 GiB OS disk.
//
// kubernetesVersion: intentionally omitted — AKS picks the current N-1 default
// per research/2026-05-20-aks.md §2.2, avoiding churn as versions rotate.
//
// References:
//   - plan.md §C Step 6
//   - research/2026-05-20-aks.md §2 (versions/SKUs), §3 (OIDC/Workload Identity),
//     §4 (Application Routing), §5 (federated credential format)
// =============================================================================

@description('Azure region for the AKS cluster.')
param location string = resourceGroup().location

@description('AKS cluster resource name.')
param clusterName string

@description('DNS prefix for the cluster API server FQDN. Must be unique within the subscription region.')
param dnsPrefix string = clusterName

@description('Log Analytics workspace ARM resource ID — required by the omsagent (Container Insights) addon profile.')
param logAnalyticsWorkspaceId string

@description('Optional override for the auto-generated node resource group name. Leave empty to let AKS auto-name (recommended).')
param nodeResourceGroupName string = ''

@description('Tags applied to the AKS cluster.')
param tags object = {}

resource aks 'Microsoft.ContainerService/managedClusters@2026-02-01' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    nodeResourceGroup: empty(nodeResourceGroupName) ? null : nodeResourceGroupName

    // OIDC issuer — required for Workload Identity federation (Step 7).
    oidcIssuerProfile: {
      enabled: true
    }

    // Workload Identity webhook — pods can exchange K8s SA tokens for AAD tokens.
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // Managed NGINX ingress (Application Routing add-on). Step 7 grants the
    // add-on identity Key Vault Certificate User + DNS Zone Contributor.
    ingressProfile: {
      webAppRouting: {
        enabled: true
      }
    }

    // System node pool — minimal demo footprint with autoscaler.
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        osType: 'Linux'
        vmSize: 'Standard_D2s_v5'
        osDiskSizeGB: 30
        count: 1
        minCount: 1
        maxCount: 2
        enableAutoScaling: true
      }
    ]

    // Container Insights — ships container logs and metrics to Log Analytics.
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

@description('AKS cluster resource name.')
output clusterName string = aks.name

@description('AKS cluster ARM resource ID.')
output clusterId string = aks.id

@description('AKS API server FQDN.')
output clusterFqdn string = aks.properties.fqdn

@description('OIDC issuer URL — used by the federated identity credential in Step 7.')
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL

@description('Object ID of the AKS kubelet (node) managed identity. Granted AcrPull on the ACR by main.bicep.')
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId

@description('Object ID of the Application Routing (managed NGINX) add-on identity. Step 7 grants it Key Vault Certificate User + DNS Zone Contributor.')
output webAppRoutingIdentityObjectId string = aks.properties.ingressProfile.webAppRouting.identity.objectId
