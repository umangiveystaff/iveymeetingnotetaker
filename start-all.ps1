<#
.SYNOPSIS
  One-command launcher for the Ivey Meeting Note-Taker.
  Starts all required local services: Ollama, the Python FastAPI backend,
  and the Tauri desktop app. Nothing is sent to the cloud.

.DESCRIPTION
  Services started (all local):
    1. Ollama          -- LLM runtime on http://127.0.0.1:11434
    2. FastAPI backend -- Meeting storage + summary API on http://127.0.0.1:5167
    3. Whisper server  -- Local STT on http://127.0.0.1:8178 (if built)
    4. Tauri app       -- Desktop UI (runs pnpm dev + Tauri)

  Privacy: No audio, transcripts, or summaries leave this device.
  All LLM calls go to 127.0.0.1:11434 (Ollama). All STT is local whisper.

.PARAMETER SkipOllama
  Do not start Ollama (use if already running in background).

.PARAMETER SkipBackend
  Do not start the FastAPI backend.

.PARAMETER SkipWhisper
  Do not start the Whisper server (the Tauri app has its own built-in whisper).

.PARAMETER SkipApp
  Do not launch the Tauri desktop app (useful if you only want services).

.PARAMETER OllamaModel
  Ollama model to verify/use. Defaults to llama3.2.

.EXAMPLE
  .\start-all.ps1                     # Start everything
  .\start-all.ps1 -SkipOllama        # Skip Ollama (already running)
  .\start-all.ps1 -SkipApp           # Services only, no Tauri UI
#>

param(
    [switch]$SkipOllama,
    [switch]$SkipBackend,
    [switch]$SkipWhisper,
    [switch]$SkipApp,
    [string]$OllamaModel = "llama3.2"
)

$root = $PSScriptRoot
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"
$whiskerPkg = Join-Path $backendDir "whisper-server-package"

Write-Host ""
Write-Host "=== Ivey Meeting Note-Taker ===" -ForegroundColor Cyan
Write-Host "Starting local-only services. No data leaves this device."
Write-Host ""

# ── 1. Ollama ─────────────────────────────────────────────────────────────────
if (!$SkipOllama) {
    Write-Host "[ Ollama ]"
    $ollamaRunning = $false
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" `
            -Method Post -ContentType "application/json" -TimeoutSec 3 `
            -Body ('{"model":"' + $OllamaModel + '","prompt":"ping","stream":false}')
        $ollamaRunning = $r.response.Length -gt 0
    }
    catch {}

    if ($ollamaRunning) {
        Write-Host "  Ollama already running with $OllamaModel -- OK" -ForegroundColor Green
    }
    else {
        Write-Host "  Starting Ollama in background..."
        $null = Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 3

        # Verify model is available
        try {
            $models = & ollama list 2>&1
            if ($models -notmatch $OllamaModel) {
                Write-Host "  Pulling model $OllamaModel..." -ForegroundColor Yellow
                & ollama pull $OllamaModel
            }
        }
        catch {
            Write-Warning "  Could not verify Ollama model. Make sure 'ollama' is in PATH."
        }
        Write-Host "  Ollama started." -ForegroundColor Green
    }
}
else {
    Write-Host "[ Ollama ] Skipped." -ForegroundColor DarkGray
}

# ── 2. Whisper server (optional, Tauri app has built-in whisper) ──────────────
if (!$SkipWhisper) {
    Write-Host ""
    Write-Host "[ Whisper Server ]"
    $whisperRunScript = Join-Path $whiskerPkg "run-server.cmd"
    $whisperExe = Join-Path $whiskerPkg "whisper-server.exe"

    if (Test-Path $whisperRunScript) {
        Write-Host "  Starting whisper server on port 8178..."
        $null = Start-Process "cmd.exe" -ArgumentList "/c $whisperRunScript" `
            -WorkingDirectory $whiskerPkg -WindowStyle Minimized -PassThru
        Start-Sleep -Seconds 2
        Write-Host "  Whisper server started (http://127.0.0.1:8178)" -ForegroundColor Green
    }
    elseif (Test-Path $whisperExe) {
        $model = @(Get-ChildItem "$whiskerPkg\models\*.bin" -ErrorAction SilentlyContinue)[0]
        if ($model) {
            Write-Host "  Starting whisper server on port 8178..."
            $null = Start-Process $whisperExe `
                -ArgumentList "--model `"$($model.FullName)`" --host 127.0.0.1 --port 8178 --diarize" `
                -WorkingDirectory $whiskerPkg -WindowStyle Minimized -PassThru
            Start-Sleep -Seconds 2
            Write-Host "  Whisper server started (http://127.0.0.1:8178)" -ForegroundColor Green
        }
        else {
            Write-Warning "  No whisper model found. Run: cd backend && build_whisper.cmd small"
        }
    }
    else {
        Write-Warning "  whisper-server.exe not found. Run: cd backend && build_whisper.cmd small"
        Write-Host "  The Tauri app uses its own built-in whisper engine as fallback." -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[ Whisper Server ] Skipped." -ForegroundColor DarkGray
}

# ── 3. FastAPI backend ────────────────────────────────────────────────────────
if (!$SkipBackend) {
    Write-Host ""
    Write-Host "[ FastAPI Backend ]"

    $venvActivate = Join-Path $backendDir "venv\Scripts\activate.ps1"
    $mainPy = Join-Path $backendDir "app\main.py"

    if (!(Test-Path $mainPy)) {
        Write-Warning "  backend/app/main.py not found. Skipping backend."
    }
    elseif (!(Test-Path $venvActivate)) {
        Write-Warning "  Python venv not found. Run: cd backend && build_whisper.cmd small"
    }
    else {
        $backendScript = @"
Set-Location '$backendDir'
& '$venvActivate'
python -m uvicorn app.main:app --host 127.0.0.1 --port 5167 --reload
"@
        $null = Start-Process "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $backendScript" `
            -WindowStyle Minimized -PassThru
        Start-Sleep -Seconds 3
        Write-Host "  FastAPI backend started (http://127.0.0.1:5167)" -ForegroundColor Green
    }
}
else {
    Write-Host "[ FastAPI Backend ] Skipped." -ForegroundColor DarkGray
}

# ── 4. Tauri desktop app ──────────────────────────────────────────────────────
if (!$SkipApp) {
    Write-Host ""
    Write-Host "[ Tauri Desktop App ]"

    # Check Node/pnpm available
    $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
    if (!$pnpm) {
        Write-Warning "  pnpm not found. Installing via npm..."
        & npm install -g pnpm 2>&1 | Select-Object -Last 3
    }

    # Install dependencies if node_modules missing
    $nodeModules = Join-Path $frontendDir "node_modules"
    if (!(Test-Path $nodeModules)) {
        Write-Host "  Installing frontend dependencies (first run, takes a minute)..."
        & pnpm --prefix $frontendDir install
    }

    # Launch Tauri dev
    Write-Host "  Launching Tauri app (dev mode)..." -ForegroundColor Cyan
    Write-Host "  First launch takes 3-5 minutes (Rust compilation)."
    Write-Host "  Subsequent launches: ~10 seconds."
    Write-Host ""
    Write-Host "  Press Ctrl+C in this window to stop all services."
    Write-Host ""

    Set-Location $frontendDir
    & pnpm run tauri:dev
}
else {
    Write-Host "[ Tauri App ] Skipped." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "=== Services running ===" -ForegroundColor Green
    Write-Host "  Ollama:           http://127.0.0.1:11434"
    Write-Host "  Whisper server:   http://127.0.0.1:8178"
    Write-Host "  FastAPI backend:  http://127.0.0.1:5167"
    Write-Host ""
    Write-Host "Launch the app manually: cd frontend && pnpm run tauri:dev"
}
