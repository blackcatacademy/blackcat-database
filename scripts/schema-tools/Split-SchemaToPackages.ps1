param(
  [string]$InDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'schema'),
  [string]$PackagesDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'packages'),
  [ValidateSet('mysql','postgres')][string[]]$Engine = @('mysql','postgres'),
  [ValidateSet('detect','snake','kebab','pascal')][string]$NameResolution = 'detect',
  [switch]$CommitPush,
  [switch]$Force,
  [switch]$CleanupLegacy,
  [switch]$IncludeFeatureViews,
  [switch]$FailOnErrors
)

# default: always include feature views unless explicitly disabled
if (-not $IncludeFeatureViews.IsPresent) { $IncludeFeatureViews = $true }
# default: fail on errors unless explicitly overridden
if (-not $PSBoundParameters.ContainsKey('FailOnErrors')) { $FailOnErrors = $true }

$script:ViewsLibraryRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'views-library'

$script:SchemaExt = '.yaml'
$script:WarnList     = New-Object System.Collections.Generic.List[string]
$script:ErrorList    = New-Object System.Collections.Generic.List[string]
$script:ClearedFiles = New-Object 'System.Collections.Generic.HashSet[string]'
$script:FeatureNamesByEngine = @{}
$script:JoinNamesByEngine    = @{}
$script:TableNamesByEngine   = @{}
$script:TableMetaByEngine    = @{}
$script:ObjectNamesByEngine  = @{}
$script:ViewRequires         = @{}
$script:OutputTargets        = @{}
$script:EncryptionMapJsonByTable = @{}

function ConvertTo-StableJson {
  param([Parameter(Mandatory)]$Object,[int]$Depth = 20)
  $json = $Object | ConvertTo-Json -Depth $Depth
  # Normalize newlines to keep diffs stable across environments.
  return ($json -replace "`r`n","`n")
}

function ConvertTo-Bool {
  param(
    [Parameter(Mandatory)]$Value,
    [string]$Context = 'value'
  )

  if ($Value -is [bool]) { return [bool]$Value }

  if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
    return ([int64]$Value -ne 0)
  }

  if ($Value -is [string]) {
    $s = $Value.Trim()
    if ($s -eq '') { return $false }
    $s = $s.ToLowerInvariant()
    if ($s -in @('true','1','yes','y','on')) { return $true }
    if ($s -in @('false','0','no','n','off')) { return $false }
  }

  throw "Invalid boolean for $Context"
}

function Get-FkTargets {
  param([string[]]$FkStatements)
  $targets = @()
  foreach ($fk in $FkStatements) {
    $m = [regex]::Match($fk, '(?i)REFERENCES\s+([a-z0-9_]+)')
    if ($m.Success) { $targets += $m.Groups[1].Value }
  }
  return $targets
}
function Get-FkInfo {
  param([string[]]$FkStatements)
  $list = @()
  foreach ($fk in $FkStatements) {
    $target = $null
    $del = $null
    $upd = $null
    $srcCols = @()
    $tgtCols = @()
    $m = [regex]::Match($fk, '(?i)REFERENCES\s+([a-z0-9_]+)')
    if ($m.Success) { $target = $m.Groups[1].Value }
    $mDel = [regex]::Match($fk, '(?i)ON\s+DELETE\s+([a-z_]+)')
    if ($mDel.Success) { $del = $mDel.Groups[1].Value.ToLowerInvariant() }
    $mUpd = [regex]::Match($fk, '(?i)ON\s+UPDATE\s+([a-z_]+)')
    if ($mUpd.Success) { $upd = $mUpd.Groups[1].Value.ToLowerInvariant() }
    $mSrc = [regex]::Match($fk, '(?i)FOREIGN\s+KEY\s*\(([^)]+)\)')
    if ($mSrc.Success) { $srcCols = Get-ColumnsFromClause $mSrc.Groups[1].Value }
    $mTgt = [regex]::Match($fk, '(?i)REFERENCES\s+[a-z0-9_]+\s*\(([^)]+)\)')
    if ($mTgt.Success) { $tgtCols = Get-ColumnsFromClause $mTgt.Groups[1].Value }
    if (-not $target) { continue } # skip entries without REFERENCES
    if (-not $del) { $del = 'restrict' }
    if (-not $upd) { $upd = 'restrict' }
    $list += @{ target=$target; onDelete=$del; onUpdate=$upd; sourceCols=$srcCols; targetCols=$tgtCols }
  }
  return $list
}
function Get-ColumnsFromClause {
  param([string]$Text)
  if (-not $Text) { return @() }
  return ($Text -split ',' | ForEach-Object { $_.Trim(' []`"') } | Where-Object { $_ -ne '' })
}
function Get-PkColumns {
  param([string]$CreateSql)
  if (-not $CreateSql) { return @() }
  # explicit PRIMARY KEY (...)
  $m = [regex]::Match($CreateSql, '(?is)PRIMARY\s+KEY\s*\(([^)]+)\)')
  if ($m.Success) { return Get-ColumnsFromClause $m.Groups[1].Value }
  # inline "col ... PRIMARY KEY"
  $lines = $CreateSql -split "`n"
  foreach ($ln in $lines) {
    $m2 = [regex]::Match($ln, '^\s*[`"\[]?([a-z0-9_]+)[`"\]]?.*PRIMARY\s+KEY', 'IgnoreCase')
    if ($m2.Success) { return @($m2.Groups[1].Value) }
  }
  return @()
}
function Get-UniqueColumns {
  param([string]$Sql)
  $cols = @()
  if (-not $Sql) { return $cols }
  # Handle:
  #   - inline table defs: UNIQUE (col1, col2) / CONSTRAINT ... UNIQUE (...)
  #   - MySQL inline: UNIQUE KEY/INDEX name (col1, col2)
  #   - standalone indexes: CREATE UNIQUE INDEX ... ON table (col1, col2)
  $uniqueMatches = [regex]::Matches($Sql, '(?is)UNIQUE\s+(?:KEY|INDEX)?[^()]*\(([^)]+)\)')
  foreach ($m in $uniqueMatches) {
    if ($m.Success -and $m.Groups.Count -gt 1) {
      $cols += ,(Get-ColumnsFromClause $m.Groups[1].Value)
    }
  }
  return $cols
}
function Get-AllIndexNames {
  param([string]$Sql)
  $names = @()
  if (-not $Sql) { return $names }
  # standalone CREATE INDEX/UNIQUE INDEX
  $idxMatches = [regex]::Matches($Sql, '(?is)CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\[]?([a-z0-9_]+)[`"\]]?', 'IgnoreCase')
  foreach ($m in $idxMatches) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  # inline constraints: CONSTRAINT name UNIQUE (...)
  $constraint = [regex]::Matches($Sql, '(?im)^\s*CONSTRAINT\s+[`"\[]?([a-z0-9_]+)[`"\]]?\s+UNIQUE\b')
  foreach ($m in $constraint) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  # inline table defs: KEY/INDEX name (...) or UNIQUE KEY/INDEX name (...)
  $inline = [regex]::Matches($Sql, '(?im)^\s*(?:UNIQUE\s+)?(?:KEY|INDEX)\s+[`"\[]?([a-z0-9_]+)[`"\]]?', 'IgnoreCase')
  foreach ($m in $inline) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  return $names
}
function Get-UniqueIndexNames {
  param([string]$Sql)
  $names = @()
  if (-not $Sql) { return $names }
  # standalone CREATE UNIQUE INDEX
  $idxMatches = [regex]::Matches($Sql, '(?is)CREATE\s+UNIQUE\s+INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\[]?([a-z0-9_]+)[`"\]]?', 'IgnoreCase')
  foreach ($m in $idxMatches) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  # inline constraints: CONSTRAINT name UNIQUE (...)
  $constraint = [regex]::Matches($Sql, '(?im)^\s*CONSTRAINT\s+[`"\[]?([a-z0-9_]+)[`"\]]?\s+UNIQUE\b')
  foreach ($m in $constraint) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  # inline table defs: UNIQUE KEY/INDEX name (...)
  $inline = [regex]::Matches($Sql, '(?im)^\s*UNIQUE\s+(?:KEY|INDEX)\s+[`"\[]?([a-z0-9_]+)[`"\]]?', 'IgnoreCase')
  foreach ($m in $inline) {
    if ($m.Success -and $m.Groups.Count -gt 1) { $names += $m.Groups[1].Value }
  }
  return $names
}
function ConvertTo-NormalizedSet {
  param([string[]]$Items)
  if (-not $Items) { return @() }
  return @($Items | Sort-Object -Unique)
}
function Get-ColumnInfo {
  param([string]$CreateSql)
  $result = @{}
  if (-not $CreateSql) { return $result }
  $m = [regex]::Match($CreateSql, '(?is)CREATE\s+TABLE.*?\((.*)\)\s*', 'Singleline')
  if (-not $m.Success) { return $result }
  $body = $m.Groups[1].Value
  $lines = $body -split "`n"
  foreach ($ln in $lines) {
    $line = $ln.Trim().TrimEnd(',')
    if (-not $line) { continue }
    if ($line -match '^(PRIMARY|UNIQUE|KEY|INDEX|FOREIGN|CONSTRAINT|CHECK)\b') { continue }
    if ($line -match '^(OR|AND)\b' -or $line -match '^[()]+') { continue }
    if ($line -match '^\)') { continue }
    $mCol = [regex]::Match($line, '^\s*[`"\[]?([a-z0-9_]+)[`"\]]?\s+(.+)$', 'IgnoreCase')
    if (-not $mCol.Success) { continue }
    $name = $mCol.Groups[1].Value
    $rest = $mCol.Groups[2].Value
    $hasNotNull = ($rest -match '(?i)\bNOT\s+NULL\b')
    $isPkInline = ($rest -match '(?i)\bPRIMARY\s+KEY\b')
    $isNullable = -not ($hasNotNull -or $isPkInline)
    $result[$name] = @{ nullable = $isNullable }
  }
  return $result
}
function Register-OutputPath {
  param([string]$Path,[string]$Kind)
  if (-not $Path) { return }
  if (-not $script:OutputTargets.ContainsKey($Path)) {
    $script:OutputTargets[$Path] = $Kind
    return
  }
  $existing = $script:OutputTargets[$Path]
  if ($existing -ne $Kind) {
    Add-ErrorMessage "Output file collision: $Path already targeted by $existing and again by $Kind."
  }
}

function Warn {
  param([Parameter(Mandatory)][string]$Message)
  $script:WarnList.Add($Message)
  Microsoft.PowerShell.Utility\Write-Warning $Message
}
function Add-ErrorMessage {
  param([Parameter(Mandatory)][string]$Message)
  $script:ErrorList.Add($Message)
  Write-Host "ERROR: $Message" -ForegroundColor Red
}
function Add-SemicolonIfMissing {
  param([Parameter(Mandatory)][string]$Text)
  $t = $Text.Trim()
  if ($t -notmatch ';$') { return "$t;`n" }
  return "$t`n"
}
function ConvertTo-PascalCase {
  param([Parameter(Mandatory)][string]$Text)
  ($Text -split '[_\-\s]+' | ForEach-Object { if ($_ -ne '') { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() } }) -join ''
}
function ConvertTo-HashtableDeep {
  param($InputObject)
  if ($InputObject -is [ValueType] -or $InputObject -is [string]) { return $InputObject }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $ht = @{}
    # IMPORTANT: do NOT use "$InputObject.Keys" here because for hashtables PowerShell will
    # prefer the entry with key "Keys" over the IDictionary.Keys property (breaking maps like Upsert:{Keys:...,Update:...}).
    foreach ($entry in $InputObject.GetEnumerator()) {
      $k = $entry.Key
      $ht[$k] = ConvertTo-HashtableDeep $entry.Value
    }
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
function ConvertTo-Hashtable {
  param([Parameter(Mandatory)]$InputObject)
  if ($InputObject -is [System.Collections.IDictionary]) { return @{} + $InputObject }
  if ($InputObject -and $InputObject.PSObject) {
    $ht = @{}
    foreach ($p in $InputObject.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    return $ht
  }
  return @{}
}
function Get-ViewCreateValue {
  param($Value)
  function Extract {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [string]) {
      return ($Obj -join "`n")
    }
    if ($Obj -is [System.Collections.IDictionary]) {
      if ($Obj.Contains('create')) { return Extract $Obj['create'] }
      if ($Obj.PSObject -and $Obj.PSObject.Properties['create']) { return Extract $Obj.create }
      foreach ($v in $Obj.Values) {
        $r = Extract $v
        if ($r) { return $r }
      }
      return ($Obj.Values | ForEach-Object { [string]$_ }) -join "`n"
    }
    if ($Obj -and $Obj.PSObject) {
      if ($Obj.PSObject.Properties['create']) { return Extract $Obj.create }
      foreach ($p in $Obj.PSObject.Properties) {
        $r = Extract $p.Value
        if ($r) { return $r }
      }
    }
    if ($Obj -is [System.Collections.IEnumerable]) {
      $parts = @()
      foreach ($item in $Obj) {
        $r = Extract $item
        if ($r) { $parts += $r }
      }
      if ($parts.Count -gt 0) { return ($parts -join "`n") }
    }
    return [string]$Obj
  }

  return [string](Extract $Value)
}
function New-DirectoryIfMissing {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}
function Test-RepoChanges {
  param([Parameter(Mandatory)][string]$RepoPath)
  $s = (git -C $RepoPath status --porcelain) 2>$null
  return -not [string]::IsNullOrWhiteSpace($s)
}
function Resolve-PackagePath {
  param(
    [Parameter(Mandatory)][string]$PackagesDir,
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Mode
  )
  $snake  = $Table
  $kebab  = ($Table -replace '_','-')
  $pascal = ConvertTo-PascalCase $Table
  $candidates = switch ($Mode) {
    'snake'  { @( Join-Path $PackagesDir $snake ) }
    'kebab'  { @( Join-Path $PackagesDir $kebab ) }
    'pascal' { @( Join-Path $PackagesDir $pascal) }
    default  { @(
      (Join-Path $PackagesDir $pascal),
      (Join-Path $PackagesDir $snake),
      (Join-Path $PackagesDir $kebab)
    ) }
  }
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}
function Resolve-ViewPackagePath {
  param(
    [Parameter(Mandatory)][string]$PackagesDir,
    [Parameter(Mandatory)][string]$ViewName,
    [Parameter(Mandatory)][string]$Mode
  )
  $direct = Resolve-PackagePath -PackagesDir $PackagesDir -Table $ViewName -Mode $Mode
  if ($direct) { return $direct }

  if ($Mode -ne 'detect') {
    $auto = Resolve-PackagePath -PackagesDir $PackagesDir -Table $ViewName -Mode 'detect'
    if ($auto) { return $auto }
  }

  $parts = $ViewName -split '[-_]'
  if ($parts.Count -lt 2) { return $null }
  for ($len = $parts.Count - 1; $len -ge 1; $len--) {
    $candidate = ($parts[0..($len - 1)] -join '_')
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $path = Resolve-PackagePath -PackagesDir $PackagesDir -Table $candidate -Mode $Mode
    if ($path) {
      Write-Host "VIEW fallback: mapped '$ViewName' -> '$candidate'." -ForegroundColor DarkGray
      return $path
    }
  }
  return $null
}
function Import-YamlFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "YAML file not found: $Path" }
  # Prefer native ConvertFrom-Yaml (PS7+); accept any module providing it (e.g., powershell-yaml).
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
        throw "ConvertFrom-Yaml not available (requires PowerShell 7+ or powershell-yaml). Attempted auto-install but failed: $($_.Exception.Message)"
      }
      if (-not $cfy) {
        throw "ConvertFrom-Yaml still not available after install attempt."
      }
    }
  try {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | & $cfy
  } catch {
    throw "Failed to parse YAML '$Path' via ConvertFrom-Yaml: $($_.Exception.Message)"
  }
}
function Import-MapFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Engine)
  if (-not (Test-Path -LiteralPath $Path)) {
    Add-ErrorMessage "SKIP [$Engine] - schema map not found: $Path"
    return $null
  }
  try {
    return ConvertTo-HashtableDeep (Import-YamlFile -Path $Path)
  }
  catch { throw "Failed to load map '$Path': $($_.Exception.Message)" }
}
function Get-StableMapStamp {
  param([Parameter(Mandatory)][string]$MapPath)
  try {
    $hash = (Get-FileHash -LiteralPath $MapPath -Algorithm SHA1).Hash
    if ($hash) { return "map@sha1:$hash" }
  } catch {}
  $mt = (Get-Item -LiteralPath $MapPath).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
  return "map@mtime:$mt"
}
function Test-MySqlViewDirectives {
  param(
    [Parameter(Mandatory)][string]$ViewSql,
    [Parameter(Mandatory)][string]$ViewName,
    [Parameter(Mandatory)][string]$SourceTag
  )
  if ($ViewSql -notmatch '\bALGORITHM\s*=') { Warn "VIEW [$ViewName] in $SourceTag missing ALGORITHM directive." }
  if ($ViewSql -notmatch '\bSQL\s+SECURITY\b') { Warn "VIEW [$ViewName] in $SourceTag missing SQL SECURITY directive." }
}
function Remove-LegacyFiles {
  param([Parameter(Mandatory)][string]$SchemaDir)
  $legacy = @(
    '001_table.sql','020_indexes.sql','030_foreign_keys.sql',
    '004_views_contract.sql','004_view_contract.sql','040_view_contract.sql'
  )
  foreach ($e in @('mysql','postgres')) {
    $legacy += @("040_view_contract.$e.sql","004_views_contract.$e.sql","004_view_contract.$e.sql")
  }
  foreach ($f in $legacy) {
    $p = Join-Path $SchemaDir $f
    if (Test-Path -LiteralPath $p) {
      Remove-Item -LiteralPath $p -Force
      Write-Host "CLEANUP legacy -> $p" -ForegroundColor Yellow
    }
  }
}
function Get-FirstTableFromSql {
  param([Parameter(Mandatory)][string]$Sql)
  $clean = $Sql -replace '/\*.*?\*/',' ' -replace '--.*?$',' ' -replace '#.*?$',' ' -replace '\s+',' ' -replace '[\[\]`"()]',' '
  $m = [regex]::Matches($clean, '(?i)\b(FROM|JOIN|APPLY|LATERAL)\s+([a-z0-9_]+)')
  foreach ($match in $m) {
    $val = $match.Groups[2].Value
    if ($val -and $val -notmatch '^(select)$') { return $val }
  }
  return $null
}
function Resolve-PackageByModuleFolder {
  param([Parameter(Mandatory)][string]$PackagesDir,[Parameter(Mandatory)][string]$ModuleFolder)
  $dirs = Get-ChildItem -LiteralPath $PackagesDir -Directory -ErrorAction SilentlyContinue
  foreach ($d in $dirs) {
    $candidate = Join-Path $d.FullName ("schema/modules/{0}" -f $ModuleFolder)
    if (Test-Path -LiteralPath $candidate) { return $d.FullName }
  }
  return $null
}
function Write-ViewFile {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$ViewSql,
    [Parameter(Mandatory)][string]$Header
  )
  if (-not $script:ClearedFiles.Contains($FilePath) -and (Test-Path -LiteralPath $FilePath)) {
    Remove-Item -LiteralPath $FilePath -Force
    $script:ClearedFiles.Add($FilePath) | Out-Null
  }
  $content = $Header + "`n" + (Add-SemicolonIfMissing $ViewSql)
  if (Test-Path -LiteralPath $FilePath) {
    Add-Content -Path $FilePath -Value ("`n" + $content) -Encoding UTF8
  } else {
    Set-Content -Path $FilePath -Value $content -NoNewline -Encoding UTF8
  }
}

function Invoke-Split {
  Write-Host "Input maps dir:  $InDir"
  Write-Host "Packages dir:    $PackagesDir"
  Write-Host "Engines:         $($Engine -join ', ')"

  foreach ($eng in $Engine) {
    if (-not $script:FeatureNamesByEngine.ContainsKey($eng)) {
      $script:FeatureNamesByEngine[$eng] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if (-not $script:JoinNamesByEngine.ContainsKey($eng)) {
      $script:JoinNamesByEngine[$eng] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if (-not $script:TableNamesByEngine.ContainsKey($eng)) {
      $script:TableNamesByEngine[$eng] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if (-not $script:TableMetaByEngine.ContainsKey($eng)) {
      $script:TableMetaByEngine[$eng] = @{}
    }
    if (-not $script:ObjectNamesByEngine.ContainsKey($eng)) {
      $script:ObjectNamesByEngine[$eng] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if (-not $script:ViewRequires.ContainsKey($eng)) {
      $script:ViewRequires[$eng] = @()
    }
    $mapLeaf = "schema-map-{0}{1}" -f $eng, $script:SchemaExt
    $mapPath = Join-Path $InDir $mapLeaf
    $map = Import-MapFile -Path $mapPath -Engine $eng
    if (-not $map) { continue }
    Write-Host ("[{0}] tables: {1}" -f $eng, $map.Tables.Keys.Count)

    $tables = @($map.Tables.Keys | Sort-Object)
    $mapLeaf = Split-Path -Leaf $mapPath
    $stamp   = Get-StableMapStamp -MapPath $mapPath

    foreach ($t in $tables) {
      $null = $script:TableNamesByEngine[$eng].Add($t)
      $pkgPath = Resolve-PackagePath -PackagesDir $PackagesDir -Table $t -Mode $NameResolution
      if (-not $pkgPath) {
        $snake = $t
        $kebab = ($t -replace '_','-')
        Warn "SKIP [$t] - package submodule not found (looked for '.\\packages\\$snake' and '.\\packages\\$kebab')."
        continue
      }
      $null = $script:ObjectNamesByEngine[$eng].Add($t)

      $schemaDir = Join-Path $pkgPath 'schema'
      New-DirectoryIfMissing -Path $schemaDir
      if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaDir }

      $file001 = Join-Path $schemaDir ("001_table.$eng.sql")
      $file020 = Join-Path $schemaDir ("020_indexes.$eng.sql")
      $file030 = Join-Path $schemaDir ("030_foreign_keys.$eng.sql")

      $spec    = $map.Tables[$t]
      $create  = [string]$spec.create
      $indexes = @(
        $spec.indexes | ForEach-Object {
          if ($_ -is [string]) { $_.Trim() }
          elseif ($_ -is [hashtable] -and $_.ContainsKey('create')) { [string]$_.create }
        } | Where-Object { $_ -and $_ -ne '' }
      )
      $fks = @(
        $spec.foreign_keys | ForEach-Object {
          if ($_ -is [string]) { $_.Trim() }
          elseif ($_ -is [hashtable] -and $_.ContainsKey('create')) { [string]$_.create }
        } | Where-Object { $_ -and $_ -ne '' }
      )

      if (-not $create) {
        Add-ErrorMessage "SKIP [$eng/$t] - missing 'create' entry in schema map."
        continue
      }

      $hasInlineIdx = ($create -match '\b(INDEX|KEY)\b')
      $hasInlineFk  = ($create -match '\bFOREIGN\s+KEY\b')
      $hasPk        = ($create -match '\bPRIMARY\s+KEY\b')
      $upsertKeys   = @()
      $upsertUpdate = @()
      if ($spec.Upsert) {
        if ($spec.Upsert.Keys)   { $upsertKeys   = @($spec.Upsert.Keys)   | Where-Object { $_ -ne $null } }
        if ($spec.Upsert.Update) { $upsertUpdate = @($spec.Upsert.Update) | Where-Object { $_ -ne $null } }
      }
  $script:TableMetaByEngine[$eng][$t] = @{
        hasIndexes = ($indexes.Count -gt 0) -or $hasInlineIdx
        hasFks     = ($fks.Count -gt 0) -or $hasInlineFk
        hasPk      = $hasPk
        hasUpsert  = ($null -ne $spec.Upsert)
        hasDefaultOrder = ($null -ne $spec.DefaultOrder)
        defaultOrder = [string]$spec.DefaultOrder
        upsertKeys   = $upsertKeys
        upsertUpdate = $upsertUpdate
        updatedAt    = [string]$spec.UpdatedAt
        tags         = @($spec.Tags) | Where-Object { $_ -ne $null }
        fkTargets    = Get-FkTargets $fks
        fkInfo       = @() + (Get-FkInfo $fks)
        pkCols       = ConvertTo-NormalizedSet (Get-PkColumns $create)
        uniqueSets   = @()
        indexNamesAll    = ConvertTo-NormalizedSet (@() + (Get-AllIndexNames $create)    + ($indexes | ForEach-Object { Get-AllIndexNames $_ }))
        uniqueIndexNames = ConvertTo-NormalizedSet (@() + (Get-UniqueIndexNames $create) + ($indexes | ForEach-Object { Get-UniqueIndexNames $_ }))
        columns      = Get-ColumnInfo $create
      }
      # Manual overrides for known column parsing edge cases
      if ($t -eq 'key_usage') {
        foreach ($colName in @('encrypt_count','decrypt_count','verify_count')) {
          if ($script:TableMetaByEngine[$eng][$t].columns.ContainsKey($colName)) {
            $script:TableMetaByEngine[$eng][$t].columns[$colName].nullable = $false
          }
        }
      }
      $pkSet = ConvertTo-NormalizedSet (Get-PkColumns $create)
      if ($pkSet.Count -gt 0) { $script:TableMetaByEngine[$eng][$t].uniqueSets += ,$pkSet }
      foreach ($ix in $indexes) {
        if ($ix -match '(?i)\bUNIQUE\b') {
          $u = ConvertTo-NormalizedSet (Get-UniqueColumns $ix)
          if ($u.Count -gt 0) { $script:TableMetaByEngine[$eng][$t].uniqueSets += ,$u }
        }
      }
      # also scan inline unique in CREATE
      foreach ($uInline in Get-UniqueColumns $create) {
        if ($uInline.Count -gt 0) { $script:TableMetaByEngine[$eng][$t].uniqueSets += ,(ConvertTo-NormalizedSet $uInline) }
      }

      # --- per-package crypto instructions (encryption-map.json) ---
      $encPath = Join-Path $schemaDir 'encryption-map.json'
      Register-OutputPath -Path $encPath -Kind 'encryption-map'

      $tableColumns = @($script:TableMetaByEngine[$eng][$t].columns.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -and $_ -ne '' } | Sort-Object)
      $tableColumnsSet = @{}
      foreach ($c in $tableColumns) { $tableColumnsSet[$c.ToLowerInvariant()] = $true }

      # Optional per-table overrides in schema-map YAML:
      # Tables:
      #   users:
      #     Crypto:
      #       email_hash:
      #         strategy: hmac
      #         context: core.hmac.email
      $cryptoErrors = $false
      $cryptoSpecRaw = $null
      if ($spec -is [hashtable] -and $spec.ContainsKey('Crypto')) { $cryptoSpecRaw = $spec.Crypto }
      if ($cryptoSpecRaw -eq $null) {
        Add-ErrorMessage "Table [$t] missing Crypto block in $mapLeaf."
        $cryptoErrors = $true
      }

      $cryptoSpec = @{}
      if (-not $cryptoErrors) {
        $ht = ConvertTo-HashtableDeep $cryptoSpecRaw
        if (-not ($ht -is [hashtable])) {
          Add-ErrorMessage "Table [$t] has invalid Crypto block (expected map) in $mapLeaf."
          $cryptoErrors = $true
        } else {
          foreach ($k in $ht.Keys) {
            if (-not $k) { continue }
            $cryptoSpec[[string]$k.ToLowerInvariant()] = $ht[$k]
          }
        }
      }

      # Detect unknown column entries (typos) early.
      foreach ($k in $cryptoSpec.Keys) {
        if (-not $tableColumnsSet.ContainsKey($k)) {
          Add-ErrorMessage "Table [$t] has Crypto entry for unknown column [$k] in $mapLeaf."
          $cryptoErrors = $true
        }
      }

      $colDefs = [ordered]@{}
      if (-not $cryptoErrors) {
        foreach ($c in $tableColumns) {
          $ck = $c.ToLowerInvariant()
          if (-not $cryptoSpec.ContainsKey($ck)) {
            Add-ErrorMessage "Table [$t] missing Crypto entry for column [$c] in $mapLeaf."
            $cryptoErrors = $true
            continue
          }

          $colSpecRaw = $cryptoSpec[$ck]
          if ($colSpecRaw -is [string]) { $colSpecRaw = @{ strategy = [string]$colSpecRaw } }

          $colSpec = ConvertTo-HashtableDeep $colSpecRaw
          if (-not ($colSpec -is [hashtable])) {
            Add-ErrorMessage "Table [$t] has invalid Crypto entry for column [$c] in $mapLeaf."
            $cryptoErrors = $true
            continue
          }

          if (-not $colSpec.ContainsKey('strategy') -or [string]::IsNullOrWhiteSpace([string]$colSpec['strategy'])) {
            Add-ErrorMessage "Table [$t] missing Crypto.strategy for column [$c] in $mapLeaf."
            $cryptoErrors = $true
            continue
          }

          $strategy = ([string]$colSpec['strategy']).ToLowerInvariant()
          if ($strategy -notin @('encrypt','hmac','passthrough')) {
            Add-ErrorMessage "Table [$t] column [$c] has invalid Crypto.strategy [$strategy] in $mapLeaf."
            $cryptoErrors = $true
            continue
          }

	          if ($strategy -in @('encrypt','hmac')) {
	            $ctx = $null
	            if ($colSpec.ContainsKey('context')) { $ctx = [string]$colSpec['context'] }
	            if ([string]::IsNullOrWhiteSpace($ctx)) {
	              Add-ErrorMessage "Table [$t] column [$c] missing Crypto.context (strategy=$strategy) in $mapLeaf."
	              $cryptoErrors = $true
	              continue
	            }
	          }
	
	          # Validate references (fail fast): encrypted columns MUST have a key version column, unless explicitly disabled.
	          # Additionally, key_version + encryption_meta columns must exist and be passthrough.
	          $writeKv = $false
	          if ($strategy -in @('encrypt','hmac')) { $writeKv = $true }
	          if ($colSpec.ContainsKey('write_key_version')) {
	            try {
	              $writeKv = ConvertTo-Bool -Value $colSpec['write_key_version'] -Context "Crypto.write_key_version for $t.$c"
	            } catch {
	              Add-ErrorMessage "Table [$t] column [$c] has invalid Crypto.write_key_version (expected boolean) in $mapLeaf."
	              $cryptoErrors = $true
	              continue
	            }
	          }
	          if ($strategy -in @('encrypt','hmac') -and -not $colSpec.ContainsKey('write_key_version')) { $colSpec['write_key_version'] = $writeKv }

	          if ($writeKv) {
	            $kvc = $null
	            if ($colSpec.ContainsKey('key_version_column')) { $kvc = [string]$colSpec['key_version_column'] }
	            if ([string]::IsNullOrWhiteSpace($kvc)) { $kvc = $c + '_key_version' }
	            if (-not $colSpec.ContainsKey('key_version_column')) { $colSpec['key_version_column'] = $kvc }

	            $kvcKey = $kvc.ToLowerInvariant()
	            if (-not $tableColumnsSet.ContainsKey($kvcKey)) {
	              Add-ErrorMessage "Table [$t] column [$c] references missing key_version_column [$kvc] in $mapLeaf."
	              $cryptoErrors = $true
	            } elseif (-not $cryptoSpec.ContainsKey($kvcKey)) {
	              Add-ErrorMessage "Table [$t] column [$c] missing Crypto entry for referenced key_version_column [$kvc] in $mapLeaf."
	              $cryptoErrors = $true
	            } else {
	              $kvcRaw = $cryptoSpec[$kvcKey]
	              $kvcStrategy = $null
	              if ($kvcRaw -is [string]) { $kvcStrategy = [string]$kvcRaw }
	              else {
	                $kvcHt = ConvertTo-HashtableDeep $kvcRaw
	                if ($kvcHt -is [hashtable] -and $kvcHt.ContainsKey('strategy')) { $kvcStrategy = [string]$kvcHt['strategy'] }
	              }
	              if ([string]::IsNullOrWhiteSpace($kvcStrategy) -or $kvcStrategy.ToLowerInvariant() -ne 'passthrough') {
	                Add-ErrorMessage "Table [$t] key_version_column [$kvc] must be Crypto.strategy=passthrough in $mapLeaf."
	                $cryptoErrors = $true
	              }
	            }
	          }
	
	          $writeMeta = $false
	          if ($colSpec.ContainsKey('write_encryption_meta')) {
	            try {
	              $writeMeta = ConvertTo-Bool -Value $colSpec['write_encryption_meta'] -Context "Crypto.write_encryption_meta for $t.$c"
	            } catch {
	              Add-ErrorMessage "Table [$t] column [$c] has invalid Crypto.write_encryption_meta (expected boolean) in $mapLeaf."
	              $cryptoErrors = $true
	              continue
	            }
	          }
	          if ($writeMeta) {
	            $metaCol = $null
	            if ($colSpec.ContainsKey('encryption_meta_column')) { $metaCol = [string]$colSpec['encryption_meta_column'] }
	            if ([string]::IsNullOrWhiteSpace($metaCol)) { $metaCol = 'encryption_meta' }
	            $metaKey = $metaCol.ToLowerInvariant()
	            if (-not $tableColumnsSet.ContainsKey($metaKey)) {
	              Add-ErrorMessage "Table [$t] column [$c] references missing encryption_meta_column [$metaCol] in $mapLeaf."
	              $cryptoErrors = $true
	            } elseif (-not $cryptoSpec.ContainsKey($metaKey)) {
	              Add-ErrorMessage "Table [$t] column [$c] missing Crypto entry for referenced encryption_meta_column [$metaCol] in $mapLeaf."
	              $cryptoErrors = $true
	            } else {
	              $metaRaw = $cryptoSpec[$metaKey]
	              $metaStrategy = $null
	              if ($metaRaw -is [string]) { $metaStrategy = [string]$metaRaw }
	              else {
	                $metaHt = ConvertTo-HashtableDeep $metaRaw
	                if ($metaHt -is [hashtable] -and $metaHt.ContainsKey('strategy')) { $metaStrategy = [string]$metaHt['strategy'] }
	              }
	              if ([string]::IsNullOrWhiteSpace($metaStrategy) -or $metaStrategy.ToLowerInvariant() -ne 'passthrough') {
	                Add-ErrorMessage "Table [$t] encryption_meta_column [$metaCol] must be Crypto.strategy=passthrough in $mapLeaf."
	                $cryptoErrors = $true
	              }
	            }
	          }

	          # Stable key order for diff-friendly JSON.
	          $orderedSpec = [ordered]@{}
	          foreach ($k in @($colSpec.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
	            $orderedSpec[$k] = $colSpec[$k]
          }

          $colDefs[$c] = $orderedSpec
        }
      }

      if (-not $cryptoErrors) {
        $encObj = [ordered]@{
          tables = [ordered]@{
            $t = [ordered]@{
              columns = $colDefs
            }
          }
        }
        $encJson = ConvertTo-StableJson -Object $encObj -Depth 30

        if (-not $script:EncryptionMapJsonByTable.ContainsKey($t)) {
          $script:EncryptionMapJsonByTable[$t] = $encJson
        } else {
          $prev = [string]$script:EncryptionMapJsonByTable[$t]
          if ($prev.Trim() -ne $encJson.Trim()) {
            Add-ErrorMessage "Table [$t] encryption-map.json differs between engines (mysql vs postgres). Keep Crypto specs identical."
          }
        }

        Set-Content -Path $encPath -Value $encJson -NoNewline -Encoding UTF8
      }

        $header = "-- Auto-generated from $mapLeaf ($stamp)`n-- engine: $eng`n-- table:  $t`n"
      Register-OutputPath -Path $file001 -Kind "table:$eng"
      Set-Content -Path $file001 -Value ($header + "`n" + (Add-SemicolonIfMissing $create)) -NoNewline -Encoding UTF8

      if ($indexes.Count -gt 0 -or $Force) {
        $content020 = $header + "`n" + (($indexes | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
        Register-OutputPath -Path $file020 -Kind "indexes:$eng"
        Set-Content -Path $file020 -Value $content020 -NoNewline -Encoding UTF8
      } elseif (Test-Path -LiteralPath $file020) {
        Remove-Item -LiteralPath $file020 -Force
      }

      if ($fks.Count -gt 0 -or $Force) {
        $content030 = $header + "`n" + (($fks | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
        Register-OutputPath -Path $file030 -Kind "fks:$eng"
        Set-Content -Path $file030 -Value $content030 -NoNewline -Encoding UTF8
      } elseif (Test-Path -LiteralPath $file030) {
        Remove-Item -LiteralPath $file030 -Force
      }

      if ($CommitPush) {
        git -C $pkgPath add schema | Out-Null
        $branch = (git -C $pkgPath rev-parse --abbrev-ref HEAD).Trim()
        if (Test-RepoChanges -RepoPath $pkgPath) {
          git -C $pkgPath commit -m "chore(schema): update $t [$eng] (split from umbrella)" | Out-Null
          git -C $pkgPath push origin $branch | Out-Null
          Write-Host "PUSHED [$eng/$t] -> $branch"
        } else {
          Write-Host "NO-CHANGE [$eng/$t]"
        }
      } else {
        Write-Host "WROTE [$eng/$t] -> $schemaDir"
      }
    }

    $viewsPath = Join-Path $InDir ("schema-views-{0}{1}" -f $eng, $script:SchemaExt)
    $viewsMap  = Import-MapFile -Path $viewsPath -Engine "$eng-views"
    if ($viewsMap -and $viewsMap.Views) {
      $viewsHt = ConvertTo-HashtableDeep $viewsMap.Views
      Write-Host ("[{0}] contract views: {1}" -f $eng, $viewsHt.Keys.Count)
      $viewsLeaf  = Split-Path -Leaf $viewsPath
      $viewsStamp = Get-StableMapStamp -MapPath $viewsPath

    foreach ($entry in $viewsHt.GetEnumerator()) {
        $table    = [string]$entry.Key
        $viewSql  = Get-ViewCreateValue $entry.Value
        $ownerRaw = $null
        if ($entry.Value -is [hashtable] -and $entry.Value.ContainsKey('Owner')) {
          $ownerRaw = Get-ViewCreateValue $entry.Value['Owner']
        }
        if ($eng -eq 'mysql') { Test-MySqlViewDirectives -ViewSql $viewSql -ViewName $table -SourceTag $viewsLeaf }

        if ([string]::IsNullOrWhiteSpace($table) -or [string]::IsNullOrWhiteSpace($viewSql)) {
          Warn "SKIP [$eng/$table] - view definition is empty."
          continue
        }

        $pkgPath = $null
        if ($ownerRaw) {
          $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $ownerRaw -Mode 'detect'
          if (-not $pkgPath) { $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $ownerRaw -Mode $NameResolution }
        }
        if (-not $pkgPath) {
          $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $table -Mode 'detect'
          if (-not $pkgPath) { $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $table -Mode $NameResolution }
        }
        if (-not $pkgPath) {
          $snake = $table
          $kebab = ($table -replace '_','-')
          Add-ErrorMessage "SKIP view [$table] - package submodule not found (looked for '.\\packages\\$snake' and '.\\packages\\$kebab')."
          continue
        }

        $schemaDir = Join-Path $pkgPath 'schema'
        New-DirectoryIfMissing -Path $schemaDir
        if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaDir }

        $file040 = Join-Path $schemaDir ("040_views.{0}.sql" -f $eng)
        $headerViews = "-- Auto-generated from $viewsLeaf ($viewsStamp)`n-- engine: $eng`n-- table:  $table`n"
        Register-OutputPath -Path $file040 -Kind "views:$eng"
        Write-ViewFile -FilePath $file040 -ViewSql $viewSql -Header $headerViews

        if ($CommitPush) {
          git -C $pkgPath add schema | Out-Null
          if (Test-RepoChanges -RepoPath $pkgPath) {
            $branch = (git -C $pkgPath rev-parse --abbrev-ref HEAD).Trim()
            git -C $pkgPath commit -m "chore(schema): update $table [$eng] (views from umbrella)" | Out-Null
            git -C $pkgPath push origin $branch | Out-Null
            Write-Host "PUSHED views [$eng/$table] -> $branch"
          } else {
            Write-Host "NO-CHANGE views [$eng/$table]"
          }
        } else {
          Write-Host "WROTE views [$eng/$table] -> $schemaDir"
        }
      }
    } else {
      Write-Host "No views map for engine '$eng' at $viewsPath - skipping." -ForegroundColor DarkGray
    }

    if ($IncludeFeatureViews) {
      $featureMaps = @()
      if ($IncludeFeatureViews -and (Test-Path -LiteralPath $script:ViewsLibraryRoot)) {
        $featureMaps = Get-ChildItem -LiteralPath $script:ViewsLibraryRoot -Recurse -File |
          Where-Object { $_.Name -match ('feature.*{0}.*\.yaml$' -f [regex]::Escape($eng)) -and $_.Name -notmatch 'joins' } |
          Sort-Object FullName
      }
      if ($featureMaps.Count -eq 0) {
        Write-Host "No feature views map for engine '$eng' - skipping." -ForegroundColor DarkGray
      }
      foreach ($fm in $featureMaps) {
        $featPath = $fm.FullName
        $featMap = Import-MapFile -Path $featPath -Engine "$eng-feature-views"
        if (-not ($featMap -and $featMap.Views)) { continue }

        $featLeaf  = Split-Path -Leaf $featPath
        $featStamp = Get-StableMapStamp -MapPath $featPath
        $isModuleMap = ($featLeaf -match 'feature-modules')
        $isExtMap    = ($featLeaf -match 'feature-.+ext')
        Write-Host ("Processing feature map {0} (views: {1})" -f $featLeaf, $featMap.Views.Keys.Count) -ForegroundColor DarkGray

        # Stable order so dependent views (e.g., rollups relying on helper views) are written after their prerequisites.
        $featureEntries = (ConvertTo-HashtableDeep $featMap.Views).GetEnumerator() | Sort-Object Key
        foreach ($entry in $featureEntries) {
          $table    = [string]$entry.Key
          $viewSql  = Get-ViewCreateValue $entry.Value
          $ownerRaw = $null
          if ($entry.Value -is [hashtable] -and $entry.Value.ContainsKey('Owner')) {
            $ownerRaw = Get-ViewCreateValue $entry.Value['Owner']
          }
          $requiresRaw = @()
          if ($entry.Value -is [hashtable] -and $entry.Value.ContainsKey('Requires')) {
            $requiresRaw = @($entry.Value['Requires']) | Where-Object { $_ -ne $null }
          }
          $null = $script:FeatureNamesByEngine[$eng].Add($table)
          $null = $script:ObjectNamesByEngine[$eng].Add($table)
          if ($requiresRaw.Count -gt 0) {
            $script:ViewRequires[$eng] += @(@{ Name=$table; Requires=$requiresRaw; Source=$featLeaf })
          }
          if ($eng -eq 'mysql') { Test-MySqlViewDirectives -ViewSql $viewSql -ViewName $table -SourceTag $featLeaf }

          if ([string]::IsNullOrWhiteSpace($table) -or [string]::IsNullOrWhiteSpace($viewSql)) {
            Add-ErrorMessage "SKIP [$eng/$table] (feature:$featLeaf) - view definition is empty."
            continue
          }

          $pkgPath = $null
          $schemaDir = $null
          $targetFileName = "040_views.{0}.sql" -f $eng
          $moduleFolder = $null

          if ($isModuleMap -or $isExtMap) {
            if (-not $ownerRaw) {
              Add-ErrorMessage "SKIP view [$table] (feature:$featLeaf) - Owner missing (required for module views; use module folder name from blackcatacademy)."
              continue
            }
            $moduleFolder = $ownerRaw

            $usedFirstTableFallback = $false
            if (-not $pkgPath) {
              $firstTable = Get-FirstTableFromSql -Sql $viewSql
              if ($firstTable) {
                $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $firstTable -Mode $NameResolution
                $usedFirstTableFallback = $null -ne $pkgPath
              }
            }
            if (-not $pkgPath) {
              $pkgPath = Resolve-PackageByModuleFolder -PackagesDir $PackagesDir -ModuleFolder $moduleFolder
            }
            if (-not $pkgPath) {
              $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $table -Mode $NameResolution
            }

            if (-not $pkgPath) {
              $snake = $table
              $kebab = ($table -replace '_','-')
              Add-ErrorMessage "SKIP view [$table] (feature:$featLeaf) - module package not found (looked for first-table/table '.\\packages\\$snake' and '.\\packages\\$kebab')."
              continue
            }

            if ($usedFirstTableFallback) {
              Write-Host "Module view [$table]: resolved package via first table fallback." -ForegroundColor DarkGray
            }
            $schemaRoot = Join-Path $pkgPath 'schema'
            New-DirectoryIfMissing -Path $schemaRoot
            if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaRoot }
            $schemaDir = Join-Path $schemaRoot ("modules/{0}" -f $moduleFolder)
            New-DirectoryIfMissing -Path $schemaDir
            $targetFileName = "040_views_modules.{0}.sql" -f $eng
          } else {
            if ($ownerRaw) {
              $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $ownerRaw -Mode $NameResolution
            }
            if (-not $pkgPath) {
              $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $table -Mode $NameResolution
            }
            if (-not $pkgPath) {
              $snake = $table
              $kebab = ($table -replace '_','-')
              Add-ErrorMessage "SKIP view [$table] (feature:$featLeaf) - package submodule not found (looked for '.\\packages\\$snake' and '.\\packages\\$kebab')."
              continue
            }
            $schemaDir = Join-Path $pkgPath 'schema'
            New-DirectoryIfMissing -Path $schemaDir
            if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaDir }
          }

          $fileTarget = Join-Path $schemaDir $targetFileName
          $headerFeat = "-- Auto-generated from $featLeaf ($featStamp)`n-- engine: $eng`n-- table:  $table`n"
          Register-OutputPath -Path $fileTarget -Kind "views:$eng"
          Write-ViewFile -FilePath $fileTarget -ViewSql $viewSql -Header $headerFeat

          if ($CommitPush) {
            git -C $pkgPath add schema | Out-Null
            if (Test-RepoChanges -RepoPath $pkgPath) {
              $branch = (git -C $pkgPath rev-parse --abbrev-ref HEAD).Trim()
              git -C $pkgPath commit -m "chore(schema): update feature view $table [$eng]" | Out-Null
              git -C $pkgPath push origin $branch | Out-Null
              Write-Host "PUSHED feature view [$eng/$table] -> $branch"
            } else {
              Write-Host "NO-CHANGE feature view [$eng/$table]"
            }
          } else {
            Write-Host "WROTE feature view [$eng/$table] -> $schemaDir ($targetFileName)"
          }
        }
      }
    }

    # --- joins views (derived aggregates across tables) ---
    $joinMaps = @()
    if (Test-Path -LiteralPath $script:ViewsLibraryRoot) {
      $joinMaps = Get-ChildItem -LiteralPath $script:ViewsLibraryRoot -Recurse -File -Filter ("joins-{0}{1}" -f $eng, $script:SchemaExt) | Sort-Object FullName
    }
    $seenJoinSource = @{}
    if (-not $joinMaps) {
      $alt = Join-Path $InDir ("schema-views-joins-{0}{1}" -f $eng, $script:SchemaExt)
      if (Test-Path -LiteralPath $alt) { $joinMaps = @(Get-Item -LiteralPath $alt) }
    }
    foreach ($joinMapFile in $joinMaps) {
      $joinsMap  = Import-MapFile -Path $joinMapFile.FullName -Engine "$eng-views-joins"
      if (-not ($joinsMap -and $joinsMap.Views)) { continue }
      $joinsLeaf  = Split-Path -Leaf $joinMapFile.FullName
      $joinsRef = $joinsLeaf
      if (Test-Path -LiteralPath $script:ViewsLibraryRoot) {
        try {
          $libFull  = (Resolve-Path -LiteralPath $script:ViewsLibraryRoot).Path
          $fileFull = (Resolve-Path -LiteralPath $joinMapFile.FullName).Path
          if ($libFull -and $fileFull -and $fileFull.StartsWith($libFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $fileFull.Substring($libFull.Length).TrimStart('\','/')
            $rel = $rel.Replace('\','/')
            if ($rel) { $joinsRef = $rel }
          }
        } catch {}
      }

      Write-Host ("[{0}] join views: {1} ({2})" -f $eng, $joinsMap.Views.Keys.Count, $joinsRef)
      $joinsStamp = Get-StableMapStamp -MapPath $joinMapFile.FullName
      $joinsHt = ConvertTo-HashtableDeep $joinsMap.Views
      foreach ($entry in ($joinsHt.GetEnumerator() | Sort-Object Key)) {
        $viewName = [string]$entry.Key
        $viewSql  = Get-ViewCreateValue $entry.Value
        if ([string]::IsNullOrWhiteSpace($viewName) -or [string]::IsNullOrWhiteSpace($viewSql)) {
          Add-ErrorMessage "SKIP join view [$viewName] - view definition is empty."
          continue
        }
        if ($seenJoinSource.ContainsKey($viewName)) {
          Add-ErrorMessage "SKIP duplicate join view [$viewName] from $joinsRef (already defined in $($seenJoinSource[$viewName]))."
          continue
        }
        $seenJoinSource[$viewName] = $joinsRef
        $null = $script:JoinNamesByEngine[$eng].Add($viewName)
        $null = $script:ObjectNamesByEngine[$eng].Add($viewName)
        # Track requires for validation
        $requiresRaw = @()
        if ($entry.Value -is [hashtable] -and $entry.Value.ContainsKey('Requires')) {
          $requiresRaw = @($entry.Value['Requires']) | Where-Object { $_ -ne $null }
        }
        if ($requiresRaw.Count -gt 0) {
          $script:ViewRequires[$eng] += @(@{ Name=$viewName; Requires=$requiresRaw; Source=$joinsRef })
        }
        $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $viewName -Mode 'detect'
        if (-not $pkgPath) { $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $viewName -Mode $NameResolution }
        if (-not $pkgPath) {
          $firstTable = Get-FirstTableFromSql -Sql $viewSql
          if ($firstTable) {
            $pkgPath = Resolve-ViewPackagePath -PackagesDir $PackagesDir -ViewName $firstTable -Mode $NameResolution
            if ($pkgPath) {
              Write-Host "JOIN [$viewName]: resolved via first table '$firstTable'." -ForegroundColor DarkGray
            }
          }
        }
        if (-not $pkgPath) {
          $snake = $viewName
          $kebab = ($viewName -replace '_','-')
          Add-ErrorMessage "SKIP join view [$viewName] - package submodule not found (looked for '.\\packages\\$snake' and '.\\packages\\$kebab')."
          continue
        }
        $schemaDir = Join-Path $pkgPath 'schema'
        New-DirectoryIfMissing -Path $schemaDir
        if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaDir }

        # joins are installed alongside contract/feature views -> keep 040 prefix
        $file050 = Join-Path $schemaDir ("040_views_joins.{0}.sql" -f $eng)
        $headerJoins = "-- Auto-generated from $joinsRef ($joinsStamp)`n-- engine: $eng`n-- view:   $viewName`n"
        Register-OutputPath -Path $file050 -Kind "joins:$eng"
        Write-ViewFile -FilePath $file050 -ViewSql $viewSql -Header $headerJoins

        if ($CommitPush) {
          git -C $pkgPath add schema | Out-Null
          if (Test-RepoChanges -RepoPath $pkgPath) {
            $branch = (git -C $pkgPath rev-parse --abbrev-ref HEAD).Trim()
            git -C $pkgPath commit -m "chore(schema): update join view $viewName [$eng]" | Out-Null
            git -C $pkgPath push origin $branch | Out-Null
            Write-Host "PUSHED join view [$eng/$viewName] -> $branch"
          } else {
            Write-Host "NO-CHANGE join view [$eng/$viewName]"
          }
        } else {
          Write-Host "WROTE join view [$eng/$viewName] -> $schemaDir (040_views_joins.$eng.sql)"
        }
      }
    }
  }

  # Cross-engine consistency checks (mysql vs postgres) for feature and join maps
  $mysqlKey = 'mysql'
  $pgKey    = 'postgres'
  if ($script:FeatureNamesByEngine.ContainsKey($mysqlKey) -and $script:FeatureNamesByEngine.ContainsKey($pgKey)) {
    $missingPg = @($script:FeatureNamesByEngine[$mysqlKey] | Where-Object { -not $script:FeatureNamesByEngine[$pgKey].Contains($_) })
    $missingMy = @($script:FeatureNamesByEngine[$pgKey]    | Where-Object { -not $script:FeatureNamesByEngine[$mysqlKey].Contains($_) })
    foreach ($m in $missingPg) { Add-ErrorMessage "Feature view [$m] present in mysql maps but missing in postgres maps." }
    foreach ($m in $missingMy) { Add-ErrorMessage "Feature view [$m] present in postgres maps but missing in mysql maps." }
  }
  if ($script:JoinNamesByEngine.ContainsKey($mysqlKey) -and $script:JoinNamesByEngine.ContainsKey($pgKey)) {
    $missingPg = @($script:JoinNamesByEngine[$mysqlKey] | Where-Object { -not $script:JoinNamesByEngine[$pgKey].Contains($_) })
    $missingMy = @($script:JoinNamesByEngine[$pgKey]    | Where-Object { -not $script:JoinNamesByEngine[$mysqlKey].Contains($_) })
    foreach ($m in $missingPg) { Add-ErrorMessage "Join view [$m] present in mysql maps but missing in postgres maps." }
    foreach ($m in $missingMy) { Add-ErrorMessage "Join view [$m] present in postgres maps but missing in mysql maps." }
  }
  if ($script:TableNamesByEngine.ContainsKey($mysqlKey) -and $script:TableNamesByEngine.ContainsKey($pgKey)) {
    # Some postgres-only indexes (e.g., GIN) have no real MySQL equivalent; skip those in name comparisons.
    $pgOnlyIndexNames = @(
      'gin_auth_events_meta',
      'gin_book_assets_enc_meta',
      'gin_encrypted_fields_meta',
      'gin_event_inbox_payload',
      'gin_event_outbox_payload',
      'gin_notifications_payload',
      'gin_orders_metadata',
      'gin_payments_details',
      'gin_session_audit_meta',
      'gin_system_errors_ctx'
    )

    $missingPg = @($script:TableNamesByEngine[$mysqlKey] | Where-Object { -not $script:TableNamesByEngine[$pgKey].Contains($_) })
    $missingMy = @($script:TableNamesByEngine[$pgKey]    | Where-Object { -not $script:TableNamesByEngine[$mysqlKey].Contains($_) })
    foreach ($m in $missingPg) { Add-ErrorMessage "Table [$m] present in mysql schema map but missing in postgres schema map." }
    foreach ($m in $missingMy) { Add-ErrorMessage "Table [$m] present in postgres schema map but missing in mysql schema map." }
    # Compare optional sections (indexes / foreign_keys)
    foreach ($t in $script:TableNamesByEngine[$mysqlKey]) {
      if (-not $script:TableNamesByEngine[$pgKey].Contains($t)) { continue }
      $mMeta = $script:TableMetaByEngine[$mysqlKey][$t]
      $pMeta = $script:TableMetaByEngine[$pgKey][$t]
      if ($mMeta.hasIndexes -and -not $pMeta.hasIndexes) { Add-ErrorMessage "Table [$t] has indexes in mysql map but none in postgres map." }
      if ($pMeta.hasIndexes -and -not $mMeta.hasIndexes) { Add-ErrorMessage "Table [$t] has indexes in postgres map but none in mysql map." }
      $mIdxAll = $mMeta.indexNamesAll;       if (-not $mIdxAll) { $mIdxAll = @() }
      $pIdxAll = $pMeta.indexNamesAll;       if (-not $pIdxAll) { $pIdxAll = @() }
      $pIdxAll = $pIdxAll | Where-Object { $_ -notin $pgOnlyIndexNames }
      if ($mIdxAll.Count -gt 0 -and $pIdxAll.Count -gt 0) {
        $cmpIdxAll = @(Compare-Object -ReferenceObject $mIdxAll -DifferenceObject $pIdxAll)
        if ($cmpIdxAll.Count -gt 0) {
          Add-ErrorMessage "Table [$t] index names differ between mysql and postgres maps."
        }
      }
      $mIdxUniq = $mMeta.uniqueIndexNames;   if (-not $mIdxUniq) { $mIdxUniq = @() }
      $pIdxUniq = $pMeta.uniqueIndexNames;   if (-not $pIdxUniq) { $pIdxUniq = @() }
      $pIdxUniq = $pIdxUniq | Where-Object { $_ -notin $pgOnlyIndexNames }
      if ($mIdxUniq.Count -gt 0 -and $pIdxUniq.Count -gt 0) {
        $cmpIdxUniq = @(Compare-Object -ReferenceObject $mIdxUniq -DifferenceObject $pIdxUniq)
        if ($cmpIdxUniq.Count -gt 0) {
          Add-ErrorMessage "Table [$t] UNIQUE index names differ between mysql and postgres maps."
        }
      }
      if ($mMeta.hasFks -and -not $pMeta.hasFks) { Add-ErrorMessage "Table [$t] has foreign_keys in mysql map but none in postgres map." }
      if ($pMeta.hasFks -and -not $mMeta.hasFks) { Add-ErrorMessage "Table [$t] has foreign_keys in postgres map but none in mysql map." }
      if ($mMeta.hasPk -and -not $pMeta.hasPk) { Add-ErrorMessage "Table [$t] has PRIMARY KEY in mysql map but none detected in postgres map." }
      if ($pMeta.hasPk -and -not $mMeta.hasPk) { Add-ErrorMessage "Table [$t] has PRIMARY KEY in postgres map but none detected in mysql map." }
      if ($mMeta.hasUpsert -and -not $pMeta.hasUpsert) { Add-ErrorMessage "Table [$t] has Upsert section in mysql map but not in postgres map." }
      if ($pMeta.hasUpsert -and -not $mMeta.hasUpsert) { Add-ErrorMessage "Table [$t] has Upsert section in postgres map but not in mysql map." }
      if ($mMeta.hasDefaultOrder -and -not $pMeta.hasDefaultOrder) { Add-ErrorMessage "Table [$t] has DefaultOrder in mysql map but not in postgres map." }
      if ($pMeta.hasDefaultOrder -and -not $mMeta.hasDefaultOrder) { Add-ErrorMessage "Table [$t] has DefaultOrder in postgres map but not in mysql map." }
      if ($mMeta.hasDefaultOrder -and $pMeta.hasDefaultOrder -and $mMeta.defaultOrder -ne $pMeta.defaultOrder) {
        Add-ErrorMessage "Table [$t] has differing DefaultOrder (mysql: '$($mMeta.defaultOrder)', postgres: '$($pMeta.defaultOrder)')."
      }
      if ($mMeta.hasUpsert -and $pMeta.hasUpsert) {
        $cmpKeys = @(Compare-Object -ReferenceObject ($mMeta.upsertKeys  + @()) -DifferenceObject ($pMeta.upsertKeys  + @()))
        if ($cmpKeys.Count -gt 0) {
          Add-ErrorMessage "Table [$t] Upsert.Keys differ between mysql and postgres maps."
        }
        $cmpUpd = @(Compare-Object -ReferenceObject ($mMeta.upsertUpdate + @()) -DifferenceObject ($pMeta.upsertUpdate + @()))
        if ($cmpUpd.Count -gt 0) {
          Add-ErrorMessage "Table [$t] Upsert.Update fields differ between mysql and postgres maps."
        }
      }
      if ($mMeta.updatedAt -and -not $pMeta.updatedAt) { Add-ErrorMessage "Table [$t] has UpdatedAt in mysql map but not in postgres map." }
      if ($pMeta.updatedAt -and -not $mMeta.updatedAt) { Add-ErrorMessage "Table [$t] has UpdatedAt in postgres map but not in mysql map." }
      if ($mMeta.updatedAt -and $pMeta.updatedAt -and $mMeta.updatedAt -ne $pMeta.updatedAt) {
        Add-ErrorMessage "Table [$t] UpdatedAt differs (mysql: '$($mMeta.updatedAt)', postgres: '$($pMeta.updatedAt)')."
      }
      if ($mMeta.tags.Count -gt 0 -or $pMeta.tags.Count -gt 0) {
        $cmpTags = @(Compare-Object -ReferenceObject $mMeta.tags -DifferenceObject $pMeta.tags)
        if ($cmpTags.Count -gt 0) { Add-ErrorMessage "Table [$t] Tags differ between mysql and postgres maps." }
      }
      # Column names + nullability
      $mCols = $mMeta.columns
      $pCols = $pMeta.columns
      foreach ($col in $mCols.Keys) {
        if (-not $pCols.ContainsKey($col)) {
          Add-ErrorMessage "Table [$t] column [$col] present in mysql map but missing in postgres map."
        }
      }
      foreach ($col in $pCols.Keys) {
        if (-not $mCols.ContainsKey($col)) {
          Add-ErrorMessage "Table [$t] column [$col] present in postgres map but missing in mysql map."
        }
      }
      foreach ($col in $mCols.Keys) {
        if (-not $pCols.ContainsKey($col)) { continue }
        $mNull = $mCols[$col].nullable
        $pNull = $pCols[$col].nullable
        if ($mNull -ne $pNull) {
          $mn = if ($mNull) { 'NULL' } else { 'NOT NULL' }
          $pn = if ($pNull) { 'NULL' } else { 'NOT NULL' }
          Add-ErrorMessage "Table [$t] column [$col] nullability differs (mysql: $mn, postgres: $pn)."
        }
      }
      # PK composition
      if ($mMeta.pkCols.Count -gt 0 -or $pMeta.pkCols.Count -gt 0) {
        $cmpPk = @(Compare-Object -ReferenceObject $mMeta.pkCols -DifferenceObject $pMeta.pkCols)
        if ($cmpPk.Count -gt 0) { Add-ErrorMessage "Table [$t] PRIMARY KEY columns differ between mysql and postgres maps." }
      }
      # Unique sets comparison (as sets)
      $mU = @($mMeta.uniqueSets | ForEach-Object { ($_ | Sort-Object) -join ',' } | Sort-Object -Unique)
      $pU = @($pMeta.uniqueSets | ForEach-Object { ($_ | Sort-Object) -join ',' } | Sort-Object -Unique)
      $cmpU = @(Compare-Object -ReferenceObject $mU -DifferenceObject $pU)
      if ($cmpU.Count -gt 0) { Add-ErrorMessage "Table [$t] UNIQUE/PK key sets differ between mysql and postgres maps." }
      # FK targets present and consistent
      foreach ($fkT in ($mMeta.fkTargets + @())) {
        if (-not $script:ObjectNamesByEngine[$mysqlKey].Contains($fkT)) {
          Add-ErrorMessage "Table [$t] FK target [$fkT] missing in mysql schema maps."
        }
      }
      foreach ($fkT in ($pMeta.fkTargets + @())) {
        if (-not $script:ObjectNamesByEngine[$pgKey].Contains($fkT)) {
          Add-ErrorMessage "Table [$t] FK target [$fkT] missing in postgres schema maps."
        }
      }
      $cmpFk = @(Compare-Object -ReferenceObject ($mMeta.fkTargets + @()) -DifferenceObject ($pMeta.fkTargets + @()))
      if ($cmpFk.Count -gt 0) { Add-ErrorMessage "Table [$t] FK target set differs between mysql and postgres maps." }
      # FK actions
      if ($mMeta.fkInfo -or $pMeta.fkInfo) {
        $fmtFk = {
          param($fk)
          "$($fk.target ?? '')|del:$($fk.onDelete ?? '')|upd:$($fk.onUpdate ?? '')"
        }
        $mFk = @($mMeta.fkInfo | ForEach-Object { & $fmtFk $_ })
        $pFk = @($pMeta.fkInfo | ForEach-Object { & $fmtFk $_ })
        $cmpFkInfo = @(Compare-Object -ReferenceObject $mFk -DifferenceObject $pFk)
        if ($cmpFkInfo.Count -gt 0) {
          Add-ErrorMessage "Table [$t] FK actions differ between mysql and postgres maps."
        }
      }
      # FK target columns exist and are PK/UNIQUE in target (per engine)
      foreach ($fk in @($mMeta.fkInfo)) {
        if (-not $fk.target) { continue }
        if (-not $script:TableMetaByEngine[$mysqlKey].ContainsKey($fk.target)) { continue }
        $targetMeta = $script:TableMetaByEngine[$mysqlKey][$fk.target]
        if (-not $fk.targetCols -or $fk.targetCols.Count -eq 0) { continue }
        $tCols = ConvertTo-NormalizedSet $fk.targetCols
        if ($tCols.Count -eq 0) { continue }
        $pkCovered = ($targetMeta.pkCols -and @(Compare-Object -ReferenceObject $targetMeta.pkCols -DifferenceObject $tCols).Count -eq 0)
        $uniqueCovered = $false
        foreach ($u in $targetMeta.uniqueSets) {
          if (@(Compare-Object -ReferenceObject $u -DifferenceObject $tCols).Count -eq 0) { $uniqueCovered = $true; break }
        }
        if (-not ($pkCovered -or $uniqueCovered)) {
          Add-ErrorMessage "Table [$t] FK -> [$($fk.target)] references non-PK/UNIQUE columns in mysql map."
        }
      }
      foreach ($fk in @($pMeta.fkInfo)) {
        if (-not $fk.target) { continue }
        if (-not $script:TableMetaByEngine[$pgKey].ContainsKey($fk.target)) { continue }
        $targetMeta = $script:TableMetaByEngine[$pgKey][$fk.target]
        if (-not $fk.targetCols -or $fk.targetCols.Count -eq 0) { continue }
        $tCols = ConvertTo-NormalizedSet $fk.targetCols
        if ($tCols.Count -eq 0) { continue }
        $pkCovered = ($targetMeta.pkCols -and @(Compare-Object -ReferenceObject $targetMeta.pkCols -DifferenceObject $tCols).Count -eq 0)
        $uniqueCovered = $false
        foreach ($u in $targetMeta.uniqueSets) {
          if (@(Compare-Object -ReferenceObject $u -DifferenceObject $tCols).Count -eq 0) { $uniqueCovered = $true; break }
        }
        if (-not ($pkCovered -or $uniqueCovered)) {
          Add-ErrorMessage "Table [$t] FK -> [$($fk.target)] references non-PK/UNIQUE columns in postgres map."
        }
      }
    }
  }

  # Validate Requires for views
  foreach ($eng in $Engine) {
    if (-not $script:ViewRequires.ContainsKey($eng)) { continue }
    foreach ($req in $script:ViewRequires[$eng]) {
      foreach ($dep in $req.Requires) {
        if (-not $script:ObjectNamesByEngine[$eng].Contains($dep)) {
          Add-ErrorMessage "View [$($req.Name)] (engine:$eng, $($req.Source)) requires missing object [$dep]."
        }
      }
    }
  }

  if ($ErrorList.Count -gt 0) {
    Write-Host ("Errors emitted: {0}" -f $ErrorList.Count) -ForegroundColor Red
    $uniqueErr = $ErrorList | Group-Object | Sort-Object Count -Descending
    foreach ($u in $uniqueErr) {
      Write-Host ("  * {0} [x{1}]" -f $u.Name, $u.Count) -ForegroundColor Red
    }
  }
  if ($WarnList.Count -gt 0) {
    Write-Host ("Warnings emitted: {0}" -f $WarnList.Count) -ForegroundColor Yellow
    $unique = $WarnList | Group-Object | Sort-Object Count -Descending
    foreach ($u in $unique) {
      Write-Host ("  * {0} [x{1}]" -f $u.Name, $u.Count) -ForegroundColor DarkYellow
    }
  }

  if ($FailOnErrors -and $ErrorList.Count -gt 0) {
    exit 1
  }
}
Invoke-Split
