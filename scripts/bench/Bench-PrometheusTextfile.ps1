
param(
  [Parameter(Mandatory=$true)] [string] $CsvGlob,
  [Parameter(Mandatory=$true)] [string] $OutPath,
  [string] $Db = "unknown",
  [string] $Mode = "select",
  [string] $Table = "bench_items"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = Get-ChildItem -Path $CsvGlob -File -ErrorAction SilentlyContinue
if (-not $files) { throw "No files match: $CsvGlob" }

$histBuckets = @(1,2,5,10,20,50,100,200,500,1000,2000)
$hist = @{}; foreach ($b in $histBuckets + @('+Inf')) { $hist["$b"] = 0 }
$ops = 0; $errs = 0; $rows = 0; $sum = 0; $cnt = 0

foreach ($fi in $files) {
  $data = Import-Csv -Path $fi.FullName
  foreach ($r in $data) {
    $ops++
    if ([int]$r.ok -ne 1) { $errs++ }
    $ms = [int]$r.ms
    $rows += [int]$r.rows
    $sum += $ms; $cnt++
    $placed = $false
    foreach ($b in $histBuckets) {
      if ($ms -le $b) { $hist["$b"]++; $placed = $true; break }
    }
    if (-not $placed) { $hist['+Inf']++ }
  }
}

$labels = "app=`"blackcat-bench`",db=`"$Db`",mode=`"$Mode`",table=`"$Table`""

$sb = New-Object System.Text.StringBuilder
$sb.AppendLine("# HELP bench_ops_total Total operations") | Out-Null
$sb.AppendLine("# TYPE bench_ops_total counter") | Out-Null
$sb.AppendLine("bench_ops_total{$labels} $ops") | Out-Null

$sb.AppendLine("# HELP bench_errors_total Total error operations") | Out-Null
$sb.AppendLine("# TYPE bench_errors_total counter") | Out-Null
$sb.AppendLine("bench_errors_total{$labels} $errs") | Out-Null

$sb.AppendLine("# HELP bench_rows_total Total rows processed") | Out-Null
$sb.AppendLine("# TYPE bench_rows_total counter") | Out-Null
$sb.AppendLine("bench_rows_total{$labels} $rows") | Out-Null

$sb.AppendLine("# HELP bench_latency_ms Latency histogram (ms)") | Out-Null
$sb.AppendLine("# TYPE bench_latency_ms histogram") | Out-Null
$cum = 0
foreach ($b in $histBuckets) {
  $cum += $hist["$b"]
  $sb.AppendLine("bench_latency_ms_bucket{$labels,le=`"$b`"} $cum") | Out-Null
}
$cum += $hist['+Inf']
$sb.AppendLine("bench_latency_ms_bucket{$labels,le=`"+Inf`"} $cum") | Out-Null
$sb.AppendLine("bench_latency_ms_sum{$labels} $sum") | Out-Null
$sb.AppendLine("bench_latency_ms_count{$labels} $cnt") | Out-Null

$dir = Split-Path -Parent $OutPath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$sb.ToString() | Out-File -FilePath $OutPath -NoNewline -Encoding ASCII
Write-Host "Wrote $OutPath"
