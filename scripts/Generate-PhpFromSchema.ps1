param(
  [Alias('Map','MapFile')]
  [string]$MapPath,                           # volitelné; když chybí, hledá se v -SchemaDir
  [string]$SchemaDir = "./schema",            # kde hledat schema-map-*.psd1
  [ValidateSet('auto','postgres','mysql','both')]
  [string]$EnginePreference = 'auto',

  [Parameter(Mandatory=$true)]
  [string]$TemplatesRoot,                     # ./templates/php (obsahuje *.psd1 šablony)

  [string]$ModulesRoot = "./packages",        # kořen submodulů; pro tabulku 'users' => ./packages/users
  [ValidateSet('detect','snake','kebab','pascal')]
  [string]$NameResolution = 'kebab',          # výchozí jen kebab
  [switch]$StrictSubmodules,                  # vyžaduj, aby cíl byl zapsán v .gitmodules

  [string]$BaseNamespace = "BlackCat\Database\Packages", # základ pro NAMESPACE token
  [string]$DatabaseFQN = "BlackCat\Core\Database",
  [string]$Timezone = "UTC",
  # Views (volitelné) – když nenecháš, autodetekuje se views-map-*.psd1 pod $ViewsDir/$SchemaDir
  [string]$ViewsPath,
  [string]$ViewsDir = "./schema",
  [switch]$FailOnViewDrift,                   # když nepředáš, skript stejně failne na drift (viz níže)
  [switch]$Force,
  [switch]$WhatIf,
  [switch]$AllowUnresolved,                   # pokud máš rozpracované šablony, můžeš dočasně povolit nedořešené tokeny
  [switch]$JoinAsInner,                       # (legacy) alias pro JoinPolicy 'all'
  [switch]$JoinAsInnerStrict,                 # (legacy) alias pro JoinPolicy 'any'
  [ValidateSet('left','all','any')]
  [string]$JoinPolicy = 'left',               # explicitní politika JOINů pro FK (left|all|any)

  # === NOVÉ: tvrdý režim a kontrola „zastaralých“ vzorů ===
  [switch]$TreatWarningsAsErrors,             # varování = chyba (non-zero exit)
  [switch]$FailOnStale,                       # po generování projede repo a spadne na „stale“ vzorech
  [string[]]$StalePatterns = @(
    '(?i)""\s*\.\s*\$order',                  # prázdné "" + tečka + $order (typické lepení)
    '(?i)"\s*ORDER\s*(BY)?\s*"\s*\.\s*\$order',
    '(?i)\(\s*\$order\s*\?\s*"?\s*ORDER\s*(BY)?\s*"?\s*\.\s*\$order'
  )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# --- Warning counter ---
$script:WarnCount = 0
function Write-Warning {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position=0, ValueFromPipeline)]
    [string]$Message
  )
  $script:WarnCount++
  Microsoft.PowerShell.Utility\Write-Warning @PSBoundParameters
}
# --- Fail policy helpers (nové) ---
function Test-StaleRepo {
  param([string]$Root)
  $hits = @()
  $pkg  = Join-Path $Root 'packages'
  $files = Get-ChildItem -Path $pkg -Filter *.php -File -Recurse -ErrorAction SilentlyContinue
  foreach ($p in $StalePatterns) {
    if ($files) {
      $hits += Select-String -Path $files.FullName -Pattern $p -AllMatches -ErrorAction SilentlyContinue
    }
  }
  ,$hits
}

function Stop-IfNeeded {
  param([string]$RepoRoot)
  Write-Host ("Warnings emitted: {0}" -f $script:WarnCount) -ForegroundColor Yellow

  if ($TreatWarningsAsErrors -and $script:WarnCount -gt 0) {
    throw "Failing due to $($script:WarnCount) warning(s) (TreatWarningsAsErrors)."
  }

  if ($FailOnStale) {
    $stale = Test-StaleRepo -Root $RepoRoot
    if ($stale.Count -gt 0) {
      $preview = $stale |
        Select-Object -First 8 |
        ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" } |
        Out-String
      throw "Stale code patterns detected:`n$preview`n(Hits total: $($stale.Count))."
    }
  }
}

# -----------------------
# Helpers
# -----------------------
function Split-ByCommaOutsideParens([string]$s) {
  $out=@(); $buf=''; $depth=0; $q=$null
  for ($i=0; $i -lt $s.Length; $i++) {
    $ch = $s[$i]
    if ($q) {                      # uvnitř uvozovek
      $buf += $ch
      if ($ch -eq $q) { $q=$null }
      continue
    }
    if ($ch -eq "'" -or $ch -eq '"') { $q=$ch; $buf+=$ch; continue }
    if ($ch -eq '(') { $depth++; $buf+=$ch; continue }
    if ($ch -eq ')') { $depth=[Math]::Max(0,$depth-1); $buf+=$ch; continue }
    if ($ch -eq ',' -and $depth -eq 0) { $out += $buf.Trim(); $buf=''; continue }
    $buf += $ch
  }
  if ($buf.Trim()) { $out += $buf.Trim() }
  return ,$out
}
function Get-PrimaryKeyCombosFromCreateSql {
  param([string]$CreateSql)

  if (-not $CreateSql) { return @() }
  $combos = @()

  # a) table-level: PRIMARY KEY (col[, col2...])
  foreach ($m in [regex]::Matches($CreateSql, '(?is)PRIMARY\s+KEY\s*\(\s*([^)]+?)\s*\)')) {
    $cols = ($m.Groups[1].Value -replace '[`"\s]','') -split ','
    if ($cols -and $cols.Count -gt 0) { $combos += ,$cols }
  }

  # b) inline: <col> ... PRIMARY KEY
  foreach ($m in [regex]::Matches($CreateSql, '(?im)^\s*[`"]?([a-z0-9_]+)[`"]?\s+[^,\r\n]*?\bPRIMARY\s+KEY\b')) {
    $col = $m.Groups[1].Value
    if ($col) { $combos += ,@($col) }
  }

  # deduplikace (case-insensitive, pořadí sloupců zachováno)
  $seen = @{}
  $out  = @()
  foreach ($arr in $combos) {
    $key = (($arr | ForEach-Object { $_.ToLower() }) -join '#')
    if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $out += ,$arr }
  }
  return ,$out
}
function Get-UniqueCombosFromCreateSql {
  param([string]$CreateSql)

  if (-not $CreateSql) { return @() }
  $combos = @()

  # Table-level UNIQUE a UNIQUE KEY/INDEX (původní část)
  $pattern = '(?isx)
    (?:CONSTRAINT \s+ [`"]? [A-Za-z0-9_]+ [`"]? \s+ )?   # volitelné jméno constraintu
    UNIQUE \s* (?:KEY|INDEX)? \s*                        # UNIQUE / UNIQUE KEY / UNIQUE INDEX
    (?: [`"]? [A-Za-z0-9_]+ [`"]? \s* )?                 # volitelně jméno indexu
    \(\s* ([^)]+?) \s*\)                                 # seznam sloupců v závorkách
  '
  foreach ($m in [regex]::Matches($CreateSql, $pattern)) {
    $cols = ($m.Groups[1].Value -replace '[`"\s]','') -split ','
    if ($cols -and $cols.Count -gt 0) { $combos += ,$cols }
  }

  # *** NEW ***: in-line UNIQUE u sloupce
  # např.:   name VARCHAR(100) NOT NULL UNIQUE,
  foreach ($m in [regex]::Matches($CreateSql, '(?im)^\s*[`"]?([a-z0-9_]+)[`"]?\s+[^,\r\n]*?\bUNIQUE\b(?!\s+(?:KEY|INDEX)\b)')) {
    $col = $m.Groups[1].Value
    if ($col) { $combos += ,@($col) }
  }

  return ,$combos
}
function Assert-UpsertConsistency {
  param(
    [string]$Table,
    [string[]]$UpsertKeys,
    [string[]]$UpsertUpdateCols,
    [string[][]]$UniqueCombos,
    [string]$UpdatedAtCol
  )
  if (-not $UpsertKeys -or $UpsertKeys.Count -eq 0) { return }
  $keys = @($UpsertKeys | ForEach-Object { $_.ToLower() } | Sort-Object)
  $match = $false
  foreach ($combo in @($UniqueCombos)) {
    $c = @($combo | ForEach-Object { $_.ToLower() } | Sort-Object)
    if ($c.Count -eq $keys.Count -and (@(Compare-Object $c $keys).Count -eq 0)) { $match = $true; break }
  }
  if (-not $match) {
    Write-Warning "Table '$Table' Upsert.Keys = [$($keys -join ', ')] does not match any UNIQUE index/PK."
  }
  foreach ($k in $keys) {
    if ($UpsertUpdateCols -and ($UpsertUpdateCols | ForEach-Object { $_.ToLower() }) -contains $k) {
      Write-Warning "Table '$Table' Upsert.Update contains key column '$k' – usually undesired."
    }
  }
  if ($UpdatedAtCol -and $UpsertUpdateCols -and -not (($UpsertUpdateCols | ForEach-Object { $_.ToLower() }) -contains $UpdatedAtCol.ToLower())) {
    Write-Warning "Table '$Table' Upsert.Update does not include '$UpdatedAtCol'."
  }
}
function Get-FkLocalColumnsFromSql([array]$ForeignKeySqls) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($raw in @($ForeignKeySqls)) {
    if (-not $raw) { continue }
    foreach ($m in [regex]::Matches([string]$raw, '(?is)FOREIGN\s+KEY\s*\(\s*([^)]+?)\s*\)\s*REFERENCES')) {
      $loc = ($m.Groups[1].Value -replace '[`"\s]','') -split ','
      foreach ($x in $loc) { if ($x) { $out.Add($x.ToLower()) } }
    }
  }
  @($out | Select-Object -Unique)
}
function Assert-ReferencedViews {
  param(
    [string]$Table,
    [array]$ForeignKeySqls,
    [hashtable]$ViewsMap,
    [switch]$FailHard
  )
  $missing = @()
  foreach ($raw in @($ForeignKeySqls)) {
    if (-not $raw) { continue }
    foreach ($m in [regex]::Matches([string]$raw, '(?i)REFERENCES\s+[`"]?([a-z0-9_]+)[`"]?')) {
      $ref = $m.Groups[1].Value
      if (-not ($ViewsMap -and $ViewsMap.Views -and $ViewsMap.Views.ContainsKey($ref))) {
        $missing += $ref
      }
    }
  }
  $missing = @($missing | Select-Object -Unique)
  if ($missing.Count -gt 0) {
    $msg = "Missing referenced views for '$Table': " + (($missing | ForEach-Object { "vw_$($_)" }) -join ', ')
    if ($FailHard) { throw $msg } else { Write-Error $msg }
  }
}
function Import-SchemaMap([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Schema map not found at '$Path'." }
  Import-PowerShellDataFile -Path $Path
}
function Import-ViewsMap([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Views map not found at '$Path'." }
  Import-PowerShellDataFile -Path $Path
}

function Get-Templates([string]$Root) {
  if (-not (Test-Path $Root)) { throw "TemplatesRoot '$Root' not found." }
  $files = Get-ChildItem -LiteralPath $Root -Filter '*.psd1' -Recurse
  if (-not $files) { throw "No .psd1 templates found under '$Root'." }
  foreach ($f in $files) {
    $t = Import-PowerShellDataFile -Path $f.FullName
    if (-not $t.File -or -not $t.Content) {
      throw "Template '$($f.FullName)' must define 'File' and 'Content'."
    }
    # Normalize Tokens to array of strings
    if (-not ($t.Keys -contains 'Tokens')) { $t['Tokens'] = @() }
    [PSCustomObject]@{
      Name    = $f.Name
      Path    = $f.FullName
      File    = $t.File
      Tokens  = @($t.Tokens)
      Content = [string]$t.Content
    }
  }
}
function ConvertTo-PhpAssoc([hashtable]$ht) {
  if (-not $ht -or $ht.Keys.Count -eq 0) { return '[]' }
  $pairs = New-Object System.Collections.Generic.List[string]
  foreach ($k in ($ht.Keys | Sort-Object)) {
    $v = [string]$ht[$k]
    if ($k -and $v) { $pairs.Add("'$k' => '$v'") }
  }
  return "[ " + ($pairs -join ', ') + " ]"
}
function ConvertTo-PascalCase([string]$snake) {
  ($snake -split '[_\s\-]+' | ForEach-Object { if ($_ -ne '') { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() } }) -join ''
}
function ConvertTo-CamelCase([string]$snake) {
  $p = ConvertTo-PascalCase $snake
  if ($p.Length -gt 0) { ($p.Substring(0,1).ToLower() + $p.Substring(1)) } else { $p }
}
function Get-SubmodulePathSet([string]$repoRoot) {
  $set = @{}
  $gm = Join-Path $repoRoot '.gitmodules'
  if (Test-Path -LiteralPath $gm) {
    $txt = Get-Content -LiteralPath $gm -Raw
    foreach ($m in [regex]::Matches($txt, '^\s*path\s*=\s*(.+)$', 'Multiline')) {
      $p = $m.Groups[1].Value.Trim()
      if ($p) { $set[$p] = $true }
    }
  }
  return $set
}
function Resolve-PackagePath {
  param(
    [Parameter(Mandatory)][string]$PackagesDir,
    [Parameter(Mandatory)][string]$Table,          # snake_case (název tabulky)
    [Parameter(Mandatory)][string]$PackagePascal,  # PascalCase (např. BookAssets)
    [Parameter(Mandatory)][string]$Mode            # detect|snake|kebab|pascal
  )

  $snake  = $Table
  $kebab  = ($Table -replace '_','-')
  $pascal = $PackagePascal

  $candidates = switch ($Mode) {
    'snake'  { @( Join-Path $PackagesDir $snake ) }
    'kebab'  { @( Join-Path $PackagesDir $kebab ) }
    'pascal' { @( Join-Path $PackagesDir $pascal ) }
    default  { @(
      (Join-Path $PackagesDir $pascal),
      (Join-Path $PackagesDir $snake),
      (Join-Path $PackagesDir $kebab)
    ) }
  }

  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
  }
  return $null
}
function Get-IndexNamesFromSql([array]$IndexSqls) {
  $names = @()
  foreach ($ix in @($IndexSqls)) {
    if (-not $ix) { continue }
    # PG / MySQL: CREATE [UNIQUE] INDEX [IF NOT EXISTS] idx_name ON ...
    if ($ix -match '(?i)CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?([`"\[]?)([A-Za-z0-9_]+)\1\s+ON') {
      $names += $matches[2]
    }
  }
  @($names | Sort-Object -Unique)
}

function Get-ForeignKeyNamesFromSql([array]$FkSqls) {
  $names = @()
  foreach ($fk in @($FkSqls)) {
    if (-not $fk) { continue }
    # ALTER TABLE ... ADD CONSTRAINT fk_name FOREIGN KEY (...)
    if ($fk -match '(?i)ADD\s+CONSTRAINT\s+([`"\[]?)([a-z0-9_]+)\1\s+FOREIGN\s+KEY') {
      $names += $matches[2]
    }
  }
  @($names | Sort-Object -Unique)
}

function Get-ProjectionColumnsFromViewSql([string]$viewSql) {
  if (-not $viewSql) { return @() }

  # --- 1) původní multi-line heuristika ---
  $lines = ($viewSql -split '\r?\n')
  $start = 0; $end = 0
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*SELECT(\s+DISTINCT)?\b') { $start = $i + 1; break }
  }
  for ($j=$start; $j -lt $lines.Count; $j++) {
    if ($lines[$j] -match '^\s*FROM\b') { $end = $j - 1; break }
  }

  $collect = New-Object System.Collections.Generic.List[string]
  if ($end -gt $start) {
    for ($k=$start; $k -le $end; $k++) {
      $ln = $lines[$k].Trim().TrimEnd(',')
      if ($ln -eq '') { continue }
      if ($ln -match '(?i)\s+AS\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*$') {
        $collect.Add($matches[1].ToLower()); continue
      }
      $m = [regex]::Matches($ln, '[A-Za-z0-9_]+')
      if ($m.Count -gt 0) { $collect.Add($m[$m.Count-1].Value.ToLower()); continue }
    }
  }

  if ($collect.Count -gt 0) {
    return @($collect | Select-Object -Unique)
  }

  # --- 2) fallback: jednorádkové SELECTy, DISTINCT apod. ---
  $m2 = [regex]::Match($viewSql, '(?is)\bSELECT\b\s+(?:DISTINCT\s+)?(.*?)\bFROM\b')
  if (-not $m2.Success) { return @() }

  $segment = $m2.Groups[1].Value
  # odstraň komentáře na konci a přebytečné whitespace
  $segment = ($segment -replace '(?s)/\*.*?\*/','' -replace '--[^\r\n]*','') -replace '\s+',' '

  $out = New-Object System.Collections.Generic.List[string]
  foreach ($piece in (Split-ByCommaOutsideParens $segment)) {
    $part = $piece.Trim()
    if ($part -eq '') { continue }

    # alias: "... AS name" nebo "... name" (poslední token)
    if ($part -match '(?i)\bAS\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*$') {
      $out.Add($matches[1].ToLower()); continue
    }

    # odstraň backticky/uvozovky a vezmi poslední identifikátor
    $plain = ($part -replace '[`"]','').Trim()
    $ids = [regex]::Matches($plain, '[A-Za-z0-9_]+')
    if ($ids.Count -gt 0) { $out.Add($ids[$ids.Count-1].Value.ToLower()) }
  }

  @($out | Select-Object -Unique)
}

function Assert-TableVsView {
  param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string[]]$TableColumns,  # lowercased
    [string[]]$Pk,
    [string]$VersionColumn,
    [string]$SoftDeleteColumn,
    [string]$DefaultOrder,
    [hashtable]$ViewsMap,
    [string[]]$BinaryColumns = @(),
    [hashtable]$PairColumns = $null,
    [string[]]$FkLocalColumns = @(),
    [switch]$FailHard
  )
  
  $errs = New-Object System.Collections.Generic.List[string]
  $warn = New-Object System.Collections.Generic.List[string]

  # --- Normalize PK to a flat array of clean column names ---
  [string[]]$PkColsNorm = @()
  foreach ($item in @($Pk)) {
    if ($null -eq $item) { continue }
    if ($item -is [System.Array]) {
      $PkColsNorm += @($item)
    } else {
      $PkColsNorm += @($item -split '[,\s]+' | Where-Object { $_ })
    }
  }
  $PkColsNorm = @($PkColsNorm |
    ForEach-Object { ($_ -replace '[`"]','').ToLower() } |
    Select-Object -Unique)

  $viewName = "vw_$Table"
  $viewSql  = $null

  if ($ViewsMap -and $ViewsMap.Views -and $ViewsMap.Views.ContainsKey($Table)) {
    $viewSql = [string]$ViewsMap.Views[$Table].create
  } else {
    $errs.Add("Missing view SQL for '$Table' (expected $viewName).")
  }

  if ($viewSql) {
    # Nejdřív si připrav sadu projekcí
    $proj = @( Get-ProjectionColumnsFromViewSql $viewSql )
    $projSet = @{}
    foreach ($c in $proj) { $projSet[$c] = $true }

    # 1) HEX helper doporučení: pokud view vystavuje binární/hash sloupec, doporuč i <col>_hex
    if ($BinaryColumns -and $BinaryColumns.Count -gt 0) {
      foreach ($b in $BinaryColumns) {
        if ($projSet.ContainsKey($b) -and -not $projSet.ContainsKey("${b}_hex")) {
          $warn.Add("$viewName exposes '$b' but not '${b}_hex' (hex helper recommended).")
        }
        if (-not $projSet.ContainsKey($b) -and -not $projSet.ContainsKey("${b}_hex")) {
        $warn.Add("$viewName does not expose '$b' nor '${b}_hex' (consider adding hex helper).")
      }
      }
    }
    # 2) Páry hash/enc -> key_version (jen pokud oba sloupce v tabulce existují)
    if ($PairColumns) {
      foreach ($k in $PairColumns.Keys) {
        $pair = $PairColumns[$k]
        if ($projSet.ContainsKey($k) -and -not $projSet.ContainsKey($pair)) {
          $errs.Add("$viewName exposes '$k' but is missing its key/version column '$pair'.")
        }
      }
    }

    # 3) FK lokální sloupce – je praktické je mít ve view (pro joiny)
    foreach ($fkcol in $FkLocalColumns) {
      if (-not $projSet.ContainsKey($fkcol)) {
        $warn.Add("$viewName does not include FK column '$fkcol' (helpful for joins).")
      }
    }

    # Povinné sloupce + DefaultOrder
    if ($PkColsNorm.Count -gt 0) {
      foreach ($p in $PkColsNorm) {
        if (-not $projSet.ContainsKey($p)) {
          $errs.Add("$viewName is missing required PK column '$p'.")
        }
      }
    }
    if ($SoftDeleteColumn -and -not $projSet.ContainsKey($SoftDeleteColumn.ToLower())) {
      $errs.Add("$viewName is missing soft-delete column '$SoftDeleteColumn'.")
    }
    if ($VersionColumn -and -not $projSet.ContainsKey($VersionColumn.ToLower())) {
      $errs.Add("$viewName is missing version column '$VersionColumn'.")
    }

    if ($DefaultOrder) {
      $orderCols = @([regex]::Matches(
        $DefaultOrder,
        '\b[a-z_][a-z0-9_]*\b',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
      ) | ForEach-Object { $_.Value.ToLower() } | Select-Object -Unique)
      foreach ($oc in $orderCols) {
        if ($TableColumns -contains $oc -and -not $projSet.ContainsKey($oc)) {
          $errs.Add("$viewName does not expose column '$oc' used in DefaultOrder ('$DefaultOrder').")
        }
      }
    }

    foreach ($opt in @('created_at','updated_at')) {
      if ($TableColumns -contains $opt -and -not $projSet.ContainsKey($opt)) {
        $warn.Add("$viewName does not include '$opt' (recommended).")
      }
    }
  }

  if ($errs.Count -gt 0) {
    $msg = "View drift for table '$Table':`n - " + ($errs -join "`n - ")
    if ($FailHard) { throw $msg } else { Write-Error $msg }
  }
  foreach ($w in $warn) { Write-Warning $w }
}

# Vygeneruje PHP metody join*() z definic cizích klíčů.
# - Preferuje $ForeignKeySqls (schema map -> .foreign_keys)
# - Fallback: pokusí se parsovat i přímo z CREATE TABLE (pokud je v seznamu)
function New-JoinMethods {
  param(
    [Parameter(Mandatory=$true)][string]$ThisTable,
    [Parameter(Mandatory=$true)][array]$ForeignKeySqls,
    [Parameter(Mandatory=$true)][hashtable]$LocalNullabilityMap,
    [ValidateSet('left','all','any')][string]$JoinPolicy = 'left'
  )

  $pairs = @()
  foreach ($raw in @($ForeignKeySqls)) {
    if (-not $raw) { continue }
    $text = [string]$raw
    $text = ($text -replace '\s+', ' ')
    $rx1 = [regex]'(?is)FOREIGN\s+KEY\s*\(\s*([^)]+?)\s*\)\s*REFERENCES\s+[`"]?([a-z0-9_]+)[`"]?\s*\(\s*([^)]+?)\s*\)'
    foreach ($m in $rx1.Matches($text)) {
      $localCols = ($m.Groups[1].Value -replace '"','' -replace '`','' -replace '\s','') -split ','
      $refTable  = $m.Groups[2].Value
      $refCols   = ($m.Groups[3].Value -replace '"','' -replace '`','' -replace '\s','') -split ','
      if ($localCols.Count -eq $refCols.Count -and $localCols.Count -gt 0) {
        $pairs += [PSCustomObject]@{ Local=$localCols; RefTable=$refTable; Ref=$refCols }
      }
    }
  }

  if ($pairs.Count -eq 0) { return '' }

  $methods = New-Object System.Collections.Generic.List[string]
  $idx = 0
  $nameCounts = @{}
  foreach ($p in $pairs) {
    $refTable = [string]$p.RefTable
    $refView  = 'vw_' + $refTable
    $baseName = 'join' + (ConvertTo-PascalCase $refTable)
    if ($nameCounts.ContainsKey($baseName)) { $nameCounts[$baseName]++ } else { $nameCounts[$baseName] = 1 }
    $methodName = if ($nameCounts[$baseName] -eq 1) {
        $baseName
    } else {
        $suffix = ($p.Local | ForEach-Object { ConvertTo-PascalCase $_ }) -join 'And'
        $baseName + 'By' + $suffix
    }
    $aliasDefault = 'j' + ($idx)

    # rozhodni JOIN podle JoinPolicy (nejdřív spočti nullability)
    $allNotNull = $true
    $anyNotNull = $false
    foreach ($lc in $p.Local) {
      $isNullable = $true
      if ($LocalNullabilityMap.ContainsKey($lc)) { $isNullable = [bool]$LocalNullabilityMap[$lc] }
      if ($isNullable) { $allNotNull = $false } else { $anyNotNull = $true }
    }
    switch ($JoinPolicy) {
      'all' {
        if ($allNotNull) { $joinKind = 'INNER JOIN' } else { $joinKind = 'LEFT JOIN' }
      }
      'any' {
        if ($anyNotNull) { $joinKind = 'INNER JOIN' } else { $joinKind = 'LEFT JOIN' }
      }
      default { $joinKind = 'LEFT JOIN' }
    }

    # Složení ON podmínky – dvě verze:
    #  - $onVerbose: jen pro log/komentář (obsahuje literály `$as`, `$alias`)
    #  - $onPhp: pro vložení do PHP (konkatenace s proměnnými $as / $alias)
    $onVerboseParts = @()
    $onPhpParts     = @()
    for ($i=0; $i -lt $p.Local.Count; $i++) {
      $lc = $p.Local[$i]
      $rc = $p.Ref[$i]
      # pro log:
      $onVerboseParts += ("`$as.$rc = `$alias.$lc")
      # pro PHP: každý dílek *sám* uzavírá poslední stringovou uvozovku,
      # takže později nemusíme přidávat žádnou koncovou "'"
      $onPhpParts += ("`$as . '." + $rc + " = ' . `$alias . '." + $lc + "'")
    }
    $onVerbose = ($onVerboseParts -join ' AND ')
    $onPhp     = ($onPhpParts -join " . ' AND ' . ")
    # nic neescapujeme — $onPhp je řetězec složený z kousků do PHP konkatenací

    Write-Verbose ("JOIN[{0}] {1} -> {2} (policy={3}; local={4}) ON {5}" -f `
      $ThisTable, $methodName, $joinKind, $JoinPolicy, ($p.Local -join ','), $onVerbose)

    $methods.Add(@"
    /**
     * FK: $($ThisTable) -> $($refTable)
     * $joinKind $refView AS `$as ON $onVerbose
     * @return array{0:string,1:array}
     */
    public function $methodName(string `$alias = 't', string `$as = '$aliasDefault'): array {
        [`$alias, `$as] = `$this->assertAliasPair(`$alias, `$as);
        return [' $joinKind $refView AS ' . `$as . ' ON ' . $onPhp . ' ', []];
    }
"@)
    $idx++
  }

  return ("`n" + ($methods -join "`n") + "`n")
}
function New-AutowireTokens {
  param(
    [string]$BaseNamespace,
    [string]$PackageName,
    [string]$EntityClass,   # např. User
    [string]$ModuleDir,     # ./modules/Users
    [string]$TableName      # např. users
  )

  $imports   = New-Object System.Collections.Generic.List[string]
  $ctorItems = New-Object System.Collections.Generic.List[string]
  $mapLines  = New-Object System.Collections.Generic.List[string]

  # --- default repo odvozený konvencí ---
  $repoFqn   = "$BaseNamespace\$PackageName\Repository\${EntityClass}Repository"
  $repoShort = "${EntityClass}Repository"
  $varName   = ($EntityClass.Substring(0,1).ToLower() + $EntityClass.Substring(1) + 'Repo')

  $imports.Add("use $repoFqn;")
  $ctorItems.Add("private $repoShort `$$varName")
  $mapLines.Add("  '$TableName' => `$this->$varName")

  # --- volitelný override ./repository-wiring.psd1 ---
  $rwPath = Join-Path $ModuleDir 'repository-wiring.psd1'
  if (Test-Path -LiteralPath $rwPath) {
    $rw = Import-PowerShellDataFile -Path $rwPath
    foreach ($r in @($rw.Repositories)) {
      $class = [string]$r.Class
      if (-not $class) { continue }
      $short = ($class -split '\\')[-1]
      $var   = if ($r.VarName) { ($r.VarName -replace '^\$','') } else { ($short.Substring(0,1).ToLower() + $short.Substring(1)) }
      $alias = if ($r.Alias) { [string]$r.Alias } else { $short }

      $imports.Add( $( if ($r.Import) { [string]$r.Import } else { "use $class;" } ) )
      $ctorItems.Add("private $short `$$var")
      $mapLines.Add("  '$alias' => `$this->$var")
    }
  }

  $ctorSuffix = ''
  if ((@($ctorItems)).Count -gt 0) { $ctorSuffix = ', ' + ($ctorItems -join ', ') }

  $repoMap = '[]'
  if ((@($mapLines)).Count -gt 0) {
    $repoMap = "[`n" + ($mapLines -join ",`n") + "`n]"
  }

  [PSCustomObject]@{
    Imports          = ($imports -join "`n")
    CtorParamsSuffix = $ctorSuffix
    RepositoryMap    = $repoMap
  }
}
function Singularize([string]$word) {
  # jednoduchá anglická heuristika – pro názvy jako users, categories, books, payments, ...
  if ($word -match 'ies$') { return ($word -replace 'ies$','y') }
  elseif ($word -match 'sses$') { return ($word -replace 'es$','') }
  elseif ($word -match 's$' -and $word -notmatch '(news|status)$') { return ($word.TrimEnd('s')) }
  return $word
}

function New-Directory([string]$dir) {
  if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
}

# --- SQL parsing & typing ---
# Return: @{ Table='users'; Columns = [ @{Name='id'; SqlType='BIGINT UNSIGNED'; Nullable=$false; Base='BIGINT';}, ... ] }
function ConvertFrom-CreateSql([string]$tableName, [string]$sql) {
  # vyzobneme sekci se sloupci (do prvního řádku, který začíná INDEX|UNIQUE KEY|CONSTRAINT|) ENGINE
  $lines = ($sql -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  # najít začátek seznamu sloupců po "CREATE TABLE ..."
  $startIdx = ($lines | Select-String -Pattern "^\s*CREATE\s+TABLE" -SimpleMatch:$false | Select-Object -First 1).LineNumber
  if (-not $startIdx) { $startIdx = 1 }
  # posbírej řádky mezi první závorkou a indexy/constraints
  $collect = $false; $colLines = @()
  foreach ($ln in $lines) {
    if ($ln -match '^\s*CREATE\s+TABLE') { $collect = $true; continue }
    if (-not $collect) { continue }
    if ($ln -match '^\)\s*ENGINE=') { break }   # MySQL
    if ($ln -match '^\)\s*;')       { break }   # Postgres
    # skip čisté index/constraint řádky
    if ($ln -match '^(INDEX|UNIQUE\s+KEY|CONSTRAINT)\b') { continue }
    $colLines += $ln.Trim().TrimEnd(',')
  }

  $cols = @()

  foreach ($raw in $colLines) {
    # 1) přeskoč zjevné ne-sloupce
    if ($raw -match '^(PRIMARY\s+KEY|UNIQUE\s+KEY|INDEX|CONSTRAINT|CHECK|FOREIGN\s+KEY)\b') { continue }
    if ($raw -match '^(OR|AND)\b') { continue }
    # ignoruj čisté závorkové řádky, kdyby se do colLines přece jen dostaly
    if ($raw -match '^\)$') { continue }
    # 2) zpracuj jen řádky, které vypadají jako "<name> <type>"
    #    => typický SQL datový typ hned po názvu sloupce
    if ($raw -notmatch '^[`"]?[a-z0-9_]+[`"]?\s+(ENUM|SET|DECIMAL|NUMERIC|DOUBLE\s+PRECISION|DOUBLE|FLOAT|REAL|TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|SERIAL|BIGSERIAL|BOOLEAN|JSONB?|UUID|DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME|YEAR|BIT|BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT|CHAR|VARCHAR)\b') {
      continue
    }
    # skip odřádkované indexy v definici (už jsme vyřadili), ale necháme sloupce typu "PRIMARY KEY (id)" — ty nechceme jako sloupce
    if ($raw -match '^(PRIMARY\s+KEY|UNIQUE\s+KEY|INDEX|CONSTRAINT)\b') { continue }

    # typický řádek: "id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY"
    # sloupec může být: `name` VARCHAR(255) NOT NULL DEFAULT 'x'
    if ($raw -match '^[`"]?([a-z0-9_]+)[`"]?\s+(.+)$') {
      $name = $matches[1]
      $rest = $matches[2]

      # SQL typ = první token typu včetně závorek: ENUM('x','y'), DECIMAL(12,2), VARCHAR(255), DATETIME(6), BIGINT UNSIGNED...
      if ($rest -match '^(ENUM|SET|DECIMAL|NUMERIC|DOUBLE\s+PRECISION|DOUBLE|FLOAT|REAL|TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|SERIAL|BIGSERIAL|BOOLEAN|JSONB?|UUID|DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME|YEAR|BIT|BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT|CHAR|VARCHAR)\b([^(]*\([^\)]*\))?(\s+UNSIGNED)?') {
        $base = $matches[1].ToUpper()
        $par  = $matches[2]
        $uns  = $matches[3]
        $sqlType = ($base + ($par ?? '') + ($uns ?? '')).Trim()
      } else {
        # fallback – vezmeme první slovo
        $base = (($rest -split '\s+')[0]).ToUpper()
        $sqlType = $base
      }

      $nullable = $true
      if ($rest -match '\bNOT\s+NULL\b') { $nullable = $false }
      # některé řádky mají explicitně "NULL" -> necháváme $true

      $cols += [PSCustomObject]@{
        Name     = $name
        SqlType  = $sqlType
        Base     = ($base -replace '\s+PRECISION','')
        Nullable = $nullable
      }
    }
  }

  [PSCustomObject]@{
    Table   = $tableName
    Columns = $cols
  }
}

function Get-ColumnClassification($columns) {
  $bool   = @()
  $ints   = @()
  $floats = @()
  $json   = @()
  $dates  = @()
  $bin    = @()
  $nullable = @()

  foreach ($c in $columns) {
    if ($c.Nullable) { $nullable += $c.Name }
    switch -Regex ($c.Base) {
      '^(BOOLEAN|BIT)$'                                               { $bool   += $c.Name; continue }
      '^(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|YEAR|SERIAL|BIGSERIAL)$' { $ints += $c.Name; continue }
      '^(DECIMAL|NUMERIC|DOUBLE|FLOAT|REAL)$'                         { $floats += $c.Name; continue }
      '^(JSON|JSONB)$'                                                { $json   += $c.Name; continue }
      '^(DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME)$'                  { $dates  += $c.Name; continue }
      '^(BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB)$'  { $bin    += $c.Name; continue }
      default { }
    }
  }

  [PSCustomObject]@{
    Bool     = $bool
    Ints     = $ints
    Floats   = $floats
    Json     = $json
    Dates    = $dates
    Binary   = $bin
    Nullable = $nullable
  }
}

function Get-PhpTypeFromSqlBase([string]$base, [bool]$nullable) {
  # rozhodnutí: DECIMAL/NUMERIC -> string (bezpečné pro peníze), ostatní plovoucí -> float
  $t = switch -Regex ($base.ToUpper()) {
    '^(BOOLEAN|BIT)$'                                   { 'bool' ; break }
    '^(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|YEAR|SERIAL|BIGSERIAL)$' { 'int'  ; break }
    '^(DECIMAL|NUMERIC)$'                               { 'string' ; break }
    '^(DOUBLE|FLOAT|REAL)$'                             { 'float' ; break }
    '^JSONB?$'                                          { 'array' ; break }
    '^(DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME)$'      { '\DateTimeImmutable' ; break }
    '^(BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB)$' { 'string' ; break }
    default                                             { 'string' }
  }
  if ($t -eq 'array') {
    if ($nullable) { return 'array|null' } else { return 'array' }
  }
  if ($t -eq '\DateTimeImmutable') {
    if ($nullable) { return '?\DateTimeImmutable' } else { return '\DateTimeImmutable' }
  }
  if ($nullable -and $t -ne 'array' -and $t -ne 'array|null') {
    return ("?{0}" -f $t)
  } else {
    return $t
  }
}

function New-DtoConstructorParameters($columns) {
  # generuj v pořadí sloupců; public readonly <type> $prop,
  $parts = @()
  foreach ($c in $columns) {
    $prop = ConvertTo-CamelCase $c.Name
    $phpType = Get-PhpTypeFromSqlBase $c.Base $c.Nullable
    $parts += ('public readonly {0} ${1}' -f $phpType, $prop)
  }
  # formát s odsazením a čárkami
  return ($parts -join ",`n        ")
}

function New-ColumnPropertyMap($columns) {
  $pairs = @()
  foreach ($c in $columns) {
    $prop = ConvertTo-CamelCase $c.Name
    if ($prop -ne $c.Name) {
      $pairs += ("'{0}' => '{1}'" -f $c.Name, $prop)
    }
  }
  if (-not $pairs -or (@($pairs)).Count -eq 0) { return '[]' }
  return "[ " + ($pairs -join ', ') + " ]"
}

function ConvertTo-PhpArray([string[]]$arr) {
  if (-not $arr -or $arr.Count -eq 0) { return '[]' }
  $q = $arr | ForEach-Object { "'{0}'" -f $_ }
  "[ " + ($q -join ', ') + " ]"
}

function Expand-Template {
  param(
    [string]$Content,
    [hashtable]$TokenValues
  )
  $out = $Content
  foreach ($k in $TokenValues.Keys) {
    $marker = "[[$k]]"
    $val    = [string]$TokenValues[$k]  # může obsahovat $, \, cokoli
    # LITERÁLNÍ nahrazení – žádné regexy, žádné backreference
    $out = $out.Replace($marker, $val)
  }
  return $out
}

function Test-TemplateTokens([string]$content) {
  $m = [regex]::Matches($content, '\[\[([A-Z0-9_]+)\]\]')
  $uniq = @{}
  foreach ($x in $m) { $uniq[$x.Groups[1].Value] = $true }
  return @($uniq.Keys)
}

# -----------------------
# Main
# -----------------------
function Get-TablesFromFromJoin([string]$sql) {
  if (-not $sql) { return @() }
  $out = New-Object System.Collections.Generic.List[string]

  # IGNORE table-functions jako json_table(...), inet6_ntoa(...), unnest(...):
  # přidaný (?!\s*\() zajistí, že po zachyceném identifikátoru nesmí ihned následovat "("
  $rx = [regex]'(?is)\b(?:FROM|JOIN(?:\s+LATERAL)?)\s+(?:ONLY\s+)?(?<ref>(?:"[^"]+"|`[^`]+`|[A-Za-z0-9_]+)(?:\.(?:"[^"]+"|`[^`]+`|[A-Za-z0-9_]+))*)(?!\s*\()'

  foreach ($m in $rx.Matches($sql)) {
    $ref   = $m.Groups['ref'].Value
    $parts = $ref -split '\.'
    $last  = $parts[$parts.Length - 1]
    $name  = ($last -replace '^[`"]|[`"]$','')    # ořízni uvozovky/backtick
    $name  = ($name -replace '^(vw_|v_)','')      # vw_* → tabulka
    if ($name) { $out.Add($name.ToLower()) }
  }
  @($out | Select-Object -Unique)
}

function Resolve-ViewDependencies([string]$table, [hashtable]$views, [hashtable]$memo) {
  # vrací množinu tabulek, které view pro $table (přímo/nepřímo) používá
  if (-not $views -or -not $views.Views -or -not $views.Views.ContainsKey($table)) { return @() }
  if ($memo.ContainsKey($table)) { return @() }
  $memo[$table] = $true

  $sql = [string]$views.Views[$table].create
  $direct = @( Get-TablesFromFromJoin $sql )

  $acc = New-Object System.Collections.Generic.List[string]
  foreach ($t in $direct) {
    if ($t -ne $table) { $acc.Add($t) }
    # pokud existuje i view pro $t, jdi do rekurze (transitivní závislosti)
    if ($views.Views.ContainsKey($t)) {
      foreach ($x in (Resolve-ViewDependencies $t $views $memo)) { $acc.Add($x) }
    }
  }
  @($acc | Select-Object -Unique)
}

$templates = @( Get-Templates -Root $TemplatesRoot )
# Pro volitelnou kontrolu submodulů (.gitmodules)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$subSet   = Get-SubmodulePathSet -repoRoot $repoRoot

# Vyber mapy: explicitní -MapPath nebo autodetekce v -SchemaDir
$mapPaths = @()
if ($MapPath) {
  # vynucené pole i pro jedinou cestu
  $mapPaths = @($MapPath)
} else {
  if (-not (Test-Path -LiteralPath $SchemaDir)) { throw "Schema dir not found: '$SchemaDir'." }

  # Získej FileInfo[], pak teprve převáděj na stringy
  $allItems = @(Get-ChildItem -LiteralPath $SchemaDir -Filter 'schema-map-*.psd1' -File)
  if (-not $allItems -or $allItems.Count -eq 0) {
    throw "No schema maps found under '$SchemaDir' (pattern 'schema-map-*.psd1')."
  }

  $pgItems  = @($allItems | Where-Object { $_.Name -match 'postgres' })
  $myItems  = @($allItems | Where-Object { $_.Name -match 'mysql' })
  $othItems = @($allItems | Where-Object { $_.Name -notmatch 'mysql|postgres' })

  # Teď si připrav čisté stringové cesty
  $pgPaths  = @($pgItems  | Select-Object -ExpandProperty FullName)
  $myPaths  = @($myItems  | Select-Object -ExpandProperty FullName)
  $othPaths = @($othItems | Select-Object -ExpandProperty FullName)

  switch ($EnginePreference) {
    'postgres' { $mapPaths = @($pgPaths + $othPaths) }
    'mysql'    { $mapPaths = @($myPaths + $othPaths) }
    'both'     { $mapPaths = @($pgPaths + $myPaths + $othPaths) }
    default {
      # auto: preferuj PG, jinak MySQL
      $prefer = if (@($pgPaths).Count -gt 0) { $pgPaths } else { $myPaths }
      $mapPaths = @($prefer + $othPaths)
    }
  }
}

# Odstranění nul, duplicit a neexistujících cest (pro jistotu)
$mapPaths = @($mapPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

if (-not $mapPaths -or $mapPaths.Count -eq 0) { throw "No schema maps selected." }

Write-Host "Selected maps ($($mapPaths.Count)):" -ForegroundColor Cyan
$mapPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkCyan }

# --- Views map (optional; autodetect when not provided)
if (-not $ViewsPath) {
  # Pokud není ViewsDir předán nebo neexistuje, použij SchemaDir
  $dirToSearch = $SchemaDir
  if ($PSBoundParameters.ContainsKey('ViewsDir') -and (Test-Path -LiteralPath $ViewsDir)) {
    $dirToSearch = $ViewsDir
  }

  if (Test-Path -LiteralPath $dirToSearch) {
    # Podporuj oba patterny: views-map-* i schema-views-*
    $allV = @(Get-ChildItem -LiteralPath $dirToSearch -File | Where-Object {
      $_.Name -match '^(views-map-|schema-views-).+\.psd1$'
    })
    if ($allV.Count -gt 0) {
      $pgV = @($allV | Where-Object { $_.Name -match 'postgres' } | Select-Object -First 1)
      $myV = @($allV | Where-Object { $_.Name -match 'mysql' }   | Select-Object -First 1)
      switch ($EnginePreference) {
        'postgres' { if ($pgV) { $ViewsPath = $pgV.FullName } elseif ($myV) { $ViewsPath = $myV.FullName } }
        'mysql'    { if ($myV) { $ViewsPath = $myV.FullName } elseif ($pgV) { $ViewsPath = $pgV.FullName } }
        default    { if ($pgV) { $ViewsPath = $pgV.FullName } elseif ($myV) { $ViewsPath = $myV.FullName } }
      }
    }
  }
}

$views = $null
if ($ViewsPath) {
  $views = Import-ViewsMap -Path $ViewsPath
  Write-Host "Loaded views map: $ViewsPath" -ForegroundColor Cyan
} else {
  Write-Warning "No views map found (looking for 'views-map-*.psd1' or 'schema-views-*.psd1'). View drift checks will throw for missing views."
}

# Fail policy: default = hard fail; allow overriding by -FailOnViewDrift switch if explicitly passed false in future (kept for compatibility)
$FailHardOnViewDrift = $true
if ($PSBoundParameters.ContainsKey('FailOnViewDrift')) {
  $FailHardOnViewDrift = [bool]$FailOnViewDrift
}

foreach ($mp in $mapPaths) {
  $schema  = Import-SchemaMap -Path $mp
  if (-not $schema.Tables) { Write-Warning "No 'Tables' in schema map: $mp"; continue }
  $mapLeaf = Split-Path -Leaf $mp
  Write-Host "Loaded '$mapLeaf' with $($schema.Tables.Keys.Count) tables. Templates: $($templates.Count)." -ForegroundColor Cyan

  # iterace přes tabulky
  $tables = $schema.Tables.GetEnumerator() | Sort-Object Key
  foreach ($entry in $tables) {
  $table = [string]$entry.Key                             # např. users
  $spec  = $entry.Value
  $createSql = [string]$spec.create

  $parsed = ConvertFrom-CreateSql -tableName $table -sql $createSql
  $cols   = @($parsed.Columns)

  # Mapa nullability lokálních sloupců (name => $true pokud nullable, $false pokud NOT NULL)
  $nullMap = @{}
  foreach ($c in $cols) { $nullMap[$c.Name] = [bool]$c.Nullable }

  if ((@($cols)).Count -eq 0) { Write-Warning "No columns parsed for table '$table'."; continue }

  $classInfo = Get-ColumnClassification -columns $cols
  $binaryCols = @($classInfo.Binary | ForEach-Object { $_.ToLower() })
  $packagePascal = ConvertTo-PascalCase $table                      # Users, UserIdentities, OrderItems...
  $entityPascal  = ConvertTo-PascalCase (Singularize $table)        # User, UserIdentity, OrderItem...
  $dtoClass      = "$($entityPascal)Dto"
  $namespace     = "$BaseNamespace\$packagePascal"
  # dopočti si názvy
  $moduleClass = "${packagePascal}Module"
  $joinsClass  = "${packagePascal}Joins"
  # slož tokeny společné pro většinu šablon
  $tokenCommon = [ordered]@{
    'NAMESPACE'              = $namespace
    'DTO_CLASS'              = $dtoClass
    'TIMEZONE'               = $Timezone
    'DATABASE_FQN'           = $DatabaseFQN
    'COLUMNS_TO_PROPS_MAP'   = (New-ColumnPropertyMap $cols)
    'BOOL_COLUMNS_ARRAY'     = (ConvertTo-PhpArray $classInfo.Bool)
    'INT_COLUMNS_ARRAY'      = (ConvertTo-PhpArray $classInfo.Ints)
    'FLOAT_COLUMNS_ARRAY'    = (ConvertTo-PhpArray $classInfo.Floats)
    'JSON_COLUMNS_ARRAY'     = (ConvertTo-PhpArray $classInfo.Json)
    'DATE_COLUMNS_ARRAY'     = (ConvertTo-PhpArray $classInfo.Dates)
    'BINARY_COLUMNS_ARRAY'   = (ConvertTo-PhpArray $classInfo.Binary)
    'NULLABLE_COLUMNS_ARRAY' = (ConvertTo-PhpArray $classInfo.Nullable)
    'DTO_CTOR_PARAMS'        = (New-DtoConstructorParameters $cols)
    'SERVICE_CLASS'          = "$($packagePascal)AggregateService"
    'USES_ARRAY'             = @(
                                  "use $DatabaseFQN;",
                                  "use $namespace\Dto\$dtoClass;",
                                  "use $namespace\Mapper\${dtoClass}Mapper;"
                                ) -join "`n"
    'CTOR_PARAMS'            = 'private Database $db'  # lze dál rozšiřovat generátorem (repo atd.)
    'TABLE_NAME'             = $table
    'ENTITY_CLASS'           = $entityPascal
    'PACKAGE_NAME'           = $packagePascal
    'AGGREGATE_METHODS'      = ''
  }
  # Aliasy sloupců pro vstupní řádky (API), např. k->setting_key, value->setting_value
  $aliasMap = @{}
  if ($spec -is [hashtable] -and $spec.ContainsKey('Aliases')) {
    foreach ($ak in $spec.Aliases.Keys) {
      $aliasMap[[string]$ak] = [string]$spec.Aliases[$ak]
    }
  }
  $tokenCommon['PARAM_ALIASES_ARRAY'] = ConvertTo-PhpAssoc $aliasMap
    # ---- doplňkové tokeny pro všechny šablony ----
    # seznam názvů sloupců
    $colNames = @($cols | ForEach-Object { $_.Name })
    # připrav páry pouze pokud obě pole v tabulce existují
    $tcLower = @{}; foreach ($n in $colNames) { $tcLower[$n.ToLower()] = $true }
    $pairMap = @{}
    $knownPairs = @(
      @{ a='email_hash';             b='email_hash_key_version' },
      @{ a='ip_hash';                b='ip_hash_key_version' },
      @{ a='last_login_ip_hash';     b='last_login_ip_key_version' },
      @{ a='token_hash';             b='token_hash_key_version' },
      @{ a='download_token_hash';    b='token_key_version' },
      @{ a='unsubscribe_token_hash'; b='unsubscribe_token_key_version' },
      @{ a='confirm_validator_hash'; b='confirm_key_version' }
    )
    foreach ($p in $knownPairs) {
      if ($tcLower.ContainsKey($p.a) -and $tcLower.ContainsKey($p.b)) { $pairMap[$p.a] = $p.b }
    }

    # heuristiky:
    $hasCreatedAt = $colNames -contains 'created_at'
    $hasUpdatedAt = $colNames -contains 'updated_at'
    $hasDeletedAt = $colNames -contains 'deleted_at'

    # PK: preferuj 'id', jinak první sloupec
    $pk = ($colNames | Where-Object { $_ -eq 'id' } | Select-Object -First 1)
    if (-not $pk) { $pk = $colNames[0] }
    # --- PK strategy (identity|uuid|natural|composite) ---

    # --- PK combos z CREATE ---
    $pkCombos = @( Get-PrimaryKeyCombosFromCreateSql -CreateSql $createSql )

    [string[]]$pkCols = @()
    if ($pkCombos.Count -gt 0) {
      # první kombinace → zajisti čisté string[]
      $pkCols = @($pkCombos[0] | ForEach-Object { [string]$_ })
    }

    # pro další logiku (DefaultOrder apod.) si nech 1. sloupec PK
    if ($pkCols.Count -gt 0) { $pk = $pkCols[0] }

    # Auto-increment heuristiky (MySQL i PG identity)
    $autoId = $false
    if ($createSql -match '(?im)^\s*id\s+[^\r\n]*\bAUTO_INCREMENT\b') { $autoId = $true }
    if ($createSql -match '(?im)GENERATED\s+(ALWAYS|BY\s+DEFAULT)\s+AS\s+IDENTITY') { $autoId = $true }
    if ($createSql -match '(?im)\bSERIAL\b')                           { $autoId = $true }

    # Typ PK sloupce pro uuid variace
    $pkCol = ($cols | Where-Object { $_.Name -eq $pk } | Select-Object -First 1)
    $looksUuid =
      ($pkCol -and (
        $pkCol.SqlType -match 'CHAR\(\s*36\)' -or
        $pkCol.SqlType -match 'BINARY\(\s*16\)' -or
        $pkCol.Base    -match '^UUID$'
      ))

    if ($pkCols.Count -gt 1) {
      $pkStrategy = 'composite'
    } elseif ($autoId) {
      $pkStrategy = 'identity'
    } elseif ($looksUuid -or $pk -match '^(uuid|uuid_bin)$') {
      $pkStrategy = 'uuid'
    } else {
      $pkStrategy = 'natural'
    }

    $tokenCommon['PK_STRATEGY'] = $pkStrategy

    # Připrav FK SQL (použijeme i CREATE TABLE jako fallback) – potřebujeme už teď
    $fkSqls = @()
    $fkSqls += @($spec.foreign_keys | Where-Object { $_ })
    $fkSqls += @($createSql) # fallback parsing inline

    # --- isRowLockSafe (pro testy a ukázky) ---
    $hasLarge  = @($cols | Where-Object { $_.Base -match '(BLOB|JSONB?)$' }).Count -gt 0
    $tooWide  = $cols.Count -gt 20

    # které FK sloupce jsou lokálně povinné?
    $fkLocalCols    = @( Get-FkLocalColumnsFromSql $fkSqls )
    $hasRequiredFk  = $false
    foreach ($lc in $fkLocalCols) {
      if ($nullMap.ContainsKey($lc) -and (-not [bool]$nullMap[$lc])) { $hasRequiredFk = $true; break }
    }

    # Safe: identity PK + žádné povinné FK; toleruj nullable FK. Stále filtruj extrémní šířku/large typy.
    $rowLockSafe = ($pkStrategy -eq 'identity') -and (-not $hasRequiredFk) -and (-not $hasLarge) -and (-not $tooWide)

    # Volitelný whitelist – chceš mít jistotu, že něco je true
    if ($table -in @('authors','users')) { $rowLockSafe = $true }

    $tokenCommon['IS_ROWLOCK_SAFE'] = if ($rowLockSafe) { 'true' } else { 'false' }

    # výchozí ORDER
    if ($hasCreatedAt) {
      $idOrPk = if ($colNames -contains 'id') { 'id' } else { $pk }
      $defaultOrder = "created_at DESC, $idOrPk DESC"
    } elseif ($colNames -contains 'id') {
      $defaultOrder = 'id DESC'
    } else {
      $defaultOrder = "$pk DESC"
    }

    # textové sloupce pro vyhledávání (LIKE)
    $textCols = @($cols | Where-Object {
        $_.Base -match '^(CHAR|VARCHAR|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT)$'
    } | ForEach-Object { $_.Name })

    # --- derive dependencies from foreign keys (spec + inline in CREATE TABLE) ---
    function Get-ReferencedTablesFromFkSqls([array]$fkSqls) {
      $out = New-Object System.Collections.Generic.List[string]
      foreach ($fk in @($fkSqls)) {
        if (-not $fk) { continue }
        foreach ($m in [regex]::Matches([string]$fk, '(?is)REFERENCES\s+[`"]?([a-z0-9_]+)[`"]?')) {
          $t = $m.Groups[1].Value.ToLower()
          if ($t) { $out.Add($t) }
        }
      }
      @($out | Select-Object -Unique)
    }

    $fkSqlsAll = @()
    $fkSqlsAll += @($spec.foreign_keys)  # z mapy
    $fkSqlsAll += @($createSql)          # fallback: inline FK v CREATE TABLE

    $depTablesFk = @( Get-ReferencedTablesFromFkSqls $fkSqlsAll )
    $depTablesFk = @($depTablesFk | Where-Object { $_ -and $_ -ne $table })

    $depNames = @($depTablesFk | ForEach-Object { "table-$_" } | Sort-Object -Unique)

    # doplň tokeny:
    $tokenCommon['TABLE']                   = $table
    $tokenCommon['VIEW']                    = "vw_${table}"
    $tokenCommon['COLUMNS_ARRAY']           = (ConvertTo-PhpArray $colNames)
    # [[PK]] může být "id" nebo "col1, col2" (pro Definitions::pkColumns)
    if ($pkCols.Count -gt 1) {
      $tokenCommon['PK'] = ($pkCols -join ', ')
    } else {
      $tokenCommon['PK'] = $pk
    }
    $tokenCommon['SOFT_DELETE_COLUMN']      = ($hasDeletedAt ? 'deleted_at' : '')
    $tokenCommon['UPDATED_AT_COLUMN']       = ($hasUpdatedAt ? 'updated_at' : '')
    $verName = ''
    if ($spec -is [hashtable] -and $spec.ContainsKey('VersionColumn')) {
      $verName = [string]$spec.VersionColumn
    } elseif ($colNames -contains 'version') {
      $verName = 'version'
    }
    $tokenCommon['VERSION_COLUMN'] = $verName
    $tokenCommon['DEFAULT_ORDER_CLAUSE']    = $defaultOrder
    # --- VIEW DRIFT CHECK ---
    $softCol = if ($hasDeletedAt) { 'deleted_at' } else { '' }

    # Zkontroluj, že všechny referenced tabulky mají view
    if ($views) {
      Assert-ReferencedViews -Table $table -ForeignKeySqls $fkSqls -ViewsMap $views -FailHard:$FailHardOnViewDrift
    }

    # Získat lokální FK sloupce pro varování ve view
    $fkLocalCols = @( Get-FkLocalColumnsFromSql $fkSqls )

    Assert-TableVsView `
      -Table $table `
      -TableColumns ($colNames | ForEach-Object { $_.ToLower() }) `
      -Pk $pkCols `
      -VersionColumn $verName `
      -SoftDeleteColumn $softCol `
      -DefaultOrder $defaultOrder `
      -ViewsMap $views `
      -BinaryColumns $binaryCols `
      -PairColumns $pairMap `
      -FkLocalColumns $fkLocalCols `
      -FailHard:$FailHardOnViewDrift

    $tokenCommon['UNIQUE_KEYS_ARRAY']       = '[]'                    # prozatím prázdné
    # JSON_COLUMNS_ARRAY už máš
    $tokenCommon['FILTERABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $colNames)
    $tokenCommon['SEARCHABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $textCols)
    $tokenCommon['DEFAULT_PER_PAGE']        = '50'
    $tokenCommon['MAX_PER_PAGE']            = '500'
    $tokenCommon['VERSION']                 = '1.0.0'
    $tokenCommon['DIALECTS_ARRAY']          = "[ 'mysql', 'postgres' ]"
    # INDEX/FK names ze schéma mapy (pokud k dispozici)
    $idxNames = Get-IndexNamesFromSql       @($spec.indexes)
    $fkNames  = Get-ForeignKeyNamesFromSql  @($spec.foreign_keys)
    $tokenCommon['INDEX_NAMES_ARRAY'] = if (@($idxNames).Count -gt 0) {
      "[ " + (($idxNames | ForEach-Object { "'$_'" }) -join ', ') + " ]"
    } else { '[]' }

    $tokenCommon['FK_NAMES_ARRAY'] = if (@($fkNames).Count -gt 0) {
      "[ " + (($fkNames | ForEach-Object { "'$_'" }) -join ', ') + " ]"
    } else { '[]' }

    # ---- UPSERT (robustně – klíč může chybět) ----
    $ukeys = @()
    $uupd  = @()
    $up    = $null

    if ($spec -is [hashtable] -and $spec.ContainsKey('Upsert')) {
      $up = $spec['Upsert']
    } elseif ($spec.PSObject -and $spec.PSObject.Properties.Match('Upsert').Count -gt 0) {
      # fallback, kdyby to náhodou nebyl čistý hashtable
      $up = $spec.Upsert
    }

    if ($null -ne $up) {
      if ($up -is [hashtable]) {
        $ukeys = @($up['Keys'])
        $uupd  = @($up['Update'])
      } else {
        # Toleruj zjednodušený zápis: Upsert = 'email' / @('email')
        $ukeys = @($up)
      }
    }

    $ukeysQuoted = @($ukeys | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { "'$_'" })
    $uupdQuoted  = @($uupd  | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { "'$_'" })

    $tokenCommon['UPSERT_KEYS_ARRAY'] = if (@($ukeysQuoted).Count -gt 0) {
      "[ " + ($ukeysQuoted -join ', ') + " ]"
    } else { '[]' }

    $tokenCommon['UPSERT_UPDATE_COLUMNS_ARRAY'] = if (@($uupdQuoted).Count -gt 0) {
      "[ " + ($uupdQuoted -join ', ') + " ]"
    } else { '[]' }

    # ---- UNIQUE kombinace: z indexů, z CREATE TABLE (UNIQUE) a ze VŠECH PK ----
    $uniqueCombos = New-Object System.Collections.Generic.List[object]

    # 1) CREATE UNIQUE INDEX ve $spec.indexes
    foreach ($ix in @($spec.indexes)) {
      if ($ix -match '(?i)CREATE\s+UNIQUE\s+INDEX\s+[^\(]+\(\s*([A-Za-z0-9_,"\s`]+)\s*\)') {
        $cols = ($matches[1] -replace '[`"\s]','') -split ','
        if ($cols -and $cols.Count -gt 0) { $uniqueCombos.Add(@($cols)) }
      }
    }

    # 2) table-level UNIQUE v CREATE TABLE
    foreach ($combo in (Get-UniqueCombosFromCreateSql -CreateSql $createSql)) {
      $normalized = @($combo | ForEach-Object { ($_ -replace '[`"\s]','').ToLower() })
      if ($normalized.Count -gt 0) { $uniqueCombos.Add($normalized) }
    }

    # 3) VŠECHNY PK kombinace jako UNIQUE
    foreach ($pkCombo in (Get-PrimaryKeyCombosFromCreateSql -CreateSql $createSql)) {
      $normalized = @($pkCombo | ForEach-Object { ($_ -replace '[`"\s]','').ToLower() })
      if ($normalized.Count -gt 0) { $uniqueCombos.Add($normalized) }
    }

    # deduplikace kombinací
    $seen = @{}
    $uniqueCombos = @($uniqueCombos | Where-Object {
      $k = ($_ -join '#')
      if ($seen.ContainsKey($k)) { $false } else { $seen[$k] = $true; $true }
    })

    # Render pro token [[UNIQUE_KEYS_ARRAY]]
    if (@($uniqueCombos).Count -gt 0) {
      $render = @()
      foreach ($arr in $uniqueCombos) {
        $render += "[ " + (($arr | ForEach-Object { "'$_'" }) -join ', ') + " ]"
      }
      $tokenCommon['UNIQUE_KEYS_ARRAY'] = "[ " + ($render -join ', ') + " ]"
    } else {
      $tokenCommon['UNIQUE_KEYS_ARRAY'] = '[]'
    }

    # Kontrola konzistence UPSERT proti unikátním kombinacím
    Assert-UpsertConsistency `
      -Table $table `
      -UpsertKeys $ukeys `
      -UpsertUpdateCols $uupd `
      -UniqueCombos $uniqueCombos `
      -UpdatedAtCol $tokenCommon['UPDATED_AT_COLUMN']

    # Urči JoinPolicy z přepínačů (explicítní -JoinPolicy má prioritu; pak legacy aliasy)
    if ($PSBoundParameters.ContainsKey('JoinPolicy') -and ($JoinAsInner -or $JoinAsInnerStrict)) {
      Write-Warning "Předány i legacy přepínače (-JoinAsInner*). Ignoruji je a použiji -JoinPolicy '$JoinPolicy'."
    }
    $joinPolicy = if ($PSBoundParameters.ContainsKey('JoinPolicy')) {
      $JoinPolicy
    } elseif ($JoinAsInnerStrict) {
      'any'
    } elseif ($JoinAsInner) {
      'all'
    } else {
      'left'
    }

    $tokenCommon['JOIN_METHODS'] = New-JoinMethods `
        -ThisTable $table `
        -ForeignKeySqls $fkSqls `
        -LocalNullabilityMap $nullMap `
        -JoinPolicy $joinPolicy
    # --- augment deps by tables referenced in our view(s) ---
    $depTablesView = @()
    if ($views -and $views.Views -and $views.Views.ContainsKey($table)) {
      $depTablesView = @( Resolve-ViewDependencies $table $views (@{}) )

      # ber jen tabulky, které v tomhle schéma mapu opravdu existují
      $knownTables = @($schema.Tables.Keys | ForEach-Object { $_.ToLower() })
      $depTablesView = @(
        $depTablesView |
        Where-Object { $_ -and $_ -ne $table -and ($knownTables -contains $_) }
      )
    }

    $depNames = @(
      $depNames +
      ($depTablesView | ForEach-Object { "table-$_" })
    ) | Sort-Object -Unique
    foreach ($t in $depTablesView) {
      # pokud neexistuje cílový balíček pro tabulku $t, připomeň to vygenerátorovi
      $p = Resolve-PackagePath -PackagesDir $ModulesRoot -Table $t -PackagePascal (ConvertTo-PascalCase $t) -Mode $NameResolution
      if (-not $p) { Write-Warning "View for '$table' references '$t' but the package for '$t' was not found under '$ModulesRoot'." }
    }
    $tokenCommon['DEPENDENCIES_ARRAY'] = (ConvertTo-PhpArray $depNames)


    # výstupní adresář EXISTUJÍCÍHO balíčku (submodulu) – hledej pascal/snake/kebab
    $moduleDir = Resolve-PackagePath -PackagesDir $ModulesRoot `
                                    -Table $table `
                                    -PackagePascal $packagePascal `
                                    -Mode $NameResolution

    if (-not $moduleDir) {
    $kebab = ($table -replace '_','-')
    throw "Nenalezen cílový balíček pro tabulku '$table'. Hledáno (mode=$NameResolution) v '$ModulesRoot': Pascal='$packagePascal', Snake='$table', Kebab='$kebab'."
    }

    # volitelně vyžaduj, aby cíl byl skutečný submodul (.gitmodules)
    if ($StrictSubmodules) {
    $repoRootResolved = (Resolve-Path -LiteralPath $repoRoot).Path
    $dirResolved      = (Resolve-Path -LiteralPath $moduleDir).Path
    $rel = $dirResolved.Substring($repoRootResolved.Length).TrimStart('\','/').Replace('\','/')
    if (-not $subSet.ContainsKey($rel)) {
        throw "Cíl '$rel' není zapsán v .gitmodules (zapni submodul nebo vypni -StrictSubmodules)."
    }
    }

    # uvnitř balíčku si klidně tvoř podadresáře (src atd.), ale NEzakládej nový balíček
    New-Directory (Join-Path $moduleDir 'src')

    # --- AUTOWIRE: doplň importy repozitářů a parametr(y) konstruktoru ---
    $auto = New-AutowireTokens -BaseNamespace $BaseNamespace `
                            -PackageName   $packagePascal `
                            -EntityClass   $entityPascal `
                            -ModuleDir     $moduleDir `
                            -TableName     $table

  # USES_ARRAY u tebe drží řádky "use ...;" → rozšiř o repo importy
  $tokenCommon['USES_ARRAY']  = ($tokenCommon['USES_ARRAY'] + "`n" + $auto.Imports).Trim()

  # CTOR_PARAMS je property promotion → přidej ", private XxxRepository $xxxRepo"
  $tokenCommon['CTOR_PARAMS'] = ($tokenCommon['CTOR_PARAMS'] + $auto.CtorParamsSuffix)

  # Volitelné: pokud máš někde [[REPOSITORY_MAP]], naplníme ho
  $tokenCommon['REPOSITORY_MAP'] = $auto.RepositoryMap

  foreach ($tpl in $templates) {
    $relPath = $tpl.File
    # nahradíme případné tokeny i v názvu souboru (např. [[DTO_CLASS]])
    $relPath = $relPath.Replace('[[DTO_CLASS]]',     $dtoClass)
    $relPath = $relPath.Replace('[[SERVICE_CLASS]]', $tokenCommon['SERVICE_CLASS'])
    $relPath = $relPath.Replace('[[PACKAGE_NAME]]',  $packagePascal)
    $relPath = $relPath.Replace('[[ENTITY_CLASS]]',  $entityPascal)
    # Vyřeš [[CLASS]] i v názvu souboru
    if ($relPath -like '*[[CLASS]]*') {
    $classForPath = ($tpl.File -match '(^|/|\\)Joins(/|\\)') ? $joinsClass : $moduleClass
    $relPath = $relPath.Replace('[[CLASS]]', $classForPath)
    }

    $outPath = Join-Path $moduleDir $relPath
    New-Directory (Split-Path -Parent $outPath)

    # vyber jen ty tokeny, které šablona očekává
    $tokensForThis = @{}

    # 1) speciální tokeny, které nejsou v $tokenCommon
    if ($tpl.Tokens -contains 'CLASS') {
    $tokensForThis['CLASS'] = ($tpl.File -match '(^|/|\\)Joins(/|\\)') ? $joinsClass : $moduleClass
    }

    # 2) běžné tokeny z $tokenCommon
    foreach ($tk in $tpl.Tokens) {
    if ($tokenCommon.Contains($tk)) {
        $tokensForThis[$tk] = $tokenCommon[$tk]
    }
    elseif ($tokensForThis.ContainsKey($tk)) {
        # už naplněno výše (např. CLASS) – ok
    }
    elseif (-not $AllowUnresolved) {
        Write-Error "Template '$($tpl.Name)' expects token '$tk' not provided by generator (table '$table'). Use -AllowUnresolved to bypass."
        continue
    }
    }

    # render
    $rendered = Expand-Template -content $tpl.Content -tokenValues $tokensForThis

    # kontrola nezpracovaných [[TOKENŮ]]
    $unresolved = Test-TemplateTokens -content $rendered
    if ((@($unresolved)).Count -gt 0 -and -not $AllowUnresolved) {      $list = $unresolved -join ', '
      throw "Unresolved tokens in '$($tpl.Name)' for table '$table': $list"
    }

    if ((Test-Path $outPath) -and -not $Force -and -not $WhatIf) {
      throw "File '$outPath' exists. Use -Force to overwrite."
    }

    if ($WhatIf) {
      Write-Host "[WhatIf] -> would write $outPath" -ForegroundColor DarkYellow
    } else {
      $rendered | Out-File -FilePath $outPath -Encoding UTF8 -Force
      Write-Host "Wrote: $outPath" -ForegroundColor Green
    }
  }
  }
}
try {
  Stop-IfNeeded -RepoRoot $repoRoot
  Write-Host "Done." -ForegroundColor Cyan
  exit 0
} catch {
  Write-Error $_
  if ($_.ScriptStackTrace) { Write-Error $_.ScriptStackTrace }
  exit 1
}
