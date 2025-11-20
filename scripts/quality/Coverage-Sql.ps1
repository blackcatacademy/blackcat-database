param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [string] $TraceFile = "./.sqltrace/exec.log",
  [switch] $FailOnMiss
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Regions defined in SQL: lines with '-- region: <name>'
$regions = @{}
$files = Get-ChildItem -Path $PackagesDir -Recurse -Filter *.sql -File
foreach ($f in $files) {
  $lns = Get-Content -Path $f.FullName
  foreach ($ln in $lns) {
    if ($ln -match '--\s*region:\s*(?<r>[\w\-\.:/]+)') {
      $r = $matches['r']
      $regions[$r] = $true
    }
  }
}

$seen = @{}
if (Test-Path $TraceFile) {
  $exec = Get-Content -Path $TraceFile | Where-Object { $_ -match 'region=' }
  foreach ($e in $exec) {
    if ($e -match 'region=(?<r>[\w\-\.:/]+)') { $seen[$matches['r']] = $true }
  }
}

$all = $regions.Keys | Sort-Object
$covered = $seen.Keys | Sort-Object
$miss = Compare-Object -ReferenceObject $all -DifferenceObject $covered -PassThru | Where-Object { $_ -in $all }

Write-Host "# SQL Coverage"
Write-Host "Defined regions: $($all.Count)"
Write-Host "Executed regions: $($covered.Count)"
if ($miss.Count -gt 0) {
  Write-Host "Missing coverage:"
  $miss | ForEach-Object { Write-Host " - $_" }
  if ($FailOnMiss) { exit 1 }
} else {
  Write-Host "All regions covered."
}
