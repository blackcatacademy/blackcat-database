<#
  Set-PackageVersion.ps1
  Sets a version for one or more packages (writes VERSION file).
  Optional: commit, tag, and push inside each submodule.
#>
[CmdletBinding(DefaultParameterSetName = 'ByTables')]
param(
  [Parameter(ParameterSetName = 'ByTables', Mandatory = $true)]
  [string[]] $Table,

  [Parameter(ParameterSetName = 'All', Mandatory = $true)]
  [switch] $All,

  [Parameter(Mandatory = $true)]
  [string] $Version,

  [Parameter(Mandatory = $true)]
  [string] $MapPath,

  [Parameter(Mandatory = $true)]
  [string] $PackagesDir,

  [switch] $Tag,
  [string] $TagPrefix = 'v',
  [switch] $Push
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $MapPath))     { throw "Map not found: $MapPath" }
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$map = Import-PowerShellDataFile -Path $MapPath

function Get-PackageSlug {
  param([string] $t)
  $t -replace '_','-'
}

# Resolve target tables
$target = @()
if ($PSCmdlet.ParameterSetName -eq 'All') {
  $target = @($map.Tables.Keys | Sort-Object)
} else {
  $target = @($Table)
}

foreach ($t in $target) {
  try {
    $slug = Get-PackageSlug $t
    $pkg  = Join-Path $PackagesDir $slug
    if (!(Test-Path -LiteralPath $pkg)) {
      Write-Warning ("SKIP [{0}] – package not found: {1}" -f $t, $pkg)
      continue
    }

    # write VERSION
    $verPath = Join-Path $pkg 'VERSION'
    Set-Content -Path $verPath -Value $Version -Encoding ASCII
    Write-Host ("WROTE [{0}] -> {1}" -f $t, $verPath)

    # if it's a git repo (submodule), optionally commit/tag/push
    $isGit = Test-Path -LiteralPath (Join-Path $pkg '.git')
    if ($isGit) {
      $msg = "chore(version): {0} -> {1}" -f $t, $Version

      & git -C $pkg add VERSION | Out-Null
      & git -C $pkg commit -m $msg 2>$null | Out-Null

      if ($Tag) {
        $tagName = "{0}@{1}{2}" -f $t, $TagPrefix, $Version
        & git -C $pkg tag -f $tagName | Out-Null
      }
      if ($Push) {
        & git -C $pkg push | Out-Null
        if ($Tag) {
          $tagName = "{0}@{1}{2}" -f $t, $TagPrefix, $Version
          & git -C $pkg push origin $tagName | Out-Null
        }
      }
    } else {
      Write-Verbose ("[{0}] not a git repo (skipping commit/tag/push)" -f $t)
    }
  } catch {
    Write-Warning ("FAILED [{0}]: {1}" -f $t, $_.Exception.Message)
  }
}