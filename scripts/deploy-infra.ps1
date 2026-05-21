<#
.SYNOPSIS
    Deploys the Zava A2A demo infrastructure (infra/main.bicep) into a resource
    group and prepares the cluster + Key Vault for Step 15 (deploy-k8s.ps1).

.DESCRIPTION
    End-to-end Azure deployment driver:
      1. Cost-warning confirmation prompt.
      2. (Optional) runs scripts/verify-quota.ps1 first.
      3. Creates the resource group.
      4. Runs `az deployment group create` against infra/main.bicep using
         infra/main.parameters.json plus per-run overrides (useGpt55, dnsZoneName,
         deployerPrincipalId).
      5. Captures all relevant Bicep outputs into local variables.
      6. Runs `az aks get-credentials` so kubectl is wired to the new cluster.
      7. TLS certificate provisioning block — either imports a provided PFX into
         Key Vault under the name `tls-cert-ops-agent` (required name; matches
         the K8s Ingress annotation from Step 10) or prints multi-vendor manual
         instructions and waits for the deployer.
      8. Prints a final summary + DNS delegation NS records + the exact next
         command to run.

    Idempotency: `az group create`, `az deployment group create` (incremental
    mode, the default), `az aks get-credentials --overwrite-existing`, and the
    `az keyvault certificate import` step are all safe to re-run; the script is
    designed so a second run on the same RG converges rather than failing.

    See plan.md §C Step 14 for the full task list and §F R4 for the TLS
    mitigation rationale.

.PARAMETER ResourceGroupName
    Resource group to create / deploy into. Default: rg-zava-a2a-smart-order-demo.

.PARAMETER Location
    Azure region. Default: eastus2 (matches infra/main.parameters.json).

.PARAMETER UseGpt55
    Switch. Default $true (primary path). Pass `-UseGpt55:$false` to use the
    gpt-5.4-mini-only fallback when gpt-5.5 quota is unavailable.

.PARAMETER DnsZoneName
    REQUIRED. Public DNS zone for the demo (e.g., zava-demo.example.com). Must
    be a domain you control; NS records printed at the end must be added at the
    parent domain registrar to complete delegation.

.PARAMETER DeployerPrincipalId
    Optional. Azure AD object ID of the principal that should receive Foundry
    Account Owner. Defaults to the signed-in `az ad signed-in-user` object ID.

.PARAMETER SkipQuotaCheck
    Switch. Skip the pre-flight call to scripts/verify-quota.ps1. Default $false.

.PARAMETER CertificatePfxPath
    Optional path to a CA-issued PFX containing the wildcard or per-host cert
    for `ops-agent.<DnsZoneName>`. If provided, the script imports it into Key
    Vault as `tls-cert-ops-agent` instead of falling back to manual instructions.

.PARAMETER CertificatePfxPassword
    Optional SecureString containing the PFX password. If $CertificatePfxPath is
    provided and the PFX is password-protected, this must also be supplied. The
    plaintext is materialized only at the moment `az keyvault certificate import`
    runs and is zeroed immediately afterward.

.EXAMPLE
    ./scripts/deploy-infra.ps1 -DnsZoneName zava-demo.example.com
    Primary path. Deployer is the signed-in user. TLS cert is provisioned
    manually after deployment (script will pause and print instructions).

.EXAMPLE
    $pw = Read-Host -AsSecureString 'PFX password'
    ./scripts/deploy-infra.ps1 -DnsZoneName zava-demo.example.com -CertificatePfxPath C:\certs\ops-agent.pfx -CertificatePfxPassword $pw
    Primary path with automatic PFX import.

.EXAMPLE
    ./scripts/deploy-infra.ps1 -DnsZoneName zava-demo.example.com -UseGpt55:$false -SkipQuotaCheck
    Fallback path (both agents on gpt-5.4-mini), skip the quota pre-flight.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupName = 'rg-zava-a2a-smart-order-demo',

    [Parameter(Mandatory = $false)]
    [string] $Location = 'eastus2',

    [Parameter(Mandatory = $false)]
    [switch] $UseGpt55 = $true,

    [Parameter(Mandatory = $true)]
    [string] $DnsZoneName,

    [Parameter(Mandatory = $false)]
    [string] $DeployerPrincipalId,

    [Parameter(Mandatory = $false)]
    [switch] $SkipQuotaCheck,

    [Parameter(Mandatory = $false)]
    [string] $CertificatePfxPath,

    [Parameter(Mandatory = $false)]
    [System.Security.SecureString] $CertificatePfxPassword,

    [Parameter(Mandatory = $false)]
    [switch] $NonInteractive
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Resolve repo-rooted paths so the script works regardless of cwd.
# -----------------------------------------------------------------------------
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot    = Split-Path -Parent $scriptDir
$infraDir    = Join-Path $repoRoot 'infra'
$templateFile     = Join-Path $infraDir 'main.bicep'
$parametersFile   = Join-Path $infraDir 'main.parameters.json'
$verifyQuotaScript = Join-Path $scriptDir 'verify-quota.ps1'

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Invoke-AzOrFail {
    param(
        [Parameter(Mandatory = $true)] [string]   $Description,
        [Parameter(Mandatory = $true)] [string[]] $Args
    )
    Write-Verbose ("az " + ($Args -join ' '))
    $out = & az @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ $Description failed:" -ForegroundColor Red
        Write-Host $out -ForegroundColor Red
        exit 1
    }
    return $out
}

# -----------------------------------------------------------------------------
# 1. Cost warning + confirmation
# -----------------------------------------------------------------------------
Write-Section 'Zava A2A Demo — Infrastructure Deployment'
Write-Host 'This script will CREATE Azure resources that incur cost.' -ForegroundColor Yellow
Write-Host 'Estimated cost: ~$15-25/day for the demo footprint (AKS Free tier control plane,' -ForegroundColor Yellow
Write-Host 'one Standard_D2s_v6 node, Basic ACR, Standard Key Vault, Log Analytics ingestion,' -ForegroundColor Yellow
Write-Host 'and pay-as-you-go Azure OpenAI tokens).' -ForegroundColor Yellow
Write-Host ''
Write-Host ("  Resource group : {0}" -f $ResourceGroupName)
Write-Host ("  Location       : {0}" -f $Location)
Write-Host ("  useGpt55       : {0}" -f ([bool]$UseGpt55))
Write-Host ("  DNS zone       : {0}" -f $DnsZoneName)
Write-Host ''
if (-not $NonInteractive) {
    Read-Host 'Press Enter to continue or Ctrl+C to cancel' | Out-Null
}
else {
    Write-Host '⚠ -NonInteractive set; skipping confirmation prompt.' -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 2. Pre-flight: quota check
# -----------------------------------------------------------------------------
if (-not $SkipQuotaCheck) {
    Write-Section 'Pre-flight: quota check'
    & $verifyQuotaScript -Location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Host '❌ verify-quota.ps1 failed. Re-run with -SkipQuotaCheck to bypass (not recommended).' -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host '⚠ -SkipQuotaCheck set; quota pre-flight skipped.' -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 3. Resolve deployer principal ID (default = signed-in user)
# -----------------------------------------------------------------------------
if (-not $DeployerPrincipalId) {
    Write-Verbose 'Resolving signed-in user object ID via az ad signed-in-user show.'
    $oid = az ad signed-in-user show --query id -o tsv 2>$null
    if (-not $oid) {
        Write-Host '❌ Could not resolve signed-in user object ID. Pass -DeployerPrincipalId <oid> explicitly.' -ForegroundColor Red
        exit 1
    }
    $DeployerPrincipalId = $oid.Trim()
}
Write-Host ("Deployer principal ID: {0}" -f $DeployerPrincipalId)

# -----------------------------------------------------------------------------
# 4. Resource group
# -----------------------------------------------------------------------------
Write-Section "Resource group ($ResourceGroupName)"
Invoke-AzOrFail -Description 'az group create' -Args @(
    'group','create',
    '--name', $ResourceGroupName,
    '--location', $Location,
    '--output','none'
) | Out-Null
Write-Host "✓ Resource group $ResourceGroupName ready in $Location." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Main Bicep deployment
# -----------------------------------------------------------------------------
Write-Section 'Bicep deployment (infra/main.bicep)'

$useGpt55Value = if ([bool]$UseGpt55) { 'true' } else { 'false' }
$deploymentName = "zava-infra-{0}" -f ([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))

Write-Host "Deployment name: $deploymentName"
$deployOutputJson = Invoke-AzOrFail -Description 'az deployment group create' -Args @(
    'deployment','group','create',
    '--resource-group', $ResourceGroupName,
    '--name', $deploymentName,
    '--template-file', $templateFile,
    '--parameters', ('@' + $parametersFile),
    '--parameters', ("useGpt55=$useGpt55Value"),
    '--parameters', ("dnsZoneName=$DnsZoneName"),
    '--parameters', ("deployerPrincipalId=$DeployerPrincipalId"),
    '--output','json'
)

try {
    $deployment = ($deployOutputJson | Out-String) | ConvertFrom-Json
}
catch {
    Write-Host '❌ Could not parse deployment output as JSON.' -ForegroundColor Red
    Write-Host $deployOutputJson
    exit 1
}

$outputs = $deployment.properties.outputs

# Helper to safely read a Bicep output by name (case-insensitive on the leading
# char since the ARM JSON uses camelCase identical to the Bicep symbol).
function Get-Out {
    param([string] $Name)
    if ($null -eq $outputs) { return $null }
    $prop = $outputs.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value.value
}

$kvName                        = Get-Out 'keyVaultUri'   # we derive name from URI below
$keyVaultUri                   = Get-Out 'keyVaultUri'
$dnsZoneNameOut                = Get-Out 'dnsZoneName'
$dnsZoneNameServers            = Get-Out 'dnsZoneNameServers'
$aksClusterName                = Get-Out 'aksClusterName'
$acrLoginServer                = Get-Out 'acrLoginServer'
$appInsightsConnectionString   = Get-Out 'appInsightsConnectionString'
$appInsightsName               = Get-Out 'appInsightsName'
$appInsightsId                 = Get-Out 'appInsightsId'
$foundryAccountName            = Get-Out 'foundryAccountName'
$foundryEndpoint               = Get-Out 'projectEndpoint'
$foundryAccountEndpoint        = Get-Out 'accountInferenceEndpoint'
$projectName                   = Get-Out 'projectName'
$uamiClientId                  = Get-Out 'uamiClientId'
$uamiPrincipalId               = Get-Out 'uamiPrincipalId'
$workerDeploymentName          = Get-Out 'workerDeploymentName'
$orchestratorDeploymentName    = Get-Out 'orchestratorDeploymentName'

# Derive Key Vault name from URI ("https://<name>.vault.azure.net/").
if ($keyVaultUri -match '^https://([^.]+)\.vault\.azure\.net') {
    $kvName = $Matches[1]
}
else {
    Write-Host "⚠ Could not parse Key Vault name from URI: $keyVaultUri" -ForegroundColor Yellow
    $kvName = $null
}

Write-Host "✓ Bicep deployment succeeded ($deploymentName)." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 6. AKS credentials
# -----------------------------------------------------------------------------
Write-Section "AKS credentials ($aksClusterName)"
Invoke-AzOrFail -Description 'az aks get-credentials' -Args @(
    'aks','get-credentials',
    '--resource-group', $ResourceGroupName,
    '--name', $aksClusterName,
    '--overwrite-existing',
    '--output','none'
) | Out-Null
Write-Host "✓ kubectl context set to $aksClusterName." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. TLS certificate provisioning
# -----------------------------------------------------------------------------
Write-Section 'TLS certificate (Key Vault: tls-cert-ops-agent)'

$certHost = "ops-agent.$dnsZoneNameOut"
Write-Host "The Ingress in Step 10 expects a Key Vault certificate named EXACTLY 'tls-cert-ops-agent'" -ForegroundColor Yellow
Write-Host "with CN/SAN = $certHost" -ForegroundColor Yellow
Write-Host ''

if ($CertificatePfxPath) {
    if (-not (Test-Path $CertificatePfxPath)) {
        Write-Host "❌ PFX file not found: $CertificatePfxPath" -ForegroundColor Red
        exit 1
    }
    Write-Host "Importing PFX into Key Vault $kvName as 'tls-cert-ops-agent'..."

    # Materialize plaintext password only for the single CLI call, then zero it.
    $plainPw = $null
    $bstr    = [IntPtr]::Zero
    try {
        if ($CertificatePfxPassword) {
            $plainPw = ConvertFrom-SecureString -SecureString $CertificatePfxPassword -AsPlainText
        }

        $importArgs = @(
            'keyvault','certificate','import',
            '--vault-name', $kvName,
            '--name','tls-cert-ops-agent',
            '--file', $CertificatePfxPath,
            '--output','none'
        )
        if ($plainPw) {
            $importArgs += @('--password', $plainPw)
        }
        Invoke-AzOrFail -Description 'az keyvault certificate import' -Args $importArgs | Out-Null
        Write-Host '✓ Certificate imported.' -ForegroundColor Green
    }
    finally {
        if ($plainPw) {
            # Best-effort scrub of the plaintext from memory before GC.
            $plainPw = ('0' * $plainPw.Length)
            Remove-Variable -Name plainPw -ErrorAction SilentlyContinue
        }
    }
}
else {
    # If the cert already exists in Key Vault (e.g., imported manually before
    # this run), skip the interactive prompt entirely. This keeps re-runs
    # idempotent and supports -NonInteractive automation.
    $existingCertJson = az keyvault certificate show --vault-name $kvName --name tls-cert-ops-agent --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingCertJson) {
        Write-Host "✓ Certificate 'tls-cert-ops-agent' already exists in Key Vault $kvName; skipping import prompt." -ForegroundColor Green
    }
    else {
        Write-Host 'No -CertificatePfxPath supplied. Provision the TLS cert manually using ONE of:' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  (a) Import an existing CA-issued PFX into Key Vault:'
        Write-Host "      az keyvault certificate import \"
        Write-Host "        --vault-name $kvName \"
        Write-Host "        --name tls-cert-ops-agent \"
        Write-Host "        --file <path-to-pfx> \"
        Write-Host "        --password <pfx-password>"
        Write-Host ''
        Write-Host '  (b) Use Key Vault''s CA integration (DigiCert / GlobalSign):'
        Write-Host "      Azure portal → Key Vault $kvName → Certificates → Generate/Import →"
        Write-Host "      Method: 'Generate', Issuer: DigiCert or GlobalSign, Subject CN: $certHost,"
        Write-Host "        Certificate name: tls-cert-ops-agent."
        Write-Host '      (Requires an active CA account configured under Certificate Authorities.)'
        Write-Host ''
        Write-Host '  (c) cert-manager + Let''s Encrypt (deferred — see docs/how-to-demo.md):'
        Write-Host "      Install cert-manager into the cluster, define a ClusterIssuer for ACME HTTP-01,"
        Write-Host "      and let cert-manager issue and rotate the cert. The Ingress annotation in Step 10"
        Write-Host "      points to Key Vault, so this path also requires uploading the issued cert to KV."
        Write-Host ''
        if ($NonInteractive) {
            Write-Host "❌ -NonInteractive set but no certificate found in Key Vault $kvName as 'tls-cert-ops-agent'." -ForegroundColor Red
            Write-Host "  Import a cert (option (a) above) before re-running, OR drop -NonInteractive." -ForegroundColor Red
            exit 1
        }
        Write-Host "After the cert exists in Key Vault as 'tls-cert-ops-agent', press Enter to continue." -ForegroundColor Yellow
        Read-Host -Prompt 'Press Enter when the certificate is imported and visible in Key Vault' | Out-Null
    }
}

# -----------------------------------------------------------------------------
# Verify cert
# -----------------------------------------------------------------------------
Write-Host ''
Write-Host "Verifying certificate 'tls-cert-ops-agent' in Key Vault $kvName ..."
$certShowJson = az keyvault certificate show --vault-name $kvName --name tls-cert-ops-agent --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host '❌ Certificate not found or inaccessible.' -ForegroundColor Red
    Write-Host $certShowJson -ForegroundColor Red
    exit 1
}
try {
    $cert = $certShowJson | ConvertFrom-Json
}
catch {
    Write-Host '❌ Could not parse certificate JSON.' -ForegroundColor Red
    exit 1
}

$enabled = [bool]$cert.attributes.enabled
$expires = $null
if ($cert.attributes.expires) {
    try { $expires = [DateTime]::Parse($cert.attributes.expires) } catch { $expires = $null }
}

if (-not $enabled) {
    Write-Host '❌ Certificate is disabled (attributes.enabled = false).' -ForegroundColor Red
    exit 1
}
if ($null -eq $expires) {
    Write-Host '❌ Could not read certificate expiry.' -ForegroundColor Red
    exit 1
}
$daysToExpiry = ($expires - [DateTime]::UtcNow).TotalDays
if ($daysToExpiry -lt 30) {
    Write-Host ("❌ Certificate expires in {0:N1} days (must be ≥ 30)." -f $daysToExpiry) -ForegroundColor Red
    exit 1
}
Write-Host ("✓ Certificate valid; enabled=true; expires {0:yyyy-MM-dd} ({1:N0} days)." -f $expires, $daysToExpiry) -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Summary + next steps
# -----------------------------------------------------------------------------
Write-Section 'Deployment Summary'

$summary = [ordered]@{
    'Resource group'                 = $ResourceGroupName
    'Location'                       = $Location
    'Foundry account'                  = $foundryAccountName
    'Foundry project'                  = $projectName
    'Foundry project endpoint'         = $foundryEndpoint
    'Foundry account inference endpoint' = $foundryAccountEndpoint
    'Orchestrator deployment'          = $orchestratorDeploymentName
    'Worker deployment'              = $workerDeploymentName
    'AKS cluster'                    = $aksClusterName
    'ACR login server'               = $acrLoginServer
    'Key Vault name'                 = $kvName
    'Key Vault URI'                  = $keyVaultUri
    'DNS zone'                       = $dnsZoneNameOut
    'UAMI client ID'                 = $uamiClientId
    'UAMI principal (object) ID'     = $uamiPrincipalId
    'App Insights name'              = $appInsightsName
    'App Insights resource ID'       = $appInsightsId
    'App Insights connection string' = $appInsightsConnectionString
}
foreach ($k in $summary.Keys) {
    Write-Host ("{0,-32} : {1}" -f $k, $summary[$k])
}

Write-Section "DNS Delegation — add these NS records at the parent domain registrar for '$dnsZoneNameOut'"
if ($dnsZoneNameServers) {
    foreach ($ns in $dnsZoneNameServers) {
        Write-Host ("  NS  {0}" -f $ns)
    }
}
else {
    Write-Host '  (No name servers returned from Bicep output — query manually with `az network dns zone show`.)' -ForegroundColor Yellow
}

Write-Section 'Next steps'
Write-Host 'Step 15 — build, push, and deploy the Ops Agent to AKS:' -ForegroundColor Cyan
Write-Host ''
$nextCmd  = "./scripts/deploy-k8s.ps1 ``"
$nextCmd += "`n    -AcrLoginServer $acrLoginServer ``"
$nextCmd += "`n    -KvName $kvName ``"
$nextCmd += "`n    -UamiClientId $uamiClientId ``"
$nextCmd += "`n    -DnsZone $dnsZoneNameOut ``"
$nextCmd += "`n    -FoundryEndpoint $foundryEndpoint ``"
$nextCmd += "`n    -FoundryAccountEndpoint $foundryAccountEndpoint ``"
$nextCmd += "`n    -WorkerDeployment $workerDeploymentName"
Write-Host $nextCmd
Write-Host ''
Write-Host 'Then Step 16: ./scripts/setup-foundry-agent.ps1' -ForegroundColor Cyan
Write-Host ''
Write-Host '✓ Infrastructure deployment complete.' -ForegroundColor Green
exit 0
