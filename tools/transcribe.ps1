<#
.SYNOPSIS
  Transcribe a WAV file using the local whisper-server with diarization.
  All processing is local — no audio or transcript leaves this machine.

.PARAMETER WavPath
  Path to the input WAV file (any sample rate; will auto-convert to 16kHz mono).

.PARAMETER OutDir
  Output directory for the transcript. Defaults to .\out\transcripts\

.PARAMETER Model
  Whisper model to use (e.g. base.en, small.en, small). Defaults to small.en.
  Model must already be downloaded via: cd backend && build_whisper.cmd small

.PARAMETER Language
  Language code for transcription. Defaults to en.

.PARAMETER NoConvert
  Skip the 16kHz mono conversion step (use if WAV is already 16kHz mono).

.EXAMPLE
  # Transcribe Teams audio captured via VB-Audio:
  .\tools\transcribe.ps1 -WavPath sample\audio\demo.wav

  # Transcribe and save to a specific folder:
  .\tools\transcribe.ps1 -WavPath sample\audio\demo.wav -OutDir out\transcripts

  # Use large model for better accuracy:
  .\tools\transcribe.ps1 -WavPath sample\audio\meeting.wav -Model large-v3-turbo
#>
param(
    [Parameter(Mandatory = $true)]  [string]$WavPath,
    [string]$OutDir = "",
    [string]$Model = "small.en",
    [string]$Language = "en",
    [switch]$NoConvert
)

$root = Split-Path $PSScriptRoot -Parent

# ── Validate input ─────────────────────────────────────────────────────────────
if (!(Test-Path $WavPath)) {
    Write-Error "WAV file not found: $WavPath"; exit 1
}

# ── Resolve out dir ───────────────────────────────────────────────────────────
if (!$OutDir) { $OutDir = Join-Path $root "out\transcripts" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseName = [IO.Path]::GetFileNameWithoutExtension($WavPath)
$outTxt = Join-Path $OutDir "$baseName-$stamp.txt"

# ── Find whisper binary ───────────────────────────────────────────────────────
$pkgDir = Join-Path $root "backend\whisper-server-package"
$whisperExe = Join-Path $pkgDir "whisper-server.exe"
if (!(Test-Path $whisperExe)) {
    # Try build output path
    $whisperExe = Join-Path $root "backend\whisper.cpp\build\bin\Release\whisper-server.exe"
}
if (!(Test-Path $whisperExe)) {
    Write-Error @"
whisper-server.exe not found. Build it first:
  cd $root\backend
  build_whisper.cmd small
"@
    exit 1
}

# ── Find model ────────────────────────────────────────────────────────────────
$modelFile = Join-Path $pkgDir "models\ggml-$Model.bin"
if (!(Test-Path $modelFile)) {
    $modelFile = Join-Path $root "backend\whisper.cpp\models\ggml-$Model.bin"
}
if (!(Test-Path $modelFile)) {
    Write-Error "Model file not found: ggml-$Model.bin. Run: cd backend && build_whisper.cmd $Model"; exit 1
}

# ── Convert to 16kHz mono (unless skipped) ────────────────────────────────────
$inputFile = $WavPath
if (!$NoConvert) {
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (!$ff) {
        Write-Warning "ffmpeg not found in PATH — skipping conversion. Install ffmpeg if the WAV is not already 16kHz mono."
    }
    else {
        $converted = [IO.Path]::ChangeExtension($WavPath, "") + "_16k.wav"
        Write-Host "Converting to 16kHz mono..."
        & ffmpeg -y -i $WavPath -ar 16000 -ac 1 $converted 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $inputFile = $converted
            Write-Host "Converted: $converted"
        }
        else {
            Write-Warning "Conversion failed — will attempt transcription with original file."
        }
    }
}

# ── Run whisper-server for transcription ──────────────────────────────────────
Write-Host ""
Write-Host "Transcribing: $inputFile"
Write-Host "Model: $modelFile"
Write-Host "Diarization: enabled (SPEAKER_00, SPEAKER_01, ...)"
Write-Host ""

# whisper-server supports --output-txt and --diarize
# Note: if using the HTTP server mode, it runs on port 8178 — we use direct-file mode here
$transcriptRaw = & $whisperExe `
    --model    $modelFile `
    --file     $inputFile `
    --language $Language `
    --diarize `
    --output-txt 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Transcription failed. Check whisper-server output above."
    exit 1
}

# ── Save transcript ───────────────────────────────────────────────────────────
$transcriptRaw | Out-File -Encoding UTF8 $outTxt
Write-Host "Transcript saved: $outTxt"
Write-Host ""

# ── Show preview ──────────────────────────────────────────────────────────────
Write-Host "=== Transcript Preview (first 20 lines) ===" -ForegroundColor Cyan
Get-Content $outTxt | Select-Object -First 20
Write-Host "..."
Write-Host ""

# ── Suggest next steps ────────────────────────────────────────────────────────
Write-Host "Next: generate meeting notes:" -ForegroundColor Green
Write-Host "  .\tools\gen-summary.ps1 -Transcript '$outTxt' -TemplateId exec_summary_v1"
Write-Host "  .\tools\gen-summary.ps1 -Transcript '$outTxt' -TemplateId action_items_v1"
Write-Host ""
Write-Host "Or map speaker labels to real names first:"
Write-Host "  .\tools\map-speakers.ps1 -TranscriptPath '$outTxt'"
