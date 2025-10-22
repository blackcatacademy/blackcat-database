<# Build-Definitions.ps1 (fixed)
    Merges schema-map.psd1 (SQL) + schema-defs.psd1 (metadata)
    → packages/<slug>/docs/definition.md
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$MapPath,
  [Parameter(Mandatory=$true)][string]$DefsPath,
  [Parameter(Mandatory=$true)][string]$PackagesDir,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if(!(Test-Path -LiteralPath $MapPath)){throw "Map not found: $MapPath"}
if(!(Test-Path -LiteralPath $DefsPath)){throw "Defs not found: $DefsPath"}
if(!(Test-Path -LiteralPath $PackagesDir)){throw "PackagesDir not found: $PackagesDir"}

$map  = Import-PowerShellDataFile -Path $MapPath
$defs = Import-PowerShellDataFile -Path $DefsPath
$mapLeaf    = Split-Path -Leaf $MapPath
$mapRev     = (git log -1 --format=%h -- $MapPath) 2>$null
$mapRevDate = (git log -1 --date=iso-strict --format=%cd -- $MapPath) 2>$null
if (-not $mapRev) { $mapRev='working-tree'; $mapRevDate=(Get-Date).ToString('s') }
$GenTag = "<!-- Auto-generated from $mapLeaf @ $mapRev ($mapRevDate) -->"

function ConvertTo-Array { param($v)
  if($null -eq $v){ return @() }
  if($v -is [string]){ return ,$v }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){ return @($v) }
  return ,$v
}

function Get-PackageSlug([string]$t){ $t -replace '_','-' }

function Get-ColumnsFromCreate([string]$CreateSql){
  $out=@()
  if([string]::IsNullOrWhiteSpace($CreateSql)){ return $out }
  $m=[regex]::Match($CreateSql,'CREATE\s+TABLE.*?\((?<cols>[\s\S]*?)\)\s*ENGINE\s*=', 'IgnoreCase')
  $block= if($m.Success){$m.Groups['cols'].Value}else{
    $start=$CreateSql.IndexOf('('); $end=$CreateSql.LastIndexOf(')')
    if($start -ge 0 -and $end -gt $start){ $CreateSql.Substring($start+1,$end-$start-1) } else { $null }
  }
  if(-not $block){ return $out }
  $lines = [regex]::Split($block,'(?:\r\n|\n|\r)')
  foreach($raw in $lines){
    $line = ($raw -replace '--.*$','').Trim()
    if(!$line){ continue }
    if($line -match '^(PRIMARY|UNIQUE|KEY|INDEX|CONSTRAINT|CHECK|FOREIGN)\b'){ continue }
    $m2=[regex]::Match($line,'^[`"]?(?<name>[A-Za-z0-9_]+)[`"]?\s+(?<rest>.+?)(,)?$')
    if(-not $m2.Success){ continue }
    $name=$m2.Groups['name'].Value
    $rest=$m2.Groups['rest'].Value.Trim()
    $stop=@('NOT','NULL','DEFAULT','AUTO_INCREMENT','PRIMARY','UNIQUE','CHECK','COMMENT','COLLATE','GENERATED','STORED','VIRTUAL','ON','REFERENCES')
    $tokens=@($rest -split '\s+'); $buf=New-Object 'System.Collections.Generic.List[string]'
    foreach($t in $tokens){ if($stop -contains $t.ToUpperInvariant()){break}; $buf.Add($t) }
    $type=($buf -join ' ')
    $isNotNull= $rest -match '\bNOT\s+NULL\b'
    $isNull   = $rest -match '(^|[\s,])NULL\b' -and -not $isNotNull
    $nullTxt = if($isNotNull){'NO'} elseif($isNull){'YES'} else {'—'}
    $defM=[regex]::Match($rest,"DEFAULT\s+((?:''[^'']*'')|(?:'[^']*')|(?:[A-Za-z0-9_\.\(\)-]+))",'IgnoreCase')
    $default= if($defM.Success){ $defM.Groups[1].Value } else {'—'}
    $out += [pscustomobject]@{ Name=$name; Type=$type; Null=$nullTxt; Default=$default }
  }
  $out
}

foreach($t in ($map.Tables.Keys | Sort-Object)){
  try{
    $slug = Get-PackageSlug $t
    $pkg  = Join-Path $PackagesDir $slug
    if(!(Test-Path -LiteralPath $pkg)){ Write-Warning "SKIP [$t] – package not found: $pkg"; continue }

    $tbl = $map.Tables[$t]
    $create = $tbl['create']
    $cols = Get-ColumnsFromCreate $create

    $meta    = $defs.Tables[$t]
    $summary = if($meta){ $meta['Summary'] } else { '' }
    $colMeta = if($meta){ $meta['Columns'] } else { @{} }

    $rows=@()
    $rows += '| Column | Type | Null | Default | Description | Notes |'
    $rows += '|-------:|:-----|:----:|:--------|:------------|:------|'
    foreach($c in $cols){
      $niceType = if($c.Type){ $c.Type -replace "''","'" } else { $c.Type }

      $m = $colMeta[$c.Name]
      # if metadata is just a string, treat it as Description
      if($m -is [string]){ $m = @{ Description = $m } }

      $desc  = if($m){ $m['Description'] } else { '' }
      $notes = @()

      $enumVals = if($m){ $m['Enum'] } else { $null }
      if($enumVals){ $notes += ('enum: ' + ((ConvertTo-Array $enumVals) -join ', ')) }

      $pii = if($m){ $m['PII'] } else { $null }
      if($pii){ $notes += ('PII: ' + $pii) }

      $rows += ("| `{0}` | {1} | {2} | {3} | {4} | {5} |" -f $c.Name,$niceType,$c.Null,$c.Default,($desc -replace '\|','\|'),($notes -join '; '))
    }

    $content=@()
    $content += $GenTag
    $content += "# Definition – $t"
    if($summary){ $content += ""; $content += $summary }
    $content += ""
    $content += "## Columns"
    $content += ($rows -join "`n")

    $docDir = Join-Path $pkg 'docs'
    New-Item -ItemType Directory -Force -Path $docDir | Out-Null
    $outPath = Join-Path $docDir 'definition.md'
    if((Test-Path $outPath) -and -not $Force){
      Write-Host "SKIP [$t] – docs/definition.md exists (use -Force)"
    } else {
      Set-Content -Path $outPath -Value ($content -join "`n") -Encoding UTF8 -NoNewline
      Write-Host "WROTE [$t] -> $outPath"
    }
  } catch {
    Write-Warning "FAILED [$t]: $($_.Exception.Message)"
  }
}