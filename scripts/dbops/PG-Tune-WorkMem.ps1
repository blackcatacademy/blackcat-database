param([Parameter(Mandatory=$true)] [string] $ExplainPath)

# Heuristic: parse 'rows=' and suggest work_mem ~ (width*rows*log2(rows)) / concurrency
$txt = Get-Content -Raw -Path $ExplainPath
if ($txt -match 'rows=(?<r>\d+)') {
  $rows = [int]$matches['r']
} else { $rows = 100000 }
$width = 64
$concurrency = 4
$wm_kb = [int]([Math]::Ceiling(($width * $rows * [Math]::Log($rows,2)) / $concurrency / 1024))
Write-Host ("suggested work_mem ≈ {0} kB (heuristic)" -f $wm_kb)
