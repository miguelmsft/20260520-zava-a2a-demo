// =============================================================================
// Foundry V2 — Model Deployments module
// =============================================================================
// Deploys two model deployments as children of the Foundry V2 account:
//   1. Orchestrator deployment (used by the Foundry Customer Service Agent)
//   2. Worker deployment        (used by the LangGraph Ops Agent on AKS)
//
// API version: 2026-03-01 (current GA, matches foundry.bicep)
//   - https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/deployments
//
// Branching semantics (R1 fallback — see plan.md §C Step 4 / §F):
//   - useGpt55 = true  (PRIMARY):
//       Orchestrator -> gpt-5.5       (2026-04-24, GlobalStandard, capacity 50)
//       Worker       -> gpt-5.4-mini  (2026-03-17, GlobalStandard, capacity 100)
//   - useGpt55 = false (FALLBACK):
//       Orchestrator -> gpt-5.4-mini  (2026-03-17, GlobalStandard, capacity 100)
//       Worker       -> gpt-5.4-mini  (2026-03-17, GlobalStandard, capacity 100)
//
// Capacity sizing notes:
//   - Code Interpreter + A2A workflows burn through TPM very quickly because
//     each tool round-trip adds reasoning tokens. With capacity=10 (1K TPM)
//     a single feasibility query hits a 429 mid-stream. capacity=100 (=100K
//     TPM for gpt-5.4-mini GlobalStandard) gives enough headroom for the
//     demo without exhausting subscription quota (default limit is 1000
//     units in eastus2).
//
// In BOTH branches the module emits two distinct deployments with different
// names so the demo's "different deployment per agent" property is preserved.
// The orchestrator deployment NAME is held stable across branches so that
// downstream consumers (Step 11 setup_agent.py) read a single env var
// (FOUNDRY_ORCHESTRATOR_DEPLOYMENT) and need no branching logic.
//
// Notes:
//   - gpt-5.5 Global Standard is only available in eastus2 and southcentralus,
//     and gpt-5.5 has 0 default quota at Tiers 1-4 (research/2026-05-20-
//     model-availability.md §4 / §7). The fallback path exists precisely for
//     subscriptions that cannot get gpt-5.5 quota.
//   - Deployment names contain no dots (per Cognitive Services naming rules).
// =============================================================================

@description('Name of the existing Foundry V2 account that will host these model deployments. Pass from foundry.bicep output (foundryAccountName).')
param foundryAccountName string

@description('Whether to deploy gpt-5.5 as the orchestrator model. true = primary path; false = fallback path (both deployments use gpt-5.4-mini, but with distinct names).')
param useGpt55 bool = true

@description('Deployment name for the orchestrator (Foundry Customer Service Agent). Kept stable across both branches so Step 11 has no branching logic. No dots allowed.')
param orchestratorDeploymentName string = 'gpt-55-orchestrator'

@description('Deployment name for the worker (LangGraph Ops Agent on AKS). No dots allowed.')
param workerDeploymentName string = 'gpt-54mini-worker'

// -----------------------------------------------------------------------------
// Constants — model identifiers and version pins
// -----------------------------------------------------------------------------
// Versions verified against research/2026-05-20-model-availability.md §2.
var gpt55ModelName = 'gpt-5.5'
var gpt55ModelVersion = '2026-04-24'

var gpt54MiniModelName = 'gpt-5.4-mini'
var gpt54MiniModelVersion = '2026-03-17'

// Resolved orchestrator model parameters (branch on useGpt55).
var orchestratorModelName = useGpt55 ? gpt55ModelName : gpt54MiniModelName
var orchestratorModelVersion = useGpt55 ? gpt55ModelVersion : gpt54MiniModelVersion
var orchestratorCapacity = useGpt55 ? 50 : 100

// -----------------------------------------------------------------------------
// Existing parent — Foundry account
// -----------------------------------------------------------------------------
resource foundry 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: foundryAccountName
}

// -----------------------------------------------------------------------------
// Deployment 1 — Orchestrator (used by the Foundry Customer Service Agent)
// -----------------------------------------------------------------------------
resource orchestratorDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-03-01' = {
  parent: foundry
  name: orchestratorDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: orchestratorCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: orchestratorModelName
      version: orchestratorModelVersion
    }
  }
}

// -----------------------------------------------------------------------------
// Deployment 2 — Worker (used by the LangGraph Ops Agent on AKS)
// -----------------------------------------------------------------------------
// Always gpt-5.4-mini regardless of useGpt55. dependsOn the orchestrator
// deployment because Cognitive Services serializes deployment writes against
// the same parent account.
resource workerDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-03-01' = {
  parent: foundry
  name: workerDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: 100
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt54MiniModelName
      version: gpt54MiniModelVersion
    }
  }
  dependsOn: [
    orchestratorDeployment
  ]
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
@description('Deployment name for the orchestrator (Foundry Customer Service Agent). Stable across primary and fallback branches.')
output orchestratorDeploymentName string = orchestratorDeployment.name

@description('Deployment name for the worker (LangGraph Ops Agent on AKS).')
output workerDeploymentName string = workerDeployment.name

@description('Resolved orchestrator model name (gpt-5.5 in primary branch, gpt-5.4-mini in fallback branch).')
output orchestratorModel string = orchestratorModelName

@description('Resolved worker model name (always gpt-5.4-mini).')
output workerModel string = gpt54MiniModelName
