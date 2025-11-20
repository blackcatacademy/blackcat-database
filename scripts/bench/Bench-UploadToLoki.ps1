param(
  [Parameter(Mandatory=$true)] [string] $CsvPath,
  [string] $LokiUrl = "http://localhost:3100/loki/api/v1/push",
  [string] $Job = "bench",
  [string] $Db  = "unknown",
  [string] $Mode = "select",
  [string] $Table = "bench_items",
  [int] $Batch = 1000,
  [switch] $DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

function ConvertTo-UnixNs([string]$iso) {
  $dto = [DateTimeOffset]::Parse($iso).ToUniversalTime()
  $ms = $dto.ToUnixTimeMilliseconds()
  return "$($ms)000000"
}

$rows = Import-Csv -Path $CsvPath
$buf = @()
foreach ($r in $rows) {
  $labels = @{
    job = $Job; app = "blackcat-bench"; db = $Db; mode = $Mode; table = $Table
  }
  $line = (ConvertTo-Json -Compress -Depth 4 @{
    level = if ($r.ok -eq '1') { "info" } else { "error" }
    message = "bench-op"
    ms = [int]$r.ms
    rows = [int]$r.rows
    ok = [int]$r.ok
    code = $r.code
    msg  = $r.msg
    pid  = [int]$r.pid
    iter = [int]$r.iter
    ts_iso = $r.ts_iso
  })
  $buf += @([pscustomobject]@{
    labels = $labels
    ts = ConvertTo-UnixNs $r.ts_iso
    line = $line
  })

  if ($buf.Count -ge $Batch) {
    $streams = @()
    $values = $buf | ForEach-Object { ,@($_.ts, $_.line) }
    $streams += @{
      stream = $buf[0].labels
      values = $values
    }
    $payload = @{ streams = $streams } | ConvertTo-Json -Depth 6
    if ($DryRun) { Write-Host "[DRYRUN] Would push $($values.Count) entries"; }
    else {
      Invoke-RestMethod -Method Post -Uri $LokiUrl -ContentType 'application/json' -Body $payload | Out-Null
    }
    $buf = @()
  }
}

if ($buf.Count -gt 0) {
  $streams = @()
  $values = $buf | ForEach-Object { ,@($_.ts, $_.line) }
  $streams += @{
    stream = $buf[0].labels
    values = $values
  }
  $payload = @{ streams = $streams } | ConvertTo-Json -Depth 6
  if ($DryRun) { Write-Host "[DRYRUN] Would push $($values.Count) entries"; }
  else {
    Invoke-RestMethod -Method Post -Uri $LokiUrl -ContentType 'application/json' -Body $payload | Out-Null
  }
}

Write-Host "Uploaded $(($rows | Measure-Object).Count) rows to Loki stream job=$Job, db=$Db, mode=$Mode, table=$Table"
