param([Parameter(Mandatory=$true)] [string] $SlowLogPath)
$lines = Get-Content -Path $SlowLogPath -ErrorAction Stop
$queries = @()
$current = @()
foreach ($ln in $lines) {
  if ($ln -match '^# Time:') { if ($current.Count -gt 0) { $queries += ($current -join ' '); $current=@() } }
  elseif ($ln -notmatch '^#') { $current += $ln.Trim() }
}
if ($current.Count -gt 0) { $queries += ($current -join ' ') }

Write-Host "# Index Candidates"
foreach ($q in $queries) {
  if ($q -match '(?i)FROM\s+([`\w]+)') { $table = $matches[1].Trim('`') }
  $cols = @()
  $m = [regex]::Matches($q, '(?i)WHERE\s+([^\n;]+)')
  foreach ($x in $m) {
    $c = $x.Groups[1].Value -replace '[^A-Za-z0-9_,\s]', ' '
    $parts = $c -split '\s+AND\s+'
    foreach ($p in $parts) {
      if ($p -match '(?i)([`\w]+)\s*=') { $cols += $matches[1].Trim('`') }
    }
  }
  $cols = $cols | Select-Object -Unique
  if ($table -and $cols.Count -gt 0) {
    Write-Host ("- Table {0}: consider index on ({1})" -f $table, ($cols -join ', '))
  }
}
