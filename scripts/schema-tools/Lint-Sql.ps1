param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [Parameter(Mandatory=$true)] [string] $MapPath,
[string] $RulesPath = "$PSScriptRoot/SqlLintRules.yaml"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

function Import-YamlWithFallback {
  param([Parameter(Mandatory)][string]$Path)
  $null = Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
  $cfy = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
  if (-not $cfy) {
    Write-Host "ConvertFrom-Yaml missing – attempting to install powershell-yaml from PSGallery..." -ForegroundColor Yellow
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default }
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
      Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      Import-Module powershell-yaml -ErrorAction Stop
      $cfy = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
    } catch {
      throw "ConvertFrom-Yaml not available and auto-install failed: $($_.Exception.Message)"
    }
  }
  if (-not $cfy) { throw "ConvertFrom-Yaml still not available." }
  return Get-Content -LiteralPath $Path -Raw | & $cfy
}

function Import-MapFile {
  param([Parameter(Mandatory)][string]$Path)
  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -eq '.yaml' -or $ext -eq '.yml') {
    return Import-YamlWithFallback -Path $Path
  }
  return Import-PowerShellDataFile -Path $Path
}

function Get-PropValue {
  param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string]$Name)
  if ($Object -is [hashtable]) {
    return $Object[$Name]
  }
  $prop = $Object.PSObject.Properties.Match($Name)
  if ($prop.Count -gt 0) { return $prop[0].Value }
  return $null
}

function Test-Prop {
  param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string]$Name)
  if ($Object -is [hashtable]) { return $Object.ContainsKey($Name) }
  return $Object.PSObject.Properties.Match($Name).Count -gt 0
}

$map = Import-MapFile -Path $MapPath
$rules = Import-MapFile -Path $RulesPath

$failCount = 0
$warnCount = 0
$items = @()

function Test-IndexForColumns {
  param([object[]]$Indexes, [string[]]$Cols)
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if (@(Compare-Object -ReferenceObject $Cols -DifferenceObject $ixCols -IncludeEqual:$false -ExcludeDifferent:$true).Count -eq 0) {
      return $true
    }
  }
  # Fallback: any index whose prefix matches FK columns order
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if ($ixCols.Count -ge $Cols.Count -and @($ixCols[0..($Cols.Count-1)] -ceq $Cols).Count -eq $Cols.Count) {
      return $true
    }
  }
  return $false
}

function Resolve-PackageDir {
  param([string]$PackagesDir, [string]$TableName, $Spec)
  $candidates = @()
  if ($Spec -and (Test-Prop $Spec 'Package')) { $candidates += (Get-PropValue $Spec 'Package') }
  if ($Spec -and (Test-Prop $Spec 'PackageDir')) { $candidates += (Get-PropValue $Spec 'PackageDir') }
  $candidates += @(
    ($TableName -replace '_','-')
    $TableName
    (($TableName -replace '_','-') -replace '-','_')
  )
  $candidates = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
  foreach ($cand in $candidates) {
    $dir = Join-Path $PackagesDir $cand
    if (Test-Path -LiteralPath $dir) { return (Resolve-Path -LiteralPath $dir).Path }
  }
  return $null
}

$entries = @()
if (Test-Prop $map 'Tables') {
  $tablesObj = Get-PropValue $map 'Tables'
  $tableKeys = ($tablesObj -is [hashtable]) ? $tablesObj.Keys : $tablesObj.PSObject.Properties.Name
  foreach ($t in $tableKeys) {
    $entries += [pscustomobject]@{
      Table = $t
      Spec  = ($tablesObj -is [hashtable]) ? $tablesObj[$t] : (Get-PropValue $tablesObj $t)
    }
  }
} else {
  $keys = ($map -is [hashtable]) ? $map.Keys : $map.PSObject.Properties.Name
  foreach ($k in $keys) {
    $entries += [pscustomobject]@{
      Table = $k
      Spec  = ($map -is [hashtable]) ? $map[$k] : (Get-PropValue $map $k)
    }
  }
}

foreach ($entry in $entries) {
  $table = [string]$entry.Table
  $spec  = $entry.Spec
  $pkgDir = Resolve-PackageDir -PackagesDir $PackagesDir -TableName $table -Spec $spec
  if (-not $pkgDir) { Write-Warning "Package directory not found for table '$table' under $PackagesDir"; continue }

  $schema = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'schema'))
  $views  = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'views'))
  $allSql = Format-SqlText -Sql ($schema + "`n" + $views)

  $tblocks = Get-TableBlocks -Sql $allSql
  $tbl = $tblocks | Where-Object { $_.Table -eq $m.Table } | Select-Object -First 1
  if (-not $tbl) { continue }
  $cols = Get-ColumnMetadata -Body $tbl.Body
  $pk   = Get-PrimaryKeyInfo -Body $tbl.Body
  $idx  = Get-IndexMetadata -Sql $allSql -Table $m.Table
  $fks  = Get-ForeignKeyMetadata -Sql $allSql -Table $m.Table
  $viewsList = Get-ViewNames -Sql $allSql

  # Rule: PK required
  if ($rules.RequirePrimaryKey -and -not $pk) {
    $failCount++
    $items += "FAIL [$([System.IO.Path]::GetFileName($pkgDir))]: table `$table` has no PRIMARY KEY"
  }

  # Rule: Each FK must have an index on referencing columns
  if ($rules.RequireFkIndex -and $fks.Count -gt 0) {
    foreach ($fk in $fks) {
      $refCols = ($fk.Columns -split ',\s*')
      if (-not (Test-IndexForColumns -Indexes $idx -Cols $refCols)) {
        $failCount++
        $items += "FAIL [$([System.IO.Path]::GetFileName($pkgDir))]: FK `$($fk.Name)` missing index on ($($fk.Columns))"
      }
    }
  }

  # View directives (only check when views exist; SQL dialect inference is outside scope)
  if ($rules.RequireViewDirectives -and $viewsList.Count -gt 0) {
    # If any view file exists under views/, require tokens ALGORITHM= and SQL SECURITY
    $rawViews = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'views'))
    if ($rawViews -notmatch 'ALGORITHM\s*=' -or $rawViews -notmatch 'SQL\s+SECURITY\s+(DEFINER|INVOKER)') {
      $warnCount++
      $items += "WARN [$([System.IO.Path]::GetFileName($pkgDir))]: views/*.sql missing ALGORITHM and/or SQL SECURITY directives (required on MySQL/MariaDB)"
    }
  }

  # Time columns recommendation
  $tc = $rules.TimeColumns
  $hasTime = $false
  foreach ($c in $cols) {
    if ($tc -contains ($c.Name.ToLower())) { $hasTime = $true; break }
  }
  if (-not $hasTime) {
    $warnCount++
    $items += "WARN [$([System.IO.Path]::GetFileName($pkgDir))]: consider adding created_at/updated_at timestamps"
  }
}

if ($items.Count -gt 0) { $items | ForEach-Object { Write-Host $_ } }
Write-Host "----"
Write-Host "Summary: FAIL=$failCount, WARN=$warnCount"
if ($failCount -gt 0) { exit 1 } else { exit 0 }
