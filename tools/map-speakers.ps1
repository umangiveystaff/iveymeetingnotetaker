<#
.SYNOPSIS
  Replace SPEAKER_00/SPEAKER_01/... labels in a diarized transcript with
  real participant names. Saves the renamed transcript and prints it.
  
  This is an OPTIONAL step. Run it between transcribe.ps1 and gen-summary.ps1
  so that action items are attributed to real names rather than SPEAKER_XX.

.PARAMETER TranscriptPath
  Path to the diarized transcript TXT file (from transcribe.ps1).

.PARAMETER MappingPath
  Optional path to a JSON mapping file. If omitted, you will be prompted
  interactively to enter names. The mapping file format is:
  { "SPEAKER_00": "Alex Smith", "SPEAKER_01": "Jordan Lee" }

.PARAMETER OutPath
  Optional output path. Defaults to <original>-named.txt in the same folder.

.EXAMPLE
  # Interactive mode — you type the names:
  .\tools\map-speakers.ps1 -TranscriptPath out\transcripts\demo.txt

  # Use a pre-built mapping file:
  .\tools\map-speakers.ps1 -TranscriptPath out\transcripts\demo.txt `
      -MappingPath config\speaker_names.json

  # One-liner with mapping specified inline:
  .\tools\map-speakers.ps1 -TranscriptPath out\transcripts\demo.txt `
      -MappingPath (New-TemporaryFile | % { '{"SPEAKER_00":"Alex","SPEAKER_01":"Jordan"}' | Set-Content $_ -Encoding UTF8; $_.FullName })
#>
param(
    [Parameter(Mandatory = $true)] [string]$TranscriptPath,
    [string]$MappingPath = "",
    [string]$OutPath = ""
)

if (!(Test-Path $TranscriptPath)) {
    Write-Error "Transcript file not found: $TranscriptPath"; exit 1
}

$content = Get-Content $TranscriptPath -Raw -Encoding UTF8

# ── Find all SPEAKER_XX labels in the transcript ──────────────────────────────
$speakerPattern = '\[SPEAKER_(\d+)\]'
$speakerLabels = [regex]::Matches($content, $speakerPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
$speakers = $speakerLabels | Select-Object -Unique

if ($speakers.Count -eq 0) {
    Write-Warning "No [SPEAKER_XX] labels found in transcript. Is the transcript diarized?"
    Write-Host "Transcript content preview:"
    $content | Select-String "SPEAKER" | Select-Object -First 5
    exit 0
}

Write-Host ""
Write-Host "=== Speaker Name Mapping ===" -ForegroundColor Cyan
Write-Host "Found $($speakers.Count) speaker(s) in transcript."
Write-Host ""

# ── Build name mapping ────────────────────────────────────────────────────────
$nameMap = @{}

if ($MappingPath -and (Test-Path $MappingPath)) {
    # Load from JSON file
    $json = Get-Content $MappingPath -Raw | ConvertFrom-Json
    $json.PSObject.Properties | ForEach-Object {
        $nameMap[$_.Name] = $_.Value
    }
    Write-Host "Loaded speaker mapping from: $MappingPath"
    $nameMap.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key) -> $($_.Value)"
    }
}
else {
    # Interactive mode
    Write-Host "Enter a real name for each speaker label." -ForegroundColor Yellow
    Write-Host "(Press Enter to keep the SPEAKER_XX label as-is.)"
    Write-Host ""

    foreach ($speaker in $speakers) {
        # Show a sample line with this speaker speaking
        $sampleLine = ($content -split "`n") | Where-Object { $_ -match [regex]::Escape($speaker) } | Select-Object -First 1
        if ($sampleLine) {
            Write-Host "  Sample: $($sampleLine.Trim())" -ForegroundColor DarkGray
        }
        $name = Read-Host "  Name for $speaker"
        if ($name.Trim()) {
            $nameMap[$speaker] = $name.Trim()
        }
    }
}

Write-Host ""

# ── Apply substitutions ───────────────────────────────────────────────────────
$renamed = $content
foreach ($entry in $nameMap.GetEnumerator()) {
    $renamed = $renamed -replace [regex]::Escape($entry.Key), "[$($entry.Value)]"
}

# ── Save output ───────────────────────────────────────────────────────────────
if (!$OutPath) {
    $dir = [IO.Path]::GetDirectoryName($TranscriptPath)
    $noExt = [IO.Path]::GetFileNameWithoutExtension($TranscriptPath)
    $OutPath = Join-Path $dir "$noExt-named.txt"
}

$renamed | Out-File -Encoding UTF8 $OutPath
Write-Host "Renamed transcript saved: $OutPath" -ForegroundColor Green

# ── Save mapping for reuse ───────────────────────────────────────────────────
if (!$MappingPath -and $nameMap.Count -gt 0) {
    $mapSave = Join-Path (Split-Path $TranscriptPath) "speaker_map.json"
    $nameMap | ConvertTo-Json | Out-File -Encoding UTF8 $mapSave
    Write-Host "Mapping saved for reuse: $mapSave" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== Preview (first 15 lines) ===" -ForegroundColor Cyan
Get-Content $OutPath | Select-Object -First 15
Write-Host ""
Write-Host "Next: generate meeting notes with attributed speakers:"
Write-Host "  .\tools\gen-summary.ps1 -Transcript '$OutPath' -TemplateId exec_summary_v1"
Write-Host "  .\tools\gen-summary.ps1 -Transcript '$OutPath' -TemplateId action_items_v1"
