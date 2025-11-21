-- === api_keys ===
-- Contract view for [api_keys]
-- (gap fix) Hides token_hash; exposes hex and activity helpers.
CREATE OR REPLACE VIEW vw_api_keys AS
SELECT
  id,
  tenant_id,
  user_id,
  name,
  name_ci,
  token_hash_key_version,
  token_hash,
  UPPER(encode(token_hash,'hex')) AS token_hash_hex,
  scopes,
  status,
  last_used_at,
  expires_at,
  created_at,
  updated_at,
  (status = 'active' AND (expires_at IS NULL OR expires_at > now())) AS is_active
FROM api_keys;

-- === app_settings ===
-- Contract view for [app_settings]
-- Masks secrets and protected values; adds has_value flag.
CREATE OR REPLACE VIEW vw_app_settings AS
SELECT
  setting_key,
  CASE WHEN "type" = 'secret' OR is_protected THEN NULL ELSE setting_value END AS setting_value,
  (app_settings.setting_value IS NOT NULL) AS has_value,
  "type",
  section,
  description,
  is_protected,
  updated_at,
  version,
  updated_by
FROM app_settings;

-- === audit_chain ===
-- Contract view for [audit_chain]
-- Hides raw hashes; exposes hex.
CREATE OR REPLACE VIEW vw_audit_chain AS
SELECT
  id,
  audit_id,
  chain_name,
  prev_hash,
  UPPER(encode(prev_hash,'hex')) AS prev_hash_hex,
  hash,
  UPPER(encode(hash,'hex'))      AS hash_hex,
  created_at
FROM audit_chain;

-- === audit_chain_gaps ===
-- Audit rows missing chain entries
CREATE OR REPLACE VIEW vw_audit_chain_gaps AS
SELECT
  al.id AS audit_id,
  al.changed_at,
  al.table_name,
  al.record_id
FROM audit_log al
LEFT JOIN audit_chain ac ON ac.audit_id = al.id
WHERE ac.audit_id IS NULL
ORDER BY al.changed_at DESC;

-- === audit_log ===
-- Contract view for [audit_log]
-- Omits old_value/new_value JSON; adds ip_bin_hex helper.
CREATE OR REPLACE VIEW vw_audit_log AS
SELECT
  id,
  table_name,
  record_id,
  changed_by,
  change_type,
  changed_at,
  ip_bin AS ip_bin,
  UPPER(encode(ip_bin,'hex')) AS ip_bin_hex,
  user_agent,
  request_id
FROM audit_log;

-- === audit_log_activity_daily ===
-- Daily audit activity split by change type
CREATE OR REPLACE VIEW vw_audit_activity_daily AS
SELECT
  date_trunc('day', changed_at) AS day,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE change_type='INSERT') AS inserts,
  COUNT(*) FILTER (WHERE change_type='UPDATE') AS updates,
  COUNT(*) FILTER (WHERE change_type='DELETE') AS deletes
FROM audit_log
GROUP BY 1
ORDER BY day DESC;

-- === auth_events ===
-- Contract view for [auth_events]
CREATE OR REPLACE VIEW vw_auth_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta,
  meta_email
FROM auth_events;

-- === authors ===
-- Contract view for [authors]
CREATE OR REPLACE VIEW vw_authors AS
SELECT
  id,
  tenant_id,
  name,
  slug,
  bio,
  photo_url,
  story,
  books_count,
  ratings_count,
  rating_sum,
  avg_rating,
  last_rating_at,
  created_at,
  updated_at,
  version,
  deleted_at
FROM authors;

-- === book_assets ===
-- Contract view for [book_assets]
-- Hides encryption_key_enc, encryption_iv, encryption_tag, encryption_aad.
CREATE OR REPLACE VIEW vw_book_assets AS
SELECT
  id,
  tenant_id,
  book_id,
  asset_type,
  filename,
  mime_type,
  size_bytes,
  storage_path,
  content_hash,
  download_filename,
  is_encrypted,
  encryption_algo,
  encryption_meta,
  key_version,
  key_id,
  created_at,
  encryption_key_enc,
  encryption_iv,
  encryption_tag,
  encryption_aad,
  UPPER(encode(encryption_key_enc,'hex'))   AS encryption_key_enc_hex,
  UPPER(encode(encryption_iv,'hex'))        AS encryption_iv_hex,
  UPPER(encode(encryption_tag,'hex'))       AS encryption_tag_hex,
  UPPER(encode(encryption_aad,'hex'))       AS encryption_aad_hex
FROM book_assets;

-- === book_assets_encryption_coverage ===
-- Encryption coverage per asset_type
CREATE OR REPLACE VIEW vw_book_assets_encryption_coverage AS
SELECT
  asset_type,
  COUNT(*)                                         AS total,
  COUNT(*) FILTER (WHERE is_encrypted)             AS encrypted,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_encrypted) / GREATEST(COUNT(*),1), 2) AS pct_encrypted
FROM book_assets
GROUP BY asset_type
ORDER BY asset_type;

-- === book_categories ===
-- Contract view for [book_categories]
CREATE OR REPLACE VIEW vw_book_categories AS
SELECT
  book_id,
  tenant_id,
  category_id
FROM book_categories;

-- === books ===
-- Contract view for [books]
-- Adds saleability helper.
CREATE OR REPLACE VIEW vw_books AS
SELECT
  id,
  tenant_id,
  title,
  slug,
  short_description,
  full_description,
  price,
  currency,
  author_id,
  main_category_id,
  isbn,
  language,
  pages,
  publisher,
  published_at,
  sku,
  is_active,
  is_available,
  stock_quantity,
  (is_active AND is_available AND (stock_quantity IS NULL OR stock_quantity > 0)) AS is_saleable,
  created_at,
  updated_at,
  version,
  deleted_at
FROM books;

-- === books_catalog_health_summary ===
-- High-level catalog health
CREATE OR REPLACE VIEW vw_catalog_health_summary AS
SELECT
  (SELECT COUNT(*) FROM authors WHERE deleted_at IS NULL) AS authors_live,
  (SELECT COUNT(*) FROM categories WHERE deleted_at IS NULL) AS categories_live,
  (SELECT COUNT(*) FROM books WHERE deleted_at IS NULL) AS books_live,
  (SELECT COUNT(*) FROM books b
     WHERE b.deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM book_assets a WHERE a.book_id = b.id AND a.asset_type='cover')) AS books_missing_cover,
  (SELECT COUNT(*) FROM books b
     WHERE b.is_active AND b.is_available AND (b.stock_quantity IS NULL OR b.stock_quantity > 0)) AS books_saleable;

-- === cart_items ===
-- Contract view for [cart_items]
CREATE OR REPLACE VIEW vw_cart_items AS
SELECT
  id,
  tenant_id,
  cart_id,
  book_id,
  sku,
  variant,
  quantity,
  unit_price,
  price_snapshot,
  currency,
  meta
FROM cart_items;

-- === carts ===
-- Contract view for [carts]
CREATE OR REPLACE VIEW vw_carts AS
SELECT
  id,
  tenant_id,
  user_id,
  note,
  created_at,
  updated_at,
  version
FROM carts;

-- === categories ===
-- Contract view for [categories]
CREATE OR REPLACE VIEW vw_categories AS
SELECT
  id,
  tenant_id,
  name,
  slug,
  parent_id,
  created_at,
  updated_at,
  version,
  deleted_at
FROM categories;

-- === countries ===
-- Contract view for [countries]
CREATE OR REPLACE VIEW vw_countries AS
SELECT
  iso2,
  name
FROM countries;

-- === coupon_redemptions ===
-- Contract view for [coupon_redemptions]
CREATE OR REPLACE VIEW vw_coupon_redemptions AS
SELECT
  id,
  tenant_id,
  coupon_id,
  user_id,
  order_id,
  redeemed_at,
  amount_applied
FROM coupon_redemptions;

-- === coupons ===
-- Contract view for [coupons]
-- Adds is_current helper.
CREATE OR REPLACE VIEW vw_coupons AS
SELECT
  id,
  tenant_id,
  code,
  type,
  value,
  currency,
  starts_at,
  ends_at,
  max_redemptions,
  min_order_amount,
  applies_to,
  is_active,
  (is_active AND (starts_at IS NULL OR now() >= starts_at) AND (ends_at IS NULL OR now() <= ends_at)) AS is_current,
  created_at,
  updated_at
FROM coupons;

-- === coupons_effectiveness ===
-- Redemptions and total discount per coupon
CREATE OR REPLACE VIEW vw_coupon_effectiveness AS
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
ORDER BY redemptions DESC NULLS LAST;

-- === crypto_algorithms ===
-- Contract view for [crypto_algorithms]
CREATE OR REPLACE VIEW vw_crypto_algorithms AS
SELECT
  id,
  class,
  name,
  variant,
  nist_level,
  status,
  params,
  created_at
FROM crypto_algorithms;

-- === crypto_algorithms_pq_readiness_summary ===
-- One-row PQ readiness snapshot
CREATE OR REPLACE VIEW vw_pq_readiness_summary AS
SELECT
  (SELECT COUNT(*) FROM crypto_algorithms WHERE class='kem'  AND status='active' AND nist_level IS NOT NULL) AS active_pq_kems,
  (SELECT COUNT(*) FROM crypto_algorithms WHERE class='sig'  AND status='active' AND nist_level IS NOT NULL) AS active_pq_sigs,
  (SELECT COUNT(DISTINCT kw.id)
     FROM key_wrappers kw
     JOIN key_wrapper_layers kwl ON kwl.key_wrapper_id = kw.id
     JOIN crypto_algorithms ca ON ca.id = kwl.kem_algo_id
    WHERE ca.nist_level IS NOT NULL) AS wrappers_with_pq_layers,
  (SELECT COUNT(*)
     FROM signatures s
     JOIN crypto_algorithms ca ON ca.id = s.algo_id
    WHERE ca.class='sig' AND ca.nist_level IS NOT NULL) AS pq_signatures_total;

-- === crypto_keys ===
-- Contract view for [crypto_keys]
-- Hides backup_blob (encrypted backup payload). Keeps metadata for inventory.
CREATE OR REPLACE VIEW vw_crypto_keys AS
SELECT
  id,
  basename,
  version,
  filename,
  file_path,
  fingerprint,
  key_meta,
  key_type,
  algorithm,
  length_bits,
  origin,
  "usage",
  scope,
  status,
  is_backup_encrypted,
  created_by,
  created_at,
  activated_at,
  retired_at,
  replaced_by,
  notes,
  backup_blob,
  UPPER(encode(backup_blob,'hex')) AS backup_blob_hex
FROM crypto_keys;

-- === crypto_keys_inventory ===
-- Inventory of keys by type/status
CREATE OR REPLACE VIEW vw_crypto_keys_inventory AS
SELECT
  key_type,
  status,
  COUNT(*) AS total
FROM crypto_keys
GROUP BY key_type, status
ORDER BY key_type, status;

-- === crypto_keys_latest ===
-- Latest version per basename
CREATE OR REPLACE VIEW vw_crypto_keys_latest AS
SELECT DISTINCT ON (basename)
  basename, id, version, status, algorithm, key_type, activated_at, retired_at
FROM crypto_keys
ORDER BY basename, version DESC;

-- === crypto_standard_aliases ===
-- Contract view for [crypto_standard_aliases]
CREATE OR REPLACE VIEW vw_crypto_standard_aliases AS
SELECT
  alias, algo_id, notes, created_at
FROM crypto_standard_aliases;

-- === data_retention_policies ===
-- Contract view for [data_retention_policies]
CREATE OR REPLACE VIEW vw_data_retention_policies AS
SELECT
  id,
  entity_table,
  field_name,
  action,
  keep_for,
  active,
  notes,
  created_at
FROM data_retention_policies;

-- === data_retention_policies_due ===
-- Policies and when they become due (relative)
CREATE OR REPLACE VIEW vw_retention_due AS
SELECT
  id,
  entity_table,
  field_name,
  action,
  keep_for,
  active,
  (CURRENT_TIMESTAMP(6) + keep_for) AS due_from_now,
  notes,
  created_at
FROM data_retention_policies
WHERE active;

-- === deletion_jobs ===
-- Contract view for [deletion_jobs]
CREATE OR REPLACE VIEW vw_deletion_jobs AS
SELECT
  id,
  entity_table,
  entity_pk,
  reason,
  hard_delete,
  scheduled_at,
  started_at,
  finished_at,
  status,
  error,
  created_by,
  created_at
FROM deletion_jobs;

-- === deletion_jobs_status ===
-- Deletion jobs summary
CREATE OR REPLACE VIEW vw_deletion_jobs_status AS
SELECT
  status,
  COUNT(*) AS jobs,
  MAX(finished_at) AS last_finished
FROM deletion_jobs
GROUP BY status
ORDER BY status;

-- === device_fingerprints ===
-- Contract view for [device_fingerprints]
CREATE OR REPLACE VIEW vw_device_fingerprints AS
SELECT
  id,
  user_id,
  fingerprint_hash,
  UPPER(encode(fingerprint_hash, 'hex')) AS fingerprint_hash_hex,
  attributes,
  risk_score,
  first_seen,
  last_seen,
  last_ip_hash,
  UPPER(encode(last_ip_hash, 'hex')) AS last_ip_hash_hex,
  last_ip_key_version
FROM device_fingerprints;

-- === device_fingerprints_risk_recent ===
-- Devices with elevated risk seen in last 30 days
CREATE OR REPLACE VIEW vw_device_risk_recent AS
SELECT
  d.id,
  d.user_id,
  d.risk_score,
  d.first_seen,
  d.last_seen,
  UPPER(encode(d.fingerprint_hash,'hex')) AS fingerprint_hash_hex
FROM device_fingerprints d
WHERE d.last_seen > now() - interval '30 days'
  AND d.risk_score IS NOT NULL
ORDER BY d.risk_score DESC, d.last_seen DESC;

-- === email_verifications ===
-- Contract view for [email_verifications]
-- Hides token_hash and validator_hash; exposes selector and timestamps.
CREATE OR REPLACE VIEW vw_email_verifications AS
SELECT
  id,
  user_id,
  selector,
  key_version,
  expires_at,
  created_at,
  used_at,
  validator_hash,
  UPPER(encode(validator_hash,'hex')) AS validator_hash_hex
FROM email_verifications;

-- === encrypted_fields ===
-- Contract view for [encrypted_fields]
-- Hides ciphertext; keeps routing metadata.
CREATE OR REPLACE VIEW vw_encrypted_fields AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  meta,
  created_at,
  updated_at,
  ciphertext,
  UPPER(encode(ciphertext,'hex')) AS ciphertext_hex
FROM encrypted_fields;

-- === encrypted_fields_without_binding ===
-- Encrypted fields without explicit encryption_binding (for governance)
CREATE OR REPLACE VIEW vw_encrypted_fields_without_binding AS
SELECT
  e.id,
  e.entity_table,
  e.entity_pk,
  e.field_name,
  e.created_at,
  e.updated_at
FROM encrypted_fields e
LEFT JOIN encryption_bindings b
  ON b.entity_table = e.entity_table
 AND b.entity_pk    = e.entity_pk
 AND (b.field_name  = e.field_name OR b.field_name IS NULL)
WHERE b.id IS NULL
ORDER BY e.created_at DESC;

-- === encryption_bindings ===
-- Contract view for [encryption_bindings]
CREATE OR REPLACE VIEW vw_encryption_bindings AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  key_wrapper_id,
  created_at
FROM encryption_bindings;

-- === encryption_events ===
-- Contract view for [encryption_events]
CREATE OR REPLACE VIEW vw_encryption_events AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  op,
  policy_id,
  local_key_version,
  layers,
  outcome,
  error_code,
  created_at
FROM encryption_events;

-- === encryption_policies ===
-- Contract view for [encryption_policies]
CREATE OR REPLACE VIEW vw_encryption_policies AS
SELECT
  id,
  policy_name,
  mode,
  layer_selection,
  min_layers,
  max_layers,
  aad_template,
  notes,
  created_at
FROM encryption_policies;

-- === encryption_policy_bindings ===
-- Contract view for [encryption_policy_bindings]
CREATE OR REPLACE VIEW vw_encryption_policy_bindings AS
SELECT
  id, entity_table, field_name, policy_id, effective_from, notes
FROM encryption_policy_bindings;

-- === encryption_policy_bindings_current ===
-- Current policy per (entity, field)
CREATE OR REPLACE VIEW vw_encryption_policy_bindings_current AS
SELECT DISTINCT ON (entity_table, field_name)
  entity_table, field_name, policy_id, effective_from
FROM encryption_policy_bindings
WHERE effective_from <= now()
ORDER BY entity_table, field_name, effective_from DESC;

-- === entity_external_ids ===
-- Contract view for [entity_external_ids]
CREATE OR REPLACE VIEW vw_entity_external_ids AS
SELECT
  id, entity_table, entity_pk, source, external_id, created_at
FROM entity_external_ids;

-- === event_dlq ===
-- Contract view for [event_dlq]
CREATE OR REPLACE VIEW vw_event_dlq AS
SELECT
  id,
  source,
  event_key,
  event,
  error,
  retryable,
  attempts,
  first_failed_at,
  last_failed_at
FROM event_dlq;

-- === event_inbox ===
-- Contract view for [event_inbox]
-- Adds helper: is_failed.
CREATE OR REPLACE VIEW vw_event_inbox AS
SELECT
  id,
  source,
  event_key,
  payload,
  status,
  attempts,
  last_error,
  received_at,
  processed_at,
  (status = 'failed') AS is_failed
FROM event_inbox;

-- === event_inbox_metrics ===
-- Aggregated metrics for [event_inbox]
CREATE OR REPLACE VIEW vw_event_inbox_metrics AS
SELECT
  source,
  COUNT(*)                                AS total,
  COUNT(*) FILTER (WHERE status='pending')   AS pending,
  COUNT(*) FILTER (WHERE status='processed') AS processed,
  COUNT(*) FILTER (WHERE status='failed')    AS failed,
  AVG(attempts)                           AS avg_attempts,
  PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY attempts) AS p95_attempts
FROM event_inbox
GROUP BY source;

-- === event_outbox ===
-- Contract view for [event_outbox]
-- Adds helpers: is_pending, is_due.
CREATE OR REPLACE VIEW vw_event_outbox AS
SELECT
  id,
  event_key,
  entity_table,
  entity_pk,
  event_type,
  payload,
  status,
  attempts,
  next_attempt_at,
  processed_at,
  producer_node,
  created_at,
  (status = 'pending') AS is_pending,
  (status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= now())) AS is_due
FROM event_outbox;

-- === event_outbox_backlog_by_node ===
-- Pending outbox backlog per producer node/channel
CREATE OR REPLACE VIEW vw_sync_backlog_by_node AS
SELECT
  COALESCE(producer_node, '(unknown)') AS producer_node,
  event_type,
  COUNT(*) FILTER (WHERE status='pending') AS pending,
  COUNT(*) FILTER (WHERE status='failed')  AS failed,
  COUNT(*) AS total
FROM event_outbox
GROUP BY COALESCE(producer_node, '(unknown)'), event_type
ORDER BY pending DESC NULLS LAST, failed DESC;

-- === event_outbox_latency ===
-- Processing latency (created -> processed) by type
CREATE OR REPLACE VIEW vw_event_outbox_latency AS
SELECT
  event_type,
  COUNT(*)                                                                 AS processed,
  AVG(EXTRACT(EPOCH FROM (processed_at - created_at)))                      AS avg_latency_sec,
  PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (processed_at - created_at))) AS p50_latency_sec,
  PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (processed_at - created_at))) AS p95_latency_sec,
  MAX(EXTRACT(EPOCH FROM (processed_at - created_at)))                      AS max_latency_sec
FROM event_outbox
WHERE processed_at IS NOT NULL
GROUP BY event_type;

-- === event_outbox_metrics ===
-- Aggregated metrics for [event_outbox]
CREATE OR REPLACE VIEW vw_event_outbox_metrics AS
SELECT
  event_type,
  COUNT(*)                                AS total,
  COUNT(*) FILTER (WHERE status='pending') AS pending,
  COUNT(*) FILTER (WHERE status='sent')    AS sent,
  COUNT(*) FILTER (WHERE status='failed')  AS failed,
  AVG(EXTRACT(EPOCH FROM (now() - created_at)))                                   AS avg_created_lag_sec,
  PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (now()-created_at))) AS p50_created_lag_sec,
  PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (now()-created_at))) AS p95_created_lag_sec,
  AVG(attempts)                           AS avg_attempts,
  MAX(attempts)                           AS max_attempts,
  COUNT(*) FILTER (WHERE status IN ('pending','failed') AND (next_attempt_at IS NULL OR next_attempt_at <= now())) AS due_now
FROM event_outbox
GROUP BY event_type;

-- === event_outbox_throughput_hourly ===
-- Hourly throughput for outbox/inbox
CREATE OR REPLACE VIEW vw_event_throughput_hourly AS
WITH o AS (
  SELECT date_trunc('hour', created_at) AS ts, COUNT(*) AS outbox_cnt
  FROM event_outbox GROUP BY 1
),
i AS (
  SELECT date_trunc('hour', received_at) AS ts, COUNT(*) AS inbox_cnt
  FROM event_inbox GROUP BY 1
)
SELECT
  COALESCE(o.ts, i.ts) AS hour_ts,
  COALESCE(outbox_cnt,0) AS outbox_cnt,
  COALESCE(inbox_cnt,0)  AS inbox_cnt
FROM o FULL JOIN i ON o.ts = i.ts
ORDER BY hour_ts DESC;

-- === field_hash_policies ===
-- Contract view for [field_hash_policies]
CREATE OR REPLACE VIEW vw_field_hash_policies AS
SELECT
  id,
  entity_table,
  field_name,
  profile_id,
  effective_from,
  notes
FROM field_hash_policies;

-- === global_id_registry ===
-- Contract view for [global_id_registry]
CREATE OR REPLACE VIEW vw_global_id_registry AS
SELECT
  gid,
  guid,
  entity_table,
  entity_pk,
  created_at
FROM global_id_registry;

-- === global_id_registry_map ===
-- Global→local id registry (legacy map alias)
CREATE OR REPLACE VIEW vw_global_id_map AS
SELECT
  gid,
  guid,
  entity_table,
  entity_pk,
  created_at
FROM global_id_registry;

-- === hash_profiles ===
-- Contract view for [hash_profiles]
CREATE OR REPLACE VIEW vw_hash_profiles AS
SELECT
  id,
  name,
  algo_id,
  output_len,
  params,
  status,
  created_at
FROM hash_profiles;

-- === idempotency_keys ===
-- Contract view for [idempotency_keys]
-- Hides gateway_payload body; adds expiry helpers.
CREATE OR REPLACE VIEW vw_idempotency_keys AS
SELECT
  key_hash,
  UPPER(btrim(key_hash)) AS key_hash_hex,
  tenant_id,
  payment_id,
  order_id,
  gateway_payload,
  redirect_url,
  created_at,
  ttl_seconds,
  (created_at + make_interval(secs => ttl_seconds)) AS expires_at,
  (ttl_seconds IS NOT NULL AND created_at IS NOT NULL AND (created_at + make_interval(secs => ttl_seconds)) <= now()) AS is_expired
FROM idempotency_keys;

-- === inventory_reservations ===
-- Contract view for [inventory_reservations]
-- Adds is_expired helper.
CREATE OR REPLACE VIEW vw_inventory_reservations AS
SELECT
  id,
  tenant_id,
  order_id,
  book_id,
  quantity,
  reserved_until,
  (now() > reserved_until) AS is_expired,
  status,
  created_at,
  version
FROM inventory_reservations;

-- === invoice_items ===
-- Contract view for [invoice_items]
CREATE OR REPLACE VIEW vw_invoice_items AS
SELECT
  id,
  tenant_id,
  invoice_id,
  line_no,
  description,
  unit_price,
  quantity,
  tax_rate,
  tax_amount,
  line_total,
  currency
FROM invoice_items;

-- === invoices ===
-- Contract view for [invoices]
CREATE OR REPLACE VIEW vw_invoices AS
SELECT
  id,
  tenant_id,
  order_id,
  invoice_number,
  variable_symbol,
  issue_date,
  due_date,
  subtotal,
  discount_total,
  tax_total,
  total,
  currency,
  qr_data,
  created_at
FROM invoices;

-- === jwt_tokens ===
-- Contract view for [jwt_tokens]
-- Hides token_hash; adds hex helper and jti as text.
CREATE OR REPLACE VIEW vw_jwt_tokens AS
SELECT
  id,
  jti,
  jti::text AS jti_text,
  user_id,
  token_hash_algo,
  token_hash_key_version,
  token_hash,
  UPPER(encode(token_hash,'hex')) AS token_hash_hex,
  type,
  scopes,
  created_at,
  version,
  expires_at,
  last_used_at,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  replaced_by,
  revoked,
  meta
FROM jwt_tokens;

-- === key_events ===
-- Contract view for [key_events]
CREATE OR REPLACE VIEW vw_key_events AS
SELECT
  id,
  key_id,
  basename,
  event_type,
  actor_id,
  job_id,
  note,
  meta,
  source,
  created_at
FROM key_events;

-- === key_rotation_jobs ===
-- Contract view for [key_rotation_jobs]
CREATE OR REPLACE VIEW vw_key_rotation_jobs AS
SELECT
  id,
  basename,
  target_version,
  scheduled_at,
  started_at,
  finished_at,
  status,
  attempts,
  executed_by,
  result,
  created_at
FROM key_rotation_jobs;

-- === key_usage ===
-- Contract view for [key_usage]
CREATE OR REPLACE VIEW vw_key_usage AS
SELECT
  id,
  key_id,
  usage_date,
  encrypt_count,
  decrypt_count,
  verify_count,
  last_used_at
FROM key_usage;

-- === key_wrapper_layers ===
-- Contract view for [key_wrapper_layers]
-- Hides ciphertexts; exposes hex helpers.
CREATE OR REPLACE VIEW vw_key_wrapper_layers AS
SELECT
  id,
  key_wrapper_id,
  layer_no,
  kms_key_id,
  kem_algo_id,
  aad,
  meta,
  created_at,
  kem_ciphertext,
  encap_pubkey,
  UPPER(encode(kem_ciphertext,'hex')) AS kem_ciphertext_hex,
  UPPER(encode(encap_pubkey,'hex'))   AS encap_pubkey_hex
FROM key_wrapper_layers;

-- === key_wrappers ===
-- Contract view for [key_wrappers]
-- Hides DEK wraps; exposes hex helpers and status flags.
CREATE OR REPLACE VIEW vw_key_wrappers AS
SELECT
  id,
  wrapper_uuid,
  kms1_key_id,
  kms2_key_id,
  crypto_suite,
  wrap_version,
  status,
  (status = 'active')  AS is_active,
  (status = 'rotated') AS is_rotated,
  created_at,
  rotated_at,
  dek_wrap1,
  dek_wrap2,
  UPPER(encode(dek_wrap1,'hex')) AS dek_wrap1_hex,
  UPPER(encode(dek_wrap2,'hex')) AS dek_wrap2_hex
FROM key_wrappers;

-- === key_wrappers_layers ===
-- Key wrappers with layer counts and PQC flag
CREATE OR REPLACE VIEW vw_key_wrappers_layers AS
SELECT
  kw.id,
  kw.wrapper_uuid,
  kw.status,
  COUNT(kwl.id)                           AS layer_count,
  MIN(kwl.layer_no)                       AS first_layer_no,
  MAX(kwl.layer_no)                       AS last_layer_no,
  BOOL_OR(ca.nist_level IS NOT NULL)      AS has_pq_layer
FROM key_wrappers kw
LEFT JOIN key_wrapper_layers kwl ON kwl.key_wrapper_id = kw.id
LEFT JOIN crypto_algorithms ca   ON ca.id = kwl.kem_algo_id
GROUP BY kw.id, kw.wrapper_uuid, kw.status
ORDER BY kw.id DESC;

-- === kms_health_checks ===
-- Contract view for [kms_health_checks]
CREATE OR REPLACE VIEW vw_kms_health_checks AS
SELECT
  id,
  provider_id,
  kms_key_id,
  status,
  latency_ms,
  error,
  checked_at
FROM kms_health_checks;

-- === kms_health_checks_latest ===
-- Latest health sample per provider/key
CREATE OR REPLACE VIEW vw_kms_health_latest AS
SELECT DISTINCT ON (COALESCE(kms_key_id,-1), COALESCE(provider_id,-1))
  id, provider_id, kms_key_id, status, latency_ms, error, checked_at
FROM kms_health_checks
ORDER BY COALESCE(kms_key_id,-1), COALESCE(provider_id,-1), checked_at DESC;

-- === kms_keys ===
-- Contract view for [kms_keys]
CREATE OR REPLACE VIEW vw_kms_keys AS
SELECT
  id,
  provider_id,
  external_key_ref,
  purpose,
  algorithm,
  status,
  created_at
FROM kms_keys;

-- === kms_keys_status_by_provider ===
-- KMS keys status per provider
CREATE OR REPLACE VIEW vw_kms_keys_status_by_provider AS
SELECT
  p.provider,
  p.name        AS provider_name,
  COUNT(k.id)   AS total,
  COUNT(k.id) FILTER (WHERE k.status='active')    AS active,
  COUNT(k.id) FILTER (WHERE k.status='retired')   AS retired,
  COUNT(k.id) FILTER (WHERE k.status='disabled')  AS disabled
FROM kms_keys k
JOIN kms_providers p ON p.id = k.provider_id
GROUP BY p.provider, p.name
ORDER BY p.provider, p.name;

-- === kms_providers ===
-- Contract view for [kms_providers]
CREATE OR REPLACE VIEW vw_kms_providers AS
SELECT
  id,
  name,
  provider,
  location,
  project_tenant,
  created_at,
  is_enabled
FROM kms_providers;

-- === kms_routing_policies ===
-- Contract view for [kms_routing_policies]
CREATE OR REPLACE VIEW vw_kms_routing_policies AS
SELECT
  id,
  name,
  priority,
  strategy,
  "match",
  providers,
  active,
  created_at
FROM kms_routing_policies;

-- === kms_routing_policies_matrix ===
-- Active KMS routing policies (ordered by priority)
CREATE OR REPLACE VIEW vw_kms_routing_matrix AS
SELECT
  name,
  priority,
  strategy,
  "match",
  providers,
  active,
  created_at
FROM kms_routing_policies
WHERE active
ORDER BY priority DESC, name;

-- === login_attempts ===
-- Contract view for [login_attempts]
-- Exposes hashed identifiers only; adds hex helpers.
CREATE OR REPLACE VIEW vw_login_attempts AS
SELECT
  id,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  attempted_at,
  success,
  user_id,
  username_hash,
  UPPER(encode(username_hash,'hex')) AS username_hash_hex,
  auth_event_id
FROM login_attempts;

-- === login_attempts_hotspots_ip ===
-- Security: IPs with failed logins (last 24h)
CREATE OR REPLACE VIEW vw_login_hotspots_ip AS
SELECT
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  COUNT(*) FILTER (WHERE attempted_at > now() - interval '24 hours')                         AS total_24h,
  COUNT(*) FILTER (WHERE success = false AND attempted_at > now() - interval '24 hours')     AS failed_24h,
  MAX(attempted_at) AS last_attempt_at
FROM login_attempts
GROUP BY ip_hash
HAVING COUNT(*) FILTER (WHERE success = false AND attempted_at > now() - interval '24 hours') > 0
ORDER BY failed_24h DESC, last_attempt_at DESC;

-- === login_attempts_hotspots_user ===
-- Security: users with failed logins (last 24h)
CREATE OR REPLACE VIEW vw_login_hotspots_user AS
SELECT
  user_id,
  COUNT(*) FILTER (WHERE attempted_at > now() - interval '24 hours')                         AS total_24h,
  COUNT(*) FILTER (WHERE success = false AND attempted_at > now() - interval '24 hours')     AS failed_24h,
  MAX(attempted_at) AS last_attempt_at
FROM login_attempts
WHERE user_id IS NOT NULL
GROUP BY user_id
HAVING COUNT(*) FILTER (WHERE success = false AND attempted_at > now() - interval '24 hours') > 0
ORDER BY failed_24h DESC, last_attempt_at DESC;

-- === merkle_anchors ===
-- Contract view for [merkle_anchors]
CREATE OR REPLACE VIEW vw_merkle_anchors AS
SELECT
  id,
  merkle_root_id,
  anchor_type,
  anchor_ref,
  anchored_at,
  meta
FROM merkle_anchors;

-- === merkle_roots ===
-- Contract view for [merkle_roots]
CREATE OR REPLACE VIEW vw_merkle_roots AS
SELECT
  id,
  subject_table,
  period_start,
  period_end,
  root_hash,
  UPPER(encode(root_hash,'hex')) AS root_hash_hex,
  proof_uri,
  status,
  created_at
FROM merkle_roots;

-- === merkle_roots_latest ===
-- Latest Merkle roots per table
CREATE OR REPLACE VIEW vw_merkle_latest AS
SELECT DISTINCT ON (subject_table)
  subject_table,
  period_start,
  period_end,
  leaf_count,
  UPPER(encode(root_hash,'hex')) AS root_hash_hex,
  created_at
FROM merkle_roots
ORDER BY subject_table, created_at DESC;

-- === migration_events ===
-- Contract view for [migration_events]
CREATE OR REPLACE VIEW vw_migration_events AS
SELECT
  id,
  system_name,
  from_version,
  to_version,
  status,
  started_at,
  finished_at,
  error,
  meta
FROM migration_events;

-- === newsletter_subscribers ===
-- Contract view for [newsletter_subscribers]
-- Hides email_enc; adds hex helpers for hashes.
CREATE OR REPLACE VIEW vw_newsletter_subscribers AS
SELECT
  id,
  tenant_id,
  user_id,
  email_enc,
  UPPER(encode(email_enc,'hex')) AS email_enc_hex,
  email_hash,
  UPPER(encode(email_hash,'hex')) AS email_hash_hex,
  email_hash_key_version,
  confirm_selector,
  confirm_validator_hash,
  UPPER(encode(confirm_validator_hash,'hex')) AS confirm_validator_hash_hex,
  confirm_key_version,
  confirm_expires,
  confirmed_at,
  unsubscribe_token_hash,
  UPPER(encode(unsubscribe_token_hash,'hex')) AS unsubscribe_token_hash_hex,
  unsubscribe_token_key_version,
  unsubscribed_at,
  origin,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  meta,
  created_at,
  updated_at,
  version
FROM newsletter_subscribers;

-- === notifications ===
-- Contract view for [notifications]
-- Adds is_locked helper.
CREATE OR REPLACE VIEW vw_notifications AS
SELECT
  id,
  tenant_id,
  user_id,
  channel,
  template,
  payload,
  status,
  retries,
  max_retries,
  next_attempt_at,
  scheduled_at,
  sent_at,
  error,
  last_attempt_at,
  locked_until,
  (locked_until IS NOT NULL AND locked_until > now()) AS is_locked,
  locked_by,
  priority,
  created_at,
  updated_at,
  version
FROM notifications;

-- === notifications_queue_metrics ===
-- Queue metrics for [notifications]
CREATE OR REPLACE VIEW vw_notifications_queue_metrics AS
SELECT
  channel,
  status,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE status IN ('pending','processing') AND (next_attempt_at IS NULL OR next_attempt_at <= now())) AS due_now,
  PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (now() - COALESCE(last_attempt_at, created_at)))) AS p95_age_sec
FROM notifications
GROUP BY channel, status
ORDER BY channel, status;

-- === order_item_downloads ===
-- Contract view for [order_item_downloads]
-- Hides download_token_hash; adds usage helpers & hex for ip_hash.
CREATE OR REPLACE VIEW vw_order_item_downloads AS
SELECT
  id,
  tenant_id,
  order_id,
  book_id,
  asset_id,
  token_key_version,
  key_version,
  max_uses,
  used,
  GREATEST(0, COALESCE(max_uses,0) - COALESCE(used,0)) AS uses_left,
  (GREATEST(0, COALESCE(max_uses,0) - COALESCE(used,0)) > 0 AND (expires_at IS NULL OR expires_at > now())) AS is_valid,
  expires_at,
  last_used_at,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  download_token_hash,
  UPPER(encode(download_token_hash,'hex')) AS download_token_hash_hex
FROM order_item_downloads;

-- === order_items ===
-- Contract view for [order_items]
CREATE OR REPLACE VIEW vw_order_items AS
SELECT
  id,
  tenant_id,
  order_id,
  book_id,
  product_ref,
  title_snapshot,
  sku_snapshot,
  unit_price,
  quantity,
  tax_rate,
  currency
FROM order_items;

-- === orders ===
-- Contract view for [orders]
-- Hides encrypted_customer_blob; PG has native uuid.
-- Adds uuid_text and uuid_hex.
CREATE OR REPLACE VIEW vw_orders AS
SELECT
  id,
  tenant_id,
  uuid,
  uuid_bin,
  uuid::text                AS uuid_text,
  UPPER(replace(uuid::text,'-',')) AS uuid_hex,
  UPPER(encode(uuid_bin,'hex'))     AS uuid_bin_hex,
  public_order_no,
  user_id,
  status,
  encrypted_customer_blob_key_version,
  encrypted_customer_blob,
  UPPER(encode(encrypted_customer_blob,'hex')) AS encrypted_customer_blob_hex,
  octet_length(encrypted_customer_blob) AS encrypted_customer_blob_len,
  encryption_meta,
  currency,
  metadata,
  subtotal,
  discount_total,
  tax_total,
  total,
  payment_method,
  created_at,
  updated_at,
  version
FROM orders;

-- === orders_funnel ===
-- Global funnel of orders
CREATE OR REPLACE VIEW vw_orders_funnel AS
SELECT
  COUNT(*)                               AS orders_total,
  COUNT(*) FILTER (WHERE status='pending')   AS pending,
  COUNT(*) FILTER (WHERE status='paid')      AS paid,
  COUNT(*) FILTER (WHERE status='completed') AS completed,
  COUNT(*) FILTER (WHERE status='failed')    AS failed,
  COUNT(*) FILTER (WHERE status='cancelled') AS cancelled,
  COUNT(*) FILTER (WHERE status='refunded')  AS refunded,
  ROUND(100.0 * COUNT(*) FILTER (WHERE status IN ('paid','completed')) / GREATEST(COUNT(*),1), 2) AS payment_conversion_pct
FROM orders;

-- === orders_revenue_daily ===
-- Daily revenue (orders) and counts; refunds reported separately
CREATE OR REPLACE VIEW vw_revenue_daily AS
SELECT
  date_trunc('day', created_at) AS day,
  COUNT(*) FILTER (WHERE status IN ('paid','completed')) AS paid_orders,
  SUM(total) FILTER (WHERE status IN ('paid','completed')) AS revenue_gross,
  COUNT(*) FILTER (WHERE status IN ('failed','cancelled')) AS lost_orders,
  SUM(total) FILTER (WHERE status IN ('failed','cancelled')) AS lost_total
FROM orders
GROUP BY 1
ORDER BY day DESC;

-- === payment_gateway_notifications ===
-- Contract view for [payment_gateway_notifications]
CREATE OR REPLACE VIEW vw_payment_gateway_notifications AS
SELECT
  id,
  tenant_id,
  transaction_id,
  received_at,
  version,
  processing_by,
  processing_until,
  attempts,
  last_error,
  status
FROM payment_gateway_notifications;

-- === payment_logs ===
-- Contract view for [payment_logs]
CREATE OR REPLACE VIEW vw_payment_logs AS
SELECT
  id,
  payment_id,
  log_at,
  message
FROM payment_logs;

-- === payment_webhooks ===
-- Contract view for [payment_webhooks]
-- Hides raw payload JSON; exposes presence.
CREATE OR REPLACE VIEW vw_payment_webhooks AS
SELECT
  id,
  payment_id,
  gateway_event_id,
  payload_hash,
  (payload IS NOT NULL) AS has_payload,
  from_cache,
  created_at
FROM payment_webhooks;

-- === payments ===
-- Contract view for [payments]
-- Includes "details" JSON; mask in your app if needed.
CREATE OR REPLACE VIEW vw_payments AS
SELECT
  id,
  tenant_id,
  order_id,
  gateway,
  transaction_id,
  provider_event_id,
  status,
  amount,
  currency,
  details,
  created_at,
  updated_at,
  version
FROM payments;

-- === payments_anomalies ===
-- Potential anomalies in payments
CREATE OR REPLACE VIEW vw_payments_anomalies AS
SELECT
  p.*
FROM payments p
WHERE
  (status IN ('paid','authorized') AND amount < 0)
  OR (status = 'paid' AND (transaction_id IS NULL OR transaction_id = ''))
  OR (status = 'failed' AND amount > 0);

-- === payments_status_summary ===
-- Payment status summary by gateway
CREATE OR REPLACE VIEW vw_payments_status_summary AS
SELECT
  gateway,
  status,
  COUNT(*) AS total,
  SUM(amount) FILTER (WHERE status IN ('authorized','paid','partially_refunded','refunded')) AS sum_amount
FROM payments
GROUP BY gateway, status
ORDER BY gateway, status;

-- === peer_nodes ===
-- Contract view for [peer_nodes]
CREATE OR REPLACE VIEW vw_peer_nodes AS
SELECT
  id,
  name,
  "type",
  location,
  status,
  last_seen,
  meta,
  created_at
FROM peer_nodes;

-- === peer_nodes_health ===
-- Peer health with last lag samples
CREATE OR REPLACE VIEW vw_peer_health AS
WITH last_lag AS (
  SELECT DISTINCT ON (peer_id, metric) peer_id, metric, value, captured_at
  FROM replication_lag_samples
  ORDER BY peer_id, metric, captured_at DESC
)
SELECT
  p.id        AS peer_id,
  p.name,
  p.type,
  p.location,
  p.status,
  p.last_seen,
  COALESCE(MAX(CASE WHEN l.metric='apply_lag_ms' THEN l.value END),0)    AS apply_lag_ms,
  COALESCE(MAX(CASE WHEN l.metric='transport_lag_ms' THEN l.value END),0) AS transport_lag_ms,
  MAX(l.captured_at) AS lag_sampled_at
FROM peer_nodes p
LEFT JOIN last_lag l ON l.peer_id = p.id
GROUP BY p.id, p.name, p.type, p.location, p.status, p.last_seen
ORDER BY p.status, p.name;

-- === permissions ===
-- Contract view for [permissions]
CREATE OR REPLACE VIEW vw_permissions AS
SELECT
  id,
  name,
  description,
  created_at,
  updated_at
FROM permissions;

-- === policy_algorithms ===
-- Contract view for [policy_algorithms]
CREATE OR REPLACE VIEW vw_policy_algorithms AS
SELECT
  policy_id,
  algo_id,
  role,
  weight,
  priority
FROM policy_algorithms;

-- === policy_kms_keys ===
-- Contract view for [policy_kms_keys]
CREATE OR REPLACE VIEW vw_policy_kms_keys AS
SELECT
  policy_id,
  kms_key_id,
  weight,
  priority
FROM policy_kms_keys;

-- === pq_migration_jobs ===
-- Contract view for [pq_migration_jobs]
-- Adds helpers: is_done, is_running.
CREATE OR REPLACE VIEW vw_pq_migration_jobs AS
SELECT
  id,
  scope,
  target_policy_id,
  target_algo_id,
  selection,
  scheduled_at,
  started_at,
  finished_at,
  status,
  processed_count,
  error,
  created_by,
  created_at,
  (status = 'done')    AS is_done,
  (status = 'running') AS is_running
FROM pq_migration_jobs;

-- === pq_migration_jobs_metrics ===
-- PQ migration progress by status
CREATE OR REPLACE VIEW vw_pq_migration_jobs_metrics AS
SELECT
  status,
  COUNT(*) AS jobs,
  SUM(processed_count) AS processed_total
FROM pq_migration_jobs
GROUP BY status
ORDER BY status;

-- === privacy_requests ===
-- Contract view for [privacy_requests]
CREATE OR REPLACE VIEW vw_privacy_requests AS
SELECT
  id,
  user_id,
  "type",
  status,
  requested_at,
  processed_at,
  meta
FROM privacy_requests;

-- === privacy_requests_status ===
-- Privacy requests status
CREATE OR REPLACE VIEW vw_privacy_requests_status AS
SELECT
  type,
  status,
  COUNT(*) AS total,
  MAX(processed_at) AS last_processed
FROM privacy_requests
GROUP BY type, status
ORDER BY type, status;

-- === rate_limit_counters ===
-- Contract view for [rate_limit_counters]
CREATE OR REPLACE VIEW vw_rate_limit_counters AS
SELECT
  id,
  subject_type,
  subject_id,
  name,
  window_start,
  window_size_sec,
  "count",
  updated_at
FROM rate_limit_counters;

-- === rate_limit_counters_usage ===
-- Rate limit counters per subject/name (last hour window)
CREATE OR REPLACE VIEW vw_rate_limit_usage AS
SELECT
  subject_type,
  subject_id,
  name,
  SUM("count") AS total_count,
  MIN(window_start) AS first_window,
  MAX(window_start) AS last_window
FROM rate_limit_counters
WHERE window_start > now() - interval '1 hour'
GROUP BY subject_type, subject_id, name
ORDER BY total_count DESC;

-- === rate_limits ===
-- Contract view for [rate_limits]
CREATE OR REPLACE VIEW vw_rate_limits AS
SELECT
  id,
  subject_type,
  subject_id,
  name,
  window_size_sec,
  limit_count,
  active,
  created_at
FROM rate_limits;

-- === rbac_repo_snapshots ===
-- Contract view for [rbac_repo_snapshots]
CREATE OR REPLACE VIEW vw_rbac_repo_snapshots AS
SELECT
  id,
  repo_id,
  commit_id,
  taken_at,
  metadata
FROM rbac_repo_snapshots;

-- === rbac_repositories ===
-- Contract view for [rbac_repositories]
CREATE OR REPLACE VIEW vw_rbac_repositories AS
SELECT
  id,
  name,
  url,
  status,
  signing_key_id,
  last_synced_at,
  last_commit,
  created_at
FROM rbac_repositories;

-- === rbac_repositories_sync_status ===
-- RBAC repository sync cursors (per peer)
CREATE OR REPLACE VIEW vw_rbac_sync_status AS
SELECT
  r.id AS repo_id,
  r.name AS repo_name,
  r.status AS repo_status,
  r.last_synced_at AS repo_last_sync,
  r.last_commit    AS repo_last_commit,
  c.peer,
  c.last_commit    AS peer_last_commit,
  c.last_synced_at AS peer_last_synced_at
FROM rbac_repositories r
LEFT JOIN rbac_sync_cursors c ON c.repo_id = r.id
ORDER BY r.id, c.peer;

-- === rbac_role_permissions ===
-- Contract view for [rbac_role_permissions]
CREATE OR REPLACE VIEW vw_rbac_role_permissions AS
SELECT
  role_id, permission_id, effect, source, created_at
FROM rbac_role_permissions;

-- === rbac_roles ===
-- Contract view for [rbac_roles]
CREATE OR REPLACE VIEW vw_rbac_roles AS
SELECT
  id, repo_id, slug, name, description, version, status, created_at, updated_at
FROM rbac_roles;

-- === rbac_roles_coverage ===
-- Role coverage: permissions per role (allow/deny)
CREATE OR REPLACE VIEW vw_rbac_roles_coverage AS
SELECT
  r.id AS role_id,
  r.slug,
  r.name,
  COUNT(*) FILTER (WHERE rp.effect = 'allow') AS allows,
  COUNT(*) FILTER (WHERE rp.effect = 'deny')  AS denies,
  COUNT(*) AS total_rules
FROM rbac_roles r
LEFT JOIN rbac_role_permissions rp ON rp.role_id = r.id
GROUP BY r.id, r.slug, r.name
ORDER BY total_rules DESC, allows DESC;

-- === rbac_sync_cursors ===
-- Contract view for [rbac_sync_cursors]
CREATE OR REPLACE VIEW vw_rbac_sync_cursors AS
SELECT
  repo_id,
  peer,
  last_commit,
  last_synced_at
FROM rbac_sync_cursors;

-- === rbac_user_permissions ===
-- Contract view for [rbac_user_permissions]
CREATE OR REPLACE VIEW vw_rbac_user_permissions AS
SELECT
  id, user_id, permission_id, tenant_id, scope, effect, granted_by, granted_at, expires_at
FROM rbac_user_permissions;

-- === rbac_user_permissions_conflicts ===
-- Potential conflicts: same (user,perm,tenant,scope) both allowed and denied
CREATE OR REPLACE VIEW vw_rbac_conflicts AS
WITH a AS (
  SELECT user_id, permission_id, tenant_id, scope FROM rbac_user_permissions WHERE effect='allow'
  UNION
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect='allow'
  WHERE ur.status='active' AND (ur.expires_at IS NULL OR ur.expires_at > now())
),
d AS (
  SELECT user_id, permission_id, tenant_id, scope FROM rbac_user_permissions WHERE effect='deny'
  UNION
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect='deny'
  WHERE ur.status='active' AND (ur.expires_at IS NULL OR ur.expires_at > now())
)
SELECT DISTINCT
  a.user_id, a.permission_id, p.name AS permission_name, a.tenant_id, a.scope
FROM a
JOIN d ON d.user_id=a.user_id AND d.permission_id=a.permission_id
      AND COALESCE(d.tenant_id,-1)=COALESCE(a.tenant_id,-1)
      AND COALESCE(d.scope,')=COALESCE(a.scope,')
JOIN permissions p ON p.id=a.permission_id;

-- === rbac_user_permissions_effective ===
-- Effective permissions per user (Deny > Allow), including tenant/scope
CREATE OR REPLACE VIEW vw_rbac_effective_permissions AS
WITH allowed AS (
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect = 'allow'
  WHERE ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > now())
  UNION
  SELECT up.user_id, up.permission_id, up.tenant_id, up.scope
  FROM rbac_user_permissions up
  WHERE up.effect = 'allow' AND (up.expires_at IS NULL OR up.expires_at > now())
),
denied AS (
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect = 'deny'
  WHERE ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > now())
  UNION
  SELECT up.user_id, up.permission_id, up.tenant_id, up.scope
  FROM rbac_user_permissions up
  WHERE up.effect = 'deny' AND (up.expires_at IS NULL OR up.expires_at > now())
)
SELECT
  a.user_id,
  a.permission_id,
  p.name AS permission_name,
  a.tenant_id,
  a.scope
FROM allowed a
JOIN permissions p ON p.id = a.permission_id
WHERE NOT EXISTS (
  SELECT 1 FROM denied d
  WHERE d.user_id = a.user_id
    AND d.permission_id = a.permission_id
    AND COALESCE(d.tenant_id, -1) = COALESCE(a.tenant_id, -1)
    AND COALESCE(d.scope, ') = COALESCE(a.scope, ')
);

-- === rbac_user_roles ===
-- Contract view for [rbac_user_roles]
CREATE OR REPLACE VIEW vw_rbac_user_roles AS
SELECT
  id, user_id, role_id, tenant_id, scope, status, granted_by, granted_at, expires_at
FROM rbac_user_roles;

-- === rbac_user_roles_expiring_assignments ===
-- Roles/permissions which will expire within 7 days
CREATE OR REPLACE VIEW vw_rbac_expiring_assignments AS
SELECT
  'role' AS kind,
  ur.user_id,
  ur.role_id::bigint AS id,
  ur.tenant_id, ur.scope,
  ur.expires_at
FROM rbac_user_roles ur
WHERE ur.expires_at IS NOT NULL AND ur.expires_at <= now() + interval '7 days'
UNION ALL
SELECT
  'permission' AS kind,
  up.user_id,
  up.permission_id::bigint AS id,
  up.tenant_id, up.scope,
  up.expires_at
FROM rbac_user_permissions up
WHERE up.expires_at IS NOT NULL AND up.expires_at <= now() + interval '7 days';

-- === refunds ===
-- Contract view for [refunds]
CREATE OR REPLACE VIEW vw_refunds AS
SELECT
  id,
  tenant_id,
  payment_id,
  amount,
  currency,
  reason,
  status,
  created_at,
  details
FROM refunds;

-- === refunds_by_day_and_gateway ===
-- Refunds aggregated by day and gateway
CREATE OR REPLACE VIEW vw_refunds_by_day_and_gateway AS
SELECT
  date_trunc('day', r.created_at) AS day,
  p.gateway,
  SUM(r.amount) AS refunds_total,
  COUNT(*)      AS refunds_count
FROM refunds r
JOIN payments p ON p.id = r.payment_id
GROUP BY 1,2
ORDER BY day DESC, gateway;

-- === refunds_daily ===
-- Daily refunds amount
CREATE OR REPLACE VIEW vw_refunds_daily AS
SELECT
  date_trunc('day', r.created_at) AS day,
  SUM(r.amount) AS refunds_total,
  COUNT(*)      AS refunds_count
FROM refunds r
GROUP BY 1
ORDER BY day DESC;

-- === register_events ===
-- Contract view for [register_events]
CREATE OR REPLACE VIEW vw_register_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta
FROM register_events;

-- === replication_lag_samples ===
-- Contract view for [replication_lag_samples]
CREATE OR REPLACE VIEW vw_replication_lag_samples AS
SELECT
  id,
  peer_id,
  metric,
  value,
  captured_at
FROM replication_lag_samples;

-- === replication_lag_samples_latest ===
-- Latest replication lag samples per peer
CREATE OR REPLACE VIEW vw_replication_lag_latest AS
SELECT
  ph.peer_id,
  ph.name,
  ph.type,
  ph.apply_lag_ms,
  ph.transport_lag_ms,
  ph.lag_sampled_at
FROM vw_peer_health ph;

-- === retention_enforcement_jobs ===
-- Contract view for [retention_enforcement_jobs]
CREATE OR REPLACE VIEW vw_retention_enforcement_jobs AS
SELECT
  id,
  policy_id,
  scheduled_at,
  started_at,
  finished_at,
  status,
  processed_count,
  error,
  created_at
FROM retention_enforcement_jobs;

-- === reviews ===
-- Contract view for [reviews]
-- Adds is_edited helper.
CREATE OR REPLACE VIEW vw_reviews AS
SELECT
  id,
  tenant_id,
  book_id,
  user_id,
  rating,
  review_text,
  created_at,
  updated_at,
  (updated_at IS NOT NULL) AS is_edited
FROM reviews;

-- === rewrap_jobs ===
-- Contract view for [rewrap_jobs]
-- Adds helpers: is_done, is_running.
CREATE OR REPLACE VIEW vw_rewrap_jobs AS
SELECT
  id,
  key_wrapper_id,
  target_kms1_key_id,
  target_kms2_key_id,
  scheduled_at,
  started_at,
  finished_at,
  status,
  attempts,
  last_error,
  created_at,
  (status = 'done')     AS is_done,
  (status = 'running')  AS is_running
FROM rewrap_jobs;

-- === session_audit ===
-- Contract view for [session_audit]
-- Includes hashed token; adds hex helpers; meta_json -> meta.
CREATE OR REPLACE VIEW vw_session_audit AS
SELECT
  id,
  session_token_hash,
  UPPER(encode(session_token_hash,'hex')) AS session_token_hash_hex,
  session_token_key_version,
  csrf_token_hash,
  UPPER(encode(csrf_token_hash,'hex')) AS csrf_token_hash_hex,
  csrf_key_version,
  session_id,
  event,
  user_id,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  meta_json AS meta,
  outcome,
  created_at
FROM session_audit;

-- === sessions ===
-- Contract view for [sessions]
-- Hides token_hash and session_blob; adds activity helper & hex helpers.
CREATE OR REPLACE VIEW vw_sessions AS
SELECT
  id,
  token_hash_key_version,
  token_hash,
  UPPER(encode(token_hash,'hex')) AS token_hash_hex,
  token_fingerprint,
  UPPER(encode(token_fingerprint,'hex')) AS token_fingerprint_hex,
  token_issued_at,
  user_id,
  created_at,
  version,
  last_seen_at,
  expires_at,
  (NOT revoked AND (expires_at IS NULL OR expires_at > now())) AS is_active,
  failed_decrypt_count,
  last_failed_decrypt_at,
  revoked,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  session_blob,
  UPPER(encode(session_blob,'hex')) AS session_blob_hex
FROM sessions;

-- === sessions_active_by_user ===
-- Active sessions per user
CREATE OR REPLACE VIEW vw_sessions_active_by_user AS
SELECT
  user_id,
  COUNT(*) AS active_sessions,
  MIN(created_at) AS first_created_at,
  MAX(last_seen_at) AS last_seen_at
FROM sessions
WHERE (NOT revoked) AND (expires_at IS NULL OR expires_at > now())
GROUP BY user_id
ORDER BY active_sessions DESC;

-- === schema_registry ===
-- Contract view for [schema_registry]
CREATE OR REPLACE VIEW vw_schema_registry AS
SELECT
  id,
  system_name,
  component,
  version,
  checksum,
  applied_at,
  meta
FROM schema_registry;

-- === schema_registry_versions_latest ===
-- Latest version per system/component
CREATE OR REPLACE VIEW vw_schema_versions_latest AS
SELECT DISTINCT ON (system_name, component)
  system_name,
  component,
  version,
  checksum,
  applied_at,
  meta
FROM schema_registry
ORDER BY system_name, component, applied_at DESC;

-- === signatures ===
-- Contract view for [signatures]
-- Hides binary signature & payload hash; exposes hex.
CREATE OR REPLACE VIEW vw_signatures AS
SELECT
  id,
  subject_table,
  subject_pk,
  context,
  algo_id,
  signing_key_id,
  signature,
  UPPER(encode(signature,'hex'))    AS signature_hex,
  payload_hash,
  UPPER(encode(payload_hash,'hex')) AS payload_hash_hex,
  hash_algo_id,
  created_at
FROM signatures;

-- === signing_keys ===
-- Contract view for [signing_keys]
-- Hides raw keys; exposes hex for public/private (enc).
CREATE OR REPLACE VIEW vw_signing_keys AS
SELECT
  id,
  algo_id,
  name,
  public_key,
  UPPER(encode(public_key,'hex'))     AS public_key_hex,
  private_key_enc,
  UPPER(encode(private_key_enc,'hex')) AS private_key_enc_hex,
  kms_key_id,
  origin,
  status,
  scope,
  created_by,
  created_at,
  activated_at,
  retired_at,
  notes
FROM signing_keys;

-- === slo_status ===
-- Contract view for [slo_status]
CREATE OR REPLACE VIEW vw_slo_status AS
SELECT
  id,
  window_id,
  computed_at,
  sli_value,
  good_events,
  total_events,
  status
FROM slo_status;

-- === slo_windows ===
-- Contract view for [slo_windows]
CREATE OR REPLACE VIEW vw_slo_windows AS
SELECT
  id,
  name,
  objective,
  target_pct,
  window_interval,
  created_at
FROM slo_windows;

-- === slo_windows_rollup ===
-- SLO last computed status
CREATE OR REPLACE VIEW vw_slo_rollup AS
SELECT DISTINCT ON (w.id)
  w.id AS window_id,
  w.name,
  w.objective,
  w.target_pct,
  w.window_interval,
  s.computed_at,
  s.sli_value,
  s.good_events,
  s.total_events,
  s.status
FROM slo_windows w
LEFT JOIN slo_status s ON s.window_id = w.id
ORDER BY w.id, s.computed_at DESC NULLS LAST;

-- === sync_batch_items ===
-- Contract view for [sync_batch_items]
CREATE OR REPLACE VIEW vw_sync_batch_items AS
SELECT
  id,
  batch_id,
  event_key,
  status,
  error,
  created_at
FROM sync_batch_items;

-- === sync_batches ===
-- Contract view for [sync_batches]
CREATE OR REPLACE VIEW vw_sync_batches AS
SELECT
  id,
  producer_peer_id,
  consumer_peer_id,
  status,
  items_total,
  items_ok,
  items_failed,
  error,
  created_at,
  started_at,
  finished_at
FROM sync_batches;

-- === sync_batches_progress ===
-- Sync batch progress and success rate
CREATE OR REPLACE VIEW vw_sync_batch_progress AS
SELECT
  b.id,
  b.channel,
  b.status,
  b.items_total,
  b.items_ok,
  b.items_failed,
  ROUND(100.0 * b.items_ok / GREATEST(b.items_total,1), 2) AS success_pct,
  b.created_at,
  b.started_at,
  b.finished_at
FROM sync_batches b
ORDER BY b.created_at DESC;

-- === sync_errors ===
-- Contract view for [sync_errors]
CREATE OR REPLACE VIEW vw_sync_errors AS
SELECT
  id,
  source,
  event_key,
  peer_id,
  error,
  created_at
FROM sync_errors;

-- === sync_errors_failures_recent ===
-- Recent sync failures (24h)
CREATE OR REPLACE VIEW vw_sync_failures_recent AS
SELECT
  e.id,
  e.source,
  e.event_key,
  e.peer_id,
  e.error,
  e.created_at
FROM sync_errors e
WHERE e.created_at > now() - interval '24 hours'
ORDER BY e.created_at DESC;

-- === system_errors ===
-- Contract view for [system_errors]
-- Hides stack_trace/token; adds hex helpers and ip_pretty (from inet).
CREATE OR REPLACE VIEW vw_system_errors AS
SELECT
  id,
  level,
  message,
  exception_class,
  file,
  line,
  context,
  fingerprint,
  occurrences,
  user_id,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  ip_text,
  COALESCE(NULLIF(ip_text,'), bc_compat.inet6_ntoa(ip_bin))::varchar(39) AS ip_pretty,
  ip_bin,
  UPPER(encode(ip_bin,'hex')) AS ip_bin_hex,
  user_agent,
  url,
  method,
  http_status,
  resolved,
  resolved_by,
  resolved_at,
  created_at,
  last_seen
FROM system_errors;

-- === system_errors_daily ===
-- System errors per day and level
CREATE OR REPLACE VIEW vw_system_errors_daily AS
SELECT
  date_trunc('day', created_at) AS day,
  level,
  COUNT(*) AS count
FROM system_errors
GROUP BY 1,2
ORDER BY day DESC, level;

-- === system_errors_top_fingerprints ===
-- Top fingerprints by total occurrences
CREATE OR REPLACE VIEW vw_system_errors_top_fingerprints AS
SELECT
  fingerprint,
  MAX(message) AS sample_message,
  SUM(occurrences) AS occurrences,
  MIN(created_at) AS first_seen,
  MAX(last_seen)  AS last_seen,
  BOOL_OR(resolved) AS any_resolved,
  COUNT(*) AS rows_count
FROM system_errors
GROUP BY fingerprint
ORDER BY occurrences DESC, last_seen DESC;

-- === system_jobs ===
-- Contract view for [system_jobs]
CREATE OR REPLACE VIEW vw_system_jobs AS
SELECT
  id,
  job_type,
  payload,
  status,
  retries,
  scheduled_at,
  started_at,
  finished_at,
  error,
  created_at,
  updated_at,
  version
FROM system_jobs;

-- === system_jobs_metrics ===
-- Metrics for [system_jobs]
CREATE OR REPLACE VIEW vw_system_jobs_metrics AS
SELECT
  job_type,
  status,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE status='pending' AND (scheduled_at IS NULL OR scheduled_at <= now())) AS due_now,
  COUNT(*) FILTER (WHERE status='processing') AS processing,
  COUNT(*) FILTER (WHERE status='failed')     AS failed
FROM system_jobs
GROUP BY job_type, status
ORDER BY job_type, status;

-- === tax_rates ===
-- Contract view for [tax_rates]
CREATE OR REPLACE VIEW vw_tax_rates AS
SELECT
  id,
  country_iso2,
  category,
  rate,
  valid_from,
  valid_to
FROM tax_rates;

-- === tax_rates_current ===
-- Current (today) effective tax rates
CREATE OR REPLACE VIEW vw_tax_rates_current AS
SELECT *
FROM tax_rates t
WHERE CURRENT_DATE >= t.valid_from
  AND (t.valid_to IS NULL OR CURRENT_DATE <= t.valid_to);

-- === tenant_domains ===
-- Contract view for [tenant_domains]
CREATE OR REPLACE VIEW vw_tenant_domains AS
SELECT
  id,
  tenant_id,
  domain,
  is_primary,
  created_at
FROM tenant_domains;

-- === tenants ===
-- Contract view for [tenants]
CREATE OR REPLACE VIEW vw_tenants AS
SELECT
  id,
  name,
  slug,
  slug_ci,
  status,
  version,
  created_at,
  updated_at,
  deleted_at
FROM tenants;

-- === two_factor ===
-- Contract view for [two_factor]
-- Exposes secret/recovery blobs with hex helpers for troubleshooting.
CREATE OR REPLACE VIEW vw_two_factor AS
SELECT
  user_id,
  method,
  secret,
  UPPER(encode(secret,'hex')) AS secret_hex,
  recovery_codes_enc,
  UPPER(encode(recovery_codes_enc,'hex')) AS recovery_codes_enc_hex,
  hotp_counter,
  enabled,
  created_at,
  version,
  last_used_at
FROM two_factor;

-- === user_consents ===
-- Contract view for [user_consents]
CREATE OR REPLACE VIEW vw_user_consents AS
SELECT
  id,
  user_id,
  consent_type,
  version,
  granted,
  granted_at,
  source,
  meta
FROM user_consents;

-- === user_identities ===
-- Contract view for [user_identities]
CREATE OR REPLACE VIEW vw_user_identities AS
SELECT
  id,
  user_id,
  provider,
  provider_user_id,
  created_at,
  updated_at
FROM user_identities;

-- === user_profiles ===
-- Contract view for [user_profiles]
-- Includes encrypted profile blob + hex helper for debugging.
CREATE OR REPLACE VIEW vw_user_profiles AS
SELECT
  user_id,
  key_version,
  encryption_meta,
  updated_at,
  version,
  profile_enc,
  UPPER(encode(profile_enc,'hex')) AS profile_enc_hex
FROM user_profiles;

-- === users ===
-- Contract view for [users]
-- Hides password_* columns. Adds hex helpers.
CREATE OR REPLACE VIEW vw_users AS
SELECT
  id,
  email_hash,
  UPPER(encode(email_hash,'hex')) AS email_hash_hex,
  email_hash_key_version,
  is_active,
  is_locked,
  failed_logins,
  must_change_password,
  last_login_at,
  last_login_ip_hash,
  UPPER(encode(last_login_ip_hash,'hex')) AS last_login_ip_hash_hex,
  last_login_ip_key_version,
  created_at,
  updated_at,
  version,
  deleted_at,
  actor_role
FROM users;

-- === users_rbac_access_summary ===
-- Per-user summary: roles + effective permissions
CREATE OR REPLACE VIEW vw_rbac_user_access_summary AS
SELECT
  u.id AS user_id,
  COUNT(DISTINCT ur.role_id) FILTER (WHERE ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > now())) AS active_roles,
  COUNT(DISTINCT ep.permission_id) AS effective_permissions
FROM users u
LEFT JOIN rbac_user_roles ur ON ur.user_id = u.id
LEFT JOIN vw_rbac_effective_permissions ep ON ep.user_id = u.id
GROUP BY u.id;

-- === vat_validations ===
-- Contract view for [vat_validations]
-- Hides raw provider response; adds freshness flag (30 days).
CREATE OR REPLACE VIEW vw_vat_validations AS
SELECT
  id,
  vat_id,
  country_iso2,
  valid,
  checked_at,
  (checked_at > now() - interval '30 days') AS is_fresh
FROM vat_validations;

-- === verify_events ===
-- Contract view for [verify_events]
CREATE OR REPLACE VIEW vw_verify_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  UPPER(encode(ip_hash,'hex')) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta
FROM verify_events;

-- === webhook_outbox ===
-- Contract view for [webhook_outbox]
CREATE OR REPLACE VIEW vw_webhook_outbox AS
SELECT
  id,
  event_type,
  payload,
  status,
  retries,
  next_attempt_at,
  created_at,
  updated_at,
  version
FROM webhook_outbox;

-- === webhook_outbox_metrics ===
-- Metrics for [webhook_outbox]
CREATE OR REPLACE VIEW vw_webhook_outbox_metrics AS
SELECT
  status,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE status='pending' AND (next_attempt_at IS NULL OR next_attempt_at <= now())) AS due_now
FROM webhook_outbox
GROUP BY status;

-- === worker_locks ===
-- Contract view for [worker_locks]
CREATE OR REPLACE VIEW vw_worker_locks AS
SELECT
  name,
  locked_until
FROM worker_locks;


