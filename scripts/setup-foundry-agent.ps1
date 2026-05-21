<#
.SYNOPSIS
    Provision the Foundry V2 customer-service agent, wire up its A2A connection
    to the AKS-hosted Ops Agent, and verify Tier 1 trace propagation.

.DESCRIPTION
    Orchestrates the manual + scripted steps required to bring the Foundry side
    of the demo online once the AKS endpoint is live (after deploy-k8s.ps1).

    Phases:
      1. A2A connection setup       (Foundry portal + create_a2a_connection.py)
      2. Agent creation             (setup_agent.py)
      3. Initial smoke test         (test_agent.py)
      4. App Insights linkage       (manual portal step)
      5. Trace verification + KQL   (test_agent.py + az monitor app-insights query)
      6. Final summary

    DO NOT run this in a CI pipeline that lacks the Foundry portal access
    required by Phase 1 and Phase 4, unless -SkipManualGates is supplied
    (in which case the deployer is expected to have completed the portal
    steps out-of-band).

    Citations:
      - plan.md §C Step 16 (Foundry agent provisioning + A2A connection)
      - research/2026-05-20-foundry-control-plane.md §2.3 (Tier 1 traces)
      - research/2026-05-20-foundry-control-plane.md §4.1 (App Insights link)

.PARAMETER FoundryEndpoint
    Foundry project endpoint, e.g.
    https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility

.PARAMETER OrchestratorDeploymentName
    Model deployment name for the orchestrator agent (default: gpt-55-orchestrator).

.PARAMETER A2aConnectionName
    Name of the A2A connection to create in the Foundry project
    (default: ops-agent-a2a).

.PARAMETER FoundryAgentName
    Name of the Foundry agent to create (default: zava-customer-service).

.PARAMETER OpsAgentEndpoint
    Public HTTPS endpoint of the AKS-hosted Ops Agent (from deploy-k8s.ps1 output),
    e.g. https://ops-agent.zava.example.com/

.PARAMETER OpsAgentApiKey
    Shared secret for x-api-key auth to the Ops Agent (from `kubectl get secret`
    or the deploy-k8s.ps1 output).

.PARAMETER AppInsightsName
    Name of the App Insights resource created by appinsights.bicep (used for the
    Phase 5 KQL fallback diagnostic).

.PARAMETER FoundryAgentDir
    Path to the foundry-agent app folder containing the Python helpers
    (default: apps/foundry-agent).

.PARAMETER SkipManualGates
    Skip Read-Host pauses (for unattended re-runs after manual portal steps
    have already been completed). Default: $false.

.EXAMPLE
    ./scripts/setup-foundry-agent.ps1 `
        -FoundryEndpoint "https://foundry-zava-a2a-smartorder.services.ai.azure.com/api/projects/smart-order-feasibility" `
        -OpsAgentEndpoint "https://ops-agent.zava-a2a-smart-order.example.com/" `
        -OpsAgentApiKey  "<secret-from-kubectl>" `
        -AppInsightsName "appi-zava-a2a-smart-order"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FoundryEndpoint,

    [string]$OrchestratorDeploymentName = "gpt-55-orchestrator",

    [string]$A2aConnectionName = "ops-agent-a2a",

    [string]$FoundryAgentName = "zava-customer-service",

    [Parameter(Mandatory = $true)]
    [string]$OpsAgentEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$OpsAgentApiKey,

    [Parameter(Mandatory = $true)]
    [string]$AppInsightsName,

    [string]$FoundryAgentDir = "apps/foundry-agent",

    [switch]$SkipManualGates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Banner {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Lines = @()
    )
    $bar = ('=' * 72)
    Write-Host ""
    Write-Host $bar -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan
    foreach ($line in $Lines) {
        Write-Host $line
    }
    Write-Host $bar -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Python {
    <#
        Runs a python script under the current interpreter, surfaces stderr
        on non-zero exit, and returns captured stdout as a single string.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [string]$Label = "python"
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "[$Label] Script not found: $ScriptPath"
    }

    $stdoutFile = New-TemporaryFile
    $stderrFile = New-TemporaryFile

    try {
        $argList = @($ScriptPath) + $ScriptArgs
        $proc = Start-Process -FilePath "python" `
            -ArgumentList $argList `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutFile.FullName `
            -RedirectStandardError  $stderrFile.FullName

        $stdout = Get-Content -LiteralPath $stdoutFile.FullName -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrFile.FullName -Raw -ErrorAction SilentlyContinue

        if ($stdout) { Write-Host $stdout }

        if ($proc.ExitCode -ne 0) {
            if ($stderr) {
                Write-Host "----- [$Label] stderr -----" -ForegroundColor Red
                Write-Host $stderr -ForegroundColor Red
                Write-Host "---------------------------" -ForegroundColor Red
            }
            throw "[$Label] python exited with code $($proc.ExitCode)"
        }

        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = if ($stdout) { $stdout } else { "" }
            StdErr   = if ($stderr) { $stderr } else { "" }
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile.FullName -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile.FullName -ErrorAction SilentlyContinue
    }
}

function Wait-ForManualGate {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    if ($SkipManualGates) {
        Write-Host "[skip-manual-gates] $Prompt" -ForegroundColor Yellow
        return
    }
    [void](Read-Host -Prompt $Prompt)
}

# ---------------------------------------------------------------------------
# Pre-flight: export environment + summary banner
# ---------------------------------------------------------------------------

$env:FOUNDRY_PROJECT_ENDPOINT       = $FoundryEndpoint
$env:FOUNDRY_ORCHESTRATOR_DEPLOYMENT = $OrchestratorDeploymentName
$env:A2A_CONNECTION_NAME            = $A2aConnectionName
$env:FOUNDRY_AGENT_NAME             = $FoundryAgentName
$env:OPS_AGENT_ENDPOINT             = $OpsAgentEndpoint
$env:OPS_AGENT_API_KEY              = $OpsAgentApiKey

Write-Banner -Title "FOUNDRY AGENT PROVISIONING" -Lines @(
    "Foundry endpoint     : $FoundryEndpoint",
    "Orchestrator model   : $OrchestratorDeploymentName",
    "A2A connection name  : $A2aConnectionName",
    "Agent name           : $FoundryAgentName",
    "Ops Agent endpoint   : $OpsAgentEndpoint",
    "API key length       : $($OpsAgentApiKey.Length) chars (value hidden)",
    "App Insights name    : $AppInsightsName",
    "Foundry agent dir    : $FoundryAgentDir",
    "Skip manual gates    : $SkipManualGates"
)

$createA2AScript = Join-Path $FoundryAgentDir "create_a2a_connection.py"
$setupAgentScript = Join-Path $FoundryAgentDir "setup_agent.py"
$testAgentScript  = Join-Path $FoundryAgentDir "test_agent.py"

foreach ($s in @($createA2AScript, $setupAgentScript, $testAgentScript)) {
    if (-not (Test-Path -LiteralPath $s)) {
        throw "Required Python script not found: $s"
    }
}

# Record wall-clock start so the KQL fallback can decide if we're past 10 minutes.
$provisioningStart = Get-Date

# ---------------------------------------------------------------------------
# PHASE 1 — A2A connection setup
# ---------------------------------------------------------------------------

Write-Banner -Title "PHASE 1 — A2A CONNECTION SETUP" -Lines @(
    "Paste the API key below into the Foundry portal A2A connection form.",
    "(Foundry portal -> Project -> Connected resources -> + Custom keys)",
    "",
    "    +" + ('-' * 68) + "+",
    "    | OPS AGENT API KEY (copy exactly, no surrounding whitespace):    |",
    "    +" + ('-' * 68) + "+",
    "    | $OpsAgentApiKey",
    "    +" + ('-' * 68) + "+"
)

try {
    Invoke-Python -ScriptPath $createA2AScript -Label "create_a2a_connection.py" | Out-Null
}
catch {
    Write-Host "create_a2a_connection.py (instructions + SDK fallback) reported an error." -ForegroundColor Yellow
    Write-Host "This is non-fatal if you intend to complete the connection via the portal." -ForegroundColor Yellow
    Write-Host "Detail: $($_.Exception.Message)" -ForegroundColor Yellow
}

Wait-ForManualGate -Prompt "Press Enter once the portal A2A connection has been created (or after SDK fallback succeeded)"

Write-Host "Verifying A2A connection exists ..." -ForegroundColor Cyan
try {
    Invoke-Python -ScriptPath $createA2AScript -ScriptArgs @("--verify") -Label "create_a2a_connection.py --verify" | Out-Null
}
catch {
    Write-Host "A2A connection verification FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host "✓ A2A connection '$A2aConnectionName' verified in Foundry project." -ForegroundColor Green

# ---------------------------------------------------------------------------
# PHASE 2 — Agent creation
# ---------------------------------------------------------------------------

Write-Banner -Title "PHASE 2 — AGENT CREATION" -Lines @(
    "Creating Foundry agent '$FoundryAgentName' with Code Interpreter +",
    "A2A tool bound to connection '$A2aConnectionName'."
)

$setupResult = $null
try {
    $setupResult = Invoke-Python -ScriptPath $setupAgentScript -Label "setup_agent.py"
}
catch {
    Write-Host "setup_agent.py FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Best-effort parse of agent id / version from the script's stdout.
$agentVersion = "<unreported>"
$agentId      = "<unreported>"
if ($setupResult -and $setupResult.StdOut) {
    $verMatch = [regex]::Match($setupResult.StdOut, '(?im)^\s*(?:version|agent\s*version)\s*[:=]\s*([^\r\n]+)')
    if ($verMatch.Success) { $agentVersion = $verMatch.Groups[1].Value.Trim() }
    $idMatch = [regex]::Match($setupResult.StdOut, '(?im)^\s*(?:id|agent\s*id)\s*[:=]\s*([^\r\n]+)')
    if ($idMatch.Success) { $agentId = $idMatch.Groups[1].Value.Trim() }
}
Write-Host "✓ Agent created  (name=$FoundryAgentName, version=$agentVersion, id=$agentId)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# PHASE 3 — Initial smoke test
# ---------------------------------------------------------------------------

Write-Banner -Title "PHASE 3 — INITIAL SMOKE TEST" -Lines @(
    "Running test_agent.py — asserts text response, chart artifact, A2A hop,",
    "and R16 structured-passthrough of the Ops Agent feasibility result."
)

$firstTestStdout = ""
try {
    $r = Invoke-Python -ScriptPath $testAgentScript -Label "test_agent.py (phase 3)"
    $firstTestStdout = $r.StdOut
}
catch {
    Write-Host "test_agent.py FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($firstTestStdout) {
        Write-Host "----- last 20 lines of test output -----" -ForegroundColor Red
        ($firstTestStdout -split "`n" | Select-Object -Last 20) | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "----------------------------------------" -ForegroundColor Red
    }
    exit 1
}
Write-Host "✓ Phase 3 smoke test passed." -ForegroundColor Green

# ---------------------------------------------------------------------------
# PHASE 4 — App Insights -> Foundry linkage (manual portal step)
# ---------------------------------------------------------------------------

# Best-effort project-name extraction from the endpoint URL.
$projectName = "<your-project>"
$projMatch = [regex]::Match($FoundryEndpoint, 'projects/([^/?#]+)')
if ($projMatch.Success) { $projectName = $projMatch.Groups[1].Value }

Write-Banner -Title "PHASE 4 — MANUAL PORTAL STEP: APP INSIGHTS LINKAGE" -Lines @(
    "1. Open the Azure portal -> Foundry resource -> Projects -> $projectName",
    "2. Project settings -> Connected resources",
    "3. Click 'Add Application Insights'",
    "4. Select the App Insights resource: $AppInsightsName",
    "5. Save",
    "",
    "Then enable tracing:",
    "6. Portal -> Project -> Tracing",
    "7. Toggle 'Enable' -> Save",
    "",
    "Citation: research/2026-05-20-foundry-control-plane.md §4.1 + §2.3"
)

Wait-ForManualGate -Prompt "Press Enter once the Connected resources show App Insights AND Tracing is enabled"

# ---------------------------------------------------------------------------
# PHASE 5 — Trace propagation verification (with KQL fallback)
# ---------------------------------------------------------------------------

Write-Banner -Title "PHASE 5 — TRACE PROPAGATION VERIFICATION" -Lines @(
    "Generating a fresh trace by invoking test_agent.py one more time, then",
    "polling the Foundry portal Traces tab (manual) and/or the App Insights",
    "KQL fallback (automated)."
)

try {
    Invoke-Python -ScriptPath $testAgentScript -Label "test_agent.py (phase 5)" | Out-Null
}
catch {
    Write-Host "Second test_agent.py invocation FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$freshTraceTime = Get-Date

$portalSawTrace = $null   # $true / $false / $null (skipped)
if (-not $SkipManualGates) {
    Write-Host ""
    Write-Host "Polling Foundry portal Traces tab — manual visual check (the next 5 minutes)." -ForegroundColor Cyan
    Write-Host "Press Enter when you see at least one trace row, or after 5 minutes." -ForegroundColor Cyan
    $answer = Read-Host -Prompt "Did you see at least one trace row in the Foundry portal? (y/n)"
    $portalSawTrace = ($answer -match '^(y|yes)$')
}

$kqlPass = $false
$runKql  = $SkipManualGates -or ($portalSawTrace -ne $true)

if ($runKql) {
    Write-Host ""
    Write-Host "Running App Insights KQL fallback diagnostic ..." -ForegroundColor Cyan
    $kqlQuery = "requests | where timestamp > ago(10m) | where customDimensions.gen_ai_agent_name == '$FoundryAgentName' | take 5"

    try {
        $kqlRaw = az monitor app-insights query `
            --apps $AppInsightsName `
            --analytics-query $kqlQuery `
            --output json 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            throw "az monitor app-insights query exited $LASTEXITCODE. Output: $kqlRaw"
        }

        $kqlObj = $kqlRaw | ConvertFrom-Json -ErrorAction Stop
        $rows = @()
        if ($kqlObj -and $kqlObj.tables -and $kqlObj.tables.Count -gt 0 -and $kqlObj.tables[0].rows) {
            $rows = $kqlObj.tables[0].rows
        }

        if ($rows.Count -gt 0) {
            $kqlPass = $true
            Write-Host "✓ KQL fallback PASS — traces ARE flowing ($($rows.Count) row(s) in last 10 min)." -ForegroundColor Green
            Write-Host "  Foundry portal Traces UI may have lag. Wait 5-10 min and refresh portal." -ForegroundColor Green
        }
        else {
            $minutesElapsed = ((Get-Date) - $provisioningStart).TotalMinutes
            if ($minutesElapsed -ge 10) {
                Write-Host "❌ KQL fallback FAIL — App Insights -> Foundry linkage appears broken." -ForegroundColor Red
                Write-Host "   Troubleshooting:" -ForegroundColor Red
                Write-Host "     * Re-check 'Connected resources' in the Foundry portal." -ForegroundColor Red
                Write-Host "     * Ensure the App Insights resource ID matches the one created by Step 14." -ForegroundColor Red
                Write-Host "     * Verify the Foundry tracing toggle is actually enabled (Phase 4)." -ForegroundColor Red
            }
            else {
                Write-Host "⚠ KQL returned 0 rows so far (only $([int]$minutesElapsed) min since start)." -ForegroundColor Yellow
                Write-Host "  Both portal and App Insights can lag a few minutes. Re-run this script with" -ForegroundColor Yellow
                Write-Host "  -SkipManualGates after waiting, or manually re-issue the KQL query." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "⚠ KQL fallback could not be executed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  (App Insights may not yet be linked, or 'az' is not authenticated to the right subscription.)" -ForegroundColor Yellow
    }
}

$tracesVerified = ($portalSawTrace -eq $true) -or $kqlPass

# ---------------------------------------------------------------------------
# PHASE 6 — Final summary
# ---------------------------------------------------------------------------

Write-Banner -Title "PHASE 6 — FOUNDRY AGENT PROVISIONING COMPLETE" -Lines @(
    "Agent name           : $FoundryAgentName",
    "Agent version        : $agentVersion",
    "Agent id             : $agentId",
    "A2A connection       : $A2aConnectionName -> $OpsAgentEndpoint",
    "App Insights         : $AppInsightsName",
    ("Traces verified      : " + ($(if ($tracesVerified) { "YES" } else { "NO" }))),
    "",
    "Demo is now ready. Start the local backend + frontend (see docs/how-to-demo.md)."
)

if (-not $tracesVerified) {
    Write-Host "NOTE: Trace verification was not confirmed. The demo will still run, but" -ForegroundColor Yellow
    Write-Host "      the Foundry portal Traces tab may remain empty until linkage is fixed." -ForegroundColor Yellow
}
