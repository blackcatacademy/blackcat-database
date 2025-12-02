. 'C:\Users\jaine\Desktop\blackcatacademy\blackcat-database\scripts\schema-tools\Split-SchemaToPackages.ps1'
$map = Import-MapFile -Path 'C:\Users\jaine\Desktop\blackcatacademy\blackcat-database\scripts\schema\schema-views-postgres.yaml' -Engine 'postgres-views'
$viewsHt = ConvertTo-Hashtable $map.Views
$entry = $viewsHt.GetEnumerator() | Where-Object { $_.Key -eq 'tenant_domains' }
$val = $entry.Value
$vs = Normalize-CreateValue $val
Write-Host "val type: $($val.GetType().FullName)"
Write-Host "normalize type: $($vs.GetType().FullName)"
Write-Host "text:\n$vs"
