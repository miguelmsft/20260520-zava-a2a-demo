<#
.SYNOPSIS
    Creates or updates the A2A (Agent-to-Agent) project connection on a Foundry
    V2 account so the Foundry Customer Service Agent can call the LangGraph
    Ops Agent via the A2A protocol.

.DESCRIPTION
    The Foundry V2 Python SDK (azure-ai-projects 2.1.x) does NOT expose
    connections.create() — only get/list/get_default. The management plane
    DOES support project-connection writes via the ARM REST API at
        Microsoft.CognitiveServices/accounts/{acct}/projects/{proj}/connections/{conn}
        ?api-version=2025-06-01
    This script wraps that PUT so it can be called non-interactively from
    deploy-k8s.ps1 / deploy-all.ps1 instead of being a manual workaround
    (see docs/deployment-learnings.md §3 for history).

    The script is **idempotent**:
      1. GET the connection. If it does not exist → PUT (CREATE).
      2. If it exists and properties.target matches -TargetUrl AND -Force is
         not set → no-op (return existing connection ID).
      3. If it exists but properties.target differs OR -Force is set → PUT
         (UPDATE). The full resource is replaced (ARM PUT semantics).

    Note: The API key (`credentials.keys.x-api-key`) is **write-only**. GET
    never returns the key, so the script cannot detect a key rotation. To
    rotate the key, pass -Force.

.PARAMETER SubscriptionId
    REQUIRED. Azure subscription ID hosting the Foundry account. Used to
    build the ARM URL.

.PARAMETER ResourceGroupName
    REQUIRED. Resource group containing the Foundry account.

.PARAMETER FoundryAccountName
    REQUIRED. Name of the Microsoft.CognitiveServices/accounts (Foundry V2)
    resource — e.g. `foundry-zava-a2a-smartorder`.

.PARAMETER ProjectName
    REQUIRED. Name of the Foundry V2 project — e.g. `smart-order-feasibility`.

.PARAMETER ConnectionName
    Name of the A2A connection to create/update. Default: `ops-agent-a2a`.

.PARAMETER TargetUrl
    REQUIRED. Public HTTP(S) URL of the remote A2A endpoint (the AKS
    LangGraph Ops Agent ingress) — e.g.
    `http://ops-agent.4-153-150-147.sslip.io/`.

.PARAMETER ApiKey
    REQUIRED. Pre-shared 32-byte base64 API key. The Ops Agent enforces this
    via the `x-api-key` header on incoming requests. Source:
    `deploy-k8s.ps1` summary (`A2A API key`).

.PARAMETER A2aSubtype
    A2A subtype metadata value. Foundry agent runtime requires the
    connection's metadata to include `a2a_subtype` so it treats this
    connection as an A2A agent target rather than a generic custom-key
    connection. Default: `agent`.

.PARAMETER Force
    Switch. Always PUT (even if target appears unchanged). Use when rotating
    the API key, since GET cannot return the existing key value.

.OUTPUTS
    Hashtable with keys:
      - Operation : 'CREATE' | 'UPDATE' | 'NOOP'
      - ConnectionId : full ARM resource ID
      - ConnectionName : connection name
      - Target : the URL set on the connection after the operation
    Also writes to stdout as JSON for downstream callers.

.EXAMPLE
    ./scripts/create-a2a-connection.ps1 `
        -SubscriptionId c6a454a9-... `
        -ResourceGroupName rg-zava-a2a-smart-order-demo `
        -FoundryAccountName foundry-zava-a2a-smartorder `
        -ProjectName smart-order-feasibility `
        -TargetUrl http://ops-agent.4-153-150-147.sslip.io/ `
        -ApiKey 'aBc1...=='

.EXAMPLE
    ./scripts/create-a2a-connection.ps1 ... -Force
    Force an UPDATE PUT (use after rotating -ApiKey).

.NOTES
    Required permissions on the Foundry account:
      - 'Azure AI Administrator' OR 'Cognitive Services Contributor'
      - (Both grant Microsoft.CognitiveServices/accounts/projects/connections/write)
    The Foundry Account Owner role granted by infra/main.bicep is sufficient.

    See docs/deployment-learnings.md §3 (historical workaround) and §10 (this
    script's replacement of the workaround).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$FoundryAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$ConnectionName = 'ops-agent-a2a',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https?://.+')]
    [string]$TargetUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [string]$A2aSubtype = 'agent',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Build the ARM URL
# ---------------------------------------------------------------------------
$apiVersion = '2025-06-01'
$armUri = "https://management.azure.com/subscriptions/$SubscriptionId" +
          "/resourceGroups/$ResourceGroupName" +
          "/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName" +
          "/projects/$ProjectName/connections/$ConnectionName" +
          "?api-version=$apiVersion"

Write-Host "[create-a2a-connection] Target ARM URL:"
Write-Host "  $armUri"
Write-Host ""

# ---------------------------------------------------------------------------
# Acquire ARM access token via the signed-in az session
# ---------------------------------------------------------------------------
Write-Host "[create-a2a-connection] Acquiring ARM access token via az CLI..."
$token = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Failed to acquire ARM access token. Is 'az login' completed and is the right subscription selected?"
    exit 1
}
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = 'application/json'
}

# ---------------------------------------------------------------------------
# Step 1: GET — does the connection exist? What is its current target?
# ---------------------------------------------------------------------------
$existingTarget = $null
$exists = $false
Write-Host "[create-a2a-connection] Step 1: GET to check current state..."
try {
    $getResp = Invoke-WebRequest -Uri $armUri -Method Get -Headers $headers -UseBasicParsing -ErrorAction Stop
    $existing = $getResp.Content | ConvertFrom-Json
    $exists = $true
    if ($existing.PSObject.Properties.Name -contains 'properties' -and
        $existing.properties.PSObject.Properties.Name -contains 'target') {
        $existingTarget = [string]$existing.properties.target
    }
    Write-Host "[create-a2a-connection]   Connection EXISTS. Current target: '$existingTarget'"
} catch {
    $statusCode = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -eq 404) {
        Write-Host "[create-a2a-connection]   Connection does not exist (HTTP 404). Will CREATE."
    } else {
        Write-Error ("[create-a2a-connection] GET failed (HTTP {0}): {1}" -f $statusCode, $_.Exception.Message)
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 2: Decide whether to PUT
# ---------------------------------------------------------------------------
$shouldPut = $true
$operation = 'CREATE'

if ($exists) {
    if ($Force) {
        Write-Host "[create-a2a-connection] -Force was set; PUT regardless of current state."
        $operation = 'UPDATE'
    } elseif ($existingTarget -eq $TargetUrl) {
        Write-Host "[create-a2a-connection] Target unchanged. No PUT needed (use -Force to rotate the API key)."
        $shouldPut = $false
        $operation = 'NOOP'
    } else {
        Write-Host "[create-a2a-connection] Target changed: '$existingTarget' -> '$TargetUrl'. Will UPDATE."
        $operation = 'UPDATE'
    }
}

# ---------------------------------------------------------------------------
# Step 3: PUT (if needed)
# ---------------------------------------------------------------------------
if ($shouldPut) {
    Write-Host "[create-a2a-connection] Step 3: PUT ($operation)..."
    $bodyObj = @{
        properties = @{
            category    = 'CustomKeys'
            target      = $TargetUrl
            authType    = 'CustomKeys'
            credentials = @{
                keys = @{
                    'x-api-key' = $ApiKey
                }
            }
            metadata    = @{
                a2a_subtype = $A2aSubtype
            }
        }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 6

    try {
        $putResp = Invoke-WebRequest -Uri $armUri -Method Put -Headers $headers -Body $body -UseBasicParsing -ErrorAction Stop
        $putContent = $putResp.Content | ConvertFrom-Json
        Write-Host "[create-a2a-connection]   PUT succeeded (HTTP $($putResp.StatusCode))."
    } catch {
        $statusCode = $null
        $errBody = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errBody = $reader.ReadToEnd()
            } catch { }
        }
        Write-Error ("[create-a2a-connection] PUT failed (HTTP {0}): {1}`n{2}" -f $statusCode, $_.Exception.Message, $errBody)
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 4: Verify final state with one more GET
# ---------------------------------------------------------------------------
Write-Host "[create-a2a-connection] Step 4: GET to verify final state..."
try {
    $verifyResp = Invoke-WebRequest -Uri $armUri -Method Get -Headers $headers -UseBasicParsing -ErrorAction Stop
    $verified = $verifyResp.Content | ConvertFrom-Json
    $finalTarget = [string]$verified.properties.target
    $finalId = [string]$verified.id
    if ($finalTarget -ne $TargetUrl) {
        Write-Error "[create-a2a-connection] Post-PUT verification FAILED: expected target '$TargetUrl', got '$finalTarget'"
        exit 1
    }
    Write-Host "[create-a2a-connection]   Verified. Final target: '$finalTarget'"
    Write-Host ""
    $result = [ordered]@{
        Operation      = $operation
        ConnectionId   = $finalId
        ConnectionName = $ConnectionName
        Target         = $finalTarget
    }
    # Print summary for human readers...
    Write-Host "[create-a2a-connection] Result:"
    Write-Host ("  Operation : {0}" -f $result.Operation)
    Write-Host ("  Target    : {0}" -f $result.Target)
    Write-Host ("  ID        : {0}" -f $result.ConnectionId)
    # ...and emit a JSON object on stdout for callers to parse.
    $result | ConvertTo-Json -Compress
    exit 0
} catch {
    Write-Error "[create-a2a-connection] Post-PUT verification GET failed: $($_.Exception.Message)"
    exit 1
}
