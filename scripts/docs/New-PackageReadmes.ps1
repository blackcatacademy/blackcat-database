<#  New-PackageReadmes.ps1 (EN Cool v3.1 SAFE QUOTING)
    Generates README.md for each package based on scripts/schema-map.psd1
    - Badges
    - Files tree
    - Quick apply (bash & PowerShell)
    - Docker quickstart
    - Columns preview (parsed from CREATE TABLE)
    - Mermaid ER diagram for outgoing FKs
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$MapPath,
  [Parameter(Mandatory=$true)]
  [string]$PackagesDir,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $MapPath))     { throw "Map file not found: $MapPath" }
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "Packages dir not found: $PackagesDir" }

$map    = Import-PowerShellDataFile -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object
$mapLeaf    = Split-Path -Leaf $MapPath
$mapRev     = (git log -1 --format=%h -- $MapPath) 2>$null
$mapRevDate = (git log -1 --date=iso-strict --format=%cd -- $MapPath) 2>$null
if (-not $mapRev) { $mapRev='working-tree'; $mapRevDate=(Get-Date).ToString('s') }
$GenTag = "<!-- Auto-generated from $mapLeaf @ $mapRev ($mapRevDate) -->"

function Get-PackageSlug {
  param([string]$Table)
  $Table -replace '_','-'
}

function ConvertTo-TitleCase {
  param([string]$Name)
  $ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  $ti.ToTitleCase(($Name -replace '[_-]+',' ').ToLowerInvariant())
}

function ConvertTo-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return ,$Value }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value) }
  return ,$Value
}

function Get-ColumnsFromCreate {
  param([string]$CreateSql)

  $out = @()
  if ([string]::IsNullOrWhiteSpace($CreateSql)) { return $out }

  # Grab block between (...) right before ENGINE=
  $m = [regex]::Match($CreateSql, 'CREATE\s+TABLE.*?\((?<cols>[\s\S]*?)\)\s*ENGINE\s*=', 'IgnoreCase')
  $block = if ($m.Success) { $m.Groups['cols'].Value } else {
    $start = $CreateSql.IndexOf('(')
    $end   = $CreateSql.LastIndexOf(')')
    if ($start -ge 0 -and $end -gt $start) { $CreateSql.Substring($start+1, $end-$start-1) } else { $null }
  }
  if (-not $block) { return $out }

  $lines = [regex]::Split($block, '(?:\r\n|\n|\r)')

  foreach($raw in $lines){
    $line = ($raw -replace '--.*$','').Trim()
    if ($line -eq '' ) { continue }
    if ($line -match '^(PRIMARY|UNIQUE|KEY|INDEX|CONSTRAINT|CHECK|FOREIGN)\b') { continue }

    # match [name] [type ...] [constraints ...]
    $m2 = [regex]::Match($line, '^[`"]?(?<name>[A-Za-z0-9_]+)[`"]?\s+(?<rest>.+?)(,)?$')
    if (-not $m2.Success){ continue }

    $name = $m2.Groups['name'].Value
    $rest = $m2.Groups['rest'].Value.Trim()

    # extract type tokens until a keyword
    $stop = @('NOT','NULL','DEFAULT','AUTO_INCREMENT','PRIMARY','UNIQUE','CHECK','COMMENT','COLLATE','GENERATED','STORED','VIRTUAL','ON','REFERENCES')
    $tokens = @($rest -split '\s+')
    $typeTokens = New-Object System.Collections.Generic.List[string]
    foreach($tok in $tokens){
      if ($stop -contains $tok.ToUpperInvariant()) { break }
      $typeTokens.Add($tok)
    }
    $type = ($typeTokens -join ' ')

    $isNotNull = $rest -match '\bNOT\s+NULL\b'
    $isNull    = $rest -match '(^|[\s,])NULL\b' -and -not $isNotNull
    $nullTxt   = if ($isNotNull) {'NO'} elseif ($isNull) {'YES'} else {'—'}

    $defM = [regex]::Match($rest, 'DEFAULT\s+((?:''[^'']*'')|(?:[A-Za-z0-9_\.\(\)-]+))', 'IgnoreCase')
    $default = if ($defM.Success) { $defM.Groups[1].Value } else { '—' }

    $extra = @()
    if ($rest -match 'AUTO_INCREMENT') { $extra += 'AUTO_INCREMENT' }
    if ($rest -match 'PRIMARY\s+KEY')  { $extra += 'PK' }

    $out += [pscustomobject]@{
      Name    = $name
      Type    = $type
      Null    = $nullTxt
      Default = $default
      Extra   = ($extra -join ', ')
      IsPK    = $extra -contains 'PK'
    }
  }
  return $out
}

function Get-Relations {
  param($FkArray)

  $rels = @()
  foreach($fk in (ConvertTo-Array $FkArray)){
    if ([string]::IsNullOrWhiteSpace($fk)) { continue }
    $ref  = [regex]::Match($fk, 'REFERENCES\s+([A-Za-z0-9_]+)\s*\(', 'IgnoreCase').Groups[1].Value
    $cols = ([regex]::Match($fk, 'FOREIGN\s+KEY\s*\(([^)]+)\)', 'IgnoreCase').Groups[1].Value) -replace '\s',''
    $onDelete = [regex]::Match($fk, 'ON\s+DELETE\s+(CASCADE|SET\s+NULL|RESTRICT|NO\s+ACTION)', 'IgnoreCase').Groups[1].Value
    if ($ref) {
      $rels += [pscustomobject]@{
        RefTable = $ref
        Columns  = $cols
        OnDelete = $( if ($onDelete) { $onDelete.ToUpper() } else { '—' } )
      }
    }
  }
  $rels | Sort-Object RefTable, Columns -Unique
}

foreach ($t in $tables) {
  try {
    $slug = Get-PackageSlug $t
    $pkg  = Join-Path $PackagesDir $slug
    if (!(Test-Path -LiteralPath $pkg)) { Write-Warning "SKIP [$t] – package not found: $pkg"; continue }

    $tbl    = $map.Tables[$t]
    $create = $tbl['create']
    $idxArr = ConvertTo-Array ($tbl['indexes'])
    $fkArr  = ConvertTo-Array ($tbl['foreign_keys'])
    $cols = Get-ColumnsFromCreate -CreateSql $create
    $rels = Get-Relations -FkArray $fkArr

    $has020 = @( $idxArr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } ).Count -gt 0
    $has030 = @( $fkArr  | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } ).Count -gt 0

    # -- helper for a safe Mermaid edge label (no brackets, wrap in quotes)
    function ConvertTo-MermaidLabel {
      param([string]$Text)
      if ([string]::IsNullOrWhiteSpace($Text)) { return '""' }
      $t = $Text -replace '[`()]','' -replace '\s*,\s*', ', ' -replace '\s+',' '
      return '"' + $t.Trim() + '"'
    }
    function Get-MermaidType {
      param([string]$DbType)

      if ([string]::IsNullOrWhiteSpace($DbType)) { return 'COL' }

      # strip parentheses and enum values in quotes
      $t = $DbType -replace '\(.*?\)', ''   # VARCHAR(100) -> VARCHAR
      $t = $t -replace "'.*?'", ''          # ENUM('a','b') -> ENUM
      $t = ($t -split '\s+')[0]             # first token
      $t = $t -replace '[^A-Za-z0-9_]', ''  # keep only safe characters

      if ([string]::IsNullOrWhiteSpace($t)) { $t = 'COL' }

      # optional reduction of types into several families
      switch -Regex ($t.ToUpperInvariant()) {
        '^(VARCHAR|CHAR|TEXT|LONGTEXT|MEDIUMTEXT)$' { return 'VARCHAR' }
        '^(TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT)$' { return 'INT' }
        '^(DECIMAL|NUMERIC|FLOAT|DOUBLE)$'          { return 'DECIMAL' }
        '^(DATETIME|TIMESTAMP|DATE|TIME)$'          { return 'DATETIME' }
        '^(BOOLEAN|BOOL)$'                          { return 'BOOLEAN' }
        '^(BINARY|VARBINARY|BLOB|LONGBLOB|MEDIUMBLOB)$' { return 'BLOB' }
        '^(ENUM|SET)$'                              { return 'ENUM' }
        default { return $t }
      }
    }

    # -- Relationships text: always initialize
    $relText = @()
    if (@($rels).Count -eq 0) {
      $relText += '- No outgoing foreign keys.'
    } else {
      foreach($r in $rels){
        $relText += "- FK → **$($r.RefTable)** via `($($r.Columns))` (ON DELETE $($r.OnDelete))."
      }
    }

    # -- Mermaid ER diagram (entity + outgoing FKs)
    $tUp = $t.ToUpperInvariant()
    $merm = @()
    $merm += '```mermaid'
    $merm += 'erDiagram'

    # entity + columns (strip parentheses/quotes from types, mark PK)
    $merm += "  $tUp {"
    foreach ($c in $cols) {
      $firstType = Get-MermaidType $c.Type
      $pk = if ($c.IsPK) { ' PK' } else { '' }

      # column names are usually safe (e.g., meta_email); still sanitize exotic characters:
      $colName = $c.Name -replace '[^A-Za-z0-9_]', '_'

      $merm += "    $firstType $colName$pk"
    }
    $merm += '  }'

    # edges (label must be quoted and free of parentheses)
    foreach ($r in $rels) {
      $refUp = $r.RefTable.ToUpperInvariant()
      $label = ConvertTo-MermaidLabel $r.Columns
      # many-to-one visual }o--|| ; label = columns
      $merm += "  $tUp }o--|| $refUp : $label"
    }
    $merm += '```'

    # ---- header & badges
    $title = ConvertTo-TitleCase $t
    $badges = @(
      '![SQL](https://img.shields.io/badge/SQL-MySQL%208.0%2B-4479A1?logo=mysql&logoColor=white)',
      '![License](https://img.shields.io/badge/license-BlackCat%20Proprietary-red)',
      '![Status](https://img.shields.io/badge/status-stable-informational)',
      '![Generated](https://img.shields.io/badge/generated-from%20schema--map-blue)'
    )

    # ---- structure
    $structureLines = @('```', 'schema/', '  001_table.sql')
    if ($has020) { $structureLines += '  020_indexes.sql' } else { $structureLines += '  # (no deferred indexes declared in map)' }
    if ($has030) { $structureLines += '  030_foreign_keys.sql' } else { $structureLines += '  # (no foreign keys declared in map)' }
    $structureLines += '```'

    # ---- columns preview table
    $colPreview = @()
    if (@($cols).Count -gt 0) {
      $colPreview += '| Column | Type | Null | Default | Extra |'
      $colPreview += '|-------:|:-----|:----:|:--------|:------|'
      foreach($c in $cols){
        $niceType = if ($c.Type) { $c.Type -replace "''","'" } else { $c.Type }
        $colPreview += ("| `{0}` | {1} | {2} | {3} | {4} |" -f $c.Name,$niceType,$c.Null,$c.Default,$c.Extra)
      }
    } else {
      $colPreview += '_No columns parsed (the generator could not extract them from CREATE TABLE)._'
    }

    # ---- indexes summary
    $indexCount = @( $idxArr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } ).Count
    $idxSummary = if ($indexCount -gt 0) { "$indexCount deferred index statement(s) in `schema/020_indexes.sql`." } else { "No deferred indexes declared for this table." }

    # ---- quick apply blocks
    $quickBash = @(
      '```bash',
      '# Apply schema (Linux/macOS):',
      'mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < schema/001_table.sql'
    )
    if ($has020) { $quickBash += 'mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < schema/020_indexes.sql' }
    if ($has030) { $quickBash += 'mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < schema/030_foreign_keys.sql' }
    $quickBash += '```'

    $quickPs = @(
      '```powershell',
      '# Apply schema (Windows PowerShell):',
      'mysql -h $env:DB_HOST -u $env:DB_USER -p$env:DB_PASS $env:DB_NAME < schema/001_table.sql'
    )
    if ($has020) { $quickPs += 'mysql -h $env:DB_HOST -u $env:DB_USER -p$env:DB_PASS $env:DB_NAME < schema/020_indexes.sql' }
    if ($has030) { $quickPs += 'mysql -h $env:DB_HOST -u $env:DB_USER -p$env:DB_PASS $env:DB_NAME < schema/030_foreign_keys.sql' }
    $quickPs += '```'

    $docker = @(
      '```bash',
      '# Spin up a throwaway MySQL and apply just this package:',
      'docker run --rm -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=app -p 3307:3306 -d mysql:8',
      'sleep 15',
      'mysql -h 127.0.0.1 -P 3307 -u root -proot app < schema/001_table.sql'
    )
    if ($has020) { $docker += 'mysql -h 127.0.0.1 -P 3307 -u root -proot app < schema/020_indexes.sql' }
    if ($has030) { $docker += 'mysql -h 127.0.0.1 -P 3307 -u root -proot app < schema/030_foreign_keys.sql' }
    $docker += '```'

    # ---- assemble README
    $readme = @()
    $readme += "# 📦 $title"
    $readme += ""
    $readme += ($badges -join " ")
    $readme += ""
    $readme += $GenTag
    $readme += ""
    $readme += ('> Schema package for table **{0}** (repo: `{1}`).' -f $t, $slug)
    $readme += ""
    $readme += "## Files"
    $readme += ($structureLines -join "`n")
    $readme += ""
    $readme += "## Quick apply"
    $readme += ($quickBash -join "`n")
    $readme += ""
    $readme += ($quickPs -join "`n")
    $readme += ""
    $readme += "## Docker quickstart"
    $readme += ($docker -join "`n")
    $readme += ""
    $readme += "## Columns"
    $readme += ($colPreview -join "`n")
    $readme += ""
    $readme += "## Relationships"
    $readme += ($relText -join "`n")
    $readme += ""
    $readme += ($merm -join "`n")
    $readme += ""
    $readme += "## Indexes"
    $readme += "- $idxSummary"
    $readme += ""
    $readme += "## Notes"
    $readme += '- Generated from the umbrella repository **blackcat-database** using `scripts/schema-map.psd1`.'
    $readme += '- To change the schema, update the map and re-run the generators.'
    $readme += ""
    $readme += "## License"
    $readme += 'Distributed under the **BlackCat Store Proprietary License v1.0**. See `LICENSE`.'
    $readme += ""

    # ---- write
    $schemaDir  = Join-Path $pkg 'schema'
    New-Item -ItemType Directory -Force -Path $schemaDir | Out-Null

    $readmePath = Join-Path $pkg 'README.md'
    if ((Test-Path -LiteralPath $readmePath) -and -not $Force) {
      Write-Host "SKIP [$t] – README exists (use -Force to overwrite)"
    } else {
      Set-Content -Path $readmePath -Value ($readme -join "`n") -Encoding UTF8 -NoNewline
      Write-Host "WROTE [$t] -> $readmePath"
    }
  }
  catch {
    Write-Warning "FAILED [$t]: $($_.Exception.Message)"
  }
}
