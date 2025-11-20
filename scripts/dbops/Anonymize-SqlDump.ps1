
param(
  [Parameter(Mandatory=$true)] [string] $InputPath,
  [Parameter(Mandatory=$true)] [string] $OutputPath,
  [Parameter(Mandatory=$true)] [string] $Secret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path $InputPath)) { throw "Input not found: $InputPath" }

function HmacHex([string]$s,[string]$key) {
  $enc = [System.Text.Encoding]::UTF8
  $h = New-Object System.Security.Cryptography.HMACSHA256 ($enc.GetBytes($key))
  $b = $h.ComputeHash($enc.GetBytes($s))
  -join ($b | ForEach-Object { $_.ToString('x2') })
}

# Mask emails anywhere in text; keep domain, hash local-part (deterministic)
function Update-Emails([string]$text,[string]$secret) {
  return [regex]::Replace($text, '(?i)\b([A-Z0-9._%+\-]+)@([A-Z0-9.\-]+\.[A-Z]{2,})\b', {
    param($m)
    $local = $m.Groups[1].Value
    $dom = $m.Groups[2].Value
    $h = (HmacHex $local $secret).Substring(0,12)
    return "user_$h@$dom"
  })
}

# Mask JSON fields "name":"..."/'name':'...' deterministically
function Update-JsonNames([string]$text,[string]$secret) {
  $pattern = '(?<q>["''])(name)\k<q>\s*:\s*(?<qv>["''])(?<val>[^"'']{1,128})\k<qv>'
  return [regex]::Replace($text, $pattern, {
    param($m)
    $val = $m.Groups['val'].Value
    $h = (HmacHex $val $secret).Substring(0,10)
    return $m.Value -replace [regex]::Escape($val), "name_$h"
  })
}

# Mask simple SQL patterns name='...' (best-effort; avoid quoted identifiers)
function Update-SqlNameColumns([string]$text,[string]$secret) {
  $pattern = '(?i)(\bname\b)\s*=\s*''([^'']{1,128})'''
  return [regex]::Replace($text, $pattern, {
    param($m)
    $orig = $m.Groups[2].Value
    $h = (HmacHex $orig $secret).Substring(0,10)
    return $m.Groups[1].Value + "='name_$h'"
  })
}

$reader = [System.IO.StreamReader]::new($InputPath, [System.Text.Encoding]::UTF8)
$writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::UTF8)
try {
  while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    $line = Update-Emails $line $Secret
    $line = Update-JsonNames $line $Secret
    $line = Update-SqlNameColumns $line $Secret
    $writer.WriteLine($line)
  }
}
finally {
  $reader.Dispose()
  $writer.Dispose()
}

Write-Host "Wrote anonymized dump: $OutputPath"
