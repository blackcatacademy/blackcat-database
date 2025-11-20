param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [Parameter(Mandatory=$true)] [string] $OutDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$index = @()
$pkgs = Get-ChildItem -Path $PackagesDir -Directory
foreach ($p in $pkgs) {
  $docs = Join-Path $p.FullName 'docs\definitions.md'
  if (!(Test-Path $docs)) { continue }
  $html = Get-Content -Raw -Path $docs
  $name = $p.Name
  $dst = Join-Path $OutDir ($name + '.md')
  $html | Out-File -FilePath $dst -NoNewline -Encoding UTF8
  $index += "* [$name]($name.md)"
}
$idxPath = Join-Path $OutDir 'index.md'
("# Schema Explorer`n`n" + ($index -join "`n")) | Out-File -FilePath $idxPath -NoNewline -Encoding UTF8
Write-Host "Wrote $OutDir/index.md"
