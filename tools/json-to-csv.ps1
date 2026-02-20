<#
.SYNOPSIS
  Convert the most recent action_items_v1 JSON file in .\out\ to CSV.
.PARAMETER JsonPath
  Optional: explicit path to a JSON file. If omitted, uses the most recent
  out\summary-action_items_v1-*.json file.
.PARAMETER OutDir
  Optional: output directory. Defaults to .\out\.
.EXAMPLE
  .\tools\json-to-csv.ps1
  .\tools\json-to-csv.ps1 -JsonPath out\summary-action_items_v1-20260220-164424.json
#>
param(
  [string]$JsonPath,
  [string]$OutDir
)

$root = Split-Path $PSScriptRoot -Parent

# ── Resolve JSON input ────────────────────────────────────────────────────────
if (-not $JsonPath) {
  $candidates = Get-ChildItem (Join-Path $root "out\summary-action_items_v1-*.json") `
                  -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  if ($candidates.Count -eq 0) {
    Write-Error "No action_items_v1 JSON files found in .\out\. Run gen-summary.ps1 first."
    exit 1
  }
  $JsonPath = $candidates[0].FullName
  Write-Host "Using: $JsonPath"
}

if (!(Test-Path $JsonPath)) {
  Write-Error "File not found: $JsonPath"
  exit 1
}

# ── Parse JSON ────────────────────────────────────────────────────────────────
$raw = Get-Content $JsonPath -Raw
try {
  $items = $raw | ConvertFrom-Json
} catch {
  # Attempt to extract JSON array if wrapped in other text
  $match = [regex]::Match($raw, '\[[\s\S]*\]')
  if (-not $match.Success) {
    Write-Error "Could not parse JSON array from: $JsonPath"
    exit 1
  }
  $items = $match.Value | ConvertFrom-Json
}

if ($items.Count -eq 0) {
  Write-Warning "JSON parsed but array is empty. Nothing to export."
  exit 0
}

# ── Build CSV ─────────────────────────────────────────────────────────────────
if (-not $OutDir) { $OutDir = Join-Path $root "out" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = Join-Path $OutDir "action-items-$stamp.csv"

$rows = $items | ForEach-Object {
  [PSCustomObject]@{
    Title = ($_.title  -replace '"','""')
    Owner = ($_.owner  -replace '"','""')
    Due   = ($_.due    -replace '"','""')
    Notes = ($_.notes  -replace '"','""')
  }
}

$rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "`n=== CSV Export ===" -ForegroundColor Cyan
Write-Host "Saved: $csvPath"
Write-Host "Rows:  $($rows.Count)"
$rows | Format-Table -AutoSize
