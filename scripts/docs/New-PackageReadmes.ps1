<# 
  New-PackageReadmes.ps1
  Regenerates README.md for each package based on the schema map (YAML).
  - Defaults: MapPath=scripts/schema/schema-map-postgres.yaml, PackagesDir=packages
  - Links to Docs/Changelog if present
  - Lists available schema files with engine detection (mysql/postgres)
  - Uses a stable map stamp (sha1 of the map content)
  - Optional RepoUrl to emit GitHub-friendly links
#>
[CmdletBinding()]
param(
  [string] $MapPath = 'scripts/schema/schema-map-postgres.yaml',
  [string] $PackagesDir = 'packages',
  # Default to the public GitHub repo so links render correctly in generated markdown
  [string] $RepoUrl = 'https://github.com/blackcatacademy/blackcat-database/blob/main',
  # Root used to build relative links; default to repo root
  [string] $MapRoot = '.',
  [string] $PackagesRoot,
  [switch] $Force,
  [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RelativePathLegacy {
  param(
    [string]$BasePath,
    [string]$TargetPath
  )

  $baseResolved   = (Resolve-Path -LiteralPath $BasePath).Path
  $targetResolved = (Resolve-Path -LiteralPath $TargetPath).Path

  $baseUri   = New-Object System.Uri($baseResolved + [IO.Path]::DirectorySeparatorChar)
  $targetUri = New-Object System.Uri($targetResolved)
  $rel = $baseUri.MakeRelativeUri($targetUri).ToString().Replace('/', [IO.Path]::DirectorySeparatorChar)
  return $rel
}

function Get-SafeCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    if ($Value -is [string]) {
        if ([string]::IsNullOrEmpty($Value)) { return 0 } else { return 1 }
    }
    if ($Value -is [System.Collections.IEnumerable]) { return (@($Value) | Measure-Object).Count }
    return 1
}

# Resolve repo roots up front (default to repo root = two levels up from this script)
$scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if (-not $MapRoot) {
    # Two levels up from scripts/docs to repo root
    $MapRoot = (Get-Item -LiteralPath $scriptRoot).Parent.Parent.FullName
}
if (-not $PackagesRoot) { $PackagesRoot = (Join-Path $MapRoot $PackagesDir) }

function Import-Map {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Map not found: $Path" }
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -notin @('.yaml','.yml')) { throw "Unsupported map format: $ext (expected .yaml/.yml)" }
  if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    try {
      Install-Module -Name powershell-yaml -Scope CurrentUser -Force -Repository PSGallery -AllowClobber -ErrorAction Stop | Out-Null
      Import-Module -Name powershell-yaml -ErrorAction Stop
    } catch {
      throw "ConvertFrom-Yaml is required to read '$Path' (install PowerShell 7+ or powershell-yaml). Failed to auto-install: $($_.Exception.Message)"
    }
  }
  Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml
}

function Get-MapStamp {
  param([string]$MapPathResolved)
  try {
    $sha = (& git hash-object -t blob $MapPathResolved 2>$null).Trim()
    if ($sha) { return "map@sha1:$sha" }
    $sha = (& git log -1 --format=%H -- $MapPathResolved 2>$null).Trim()
    if ($sha) { return "map@sha1:$sha" }
  } catch {}
  $mt = (Get-Item -LiteralPath $MapPathResolved).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z'
  "map@mtime:$mt"
}

function ConvertTo-Slug {
  param([string]$TableName)
  $TableName -replace '_','-'
}

function ConvertTo-TitleCase {
  param([string]$Name)
  $ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  $ti.ToTitleCase(($Name -replace '[_-]+',' ').ToLowerInvariant())
}

function Get-LinkForPath {
  param([string]$Path, [string]$RepoUrl, [string]$Root)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $rel = Get-RelativePathLegacy -BasePath $Root -TargetPath (Resolve-Path -LiteralPath $Path)
  $rel = $rel -replace '\\','/'
  if ($RepoUrl) { return ($RepoUrl.TrimEnd('/') + '/' + $rel) }
  $rel
}

function Get-EngineFromFileName {
  param([string]$FileName)
  $n = $FileName.ToLowerInvariant()
  if ($n -match 'postgres') { return 'postgres' }
  if ($n -match 'mysql')    { return 'mysql' }
  if ($n -match 'mariadb')  { return 'mysql' }
  ''
}

function ConvertTo-NormalizedType {
  param([string]$Type)
  if (-not $Type) { return '' }
  $t = $Type.Trim().ToLowerInvariant()
  $t = $t -replace '\s+',''
  switch -regex ($t) {
    '^tinyint\(1\)$'        { return 'bool' }
    '^(bool|boolean)$'      { return 'bool' }
    '^(int|integer)$'       { return 'int' }
    '^bigint$'              { return 'bigint' }
    '^smallint$'            { return 'smallint' }
    '^(text|mediumtext|longtext)$' { return 'text' }
    '^varchar.*$'           { return 'varchar' }
    '^(json|jsonb)$'        { return 'jsonb' }
    '^bytea$'               { return 'bytea' }
    '^varbinary.*$'         { return 'bytea' }
    '^timestamp.*with.*time' { return 'timestamptz' }
    '^timestamptz'          { return 'timestamptz' }
    '^timestamp'            { return 'timestamp' }
    '^interval'             { return 'interval' }
    default                 { return $t }
  }
}

function ConvertTo-NormalizedDefault {
  param([string]$Default)
  if ($null -eq $Default) { return '' }
  $d = $Default.Trim()
  $d = $d -replace "::jsonb$",''
  $d = $d.Trim(@("'", '"'))
  switch ($d.ToLowerInvariant()) {
    '0'      { return 'false' }
    '1'      { return 'true' }
    'false'  { return 'false' }
    'true'   { return 'true' }
    default  { return $d }
  }
}

function ConvertFrom-ColumnDiffLine {
  param([string]$Line)
  if (-not $Line) { return $null }
  $payload = ($Line -replace '^-+\s*Column differences:\s*','').Trim()
  if (-not $payload) { return $Line }
  $parts = $payload -split '\s*\|\s*'
  $keep = @()
  foreach ($part in $parts) {
    if (-not $part) { continue }
    $m = [regex]::Match($part, '^(?<col>[^=]+)=>\s*mysql:type=(?<mt>[^;]*);null=(?<mn>[^;]*);def=(?<md>[^;]*);\s*postgres:type=(?<pt>[^;]*);null=(?<pn>[^;]*);def=(?<pd>.*)$')
    if (-not $m.Success) { $keep += $part; continue }
    $mt = ConvertTo-NormalizedType $m.Groups['mt'].Value
    $pt = ConvertTo-NormalizedType $m.Groups['pt'].Value
    $md = ConvertTo-NormalizedDefault $m.Groups['md'].Value
    $pd = ConvertTo-NormalizedDefault $m.Groups['pd'].Value
    $mn = $m.Groups['mn'].Value
    $pn = $m.Groups['pn'].Value
    $isSame = ($mt -eq $pt) -and ($md -eq $pd) -and ($mn -eq $pn)
    if (-not $isSame) { $keep += $part }
  }
  if ((Get-SafeCount $keep) -eq 0) { return $null }
  return "- Column differences: " + ($keep -join ' | ')
}

function Get-SectionRowCount {
  param([string[]]$Lines, [string]$Header)
  $linesArr = ConvertTo-Array $Lines
  if ($linesArr.Length -eq 0) { return 0 }
  $idx = [Array]::IndexOf($linesArr, $Header)
  if ($idx -lt 0) { return 0 }
  $count = 0
  for ($i = $idx + 1; $i -lt $linesArr.Length; $i++) {
    $ln = $linesArr[$i]
    if ($ln -match '^## ') { break }
    if ($ln.Trim().Length -eq 0) { if ($count -gt 0) { break } else { continue } }
    if ($ln -match '^\|') { $count++ }
  }
  return $count
}

# Helper to ensure collection semantics
function ConvertTo-Array {
  param($InputObject)
  if ($null -eq $InputObject) { return @() }
  if ($InputObject -is [System.Array]) { return $InputObject }
  if ($InputObject -is [string]) { return @($InputObject) }
  if ($InputObject -is [System.Collections.IEnumerable]) {
    $tmp = @()
    foreach ($item in $InputObject) { $tmp += $item }
    return $tmp
  }
  return @($InputObject)
}

function Get-ColumnObjects {
  param([string[]]$DefsLines)

  $defsArr = ConvertTo-Array $DefsLines
  $cols = New-Object 'System.Collections.Generic.List[pscustomobject]'
  $idx = $defsArr.IndexOf('## Columns')
  if ($idx -lt 0) { return $cols.ToArray() }

  for ($i = $idx + 1; $i -lt $defsArr.Length; $i++) {
    $line = $defsArr[$i].Trim()
    if ($line -match '^## ') { break }
    if ($line -notmatch '^\|') { continue }
    if ($line -match '^\|\s*---') { continue }
    if ($line -match '^\|\s*Column\s*\|') { continue }

    $m = [regex]::Match($line, '^\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|')
    if (-not $m.Success) { continue }
    $cols.Add([pscustomobject]@{
      Name        = $m.Groups[1].Value.Trim()
      Type        = $m.Groups[2].Value.Trim()
      Null        = $m.Groups[3].Value.Trim()
      Default     = $m.Groups[4].Value.Trim()
      Description = $m.Groups[5].Value.Trim()
    }) | Out-Null
  }
  return $cols.ToArray()
}

function Get-PiiSignals {
  param([pscustomobject[]]$Columns)

  $signals = New-Object 'System.Collections.Generic.List[string]'
  $patterns = @(
    'email','phone','tel','ssn','tax','vat','passport','license',
    'token','secret','password','pass','key','card','credit','iban'
  )
  foreach ($c in $Columns) {
    $text = ($c.Name + ' ' + $c.Description) -replace '[^a-zA-Z0-9 ]',' '
    $text = $text.ToLowerInvariant()
    foreach ($p in $patterns) {
      if ($text -match "\b$p\b") {
        $signals.Add("$($c.Name) ($p)") | Out-Null
        break
      }
    }
  }
  return ($signals | Select-Object -Unique)
}

function Get-ConstraintSnippets {
  param([pscustomobject[]]$Columns, [int]$Max = 5)

  $snips = New-Object 'System.Collections.Generic.List[string]'
  foreach ($c in ($Columns | Sort-Object -Stable -Property @{Expression = { $_.Name.ToLowerInvariant() }})) {
    $desc = $c.Description
    $hasEnum = ($desc -match '(?i)\benum\b')
    $hasCheck = ($desc -match '(?i)\bcheck\b')
    $hasDefault = -not [string]::IsNullOrWhiteSpace($c.Default)
    if ($hasEnum -or $hasCheck -or $hasDefault) {
      $parts = @()
      if ($hasDefault) { $parts += "default=$($c.Default)" }
      if ($hasEnum) { $parts += "enum" }
      if ($hasCheck) { $parts += "check" }
      $snips.Add(('`{0}` – {1}' -f $c.Name, ($parts -join ', '))) | Out-Null
    }
    if ($snips.Count -ge $Max) { break }
  }
  return $snips.ToArray()
}

function Get-ForeignKeyRefs {
  param([string[]]$DefsLines)

  $defsArr = ConvertTo-Array $DefsLines
  $refs = New-Object 'System.Collections.Generic.List[string]'
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  for ($i = 0; $i -lt $defsArr.Length; $i++) {
    $line = $defsArr[$i].Trim()
    if ($line -ne 'Foreign keys:') { continue }

    for ($j = $i + 1; $j -lt $defsArr.Length; $j++) {
      $row = $defsArr[$j].Trim()
      if (-not $row) { break }
      if ($row -match '^### ' -or $row -match '^## ') { break }
      if ($row -notmatch '^\|') { break }
      if ($row -match '^\|\s*---') { continue }
      if ($row -match '^\|\s*Name\s*\|') { continue }

      $m = [regex]::Match($row, '^\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|')
      if (-not $m.Success) { continue }

      $refCell = $m.Groups[3].Value.Trim()
      if (-not $refCell) { continue }

      $target = $refCell -replace '\(.*$',''
      $target = $target.Trim('`','"',"'",'[',']')
      if (-not $target) { continue }

      if ($seen.Add($target)) { $refs.Add($target) | Out-Null }
    }
  }

  return $refs.ToArray()
}

function New-RelationshipGraph {
  param(
    [string]$TableName,
    [string[]]$Outbound,
    [string[]]$Inbound
  )

  $id = ($TableName -replace '[^a-zA-Z0-9_]','_')
  $colors = '#ff6b6b,#64dfdf,#a855f7,#ffd166,#4ade80'.Split(',')
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('```mermaid') | Out-Null
  $lines.Add('graph LR') | Out-Null
  $lines.Add('  %% Neon lineage view (auto-parsed from docs/definitions.md)') | Out-Null
  $lines.Add('  classDef center fill:#0b1021,stroke:#ff6b6b,stroke-width:3px,color:#fefefe;') | Out-Null
  $lines.Add('  classDef link fill:#0a1f33,stroke:#64dfdf,stroke-width:2px,color:#e8f7ff;') | Out-Null
  $lines.Add('  classDef accent fill:#1d1b4c,stroke:#a855f7,stroke-width:2px,color:#f5e1ff;') | Out-Null
  $lines.Add('  classDef inbound fill:#0f172a,stroke:#10b981,stroke-width:2px,color:#e2fcef;') | Out-Null
  $lines.Add(('  {0}["{1}"]:::center' -f $id, $TableName)) | Out-Null

  $edgeIdx = 0
  foreach ($ref in $Outbound) {
    $refId = ($ref -replace '[^a-zA-Z0-9_]','_')
    $class = if ($edgeIdx % 2 -eq 0) { 'link' } else { 'accent' }
    $lines.Add(('  {0} -->|FK| {1}["{2}"]:::{3}' -f $id, $refId, $ref, $class)) | Out-Null
    $edgeIdx++
  }
  foreach ($src in $Inbound) {
    $srcId = ($src -replace '[^a-zA-Z0-9_]','_')
    $class = 'inbound'
    $lines.Add(('  {0}["{1}"]:::{2} -->|FK| {3}' -f $srcId, $src, $class, $id)) | Out-Null
    $edgeIdx++
  }

  for ($k = 0; $k -lt $edgeIdx; $k++) {
    $color = $colors[$k % $colors.Length]
    $lines.Add("  linkStyle $k stroke:$color,stroke-width:3px,opacity:0.92;") | Out-Null
  }

  $lines.Add('```') | Out-Null
  return $lines.ToArray()
}

# Resolve roots
$root = if ($MapRoot) { (Resolve-Path -LiteralPath $MapRoot).Path } else { (Resolve-Path '.').Path }
$pkgRoot = if ($PackagesRoot) { (Resolve-Path -LiteralPath $PackagesRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $root $PackagesDir)).Path }
$mapPathResolved = (Resolve-Path -LiteralPath (Join-Path $root $MapPath)).Path
$mapLabel = Split-Path -Path $mapPathResolved -Leaf
$mapLink = Get-LinkForPath -Path $mapPathResolved -RepoUrl $RepoUrl -Root $MapRoot
if (-not $mapLink) { $mapLink = (Get-RelativePathLegacy -BasePath $root -TargetPath $mapPathResolved -replace '\\','/') }
$licensePath = Join-Path $root 'LICENSE'
$licenseLink = Get-LinkForPath -Path $licensePath -RepoUrl $RepoUrl -Root $root
$packagesResolved = $pkgRoot

# Build inbound FK index from all package definitions (docs/definitions.md only)
$inboundIndex = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]' ([System.StringComparer]::OrdinalIgnoreCase)
$defsFiles = @()
try {
  $defsFiles = Get-ChildItem -LiteralPath $packagesResolved -Filter 'definitions.md' -Recurse -ErrorAction SilentlyContinue
} catch {}
foreach ($df in $defsFiles) {
  $pkgDir = $df.Directory.Parent
  if (-not $pkgDir) { continue }
  $srcTable = ($pkgDir.Name -replace '-','_')
  $defsLinesForIndex = ConvertTo-Array (Get-Content -LiteralPath $df.FullName -ErrorAction SilentlyContinue)
  $outRefsForIndex = Get-ForeignKeyRefs -DefsLines $defsLinesForIndex
  foreach ($r in $outRefsForIndex) {
    if (-not $inboundIndex.ContainsKey($r)) {
      $inboundIndex[$r] = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    }
    $null = $inboundIndex[$r].Add($srcTable)
  }
}
function Get-InboundRefsForTable {
  param([string]$TableName)
  if ($inboundIndex.ContainsKey($TableName)) { return @($inboundIndex[$TableName]) }
  return @()
}

# Load map
$map = Import-Map -Path $mapPathResolved
$tables = @($map.Tables.Keys | Sort-Object)
$stamp = Get-MapStamp -MapPathResolved $mapPathResolved

foreach ($t in $tables) {
  $slug = ConvertTo-Slug $t
  $pkgPath = Join-Path $packagesResolved $slug
  if (-not (Test-Path -LiteralPath $pkgPath)) {
    if (-not $Quiet) { Write-Warning "SKIP [$t] – package folder not found: $pkgPath" }
    continue
  }

  $readmePath = Join-Path $pkgPath 'README.md'
  $readmeDir = Split-Path -LiteralPath $readmePath
  if ((Test-Path -LiteralPath $readmePath) -and -not $Force) {
    if (-not $Quiet) { Write-Host "SKIP [$t] – README exists (use -Force to overwrite)" }
    continue
  }

  $docsPath = Join-Path $pkgPath 'docs/definitions.md'
  $changelogPath = Join-Path $pkgPath 'CHANGELOG.md'
  $pkgRootRel = (Get-RelativePathLegacy -BasePath $root -TargetPath $pkgPath -replace '\\','/')
  $pkgRootLink = $null
  if ($RepoUrl) {
    $pkgRootLink = ($RepoUrl.TrimEnd('/') + '/' + $pkgRootRel)
  }
  if ($pkgRootLink) { $pkgRootLink = ($pkgRootLink -replace '\\','/') }
  function Get-PkgLink {
    param([string]$Path, [switch]$PreferRelative)
    $base = $pkgPath
    if ($Path -match 'views-library') { $base = $MapRoot }
    elseif ($Path -like "$root*") { $base = $root }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ($PreferRelative) {
      $rel = Get-RelativePathLegacy -BasePath $readmeDir -TargetPath $resolved
      return ($rel -replace '\\','/')
    }
    $link = Get-LinkForPath -Path $resolved -RepoUrl $RepoUrl -Root $base
    if ($link) { $link = ($link -replace '\\','/') }
    return $link
  }
  $docsLink = Get-PkgLink -Path $docsPath -PreferRelative
  $changelogLink = Get-PkgLink -Path $changelogPath -PreferRelative
  $engineDiffLink = if ($docsLink) { $docsLink + '#engine-differences' } else { $null }
  $explorerPath = Join-Path $pkgPath 'docs/schema-explorer.html'
  $explorerLink = Get-PkgLink -Path $explorerPath -PreferRelative

  $schemaDir = Join-Path $pkgPath 'schema'
  $schemaFiles = @()
  if (Test-Path -LiteralPath $schemaDir) {
    $schemaFiles = ConvertTo-Array (Get-ChildItem -LiteralPath $schemaDir -File -Recurse | Sort-Object FullName)
  }
  $viewFiles = ConvertTo-Array ($schemaFiles | Where-Object { $_.Name -match 'views' })
  $seedFiles = ConvertTo-Array ($schemaFiles | Where-Object { $_.Name -match 'seed' })

  $lines = New-Object System.Collections.Generic.List[string]
  $title = ConvertTo-TitleCase $slug

  $lines.Add("# 📦 $title") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("> Auto-generated from [$mapLabel]($mapLink) ($stamp). Do not edit manually.") | Out-Null
  $lines.Add("> Targets: PHP 8.3; MySQL 8.x / MariaDB 10.4; Postgres 15+.") | Out-Null
  $lines.Add("") | Out-Null

  # Badges
  $badges = @(
    '![PHP](https://img.shields.io/badge/PHP-8.3-blueviolet)',
    '![DB](https://img.shields.io/badge/DB-MySQL%20%7C%20MariaDB%20%7C%20Postgres-informational)',
    '![License](https://img.shields.io/badge/license-BlackCat%20Proprietary-red)',
    '![Status](https://img.shields.io/badge/status-stable-success)'
  )
  $lines.Add(($badges -join " ")) | Out-Null
  $lines.Add("") | Out-Null

  function New-StatusBadge {
    param([string]$Label, [bool]$Ok, [string]$TextIfOk = 'ok', [string]$TextIfFail = 'missing')
    $val = if ($Ok) { $TextIfOk } else { $TextIfFail }
    $color = if ($Ok) { 'success' } else { 'critical' }
    $safeLabel = ($Label -replace ' ','%20')
    $safeVal   = ($val -replace ' ','%20')
    "![${safeLabel}](https://img.shields.io/badge/${safeLabel}-${safeVal}-${color})"
  }

  $hasDocs = Test-Path -LiteralPath $docsPath
  $hasChangelog = Test-Path -LiteralPath $changelogPath
  $changelogFresh = $null
  $changelogFreshDays = $null
  $changelogFreshThreshold = 45
  if ($hasChangelog) {
    $clItem = Get-Item -LiteralPath $changelogPath -ErrorAction SilentlyContinue
    if ($clItem) {
      # use UTC + whole days to avoid day-to-day drift between environments/timezones
      $changelogFreshDays = [int](([datetime]::UtcNow.Date - $clItem.LastWriteTimeUtc.Date).TotalDays)
      $changelogFresh = if ($changelogFreshDays -le $changelogFreshThreshold) { 'fresh' } else { 'stale' }
    }
  }
  $schemaCount = Get-SafeCount $schemaFiles
  $viewCount   = Get-SafeCount $viewFiles
  $seedCount   = Get-SafeCount $seedFiles
  $hasSeeds = ($seedCount -gt 0)
  $hasViews = ($viewCount -gt 0)

  # Drift badge (from definitions, normalized)
  $defsLines = @()
  if (Test-Path -LiteralPath $docsPath) {
    $defsLines = ConvertTo-Array (Get-Content -LiteralPath $docsPath -ErrorAction SilentlyContinue)
  }
  $driftLines = @()
  $defsCount = Get-SafeCount $defsLines
  $fkRefs = @()
  $colObjects = @()
  $piiSignals = @()
  $constraintSnips = @()
  if ($defsCount -gt 0) {
    $idxDiff = $defsLines.IndexOf('## Engine differences')
    if ($idxDiff -ge 0) {
      for ($i = $idxDiff + 1; $i -lt $defsLines.Length; $i++) {
        if ($defsLines[$i] -match '^## ') { break }
        $trim = $defsLines[$i].Trim()
        if (-not $trim) { continue }
        if ($trim -like '- Column differences:*') {
          $parsed = ConvertFrom-ColumnDiffLine -Line $trim
          if ($parsed) { $driftLines += $parsed }
        } else {
          $driftLines += $trim
        }
      }
    }
    $fkRefs = Get-ForeignKeyRefs -DefsLines $defsLines
    $colObjects = Get-ColumnObjects -DefsLines $defsLines
    $piiSignals = Get-PiiSignals -Columns $colObjects
    $constraintSnips = Get-ConstraintSnippets -Columns $colObjects -Max 5
  }

  $driftCount = Get-SafeCount $driftLines
  $inboundRefs = Get-InboundRefsForTable -TableName $t
  $fkRefs = @($fkRefs | Sort-Object -Stable -Property @{ Expression = { $_.ToLowerInvariant() } })
  $inboundRefs = @($inboundRefs | Sort-Object -Stable -Property @{ Expression = { $_.ToLowerInvariant() } })
  $inboundRefCount = Get-SafeCount $inboundRefs
  $fkRefCount = Get-SafeCount $fkRefs
  $lineageTotal = $fkRefCount + $inboundRefCount
  $colCount = Get-SectionRowCount -Lines $defsLines -Header '## Columns'
  $idxCount = Get-SectionRowCount -Lines $defsLines -Header 'Indexes:'
  $fkCount  = Get-SectionRowCount -Lines $defsLines -Header 'Foreign keys:'
  $uniqueCount = Get-SectionRowCount -Lines $defsLines -Header 'Unique keys:'
  $viewsCount = Get-SectionRowCount -Lines $defsLines -Header '## Views'
  $hasPrimaryKey = (($defsLines -join "`n") -match '\bPRIMARY\s+KEY\b')
  # Consider index coverage OK if we at least see a primary key and any secondary index.
  $indexCoverageOk = $hasPrimaryKey -and ($idxCount -gt 0)
  $piiCount = Get-SafeCount $piiSignals
  $constraintCount = Get-SafeCount $constraintSnips
  $changelogDescriptor = if ($changelogFresh) { $changelogFresh } else { 'n/a' }
  $driftStatus = $null
  if ($driftCount -gt 0) { $driftStatus = '⚠️ Engine drift detected (see definitions)' }
  elseif ($defsCount -gt 0) { $driftStatus = '✅ No engine drift detected' }

  $statusBadges = @(
    New-StatusBadge -Label 'Docs' -Ok $hasDocs -TextIfOk 'ready'
    New-StatusBadge -Label 'Changelog' -Ok $hasChangelog
    New-StatusBadge -Label 'Changelog freshness' -Ok (($changelogFresh -eq 'fresh') -or (-not $hasChangelog)) -TextIfOk 'fresh' -TextIfFail 'stale'
    New-StatusBadge -Label 'Seeds' -Ok $hasSeeds
    New-StatusBadge -Label 'Views' -Ok $hasViews
    New-StatusBadge -Label 'Lineage' -Ok (($fkRefCount + $inboundRefCount) -gt 0) -TextIfOk 'linked' -TextIfFail 'solo'
    New-StatusBadge -Label 'Drift' -Ok (($driftCount -eq 0) -and ($defsCount -gt 0)) -TextIfOk 'clean' -TextIfFail ($(if ($defsCount -gt 0) { 'warn' } else { 'n/a' }))
    New-StatusBadge -Label 'Index coverage' -Ok $indexCoverageOk -TextIfOk 'ready' -TextIfFail 'todo'
    New-StatusBadge -Label 'PII' -Ok ($piiCount -eq 0) -TextIfOk 'none' -TextIfFail 'review'
  )
  $lines.Add(($statusBadges -join " ")) | Out-Null
  $lines.Add("") | Out-Null

  if ($lineageTotal -ge 4) {
    $lines.Add("> 🔥 Lineage hotspot: $lineageTotal FK links detected. Make sure cascades/nullability are intentional.") | Out-Null
    $lines.Add("") | Out-Null
  }

  if ($driftStatus) {
    $lines.Add($driftStatus) | Out-Null
    $lines.Add("") | Out-Null
  }

  # Hero/vibe block (Markdown-friendly callout)
  $docsLabel = if ($docsLink) { "[$docsLink]($docsLink)" } else { "_definitions missing_" }
  $driftLabel = if ($driftStatus) { $driftStatus } else { 'Drift: n/a (no definitions yet)' }
  $lines.Add("> **Schema snapshot**") | Out-Null
  $lines.Add(("> Map: [{0}]({1}) · Docs: {2} · Drift warnings: {3}" -f $mapLabel, $mapLink, $docsLabel, $driftCount)) | Out-Null
  $lines.Add(("> Lineage: {0} outbound / {1} inbound · {2} · Index coverage: {3} · PII flags: {4} · Changelog: {5}" -f $fkRefCount, $inboundRefCount, $driftLabel, ($(if ($indexCoverageOk) { 'ready' } else { 'todo' })), $piiCount, $changelogDescriptor)) | Out-Null
  $lines.Add("") | Out-Null

  # Quick links
  $lines.Add("## Quick Links") | Out-Null
  $lines.Add("| What | Link | Notes |") | Out-Null
  $lines.Add("| --- | --- | --- |") | Out-Null
  $lines.Add(("| Schema map | [{0}]({1}) | Source for table metadata |" -f $mapLabel, $mapLink)) | Out-Null
  $pkgLabel = if ($pkgRootRel) { $pkgRootRel } else { $pkgPath }
  if ($pkgLabel) { $pkgLabel = ($pkgLabel -replace '\\','/') }
  if ($pkgRootLink) {
    $lines.Add(("| Pkg folder | [{0}]({1}) | Repo location |" -f $pkgLabel, $pkgRootLink)) | Out-Null
  } else {
    $lines.Add(("| Pkg folder | {0} | Repo location |" -f $pkgLabel)) | Out-Null
  }
  if ($docsLink) { $lines.Add(("| Definitions | [{0}]({0}) | Column/index/FK docs |" -f $docsLink)) | Out-Null } else { $lines.Add("| Definitions | _(missing)_ | run Build-Definitions |") | Out-Null }
  if ($engineDiffLink) { $lines.Add(("| Engine differences | [{0}]({0}) | Drift section in definitions |" -f $engineDiffLink)) | Out-Null }
  if ($explorerLink) { $lines.Add(("| Schema Explorer | [{0}]({0}) | HTML explorer (local) |" -f $explorerLink)) | Out-Null }
  if ($changelogLink) { $lines.Add(("| Changelog | [{0}]({0}) | Recent changes |" -f $changelogLink)) | Out-Null } else { $lines.Add("| Changelog | _(missing)_ |  |") | Out-Null }
  $lines.Add("") | Out-Null
  # Contents / TOC
  $lines.Add("## Contents") | Out-Null
  $lines.Add("| Section | Purpose |") | Out-Null
  $lines.Add("| --- | --- |") | Out-Null
  $lines.Add("| [Quick Links](#quick-links) | Jump to definitions/changelog/tooling |") | Out-Null
  $lines.Add("| [At a Glance](#at-a-glance) | Key counts (columns/indexes/views) |") | Out-Null
  $lines.Add("| [Summary](#summary) | Compact status matrix for this package |") | Out-Null
  $lines.Add("| [Relationship Graph](#relationship-graph) | FK lineage snapshot |") | Out-Null
  $lines.Add("| [Engine Matrix](#engine-matrix) | MySQL/Postgres coverage |") | Out-Null
  $lines.Add("| [Engine Drift](#engine-drift) | Cross-engine diffs |") | Out-Null
  $lines.Add("| [Constraints Snapshot](#constraints-snapshot) | Defaults/enums/checks |") | Out-Null
  $lines.Add("| [Compliance Notes](#compliance-notes) | PII/secret hints |") | Out-Null
  $lines.Add("| [Schema Files](#schema-files) | Scripts by engine |") | Out-Null
  $lines.Add("| [Views](#views) | View definitions |") | Out-Null
  $lines.Add("| [Seeds](#seeds) | Fixtures/smoke data |") | Out-Null
  $lines.Add("| [Usage](#usage) | Runnable commands |") | Out-Null
  $lines.Add("| [Quality Gates](#quality-gates) | Readiness checklist |") | Out-Null
  $lines.Add("| [Regeneration](#regeneration) | Rebuild docs/readme |") | Out-Null
  $lines.Add("") | Out-Null

  # Summary
  $lines.Add("## At a Glance") | Out-Null
  $lines.Add("| Metric | Count |") | Out-Null
  $lines.Add("| --- | --- |") | Out-Null
  $lines.Add(("| Columns | **{0}** |" -f $colCount)) | Out-Null
  $lines.Add(("| Indexes | **{0}** |" -f $idxCount)) | Out-Null
  $lines.Add(("| Foreign keys | **{0}** |" -f $fkCount)) | Out-Null
  $lines.Add(("| Unique keys | **{0}** |" -f $uniqueCount)) | Out-Null
  $lines.Add(("| Outbound links (FK targets) | **{0}** |" -f $fkRefCount)) | Out-Null
  $lines.Add(("| Inbound links (tables depending on this) | **{0}** |" -f $inboundRefCount)) | Out-Null
  $lines.Add(("| Views | **{0}** |" -f $viewsCount)) | Out-Null
  $lines.Add(("| Seeds | **{0}** |" -f $seedCount)) | Out-Null
  $lines.Add(("| Drift warnings | **{0}** |" -f $driftCount)) | Out-Null
  $lines.Add(("| PII flags | **{0}** |" -f $piiCount)) | Out-Null
  $lines.Add("") | Out-Null

  $lines.Add("## Summary") | Out-Null
  $lines.Add("| Item | Value |") | Out-Null
  $lines.Add("| --- | --- |") | Out-Null
  $lines.Add(("| Table | `{0}` |" -f $t)) | Out-Null
  $lines.Add(("| Schema files | **{0}** |" -f $schemaCount)) | Out-Null
  $lines.Add(("| Views | **{0}** |" -f $viewCount)) | Out-Null
  $lines.Add(("| Seeds | **{0}** |" -f $seedCount)) | Out-Null
  $lines.Add("| Docs | " + ($(if ($docsLink) { "**present**" } else { "_missing (run Build-Definitions)_" })) + " |") | Out-Null
  $lines.Add("| Changelog | " + ($(if ($changelogLink) { "**present**" } else { "_missing_" })) + " |") | Out-Null
  if ($changelogFresh) { $lines.Add(("| Changelog freshness | {0} (threshold {1} d) |" -f $changelogFresh, $changelogFreshThreshold)) | Out-Null }
  $lines.Add(("| Lineage | outbound **{0}** / inbound **{1}** |" -f $fkRefCount, $inboundRefCount)) | Out-Null
  $lines.Add("| Index coverage | " + ($(if ($indexCoverageOk) { '**ready**' } else { '_todo (add PK and at least one index)_' })) + " |") | Out-Null
  $lines.Add("| Engine targets | PHP 8.3; MySQL/MariaDB/Postgres |") | Out-Null
  $lines.Add("") | Out-Null

  $lines.Add("## Relationship Graph") | Out-Null
  if (($defsCount -eq 0) -and ($inboundRefCount -eq 0)) {
    $lines.Add("_No definitions found, so lineage cannot be rendered._") | Out-Null
  } elseif (($fkRefCount + $inboundRefCount) -eq 0) {
    $lines.Add("_No foreign keys declared in docs/definitions.md (inbound or outbound)._") | Out-Null
  } else {
    $lines.Add("> ⚡ Neon FK map below is parsed straight from docs/definitions.md for quick orientation.") | Out-Null
    $graphLines = New-RelationshipGraph -TableName $t -Outbound $fkRefs -Inbound $inboundRefs
    foreach ($g in $graphLines) { $lines.Add($g) | Out-Null }
    $lines.Add("") | Out-Null
    $prettyOutbound = ($fkRefs | Sort-Object) | ForEach-Object { '"{0}"' -f $_ }
    $prettyInbound = ($inboundRefs | Sort-Object) | ForEach-Object { '"{0}"' -f $_ }
    $lines.Add("- Outbound (depends on): " + ($(if ($fkRefCount -gt 0) { ($prettyOutbound -join ', ') } else { '_none_' }))) | Out-Null
    $lines.Add("- Inbound (relies on this): " + ($(if ($inboundRefCount -gt 0) { ($prettyInbound -join ', ') } else { '_none from defs_'}))) | Out-Null
    $lines.Add("- Legend: central node = this table, teal/purple arrows = outbound FK targets, green arrows = inbound FK sources.") | Out-Null
  }
  $lines.Add("") | Out-Null

  # Engine matrix
  $engineStats = @{
    mysql    = @{ schema = 0; views = 0 }
    postgres = @{ schema = 0; views = 0 }
  }
  foreach ($f in $schemaFiles) {
    $eng = Get-EngineFromFileName $f.Name
    if ($eng -and $engineStats.ContainsKey($eng)) { $engineStats[$eng].schema++ }
  }
  foreach ($vf in $viewFiles) {
    $eng = Get-EngineFromFileName $vf.Name
    if ($eng -and $engineStats.ContainsKey($eng)) { $engineStats[$eng].views++ }
  }
  function Format-EngineCell {
    param([int]$SchemaCount, [int]$ViewCount, [bool]$HasSeeds)
    $bits = @()
    $bits += $(if ($SchemaCount -gt 0) { "✅ schema($SchemaCount)" } else { "⚠️ schema" })
    $bits += $(if ($ViewCount -gt 0) { "✅ views($ViewCount)" } else { "⚠️ views" })
    $bits += $(if ($HasSeeds) { "✅ seeds" } else { "⚠️ seeds" })
    return ($bits -join '<br/>')
  }
  $lines.Add("## Engine Matrix") | Out-Null
  $lines.Add("| Engine | Support |") | Out-Null
  $lines.Add("| --- | --- |") | Out-Null
  foreach ($eng in @('mysql','postgres')) {
    $stat = $engineStats[$eng]
    $cell = Format-EngineCell -SchemaCount $stat.schema -ViewCount $stat.views -HasSeeds $hasSeeds
    $lines.Add("| $eng | $cell |") | Out-Null
  }
  $lines.Add("") | Out-Null

  $lines.Add("## Engine Drift") | Out-Null
  if ($driftCount -eq 0) {
    $lines.Add("_No engine differences detected._") | Out-Null
  } else {
    $lines.Add("_Listed after normalizing common equivalents (INT/INTEGER, TINYINT(1)/BOOLEAN, TEXT/JSONB where applicable, defaults 0/1/TRUE/FALSE)._") | Out-Null
    $lines.Add("") | Out-Null
    foreach ($d in $driftLines) { $lines.Add("- $d") | Out-Null }
  }
  $lines.Add("") | Out-Null

  # Constraints snapshot
  $lines.Add("## Constraints Snapshot") | Out-Null
  if ($constraintCount -eq 0) {
    $lines.Add("_No defaults/enums/checks detected in definitions.md columns._") | Out-Null
  } else {
    foreach ($sn in $constraintSnips) { $lines.Add("- $sn") | Out-Null }
  }
  $lines.Add("") | Out-Null

  # Schema files
  $lines.Add("## Schema Files") | Out-Null
  if ($schemaCount -eq 0) {
    $lines.Add("_No schema files found in `schema/`._") | Out-Null
  } else {
    $lines.Add("| File | Engine |") | Out-Null
    $lines.Add("| --- | --- |") | Out-Null
    foreach ($f in $schemaFiles) {
      $eng = Get-EngineFromFileName $f.Name
      $link = Get-PkgLink -Path $f.FullName -PreferRelative
      $lines.Add("| [$($f.Name)]($link) | $eng |") | Out-Null
    }
  }
  $lines.Add("") | Out-Null

  # Views
  $lines.Add("## Views") | Out-Null
  if ($viewCount -eq 0) {
    $lines.Add("_No view files found._") | Out-Null
  } else {
    $lines.Add("| File | Engine | Source |") | Out-Null
    $lines.Add("| --- | --- | --- |") | Out-Null
    foreach ($vf in $viewFiles) {
      $eng = Get-EngineFromFileName $vf.Name
      $link = Get-PkgLink -Path $vf.FullName -PreferRelative
      $source = 'package'
      if ($vf.FullName -match 'views-library') {
        $srcLink = Get-PkgLink -Path $vf.FullName
        $source = if ($srcLink) { "[views-library]($srcLink)" } else { 'views-library' }
      }
      $lines.Add("| [$($vf.Name)]($link) | $eng | $source |") | Out-Null
    }
  }
  $lines.Add("") | Out-Null

  # Seeds / fixtures
  $lines.Add("## Seeds") | Out-Null
  if ($seedCount -eq 0) {
    $lines.Add("_No seed files found._") | Out-Null
  } else {
    $lines.Add("| File | Engine |") | Out-Null
    $lines.Add("| --- | --- |") | Out-Null
    foreach ($sf in $seedFiles) {
      $eng = Get-EngineFromFileName $sf.Name
      $link = Get-PkgLink -Path $sf.FullName -PreferRelative
      $lines.Add("| [$($sf.Name)]($link) | $eng |") | Out-Null
    }
    $preview = ($seedFiles | Select-Object -First 3 | ForEach-Object { $_.Name })
    if ($preview.Count -gt 0) {
      $lines.Add("") | Out-Null
      $lines.Add("_Seed snapshot:_ " + ($preview -join ', ') + ($(if ($seedCount -gt $preview.Count) { " + $(($seedCount - $preview.Count)) more" } else { "" }))) | Out-Null
    }
  }
  $lines.Add("") | Out-Null

  # Compliance notes
  $lines.Add("## Compliance Notes") | Out-Null
  if ($piiCount -eq 0) {
    $lines.Add("_No PII-like columns detected in definitions.md._") | Out-Null
  } else {
    $lines.Add("> ⚠️ Potential PII/secret fields – review retention/encryption policies:") | Out-Null
    foreach ($p in $piiSignals | Sort-Object) { $lines.Add("- $p") | Out-Null }
  }
  $lines.Add("") | Out-Null

  # Usage hints
  $lines.Add("## Usage") | Out-Null
  foreach ($ln in @(
    '```bash',
    "# Install/upgrade schema",
    "pwsh -NoLogo -NoProfile -File scripts/schema-tools/Migrate-DryRun.ps1 -Package $slug -Apply",
    "# Split schema to packages",
    'pwsh -NoLogo -NoProfile -File scripts/schema-tools/Split-SchemaToPackages.ps1',
    "# Generate PHP DTO/Repo from schema",
    'pwsh -NoLogo -NoProfile -File scripts/schema-tools/Generate-PhpFromSchema.ps1 -SchemaDir scripts/schema -TemplatesRoot scripts/templates/php -ModulesRoot packages -NameResolution detect -Force',
    "# Validate SQL across packages",
    "pwsh -NoLogo -NoProfile -File scripts/schema-tools/Lint-Sql.ps1 -PackagesDir $PackagesDir",
    '```',
    '',
    '- PHPUnit (full DB matrix):',
    '```bash',
    'BC_DB=mysql vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"',
    'BC_DB=postgres vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"',
    'BC_DB=mariadb vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"',
    '```',
    ''
  )) { $lines.Add($ln) | Out-Null }

  # Quality gates
  function Format-Check {
    param([bool]$Ok, [string]$Label, [string]$HintIfFail = '')
    $mark = if ($Ok) { '[x]' } else { '[ ]' }
    $suffix = if ($Ok -or -not $HintIfFail) { '' } else { " – $HintIfFail" }
    return "$mark $Label$suffix"
  }
  $lines.Add("## Quality Gates") | Out-Null
  $lines.Add("- " + $(Format-Check -Ok $hasDocs -Label 'Definitions present' -HintIfFail 'run Build-Definitions')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok $hasChangelog -Label 'Changelog present')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok (($changelogFresh -eq 'fresh') -or -not $hasChangelog) -Label 'Changelog fresh' -HintIfFail ('older than {0} d' -f $changelogFreshThreshold))) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok $indexCoverageOk -Label 'Index coverage (PK + index)')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok ($fkRefCount -gt 0) -Label 'Outbound lineage captured')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok ($inboundRefCount -gt 0) -Label 'Inbound lineage mapped')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok ($defsCount -gt 0) -Label 'ERD renderable (mermaid)' -HintIfFail 'add docs/definitions.md')) | Out-Null
  $lines.Add("- " + $(Format-Check -Ok ($seedCount -gt 0) -Label 'Seeds available' -HintIfFail 'add smoke data seeds')) | Out-Null
  $lines.Add("") | Out-Null

  # Maintenance checklist
  $lines.Add("## Maintenance Checklist") | Out-Null
  $lines.Add("- [ ] Update schema map and split: Split-SchemaToPackages.ps1") | Out-Null
  $lines.Add("- [ ] Regenerate PHP DTO/Repo: Generate-PhpFromSchema.ps1") | Out-Null
  $lines.Add("- [ ] Rebuild definitions + README + docs index") | Out-Null
  $lines.Add("- [ ] Ensure seeds/smoke data are present (if applicable)") | Out-Null
  $lines.Add("- [ ] Lint SQL + run full PHPUnit DB matrix") | Out-Null
  $lines.Add("") | Out-Null

  # Regeneration
  $lines.Add("## Regeneration") | Out-Null
  foreach ($ln in @(
    '```bash',
    '# Rebuild definitions (docs/definitions.md)',
    'pwsh -NoLogo -NoProfile -File scripts/schema-tools/Build-Definitions.ps1 -Force',
    '# Regenerate package READMEs',
    'pwsh -NoLogo -NoProfile -File scripts/docs/New-PackageReadmes.ps1 -Force',
    '# Regenerate docs index',
    'pwsh -NoLogo -NoProfile -File scripts/docs/New-DocsIndex.ps1 -Force',
    '# Regenerate package changelogs',
    'pwsh -NoLogo -NoProfile -File scripts/docs/New-PackageChangelogs.ps1 -Force',
    '```',
    ''
  )) { $lines.Add($ln) | Out-Null }

  # Footer
  $lines.Add("---") | Out-Null
  $licenseNote = if ($licenseLink) {
    "> ⚖️ License: BlackCat Proprietary – detailed terms in [LICENSE]($licenseLink)."
  } else {
    "> ⚖️ License: BlackCat Proprietary – detailed terms in LICENSE at repo root."
  }
  $lines.Add($licenseNote) | Out-Null

  # Write file
  Set-Content -LiteralPath $readmePath -Value ($lines -join "`n") -Encoding UTF8
  if (-not $Quiet) { Write-Host "WROTE $readmePath" }
}
