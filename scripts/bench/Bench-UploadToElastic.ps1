param(
  [Parameter(Mandatory=$true)] [string] $CsvPath,
  [string] $EsUrl = "http://localhost:9200",
  [string] $Index = "bench-logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

# Ensure index with basic mapping
try {
  Invoke-RestMethod -Method GET -Uri "$EsUrl/$Index" -ErrorAction Stop | Out-Null
} catch {
  $mapping = @{
    settings = @{
      number_of_shards = 1; number_of_replicas = 0
    }
    mappings = @{
      properties = @{
        ts_iso = @{ type = "date"; format = "strict_date_optional_time||epoch_millis" }
        ms     = @{ type = "integer" }
        rows   = @{ type = "integer" }
        ok     = @{ type = "boolean" }
        code   = @{ type = "keyword" }
        msg    = @{ type = "text" }
        pid    = @{ type = "integer" }
        iter   = @{ type = "integer" }
        mode   = @{ type = "keyword" }
        db     = @{ type = "keyword" }
        table  = @{ type = "keyword" }
      }
    }
  } | ConvertTo-Json -Depth 6
  Invoke-RestMethod -Method PUT -Uri "$EsUrl/$Index" -ContentType 'application/json' -Body $mapping | Out-Null
  Write-Host "Created index $Index"
}

$rows = Import-Csv -Path $CsvPath
$B = New-Object System.Text.StringBuilder
$batch = 0
function Invoke-BulkFlush {
  param([string]$payload)
  if (-not $payload) { return }
  Invoke-RestMethod -Method POST -Uri "$EsUrl/$Index/_bulk" -ContentType 'application/x-ndjson' -Body $payload | Out-Null
}

foreach ($r in $rows) {
  $meta = @{ index = @{ _index = $Index } } | ConvertTo-Json -Compress
  $doc  = @{
    ts_iso = $r.ts_iso; ms=[int]$r.ms; rows=[int]$r.rows; ok=([int]$r.ok -eq 1);
    code=$r.code; msg=$r.msg; pid=[int]$r.pid; iter=[int]$r.iter; mode=$r.mode; db=$env:DB_DIALECT; table=$env:BENCH_TABLE
  } | ConvertTo-Json -Compress
  [void]$B.AppendLine($meta)
  [void]$B.AppendLine($doc)
  $batch++
  if ($batch -ge 1000) {
    Invoke-BulkFlush -payload $B.ToString()
    $B.Clear() | Out-Null
    $batch = 0
  }
}
if ($batch -gt 0) { Invoke-BulkFlush -payload $B.ToString() }

Write-Host "Uploaded $(($rows | Measure-Object).Count) rows to Elasticsearch index=$Index"
