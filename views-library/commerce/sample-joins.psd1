@{
  FormatVersion = '1.1'
  Views = @{
    sample_orders_with_user = @{
      Owner    = 'blackcat-commerce'
      Tags     = @('commerce','reporting')
      Requires = @('orders','users')
      create = @'
CREATE OR REPLACE VIEW vw_sample_orders_with_user AS
SELECT
  o.id,
  o.tenant_id,
  o.user_id,
  u.email_hash,
  o.status,
  o.total_amount,
  o.currency,
  o.created_at
FROM orders o
LEFT JOIN users u ON u.id = o.user_id;
'@
    }
  }
}
