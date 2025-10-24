@{
  FormatVersion = '1.0'

  Views = @{

    users = @{
      create = @'
-- Contract view for [users]
-- Hides password_* columns. Keeps operational flags and audit fields.
CREATE OR REPLACE VIEW vw_users AS
SELECT
  id,
  email_hash,
  email_hash_key_version,
  is_active,
  is_locked,
  failed_logins,
  must_change_password,
  last_login_at,
  last_login_ip_hash,
  last_login_ip_key_version,
  created_at,
  updated_at,
  deleted_at,
  actor_role
FROM users;
'@
    }

    login_attempts = @{
      create = @'
-- Contract view for [login_attempts]
-- Exposes hashed identifiers only; safe for security dashboards.
CREATE OR REPLACE VIEW vw_login_attempts AS
SELECT
  id,
  ip_hash,
  attempted_at,
  success,
  user_id,
  username_hash,
  auth_event_id
FROM login_attempts;
'@
    }

    user_profiles = @{
      create = @'
-- Contract view for [user_profiles]
-- Omits large encrypted profile blob by default; add it back only if needed.
CREATE OR REPLACE VIEW vw_user_profiles AS
SELECT
  user_id,
  key_version,
  encryption_meta,
  updated_at
FROM user_profiles;
'@
    }

    user_identities = @{
      create = @'
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
'@
    }

    permissions = @{
      create = @'
-- Contract view for [permissions]
CREATE OR REPLACE VIEW vw_permissions AS
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
-- Hides secret and recovery_codes_enc; keeps method and state.
CREATE OR REPLACE VIEW vw_two_factor AS
SELECT
  user_id,
  method,
  hotp_counter,
  enabled,
  created_at,
  last_used_at
FROM two_factor;
'@
    }

    session_audit = @{
      create = @'
-- Contract view for [session_audit]
-- Session token is typically hashed; included for correlation. Adjust if sensitive.
CREATE OR REPLACE VIEW vw_session_audit AS
SELECT
  id,
  session_token,
  session_token_key_version,
  csrf_key_version,
  session_id,
  event,
  user_id,
  ip_hash,
  ip_hash_key_version,
  user_agent,
  meta_json,
  outcome,
  created_at
FROM session_audit;
'@
    }

    sessions = @{
      create = @'
-- Contract view for [sessions]
-- Hides token_hash and session_blob.
CREATE OR REPLACE VIEW vw_sessions AS
SELECT
  id,
  token_hash_key_version,
  token_fingerprint,
  token_issued_at,
  user_id,
  created_at,
  last_seen_at,
  expires_at,
  failed_decrypt_count,
  last_failed_decrypt_at,
  revoked,
  ip_hash,
  ip_hash_key_version,
  user_agent
FROM sessions;
'@
    }

    auth_events = @{
      create = @'
-- Contract view for [auth_events]
CREATE OR REPLACE VIEW vw_auth_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
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
CREATE OR REPLACE VIEW vw_register_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
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
CREATE OR REPLACE VIEW vw_verify_events AS
SELECT
  id,
  user_id,
  type,
  ip_hash,
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
-- Hides stack_trace and token; safe for dashboards and triage.
CREATE OR REPLACE VIEW vw_system_errors AS
SELECT
  id,
  level,
  message,
  exception_class,
  file,
  line,
  fingerprint,
  occurrences,
  user_id,
  ip_hash,
  ip_hash_key_version,
  ip_text,
  ip_bin,
  user_agent,
  url,
  method,
  http_status,
  resolved,
  resolved_by,
  resolved_at,
  created_at,
  last_seen,
  context
FROM system_errors;
'@
    }

    user_consents = @{
      create = @'
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
'@
    }

    authors = @{
      create = @'
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
  deleted_at
FROM authors;
'@
    }

    categories = @{
      create = @'
-- Contract view for [categories]
CREATE OR REPLACE VIEW vw_categories AS
SELECT
  id,
  name,
  slug,
  parent_id,
  created_at,
  updated_at,
  deleted_at
FROM categories;
'@
    }

    books = @{
      create = @'
-- Contract view for [books]
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
  created_at,
  updated_at,
  deleted_at
FROM books;
'@
    }

    reviews = @{
      create = @'
-- Contract view for [reviews]
CREATE OR REPLACE VIEW vw_reviews AS
SELECT
  id,
  book_id,
  user_id,
  rating,
  review_text,
  created_at,
  updated_at
FROM reviews;
'@
    }

    crypto_keys = @{
      create = @'
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
  notes
FROM crypto_keys;
'@
    }

    key_events = @{
      create = @'
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
'@
    }

    key_rotation_jobs = @{
      create = @'
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
'@
    }

    key_usage = @{
      create = @'
-- Contract view for [key_usage]
CREATE OR REPLACE VIEW vw_key_usage AS
SELECT
  id,
  key_id,
  date,
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
-- Hides token_hash.
CREATE OR REPLACE VIEW vw_jwt_tokens AS
SELECT
  id,
  jti,
  user_id,
  token_hash_algo,
  token_hash_key_version,
  type,
  scopes,
  created_at,
  expires_at,
  last_used_at,
  ip_hash,
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
  created_at
FROM book_assets;
'@
    }

    book_categories = @{
      create = @'
-- Contract view for [book_categories]
CREATE OR REPLACE VIEW vw_book_categories AS
SELECT
  book_id,
  category_id
FROM book_categories;
'@
    }

    inventory_reservations = @{
      create = @'
-- Contract view for [inventory_reservations]
CREATE OR REPLACE VIEW vw_inventory_reservations AS
SELECT
  id,
  order_id,
  book_id,
  quantity,
  reserved_until,
  status,
  created_at
FROM inventory_reservations;
'@
    }

    carts = @{
      create = @'
-- Contract view for [carts]
CREATE OR REPLACE VIEW vw_carts AS
SELECT
  id,
  user_id,
  created_at,
  updated_at
FROM carts;
'@
    }

    cart_items = @{
      create = @'
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
'@
    }

    orders = @{
      create = @'
-- Contract view for [orders]
-- Hides encrypted_customer_blob; keeps metadata and totals.
CREATE OR REPLACE VIEW vw_orders AS
SELECT
  id,
  uuid,
  uuid_bin,
  public_order_no,
  user_id,
  status,
  encrypted_customer_blob_key_version,
  encryption_meta,
  currency,
  metadata,
  subtotal,
  discount_total,
  tax_total,
  total,
  payment_method,
  created_at,
  updated_at
FROM orders;
'@
    }

    order_items = @{
      create = @'
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
'@
    }

    order_item_downloads = @{
      create = @'
-- Contract view for [order_item_downloads]
-- Hides download_token_hash.
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
  expires_at,
  last_used_at,
  ip_hash,
  ip_hash_key_version
FROM order_item_downloads;
'@
    }

    invoices = @{
      create = @'
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
'@
    }

    invoice_items = @{
      create = @'
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
'@
    }

    payments = @{
      create = @'
-- Contract view for [payments]
-- Includes "details" JSON; mask in your app if it can contain sensitive provider payloads.
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
  updated_at
FROM payments;
'@
    }

    payment_logs = @{
      create = @'
-- Contract view for [payment_logs]
CREATE OR REPLACE VIEW vw_payment_logs AS
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
-- Hides raw payload JSON; exposes hash and identifiers.
CREATE OR REPLACE VIEW vw_payment_webhooks AS
SELECT
  id,
  payment_id,
  gateway_event_id,
  payload_hash,
  from_cache,
  created_at
FROM payment_webhooks;
'@
    }

    idempotency_keys = @{
      create = @'
-- Contract view for [idempotency_keys]
-- Hides gateway_payload body by default.
CREATE OR REPLACE VIEW vw_idempotency_keys AS
SELECT
  key_hash,
  payment_id,
  order_id,
  redirect_url,
  created_at,
  ttl_seconds
FROM idempotency_keys;
'@
    }

    refunds = @{
      create = @'
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
'@
    }

    coupons = @{
      create = @'
-- Contract view for [coupons]
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
  created_at,
  updated_at
FROM coupons;
'@
    }

    coupon_redemptions = @{
      create = @'
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
'@
    }

    countries = @{
      create = @'
-- Contract view for [countries]
CREATE OR REPLACE VIEW vw_countries AS
SELECT
  iso2,
  name
FROM countries;
'@
    }

    tax_rates = @{
      create = @'
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
'@
    }

    vat_validations = @{
      create = @'
-- Contract view for [vat_validations]
-- Hides raw provider response JSON.
CREATE OR REPLACE VIEW vw_vat_validations AS
SELECT
  id,
  vat_id,
  country_iso2,
  valid,
  checked_at
FROM vat_validations;
'@
    }

    app_settings = @{
      create = @'
-- Contract view for [app_settings]
-- Masks setting_value for secret entries.
CREATE OR REPLACE VIEW vw_app_settings AS
SELECT
  setting_key,
  CASE WHEN "type" = 'secret' THEN NULL ELSE setting_value END AS setting_value,
  "type",
  section,
  description,
  is_protected,
  updated_at,
  updated_by
FROM app_settings;
'@
    }

    audit_log = @{
      create = @'
-- Contract view for [audit_log]
-- Omits old_value/new_value JSON to reduce payload and potential leakage.
CREATE OR REPLACE VIEW vw_audit_log AS
SELECT
  id,
  table_name,
  record_id,
  changed_by,
  change_type,
  changed_at,
  ip_bin,
  user_agent,
  request_id
FROM audit_log;
'@
    }

    webhook_outbox = @{
      create = @'
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
  updated_at
FROM webhook_outbox;
'@
    }

    payment_gateway_notifications = @{
      create = @'
-- Contract view for [payment_gateway_notifications]
CREATE OR REPLACE VIEW vw_payment_gateway_notifications AS
SELECT
  id,
  transaction_id,
  received_at,
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
CREATE OR REPLACE VIEW vw_email_verifications AS
SELECT
  id,
  user_id,
  selector,
  key_version,
  expires_at,
  created_at,
  used_at
FROM email_verifications;
'@
    }

    notifications = @{
      create = @'
-- Contract view for [notifications]
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
  locked_by,
  priority,
  created_at,
  updated_at
FROM notifications;
'@
    }

    newsletter_subscribers = @{
      create = @'
-- Contract view for [newsletter_subscribers]
-- Hides email_enc; keeps hash and status fields.
CREATE OR REPLACE VIEW vw_newsletter_subscribers AS
SELECT
  id,
  user_id,
  email_hash,
  email_hash_key_version,
  confirm_selector,
  confirm_validator_hash,
  confirm_key_version,
  confirm_expires,
  confirmed_at,
  unsubscribe_token_hash,
  unsubscribe_token_key_version,
  unsubscribed_at,
  origin,
  ip_hash,
  ip_hash_key_version,
  meta,
  created_at,
  updated_at
FROM newsletter_subscribers;
'@
    }

    system_jobs = @{
      create = @'
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
  updated_at
FROM system_jobs;
'@
    }

    worker_locks = @{
      create = @'
-- Contract view for [worker_locks]
CREATE OR REPLACE VIEW vw_worker_locks AS
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
CREATE OR REPLACE VIEW vw_encrypted_fields AS
SELECT
  id,
  entity_table,
  entity_pk,
  field_name,
  meta,
  created_at,
  updated_at
FROM encrypted_fields;
'@
    }

    kms_providers = @{
      create = @'
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
'@
    }

    kms_keys = @{
      create = @'
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
'@
    }

    encryption_policies = @{
      create = @'
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
'@
    }

    policy_kms_keys = @{
      create = @'
-- Contract view for [policy_kms_keys]
CREATE OR REPLACE VIEW vw_policy_kms_keys AS
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
'@
    }

  } # /Views
}
