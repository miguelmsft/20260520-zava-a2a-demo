<#
.SYNOPSIS
    Verifies Azure prerequisites for the Zava A2A demo: model quota for gpt-5.5 +
    gpt-5.4-mini, and AKS Standard_D2s_v6 SKU availability in the target region.

.DESCRIPTION
    Read-only Azure CLI script. Calls `az cognitiveservices usage list` to inspect
    Azure OpenAI Global Standard quota for the two models the demo deploys, and
    `az vm list-skus` to confirm the AKS node SKU is available in the region.

    Exit codes:
      0 = at least one of the two paths is viable (primary gpt-5.5, or fallback
          gpt-5.4-mini-only with -UseGpt55:$false on deploy-infra.ps1)
      1 = neither path is viable, or a hard prerequisite failure occurred (az not
          logged in, region invalid, etc.)

    See research/2026-05-20-model-availability.md §7 for the quota matrix and the
    documented fallback path. See plan.md §C Step 14.

.PARAMETER Location
    Azure region to check. Default: eastus2 (the only US region where both gpt-5.5
    and gpt-5.4-mini are available as Global Standard per the model-availability
    research).

.PARAMETER SubscriptionId
    Optional. If provided, the script runs `az account set --subscription` before
    any other call so quota checks target the intended subscription.

.EXAMPLE
    ./scripts/verify-quota.ps1
    Run with defaults (eastus2, current az subscription).

.EXAMPLE
    ./scripts/verify-quota.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Verbose
    Switch subscription first, then verify with verbose diagnostics.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $Location = 'eastus2',

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionId
)

$ErrorActionPreference = 'Stop'

# Quota-name patterns published by the Cognitive Services usage API. Each Azure
# OpenAI model + SKU combination is reported with a `name.value` of the form
# `OpenAI.<SkuName>.<modelId>`. We match `OpenAI.GlobalStandard.<modelId>` since
# both demo deployments use Global Standard.
$primaryUsageName  = 'OpenAI.GlobalStandard.gpt-5.5'
$fallbackUsageName = 'OpenAI.GlobalStandard.gpt-5.4-mini'
$aksNodeSku        = 'Standard_D2s_v6'

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Test-AzCli {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        Write-Host '❌ Azure CLI (`az`) is not on PATH. Install from https://aka.ms/azcli and re-run.' -ForegroundColor Red
        exit 1
    }
}

function Get-AzContext {
    # Returns the parsed `az account show` object, or exits with a clear message
    # if the user is not logged in.
    try {
        $raw = az account show --output json 2>$null
    }
    catch {
        $raw = $null
    }
    if (-not $raw) {
        Write-Host '❌ Not logged in to Azure CLI. Run `az login` and re-run this script.' -ForegroundColor Red
        exit 1
    }
    return ($raw | ConvertFrom-Json)
}

function Get-CognitiveUsageEntry {
    param(
        [Parameter(Mandatory = $true)] [object[]] $Usage,
        [Parameter(Mandatory = $true)] [string]   $QuotaName
    )
    # The usage API returns each quota as { name: { value: '...' }, currentValue, limit, unit }.
    # We do a case-insensitive exact match on name.value.
    foreach ($entry in $Usage) {
        if ($null -ne $entry.name -and $entry.name.value -ieq $QuotaName) {
            return $entry
        }
    }
    return $null
}

function Format-QuotaLine {
    param(
        [Parameter(Mandatory = $true)] [string] $Label,
        [Parameter(Mandatory = $false)] $Entry
    )
    if ($null -eq $Entry) {
        return "{0,-40} : not reported in this region" -f $Label
    }
    $current   = [double]($Entry.currentValue)
    $limit     = [double]($Entry.limit)
    $available = [Math]::Max(0, $limit - $current)
    $unit      = if ($Entry.unit) { $Entry.unit } else { 'Count' }
    return ("{0,-40} : limit={1}  current={2}  available={3}  ({4})" -f `
        $Label, $limit, $current, $available, $unit)
}

# -----------------------------------------------------------------------------
# 1. Pre-flight
# -----------------------------------------------------------------------------
Test-AzCli

if ($SubscriptionId) {
    Write-Verbose "Setting active subscription to $SubscriptionId"
    az account set --subscription $SubscriptionId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to set subscription $SubscriptionId." -ForegroundColor Red
        exit 1
    }
}

$ctx = Get-AzContext

Write-Section 'Azure Context'
Write-Host ("Subscription : {0} ({1})" -f $ctx.name, $ctx.id)
Write-Host ("Tenant       : {0}" -f $ctx.tenantId)
Write-Host ("User         : {0}" -f $ctx.user.name)
Write-Host ("Target region: {0}" -f $Location)

# -----------------------------------------------------------------------------
# 2. Cognitive Services / Azure OpenAI quota
# -----------------------------------------------------------------------------
Write-Section "Azure OpenAI Quota (region: $Location)"

Write-Verbose "az cognitiveservices usage list --location $Location"
$usageJson = az cognitiveservices usage list --location $Location --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ `az cognitiveservices usage list` failed:" -ForegroundColor Red
    Write-Host $usageJson -ForegroundColor Red
    Write-Host ''
    Write-Host 'Common causes:' -ForegroundColor Yellow
    Write-Host '  - The subscription has never registered Microsoft.CognitiveServices.'
    Write-Host '    Fix: az provider register --namespace Microsoft.CognitiveServices'
    Write-Host '  - The selected subscription does not have access to Azure OpenAI in this region.'
    exit 1
}

try {
    $usage = $usageJson | ConvertFrom-Json
}
catch {
    Write-Host '❌ Could not parse cognitive services usage JSON.' -ForegroundColor Red
    Write-Host $usageJson
    exit 1
}

$primaryEntry  = Get-CognitiveUsageEntry -Usage $usage -QuotaName $primaryUsageName
$fallbackEntry = Get-CognitiveUsageEntry -Usage $usage -QuotaName $fallbackUsageName

Write-Host (Format-QuotaLine -Label 'gpt-5.5      (Global Standard)' -Entry $primaryEntry)
Write-Host (Format-QuotaLine -Label 'gpt-5.4-mini (Global Standard)' -Entry $fallbackEntry)

# Compute available headroom = limit - currentValue. Readiness is based on
# this, NOT on raw limit (which can be > 0 even when fully consumed).
function Get-Available {
    param($Entry)
    if ($null -eq $Entry) { return 0 }
    $limit   = [double]($Entry.limit)
    $current = [double]($Entry.currentValue)
    return [Math]::Max(0, $limit - $current)
}
$primaryAvailable  = Get-Available -Entry $primaryEntry
$fallbackAvailable = Get-Available -Entry $fallbackEntry

# Minimum capacity required (in thousands TPM). gpt-5.5 deploys at capacity=1
# (=1k TPM), gpt-5.4-mini at capacity=10. We require at least the deployment
# size + a small headroom buffer.
$minPrimaryCapacity  = 1   # gpt-5.5 (orchestrator)
$minWorkerCapacity   = 10  # gpt-5.4-mini (worker in primary, both deployments in fallback)
$minFallbackCapacity = 20  # 2 × worker (orchestrator + worker share the same model in fallback path)

# -----------------------------------------------------------------------------
# 3. AKS SKU availability
# -----------------------------------------------------------------------------
Write-Section "AKS Node SKU Availability ($aksNodeSku in $Location)"

Write-Verbose "az vm list-skus --location $Location --size $aksNodeSku"
$skuJson = az vm list-skus --location $Location --size $aksNodeSku --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ `az vm list-skus` failed; cannot verify AKS node SKU." -ForegroundColor Yellow
    Write-Host $skuJson -ForegroundColor Yellow
    $skuAvailable = $false
}
else {
    try {
        $skus = $skuJson | ConvertFrom-Json
    }
    catch {
        $skus = @()
    }
    $matching = @($skus | Where-Object { $_.name -ieq $aksNodeSku })
    if ($matching.Count -eq 0) {
        Write-Host "⚠ $aksNodeSku not listed in $Location." -ForegroundColor Yellow
        $skuAvailable = $false
    }
    else {
        # Look for any restriction entry that would prevent the demo using this SKU.
        $restrictions = @()
        foreach ($s in $matching) {
            if ($s.restrictions) {
                foreach ($r in $s.restrictions) {
                    $restrictions += $r
                }
            }
        }
        if ($restrictions.Count -gt 0) {
            Write-Host "⚠ $aksNodeSku is RESTRICTED in ${Location}:" -ForegroundColor Yellow
            foreach ($r in $restrictions) {
                Write-Host ("   - {0} ({1})" -f $r.reasonCode, ($r.values -join ',')) -ForegroundColor Yellow
            }
            $skuAvailable = $false
        }
        else {
            Write-Host "✓ $aksNodeSku is available in $Location with no restrictions." -ForegroundColor Green
            $skuAvailable = $true
        }
    }
}

# -----------------------------------------------------------------------------
# 4. Decision
# -----------------------------------------------------------------------------
Write-Section 'Decision'

$primaryReady  = ($primaryAvailable  -ge $minPrimaryCapacity) -and ($fallbackAvailable -ge $minWorkerCapacity)
$fallbackReady = ($fallbackAvailable -ge $minFallbackCapacity)

if (-not $skuAvailable) {
    Write-Host "⚠ AKS SKU $aksNodeSku is not confirmed in $Location. Choose a different SKU in infra/modules/aks.bicep or a different region before deploying." -ForegroundColor Yellow
}

if ($primaryReady) {
    Write-Host ("✓ PRIMARY PATH READY (useGpt55=true). gpt-5.5 available={0}, gpt-5.4-mini available={1}." -f $primaryAvailable, $fallbackAvailable) -ForegroundColor Green
    Write-Host '  → Run: ./scripts/deploy-infra.ps1 -DnsZoneName <your.zone>'
    exit 0
}
elseif ($fallbackReady) {
    Write-Host ("⚠ FALLBACK PATH AVAILABLE (set useGpt55=false). gpt-5.5 available={0} (need {1}); gpt-5.4-mini available={2} (need {3})." -f $primaryAvailable, $minPrimaryCapacity, $fallbackAvailable, $minFallbackCapacity) -ForegroundColor Yellow
    Write-Host '  Both agents will run on gpt-5.4-mini (with distinct deployment names — see plan §F R1).'
    Write-Host '  → Run: ./scripts/deploy-infra.ps1 -DnsZoneName <your.zone> -UseGpt55:$false'
    Write-Host ''
    Write-Host '  To unlock the primary path, request gpt-5.5 quota in the Azure portal:'
    Write-Host '    Foundry portal → Management center → Quotas → request increase for gpt-5.5 GlobalStandard.'
    exit 0
}
else {
    Write-Host '❌ NEITHER PATH AVAILABLE. Both gpt-5.5 and gpt-5.4-mini Global Standard quotas are 0 in this subscription/region.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Remediation:' -ForegroundColor Yellow
    Write-Host '  1. Request quota: Azure portal → Foundry portal → Management center → Quotas → request increase.'
    Write-Host '  2. Or switch to a subscription that already has quota (Tier 5+ for gpt-5.5).'
    Write-Host '  3. Or change the target region (gpt-5.5 is limited to East US 2 and South Central US for Global Standard).'
    exit 1
}
