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
    return Get-Content -LiteralPath $Path -Raw | & $cfy
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
    $sha = (& git log -1 --format=%h -- $MapPath 2>$null).Trim()
    if ($sha) { return "map@$sha" }
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
    $mapLeaf = "schema-map-{0}{1}" -f $eng, $script:SchemaExt
    $mapPath = Join-Path $InDir $mapLeaf
    $map = Import-MapFile -Path $mapPath -Engine $eng
    if (-not $map) { continue }
    Write-Host ("[{0}] tables: {1}" -f $eng, $map.Tables.Keys.Count)

    $tables = @($map.Tables.Keys | Sort-Object)
    $mapLeaf = Split-Path -Leaf $mapPath
    $stamp   = Get-StableMapStamp -MapPath $mapPath

    foreach ($t in $tables) {
      $pkgPath = Resolve-PackagePath -PackagesDir $PackagesDir -Table $t -Mode $NameResolution
      if (-not $pkgPath) {
        $snake = $t
        $kebab = ($t -replace '_','-')
        Warn "SKIP [$t] - package submodule not found (looked for '.\\packages\\$snake' and '.\\packages\\$kebab')."
        continue
      }

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

        $header = "-- Auto-generated from $mapLeaf ($stamp)`n-- engine: $eng`n-- table:  $t`n"
      Set-Content -Path $file001 -Value ($header + "`n" + (Add-SemicolonIfMissing $create)) -NoNewline -Encoding UTF8

      if ($indexes.Count -gt 0 -or $Force) {
        $content020 = $header + "`n" + (($indexes | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
        Set-Content -Path $file020 -Value $content020 -NoNewline -Encoding UTF8
      } elseif (Test-Path -LiteralPath $file020) {
        Remove-Item -LiteralPath $file020 -Force
      }

      if ($fks.Count -gt 0 -or $Force) {
        $content030 = $header + "`n" + (($fks | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
        Set-Content -Path $file030 -Value $content030 -NoNewline -Encoding UTF8
      } elseif (Test-Path -LiteralPath $file030) {
        Remove-Item -LiteralPath $file030 -Force
      }

      if ($CommitPush) {
        git -C $pkgPath add schema/*.sql schema/**/*.sql | Out-Null
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
        Write-ViewFile -FilePath $file040 -ViewSql $viewSql -Header $headerViews

        if ($CommitPush) {
          git -C $pkgPath add schema/*.sql schema/**/*.sql | Out-Null
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
          Write-ViewFile -FilePath $fileTarget -ViewSql $viewSql -Header $headerFeat

          if ($CommitPush) {
            git -C $pkgPath add schema/*.sql schema/**/*.sql | Out-Null
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
    if (-not $joinMaps) {
      $alt = Join-Path $InDir ("schema-views-joins-{0}{1}" -f $eng, $script:SchemaExt)
      if (Test-Path -LiteralPath $alt) { $joinMaps = @(Get-Item -LiteralPath $alt) }
    }
    foreach ($joinMapFile in $joinMaps) {
      $joinsMap  = Import-MapFile -Path $joinMapFile.FullName -Engine "$eng-views-joins"
      if (-not ($joinsMap -and $joinsMap.Views)) { continue }
      Write-Host ("[{0}] join views: {1} ({2})" -f $eng, $joinsMap.Views.Keys.Count, $joinMapFile.Name)
      $joinsLeaf  = Split-Path -Leaf $joinMapFile.FullName
      $joinsStamp = Get-StableMapStamp -MapPath $joinMapFile.FullName
      $joinsEntries = (ConvertTo-HashtableDeep $joinsMap.Views).GetEnumerator() | Sort-Object Key
      foreach ($entry in $joinsEntries) {
        $viewName = [string]$entry.Key
        $viewSql  = Get-ViewCreateValue $entry.Value
        if ([string]::IsNullOrWhiteSpace($viewName) -or [string]::IsNullOrWhiteSpace($viewSql)) {
          Add-ErrorMessage "SKIP join view [$viewName] - view definition is empty."
          continue
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
        $headerJoins = "-- Auto-generated from $joinsLeaf ($joinsStamp)`n-- engine: $eng`n-- view:   $viewName`n"
        Write-ViewFile -FilePath $file050 -ViewSql $viewSql -Header $headerJoins

        if ($CommitPush) {
          git -C $pkgPath add schema/*.sql schema/**/*.sql | Out-Null
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
