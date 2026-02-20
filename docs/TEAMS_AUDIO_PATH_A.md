# Teams Audio Capture — Path A (Local, Privacy-First)

> **Privacy guarantee:** All audio stays on this device. No audio is transmitted to Microsoft's cloud in this workflow.

## Overview

This path routes Teams' speaker output through a **VB-Audio Virtual Cable** (a local loopback device), captures it with **FFmpeg** (DirectShow), converts it to 16kHz mono WAV, and transcribes it locally with **whisper.cpp**.

```
Teams app
  └─→ [CABLE Input] (VB-Audio virtual device — in Windows Sound settings)
         └─→ [CABLE Output] (read by FFmpeg as a DirectShow audio input)
                └─→ demo.wav → 16kHz mono WAV → whisper.cpp → transcript.txt
```

---

## Step 1 — Install VB-Audio Virtual Cable

1. Download from https://vb-audio.com/Cable/
2. Run **VBCABLE_Setup_x64.exe** as Administrator
3. **Reboot** (drivers are not active until reboot)
4. After reboot, open **Sound settings** → confirm **CABLE Input** appears as a Playback device and **CABLE Output** as a Recording device

---

## Step 2 — Route Teams audio through the cable

1. In **Windows Sound settings** → **App volume and device preferences**  
   (or Right-click speaker icon → Open Sound settings → scroll down)
2. Find **Microsoft Teams** in the list and set its **Output** to **CABLE Input (VB-Audio Virtual Cable)**
3. Optionally also leave your real speakers device so you can still hear the call:  
   - Use a **Virtual Audio Cable split** or set Teams' secondary ringtone device to your real speakers

> **Tip:** You can also route per-meeting. When a Teams call starts, in **Teams → Settings → Devices**, change the Speaker to "CABLE Input".

---

## Step 3 — Enumerate DirectShow devices (verify cable is visible)

```powershell
ffmpeg -f dshow -list_devices true -i dummy 2>&1
```

Look for lines like:
```
[dshow @ ...] "CABLE Output (VB-Audio Virtual Cable)"  (audio)
```

If you don't see it, recheck the VB-Audio install and reboot.

---

## Step 4 — Start a Teams call and record audio

Replace `"CABLE Output (VB-Audio Virtual Cable)"` with the **exact name** returned by Step 3.

```powershell
# Make dirs
New-Item -ItemType Directory -Force sample\audio | Out-Null
New-Item -ItemType Directory -Force out\transcripts | Out-Null

# Record 60 seconds (adjust -t as needed; Ctrl+C to stop early)
ffmpeg -f dshow -i audio="CABLE Output (VB-Audio Virtual Cable)" `
       -t 60 -y sample\audio\demo.wav
```

> For an open-ended recording, drop `-t 60` and press **q** then Enter to stop.

---

## Step 5 — Convert to 16kHz mono (required by whisper.cpp)

```powershell
ffmpeg -i sample\audio\demo.wav -ar 16000 -ac 1 -y sample\audio\demo_16k.wav
```

---

## Step 6 — Transcribe with whisper.cpp

First, ensure the whisper server binary and model exist. If not, build them:

```cmd
cd backend
build_whisper.cmd small
cd ..
```

Then transcribe (use the `whisper-server.exe` or the standalone `whisper-cli.exe` depending on your build):

```powershell
# Adjust paths to match your actual build output
$whisperExe = "backend\whisper-server-package\whisper-server.exe"
$model      = "backend\whisper-server-package\models\ggml-small.en.bin"

# Transcribe (outputs to stdout; redirect to file)
& $whisperExe --model $model --file sample\audio\demo_16k.wav --output-txt `
  2>&1 | Out-File -Encoding utf8 out\transcripts\demo.txt

Write-Host "Transcript saved to out\transcripts\demo.txt"
```

> Alternatively, start the whisper **server** on port 8178 and POST the WAV:
> ```powershell
> backend\whisper-server-package\run-server.cmd
> # Then in another terminal:
> curl -F file=@sample\audio\demo_16k.wav http://127.0.0.1:8178/inference
> ```

---

## Step 7 — Summarize the transcript

```powershell
# Executive summary (Markdown)
.\tools\gen-summary.ps1 -Transcript out\transcripts\demo.txt -TemplateId exec_summary_v1

# Action items (JSON)
.\tools\gen-summary.ps1 -Transcript out\transcripts\demo.txt -TemplateId action_items_v1

# List all outputs
Get-ChildItem out\ | Sort-Object LastWriteTime -Descending | Select-Object Name, Length, LastWriteTime
```

---

## Step 8 — (Optional) Export to CSV / DOCX

```powershell
# CSV export of action items
.\tools\json-to-csv.ps1

# DOCX export of exec summary (requires Pandoc)
$md  = Get-ChildItem out\summary-exec_summary_v1-*.md | Sort-Object LastWriteTime | Select-Object -Last 1
pandoc $md.FullName -o ($md.FullName -replace '\.md$','.docx')
```

---

## Full one-liner (after VB-Audio is set up)

```powershell
# Capture → convert → transcribe → summarize
cd C:\Users\usharma\dev\iveymeetingnotetaker

ffmpeg -f dshow -i audio="CABLE Output (VB-Audio Virtual Cable)" -t 60 -y sample\audio\demo.wav
ffmpeg -i sample\audio\demo.wav -ar 16000 -ac 1 -y sample\audio\demo_16k.wav

$exe   = "backend\whisper-server-package\whisper-server.exe"
$model = "backend\whisper-server-package\models\ggml-small.en.bin"
& $exe --model $model --file sample\audio\demo_16k.wav --output-txt 2>&1 | Out-File out\transcripts\demo.txt

.\tools\gen-summary.ps1 -Transcript out\transcripts\demo.txt -TemplateId exec_summary_v1
.\tools\gen-summary.ps1 -Transcript out\transcripts\demo.txt -TemplateId action_items_v1
```

---

## Compliance reminder

- Always inform all call participants that the meeting is being recorded/transcribed.
- Check your organization's recording and consent policies before use.
- All processing is local — no audio leaves the device.
