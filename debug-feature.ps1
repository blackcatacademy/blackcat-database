. 'C:\Users\jaine\Desktop\blackcatacademy\blackcat-database\scripts\schema-tools\Split-SchemaToPackages.ps1'
$featPath = 'C:\Users\jaine\Desktop\blackcatacademy\blackcat-database\views-library\auth-rbac\feature-modules-mysql.yaml'
$featMap = Import-MapFile -Path $featPath -Engine 'mysql-feature-views'
$views = ConvertTo-Hashtable $featMap.Views
$entry = $views.GetEnumerator() | Where-Object { $_.Key -eq 'rbac_roles_coverage' }
$val = $entry.Value
Write-Host "value type: $($val.GetType().FullName)"
Write-Host "owner type: $($val.Owner.GetType().FullName) value: $($val.Owner)"
Write-Host "create type: $($val.create.GetType().FullName)"
