[CmdletBinding()]
param(
  [string] $Root = ".",
  [int] $MaxFileSizeMB = 5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$patterns = @(
  '(?i)aws_secret_access_key\s*=\s*[A-Za-z0-9\/+=]{20,}',
  '(?i)api[_-]?key\s*=\s*[A-Za-z0-9_\-]{16,}',
  '(?i)password\s*=\s*[^#\r\n]{6,}',
  '(?i)BEGIN\s+PRIVATE\s+KEY'
)
$maxBytes = $MaxFileSizeMB * 1MB
$files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
  $_.FullName -notmatch '\.git|node_modules|vendor|bench/results|\.enc\.yaml|\.png|\.jpg|\.jpeg|\.gif'
}

$hits = @()
foreach ($f in $files) {
  if ($f.Length -gt $maxBytes) { continue }
  foreach ($pat in $patterns) {
    $match = Select-String -Path $f.FullName -Pattern $pat -ErrorAction SilentlyContinue -Quiet
    if ($match) {
      $hits += "$($f.FullName): pattern $pat"
      break
    }
  }
}
if ($hits.Count -gt 0) {
  Write-Host "Potential plaintext secrets found:"
  $hits | ForEach-Object { Write-Host " - $_" }
  exit 1
} else {
  Write-Host "No plaintext secrets detected."
}
