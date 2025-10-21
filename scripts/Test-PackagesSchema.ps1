param(
  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages')
)

$errors = @()
$pkgs = Get-ChildItem -LiteralPath $PackagesDir -Directory

foreach ($p in $pkgs) {
  $schema = Join-Path $p.FullName 'schema'
  $f001 = Join-Path $schema '001_table.sql'
  $f020 = Join-Path $schema '020_indexes.sql'
  $f030 = Join-Path $schema '030_foreign_keys.sql'

  if (!(Test-Path $schema)) { $errors += "MISSING schema dir: $($p.Name)"; continue }

  if (!(Test-Path $f001)) { $errors += "MISSING 001_table.sql in $($p.Name)" }

  # 020/030 nemusí existovat, ale když existují, nemají být prázdné
  foreach ($f in @($f020,$f030)) {
    if (Test-Path $f) {
      $txt = (Get-Content -Raw -LiteralPath $f)
      if ([string]::IsNullOrWhiteSpace($txt)) { $errors += "EMPTY $(Split-Path -Leaf $f) in $($p.Name)" }
    }
  }
}

if ($errors.Count -gt 0) {
  "== Problémy =="; $errors | ForEach-Object { " - $_" }
  throw "Nalezeny problémy viz výše."
} else {
  "OK: Všechny balíčky mají očekávané soubory."
}