@{
  # Sample feature map (not loaded by tools; naming without "feature-" prefix on purpose)
  FormatVersion = '1.1'
  Views = @{
    sample_rbac_audit_snapshot = @{
      Owner    = 'blackcat-auth'
      Tags     = @('audit','rbac','reporting')
      Requires = @('rbac_user_roles', 'rbac_role_permissions', 'audit_log')
      create = @'
CREATE OR REPLACE VIEW vw_sample_rbac_audit_snapshot AS
SELECT
  u.id           AS user_id,
  u.email_hash   AS email_hash,
  COUNT(DISTINCT ur.role_id) AS roles_count,
  COUNT(DISTINCT rp.permission_id) AS perms_count,
  MAX(al.changed_at) AS last_change_at
FROM users u
LEFT JOIN rbac_user_roles ur      ON ur.user_id = u.id AND ur.status = 'active'
LEFT JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect = 'allow'
LEFT JOIN audit_log al             ON al.user_id = u.id
GROUP BY u.id, u.email_hash;
'@
    }
  }
}
