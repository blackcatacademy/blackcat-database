param(
  [string]$MapPath   = (Join-Path $PSScriptRoot '..\schema\schema-map-postgres.yaml'),
  [string]$SchemaDir = (Join-Path $PSScriptRoot '..\schema')
)

function Import-YamlFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "YAML file not found: $Path" }
  $null = Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue
  $cfy = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
  if (-not $cfy) { throw "ConvertFrom-Yaml missing; install powershell-yaml or use PowerShell 7+" }
  Get-Content -LiteralPath $Path -Raw | & $cfy
}

function Get-FileText([string]$path) {
  if (!(Test-Path -LiteralPath $path)) { throw "Soubor nenalezen: $path" }
  return [System.IO.File]::ReadAllText((Resolve-Path $path))
}

# Regex options: Multiline (treats ^/$ per line) + IgnoreCase
$rxOpts = [System.Text.RegularExpressions.RegexOptions]::Multiline `
        -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

$map = Import-YamlFile -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object

# Dialect-aware suffix
$suffix =
  if ($MapPath -match 'postgres') { '.postgres.sql' }
  elseif ($MapPath -match 'mysql') { '.mysql.sql' }
  else { '.sql' }

$createPath = Join-Path $SchemaDir ("001_table$suffix")
$indexPath  = Join-Path $SchemaDir ("020_indexes$suffix")
$fkPath     = Join-Path $SchemaDir ("030_foreign_keys$suffix")

$createText = Get-FileText $createPath
$indexText  = (Test-Path $indexPath) ? (Get-FileText $indexPath) : ''
$fkText     = (Test-Path $fkPath)    ? (Get-FileText $fkPath)    : ''

$missingCreates = @()
$missingIndexes = @()
$missingFks     = @()

# 1) CREATE TABLE blocks (detection fixed: multiline + case-insensitive)
foreach ($t in $tables) {
  $headerPat = "^\s*--\s*===\s*$([regex]::Escape($t))\s*===\s*$"
  $createPat = "CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+$([regex]::Escape($t))\s*\("

  $hasHeader = [regex]::IsMatch($createText, $headerPat, $rxOpts)
  $hasCreate = [regex]::IsMatch($createText, $createPat, $rxOpts)

  if (-not ($hasHeader -and $hasCreate)) {
    $missingCreates += $t
  }
}

# 2) INDEXES (deferred)
foreach ($t in $tables) {
  $ix = $map.Tables[$t].indexes
  if ($ix) {
    foreach ($stmt in $ix) {
      $pat = [regex]::Escape(($stmt.TrimEnd(';'))) + "\s*;?"
      if (-not [regex]::IsMatch($indexText, $pat, $rxOpts)) {
        $missingIndexes += @{ table=$t; index=$stmt }
      }
    }
  }
}

# 3) FOREIGN KEYS
foreach ($t in $tables) {
  $fks = $map.Tables[$t].foreign_keys
  if ($fks) {
    foreach ($stmt in $fks) {
      $pat = [regex]::Escape(($stmt.TrimEnd(';'))) + "\s*;?"
      if (-not [regex]::IsMatch($fkText, $pat, $rxOpts)) {
        $missingFks += @{ table=$t; fk=$stmt }
      }
    }
  }
}

# 4) Summary (section counting remains the same)
$sectionCount = ([regex]::Matches($createText, '^--\s*===\s*.+?\s*===\s*$', $rxOpts)).Count
$indexCount   = ([regex]::Matches($indexText, '^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+', $rxOpts)).Count
$fkCount      = ([regex]::Matches($fkText, '^\s*ALTER\s+TABLE\s+', $rxOpts)).Count

Write-Host "== Summary ==" -ForegroundColor Cyan
Write-Host ("Tables (sections) in 001_table{0} : {1}" -f $suffix, $sectionCount)
Write-Host ("Deferred indexes in 020_indexes{0} : {1}" -f $suffix, $indexCount)
Write-Host ("Foreign keys in 030_foreign_keys{0} : {1}" -f $suffix, $fkCount)
Write-Host ""

if ($missingCreates.Count -eq 0 -and $missingIndexes.Count -eq 0 -and $missingFks.Count -eq 0) {
  Write-Host "OK: Generated outputs match the schema map." -ForegroundColor Green
} else {
  if ($missingCreates.Count) {
    Write-Host "Missing CREATE TABLE sections:" -ForegroundColor Yellow
    $missingCreates | ForEach-Object { " - $_" } | Write-Host
  }
  if ($missingIndexes.Count) {
    Write-Host "`nMissing INDEX statements:" -ForegroundColor Yellow
    $missingIndexes | ForEach-Object { " - [$($_.table)] $($_.index)" } | Write-Host
  }
  if ($missingFks.Count) {
    Write-Host "`nMissing FOREIGN KEY statements:" -ForegroundColor Yellow
    $missingFks | ForEach-Object { " - [$($_.table)] $($_.fk)" } | Write-Host
  }
  throw "Some schema parts are missing—see details above."
}
