@{
  FormatVersion = '1.1'

  # Contract views (v1.1) – sensitive fields still hidden, derived columns and HEX/UUID aliases added
  Views = @{

    users = @{
      create = @'
-- Contract view for [users]
-- Hides password_* columns. Adds HEX helpers for hashes.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_users AS
SELECT
  id,
  email_hash,
  CAST(LPAD(HEX(email_hash), 64, '0') AS CHAR(64)) AS email_hash_hex,
  email_hash_key_version,
  is_active,
  is_locked,
  failed_logins,
  must_change_password,
  last_login_at,
  last_login_ip_hash,
  CAST(LPAD(HEX(last_login_ip_hash), 64, '0') AS CHAR(64)) AS last_login_ip_hash_hex,
  last_login_ip_key_version,
  created_at,
  updated_at,
  version,
  deleted_at,
  actor_role
FROM users;
'@
    }

    login_attempts = @{
      create = @'
-- Contract view for [login_attempts]
-- Exposes hashed identifiers; adds HEX helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_login_attempts AS
SELECT
  id,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  attempted_at,
  success,
  user_id,
  username_hash,
  CAST(LPAD(HEX(username_hash), 64, '0') AS CHAR(64)) AS username_hash_hex,
  auth_event_id
FROM login_attempts;
'@
    }

    user_profiles = @{
      create = @'
-- Contract view for [user_profiles]
-- Includes encrypted profile blob + hex helper for debugging.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_user_profiles AS
SELECT
  user_id,
  key_version,
  encryption_meta,
  updated_at,
  version,
  profile_enc,
  UPPER(HEX(profile_enc)) AS profile_enc_hex
FROM user_profiles;
'@
    }

    user_identities = @{
      create = @'
-- Contract view for [user_identities]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_user_identities AS
SELECT
  id,
  user_id,
  provider,
  provider_user_id,
  created_at,
  updated_at
FROM user_identities;
'@
    }

    permissions = @{
      create = @'
-- Contract view for [permissions]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_permissions AS
SELECT
  id,
  name,
  description,
  created_at,
  updated_at
FROM permissions;
'@
    }

    two_factor = @{
      create = @'
-- Contract view for [two_factor]
-- Exposes secret/recovery blobs with hex helpers for troubleshooting.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_two_factor AS
SELECT
  user_id,
  `method`,
  secret,
  UPPER(HEX(secret)) AS secret_hex,
  recovery_codes_enc,
  UPPER(HEX(recovery_codes_enc)) AS recovery_codes_enc_hex,
  hotp_counter,
  enabled,
  created_at,
  version,
  last_used_at
FROM two_factor;
'@
    }

    session_audit = @{
      create = @'
-- Contract view for [session_audit]
-- Includes hashed token + HEX helpers; meta_json -> meta.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_session_audit AS
SELECT
  id,
  session_token_hash,
  CAST(LPAD(HEX(session_token_hash), 64, '0') AS CHAR(64)) AS session_token_hash_hex,
  session_token_key_version,
  csrf_token_hash,
  CAST(LPAD(HEX(csrf_token_hash), 64, '0') AS CHAR(64)) AS csrf_token_hash_hex,
  csrf_key_version,
  session_id,
  `event`,
  user_id,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  meta_json AS meta,
  outcome,
  created_at
FROM session_audit;
'@
    }

    sessions = @{
      create = @'
-- Contract view for [sessions]
-- Hides token_hash and session_blob; adds activity helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sessions AS
SELECT
  id,
  token_hash_key_version,
  token_hash,
  CAST(LPAD(HEX(token_hash), 64, '0') AS CHAR(64)) AS token_hash_hex,
  token_fingerprint,
  CAST(LPAD(HEX(token_fingerprint), 64, '0') AS CHAR(64)) AS token_fingerprint_hex,
  token_issued_at,
  user_id,
  created_at,
  version,
  last_seen_at,
  expires_at,
  (revoked = 0 AND (expires_at IS NULL OR expires_at > NOW())) AS is_active,
  failed_decrypt_count,
  last_failed_decrypt_at,
  revoked,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  session_blob,
  UPPER(HEX(session_blob)) AS session_blob_hex
FROM sessions;
'@
    }

    auth_events = @{
      create = @'
-- Contract view for [auth_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_auth_events AS
SELECT
  id,
  user_id,
  `type`,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta,
  meta_email
FROM auth_events;
'@
    }

    register_events = @{
      create = @'
-- Contract view for [register_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_register_events AS
SELECT
  id,
  user_id,
  `type`,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta
FROM register_events;
'@
    }

    verify_events = @{
      create = @'
-- Contract view for [verify_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_verify_events AS
SELECT
  id,
  user_id,
  `type`,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  user_agent,
  occurred_at,
  meta
FROM verify_events;
'@
    }

    system_errors = @{
      create = @'
-- Contract view for [system_errors]
-- Hides stack_trace and token; adds HEX/ip_pretty helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_system_errors AS
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
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  ip_text,
  ip_bin,
  CAST(LPAD(HEX(ip_bin), 32, '0') AS CHAR(32)) AS ip_bin_hex,
  CAST(COALESCE(INET6_NTOA(ip_bin), ip_text) AS CHAR(39)) AS ip_pretty,
  user_agent,
  url,
  `method`,
  http_status,
  resolved,
  resolved_by,
  resolved_at,
  created_at,
  last_seen
FROM system_errors;
'@
    }

    user_consents = @{
      create = @'
-- Contract view for [user_consents]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_user_consents AS
SELECT
  id,
  user_id,
  consent_type,
  version,
  granted,
  granted_at,
  `source`,
  meta
FROM user_consents;
'@
    }

    authors = @{
      create = @'
-- Contract view for [authors]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_authors AS
SELECT
  tenant_id,
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
'@
    }

    categories = @{
      create = @'
-- Contract view for [categories]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_categories AS
SELECT
  tenant_id,
  id,
  name,
  slug,
  parent_id,
  created_at,
  updated_at,
  version,
  deleted_at
FROM categories;
'@
    }

    books = @{
      create = @'
-- Contract view for [books]
-- Adds saleability helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_books AS
SELECT
  tenant_id,
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
  (is_active = 1 AND is_available = 1 AND (stock_quantity IS NULL OR stock_quantity > 0)) AS is_saleable,
  created_at,
  updated_at,
  version,
  deleted_at
FROM books;
'@
    }

    reviews = @{
      create = @'
-- Contract view for [reviews]
-- Adds is_edited helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_reviews AS
SELECT
  tenant_id,
  id,
  book_id,
  user_id,
  rating,
  review_text,
  created_at,
  updated_at,
  (updated_at IS NOT NULL) AS is_edited
FROM reviews;
'@
    }

    crypto_keys = @{
      create = @'
-- Contract view for [crypto_keys]
-- Hides backup_blob (encrypted backup payload). Keeps metadata for inventory.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_crypto_keys AS
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
  `usage`,
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
  CAST(LPAD(HEX(backup_blob), 64, '0') AS CHAR(64)) AS backup_blob_hex
FROM crypto_keys;
'@
    }

    key_events = @{
      create = @'
-- Contract view for [key_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_events AS
SELECT
  id,
  key_id,
  basename,
  event_type,
  actor_id,
  job_id,
  note,
  meta,
  `source`,
  created_at
FROM key_events;
'@
    }

    key_rotation_jobs = @{
      create = @'
-- Contract view for [key_rotation_jobs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_rotation_jobs AS
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
'@
    }

    key_usage = @{
      create = @'
-- Contract view for [key_usage]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_usage AS
SELECT
  id,
  key_id,
  usage_date,
  encrypt_count,
  decrypt_count,
  verify_count,
  last_used_at
FROM key_usage;
'@
    }

    jwt_tokens = @{
      create = @'
-- Contract view for [jwt_tokens]
-- Exposes token hash + hex helper and ip hash hex.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_jwt_tokens AS
SELECT
  id,
  jti,
  CAST(jti AS CHAR(36)) AS jti_text,
  user_id,
  token_hash_algo,
  token_hash_key_version,
  token_hash,
  CAST(LPAD(HEX(token_hash), 64, '0') AS CHAR(64)) AS token_hash_hex,
  `type`,
  scopes,
  created_at,
  version,
  expires_at,
  last_used_at,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0') AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  replaced_by,
  revoked,
  meta
FROM jwt_tokens;
'@
    }

    book_assets = @{
      create = @'
-- Contract view for [book_assets]
-- Hides encryption_key_enc, encryption_iv, encryption_tag, encryption_aad.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_book_assets AS
SELECT
  tenant_id,
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
  encryption_key_enc,
  encryption_iv,
  encryption_tag,
  encryption_aad,
  CAST(LPAD(HEX(encryption_key_enc), 64, '0') AS CHAR(64)) AS encryption_key_enc_hex,
  CAST(LPAD(HEX(encryption_iv),      32, '0') AS CHAR(32)) AS encryption_iv_hex,
  CAST(LPAD(HEX(encryption_tag),     32, '0') AS CHAR(32)) AS encryption_tag_hex,
  CAST(LPAD(HEX(encryption_aad),     64, '0') AS CHAR(64)) AS encryption_aad_hex
FROM book_assets;
'@
    }

    book_categories = @{
      create = @'
-- Contract view for [book_categories]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_book_categories AS
SELECT
  tenant_id,
  book_id,
  category_id
FROM book_categories;
'@
    }

    inventory_reservations = @{
      create = @'
-- Contract view for [inventory_reservations]
-- Adds is_expired helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_inventory_reservations AS
SELECT
  tenant_id,
  id,
  order_id,
  book_id,
  quantity,
  reserved_until,
  (NOW() > reserved_until) AS is_expired,
  status,
  created_at,
  version
FROM inventory_reservations;
'@
    }

    carts = @{
      create = @'
-- Contract view for [carts]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_carts AS
SELECT
  tenant_id,
  id,
  user_id,
  note,
  created_at,
  updated_at,
  version
FROM carts;
'@
    }

    cart_items = @{
      create = @'
-- Contract view for [cart_items]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_cart_items AS
SELECT
  tenant_id,
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
'@
    }

    orders = @{
      create = @'
-- Contract view for [orders]
-- Hides encrypted_customer_blob; adds UUID helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_orders AS
SELECT
  id,
  tenant_id,
  uuid,
  uuid_bin,
  CAST(BIN_TO_UUID(uuid_bin, TRUE) AS CHAR(36)) AS uuid_text,
  CAST(LPAD(HEX(uuid_bin), 32, '0') AS CHAR(32)) AS uuid_bin_hex,
  CAST(HEX(COALESCE(uuid_bin, UNHEX(REPLACE(CAST(uuid AS CHAR(36)), '-', '')))) AS CHAR(32)) AS uuid_hex,
  public_order_no,
  user_id,
  status,
  encrypted_customer_blob_key_version,
  encrypted_customer_blob,
  UPPER(HEX(encrypted_customer_blob)) AS encrypted_customer_blob_hex,
  OCTET_LENGTH(encrypted_customer_blob) AS encrypted_customer_blob_len,
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
'@
    }

    order_items = @{
      create = @'
-- Contract view for [order_items]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_order_items AS
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
'@
    }

    order_item_downloads = @{
      create = @'
-- Contract view for [order_item_downloads]
-- Hides download_token_hash; adds usage helpers and HEX for ip_hash.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_order_item_downloads AS
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
  ((GREATEST(0, COALESCE(max_uses,0) - COALESCE(used,0)) > 0) AND (expires_at IS NULL OR expires_at > NOW())) AS is_valid,
  expires_at,
  last_used_at,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  download_token_hash,
  CAST(LPAD(HEX(download_token_hash), 64, '0')  AS CHAR(64)) AS download_token_hash_hex
FROM order_item_downloads;
'@
    }

    invoices = @{
      create = @'
-- Contract view for [invoices]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_invoices AS
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
'@
    }

    invoice_items = @{
      create = @'
-- Contract view for [invoice_items]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_invoice_items AS
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
'@
    }

    payments = @{
      create = @'
-- Contract view for [payments]
-- Includes "details" JSON; mask in your app if needed.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payments AS
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
'@
    }

    payment_logs = @{
      create = @'
-- Contract view for [payment_logs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payment_logs AS
SELECT
  id,
  payment_id,
  log_at,
  message
FROM payment_logs;
'@
    }

    payment_webhooks = @{
      create = @'
-- Contract view for [payment_webhooks]
-- Hides raw payload JSON; exposes presence.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payment_webhooks AS
SELECT
  id,
  payment_id,
  gateway_event_id,
  payload_hash,
  CAST(payload IS NOT NULL AS UNSIGNED) AS has_payload,
  from_cache,
  created_at
FROM payment_webhooks;
'@
    }

    idempotency_keys = @{
      create = @'
-- Contract view for [idempotency_keys]
-- Hides gateway_payload body; adds expiry helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_idempotency_keys AS
SELECT
  key_hash,
  tenant_id,
  payment_id,
  order_id,
  gateway_payload,
  redirect_url,
  created_at,
  ttl_seconds,
  (created_at + INTERVAL ttl_seconds SECOND) AS expires_at,
  (ttl_seconds IS NOT NULL AND created_at IS NOT NULL AND created_at + INTERVAL ttl_seconds SECOND <= NOW()) AS is_expired,
  UPPER(key_hash) AS key_hash_hex
FROM idempotency_keys;
'@
    }

    refunds = @{
      create = @'
-- Contract view for [refunds]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_refunds AS
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
'@
    }

    coupons = @{
      create = @'
-- Contract view for [coupons]
-- Adds is_current helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_coupons AS
SELECT
  id,
  tenant_id,
  code,
  `type`,
  value,
  currency,
  starts_at,
  ends_at,
  max_redemptions,
  min_order_amount,
  applies_to,
  is_active,
  (is_active = 1 AND (starts_at IS NULL OR NOW() >= starts_at) AND (ends_at IS NULL OR NOW() <= ends_at)) AS is_current,
  created_at,
  updated_at
FROM coupons;
'@
    }

    coupon_redemptions = @{
      create = @'
-- Contract view for [coupon_redemptions]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_coupon_redemptions AS
SELECT
  id,
  tenant_id,
  coupon_id,
  user_id,
  order_id,
  redeemed_at,
  amount_applied
FROM coupon_redemptions;
'@
    }

    countries = @{
      create = @'
-- Contract view for [countries]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_countries AS
SELECT
  iso2,
  name
FROM countries;
'@
    }

    tax_rates = @{
      create = @'
-- Contract view for [tax_rates]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_tax_rates AS
SELECT
  id,
  country_iso2,
  category,
  rate,
  valid_from,
  valid_to
FROM tax_rates;
'@
    }

    vat_validations = @{
      create = @'
-- Contract view for [vat_validations]
-- Hides raw provider response; adds freshness flag (30 days).
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_vat_validations AS
SELECT
  id,
  vat_id,
  country_iso2,
  valid,
  checked_at,
  (checked_at > NOW() - INTERVAL 30 DAY) AS is_fresh
FROM vat_validations;
'@
    }

    app_settings = @{
      create = @'
-- Contract view for [app_settings]
-- Masks secrets and protected values; adds has_value flag.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_app_settings AS
SELECT
  setting_key,
  CASE WHEN `type` = 'secret' OR is_protected = 1 THEN NULL ELSE setting_value END AS setting_value,
  CASE WHEN app_settings.setting_value IS NOT NULL THEN 1 ELSE 0 END AS has_value,
  `type`,
  section,
  description,
  is_protected,
  updated_at,
  version,
  updated_by
FROM app_settings;
'@
    }

    audit_log = @{
      create = @'
-- Contract view for [audit_log]
-- Omits old_value/new_value JSON; adds ip_pretty from ip_bin.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_audit_log AS
SELECT
  id,
  table_name,
  record_id,
  changed_by,
  change_type,
  changed_at,
  ip_bin,
  CAST(LPAD(HEX(ip_bin), 32, '0') AS CHAR(32)) AS ip_bin_hex,
  CAST(INET6_NTOA(ip_bin) AS CHAR(39)) AS ip_pretty,
  user_agent,
  request_id
FROM audit_log;
'@
    }

    webhook_outbox = @{
      create = @'
-- Contract view for [webhook_outbox]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_webhook_outbox AS
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
'@
    }

    payment_gateway_notifications = @{
      create = @'
-- Contract view for [payment_gateway_notifications]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payment_gateway_notifications AS
SELECT
  id,
  transaction_id,
  tenant_id,
  received_at,
  version,
  processing_by,
  processing_until,
  attempts,
  last_error,
  status
FROM payment_gateway_notifications;
'@
    }

    email_verifications = @{
      create = @'
-- Contract view for [email_verifications]
-- Hides token_hash and validator_hash; exposes selector and timestamps.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_email_verifications AS
SELECT
  id,
  user_id,
  selector,
  key_version,
  expires_at,
  created_at,
  used_at,
  validator_hash,
  CAST(LPAD(HEX(validator_hash), 64, '0') AS CHAR(64)) AS validator_hash_hex
FROM email_verifications;
'@
    }

    notifications = @{
      create = @'
-- Contract view for [notifications]
-- Adds is_locked helper.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_notifications AS
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
  (locked_until IS NOT NULL AND locked_until > NOW()) AS is_locked,
  locked_by,
  priority,
  created_at,
  updated_at,
  version
FROM notifications;
'@
    }

    newsletter_subscribers = @{
      create = @'
-- Contract view for [newsletter_subscribers]
-- Hides email_enc; adds HEX helpers for hashes.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_newsletter_subscribers AS
SELECT
  id,
  tenant_id,
  user_id,
  email_enc,
  email_hash,
  CAST(LPAD(HEX(email_hash), 64, '0') AS CHAR(64)) AS email_hash_hex,
  email_hash_key_version,
  confirm_selector,
  confirm_validator_hash,
  CAST(LPAD(HEX(confirm_validator_hash), 64, '0') AS CHAR(64)) AS confirm_validator_hash_hex,
  confirm_key_version,
  confirm_expires,
  confirmed_at,
  unsubscribe_token_hash,
  CAST(LPAD(HEX(unsubscribe_token_hash), 64, '0') AS CHAR(64)) AS unsubscribe_token_hash_hex,
  unsubscribe_token_key_version,
  unsubscribed_at,
  origin,
  ip_hash,
  CAST(LPAD(HEX(ip_hash), 64, '0')  AS CHAR(64)) AS ip_hash_hex,
  ip_hash_key_version,
  meta,
  created_at,
  updated_at,
  version,
  CAST(LPAD(HEX(email_enc), 64, '0') AS CHAR(64)) AS email_enc_hex
FROM newsletter_subscribers;
'@
    }

    system_jobs = @{
      create = @'
-- Contract view for [system_jobs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_system_jobs AS
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
'@
    }

    worker_locks = @{
      create = @'
-- Contract view for [worker_locks]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_worker_locks AS
SELECT
  name,
  locked_until
FROM worker_locks;
'@
    }

    encrypted_fields = @{
      create = @'
-- Contract view for [encrypted_fields]
-- Hides ciphertext; keeps routing metadata.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encrypted_fields AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  meta,
  created_at,
  updated_at,
  ciphertext,
  CAST(LPAD(HEX(ciphertext), 64, '0') AS CHAR(64)) AS ciphertext_hex
FROM encrypted_fields;
'@
    }

    kms_providers = @{
      create = @'
-- Contract view for [kms_providers]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_providers AS
SELECT
  id,
  name,
  provider,
  location,
  project_tenant,
  created_at,
  is_enabled
FROM kms_providers;
'@
    }

    kms_keys = @{
      create = @'
-- Contract view for [kms_keys]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_keys AS
SELECT
  id,
  provider_id,
  external_key_ref,
  purpose,
  algorithm,
  status,
  created_at
FROM kms_keys;
'@
    }

    encryption_policies = @{
      create = @'
-- Contract view for [encryption_policies]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encryption_policies AS
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
'@
    }

    policy_kms_keys = @{
      create = @'
-- Contract view for [policy_kms_keys]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_policy_kms_keys AS
SELECT
  policy_id,
  kms_key_id,
  weight,
  priority
FROM policy_kms_keys;
'@
    }

    encryption_events = @{
      create = @'
-- Contract view for [encryption_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encryption_events AS
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
'@
    }

    tenants = @{
      create = @'
-- Contract view for [tenants]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_tenants AS
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
'@
    }

    encryption_bindings = @{
      create = @'
-- Contract view for [encryption_bindings]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encryption_bindings AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  key_wrapper_id,
  created_at
FROM encryption_bindings;
'@
    }

    event_outbox = @{
      create = @'
-- Contract view for [event_outbox]
-- Adds helpers: is_pending, is_due.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_outbox AS
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
  (status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())) AS is_due
FROM event_outbox;
'@
    }

    event_inbox = @{
      create = @'
-- Contract view for [event_inbox]
-- Adds helper: is_failed.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_inbox AS
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
'@
    }

    event_dlq = @{
      create = @'
-- Contract view for [event_dlq]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_dlq AS
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
'@
    }

    rewrap_jobs = @{
      create = @'
-- Contract view for [rewrap_jobs]
-- Adds helpers: is_done, is_running.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rewrap_jobs AS
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
  (status = 'done')    AS is_done,
  (status = 'running') AS is_running
FROM rewrap_jobs;
'@
    }

    audit_chain = @{
      create = @'
-- Contract view for [audit_chain]
-- Exposes hash blobs with hex helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_audit_chain AS
SELECT
  id,
  audit_id,
  chain_name,
  prev_hash,
  UPPER(HEX(prev_hash)) AS prev_hash_hex,
  `hash`,
  UPPER(HEX(`hash`))    AS hash_hex,
  created_at
FROM audit_chain;
'@
    }

    crypto_algorithms = @{
      create = @'
-- Contract view for [crypto_algorithms]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_crypto_algorithms AS
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
'@
    }

    policy_algorithms = @{
      create = @'
-- Contract view for [policy_algorithms]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_policy_algorithms AS
SELECT
  policy_id,
  algo_id,
  role,
  weight,
  priority
FROM policy_algorithms;
'@
    }

    key_wrapper_layers = @{
      create = @'
-- Contract view for [key_wrapper_layers]
-- Hides ciphertexts; exposes hex helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_wrapper_layers AS
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
  UPPER(HEX(kem_ciphertext)) AS kem_ciphertext_hex,
  UPPER(HEX(encap_pubkey))   AS encap_pubkey_hex
FROM key_wrapper_layers;
'@
    }

    key_wrappers = @{
      create = @'
-- Contract view for [key_wrappers]
-- Hides DEK wraps; exposes hex helpers and status flags.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_key_wrappers AS
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
  UPPER(HEX(dek_wrap1)) AS dek_wrap1_hex,
  UPPER(HEX(dek_wrap2)) AS dek_wrap2_hex
FROM key_wrappers;
'@
    }

    hash_profiles = @{
      create = @'
-- Contract view for [hash_profiles]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_hash_profiles AS
SELECT
  id,
  name,
  algo_id,
  output_len,
  params,
  status,
  created_at
FROM hash_profiles;
'@
    }

    field_hash_policies = @{
      create = @'
-- Contract view for [field_hash_policies]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_field_hash_policies AS
SELECT
  id,
  entity_table,
  field_name,
  profile_id,
  effective_from,
  notes
FROM field_hash_policies;
'@
    }

    pq_migration_jobs = @{
      create = @'
-- Contract view for [pq_migration_jobs]
-- Adds helpers: is_done, is_running.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_pq_migration_jobs AS
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
'@
    }

    api_keys = @{
      create = @'
-- Contract view for [api_keys]
-- Hides token_hash; exposes hex and activity helpers.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_api_keys AS
SELECT
  id,
  tenant_id,
  user_id,
  name,
  token_hash_key_version,
  token_hash,
  UPPER(HEX(token_hash)) AS token_hash_hex,
  scopes,
  status,
  last_used_at,
  expires_at,
  created_at,
  updated_at,
  (status = 'active' AND (expires_at IS NULL OR expires_at > NOW())) AS is_active
FROM api_keys;
'@
    }

    encryption_policy_bindings = @{
      create = @'
-- Contract view for [encryption_policy_bindings]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encryption_policy_bindings AS
SELECT
  id,
  entity_table,
  field_name,
  policy_id,
  effective_from,
  notes
FROM encryption_policy_bindings;
'@
    }

    encryption_policy_bindings_current = @{
      create = @'
-- Current policy per (entity, field)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encryption_policy_bindings_current AS
SELECT
  entity_table,
  field_name,
  policy_id,
  effective_from
FROM (
  SELECT
    entity_table,
    field_name,
    policy_id,
    effective_from,
    ROW_NUMBER() OVER (PARTITION BY entity_table, field_name ORDER BY effective_from DESC) AS rn
  FROM encryption_policy_bindings
  WHERE effective_from <= NOW()
) ranked
WHERE rn = 1;
'@
    }

    entity_external_ids = @{
      create = @'
-- Contract view for [entity_external_ids]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_entity_external_ids AS
SELECT
  id,
  entity_table,
  entity_pk,
  source,
  external_id,
  created_at
FROM entity_external_ids;
'@
    }

    crypto_standard_aliases = @{
      create = @'
-- Contract view for [crypto_standard_aliases]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_crypto_standard_aliases AS
SELECT
  alias,
  algo_id,
  notes,
  created_at
FROM crypto_standard_aliases;
'@
    }

    global_id_registry = @{
      create = @'
-- Contract view for [global_id_registry]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_global_id_registry AS
SELECT
  gid,
  guid,
  entity_table,
  entity_pk,
  created_at
FROM global_id_registry;
'@
    }

    global_id_registry_map = @{
      create = @'
-- Global→local id registry (legacy map alias)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_global_id_map AS
SELECT
  gid,
  guid,
  entity_table,
  entity_pk,
  created_at
FROM global_id_registry;
'@
    }

    kms_health_checks = @{
      create = @'
-- Contract view for [kms_health_checks]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_health_checks AS
SELECT
  id,
  provider_id,
  kms_key_id,
  status,
  latency_ms,
  error,
  checked_at
FROM kms_health_checks;
'@
    }

    signing_keys = @{
      create = @'
-- Contract view for [signing_keys]
-- Hides raw keys; exposes hex for public/private (enc).
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_signing_keys AS
SELECT
  id,
  algo_id,
  name,
  public_key,
  UPPER(HEX(public_key))      AS public_key_hex,
  private_key_enc,
  UPPER(HEX(private_key_enc)) AS private_key_enc_hex,
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
'@
    }

    signatures = @{
      create = @'
-- Contract view for [signatures]
-- Hides binary signature & payload hash; exposes hex.
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_signatures AS
SELECT
  id,
  subject_table,
  subject_pk,
  context,
  algo_id,
  signing_key_id,
  signature,
  UPPER(HEX(signature))    AS signature_hex,
  payload_hash,
  UPPER(HEX(payload_hash)) AS payload_hash_hex,
  hash_algo_id,
  created_at
FROM signatures;
'@
    }

    book_assets_encryption_coverage = @{
      create = @'
-- Encryption coverage per asset_type
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_book_assets_encryption_coverage AS
SELECT
  asset_type,
  COUNT(*) AS total,
  SUM(CASE WHEN is_encrypted THEN 1 ELSE 0 END) AS encrypted,
  ROUND(100.0 * SUM(CASE WHEN is_encrypted THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS pct_encrypted
FROM book_assets
GROUP BY asset_type
ORDER BY asset_type;
'@
    }

    crypto_keys_inventory = @{
      create = @'
-- Inventory of keys by type/status
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_crypto_keys_inventory AS
SELECT
  key_type,
  status,
  COUNT(*) AS total
FROM crypto_keys
GROUP BY key_type, status
ORDER BY key_type, status;
'@
    }

    crypto_keys_latest = @{
      create = @'
-- Latest version per basename
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_crypto_keys_latest AS
SELECT
  basename,
  id,
  version,
  status,
  algorithm,
  key_type,
  activated_at,
  retired_at
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY basename ORDER BY version DESC) AS rn
  FROM crypto_keys
) ranked
WHERE rn = 1
ORDER BY basename;
'@
    }

    rbac_role_permissions = @{
      create = @'
-- Contract view for [rbac_role_permissions]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_role_permissions AS
SELECT
  role_id,
  permission_id,
  effect,
  source,
  created_at
FROM rbac_role_permissions;
'@
    }

    rbac_roles = @{
      create = @'
-- Contract view for [rbac_roles]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_roles AS
SELECT
  id,
  repo_id,
  slug,
  name,
  description,
  version,
  status,
  created_at,
  updated_at
FROM rbac_roles;
'@
    }

    rbac_user_roles = @{
      create = @'
-- Contract view for [rbac_user_roles]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_user_roles AS
SELECT
  id,
  user_id,
  role_id,
  tenant_id,
  scope,
  status,
  granted_by,
  granted_at,
  expires_at
FROM rbac_user_roles;
'@
    }

    rbac_user_permissions = @{
      create = @'
-- Contract view for [rbac_user_permissions]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_user_permissions AS
SELECT
  id,
  user_id,
  permission_id,
  tenant_id,
  scope,
  effect,
  granted_by,
  granted_at,
  expires_at
FROM rbac_user_permissions;
'@
    }

    rbac_roles_coverage = @{
      create = @'
-- Role coverage: permissions per role (allow/deny)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_roles_coverage AS
SELECT
  r.id AS role_id,
  r.slug,
  r.name,
  SUM(CASE WHEN rp.effect = 'allow' THEN 1 ELSE 0 END) AS allows,
  SUM(CASE WHEN rp.effect = 'deny'  THEN 1 ELSE 0 END) AS denies,
  COUNT(rp.permission_id) AS total_rules
FROM rbac_roles r
LEFT JOIN rbac_role_permissions rp ON rp.role_id = r.id
GROUP BY r.id, r.slug, r.name
ORDER BY total_rules DESC, allows DESC;
'@
    }

    rbac_user_roles_expiring_assignments = @{
      create = @'
-- Roles/permissions which will expire within 7 days
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_expiring_assignments AS
SELECT
  'role' AS kind,
  ur.user_id,
  CAST(ur.role_id AS UNSIGNED) AS id,
  ur.tenant_id,
  ur.scope,
  ur.expires_at
FROM rbac_user_roles ur
WHERE ur.expires_at IS NOT NULL
  AND ur.expires_at <= NOW() + INTERVAL 7 DAY
UNION ALL
SELECT
  'permission' AS kind,
  up.user_id,
  CAST(up.permission_id AS UNSIGNED) AS id,
  up.tenant_id,
  up.scope,
  up.expires_at
FROM rbac_user_permissions up
WHERE up.expires_at IS NOT NULL
  AND up.expires_at <= NOW() + INTERVAL 7 DAY;
'@
    }

    rbac_user_permissions_conflicts = @{
      create = @'
-- Potential conflicts: same (user,perm,tenant,scope) both allowed and denied
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_conflicts AS
WITH allowed AS (
  SELECT user_id, permission_id, tenant_id, scope FROM rbac_user_permissions WHERE effect='allow'
  UNION
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect='allow'
  WHERE ur.status='active' AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
),
denied AS (
  SELECT user_id, permission_id, tenant_id, scope FROM rbac_user_permissions WHERE effect='deny'
  UNION
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect='deny'
  WHERE ur.status='active' AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
)
SELECT DISTINCT
  a.user_id,
  a.permission_id,
  p.name AS permission_name,
  a.tenant_id,
  a.scope
FROM allowed a
JOIN denied d
  ON d.user_id = a.user_id
 AND d.permission_id = a.permission_id
 AND COALESCE(d.tenant_id, -1) = COALESCE(a.tenant_id, -1)
 AND COALESCE(d.scope, '') = COALESCE(a.scope, '')
JOIN permissions p ON p.id = a.permission_id;
'@
    }

    rbac_user_permissions_effective = @{
      create = @'
-- Effective permissions per user (Deny > Allow), including tenant/scope
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_effective_permissions AS
WITH allowed AS (
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect = 'allow'
  WHERE ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
  UNION
  SELECT up.user_id, up.permission_id, up.tenant_id, up.scope
  FROM rbac_user_permissions up
  WHERE up.effect = 'allow' AND (up.expires_at IS NULL OR up.expires_at > NOW())
),
denied AS (
  SELECT ur.user_id, rp.permission_id, ur.tenant_id, ur.scope
  FROM rbac_user_roles ur
  JOIN rbac_role_permissions rp ON rp.role_id = ur.role_id AND rp.effect = 'deny'
  WHERE ur.status = 'active' AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
  UNION
  SELECT up.user_id, up.permission_id, up.tenant_id, up.scope
  FROM rbac_user_permissions up
  WHERE up.effect = 'deny' AND (up.expires_at IS NULL OR up.expires_at > NOW())
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
  SELECT 1
  FROM denied d
  WHERE d.user_id = a.user_id
    AND d.permission_id = a.permission_id
    AND COALESCE(d.tenant_id, -1) = COALESCE(a.tenant_id, -1)
    AND COALESCE(d.scope, '') = COALESCE(a.scope, '')
);
'@
    }

    rbac_repositories_sync_status = @{
      create = @'
-- RBAC repository sync cursors (per peer)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_sync_status AS
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
'@
    }

    deletion_jobs = @{
      create = @'
-- Contract view for [deletion_jobs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_deletion_jobs AS
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
'@
    }

    device_fingerprints = @{
      create = @'
-- Contract view for [device_fingerprints]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_device_fingerprints AS
SELECT
  id,
  user_id,
  fingerprint_hash,
  UPPER(HEX(fingerprint_hash)) AS fingerprint_hash_hex,
  attributes,
  risk_score,
  first_seen,
  last_seen,
  last_ip_hash,
  UPPER(HEX(last_ip_hash)) AS last_ip_hash_hex,
  last_ip_key_version
FROM device_fingerprints;
'@
    }

    deletion_jobs_status = @{
      create = @'
-- Deletion jobs summary
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_deletion_jobs_status AS
SELECT
  status,
  COUNT(*) AS jobs,
  MAX(finished_at) AS last_finished
FROM deletion_jobs
GROUP BY status
ORDER BY status;
'@
    }

    device_fingerprints_risk_recent = @{
      create = @'
-- Devices with elevated risk seen in last 30 days
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_device_risk_recent AS
SELECT
  d.id,
  d.user_id,
  d.risk_score,
  d.first_seen,
  d.last_seen,
  UPPER(HEX(d.fingerprint_hash)) AS fingerprint_hash_hex
FROM device_fingerprints d
WHERE d.last_seen > NOW() - INTERVAL 30 DAY
  AND d.risk_score IS NOT NULL
ORDER BY d.risk_score DESC, d.last_seen DESC;
'@
    }

    encrypted_fields_without_binding = @{
      create = @'
-- Encrypted fields without explicit encryption_binding (for governance)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_encrypted_fields_without_binding AS
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
'@
    }

    privacy_requests_status = @{
      create = @'
-- Privacy requests status
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_privacy_requests_status AS
SELECT
  type,
  status,
  COUNT(*) AS total,
  MAX(processed_at) AS last_processed
FROM privacy_requests
GROUP BY type, status
ORDER BY type, status;
'@
    }

    rate_limit_counters_usage = @{
      create = @'
-- Rate limit counters per subject/name (last hour window)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rate_limit_usage AS
SELECT
  subject_type,
  subject_id,
  name,
  SUM(`count`) AS total_count,
  MIN(window_start) AS first_window,
  MAX(window_start) AS last_window
FROM rate_limit_counters
WHERE window_start > NOW() - INTERVAL 1 HOUR
GROUP BY subject_type, subject_id, name
ORDER BY total_count DESC;
'@
    }

    tax_rates_current = @{
      create = @'
-- Current (today) effective tax rates
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_tax_rates_current AS
SELECT
  *
FROM tax_rates t
WHERE CURRENT_DATE() >= t.valid_from
  AND (t.valid_to IS NULL OR CURRENT_DATE() <= t.valid_to);
'@
    }

    pq_migration_jobs_metrics = @{
      create = @'
-- PQ migration progress by status
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_pq_migration_jobs_metrics AS
SELECT
  status,
  COUNT(*) AS jobs,
  SUM(processed_count) AS processed_total
FROM pq_migration_jobs
GROUP BY status
ORDER BY status;
'@
    }

    data_retention_policies = @{
      create = @'
-- Contract view for [data_retention_policies]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_data_retention_policies AS
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
'@
    }

    data_retention_policies_due = @{
      create = @'
-- Policies and when they become due (relative)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_retention_due AS
-- NOTE: keep_for is stored as textual duration in MySQL, so due_from_now is emitted as NULL.
SELECT
  id,
  entity_table,
  field_name,
  action,
  keep_for,
  active,
  NULL AS due_from_now,
  notes,
  created_at
FROM data_retention_policies
WHERE active;
'@
    }

    payments_anomalies = @{
      create = @'
-- Potential anomalies in payments
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payments_anomalies AS
SELECT
  p.*
FROM payments p
WHERE
  (status IN ('paid','authorized') AND amount < 0)
  OR (status = 'paid' AND (transaction_id IS NULL OR transaction_id = ''))
  OR (status = 'failed' AND amount > 0);
'@
    }

    payments_status_summary = @{
      create = @'
-- Payment status summary by gateway
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_payments_status_summary AS
SELECT
  gateway,
  status,
  COUNT(*) AS total,
  SUM(CASE WHEN status IN ('authorized','paid','partially_refunded','refunded') THEN amount ELSE 0 END) AS sum_amount
FROM payments
GROUP BY gateway, status
ORDER BY gateway, status;
'@
    }

    event_inbox_metrics = @{
      create = @'
-- Aggregated metrics for [event_inbox]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_inbox_metrics AS
WITH base AS (
  SELECT
    source,
    COUNT(*) AS total,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END)   AS pending,
    SUM(CASE WHEN status = 'processed' THEN 1 ELSE 0 END) AS processed,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)    AS failed,
    AVG(attempts) AS avg_attempts
  FROM event_inbox
  GROUP BY source
),
ranked AS (
  SELECT
    source,
    attempts,
    ROW_NUMBER() OVER (PARTITION BY source ORDER BY attempts) AS rn,
    COUNT(*) OVER (PARTITION BY source) AS cnt
  FROM event_inbox
),
pcts AS (
  SELECT
    source,
    MAX(CASE WHEN rn = CEIL(0.95 * cnt) THEN attempts END) AS p95_attempts
  FROM ranked
  GROUP BY source
)
SELECT
  b.source,
  b.total,
  b.pending,
  b.processed,
  b.failed,
  b.avg_attempts,
  p.p95_attempts
FROM base b
LEFT JOIN pcts p ON p.source = b.source;
'@
    }

    event_outbox_metrics = @{
      create = @'
-- Aggregated metrics for [event_outbox]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_outbox_metrics AS
WITH base AS (
  SELECT
    event_type,
    COUNT(*) AS total,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending,
    SUM(CASE WHEN status = 'sent'     THEN 1 ELSE 0 END) AS sent,
    SUM(CASE WHEN status = 'failed'   THEN 1 ELSE 0 END) AS failed,
    AVG(TIMESTAMPDIFF(SECOND, created_at, NOW())) AS avg_created_lag_sec,
    AVG(attempts) AS avg_attempts,
    MAX(attempts) AS max_attempts,
    SUM(CASE WHEN status IN ('pending','failed') AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
             THEN 1 ELSE 0 END) AS due_now
  FROM event_outbox
  GROUP BY event_type
),
ranked AS (
  SELECT
    event_type,
    TIMESTAMPDIFF(SECOND, created_at, NOW()) AS lag_sec,
    ROW_NUMBER() OVER (PARTITION BY event_type ORDER BY TIMESTAMPDIFF(SECOND, created_at, NOW())) AS rn,
    COUNT(*) OVER (PARTITION BY event_type) AS cnt
  FROM event_outbox
),
pcts AS (
  SELECT
    event_type,
    MAX(CASE WHEN rn = CEIL(0.50 * cnt) THEN lag_sec END) AS p50_created_lag_sec,
    MAX(CASE WHEN rn = CEIL(0.95 * cnt) THEN lag_sec END) AS p95_created_lag_sec
  FROM ranked
  GROUP BY event_type
)
SELECT
  b.event_type,
  b.total,
  b.pending,
  b.sent,
  b.failed,
  b.avg_created_lag_sec,
  p.p50_created_lag_sec,
  p.p95_created_lag_sec,
  b.avg_attempts,
  b.max_attempts,
  b.due_now
FROM base b
LEFT JOIN pcts p ON p.event_type = b.event_type;
'@
    }

    event_outbox_latency = @{
      create = @'
-- Processing latency (created -> processed) by type
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_outbox_latency AS
WITH latencies AS (
  SELECT
    event_type,
    TIMESTAMPDIFF(SECOND, created_at, processed_at) AS latency_sec
  FROM event_outbox
  WHERE processed_at IS NOT NULL
),
ranked AS (
  SELECT
    event_type,
    latency_sec,
    ROW_NUMBER() OVER (PARTITION BY event_type ORDER BY latency_sec) AS rn,
    COUNT(*) OVER (PARTITION BY event_type) AS cnt
  FROM latencies
)
SELECT
  event_type,
  COUNT(*) AS processed,
  AVG(latency_sec) AS avg_latency_sec,
  MAX(latency_sec) AS max_latency_sec,
  MAX(CASE WHEN rn = CEIL(0.50 * cnt) THEN latency_sec END) AS p50_latency_sec,
  MAX(CASE WHEN rn = CEIL(0.95 * cnt) THEN latency_sec END) AS p95_latency_sec
FROM ranked
GROUP BY event_type;
'@
    }

    event_outbox_throughput_hourly = @{
      create = @'
-- Hourly throughput for outbox/inbox
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_event_throughput_hourly AS
SELECT
  hour_ts,
  SUM(outbox_cnt) AS outbox_cnt,
  SUM(inbox_cnt)  AS inbox_cnt
FROM (
  SELECT
    DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00') AS hour_ts,
    COUNT(*) AS outbox_cnt,
    0 AS inbox_cnt
  FROM event_outbox
  GROUP BY hour_ts
  UNION ALL
  SELECT
    DATE_FORMAT(received_at, '%Y-%m-%d %H:00:00') AS hour_ts,
    0 AS outbox_cnt,
    COUNT(*) AS inbox_cnt
  FROM event_inbox
  GROUP BY hour_ts
) t
GROUP BY hour_ts
ORDER BY hour_ts DESC;
'@
    }

    notifications_queue_metrics = @{
      create = @'
-- Queue metrics for [notifications]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_notifications_queue_metrics AS
WITH base AS (
  SELECT
    channel,
    status,
    COUNT(*) AS total,
    SUM(CASE WHEN status IN ('pending','processing') AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
             THEN 1 ELSE 0 END) AS due_now
  FROM notifications
  GROUP BY channel, status
),
ranked AS (
  SELECT
    channel,
    status,
    TIMESTAMPDIFF(SECOND, COALESCE(last_attempt_at, created_at), NOW()) AS age_sec,
    ROW_NUMBER() OVER (PARTITION BY channel, status ORDER BY TIMESTAMPDIFF(SECOND, COALESCE(last_attempt_at, created_at), NOW())) AS rn,
    COUNT(*) OVER (PARTITION BY channel, status) AS cnt
  FROM notifications
)
SELECT
  b.channel,
  b.status,
  b.total,
  b.due_now,
  MAX(CASE WHEN r.rn = CEIL(0.95 * r.cnt) THEN r.age_sec END) AS p95_age_sec
FROM base b
LEFT JOIN ranked r
  ON r.channel = b.channel AND r.status = b.status
GROUP BY b.channel, b.status, b.total, b.due_now;
'@
    }

    webhook_outbox_metrics = @{
      create = @'
-- Metrics for [webhook_outbox]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_webhook_outbox_metrics AS
SELECT
  status,
  COUNT(*) AS total,
  SUM(CASE WHEN status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= NOW()) THEN 1 ELSE 0 END) AS due_now
FROM webhook_outbox
GROUP BY status;
'@
    }

    system_jobs_metrics = @{
      create = @'
-- Metrics for [system_jobs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_system_jobs_metrics AS
SELECT
  job_type,
  status,
  COUNT(*) AS total,
  SUM(CASE WHEN status = 'pending' AND (scheduled_at IS NULL OR scheduled_at <= NOW()) THEN 1 ELSE 0 END) AS due_now,
  SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) AS processing,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
FROM system_jobs
GROUP BY job_type, status
ORDER BY job_type, status;
'@
    }

    event_outbox_backlog_by_node = @{
      create = @'
-- Pending outbox backlog per producer node/channel
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_backlog_by_node AS
SELECT
  COALESCE(producer_node, '(unknown)') AS producer_node,
  event_type,
  SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)  AS failed,
  COUNT(*) AS total
FROM event_outbox
GROUP BY COALESCE(producer_node, '(unknown)'), event_type
ORDER BY pending DESC, failed DESC;
'@
    }

    sync_batches_progress = @{
      create = @'
-- Sync batch progress and success rate
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_batch_progress AS
SELECT
  b.id,
  b.channel,
  b.status,
  b.items_total,
  b.items_ok,
  b.items_failed,
  ROUND(100.0 * b.items_ok / NULLIF(b.items_total, 0), 2) AS success_pct,
  b.created_at,
  b.started_at,
  b.finished_at
FROM sync_batches b
ORDER BY b.created_at DESC;
'@
    }

    sync_errors_failures_recent = @{
      create = @'
-- Recent sync failures (24h)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_failures_recent AS
SELECT
  e.id,
  e.source,
  e.event_key,
  e.peer_id,
  e.error,
  e.created_at
FROM sync_errors e
WHERE e.created_at > NOW() - INTERVAL 24 HOUR
ORDER BY e.created_at DESC;
'@
    }

    audit_chain_gaps = @{
      create = @'
-- Audit rows missing chain entries
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_audit_chain_gaps AS
SELECT
  al.id AS audit_id,
  al.changed_at,
  al.table_name,
  al.record_id
FROM audit_log al
LEFT JOIN audit_chain ac ON ac.audit_id = al.id
WHERE ac.audit_id IS NULL
ORDER BY al.changed_at DESC;
'@
    }

    audit_log_activity_daily = @{
      create = @'
-- Daily audit activity split by change type
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_audit_activity_daily AS
SELECT
  DATE(changed_at) AS day,
  COUNT(*) AS total,
  SUM(CASE WHEN change_type = 'INSERT' THEN 1 ELSE 0 END) AS inserts,
  SUM(CASE WHEN change_type = 'UPDATE' THEN 1 ELSE 0 END) AS updates,
  SUM(CASE WHEN change_type = 'DELETE' THEN 1 ELSE 0 END) AS deletes
FROM audit_log
GROUP BY day
ORDER BY day DESC;
'@
    }

    kms_health_checks_latest = @{
      create = @'
-- Latest health sample per provider/key
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_health_latest AS
WITH ranked AS (
  SELECT
    id,
    provider_id,
    kms_key_id,
    status,
    latency_ms,
    error,
    checked_at,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(kms_key_id, -1), COALESCE(provider_id, -1)
      ORDER BY checked_at DESC
    ) AS rn
  FROM kms_health_checks
)
SELECT
  id,
  provider_id,
  kms_key_id,
  status,
  latency_ms,
  error,
  checked_at
FROM ranked
WHERE rn = 1
ORDER BY COALESCE(kms_key_id, -1), COALESCE(provider_id, -1);
'@
    }

    kms_keys_status_by_provider = @{
      create = @'
-- KMS keys status per provider
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_keys_status_by_provider AS
SELECT
  p.provider,
  p.name AS provider_name,
  COUNT(k.id) AS total,
  SUM(CASE WHEN k.status = 'active'   THEN 1 ELSE 0 END) AS active,
  SUM(CASE WHEN k.status = 'retired'  THEN 1 ELSE 0 END) AS retired,
  SUM(CASE WHEN k.status = 'disabled' THEN 1 ELSE 0 END) AS disabled
FROM kms_keys k
JOIN kms_providers p ON p.id = k.provider_id
GROUP BY p.provider, p.name
ORDER BY p.provider, p.name;
'@
    }

    kms_routing_policies = @{
      create = @'
-- Contract view for [kms_routing_policies]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_routing_policies AS
SELECT
  id,
  name,
  priority,
  strategy,
  `match`,
  providers,
  active,
  created_at
FROM kms_routing_policies;
'@
    }

    kms_routing_policies_matrix = @{
      create = @'
-- Active KMS routing policies (ordered by priority)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_kms_routing_matrix AS
SELECT
  name,
  priority,
  strategy,
  `match`,
  providers,
  active,
  created_at
FROM kms_routing_policies
WHERE active
ORDER BY priority DESC, name;
'@
    }

    merkle_anchors = @{
      create = @'
-- Contract view for [merkle_anchors]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_merkle_anchors AS
SELECT
  id,
  merkle_root_id,
  anchor_type,
  anchor_ref,
  anchored_at,
  meta
FROM merkle_anchors;
'@
    }

    merkle_roots = @{
      create = @'
-- Contract view for [merkle_roots]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_merkle_roots AS
SELECT
  id,
  subject_table,
  period_start,
  period_end,
  root_hash,
  UPPER(HEX(root_hash)) AS root_hash_hex,
  proof_uri,
  status,
  created_at
FROM merkle_roots;
'@
    }

    privacy_requests = @{
      create = @'
-- Contract view for [privacy_requests]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_privacy_requests AS
SELECT
  id,
  user_id,
  `type`,
  status,
  requested_at,
  processed_at,
  meta
FROM privacy_requests;
'@
    }

    migration_events = @{
      create = @'
-- Contract view for [migration_events]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_migration_events AS
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
'@
    }

    peer_nodes = @{
      create = @'
-- Contract view for [peer_nodes]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_peer_nodes AS
SELECT
  id,
  name,
  `type`,
  location,
  status,
  last_seen,
  meta,
  created_at
FROM peer_nodes;
'@
    }

    rate_limit_counters = @{
      create = @'
-- Contract view for [rate_limit_counters]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rate_limit_counters AS
SELECT
  id,
  subject_type,
  subject_id,
  name,
  window_start,
  window_size_sec,
  `count`,
  updated_at
FROM rate_limit_counters;
'@
    }

    rate_limits = @{
      create = @'
-- Contract view for [rate_limits]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rate_limits AS
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
'@
    }

    rbac_repositories = @{
      create = @'
-- Contract view for [rbac_repositories]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_repositories AS
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
'@
    }

    rbac_repo_snapshots = @{
      create = @'
-- Contract view for [rbac_repo_snapshots]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_repo_snapshots AS
SELECT
  id,
  repo_id,
  commit_id,
  taken_at,
  metadata
FROM rbac_repo_snapshots;
'@
    }

    rbac_sync_cursors = @{
      create = @'
-- Contract view for [rbac_sync_cursors]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_rbac_sync_cursors AS
SELECT
  repo_id,
  peer,
  last_commit,
  last_synced_at
FROM rbac_sync_cursors;
'@
    }

    replication_lag_samples = @{
      create = @'
-- Contract view for [replication_lag_samples]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_replication_lag_samples AS
SELECT
  id,
  peer_id,
  metric,
  value,
  captured_at
FROM replication_lag_samples;
'@
    }

    retention_enforcement_jobs = @{
      create = @'
-- Contract view for [retention_enforcement_jobs]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_retention_enforcement_jobs AS
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
'@
    }

    schema_registry = @{
      create = @'
-- Contract view for [schema_registry]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_schema_registry AS
SELECT
  id,
  system_name,
  component,
  version,
  checksum,
  applied_at,
  meta
FROM schema_registry;
'@
    }

    slo_windows = @{
      create = @'
-- Contract view for [slo_windows]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_slo_windows AS
SELECT
  id,
  name,
  objective,
  target_pct,
  window_interval,
  created_at
FROM slo_windows;
'@
    }

    slo_status = @{
      create = @'
-- Contract view for [slo_status]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_slo_status AS
SELECT
  id,
  window_id,
  computed_at,
  sli_value,
  good_events,
  total_events,
  status
FROM slo_status;
'@
    }

    sync_batches = @{
      create = @'
-- Contract view for [sync_batches]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_batches AS
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
'@
    }

    sync_batch_items = @{
      create = @'
-- Contract view for [sync_batch_items]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_batch_items AS
SELECT
  id,
  batch_id,
  event_key,
  status,
  error,
  created_at
FROM sync_batch_items;
'@
    }

    sync_errors = @{
      create = @'
-- Contract view for [sync_errors]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sync_errors AS
SELECT
  id,
  source,
  event_key,
  peer_id,
  error,
  created_at
FROM sync_errors;
'@
    }

    tenant_domains = @{
      create = @'
-- Contract view for [tenant_domains]
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_tenant_domains AS
SELECT
  id,
  tenant_id,
  domain,
  is_primary,
  created_at
FROM tenant_domains;
'@
    }

    login_attempts_hotspots_ip = @{
      create = @'
-- Security: IPs with failed logins (last 24h)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_login_hotspots_ip AS
SELECT
  ip_hash,
  UPPER(HEX(ip_hash)) AS ip_hash_hex,
  SUM(CASE WHEN attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END)                             AS total_24h,
  SUM(CASE WHEN success = 0 AND attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END)             AS failed_24h,
  MAX(attempted_at) AS last_attempt_at
FROM login_attempts
GROUP BY ip_hash
HAVING SUM(CASE WHEN success = 0 AND attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END) > 0
ORDER BY failed_24h DESC, last_attempt_at DESC;
'@
    }

    login_attempts_hotspots_user = @{
      create = @'
-- Security: users with failed logins (last 24h)
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_login_hotspots_user AS
SELECT
  user_id,
  SUM(CASE WHEN attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END)                         AS total_24h,
  SUM(CASE WHEN success = 0 AND attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END)         AS failed_24h,
  MAX(attempted_at) AS last_attempt_at
FROM login_attempts
WHERE user_id IS NOT NULL
GROUP BY user_id
HAVING SUM(CASE WHEN success = 0 AND attempted_at > NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END) > 0
ORDER BY failed_24h DESC, last_attempt_at DESC;
'@
    }

    merkle_roots_latest = @{
      create = @'
-- Latest Merkle roots per table
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_merkle_latest AS
WITH ranked AS (
  SELECT
    subject_table,
    period_start,
    period_end,
    leaf_count,
    root_hash,
    created_at,
    ROW_NUMBER() OVER (PARTITION BY subject_table ORDER BY created_at DESC) AS rn
  FROM merkle_roots
)
SELECT
  subject_table,
  period_start,
  period_end,
  leaf_count,
  UPPER(HEX(root_hash)) AS root_hash_hex,
  created_at
FROM ranked
WHERE rn = 1
ORDER BY subject_table;
'@
    }

    orders_funnel = @{
      create = @'
-- Global funnel of orders
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_orders_funnel AS
SELECT
  COUNT(*) AS orders_total,
  SUM(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending,
  SUM(CASE WHEN status = 'paid'      THEN 1 ELSE 0 END) AS paid,
  SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
  SUM(CASE WHEN status = 'failed'    THEN 1 ELSE 0 END) AS failed,
  SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
  SUM(CASE WHEN status = 'refunded'  THEN 1 ELSE 0 END) AS refunded,
  ROUND(
    100.0 * SUM(CASE WHEN status IN ('paid','completed') THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
    2
  ) AS payment_conversion_pct
FROM orders;
'@
    }

    peer_nodes_health = @{
      create = @'
-- Peer health with last lag samples
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_peer_health AS
WITH ranked AS (
  SELECT
    peer_id,
    metric,
    value,
    captured_at,
    ROW_NUMBER() OVER (PARTITION BY peer_id, metric ORDER BY captured_at DESC) AS rn
  FROM replication_lag_samples
)
SELECT
  p.id        AS peer_id,
  p.name,
  p.type,
  p.location,
  p.status,
  p.last_seen,
  COALESCE(MAX(CASE WHEN r.metric = 'apply_lag_ms' THEN r.value END), 0)    AS apply_lag_ms,
  COALESCE(MAX(CASE WHEN r.metric = 'transport_lag_ms' THEN r.value END), 0) AS transport_lag_ms,
  MAX(r.captured_at) AS lag_sampled_at
FROM peer_nodes p
LEFT JOIN ranked r ON r.peer_id = p.id AND r.rn = 1
GROUP BY p.id, p.name, p.type, p.location, p.status, p.last_seen;
'@
    }

    refunds_by_day_and_gateway = @{
      create = @'
-- Refunds aggregated by day and gateway
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_refunds_by_day_and_gateway AS
SELECT
  DATE(r.created_at) AS day,
  p.gateway,
  SUM(r.amount) AS refunds_total,
  COUNT(*)      AS refunds_count
FROM refunds r
JOIN payments p ON p.id = r.payment_id
GROUP BY DATE(r.created_at), p.gateway
ORDER BY day DESC, gateway;
'@
    }

    refunds_daily = @{
      create = @'
-- Daily refunds amount
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_refunds_daily AS
SELECT
  DATE(r.created_at) AS day,
  SUM(r.amount) AS refunds_total,
  COUNT(*)      AS refunds_count
FROM refunds r
GROUP BY DATE(r.created_at)
ORDER BY day DESC;
'@
    }

    orders_revenue_daily = @{
      create = @'
-- Daily revenue (orders) and counts; refunds reported separately
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_revenue_daily AS
SELECT
  DATE(created_at) AS day,
  SUM(CASE WHEN status IN ('paid','completed') THEN 1 ELSE 0 END) AS paid_orders,
  SUM(CASE WHEN status IN ('paid','completed') THEN total ELSE 0 END) AS revenue_gross,
  SUM(CASE WHEN status IN ('failed','cancelled') THEN 1 ELSE 0 END) AS lost_orders,
  SUM(CASE WHEN status IN ('failed','cancelled') THEN total ELSE 0 END) AS lost_total
FROM orders
GROUP BY DATE(created_at)
ORDER BY day DESC;
'@
    }

    replication_lag_samples_latest = @{
      create = @'
-- Latest replication lag samples per peer
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_replication_lag_latest AS
SELECT
  ph.peer_id,
  ph.name,
  ph.type,
  ph.apply_lag_ms,
  ph.transport_lag_ms,
  ph.lag_sampled_at
FROM vw_peer_health ph;
'@
    }

    schema_registry_versions_latest = @{
      create = @'
-- Latest version per system/component
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_schema_versions_latest AS
WITH ranked AS (
  SELECT
    system_name,
    component,
    version,
    checksum,
    applied_at,
    meta,
    ROW_NUMBER() OVER (PARTITION BY system_name, component ORDER BY applied_at DESC) AS rn
  FROM schema_registry
)
SELECT
  system_name,
  component,
  version,
  checksum,
  applied_at,
  meta
FROM ranked
WHERE rn = 1
ORDER BY system_name, component;
'@
    }

    sessions_active_by_user = @{
      create = @'
-- Active sessions per user
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_sessions_active_by_user AS
SELECT
  user_id,
  COUNT(*) AS active_sessions,
  MIN(created_at) AS first_created_at,
  MAX(last_seen_at) AS last_seen_at
FROM sessions
WHERE revoked = 0 AND (expires_at IS NULL OR expires_at > NOW())
GROUP BY user_id
ORDER BY active_sessions DESC;
'@
    }

    slo_windows_rollup = @{
      create = @'
-- SLO last computed status
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_slo_rollup AS
WITH ranked AS (
  SELECT
    w.id AS window_id,
    w.name,
    w.objective,
    w.target_pct,
    w.window_interval,
    s.computed_at,
    s.sli_value,
    s.good_events,
    s.total_events,
    s.status,
    ROW_NUMBER() OVER (PARTITION BY w.id ORDER BY s.computed_at DESC) AS rn
  FROM slo_windows w
  LEFT JOIN slo_status s ON s.window_id = w.id
)
SELECT
  window_id,
  name,
  objective,
  target_pct,
  window_interval,
  computed_at,
  sli_value,
  good_events,
  total_events,
  status
FROM ranked
WHERE rn = 1;
'@
    }

    system_errors_daily = @{
      create = @'
-- System errors per day and level
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_system_errors_daily AS
SELECT
  DATE(created_at) AS day,
  level,
  COUNT(*) AS count
FROM system_errors
GROUP BY DATE(created_at), level
ORDER BY day DESC, level;
'@
    }

    system_errors_top_fingerprints = @{
      create = @'
-- Top fingerprints by total occurrences
CREATE OR REPLACE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW vw_system_errors_top_fingerprints AS
SELECT
  fingerprint,
  MAX(message) AS sample_message,
  SUM(occurrences) AS occurrences,
  MIN(created_at) AS first_seen,
  MAX(last_seen)  AS last_seen,
  MAX(CASE WHEN resolved THEN 1 ELSE 0 END) AS any_resolved,
  COUNT(*) AS rows_count
FROM system_errors
GROUP BY fingerprint
ORDER BY occurrences DESC, last_seen DESC;
'@
    }

  } # /Views
}
