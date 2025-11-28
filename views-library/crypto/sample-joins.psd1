@{
  FormatVersion = '1.1'
  Views = @{
    sample_crypto_keys_inventory = @{
      Owner    = 'blackcat-crypto'
      Tags     = @('crypto','ops')
      Requires = @('crypto_keys','crypto_algorithms')
      create = @'
CREATE OR REPLACE VIEW vw_sample_crypto_keys_inventory AS
SELECT
  ck.id,
  ck.tenant_id,
  ck.kms_provider_id,
  ck.status,
  ck.created_at,
  ca.class   AS algo_class,
  ca.nist_level
FROM crypto_keys ck
LEFT JOIN crypto_algorithms ca ON ca.id = ck.algo_id;
'@
    }
  }
}
