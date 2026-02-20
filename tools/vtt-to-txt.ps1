<#
.SYNOPSIS
  Strip timestamps and WEBVTT headers from a .vtt transcript file and
  produce a readable plain-text file suitable for gen-summary.ps1.
.PARAMETER VttPath
  Path to the .vtt file downloaded from Teams Recap / OneDrive.
.PARAMETER OutPath
  Optional output path. Defaults to same folder as VttPath with .txt extension.
.EXAMPLE
  .\tools\vtt-to-txt.ps1 -VttPath "C:\Downloads\Meeting-Transcript.vtt"
#>
param(
  [Parameter(Mandatory=$true)] [string]$VttPath,
  [string]$OutPath
)

if (!(Test-Path $VttPath)) {
  Write-Error "VTT file not found: $VttPath"
  exit 1
}

$lines = Get-Content $VttPath -Encoding UTF8

$text = $lines | Where-Object {
  $_ -notmatch '^WEBVTT'       -and   # VTT header
  $_ -notmatch '^NOTE '        -and   # VTT comments
  $_ -notmatch '^\d+$'         -and   # sequence numbers
  $_ -notmatch '^\d{2}:\d{2}' -and   # timestamp lines  00:00:01.000 --> 00:00:05.000
  $_.Trim() -ne ''                    # blank lines
} | ForEach-Object { $_.Trim() }

# Collapse consecutive duplicate speaker lines
$deduped = @()
$prev    = ""
foreach ($line in $text) {
  if ($line -ne $prev) {
    $deduped += $line
    $prev     = $line
  }
}

if (-not $OutPath) {
  $OutPath = [IO.Path]::ChangeExtension($VttPath, ".txt")
}

$deduped -join "`n" | Out-File -Encoding UTF8 $OutPath
Write-Host "Plain text saved: $OutPath ($($deduped.Count) lines)"
Write-Host ""
Write-Host "Next step:"
Write-Host "  .\tools\gen-summary.ps1 -Transcript '$OutPath' -TemplateId exec_summary_v1"
