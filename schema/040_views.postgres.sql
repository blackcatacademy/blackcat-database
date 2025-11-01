-- === app_settings ===
-- Contract view for [app_settings]
-- Masks secrets and protected values; adds has_value flag.
CREATE OR REPLACE VIEW vw_app_settings AS
SELECT
  setting_key,
  CASE WHEN "type" = 'secret' OR is_protected THEN NULL ELSE setting_value END AS setting_value,
  CASE WHEN app_settings.setting_value IS NOT NULL THEN 1 ELSE 0 END AS has_value,
  "type",
  section,
  description,
  is_protected,
  updated_at,
  version,
  updated_by
FROM app_settings;

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
  ip_bin,
  encode(ip_bin, 'hex') AS ip_bin_hex,
  user_agent,
  request_id
FROM audit_log;

-- === auth_events ===
-- Contract view for [auth_events]
CREATE OR REPLACE VIEW vw_auth_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
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
  encode(encryption_key_enc, 'hex') AS encryption_key_enc_hex,
  encode(encryption_iv,  'hex')     AS encryption_iv_hex,
  encode(encryption_tag, 'hex')     AS encryption_tag_hex,
  encode(encryption_aad, 'hex')     AS encryption_aad_hex
FROM book_assets;

-- === book_categories ===
-- Contract view for [book_categories]
CREATE OR REPLACE VIEW vw_book_categories AS
SELECT
  book_id,
  category_id
FROM book_categories;

-- === books ===
-- Contract view for [books]
-- Adds saleability helper.
CREATE OR REPLACE VIEW vw_books AS
SELECT
  id,
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
  CASE WHEN (is_active AND is_available AND (stock_quantity IS NULL OR stock_quantity > 0)) THEN 1 ELSE 0 END AS is_saleable,
  created_at,
  updated_at,
  version,
  deleted_at
FROM books;

-- === cart_items ===
-- Contract view for [cart_items]
CREATE OR REPLACE VIEW vw_cart_items AS
SELECT
  id,
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
  CASE WHEN (is_active AND (starts_at IS NULL OR now() >= starts_at) AND (ends_at IS NULL OR now() <= ends_at)) THEN 1 ELSE 0 END AS is_current,
  created_at,
  updated_at
FROM coupons;

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
  encode(backup_blob, 'hex') AS backup_blob_hex
FROM crypto_keys;

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
  encode(validator_hash, 'hex') AS validator_hash_hex
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
  encode(ciphertext, 'hex') AS ciphertext_hex
FROM encrypted_fields;

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

-- === idempotency_keys ===
-- Contract view for [idempotency_keys]
-- Hides gateway_payload body; adds expiry helpers.
CREATE OR REPLACE VIEW vw_idempotency_keys AS
SELECT
  key_hash,
  encode(key_hash, 'hex') AS key_hash_hex,
  payment_id,
  order_id,
  redirect_url,
  created_at,
  ttl_seconds,
  (created_at + make_interval(secs => ttl_seconds)) AS expires_at,
  CASE WHEN (ttl_seconds IS NOT NULL AND created_at IS NOT NULL AND (created_at + make_interval(secs => ttl_seconds)) <= now()) THEN 1 ELSE 0 END AS is_expired
FROM idempotency_keys;

-- === inventory_reservations ===
-- Contract view for [inventory_reservations]
-- Adds is_expired helper.
CREATE OR REPLACE VIEW vw_inventory_reservations AS
SELECT
  id,
  order_id,
  book_id,
  quantity,
  reserved_until,
  CASE WHEN now() > reserved_until THEN 1 ELSE 0 END AS is_expired,
  status,
  created_at,
  version
FROM inventory_reservations;

-- === invoice_items ===
-- Contract view for [invoice_items]
CREATE OR REPLACE VIEW vw_invoice_items AS
SELECT
  id,
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
  type,
  scopes,
  created_at,
  version,
  expires_at,
  last_used_at,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  replaced_by,
  revoked,
  meta,
  encode(token_hash, 'hex') AS token_hash_hex
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

-- === login_attempts ===
-- Contract view for [login_attempts]
-- Exposes hashed identifiers only; adds hex helpers.
CREATE OR REPLACE VIEW vw_login_attempts AS
SELECT
  id,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  attempted_at,
  success,
  user_id,
  username_hash,
  encode(username_hash, 'hex') AS username_hash_hex,
  auth_event_id
FROM login_attempts;

-- === newsletter_subscribers ===
-- Contract view for [newsletter_subscribers]
-- Hides email_enc; adds hex helpers for hashes.
CREATE OR REPLACE VIEW vw_newsletter_subscribers AS
SELECT
  id,
  user_id,
  email_hash,
  encode(email_hash, 'hex') AS email_hash_hex,
  email_hash_key_version,
  confirm_selector,
  confirm_validator_hash,
  encode(confirm_validator_hash, 'hex') AS confirm_validator_hash_hex,
  confirm_key_version,
  confirm_expires,
  confirmed_at,
  unsubscribe_token_hash,
  encode(unsubscribe_token_hash, 'hex') AS unsubscribe_token_hash_hex,
  unsubscribe_token_key_version,
  unsubscribed_at,
  origin,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  meta,
  created_at,
  updated_at,
  version,
  encode(email_enc, 'hex') AS email_enc_hex
FROM newsletter_subscribers;

-- === notifications ===
-- Contract view for [notifications]
-- Adds is_locked helper.
CREATE OR REPLACE VIEW vw_notifications AS
SELECT
  id,
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
  CASE WHEN (locked_until IS NOT NULL AND locked_until > now()) THEN 1 ELSE 0 END AS is_locked,
  locked_by,
  priority,
  created_at,
  updated_at,
  version
FROM notifications;

-- === order_item_downloads ===
-- Contract view for [order_item_downloads]
-- Hides download_token_hash; adds usage helpers & hex for ip_hash.
CREATE OR REPLACE VIEW vw_order_item_downloads AS
SELECT
  id,
  order_id,
  book_id,
  asset_id,
  token_key_version,
  key_version,
  max_uses,
  used,
  GREATEST(0, COALESCE(max_uses,0) - COALESCE(used,0)) AS uses_left,
  CASE WHEN (GREATEST(0, COALESCE(max_uses,0) - COALESCE(used,0)) > 0
        AND (expires_at IS NULL OR expires_at > now())) THEN 1 ELSE 0 END AS is_valid,
  expires_at,
  last_used_at,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  encode(download_token_hash, 'hex') AS download_token_hash_hex
FROM order_item_downloads;

-- === order_items ===
-- Contract view for [order_items]
CREATE OR REPLACE VIEW vw_order_items AS
SELECT
  id,
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
-- Hides encrypted_customer_blob; PG has native uuid (uuid_bin removed).
-- Adds uuid_text and uuid_hex.
CREATE OR REPLACE VIEW vw_orders AS
SELECT
  id,
  uuid,
  uuid::text AS uuid_text,
  upper(replace(uuid::text, '-','')) AS uuid_hex,
  encode(uuid_bin, 'hex') AS uuid_bin_hex,
  public_order_no,
  user_id,
  status,
  encrypted_customer_blob_key_version,
  encode(encrypted_customer_blob, 'hex') AS encrypted_customer_blob_hex,
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

-- === payment_gateway_notifications ===
-- Contract view for [payment_gateway_notifications]
CREATE OR REPLACE VIEW vw_payment_gateway_notifications AS
SELECT
  id,
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
  CASE WHEN payload IS NOT NULL THEN 1 ELSE 0 END AS has_payload,
  from_cache,
  created_at
FROM payment_webhooks;

-- === payments ===
-- Contract view for [payments]
-- Includes "details" JSON; mask in your app if needed.
CREATE OR REPLACE VIEW vw_payments AS
SELECT
  id,
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

-- === policy_kms_keys ===
-- Contract view for [policy_kms_keys]
CREATE OR REPLACE VIEW vw_policy_kms_keys AS
SELECT
  policy_id,
  kms_key_id,
  weight,
  priority
FROM policy_kms_keys;

-- === refunds ===
-- Contract view for [refunds]
CREATE OR REPLACE VIEW vw_refunds AS
SELECT
  id,
  payment_id,
  amount,
  currency,
  reason,
  status,
  created_at,
  details
FROM refunds;

-- === register_events ===
-- Contract view for [register_events]
CREATE OR REPLACE VIEW vw_register_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta
FROM register_events;

-- === reviews ===
-- Contract view for [reviews]
-- Adds is_edited helper.
CREATE OR REPLACE VIEW vw_reviews AS
SELECT
  id,
  book_id,
  user_id,
  rating,
  review_text,
  created_at,
  updated_at,
  CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END AS is_edited
FROM reviews;

-- === session_audit ===
-- Contract view for [session_audit]
-- Includes hashed token; adds hex helpers; meta_json -> meta.
CREATE OR REPLACE VIEW vw_session_audit AS
SELECT
  id,
  session_token,
  encode(session_token, 'hex') AS session_token_hex,
  session_token_key_version,
  csrf_key_version,
  session_id,
  event,
  user_id,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
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
  token_fingerprint,
  encode(token_fingerprint, 'hex') AS token_fingerprint_hex,
  token_issued_at,
  user_id,
  created_at,
  version,
  last_seen_at,
  expires_at,
  CASE WHEN (NOT revoked AND (expires_at IS NULL OR expires_at > now())) THEN 1 ELSE 0 END AS is_active,
  failed_decrypt_count,
  last_failed_decrypt_at,
  revoked,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  encode(token_hash,  'hex') AS token_hash_hex,
  encode(session_blob,'hex') AS session_blob_hex
FROM sessions;

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
  encode(ip_hash, 'hex') AS ip_hash_hex,
  ip_hash_key_version,
  ip_text,
  ip_text::text AS ip_pretty,
  ip_bin,
  encode(ip_bin, 'hex') AS ip_bin_hex,
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

-- === two_factor ===
-- Contract view for [two_factor]
-- Hides secret and recovery_codes_enc; keeps method and state.
CREATE OR REPLACE VIEW vw_two_factor AS
SELECT
  user_id,
  method,
  hotp_counter,
  enabled,
  created_at,
  version,
  last_used_at,
  encode(secret, 'hex')            AS secret_hex,
  encode(recovery_codes_enc, 'hex') AS recovery_codes_enc_hex
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
-- Omits large encrypted profile blob by default.
CREATE OR REPLACE VIEW vw_user_profiles AS
SELECT
  user_id,
  key_version,
  encryption_meta,
  updated_at,
  version,
  encode(profile_enc, 'hex') AS profile_enc_hex
FROM user_profiles;

-- === users ===
-- Contract view for [users]
-- Hides password_* columns. Adds hex helpers.
CREATE OR REPLACE VIEW vw_users AS
SELECT
  id,
  email_hash,
  encode(email_hash, 'hex') AS email_hash_hex,
  email_hash_key_version,
  is_active,
  is_locked,
  failed_logins,
  must_change_password,
  last_login_at,
  last_login_ip_hash,
  encode(last_login_ip_hash, 'hex') AS last_login_ip_hash_hex,
  last_login_ip_key_version,
  created_at,
  updated_at,
  version,
  deleted_at,
  actor_role
FROM users;

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
  CASE WHEN checked_at > now() - interval '30 days' THEN 1 ELSE 0 END AS is_fresh
FROM vat_validations;

-- === verify_events ===
-- Contract view for [verify_events]
CREATE OR REPLACE VIEW vw_verify_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
  encode(ip_hash, 'hex') AS ip_hash_hex,
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

-- === worker_locks ===
-- Contract view for [worker_locks]
CREATE OR REPLACE VIEW vw_worker_locks AS
SELECT
  name,
  locked_until
FROM worker_locks;


