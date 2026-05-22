<#
.SYNOPSIS
    End-to-end smoke test for the Zava Smart Order Feasibility A2A demo.

.DESCRIPTION
    Read-only validation script. Probes the full stack and reports PASS / FAIL
    for each check. The script never mutates Azure resources — it only issues
    GET / POST requests and inspects the responses, so it is fully idempotent.

    Checks (each can be skipped with the corresponding switch):

      Cluster (skipped with -SkipCluster):
        1. AKS ops-agent /health        — GET https://<sub>.<dnsZone>/health
        2. AKS ops-agent Agent Card     — GET /.well-known/agent-card.json
        3. A2A endpoint message/send    — POST / with v0.3 JSON-RPC envelope

      Local (skipped with -SkipLocal):
        4. Backend /api/health          — GET http://localhost:8000/api/health
        5. Frontend dev server          — GET http://localhost:5173/
        6. Full integration             — POST /api/chat → SSE stream parses

      Always:
        7. Foundry tracing instructions — printed reminder; no automation

    Exit codes:
      0 = every executed check passed (or was skipped)
      1 = at least one executed check failed

    Header / route choices (verified against source):
      * Authorization header for the A2A endpoint is `x-api-key`
        (NOT `Authorization: Bearer`). See apps/ops-agent/app/server.py:43,76
        and docs/a2a-implementation.md §4.2 / §5.1.
      * The A2A endpoint is mounted at the root path `/`. See
        apps/ops-agent/app/server.py:137 (`create_jsonrpc_routes(handler, "/")`).
      * The v0.3 `message/send` envelope (jsonrpc 2.0, params.message with a
        TextPart) matches docs/a2a-implementation.md §4.2.
      * No `A2A-Version` header is sent; the server is configured with
        `enable_v0_3_compat=True` and treats the absence of the header as v0.3
        (server.py:137; docs/a2a-implementation.md §6).
      * `/api/chat` request schema (sku, quantity, target_date, customer_id)
        comes from apps/backend/app/models.py ChatRequest (lines 32–51).
      * SSE event shape `data: {"type": ..., "data": {...}}\n\n` is defined in
        apps/backend/app/main.py:_format_sse and AgentEvent in models.py.

.PARAMETER DnsZone
    Public DNS zone the AKS ingress is exposed on. Defaults to
    $env:DNS_ZONE if set, otherwise "zava.example.com".

.PARAMETER OpsAgentSubdomain
    Subdomain of the ops-agent under DnsZone. Default: "ops-agent".

.PARAMETER BackendUrl
    Base URL for the local FastAPI backend. Default: http://localhost:8000.

.PARAMETER FrontendUrl
    Base URL for the local Vite dev server. Default: http://localhost:5173.

.PARAMETER ApiKey
    Shared-secret API key sent in the `x-api-key` header on the A2A request.
    Defaults to $env:A2A_API_KEY. Required for the A2A check; if missing,
    the A2A check is reported as FAIL with an explanatory note.

.PARAMETER SkipLocal
    Skip the backend, frontend, and full-integration checks (4, 5, 6).

.PARAMETER SkipCluster
    Skip the AKS health, agent-card, and A2A checks (1, 2, 3).

.EXAMPLE
    ./scripts/smoke-test.ps1
    Run all checks against defaults, using $env:DNS_ZONE and $env:A2A_API_KEY.

.EXAMPLE
    ./scripts/smoke-test.ps1 -SkipLocal
    Cluster-only validation (e.g., from CI).

.EXAMPLE
    ./scripts/smoke-test.ps1 -SkipCluster
    Local-only validation (when AKS is not reachable from the dev box).

.EXAMPLE
    ./scripts/smoke-test.ps1 -DnsZone contoso.com -OpsAgentSubdomain ops `
        -ApiKey (Get-Content ./.api-key) -Verbose
    Full run with verbose response dumps on failure.
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $DnsZone = $(if ($env:DNS_ZONE) { $env:DNS_ZONE } else { 'zava.example.com' }),

    [Parameter(Mandatory = $false)]
    [string] $OpsAgentSubdomain = 'ops-agent',

    [Parameter(Mandatory = $false)]
    [string] $OpsAgentEndpoint,

    [Parameter(Mandatory = $false)]
    [string] $BackendUrl = 'http://localhost:8000',

    [Parameter(Mandatory = $false)]
    [string] $FrontendUrl = 'http://localhost:5173',

    [Parameter(Mandatory = $false)]
    [string] $ApiKey = $env:A2A_API_KEY,

    [Parameter(Mandatory = $false)]
    [switch] $SkipLocal,

    [Parameter(Mandatory = $false)]
    [switch] $SkipCluster
)

$ErrorActionPreference = 'Stop'
# `-Verbose` is provided automatically by [CmdletBinding()]; check the
# preference to decide whether to print full HTTP bodies on failure.
$verboseMode = ($VerbosePreference -ne 'SilentlyContinue')

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
# Each entry is a [pscustomobject] with: Check, Status (PASS|FAIL|SKIP), Notes.
$script:results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)] [string] $Check,
        [Parameter(Mandatory)] [ValidateSet('PASS', 'FAIL', 'SKIP')] [string] $Status,
        [string] $Notes = ''
    )
    $script:results.Add([pscustomobject]@{
        Check  = $Check
        Status = $Status
        Notes  = $Notes
    }) | Out-Null

    $marker = switch ($Status) {
        'PASS' { '✅ PASS' }
        'FAIL' { '❌ FAIL' }
        'SKIP' { '⚠️  SKIP' }
    }
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'SKIP' { 'Yellow' }
    }
    Write-Host ("  {0,-8} {1}" -f $marker, $Check) -ForegroundColor $color
    if ($Notes) {
        Write-Host ("           → {0}" -f $Notes) -ForegroundColor DarkGray
    }
}

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Write-VerboseBody {
    param([string] $Label, [string] $Body)
    if ($verboseMode -and $Body) {
        Write-Host "    --- $Label ---" -ForegroundColor DarkGray
        $Body -split "`n" | Select-Object -First 40 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Invoke-Probe {
    <#
    .SYNOPSIS
        Issue an HTTP request and return @{ ok; status; body; error }.
        Never throws — failures are returned in the hashtable.
    #>
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Headers,
        [string] $Body,
        [int] $TimeoutSec = 15
    )

    $params = @{
        Uri             = $Uri
        Method          = $Method
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($Body)    {
        $params.Body        = $Body
        $params.ContentType = 'application/json'
    }

    try {
        $resp = Invoke-WebRequest @params
        return @{
            ok     = $true
            status = [int] $resp.StatusCode
            body   = $resp.Content
            error  = $null
        }
    }
    catch [System.Net.WebException], [Microsoft.PowerShell.Commands.HttpResponseException] {
        $status = $null
        $bodyText = $null
        if ($_.Exception.Response) {
            try { $status = [int] $_.Exception.Response.StatusCode } catch {}
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $bodyText = $reader.ReadToEnd()
            } catch {}
        }
        return @{
            ok     = $false
            status = $status
            body   = $bodyText
            error  = $_.Exception.Message
        }
    }
    catch {
        return @{
            ok     = $false
            status = $null
            body   = $null
            error  = $_.Exception.Message
        }
    }
}

# ---------------------------------------------------------------------------
# Cluster checks
# ---------------------------------------------------------------------------

if (-not [string]::IsNullOrWhiteSpace($OpsAgentEndpoint)) {
    # Caller-supplied full URL (with scheme). This is the path the orchestrator
    # `scripts/deploy-all.ps1` uses so http://ops-agent.<sslip>.sslip.io/ flows
    # through unchanged. Strip any trailing slash so we can append /health etc.
    $opsAgentBase = $OpsAgentEndpoint.TrimEnd('/')
} else {
    # Legacy / DnsZone+HTTPS path.
    $opsAgentBase = "https://${OpsAgentSubdomain}.${DnsZone}"
}

function Test-OpsAgentHealth {
    $name = "AKS ops-agent /health ($opsAgentBase/health)"
    $r = Invoke-Probe -Method GET -Uri "$opsAgentBase/health" -TimeoutSec 10
    if (-not $r.ok) {
        Write-VerboseBody -Label 'response body' -Body $r.body
        Add-Result -Check $name -Status FAIL -Notes "request failed: $($r.error)"
        return
    }
    if ($r.status -ne 200) {
        Add-Result -Check $name -Status FAIL -Notes "expected 200, got $($r.status)"
        return
    }
    if ($r.body -notmatch '"status"\s*:\s*"ok"') {
        Add-Result -Check $name -Status FAIL -Notes "body did not contain 'status:ok': $($r.body)"
        return
    }
    Add-Result -Check $name -Status PASS -Notes "200 OK, status=ok"
}

function Test-OpsAgentCard {
    $name = "AKS ops-agent Agent Card"
    $uri  = "$opsAgentBase/.well-known/agent-card.json"
    $r = Invoke-Probe -Method GET -Uri $uri -TimeoutSec 10
    if (-not $r.ok -or $r.status -ne 200) {
        Write-VerboseBody -Label 'response body' -Body $r.body
        Add-Result -Check $name -Status FAIL -Notes "expected 200, got $($r.status); err=$($r.error)"
        return
    }
    try {
        $card = $r.body | ConvertFrom-Json -Depth 20
    } catch {
        Add-Result -Check $name -Status FAIL -Notes "response was not valid JSON: $($_.Exception.Message)"
        return
    }
    # protocolVersion lives on supported_interfaces[].protocol_version per
    # apps/ops-agent/app/agent_card.py:65–71.
    $iface = $null
    if ($card.PSObject.Properties.Name -contains 'supportedInterfaces') {
        $iface = $card.supportedInterfaces | Select-Object -First 1
    } elseif ($card.PSObject.Properties.Name -contains 'supported_interfaces') {
        $iface = $card.supported_interfaces | Select-Object -First 1
    }
    $protoVersion = $null
    if ($iface) {
        if ($iface.PSObject.Properties.Name -contains 'protocolVersion') { $protoVersion = $iface.protocolVersion }
        elseif ($iface.PSObject.Properties.Name -contains 'protocol_version') { $protoVersion = $iface.protocol_version }
    }
    $cardName = [string] $card.name
    if (-not $cardName) {
        Add-Result -Check $name -Status FAIL -Notes "agent card has no 'name' field"
        return
    }
    if (-not $protoVersion) {
        Add-Result -Check $name -Status FAIL -Notes "agent card missing supported_interfaces[].protocol_version"
        return
    }
    if ($cardName -notmatch '(?i)ops|zava') {
        Add-Result -Check $name -Status FAIL -Notes "name '$cardName' did not match Ops/Zava"
        return
    }
    Add-Result -Check $name -Status PASS -Notes "name='$cardName', protocolVersion=$protoVersion"
}

function Test-A2AMessageSend {
    $name = "A2A endpoint message/send (v0.3)"
    if (-not $ApiKey) {
        Add-Result -Check $name -Status FAIL -Notes "no API key supplied; set -ApiKey or `$env:A2A_API_KEY (server returns 401 without it)"
        return
    }

    # v0.3 envelope per docs/a2a-implementation.md §4.2.
    $messageId = "smoke-" + ([guid]::NewGuid().ToString('N').Substring(0, 12))
    $envelope = @{
        jsonrpc = '2.0'
        id      = 1
        method  = 'message/send'
        params  = @{
            message = @{
                messageId = $messageId
                role      = 'user'
                kind      = 'message'
                parts     = @(
                    @{
                        kind = 'text'
                        text = "Check feasibility for SKU ZP-7000, quantity 10, customer CUST-001, target_date 2026-08-15"
                    }
                )
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{
        'x-api-key' = $ApiKey
        'Accept'    = 'application/json'
    }

    $r = Invoke-Probe -Method POST -Uri "$opsAgentBase/" -Headers $headers -Body $envelope -TimeoutSec 60
    if (-not $r.ok -or $r.status -ne 200) {
        Write-VerboseBody -Label 'A2A response body' -Body $r.body
        Add-Result -Check $name -Status FAIL -Notes "HTTP $($r.status); err=$($r.error)"
        return
    }
    try {
        $resp = $r.body | ConvertFrom-Json -Depth 30
    } catch {
        Add-Result -Check $name -Status FAIL -Notes "response was not valid JSON-RPC: $($_.Exception.Message)"
        return
    }
    if ($resp.PSObject.Properties.Name -contains 'error' -and $null -ne $resp.error) {
        $errMsg = "$($resp.error.code): $($resp.error.message)"
        Write-VerboseBody -Label 'JSON-RPC error' -Body $r.body
        Add-Result -Check $name -Status FAIL -Notes "JSON-RPC error $errMsg"
        return
    }
    if ($resp.PSObject.Properties.Name -notcontains 'result' -or $null -eq $resp.result) {
        Add-Result -Check $name -Status FAIL -Notes "JSON-RPC envelope had no 'result' field"
        return
    }
    $task = $resp.result
    $state = $null
    if ($task.PSObject.Properties.Name -contains 'status' -and $task.status) {
        $state = [string] $task.status.state
    }
    # Tolerate both v0.3 lowercase and v1.0 enum spellings per
    # docs/a2a-implementation.md §6.
    $completed = @('completed', 'TASK_STATE_COMPLETED')
    if ($state -notin $completed) {
        Write-VerboseBody -Label 'task body' -Body $r.body
        Add-Result -Check $name -Status FAIL -Notes "task state was '$state', expected 'completed'"
        return
    }
    if (-not $task.artifacts -or $task.artifacts.Count -lt 1) {
        Add-Result -Check $name -Status FAIL -Notes "task had no artifacts"
        return
    }
    $artifact = $task.artifacts[0]
    $hasText = $false
    $hasData = $false
    foreach ($part in $artifact.parts) {
        $kind = [string] $part.kind
        if ($kind -eq 'text' -and [string] $part.text) { $hasText = $true }
        if ($kind -eq 'data' -and $null -ne $part.data) { $hasData = $true }
    }
    if (-not ($hasText -and $hasData)) {
        Add-Result -Check $name -Status FAIL -Notes "artifact missing dual parts (text=$hasText data=$hasData)"
        return
    }
    Add-Result -Check $name -Status PASS -Notes "task completed with TextPart + DataPart artifact"
}

# ---------------------------------------------------------------------------
# Local checks
# ---------------------------------------------------------------------------

function Test-BackendHealth {
    $name = "Backend /api/health ($BackendUrl/api/health)"
    $r = Invoke-Probe -Method GET -Uri "$BackendUrl/api/health" -TimeoutSec 5
    if (-not $r.ok -or $r.status -ne 200) {
        Add-Result -Check $name -Status FAIL -Notes "expected 200, got $($r.status); err=$($r.error)"
        return
    }
    if ($r.body -notmatch '"status"\s*:\s*"ok"') {
        Add-Result -Check $name -Status FAIL -Notes "body did not contain 'status:ok': $($r.body)"
        return
    }
    Add-Result -Check $name -Status PASS -Notes "200 OK, status=ok"
}

function Test-FrontendDevServer {
    $name = "Frontend dev server ($FrontendUrl)"
    $r = Invoke-Probe -Method GET -Uri "$FrontendUrl/" -TimeoutSec 5
    if (-not $r.ok -or $r.status -ne 200) {
        Add-Result -Check $name -Status FAIL -Notes "expected 200, got $($r.status); err=$($r.error)"
        return
    }
    if ($r.body -notmatch '<title') {
        Add-Result -Check $name -Status FAIL -Notes "response did not contain <title> tag"
        return
    }
    Add-Result -Check $name -Status PASS -Notes "200 OK, served HTML"
}

function Test-FullIntegration {
    $name = "Full integration (POST /api/chat → SSE)"
    # Schema per apps/backend/app/models.py ChatRequest.
    $body = @{
        sku         = 'ZP-7000'
        quantity    = 10
        target_date = '2026-08-15'
        customer_id = 'CUST-001'
    } | ConvertTo-Json -Compress

    # Use HttpClient directly so we can read the SSE stream incrementally
    # rather than buffering the entire response (Invoke-WebRequest buffers).
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client  = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(75)

    $req = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Post,
        "$BackendUrl/api/chat"
    )
    $req.Content = [System.Net.Http.StringContent]::new(
        $body,
        [System.Text.Encoding]::UTF8,
        'application/json'
    )
    $req.Headers.Accept.ParseAdd('text/event-stream')

    $deadline = (Get-Date).AddSeconds(60)
    $sawText  = $false
    $sawA2A   = $false
    $sawChart = $false
    $sawDone  = $false
    $sawError = $false
    $errorMsg = $null
    $eventCount = 0

    try {
        $resp = $client.SendAsync(
            $req,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()

        if (-not $resp.IsSuccessStatusCode) {
            $errBody = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            Write-VerboseBody -Label 'chat error body' -Body $errBody
            Add-Result -Check $name -Status FAIL -Notes "HTTP $([int] $resp.StatusCode): $errBody"
            return
        }

        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream)

        while (-not $reader.EndOfStream) {
            if ((Get-Date) -gt $deadline) {
                Add-Result -Check $name -Status FAIL -Notes ("timed out after 60s; events seen={0} text={1} a2a={2} chart={3} done={4}" -f $eventCount, $sawText, $sawA2A, $sawChart, $sawDone)
                return
            }
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if (-not $line.StartsWith('data: ')) { continue }
            $payload = $line.Substring(6).Trim()
            if (-not $payload) { continue }
            $eventCount++
            try {
                $evt = $payload | ConvertFrom-Json -Depth 20
            } catch {
                if ($verboseMode) {
                    Write-Host "    (skipping unparseable SSE frame: $payload)" -ForegroundColor DarkGray
                }
                continue
            }
            switch ([string] $evt.type) {
                'text_delta' { $sawText  = $true }
                'a2a_hop'    { $sawA2A   = $true }
                'chart'      { $sawChart = $true }
                'tool_call'  {
                    # Code Interpreter calls also satisfy "tool/A2A activity"
                    # but specifically the A2A delegation surfaces as a2a_hop;
                    # we don't flip $sawA2A here.
                }
                'done'       { $sawDone  = $true }
                'error'      {
                    $sawError = $true
                    $errorMsg = [string] $evt.data.message
                }
            }
            if ($sawDone -or $sawError) { break }
        }
    }
    catch {
        Add-Result -Check $name -Status FAIL -Notes "stream error: $($_.Exception.Message)"
        return
    }
    finally {
        try { $client.Dispose() } catch {}
    }

    if ($sawError) {
        Add-Result -Check $name -Status FAIL -Notes "stream emitted error event: $errorMsg"
        return
    }
    if ($eventCount -eq 0) {
        Add-Result -Check $name -Status FAIL -Notes "no SSE events received"
        return
    }
    # Per task list (line 1344), expect at least:
    #   - one text event from the Foundry agent
    #   - one A2A hop event
    #   - one chart event (DataPart payload from ops-agent rendered via Code Interpreter)
    $missing = @()
    if (-not $sawText)  { $missing += 'text_delta' }
    if (-not $sawA2A)   { $missing += 'a2a_hop' }
    if (-not $sawChart) { $missing += 'chart' }
    if ($missing.Count -gt 0) {
        Add-Result -Check $name -Status FAIL -Notes ("events=$eventCount; missing required event types: " + ($missing -join ', '))
        return
    }
    Add-Result -Check $name -Status PASS -Notes "events=$eventCount; saw text + a2a_hop + chart + done=$sawDone"
}

# ---------------------------------------------------------------------------
# Foundry trace reminder (always printed; never fails)
# ---------------------------------------------------------------------------

function Show-FoundryTraceInstructions {
    Write-Section "7. Foundry tracing — manual verification"
    Write-Host @"
Automated trace verification is not feasible (no public read API for
Foundry traces in V2). After running this smoke test, manually verify:

  1. Open https://ai.azure.com
  2. Select your project (e.g., 'zava-foundry')
  3. Go to Tracing → Traces
  4. Confirm the most recent trace (within the last few minutes) shows:
       * The Foundry agent run kicked off by the backend
       * One or more tool calls (Code Interpreter)
       * An A2A connection invocation to the Ops Agent
       * Response artifacts (text + chart)

If you see these, Foundry tracing is wired correctly end-to-end.
"@ -ForegroundColor White
    Add-Result -Check 'Foundry traces (manual)' -Status SKIP -Notes 'see instructions above'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Section "Zava A2A demo — smoke test"
Write-Host "DnsZone           : $DnsZone"
Write-Host "OpsAgentSubdomain : $OpsAgentSubdomain"
Write-Host "Ops Agent base URL: $opsAgentBase"
Write-Host "BackendUrl        : $BackendUrl"
Write-Host "FrontendUrl       : $FrontendUrl"
Write-Host ("ApiKey provided   : {0}" -f ($(if ($ApiKey) { 'yes (length=' + $ApiKey.Length + ')' } else { 'no' })))
Write-Host "SkipCluster       : $SkipCluster"
Write-Host "SkipLocal         : $SkipLocal"
Write-Host "Verbose           : $verboseMode"

if ($SkipCluster) {
    Write-Section "1–3. Cluster checks — SKIPPED"
    Add-Result -Check 'AKS ops-agent /health'         -Status SKIP -Notes '-SkipCluster'
    Add-Result -Check 'AKS ops-agent Agent Card'      -Status SKIP -Notes '-SkipCluster'
    Add-Result -Check 'A2A endpoint message/send'     -Status SKIP -Notes '-SkipCluster'
} else {
    Write-Section "1. AKS ops-agent /health"
    Test-OpsAgentHealth
    Write-Section "2. AKS ops-agent Agent Card"
    Test-OpsAgentCard
    Write-Section "3. A2A endpoint message/send (v0.3)"
    Test-A2AMessageSend
}

if ($SkipLocal) {
    Write-Section "4–6. Local checks — SKIPPED"
    Add-Result -Check 'Backend /api/health'  -Status SKIP -Notes '-SkipLocal'
    Add-Result -Check 'Frontend dev server'  -Status SKIP -Notes '-SkipLocal'
    Add-Result -Check 'Full integration SSE' -Status SKIP -Notes '-SkipLocal'
} else {
    Write-Section "4. Backend /api/health"
    Test-BackendHealth
    Write-Section "5. Frontend dev server"
    Test-FrontendDevServer
    Write-Section "6. Full integration (POST /api/chat → SSE)"
    Test-FullIntegration
}

Show-FoundryTraceInstructions

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Section "Summary"

$rows = $script:results | ForEach-Object {
    $statusGlyph = switch ($_.Status) {
        'PASS' { '✅ PASS' }
        'FAIL' { '❌ FAIL' }
        'SKIP' { '⚠️  SKIP' }
    }
    [pscustomobject]@{
        Check  = $_.Check
        Status = $statusGlyph
        Notes  = $_.Notes
    }
}
$rows | Format-Table -AutoSize -Wrap | Out-String | Write-Host

$passed  = ($script:results | Where-Object Status -EQ 'PASS').Count
$failed  = ($script:results | Where-Object Status -EQ 'FAIL').Count
$skipped = ($script:results | Where-Object Status -EQ 'SKIP').Count

Write-Host ("Totals: {0} passed, {1} failed, {2} skipped" -f $passed, $failed, $skipped) -ForegroundColor Cyan

if ($failed -gt 0) {
    Write-Host ''
    Write-Host "❌ Smoke test FAILED — $failed check(s) did not pass." -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host "✅ Smoke test PASSED — all executed checks succeeded." -ForegroundColor Green
exit 0
