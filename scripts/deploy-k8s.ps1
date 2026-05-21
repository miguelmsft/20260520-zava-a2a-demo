<#
.SYNOPSIS
    Renders and applies the Ops Agent Kubernetes manifests to the AKS cluster,
    generates and upserts the A2A API key Secret, waits for the rollout, and
    prints the public endpoint plus the API key for the deployer to copy into
    the Foundry portal A2A connection (Step 16). Step 15 (plan.md), part 2 of 2.

.DESCRIPTION
    Inputs come from the outputs of scripts/deploy-infra.ps1 (Step 14) and the
    image produced by scripts/build-and-push.ps1.

    What this script does, in order:
      1. Pre-flight: print kubectl current-context and verify the cluster is
         reachable (`kubectl cluster-info`).
      2. Generate (or accept) an A2A API key — 32 bytes, base64-encoded.
      3. Upsert the K8s Secret `ops-agent-secrets` via the dry-run + apply
         pattern (idempotent — safe to re-run).
      4. Render the deployment / service / ingress manifests by substituting
         `${ACR_LOGIN_SERVER}`, `${KV_NAME}`, `${DNS_ZONE}`, `${UAMI_CLIENT_ID}`,
         `${FOUNDRY_ENDPOINT}`, `${WORKER_DEPLOYMENT_NAME}`, and `${IMAGE_TAG}`
         into a rendered output directory (NOT the originals — the templates
         stay templates).
         Also rewrites the hard-coded `ops-agent:latest` reference in
         deployment.yaml when -ImageTag is non-default, so the chosen tag wins
         even though the template lacks a literal `${IMAGE_TAG}` placeholder.
      5. `kubectl apply -f` the three rendered manifests (deployment.yaml
         also defines the ServiceAccount).
      6. `kubectl rollout status deployment/ops-agent --timeout=5m` and, on
         timeout, dump describe + logs to aid diagnosis.
      7. Poll the Ingress address for up to 5 minutes; print once available.
      8. Optional smoke check: GET https://ops-agent.<dns-zone>/health. A
         non-200 / TLS error here does not abort — DNS delegation and the
         App Routing → Key Vault cert sync can take several minutes after
         first apply and are out of scope for this script.
      9. Print a one-screen summary including the API key (with copy/paste
         framing for the Foundry portal A2A connection form in Step 16).
     10. Clean up the rendered manifest directory (override with -KeepRendered
         for debugging).

    Idempotency: the Secret upsert and `kubectl apply` calls are all safe to
    re-run; re-running with the same -A2aApiKey leaves the cluster state
    unchanged. Re-running WITHOUT -A2aApiKey generates a new key and overwrites
    the Secret — pods pick up the new value on next restart, and the Foundry
    A2A connection must be updated to match.

.PARAMETER AcrLoginServer
    REQUIRED. Fully-qualified ACR login server (e.g.,
    `acrzavademoabc123.azurecr.io`). Source: deploy-infra.ps1 summary.

.PARAMETER KvName
    REQUIRED. Key Vault resource name (without the URI). Source:
    deploy-infra.ps1 summary ("Key Vault name").

.PARAMETER DnsZone
    REQUIRED. Public DNS zone (e.g., `zava-demo.example.com`). Source:
    deploy-infra.ps1 summary ("DNS zone").

.PARAMETER UamiClientId
    REQUIRED. Client ID (GUID) of the User-Assigned Managed Identity that the
    ops-agent ServiceAccount federates with via Workload Identity. Source:
    deploy-infra.ps1 summary ("UAMI client ID").

.PARAMETER FoundryEndpoint
    REQUIRED. Foundry project endpoint, e.g.,
    `https://zava-foundry.services.ai.azure.com/api/projects/zava-project`.
    Source: deploy-infra.ps1 summary ("Foundry project endpoint"). Used as
    FOUNDRY_PROJECT_ENDPOINT inside the pod (for future AIProjectClient use).

.PARAMETER FoundryAccountEndpoint
    Optional. Foundry account inference endpoint (Azure OpenAI-compatible base
    URL), e.g., `https://zava-foundry.services.ai.azure.com`. Source:
    deploy-infra.ps1 summary ("Foundry account inference endpoint"). Used as
    AZURE_OPENAI_ENDPOINT inside the pod by `langchain_openai.AzureChatOpenAI`.
    If omitted, the script derives it by stripping the `/api/projects/...`
    suffix from -FoundryEndpoint.

.PARAMETER WorkerDeploymentName
    REQUIRED. Name of the model deployment the LangGraph worker calls
    (e.g., `gpt-54mini-worker`). Source: deploy-infra.ps1 summary
    ("Worker deployment"). Used as AZURE_OPENAI_DEPLOYMENT inside the pod.

.PARAMETER ImageTag
    Optional. Image tag to deploy. Default `latest`. Must match a tag pushed
    by scripts/build-and-push.ps1.

.PARAMETER A2aApiKey
    Optional. Pre-generated A2A API key. If omitted, the script generates one.
    Provide this on re-runs if you want to keep the existing Foundry-side
    connection's key unchanged.

.PARAMETER Namespace
    Optional. Kubernetes namespace. Default `default` (matches the manifests
    in apps/ops-agent/k8s/).

.PARAMETER KeepRendered
    Switch. If set, the rendered manifests directory is NOT deleted at the
    end. Useful for debugging substitution issues. Default $false.

.EXAMPLE
    ./scripts/deploy-k8s.ps1 `
        -AcrLoginServer acrzavademoabc123.azurecr.io `
        -KvName kv-zava-abc123 `
        -DnsZone zava-demo.example.com `
        -UamiClientId 11111111-2222-3333-4444-555555555555 `
        -FoundryEndpoint https://zava-foundry.services.ai.azure.com/api/projects/zava-project `
        -WorkerDeploymentName gpt-54mini-worker

.NOTES
    Verification (post-deploy): `kubectl get pods -l app=ops-agent` shows
    1/1 Running; `kubectl get ingress ops-agent-ingress` shows an address;
    `curl https://ops-agent.<dns-zone>/health` returns 200 (once DNS +
    TLS cert sync is complete).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AcrLoginServer,

    [Parameter(Mandatory = $true)]
    [string] $KvName,

    [Parameter(Mandatory = $true)]
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
    [switch] $KeepRendered
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

foreach ($p in @($deploymentSrc, $serviceSrc, $ingressSrc)) {
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
Write-Section 'Render manifests'

# Token map. Note: the deployment.yaml template currently hard-codes
# `ops-agent:latest` rather than `ops-agent:${IMAGE_TAG}`. We honor -ImageTag
# by replacing the literal image reference; if a future revision of the template
# uses `${IMAGE_TAG}` directly, the substitution below also covers it.
$substitutions = [ordered]@{
    '${ACR_LOGIN_SERVER}'              = $AcrLoginServer
    '${KV_NAME}'                       = $KvName
    '${DNS_ZONE}'                      = $DnsZone
    '${UAMI_CLIENT_ID}'                = $UamiClientId
    '${FOUNDRY_ENDPOINT}'              = $FoundryEndpoint
    '${FOUNDRY_ACCOUNT_ENDPOINT}'      = ''  # set below
    '${WORKER_DEPLOYMENT_NAME}'        = $WorkerDeploymentName
    '${IMAGE_TAG}'                     = $ImageTag
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
    # silently slip through to kubectl.
    $leftover = [regex]::Matches($content, '\$\{[A-Z_][A-Z0-9_]*\}') |
        ForEach-Object { $_.Value } |
        Select-Object -Unique
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
Invoke-ManifestRender -SrcPath $ingressSrc    -DstPath $ingressDst

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
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $hostnameOut = & kubectl get ingress ops-agent-ingress --namespace $Namespace -o "jsonpath={.status.loadBalancer.ingress[0].hostname}" 2>$null
    $ipOut       = & kubectl get ingress ops-agent-ingress --namespace $Namespace -o "jsonpath={.status.loadBalancer.ingress[0].ip}"       2>$null
    $hostname = if ($hostnameOut) { ($hostnameOut | Out-String).Trim() } else { '' }
    $ip       = if ($ipOut)       { ($ipOut       | Out-String).Trim() } else { '' }
    $candidate = if ($hostname) { $hostname } elseif ($ip) { $ip } else { '' }
    if ($candidate) {
        $ingressAddress = $candidate
        break
    }
    Write-Host '  (no address yet — sleeping 10s)'
    Start-Sleep -Seconds 10
}

if ($ingressAddress) {
    Write-Host ("✓ Ingress address: {0}" -f $ingressAddress) -ForegroundColor Green
}
else {
    Write-Host '⚠ Ingress did not surface an address within 5 minutes. Continuing — App Routing may still be provisioning.' -ForegroundColor Yellow
}

# =============================================================================
# 8. Smoke check (read-only; failures are diagnostic, not fatal)
# =============================================================================
Write-Section 'Smoke check: GET /health'

$healthUrl = "https://ops-agent.$DnsZone/health"
Write-Host ("Probing {0} ..." -f $healthUrl)
try {
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    Write-Host ("✓ {0} returned HTTP {1}" -f $healthUrl, $resp.StatusCode) -ForegroundColor Green
}
catch {
    Write-Host ("⚠ Smoke check failed (non-fatal): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host '  Common causes (resolved by waiting / completing prerequisites):' -ForegroundColor Yellow
    Write-Host '    - DNS A record for ops-agent.<zone> not yet created or not yet propagated' -ForegroundColor Yellow
    Write-Host '    - Parent-domain NS records not yet delegated to Azure DNS' -ForegroundColor Yellow
    Write-Host '    - App Routing → Key Vault cert sync still in progress (first apply can take ~5 min)' -ForegroundColor Yellow
    Write-Host '    - tls-cert-ops-agent missing from Key Vault — see scripts/deploy-infra.ps1 §7' -ForegroundColor Yellow
}

# =============================================================================
# 9. Summary
# =============================================================================
Write-Host ''
Write-Host '========================================================================' -ForegroundColor Green
Write-Host 'OPS AGENT DEPLOYED' -ForegroundColor Green
Write-Host '========================================================================' -ForegroundColor Green
Write-Host ("Endpoint URL          : https://ops-agent.{0}/" -f $DnsZone)
Write-Host ("Image                 : {0}/ops-agent:{1}" -f $AcrLoginServer, $ImageTag)
Write-Host ("K8s namespace         : {0}" -f $Namespace)
Write-Host  "Workload identity SA  : ops-agent-sa"
if ($ingressAddress) {
    Write-Host ("Ingress address       : {0}" -f $ingressAddress)
}
Write-Host ''
Write-Host 'API KEY (copy into Foundry portal A2A connection in Step 16):' -ForegroundColor Yellow
Write-Host $A2aApiKey -ForegroundColor Yellow
Write-Host ''
Write-Host 'Next step: run scripts/setup-foundry-agent.ps1' -ForegroundColor Cyan
Write-Host ("  ./scripts/setup-foundry-agent.ps1 ``" )
Write-Host ("      -FoundryEndpoint {0} ``" -f $FoundryEndpoint)
Write-Host ("      -OpsAgentEndpoint https://ops-agent.{0}/ ``" -f $DnsZone)
Write-Host  "      -OpsAgentApiKey <paste-the-key-above>"
Write-Host '========================================================================' -ForegroundColor Green

# =============================================================================
# 10. Cleanup
# =============================================================================
Invoke-Cleanup
exit 0
