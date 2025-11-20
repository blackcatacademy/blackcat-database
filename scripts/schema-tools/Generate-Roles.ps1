param(
  [Parameter(Mandatory=$true)] [string] $MapPath,
  [Parameter(Mandatory=$true)] [string] $OutPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$map = Import-PowerShellDataFile -Path $MapPath

$pg = @()
$my = @()
foreach ($k in $map.Keys) {
  $m = $map[$k]
  $tbl = $m.Table
  $pg += @"
-- $tbl
GRANT USAGE ON SCHEMA public TO app_reader, app_writer;
GRANT SELECT ON TABLE $tbl TO app_reader;
GRANT INSERT, UPDATE, DELETE ON TABLE $tbl TO app_writer;
"@
  $my += @"
-- $tbl
GRANT SELECT ON $tbl TO 'app_reader'@'%';
GRANT INSERT, UPDATE, DELETE ON $tbl TO 'app_writer'@'%';
"@
}

@"
-- PostgreSQL
CREATE ROLE app_reader NOINHERIT;
CREATE ROLE app_writer NOINHERIT;
$(($pg -join "`n"))

-- MySQL/MariaDB
CREATE USER IF NOT EXISTS 'app_reader'@'%' IDENTIFIED BY 'CHANGE_ME';
CREATE USER IF NOT EXISTS 'app_writer'@'%' IDENTIFIED BY 'CHANGE_ME';
$(($my -join "`n"))
"@ | Out-File -FilePath $OutPath -NoNewline -Encoding UTF8

Write-Host "Wrote $OutPath"
