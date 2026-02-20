<#
.SYNOPSIS
  Record audio from a VB-Audio Virtual Cable (Teams output) to a WAV file.
  All audio stays local — nothing is transmitted anywhere.

.PARAMETER Duration
  Recording duration in seconds. Defaults to 3600 (1 hour).
  Press Ctrl+C or 'q' + Enter to stop early.

.PARAMETER DeviceName
  Exact DirectShow device name. If omitted, the script will list available
  devices and let you choose. Run .\tools\list-devices.ps1 first to see names.

.PARAMETER OutDir
  Output directory. Defaults to .\sample\audio\

.PARAMETER FileName
  Output file name (no extension). Defaults to meeting-<timestamp>.

.EXAMPLE
  # Interactive: lists devices and prompts for choice
  .\tools\capture.ps1

  # Explicit device name from ffmpeg -list_devices output:
  .\tools\capture.ps1 -DeviceName "CABLE Output (VB-Audio Virtual Cable)"

  # Record for exactly 30 minutes:
  .\tools\capture.ps1 -Duration 1800 -DeviceName "CABLE Output (VB-Audio Virtual Cable)"
#>
param(
    [int]   $Duration = 3600,
    [string]$DeviceName = "",
    [string]$OutDir = "",
    [string]$FileName = ""
)

$root = $PSScriptRoot | Split-Path -Parent

# ── Verify ffmpeg ──────────────────────────────────────────────────────────────
$ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (!$ff) {
    Write-Error @"
ffmpeg not found in PATH.
Install: winget install Gyan.FFmpeg
Or: choco install ffmpeg
"@
    exit 1
}

# ── Resolve output path ───────────────────────────────────────────────────────
if (!$OutDir) { $OutDir = Join-Path $root "sample\audio" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

if (!$FileName) { $FileName = "meeting-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
$wavOut = Join-Path $OutDir "$FileName.wav"

# ── List devices if name not provided ─────────────────────────────────────────
if (!$DeviceName) {
    Write-Host ""
    Write-Host "=== Available DirectShow Audio Devices ===" -ForegroundColor Cyan
    Write-Host "(Listed from ffmpeg -f dshow -list_devices true -i dummy)"
    Write-Host ""

    $devOutput = & ffmpeg -f dshow -list_devices true -i dummy 2>&1
    $audioDevices = $devOutput | Where-Object { $_ -match '".*"\s*(audio)?' } | ForEach-Object {
        if ($_ -match '"([^"]+)"') { $Matches[1] }
    } | Where-Object { $_ }

    if ($audioDevices.Count -eq 0) {
        Write-Warning "No DirectShow audio devices found. Make sure VB-Audio is installed and you've rebooted."
        Write-Host ""
        Write-Host "Raw ffmpeg output:"
        $devOutput | Select-Object -Last 20
        exit 1
    }

    Write-Host "Audio devices found:" -ForegroundColor Green
    for ($i = 0; $i -lt $audioDevices.Count; $i++) {
        Write-Host "  [$i] $($audioDevices[$i])"
    }
    Write-Host ""

    $cable = $audioDevices | Where-Object { $_ -match 'CABLE' } | Select-Object -First 1
    if ($cable) {
        Write-Host "CABLE device detected: $cable" -ForegroundColor Green
        Write-Host "Auto-selecting CABLE Output for Teams capture."
        $DeviceName = $cable
    }
    else {
        $idx = Read-Host "Enter the number of the device to record from"
        if ($idx -match '^\d+$' -and [int]$idx -lt $audioDevices.Count) {
            $DeviceName = $audioDevices[[int]$idx]
        }
        else {
            Write-Error "Invalid selection."; exit 1
        }
    }
}

# ── Privacy reminder ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Privacy Notice ===" -ForegroundColor Yellow
Write-Host "Recording from: $DeviceName"
Write-Host "Output file:    $wavOut"
Write-Host "This recording stays on this machine. No audio is transmitted."
Write-Host "Always inform meeting participants that you are recording."
Write-Host ""
Write-Host "Recording for up to $([math]::Round($Duration/60)) minutes. Press 'q' + Enter to stop."
Write-Host ""

# ── Start recording ───────────────────────────────────────────────────────────
Write-Host "Starting capture..." -ForegroundColor Green
& ffmpeg -f dshow -i "audio=$DeviceName" -t $Duration -y $wavOut

if ($LASTEXITCODE -eq 0 -or (Test-Path $wavOut)) {
    $size = [math]::Round((Get-Item $wavOut).Length / 1MB, 2)
    Write-Host ""
    Write-Host "=== Recording saved ===" -ForegroundColor Green
    Write-Host "File: $wavOut ($size MB)"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Transcribe (with speaker diarization):"
    Write-Host "     .\tools\transcribe.ps1 -WavPath '$wavOut'"
    Write-Host ""
    Write-Host "  2. (Optional) Map speaker labels to real names:"
    Write-Host "     .\tools\map-speakers.ps1 -TranscriptPath out\transcripts\<name>.txt"
    Write-Host ""
    Write-Host "  3. Generate meeting notes:"
    Write-Host "     .\tools\gen-summary.ps1 -Transcript out\transcripts\<name>.txt -TemplateId ivey_meeting"
}
else {
    Write-Error "Recording failed or output file missing."
    exit 1
}
