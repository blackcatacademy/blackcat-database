
param(
  [Parameter(Mandatory=$true)] [string] $CsvGlob,
  [Parameter(Mandatory=$true)] [string] $ProjectId,
  [Parameter(Mandatory=$true)] [string] $Dataset,
  [Parameter(Mandatory=$true)] [string] $Table,
  [string] $AccessToken,
  [switch] $Ensure,
  [string] $Location = "EU",
  [int] $BatchSize = 500
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AccessToken {
  param([string]$Provided)
  if ($Provided) { return $Provided }
  try {
    $tok = (& gcloud auth application-default print-access-token) 2>$null
    if ($tok) { return $tok.Trim() }
  } catch {}
  try {
    $tok = (& gcloud auth print-access-token) 2>$null
    if ($tok) { return $tok.Trim() }
  } catch {}
  throw "No AccessToken provided and gcloud not available. Pass -AccessToken."
}

function Invoke-Google {
  param([string]$Method,[string]$Url,$Body=$null,[string]$Token)
  $headers = @{ 'Authorization' = "Bearer $Token" }
  if ($Body) {
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 10)
  } else {
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers
  }
}

$token = Get-AccessToken -Provided $AccessToken

$files = Get-ChildItem -Path $CsvGlob -File -ErrorAction SilentlyContinue
if (-not $files) { throw "No files match: $CsvGlob" }

$base = "https://www.googleapis.com/bigquery/v2/projects/$ProjectId"

if ($Ensure) {
  # Ensure dataset
  try {
    Invoke-Google -Method GET -Url "$base/datasets/$Dataset" -Token $token | Out-Null
  } catch {
    Write-Host "Creating dataset $Dataset ($Location)"
    Invoke-Google -Method POST -Url "$base/datasets" -Token $token -Body @{
      datasetReference = @{ datasetId = $Dataset; projectId = $ProjectId }
      location = $Location
    } | Out-Null
  }
  # Ensure table
  try {
    Invoke-Google -Method GET -Url "$base/datasets/$Dataset/tables/$Table" -Token $token | Out-Null
  } catch {
    Write-Host "Creating table $Table"
    $schema = @{
      fields = @(
        @{ name='ts_iso'; type='TIMESTAMP' },
        @{ name='ms';     type='INTEGER' },
        @{ name='rows';   type='INTEGER' },
        @{ name='ok';     type='BOOLEAN' },
        @{ name='code';   type='STRING' },
        @{ name='msg';    type='STRING' },
        @{ name='pid';    type='INTEGER' },
        @{ name='iter';   type='INTEGER' },
        @{ name='mode';   type='STRING' },
        @{ name='db';     type='STRING' },
        @{ name='table';  type='STRING' }
      )
    }
    Invoke-Google -Method POST -Url "$base/datasets/$Dataset/tables" -Token $token -Body @{
      tableReference = @{ projectId = $ProjectId; datasetId = $Dataset; tableId = $Table }
      schema = $schema
    } | Out-Null
  }
}

$insertUrl = "$base/datasets/$Dataset/tables/$Table/insertAll"

foreach ($fi in $files) {
  $rows = Import-Csv -Path $fi.FullName
  $batch = @()
  $count = 0
  foreach ($r in $rows) {
    $count++
    $doc = @{
      ts_iso = $r.ts_iso
      ms     = [int]$r.ms
      rows   = [int]$r.rows
      ok     = ([int]$r.ok -eq 1)
      code   = $r.code
      msg    = $r.msg
      pid    = [int]$r.pid
      iter   = [int]$r.iter
      mode   = $r.mode
      db     = $env:DB_DIALECT
      table  = $env:BENCH_TABLE
    }
    $batch += @{ json = $doc; insertId = ("{0}-{1}" -f $fi.Name, $count) }
    if ($batch.Count -ge $BatchSize) {
      $payload = @{ kind='bigquery#tableDataInsertAllRequest'; rows = $batch }
      $resp = Invoke-Google -Method POST -Url $insertUrl -Token $token -Body $payload
      if ($resp.insertErrors) {
        Write-Error ("Insert errors for file {0}: {1}" -f $fi.Name, ($resp.insertErrors | ConvertTo-Json -Depth 6))
      }
      $batch = @()
    }
  }
  if ($batch.Count -gt 0) {
    $payload = @{ kind='bigquery#tableDataInsertAllRequest'; rows = $batch }
    $resp = Invoke-Google -Method POST -Url $insertUrl -Token $token -Body $payload
    if ($resp.insertErrors) {
      Write-Error ("Insert errors for file {0}: {1}" -f $fi.Name, ($resp.insertErrors | ConvertTo-Json -Depth 6))
    }
  }
  Write-Host ("Uploaded {0} rows from {1}" -f $rows.Count, $fi.Name)
}
