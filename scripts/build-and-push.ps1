<#
.SYNOPSIS
    Builds the Ops Agent container image inside Azure Container Registry (ACR)
    using `az acr build` and verifies the resulting tag is present in the
    registry. Step 15 (plan.md), part 1 of 2.

.DESCRIPTION
    Server-side build via `az acr build` is preferred over a local
    `docker build` + `docker push` because it:
      - removes the local Docker daemon dependency (works on dev boxes that
        don't have Docker Desktop installed);
      - performs the build inside ACR's build environment (architecture-matched
        to the AKS node pool — amd64 Linux by default in this demo);
      - reuses ACR's authenticated context, so no separate `docker login` is
        required (the caller just needs to be signed in via `az login` with
        the AcrPush role or higher on the registry).

    The script does NOT push to AKS or modify cluster state — that is handled
    by scripts/deploy-k8s.ps1.

    Idempotency: re-running with the same -ImageTag overwrites the tag in ACR
    (intended). Re-running with a fresh tag adds an additional tag and leaves
    older ones alone.

.PARAMETER AcrLoginServer
    REQUIRED. Fully-qualified ACR login server (e.g.,
    `acrzavaa2asmartorderabc123.azurecr.io`). Surfaced by scripts/deploy-infra.ps1 in
    its final summary as "ACR login server".

.PARAMETER AcrName
    Optional. ACR resource name without the `.azurecr.io` suffix (e.g.,
    `acrzavaa2asmartorderabc123`). If omitted, derived by stripping `.azurecr.io` from
    -AcrLoginServer.

.PARAMETER ImageTag
    Optional. Tag to apply to the built image. Default: `latest`. The Step 10
    Deployment manifest currently references `ops-agent:latest`; if you build
    a non-latest tag here you must pass the same -ImageTag to
    scripts/deploy-k8s.ps1 so the manifest substitution stays in sync.

.PARAMETER DockerfilePath
    Optional. Path (repo-relative or absolute) to the Dockerfile. Default:
    `apps/ops-agent/Dockerfile`.

.PARAMETER ContextPath
    Optional. Build context directory. Default: `apps/ops-agent`.

.EXAMPLE
    ./scripts/build-and-push.ps1 -AcrLoginServer acrzavaa2asmartorderabc123.azurecr.io
    Build with all defaults; produces `ops-agent:latest` in the registry.

.EXAMPLE
    ./scripts/build-and-push.ps1 -AcrLoginServer acrzavaa2asmartorderabc123.azurecr.io -ImageTag v1.0.0
    Build a versioned tag. Remember to pass `-ImageTag v1.0.0` to deploy-k8s.ps1.

.NOTES
    Verification (post-build): the script lists tags in the `ops-agent`
    repository and asserts that the requested tag appears. A non-zero
    `az acr build` exit causes immediate abort with the underlying error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AcrLoginServer,

    [Parameter(Mandatory = $false)]
    [string] $AcrName,

    [Parameter(Mandatory = $false)]
    [string] $ImageTag = 'latest',

    [Parameter(Mandatory = $false)]
    [string] $DockerfilePath = 'apps/ops-agent/Dockerfile',

    [Parameter(Mandatory = $false)]
    [string] $ContextPath = 'apps/ops-agent'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Force UTF-8 I/O so `az acr build` can stream build logs containing non-ASCII
# characters (e.g. pip's box-drawing progress bars U+2501) without crashing on
# the default Windows cp1252 stdout encoding. PYTHONUTF8=1 enables Python's
# "UTF-8 mode" globally inside the Python child process the Azure CLI runs as,
# which overrides the cp1252 locale that colorama otherwise inherits.
# Without these env vars the `az acr build` call can fail with a
# UnicodeEncodeError mid-stream even though the actual image build inside ACR
# succeeded. See docs/deployment-learnings.md §11.
# -----------------------------------------------------------------------------
$env:PYTHONUTF8        = '1'
$env:PYTHONIOENCODING  = 'utf-8'
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding           = [System.Text.UTF8Encoding]::new($false)
} catch {
    # On older PowerShell hosts setting console encoding can throw; the
    # PYTHONUTF8/PYTHONIOENCODING env vars alone are usually sufficient.
}

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

function Invoke-AzOrFail {
    param(
        [Parameter(Mandatory = $true)] [string]   $Description,
        [Parameter(Mandatory = $true)] [string[]] $AzArgs
    )
    Write-Verbose ("az " + ($AzArgs -join ' '))
    $out = & az @AzArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ $Description failed:" -ForegroundColor Red
        Write-Host ($out | Out-String) -ForegroundColor Red
        exit 1
    }
    return $out
}

# -----------------------------------------------------------------------------
# 0. Derive AcrName from AcrLoginServer if not provided
# -----------------------------------------------------------------------------
if (-not $AcrName) {
    if ($AcrLoginServer -match '^([^.]+)\.azurecr\.io$') {
        $AcrName = $Matches[1]
    }
    else {
        Write-Host "❌ Could not derive ACR name from '$AcrLoginServer'. Expected '<name>.azurecr.io' or pass -AcrName explicitly." -ForegroundColor Red
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Resolve repo-rooted paths so the script works regardless of cwd.
# -----------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot  = Split-Path -Parent $scriptDir

function Resolve-RepoPath {
    param([string] $Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $repoRoot $Path)
}

$dockerfileAbs = Resolve-RepoPath $DockerfilePath
$contextAbs    = Resolve-RepoPath $ContextPath

if (-not (Test-Path $dockerfileAbs)) {
    Write-Host "❌ Dockerfile not found: $dockerfileAbs" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $contextAbs)) {
    Write-Host "❌ Build context not found: $contextAbs" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Pre-flight: az version, current subscription
# -----------------------------------------------------------------------------
Write-Section 'Pre-flight'

try {
    $azVerJson = & az version --output json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "az version failed: $azVerJson" }
    $azVer = ($azVerJson | Out-String) | ConvertFrom-Json
    Write-Host ("az CLI version           : {0}" -f $azVer.'azure-cli')
}
catch {
    Write-Host "❌ Could not run 'az version'. Is the Azure CLI installed and on PATH?" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

try {
    $subJson = & az account show --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az account show failed. Run 'az login' first.`n$subJson"
    }
    $sub = ($subJson | Out-String) | ConvertFrom-Json
    Write-Host ("Subscription             : {0} ({1})" -f $sub.name, $sub.id)
    Write-Host ("Tenant                   : {0}" -f $sub.tenantId)
}
catch {
    Write-Host "❌ Not signed in to Azure." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ("ACR login server         : {0}" -f $AcrLoginServer)
Write-Host ("ACR name                 : {0}" -f $AcrName)
Write-Host ("Image tag                : {0}" -f $ImageTag)
Write-Host ("Dockerfile               : {0}" -f $dockerfileAbs)
Write-Host ("Build context            : {0}" -f $contextAbs)

# -----------------------------------------------------------------------------
# 2. az acr build
# -----------------------------------------------------------------------------
Write-Section "az acr build → ops-agent:$ImageTag"

$buildArgs = @(
    'acr','build',
    '--registry', $AcrName,
    '--image', ("ops-agent:{0}" -f $ImageTag),
    '--file', $dockerfileAbs,
    '--no-logs',
    $contextAbs
)
# --no-logs: Queue + wait for the build, but do not stream the log lines back
# to PowerShell. This avoids a Windows-only Azure CLI crash where pip's
# Unicode box-drawing progress bars (U+2501) inside the ACR build log can't
# be encoded to cp1252 by the bundled Python's stdout, killing the CLI
# mid-stream even though the actual image build succeeded.
# See docs/deployment-learnings.md §11.
# On build failure, retrieve full logs with:
#   az acr task logs --registry <acrName> --run-id <runId>
Invoke-AzOrFail -Description 'az acr build' -AzArgs $buildArgs | Out-Host
Write-Host "✓ Build completed." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Verify the tag exists in ACR
# -----------------------------------------------------------------------------
Write-Section "Verify tag in ACR"

$tagsJson = Invoke-AzOrFail -Description 'az acr repository show-tags' -AzArgs @(
    'acr','repository','show-tags',
    '--name', $AcrName,
    '--repository','ops-agent',
    '--output','json'
)

try {
    $tags = ($tagsJson | Out-String) | ConvertFrom-Json
}
catch {
    Write-Host "❌ Could not parse tag list returned by ACR." -ForegroundColor Red
    Write-Host ($tagsJson | Out-String) -ForegroundColor Red
    exit 1
}

Write-Host ("Tags in ops-agent repository: {0}" -f (($tags | ForEach-Object { $_ }) -join ', '))

if ($tags -notcontains $ImageTag) {
    Write-Host "❌ Tag '$ImageTag' not found in repository after build." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Tag '$ImageTag' present in ACR." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 4. Summary
# -----------------------------------------------------------------------------
$imageUrl = "{0}/ops-agent:{1}" -f $AcrLoginServer, $ImageTag

Write-Section 'BUILD SUMMARY'
Write-Host ("Image URL                : {0}" -f $imageUrl)
Write-Host ''
Write-Host 'Manual pull verification (optional):'
Write-Host ("  az acr login --name {0}" -f $AcrName)
Write-Host ("  docker pull {0}" -f $imageUrl)
Write-Host ''
Write-Host 'Next step: deploy to AKS'
Write-Host ("  ./scripts/deploy-k8s.ps1 -AcrLoginServer {0} -ImageTag {1} ..." -f $AcrLoginServer, $ImageTag)
Write-Host ''
Write-Host '✓ Build and push complete.' -ForegroundColor Green
exit 0
