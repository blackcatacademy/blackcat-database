param(
  [Alias('Map','MapFile')]
  [string]$MapPath,                           # volitelné; když chybí, hledá se v -SchemaDir
  [string]$SchemaDir = "./schema",            # kde hledat schema-map-*.psd1
  [ValidateSet('auto','postgres','mysql','both')]
  [string]$EnginePreference = 'auto',

  [Parameter(Mandatory=$true)]
  [string]$TemplatesRoot,                     # ./templates/php (obsahuje *.psd1 šablony)

  [string]$ModulesRoot = "./modules",         # kořen submodulů; pro tabulku 'users' => ./modules/Users
  [ValidateSet('detect','snake','kebab','pascal')]
  [string]$NameResolution = 'detect',   # jak hledat cílový balíček (složku)
  [switch]$StrictSubmodules,            # vyžaduj, aby cíl byl zapsaný v .gitmodules

  [string]$BaseNamespace = "BlackCat\Database\Packages", # základ pro NAMESPACE token
  [string]$DatabaseFQN = "BlackCat\Core\Database",
  [string]$Timezone = "UTC",

  [switch]$Force,
  [switch]$WhatIf,
  [switch]$AllowUnresolved                      # pokud máš rozpracované šablony, můžeš dočasně povolit nedořešené tokeny
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------
# Helpers
# -----------------------
function Import-SchemaMap([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Schema map not found at '$Path'." }
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
  $lines = ($sql -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
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
    # array může být null
    return ($nullable ? 'array|null' : 'array')
  }
  if ($t -eq '\DateTimeImmutable') {
    return ($nullable ? '?\DateTimeImmutable' : '\DateTimeImmutable')
  }
  return ($nullable -and $t -ne 'array' -and $t -ne 'array|null') ? ("?{0}" -f $t) : $t
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
      $prefer = if ($pgPaths.Count -gt 0) { $pgPaths } else { $myPaths }
      $mapPaths = @($prefer + $othPaths)
    }
  }
}

# Odstranění nul, duplicit a neexistujících cest (pro jistotu)
$mapPaths = @($mapPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

if (-not $mapPaths -or $mapPaths.Count -eq 0) { throw "No schema maps selected." }

Write-Host "Selected maps ($($mapPaths.Count)):" -ForegroundColor Cyan
$mapPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkCyan }

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

  if ((@($cols)).Count -eq 0) { Write-Warning "No columns parsed for table '$table'."; continue }

  $classInfo = Get-ColumnClassification -columns $cols

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
    # ---- doplňkové tokeny pro všechny šablony ----
    # seznam názvů sloupců
    $colNames = @($cols | ForEach-Object { $_.Name })

    # heuristiky:
    $hasCreatedAt = $colNames -contains 'created_at'
    $hasUpdatedAt = $colNames -contains 'updated_at'
    $hasDeletedAt = $colNames -contains 'deleted_at'

    # PK: preferuj 'id', jinak první sloupec
    $pk = ($colNames | Where-Object { $_ -eq 'id' } | Select-Object -First 1)
    if (-not $pk) { $pk = $colNames[0] }

    # výchozí ORDER
    $defaultOrder =
        if ($hasCreatedAt) { 'created_at DESC, id DESC' }
        elseif ($colNames -contains 'id') { 'id DESC' }
        else { $pk + ' DESC' }

    # textové sloupce pro vyhledávání (LIKE)
    $textCols = @($cols | Where-Object {
        $_.Base -match '^(CHAR|VARCHAR|TEXT|TINYTEXT|MEDIUMTEXT|LONGTEXT)$'
    } | ForEach-Object { $_.Name })

    # --- NEW: derive dependencies from foreign keys ---
    $depNames = @()
    foreach ($fk in @($spec.foreign_keys)) {
      if ($fk -match 'REFERENCES\s+[`"]?([a-z0-9_]+)[`"]?') {
        $ref = $matches[1]
        if ($ref -and $ref -ne $table) { $depNames += "table-$ref" }
      }
    }
    $depNames = @($depNames | Sort-Object -Unique)

    # doplň tokeny:
    $tokenCommon['TABLE']                   = $table
    $tokenCommon['VIEW']                    = "vw_${table}"
    $tokenCommon['COLUMNS_ARRAY']           = (ConvertTo-PhpArray $colNames)
    $tokenCommon['PK']                      = $pk
    $tokenCommon['SOFT_DELETE_COLUMN']      = ($hasDeletedAt ? 'deleted_at' : '')
    $tokenCommon['UPDATED_AT_COLUMN']       = ($hasUpdatedAt ? 'updated_at' : '')
    $tokenCommon['VERSION_COLUMN']          = ''                      # pokud budeš používat optimistic locking
    $tokenCommon['DEFAULT_ORDER_CLAUSE']    = $defaultOrder
    $tokenCommon['UNIQUE_KEYS_ARRAY']       = '[]'                    # prozatím prázdné
    # JSON_COLUMNS_ARRAY už máš
    $tokenCommon['FILTERABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $colNames)
    $tokenCommon['SEARCHABLE_COLUMNS_ARRAY']= (ConvertTo-PhpArray $textCols)
    $tokenCommon['DEFAULT_PER_PAGE']        = '50'
    $tokenCommon['MAX_PER_PAGE']            = '500'
    $tokenCommon['VERSION']                 = '1.0.0'
    $tokenCommon['DIALECTS_ARRAY']          = "[ 'mysql', 'postgres' ]"
    $tokenCommon['INDEX_NAMES_ARRAY']       = '[]'
    $tokenCommon['FK_NAMES_ARRAY']          = '[]'
    $tokenCommon['UPSERT_KEYS_ARRAY']       = '[]'
    $tokenCommon['UPSERT_UPDATE_COLUMNS_ARRAY'] = '[]'
    $tokenCommon['JOIN_METHODS']            = ''   # šablona Joins chce [[JOIN_METHODS]]
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

Write-Host "Done." -ForegroundColor Cyan
