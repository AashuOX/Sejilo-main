<#
.SYNOPSIS
    Verifies a hosted SejiloChat backend end to end over its public HTTPS URL.

.DESCRIPTION
    Written for the free-tier deployment described in docs/FREE_HOSTING.md, but it
    works against any reachable backend, including a Cloudflare tunnel.

    Checks, in order:
      1. /health/live               — process is up (no database round trip)
      2. /health/ready              — Postgres and Redis reachable from inside
      3. /api/docs                  — Swagger is NOT exposed in production
      4. CORS preflight             — a stranger's browser origin is refused
      5. WebSocket upgrade          — /v1/chat/ws accepts a socket
      6. register -> login          — a throwaway account round trip

    The first request may take ~60 seconds: a sleeping free instance has to boot.

.PARAMETER BaseUrl
    Public base URL, e.g. https://sejilo-backend.onrender.com

.PARAMETER SkipAuthCheck
    Skip step 6 so no test user is created.

.PARAMETER TimeoutSeconds
    Per-request timeout. Default 90, sized for a cold start.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\check-online.ps1 -BaseUrl https://sejilo-backend.onrender.com
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [switch]$SkipAuthCheck,
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Base = $BaseUrl.TrimEnd('/')
$script:Failures = 0
$script:Warnings = 0

function Write-Step { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Pass { param([string]$m) Write-Host "    PASS  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) $script:Warnings++; Write-Host "    WARN  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) $script:Failures++; Write-Host "    FAIL  $m" -ForegroundColor Red }

# Invoke-WebRequest throws on any non-2xx, which hides the status code we want to
# assert on, so every call goes through here and returns the response either way.
# Windows PowerShell 5.1 and PowerShell 7 raise different exception types for the
# same HTTP error, but both expose the status on .Exception.Response and the body
# on .ErrorDetails.Message.
function Invoke-Api {
    param(
        [string]$Path,
        [string]$Method = 'GET',
        [hashtable]$Headers,
        $Body
    )
    $request = @{
        Uri             = "$Base$Path"
        Method          = $Method
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSeconds
    }
    if ($Headers) { $request.Headers = $Headers }
    if ($null -ne $Body) {
        $request.Body        = ($Body | ConvertTo-Json -Depth 6 -Compress)
        $request.ContentType = 'application/json'
    }
    try {
        $response = Invoke-WebRequest @request
        return [pscustomobject]@{
            Code    = [int]$response.StatusCode
            Body    = $response.Content
            Headers = $response.Headers
        }
    } catch {
        $status = 0
        $webResponse = $_.Exception.Response
        if ($webResponse -and $null -ne $webResponse.StatusCode) {
            $status = [int]$webResponse.StatusCode
        }
        $body = $_.ErrorDetails.Message
        if ([string]::IsNullOrEmpty($body)) { $body = $_.Exception.Message }
        # Not named $headers: that is the same variable as the [hashtable]$Headers
        # parameter above (PowerShell is case-insensitive), and assigning a
        # WebHeaderCollection to it would fail the parameter's type constraint.
        $responseHeaders = $null
        if ($webResponse) { $responseHeaders = $webResponse.Headers }
        return [pscustomobject]@{ Code = $status; Body = $body; Headers = $responseHeaders }
    }
}

# Header collections differ by PowerShell version (Dictionary vs HttpHeaders), and
# indexing a missing key throws on some of them.
function Get-HeaderValue {
    param($Headers, [string]$Name)
    if (-not $Headers) { return $null }
    try {
        foreach ($key in $Headers.Keys) {
            if ($key -and $key.ToString().ToLowerInvariant() -eq $Name.ToLowerInvariant()) {
                $value = $Headers[$key]
                if ($value -is [array]) { return ($value -join ', ') }
                return [string]$value
            }
        }
    } catch { }
    return $null
}

Write-Host ''
Write-Host "  Verifying $Base" -ForegroundColor White
Write-Host '  A sleeping free instance takes about a minute to answer the first call.'
Write-Host ''

# ── 1. Liveness ──────────────────────────────────────────────────────────────────
Write-Step 'Liveness  /health/live'
$live = Invoke-Api -Path '/health/live'
if ($live.Code -eq 200) {
    Write-Pass "200 $($live.Body)"
} else {
    Write-Fail "expected 200, got $($live.Code) - $($live.Body)"
    Write-Host ''
    Write-Host '  Nothing is answering. Check the Render dashboard: a failed build or a' -ForegroundColor Gray
    Write-Host '  crash loop from a bad DATABASE_URL both look like this.' -ForegroundColor Gray
    Write-Host ''
    exit 1
}

# ── 2. Dependencies ─────────────────────────────────────────────────────────────
Write-Step 'Dependencies  /health/ready'
$ready = Invoke-Api -Path '/health/ready'
$readyJson = $null
try { $readyJson = $ready.Body | ConvertFrom-Json } catch { }

if ($ready.Code -eq 200) {
    Write-Pass "200 database=$($readyJson.database) redis=$($readyJson.redis)"
} else {
    Write-Fail "expected 200, got $($ready.Code) - $($ready.Body)"
}
if ($readyJson) {
    if ($readyJson.database -ne 'ok') {
        Write-Fail 'Postgres unreachable - check DATABASE_URL and that sslmode=require is present'
    }
    if ($readyJson.redis -eq 'unavailable') {
        Write-Fail 'Redis unreachable - Upstash needs the rediss:// TCP URL, not redis:// or the REST URL'
    } elseif ($readyJson.redis -eq 'disabled') {
        Write-Warn 'Redis not configured - presence, typing indicators and fan-out are off'
    }
}

# ── 3. Swagger must be closed in production ─────────────────────────────────────
Write-Step 'Attack surface  /api/docs'
$docs = Invoke-Api -Path '/api/docs'
if ($docs.Code -eq 404) {
    Write-Pass '404 - API docs are not published'
} elseif ($docs.Code -eq 200) {
    Write-Warn 'Swagger UI is public: every route, DTO and validation rule is readable.'
    Write-Warn 'Set ENABLE_SWAGGER=false (or unset it while NODE_ENV=production).'
} else {
    Write-Warn "unexpected status $($docs.Code)"
}

# ── 4. CORS must fail closed for unknown browser origins ────────────────────────
Write-Step 'CORS  preflight from an unknown origin'
$preflight = Invoke-Api -Path '/health' -Method 'OPTIONS' -Headers @{
    'Origin'                        = 'https://attacker.example'
    'Access-Control-Request-Method'  = 'GET'
}
$allowOrigin = Get-HeaderValue -Headers $preflight.Headers -Name 'Access-Control-Allow-Origin'
if ([string]::IsNullOrWhiteSpace($allowOrigin)) {
    Write-Pass 'no Access-Control-Allow-Origin returned - unknown origins are blocked'
} elseif ($allowOrigin -eq 'https://attacker.example' -or $allowOrigin -eq '*') {
    Write-Fail "origin reflected as '$allowOrigin' with credentials enabled - set CORS_ORIGIN and NODE_ENV=production"
} else {
    Write-Pass "allowed origin is pinned to '$allowOrigin'"
}

# ── 5. WebSocket upgrade ────────────────────────────────────────────────────────
Write-Step 'Realtime  /v1/chat/ws upgrade'
$wsUrl = ($Base -replace '^https://', 'wss://' -replace '^http://', 'ws://') + '/v1/chat/ws'
try {
    # ClientWebSocket ships with .NET Framework 4.5+, so Windows PowerShell 5.1 has
    # it without an Add-Type. GetResult() emits a VoidTaskResult onto the pipeline,
    # hence the $null assignments.
    $socket = New-Object Net.WebSockets.ClientWebSocket
    $cancel = New-Object Threading.CancellationTokenSource([TimeSpan]::FromSeconds([Math]::Min($TimeoutSeconds, 30)))
    $null = $socket.ConnectAsync([Uri]$wsUrl, $cancel.Token).GetAwaiter().GetResult()
    if ($socket.State -eq 'Open') {
        Write-Pass "handshake accepted at $wsUrl"
        $null = $socket.CloseAsync('NormalClosure', 'check complete', [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    } else {
        Write-Warn "socket state after connect: $($socket.State)"
    }
} catch {
    # Older Windows PowerShell builds cannot do a TLS WebSocket at all, which is a
    # limitation of the checker rather than of the deployment.
    Write-Warn "could not complete the handshake: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
    Write-Warn "verify manually: $wsUrl"
}

# ── 6. Auth round trip ──────────────────────────────────────────────────────────
if ($SkipAuthCheck) {
    Write-Step 'Auth  skipped (-SkipAuthCheck)'
} else {
    Write-Step 'Auth  register -> login'
    $suffix   = [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $email    = "healthcheck+$suffix@example.com"
    $password = 'Hc!' + [Guid]::NewGuid().ToString('N').Substring(0, 16) + 'x9'

    $register = Invoke-Api -Path '/v1/auth/register' -Method 'POST' -Body @{
        email       = $email
        password    = $password
        username    = "hc$suffix"
        displayName = 'Health Check'
    }

    if ($register.Code -ge 200 -and $register.Code -lt 300) {
        Write-Pass "register returned $($register.Code)"

        $login = Invoke-Api -Path '/v1/auth/login' -Method 'POST' -Body @{
            email    = $email
            password = $password
        }
        if ($login.Code -ge 200 -and $login.Code -lt 300 -and $login.Body -match 'token') {
            Write-Pass 'login returned a token - Postgres writes and JWT signing both work'
        } else {
            Write-Fail "login returned $($login.Code) - $($login.Body)"
        }
        Write-Host "    note: left a test account behind ($email)" -ForegroundColor DarkGray
    } elseif ($register.Code -eq 429) {
        Write-Warn 'rate limited (429) - the throttler is working; re-run in a minute'
    } elseif ($register.Code -eq 400 -or $register.Code -eq 422) {
        Write-Warn "register rejected the payload ($($register.Code)): $($register.Body)"
        Write-Warn 'the route is live; the DTO may expect different fields than this check sends'
    } else {
        Write-Fail "register returned $($register.Code) - $($register.Body)"
    }
}

# ── Summary ─────────────────────────────────────────────────────────────────────
Write-Host ''
if ($script:Failures -eq 0 -and $script:Warnings -eq 0) {
    Write-Host '  Backend is fully online.' -ForegroundColor Green
} elseif ($script:Failures -eq 0) {
    Write-Host "  Backend is online with $($script:Warnings) warning(s)." -ForegroundColor Yellow
} else {
    Write-Host "  $($script:Failures) check(s) failed, $($script:Warnings) warning(s)." -ForegroundColor Red
}
Write-Host '  ----------------------------------------------------------'
Write-Host "  API base    $Base"
Write-Host "  Health      $Base/health"
Write-Host "  WebSocket   $wsUrl"
Write-Host "  Flutter     --dart-define=SEJILO_API_BASE_URL=$Base"
Write-Host '  ----------------------------------------------------------'
Write-Host ''

exit $(if ($script:Failures -gt 0) { 1 } else { 0 })
