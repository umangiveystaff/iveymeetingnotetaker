# Teams Transcript Export — Path B (Live Transcription)

> **Use case:** Your Microsoft 365 tenant has Teams Premium or a meeting policy that allows **Live Transcription**. Rather than capturing audio, you download the official transcript file and feed it into the summary pipeline.

---

## Licensing & Policy Requirements

| Feature | Required License/Policy |
|---------|------------------------|
| Start Live Transcription | Teams Premium **or** Microsoft 365 E3/E5 + Teams meeting transcription policy enabled |
| Download transcript after meeting | Same as above; meeting organizer controls who can download |
| Transcript stored in OneDrive/SharePoint | Requires OneDrive for Business (included in most M365 plans) |

> **Check with your IT admin** if Live Transcription is greyed out — it is a per-tenant and per-user meeting policy set in the Teams Admin Center.

---

## Step 1 — Enable Live Transcription during a meeting

1. Join or start a Teams meeting
2. Click the three-dot menu **(···)** in the meeting controls
3. Select **Start transcription**
   - If the option is missing, transcription is not enabled for your tenant (use Path A instead)
4. The transcript panel opens on the right; speakers are identified with their display names

---

## Step 2 — Stop the meeting and find the transcript

After the meeting ends, the transcript is available in two places:

### Option A — Meeting Recap (recommended)

1. In Teams, go to **Calendar**
2. Click the meeting that just ended
3. Select the **Recap** tab (appears after the meeting)
4. Click **Transcript** → **Download** → saves as a `.vtt` file (WebVTT) or `.docx`

### Option B — Meeting Chat

1. In the meeting chat thread, scroll down after the meeting ends
2. Teams posts a **"Meeting ended"** card with a link to the transcript
3. Click **Download** → `.vtt` file

### Option C — OneDrive / SharePoint

Transcripts are automatically stored in the meeting organizer's OneDrive:
```
OneDrive / Recordings / <MeetingName> / <MeetingName>-Transcript.vtt
```

---

## Step 3 — Convert the VTT transcript to plain text

The `.vtt` file contains timestamps and speaker labels. Use this PowerShell snippet to strip them:

```powershell
param([string]$VttPath)

$lines = Get-Content $VttPath -Encoding UTF8
$text  = $lines | Where-Object {
  $_ -notmatch '^WEBVTT' -and
  $_ -notmatch '^\d+$' -and
  $_ -notmatch '^\d{2}:\d{2}' -and
  $_.Trim() -ne ''
} | ForEach-Object { $_.Trim() }

$outPath = [IO.Path]::ChangeExtension($VttPath, ".txt")
$text -join "`n" | Out-File -Encoding utf8 $outPath
Write-Host "Plain text saved: $outPath"
```

Save as `tools\vtt-to-txt.ps1` and run:

```powershell
.\tools\vtt-to-txt.ps1 -VttPath "C:\path\to\transcript.vtt"
```

This produces a `.txt` file suitable for the summary pipeline.

---

## Step 4 — Run the summary pipeline on the transcript

```powershell
cd C:\Users\usharma\dev\iveymeetingnotetaker

$transcript = "C:\path\to\transcript.txt"   # path from Step 3 output

# Executive summary
.\tools\gen-summary.ps1 -Transcript $transcript -TemplateId exec_summary_v1

# Action items
.\tools\gen-summary.ps1 -Transcript $transcript -TemplateId action_items_v1
```

Outputs appear in `.\out\` with timestamps.

---

## Comparison: Path A vs Path B

| | Path A (local capture) | Path B (Teams transcript) |
|-|----------------------|--------------------------|
| Requires VB-Audio + FFmpeg | ✅ Yes | ❌ No |
| Requires Teams Premium license | ❌ No | ✅ Often yes |
| Speaker attribution | Via diarization (whisper) | ✅ Built-in (display names) |
| Works without IT admin | ✅ Yes | Depends on tenant policy |
| Privacy | 100% local | Transcript stored in M365 cloud |
| Works with external guests | ✅ Yes | Depends on guest policy |

---

## Hybrid (Path C)

If Live Transcription is sometimes available and sometimes not:

1. **Default:** Use Path A (always works, no policy dependency)
2. **When transcription IS available:** Download the VTT → skip whisper.cpp → run Path B pipeline
3. Both paths converge at `gen-summary.ps1` — same summarization regardless of transcription source

---

## Compliance reminder

- Teams Live Transcription notifies all participants that the meeting is being transcribed — this is a Microsoft-provided consent mechanism built into the product.
- Transcripts stored in OneDrive are subject to your organization's data retention and DLP policies.
- Do not share transcript files externally without authorization.
