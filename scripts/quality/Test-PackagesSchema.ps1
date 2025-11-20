param(
  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages')
)

$errors = @()
$pkgs = Get-ChildItem -LiteralPath $PackagesDir -Directory

foreach ($p in $pkgs) {
  $schema = Join-Path $p.FullName 'schema'
  if (!(Test-Path $schema)) { $errors += "MISSING schema dir: $($p.Name)"; continue }

  # Accept dialect-specific filenames (001_table.mysql.sql / 001_table.postgres.sql)
  $createFiles = @(Get-ChildItem -LiteralPath $schema -Filter '001_table.*.sql' -File -ErrorAction SilentlyContinue)
  if ($createFiles.Count -eq 0) {
    $errors += "MISSING 001_table.<dialect>.sql in $($p.Name)"
  }

  # 020/030 may be absent, but if they exist they must not be empty (any dialect)
  $extraFiles = @(
    Get-ChildItem -LiteralPath $schema -Filter '020_indexes.*.sql' -File -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $schema -Filter '030_foreign_keys.*.sql' -File -ErrorAction SilentlyContinue
  ) | Where-Object { $_ }

  foreach ($f in $extraFiles) {
    $txt = (Get-Content -Raw -LiteralPath $f.FullName)
    if ([string]::IsNullOrWhiteSpace($txt)) { $errors += "EMPTY $($f.Name) in $($p.Name)" }
  }
}

if ($errors.Count -gt 0) {
  "== Issues =="; $errors | ForEach-Object { " - $_" }
  throw "Problems detected—see list above."
} else {
  "OK: All packages contain the expected files."
}
