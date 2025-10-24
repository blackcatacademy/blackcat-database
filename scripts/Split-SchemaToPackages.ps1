param(
  [string]$InDir = (Join-Path $PSScriptRoot 'schema'),
  [string]$PackagesDir = (Join-Path (Join-Path $PSScriptRoot '..') 'packages'),
  [ValidateSet('mysql','postgres')]
  [string[]]$Engine = @('mysql','postgres'),
  [ValidateSet('detect','snake','kebab','pascal')]
  [string]$NameResolution = 'detect',
  [switch]$CommitPush,
  [switch]$Force,
  [switch]$CleanupLegacy
)

# --- utils s "approved verbs" ---
function Add-SemicolonIfMissing {
  param([Parameter(Mandatory)][string]$Text)
  $t = $Text.Trim()
  if ($t -notmatch ';$') { return "$t;`n" } else { return "$t`n" }
}
function ConvertTo-PascalCase {
  param([Parameter(Mandatory)][string]$Text)
  ($Text -split '[_\-\s]+' | ForEach-Object {
    if ($_ -ne '') { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
  }) -join ''
}

function New-DirectoryIfMissing {
  param([Parameter(Mandatory)][string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
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

function Import-MapFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Engine)
  if (!(Test-Path -LiteralPath $Path)) {
    Write-Warning "SKIP [$Engine] – mapa nenalezena: $Path"
    return $null
  }
  try { return Import-PowerShellDataFile -Path $Path }
  catch {
    throw "Nepodařilo se načíst mapu '$Path': $($_.Exception.Message)"
  }
}

function Get-StableMapStamp {
  param([Parameter(Mandatory=$true)][string]$MapPath)
  try {
    $sha = (& git log -1 --format=%h -- $MapPath 2>$null).Trim()
    if ($sha) { return "map@$sha" }
  } catch {}
  $mt = (Get-Item -LiteralPath $MapPath).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
  return "map@mtime:$mt"
}

function Remove-LegacyFiles {
  param([Parameter(Mandatory)][string]$SchemaDir)
  $legacy = @(
    # staré společné názvy
    '001_table.sql','020_indexes.sql','030_foreign_keys.sql',
    # legacy názvy views (neengine-specific)
    '004_views_contract.sql','004_view_contract.sql','040_view_contract.sql'
  )
  # také zkusíme engine-suffixed legacy varianty
  $engines = @('mysql','postgres')
  foreach ($e in $engines) {
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

# --- hlavní logika ---
Write-Host "Input maps dir:  $InDir"
Write-Host "Packages dir:    $PackagesDir"
Write-Host "Engines:         $($Engine -join ', ')"

foreach ($eng in $Engine) {
  $mapPath = Join-Path $InDir "schema-map-$eng.psd1"
  $map = Import-MapFile -Path $mapPath -Engine $eng
  if (-not $map) { continue }

  $tables = @($map.Tables.Keys | Sort-Object)
  $mapLeaf = Split-Path -Leaf $mapPath
  $stamp   = Get-StableMapStamp -MapPath $mapPath
  foreach ($t in $tables) {
    $pkgPath = Resolve-PackagePath -PackagesDir $PackagesDir -Table $t -Mode $NameResolution
    if (-not $pkgPath) {
      $snake = $t
      $kebab = ($t -replace '_','-')
      Write-Warning "SKIP [$t] – nenalezen submodul. Hledáno: '.\packages\$snake' a '.\packages\$kebab'."
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
    $indexes = @($spec.indexes       | Where-Object { $_ -and $_.Trim() -ne '' })
    $fks     = @($spec.foreign_keys  | Where-Object { $_ -and $_.Trim() -ne '' })

    if (-not $create) {
      Write-Warning "SKIP [$eng/$t] – chybí 'create' v mapě."
      continue
    }

    $header = @"
-- Auto-generated from $mapLeaf ($stamp)
-- engine: $eng
-- table:  $t
"@

    # 001
    $content001 = $header + "`n" + (Add-SemicolonIfMissing $create)
    Set-Content -Path $file001 -Value $content001 -NoNewline -Encoding UTF8

    # 020
    if ($indexes.Count -gt 0 -or $Force) {
      $content020 = $header + "`n" + (($indexes | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
      Set-Content -Path $file020 -Value $content020 -NoNewline -Encoding UTF8
    } elseif (Test-Path -LiteralPath $file020) { Remove-Item -LiteralPath $file020 -Force }

    # 030
    if ($fks.Count -gt 0 -or $Force) {
      $content030 = $header + "`n" + (($fks | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
      Set-Content -Path $file030 -Value $content030 -NoNewline -Encoding UTF8
    } elseif (Test-Path -LiteralPath $file030) { Remove-Item -LiteralPath $file030 -Force }

    if ($CommitPush) {
      git -C $pkgPath add schema/*.sql | Out-Null
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

  # ----- EMIT CONTRACT VIEWS pro daný engine -----
  $viewsPath = Join-Path $InDir "schema-views-$eng.psd1"
  $viewsMap  = Import-MapFile -Path $viewsPath -Engine "$eng-views"
  if ($viewsMap -and $viewsMap.Views) {
    $viewsLeaf = Split-Path -Leaf $viewsPath
    $viewsStamp = Get-StableMapStamp -MapPath $viewsPath

    foreach ($entry in $viewsMap.Views.GetEnumerator()) {
      $table = [string]$entry.Key
      $viewSql = [string]$entry.Value.create

      if ([string]::IsNullOrWhiteSpace($table) -or [string]::IsNullOrWhiteSpace($viewSql)) {
        Write-Warning "SKIP [$eng/$table] – prázdná view definice."
        continue
      }

      $pkgPath = Resolve-PackagePath -PackagesDir $PackagesDir -Table $table -Mode $NameResolution
      if (-not $pkgPath) {
        $snake = $table
        $kebab = ($table -replace '_','-')
        Write-Warning "SKIP view [$table] – nenalezen submodul. Hledáno: '.\packages\$snake' a '.\packages\$kebab'."
        continue
      }

      $schemaDir = Join-Path $pkgPath 'schema'
      New-DirectoryIfMissing -Path $schemaDir
      if ($CleanupLegacy) { Remove-LegacyFiles -SchemaDir $schemaDir }

      $file040 = Join-Path $schemaDir ("040_views.{0}.sql" -f $eng)

      $headerViews = @"
-- Auto-generated from $viewsLeaf ($viewsStamp)
-- engine: $eng
-- table:  $table
"@

      $content040 = $headerViews + "`n" + (Add-SemicolonIfMissing $viewSql)
      Set-Content -Path $file040 -Value $content040 -NoNewline -Encoding UTF8

      if ($CommitPush) {
        git -C $pkgPath add schema/*.sql | Out-Null
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
    Write-Host "No views map for engine '$eng' at $viewsPath — skipping." -ForegroundColor DarkGray
  }

}