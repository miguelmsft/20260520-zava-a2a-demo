<#
.SYNOPSIS
    Renders and applies the Ops Agent Kubernetes manifests to the AKS cluster,
    generates and upserts the A2A API key Secret, waits for the rollout, and
    (in sslip.io mode) automatically creates/updates the Foundry-side A2A
    connection so the Foundry Customer Service Agent can call this Ops Agent
    end-to-end without manual portal work.

.DESCRIPTION
    Inputs come from the outputs of scripts/deploy-infra.ps1 (Step 14) and the
    image produced by scripts/build-and-push.ps1.

    Two deployment modes:

    1. **sslip.io mode (default — `-UseSslipIo:$true`)**
       Uses the free sslip.io public DNS service so no real DNS zone is
       required. Flow:
         a. Generate / upsert the A2A API key Secret.
         b. Render & apply deployment + service (with a placeholder
            OPS_AGENT_PUBLIC_URL).
         c. Apply the sslip ingress template with a literal placeholder
            host so the App Routing add-on provisions an LB.
         d. Poll the ingress until the LoadBalancer IP surfaces (≤5 min).
         e. Compute `ops-agent.<ip-dashed>.sslip.io` and assert IPv4.
         f. Re-render and re-apply the sslip ingress with the real host.
         g. `kubectl set env` OPS_AGENT_PUBLIC_URL=http://<sslip>/ on the
            deployment, then wait for the rollout to pick up the new env.
         h. Optionally call scripts/create-a2a-connection.ps1 to PUT the
            A2A connection on the Foundry project (idempotent —
            CREATE / UPDATE / NOOP based on current state).
       This mode eliminates W1, W2, and W3 from
       docs/deployment-learnings.md.

    2. **DnsZone mode (`-UseSslipIo:$false`)**
       Uses a real DNS zone (e.g., `zava-demo.example.com`) and TLS via
       App Routing's Key Vault cert sync. Requires -DnsZone and the
       tls-cert-ops-agent certificate to already exist in Key Vault.
       Same A2A connection auto-creation when -SubscriptionId/-ResourceGroupName/
       -FoundryAccountName/-ProjectName are provided.

    Idempotency: re-running with the same inputs is safe. The Secret upsert,
    `kubectl apply`, and A2A connection PUT are all designed to no-op when
    inputs haven't changed. The deployment env override is a kubectl set env
    that triggers a rollout only when the value actually differs (kubectl set
    env behavior).

.PARAMETER AcrLoginServer
    REQUIRED. Fully-qualified ACR login server (e.g.,
    `acrzavaa2asmartorderabc123.azurecr.io`). Source: deploy-infra.ps1 summary.

.PARAMETER KvName
    Optional. Key Vault resource name (without the URI). Required when
    -UseSslipIo:$false (the TLS path needs the cert URL). Source:
    deploy-infra.ps1 summary ("Key Vault name").

.PARAMETER DnsZone
    Optional. Public DNS zone (e.g., `zava-demo.example.com`). Required when
    -UseSslipIo:$false. Ignored in sslip.io mode. Source: deploy-infra.ps1
    summary ("DNS zone").

.PARAMETER UamiClientId
    REQUIRED. Client ID (GUID) of the User-Assigned Managed Identity that the
    ops-agent ServiceAccount federates with via Workload Identity. Source:
    deploy-infra.ps1 summary ("UAMI client ID").

.PARAMETER FoundryEndpoint
    REQUIRED. Foundry project endpoint, e.g.,
    `https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility`.
    Source: deploy-infra.ps1 summary ("Foundry project endpoint").

.PARAMETER FoundryAccountEndpoint
    Optional. Foundry account inference endpoint (Azure OpenAI-compatible base
    URL). If omitted, derived by stripping `/api/projects/...` from
    -FoundryEndpoint.

.PARAMETER WorkerDeploymentName
    REQUIRED. Name of the model deployment the LangGraph worker calls
    (e.g., `gpt-54mini-worker`). Source: deploy-infra.ps1 summary.

.PARAMETER ImageTag
    Optional. Image tag to deploy. Default `latest`.

.PARAMETER A2aApiKey
    Optional. Pre-generated A2A API key. If omitted, generated here.

.PARAMETER Namespace
    Optional. Kubernetes namespace. Default `default`.

.PARAMETER KeepRendered
    Switch. Keep the rendered manifests directory for debugging. Default $false.

.PARAMETER UseSslipIo
    Optional. Default $true. When $true, use sslip.io DNS + HTTP (no real DNS
    zone or TLS certificate required). When $false, use -DnsZone + TLS via
    App Routing + Key Vault.

.PARAMETER SubscriptionId
    Optional. Azure subscription ID hosting the Foundry account. Required for
    automatic A2A connection creation. If omitted (and -SkipA2aConnection is
    not set), the script prints a warning and skips the A2A connection step,
    leaving it to be performed manually via the Foundry portal (legacy flow).

.PARAMETER ResourceGroupName
    Optional. Resource group containing the Foundry account. Required for
    A2A connection creation.

.PARAMETER FoundryAccountName
    Optional. Microsoft.CognitiveServices/accounts (Foundry V2) account name.
    Required for A2A connection creation.

.PARAMETER ProjectName
    Optional. Foundry V2 project name. Required for A2A connection creation.

.PARAMETER A2aConnectionName
    Optional. Name of the A2A connection on the Foundry project. Default:
    `ops-agent-a2a`.

.PARAMETER SkipA2aConnection
    Switch. Explicitly skip the A2A connection step even if all parameters
    are present. Use to opt out of automation and create the connection
    manually later.

.PARAMETER ForceA2aConnection
    Switch. Forwarded to scripts/create-a2a-connection.ps1 as -Force.
    Use when rotating the A2A API key (PUT regardless of GET state).

.EXAMPLE
    ./scripts/deploy-k8s.ps1 `
        -AcrLoginServer acrzavaa2asmartorderabc123.azurecr.io `
        -UamiClientId 11111111-2222-3333-4444-555555555555 `
        -FoundryEndpoint https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility `
        -WorkerDeploymentName gpt-54mini-worker `
        -SubscriptionId c6a454a9-... `
        -ResourceGroupName rg-zava-a2a-smart-order-demo `
        -FoundryAccountName foundry-zava-a2a-smartorder `
        -ProjectName smart-order-feasibility
    (sslip.io mode, A2A connection auto-created — single command)

.EXAMPLE
    ./scripts/deploy-k8s.ps1 -UseSslipIo:$false `
        -AcrLoginServer ... -KvName kv-zava-a2aabc123 `
        -DnsZone zava-demo.example.com `
        -UamiClientId ... -FoundryEndpoint ... -WorkerDeploymentName ...
    (TLS / DnsZone mode, no A2A connection auto-creation)

.NOTES
    See docs/deployment-learnings.md §1 / §3 for the history of W1, W2, W3
    workarounds this script now automates.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AcrLoginServer,

    [Parameter(Mandatory = $false)]
    [string] $KvName,

    [Parameter(Mandatory = $false)]
    [string] $DnsZone,

    [Parameter(Mandatory = $true)]
    [string] $UamiClientId,

    [Parameter(Mandatory = $true)]
    [string] $FoundryEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $FoundryAccountEndpoint,

    [Parameter(Mandatory = $true)]
    [string] $WorkerDeploymentName,

    [Parameter(Mandatory = $false)]
    [string] $ImageTag = 'latest',

    [Parameter(Mandatory = $false)]
    [string] $A2aApiKey,

    [Parameter(Mandatory = $false)]
    [string] $Namespace = 'default',

    [Parameter(Mandatory = $false)]
    [switch] $KeepRendered,

    [Parameter(Mandatory = $false)]
    [bool] $UseSslipIo = $true,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string] $FoundryAccountName,

    [Parameter(Mandatory = $false)]
    [string] $ProjectName,

    [Parameter(Mandatory = $false)]
    [string] $A2aConnectionName = 'ops-agent-a2a',

    [Parameter(Mandatory = $false)]
    [switch] $SkipA2aConnection,

    [Parameter(Mandatory = $false)]
    [switch] $ForceA2aConnection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Mode validation
# -----------------------------------------------------------------------------
if (-not $UseSslipIo) {
    if ([string]::IsNullOrWhiteSpace($DnsZone)) {
        Write-Host "❌ -DnsZone is required when -UseSslipIo:`$false." -ForegroundColor Red
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($KvName)) {
        Write-Host "❌ -KvName is required when -UseSslipIo:`$false (App Routing reads the TLS cert from Key Vault)." -ForegroundColor Red
        exit 1
    }
}

# Determine whether we have enough info to auto-create the A2A connection.
$canAutoCreateA2a = (-not $SkipA2aConnection) -and `
    (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) -and `
    (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) -and `
    (-not [string]::IsNullOrWhiteSpace($FoundryAccountName)) -and `
    (-not [string]::IsNullOrWhiteSpace($ProjectName))

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Invoke-KubectlOrFail {
    param(
        [Parameter(Mandatory = $true)] [string]   $Description,
        [Parameter(Mandatory = $true)] [string[]] $KubectlArgs,
        [string] $StdInput
    )
    Write-Verbose ("kubectl " + ($KubectlArgs -join ' '))
    if ($PSBoundParameters.ContainsKey('StdInput') -and $StdInput) {
        $out = $StdInput | & kubectl @KubectlArgs 2>&1
    }
    else {
        $out = & kubectl @KubectlArgs 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ kubectl $Description failed:" -ForegroundColor Red
        Write-Host ($out | Out-String) -ForegroundColor Red
        Write-Host '' -ForegroundColor Red
        Write-Host 'Common causes:' -ForegroundColor Yellow
        Write-Host "  - kubectl context not set. Run: az aks get-credentials --resource-group <rg> --name <aks-name> --overwrite-existing" -ForegroundColor Yellow
        Write-Host "  - Wrong context selected. Verify with: kubectl config current-context" -ForegroundColor Yellow
        Write-Host "  - Cluster firewall / authorized-IP rules blocking the API server." -ForegroundColor Yellow
        exit 1
    }
    return $out
}

# -----------------------------------------------------------------------------
# Resolve repo-rooted paths so the script works regardless of cwd.
# -----------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot  = Split-Path -Parent $scriptDir
$k8sDir    = Join-Path $repoRoot 'apps/ops-agent/k8s'

$deploymentSrc = Join-Path $k8sDir 'deployment.yaml'
$serviceSrc    = Join-Path $k8sDir 'service.yaml'
$ingressSrc    = Join-Path $k8sDir 'ingress.yaml'
$ingressSslipSrc = Join-Path $k8sDir 'ingress.sslip.yaml'

$requiredManifests = @($deploymentSrc, $serviceSrc)
if ($UseSslipIo) {
    $requiredManifests += $ingressSslipSrc
} else {
    $requiredManifests += $ingressSrc
}
foreach ($p in $requiredManifests) {
    if (-not (Test-Path $p)) {
        Write-Host "❌ Required manifest not found: $p" -ForegroundColor Red
        exit 1
    }
}

# Rendered output directory. Per-run stamp avoids collisions between parallel
# deployers on the same workstation.
$renderRoot = Join-Path $env:TEMP ("zava-k8s-rendered-{0}" -f ([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')))
$null = New-Item -ItemType Directory -Path $renderRoot -Force

$cleanedUp = $false
function Invoke-Cleanup {
    if ($script:cleanedUp) { return }
    if ($KeepRendered) {
        Write-Host ("Rendered manifests retained at: {0}" -f $renderRoot) -ForegroundColor Yellow
    }
    else {
        try {
            Remove-Item -Path $renderRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host ("⚠ Could not remove rendered directory {0}: {1}" -f $renderRoot, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    $script:cleanedUp = $true
}

trap {
    Invoke-Cleanup
    break
}

# =============================================================================
# 1. Pre-flight: kubectl context + reachability
# =============================================================================
Write-Section 'Pre-flight: kubectl context'

try {
    $ctx = & kubectl config current-context 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl could not determine the current context. Run 'az aks get-credentials' first.`n$ctx"
    }
    $ctx = ($ctx | Out-String).Trim()
    Write-Host ("kubectl context          : {0}" -f $ctx)
}
catch {
    Write-Host "❌ kubectl is not configured." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Invoke-Cleanup
    exit 1
}

Invoke-KubectlOrFail -Description 'cluster-info' -KubectlArgs @('cluster-info') | Out-Host

# =============================================================================
# 2. Generate (or accept) the A2A API key
# =============================================================================
Write-Section 'A2A API key'

if (-not $A2aApiKey) {
    $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslPath) {
        $A2aApiKey = (& openssl rand -base64 32 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $A2aApiKey) {
            Write-Host "⚠ openssl present but rand failed; falling back to PowerShell RNG." -ForegroundColor Yellow
            $A2aApiKey = $null
        }
        else {
            Write-Host 'Generated A2A API key via openssl rand -base64 32.'
        }
    }
    if (-not $A2aApiKey) {
        $bytes = 1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }
        $A2aApiKey = [Convert]::ToBase64String([byte[]]$bytes)
        Write-Host 'Generated A2A API key via PowerShell RNG (Get-Random).'
    }
}
else {
    Write-Host 'Using -A2aApiKey supplied by caller.'
}

# Strip any whitespace / line breaks defensively.
$A2aApiKey = ($A2aApiKey -replace '\s', '')
if ($A2aApiKey.Length -lt 16) {
    Write-Host "❌ Generated A2A API key is implausibly short ($($A2aApiKey.Length) chars)." -ForegroundColor Red
    Invoke-Cleanup
    exit 1
}

# =============================================================================
# 3. Upsert Kubernetes Secret (dry-run + apply pattern → idempotent)
# =============================================================================
Write-Section ("Upsert Secret ops-agent-secrets in namespace '{0}'" -f $Namespace)

$secretYaml = Invoke-KubectlOrFail -Description 'create secret --dry-run' -KubectlArgs @(
    'create','secret','generic','ops-agent-secrets',
    ('--from-literal=A2A_API_KEY={0}' -f $A2aApiKey),
    '--namespace', $Namespace,
    '--dry-run=client',
    '-o','yaml'
)
$secretYamlStr = ($secretYaml | Out-String)

Invoke-KubectlOrFail -Description 'apply Secret' -KubectlArgs @('apply','-f','-') -StdInput $secretYamlStr | Out-Host
Write-Host "✓ Secret ops-agent-secrets upserted." -ForegroundColor Green

# =============================================================================
# 4. Render manifests (substitute placeholders → temp dir)
# =============================================================================
Write-Section 'Render manifests (initial pass)'

# In sslip.io mode we don't yet know the LB IP, so we render the deployment
# with a placeholder OPS_AGENT_PUBLIC_URL that gets overridden via `kubectl
# set env` after the ingress IP is known. KvName / DnsZone are also stubbed
# to non-empty values that satisfy the placeholder check but never reach
# anywhere they'd cause behavior (the sslip ingress doesn't read them).
if ($UseSslipIo) {
    $renderKvName  = if ([string]::IsNullOrWhiteSpace($KvName))  { 'sslip-mode-unused' } else { $KvName }
    $renderDnsZone = if ([string]::IsNullOrWhiteSpace($DnsZone)) { 'sslip-mode-unused' } else { $DnsZone }
    $opsAgentPublicUrlInitial = 'http://__sslip_placeholder__/'
} else {
    $renderKvName  = $KvName
    $renderDnsZone = $DnsZone
    $opsAgentPublicUrlInitial = ("https://ops-agent.{0}/" -f $DnsZone)
}

# Token map. Note: the deployment.yaml template currently hard-codes
# `ops-agent:latest` rather than `ops-agent:${IMAGE_TAG}`. We honor -ImageTag
# by replacing the literal image reference; if a future revision of the template
# uses `${IMAGE_TAG}` directly, the substitution below also covers it.
$substitutions = [ordered]@{
    '${ACR_LOGIN_SERVER}'              = $AcrLoginServer
    '${KV_NAME}'                       = $renderKvName
    '${DNS_ZONE}'                      = $renderDnsZone
    '${UAMI_CLIENT_ID}'                = $UamiClientId
    '${FOUNDRY_ENDPOINT}'              = $FoundryEndpoint
    '${FOUNDRY_ACCOUNT_ENDPOINT}'      = ''  # set below
    '${WORKER_DEPLOYMENT_NAME}'        = $WorkerDeploymentName
    '${IMAGE_TAG}'                     = $ImageTag
    '${OPS_AGENT_PUBLIC_URL}'          = $opsAgentPublicUrlInitial
    '${SSLIP_HOST}'                    = 'placeholder.sslip.io'  # overwritten in pass 2 for sslip mode
}

# Derive the OpenAI-compatible inference endpoint if not provided explicitly.
# Strip the `/api/projects/...` suffix from the Foundry project endpoint so the
# pod gets the account base URL that AzureChatOpenAI expects.
if (-not [string]::IsNullOrWhiteSpace($FoundryAccountEndpoint)) {
    $substitutions['${FOUNDRY_ACCOUNT_ENDPOINT}'] = $FoundryAccountEndpoint
}
else {
    $derived = $FoundryEndpoint -replace '/api/projects/.*$', ''
    $derived = $derived.TrimEnd('/')
    $substitutions['${FOUNDRY_ACCOUNT_ENDPOINT}'] = $derived
    Write-Host ("  ℹ Derived FOUNDRY_ACCOUNT_ENDPOINT from FoundryEndpoint: {0}" -f $derived) -ForegroundColor DarkGray
}

function Invoke-ManifestRender {
    param(
        [Parameter(Mandatory = $true)] [string] $SrcPath,
        [Parameter(Mandatory = $true)] [string] $DstPath
    )
    $content = Get-Content -Path $SrcPath -Raw

    foreach ($token in $substitutions.Keys) {
        $value = [string]$substitutions[$token]
        # Plain string replacement (no regex) — placeholder syntax `${NAME}`
        # is literal text in the templates.
        $content = $content.Replace($token, $value)
    }

    # Honor -ImageTag even when the template hard-codes `ops-agent:latest`.
    if ($ImageTag -ne 'latest') {
        $content = $content.Replace('ops-agent:latest', ("ops-agent:{0}" -f $ImageTag))
    }

    # Detect any leftover `${...}` placeholders so a missing parameter doesn't
    # silently slip through to kubectl. Wrap in @() so `.Count` works under
    # StrictMode even when there's only 0 or 1 match.
    $leftover = @([regex]::Matches($content, '\$\{[A-Z_][A-Z0-9_]*\}') |
        ForEach-Object { $_.Value } |
        Select-Object -Unique)
    if ($leftover.Count -gt 0) {
        Write-Host ("❌ Unresolved placeholders in {0}: {1}" -f (Split-Path -Leaf $SrcPath), ($leftover -join ', ')) -ForegroundColor Red
        Invoke-Cleanup
        exit 1
    }

    Set-Content -Path $DstPath -Value $content -Encoding UTF8 -NoNewline
    Write-Host ("  rendered → {0}" -f $DstPath)
}

$deploymentDst = Join-Path $renderRoot 'deployment.yaml'
$serviceDst    = Join-Path $renderRoot 'service.yaml'
$ingressDst    = Join-Path $renderRoot 'ingress.yaml'

Invoke-ManifestRender -SrcPath $deploymentSrc -DstPath $deploymentDst
Invoke-ManifestRender -SrcPath $serviceSrc    -DstPath $serviceDst

if ($UseSslipIo) {
    Invoke-ManifestRender -SrcPath $ingressSslipSrc -DstPath $ingressDst
} else {
    Invoke-ManifestRender -SrcPath $ingressSrc      -DstPath $ingressDst
}

# =============================================================================
# 5. kubectl apply (deployment first → also creates the ServiceAccount)
# =============================================================================
Write-Section 'kubectl apply'

Invoke-KubectlOrFail -Description ('apply ' + (Split-Path -Leaf $deploymentDst)) -KubectlArgs @('apply','-f', $deploymentDst) | Out-Host
Invoke-KubectlOrFail -Description ('apply ' + (Split-Path -Leaf $serviceDst))    -KubectlArgs @('apply','-f', $serviceDst)    | Out-Host
Invoke-KubectlOrFail -Description ('apply ' + (Split-Path -Leaf $ingressDst))    -KubectlArgs @('apply','-f', $ingressDst)    | Out-Host
Write-Host '✓ Manifests applied.' -ForegroundColor Green

# =============================================================================
# 6. Wait for rollout
# =============================================================================
Write-Section 'Wait for deployment rollout (timeout 5m)'

$rolloutOut = & kubectl rollout status deployment/ops-agent --namespace $Namespace --timeout=5m 2>&1
$rolloutExit = $LASTEXITCODE
Write-Host ($rolloutOut | Out-String)

if ($rolloutExit -ne 0) {
    Write-Host '❌ Deployment rollout did not complete within 5 minutes. Diagnostics:' -ForegroundColor Red
    Write-Host ''
    Write-Host '--- kubectl describe pod -l app=ops-agent ---' -ForegroundColor Yellow
    & kubectl describe pod -l app=ops-agent --namespace $Namespace 2>&1 | Out-Host
    Write-Host '--- kubectl logs -l app=ops-agent --tail=50 ---' -ForegroundColor Yellow
    & kubectl logs -l app=ops-agent --namespace $Namespace --tail=50 2>&1 | Out-Host
    Invoke-Cleanup
    exit 1
}
Write-Host '✓ Rollout complete.' -ForegroundColor Green

# =============================================================================
# 7. Wait for Ingress address (poll up to 5 minutes)
# =============================================================================
Write-Section 'Wait for Ingress address (poll up to 5m)'

$ingressAddress = $null
$ingressIp      = $null
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $hostnameOut = & kubectl get ingress ops-agent-ingress --namespace $Namespace -o "jsonpath={.status.loadBalancer.ingress[0].hostname}" 2>$null
    $ipOut       = & kubectl get ingress ops-agent-ingress --namespace $Namespace -o "jsonpath={.status.loadBalancer.ingress[0].ip}"       2>$null
    $hostname = if ($hostnameOut) { ($hostnameOut | Out-String).Trim() } else { '' }
    $ip       = if ($ipOut)       { ($ipOut       | Out-String).Trim() } else { '' }
    if ($ip) {
        $ingressIp = $ip
        $ingressAddress = $ip
        break
    } elseif ($hostname) {
        $ingressAddress = $hostname
        break
    }
    Write-Host '  (no address yet — sleeping 10s)'
    Start-Sleep -Seconds 10
}

if (-not $ingressAddress) {
    Write-Host '❌ Ingress did not surface an address within 5 minutes.' -ForegroundColor Red
    Write-Host '  Without an LB IP the sslip.io host cannot be computed and the A2A connection cannot be created.' -ForegroundColor Red
    if ($UseSslipIo) {
        Invoke-Cleanup
        exit 1
    } else {
        Write-Host '  Continuing — DnsZone mode does not need the IP up-front.' -ForegroundColor Yellow
    }
} else {
    Write-Host ("✓ Ingress address: {0}" -f $ingressAddress) -ForegroundColor Green
}

# =============================================================================
# 7b. (sslip mode only) Pass 2 — re-render ingress with the real sslip host,
#     then `kubectl set env` to update OPS_AGENT_PUBLIC_URL on the deployment.
# =============================================================================
$publicUrl = $opsAgentPublicUrlInitial

if ($UseSslipIo) {
    Write-Section 'sslip.io mode — pass 2: real host + env override'

    if (-not $ingressIp) {
        Write-Host '❌ sslip.io mode requires an IPv4 LB ingress IP, but got hostname instead. Aborting.' -ForegroundColor Red
        Invoke-Cleanup
        exit 1
    }

    if ($ingressIp -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        Write-Host ("❌ Ingress LB IP '{0}' is not IPv4 — sslip.io requires IPv4." -f $ingressIp) -ForegroundColor Red
        Invoke-Cleanup
        exit 1
    }

    $sslipHost = "ops-agent.{0}.sslip.io" -f ($ingressIp -replace '\.', '-')
    $publicUrl = "http://$sslipHost/"
    Write-Host ("  sslip host : {0}" -f $sslipHost)
    Write-Host ("  public URL : {0}" -f $publicUrl)
    Write-Host ''

    # Pass 2: re-render the sslip ingress with the real SSLIP_HOST.
    $substitutions['${SSLIP_HOST}'] = $sslipHost
    $ingressDst2 = Join-Path $renderRoot 'ingress.pass2.yaml'
    Invoke-ManifestRender -SrcPath $ingressSslipSrc -DstPath $ingressDst2
    Invoke-KubectlOrFail -Description 'apply ingress.pass2.yaml' -KubectlArgs @('apply','-f', $ingressDst2) | Out-Host
    Write-Host '✓ Ingress re-applied with real sslip.io host.' -ForegroundColor Green
    Write-Host ''

    # Update OPS_AGENT_PUBLIC_URL via `kubectl set env`. kubectl set env triggers
    # a rollout only when the env value actually differs, so this is idempotent.
    Invoke-KubectlOrFail -Description 'set env OPS_AGENT_PUBLIC_URL' -KubectlArgs @(
        'set','env','deployment/ops-agent',
        ("OPS_AGENT_PUBLIC_URL={0}" -f $publicUrl),
        '--namespace', $Namespace
    ) | Out-Host

    Write-Host 'Waiting for rollout after env override (timeout 3m)...'
    $rolloutOut2 = & kubectl rollout status deployment/ops-agent --namespace $Namespace --timeout=3m 2>&1
    $rolloutExit2 = $LASTEXITCODE
    Write-Host ($rolloutOut2 | Out-String)
    if ($rolloutExit2 -ne 0) {
        Write-Host '⚠ Post-env-override rollout did not complete in 3m. The deployment may already have had the same value (no restart triggered).' -ForegroundColor Yellow
    } else {
        Write-Host '✓ Pod restarted with new OPS_AGENT_PUBLIC_URL.' -ForegroundColor Green
    }
}

# =============================================================================
# 8. Smoke check (read-only; failures are diagnostic, not fatal)
# =============================================================================
Write-Section 'Smoke check: GET /health'

$healthUrl = "{0}health" -f $publicUrl
Write-Host ("Probing {0} ..." -f $healthUrl)
try {
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    Write-Host ("✓ {0} returned HTTP {1}" -f $healthUrl, $resp.StatusCode) -ForegroundColor Green
}
catch {
    Write-Host ("⚠ Smoke check failed (non-fatal): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host '  Common causes (resolved by waiting / completing prerequisites):' -ForegroundColor Yellow
    if ($UseSslipIo) {
        Write-Host '    - sslip.io DNS resolution propagation (usually instant, occasionally a few sec)' -ForegroundColor Yellow
        Write-Host '    - App Routing nginx still picking up the new ingress (~30s after re-apply)' -ForegroundColor Yellow
    } else {
        Write-Host '    - DNS A record for ops-agent.<zone> not yet created / propagated' -ForegroundColor Yellow
        Write-Host '    - App Routing → Key Vault cert sync still in progress (first apply ~5 min)' -ForegroundColor Yellow
        Write-Host '    - tls-cert-ops-agent missing from Key Vault — see scripts/deploy-infra.ps1 §7' -ForegroundColor Yellow
    }
}

# =============================================================================
# 8b. (optional) Create / update the Foundry-side A2A connection.
# =============================================================================
$a2aConnectionResult = $null
if ($SkipA2aConnection) {
    Write-Section 'A2A connection — SKIPPED (-SkipA2aConnection)'
    Write-Host 'You must create / update the connection manually:' -ForegroundColor Yellow
    Write-Host ('  Target URL : {0}' -f $publicUrl)
    Write-Host  '  API key    : (see summary below)'
    Write-Host  '  Either: Foundry portal → Project → Connections → +New connection'
    Write-Host  '  Or run : ./scripts/create-a2a-connection.ps1 ...'
} elseif (-not $canAutoCreateA2a) {
    Write-Section 'A2A connection — SKIPPED (insufficient parameters)'
    Write-Host 'To auto-create the A2A connection, re-run with all of:' -ForegroundColor Yellow
    Write-Host  '  -SubscriptionId -ResourceGroupName -FoundryAccountName -ProjectName'
} else {
    Write-Section 'Create / update A2A connection on Foundry project'

    $createA2aScript = Join-Path $scriptDir 'create-a2a-connection.ps1'
    if (-not (Test-Path $createA2aScript)) {
        Write-Host ("❌ Helper script not found: {0}" -f $createA2aScript) -ForegroundColor Red
        Invoke-Cleanup
        exit 1
    }

    $a2aArgs = @{
        SubscriptionId     = $SubscriptionId
        ResourceGroupName  = $ResourceGroupName
        FoundryAccountName = $FoundryAccountName
        ProjectName        = $ProjectName
        ConnectionName     = $A2aConnectionName
        TargetUrl          = $publicUrl
        ApiKey             = $A2aApiKey
    }
    if ($ForceA2aConnection) {
        $a2aArgs['Force'] = $true
    }
    try {
        & $createA2aScript @a2aArgs | Tee-Object -Variable a2aRawOut | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "create-a2a-connection.ps1 exited with code $LASTEXITCODE"
        }
        # Find the JSON line in the script's output (the script emits one
        # compact JSON object at the end as a machine-readable result).
        $jsonLine = $a2aRawOut |
            Where-Object { $_ -match '^\s*\{' -and $_ -match '"Operation"' } |
            Select-Object -Last 1
        if ($jsonLine) {
            $a2aConnectionResult = $jsonLine | ConvertFrom-Json
        }
    }
    catch {
        Write-Host ("❌ Failed to create / update A2A connection: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Invoke-Cleanup
        exit 1
    }
}

# =============================================================================
# 9. Summary
# =============================================================================
Write-Host ''
Write-Host '========================================================================' -ForegroundColor Green
Write-Host 'OPS AGENT DEPLOYED' -ForegroundColor Green
Write-Host '========================================================================' -ForegroundColor Green
$modeLabel = if ($UseSslipIo) { 'sslip.io (HTTP)' } else { 'DnsZone (HTTPS)' }
Write-Host ("Mode                  : {0}" -f $modeLabel)
Write-Host ("Public URL            : {0}" -f $publicUrl)
Write-Host ("Image                 : {0}/ops-agent:{1}" -f $AcrLoginServer, $ImageTag)
Write-Host ("K8s namespace         : {0}" -f $Namespace)
Write-Host  "Workload identity SA  : ops-agent-sa"
if ($ingressAddress) {
    Write-Host ("Ingress LB address    : {0}" -f $ingressAddress)
}
if ($a2aConnectionResult) {
    Write-Host ("A2A connection        : {0} ({1})" -f $a2aConnectionResult.ConnectionName, $a2aConnectionResult.Operation)
    Write-Host ("                        target = {0}" -f $a2aConnectionResult.Target)
}
Write-Host ''
if (-not $a2aConnectionResult) {
    Write-Host 'API KEY (copy into Foundry portal A2A connection):' -ForegroundColor Yellow
    Write-Host $A2aApiKey -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Next step: run scripts/setup-foundry-agent.ps1 (the agent prompt setup):' -ForegroundColor Cyan
    Write-Host ("  ./scripts/setup-foundry-agent.ps1 ``" )
    Write-Host ("      -FoundryEndpoint {0} ``" -f $FoundryEndpoint)
    Write-Host ("      -OpsAgentEndpoint {0} ``" -f $publicUrl)
    Write-Host  "      -OpsAgentApiKey <paste-the-key-above>"
} else {
    Write-Host 'Next step: run scripts/setup-foundry-agent.ps1 to create the agent prompt:' -ForegroundColor Cyan
    Write-Host ("  ./scripts/setup-foundry-agent.ps1 -FoundryEndpoint {0} -SkipManualGates" -f $FoundryEndpoint)
}
Write-Host '========================================================================' -ForegroundColor Green

# =============================================================================
# 10. Cleanup
# =============================================================================
Invoke-Cleanup
exit 0
