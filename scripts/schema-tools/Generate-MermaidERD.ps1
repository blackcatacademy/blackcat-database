param(
  [string] $PackagesDir = 'packages',
  [string] $MapPath = 'scripts/schema/schema-map-postgres.yaml',
  [string] $ViewsLibraryRoot = 'views-library',
  [string] $OutPath = 'docs/ERD.md',
  [ValidateSet('LR','TB','RL','BT')] [string] $Direction = 'TB',
  [string[]] $IncludeTables = @(),
  [string[]] $ExcludeTables = @(),
  [int] $MaxTables = 0,
  [int] $MaxEdges = 0,
  [int] $HubThreshold = 5,
  [switch] $ShowLegend,
  [switch] $ShowStatsTable,
  [string] $ThemeInit = '%%{init: {"theme":"forest","themeVariables":{"primaryColor":"#e5e7eb","primaryBorderColor":"#111827","primaryTextColor":"#0b1021","edgeLabelBackground":"#f8fafc","tertiaryColor":"#cbd5e1","tertiaryTextColor":"#0f172a","lineColor":"#0f172a","nodeBorder":"#111827","textColor":"#0b1021","fontSize":"14px"}} }%%',
  [switch] $ShowConsoleSummary,
  [switch] $Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

# Enable defaults for switches if caller omitted them (keeps PSSA happy).
if (-not $PSBoundParameters.ContainsKey('ShowLegend'))         { $ShowLegend = $true }
if (-not $PSBoundParameters.ContainsKey('ShowStatsTable'))     { $ShowStatsTable = $true }
if (-not $PSBoundParameters.ContainsKey('ShowConsoleSummary')) { $ShowConsoleSummary = $true }

# Resolve repo root (two levels up from scripts/schema-tools) and normalize paths
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..') | Select-Object -ExpandProperty Path
$mapPathResolved = if ([IO.Path]::IsPathRooted($MapPath)) { $MapPath } else { Join-Path $repoRoot $MapPath }
$packagesResolved = if ([IO.Path]::IsPathRooted($PackagesDir)) { $PackagesDir } else { Join-Path $repoRoot $PackagesDir }
$outPathResolved = if ([IO.Path]::IsPathRooted($OutPath)) { $OutPath } else { Join-Path $repoRoot $OutPath }

$viewsResolved = if ([string]::IsNullOrWhiteSpace($ViewsLibraryRoot)) { $null } else { if ([IO.Path]::IsPathRooted($ViewsLibraryRoot)) { $ViewsLibraryRoot } else { Join-Path $repoRoot $ViewsLibraryRoot } }

if (-not (Test-Path -LiteralPath $mapPathResolved)) { throw "Map not found: $mapPathResolved" }
if (-not (Test-Path -LiteralPath $packagesResolved)) { throw "PackagesDir not found: $packagesResolved" }

$map = Get-Content -LiteralPath $mapPathResolved -Raw -Encoding UTF8 | ConvertFrom-Yaml
$engine = ''
if ($mapPathResolved -match 'postgres') { $engine = 'postgres' }
elseif ($mapPathResolved -match 'mysql') { $engine = 'mysql' }

$lines = @(
  '```mermaid',
  $ThemeInit,
  ("%% ERD generated from {0} (engine: {1})" -f $mapPathResolved, $(if ([string]::IsNullOrWhiteSpace($engine)) { 'any' } else { $engine })),
  ("erDiagram"),
  ("  direction {0}" -f $Direction)
)

$tables = @{}
$rels = New-Object System.Collections.Generic.List[string]
$edgeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$nodeClasses = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
$nodeDegree = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::OrdinalIgnoreCase)
$pkgLinkBase = $packagesResolved
$outDir = Split-Path -Parent $outPathResolved
if ($outDir) {
  $pkgLinkBase = [IO.Path]::GetRelativePath($outDir, $packagesResolved)
}
$pkgLinkBase = ($pkgLinkBase -replace '\\','/')
$detailDir = if ($outDir) { Join-Path $outDir 'erd-details' } else { 'erd-details' }

function Get-EngineFiles {
  param(
    [Parameter(Mandatory=$true)][string]$Dir,
    [string]$Engine
  )
  $all = Get-SqlFiles -Dir $Dir
  if ([string]::IsNullOrWhiteSpace($Engine)) { return $all }
  return $all | Where-Object {
    ($_ -match "\.$Engine\.sql$") -or ($_ -notmatch '\.(mysql|postgres)\.sql$')
  }
}

function Repair-TypeString {
  param([string]$Type)
  $t = if ($null -eq $Type) { '' } else { $Type.Trim() }
  $chars  = [char[]]$t
  $opens  = @($chars | Where-Object { $_ -eq '(' }).Count
  $closes = @($chars | Where-Object { $_ -eq ')' }).Count
  if ($opens -gt $closes) { $t += (')' * ($opens - $closes)) }
  return $t
}

function Add-Edge {
  param([string]$From,[string]$To,[string]$Label)
  if ([string]::IsNullOrWhiteSpace($From) -or [string]::IsNullOrWhiteSpace($To)) { return }
  $lab = if ([string]::IsNullOrWhiteSpace($Label)) { 'fk' } else { $Label }
  $edgeLine = "$From }o--|| $To : $lab"
  if ($edgeSet.Add($edgeLine)) {
    $rels.Add($edgeLine) | Out-Null
  }
  # track that these nodes participate in edges
  if (-not $nodeClasses.ContainsKey($From)) { $nodeClasses[$From] = 'linked' }
  if (-not $nodeClasses.ContainsKey($To))   { $nodeClasses[$To]   = 'linked' }
  if (-not $nodeDegree.ContainsKey($From)) { $nodeDegree[$From] = 0 }
  if (-not $nodeDegree.ContainsKey($To))   { $nodeDegree[$To]   = 0 }
  $nodeDegree[$From]++
  $nodeDegree[$To]++
}

function New-DetailErDiagram {
  param(
    [string]$Table,
    [System.Collections.Generic.HashSet[string]]$Neighbors,
    [string[]]$Edges
  )
  $detailLines = @(
    '```mermaid',
    $ThemeInit,
    ("%% Detail ERD for {0} (engine: {1}, neighbors: {2})" -f $Table, $(if ([string]::IsNullOrWhiteSpace($engine)) { 'any' } else { $engine }), $Neighbors.Count),
    'erDiagram',
    ("  direction {0}" -f $Direction)
  )
  $nodeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  $null = $nodeSet.Add($Table)
  foreach ($n in $Neighbors) { $null = $nodeSet.Add($n) }

  foreach ($t in $nodeSet) {
    if (-not $tables.ContainsKey($t)) { continue }
    $detailLines += ("  " + $t + " {")
    foreach ($c in $tables[$t]) {
      $tNorm = Repair-TypeString $c.Type
      $detailLines += ("    {0} {1}" -f $tNorm, $c.Name)
    }
    $detailLines += "  }"
  }

  $edgeFiltered = @()
  foreach ($e in $Edges) {
    if ($e -match '^(?<a>\S+)\s+.\S+\s+(?<b>\S+)\s*:') {
      $a=$matches.a; $b=$matches.b
      if ($nodeSet.Contains($a) -or $nodeSet.Contains($b)) {
        $edgeFiltered += $e
      }
    }
  }
  if ($edgeFiltered.Count -gt 0) {
    $detailLines += ($edgeFiltered | Sort-Object -Unique)
  } else {
    $detailLines += '  %% No edges for this detail view.'
  }
  $detailLines += '```'
  return ($detailLines -join [Environment]::NewLine)
}
$tablesKeys = $map.Tables.Keys | Sort-Object
$truncatedTables = $false
$tablesKeys = @($tablesKeys | Where-Object {
  ($IncludeTables.Count -eq 0 -or $IncludeTables -contains $_) -and
  ($ExcludeTables.Count -eq 0 -or -not ($ExcludeTables -contains $_))
})
if ($MaxTables -gt 0 -and $tablesKeys.Count -gt $MaxTables) {
  $tablesKeys = $tablesKeys[0..($MaxTables-1)]
  $truncatedTables = $true
}

foreach ($tableName in $tablesKeys) {
  $tableDef = $map.Tables[$tableName]
  $pkgSlug = ($tableName -replace '_','-')
  $pkgDir = Join-Path $PackagesDir $pkgSlug
  $schemaDir = Join-Path $pkgDir 'schema'
  $viewDirs = @()
  $viewDirPkg = Join-Path $pkgDir 'views'
  if (Test-Path -LiteralPath $viewDirPkg) { $viewDirs += $viewDirPkg }
  if ($viewsResolved) {
    $viewLib = Join-Path $viewsResolved $pkgSlug
    if (Test-Path -LiteralPath $viewLib) { $viewDirs += $viewLib }
  }

  # Map-defined FKs (always add)
  $mapFks = @()
  if ($tableDef -is [System.Collections.IDictionary]) {
    if ($tableDef.Contains('foreign_keys')) { $mapFks = @($tableDef['foreign_keys']) }
  } elseif ($tableDef.PSObject.Properties.Name -contains 'foreign_keys') {
    $mapFks = @($tableDef.foreign_keys)
  }
  foreach ($fkStmt in $mapFks) {
    if (-not $fkStmt) { continue }
    $label = ''
    $stmt = "$fkStmt"
    if ($stmt -match '(?i)CONSTRAINT\s+(?<name>\S+)') { $label = $matches.name }
    if ($stmt -match '(?i)REFERENCES\s+(?<rt>[^\s\(\)]+)') {
      Add-Edge -From $tableName -To $matches.rt -Label $label
    }
  }

  if (-not (Test-Path -LiteralPath $schemaDir) -and $viewDirs.Count -eq 0) { continue }

  $schemaSql = @()
  if (Test-Path -LiteralPath $schemaDir) {
    $schemaSql = Get-FileText -Files (Get-EngineFiles -Dir $schemaDir -Engine $engine)
  }
  $viewSql = @()
  foreach ($vd in $viewDirs) {
    $viewSql += Get-FileText -Files (Get-EngineFiles -Dir $vd -Engine $engine)
  }

  $sql = Format-SqlText -Sql (($schemaSql + $viewSql) -join "`n")
  $tblBlocks = Get-TableBlocks -Sql $sql
  $tbl = $tblBlocks | Where-Object { $_.Table -eq $tableName } | Select-Object -First 1
  if (-not $tbl) { continue }

  $cols = @(Get-ColumnMetadata -Body $tbl.Body)
  $tables[$tableName] = $cols

  $fks  = @(Get-ForeignKeyMetadata -Sql $sql -Table $tableName)
  foreach ($fk in $fks) {
    $ref = $fk.References
    if (-not [string]::IsNullOrWhiteSpace($ref)) {
      $refTable = ($ref -split '\(')[0]
      Add-Edge -From $tableName -To $refTable.Trim() -Label $fk.Name
    }
  }
}

$tableListOrdered = $tables.Keys | Sort-Object
foreach ($t in $tableListOrdered) {
  $lines += ("  " + $t + " {")
  foreach ($c in $tables[$t]) {
    $tNorm = Repair-TypeString $c.Type
    $lines += ("    {0} {1}" -f $tNorm, $c.Name)
  }
  $lines += "  }"
  if (-not $nodeClasses.ContainsKey($t)) { $nodeClasses[$t] = 'orphan' }
}
$edgesSorted = $rels | Sort-Object -Unique
$truncatedEdges = $false
if ($MaxEdges -gt 0 -and $edgesSorted.Count -gt $MaxEdges) {
  $edgesSorted = $edgesSorted[0..($MaxEdges-1)]
  $truncatedEdges = $true
}
$lines += $(if ($edgesSorted.Count -gt 0) { $edgesSorted } else { @('  %% No FK edges detected – verify foreign_keys in map/DDL.') })
$lines += '  %% styling'
$lines += '  classDef linked fill:#0b1021,stroke:#38bdf8,stroke-width:2px,color:#e2e8f0'
$lines += '  classDef orphan fill:#111827,stroke:#94a3b8,stroke-width:1px,color:#cbd5e1'
$lines += '  classDef hub fill:#0f172a,stroke:#f59e0b,stroke-width:3px,color:#fef3c7'
foreach ($kv in $nodeDegree.GetEnumerator()) {
  if ($kv.Value -ge $HubThreshold) { $nodeClasses[$kv.Key] = 'hub' }
}
foreach ($kv in $nodeClasses.GetEnumerator()) {
  $lines += ("  class {0} {1}" -f $kv.Key, $kv.Value)
}
$summary = @{
  Tables  = $tableListOrdered.Count
  Edges   = $edgesSorted.Count
  Linked  = ($nodeClasses.Values | Where-Object { $_ -eq 'linked' }).Count
  Orphans = ($nodeClasses.Values | Where-Object { $_ -eq 'orphan' }).Count
  Hubs    = ($nodeClasses.Values | Where-Object { $_ -eq 'hub' }).Count
  TruncTables = $truncatedTables
  TruncEdges  = $truncatedEdges
}
$ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
$lines += ("  %% Summary: tables={0}, edges={1}, linked={2}, orphans={3}, hubs={4}, generated={5}" -f $summary.Tables,$summary.Edges,$summary.Linked,$summary.Orphans,$summary.Hubs,$ts)
$lines += '```'

if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$content = $lines -join [Environment]::NewLine
$md = New-Object System.Collections.Generic.List[string]
$md.Add($content) | Out-Null
$md.Add("") | Out-Null
$md.Add("> Legend: linked = tables with FK edges; orphan = no FK in/out; hub = degree >= $HubThreshold.") | Out-Null
$md.Add("") | Out-Null
$md.Add("| Metric | Value |") | Out-Null
$md.Add("| --- | ---: |") | Out-Null
$md.Add(("| Tables | {0} |" -f $summary.Tables)) | Out-Null
$md.Add(("| Edges | {0} |" -f $summary.Edges)) | Out-Null
$md.Add(("| Linked | {0} |" -f $summary.Linked)) | Out-Null
$md.Add(("| Orphans | {0} |" -f $summary.Orphans)) | Out-Null
$md.Add(("| Hubs (≥{0}) | {1} |" -f $HubThreshold, $summary.Hubs)) | Out-Null
$md.Add(("| Engine | {0} |" -f $(if ([string]::IsNullOrWhiteSpace($engine)) { 'any' } else { $engine }))) | Out-Null
$md.Add(("| Generated | {0} |" -f $ts)) | Out-Null
if ($MaxTables -gt 0) { $md.Add(("| Truncated tables (max={0}) | {1} |" -f $MaxTables, $summary.TruncTables)) | Out-Null }
if ($MaxEdges  -gt 0) { $md.Add(("| Truncated edges (max={0}) | {1} |" -f $MaxEdges,  $summary.TruncEdges)) | Out-Null }
$md.Add(("| Direction | {0} |" -f $Direction)) | Out-Null
# Quick navigation to hubs (all with degree > 0) and per-table detail ERDs (neighbors limited to 10)
$hubList = @(
  $nodeDegree.GetEnumerator() |
    Where-Object { $_.Value -gt 0 } |
    Sort-Object -Property Value, Key -Descending
)
$detailLinks = @()
if ($hubList.Count -gt 0) {
  if ($detailDir) { New-Item -ItemType Directory -Force -Path $detailDir | Out-Null }
  $md.Add("") | Out-Null
  $md.Add("**Quick navigation (hubs)**") | Out-Null
  $md.Add("| Table | Degree | Package |") | Out-Null
  $md.Add("| --- | ---: | --- |") | Out-Null
  foreach ($hub in $hubList) {
    $pkgSlug = ($hub.Key -replace '_','-')
    $pkgLink = ("{0}/{1}" -f $pkgLinkBase, $pkgSlug) -replace '\\','/'
    $detailFileName = "ERD-{0}.md" -f $hub.Key
    $detailPath = if ($detailDir) { Join-Path $detailDir $detailFileName } else { $detailFileName }
    $neighbors = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($edge in $edgesSorted) {
      if ($edge -match '^(?<a>\S+)\s+.\S+\s+(?<b>\S+)\s*:') {
        $a=$matches.a; $b=$matches.b
        if ($a -eq $hub.Key -and $b -ne $hub.Key) { $null = $neighbors.Add($b) }
        elseif ($b -eq $hub.Key -and $a -ne $hub.Key) { $null = $neighbors.Add($a) }
      }
    }
    # limit neighbors to 10 for readability
    $neighborsLimited = @($neighbors | Sort-Object -CaseSensitive | Select-Object -First 10)
    $detailContent = New-DetailErDiagram -Table $hub.Key -Neighbors $neighborsLimited -Edges $edgesSorted
    Set-Content -LiteralPath $detailPath -Value $detailContent -Encoding UTF8
    $detailRel = if ($outDir) { [IO.Path]::GetRelativePath($outDir, $detailPath) } else { $detailFileName }
    $detailRel = ($detailRel -replace '\\','/')
    $md.Add(("| [`{0}`]({1}) | {2} | [{3}]({4}) |" -f $hub.Key, $detailRel, $hub.Value, $pkgSlug, $pkgLink)) | Out-Null
  }
}
$content = $md -join [Environment]::NewLine
Set-Content -LiteralPath $outPathResolved -Value $content -Encoding UTF8
if ($ShowConsoleSummary) {
  Write-Host ("ERD written to {0} (tables={1}, edges={2}, hubs={3}, generated={4})" -f $OutPath,$summary.Tables,$summary.Edges,$summary.Hubs,$ts)
  if ($summary.TruncTables -or $summary.TruncEdges) {
    Write-Host ("  Note: truncated tables={0} (max={1}), truncated edges={2} (max={3})" -f $summary.TruncTables,$MaxTables,$summary.TruncEdges,$MaxEdges)
  }
  if ($summary.Edges -eq 0) {
    Write-Host "  Warning: no FK edges detected; check foreign_keys in map and DDL parsing."
  }
}
