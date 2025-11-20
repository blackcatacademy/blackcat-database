<# Push-All.ps1
   Push submodules in ./packages and then the umbrella repo.
#>
[CmdletBinding()]
param(
  [string]$PackagesDir = "./packages",
  [switch]$SkipUmbrella
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- helpers ---
function Test-GitInstalled {
  try { git --version *> $null; return $true } catch { return $false }
}
function Test-GitRepo {
  param([string]$Path)
  try { (git -C $Path rev-parse --is-inside-work-tree 2>$null) -eq 'true' } catch { $false }
}
function Test-GitDirty {
  param([string]$Path)
  $s = git -C $Path status --porcelain
  return -not [string]::IsNullOrWhiteSpace($s)
}
function Get-DefaultBranch {
  param([string]$Path)
  $out = git -C $Path remote show origin 2>$null
  $head = ($out | Select-String -Pattern 'HEAD branch:\s*(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($head)) { return 'main' } else { return $head }
}

if (-not (Test-GitInstalled)) { throw "git is not installed (or not in PATH)" }
if (-not (Test-Path -LiteralPath $PackagesDir)) { throw "Packages dir not found: $PackagesDir" }

$root = (Resolve-Path .).Path
Write-Host "Root: $root"
Write-Host "Packages: $PackagesDir"
Write-Host ""

# --- push each submodule ---
$dirs = Get-ChildItem -LiteralPath $PackagesDir -Directory | Sort-Object Name
foreach($d in $dirs){
  $path = $d.FullName
  if (-not (Test-GitRepo -Path $path)) { Write-Warning "SKIP (not a git repo): $($d.Name)"; continue }

  $branch = Get-DefaultBranch -Path $path
  Write-Host "== [$($d.Name)] -> branch: $branch"

  $hasLocal  = ($null -ne (git -C $path rev-parse --verify $branch 2>$null))
  $hasRemote = -not [string]::IsNullOrWhiteSpace((git -C $path ls-remote --heads origin $branch))

  if ($hasLocal) {
    git -C $path switch $branch | Out-Null
  } elseif ($hasRemote) {
    git -C $path switch -c $branch --track origin/$branch | Out-Null
  } else {
    git -C $path switch -c $branch | Out-Null
  }

  if ($hasRemote) {
    git -C $path fetch origin $branch --prune | Out-Null
    git -C $path pull --rebase origin $branch | Out-Null
  }

  if (Test-GitDirty -Path $path) {
    git -C $path add -A
    git -C $path commit -m "fix(repo): align optimistic locking & quoting across backends

    - implement optimistic locking: SET version = version + 1 WHERE id=:id AND version=:expected
    - consistent identifier quoting for MySQL/MariaDB/Postgres
    - do not touch timestamps unless provided
    - small cleanups discovered by the concurrency tests"
    git -C $path push -u origin $branch
    Write-Host "PUSHED [$($d.Name)]"
  } else {
    Write-Host "CLEAN  [$($d.Name)] – no changes"
  }

  Write-Host ""
}

if (-not $SkipUmbrella) {
  Write-Host "== Umbrella repo =="
  # add updated submodule pointers along with scripts and schema maps
  git submodule status
  git add -A
  if (Test-GitDirty -Path $root) {
    git commit -m "test(concurrency): stabilize suite on MariaDB/MySQL/Postgres

    - RowLocksAndDeadlocksTest: emulate SKIP LOCKED on MariaDB via NOWAIT (non-blocking, returns 0 rows)
    - DoubleWriterRepositoryTest: forward MARIADB_* env; stream worker I/O; stricter repo selection; richer debug
    - tests/support/lock_row_repo.php: never crash diagnostics; fallback @@transaction_isolation -> @@tx_isolation; best-effort env info
    - tests/support/deadlock_worker.php: normalize BC_DB vs PDO driver; session timeouts; avoid bc_compat reinstall in children
    - phpunit.bootstrap: set PDO::MYSQL_ATTR_FOUND_ROWS; disable buffered queries; robust backend resolution"
    git push
    Write-Host "PUSHED umbrella"
  } else {
    Write-Host "CLEAN  umbrella – no changes"
  }
}
