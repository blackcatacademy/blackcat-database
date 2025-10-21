param(
  [string]$MapPath   = (Join-Path $PSScriptRoot 'schema-map.psd1'),
  [string]$SchemaDir = (Join-Path $PSScriptRoot '..\schema')
)

function Get-FileText([string]$path) {
  if (!(Test-Path -LiteralPath $path)) { throw "Soubor nenalezen: $path" }
  return [System.IO.File]::ReadAllText((Resolve-Path $path))
}

# Regex options: Multiline (pro ^/$ po řádcích) + IgnoreCase
$rxOpts = [System.Text.RegularExpressions.RegexOptions]::Multiline `
        -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase

$map = Import-PowerShellDataFile -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object

$createPath = Join-Path $SchemaDir '001_table.sql'
$indexPath  = Join-Path $SchemaDir '020_indexes.sql'
$fkPath     = Join-Path $SchemaDir '030_foreign_keys.sql'

$createText = Get-FileText $createPath
$indexText  = (Test-Path $indexPath) ? (Get-FileText $indexPath) : ''
$fkText     = (Test-Path $fkPath)    ? (Get-FileText $fkPath)    : ''

$missingCreates = @()
$missingIndexes = @()
$missingFks     = @()

# 1) CREATE TABLE bloky (opravena detekce: multiline + case-insensitive)
foreach ($t in $tables) {
  $headerPat = "^\s*--\s*===\s*$([regex]::Escape($t))\s*===\s*$"
  $createPat = "CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+$([regex]::Escape($t))\s*\("

  $hasHeader = [regex]::IsMatch($createText, $headerPat, $rxOpts)
  $hasCreate = [regex]::IsMatch($createText, $createPat, $rxOpts)

  if (-not ($hasHeader -and $hasCreate)) {
    $missingCreates += $t
  }
}

# 2) INDEXY (odložené)
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

# 4) Rekapitulace (počítání sekcí zůstává stejné)
$sectionCount = ([regex]::Matches($createText, '^--\s*===\s*.+?\s*===\s*$', $rxOpts)).Count
$indexCount   = ([regex]::Matches($indexText, '^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+', $rxOpts)).Count
$fkCount      = ([regex]::Matches($fkText, '^\s*ALTER\s+TABLE\s+', $rxOpts)).Count

Write-Host "== Rekapitulace ==" -ForegroundColor Cyan
Write-Host "Tabulek (sekcí) v 001_table.sql : $sectionCount"
Write-Host "Odložených indexů v 020_indexes.sql : $indexCount"
Write-Host "FK v 030_foreign_keys.sql         : $fkCount"
Write-Host ""

if ($missingCreates.Count -eq 0 -and $missingIndexes.Count -eq 0 -and $missingFks.Count -eq 0) {
  Write-Host "OK: Výstupy odpovídají mapě." -ForegroundColor Green
} else {
  if ($missingCreates.Count) {
    Write-Host "Chybějící CREATE TABLE sekce:" -ForegroundColor Yellow
    $missingCreates | ForEach-Object { " - $_" } | Write-Host
  }
  if ($missingIndexes.Count) {
    Write-Host "`nChybějící INDEX příkazy:" -ForegroundColor Yellow
    $missingIndexes | ForEach-Object { " - [$($_.table)] $($_.index)" } | Write-Host
  }
  if ($missingFks.Count) {
    Write-Host "`nChybějící FOREIGN KEY příkazy:" -ForegroundColor Yellow
    $missingFks | ForEach-Object { " - [$($_.table)] $($_.fk)" } | Write-Host
  }
  throw "Některé části schématu chybí – viz výše."
}