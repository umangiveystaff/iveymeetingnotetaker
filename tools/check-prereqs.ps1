<#
.SYNOPSIS
  Check all local prerequisites for the Ivey Meeting Note-Taker.
  Reports OK / MISSING for each dependency. Does NOT install anything.
.USAGE
  cd C:\Users\usharma\dev\iveymeetingnotetaker
  .\tools\check-prereqs.ps1
#>

$root = Split-Path $PSScriptRoot -Parent
$ok = $true

function Check-Item {
    param([string]$Name, [bool]$Pass, [string]$Hint)
    if ($Pass) {
        Write-Host "  [OK]      $Name" -ForegroundColor Green
    }
    else {
        Write-Host "  [MISSING] $Name  -- $Hint" -ForegroundColor Red
        $script:ok = $false
    }
}

Write-Host ""
Write-Host "=== Ivey Meeting Note-Taker - Prerequisite Check ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# --- Ollama ---
Write-Host "[ Ollama ]"
try {
    $body = '{"model":"llama3.2","prompt":"ping","stream":false}'
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" -Method Post `
        -ContentType "application/json" -Body $body -TimeoutSec 15
    Check-Item "Ollama reachable (llama3.2)" ($r.response.Length -gt 0) "Start Ollama: ollama serve"
}
catch {
    Check-Item "Ollama reachable (llama3.2)" $false "Start: ollama serve && ollama pull llama3.2"
}

# --- FFmpeg ---
Write-Host ""
Write-Host "[ FFmpeg ]"
$ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
Check-Item "ffmpeg in PATH" ($null -ne $ff) "winget install Gyan.FFmpeg  OR  choco install ffmpeg"
if ($ff) {
    $ffVer = (& ffmpeg -version 2>&1) | Select-Object -First 1
    Write-Host "         $ffVer" -ForegroundColor DarkGray
}

# --- VB-Audio Virtual Cable ---
Write-Host ""
Write-Host "[ VB-Audio Virtual Cable ]"
if ($ff) {
    try {
        $devOut = & ffmpeg -f dshow -list_devices true -i dummy 2>&1
        $devStr = ($devOut -join "`n")
        $found = $devStr -match "CABLE"
        Check-Item "CABLE Input/Output visible to ffmpeg" $found `
            "Install VB-Audio from https://vb-audio.com/Cable/ then reboot"
    }
    catch {
        Check-Item "CABLE devices (dshow enum)" $false "ffmpeg dshow enum failed"
    }
}
else {
    Check-Item "CABLE devices (dshow enum)" $false "ffmpeg not found - install it first"
}

# --- whisper.cpp binary ---
Write-Host ""
Write-Host "[ whisper.cpp ]"
$whisperPkg = Join-Path $root "backend\whisper-server-package"
$whisperExe1 = Join-Path $whisperPkg "whisper-server.exe"
$whisperExe2 = Join-Path $root "backend\whisper.cpp\build\bin\Release\whisper-server.exe"
$whisperOk = (Test-Path $whisperExe1) -or (Test-Path $whisperExe2)
Check-Item "whisper-server.exe present" $whisperOk "Run: cd backend && build_whisper.cmd small"

$modelDir1 = Join-Path $whisperPkg "models"
$modelDir2 = Join-Path $root "backend\whisper.cpp\models"
$cnt1 = if (Test-Path $modelDir1) { @(Get-ChildItem "$modelDir1\*.bin" -ErrorAction SilentlyContinue).Count } else { 0 }
$cnt2 = if (Test-Path $modelDir2) { @(Get-ChildItem "$modelDir2\*.bin" -ErrorAction SilentlyContinue).Count } else { 0 }
$hasModel = ($cnt1 -gt 0) -or ($cnt2 -gt 0)
Check-Item "ggml model (.bin) present" $hasModel "Run: cd backend && build_whisper.cmd small"

# --- Pandoc (optional) ---
Write-Host ""
Write-Host "[ Pandoc (optional - DOCX/PDF export) ]"
$pd = Get-Command pandoc -ErrorAction SilentlyContinue
Check-Item "pandoc in PATH" ($null -ne $pd) "winget install JohnMacFarlane.Pandoc  OR  choco install pandoc"
if ($pd) {
    $pdVer = (& pandoc --version) | Select-Object -First 1
    Write-Host "         $pdVer" -ForegroundColor DarkGray
}

# --- Output directories (create if missing) ---
Write-Host ""
Write-Host "[ Output directories ]"
$outDir = Join-Path $root "out"
$transcriptsDir = Join-Path $root "out\transcripts"
$audioDir = Join-Path $root "sample\audio"

New-Item -ItemType Directory -Force $outDir         | Out-Null
New-Item -ItemType Directory -Force $transcriptsDir | Out-Null
New-Item -ItemType Directory -Force $audioDir       | Out-Null

Check-Item "out\ created/exists"             $true ""
Check-Item "out\transcripts\ created/exists" $true ""
Check-Item "sample\audio\ created/exists"    $true ""

# --- Core project files ---
Write-Host ""
Write-Host "[ Core project files ]"
$files = [ordered]@{
    "frontend\src\config\summary_templates.json" = "summary_templates.json"
    "frontend\src\ollamaClient.ts"               = "ollamaClient.ts"
    "frontend\src\generateSummary.ts"            = "generateSummary.ts"
    "tools\gen-summary.ps1"                      = "gen-summary.ps1"
    "sample\transcript.txt"                      = "sample\transcript.txt"
}
foreach ($rel in $files.Keys) {
    $full = Join-Path $root $rel
    Check-Item $files[$rel] (Test-Path $full) "Missing - check the repo"
}

# --- Summary ---
Write-Host ""
if ($ok) {
    Write-Host "=== All checks PASSED - ready to run the full pipeline! ===" -ForegroundColor Green
}
else {
    Write-Host "=== Some checks FAILED - fix items marked [MISSING] above. ===" -ForegroundColor Yellow
}
Write-Host ""
