<#
.SYNOPSIS
    Brings the whole SejiloChat stack up and publishes it at a public HTTPS URL.

.DESCRIPTION
    One command for the full sequence:
      1. start Docker Desktop and wait for its daemon
      2. docker compose up -d  (Postgres, Redis, backend)
      3. wait for the backend to answer /health on localhost
      4. hand off to scripts\go-online.ps1 for the Cloudflare quick tunnel

    Safe to re-run: every step is skipped if it is already satisfied.

.PARAMETER Port
    Local port the backend listens on. Default 8080.

.PARAMETER BuildTimeoutMinutes
    How long to allow for the image build and first boot. Default 10.

.PARAMETER NoTunnel
    Bring the stack up but stay local - do not open the public tunnel.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$Port = 8080,
    [int]$BuildTimeoutMinutes = 10,
    [switch]$NoTunnel
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LocalUrl = "http://127.0.0.1:$Port"

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }

function Test-DockerDaemon {
    try {
        & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Find-DockerDesktop {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Start-DockerDesktop {
    param([int]$TimeoutMinutes = 4)

    if (Test-DockerDaemon) {
        Write-Ok 'Docker daemon is already responding.'
        return
    }

    $exe = Find-DockerDesktop
    if (-not $exe) {
        throw "Docker Desktop was not found on this machine. Install it from https://docs.docker.com/desktop/setup/install/windows-install/ or re-run with -NoTunnel once you have Postgres and Redis running some other way."
    }

    Write-Info "Launching $exe"
    Start-Process -FilePath $exe | Out-Null

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $spin = 0
    while ((Get-Date) -lt $deadline) {
        if (Test-DockerDaemon) {
            Write-Ok 'Docker daemon is up.'
            return
        }
        $spin++
        if ($spin % 10 -eq 0) {
            $waited = [int]((Get-Date) - $deadline.AddMinutes(-$TimeoutMinutes)).TotalSeconds
            Write-Info "still waiting for the daemon ($waited s)"
        }
        Start-Sleep -Seconds 3
    }

    throw "Docker Desktop did not become ready within $TimeoutMinutes minutes. Open it manually and watch for an error - on Windows this is usually the WSL2 backend, which 'wsl --update' then a reboot normally fixes."
}

function Test-BackendHealth {
    try {
        $response = Invoke-WebRequest -Uri "$LocalUrl/health" -UseBasicParsing -TimeoutSec 5
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

Write-Host ''
Write-Host 'SejiloChat - bring the stack up and put it online' -ForegroundColor White
Write-Host ''

Write-Step 'Checking Docker'
Start-DockerDesktop

Write-Step 'Starting the stack (postgres, redis, backend)'
Push-Location $RepoRoot
try {
    # docker compose writes its build progress to stderr, which PowerShell 5.1 can
    # turn into a terminating error while ErrorActionPreference is 'Stop'. Judge the
    # call by its exit code instead.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker compose up -d --build
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE. Read the output above; 'docker compose logs backend' usually says why."
    }
} finally {
    Pop-Location
}
Write-Ok 'Containers requested.'

Write-Step "Waiting for the backend on $LocalUrl"
$deadline = (Get-Date).AddMinutes($BuildTimeoutMinutes)
$healthy = $false
$ticks = 0
while ((Get-Date) -lt $deadline) {
    if (Test-BackendHealth) { $healthy = $true; break }
    $ticks++
    if ($ticks % 12 -eq 0) { Write-Info "not answering yet ($([int]($ticks * 5)) s) - first boot runs prisma migrate deploy" }
    Start-Sleep -Seconds 5
}

if (-not $healthy) {
    Write-Warn "The backend never answered $LocalUrl/health."
    Write-Info 'Check what the container is doing:'
    Write-Info "  cd $RepoRoot"
    Write-Info '  docker compose ps'
    Write-Info '  docker compose logs --tail 80 backend'
    exit 1
}
Write-Ok 'Backend is healthy locally.'

if ($NoTunnel) {
    Write-Host ''
    Write-Ok "Stack is up at $LocalUrl (staying local, -NoTunnel was given)."
    exit 0
}

Write-Step 'Publishing it with a Cloudflare quick tunnel'
$ErrorActionPreference = 'Continue'
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'go-online.ps1') -Port $Port
exit $LASTEXITCODE

