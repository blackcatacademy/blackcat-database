param(
  [Alias('Map','MapFile')]
  [string]$MapPath = "./schema-map.psd1",

  [string]$OutDir = "./schema",

  [string]$TablesFile = "001_table.sql",
  [string]$IndexesFile = "020_indexes.sql",
  [string]$ForeignKeysFile = "030_foreign_keys.sql",

  [switch]$Force
)

function Get-SchemaMap {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Schema map not found at '$Path'."
  }
  Import-PowerShellDataFile -Path $Path
}

function Add-SqlTerminator {
  param([string]$Sql)
  if ([string]::IsNullOrWhiteSpace($Sql)) { return "" }
  $t = $Sql.Trim()
  if ($t -match ';$') { return "$t`n" } else { return "$t;`n" }
}

function New-SchemaFiles {
  param(
    [hashtable]$Map,
    [string]$OutDir,
    [string]$TablesFile,
    [string]$IndexesFile,
    [string]$ForeignKeysFile,
    [switch]$Force
  )

  $null = New-Item -ItemType Directory -Force -Path $OutDir

  $tablesPath = Join-Path $OutDir $TablesFile
  $idxPath    = Join-Path $OutDir $IndexesFile
  $fkPath     = Join-Path $OutDir $ForeignKeysFile

  foreach ($p in @($tablesPath,$idxPath,$fkPath)) {
    if ((Test-Path $p) -and -not $Force) {
      throw "Output file '$p' exists. Use -Force to overwrite."
    }
  }

  $tablesSb = New-Object System.Text.StringBuilder
  $idxSb    = New-Object System.Text.StringBuilder
  $fkSb     = New-Object System.Text.StringBuilder

  $tables = $Map.Tables.GetEnumerator() | Sort-Object Key
  foreach ($entry in $tables) {
    $name = $entry.Key
    $spec = $entry.Value

    [void]$tablesSb.AppendLine("-- === $name ===")
    [void]$tablesSb.Append( (Add-SqlTerminator $spec.create) )
    [void]$tablesSb.AppendLine()

    if ($spec.indexes) {
      [void]$idxSb.AppendLine("-- === $name ===")
      foreach ($ix in $spec.indexes) { [void]$idxSb.Append( (Add-SqlTerminator $ix) ) }
      [void]$idxSb.AppendLine()
    }

    if ($spec.foreign_keys) {
      [void]$fkSb.AppendLine("-- === $name ===")
      foreach ($fk in $spec.foreign_keys) { [void]$fkSb.Append( (Add-SqlTerminator $fk) ) }
      [void]$fkSb.AppendLine()
    }
  }

  $tablesSb.ToString() | Out-File -FilePath $tablesPath -Encoding utf8 -Force
  $idxSb.ToString()    | Out-File -FilePath $idxPath    -Encoding utf8 -Force
  $fkSb.ToString()     | Out-File -FilePath $fkPath     -Encoding utf8 -Force

  Write-Host "Wrote:" -ForegroundColor Green
  Write-Host "  $tablesPath"
  Write-Host "  $idxPath"
  Write-Host "  $fkPath"
}

# --- main ---
$map = Get-SchemaMap -Path $MapPath
New-SchemaFiles -Map $map -OutDir $OutDir -TablesFile $TablesFile -IndexesFile $IndexesFile -ForeignKeysFile $ForeignKeysFile -Force:$Force