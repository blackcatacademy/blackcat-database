[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages'),
  [string[]]$Only = @(),    # volitelné: čistit jen vybrané balíčky (podadresáře podle jména)
  [string[]]$Exclude = @(), # volitelné: vynechat tyto balíčky
  [switch]$CommitPush       # volitelné: commit & push změn v jednotlivých repo/submodulech
)

function Test-RepoChanges {
  param([Parameter(Mandatory)][string]$RepoPath)
  $s = (git -C $RepoPath status --porcelain) 2>$null
  return -not [string]::IsNullOrWhiteSpace($s)
}

Write-Host "Packages dir: $PackagesDir"
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "Packages dir not found: $PackagesDir" }

$pkgs = Get-ChildItem -LiteralPath $PackagesDir -Directory | Sort-Object Name
if ($Only.Count -gt 0)   { $pkgs = $pkgs | Where-Object { $Only -contains $_.Name } }
if ($Exclude.Count -gt 0){ $pkgs = $pkgs | Where-Object { $Exclude -notcontains $_.Name } }

$removed = 0; $missing = 0; $failed = 0

foreach ($pkg in $pkgs) {
  $schemaDir = Join-Path $pkg.FullName 'src'
  if (!(Test-Path -LiteralPath $schemaDir)) {
    Write-Host ("[SKIP] {0} – není 'schema'" -f $pkg.Name) -ForegroundColor DarkGray
    $missing++
    continue
  }

  Write-Host ("[FOUND] {0} -> {1}" -f $pkg.Name, $schemaDir) -ForegroundColor Yellow
  if ($PSCmdlet.ShouldProcess($schemaDir, 'Remove directory recursively')) {
    try {
      Remove-Item -LiteralPath $schemaDir -Recurse -Force -ErrorAction Stop
      Write-Host ("[REMOVED] {0}" -f $schemaDir) -ForegroundColor Green
      $removed++

      if ($CommitPush) {
        git -C $pkg.FullName add -A | Out-Null
        if (Test-RepoChanges -RepoPath $pkg.FullName) {
          $branch = (git -C $pkg.FullName rev-parse --abbrev-ref HEAD).Trim()
          git -C $pkg.FullName commit -m "chore(schema): remove legacy schema directory" | Out-Null
          git -C $pkg.FullName push origin $branch | Out-Null
          Write-Host ("[PUSHED] {0} -> {1}" -f $pkg.Name, $branch) -ForegroundColor Cyan
        } else {
          Write-Host ("[NO-CHANGE] {0}" -f $pkg.Name)
        }
      }
    }
    catch {
      Write-Warning ("[FAILED] {0}: {1}" -f $schemaDir, $_.Exception.Message)
      $failed++
    }
  }
}

Write-Host "== SUMMARY =="
Write-Host ("  removed: {0}" -f $removed) -ForegroundColor Green
Write-Host ("  missing: {0}" -f $missing) -ForegroundColor DarkGray
Write-Host ("  failed:  {0}" -f $failed)  -ForegroundColor Red
