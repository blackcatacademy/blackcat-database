param(
  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages'),
  [string]$Message = "chore(schema): split from umbrella",
  [switch]$Tag,                       # optional: tags each package
  [string]$TagName = $(Get-Date -Format "v0.1.0-schemas-{yyyyMMdd-HHmmss}")
)

function Test-RepoChanges([string]$RepoPath) {
  $s = (git -C $RepoPath status --porcelain) 2>$null
  return -not [string]::IsNullOrWhiteSpace($s)
}

$dirs = Get-ChildItem -LiteralPath $PackagesDir -Directory
foreach ($d in $dirs) {
  $schema = Join-Path $d.FullName 'schema'
  if (!(Test-Path $schema)) { continue }
  git -C $d.FullName add schema/*.sql | Out-Null
  if (Test-RepoChanges $d.FullName) {
    $branch = (git -C $d.FullName rev-parse --abbrev-ref HEAD).Trim()
    git -C $d.FullName commit -m $Message | Out-Null
    git -C $d.FullName push origin $branch | Out-Null
    if ($Tag) {
      git -C $d.FullName tag $TagName
      git -C $d.FullName push origin $TagName
    }
    Write-Host "PUSHED  $($d.Name)"
  } else {
    Write-Host "NO-CHG  $($d.Name)"
  }
}

# finally record submodule SHA changes in the umbrella repo
git add packages
git commit -m "chore: bump submodule SHAs (schema split)" 2>$null
git push 2>$null
Write-Host "Umbrella SHAs pushed."
