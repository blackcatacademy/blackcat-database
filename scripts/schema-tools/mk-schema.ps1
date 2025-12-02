param(
  # Input directory containing all *.yaml files
  [string]$InDir  = (Join-Path $PSScriptRoot "schema"),
  # Output directory for the generated *.sql files
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "schema"),

  [ValidateSet('mysql','postgres')]
  [string[]]$Engine = @('mysql','postgres'),

  [switch]$SeedInTransaction,
  [switch]$Force
)

$scriptRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $scriptRoot -Parent
$repoSchemaDir = Join-Path $scriptRoot "schema"
if (-not $PSBoundParameters.ContainsKey('OutDir')) {
  $OutDir = Join-Path $repoRoot 'schema'
}
if (-not (Test-Path -LiteralPath $InDir)) {
  if (-not $PSBoundParameters.ContainsKey('InDir') -and (Test-Path -LiteralPath $repoSchemaDir)) {
    Write-Host "Input directory '$InDir' not found. Falling back to '$repoSchemaDir'." -ForegroundColor Yellow
    $InDir = $repoSchemaDir
  } else {
    throw "Input directory not found: '$InDir'"
  }
}

# ---------- helpers ----------
function Import-Map {
  param([string]$Path, [string]$Label)
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "  (skip) $Label — nenalezeno: $Path" -ForegroundColor Yellow
    return $null
  }
  $null = Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
  $cfy = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
  if (-not $cfy) {
    throw "ConvertFrom-Yaml not available; install powershell-yaml or use PowerShell 7+."
  }
  ConvertFrom-Yaml (Get-Content -LiteralPath $Path -Raw)
}

function Add-SqlTerminator {
  param([string]$Sql)
  if ([string]::IsNullOrWhiteSpace($Sql)) { return "" }
  $t = $Sql.Trim()
  if ($t -match ';$') { return "$t`n" } else { return "$t;`n" }
}

function Test-OutputWritable {
  param([string[]]$Path, [switch]$Force)
  foreach ($p in $Path) {
    if ((Test-Path -LiteralPath $p) -and -not $Force) {
      throw "Output file exists: '$p'. Use -Force to overwrite."
    }
  }
}

# ---------- generators ----------
function Write-TablesIndexesFks {
  param(
    [hashtable]$Map,
    [string]$TablesPath,
    [string]$IndexesPath,
    [string]$FkPath
  )
  if (-not $Map) { return }

  $tablesSb = New-Object System.Text.StringBuilder
  $idxSb    = New-Object System.Text.StringBuilder
  $fkSb     = New-Object System.Text.StringBuilder

  $tables = $Map.Tables.GetEnumerator() | Sort-Object Key
  foreach ($t in $tables) {
    $name = $t.Key
    $spec = $t.Value

    [void]$tablesSb.AppendLine("-- === $name ===")
    [void]$tablesSb.Append( (Add-SqlTerminator $spec.create) )
    [void]$tablesSb.AppendLine()

    if ($spec.indexes) {
      [void]$idxSb.AppendLine("-- === $name ===")
      foreach ($ix in $spec.indexes) { [void]$idxSb.Append( (Add-SqlTerminator $ix) ) }
      [void]$idxSb.AppendLine()
    }

    if ($spec.foreign_keys) {
      [void]$fkSb.AppendLine("-- === $name ===")
      foreach ($fk in $spec.foreign_keys) { [void]$fkSb.Append( (Add-SqlTerminator $fk) ) }
      [void]$fkSb.AppendLine()
    }
  }

  $tablesSb.ToString() | Out-File -FilePath $TablesPath -Encoding utf8 -Force
  $idxSb.ToString()    | Out-File -FilePath $IndexesPath -Encoding utf8 -Force
  $fkSb.ToString()     | Out-File -FilePath $FkPath     -Encoding utf8 -Force

  Write-Host "  $TablesPath"
  Write-Host "  $IndexesPath"
  Write-Host "  $FkPath"
}

function Write-Views {
  param(
    [hashtable]$ViewsMap,
    [string]$ViewsPath
  )
  if (-not $ViewsMap) { return }

  $sb = New-Object System.Text.StringBuilder
  $views = $ViewsMap.Views.GetEnumerator() | Sort-Object Key
  foreach ($v in $views) {
    [void]$sb.AppendLine("-- === $($v.Key) ===")
    [void]$sb.Append( (Add-SqlTerminator $v.Value.create) )
    [void]$sb.AppendLine()
  }
  $sb.ToString() | Out-File -FilePath $ViewsPath -Encoding utf8 -Force
  Write-Host "  $ViewsPath"
}
function Get-SeedRoot {
  param([hashtable]$SeedMap)
  if (-not $SeedMap) { return $null }

  $dict = $SeedMap -as [System.Collections.IDictionary]
  if ($null -eq $dict) { return $null }

  foreach ($key in @('Seeds','Seed','Tables','Data')) {
    if ($dict.Contains($key)) {
      $root = $dict[$key]
      $rootDict = $root -as [System.Collections.IDictionary]
      if ($null -ne $rootDict) { return $rootDict }
    }
  }

  # Heuristic: all values are IDictionary => treat it as the table root
  $allDict = $true
  foreach ($k in $dict.Keys) {
    if ($dict[$k] -isnot [System.Collections.IDictionary]) { $allDict = $false; break }
  }
  if ($allDict) { return $dict }

  return $null
}

function Get-SeedStatements {
  param([object]$Spec)

  # 1) Simple string
  if ($Spec -is [string]) { return @([string]$Spec) }

  # 2) Collection of strings
  if ($Spec -is [System.Collections.IEnumerable] -and -not ($Spec -is [System.Collections.IDictionary])) {
    $out = @()
    foreach ($s in $Spec) { if ($s) { $out += [string]$s } }
    return $out
  }

  # 3) Mapy (Hashtable/OrderedDictionary/IDictionary)
  $dict = $Spec -as [System.Collections.IDictionary]
  if ($null -ne $dict) {
    $out = @()
    foreach ($k in @('seed','seeds','insert','inserts','statement','statements','data','sql')) {
      if ($dict.Contains($k) -and $dict[$k]) {
        $v = $dict[$k]
        if ($v -is [string]) { $out += $v }
        elseif ($v -is [System.Collections.IEnumerable]) {
          foreach ($s in $v) { if ($s) { $out += [string]$s } }
        }
      }
    }
    return $out
  }

  return @()
}

function Write-Seed {
  param(
    [hashtable]$SeedMap,
    [string]$SeedPath,
    [ValidateSet('mysql','postgres')] [string]$Engine,
    [switch]$InTx
  )
  if (-not $SeedMap) { return }

  $sb = New-Object System.Text.StringBuilder
  if ($InTx) {
    [void]$sb.AppendLine( ($Engine -eq 'mysql') ? 'START TRANSACTION;' : 'BEGIN;' )
    [void]$sb.AppendLine()
  }

  $root = Get-SeedRoot -SeedMap $SeedMap
  if (-not $root) {
    $d = $SeedMap -as [System.Collections.IDictionary]
    $keyList = if ($null -ne $d) { ($d.Keys -join ', ') } else { ($SeedMap.PSObject.Properties.Name -join ', ') }
    Write-Host "  (skip) Seed - could not determine the root (Seeds/Tables). Keys present: $keyList" -ForegroundColor Yellow
    return
  }

  $tables = $root.GetEnumerator() | Sort-Object Key
  foreach ($t in $tables) {
    $stmts = @(Get-SeedStatements -Spec $t.Value)
    if ($stmts.Count -eq 0) { continue }
    [void]$sb.AppendLine("-- === $($t.Key) ===")
    foreach ($s in $stmts) { [void]$sb.Append( (Add-SqlTerminator $s) ) }
    [void]$sb.AppendLine()
  }

  if ($InTx) { [void]$sb.AppendLine('COMMIT;') }

  $sb.ToString() | Out-File -FilePath $SeedPath -Encoding utf8 -Force
  Write-Host "  $SeedPath"
}

# ---------- konfigurace cest ----------
$In = @{
  mysql = @{
    Map   = Join-Path $InDir "schema-map-mysql.yaml"
    Views = Join-Path $InDir "schema-views-mysql.yaml"
    FeatureViews = Join-Path $InDir "schema-views-feature-mysql.yaml"
    Seed  = Join-Path $InDir "schema-seed-mysql.yaml"
  }
  postgres = @{
    Map   = Join-Path $InDir "schema-map-postgres.yaml"
    Views = Join-Path $InDir "schema-views-postgres.yaml"
    FeatureViews = Join-Path $InDir "schema-views-feature-postgres.yaml"
    Seed  = Join-Path $InDir "schema-seed-postgres.yaml"
  }
}

$Out = @{
  mysql = @{
    Tables      = Join-Path $OutDir "001_table.mysql.sql"
    Indexes     = Join-Path $OutDir "020_indexes.mysql.sql"
    ForeignKeys = Join-Path $OutDir "030_foreign_keys.mysql.sql"
    Views       = Join-Path $OutDir "040_views.mysql.sql"
    Seed        = Join-Path $OutDir "050_seed.mysql.sql"
  }
  postgres = @{
    Tables      = Join-Path $OutDir "001_table.postgres.sql"
    Indexes     = Join-Path $OutDir "020_indexes.postgres.sql"
    ForeignKeys = Join-Path $OutDir "030_foreign_keys.postgres.sql"
    Views       = Join-Path $OutDir "040_views.postgres.sql"
    Seed        = Join-Path $OutDir "050_seed.postgres.sql"
  }
}

# ---------- main ----------
$null = New-Item -ItemType Directory -Force -Path $OutDir
Write-Host "Input:  $InDir"
Write-Host "Output: $OutDir"

foreach ($eng in $Engine) {
  Write-Host "== Building $eng ==" -ForegroundColor Cyan

  $inPaths   = $In[$eng]
  $outPaths  = $Out[$eng]
  Test-OutputWritable -Path $outPaths.Values -Force:$Force

  $map   = Import-Map -Path $inPaths.Map   -Label "Tables/Indexes/FKs ($eng)"
  $views = Import-Map -Path $inPaths.Views -Label "Views ($eng)"
  $viewsFeat = Import-Map -Path $inPaths.FeatureViews -Label "Feature Views ($eng)"
  $seed  = Import-Map -Path $inPaths.Seed  -Label "Seed ($eng)"

  if ($viewsFeat -and $viewsFeat.Views) {
    if (-not $views) { $views = @{ Views = @{} } }
    if (-not $views.Views) { $views['Views'] = @{} }
    foreach ($kv in $viewsFeat.Views.GetEnumerator()) { $views.Views[$kv.Key] = $kv.Value }
  }

  if ($map)   { Write-TablesIndexesFks -Map $map   -TablesPath $outPaths.Tables -IndexesPath $outPaths.Indexes -FkPath $outPaths.ForeignKeys }
  if ($views) { Write-Views             -ViewsMap $views -ViewsPath $outPaths.Views }
  if ($seed)  { Write-Seed              -SeedMap $seed  -SeedPath  $outPaths.Seed -Engine $eng -InTx:$SeedInTransaction }
}
