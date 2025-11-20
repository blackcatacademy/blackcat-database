@{
  RequirePrimaryKey = $true
  RequireFkIndex    = $true
  RequireViewDirectives = $true  # For MySQL/MariaDB: ALGORITHM + SQL SECURITY in views/*.sql
  TimeColumns = @('created_at','updated_at','createdon','updatedon','timestamp','ts')
}
