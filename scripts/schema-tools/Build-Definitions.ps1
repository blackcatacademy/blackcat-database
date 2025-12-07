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
    return $cols | ForEach-Object { ($_ -replace '[`" ]', '') } | Where-Object { $_ }
}

function Get-ForeignKeys {
    param([hashtable]$FkMap)

    $list = @()
    if (-not $FkMap) { return $list }

    foreach ($fk in $FkMap.GetEnumerator()) {
        $name    = $fk.Key
        $val     = $fk.Value
        $target  = $null
        $cols    = $null
        $actions = @()

        $m = [regex]::Match($val, 'REFERENCES\s+[`"]?([A-Za-z0-9_]+)[`"]?\s*\(([^)]+)\)', $RegexIgnore)
        if ($m.Success) {
            $target = $m.Groups[1].Value
            $cols   = $m.Groups[2].Value
        }

        $onUpd = [regex]::Match($val, 'ON\s+UPDATE\s+([A-Z_]+)', $RegexIgnore)
        if ($onUpd.Success) { $actions += ('ON UPDATE ' + $onUpd.Groups[1].Value.ToUpperInvariant()) }

        $onDel = [regex]::Match($val, 'ON\s+DELETE\s+([A-Z_]+)', $RegexIgnore)
        if ($onDel.Success) { $actions += ('ON DELETE ' + $onDel.Groups[1].Value.ToUpperInvariant()) }

        $list += [PSCustomObject]@{
            Name    = $name
            Target  = $target
            Columns = $cols
            Actions = ($actions -join ', ')
        }
    }

    return $list
}

function Convert-CreateColumns {
    param([string]$CreateText)

    $result = @{}
    if (-not $CreateText) { return $result }

    $lines = $CreateText -split "`r?`n"
    foreach ($ln in $lines) {
        $trim = $ln.Trim()
        if (-not $trim) { continue }
        if ($trim -match '^(primary|unique|constraint|key)\b') { continue }
        if ($trim -notmatch '^[`"\[]?[A-Za-z0-9_]+[`"\]]?\s+') { continue }

        $colName = ($trim -replace '^([`"\[]?)([A-Za-z0-9_]+)([`"\]]?)\s+.*$', '$2')
        $rest    = $trim.Substring($trim.IndexOf(' ') + 1)
        $type    = ($rest -split '\s+')[0]
        $nullable = -not ($rest -match 'not\s+null')

        $default = $null
        $m = [regex]::Match($rest, 'default\s+([^ ,]+)', $RegexIgnore)
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

    return $result
}

function Get-EngineColumnMeta {
    param([hashtable]$EngineMaps)

    $meta = @{}
    foreach ($eng in $EngineMaps.Keys) {
        $meta[$eng] = Convert-CreateColumns -CreateText $EngineMaps[$eng].create
    }
    return $meta
}

function Get-EngineIndexMeta {
    param([hashtable]$EngineMaps)

    $meta = @{}
    foreach ($eng in $EngineMaps.Keys) {
        $idx = @{}
        if ($EngineMaps[$eng].indexes) {
            foreach ($i in $EngineMaps[$eng].indexes.GetEnumerator()) {
                $idx[$i.Key] = @{
                    Columns = Get-IndexColumns -Definition $i.Value
                    Raw     = $i.Value
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
        $meta[$eng] = Get-ForeignKeys -FkMap $EngineMaps[$eng].foreign_keys
    }
    return $meta
}

function Get-ViewList {
    param(
        [string]$PackagePath,
        [string]$RepoUrl
    )

    $views = @()
    $files = Get-ChildItem -LiteralPath (Join-Path $PackagePath 'schema') -Filter '040_views*.sql' -File -ErrorAction SilentlyContinue

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

        $viewMatches = [regex]::Matches($text, 'view\s+([A-Za-z0-9_]+)', $RegexIgnore)
        foreach ($m in $viewMatches) {
            $name = $m.Groups[1].Value

            $parts = @()
            if ($alg) { $parts += ('algorithm=' + $alg) }
            if ($sec) { $parts += ('security=' + $sec) }

            $url = $null
            if ($RepoUrl) {
                $url = $RepoUrl.TrimEnd('/') + '/' + [IO.Path]::GetRelativePath((Resolve-Path '.').Path, $f.FullName)
                $url = $url -replace '\\', '/'
            }

            $views += [PSCustomObject]@{
                Name    = $name
                Engine  = $engine
                Flags   = ($parts -join ', ')
                RelPath = [IO.Path]::GetRelativePath($PackagePath, $f.FullName)
                Url     = $url
            }
        }
    }

    return $views | Sort-Object -Property Name -Unique
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

    if ($DefEntry -and $DefEntry.Columns) {
        $lines.Add('')
        $lines.Add('## Columns')
        $lines.Add('| Column | Type | Null | Default | Description |')
        $lines.Add('| --- | --- | --- | --- | --- |')

        $colMeta = @{}
        $sampleMap = $EngineMaps.Values | Select-Object -First 1
        if ($sampleMap) { $colMeta = Convert-CreateColumns -CreateText $sampleMap.create }

        $missingDesc = 0
        foreach ($col in ($DefEntry.Columns.GetEnumerator() | Sort-Object Name)) {
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
                elseif ($col.Value.PSObject.Properties.Match('Enum')) {
                    $hasEnum = $true
                    $enumValues = $col.Value.Enum
                }
            }
            if ($hasEnum) {
                $suffix = ' (enum: ' + (($enumValues | ForEach-Object { $_ }) -join ', ') + ')'
            }

            $meta = $null
            if ($colMeta.ContainsKey($col.Key)) { $meta = $colMeta[$col.Key] }

            $colType = ''
            $colNull = 'YES'
            $colDef  = ''
            if ($meta) {
                if ($meta.Type) { $colType = $meta.Type }
                if (-not $meta.Nullable) { $colNull = 'NO' }
                if ($null -ne $meta.Default) { $colDef = $meta.Default }
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

            if ($map.DefaultOrder) {
                $lines.Add('')
                $lines.Add( ("- Default order: `{0}` " -f $map.DefaultOrder) )
            }

            if ($map.indexes) {
                $pkRows   = @()
                $uniqRows = @()
                foreach ($idx in $map.indexes.GetEnumerator()) {
                    $cols = Get-IndexColumns -Definition $idx.Value
                    if ($idx.Key -match 'pk' -or $idx.Value -match 'primary key') {
                        $pkRows += ("{0}: ({1})" -f $idx.Key, ($cols -join ', '))
                    }
                    elseif ($idx.Key -match 'uniq' -or $idx.Value -match 'unique') {
                        $uniqRows += ("{0}: ({1})" -f $idx.Key, ($cols -join ', '))
                    }
                }
                if ($pkRows.Count -gt 0)   { $lines.Add("- Primary keys: {0}" -f ($pkRows -join '; ')) }
                if ($uniqRows.Count -gt 0) { $lines.Add("- Unique keys: {0}"  -f ($uniqRows -join '; ')) }
            }

            if ($map.indexes) {
                $lines.Add('')
                $lines.Add('Indexes:')
                foreach ($idx in $map.indexes.GetEnumerator() | Sort-Object Name) {
                    $lines.Add("- `{0}`: {1}" -f $idx.Key, ($idx.Value -replace '\r?\n', ' '))
                }
            }

            if ($map.foreign_keys) {
                $lines.Add('')
                $lines.Add('Foreign keys:')
                $fkParsed = Get-ForeignKeys -FkMap $map.foreign_keys
                foreach ($fk in ($fkParsed | Sort-Object Name)) {
                    $lines.Add("- `{0}`: cols=({1}) -> {2} {3}" -f $fk.Name, $fk.Columns, $fk.Target, $fk.Actions)
                }
            }

            if ($map.Upsert) {
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

        $defOrders = @()
        foreach ($kv in $EngineMaps.GetEnumerator()) { $defOrders += @{ eng = $kv.Key; val = $kv.Value.DefaultOrder } }
        $distinctOrders = $defOrders | Select-Object -ExpandProperty val | Sort-Object -Unique
        if ($distinctOrders.Count -gt 1) {
            $defOrderText = ($defOrders |
                ForEach-Object { "{0}: {1}" -f $_.eng, $_.val } |
                Sort-Object) -join '; '
            $lines.Add("- Default order differs: " + $defOrderText)
        }

        $idxSets = @{}
        foreach ($e in $EngineMaps.GetEnumerator()) {
            $names = @()
            if ($e.Value.indexes) { $names = @($e.Value.indexes.Keys) }
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
            if ($e.Value.foreign_keys) { $names = @($e.Value.foreign_keys.Keys) }
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
            if ($e.Value.Upsert -and $e.Value.Upsert.Keys) { $keys = @($e.Value.Upsert.Keys) }
            $upsertKeys[$e.Key] = $keys
        }
        if ($upsertKeys.Count -gt 0) {
            $distinctUpsert = $upsertKeys.GetEnumerator() |
                Select-Object -ExpandProperty Value |
                ForEach-Object { ($_ -join ',') } |
                Sort-Object -Unique
            if ($distinctUpsert.Count -gt 1) { $lines.Add('- Upsert keys differ across engines.') }
        }

        $engineColMeta = Get-EngineColumnMeta -EngineMaps $EngineMaps
        $engineIdxMeta = Get-EngineIndexMeta -EngineMaps $EngineMaps
        $engineFkMeta  = Get-EngineFkMeta  -EngineMaps $EngineMaps

        $allCols = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineColMeta.Values) { $allCols.UnionWith($meta.Keys) }

        $colDrift = @()
        foreach ($c in $allCols) {
            $values = @()
            foreach ($eng in $engineColMeta.Keys) {
                $m = $engineColMeta[$eng]
                $valStr = ''
                if ($m.ContainsKey($c)) {
                    $v = $m[$c]
                    $nullFlag = 'YES'; if (-not $v.Nullable) { $nullFlag = 'NO' }
                    $defVal   = ''; if ($null -ne $v.Default) { $defVal = $v.Default }
                    $valStr   = "type={0};null={1};def={2}" -f $v.Type, $nullFlag, $defVal
                }
                $values += ("{0}:{1}" -f $eng, $valStr)
            }
            if (($values | Sort-Object -Unique).Count -gt 1) { $colDrift += ("{0} => {1}" -f $c, ($values -join '; ')) }
        }
        if ($colDrift.Count -gt 0) { $lines.Add("- Column differences: " + ($colDrift -join ' | ')) }

        $idxNamesUnion = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineIdxMeta.Values) { $idxNamesUnion.UnionWith($meta.Keys) }

        $idxDrift = @()
        foreach ($ix in $idxNamesUnion) {
            $vals = @()
            foreach ($eng in $engineIdxMeta.Keys) {
                $info = $engineIdxMeta[$eng]
                $valStr = ''
                if ($info.ContainsKey($ix)) { $valStr = ($info[$ix].Columns -join ',') }
                $vals += ("{0}:{1}" -f $eng, $valStr)
            }
            if (($vals | Sort-Object -Unique).Count -gt 1) { $idxDrift += ("{0} => {1}" -f $ix, ($vals -join '; ')) }
        }
        if ($idxDrift.Count -gt 0) { $lines.Add("- Index column differences: " + ($idxDrift -join ' | ')) }

        $fkNamesUnion = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($meta in $engineFkMeta.Values) { foreach ($fk in $meta) { $null = $fkNamesUnion.Add($fk.Name) } }

        $fkDrift = @()
        foreach ($fkName in $fkNamesUnion) {
            $vals = @()
            foreach ($eng in $engineFkMeta.Keys) {
                $fkEntry = $engineFkMeta[$eng] | Where-Object { $_.Name -eq $fkName }
                $valStr = ''
                if ($fkEntry) { $valStr = "cols=({0})->{1};{2}" -f $fkEntry.Columns, $fkEntry.Target, $fkEntry.Actions }
                $vals += ("{0}:{1}" -f $eng, $valStr)
            }
            if (($vals | Sort-Object -Unique).Count -gt 1) { $fkDrift += ("{0} => {1}" -f $fkName, ($vals -join '; ')) }
        }
        if ($fkDrift.Count -gt 0) { $lines.Add("- Foreign key differences: " + ($fkDrift -join ' | ')) }
    }

    $views = Get-ViewList -PackagePath $PackagePath -RepoUrl $RepoUrl
    if ($views.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Views')
        $lines.Add('| View | Engine | Flags | File |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($v in $views) {
            $link = $v.RelPath
            if ($v.Url) { $link = $v.Url }
            $flags = ''
            if ($v.Flags) { $flags = $v.Flags }
            $lines.Add("| {0} | {1} | {2} | [{3}]({4}) |" -f $v.Name, $v.Engine, $flags, $v.RelPath, $link)
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
            foreach ($m in $engViewMeta.Values) { $allViewNames.UnionWith($m.Keys) }

            $flagDrift = @()
            foreach ($vn in $allViewNames) {
                $vals = @()
                foreach ($eng in $engViewMeta.Keys) {
                    $flag = ''
                    if ($engViewMeta[$eng].ContainsKey($vn)) { $flag = $engViewMeta[$eng][$vn] }
                    $vals += ("{0}:{1}" -f $eng, $flag)
                }
                if (($vals | Sort-Object -Unique).Count -gt 1) { $flagDrift += ("{0} => {1}" -f $vn, ($vals -join '; ')) }
            }

            if ($flagDrift.Count -gt 0) {
                $lines.Add("> Warning: view flags (algorithm/security) differ across engines: " + ($flagDrift -join ' | '))
            }
        }
    }

    $seeds = Get-SeedFiles -PackagePath $PackagePath -RepoUrl $RepoUrl
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

foreach ($table in ($allMaps.Keys | Sort-Object)) {
    $pkgPath = Join-Path $PackagesDir $table
    if (-not (Test-Path -LiteralPath $pkgPath)) {
        Write-Warning ("Package folder not found for table '{0}' ({1}); skipping." -f $table, $pkgPath)
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
