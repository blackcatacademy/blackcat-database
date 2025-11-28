@{
  FormatVersion = '1.1'
  Views = @{
    sample_payments_status = @{
      Owner    = 'blackcat-commerce'
      Tags     = @('payments','ops','analytics')
      Requires = @('payments','payment_logs')
      create = @'
CREATE OR REPLACE VIEW vw_sample_payments_status AS
SELECT
  p.id,
  p.tenant_id,
  p.user_id,
  p.gateway,
  p.status,
  p.amount,
  p.currency,
  COALESCE(MAX(pl.created_at), p.created_at) AS last_update_at
FROM payments p
LEFT JOIN payment_logs pl ON pl.payment_id = p.id
GROUP BY p.id, p.tenant_id, p.user_id, p.gateway, p.status, p.amount, p.currency;
'@
    }
  }
}
