Param(
    [string]$PackagesDir = 'packages',

    [Alias('MapPath')]
    [string[]]$MapPaths = @(
        'scripts/schema/schema-map-postgres.yaml',
        'scripts/schema/schema-map-mysql.yaml'
    ),

    [Alias('DefsPath')]
    [string[]]$DefsPaths = @(
        'scripts/schema/schema-defs-postgres.yaml',
        'scripts/schema/schema-defs-mysql.yaml'
    ),

    [string]$RepoUrl = 'https://github.com/blackcatacademy/blackcat-database',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:EngineDiffWarnings = New-Object System.Collections.Generic.List[string]

$RegexIgnore = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

function Import-YamlOrDataFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.psd1' { return Import-PowerShellDataFile -LiteralPath $Path }
        '.yml' { break }
        '.yaml' { break }
        default { throw "Unsupported definition format: $ext" }
    }

    if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        throw "ConvertFrom-Yaml is required to read '$Path' (install PowerShell 7+ or the powershell-yaml module)."
    }

    try {
        $docs = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml -AllDocuments -ErrorAction Stop
    }
    catch {
        throw "Failed to parse '$Path': $($_.Exception.Message)"
    }

    if ($docs -is [System.Array]) {
        $docs = $docs | Where-Object { $_ }
        if ($docs.Count -gt 1) { throw "Multiple YAML documents in '$Path' are not supported (found $($docs.Count))." }
        if ($docs.Count -eq 1) { return $docs[0] }
        return $null
    }

    return $docs
}

function Get-EngineLabel {
    param([string]$Path)

    $name = [IO.Path]::GetFileName($Path).ToLowerInvariant()
    if ($name -match 'postgres') { return 'postgres' }
    if ($name -match 'mysql') { return 'mysql' }
    if ($name -match 'mariadb') { return 'mysql' }
    return ($name -replace '\.ya?ml$', '')
}

function Merge-Defs {
    param([string[]]$Paths)

    $result = @{}
    foreach ($p in $Paths) {
        $d = Import-YamlOrDataFile -Path $p
        if ($d.Tables) {
            foreach ($kv in $d.Tables.GetEnumerator()) { $result[$kv.Key] = $kv.Value }
        }
    }
    return $result
}

function Get-Maps {
    param([string[]]$Paths)

    $result = @{}
    $engineTables = @{}

    foreach ($p in $Paths) {
        $m = Import-YamlOrDataFile -Path $p
        if (-not $m.Tables) { throw "Map '$p' missing Tables section." }

        $engine = Get-EngineLabel -Path $p
        if (-not $engineTables.ContainsKey($engine)) {
            $engineTables[$engine] = [System.Collections.Generic.HashSet[string]]::new()
        }

        foreach ($kv in $m.Tables.GetEnumerator()) {
            $table = $kv.Key
            $null = $engineTables[$engine].Add($table)
            if (-not $result.ContainsKey($table)) { $result[$table] = @{} }
            $result[$table][$engine] = $kv.Value
        }
    }

    return @{
        Tables       = $result
        EngineTables = $engineTables
    }
}

function Get-IndexColumns {
    param([string]$Definition)

    if (-not $Definition) { return @() }
    $m = [regex]::Match($Definition, '\(([^)]+)\)')
    if (-not $m.Success) { return @() }

    $cols = $m.Groups[1].Value.Split(',')
    return $cols |
        ForEach-Object {
            $c = ($_ -replace '[`" ]', '')
            # strip a single pair of wrapping parens if present
            $c = $c -replace '^\((.+)\)$', '$1'
            $c = $c.Trim()
            if ($c -match '^\(?LOWER\((.+)\)\)?$') {
                $c = 'lower(' + $Matches[1] + ')'
            }
            # normalize simple function args like lower(name) -> lower(name)
            $c = $c -replace 'LOWER\((.+)\)', { 'lower(' + $args[0].Groups[1].Value + ')' }
            $c
        } |
        Where-Object { $_ }
}

function Get-InlineIndexesFromCreate {
    param([string]$CreateSql)

    $results = @()
    if (-not $CreateSql) { return $results }

    $mTable = [regex]::Match($CreateSql, '(?is)CREATE\s+TABLE.*?\((.*)\)\s*', 'Singleline')
    if (-not $mTable.Success) { return $results }
    $body = $mTable.Groups[1].Value
    $lines = $body -split "`n"
    foreach ($ln in $lines) {
        $line = $ln.Trim()
        if (-not $line) { continue }
        $mIdx = [regex]::Match($line, '^(?:UNIQUE\s+)?(?:KEY|INDEX)\s+[`"\[]?([a-z0-9_]+)[`"\]]?\s*\(([^)]+)\)', $RegexIgnore)
        $mUniq = $mIdx
        if (-not $mUniq.Success) {
            $mUniq = [regex]::Match($line, '^CONSTRAINT\s+[`"\[]?([a-z0-9_]+)[`"\]]?\s+UNIQUE\s*\(([^)]+)\)', $RegexIgnore)
        }
        if ($mUniq.Success) {
            $name = $mUniq.Groups[1].Value
            $results += [PSCustomObject]@{
                Name = $name
                Sql  = $line.TrimEnd(',')
            }
        }
    }
    return $results
}

function Get-ForeignKeys {
    param([object]$FkMap)

    $list = @()
    if (-not $FkMap) { return $list }

    $entries = @()
    if ($FkMap -is [System.Collections.IDictionary]) {
        $entries = $FkMap.GetEnumerator()
    }
    elseif ($FkMap -is [System.Collections.IEnumerable]) {
        foreach ($item in $FkMap) {
            $k = $null; $v = $null
            if ($item -is [System.Collections.DictionaryEntry]) {
                $k = $item.Key; $v = $item.Value
            }
            elseif ($item.PSObject.Properties.Match('Key').Count -gt 0) {
                $k = $item.Key; $v = $item.Value
            }
            elseif ($item.PSObject.Properties.Match('Name').Count -gt 0 -and $item.PSObject.Properties.Match('Value').Count -gt 0) {
                $k = $item.Name; $v = $item.Value
            }
            elseif ($item -is [string]) {
                $v = $item
                $mName = [regex]::Match($item, 'CONSTRAINT\s+([A-Za-z0-9_]+)', $RegexIgnore)
                if ($mName.Success) { $k = $mName.Groups[1].Value }
                $mFk = [regex]::Match($item, 'FOREIGN\s+KEY\s+[`"]?([A-Za-z0-9_]+)[`"]?', $RegexIgnore)
                if (-not $k -and $mFk.Success) { $k = $mFk.Groups[1].Value }
                if (-not $k) { $k = $item.GetHashCode().ToString() }
            }
            if ($k) { $entries += [PSCustomObject]@{ Key = $k; Value = $v } }
        }
    }

    foreach ($fk in $entries) {
        $name    = $fk.Key
        $val     = "$($fk.Value)"
        $target  = $null
        $srcCols = $null
        $tgtCols = $null
        $actions = @()

        $valFlat = ($val -replace '\s+', ' ')

        # skip constraints that are not foreign keys
        if ($valFlat -notmatch 'REFERENCES') { continue }

        $mSrc = [regex]::Match($valFlat, 'FOREIGN\s+KEY\s*\(([^)]+)\)', $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($mSrc.Success) {
            $srcCols = ($mSrc.Groups[1].Value -split ',') | ForEach-Object { $_.Trim(' `"''()') } | Where-Object { $_ }
        }
        $m = [regex]::Match($valFlat, 'REFERENCES\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*\(([^)]+)\)', $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($m.Success) {
            $target = $m.Groups[1].Value
            $tgtCols = ($m.Groups[2].Value -split ',') | ForEach-Object { $_.Trim(' `"''()') } | Where-Object { $_ }
        }

        $onUpd = [regex]::Match($valFlat, 'ON\s+UPDATE\s+([A-Z_]+)', $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($onUpd.Success) { $actions += ('ON UPDATE ' + $onUpd.Groups[1].Value.ToUpperInvariant()) }

        $onDel = [regex]::Match($valFlat, 'ON\s+DELETE\s+([A-Z_]+)', $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($onDel.Success) { $actions += ('ON DELETE ' + $onDel.Groups[1].Value.ToUpperInvariant()) }

        $list += [PSCustomObject]@{
            Name    = $name
            Target  = $target
            SourceColumns = ($srcCols | ForEach-Object { $_.ToLowerInvariant() })
            TargetColumns = ($tgtCols | ForEach-Object { $_.ToLowerInvariant() })
            Actions = ($actions -join ', ')
        }
    }

    return $list
}

function Convert-CreateColumns {
    param([string]$CreateText)

    # preserve column order as written in the CREATE TABLE statement
    $result = [ordered]@{}
    if (-not $CreateText) { return $result }
    if ($CreateText -isnot [string]) { $CreateText = ($CreateText -join "`n") }

    $lines = $CreateText -split "`r?`n"
    foreach ($ln in $lines) {
        $trim = $ln.Trim()
        if (-not $trim) { continue }
        if ($trim -match '^create\s+table\b') { continue }
        if ($trim -match '^(primary|unique|constraint|key|index|check)\b') { continue }
        if ($trim -notmatch '^[`"\[]?[A-Za-z0-9_]+[`"\]]?\s+') { continue }

        $colName = ($trim -replace '^([`"\[]?)([A-Za-z0-9_]+)([`"\]]?)\s+.*$', '$2')
        $colNameLower = $colName.ToLowerInvariant()
        if ($colNameLower -in @('or','check')) { continue }
        $rest    = $trim.Substring($trim.IndexOf(' ') + 1)
        if ($rest -match '>=') { continue }
        # squash identity phrases so "GENERATED BY DEFAULT AS IDENTITY" does not leak "AS" as default
        $restSanitized = $rest -replace 'generated\s+(by\s+default|always)\s+as\s+identity', 'generated_identity'
        $type    = ($rest -split '\s+')[0]
        $type    = $type.Trim(',')
        $nullable = -not ($rest -match 'not\s+null')
        # identity / primary key imply NOT NULL even pokud explicitně chybí
        if ($rest -match 'primary\s+key' -or $restSanitized -match 'generated_identity') {
            $nullable = $false
        }

        $default = $null
        $m = [regex]::Match($restSanitized, 'default\s+([^ ,]+)', $RegexIgnore)
        if ($m.Success) {
            # avoid tricky quoting by using an explicit char array
            $trimChars = @("'", '"')
            $default = $m.Groups[1].Value.Trim().Trim($trimChars)
        }

        $result[$colName] = @{
            Type     = $type
            Nullable = $nullable
            Default  = $default
        }
    }

    # fallback: if nothing parsed (e.g. unexpected formatting), try a simple pattern match
    if ($result.Count -eq 0 -and $CreateText) {
        foreach ($ln in $lines) {
            $trim = $ln.Trim()
        if (-not $trim) { continue }
        if ($trim -match '^create\s+table\b') { continue }
        if ($trim -match '^(primary|unique|constraint|key|index|check)\b') { continue }
        if ($trim -notmatch '^[`"\[]?[A-Za-z0-9_]+[`"\]]?\s+') { continue }

        $tokens = $trim -split '\s+', 3
        if ($tokens.Count -lt 2) { continue }
        $colName = ($tokens[0] -replace '^[`"\[]?(.+?)[`"\]]?$', '$1')
        $colNameLower = $colName.ToLowerInvariant()
        if ($colNameLower -in @('or','check')) { continue }
        $type    = $tokens[1]
        $type = $type.Trim(',')
        $nullable = -not ($trim -match 'not\s+null')
        $default  = $null
        $m2 = [regex]::Match($trim, 'default\s+([^ ,]+)', $RegexIgnore)
        if ($m2.Success) {
            $trimChars = @("'", '"')
                $default = $m2.Groups[1].Value.Trim().Trim($trimChars)
            }
            if (-not $result.ContainsKey($colName)) {
                $result[$colName] = @{
                    Type     = $type
                    Nullable = $nullable
                    Default  = $default
                }
            }
        }

        # secondary fallback: parse the inner block between the first '(' and the final ')'
        if ($result.Count -eq 0 -and ($CreateText -match '\(')) {
            $inner = $CreateText
            $blockMatch = [regex]::Match($CreateText, '(?s)\((.*)\)')
            if ($blockMatch.Success) { $inner = $blockMatch.Groups[1].Value }

            $chunks = $inner -split ",`r?`n"
            foreach ($chunk in $chunks) {
                $trim = $chunk.Trim()
            if (-not $trim) { continue }
            if ($trim -match '^(primary|unique|constraint|key|index|check|or)\b') { continue }
            if ($trim -match '\bCHECK\b') { continue }
            if ($trim -notmatch '^[`"\[]?[A-Za-z0-9_]+[`"\]]?\s+') { continue }

            $tokens = $trim -split '\s+', 3
            if ($tokens.Count -lt 2) { continue }
            $colName = ($tokens[0] -replace '^[`"\[]?(.+?)[`"\]]?$', '$1')
            if ($colName.ToLowerInvariant() -in @('or','check')) { continue }
            $type    = $tokens[1].Trim(',')
            $nullable = -not ($trim -match 'not\s+null')
            if ($trim -match 'primary\s+key') { $nullable = $false }
            $default  = $null
            $m3 = [regex]::Match($trim, 'default\s+([^ ,]+)', $RegexIgnore)
            if ($m3.Success) {
                    $trimChars = @("'", '"')
                    $default = $m3.Groups[1].Value.Trim().Trim($trimChars)
                }
                if (-not $result.ContainsKey($colName)) {
                    $result[$colName] = @{
                        Type     = $type
                        Nullable = $nullable
                        Default  = $default
                    }
                }
            }
        }

        # tertiary fallback: simple regex over the whole text
        if ($result.Count -eq 0) {
            $colMatches = [regex]::Matches($CreateText, '^[ \t]*[`"\[]?([A-Za-z0-9_]+)[`"\]]?\s+([A-Za-z0-9_\(\)]+)', $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $colMatches) {
                $colName = $m.Groups[1].Value
                $type    = $m.Groups[2].Value
                if (-not $result.ContainsKey($colName)) {
                    $result[$colName] = @{
                        Type     = $type
                        Nullable = $true
                        Default  = $null
                    }
                }
            }
        }
    }

    return $result
}

function Convert-TypeNormalized {
    param(
        [string]$TypeText,
        [string]$Engine
    )

    if (-not $TypeText) { return '' }
    $t = $TypeText.Trim().ToUpperInvariant()

    # collapse multiple spaces
    $t = ($t -replace '\s+', ' ')
    # normalize integer families with optional lengths
    if ($t -match '^INT(\(\d+\))?$') { $t = 'INT' }
    if ($t -match '^INTEGER(\(\d+\))?$') { $t = 'INTEGER' }
    if ($t -match '^BIGSERIAL') { $t = 'BIGINT' }
    if ($t -match '^BIGINT(\s+UNSIGNED)?') { $t = 'BIGINT' }
    # normalize timestamp/datetime families
    if ($t -match '^DATETIME(\(\d+\))?$') { $t = 'TIMESTAMP' }
    if ($t -match '^TIMESTAMP( WITH(OUT)? TIME ZONE)?(\(\d+\))?$') { $t = 'TIMESTAMP' }
    if ($t -match '^TIMESTAMPTZ(\(\d+\))?$') { $t = 'TIMESTAMP' }
    if ($t -match '^INTERVAL') { $t = 'TEXT' }
    # normalize binary/blob families
    if ($t -match '^(VARBINARY|BLOB|TINYBLOB|MEDIUMBLOB|LONGBLOB)(\(\d+\))?$') { $t = 'BYTEA' }
    if ($t -match '^BINARY\(\d+\)$') { $t = 'BYTEA' }
    # normalize varchar/text and tinyint(1) boolean
    if ($t -match '^VARCHAR(\(\d+\))?,?$') { $t = 'TEXT' }
    if ($t -match '^CHAR\(36\)$') { $t = 'UUID' }
    if ($t -match '^TINYINT\(1\)$') { $t = 'BOOLEAN' }
    # normalize tinyint (non-boolean) to smallint, and large text variants to TEXT
    if ($t -match '^TINYINT(\(\d+\))?$') { $t = 'SMALLINT' }
    if ($t -match '^(MEDIUMTEXT|LONGTEXT)$') { $t = 'TEXT' }
    # normalize decimal/numeric
    if ($t -match '^DECIMAL(\([0-9, ]+\))?$') { $t = ($t -replace '^DECIMAL', 'NUMERIC') }
    if ($t -match '^NUMERIC(\([0-9, ]+\))?$') { $t = $t }
    # normalize enums -> treat as text-equivalent for drift purposes
    if ($t -match '^ENUM\(') { $t = 'TEXT' }
    # normalize MySQL SET to PG-equivalent array
    if ($t -match '^SET\(')  { $t = 'TEXT[]' }
    # normalize json/jsonb
    if ($t -eq 'JSON')  { $t = 'JSONB' }
    if ($t -eq 'JSONB') { $t = 'JSONB' }

    switch ($t) {
        'INT' { return 'INTEGER' }
        'INTEGER' { return 'INTEGER' }
        'BOOL' { return 'BOOLEAN' }
        'BOOLEAN' { return 'BOOLEAN' }
        'DOUBLE' { return 'DOUBLE PRECISION' }
        default { return $t }
    }
}

function Convert-DefaultNormalized {
    param([string]$DefaultValue)

    if ($null -eq $DefaultValue) { return '' }
    $d = $DefaultValue.Trim().ToUpperInvariant()
    switch ($d) {
        '0'     { return 'FALSE' }
        '1'     { return 'TRUE' }
        'FALSE' { return 'FALSE' }
        'TRUE'  { return 'TRUE' }
        '[]::JSONB' { return '[]' }
        \"'[]'::JSONB\" { return '[]' }
        \"[]'::JSONB\"  { return '[]' }
        default {
            if ($d -match '\[\]\s*::\s*JSONB') { return '[]' }
            if ($d -match "\[\]'\s*::\s*JSONB") { return '[]' }
            return $DefaultValue
        }
    }
}

function Get-EngineColumnMeta {
    param([hashtable]$EngineMaps)

    $meta = @{}
    foreach ($eng in $EngineMaps.Keys) {
        $createText = $EngineMaps[$eng].create
        if ($createText -isnot [string]) { $createText = ($createText -join "`n") }
        $meta[$eng] = Convert-CreateColumns -CreateText $createText
    }
    return $meta
}

function Get-ColumnFromCreate {
    param(
        [string]$CreateText,
        [string]$ColumnName
    )
    if ($CreateText -isnot [string]) { $CreateText = ($CreateText -join "`n") }
    if ([string]::IsNullOrWhiteSpace($CreateText) -or [string]::IsNullOrWhiteSpace($ColumnName)) { return $null }

    $nameLookup = $ColumnName.ToLowerInvariant()

    # line-based scan between the first "(" and the matching ")"
    $innerLines = @()
    $openSeen   = $false
    $depth      = 0
    foreach ($line in ($CreateText -split "`n")) {
        if (-not $openSeen -and $line -match '\(') { $openSeen = $true }
        if (-not $openSeen) { continue }

        $depth += ([regex]::Matches($line, '\(').Count)
        $depth -= ([regex]::Matches($line, '\)').Count)

        if ($depth -gt 0) {
            $innerLines += $line
        }
        elseif ($depth -eq 0 -and $line -match '\)') {
            break
        }
    }

    foreach ($rawLine in $innerLines) {
        $trim = $rawLine.Trim().Trim(',')
        if (-not $trim) { continue }
        if ($trim -match '^(primary|unique|constraint|index|or)\s' ) { continue }
        if ($trim -match '\bCHECK\b') { continue }

        $tokens = $trim -split '\s+', 3
        if ($tokens.Count -lt 2) { continue }

        $colToken = ($tokens[0] -replace '^[`"\[]?(.+?)[`"\]]?$', '$1')
        if ($colToken.ToLowerInvariant() -ne $nameLookup) { continue }

        $type = $tokens[1].Trim(',')
        if ([string]::IsNullOrWhiteSpace($type)) {
            $mType = [regex]::Match($trim, '^[`"\[]?[A-Za-z0-9_]+[`"\]]?\s+([A-Za-z0-9_\(\)]+)', $RegexIgnore)
            if ($mType.Success) { $type = $mType.Groups[1].Value }
        }

        $nullable = -not ($trim -match 'not\s+null')
        if ($trim -match 'primary\s+key') { $nullable = $false }

        $default = $null
        $mDef = [regex]::Match($trim, 'default\s+([^ ,]+)', $RegexIgnore)
        if ($mDef.Success) {
            $trimChars = @("'", '"')
            $default = $mDef.Groups[1].Value.Trim().Trim($trimChars)
        }

        return @{
            Type     = $type
            Nullable = $nullable
            Default  = $default
        }
    }

    # regex fallback if line-based scan failed
    $pattern = '^\\s*[`"\\[]?{0}[`"\\]]?\\s+([A-Za-z0-9_\\(\\)]+).*$'
    $pattern = $pattern -f [regex]::Escape($ColumnName)
    $m = [regex]::Match($CreateText, $pattern, $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($m.Success) {
        if ($m.Value -match '\bCHECK\b' -or $m.Value -match '>=' ) { return $null }
        $type = $m.Groups[1].Value.Trim(',')
        $nullable = -not ($m.Value -match 'not\s+null')
        $default = $null
        $mDef = [regex]::Match($m.Value, 'default\s+([^ ,]+)', $RegexIgnore)
        if ($mDef.Success) {
            $trimChars = @("'", '"')
            $default = $mDef.Groups[1].Value.Trim().Trim($trimChars)
        }
        return @{
            Type     = $type
            Nullable = $nullable
            Default  = $default
        }
    }

    return $null
}

function Get-EngineIndexMeta {
    param([hashtable]$EngineMaps)

    $meta = @{}
    foreach ($eng in $EngineMaps.Keys) {
        $idx = @{}
        if ($EngineMaps[$eng].indexes) {
            foreach ($entry in $EngineMaps[$eng].indexes.GetEnumerator()) {
                $k = $null; $v = $null
                if ($entry -is [System.Collections.DictionaryEntry]) {
                    $k = $entry.Key; $v = $entry.Value
                }
                elseif ($entry.PSObject.Properties.Match('Key').Count -gt 0) {
                    $k = $entry.Key; $v = $entry.Value
                }
                elseif ($entry.PSObject.Properties.Match('Name').Count -gt 0) {
                    $k = $entry.Name; $v = $entry.Value
                }
                elseif ($entry -is [string]) {
                    $v = $entry
                    $mName = [regex]::Match($entry, 'INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"]?([A-Za-z0-9_]+)[`"]?', $RegexIgnore)
                    if ($mName.Success) { $k = $mName.Groups[1].Value }
                    if (-not $k) { $k = $entry.GetHashCode().ToString() }
                }
                if (-not $k) { continue }
                if (-not $idx.ContainsKey($k)) {
                    $idx[$k] = @{
                        Columns = Get-IndexColumns -Definition $v
                        Raw     = $v
                    }
                }
            }
        }

        # Parse inline INDEX/KEY declarations inside CREATE TABLE text (common in MySQL maps).
        if ($EngineMaps[$eng].create) {
            $createText = $EngineMaps[$eng].create
            $inlineIdxMatches = [regex]::Matches(
                $createText,
                '^\s*(UNIQUE\s+)?(?:KEY|INDEX)\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*\(([^)]+)\)',
                $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Multiline
            )
            foreach ($m in $inlineIdxMatches) {
                $k = $m.Groups[2].Value
                if (-not $k) { continue }
                if (-not $idx.ContainsKey($k)) {
                    $cols = $m.Groups[3].Value.Split(',') | ForEach-Object { ($_ -replace '[`" ]', '') } | Where-Object { $_ }
                    $idx[$k] = @{
                        Columns = $cols
                        Raw     = $m.Value.Trim()
                    }
                }
            }

            # Inline UNIQUE constraints without explicit KEY/INDEX keywords (common in Postgres).
            $uniqueMatches = [regex]::Matches(
                $createText,
                'CONSTRAINT\s+[`"]?([A-Za-z0-9_]+)[`"]?\s+UNIQUE\s*\(([^)]+)\)',
                $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Multiline
            )
            $autoUq = 0
            foreach ($m in $uniqueMatches) {
                $k = $m.Groups[1].Value
                if (-not $k) {
                    $autoUq++
                    $k = "uq_inline_$autoUq"
                }
                if ($idx.ContainsKey($k)) { continue }
                $cols = $m.Groups[2].Value.Split(',') | ForEach-Object { ($_ -replace '[`" ]', '') } | Where-Object { $_ }
                $idx[$k] = @{
                    Columns = $cols
                    Raw     = $m.Value.Trim()
                }
            }
        }
        $meta[$eng] = $idx
    }
    return $meta
}

function Get-EngineFkMeta {
    param([hashtable]$EngineMaps)

    $meta = @{}
    foreach ($eng in $EngineMaps.Keys) {
        $fks = @()
        if ($EngineMaps[$eng].foreign_keys) {
            $fks += Get-ForeignKeys -FkMap $EngineMaps[$eng].foreign_keys
        }

        # Parse inline FK definitions from CREATE TABLE blocks.
        if ($EngineMaps[$eng].create) {
            $createText = $EngineMaps[$eng].create
            $fkMatches = [regex]::Matches(
                $createText,
                '(?:CONSTRAINT\s+[`"]?([A-Za-z0-9_]+)[`"]?\s+)?FOREIGN\s+KEY\s*\(([^)]+)\)\s+REFERENCES\s+[`"]?([A-Za-z0-9_\.]+)[`"]?\s*\(([^)]+)\)\s*([^,]*)',
                $RegexIgnore + [System.Text.RegularExpressions.RegexOptions]::Multiline
            )
            $autoCounter = 0
            foreach ($m in $fkMatches) {
                $name  = $m.Groups[1].Value
                if (-not $name) {
                    $autoCounter++
                    $name = "fk_inline_$autoCounter"
                }
                $cols  = $m.Groups[2].Value.Split(',') | ForEach-Object { ($_ -replace '[`" ]', '') } | Where-Object { $_ }
                $targetTbl = $m.Groups[3].Value
                $targetCols = $m.Groups[4].Value.Split(',') | ForEach-Object { ($_ -replace '[`" ]', '') } | Where-Object { $_ }
                $actions = $m.Groups[5].Value.Trim()
                $fks += [PSCustomObject]@{
                    Name    = $name
                    Columns = ($cols -join ',')
                    Target  = ("{0}({1})" -f $targetTbl, ($targetCols -join ','))
                    Actions = $actions
                }
            }
        }

        $meta[$eng] = $fks
    }
    return $meta
}

function Get-ViewList {
    param(
        [string]$PackagePath,
        [string]$RepoUrl,
        [string[]]$ExtraRoots = @('views-library')
    )

    $views   = @()
    $repoDir = (Resolve-Path '.').Path
    $pkgDir  = (Resolve-Path -LiteralPath $PackagePath).Path

    $roots = @($PackagePath)
    foreach ($r in $ExtraRoots) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        $rp = $r
        if (-not (Test-Path -LiteralPath $rp)) {
            $rp = Join-Path $repoDir $r
        }
        if (Test-Path -LiteralPath $rp) {
            $roots += (Resolve-Path -LiteralPath $rp).Path
        }
    }

    $files = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        $schemaDir = Join-Path $root 'schema'
        if (-not (Test-Path -LiteralPath $schemaDir)) { continue }
        $files += Get-ChildItem -LiteralPath $schemaDir -Filter '040_views*.sql' -File -ErrorAction SilentlyContinue
    }

    foreach ($f in $files) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        $engine = 'mysql'
        if ($f.Name.ToLowerInvariant() -match 'postgres') { $engine = 'postgres' }

        $alg = $null
        $sec = $null
        $algMatch = [regex]::Match($text, 'ALGORITHM=([A-Z]+)', $RegexIgnore)
        if ($algMatch.Success) { $alg = $algMatch.Groups[1].Value.ToUpperInvariant() }
        $secMatch = [regex]::Match($text, 'SECURITY\s+(DEFINER|INVOKER)', $RegexIgnore)
        if ($secMatch.Success) { $sec = $secMatch.Groups[1].Value.ToUpperInvariant() }

        $viewMatches = [regex]::Matches(
            $text,
            'create\s+(?:or\s+replace\s+)?(?:algorithm\s*=\s*[A-Z]+\s+)?(?:definer\s*=\s*\S+\s+)?(?:sql\s+security\s+\w+\s+)?view\s+[`"]?([A-Za-z0-9_]+)[`"]?',
            $RegexIgnore
        )
        foreach ($m in $viewMatches) {
            $name = $m.Groups[1].Value

            $parts = @()
            if ($alg) { $parts += ('algorithm=' + $alg) }
            if ($sec) { $parts += ('security=' + $sec) }

            $relPath = $null
            if ($f.FullName.StartsWith($pkgDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relPath = [IO.Path]::GetRelativePath($pkgDir, $f.FullName)
            } else {
                $relPath = [IO.Path]::GetRelativePath($repoDir, $f.FullName)
            }

            $views += [PSCustomObject]@{
                Name    = $name
                Engine  = $engine
                Flags   = ($parts -join ', ')
                RelPath = $relPath
                Url     = $null
            }
        }
    }

    return $views | Sort-Object -Property Name, Engine -Unique
}

function Get-SeedFiles {
    param(
        [string]$PackagePath,
        [string]$RepoUrl
    )

    $files = Get-ChildItem -LiteralPath (Join-Path $PackagePath 'schema') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'seed' }

    $result = @()
    foreach ($f in $files) {
        $engine = 'mysql'
        if ($f.Name.ToLowerInvariant() -match 'postgres') { $engine = 'postgres' }

        $url = $null
        if ($RepoUrl) {
            $url = $RepoUrl.TrimEnd('/') + '/' + [IO.Path]::GetRelativePath((Resolve-Path '.').Path, $f.FullName)
            $url = $url -replace '\\', '/'
        }

        $result += [PSCustomObject]@{
            RelPath = [IO.Path]::GetRelativePath($PackagePath, $f.FullName)
            Engine  = $engine
            Url     = $url
        }
    }

    return $result | Sort-Object -Property RelPath -Unique
}

function Write-DefinitionFile {
    param(
        [string]$OutPath,
        [string]$TableName,
        [hashtable]$EngineMaps,
        [hashtable]$DefEntry,
        [string]$PackagePath,
        [string]$RepoUrl
    )

    $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $lines.Add("# $TableName")

    $summary = $null
    if ($DefEntry -and $DefEntry.Summary) { $summary = $DefEntry.Summary }
    if ([string]::IsNullOrWhiteSpace($summary)) { $summary = 'Definition not provided.' }
    $lines.Add('')
    $lines.Add($summary.Trim())
    $docDir = Split-Path -Parent $OutPath
    $pkgRelForLinks = if ($docDir) { [IO.Path]::GetRelativePath($docDir, $PackagePath) } else { '.' }
    $pkgRelForLinks = ($pkgRelForLinks -replace '\\','/')

    if ($DefEntry -and $DefEntry.Columns) {
        $lines.Add('')
        $lines.Add('## Columns')
        $lines.Add('| Column | Type | Null | Default | Description |')
        $lines.Add('| --- | --- | --- | --- | --- |')

        # collect column metadata per engine (type, nullable, default)
        $colMetaPerEngine = @{}
        foreach ($engKey in $EngineMaps.Keys) {
            $engMap = $EngineMaps[$engKey]
            $colMetaPerEngine[$engKey] = Convert-CreateColumns -CreateText $engMap.create
        }
        $colMetaSample = $null
        foreach ($engKey in ($colMetaPerEngine.Keys | Sort-Object)) {
            $colMetaSample = $colMetaPerEngine[$engKey]
            break
        }

        $missingDesc = 0
        # Use deterministic, culture-invariant ordering so output is stable across platforms
        $colEntries = New-Object 'System.Collections.Generic.List[System.Collections.DictionaryEntry]'
        foreach ($c in $DefEntry.Columns.GetEnumerator()) { $null = $colEntries.Add($c) }
        $colsOrdered = [System.Linq.Enumerable]::OrderBy(
            $colEntries,
            [System.Func[System.Collections.DictionaryEntry,string]]{ param($e) [string]$e.Key },
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($col in $colsOrdered) {
            $desc = $col.Value.Description
            if (-not $desc) { $desc = '' }
            if ([string]::IsNullOrWhiteSpace($desc)) { $missingDesc++ }

            $suffix = ''
            $hasEnum = $false
            $enumValues = $null
            if ($col.Value) {
                if ($col.Value -is [hashtable] -and $col.Value.ContainsKey('Enum')) {
                    $hasEnum = $true
                    $enumValues = $col.Value['Enum']
                }
                elseif ($col.Value.PSObject.Properties.Match('Enum').Count -gt 0) {
                    $hasEnum = $true
                    $enumValues = $col.Value.Enum
                }
            }
            if ($hasEnum) {
                $suffix = ' (enum: ' + (($enumValues | ForEach-Object { $_ }) -join ', ') + ')'
            }

            # combine types per engine; if identical, show single type, otherwise eng:type separated by " / "
            $typeParts = @()
            $typeSet   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($engKey in ($colMetaPerEngine.Keys | Sort-Object)) {
                $engCols = $colMetaPerEngine[$engKey]
                if ($engCols -and $engCols.Contains($col.Key) -and $engCols[$col.Key].Type) {
                    $type = $engCols[$col.Key].Type
                    if (-not $typeSet.Contains($type)) { $null = $typeSet.Add($type) }
                    $typeParts += @{ Engine = $engKey; Type = $type }
                }
            }
            $colType = ''
            if ($typeParts.Count -gt 0) {
                if ($typeSet.Count -eq 1) {
                    $colType = $typeParts[0].Type
                } else {
                    $colType = ($typeParts | ForEach-Object { "{0}: {1}" -f $_.Engine, $_.Type }) -join ' / '
                }
            }

            # null/default from sample engine
            $meta = $null
            if ($colMetaSample -and $colMetaSample.Contains($col.Key)) { $meta = $colMetaSample[$col.Key] }

            $colNull = 'YES'
            $colDef  = ''
            if ($meta) {
                if (-not $meta.Nullable) { $colNull = 'NO' }
            }
            # defaults per engine
            $defParts = @()
            $defSet   = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($engKey in ($colMetaPerEngine.Keys | Sort-Object)) {
                $engCols = $colMetaPerEngine[$engKey]
                if ($engCols -and $engCols.Contains($col.Key)) {
                    $defVal = $engCols[$col.Key].Default
                    if ($null -ne $defVal -and $defVal -ne '') {
                        $txt = [string]$defVal
                        if (-not $defSet.Contains($txt)) { $null = $defSet.Add($txt) }
                        $defParts += @{ Engine = $engKey; Value = $txt }
                    }
                }
            }
            if ($defParts.Count -gt 0) {
                if ($defSet.Count -eq 1) {
                    $colDef = $defParts[0].Value
                } else {
                    $colDef = ($defParts | ForEach-Object { "{0}: {1}" -f $_.Engine, $_.Value }) -join ' / '
                }
            }

            $lines.Add( ("| {0} | {1} | {2} | {3} | {4}{5} |" -f $col.Key, $colType, $colNull, $colDef, ($desc -replace '\r?\n', '<br/>'), $suffix) )
        }

        if ($missingDesc -gt 0) {
            $lines.Add('')
            $lines.Add( ("> Note: {0} column descriptions are missing in definitions; consider filling them in." -f $missingDesc) )
        }
    }
    else {
        $lines.Add('')
        $lines.Add('> Definitions: missing for this table (no entry in defs files).')
    }

    if ($EngineMaps -and $EngineMaps.Keys.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Engine Details')

        foreach ($eng in ($EngineMaps.Keys | Sort-Object)) {
            $map = $EngineMaps[$eng]
            $lines.Add('')
            $lines.Add("### $eng")

            if ($map.PSObject.Properties.Match('DefaultOrder').Count -gt 0 -and $map.DefaultOrder) {
                $lines.Add('')
                $lines.Add( ("- Default order: `{0}` " -f $map.DefaultOrder) )
            }

            # build combined index list (explicit indexes + inline from CREATE)
            $idxEntries = @()
            if ($map.indexes) {
                foreach ($idxEntry in $map.indexes.GetEnumerator()) {
                    $idxKey = $null; $idxVal = $null
                    if ($idxEntry -is [System.Collections.DictionaryEntry]) {
                        $idxKey = $idxEntry.Key; $idxVal = $idxEntry.Value
                    }
                    elseif ($idxEntry.PSObject.Properties.Match('Key').Count -gt 0) {
                        $idxKey = $idxEntry.Key; $idxVal = $idxEntry.Value
                    }
                    elseif ($idxEntry.PSObject.Properties.Match('Name').Count -gt 0) {
                        $idxKey = $idxEntry.Name; $idxVal = $idxEntry.Value
                    }
                    elseif ($idxEntry -is [string]) {
                        $idxVal = $idxEntry
                        $mName = [regex]::Match($idxEntry, 'INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"]?([A-Za-z0-9_]+)[`"]?', $RegexIgnore)
                        if ($mName.Success) { $idxKey = $mName.Groups[1].Value }
                        if (-not $idxKey) { $idxKey = $idxEntry.GetHashCode().ToString() }
                    }
                    if ($idxKey) {
                        $idxEntries += [PSCustomObject]@{ Name = $idxKey; Sql = $idxVal }
                    }
                }
            }
            foreach ($inline in (Get-InlineIndexesFromCreate -CreateSql $map.create)) {
                if (-not ($idxEntries | Where-Object { $_.Name -eq $inline.Name })) {
                    $idxEntries += $inline
                }
            }

            if ($idxEntries.Count -gt 0) {
                # summarize PK/UNIQUE
                $pkRows      = @()
                $uniqEntries = @()
                foreach ($idxEntry in $idxEntries) {
                    $idxKey = $idxEntry.Name
                    $idxVal = $idxEntry.Sql
                    $cols = Get-IndexColumns -Definition $idxVal
                    if ($idxKey -match 'pk' -or $idxVal -match 'primary key') {
                        $pkRows += ("{0}: ({1})" -f $idxKey, ($cols -join ', '))
                    }
                    elseif ($idxKey -match 'uniq' -or $idxVal -match 'unique') {
                        $uniqEntries += [PSCustomObject]@{
                            Name    = $idxKey
                            Columns = ($cols -join ', ')
                        }
                    }
                }
                if ($pkRows.Count -gt 0)   { $lines.Add("- Primary keys: {0}" -f ($pkRows -join '; ')) }
                if ($uniqEntries.Count -gt 0) {
                    $lines.Add('')
                    $lines.Add('Unique keys:')
                    $lines.Add('| Name | Columns |')
                    $lines.Add('| --- | --- |')
                    foreach ($u in ($uniqEntries | Sort-Object Name)) {
                        $colTxt = ($u.Columns | ForEach-Object { $_ }) -join ', '
                        $lines.Add("| `{0}` | {1} |" -f @($u.Name, $colTxt))
                    }
                }

                $lines.Add('')
                $lines.Add('Indexes:')
                $lines.Add('| Name | Columns | SQL |')
                $lines.Add('| --- | --- | --- |')
                foreach ($idxEntry in $idxEntries | Sort-Object Name) {
                    $cols = Get-IndexColumns -Definition $idxEntry.Sql
                    $colText = ($cols -join ',')
                    $lines.Add("| `{0}` | {1} | {2} |" -f @($idxEntry.Name, $colText, ($idxEntry.Sql -replace '\r?\n', ' ')))
                }
            }

            if ($map.foreign_keys) {
                $lines.Add('')
                $lines.Add('Foreign keys:')
                $lines.Add('| Name | Columns | References | Actions |')
                $lines.Add('| --- | --- | --- | --- |')
                $fkParsed = Get-ForeignKeys -FkMap $map.foreign_keys
                foreach ($fk in ($fkParsed | Sort-Object Name)) {
                    if (-not $fk) { continue }
                    $fkName   = "$($fk.PSObject.Properties['Name'].Value)"
                    $srcCols  = $fk.PSObject.Properties['SourceColumns'].Value
                    if ($srcCols -is [System.Collections.IEnumerable] -and $srcCols -isnot [string]) { $srcCols = ($srcCols -join ',') }
                    $srcCols  = "$srcCols"
                    $fkTarget = "$($fk.PSObject.Properties['Target'].Value)"
                    $tgtCols  = $fk.PSObject.Properties['TargetColumns'].Value
                    if ($tgtCols -is [System.Collections.IEnumerable] -and $tgtCols -isnot [string]) { $tgtCols = ($tgtCols -join ',') }
                    $tgtCols  = "$tgtCols"
                    $fkAct    = "$($fk.PSObject.Properties['Actions'].Value)"
                    $refText  = $fkTarget
                    if ($tgtCols) { $refText = "$fkTarget($tgtCols)" }
                    $lines.Add("| `{0}` | {1} | {2} | {3} |" -f @($fkName, $srcCols, $refText, $fkAct))
                }
            }

            if ($map.PSObject.Properties.Match('Upsert').Count -gt 0 -and $map.Upsert) {
                $lines.Add('')
                $lines.Add('Upsert:')
                if ($map.Upsert.Keys)   { $lines.Add("- Keys: {0}"            -f (($map.Upsert.Keys) -join ', ')) }
                if ($map.Upsert.Update) { $lines.Add("- Update columns: {0}" -f (($map.Upsert.Update) -join ', ')) }
            }
        }
    }

    if ($EngineMaps.Keys.Count -gt 1) {
        $lines.Add('')
        $lines.Add('## Engine differences')
        $diffPayload = New-Object System.Collections.Generic.List[string]

        $defOrders = @()
        foreach ($kv in $EngineMaps.GetEnumerator()) {
            $val = $null
            if ($kv.Value.PSObject.Properties.Match('DefaultOrder').Count -gt 0) {
                $val = $kv.Value.DefaultOrder
            }
            $defOrders += @{ eng = $kv.Key; val = $val }
        }
        $distinctOrders = @($defOrders | Select-Object -ExpandProperty val | Sort-Object -Unique)
        if ($distinctOrders.Count -gt 1) {
            $defOrderText = ($defOrders |
                ForEach-Object { "{0}: {1}" -f $_.eng, $_.val } |
                Sort-Object) -join '; '
            $lines.Add("- Default order differs: " + $defOrderText)
            $diffPayload.Add("- Default order differs: " + $defOrderText)
        }

        $idxSets = @{}
        foreach ($e in $EngineMaps.GetEnumerator()) {
            $names = @()
            if ($e.Value.indexes) {
                if ($e.Value.indexes -is [System.Collections.IDictionary]) {
                    $names = @($e.Value.indexes.Keys)
                }
                else {
                    $tmp = @()
                    foreach ($it in $e.Value.indexes) {
                        if ($it -is [System.Collections.DictionaryEntry]) { $tmp += $it.Key }
                        elseif ($it.PSObject.Properties.Match('Key').Count -gt 0) { $tmp += $it.Key }
                        elseif ($it.PSObject.Properties.Match('Name').Count -gt 0) { $tmp += $it.Name }
                    }
                    $names = $tmp
                }
            }
            $set = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($n in $names) { $null = $set.Add($n) }
            $idxSets[$e.Key] = $set
        }
        if ($idxSets.Count -gt 0) {
            $firstSet = $idxSets.Values | Select-Object -First 1
            foreach ($kv in $idxSets.GetEnumerator()) {
                if (-not $firstSet.SetEquals($kv.Value)) { $lines.Add('- Index names differ across engines.'); break }
            }
        }

        $fkSets = @{}
        foreach ($e in $EngineMaps.GetEnumerator()) {
            $names = @()
            if ($e.Value.foreign_keys) {
                if ($e.Value.foreign_keys -is [System.Collections.IDictionary]) {
                    $names = @($e.Value.foreign_keys.Keys)
                }
                else {
                    $tmp = @()
                    foreach ($it in $e.Value.foreign_keys) {
                        if ($it -is [System.Collections.DictionaryEntry]) { $tmp += $it.Key }
                        elseif ($it.PSObject.Properties.Match('Key').Count -gt 0) { $tmp += $it.Key }
                        elseif ($it.PSObject.Properties.Match('Name').Count -gt 0) { $tmp += $it.Name }
                    }
                    $names = $tmp
                }
            }
            $set = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($n in $names) { $null = $set.Add($n) }
            $fkSets[$e.Key] = $set
        }
        if ($fkSets.Count -gt 0) {
            $firstFk = $fkSets.Values | Select-Object -First 1
            foreach ($kv in $fkSets.GetEnumerator()) {
                if (-not $firstFk.SetEquals($kv.Value)) { $lines.Add('- Foreign key names differ across engines.'); break }
            }
        }

        $upsertKeys = @{}
        foreach ($e in $EngineMaps.GetEnumerator()) {
            $keys = @()
            if ($e.Value.PSObject.Properties.Match('Upsert').Count -gt 0 -and $e.Value.Upsert -and $e.Value.Upsert.Keys) {
                $keys = @($e.Value.Upsert.Keys)
            }
            $upsertKeys[$e.Key] = $keys
        }
        if ($upsertKeys.Count -gt 0) {
            $distinctUpsert = @($upsertKeys.GetEnumerator() |
                Select-Object -ExpandProperty Value |
                ForEach-Object { ($_ -join ',') } |
                Sort-Object -Unique)
            if ($distinctUpsert.Count -gt 1) { $lines.Add('- Upsert keys differ across engines.') }
        }

        $engineColMeta = Get-EngineColumnMeta -EngineMaps $EngineMaps
        $engineIdxMeta = Get-EngineIndexMeta -EngineMaps $EngineMaps
        $engineFkMeta  = Get-EngineFkMeta  -EngineMaps $EngineMaps

        $allCols = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineColMeta.Values) { $allCols.UnionWith([string[]]$meta.Keys) }

        $colDrift = @()
        foreach ($c in $allCols) {
            $valsByEng = @{}
            foreach ($eng in $engineColMeta.Keys) {
                $m = $engineColMeta[$eng]
                $valStr = ''
                if ($m.Contains($c)) {
                    $v = $m[$c]
                    if ($v -is [System.Collections.DictionaryEntry]) { $v = $v.Value }
                    elseif ($v -is [string]) { $v = @{ Type = $v; Nullable = $true; Default = $null } }
                    if ($v -isnot [hashtable] -and $v.PSObject) { $v = $v | ConvertTo-Json | ConvertFrom-Json }
                    if ([string]::IsNullOrWhiteSpace($v.Type) -and $EngineMaps[$eng].create) {
                        $fallbackCol = Get-ColumnFromCreate -CreateText $EngineMaps[$eng].create -ColumnName $c
                        if ($fallbackCol) { $v = $fallbackCol }
                    }
                    $normType = Convert-TypeNormalized -TypeText $v.Type -Engine $eng
                    $nullFlag = 'YES'; if (-not $v.Nullable) { $nullFlag = 'NO' }
                    $defVal   = ''
                    if ($null -ne $v.Default) { $defVal = Convert-DefaultNormalized $v.Default }
                    if ($normType -eq 'JSONB' -and [string]::IsNullOrWhiteSpace($defVal)) { $defVal = '[]' }
                    if ([string]::IsNullOrWhiteSpace($normType) -and $defVal -match '^(TRUE|FALSE)$') {
                        $normType = 'BOOLEAN'
                    }
                    $valStr   = "type={0};null={1};def={2}" -f $normType, $nullFlag, $defVal
                }

                if ([string]::IsNullOrWhiteSpace($valStr) -and $EngineMaps[$eng].create) {
                    $fallbackCol = Get-ColumnFromCreate -CreateText $EngineMaps[$eng].create -ColumnName $c
                    if ($fallbackCol) {
                        $normType = Convert-TypeNormalized -TypeText $fallbackCol.Type -Engine $eng
                        $nullFlag = 'YES'; if (-not $fallbackCol.Nullable) { $nullFlag = 'NO' }
                        $defVal   = ''
                        if ($null -ne $fallbackCol.Default) { $defVal = Convert-DefaultNormalized $fallbackCol.Default }
                        if ($normType -eq 'JSONB' -and [string]::IsNullOrWhiteSpace($defVal)) { $defVal = '[]' }
                        if ([string]::IsNullOrWhiteSpace($normType) -and $defVal -match '^(TRUE|FALSE)$') {
                            $normType = 'BOOLEAN'
                        }
                        $valStr   = "type={0};null={1};def={2}" -f $normType, $nullFlag, $defVal
                    }
                }

                if ([string]::IsNullOrWhiteSpace($valStr) -and $DefEntry -and $DefEntry.Columns -and $DefEntry.Columns.ContainsKey($c)) {
                    $fallback = $DefEntry.Columns[$c]
                    $ftype = ''
                    if ($fallback.PSObject.Properties.Match('Type').Count -gt 0) { $ftype = $fallback.Type }
                    $fnull = $true
                    if ($fallback.PSObject.Properties.Match('Nullable').Count -gt 0) { $fnull = [bool]$fallback.Nullable }
                    $fdef = $null
                    if ($fallback.PSObject.Properties.Match('Default').Count -gt 0) { $fdef = $fallback.Default }

                    $normType = Convert-TypeNormalized -TypeText $ftype -Engine $eng
                    $nullFlag = 'YES'; if (-not $fnull) { $nullFlag = 'NO' }
                    $defVal   = ''
                    if ($null -ne $fdef) { $defVal = Convert-DefaultNormalized $fdef }
                    if ($normType -eq 'JSONB' -and [string]::IsNullOrWhiteSpace($defVal)) { $defVal = '[]' }
                    if ([string]::IsNullOrWhiteSpace($normType) -and $defVal -match '^(TRUE|FALSE)$') {
                        $normType = 'BOOLEAN'
                    }
                    $valStr   = "type={0};null={1};def={2}" -f $normType, $nullFlag, $defVal
                }
                $valsByEng[$eng] = $valStr
            }
            $distinctVals = @($valsByEng.Values | Sort-Object -Unique)
            if ($distinctVals.Count -gt 1) {
                $pairs = $valsByEng.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}:{1}" -f $_.Key, $_.Value }
                $colDrift += ("{0} => {1}" -f $c, ($pairs -join '; '))
            }
        }
        if ($colDrift.Count -gt 0) {
            $lines.Add("- Column differences: " + ($colDrift -join ' | '))
            $diffPayload.Add("- Column differences: " + ($colDrift -join ' | '))
        }

        $idxNamesUnion = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineIdxMeta.Values) { $idxNamesUnion.UnionWith([string[]]$meta.Keys) }

        $idxDrift = @()
        foreach ($ix in $idxNamesUnion) {
            if ("$ix" -match '^(?i)gin_') { continue }
            $valsByEng = @{}
            foreach ($eng in $engineIdxMeta.Keys) {
                $info = $engineIdxMeta[$eng]
                $valStr = ''
                if ($info.ContainsKey($ix)) {
                    $valStr = ($info[$ix].Columns |
                        Sort-Object |
                        ForEach-Object { $_.ToLowerInvariant() }) -join ','
                }
                $valsByEng[$eng] = $valStr
            }
            $distinctVals = @($valsByEng.Values | Sort-Object -Unique)
            if ($distinctVals.Count -gt 1) {
                $pairs = $valsByEng.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}:{1}" -f $_.Key, $_.Value }
                $idxDrift += ("{0} => {1}" -f $ix, ($pairs -join ' | '))
            }
        }
        if ($idxDrift.Count -gt 0) {
            $lines.Add("- Index column differences: " + ($idxDrift -join ' | '))
            $diffPayload.Add("- Index column differences: " + ($idxDrift -join ' | '))
        }

        $fkNamesUnion = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineFkMeta.Values) { foreach ($fk in $meta) { $null = $fkNamesUnion.Add($fk.Name) } }

        $fkDrift = @()
        foreach ($fkName in $fkNamesUnion) {
            $valsByEng = @{}
            foreach ($eng in $engineFkMeta.Keys) {
                $fkEntry = $engineFkMeta[$eng] | Where-Object { $_.Name -eq $fkName }
                if ($fkEntry -is [System.Collections.IEnumerable] -and $fkEntry -isnot [string]) {
                    $fkEntry = $fkEntry | Select-Object -First 1
                }
                $valStr = ''
                if ($fkEntry) {
                    $src = $fkEntry.PSObject.Properties['SourceColumns'].Value
                    if ($src -is [System.Collections.IEnumerable] -and $src -isnot [string]) { $src = ($src -join ',') }
                    $tgtCols = $fkEntry.PSObject.Properties['TargetColumns'].Value
                    if ($tgtCols -is [System.Collections.IEnumerable] -and $tgtCols -isnot [string]) { $tgtCols = ($tgtCols -join ',') }
                    $tgt = $fkEntry.PSObject.Properties['Target'].Value
                    $ref = $tgt
                    if ($tgtCols) { $ref = "$tgt($tgtCols)" }
                    $act = $fkEntry.PSObject.Properties['Actions'].Value
                    $valStr = "cols=({0})->{1};{2}" -f $src, $ref, $act
                }
                $valsByEng[$eng] = $valStr
            }
            $distinctVals = @($valsByEng.Values | Sort-Object -Unique)
            if ($distinctVals.Count -gt 1) {
                $pairs = $valsByEng.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}:{1}" -f $_.Key, $_.Value }
                $fkDrift += ("{0} => {1}" -f $fkName, ($pairs -join ' | '))
            }
        }
        if ($fkDrift.Count -gt 0) {
            $lines.Add("- Foreign key differences: " + ($fkDrift -join ' | '))
            $diffPayload.Add("- Foreign key differences: " + ($fkDrift -join ' | '))
        }

        if ($diffPayload.Count -gt 0) {
            $tableTag = $TableName
            $payload  = ($diffPayload -join ' ')
            $script:EngineDiffWarnings.Add( ("{0}: {1}" -f $tableTag, $payload) )
        }
    }

    # collect views for each engine present in maps (from package schema + views-library)
    $views = @()
    $engList = @()
    if ($EngineMaps) { $engList = @($EngineMaps.Keys | Sort-Object -Unique) }
    if (-not $engList -or $engList.Count -eq 0) { $engList = @('mysql','postgres') }
    foreach ($eng in $engList) {
        $views += (Get-ViewList -PackagePath $PackagePath -RepoUrl $RepoUrl -ExtraRoots @('views-library') |
            Where-Object { $_.Engine -eq $eng })
    }
    if ($views.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Views')
        $lines.Add('| View | Engine | Flags | File |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($v in $views) {
            $rel = ($v.RelPath -replace '\\','/')
            if ($pkgRelForLinks -and $pkgRelForLinks -ne '.') {
                $rel = ("{0}/{1}" -f ($pkgRelForLinks.TrimEnd('/')), $rel)
            }
            $link = $rel
            $flags = ''
            if ($v.Flags) { $flags = $v.Flags }
            $lineArgs = @($v.Name, $v.Engine, $flags, $rel, $link)
            $lines.Add(("| {0} | {1} | {2} | [{3}]({4}) |" -f $lineArgs))
        }

        $engViewSets = @{}
        foreach ($g in ($views | Group-Object Engine)) {
            $set = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($v in $g.Group) { $null = $set.Add($v.Name) }
            $engViewSets[$g.Name] = $set
        }

        if ($engViewSets.Keys.Count -gt 1) {
            $first = $engViewSets.Values | Select-Object -First 1
            foreach ($kv in $engViewSets.GetEnumerator()) {
                if (-not $first.SetEquals($kv.Value)) { $lines.Add('> Warning: view names differ across engines.'); break }
            }

            $engViewMeta = @{}
            foreach ($g in ($views | Group-Object Engine)) {
                $tmp = @{}
                foreach ($v in $g.Group) { $tmp[$v.Name] = $v.Flags }
                $engViewMeta[$g.Name] = $tmp
            }

            $allViewNames = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($m in $engViewMeta.Values) { $allViewNames.UnionWith([string[]]$m.Keys) }

            $flagDrift = @()
            foreach ($vn in $allViewNames) {
                $vals = @()
                $nonEmpty = @()
                foreach ($eng in $engViewMeta.Keys) {
                    $flag = ''
                    if ($engViewMeta[$eng].ContainsKey($vn)) { $flag = $engViewMeta[$eng][$vn] }
                    $vals += ("{0}:{1}" -f $eng, $flag)
                    if ($flag) { $nonEmpty += ("{0}:{1}" -f $eng, $flag) }
                }
                $distinctNonEmpty = @($nonEmpty | Sort-Object -Unique)
                if ($distinctNonEmpty.Count -gt 1) { $flagDrift += ("{0} => {1}" -f $vn, ($vals -join '; ')) }
            }

            if ($flagDrift.Count -gt 0) {
                $lines.Add("> Warning: view flags (algorithm/security) differ across engines: " + ($flagDrift -join ' | '))
            }
        }
    }

    $seeds = @((Get-SeedFiles -PackagePath $PackagePath -RepoUrl $RepoUrl))
    if ($seeds.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Seed files')
        $lines.Add('| Engine | File |')
        $lines.Add('| --- | --- |')
        foreach ($s in $seeds) {
            $link = $s.RelPath
            if ($s.Url) { $link = $s.Url }
            $lines.Add("| {0} | [{1}]({2}) |" -f $s.Engine, $s.RelPath, $link)
        }
        $lines.Add('')
        $lines.Add("> Note: {0} seed file(s) present; ensure tests account for initial data." -f $seeds.Count)
    }

    $content   = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $dir       = Split-Path -Parent $OutPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($OutPath, $content, $utf8NoBom)
}

if (-not (Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir '$PackagesDir' not found." }
foreach ($mp in $MapPaths)  { if (-not (Test-Path -LiteralPath $mp)) { throw "MapPath '$mp' not found." } }
foreach ($dp in $DefsPaths) { if (-not (Test-Path -LiteralPath $dp)) { throw "DefsPath '$dp' not found." } }

    $mapData      = Get-Maps -Paths $MapPaths
$allMaps      = $mapData.Tables
$engineTables = $mapData.EngineTables
$allDefs      = Merge-Defs -Paths $DefsPaths

$engines       = $engineTables.Keys
$allTableNames = [System.Collections.Generic.HashSet[string]]::new()
foreach ($set in $engineTables.Values) { $allTableNames.UnionWith($set) }

$missingErrors = @()
foreach ($eng in $engines) {
    $set = $engineTables[$eng]
    $missing = @()
    foreach ($t in $allTableNames) { if (-not $set.Contains($t)) { $missing += $t } }
    if ($missing.Count -gt 0) { $missingErrors += ("{0} missing tables: {1}" -f $eng, (($missing | Sort-Object) -join ', ')) }
}
if ($missingErrors.Count -gt 0) {
    throw ("Schema completeness check failed:`n{0}" -f ($missingErrors -join "`n"))
}

function Get-PackagePath {
    param([string]$Root, [string]$TableName)

    $candidates = @(
        (Join-Path $Root $TableName),
        (Join-Path $Root ($TableName -replace '_','-')),
        (Join-Path $Root ($TableName.ToLowerInvariant())),
        (Join-Path $Root (($TableName -replace '_','-').ToLowerInvariant()))
    ) | Select-Object -Unique

    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

foreach ($table in ($allMaps.Keys | Sort-Object)) {
    $pkgPath = Get-PackagePath -Root $PackagesDir -TableName $table
    if (-not $pkgPath) {
        Write-Warning ("Package folder not found for table '{0}' under '{1}'; tried variations with hyphens/lowercase." -f $table, $PackagesDir)
        continue
    }

    $defEntry = $null
    if ($allDefs.ContainsKey($table)) { $defEntry = $allDefs[$table] }

    $outPath = Join-Path $pkgPath 'docs/definitions.md'
    if (-not $Force -and (Test-Path -LiteralPath $outPath)) {
        Write-Host "Skipping $table (docs/definitions.md exists). Use -Force to overwrite."
        continue
    }

    Write-Host "Writing definitions for $table -> $outPath"
    Write-DefinitionFile -OutPath $outPath -TableName $table -EngineMaps $allMaps[$table] -DefEntry $defEntry -PackagePath $pkgPath -RepoUrl $RepoUrl
}

if ($EngineDiffWarnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Engine drift summary:"
    foreach ($w in ($EngineDiffWarnings | Sort-Object)) {
        Write-Host (" - {0}" -f $w)
    }
}
