<#
.SYNOPSIS
    Publishes the locally running SejiloChat backend at a public HTTPS URL via a
    Cloudflare quick tunnel.

.DESCRIPTION
    Verifies the backend is healthy on localhost, ensures `cloudflared` is
    installed, opens a quick tunnel, and prints the public URL once Cloudflare
    has assigned one. The tunnel is outbound-only: no firewall port is opened and
    no inbound rule is needed.

    The URL is temporary and changes every run. Anyone holding it can reach every
    public endpoint (registration, login, explore feed, user search), so treat it
    as a live deployment rather than a private test link.

    Stop the tunnel with Ctrl+C; the backend keeps running.

.PARAMETER Port
    Local port the backend listens on. Default 8080.

.PARAMETER TimeoutSeconds
    How long to wait for Cloudflare to assign a hostname. Default 60.

.PARAMETER SkipHealthCheck
    Start the tunnel even if the local health probe fails.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\go-online.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$Port = 8080,
    [int]$TimeoutSeconds = 60,
    [switch]$SkipHealthCheck
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LocalUrl = "http://127.0.0.1:$Port"
$ToolsDir = Join-Path $RepoRoot '.tools'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Test-LocalBackend {
    try {
        $response = Invoke-WebRequest -Uri "$LocalUrl/health" -UseBasicParsing -TimeoutSec 5
        return [int]$response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Resolve-Cloudflared {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $local = Join-Path $ToolsDir 'cloudflared.exe'
    if (Test-Path $local) { return $local }

    Write-Step 'cloudflared not found - installing'

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id Cloudflare.cloudflared --accept-source-agreements `
                --accept-package-agreements --disable-interactivity | Out-Host
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path', 'User')
            $command = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($command) {
                Write-Ok "installed via winget: $($command.Source)"
                return $command.Source
            }
        } catch {
            Write-Warn "winget install failed ($($_.Exception.Message)) - falling back to direct download"
        }
    }

    # Official signed release binary, kept inside the repo's .tools directory.
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '386' }
    $downloadUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-$arch.exe"
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    Write-Host "    downloading $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $local -UseBasicParsing
    Write-Ok "installed: $local"
    return $local
}

Write-Step "Checking the backend on $LocalUrl"
if (Test-LocalBackend) {
    Write-Ok 'backend responded on /health'
} elseif ($SkipHealthCheck) {
    Write-Warn 'health check failed - continuing because -SkipHealthCheck was passed'
} else {
    Write-Host ''
    Write-Host "Nothing healthy is listening on $LocalUrl." -ForegroundColor Red
    Write-Host ''
    Write-Host '  Start the backend first, from one of:' -ForegroundColor Gray
    Write-Host '    cd backend; npm run start:dev        # host process, uses backend\.env' -ForegroundColor Gray
    Write-Host '    docker compose up -d backend         # container, uses repo-root .env' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Then re-run this script. Use -Port to point at a different port.' -ForegroundColor Gray
    exit 1
}

$exe = Resolve-Cloudflared

Write-Step 'Opening the Cloudflare quick tunnel'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP "sejilo-tunnel-$stamp.log"
$errPath = Join-Path $env:TEMP "sejilo-tunnel-$stamp.err.log"
New-Item -ItemType File -Force -Path $logPath, $errPath | Out-Null

$process = Start-Process -FilePath $exe `
    -ArgumentList @('tunnel', '--no-autoupdate', '--url', $LocalUrl) `
    -RedirectStandardOutput $logPath -RedirectStandardError $errPath `
    -WindowStyle Hidden -PassThru

try {
    $publicUrl = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            throw "cloudflared exited with code $($process.ExitCode). Log: $errPath"
        }
        $text = @(
            (Get-Content -Path $errPath -Raw -ErrorAction SilentlyContinue),
            (Get-Content -Path $logPath -Raw -ErrorAction SilentlyContinue)
        ) -join "`n"
        $match = [regex]::Match($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
        if ($match.Success) { $publicUrl = $match.Value; break }
        Start-Sleep -Milliseconds 500
    }

    if (-not $publicUrl) {
        throw "Cloudflare did not assign a hostname within $TimeoutSeconds seconds. Log: $errPath"
    }

    Write-Ok "public URL: $publicUrl"

    Write-Step 'Verifying the API through the public URL'
    $ready = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            $ready = Invoke-WebRequest -Uri "$publicUrl/health/ready" -UseBasicParsing -TimeoutSec 10
            break
        } catch {
            # The edge needs a moment to register a freshly created tunnel.
            Start-Sleep -Seconds 2
        }
    }

    if ($ready -and [int]$ready.StatusCode -eq 200) {
        Write-Ok "/health/ready returned 200 - $($ready.Content)"
    } elseif ($ready) {
        Write-Warn "/health/ready returned $([int]$ready.StatusCode): $($ready.Content)"
        Write-Warn 'The tunnel is up but Postgres or Redis is unreachable from the backend.'
    } else {
        Write-Warn 'Could not reach /health/ready through the tunnel yet. Try the URL in a browser.'
    }

    Set-Content -Path (Join-Path $RepoRoot '.tunnel-url.txt') -Value $publicUrl -Encoding ASCII

    $wsUrl = ($publicUrl -replace '^https://', 'wss://') + '/v1/chat/ws'

    Write-Host ''
    Write-Host '  SejiloChat backend is online' -ForegroundColor Green
    Write-Host '  ----------------------------------------------------------'
    Write-Host "  API base       $publicUrl"
    Write-Host "  Health         $publicUrl/health"
    Write-Host "  WebSocket      $wsUrl"
    Write-Host "  Flutter        BACKEND_URL=$publicUrl"
    Write-Host '  ----------------------------------------------------------'
    Write-Host '  This URL is live on the public internet and rotates on every'
    Write-Host '  restart. Ctrl+C takes it offline; the backend keeps running.'
    Write-Host ''
    Write-Host "  cloudflared log: $errPath" -ForegroundColor DarkGray
    Write-Host ''

    while (-not $process.HasExited) { Start-Sleep -Seconds 2 }
    Write-Warn "cloudflared exited with code $($process.ExitCode)"
}
finally {
    if ($process -and -not $process.HasExited) {
        Write-Step 'Closing the tunnel'
        try { $process.Kill() } catch { }
    }
}
