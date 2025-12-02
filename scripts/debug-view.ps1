$y = Get-Content -Raw 'scripts/schema/schema-views-postgres.yaml' | ConvertFrom-Yaml
$v = $y.Views['tenant_domains']
$v.create.GetType().FullName
$v.create
