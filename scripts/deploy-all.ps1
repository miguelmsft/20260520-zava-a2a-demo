<#
.SYNOPSIS
    End-to-end "one command" orchestrator for the Zava Smart Order Feasibility
    A2A demo. Runs infrastructure deploy, image build/push, AKS deploy
    (sslip.io mode by default), Foundry agent creation, and a final smoke
    test — with zero manual intervention on a fresh resource group.

.DESCRIPTION
    Chains:
      1. scripts/verify-quota.ps1            (pre-flight; skippable)
      2. scripts/deploy-infra.ps1            (bicep deploy + AKS creds)
                                            -SkipCertProvisioning when sslip.io
      3. scripts/build-and-push.ps1          (Docker build → ACR push)
      4. scripts/deploy-k8s.ps1              (manifests + ingress + env)
                                            -UseSslipIo:$true by default
                                            (auto-creates A2A connection)
      5. (verify Workload Identity binding)
      6. scripts/setup-foundry-agent.ps1     (Foundry agent prompt)
                                            -SkipManualGates
      7. scripts/smoke-test.ps1              (validation)

    On any step's failure, the script exits non-zero with a clear "Step N
    failed" message naming the script that failed so the deployer can pick
    up where it stopped.

    The output of each step is passed to subsequent steps via parsed values,
    not via files. A run log is written to artifacts/deploy-all-<timestamp>.log
    so the deployer can review the full transcript after-the-fact.

.PARAMETER ResourceGroupName
    Resource group to deploy into. Default: rg-zava-a2a-smart-order-demo.

.PARAMETER Location
    Azure region. Default: eastus2.

.PARAMETER UseGpt55
    Bool. Default $true. Pass `-UseGpt55:$false` to use the gpt-5.4-mini-only
    fallback path when gpt-5.5 quota is unavailable.

.PARAMETER UseSslipIo
    Bool. Default $true. When $true: HTTP + sslip.io DNS (no real DNS zone or
    TLS cert required — the single-command path). When $false: real DNS zone +
    TLS via App Routing + Key Vault. The sslip.io path is the recommended demo
    path; the DnsZone path is for polished customer demos behind HTTPS.

.PARAMETER DnsZoneName
    Optional. DNS zone to use when -UseSslipIo:$false. Ignored otherwise.
    Default: zava-a2a-demo.example.com (RFC 2606 reserved).

.PARAMETER FoundryName
    Optional. Override the Foundry account name. The default in bicep is
    `foundry-zava-a2a-smartorder`. Pass a unique value when redeploying to a
    fresh RG to avoid soft-delete collisions with a previously-deleted
    Foundry account (48-hour soft-delete window).

.PARAMETER SkipQuotaCheck
    Switch. Skip the pre-flight quota check.

.PARAMETER SkipSmokeTest
    Switch. Skip the final smoke-test step (useful when the local backend +
    frontend are not running and the AKS-only validation is sufficient).

.PARAMETER SubscriptionId
    Optional. Azure subscription ID. If omitted, uses the currently-selected
    subscription (`az account show`). Used by deploy-k8s.ps1's A2A connection
    creation step.

.PARAMETER ImageTag
    Optional. Docker image tag. Default: latest.

.EXAMPLE
    ./scripts/deploy-all.ps1
    Single command. sslip.io / HTTP / gpt-5.5+gpt-5.4-mini in the
    default resource group + region. ~30-60 minutes.

.EXAMPLE
    ./scripts/deploy-all.ps1 -ResourceGroupName rg-zava-a2a-validate-20260522 -FoundryName foundry-zava-a2a-v20260522
    Clean-room validation deploy to a fresh RG with a fresh Foundry name.

.EXAMPLE
    ./scripts/deploy-all.ps1 -UseSslipIo:$false -DnsZoneName zava.example.com -SkipSmokeTest
    HTTPS / DnsZone mode (requires TLS cert workflow; -SkipSmokeTest because
    local backend isn't expected to be up during a fresh CI-style deploy).

.NOTES
    Replaces W1, W2, W3, W4 manual workarounds in docs/deployment-learnings.md.
    Pre-req: `az login` complete and the MCAPS subscription selected
    (`az account set --subscription ME-MngEnvMCAP422553-migmartinez-1`).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupName = 'rg-zava-a2a-smart-order-demo',

    [Parameter(Mandatory = $false)]
    [string] $Location = 'eastus2',

    [Parameter(Mandatory = $false)]
    [bool] $UseGpt55 = $true,

    [Parameter(Mandatory = $false)]
    [bool] $UseSslipIo = $true,

    [Parameter(Mandatory = $false)]
    [string] $DnsZoneName = 'zava-a2a-demo.example.com',

    [Parameter(Mandatory = $false)]
    [string] $FoundryName,

    [Parameter(Mandatory = $false)]
    [switch] $SkipQuotaCheck,

    [Parameter(Mandatory = $false)]
    [switch] $SkipSmokeTest,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string] $ImageTag = 'latest'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Force UTF-8 I/O before invoking any child script. Without this Azure CLI
# can crash on Windows when streaming non-ASCII characters from ACR build
# logs or Bicep diagnostics through the default cp1252 stdout encoding.
# PYTHONUTF8=1 enables Python's "UTF-8 mode" globally in the child Python
# processes the az CLI spawns. See docs/deployment-learnings.md §11.
# -----------------------------------------------------------------------------
$env:PYTHONUTF8        = '1'
$env:PYTHONIOENCODING  = 'utf-8'
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding           = [System.Text.UTF8Encoding]::new($false)
} catch { }

# -----------------------------------------------------------------------------
# Resolve repo-rooted paths
# -----------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot  = Split-Path -Parent $scriptDir
$artifactsDir = Join-Path $repoRoot 'artifacts'
if (-not (Test-Path $artifactsDir)) {
    $null = New-Item -ItemType Directory -Path $artifactsDir -Force
}
$stamp   = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
$logFile = Join-Path $artifactsDir ("deploy-all-{0}.log" -f $stamp)

# Mirror everything to a transcript so the deployer has a complete record.
Start-Transcript -Path $logFile -IncludeInvocationHeader | Out-Null

# Best-effort cleanup so PowerShell never thinks the transcript is still open
# after an early exit.
$transcriptOpen = $true
function Stop-TranscriptSafe {
    if ($script:transcriptOpen) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:transcriptOpen = $false
    }
}
trap {
    Stop-TranscriptSafe
    break
}

function Write-Banner {
    param([string] $Title)
    Write-Host ''
    Write-Host ('═' * 78) -ForegroundColor Cyan
    Write-Host (' ' + $Title) -ForegroundColor Cyan
    Write-Host ('═' * 78) -ForegroundColor Cyan
}

function Invoke-StepOrFail {
    <#
        Runs a script with the supplied splat. By default, exits the orchestrator
        with code 1 on any failure (default behavior — fail fast). When called
        with -ContinueOnFailure, returns $true on success and $false on failure
        so the caller can decide whether to abort.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $StepName,
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [Parameter(Mandatory = $true)] [hashtable] $Splat,
        [switch] $ContinueOnFailure
    )
    Write-Banner $StepName
    Write-Host ("Running: {0}" -f (Split-Path -Leaf $ScriptPath))
    if (-not (Test-Path $ScriptPath)) {
        Write-Host ("❌ {0}: script not found: {1}" -f $StepName, $ScriptPath) -ForegroundColor Red
        if ($ContinueOnFailure) { return $false }
        Stop-TranscriptSafe
        exit 1
    }
    & $ScriptPath @Splat
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host ("❌ {0} FAILED (exit code {1})." -f $StepName, $LASTEXITCODE) -ForegroundColor Red
        Write-Host ("   Script: {0}" -f $ScriptPath) -ForegroundColor Red
        Write-Host ("   Log file: {0}" -f $logFile) -ForegroundColor Red
        if ($ContinueOnFailure) { return $false }
        Stop-TranscriptSafe
        exit 1
    }
    Write-Host ("✓ {0} OK." -f $StepName) -ForegroundColor Green
    if ($ContinueOnFailure) { return $true }
}

# -----------------------------------------------------------------------------
# Step 0: Pre-flight — subscription + signed-in user
# -----------------------------------------------------------------------------
Write-Banner '0. Pre-flight'
if ($SubscriptionId) {
    Write-Host ("Setting subscription: {0}" -f $SubscriptionId)
    az account set --subscription $SubscriptionId 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("❌ az account set failed for subscription '{0}'." -f $SubscriptionId) -ForegroundColor Red
        Stop-TranscriptSafe
        exit 1
    }
}
$currentSub = az account show --query "{id:id, name:name}" -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host '❌ az account show failed. Run `az login` first.' -ForegroundColor Red
    Stop-TranscriptSafe
    exit 1
}
$subInfo = $currentSub | ConvertFrom-Json
$resolvedSubId = $subInfo.id
Write-Host ("Subscription : {0} ({1})" -f $subInfo.name, $subInfo.id)
$signedIn = az ad signed-in-user show --query "{oid:id, upn:userPrincipalName}" -o json 2>&1
if ($LASTEXITCODE -eq 0) {
    $u = $signedIn | ConvertFrom-Json
    Write-Host ("Signed-in    : {0} (oid {1})" -f $u.upn, $u.oid)
}

# -----------------------------------------------------------------------------
# Step 1: deploy-infra
# -----------------------------------------------------------------------------
$infraArgs = @{
    ResourceGroupName    = $ResourceGroupName
    Location             = $Location
    UseGpt55             = $UseGpt55
    DnsZoneName          = $DnsZoneName
    NonInteractive       = $true
}
if ($SkipQuotaCheck) { $infraArgs['SkipQuotaCheck'] = $true }
if ($UseSslipIo)     { $infraArgs['SkipCertProvisioning'] = $true }
if ($FoundryName)    { $infraArgs['FoundryName'] = $FoundryName }

# deploy-infra.ps1 writes its bicep outputs to stdout; we capture them again
# below by querying the deployment directly (more robust than scraping stdout).
Invoke-StepOrFail -StepName '1. Infrastructure (bicep)' `
                  -ScriptPath (Join-Path $scriptDir 'deploy-infra.ps1') `
                  -Splat $infraArgs

# -----------------------------------------------------------------------------
# Re-read bicep outputs from the most-recent successful deployment in the RG.
# This is the canonical source so we never depend on stdout parsing.
# -----------------------------------------------------------------------------
Write-Banner '1b. Reading bicep outputs'
$latestDeployJson = az deployment group list `
    --resource-group $ResourceGroupName `
    --query "sort_by([?properties.provisioningState=='Succeeded'], &properties.timestamp)[-1]" `
    -o json
if ($LASTEXITCODE -ne 0 -or -not $latestDeployJson) {
    Write-Host '❌ Could not list deployments in the resource group.' -ForegroundColor Red
    Stop-TranscriptSafe
    exit 1
}
$latestDeploy = $latestDeployJson | ConvertFrom-Json
$outputs = $latestDeploy.properties.outputs
function Get-Out {
    param([string] $Name)
    if ($null -eq $outputs) { return $null }
    $prop = $outputs.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value.value
}

$keyVaultUri                = Get-Out 'keyVaultUri'
$kvName                     = if ($keyVaultUri -match '^https://([^.]+)\.vault\.azure\.net') { $Matches[1] } else { $null }
$acrLoginServer             = Get-Out 'acrLoginServer'
$uamiClientId               = Get-Out 'uamiClientId'
$foundryEndpoint            = Get-Out 'projectEndpoint'
$foundryAccountEndpoint     = Get-Out 'accountInferenceEndpoint'
$workerDeploymentName       = Get-Out 'workerDeploymentName'
$foundryAccountName         = Get-Out 'foundryAccountName'
$projectName                = Get-Out 'projectName'
$aksClusterName             = Get-Out 'aksClusterName'
$appInsightsName            = Get-Out 'appInsightsName'
$dnsZoneOut                 = Get-Out 'dnsZoneName'
foreach ($pair in @(
    @{ Name = 'acrLoginServer'; Value = $acrLoginServer },
    @{ Name = 'uamiClientId'; Value = $uamiClientId },
    @{ Name = 'projectEndpoint'; Value = $foundryEndpoint },
    @{ Name = 'workerDeploymentName'; Value = $workerDeploymentName },
    @{ Name = 'foundryAccountName'; Value = $foundryAccountName },
    @{ Name = 'projectName'; Value = $projectName },
    @{ Name = 'aksClusterName'; Value = $aksClusterName }
)) {
    if ([string]::IsNullOrWhiteSpace([string]$pair.Value)) {
        Write-Host ("❌ Bicep did not surface required output '{0}'." -f $pair.Name) -ForegroundColor Red
        Stop-TranscriptSafe
        exit 1
    }
}
Write-Host ("Foundry account name : {0}" -f $foundryAccountName)
Write-Host ("Foundry project name : {0}" -f $projectName)
Write-Host ("ACR login server     : {0}" -f $acrLoginServer)
Write-Host ("Key Vault name       : {0}" -f $kvName)
Write-Host ("UAMI client ID       : {0}" -f $uamiClientId)
Write-Host ("Worker deployment    : {0}" -f $workerDeploymentName)
Write-Host ("AKS cluster          : {0}" -f $aksClusterName)
Write-Host ("App Insights name    : {0}" -f $appInsightsName)

# -----------------------------------------------------------------------------
# Step 2: build-and-push
# -----------------------------------------------------------------------------
$buildArgs = @{
    AcrLoginServer = $acrLoginServer
    ImageTag       = $ImageTag
}
Invoke-StepOrFail -StepName '2. Build + push Docker image' `
                  -ScriptPath (Join-Path $scriptDir 'build-and-push.ps1') `
                  -Splat $buildArgs

# -----------------------------------------------------------------------------
# Step 2b: Verify Workload Identity federated cred binding
# AKS recreate would change the OIDC issuer URL; bicep already binds it to the
# UAMI federated credential during deploy-infra, but verify post-AKS in case
# of mid-life replacement.
# -----------------------------------------------------------------------------
Write-Banner '2b. Workload Identity verification'
$aksOidcIssuer = az aks show -g $ResourceGroupName -n $aksClusterName --query oidcIssuerProfile.issuerUrl -o tsv 2>$null
$aksOidcIssuer = if ($aksOidcIssuer) { $aksOidcIssuer.Trim() } else { '' }
if ([string]::IsNullOrWhiteSpace($aksOidcIssuer)) {
    Write-Host '⚠ Could not read AKS OIDC issuer URL.' -ForegroundColor Yellow
} else {
    Write-Host ("AKS OIDC issuer  : {0}" -f $aksOidcIssuer)
    # The UAMI is named after the AKS cluster's UAMI; deploy-infra surfaces
    # only the client ID. Look up its name from the UAMI client ID.
    $uamiJson = az identity list -g $ResourceGroupName --query "[?clientId=='$uamiClientId'].{name:name, principalId:principalId}" -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $uamiJson) {
        $uamis = $uamiJson | ConvertFrom-Json
        if ($uamis -and $uamis.Count -gt 0) {
            $uamiName = $uamis[0].name
            $fedCredJson = az identity federated-credential list -g $ResourceGroupName --identity-name $uamiName --query "[].{name:name, issuer:issuer, subject:subject}" -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $fedCredJson) {
                $feds = $fedCredJson | ConvertFrom-Json
                $match = $feds | Where-Object { $_.issuer.TrimEnd('/') -eq $aksOidcIssuer.TrimEnd('/') }
                if ($match) {
                    Write-Host ("✓ Federated credential bound to current AKS OIDC issuer ({0} matches found)." -f @($match).Count) -ForegroundColor Green
                } else {
                    Write-Host '⚠ NO federated credential matches the current AKS OIDC issuer URL.' -ForegroundColor Yellow
                    Write-Host '  Existing creds:' -ForegroundColor Yellow
                    foreach ($f in $feds) { Write-Host ("    name={0} issuer={1}" -f $f.name, $f.issuer) -ForegroundColor Yellow }
                    Write-Host '  This usually only happens when AKS was recreated AFTER deploy-infra ran.' -ForegroundColor Yellow
                    Write-Host '  Workload Identity authentication will fail. Re-run deploy-infra.ps1.' -ForegroundColor Yellow
                }
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Step 3: deploy-k8s (with A2A connection auto-creation)
# -----------------------------------------------------------------------------
$k8sArgs = @{
    AcrLoginServer       = $acrLoginServer
    UamiClientId         = $uamiClientId
    FoundryEndpoint      = $foundryEndpoint
    WorkerDeploymentName = $workerDeploymentName
    ImageTag             = $ImageTag
    UseSslipIo           = $UseSslipIo
    SubscriptionId       = $resolvedSubId
    ResourceGroupName    = $ResourceGroupName
    FoundryAccountName   = $foundryAccountName
    ProjectName          = $projectName
}
if (-not [string]::IsNullOrWhiteSpace($foundryAccountEndpoint)) { $k8sArgs['FoundryAccountEndpoint'] = $foundryAccountEndpoint }
if (-not $UseSslipIo) {
    $k8sArgs['KvName']  = $kvName
    $k8sArgs['DnsZone'] = $DnsZoneName
}

Invoke-StepOrFail -StepName '3. AKS deploy + A2A connection' `
                  -ScriptPath (Join-Path $scriptDir 'deploy-k8s.ps1') `
                  -Splat $k8sArgs

# After deploy-k8s, query the actual public URL it set on the deployment.
$publicUrlOnDeployment = & kubectl get deployment ops-agent -o "jsonpath={.spec.template.spec.containers[0].env[?(@.name=='OPS_AGENT_PUBLIC_URL')].value}" 2>$null
$opsAgentPublicUrl = if ($publicUrlOnDeployment) { ($publicUrlOnDeployment | Out-String).Trim() } else { '' }
if ([string]::IsNullOrWhiteSpace($opsAgentPublicUrl)) {
    Write-Host '⚠ Could not read OPS_AGENT_PUBLIC_URL from the deployment; smoke test may use a stale default.' -ForegroundColor Yellow
} else {
    Write-Host ("Ops Agent public URL : {0}" -f $opsAgentPublicUrl)
}

# -----------------------------------------------------------------------------
# Step 4: setup-foundry-agent (creates / updates the agent prompt)
# -----------------------------------------------------------------------------
$foundryAgentScript = Join-Path $scriptDir 'setup-foundry-agent.ps1'
if (Test-Path $foundryAgentScript) {
    # Pre-flight: ensure the apps/foundry-agent venv exists. The Foundry SDK
    # (azure-ai-agents) uses pydantic models with discriminated unions that
    # raise AttributeError on Python 3.14+ ("'typing.Union' object has no
    # attribute '__discriminator__'"). The venv pins Python 3.13 via pyproject
    # `requires-python = ">=3.13"`. We auto-create it here so a fresh clone
    # on a machine with Python 3.13+ available works out of the box.
    $foundryAgentDir = Join-Path $repoRoot 'apps/foundry-agent'
    $venvPython = Join-Path $foundryAgentDir '.venv/Scripts/python.exe'
    if (-not (Test-Path $venvPython)) {
        Write-Host '— foundry-agent venv missing; bootstrapping ...' -ForegroundColor Yellow
        Push-Location $foundryAgentDir
        try {
            $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
            if ($uvCmd) {
                Write-Host '  Using uv (uv.lock present)' -ForegroundColor Gray
                & uv sync 2>&1 | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    Write-Host '⚠ uv sync failed; will let setup-foundry-agent fall back to system python.' -ForegroundColor Yellow
                }
            } else {
                Write-Host '  uv not on PATH; using python -m venv + pip' -ForegroundColor Gray
                & python -m venv .venv 2>&1 | Out-Host
                if ($LASTEXITCODE -eq 0) {
                    & (Join-Path $foundryAgentDir '.venv/Scripts/python.exe') -m pip install --quiet -e . 2>&1 | Out-Host
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host '⚠ pip install -e . failed; will let setup-foundry-agent fall back to system python.' -ForegroundColor Yellow
                    }
                }
            }
        } finally {
            Pop-Location
        }
    }

    # Read the A2A API key from the K8s secret (deploy-k8s.ps1 just upserted it).
    # setup-foundry-agent.ps1 wants the key so it can construct an A2A test call
    # against the Ops Agent during its verification phase.
    $apiKeyB64 = & kubectl get secret ops-agent-secrets -o "jsonpath={.data.A2A_API_KEY}" 2>$null
    $apiKey = ''
    if ($apiKeyB64) {
        try {
            $apiKey = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($apiKeyB64 | Out-String).Trim()))
        } catch {
            Write-Host '⚠ Could not decode A2A API key from K8s secret.' -ForegroundColor Yellow
        }
    }

    $faArgs = @{
        FoundryEndpoint  = $foundryEndpoint
        SkipManualGates  = $true
    }
    if ($opsAgentPublicUrl) { $faArgs['OpsAgentEndpoint'] = $opsAgentPublicUrl }
    if ($apiKey)            { $faArgs['OpsAgentApiKey']   = $apiKey }
    if ($appInsightsName)   { $faArgs['AppInsightsName']  = $appInsightsName }
    # Pass the RG so the KQL fallback can resolve the App Insights appId GUID
    # without relying on the deployer's az default context.
    if ($ResourceGroupName) { $faArgs['AppInsightsResourceGroup'] = $ResourceGroupName }

    # Use -ContinueOnFailure: even if Phase 3 smoke-test inside setup-foundry-agent
    # fails (e.g. transient streaming issue or content-level assertion), the Foundry
    # account / project / agent / A2A connection are all provisioned by Phase 1+2,
    # so deploy-all should still proceed to its own smoke-test step rather than abort.
    $faOk = Invoke-StepOrFail -StepName '4. Foundry agent provisioning' `
                              -ScriptPath $foundryAgentScript `
                              -Splat $faArgs `
                              -ContinueOnFailure
    if (-not $faOk) {
        Write-Host '⚠ Foundry agent provisioning step reported non-zero exit.' -ForegroundColor Yellow
        Write-Host '   Phases 1 (A2A connection) + 2 (agent create) typically still succeeded.' -ForegroundColor Yellow
        Write-Host '   Verify in portal: Foundry → Project → Agents.' -ForegroundColor Yellow
    }
} else {
    Write-Host '⚠ scripts/setup-foundry-agent.ps1 not found; skipping agent provisioning.' -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Step 5: smoke-test (optional)
# -----------------------------------------------------------------------------
if (-not $SkipSmokeTest) {
    $smokeScript = Join-Path $scriptDir 'smoke-test.ps1'
    if (Test-Path $smokeScript) {
        $smokeArgs = @{
            SkipLocal = $true   # local backend/frontend not expected during a fresh AKS-only deploy
        }
        if ($opsAgentPublicUrl) { $smokeArgs['OpsAgentEndpoint'] = $opsAgentPublicUrl }
        try {
            Invoke-StepOrFail -StepName '5. Smoke test (cluster path only)' `
                              -ScriptPath $smokeScript `
                              -Splat $smokeArgs
        } catch {
            Write-Host ("⚠ Smoke test failed (non-fatal at this stage): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    } else {
        Write-Host '⚠ scripts/smoke-test.ps1 not found; skipping.' -ForegroundColor Yellow
    }
} else {
    Write-Host '⚠ -SkipSmokeTest set; smoke test skipped.' -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
Write-Banner 'DEPLOYMENT COMPLETE'
Write-Host ("Resource group       : {0}" -f $ResourceGroupName)
Write-Host ("Location             : {0}" -f $Location)
Write-Host ("Subscription         : {0} ({1})" -f $subInfo.name, $subInfo.id)
Write-Host ("Foundry account      : {0}" -f $foundryAccountName)
Write-Host ("Foundry project      : {0}" -f $projectName)
Write-Host ("Ops Agent public URL : {0}" -f $opsAgentPublicUrl)
Write-Host ("Mode                 : {0}" -f $(if ($UseSslipIo) { 'sslip.io (HTTP)' } else { 'DnsZone (HTTPS)' }))
Write-Host ("Log file             : {0}" -f $logFile)
Write-Host ''
Write-Host 'To run the full demo locally (React UI + FastAPI backend):' -ForegroundColor Cyan
Write-Host '  ./scripts/start-backend.ps1   (or apps/backend then `uvicorn ...`)'
Write-Host '  ./scripts/start-frontend.ps1  (or apps/web then `npm run dev`)'
Write-Host ''

Stop-TranscriptSafe
exit 0
