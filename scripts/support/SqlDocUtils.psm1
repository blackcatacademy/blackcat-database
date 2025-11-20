# Lightweight SQL doc utilities (regex-based; portable for PG/MySQL/MariaDB DDL)

function Get-SqlFiles {
  param([string]$Dir)
  if (-not (Test-Path $Dir)) { return @() }
  Get-ChildItem -Path $Dir -Filter *.sql -Recurse -File | Select-Object -ExpandProperty FullName
}

function Get-FileText {
  param([string[]]$Files)
  $texts = foreach ($f in $Files) { Get-Content -Raw -Path $f -ErrorAction Stop }
  return ($texts -join "`n")
}

function Format-SqlText {
  param([string]$Sql)
  # Normalize whitespace, remove multi-line comments cautiously
  $s = $Sql -replace '/\*.*?\*/', ' ' -replace '--[^\r\n]*', '' -replace '\s+', ' '
  return $s
}

function Get-TableBlocks {
  param([string]$Sql)
  # Capture CREATE TABLE ... ( ... );
  $regex = [regex]'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<table>[`"\[\]\w\.]+)\s*\((?<cols>.*?)\)\s*;'
  $m = $regex.Matches($Sql)
  foreach ($x in $m) {
    [pscustomobject]@{
      Table = ($x.Groups['table'].Value -replace '[`\[\]""]','')
      Body  = $x.Groups['cols'].Value
    }
  }
}

function Get-ColumnMetadata {
  param([string]$Body)
  $lines = $Body -split ','
  $cols = @()
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^(PRIMARY\s+KEY|FOREIGN\s+KEY|CONSTRAINT|UNIQUE\s*\(|CHECK\s*\(|INDEX\b)') { continue }
    if ($t -match '^(?<name>[`"\[\]\w]+)\s+(?<type>[^,\s\)]+)') {
      $name = $matches['name'] -replace '[`\[\]""]',''
      $type = $matches['type']
      $nullable = if ($t -match '\bNOT\s+NULL\b') { $false } elseif ($t -match '\bNULL\b') { $true } else { $null }
      $default = $null
      if ($t -match '\bDEFAULT\s+(?<def>[^,\s\)]+)') { $default = $matches['def'] }
      $cols += [pscustomobject]@{
        Name = $name; Type=$type; Nullable=$nullable; Default=$default
      }
    }
  }
  return $cols
}

function Get-PrimaryKeyInfo {
  param([string]$Body)
  $pk = $null
  if ($Body -match 'PRIMARY\s+KEY\s*\((?<cols>[^\)]+)\)') {
    $list = $matches['cols'].Split(',') | ForEach-Object { $_.Trim() -replace '[`\[\]""]','' }
    $pk = $list -join ', '
  } elseif ($Body -match '^(?<col>[`"\[\]\w]+)\s+.*\bPRIMARY\s+KEY\b') {
    $pk = ($matches['col'] -replace '[`\[\]""]','')
  }
  return $pk
}

function Get-IndexMetadata {
  param([string]$Sql, [string]$Table)
  $ix = @()
  $pattern = @'
CREATE\s+(?<uniq>UNIQUE\s+)?INDEX\s+(?<name>[`"\[\]\w]+)?\s+ON\s+[`"\[\]\w\.]*{0}\s*\((?<cols>[^\)]+)\)
'@
  $escapedTable = [regex]::Escape($Table)
  $re = [regex]($pattern -f $escapedTable)
  $m = $re.Matches($Sql)
  foreach ($x in $m) {
    $name = ($x.Groups['name'].Value -replace '[`\[\]""]','')
    if (-not $name) { $name = "$($Table)_idx_" + ($ix.Count+1) }
    $cols = $x.Groups['cols'].Value.Split(',') | ForEach-Object { $_.Trim() -replace '[`\[\]""]','' }
    $ix += [pscustomobject]@{
      Name=$name; Columns=($cols -join ', '); Unique=([bool]$x.Groups['uniq'].Value)
    }
  }
  return $ix
}

function Get-ForeignKeyMetadata {
  param([string]$Sql, [string]$Table)
  $fks = @()
  $segments = @($Sql)
  if ($Table) {
    $segments = @()
    $block = Get-TableBlocks -Sql $Sql | Where-Object { $_.Table -eq $Table } | Select-Object -First 1
    if ($block) { $segments += $block.Body }
    $escaped = [regex]::Escape($Table)
    $alterPatternText = @'
ALTER\s+TABLE\s+[`"\[\]]?{0}[`"\[\]]?\s+(?<body>.*?);
'@
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    $alterPattern = [regex]::new(($alterPatternText -f $escaped), $regexOptions)
    $alterMatches = $alterPattern.Matches($Sql)
    foreach ($match in $alterMatches) {
      $segments += $match.Groups['body'].Value
    }
    if (-not $segments) { return @() }
  }
  $re = [regex]'CONSTRAINT\s+(?<name>[`"\[\]\w]+)\s+FOREIGN\s+KEY\s*\((?<cols>[^\)]+)\)\s*REFERENCES\s+(?<ref>[`"\[\]\w\.]+)\s*\((?<refcols>[^\)]+)\)'
  foreach ($segment in $segments) {
    $m = $re.Matches($segment)
    foreach ($x in $m) {
      $name = ($x.Groups['name'].Value -replace '[`\[\]""]','')
      $cols = $x.Groups['cols'].Value.Split(',') | ForEach-Object { $_.Trim() -replace '[`\[\]""]','' }
      $ref  = ($x.Groups['ref'].Value -replace '[`\[\]""]','')
      $refc = $x.Groups['refcols'].Value.Split(',') | ForEach-Object { $_.Trim() -replace '[`\[\]""]','' }
      $fks += [pscustomobject]@{ Name=$name; Columns=($cols -join ', '); References="$ref(" + ($refc -join ', ') + ")" }
    }
  }
  return $fks
}

function Get-ViewNames {
  param([string]$Sql)
  $views = @()
  $re = [regex]'CREATE\s+VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<name>[`"\[\]\w\.]+)\s+AS'
  $m = $re.Matches($Sql)
  foreach ($x in $m) {
    $views += ($x.Groups['name'].Value -replace '[`\[\]""]','')
  }
  return $views
}

Export-ModuleMember -Function *-*
