@{
  FormatVersion = '1.1'

  Views = @{
    key_wrappers_layers = @{
      create = @'
-- Key wrappers with layer counts and PQC flag
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_wrappers_layers AS
SELECT
  kw.id,
  kw.wrapper_uuid,
  kw.status,
  COUNT(kwl.id)                           AS layer_count,
  MIN(kwl.layer_no)                       AS first_layer_no,
  MAX(kwl.layer_no)                       AS last_layer_no,
  MAX(CASE WHEN ca.nist_level IS NOT NULL THEN 1 ELSE 0 END) AS has_pq_layer
FROM key_wrappers kw
LEFT JOIN key_wrapper_layers kwl ON kwl.key_wrapper_id = kw.id
LEFT JOIN crypto_algorithms ca   ON ca.id = kwl.kem_algo_id
GROUP BY kw.id, kw.wrapper_uuid, kw.status
ORDER BY kw.id DESC;
'@
    }

    crypto_algorithms_pq_readiness_summary = @{
      create = @'
-- One-row PQ readiness snapshot
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_pq_readiness_summary AS
SELECT
  (SELECT COUNT(*) FROM crypto_algorithms WHERE class='kem' AND status='active' AND nist_level IS NOT NULL) AS active_pq_kems,
  (SELECT COUNT(*) FROM crypto_algorithms WHERE class='sig' AND status='active' AND nist_level IS NOT NULL) AS active_pq_sigs,
  (SELECT COUNT(DISTINCT kw.id)
     FROM key_wrappers kw
     JOIN key_wrapper_layers kwl ON kwl.key_wrapper_id = kw.id
     JOIN crypto_algorithms ca ON ca.id = kwl.kem_algo_id
    WHERE ca.nist_level IS NOT NULL) AS wrappers_with_pq_layers,
  (SELECT COUNT(*)
     FROM signatures s
     JOIN crypto_algorithms ca ON ca.id = s.algo_id
    WHERE ca.class='sig' AND ca.nist_level IS NOT NULL) AS pq_signatures_total;
'@
    }

    books_catalog_health_summary = @{
      create = @'
-- High-level catalog health
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_catalog_health_summary AS
SELECT
  (SELECT COUNT(*) FROM authors WHERE deleted_at IS NULL) AS authors_live,
  (SELECT COUNT(*) FROM categories WHERE deleted_at IS NULL) AS categories_live,
  (SELECT COUNT(*) FROM books WHERE deleted_at IS NULL) AS books_live,
  (SELECT COUNT(*) FROM books b
     WHERE b.deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM book_assets a WHERE a.book_id = b.id AND a.asset_type='cover')) AS books_missing_cover,
  (SELECT COUNT(*) FROM books b
     WHERE b.is_active AND b.is_available AND (b.stock_quantity IS NULL OR b.stock_quantity > 0)) AS books_saleable;
'@
    }

    coupons_effectiveness = @{
      create = @'
-- Redemptions and total discount per coupon
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_coupon_effectiveness AS
SELECT
  c.id,
  c.code,
  c.is_active,
  c.starts_at,
  c.ends_at,
  COUNT(cr.id)      AS redemptions,
  SUM(cr.amount_applied) AS total_applied
FROM coupons c
LEFT JOIN coupon_redemptions cr ON cr.coupon_id = c.id
GROUP BY c.id, c.code, c.is_active, c.starts_at, c.ends_at
ORDER BY redemptions DESC;
'@
    }

    users_rbac_access_summary = @{
      create = @'
-- Per-user summary: roles + effective permissions
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_user_access_summary AS
SELECT
  u.id AS user_id,
  COUNT(DISTINCT CASE
      WHEN ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
      THEN ur.role_id END) AS active_roles,
  COUNT(DISTINCT ep.permission_id) AS effective_permissions
FROM users u
LEFT JOIN rbac_user_roles ur ON ur.user_id = u.id
LEFT JOIN vw_rbac_effective_permissions ep ON ep.user_id = u.id
GROUP BY u.id;
'@
    }
  }
}
