[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages'),
  [string[]]$Targets = @('schema'),
  [string[]]$Only = @(),
  [string[]]$Exclude = @(),
  [switch]$AutoConfirm,
  [switch]$DryRun,
  [switch]$CommitPush
)

function Test-RepoChanges {
  param([Parameter(Mandatory)][string]$RepoPath)
  $s = (git -C $RepoPath status --porcelain) 2>$null
  return -not [string]::IsNullOrWhiteSpace($s)
}

function Confirm-Removal {
  param(
    [string]$Package,
    [string]$Target,
    [string]$Kind,
    [switch]$AutoConfirm
  )
  if ($AutoConfirm) { return $true }
  $answer = Read-Host ("Delete {0} '{1}' inside package '{2}'? (y/N)" -f $Kind, $Target, $Package)
  return $answer -match '^(?i)y(es)?$'
}

Write-Host "Packages dir: $PackagesDir"
if (!(Test-Path -LiteralPath $PackagesDir)) {
  throw "Packages directory not found: $PackagesDir"
}

$pkgs = Get-ChildItem -LiteralPath $PackagesDir -Directory | Sort-Object Name
if ($Only.Count -gt 0)   { $pkgs = $pkgs | Where-Object { $Only -contains $_.Name } }
if ($Exclude.Count -gt 0){ $pkgs = $pkgs | Where-Object { $Exclude -notcontains $_.Name } }

$summary = [ordered]@{ Removed = 0; Skipped = 0; Missing = 0; Failed = 0 }

foreach ($pkg in $pkgs) {
  $packageHadChanges = $false
  foreach ($relTarget in $Targets) {
    $fullPath = Join-Path $pkg.FullName $relTarget
    if (-not (Test-Path -LiteralPath $fullPath)) {
      $summary.Missing++
      Write-Host ("[MISS] {0} → {1}" -f $pkg.Name, $relTarget) -ForegroundColor DarkGray
      continue
    }

    $item = Get-Item -LiteralPath $fullPath -Force
    $descriptor = if ($item.PSIsContainer) { 'directory' } else { 'file' }
    if (-not (Confirm-Removal -Package $pkg.Name -Target $relTarget -Kind $descriptor -AutoConfirm:$AutoConfirm)) {
      $summary.Skipped++
      Write-Host ("[SKIP] {0} {1} (user declined)" -f $relTarget, $descriptor) -ForegroundColor Yellow
      continue
    }

    if ($DryRun) {
      Write-Host ("[DRY-RUN] Would remove {0} {1} from {2}" -f $descriptor, $relTarget, $pkg.Name) -ForegroundColor Cyan
      $summary.Skipped++
      continue
    }

    try {
      if ($PSCmdlet.ShouldProcess($fullPath, "Remove {0}" -f $descriptor)) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
        $summary.Removed++
        $packageHadChanges = $true
        Write-Host ("[REMOVED] {0} {1}" -f $descriptor, $relTarget) -ForegroundColor Green
      }
    } catch {
      $summary.Failed++
      Write-Warning ("[FAILED] {0}: {1}" -f $fullPath, $_.Exception.Message)
    }
  }

  if ($CommitPush -and $packageHadChanges) {
    git -C $pkg.FullName add -A | Out-Null
    if (Test-RepoChanges -RepoPath $pkg.FullName) {
      $branch = (git -C $pkg.FullName rev-parse --abbrev-ref HEAD).Trim()
      git -C $pkg.FullName commit -m "chore(cleanup): delete legacy paths ($($Targets -join ', '))" | Out-Null
      git -C $pkg.FullName push origin $branch | Out-Null
      Write-Host ("[PUSHED] {0} -> {1}" -f $pkg.Name, $branch) -ForegroundColor Cyan
    } else {
      Write-Host ("[NO-CHANGE] {0} (nothing to commit after cleanup)" -f $pkg.Name)
    }
  }
}

Write-Host "== SUMMARY ==" -ForegroundColor Magenta
Write-Host ("  removed : {0}" -f $summary.Removed) -ForegroundColor Green
Write-Host ("  skipped : {0}" -f $summary.Skipped) -ForegroundColor Yellow
Write-Host ("  missing : {0}" -f $summary.Missing) -ForegroundColor DarkGray
Write-Host ("  failed  : {0}" -f $summary.Failed)  -ForegroundColor Red
