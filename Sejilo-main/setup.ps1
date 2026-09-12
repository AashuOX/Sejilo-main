# SejiloChat quick setup for Windows
# Run this from the repo root: C:\Users\ASUS\Desktop\Sejilo-main\Sejilo-main

param(
    [switch]$SkipApp
)

$ErrorActionPreference = 'Stop'

function Write-Status($msg) { Write-Host "[setup] $msg" -ForegroundColor Cyan }

Write-Status 'Checking prerequisites...'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Flutter is not installed or not in PATH.' -ForegroundColor Red
    exit 1
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host 'Docker is not installed or not in PATH.' -ForegroundColor Red
    exit 1
}

$adb = 'C:\Users\ASUS\AppData\Local\Android\sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    Write-Host 'ADB not found at expected path. Ensure Android SDK is installed.' -ForegroundColor Red
    exit 1
}

Write-Status 'Starting Docker Desktop...'
Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

Write-Status 'Waiting for Docker to be ready...'
$retries = 0
while ($retries -lt 30) {
    try {
        docker info --format '{{.ServerVersion}}' | Out-Null
        break
    } catch {
        $retries++
        Start-Sleep -Seconds 2
    }
}
if ($retries -ge 30) {
    Write-Host 'Docker did not become ready in time.' -ForegroundColor Red
    exit 1
}

Write-Status 'Starting backend services...'
Push-Location 'C:\Users\ASUS\Desktop\Sejilo-main\Sejilo-main'
try {
    docker compose up -d --build | Out-Null
} catch {
    Write-Host "docker compose failed: $_" -ForegroundColor Red
    exit 1
}
Pop-Location

Write-Status 'Waiting for backend health...'
$retries = 0
while ($retries -lt 30) {
    try {
        $health = Invoke-RestMethod http://127.0.0.1:8080/health/ready -ErrorAction Stop
        if ($health.status -eq 'ok') { break }
    } catch {
        $retries++
        Start-Sleep -Seconds 2
    }
}
if ($retries -ge 30) {
    Write-Host 'Backend did not become healthy in time.' -ForegroundColor Red
    exit 1
}
Write-Host 'Backend healthy.' -ForegroundColor Green

Write-Status 'Enabling adb reverse for physical device...'
& $adb reverse tcp:8080 tcp:8080 | Out-Null

$device = & $adb devices | Select-String '\tdevice' | Select-Object -First 1
if (-not $device) {
    Write-Host 'No Android device detected. Connect a device with USB debugging enabled.' -ForegroundColor Yellow
} else {
    Write-Host "Device detected: $($device.ToString().Trim())" -ForegroundColor Green
}

if (-not $SkipApp) {
    Write-Status 'Building and running Flutter app...'
    Push-Location 'C:\Users\ASUS\Desktop\Sejilo-main\Sejilo-main\sejilo_chat'
    try {
        flutter pub get | Out-Null
        flutter run -d 2409BRN2CA | Out-Null
    } catch {
        Write-Host "Flutter run failed: $_" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
}

Write-Host "`nSetup complete. Backend: http://localhost:8080" -ForegroundColor Green
