[CmdletBinding(PositionalBinding=$true)]
param(
  # Catch stray positional arguments (e.g., accidental "+") before binding errors
  [Parameter(ValueFromRemainingArguments=$true, Position=0)]
  [string[]]$ExtraArgs,

  [Alias('Map','MapFile')]
  [string]$MapPath,                           # optional; defaults to autodetect inside -SchemaDir
  [string]$SchemaDir = "./schema",            # where to look for schema-map files
  [ValidateSet('auto','postgres','mysql','both')]
  [string]$EnginePreference = 'both',

  [Parameter(Mandatory=$true)]
  [string]$TemplatesRoot,                     # ./templates/php (contains the *.yaml templates)

  [string]$ModulesRoot = "./packages",        # root of package submodules (e.g., users -> ./packages/users)
  [ValidateSet('detect','snake','kebab','pascal')]
  [string]$NameResolution = 'kebab',          # default is kebab only
  [switch]$StrictSubmodules,                  # require the target to be listed in .gitmodules

  [string]$BaseNamespace = "BlackCat\Database\Packages", # base namespace token
  [string]$DatabaseFQN = "BlackCat\Core\Database",
  [string]$Timezone = "UTC",
  # Views (optional) – otherwise autodetect views-map under $ViewsDir/$SchemaDir
  [string]$ViewsPath,
  [string]$ViewsDir = "./schema",
  [switch]$FailOnViewDrift,                   # without it, the script still fails when drift is found (see below)
  [switch]$Force,
  [switch]$WhatIf,
  [switch]$AllowUnresolved,                   # for work-in-progress templates, temporarily allow unresolved tokens
  [switch]$JoinAsInner,                       # (legacy) alias for JoinPolicy 'all'
  [switch]$JoinAsInnerStrict,                 # (legacy) alias for JoinPolicy 'any'
  [ValidateSet('left','all','any')]
  [string]$JoinPolicy = 'left',               # explicit FK JOIN policy (left|all|any)

  # === NEW: strict mode and stale-pattern checks ===
  [switch]$TreatWarningsAsErrors,             # warnings count as failures (non-zero exit)
  [switch]$FailOnStale,                       # after generation, scan the repo and fail if stale patterns remain
  [string[]]$StalePatterns = @(
    '(?i)""\s*\.\s*\$order',                  # empty "" + concatenation + $order (classic string glue)
    '(?i)"\s*ORDER\s*(BY)?\s*"\s*\.\s*\$order',
    '(?i)\(\s*\$order\s*\?\s*"?\s*ORDER\s*(BY)?\s*"?\s*\.\s*\$order',
    '(?i)\bSELECT\s+\*\s+FROM\b',                  # undesired SELECT *
    '(?i)\border\s+by\s*"\s*\.\s*\$order\b',       # another glued ORDER BY variant
    '(?i)\bLIMIT\s*"\s*\.\s*\$limit\b',            # glued LIMIT
    '(?i)\bWHERE\s+1\s*=\s*1\b',                  # "where 1=1" – typical glue
    '(?i)\bAND\s+1\s*=\s*1\b',                    # same idea as above
    '(?i)\bINSERT\s+INTO\b.*\(\s*\)\s*VALUES',    # empty column list
    '(?i)\bstring_agg\s*\(\s*\*\s*,',             # aggregating with a star
    '(?i)\bGROUP\s+BY\s*"\s*\.\s*\$[a-z_]+\b'     # glued GROUP BY
  )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# --- Warning counter ---
$script:WarnCount = 0
$script:WarnMessages = New-Object System.Collections.Generic.List[string]
function Write-Warning {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position=0, ValueFromPipeline)]
    [string]$Message
  )
  $script:WarnCount++
  if ($Message) { $script:WarnMessages.Add($Message) }
  Microsoft.PowerShell.Utility\Write-Warning @PSBoundParameters
}
# --- Fail policy helpers (new) ---
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

$script:SchemaExt = '.yaml'

function Stop-IfNeeded {
  param([string]$RepoRoot)
  Write-Host ("Warnings emitted: {0}" -f $script:WarnCount) -ForegroundColor Yellow
  if ($script:WarnMessages.Count -gt 0) {
    $summary = @($script:WarnMessages | Group-Object | Sort-Object Count -Descending)
    Write-Host ("Warnings summary (unique: {0})" -f $summary.Count) -ForegroundColor Yellow
    $maxShow = 15
    $shown = 0
    foreach ($grp in $summary) {
      Write-Host ("  • {0} [x{1}]" -f $grp.Name, $grp.Count) -ForegroundColor DarkYellow
      $shown++
      if ($shown -ge $maxShow) { break }
    }
    if ($summary.Count -gt $maxShow) {
      $remaining = $summary.Count - $maxShow
      Write-Host ("  … plus {0} more unique warning(s)." -f $remaining) -ForegroundColor DarkYellow
    }
  }

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
function Get-PhpParamTypeForColumn($col) {
  # force non-null parameter type
  $t = Get-PhpTypeFromSqlBase $col.Base $false
  $t = ($t -replace '^\?','')
  if ($t -eq '\DateTimeImmutable') { return '\DateTimeInterface|string' }
  if ($t -match '^array') { return 'array' }
  return $t
}

function New-UniqueHelpers {
  param(
    [Parameter(Mandatory)][string[][]]$UniqueCombos,
    [Parameter(Mandatory)][hashtable]  $ColumnMap,
    [string[]]$PkCols = @(),
    [string[]]$ColNames = @(),
    [string]$TableName = ''
  )

  $colMap = $ColumnMap
  $out = New-Object System.Collections.Generic.List[string]

  foreach ($combo in $UniqueCombos) {
    if (-not $combo -or $combo.Count -eq 0) { continue }
    # Skip helpers that would collide with built-ins (e.g., PK = id already has getById/existsById)
    if ($PkCols -and $PkCols.Count -eq 1 -and $combo.Count -eq 1) {
      if ($combo[0].ToLower() -eq $PkCols[0].ToLower()) { continue }
    }
    $namesPascal = @($combo | ForEach-Object { ConvertTo-PascalCase $_ })
    $namesCamel  = @(
      $combo | ForEach-Object {
        $v = ConvertTo-CamelCase $_
        if ($v -match '^[^A-Za-z_]') { $v = 'c' + $v } # ensure valid PHP variable name
        return $v
      }
    )
    $suffix = ($namesPascal -join 'And')

    $paramDecl = New-Object System.Collections.Generic.List[string]
    $assocKvs  = New-Object System.Collections.Generic.List[string]
    $whereParts= New-Object System.Collections.Generic.List[string]
    $bindPairs = New-Object System.Collections.Generic.List[string]

    for ($i=0; $i -lt $combo.Count; $i++) {
      $col = $combo[$i].ToLower()
      $var = $namesCamel[$i]
      $tp  = 'mixed'
    if ($colMap.ContainsKey($col)) { $tp = Get-PhpParamTypeForColumn $colMap[$col] }
      $paramDecl.Add("$tp `$$var")
      $assocKvs.Add("'$col' => `$$var")
      $bindPairs.Add("'uniq_$col' => `$$var")
      $whereParts.Add("'t.' . Ident::q(`$this->db, '$col') . ' = :uniq_$col'")
    }

    $paramList = ($paramDecl -join ', ')
    $assocPhp  = '[ ' + ($assocKvs -join ', ') + ' ]'
    $wherePhp  = ($whereParts -join " . ' AND ' . ")
    $bindPhp   = '[ ' + ($bindPairs -join ', ') + ' ]'

    $out.Add(@"
    /** @return array<string,mixed>|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null */
    public function getBy$suffix($paramList, bool `$asDto = false): array|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null {
        return `$this->getByUnique($assocPhp, `$asDto);
    }
"@)

    $out.Add(@"
    public function existsBy$suffix($paramList): bool {
        `$where = $wherePhp;
        return `$this->exists(`$where, $bindPhp);
    }
"@)

    if ($PkCols -and $PkCols.Count -eq 1) {
      $pk = $PkCols[0]
      $argsJoined = '$' + ($namesCamel -join ', $')
      $out.Add(@"
    /** @return int|string|null */
    public function getIdBy$suffix($paramList) {
        `$row = `$this->getBy$suffix($argsJoined, false);
        if (!is_array(`$row)) { return null; }
        return `$row['$pk'] ?? null;
    }
"@)
    }
  }

  if ($out.Count -eq 0) { return '' }
  return ("`n" + ($out -join "`n") + "`n")
}

function New-CriteriaHelpers {
  param(
    [Parameter(Mandatory)][string[]]$ColNames,
    [string[]]$PkCols = @()
  )

  $set = @{}; foreach ($c in $ColNames) { $set[$c.ToLower()] = $true }
  $out = New-Object System.Collections.Generic.List[string]

  if ($PkCols -and $PkCols.Count -eq 1) {
    $pk = $PkCols[0]
    $out.Add(@"
    public function byId(int|string `$id): static {
        return `$this->where('$pk', '=', `$id);
    }
    public function byIds(array `$ids): static {
        if (!`$ids) return `$this->whereRaw('1=0');
        return `$this->where('$pk', 'IN', array_values(`$ids));
    }
"@)
  } elseif ($PkCols -and $PkCols.Count -gt 1) {
    $parts = @()
    foreach ($k in $PkCols) { $parts += "$k = :cid_$k" }
    $where = [string]::Join(' AND ', $parts)
    $out.Add(@"
    /** @param array<string,mixed> `$id */
    public function byId(array `$id): self {
        return `$this->whereRaw('$where', array_combine(
            array_map(fn(\$k) => 'cid_' . \$k, array_keys(`$id)),
            array_values(`$id)
        ));
    }
"@)
  }

  if ($set.ContainsKey('status')) {
    $out.Add(@"
    /** @param string|array<int,string> `$status */
    public function byStatus(string|array `$status): static {
        if (is_array(`$status)) { return `$this->where('status', 'IN', `$status); }
        return `$this->where('status', '=', `$status);
    }
"@)
  }

  if ($set.ContainsKey('tenant_id')) {
    $out.Add(@"
    /** @param int|string|array<int,int|string> `$tenantId */
    public function forTenant(int|string|array `$tenantId): static {
        if (is_array(`$tenantId)) { return `$this->where('tenant_id', 'IN', `$tenantId); }
        return `$this->where('tenant_id', '=', `$tenantId);
    }
"@)
  }

  if ($set.ContainsKey('created_at')) {
    $out.Add(@"
    public function createdBetween(?\DateTimeInterface `$from, ?\DateTimeInterface `$to): static {
        return `$this->between('created_at', `$from, `$to);
    }
"@)
  }
  if ($set.ContainsKey('updated_at')) {
    $out.Add(@"
    public function updatedSince(\DateTimeInterface `$ts): static {
        return `$this->where('updated_at', '>=', `$ts);
    }
"@)
  }

  if ($set.ContainsKey('deleted_at')) {
    $out.Add(@"
    public function withTrashed(bool `$on = true): static { return parent::withTrashed(`$on); }
    public function onlyTrashed(bool `$on = true): static { return parent::onlyTrashed(`$on); }
"@)
  }

  foreach ($spec in @(
    @{col='slug';  name='Slug';  type='string'},
    @{col='code';  name='Code';  type='string'},
    @{col='uuid';  name='Uuid';  type='string'},
    @{col='uuid_bin'; name='UuidBin'; type='string'}
  )) {
    if ($set.ContainsKey($spec.col)) {
      $out.Add(@"
    public function by$($spec.name)($($spec.type) `$$($spec.col)): static {
        return `$this->whereRaw('$($spec.col) = :c_$($spec.col)', ['c_$($spec.col)' => `$$($spec.col)]);
    }
"@)
    }
  }

  if ($out.Count -eq 0) { return '' }
  return ("`n" + ($out -join "`n") + "`n")
}

function New-TenancyRepoHelpers {
  param(
    [string[]]$ColNames = @(),
    [string[]]$PkCols = @()
  )
  $hasTenant = $ColNames -contains 'tenant_id'
  if (-not $hasTenant) { return '' }

  $getByIdSig =
    if ($PkCols -and $PkCols.Count -eq 1) {
      @"
    /** @return array<string,mixed>|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null */
    public function getByIdForTenant(int|string `$id, int|string `$tenantId, bool `$asDto = false): array|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null {
        return `$this->getByUnique(['id' => `$id, 'tenant_id' => `$tenantId], `$asDto);
    }
"@
    } else { '' }

  $existsForTenant = @"
    public function existsForTenant(array `$where, int|string `$tenantId): bool {
        `$w = `$where; `$w['tenant_id'] = `$tenantId;
        `$parts = []; `$params = [];
        foreach (`$w as `$k => `$v) {
            `$col = 't.' . Ident::q(`$this->db, (string)`$k);
            if (`$v === null) {
                `$parts[] = `$col . ' IS NULL';
            } else {
                `$parts[] = `$col . ' = :x_' . `$k;
                `$params['x_' . `$k] = `$v;
            }
        }
        return `$this->exists(implode(' AND ', `$parts), `$params);
    }
"@

  return "`n$getByIdSig`n$existsForTenant`n"
}

function New-StatusTransitionHelper {
  param([string]$TransitionsPhp = '[]')
  if ($TransitionsPhp -eq '[]') { return '' }
  return @"
    public function updateStatus(int|string `$id, string `$new, ?string `$old = null): void {
        `$allowed = \[[NAMESPACE]]\Definitions::STATUS_TRANSITIONS;
        if (`$old === null) {
            `$row = `$this->getById(`$id);
            if (!`$row) { throw new \[[NAMESPACE]]\ModuleException('Not found'); }
            `$old = (string)(`$row['status'] ?? '');
        }
        if (!isset(`$allowed[`$old]) || !in_array(`$new, `$allowed[`$old], true)) {
            throw new \[[NAMESPACE]]\ValidationException('Transition ' . `$old . ' → ' . `$new . ' not allowed');
        }
        `$this->updateById(`$id, ['status' => `$new]);
    }
"@
}

function Split-ByCommaOutsideParens([string]$s) {
  $out=@(); $buf=''; $depth=0; $q=$null
  for ($i=0; $i -lt $s.Length; $i++) {
    $ch = $s[$i]
    if ($q) {                      # inside quotes
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

  # deduplicate case-insensitively and keep column order
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

  # Table-level UNIQUE and UNIQUE KEY/INDEX (original section)
  $pattern = '(?isx)
    (?:CONSTRAINT \s+ [`"]? [A-Za-z0-9_]+ [`"]? \s+ )?        # optional constraint name
    UNIQUE \s* (?:KEY|INDEX)? \s*                             # UNIQUE / UNIQUE KEY / UNIQUE INDEX
    (?:IF \s+ NOT \s+ EXISTS \s+)?                            # optional IF NOT EXISTS
    (?: [`"]? [A-Za-z0-9_]+ [`"]? \s* )?                      # optional index name
    (?:ON \s+ [^\(]+ )?                                       # optional ON <table>
    \(\s* ([^)]+?) \s*\)                                      # column list in parentheses
  '
  foreach ($m in [regex]::Matches($CreateSql, $pattern)) {
    $cols = ($m.Groups[1].Value -replace '[`"\s]','') -split ','
    if ($cols -and $cols.Count -gt 0) { $combos += ,$cols }
  }

  # *** NEW ***: in-line UNIQUE on a column
  # e.g.:   name VARCHAR(100) NOT NULL UNIQUE,
  foreach ($m in [regex]::Matches($CreateSql, '(?im)^(?!\s*CONSTRAINT\b)\s*[`"]?([a-z0-9_]+)[`"]?\s+[^,\r\n]*?\bUNIQUE\b(?!\s+(?:KEY|INDEX)\b).*?(?:,|$)')) {
    $col = $m.Groups[1].Value
    if ($col) { $combos += ,@($col) }
  }

  # Drop combos that contain expressions/invalid identifiers (e.g., COALESCE(...))
  $filtered = @()
  foreach ($combo in $combos) {
    if (-not $combo) { continue }
    $valid = $true
    foreach ($c in $combo) {
      if (-not ($c -match '^[a-z0-9_]+$')) { $valid = $false; break }
    }
    if ($valid) { $filtered += ,$combo }
  }

  return ,$filtered
}

function Get-GeneratedColumnsFromCreateSql {
  param([string]$CreateSql)

  if (-not $CreateSql) { return @() }
  $cols = @()
  foreach ($m in [regex]::Matches($CreateSql, '(?im)^\s*[`"]?([a-z0-9_]+)[`"]?\s+[^,\r\n]*\bGENERATED\s+ALWAYS\b')) {
    $c = $m.Groups[1].Value
    if ($c -and $c -match '^[a-z0-9_]+$') { $cols += $c.ToLower() }
  }
  # dedupe
  return @($cols | Select-Object -Unique)
}
function Assert-UpsertConsistency {
  param(
    [string]$Table,
    [string[]]$UpsertKeys,
    [string[]]$UpsertUpdateCols,
    [string[][]]$UniqueCombos,
    [string]$SoftDeleteColumn
  )
  if (-not $UpsertKeys -or $UpsertKeys.Count -eq 0) { return }
  $keys = @($UpsertKeys | Where-Object { $_ } | ForEach-Object { $_.ToLower() } | Sort-Object -Unique)
  $allowedExtras = @()
  if ($SoftDeleteColumn) {
    $allowedExtras += $SoftDeleteColumn.ToLower()
    $allowedExtras += 'is_live'
  }
  $match = $false
  foreach ($combo in @($UniqueCombos)) {
    $c = @($combo | Where-Object { $_ } | ForEach-Object { $_.ToLower() } | Sort-Object -Unique)
    if ($c.Count -eq 0) { continue }
    $allPresent = $true
    foreach ($key in $keys) {
      if (-not ($c -contains $key)) { $allPresent = $false; break }
    }
    if (-not $allPresent) { continue }
    $extras = @($c | Where-Object { $keys -notcontains $_ })
    if ($extras.Count -eq 0) { $match = $true; break }
    $extraOk = $true
    foreach ($extra in $extras) {
      if (-not ($allowedExtras -contains $extra)) { $extraOk = $false; break }
    }
    if ($extraOk) { $match = $true; break }
  }
  if (-not $match) {
    Write-Warning "Table '$Table' Upsert.Keys = [$($keys -join ', ')] does not match any UNIQUE index/PK."
  }
  foreach ($k in $keys) {
    if ($UpsertUpdateCols -and ($UpsertUpdateCols | ForEach-Object { $_.ToLower() }) -contains $k) {
      Write-Warning "Table '$Table' Upsert.Update contains key column '$k' – usually undesired."
    }
  }
}

function Test-TypeEquivalent {
  param(
    [string]$PgType,
    [string]$MyType
  )
  $pgNorm = Convert-TypeToken $PgType
  $myNorm = Convert-TypeToken $MyType
  if ($pgNorm -eq $myNorm) { return $true }
  if (($pgNorm -like 'TIMESTAMPTZ*' -or $pgNorm -like 'TIMESTAMP*') -and $myNorm -like 'DATETIME*') { return $true }
  if ($pgNorm -like 'DATETIME*' -and ($myNorm -like 'TIMESTAMPTZ*' -or $myNorm -like 'TIMESTAMP*')) { return $true }
  if (($pgNorm -like 'JSONB*' -and $myNorm -like 'JSON*') -or ($pgNorm -like 'JSON*' -and $myNorm -like 'JSONB*')) { return $true }
  if (($pgNorm -like 'INTERVAL*' -and $myNorm -like 'TEXT*') -or ($pgNorm -like 'TEXT*' -and $myNorm -like 'INTERVAL*')) { return $true }
  return $false
}

function Convert-TypeToken {
  param([string]$Type)
  if (-not $Type) { return '' }
  $t = $Type.ToUpper().Trim()
  $t = ($t -replace '\s+UNSIGNED','')
  $t = ($t -replace '\s+SIGNED','')
  if ($t -match '^TINYINT\(\s*1\s*\)$') { return 'BOOL' }
  if ($t -eq '') { return '' }
  switch -regex ($t) {
    'CHAR\(\s*36\s*\)'        { return 'UUID' }
    'UUID'                    { return 'UUID' }
    'TIMESTAMPTZ|TIMESTAMP' { return 'TIMESTAMP' }
    'DATETIME'              { return 'TIMESTAMP' }
    '\bDATE\b'              { return 'DATE' }
    'JSONB?|JSON'           { return 'JSON' }
    'INTERVAL'              { return 'INTERVAL' }
    'BYTEA|VARBINARY|BINARY|BLOB' { return 'BINARY' }
    'TINYINT'               { return 'SMALLINT' }
    'SMALLINT'              { return 'SMALLINT' }
    'ENUM\('                { return 'TEXT' }
    'SET\('                 { return 'TEXT' }
    'LONGTEXT|MEDIUMTEXT|TINYTEXT|TEXT' { return 'TEXT' }
    'CHAR\(|VARCHAR'        { return 'TEXT' }
    '\bUUID\b'              { return 'UUID' }
    'CHAR\(\s*36\s*\)'      { return 'UUID' }
    'BIGINT'                { return 'BIGINT' }
    'BIGSERIAL'             { return 'BIGINT' }
    'SERIAL'                { return 'INT' }
    'SMALLINT'              { return 'SMALLINT' }
    'TINYINT'               { return 'TINYINT' }
    'MEDIUMINT'             { return 'INT' }
    '\bINT(?:EGER)?'        { return 'INT' }
    'NUMERIC|DECIMAL'       { return 'DECIMAL' }
    'DOUBLE|REAL|FLOAT'     { return 'FLOAT' }
    'BOOLEAN|BOOL'          { return 'BOOL' }
    default                 { return (($t -split '\s+')[0]) }
  }
}

function Test-SchemaParity {
  param([hashtable]$Snapshots)

  if (-not $Snapshots) { return }
  $pgKey = 'postgres'
  $myKey = 'mysql'
  if (-not ($Snapshots.ContainsKey($pgKey) -and $Snapshots.ContainsKey($myKey))) { return }

  $pgMeta = $Snapshots[$pgKey]
  $myMeta = $Snapshots[$myKey]
  if (-not ($pgMeta -and $myMeta)) { return }

  $pgTables = $pgMeta.Tables
  $myTables = $myMeta.Tables
  if (-not ($pgTables -and $myTables)) { return }

  $pgPath = $pgMeta.Path
  $myPath = $myMeta.Path
  Write-Host ("Schema parity check: comparing Postgres ({0}) vs MySQL ({1})." -f $pgPath, $myPath) -ForegroundColor Cyan

  $issues = 0
  $allTables = @(($pgTables.Keys + $myTables.Keys) | Sort-Object -Unique)
  foreach ($table in $allTables) {
    if (-not $pgTables.ContainsKey($table)) {
      Write-Warning "Schema parity: table '$table' missing from Postgres map."
      $issues++
      continue
    }
    if (-not $myTables.ContainsKey($table)) {
      Write-Warning "Schema parity: table '$table' missing from MySQL map."
      $issues++
      continue
    }

    $pgInfo = $pgTables[$table]
    $myInfo = $myTables[$table]

    # normalize collections
    $pgCols = @()
    $myCols = @()
    if ($pgInfo -and $pgInfo.Columns) {
      foreach ($col in @($pgInfo.Columns)) {
        if ($null -ne $col) { $pgCols += $col }
      }
    }
    if ($myInfo -and $myInfo.Columns) {
      foreach ($col in @($myInfo.Columns)) {
        if ($null -ne $col) { $myCols += $col }
      }
    }
    if ($null -eq $pgCols) { $pgCols = @() }
    if ($null -eq $myCols) { $myCols = @() }

    # compare column presence/order
    $refCols = @()
    $diffCols = @()
    if ($pgCols) { $refCols += @($pgCols) }
    if ($myCols) { $diffCols += @($myCols) }
    $colDiff = @()
    if ((@($refCols)).Count -gt 0 -or (@($diffCols)).Count -gt 0) {
      $colDiff = Compare-Object -ReferenceObject $refCols -DifferenceObject $diffCols
    }
    if (@($colDiff).Count -gt 0) {
      $pgOnly = @(
        $colDiff | Where-Object { $_.SideIndicator -eq '<=' } | ForEach-Object { $_.InputObject }
      )
      $myOnly = @(
        $colDiff | Where-Object { $_.SideIndicator -eq '=>' } | ForEach-Object { $_.InputObject }
      )
      $msg = "Schema parity: column mismatch in '$table'"
      if (@($pgOnly).Count -gt 0) { $msg += ("; Postgres-only: [{0}]" -f ($pgOnly -join ', ')) }
      if (@($myOnly).Count -gt 0) { $msg += ("; MySQL-only: [{0}]" -f ($myOnly -join ', ')) }
      Write-Warning $msg
      $issues++
    } elseif ((@($pgInfo.Columns) -join ',') -ne (@($myInfo.Columns) -join ',')) {
      Write-Warning "Schema parity: column order differs for '$table'."
      $issues++
    }

    # compare column type/nullability for shared columns
    $pgDetail = @{}
    $myDetail = @{}
    if ($pgInfo -and $pgInfo.ColumnDetail -and $pgInfo.ColumnDetail -is [System.Collections.IDictionary]) {
      $pgDetail = $pgInfo.ColumnDetail
    }
    if ($myInfo -and $myInfo.ColumnDetail -and $myInfo.ColumnDetail -is [System.Collections.IDictionary]) {
      $myDetail = $myInfo.ColumnDetail
    }
    $colNames = @(($pgDetail.Keys + $myDetail.Keys) | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($col in $colNames) {
      if (-not ($pgDetail.ContainsKey($col) -and $myDetail.ContainsKey($col))) { continue }
      $pgCol = $pgDetail[$col]
      $myCol = $myDetail[$col]
      $pgType = ([string]$pgCol.Type).ToUpper()
      $myType = ([string]$myCol.Type).ToUpper()
      if (-not (Test-TypeEquivalent -PgType $pgType -MyType $myType)) {
        Write-Warning "Schema parity: column '$table.$col' type mismatch (PG=$pgType, MySQL=$myType)."
        $issues++
      }
      if ([bool]$pgCol.Nullable -ne [bool]$myCol.Nullable) {
        Write-Warning "Schema parity: column '$table.$col' NULLability mismatch."
        $issues++
      }
    }

    # compare upsert metadata
    $normalize = { param($arr)
      @( $arr | Where-Object { $_ } | ForEach-Object { $_.ToLower() } | Sort-Object -Unique )
    }
    $pgKeys = & $normalize $pgInfo.UpsertKeys
    $myKeys = & $normalize $myInfo.UpsertKeys
    if ($null -eq $pgKeys) { $pgKeys = @() }
    if ($null -eq $myKeys) { $myKeys = @() }
    $keysDiff = @()
    if ((@($pgKeys)).Count -gt 0 -or (@($myKeys)).Count -gt 0) {
      $keysDiff = Compare-Object -ReferenceObject $pgKeys -DifferenceObject $myKeys
    }
    if (@($keysDiff).Count -gt 0) {
      Write-Warning ("Schema parity: Upsert.Keys differ for '{0}' (PG=[{1}] vs MySQL=[{2}])." -f $table, ($pgKeys -join ', '), ($myKeys -join ', '))
      $issues++
    }
    $pgUpd = & $normalize $pgInfo.UpsertUpdate
    $myUpd = & $normalize $myInfo.UpsertUpdate
    if ($null -eq $pgUpd) { $pgUpd = @() }
    if ($null -eq $myUpd) { $myUpd = @() }
    $updDiff = @()
    if ((@($pgUpd)).Count -gt 0 -or (@($myUpd)).Count -gt 0) {
      $updDiff = Compare-Object -ReferenceObject $pgUpd -DifferenceObject $myUpd
    }
    if (@($updDiff).Count -gt 0) {
      Write-Warning ("Schema parity: Upsert.Update differs for '{0}' (PG=[{1}] vs MySQL=[{2}])." -f $table, ($pgUpd -join ', '), ($myUpd -join ', '))
      $issues++
    }

    $pgSoft = [string]$pgInfo.SoftDelete
    $mySoft = [string]$myInfo.SoftDelete
    if ($pgSoft -ne $mySoft) {
      Write-Warning "Schema parity: soft-delete column mismatch for '$table' (PG='$pgSoft', MySQL='$mySoft')."
      $issues++
    }

    $pgVer = [string]$pgInfo.Version
    $myVer = [string]$myInfo.Version
    if ($pgVer -ne $myVer) {
      Write-Warning "Schema parity: version column mismatch for '$table' (PG='$pgVer', MySQL='$myVer')."
      $issues++
    }
  }

  if ($issues -gt 0) {
    Write-Warning "Schema parity check detected $issues issue(s) between Postgres and MySQL maps."
  } else {
    Write-Host "Schema parity check: no discrepancies detected across $($allTables.Count) tables." -ForegroundColor Green
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

function Assert-ViewAlgorithms {
  param(
    [Parameter(Mandatory)][hashtable]$ViewsMap,
    [Parameter(Mandatory)][string]$Path
  )
  if (-not $ViewsMap -or -not $ViewsMap.Views) { return }
  $engine = Get-EngineTag $Path
  foreach ($kv in $ViewsMap.Views.GetEnumerator()) {
    $name = [string]$kv.Key
    $ddl  = Get-CreateText $kv.Value
    if (-not $ddl) { continue }

    if ($engine -eq 'postgres') { continue } # Postgres does not use ALGORITHM
    if ($ddl -notmatch '(?i)ALGORITHM\s*=\s*([A-Z]+)') {
      throw "View '$name' in '$Path' is missing ALGORITHM=MERGE|TEMPTABLE."
    }
    $alg = $Matches[1].ToUpperInvariant()
    if ($alg -ne 'MERGE' -and $alg -ne 'TEMPTABLE') {
      throw "View '$name' in '$Path' uses unsupported ALGORITHM='$alg' (expected MERGE or TEMPTABLE)."
    }
  }
}

function Import-SchemaMap([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Schema map not found at '$Path'." }
  $map = Import-YamlFile -Path $Path
  ConvertTo-HashtableDeep $map
}
function Import-ViewsMap([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Views map not found at '$Path'." }
  $data = Import-YamlFile -Path $Path
  $data = ConvertTo-HashtableDeep $data
  Assert-ViewAlgorithms -ViewsMap $data -Path $Path
  $data
}

function Get-Templates([string]$Root) {
  if (-not (Test-Path $Root)) { throw "TemplatesRoot '$Root' not found." }
  $files = Get-ChildItem -LiteralPath $Root -Filter '*.yaml' -Recurse
  if (-not $files) { throw "No .yaml templates found under '$Root'." }
  foreach ($f in $files) {
    $t = Import-YamlFile -Path $f.FullName
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
function Get-EngineTag([string]$path) {
  $leaf = Split-Path -Leaf $path
  if ($leaf -match 'mysql')    { return 'mysql' }
  if ($leaf -match 'postgres') { return 'postgres' }
  return 'default'
}
function Import-YamlFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "YAML file not found: $Path" }
  # Prefer native ConvertFrom-Yaml (PS7+); accept any module providing it (e.g., powershell-yaml).
  $null = Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
  $cfy = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
  if (-not $cfy) {
    $msg = @'
ConvertFrom-Yaml not available (requires PowerShell 7+ with Microsoft.PowerShell.Utility). Install a YAML parser, e.g.:
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default }; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name powershell-yaml -Scope CurrentUser -Force
'@
    throw $msg
  }
  try {
    return Get-Content -LiteralPath $Path -Raw | & $cfy
  } catch {
    throw "Failed to parse YAML '$Path' via ConvertFrom-Yaml: $($_.Exception.Message)"
  }
}

function ConvertTo-PhpAssoc([hashtable]$ht) {
  if (-not $ht -or $ht.Keys.Count -eq 0) { return '[]' }
  $pairs = New-Object System.Collections.Generic.List[string]
  foreach ($k in ($ht.Keys | Sort-Object)) {
    $v = [string]$ht[$k]
    $v = $v -replace "'", "\\'"
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
function Get-CreateText {
  param($Value)
  function Extract($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [string]) { return $Obj }
    if ($Obj -is [System.Collections.IDictionary]) {
      if ($Obj.Contains('create')) { return Extract $Obj['create'] }
      if ($Obj.PSObject -and $Obj.PSObject.Properties['create']) { return Extract $Obj.create }
      foreach ($v in $Obj.Values) { $r = Extract $v; if ($r) { return $r } }
      return ($Obj.Values | ForEach-Object { [string]$_ }) -join "`n"
    }
    if ($Obj -and $Obj.PSObject) {
      if ($Obj.PSObject.Properties['create']) { return Extract $Obj.create }
      foreach ($p in $Obj.PSObject.Properties) { $r = Extract $p.Value; if ($r) { return $r } }
    }
    if ($Obj -is [System.Collections.IEnumerable] -and -not ($Obj -is [string])) {
      $parts = @()
      foreach ($item in $Obj) { $r = Extract $item; if ($r) { $parts += $r } }
      if ($parts.Count -gt 0) { return ($parts -join "`n") }
    }
    return [string]$Obj
  }
  return [string](Extract $Value)
}
function ConvertTo-HashtableDeep {
  param($InputObject)
  if ($InputObject -is [ValueType] -or $InputObject -is [string]) { return $InputObject }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $ht = @{}
    foreach ($k in $InputObject.Keys) { $ht[$k] = ConvertTo-HashtableDeep $InputObject[$k] }
    return $ht
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    return @($InputObject | ForEach-Object { ConvertTo-HashtableDeep $_ })
  }
  if ($InputObject -and $InputObject.PSObject) {
    $ht = @{}
    foreach ($p in $InputObject.PSObject.Properties) { $ht[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $ht
  }
  return $InputObject
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
    [Parameter(Mandatory)][string]$Table,          # snake_case table name
    [Parameter(Mandatory)][string]$PackagePascal,  # PascalCase variant (e.g., BookAssets)
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

  # 1) quick star detection – SELECT t.* / *
  $mStar = [regex]::Match($viewSql, '(?is)\bSELECT\b\s+(?:DISTINCT(?:\s+ON\s*\([^)]+\))?\s+)?(.*?)\bFROM\b')
  if ($mStar.Success) {
    $seg = $mStar.Groups[1].Value
    if ($seg -match '(^|\s)([A-Za-z0-9_]+)\.\*\s*(,|$)' -or $seg -match '(^|\s)\*\s*(,|$)') {
      # let the caller (Assert-TableVsView) decide – returning empty triggers the fallback
      return @()
    }
  }

  # --- original logic (trimmed and simplified) ---
  $m2 = [regex]::Match($viewSql, '(?is)\bSELECT\b\s+(?:DISTINCT(?:\s+ON\s*\([^)]+\))?\s+)?(.*?)\bFROM\b')
  if (-not $m2.Success) { return @() }
  $segment = $m2.Groups[1].Value
  $segment = ($segment -replace '(?s)/\*.*?\*/','' -replace '--[^\r\n]*','') -replace '\s+',' '

  $out = New-Object System.Collections.Generic.List[string]
  foreach ($piece in (Split-ByCommaOutsideParens $segment)) {
    $part = $piece.Trim()
    if ($part -eq '') { continue }
    if ($part -match '(?i)\bAS\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*$') {
      $out.Add($matches[1].ToLower()); continue
    }
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
    $viewSql = Get-CreateText $ViewsMap.Views[$Table]
  } else {
    $errs.Add("Missing view SQL for '$Table' (expected $viewName).")
  }

  if ($viewSql) {
    $usesSelectStar = Test-SelectStar $viewSql
    # Prepare the set of projected columns first
    $proj = @( Get-ProjectionColumnsFromViewSql $viewSql )
    if ($usesSelectStar -and $proj.Count -eq 0) {
      $warn.Add("$viewName uses 'SELECT *' (explicit column list recommended).")
    }
    $projSet = @{}
    foreach ($c in $proj) { $projSet[$c] = $true }

    # 1) HEX helper recommendation: when the view exposes a binary/hash column, also expose <col>_hex
    if ($BinaryColumns -and $BinaryColumns.Count -gt 0) {
      foreach ($b in $BinaryColumns) {
        if ($projSet.ContainsKey($b) -and -not $projSet.ContainsKey("${b}_hex")) {
          $warn.Add("$viewName exposes '$b' but not '${b}_hex' (hex helper recommended).")
        }
        if ($projSet.ContainsKey("${b}_hex") -and -not $projSet.ContainsKey($b)) {
          $warn.Add("$viewName exposes '${b}_hex' but not '$b' (raw column recommended).")
        }
        if (-not $projSet.ContainsKey($b) -and -not $projSet.ContainsKey("${b}_hex")) {
          $warn.Add("$viewName does not expose '$b' nor '${b}_hex' (consider adding hex helper).")
        }
      }
    }
    # 2) Hash/encrypted pairs -> key_version (only if both columns exist on the table)
    if ($PairColumns) {
      foreach ($k in $PairColumns.Keys) {
        $pair = $PairColumns[$k]
        if ($projSet.ContainsKey($k) -and -not $projSet.ContainsKey($pair)) {
          $errs.Add("$viewName exposes '$k' but is missing its key/version column '$pair'.")
        }
      }
    }

    # 3) FK local columns – helpful to keep them in the view for joins
    foreach ($fkcol in $FkLocalColumns) {
      if (-not $projSet.ContainsKey($fkcol)) {
        $warn.Add("$viewName does not include FK column '$fkcol' (helpful for joins).")
      }
    }

    # Required columns + DefaultOrder
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

# Generate PHP join*() methods from foreign key definitions.
# - Prefer $ForeignKeySqls (schema map -> .foreign_keys)
# - Fallback: attempt to parse CREATE TABLE when listed
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
    $methodName = $baseName
    if ($nameCounts[$baseName] -ne 1) {
      $suffix = ($p.Local | ForEach-Object { ConvertTo-PascalCase $_ }) -join 'And'
      $methodName = $baseName + 'By' + $suffix
    }
    $aliasDefault = 'j' + ($idx)

    # decide the JOIN type per JoinPolicy (first compute nullability)
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

    # Build the ON condition in two variants:
    #  - $onVerbose: for logs/comments (contains the literal `$as` / `$alias`)
    #  - $onPhp: embeddable into PHP (concatenates with $as / $alias variables)
    $onVerboseParts = @()
    $onPhpParts     = @()
    for ($i=0; $i -lt $p.Local.Count; $i++) {
      $lc = $p.Local[$i]
      $rc = $p.Ref[$i]
      # for logging:
      $onVerboseParts += ("`$as.$rc = `$alias.$lc")
      # for PHP: each fragment closes the string quote on its own,
      # so we do not need to append a trailing "'"
      $onPhpParts += ("`$as . '." + $rc + " = ' . `$alias . '." + $lc + "'")
    }
    $onVerbose = ($onVerboseParts -join ' AND ')
    $onPhp     = ($onPhpParts -join " . ' AND ' . ")
    # no escaping needed — $onPhp already consists of concatenated PHP fragments

    Write-Verbose ("JOIN[{0}] {1} -> {2} (policy={3}; local={4}) ON {5}" -f `
      $ThisTable, $methodName, $joinKind, $JoinPolicy, ($p.Local -join ','), $onVerbose)

    $methods.Add(@"
    /**
     * FK: $($ThisTable) -> $($refTable)
     * $joinKind $refView AS `$as ON $onVerbose
     * @return array{0:string,1:array<string,mixed>}
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
    [string]$EntityClass,   # e.g., User
    [string]$ModuleDir,     # ./modules/Users
    [string]$TableName      # e.g., users
  )

  $imports   = New-Object System.Collections.Generic.List[string]
  $ctorItems = New-Object System.Collections.Generic.List[string]
  $mapLines  = New-Object System.Collections.Generic.List[string]

  # --- default repository derived from convention ---
  $repoFqn   = "$BaseNamespace\$PackageName\Repository\${EntityClass}Repository"
  $repoShort = "${EntityClass}Repository"
  $varName   = ($EntityClass.Substring(0,1).ToLower() + $EntityClass.Substring(1) + 'Repo')

  $imports.Add("use $repoFqn;")
  $ctorItems.Add("private $repoShort `$$varName")
  $mapLines.Add("  '$TableName' => `$this->$varName")

  # --- optional override via ./repository-wiring.yaml ---
  $rwPath = Join-Path $ModuleDir 'repository-wiring.yaml'
  if (Test-Path -LiteralPath $rwPath) {
    $rw = Import-PowerShellDataFile -Path $rwPath
    foreach ($r in @($rw.Repositories)) {
      $class = [string]$r.Class
      if (-not $class) { continue }
      $short = ($class -split '\\')[-1]
      $var   = ($short.Substring(0,1).ToLower() + $short.Substring(1))
      if ($r.VarName) { $var = ($r.VarName -replace '^\$','') }
      $alias = $short
      if ($r.Alias) { $alias = [string]$r.Alias }

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
  # simple English heuristic for names like users, categories, books, payments, ...
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
  # extract the column section (up to the first line starting with INDEX|UNIQUE KEY|CONSTRAINT|) ENGINE
  $lines = ($sql -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  # find the start of the column list after "CREATE TABLE ..."
  $startIdx = ($lines | Select-String -Pattern "^\s*CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\b" | Select-Object -First 1).LineNumber
  if (-not $startIdx) { $startIdx = 1 }
  # collect lines between the first opening parenthesis and the index/constraint section
  $collect = $false; $colLines = @()
  foreach ($ln in $lines) {
    if ($ln -match '^\s*CREATE\s+TABLE') { $collect = $true; continue }
    if (-not $collect) { continue }
    if ($ln -match '^\)\s*ENGINE=') { break }   # MySQL
    if ($ln -match '^\)\s*;')       { break }   # Postgres
    # skip pure index/constraint lines
    if ($ln -match '(?i)^(INDEX|UNIQUE\s+KEY|CONSTRAINT)\b') { continue }
    $colLines += $ln.Trim().TrimEnd(',')
  }

  $cols = @()

  foreach ($raw in $colLines) {
    # 1) skip obvious non-column definitions
    if ($raw -match '^(PRIMARY\s+KEY|UNIQUE\s+KEY|INDEX|CONSTRAINT|CHECK|FOREIGN\s+KEY)\b') { continue }
    if ($raw -match '^(OR|AND)\b') { continue }
    # ignore orphaned parenthesis lines in case they slipped into colLines
    if ($raw -match '^\)$') { continue }
    # 2) only process lines that look like "<name> <type>"
    #    => a typical SQL data type immediately after the column name
    if ($raw -notmatch '^[`"]?[a-z0-9_]+[`"]?\s+(ENUM|SET|DECIMAL|NUMERIC|DOUBLE\s+PRECISION|DOUBLE|FLOAT|REAL|TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|SERIAL|BIGSERIAL|BOOLEAN|JSONB?|UUID|DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME|YEAR|BIT|BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT|CHAR|VARCHAR|INTERVAL)\b') {
      continue
    }
    # skip multi-line index declarations (already filtered) yet let "PRIMARY KEY (id)" pass so we can ignore it explicitly
    if ($raw -match '(?i)^(PRIMARY\s+KEY|UNIQUE\s+KEY|INDEX|CONSTRAINT)\b') { continue }

    # typical lines: "id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY"
    # another example: `name` VARCHAR(255) NOT NULL DEFAULT 'x'
    if ($raw -match '^[`"]?([a-z0-9_]+)[`"]?\s+(.+)$') {
      $name = $matches[1]
      $rest = $matches[2]

      # SQL type = first token including parentheses: ENUM('x','y'), DECIMAL(12,2), VARCHAR(255), DATETIME(6), BIGINT UNSIGNED...
      if ($rest -match '^(ENUM|SET|DECIMAL|NUMERIC|DOUBLE\s+PRECISION|DOUBLE|FLOAT|REAL|TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|SERIAL|BIGSERIAL|BOOLEAN|JSONB?|UUID|DATE|DATETIME|TIMESTAMP|TIMESTAMPTZ|TIME|YEAR|BIT|BINARY|VARBINARY|BYTEA|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT|CHAR|VARCHAR|INTERVAL)\b([^(]*\([^\)]*\))?(\s+UNSIGNED)?') {
        $base = $matches[1].ToUpper()
        $par  = $matches[2]
        $uns  = $matches[3]
        $parText = ''
        if ($null -ne $par) { $parText = $par }
        $unsText = ''
        if ($null -ne $uns) { $unsText = $uns }
        $sqlType = ($base + $parText + $unsText).Trim()
      } else {
        # fallback – take the first word
        $base = (($rest -split '\s+')[0]).ToUpper()
        $sqlType = $base
      }

      $nullable = $true
      if ($rest -match '\bNOT\s+NULL\b') { $nullable = $false }
      if ($rest -match '\bPRIMARY\s+KEY\b') { $nullable = $false }
      # if a line explicitly contains "NULL", keep $true

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
  # decision: DECIMAL/NUMERIC => string (safer for money), other floating types => float
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

function New-DtoConstructorParameters {
  param(
    [Parameter(Mandatory)][object[]]$columns,
    [string[]]$piiNames = @()
  )
  $piiSet = @{}
  foreach ($n in @($piiNames)) { if ($n) { $piiSet[$n.ToLower()] = $true } }

  $parts = @()
  foreach ($c in $columns) {
    $prop    = ConvertTo-CamelCase $c.Name
    $phpType = Get-PhpTypeFromSqlBase $c.Base $c.Nullable
    $attr    = ''
    if ($piiSet.ContainsKey($c.Name.ToLower())) { $attr = '#[\SensitiveParameter] ' }
    $parts  += ('{0}public readonly {1} ${2}' -f $attr, $phpType, $prop)
  }
  return ($parts -join ",`n        ")
}

function New-ColumnPropertyMap($columns) {
  $pairs = @()
  foreach ($c in $columns) {
    $prop = ConvertTo-CamelCase $c.Name
    $pairs += ("'{0}' => '{1}'" -f $c.Name, $prop)
  }
  if (-not $pairs -or (@($pairs)).Count -eq 0) { return '[]' }
  return "[ " + ($pairs -join ', ') + " ]"
}

function ConvertTo-PhpArray([string[]]$arr) {
  if (-not $arr -or $arr.Count -eq 0) { return '[]' }
  $q = $arr | ForEach-Object {
    $escaped = $_.Replace('\', '\\').Replace("'", "\'")
    "'$escaped'"
  }
  "[ " + ($q -join ', ') + " ]"
}

function Expand-Template {
  param([string]$Content, [hashtable]$TokenValues)
  $out = $Content
  for ($i=0; $i -lt 3; $i++) {
    foreach ($k in $TokenValues.Keys) {
      $marker = "[[$k]]"
      $val = [string]$TokenValues[$k]
      if ($out -like "*$marker*") { $out = $out.Replace($marker, $val) }
    }
    if ($out -notmatch '\[\[[A-Z0-9_]+\]\]') { break }
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
function Get-TablesFromJoin([string]$sql) {
  if (-not $sql) { return @() }
  $out = New-Object System.Collections.Generic.List[string]

  # Ignore table-functions such as json_table(...), inet6_ntoa(...), unnest(...):
  # the extra (?!\s*\() ensures the captured identifier is not immediately followed by "("
  # Allow comments/hints and APPLY variants.
  $rx = [regex]'(?is)\b(?:FROM|JOIN(?:\s+LATERAL)?|CROSS\s+APPLY|OUTER\s+APPLY)\s+(?:ONLY\s+)?(?:/\*.*?\*/\s*)*(?<ref>(?:"[^"]+"|`[^`]+`|\[[^\]]+\]|[A-Za-z0-9_]+)(?:\.(?:"[^"]+"|`[^`]+`|\[[^\]]+\]|[A-Za-z0-9_]+))*)(?!\s*\()'

  foreach ($m in $rx.Matches($sql)) {
    $ref   = $m.Groups['ref'].Value
    $parts = $ref -split '\.'
    $last  = $parts[$parts.Length - 1]
    $name  = ($last -replace '^[`"]|[`"]$','')    # trim quotes/backticks
    $name  = ($name -replace '^(vw_|v_)','')      # vw_* → underlying table
    if ($name) { $out.Add($name.ToLower()) }
  }
  @($out | Select-Object -Unique)
}

function Resolve-ViewDependencies([string]$table, [hashtable]$views, [hashtable]$memo) {
  # return the set of tables the view for $table uses (directly or transitively)
  if (-not $views -or -not $views.Views -or -not $views.Views.ContainsKey($table)) { return @() }
  if ($memo.ContainsKey($table)) { return @() }
  $memo[$table] = $true

  $sql = Get-CreateText $views.Views[$table]
  $direct = @( Get-TablesFromJoin $sql )

  $acc = New-Object System.Collections.Generic.List[string]
  foreach ($t in $direct) {
    if ($t -ne $table) { $acc.Add($t) }
    # if a view for $t exists as well, recurse to capture transitive dependencies
    if ($views.Views.ContainsKey($t)) {
      foreach ($x in (Resolve-ViewDependencies $t $views $memo)) { $acc.Add($x) }
    }
  }
  @($acc | Select-Object -Unique)
}

function Resolve-ViewOwnerName {
  param(
    [Parameter(Mandatory)][string]$ViewName,
    [Parameter(Mandatory)][hashtable]$KnownTableSet
  )
  if ([string]::IsNullOrWhiteSpace($ViewName)) { return $null }
  $viewLower = $ViewName.ToLowerInvariant()
  if ($KnownTableSet.ContainsKey($viewLower)) { return $viewLower }

  $parts = @($viewLower -split '[-_]')
  if ($parts.Count -lt 2) { return $null }
  for ($len = $parts.Count - 1; $len -ge 1; $len--) {
    $candidate = ($parts[0..($len - 1)] -join '_')
    if ($KnownTableSet.ContainsKey($candidate)) { return $candidate }
  }
  return $null
}

function Build-ViewOwnershipIndex {
  param(
    [hashtable]$ViewsMap,
    [System.Collections.IEnumerable]$KnownTables
  )
  $index = @{}
  if (-not $ViewsMap -or -not $ViewsMap.Views) { return $index }

  $knownSet = @{}
  foreach ($tbl in @($KnownTables)) {
    if ($tbl) {
      $knownSet[$tbl.ToLower()] = $true
    }
  }

  foreach ($entry in $ViewsMap.Views.GetEnumerator()) {
    $viewName = [string]$entry.Key
    $owner = Resolve-ViewOwnerName -ViewName $viewName -KnownTableSet $knownSet

    if (-not ($owner -and $knownSet.ContainsKey($owner))) {
      Write-Warning "Unable to map view '$viewName' to a table defined in the schema map."
      continue
    }

    if (-not $index.ContainsKey($owner)) {
      $index[$owner] = New-Object System.Collections.Generic.List[string]
    }
    $index[$owner].Add($viewName)
  }

  foreach ($key in @($index.Keys)) {
    $index[$key] = @($index[$key])
  }
  return $index
}

$templates = @( Get-Templates -Root $TemplatesRoot )
# For optional submodule checks (.gitmodules)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$subSet   = Get-SubmodulePathSet -repoRoot $repoRoot

# Choose maps: explicit -MapPath or autodetect under -SchemaDir
$mapPaths = @()
if ($MapPath) {
  # force an array even for a single path
  $mapPaths = @($MapPath)
} else {
  if (-not (Test-Path -LiteralPath $SchemaDir)) { throw "Schema dir not found: '$SchemaDir'." }

  # Get FileInfo[] first, then convert to strings
  $allItems = @(Get-ChildItem -LiteralPath $SchemaDir -Filter ("schema-map-*{0}" -f $script:SchemaExt) -File)
  if (-not $allItems -or $allItems.Count -eq 0) {
    throw "No schema maps found under '$SchemaDir' (pattern 'schema-map-*' + $script:SchemaExt)."
  }

  $pgItems  = @($allItems | Where-Object { $_.Name -match 'postgres' })
  $myItems  = @($allItems | Where-Object { $_.Name -match 'mysql' })
  $othItems = @($allItems | Where-Object { $_.Name -notmatch 'mysql|postgres' })

  # Prepare clean string paths
  $pgPaths  = @($pgItems  | Select-Object -ExpandProperty FullName)
  $myPaths  = @($myItems  | Select-Object -ExpandProperty FullName)
  $othPaths = @($othItems | Select-Object -ExpandProperty FullName)

  switch ($EnginePreference) {
    'postgres' { $mapPaths = @($pgPaths + $othPaths) }
    'mysql'    { $mapPaths = @($myPaths + $othPaths) }
    'both'     { $mapPaths = @($pgPaths + $myPaths + $othPaths) }
    default {
      # auto: prefer Postgres, otherwise MySQL
      $prefer = @()
      if (@($pgPaths).Count -gt 0) {
        $prefer = $pgPaths
      } else {
        $prefer = $myPaths
      }
      $mapPaths = @($prefer + $othPaths)
    }
  }
}

function Test-SelectStar([string]$viewSql) {
  if (-not $viewSql) { return $false }
  $m = [regex]::Match($viewSql, '(?is)\bSELECT\b\s+(?:DISTINCT(?:\s+ON\s*\([^)]+\))?\s+)?(.*?)\bFROM\b')
  if (-not $m.Success) { return $false }
  $segment = $m.Groups[1].Value
  return ($segment -match '(^|\s)([A-Za-z0-9_]+)\.\*\s*(,|$)' -or $segment -match '(^|\s)\*\s*(,|$)')
}

# Remove nulls, duplicates, and missing paths (safety)
  $mapPaths = @($mapPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

  if (-not $mapPaths -or $mapPaths.Count -eq 0) { throw "No schema maps selected." }

  Write-Host "Selected maps ($($mapPaths.Count)):" -ForegroundColor Cyan
  $mapPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkCyan }

# --- Views map registry (support per-engine maps, search multiple dirs) ---
  $viewMaps = @{}
  $joinViewMaps = @{}

# search order: prefer full views-library (recursive), then explicit ViewsDir/SchemaDir
  $viewDirs = @()
  $libRoot = Join-Path $PSScriptRoot '..\..\views-library'
  if (-not (Test-Path -LiteralPath $libRoot)) {
    $libRoot = Join-Path $PSScriptRoot '..\views-library'
  }
  if (Test-Path -LiteralPath $libRoot) {
    $viewDirs += $libRoot
  }
  if ($ViewsPath) {
    $viewDirs += (Split-Path -Parent $ViewsPath)
  } elseif ($PSBoundParameters.ContainsKey('ViewsDir') -and (Test-Path -LiteralPath $ViewsDir)) {
    $viewDirs += $ViewsDir
  } else {
    $viewDirs += $SchemaDir
  }
  $viewDirs = @($viewDirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

# load view maps (merge all)
foreach ($dir in $viewDirs) {
  $candidates = @(Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {
    $_.Name -match '^(views-map-|schema-views-|feature)' -and $_.Extension -eq $script:SchemaExt -and $_.Name -notmatch 'joins'
  })
  foreach ($candidate in @($candidates | Sort-Object FullName)) {
    $tag = Get-EngineTag $candidate.Name
    if (-not $viewMaps.ContainsKey($tag)) {
      $viewMaps[$tag] = [pscustomobject]@{
        Path = $candidate.FullName
        Data = Import-ViewsMap -Path $candidate.FullName
      }
    } else {
      $data = Import-ViewsMap -Path $candidate.FullName
      if ($data -and $data.Views) {
        if (-not $viewMaps[$tag].Data.Views) { $viewMaps[$tag].Data.Views = @{} }
        foreach ($kv in $data.Views.GetEnumerator()) { $viewMaps[$tag].Data.Views[$kv.Key] = $kv.Value }
        $viewMaps[$tag].Path += "," + $candidate.FullName
      }
    }
  }
}
foreach ($entry in $viewMaps.GetEnumerator()) {
  Write-Host ("Loaded views map [{0}]: {1}" -f $entry.Key, $entry.Value.Path) -ForegroundColor Cyan
}
if ($viewMaps.Count -eq 0) {
  Write-Warning "No views map found (looking for 'views-map-*' + $script:SchemaExt or 'schema-views-*' + $script:SchemaExt). View drift checks will throw for missing views."
}

# load join maps strictly from the views-library (joins-*.$script:SchemaExt); no legacy fallbacks
$joinDirs = @()
if (Test-Path -LiteralPath $libRoot) {
  $joinDirs += $libRoot
}
elseif ($ViewsPath) {
  # explicit override when someone points to a custom views dir
  $joinDirs += (Split-Path -Parent $ViewsPath)
}
foreach ($eng in @('postgres','mysql')) {
  $merged = $null
  $paths = @()
  foreach ($dir in $joinDirs) {
    $candidates = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter ("joins-{0}{1}" -f $eng, $script:SchemaExt))
    foreach ($c in $candidates) {
      $paths += $c.FullName
      $data = Import-ViewsMap -Path $c.FullName
      if ($data -and $data.Views) {
        if (-not $merged) { $merged = [ordered]@{ Views = @{} } }
        foreach ($kv in $data.Views.GetEnumerator()) { $merged.Views[$kv.Key] = $kv.Value }
      }
    }
  }
  if ($merged) {
    $joinViewMaps[$eng] = $merged
    Write-Host ("Loaded joins map [{0}]: {1}" -f $eng, ($paths -join ',')) -ForegroundColor DarkCyan
  } else {
    Write-Warning "Join views map for '$eng' not found in: $($joinDirs -join ', ')"
  }
}

$FailHardOnViewDrift = $true
if ($PSBoundParameters.ContainsKey('FailOnViewDrift')) {
  $FailHardOnViewDrift = [bool]$FailOnViewDrift
}

$schemaSnapshots = @{}

foreach ($mp in $mapPaths) {
  $schema  = Import-SchemaMap -Path $mp
  $mapLeaf = Split-Path -Leaf $mp
  $mapEngine = Get-EngineTag $mapLeaf
  $activeViews = $null
  if ($viewMaps.ContainsKey($mapEngine)) {
    $activeViews = $viewMaps[$mapEngine].Data
  } elseif ($viewMaps.ContainsKey('default')) {
    $activeViews = $viewMaps['default'].Data
  } elseif ($viewMaps.Count -eq 1) {
    $firstKey = @($viewMaps.Keys)[0]
    $activeViews = $viewMaps[$firstKey].Data
  }
  if (-not $schema.Tables) { Write-Warning "No 'Tables' in schema map: $mp"; continue }
  Write-Host "Loaded '$mapLeaf' with $($schema.Tables.Keys.Count) tables. Templates: $($templates.Count)." -ForegroundColor Cyan

  # iterate over tables
  $tables = $schema.Tables.GetEnumerator() | Sort-Object Key
  foreach ($entry in $tables) {
  $table = [string]$entry.Key                             # e.g. users
  $spec  = $entry.Value
  $createSql = Get-CreateText $spec.create

  $parsed = ConvertFrom-CreateSql -tableName $table -sql $createSql
  $cols   = @($parsed.Columns)
  $colMap = @{}
  foreach ($col in $cols) {
    if (-not ($col -and $col.PSObject.Properties['Name'])) {
      $colType = 'null'
      if ($col) { $colType = $col.GetType().FullName }
      $raw = ''
      if ($col) { $raw = $col | Out-String }
      throw "Parsed column without Name for table '$table' (type=$colType). Raw:`n$raw"
    }
    $colMap[$col.Name.ToLower()] = $col
  }

  # Map of local column nullability (name => $true if nullable, $false if NOT NULL)
  $nullMap = @{}
  foreach ($c in $cols) { $nullMap[$c.Name] = [bool]$c.Nullable }

  if ((@($cols)).Count -eq 0) { Write-Warning "No columns parsed for table '$table'."; continue }

  $classInfo = Get-ColumnClassification -columns $cols
  $binaryCols = @($classInfo.Binary | ForEach-Object { $_.ToLower() })
  # list of column names (needed immediately for the PII heuristic)
  $colNames = @($cols | ForEach-Object { $_.Name })
  $generatedCols = Get-GeneratedColumnsFromCreateSql -CreateSql $createSql
  $packagePascal = ConvertTo-PascalCase $table                      # Users, UserIdentities, OrderItems...
  $entityPascal  = ConvertTo-PascalCase (Singularize $table)        # User, UserIdentity, OrderItem...
  $dtoClass      = "$($entityPascal)Dto"
  $namespace     = "$BaseNamespace\$packagePascal"
  # derive module- and joins-class names
  $moduleClass = "${packagePascal}Module"
  $joinsClass  = "${packagePascal}Joins"
  # PII columns: prefer the explicit map, otherwise use a conservative heuristic
  $piiCols = @()
  if ($spec -is [hashtable] -and $spec.ContainsKey('PiiColumns')) {
    $piiCols = @($spec.PiiColumns)
  } else {
    $piiCols = @($colNames | Where-Object {
    $_ -match '(?i)\b(email(_hash)?|phone|msisdn|password(_hash)?|token(_hash)?|session|secret|otp|ssn|iban|card|cvv|address|ip(_hash)?|name|surname)\b'
    } )
  }
  # compose tokens shared across most templates
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
    'GENERATED_COLUMNS_ARRAY'= (ConvertTo-PhpArray $generatedCols)
    'PII_COLUMNS_ARRAY'      = (ConvertTo-PhpArray $piiCols)
    'DTO_CTOR_PARAMS'        = (New-DtoConstructorParameters -columns $cols -piiNames $piiCols)
    'SERVICE_CLASS'          = "$($packagePascal)AggregateService"
    'USES_ARRAY'             = @(
                                  "use $DatabaseFQN;",
                                  "use $namespace\Dto\$dtoClass;",
                                  "use $namespace\Mapper\${dtoClass}Mapper;"
                                ) -join "`n"
    'CTOR_PARAMS'            = 'private Database $db'  # generator can extend later (repositories, etc.)
    'TABLE_NAME'             = $table
    'ENTITY_CLASS'           = $entityPascal
    'PACKAGE_NAME'           = $packagePascal
    'AGGREGATE_METHODS'      = ''
  }
  # Column aliases for input rows (API), e.g., k->setting_key, value->setting_value
  $aliasMap = @{}
  if ($spec -is [hashtable] -and $spec.ContainsKey('Aliases')) {
    foreach ($ak in $spec.Aliases.Keys) {
      $aliasMap[[string]$ak] = [string]$spec.Aliases[$ak]
    }
  }
  $tokenCommon['PARAM_ALIASES_ARRAY'] = ConvertTo-PhpAssoc $aliasMap
  # --- new safe default tokens (templates use them, but values may stay empty) ---
  $tokenCommon['STATUS_TRANSITIONS_MAP']   = '[]'   # optional: e.g., @{ draft=@('ready'); ready=@('sent','canceled') }
  $tokenCommon['UNIQUE_HELPERS']           = ''     # generator can later emit per-unique helpers; keep empty now
  $tokenCommon['CRITERIA_HELPERS']         = ''     # generator can add preset-join sugar later; keep empty now
    # ---- supplemental tokens for all templates ----
    # prepare pairs only when both columns exist in the table
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

    # heuristics:
    $hasCreatedAt = $colNames -contains 'created_at'
    $hasUpdatedAt = $colNames -contains 'updated_at'
    $hasDeletedAt = $colNames -contains 'deleted_at'

    # PK: prefer 'id', otherwise take the first column
    $pk = ($colNames | Where-Object { $_ -eq 'id' } | Select-Object -First 1)
    if (-not $pk) { $pk = $colNames[0] }
    # --- PK strategy (identity|uuid|natural|composite) ---

    # --- PK combos extracted from CREATE ---
    $pkCombos = @( Get-PrimaryKeyCombosFromCreateSql -CreateSql $createSql )

    [string[]]$pkCols = @()
    if ($pkCombos.Count -gt 0) {
      # first combination → ensure a clean string[]
      $pkCols = @($pkCombos[0] | ForEach-Object { [string]$_ })
    }

    # keep the first PK column around for DefaultOrder and friends
    if ($pkCols.Count -gt 0) { $pk = $pkCols[0] }

    # Auto-increment heuristics (MySQL as well as Postgres identity)
    $autoId = $false
    if ($createSql -match '(?im)^\s*id\s+[^\r\n]*\bAUTO_INCREMENT\b') { $autoId = $true }
    if ($createSql -match '(?im)GENERATED\s+(ALWAYS|BY\s+DEFAULT)\s+AS\s+IDENTITY') { $autoId = $true }
    if ($createSql -match '(?im)\bSERIAL\b')                           { $autoId = $true }

    # PK column type to infer uuid variations
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

    # Prepare FK SQL (use CREATE TABLE as fallback) — needed immediately
    $fkSqls = @()
    $fkSqls += @($spec.foreign_keys | Where-Object { $_ })
    $fkSqls += @($createSql) # fallback parsing inline

    # --- isRowLockSafe (for tests and samples) ---
    $hasLarge  = @($cols | Where-Object { $_.Base -match '(BLOB|JSONB?)$' }).Count -gt 0
    $tooWide  = $cols.Count -gt 20

    # which FK columns are locally required?
    $fkLocalCols    = @( Get-FkLocalColumnsFromSql $fkSqls )
    $hasRequiredFk  = $false
    foreach ($lc in $fkLocalCols) {
      if ($nullMap.ContainsKey($lc) -and (-not [bool]$nullMap[$lc])) { $hasRequiredFk = $true; break }
    }

    # Safe = identity PK + no required FKs; nullable FK allowed. Still filter extreme width/large types.
    $rowLockSafe = ($pkStrategy -eq 'identity') -and (-not $hasRequiredFk) -and (-not $hasLarge) -and (-not $tooWide)

    # Optional whitelist – force a true value when desired
    if ($table -in @('authors','users')) { $rowLockSafe = $true }

    $tokenCommon['IS_ROWLOCK_SAFE'] = 'false'
    if ($rowLockSafe) { $tokenCommon['IS_ROWLOCK_SAFE'] = 'true' }

    # default ORDER clause
    if ($hasCreatedAt) {
      $idOrPk = $pk
      if ($colNames -contains 'id') { $idOrPk = 'id' }
      $defaultOrder = "created_at DESC, $idOrPk DESC"
    } elseif ($colNames -contains 'id') {
      $defaultOrder = 'id DESC'
    } else {
      $defaultOrder = "$pk DESC"
    }

    # text columns eligible for LIKE searches
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
    $fkSqlsAll += @($spec.foreign_keys)  # from the schema map
    $fkSqlsAll += @($createSql)          # fallback: inline FK definitions in CREATE TABLE

    $depTablesFk = @( Get-ReferencedTablesFromFkSqls $fkSqlsAll )
    $depTablesFk = @($depTablesFk | Where-Object { $_ -and $_ -ne $table })

  # populate tokens:
  $tokenCommon['TABLE']                   = $table
  $tokenCommon['VIEW']                    = "vw_${table}"
  # Contract view SQL per engine, sourced directly from schema view maps.
  $viewSqlByEngine = @{}
  $enginesToLoad = @('mysql','postgres')
  foreach ($eng in $enginesToLoad) {
    $sql = ''
    if ($viewMaps.ContainsKey($eng)) {
      $vm = $viewMaps[$eng].Data
      if ($vm -and $vm.Views -and $vm.Views.ContainsKey($table)) {
        $cv = $vm.Views[$table]
        if ($cv -is [hashtable] -and $cv.ContainsKey('create')) {
          $sql = [string]$cv.create
        } elseif ($cv -and $cv.PSObject -and $cv.PSObject.Properties['create']) {
          $sql = [string]$cv.create
        }
      }
    }
    if (-not $sql) {
      throw "Contract view SQL for table '$table' not found in schema-views-$eng$script:SchemaExt (missing 'create' entry)."
    }
    # Strip leading SQL comments/blank lines so CREATE is the first token for DdlGuard (compatible with Windows PS where \R is unsupported)
    $sql = [regex]::Replace($sql, '(?m)^(\\s*--.*(?:\\r?\\n|$))+', '', 'Multiline')
    $idxCreate = [System.Globalization.CultureInfo]::InvariantCulture.CompareInfo.IndexOf($sql, 'CREATE', [System.Globalization.CompareOptions]::IgnoreCase)
    if ($idxCreate -ge 0) {
      $sql = $sql.Substring($idxCreate)
    } else {
      throw "CREATE keyword not found in contract view definition for table '$table' (engine '$eng')."
    }
    $viewSqlByEngine[$eng] = $sql.Trim()
  }

  $tokenCommon['CONTRACT_VIEW_SQL_MYSQL']    = $viewSqlByEngine['mysql']
  $tokenCommon['CONTRACT_VIEW_SQL_POSTGRES'] = $viewSqlByEngine['postgres']
  $tokenCommon['COLUMNS_ARRAY']           = (ConvertTo-PhpArray $colNames)
    # finalize dependencies (FK-derived only)
    $depNames = @($depTablesFk | ForEach-Object { "table-$_" } | Sort-Object -Unique)
    # [[PK]] can be "id" or "col1, col2" (used by Definitions::pkColumns)
    if ($pkCols.Count -gt 1) {
      $tokenCommon['PK'] = ($pkCols -join ', ')
    } else {
      $tokenCommon['PK'] = $pk
    }
    $tokenCommon['SOFT_DELETE_COLUMN'] = ''
    if ($hasDeletedAt)  { $tokenCommon['SOFT_DELETE_COLUMN'] = 'deleted_at' }
    $tokenCommon['UPDATED_AT_COLUMN'] = ''
    if ($hasUpdatedAt)  { $tokenCommon['UPDATED_AT_COLUMN'] = 'updated_at' }
    $verName = ''
    if ($spec -is [hashtable] -and $spec.ContainsKey('VersionColumn')) {
      $verName = [string]$spec.VersionColumn
    } elseif ($colNames -contains 'version') {
      $verName = 'version'
    }
    $tokenCommon['VERSION_COLUMN'] = $verName
    $tokenCommon['DEFAULT_ORDER_CLAUSE']    = $defaultOrder
    # --- VIEW DRIFT CHECK ---
    $softCol = ''
    if ($hasDeletedAt) { $softCol = 'deleted_at' }

    # Ensure every referenced table has a view
    if ($activeViews) {
      Assert-ReferencedViews -Table $table -ForeignKeySqls $fkSqls -ViewsMap $activeViews -FailHard:$FailHardOnViewDrift
    }

    # Retrieve local FK columns for view warnings
    $fkLocalCols = @( Get-FkLocalColumnsFromSql $fkSqls )

    Assert-TableVsView `
      -Table $table `
      -TableColumns ($colNames | ForEach-Object { $_.ToLower() }) `
      -Pk $pkCols `
      -VersionColumn $verName `
      -SoftDeleteColumn $softCol `
      -DefaultOrder $defaultOrder `
      -ViewsMap $activeViews `
      -BinaryColumns $binaryCols `
      -PairColumns $pairMap `
      -FkLocalColumns $fkLocalCols `
      -FailHard:$FailHardOnViewDrift

    $tokenCommon['UNIQUE_KEYS_ARRAY']       = 'null'                  # keep empty for now
    # JSON_COLUMNS_ARRAY already populated above
    $tokenCommon['FILTERABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $colNames)
    $tokenCommon['SEARCHABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $textCols)
    # SORTABLE: drop JSON/BINARY columns (rarely desired in ORDER BY)
    $sortable = @($colNames | Where-Object { 
      -not ($classInfo.Json -contains $_) -and -not ($classInfo.Binary -contains $_)
    })
    $tokenCommon['SORTABLE_COLUMNS_ARRAY'] = (ConvertTo-PhpArray $sortable)
    $tokenCommon['DEFAULT_PER_PAGE']        = '50'
    $tokenCommon['MAX_PER_PAGE']            = '500'
    $tokenCommon['VERSION']                 = '1.0.0'
    $tokenCommon['DIALECTS_ARRAY']          = "[ 'mysql', 'postgres' ]"
    # INDEX/FK names sourced from the schema map when available
    $idxNames = Get-IndexNamesFromSql       @($spec.indexes)
    $fkNames  = Get-ForeignKeyNamesFromSql  @($spec.foreign_keys)
    if (@($idxNames).Count -gt 0) {
      $tokenCommon['INDEX_NAMES_ARRAY'] = "[ " + (($idxNames | ForEach-Object { "'$_'" }) -join ', ') + " ]"
    } else { $tokenCommon['INDEX_NAMES_ARRAY'] = '[]' }

    if (@($fkNames).Count -gt 0) {
      $tokenCommon['FK_NAMES_ARRAY'] = "[ " + (($fkNames | ForEach-Object { "'$_'" }) -join ', ') + " ]"
    } else { $tokenCommon['FK_NAMES_ARRAY'] = '[]' }

    # ---- UPSERT (robust – keys may be missing) ----
    $ukeys = @()
    $uupd  = @()
    $up    = $null

    if ($spec -is [hashtable] -and $spec.ContainsKey('Upsert')) {
      $up = $spec['Upsert']
    } elseif ($spec.PSObject -and $spec.PSObject.Properties.Match('Upsert').Count -gt 0) {
      # fallback in case this is not a plain hashtable
      $up = $spec.Upsert
    }

    if ($null -ne $up) {
      if ($up -is [hashtable]) {
        $ukeys = @($up['Keys'])
        $uupd  = @($up['Update'])
      } else {
        # Allow compact syntax: Upsert = 'email' / @('email')
        $ukeys = @($up)
      }
    }

    $ukeysQuoted = @($ukeys | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { "'$_'" })
    $uupdQuoted  = @($uupd  | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { "'$_'" })

    if (@($ukeysQuoted).Count -gt 0) {
      $tokenCommon['UPSERT_KEYS_ARRAY'] = "[ " + ($ukeysQuoted -join ', ') + " ]"
    } else { $tokenCommon['UPSERT_KEYS_ARRAY'] = '[]' }

    if (@($uupdQuoted).Count -gt 0) {
      $tokenCommon['UPSERT_UPDATE_COLUMNS_ARRAY'] = "[ " + ($uupdQuoted -join ', ') + " ]"
    } else { $tokenCommon['UPSERT_UPDATE_COLUMNS_ARRAY'] = '[]' }

    # ---- UNIQUE combinations: gather table-level UNIQUEs, unique indexes, and PKs ----
    $addUniqueCombo = {
      param($combo, [System.Collections.Generic.List[object]]$target)
      if (-not $combo) { return }
      $normalized = @($combo | ForEach-Object { ($_ -replace '[`"\s]','').ToLower() })
      if ($normalized.Count -gt 0) { $target.Add($normalized) }
    }

    $uniqueCombosList = New-Object System.Collections.Generic.List[object]
    foreach ($combo in (Get-UniqueCombosFromCreateSql -CreateSql $createSql)) {
      & $addUniqueCombo $combo $uniqueCombosList
    }
    foreach ($idxSql in @($spec.indexes)) {
      foreach ($combo in (Get-UniqueCombosFromCreateSql -CreateSql $idxSql)) {
        & $addUniqueCombo $combo $uniqueCombosList
      }
    }
    foreach ($pkCombo in (Get-PrimaryKeyCombosFromCreateSql -CreateSql $createSql)) {
        & $addUniqueCombo $pkCombo $uniqueCombosList
    }
    $uniqueCombos = $uniqueCombosList

    # deduplicate combinations
    $seen = @{}
    $uniqueCombos = @($uniqueCombos | Where-Object {
      $k = ($_ -join '#')
      if ($seen.ContainsKey($k)) { $false } else { $seen[$k] = $true; $true }
    })

    # keep only combos composed of known columns
    $colSet = @{}
    foreach ($c in $colNames) { $colSet[$c.ToLower()] = $true }
    $uniqueCombos = @($uniqueCombos | Where-Object {
      $allInTable = $true
      foreach ($c in $_) {
        if (-not $colSet.ContainsKey($c.ToLower())) { $allInTable = $false; break }
      }
      $allInTable
    })

    # Render into [[UNIQUE_KEYS_ARRAY]]
    if (@($uniqueCombos).Count -gt 0) {
      $render = @()
      foreach ($arr in $uniqueCombos) {
        $render += "[ " + (($arr | ForEach-Object { "'$_'" }) -join ', ') + " ]"
      }
      $tokenCommon['UNIQUE_KEYS_ARRAY'] = "[ " + ($render -join ', ') + " ]"
    } else {
      $tokenCommon['UNIQUE_KEYS_ARRAY'] = 'null'
    }

    # Validate UPSERT settings against unique combinations
    Assert-UpsertConsistency `
      -Table $table `
      -UpsertKeys $ukeys `
      -UpsertUpdateCols $uupd `
      -UniqueCombos $uniqueCombos `
      -SoftDeleteColumn $softCol

    # snapshot for cross-engine schema parity checks
    if (-not $schemaSnapshots.ContainsKey($mapEngine)) {
      $schemaSnapshots[$mapEngine] = @{
        Path   = $mp
        Tables = @{}
      }
    } elseif (-not $schemaSnapshots[$mapEngine].Tables) {
      $schemaSnapshots[$mapEngine].Tables = @{}
    }
    $colDetailSnapshot = @{}
    foreach ($c in $cols) {
      $colName = ''
      if ($c -is [psobject]) {
        if ($c.PSObject.Properties.Match('Name').Count -gt 0) {
          $colName = [string]$c.Name
        }
      } elseif ($c -is [hashtable]) {
        if ($c.ContainsKey('Name')) {
          $colName = [string]$c['Name']
        }
      }
      if (-not $colName) { continue }
      $typeVal = ''
      if ($c -is [psobject]) {
        if ($c.PSObject.Properties.Match('SqlType').Count -gt 0) {
          $typeVal = [string]$c.SqlType
        } elseif ($c.PSObject.Properties.Match('Type').Count -gt 0) {
          $typeVal = [string]$c.Type
        }
      } elseif ($c -is [hashtable]) {
        if ($c.ContainsKey('SqlType')) {
          $typeVal = [string]$c['SqlType']
        } elseif ($c.ContainsKey('Type')) {
          $typeVal = [string]$c['Type']
        }
      }
      $nullableVal = $false
      if ($c -is [psobject]) {
        if ($c.PSObject.Properties.Match('Nullable').Count -gt 0) {
          $nullableVal = [bool]$c.Nullable
        } elseif ($c.PSObject.Properties.Match('IsNullable').Count -gt 0) {
          $nullableVal = [bool]$c.IsNullable
        }
      } elseif ($c -is [hashtable]) {
        if ($c.ContainsKey('Nullable')) {
          $nullableVal = [bool]$c['Nullable']
        } elseif ($c.ContainsKey('IsNullable')) {
          $nullableVal = [bool]$c['IsNullable']
        }
      }
      $colDetailSnapshot[$colName] = @{
        Type     = $typeVal
        Nullable = $nullableVal
      }
    }
    $schemaSnapshots[$mapEngine].Tables[$table] = @{
      Columns      = $colNames
      ColumnDetail = $colDetailSnapshot
      UpsertKeys   = $ukeys
      UpsertUpdate = $uupd
      SoftDelete   = $softCol
      Version      = $verName
      DefaultOrder = $defaultOrder
    }

    # --- UNIQUE_HELPERS (Repository) ---
    try {
      $uniqueHelpers = New-UniqueHelpers $uniqueCombos $colMap $pkCols $colNames $table
    } catch {
      throw "New-UniqueHelpers failed for table '$table': $($_.Exception.Message)"
    }
    $tokenCommon['UNIQUE_HELPERS'] = (
      $uniqueHelpers +
      (New-TenancyRepoHelpers  -ColNames $colNames -PkCols $pkCols) +
      (New-StatusTransitionHelper -TransitionsPhp $tokenCommon['STATUS_TRANSITIONS_MAP'])
    )

    # --- CRITERIA_HELPERS (Criteria) ---
    $tokenCommon['CRITERIA_HELPERS'] = New-CriteriaHelpers -ColNames $colNames -PkCols $pkCols

    # Determine JoinPolicy from switches (explicit -JoinPolicy wins; then legacy aliases)
    if ($PSBoundParameters.ContainsKey('JoinPolicy') -and ($JoinAsInner -or $JoinAsInnerStrict)) {
      Write-Warning "Legacy switches (-JoinAsInner*) were provided alongside -JoinPolicy. Ignoring the legacy flags and using '$JoinPolicy'."
    }
    if ($PSBoundParameters.ContainsKey('JoinPolicy')) {
      $joinPolicy = $JoinPolicy
    } elseif ($JoinAsInnerStrict) {
      $joinPolicy = 'any'
    } elseif ($JoinAsInner) {
      $joinPolicy = 'all'
    } else {
      $joinPolicy = 'left'
    }

    $tokenCommon['JOIN_METHODS'] = New-JoinMethods `
        -ThisTable $table `
        -ForeignKeySqls $fkSqls `
        -LocalNullabilityMap $nullMap `
        -JoinPolicy $joinPolicy
    # JOINABLE_ENTITIES_MAP: assign aliases j0, j1, ... based on FK order
    $refTables = @()
    foreach ($fk in @($fkSqls)) {
      if (-not $fk) { continue }
      foreach ($m in [regex]::Matches([string]$fk, '(?is)REFERENCES\s+[`"]?([a-z0-9_]+)[`"]?')) {
        $t = $m.Groups[1].Value.ToLower()
        if ($t -and $t -ne $table) { $refTables += $t }
      }
    }
    $refTables = @($refTables | Select-Object -Unique)
    $joinablePairs = @()
    for ($i=0; $i -lt $refTables.Count; $i++) {
      $alias = "j$($i)"
      $joinablePairs += "'$($refTables[$i])' => '$alias'"
    }
    if ($joinablePairs.Count -gt 0) {
      $tokenCommon['JOINABLE_ENTITIES_MAP'] = '[ ' + ($joinablePairs -join ', ') + ' ]'
    } else {
      $tokenCommon['JOINABLE_ENTITIES_MAP'] = '[]'
    }
    # --- augment deps by tables referenced in our view(s) ---
    $depTablesView = @()
    # View-derived deps disabled for initial install (joins/feature handled separately)
    $depNames = @($depNames) | Sort-Object -Unique
    foreach ($t in $depTablesView) {
      # if the package for table $t is missing, remind the generator
      $p = Resolve-PackagePath -PackagesDir $ModulesRoot -Table $t -PackagePascal (ConvertTo-PascalCase $t) -Mode $NameResolution
      if (-not $p) { Write-Warning "View for '$table' references '$t' but the package for '$t' was not found under '$ModulesRoot'." }
    }
    $tokenCommon['DEPENDENCIES_ARRAY'] = (ConvertTo-PhpArray $depNames)

    # output directory of the EXISTING package (submodule) – search pascal/snake/kebab
    $moduleDir = Resolve-PackagePath -PackagesDir $ModulesRoot `
                                    -Table $table `
                                    -PackagePascal $packagePascal `
                                    -Mode $NameResolution

    if (-not $moduleDir) {
    $kebab = ($table -replace '_','-')
    throw "Target package for table '$table' was not found (mode=$NameResolution, looked under '$ModulesRoot' for Pascal='$packagePascal', Snake='$table', Kebab='$kebab')."
    }

  # optionally require the target to be a tracked submodule (.gitmodules)
  if ($StrictSubmodules) {
    $repoRootResolved = (Resolve-Path -LiteralPath $repoRoot).Path
    $dirResolved      = (Resolve-Path -LiteralPath $moduleDir).Path
    $relRaw = [System.IO.Path]::GetRelativePath($repoRootResolved, $dirResolved)
    $rel = $relRaw.TrimStart('\','/').Replace('\','/')
    # allow matching by suffix if relative path normalization differs
    $isTracked = $subSet.ContainsKey($rel) -or ($subSet.Keys | Where-Object { $_.Trim('/\') -eq $rel.Trim('/\') -or $_.Trim('/\').EndsWith("/$rel") }).Count -gt 0
    if (-not $isTracked) {
        throw "Target '$rel' is not listed in .gitmodules (initialize the submodule or disable -StrictSubmodules)."
    }
  }
    # inside the package you may create subdirectories (src etc.), but do NOT create a new package
    New-Directory (Join-Path $moduleDir 'src')

    # --- AUTOWIRE: add repository imports and constructor parameter(s) ---
    $auto = New-AutowireTokens -BaseNamespace $BaseNamespace `
                            -PackageName   $packagePascal `
                            -EntityClass   $entityPascal `
                            -ModuleDir     $moduleDir `
                            -TableName     $table

  # USES_ARRAY already lists "use ...;" lines → extend with repository imports
  $tokenCommon['USES_ARRAY']  = ($tokenCommon['USES_ARRAY'] + "`n" + $auto.Imports).Trim()

  # CTOR_PARAMS uses property promotion → append ", private XxxRepository $xxxRepo"
  $tokenCommon['CTOR_PARAMS'] = ($tokenCommon['CTOR_PARAMS'] + $auto.CtorParamsSuffix)

  # Optional: populate [[REPOSITORY_MAP]] when present
  $tokenCommon['REPOSITORY_MAP'] = $auto.RepositoryMap

  foreach ($tpl in $templates) {
    $relPath = $tpl.File
    # replace tokens inside file names as well (e.g., [[DTO_CLASS]])
    $relPath = $relPath.Replace('[[DTO_CLASS]]',     $dtoClass)
    $relPath = $relPath.Replace('[[SERVICE_CLASS]]', $tokenCommon['SERVICE_CLASS'])
    $relPath = $relPath.Replace('[[PACKAGE_NAME]]',  $packagePascal)
    $relPath = $relPath.Replace('[[ENTITY_CLASS]]',  $entityPascal)
    # Resolve [[CLASS]] inside file paths
    if ($relPath -like '*[[CLASS]]*') {
      $classForPath = $moduleClass
      if ($tpl.File -match '(^|/|\\)Joins(/|\\)') { $classForPath = $joinsClass }
      $relPath = $relPath.Replace('[[CLASS]]', $classForPath)
    }

    $outPath = Join-Path $moduleDir $relPath
    New-Directory (Split-Path -Parent $outPath)
    # select only the tokens the template expects
    $tokensForThis = @{}
    # 1) special tokens not stored in $tokenCommon
    if ($tpl.Tokens -contains 'CLASS') {
      $tokensForThis['CLASS'] = $moduleClass
      if ($tpl.File -match '(^|/|\\)Joins(/|\\)') { $tokensForThis['CLASS'] = $joinsClass }
    }
    # 2) regular tokens sourced from $tokenCommon
    foreach ($tk in $tpl.Tokens) {
    if ($tokenCommon.Contains($tk)) {
        $tokensForThis[$tk] = $tokenCommon[$tk]
    }
    elseif ($tokensForThis.ContainsKey($tk)) {
        # already filled earlier (e.g., CLASS) – fine
    }
    elseif (-not $AllowUnresolved) {
        Write-Error "Template '$($tpl.Name)' expects token '$tk' not provided by generator (table '$table'). Use -AllowUnresolved to bypass."
        continue
    }
    }

    # render

    # Template-specific tweaks
    if ($tpl.Name -match 'aggregate-service-template') {
      # Aggregate services still need Database + repository imports, but not DTO/Mapper extras.
      $tokensForThis['USES_ARRAY'] = ("use $DatabaseFQN;`n" + $auto.Imports).Trim()
    }
    $rendered = Expand-Template -content $tpl.Content -tokenValues $tokensForThis

    # check for unresolved [[TOKENS]]
    $unresolved = Test-TemplateTokens -content $rendered
    if ((@($unresolved)).Count -gt 0 -and -not $AllowUnresolved) {      $list = $unresolved -join ', '
      throw "Unresolved tokens in '$($tpl.Name)' for table '$table': $list"
    }

    # Cosmetic: normalize leading whitespace for 'use' imports to avoid mixed indentation when templates carry extra spaces.
    $rendered = ($rendered -split "`n" | ForEach-Object { $_ -replace '^\s+use\s+', 'use ' }) -join "`n"

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
Test-SchemaParity -Snapshots $schemaSnapshots

try {
  Stop-IfNeeded -RepoRoot $repoRoot
  Write-Host "Done." -ForegroundColor Cyan
  exit 0
} catch {
  Write-Error $_
  if ($_.ScriptStackTrace) { Write-Error $_.ScriptStackTrace }
  exit 1
}
