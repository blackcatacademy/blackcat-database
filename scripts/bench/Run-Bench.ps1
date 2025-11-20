[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string] $Dsn,
  [string] $User = "",
  [string] $Pass = "",
  [ValidateSet('select','seek')] [string] $Mode = "select",
  [int] $Concurrency = 4,
  [int] $Duration = 30,
  [string] $Table = "bench_items",
  [int] $SeedRows = 50000,
  [int] $PageSize = 50,
  [string] $OutDir = "bench/results"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 1) Ensure results dir
$null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction SilentlyContinue

# 2) Ensure schema + seed data
Write-Host "Preparing schema/table '$Table' and seed data (target $SeedRows rows)..."
$phpArgs = @(
  (Join-Path $PSScriptRoot "BenchSchema.php"),
  "--dsn", $Dsn,
  "--user", $User,
  "--pass", $Pass,
  "--table", $Table,
  "--seed", "$SeedRows"
)
$phpOut = & php @phpArgs 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "BenchSchema failed: $phpOut"
  exit $LASTEXITCODE
}
Write-Host $phpOut

# 3) Spawn workers
$procs = @()
for ($i=1; $i -le $Concurrency; $i++) {
  $csv = Join-Path $OutDir ("worker_{0}.csv" -f $i)
  # write header to CSV
  "iter,ms,ok,rows" | Out-File -FilePath $csv -Encoding ASCII -NoNewline
  Add-Content -Path $csv -Value "`n"
  $workerArgs = @(
    (Join-Path $PSScriptRoot "BenchWorker.php"),
    "--dsn", $Dsn,
    "--user", $User,
    "--pass", $Pass,
    "--mode", $Mode,
    "--table", $Table,
    "--duration", "$Duration",
    "--page", "$PageSize",
    "--out", $csv
  )
  $p = Start-Process -FilePath "php" -ArgumentList $workerArgs -NoNewWindow -PassThru
  $procs += $p
  Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 60) # small jitter
}

# 4) Wait for all
Wait-Process -Id ($procs | ForEach-Object { $_.Id })
Write-Host "Benchmark finished. Results in $OutDir"
