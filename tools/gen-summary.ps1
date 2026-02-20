param(
  [Parameter(Mandatory = $true)] [string]$Transcript,
  [Parameter(Mandatory = $true)] [ValidateSet("exec_summary_v1", "action_items_v1", "ivey_meeting", "standard_meeting", "daily_standup")] [string]$TemplateId,
  [string]$Model = "llama3.2"
)

if (!(Test-Path $Transcript)) { Write-Error "Transcript file not found: $Transcript"; exit 1 }

$templatesPath = Join-Path $PSScriptRoot "..\frontend\src\config\summary_templates.json"
if (!(Test-Path $templatesPath)) { Write-Error "Templates not found: $templatesPath"; exit 1 }
$templates = Get-Content $templatesPath -Raw | ConvertFrom-Json
$template = $templates | Where-Object { $_.id -eq $TemplateId }
if (!$template) { Write-Error "TemplateId not found: $TemplateId"; exit 1 }

$transcriptText = Get-Content $Transcript -Raw
$prompt = @"
You are an AI assistant analyzing a meeting transcript.

TRANSCRIPT (speaker-labeled where possible):
$transcriptText

TASK:
$($template.prompt)
"@.Trim()

$body = @{ model = $Model; prompt = $prompt; stream = $false }
if ($template.format -eq "json") { $body.format = "json" }

$response = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" -Method Post -Body ($body | ConvertTo-Json -Depth 6) -ContentType "application/json"

$outDir = Join-Path $PSScriptRoot "..\out"
New-Item -ItemType Directory -Force $outDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$base = Join-Path $outDir "summary-$TemplateId-$stamp"

if ($template.format -eq "json") {
  try {
    $json = $response.response | ConvertFrom-Json
    $json | ConvertTo-Json -Depth 10 | Tee-Object -FilePath ("$base.json")
    Write-Host "`n=== ACTION ITEMS (JSON) ==="
    $json | ConvertTo-Json -Depth 10
  }
  catch {
    $fixed = $response.response.Trim() -replace "^[^\[]*", "" -replace "[^\]]*$", ""
    $fixed | Out-File -Encoding utf8 ("$base.json")
    Write-Warning "Model returned non-strict JSON. Saved raw/fixed JSON to $base.json"
    Write-Host $fixed
  }
}
else {
  $response.response | Out-File -Encoding utf8 ("$base.md")
  Write-Host "`n=== EXEC SUMMARY (Markdown) ==="
  Write-Host $response.response
}
