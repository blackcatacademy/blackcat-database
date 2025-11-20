-- === api_keys ===
CREATE TABLE IF NOT EXISTS api_keys (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  name VARCHAR(120) NOT NULL,
  name_ci VARCHAR(120) GENERATED ALWAYS AS (LOWER(name)) STORED,
  token_hash BINARY(32) NOT NULL,
  token_hash_key_version VARCHAR(64) NOT NULL,
  scopes JSON NOT NULL,
  status ENUM('active','revoked','disabled') NOT NULL DEFAULT 'active',
  last_used_at DATETIME(6) NULL,
  expires_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NULL,
  CONSTRAINT uq_api_keys_token UNIQUE (token_hash),
  INDEX idx_api_keys_tenant (tenant_id),
  INDEX idx_api_keys_user   (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === app_settings ===
CREATE TABLE IF NOT EXISTS app_settings (
  setting_key VARCHAR(100) PRIMARY KEY,
  setting_value TEXT NULL,
  `type` VARCHAR(20) NOT NULL,
  section VARCHAR(100) NULL,
  description TEXT NULL,
  is_protected BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  updated_by BIGINT UNSIGNED NULL,
  CONSTRAINT chk_app_settings_type CHECK (`type` IN ('string','int','bool','json','secret'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === audit_chain ===
CREATE TABLE IF NOT EXISTS audit_chain (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  audit_id BIGINT UNSIGNED NOT NULL,
  chain_name VARCHAR(100) NOT NULL DEFAULT 'default',
  prev_hash VARBINARY(255) NULL,
  hash VARBINARY(255) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_audit_chain (audit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === audit_log ===
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  table_name VARCHAR(100) NOT NULL,
  record_id BIGINT UNSIGNED NOT NULL,
  changed_by BIGINT UNSIGNED NULL,
  change_type ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  old_value JSON NULL,
  new_value JSON NULL,
  changed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  ip_bin VARBINARY(16) NULL,
  user_agent VARCHAR(1024) NULL,
  request_id VARCHAR(100) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === auth_events ===
CREATE TABLE IF NOT EXISTS auth_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  `type` ENUM('login_success','login_failure','logout','password_reset','lockout') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  meta_email VARCHAR(255) GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(meta, '$.email'))) STORED,
  INDEX idx_auth_meta_email (meta_email),
  INDEX idx_auth_user (user_id),
  INDEX idx_auth_time (occurred_at),
  INDEX idx_auth_type_time (`type`, occurred_at),
  INDEX idx_auth_ip_hash (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === authors ===
CREATE TABLE IF NOT EXISTS authors (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  slug_ci VARCHAR(255) GENERATED ALWAYS AS (LOWER(slug)) STORED,
  bio TEXT NULL,
  photo_url VARCHAR(255) NULL,
  story LONGTEXT NULL,
  books_count INT NOT NULL DEFAULT 0,
  ratings_count INT NOT NULL DEFAULT 0,
  rating_sum INT NOT NULL DEFAULT 0,
  avg_rating DECIMAL(3,2) NULL DEFAULT NULL,
  last_rating_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at DATETIME(6) NULL,
  is_live TINYINT(1) GENERATED ALWAYS AS (deleted_at IS NULL) STORED,
  INDEX idx_authors_avg_rating (avg_rating),
  INDEX idx_authors_books_count (books_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === book_assets ===
CREATE TABLE IF NOT EXISTS book_assets (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  asset_type ENUM('cover','pdf','epub','mobi','sample','extra') NOT NULL,
  filename VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  size_bytes BIGINT NOT NULL,
  storage_path TEXT NULL,
  content_hash VARCHAR(64) NULL,
  download_filename VARCHAR(255) NULL,
  is_encrypted BOOLEAN NOT NULL DEFAULT 0,
  encryption_algo VARCHAR(50) NULL,
  encryption_key_enc BLOB NULL,
  encryption_iv VARBINARY(32) NULL,
  encryption_tag VARBINARY(32) NULL,
  encryption_aad VARBINARY(255) NULL,
  encryption_meta JSON NULL,
  key_version VARCHAR(64) NULL,
  key_id BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_book_assets_book (book_id),
  INDEX idx_book_assets_type (asset_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === book_categories ===
CREATE TABLE IF NOT EXISTS book_categories (
  tenant_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (tenant_id, book_id, category_id),
  INDEX idx_book_categories_category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === books ===
CREATE TABLE IF NOT EXISTS books (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  slug_ci VARCHAR(255) GENERATED ALWAYS AS (LOWER(slug)) STORED,
  short_description VARCHAR(512) NULL,
  full_description LONGTEXT NULL,
  price DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  currency CHAR(3) NOT NULL DEFAULT 'EUR',
  author_id BIGINT UNSIGNED NOT NULL,
  main_category_id BIGINT UNSIGNED NOT NULL,
  isbn VARCHAR(32) NULL,
  language CHAR(5) NULL,
  pages INT UNSIGNED NULL,
  publisher VARCHAR(255) NULL,
  published_at DATE NULL,
  sku VARCHAR(64) NULL,
  is_active BOOLEAN NOT NULL DEFAULT 1,
  is_available BOOLEAN NOT NULL DEFAULT 1,
  stock_quantity INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at DATETIME(6) NULL,
  is_live TINYINT(1) GENERATED ALWAYS AS (deleted_at IS NULL) STORED,
  INDEX idx_books_author_id (author_id),
  INDEX idx_books_main_category_id (main_category_id),
  INDEX idx_books_sku (sku),
  CONSTRAINT chk_books_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === cart_items ===
CREATE TABLE IF NOT EXISTS cart_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT UNSIGNED NOT NULL,
  cart_id CHAR(36) NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  sku VARCHAR(64) NULL,
  variant JSON NULL,
  quantity INT UNSIGNED NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  price_snapshot DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  meta JSON NULL,
  PRIMARY KEY (id),
  INDEX idx_cart_items_cart_id (cart_id),
  CONSTRAINT chk_cart_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  CONSTRAINT chk_cart_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === carts ===
CREATE TABLE IF NOT EXISTS carts (
  id CHAR(36) PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  note VARCHAR(200) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === categories ===
CREATE TABLE IF NOT EXISTS categories (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  slug_ci VARCHAR(255) GENERATED ALWAYS AS (LOWER(slug)) STORED,
  parent_id BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at DATETIME(6) NULL,
  is_live TINYINT(1) GENERATED ALWAYS AS (deleted_at IS NULL) STORED,
  INDEX idx_categories_parent (parent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === countries ===
CREATE TABLE IF NOT EXISTS countries (
  iso2 CHAR(2) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  CONSTRAINT chk_countries_iso2 CHECK (iso2 REGEXP '^[A-Z]{2}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === coupon_redemptions ===
CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  coupon_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  redeemed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  amount_applied DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === coupons ===
CREATE TABLE IF NOT EXISTS coupons (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  code VARCHAR(100) NOT NULL,
  code_ci VARCHAR(100) GENERATED ALWAYS AS (LOWER(code)) STORED,
  `type` ENUM('percent','fixed') NOT NULL,
  value DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NULL,
  starts_at DATE NOT NULL,
  ends_at DATE NULL,
  max_redemptions INT NOT NULL DEFAULT 0,
  min_order_amount DECIMAL(12,2) NULL,
  applies_to JSON NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT chk_coupon_percent_fixed CHECK (
    (`type`='percent' AND value BETWEEN 0 AND 100 AND currency IS NULL)
    OR (`type`='fixed' AND value >= 0 AND (currency REGEXP '^[A-Z]{3}$')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === crypto_algorithms ===
CREATE TABLE IF NOT EXISTS crypto_algorithms (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  class ENUM('kem','sig','hash','symmetric') NOT NULL,
  name VARCHAR(120) NOT NULL,
  variant VARCHAR(80) NULL,
  variant_norm VARCHAR(80) GENERATED ALWAYS AS (IFNULL(variant,'')) STORED,
  nist_level SMALLINT UNSIGNED NULL,
  status ENUM('active','deprecated','experimental') NOT NULL DEFAULT 'active',
  params JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_crypto_algorithms (class, name, variant_norm),
  UNIQUE KEY uq_crypto_algorithms_raw (class, name, variant)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === crypto_keys ===
CREATE TABLE IF NOT EXISTS crypto_keys (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  basename VARCHAR(100) NOT NULL,
  version INT NOT NULL,
  filename VARCHAR(255) NULL,
  file_path VARCHAR(1024) NULL,
  fingerprint CHAR(64) NULL,
  key_meta JSON NULL,
  key_type ENUM('dek','kek','hmac','pepper') NULL,
  algorithm VARCHAR(64) NULL,
  length_bits SMALLINT NULL,
  origin ENUM('local','kms','imported') NULL,
  `usage` SET('encrypt','decrypt','sign','verify','wrap','unwrap') NULL,
  scope VARCHAR(100) NULL,
  status ENUM('active','retired','compromised','archived') NOT NULL DEFAULT 'active',
  is_backup_encrypted BOOLEAN NOT NULL DEFAULT 0,
  backup_blob LONGBLOB NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  activated_at DATETIME(6) NULL,
  retired_at DATETIME(6) NULL,
  replaced_by BIGINT UNSIGNED NULL,
  notes TEXT NULL,
  CONSTRAINT uq_keys_basename_version UNIQUE (basename, version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === crypto_standard_aliases ===
CREATE TABLE IF NOT EXISTS crypto_standard_aliases (
  alias VARCHAR(120) PRIMARY KEY,
  algo_id BIGINT UNSIGNED NOT NULL,
  notes TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === data_retention_policies ===
CREATE TABLE IF NOT EXISTS data_retention_policies (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NULL,
  action ENUM('delete','anonymize','hash','truncate') NOT NULL,
  keep_for VARCHAR(64) NOT NULL,   -- e.g. "90 days"
  active BOOLEAN NOT NULL DEFAULT TRUE,
  notes TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY ux_drp (entity_table, field_name, action, keep_for),
  INDEX idx_drp_entity (entity_table, field_name),
  INDEX idx_drp_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === deletion_jobs ===
CREATE TABLE IF NOT EXISTS deletion_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  reason TEXT NULL,
  hard_delete BOOLEAN NOT NULL DEFAULT FALSE,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  status ENUM('pending','running','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  error TEXT NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_deletion_jobs (entity_table, entity_pk),
  INDEX idx_dj_status_sched (status, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === device_fingerprints ===
CREATE TABLE IF NOT EXISTS device_fingerprints (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  fingerprint_hash BINARY(32) NOT NULL,
  attributes JSON NULL,
  risk_score TINYINT UNSIGNED NULL,
  first_seen DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_seen DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_ip_hash BINARY(32) NULL,
  last_ip_key_version VARCHAR(64) NULL,
  UNIQUE KEY uq_device_fp (fingerprint_hash),
  INDEX idx_df_user      (user_id),
  INDEX idx_df_last_seen (last_seen)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === email_verifications ===
CREATE TABLE IF NOT EXISTS email_verifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NULL,
  selector CHAR(12) NOT NULL,
  validator_hash BINARY(32) NULL,
  key_version VARCHAR(64) NULL,
  expires_at DATETIME(6) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  used_at DATETIME(6) NULL,
  UNIQUE KEY ux_ev_selector (selector),
  INDEX idx_ev_user (user_id),
  INDEX idx_ev_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === encrypted_fields ===
CREATE TABLE IF NOT EXISTS encrypted_fields (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NOT NULL,
  ciphertext LONGBLOB NOT NULL,
  meta JSON NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY ux_enc_entity_field (entity_table, entity_pk, field_name),
  INDEX idx_enc_entity (entity_table, entity_pk)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === encryption_bindings ===
CREATE TABLE IF NOT EXISTS encryption_bindings (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NULL,
  field_name_norm VARCHAR(64) GENERATED ALWAYS AS (IFNULL(field_name,'')) STORED,
  key_wrapper_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_enc_bind (entity_table, entity_pk, field_name_norm),
  UNIQUE KEY uq_enc_bind_raw (entity_table, entity_pk, field_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === encryption_events ===
CREATE TABLE IF NOT EXISTS encryption_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NOT NULL,
  op ENUM('encrypt','decrypt','rotate','rehash','unwrap','wrap') NOT NULL,
  policy_id BIGINT UNSIGNED NULL,
  local_key_version VARCHAR(64) NULL,
  layers JSON NULL,
  outcome ENUM('success','failure') NOT NULL,
  error_code VARCHAR(64) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_enc_events_entity (entity_table, entity_pk, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === encryption_policies ===
CREATE TABLE IF NOT EXISTS encryption_policies (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  policy_name VARCHAR(100) NOT NULL UNIQUE,
  mode ENUM('local','kms','multi-kms') NOT NULL,
  layer_selection ENUM('defined','round_robin','random','hash_mod') NOT NULL DEFAULT 'defined',
  min_layers TINYINT UNSIGNED NOT NULL DEFAULT 1,
  max_layers TINYINT UNSIGNED NOT NULL DEFAULT 3,
  aad_template JSON NULL,
  notes TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === encryption_policy_bindings ===
CREATE TABLE IF NOT EXISTS encryption_policy_bindings (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NOT NULL,
  policy_id BIGINT UNSIGNED NOT NULL,
  effective_from DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  notes TEXT NULL,
  UNIQUE KEY uq_enc_policy_bind (entity_table, field_name, effective_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === entity_external_ids ===
CREATE TABLE IF NOT EXISTS entity_external_ids (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  `source` VARCHAR(100) NOT NULL,
  external_id VARCHAR(200) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_entity_external_ids (entity_table, entity_pk, `source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === event_dlq ===
CREATE TABLE IF NOT EXISTS event_dlq (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `source` VARCHAR(100) NOT NULL,
  event_key CHAR(36) NULL,
  event JSON NOT NULL,
  error TEXT NOT NULL,
  retryable BOOLEAN NOT NULL DEFAULT 0,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  first_failed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_failed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === event_inbox ===
CREATE TABLE IF NOT EXISTS event_inbox (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `source` VARCHAR(100) NOT NULL,
  event_key CHAR(36) NOT NULL,
  payload JSON NOT NULL,
  status ENUM('pending','processed','failed') NOT NULL DEFAULT 'pending',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  last_error TEXT NULL,
  received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  processed_at DATETIME(6) NULL,
  UNIQUE KEY uq_event_inbox_key (`source`, event_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === event_outbox ===
CREATE TABLE IF NOT EXISTS event_outbox (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  event_key CHAR(36) NOT NULL,
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSON NOT NULL,
  status ENUM('pending','sent','failed') NOT NULL DEFAULT 'pending',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  next_attempt_at DATETIME(6) NULL,
  processed_at DATETIME(6) NULL,
  producer_node VARCHAR(100) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_event_outbox_key (event_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === field_hash_policies ===
CREATE TABLE IF NOT EXISTS field_hash_policies (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  entity_table VARCHAR(64) NOT NULL,
  field_name VARCHAR(64) NOT NULL,
  profile_id BIGINT UNSIGNED NOT NULL,
  effective_from DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  notes TEXT NULL,
  UNIQUE KEY uq_fhp (entity_table, field_name, effective_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === global_id_registry ===
CREATE TABLE IF NOT EXISTS global_id_registry (
  gid CHAR(26) PRIMARY KEY,              -- ULID
  guid CHAR(36) NULL,                    -- UUID (text)
  entity_table VARCHAR(64) NOT NULL,
  entity_pk VARCHAR(64) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_gid_entity (entity_table, entity_pk),
  INDEX idx_gid_guid  (guid),
  INDEX idx_gid_table (entity_table)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === hash_profiles ===
CREATE TABLE IF NOT EXISTS hash_profiles (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  algo_id BIGINT UNSIGNED NOT NULL,
  output_len SMALLINT UNSIGNED NULL,
  params JSON NULL,
  status ENUM('active','deprecated') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_hash_profiles_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === idempotency_keys ===
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key_hash CHAR(64) NOT NULL PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  payment_id BIGINT UNSIGNED NULL DEFAULT NULL,
  order_id BIGINT UNSIGNED NULL DEFAULT NULL,
  gateway_payload JSON NULL,
  redirect_url VARCHAR(1024) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  ttl_seconds INT NOT NULL DEFAULT 86400,
  INDEX idx_idemp_payment (payment_id),
  INDEX idx_idemp_order (order_id),
  INDEX idx_idemp_created_at (created_at),
  INDEX idx_idemp_tenant_payment (tenant_id, payment_id),
  INDEX idx_idemp_tenant_order (tenant_id, order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === inventory_reservations ===
CREATE TABLE IF NOT EXISTS inventory_reservations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  quantity INT UNSIGNED NOT NULL,
  reserved_until DATETIME(6) NOT NULL,
  status ENUM('pending','confirmed','expired','cancelled') NOT NULL DEFAULT 'pending',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  INDEX idx_res_book (book_id),
  INDEX idx_res_order (order_id),
  INDEX idx_res_status_until (status, reserved_until),
  CONSTRAINT chk_res_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === invoice_items ===
CREATE TABLE IF NOT EXISTS invoice_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  invoice_id BIGINT UNSIGNED NOT NULL,
  line_no INT NOT NULL,
  description TEXT NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  quantity INT UNSIGNED NOT NULL,
  tax_rate DECIMAL(5,2) NOT NULL,
  tax_amount DECIMAL(12,2) NOT NULL,
  line_total DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  UNIQUE KEY uq_invoice_line (invoice_id, line_no),
  INDEX idx_invoice_items_tenant_invoice (tenant_id, invoice_id),
  CONSTRAINT chk_invoice_items_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  CONSTRAINT chk_invoice_items_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === invoices ===
CREATE TABLE IF NOT EXISTS invoices (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NULL,
  invoice_number VARCHAR(100) NOT NULL,
  variable_symbol VARCHAR(50) NULL,
  issue_date DATE NOT NULL,
  due_date DATE NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  discount_total DECIMAL(12,2) NOT NULL,
  tax_total DECIMAL(12,2) NOT NULL,
  total DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  qr_data LONGTEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT chk_invoices_nonneg CHECK (subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT chk_invoices_total_eq CHECK (total = subtotal - discount_total + tax_total),
  CONSTRAINT chk_invoices_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  UNIQUE KEY ux_invoices_tenant_no (tenant_id, invoice_number),
  INDEX idx_invoices_tenant_order (tenant_id, order_id),
  UNIQUE KEY ux_invoices_tenant_id (tenant_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === jwt_tokens ===
CREATE TABLE IF NOT EXISTS jwt_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  jti CHAR(36) NOT NULL UNIQUE,
  user_id BIGINT UNSIGNED NULL,
  token_hash BINARY(32) NOT NULL,
  token_hash_algo VARCHAR(50) NULL,
  token_hash_key_version VARCHAR(64) NULL,
  `type` ENUM('refresh','api') NOT NULL DEFAULT 'refresh',
  scopes VARCHAR(255) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  expires_at DATETIME(6) NULL,
  last_used_at DATETIME(6) NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  replaced_by BIGINT UNSIGNED NULL,
  revoked BOOLEAN NOT NULL DEFAULT 0,
  meta JSON NULL,
  UNIQUE KEY uq_jwt_token_hash (token_hash),
  INDEX idx_jwt_user (user_id),
  INDEX idx_jwt_expires (expires_at),
  INDEX idx_jwt_revoked_user (revoked, user_id),
  INDEX idx_jwt_last_used (last_used_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === key_events ===
CREATE TABLE IF NOT EXISTS key_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  key_id BIGINT UNSIGNED NULL,
  basename VARCHAR(100) NULL,
  event_type ENUM('created','rotated','activated','retired','compromised','deleted','used_encrypt','used_decrypt','access_failed','backup','restore') NOT NULL,
  actor_id BIGINT UNSIGNED NULL,
  job_id BIGINT UNSIGNED NULL,
  note TEXT NULL,
  meta JSON NULL,
  `source` ENUM('cron','admin','api','manual') NOT NULL DEFAULT 'admin',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_key_events_key_created (key_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === key_rotation_jobs ===
CREATE TABLE IF NOT EXISTS key_rotation_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  basename VARCHAR(100) NOT NULL,
  target_version INT NULL,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  status ENUM('pending','running','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  attempts INT NOT NULL DEFAULT 0,
  executed_by BIGINT UNSIGNED NULL,
  result TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_key_rotation_jobs_basename_sched (basename, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === key_usage ===
CREATE TABLE IF NOT EXISTS key_usage (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  key_id BIGINT UNSIGNED NOT NULL,
  usage_date DATE NOT NULL,
  encrypt_count INT NOT NULL DEFAULT 0,
  decrypt_count INT NOT NULL DEFAULT 0,
  verify_count INT NOT NULL DEFAULT 0,
  last_used_at DATETIME(6) NULL,
  UNIQUE KEY uq_key_usage_key_date (key_id, usage_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === key_wrapper_layers ===
CREATE TABLE IF NOT EXISTS key_wrapper_layers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  key_wrapper_id BIGINT UNSIGNED NOT NULL,
  layer_no SMALLINT UNSIGNED NOT NULL,
  kms_key_id BIGINT UNSIGNED NULL,
  kem_algo_id BIGINT UNSIGNED NOT NULL,
  kem_ciphertext LONGBLOB NOT NULL,
  encap_pubkey LONGBLOB NULL,
  aad JSON NULL,
  meta JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_kwl (key_wrapper_id, layer_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === key_wrappers ===
CREATE TABLE IF NOT EXISTS key_wrappers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  wrapper_uuid CHAR(36) NOT NULL,
  kms1_key_id BIGINT UNSIGNED NOT NULL,
  kms2_key_id BIGINT UNSIGNED NOT NULL,
  dek_wrap1 LONGBLOB NOT NULL,
  dek_wrap2 LONGBLOB NOT NULL,
  crypto_suite JSON NULL,
  wrap_version INT NOT NULL DEFAULT 1,
  status ENUM('active','rotated','retired','invalid') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  rotated_at DATETIME(6) NULL,
  UNIQUE KEY uq_key_wrappers_uuid (wrapper_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === kms_health_checks ===
CREATE TABLE IF NOT EXISTS kms_health_checks (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id BIGINT UNSIGNED NULL,
  kms_key_id BIGINT UNSIGNED NULL,
  status ENUM('up','degraded','down') NOT NULL,
  latency_ms INT NULL,
  error TEXT NULL,
  checked_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === kms_keys ===
CREATE TABLE IF NOT EXISTS kms_keys (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id BIGINT UNSIGNED NOT NULL,
  external_key_ref VARCHAR(512) NOT NULL,
  purpose ENUM('wrap','encrypt','both') NOT NULL DEFAULT 'wrap',
  algorithm VARCHAR(64) NULL,
  status ENUM('active','retired','disabled') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === kms_providers ===
CREATE TABLE IF NOT EXISTS kms_providers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  provider ENUM('gcp','aws','azure','vault') NOT NULL,
  location VARCHAR(100) NULL,
  project_tenant VARCHAR(150) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === kms_routing_policies ===
CREATE TABLE IF NOT EXISTS kms_routing_policies (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  priority INT NOT NULL DEFAULT 0,
  strategy ENUM('prefer','require','avoid') NOT NULL DEFAULT 'prefer',
  `match` JSON NULL,
  providers JSON NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT uq_kms_route_name UNIQUE (name),
  INDEX idx_kms_route_active (active, priority DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === login_attempts ===
CREATE TABLE IF NOT EXISTS login_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  ip_hash BINARY(32) NOT NULL,
  attempted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  success BOOLEAN NOT NULL DEFAULT 0,
  user_id BIGINT UNSIGNED NULL,
  username_hash BINARY(32) NULL,
  auth_event_id BIGINT UNSIGNED NULL,
  INDEX idx_login_ip_success_time (ip_hash, success, attempted_at),
  INDEX idx_login_attempted_at (attempted_at),
  INDEX idx_login_username_hash (username_hash),
  INDEX idx_login_auth_event (auth_event_id),
  INDEX idx_login_user_time (user_id, attempted_at),
  CONSTRAINT chk_login_success CHECK (success IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === merkle_anchors ===
CREATE TABLE IF NOT EXISTS merkle_anchors (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  merkle_root_id BIGINT UNSIGNED NOT NULL,
  anchor_type ENUM('file','blockchain','notary') NOT NULL,
  anchor_ref VARCHAR(512) NOT NULL,
  anchored_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  UNIQUE KEY ux_anchor_triplet (merkle_root_id, anchor_type, anchor_ref),
  INDEX idx_merkle_anchors_mrid (merkle_root_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === merkle_roots ===
CREATE TABLE IF NOT EXISTS merkle_roots (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  subject_table VARCHAR(64) NOT NULL,
  period_start DATETIME(6) NOT NULL,
  period_end DATETIME(6) NOT NULL,
  root_hash BINARY(32) NOT NULL,
  proof_uri VARCHAR(512) NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  leaf_count BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_merkle_subject_period (subject_table, period_start, period_end),
  INDEX idx_merkle_subject (subject_table),
  INDEX idx_merkle_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === migration_events ===
CREATE TABLE IF NOT EXISTS migration_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  system_name VARCHAR(120) NOT NULL,
  from_version VARCHAR(64) NULL,
  to_version VARCHAR(64) NOT NULL,
  status ENUM('pending','running','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  error TEXT NULL,
  meta JSON NULL,
  INDEX idx_mig_system_status (system_name, status),
  INDEX idx_mig_started       (started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === newsletter_subscribers ===
CREATE TABLE IF NOT EXISTS newsletter_subscribers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  email_hash BINARY(32) NOT NULL,
  email_hash_key_version VARCHAR(64) NULL,
  email_enc LONGBLOB NULL,
  email_key_version VARCHAR(64) NULL,
  confirm_selector CHAR(12) DEFAULT NULL,
  confirm_validator_hash BINARY(32) DEFAULT NULL,
  confirm_key_version VARCHAR(64) DEFAULT NULL,
  confirm_expires DATETIME(6) DEFAULT NULL,
  confirmed_at DATETIME(6) DEFAULT NULL,
  unsubscribe_token_hash BINARY(32) DEFAULT NULL,
  unsubscribe_token_key_version VARCHAR(64) DEFAULT NULL,
  unsubscribed_at DATETIME(6) DEFAULT NULL,
  origin VARCHAR(100) DEFAULT NULL,
  ip_hash BINARY(32) DEFAULT NULL,
  ip_hash_key_version VARCHAR(64) DEFAULT NULL,
  meta JSON DEFAULT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY ux_ns_tenant_email_hash (tenant_id, email_hash),
  UNIQUE KEY ux_ns_confirm_selector (confirm_selector),
  INDEX idx_ns_tenant (tenant_id),
  INDEX idx_ns_user (user_id),
  INDEX idx_ns_confirm_expires (confirm_expires),
  INDEX idx_ns_unsubscribed_at (unsubscribed_at),
  INDEX idx_ns_confirmed_at (confirmed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === notifications ===
CREATE TABLE IF NOT EXISTS notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  channel ENUM('email','push') NOT NULL,
  template VARCHAR(100) NOT NULL,
  payload JSON NULL,
  status ENUM('pending','processing','sent','failed') NOT NULL DEFAULT 'pending',
  retries INT NOT NULL DEFAULT 0,
  max_retries INT NOT NULL DEFAULT 6,
  next_attempt_at DATETIME(6) NULL,
  scheduled_at DATETIME(6) NULL,
  sent_at DATETIME(6) NULL,
  error TEXT NULL,
  last_attempt_at DATETIME(6) NULL,
  locked_until DATETIME(6) NULL,
  locked_by VARCHAR(100) NULL,
  priority INT NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  INDEX idx_notifications_status_scheduled (status, scheduled_at),
  INDEX idx_notifications_tenant_status_sched (tenant_id, status, scheduled_at),
  INDEX idx_notifications_next_attempt (next_attempt_at),
  INDEX idx_notifications_locked_until (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === order_item_downloads ===
CREATE TABLE IF NOT EXISTS order_item_downloads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  asset_id BIGINT UNSIGNED NOT NULL,
  download_token_hash BINARY(32) NULL,
  token_key_version VARCHAR(64) NULL,
  key_version VARCHAR(64) NULL,
  max_uses INT NOT NULL,
  used INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) GENERATED ALWAYS AS (used < max_uses) STORED,
  expires_at DATETIME(6) NOT NULL,
  last_used_at DATETIME(6) NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  INDEX idx_oid_download_token_hash (download_token_hash),
  INDEX idx_oid_expires_at (expires_at),
  INDEX idx_oid_tenant_order (tenant_id, order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === order_items ===
CREATE TABLE IF NOT EXISTS order_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NULL,
  book_id BIGINT UNSIGNED NULL,
  product_ref INT NULL,
  title_snapshot VARCHAR(255) NOT NULL,
  sku_snapshot VARCHAR(64) NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  quantity INT UNSIGNED NOT NULL,
  tax_rate DECIMAL(5,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  INDEX idx_order_items_order_id (order_id),
  INDEX idx_order_items_book_id (book_id),
  INDEX idx_order_items_tenant_order (tenant_id, order_id),
  INDEX idx_order_items_tenant_book (tenant_id, book_id),
  CONSTRAINT chk_order_items_qty CHECK (quantity > 0),
  CONSTRAINT chk_order_items_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === orders ===
CREATE TABLE IF NOT EXISTS orders (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  uuid CHAR(36) NOT NULL UNIQUE,
  uuid_bin BINARY(16) NULL,
  public_order_no VARCHAR(64) NULL,
  user_id BIGINT UNSIGNED NULL,
  status ENUM('pending','paid','failed','cancelled','refunded','completed') NOT NULL DEFAULT 'pending',
  encrypted_customer_blob LONGBLOB NULL,
  encrypted_customer_blob_key_version VARCHAR(64) NULL,
  encryption_meta JSON NULL,
  currency CHAR(3) NOT NULL,
  metadata JSON NULL,
  subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  total DECIMAL(12,2) NOT NULL DEFAULT 0,
  payment_method VARCHAR(100) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  INDEX idx_orders_user_id (user_id),
  INDEX idx_orders_status (status),
  INDEX idx_orders_user_status (user_id, status),
  INDEX idx_orders_tenant (tenant_id),
  INDEX idx_orders_tenant_user (tenant_id, user_id),
  UNIQUE KEY ux_orders_uuid_bin (uuid_bin),
  UNIQUE KEY ux_orders_tenant_public_no (tenant_id, public_order_no),
  UNIQUE KEY ux_orders_tenant_id (tenant_id, id),
  CONSTRAINT chk_orders_nonneg CHECK (subtotal >= 0 AND discount_total >= 0 AND tax_total >= 0 AND total >= 0),
  CONSTRAINT chk_orders_total_eq CHECK (total = subtotal - discount_total + tax_total),
  CONSTRAINT chk_orders_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  CONSTRAINT chk_orders_version CHECK (version >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === payment_gateway_notifications ===
CREATE TABLE IF NOT EXISTS payment_gateway_notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaction_id VARCHAR(255) NOT NULL,
  tenant_id BIGINT UNSIGNED NOT NULL,
  received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  processing_by VARCHAR(100) NULL,
  processing_until DATETIME(6) NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  last_error VARCHAR(255) NULL,
  status ENUM('pending','processing','done','failed') NOT NULL DEFAULT 'pending',
  UNIQUE KEY ux_pg_notify_tenant_tx (tenant_id, transaction_id),
  INDEX idx_pg_notify_status_received (status, received_at),
  INDEX idx_pg_notify_tenant_status_received (tenant_id, status, received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === payment_logs ===
CREATE TABLE IF NOT EXISTS payment_logs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  payment_id BIGINT UNSIGNED NOT NULL,
  log_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  message TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === payment_webhooks ===
CREATE TABLE IF NOT EXISTS payment_webhooks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  payment_id BIGINT UNSIGNED NULL,
  gateway_event_id VARCHAR(255) NULL,
  payload_hash CHAR(64) NOT NULL,
  payload JSON NULL,
  from_cache BOOLEAN NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_payment_webhooks_payment (payment_id),
  INDEX idx_payment_webhooks_gw_id (gateway_event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === payments ===
CREATE TABLE IF NOT EXISTS payments (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NULL,
  gateway VARCHAR(100) NOT NULL,
  transaction_id VARCHAR(255) NULL,
  provider_event_id VARCHAR(255) NULL,
  status ENUM('initiated','pending','authorized','paid','cancelled','partially_refunded','refunded','failed') NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  details JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY ux_payments_tenant_tx (tenant_id, transaction_id),
  UNIQUE KEY ux_payments_tenant_id (tenant_id, id),
  INDEX idx_payments_tenant (tenant_id),
  INDEX idx_payments_tenant_order (tenant_id, order_id),
  INDEX idx_payments_order (order_id),
  INDEX idx_payments_provider_event (provider_event_id),
  CONSTRAINT chk_payments_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  CONSTRAINT chk_payments_version CHECK (version >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === peer_nodes ===
CREATE TABLE IF NOT EXISTS peer_nodes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  `type` ENUM('postgres','mysql','app','service') NOT NULL,
  location VARCHAR(120) NULL,
  status ENUM('active','offline','degraded','disabled') NOT NULL DEFAULT 'active',
  last_seen DATETIME(6) NULL,
  meta JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT uq_peer_nodes_name UNIQUE (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === permissions ===
CREATE TABLE IF NOT EXISTS permissions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  description TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === policy_algorithms ===
CREATE TABLE IF NOT EXISTS policy_algorithms (
  policy_id BIGINT UNSIGNED NOT NULL,
  algo_id BIGINT UNSIGNED NOT NULL,
  role ENUM('kem','sig','hash','symmetric') NOT NULL,
  weight INT NOT NULL DEFAULT 1,
  priority INT NOT NULL DEFAULT 0,
  PRIMARY KEY (policy_id, algo_id, role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === policy_kms_keys ===
CREATE TABLE IF NOT EXISTS policy_kms_keys (
  policy_id BIGINT UNSIGNED NOT NULL,
  kms_key_id BIGINT UNSIGNED NOT NULL,
  weight INT NOT NULL DEFAULT 1,
  priority INT NOT NULL DEFAULT 0,
  PRIMARY KEY (policy_id, kms_key_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === pq_migration_jobs ===
CREATE TABLE IF NOT EXISTS pq_migration_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  scope ENUM('hashes','wrappers','signatures') NOT NULL,
  target_policy_id BIGINT UNSIGNED NULL,
  target_algo_id BIGINT UNSIGNED NULL,
  selection JSON NULL,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  status ENUM('pending','running','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  processed_count BIGINT UNSIGNED NOT NULL DEFAULT 0,
  error TEXT NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_pq_mig_status_sched (status, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === privacy_requests ===
CREATE TABLE IF NOT EXISTS privacy_requests (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  `type` ENUM('access','erasure','rectify','restrict','portability') NOT NULL,
  status ENUM('pending','processing','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  requested_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  processed_at DATETIME(6) NULL,
  meta JSON NULL,
  INDEX idx_pr_user        (user_id),
  INDEX idx_pr_type_status (`type`, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rate_limit_counters ===
CREATE TABLE IF NOT EXISTS rate_limit_counters (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  subject_type ENUM('ip','user','api_key','tenant') NOT NULL,
  subject_id VARCHAR(128) NOT NULL,
  name VARCHAR(120) NOT NULL,
  window_start DATETIME(6) NOT NULL,
  window_size_sec INT NOT NULL,
  `count` INT NOT NULL DEFAULT 0,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_rlc (subject_type, subject_id, name, window_start, window_size_sec),
  INDEX idx_rlc_window  (name, window_start),
  INDEX idx_rlc_subject (subject_type, subject_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rate_limits ===
CREATE TABLE IF NOT EXISTS rate_limits (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  subject_type ENUM('ip','user','api_key','tenant') NOT NULL,
  subject_id VARCHAR(128) NOT NULL,
  name VARCHAR(120) NOT NULL,
  window_size_sec INT NOT NULL,
  limit_count INT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_rate_limits (subject_type, subject_id, name, window_size_sec),
  INDEX idx_rate_limits_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_repo_snapshots ===
CREATE TABLE IF NOT EXISTS rbac_repo_snapshots (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  repo_id BIGINT UNSIGNED NOT NULL,
  commit_id VARCHAR(128) NOT NULL,
  taken_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  metadata JSON NULL,
  UNIQUE KEY uq_rbac_repo_snap (repo_id, commit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_repositories ===
CREATE TABLE IF NOT EXISTS rbac_repositories (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  url VARCHAR(1024) NULL,
  signing_key_id BIGINT UNSIGNED NULL,
  status ENUM('active','disabled') NOT NULL DEFAULT 'active',
  last_synced_at DATETIME(6) NULL,
  last_commit VARCHAR(128) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_rbac_repositories_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_role_permissions ===
CREATE TABLE IF NOT EXISTS rbac_role_permissions (
  role_id BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  effect ENUM('allow','deny') NOT NULL DEFAULT 'allow',
  source ENUM('repo','local') NOT NULL DEFAULT 'repo',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (role_id, permission_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_roles ===
CREATE TABLE IF NOT EXISTS rbac_roles (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  repo_id BIGINT UNSIGNED NULL,
  slug VARCHAR(120) NOT NULL,
  name VARCHAR(200) NOT NULL,
  description TEXT NULL,
  version INT NOT NULL DEFAULT 1,
  status ENUM('active','deprecated','archived') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_rbac_roles_repo_slug (repo_id, slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_sync_cursors ===
CREATE TABLE IF NOT EXISTS rbac_sync_cursors (
  repo_id BIGINT UNSIGNED NOT NULL,
  peer VARCHAR(120) NOT NULL,
  last_commit VARCHAR(128) NULL,
  last_synced_at DATETIME(6) NULL,
  PRIMARY KEY (repo_id, peer)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_user_permissions ===
CREATE TABLE IF NOT EXISTS rbac_user_permissions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  tenant_id BIGINT UNSIGNED NULL,
  scope VARCHAR(120) NULL,
  effect ENUM('allow','deny') NOT NULL DEFAULT 'allow',
  granted_by BIGINT UNSIGNED NULL,
  granted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  expires_at DATETIME(6) NULL,
  UNIQUE KEY uq_rbac_user_perm (user_id, permission_id, tenant_id, scope)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rbac_user_roles ===
CREATE TABLE IF NOT EXISTS rbac_user_roles (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  tenant_id BIGINT UNSIGNED NULL,
  scope VARCHAR(120) NULL,
  status ENUM('active','revoked','expired') NOT NULL DEFAULT 'active',
  granted_by BIGINT UNSIGNED NULL,
  granted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  expires_at DATETIME(6) NULL,
  UNIQUE KEY uq_rbac_user_roles (user_id, role_id, tenant_id, scope)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === refunds ===
CREATE TABLE IF NOT EXISTS refunds (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  payment_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  reason TEXT NULL,
  status VARCHAR(50) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  details JSON NULL,
  CONSTRAINT chk_refunds_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  INDEX idx_refunds_tenant_payment (tenant_id, payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === register_events ===
CREATE TABLE IF NOT EXISTS register_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  `type` ENUM('register_success','register_failure') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  INDEX idx_reg_user (user_id),
  INDEX idx_reg_time (occurred_at),
  INDEX idx_reg_type_time (`type`, occurred_at),
  INDEX idx_reg_ip (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === replication_lag_samples ===
CREATE TABLE IF NOT EXISTS replication_lag_samples (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  peer_id BIGINT UNSIGNED NOT NULL,
  metric ENUM('apply_lag_ms','transport_lag_ms') NOT NULL,
  value BIGINT NOT NULL,
  captured_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_lag_peer_time (peer_id, captured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === retention_enforcement_jobs ===
CREATE TABLE IF NOT EXISTS retention_enforcement_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  policy_id BIGINT UNSIGNED NOT NULL,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  status ENUM('pending','running','done','failed','cancelled') NOT NULL DEFAULT 'pending',
  processed_count BIGINT UNSIGNED NOT NULL DEFAULT 0,
  error TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_rej_status_sched (status, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === reviews ===
CREATE TABLE IF NOT EXISTS reviews (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  rating TINYINT UNSIGNED NOT NULL,
  review_text TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NULL ON UPDATE CURRENT_TIMESTAMP(6),
  INDEX idx_reviews_book_id (book_id),
  INDEX idx_reviews_created_at (created_at),
  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === rewrap_jobs ===
CREATE TABLE IF NOT EXISTS rewrap_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  key_wrapper_id BIGINT UNSIGNED NOT NULL,
  target_kms1_key_id BIGINT UNSIGNED NULL,
  target_kms2_key_id BIGINT UNSIGNED NULL,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  status ENUM('pending','running','done','failed') NOT NULL DEFAULT 'pending',
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  last_error TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === session_audit ===
CREATE TABLE IF NOT EXISTS session_audit (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_token_hash BINARY(32) NULL,
  session_token_key_version VARCHAR(64) NULL,
  csrf_token_hash BINARY(32) NULL,
  csrf_key_version VARCHAR(64) NULL,
  session_id VARCHAR(128) NULL,
  `event` VARCHAR(64) NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  meta_json JSON NULL,
  outcome VARCHAR(32) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_session_audit_token_hash (session_token_hash),
  INDEX idx_session_audit_session_id (session_id),
  INDEX idx_session_audit_user_id (user_id),
  INDEX idx_session_audit_created_at (created_at),
  INDEX idx_session_audit_event (`event`),
  INDEX idx_session_audit_ip_hash (ip_hash),
  INDEX idx_session_audit_ip_key (ip_hash_key_version),
  INDEX idx_session_audit_event_time (`event`, created_at),
  INDEX idx_session_audit_user_event_time (user_id, `event`, created_at),
  INDEX idx_session_audit_event_user_time (`event`, user_id, created_at),
  INDEX idx_session_audit_token_time (session_token_hash, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === sessions ===
CREATE TABLE IF NOT EXISTS sessions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  token_hash BINARY(32) NOT NULL,
  token_hash_key_version VARCHAR(64) NULL,
  token_fingerprint BINARY(32) NULL,
  token_issued_at DATETIME(6) NULL,
  user_id BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  last_seen_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  expires_at DATETIME(6) NULL,
  failed_decrypt_count INT UNSIGNED NOT NULL DEFAULT 0,
  last_failed_decrypt_at DATETIME(6) NULL,
  revoked BOOLEAN NOT NULL DEFAULT 0,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  session_blob LONGBLOB NULL,
  UNIQUE KEY uq_sessions_token_hash (token_hash),
  INDEX idx_sessions_user_created (user_id, created_at),
  INDEX idx_sessions_user (user_id),
  INDEX idx_sessions_expires_at (expires_at),
  INDEX idx_sessions_last_seen (last_seen_at),
  INDEX idx_sessions_token_hash_key (token_hash_key_version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === schema_registry ===
CREATE TABLE IF NOT EXISTS schema_registry (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  system_name VARCHAR(120) NOT NULL,
  component VARCHAR(120) NOT NULL,
  version VARCHAR(64) NOT NULL,
  checksum VARCHAR(64) NULL,
  applied_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  UNIQUE KEY uq_schema_version (system_name, component, version),
  INDEX idx_schema_component (system_name, component)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === signatures ===
CREATE TABLE IF NOT EXISTS signatures (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  subject_table VARCHAR(64) NOT NULL,
  subject_pk VARCHAR(64) NOT NULL,
  `context` VARCHAR(64) NOT NULL,
  algo_id BIGINT UNSIGNED NOT NULL,
  signing_key_id BIGINT UNSIGNED NULL,
  signature LONGBLOB NOT NULL,
  payload_hash VARBINARY(64) NOT NULL,
  hash_algo_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_signatures (subject_table, subject_pk, `context`, algo_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === signing_keys ===
CREATE TABLE IF NOT EXISTS signing_keys (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  algo_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(120) NOT NULL,
  public_key LONGBLOB NOT NULL,
  private_key_enc LONGBLOB NULL,
  kms_key_id BIGINT UNSIGNED NULL,
  origin ENUM('local','kms','imported') NOT NULL DEFAULT 'local',
  status ENUM('active','retired','compromised') NOT NULL DEFAULT 'active',
  scope VARCHAR(120) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  activated_at DATETIME(6) NULL,
  retired_at DATETIME(6) NULL,
  notes TEXT NULL,
  UNIQUE KEY uq_signing_keys_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === slo_status ===
CREATE TABLE IF NOT EXISTS slo_status (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  window_id BIGINT UNSIGNED NOT NULL,
  computed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  sli_value DECIMAL(18,6) NULL,
  good_events BIGINT UNSIGNED NOT NULL DEFAULT 0,
  total_events BIGINT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('good','breach','unknown') NOT NULL DEFAULT 'unknown',
  UNIQUE KEY ux_slo_status (window_id, computed_at),
  INDEX idx_slo_status_window (window_id, computed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === slo_windows ===
CREATE TABLE IF NOT EXISTS slo_windows (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  objective JSON NOT NULL,      -- {"metric":"outbox_latency_sec","threshold":10,"percentile":95}
  target_pct DECIMAL(5,2) NOT NULL,
  window_interval VARCHAR(64) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT uq_slo_windows_name UNIQUE (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === sync_batch_items ===
CREATE TABLE IF NOT EXISTS sync_batch_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  batch_id BIGINT UNSIGNED NOT NULL,
  event_key CHAR(36) NOT NULL,
  status ENUM('pending','sent','applied','failed','skipped') NOT NULL DEFAULT 'pending',
  error TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_sync_batch_event (batch_id, event_key),
  INDEX idx_sbi_batch  (batch_id),
  INDEX idx_sbi_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === sync_batches ===
CREATE TABLE IF NOT EXISTS sync_batches (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  channel VARCHAR(120) NOT NULL,
  producer_peer_id BIGINT UNSIGNED NOT NULL,
  consumer_peer_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending','sending','completed','failed','cancelled') NOT NULL DEFAULT 'pending',
  items_total INT NOT NULL DEFAULT 0,
  items_ok INT NOT NULL DEFAULT 0,
  items_failed INT NOT NULL DEFAULT 0,
  error TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  INDEX idx_sync_batches_status  (status),
  INDEX idx_sync_batches_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === sync_errors ===
CREATE TABLE IF NOT EXISTS sync_errors (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  source VARCHAR(100) NOT NULL,
  event_key CHAR(36) NULL,
  peer_id BIGINT UNSIGNED NULL,
  error TEXT NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_sync_errors_peer    (peer_id),
  INDEX idx_sync_errors_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === system_errors ===
CREATE TABLE IF NOT EXISTS system_errors (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  level ENUM('notice','warning','error','critical') NOT NULL,
  message TEXT NOT NULL,
  exception_class VARCHAR(255) NULL,
  file VARCHAR(1024) NULL,
  line INT UNSIGNED NULL,
  stack_trace MEDIUMTEXT NULL,
  token VARCHAR(255) NULL,
  context JSON NULL,
  fingerprint VARCHAR(64) NULL,
  occurrences INT UNSIGNED NOT NULL DEFAULT 1,
  user_id BIGINT UNSIGNED NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  ip_text VARCHAR(45) NULL,
  ip_bin VARBINARY(16) NULL,
  user_agent VARCHAR(1024) NULL,
  url VARCHAR(2048) NULL,
  `method` VARCHAR(10) NULL,
  http_status SMALLINT UNSIGNED NULL,
  resolved BOOLEAN NOT NULL DEFAULT 0,
  resolved_by BIGINT UNSIGNED NULL,
  resolved_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_seen DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_err_level (level),
  INDEX idx_err_time (created_at),
  INDEX idx_err_user (user_id),
  INDEX idx_err_ip (ip_hash),
  INDEX idx_err_resolved (resolved),
  UNIQUE KEY uq_err_fp (fingerprint)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === system_jobs ===
CREATE TABLE IF NOT EXISTS system_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  job_type VARCHAR(100) NOT NULL,
  payload JSON NULL,
  status ENUM('pending','processing','done','failed') NOT NULL DEFAULT 'pending',
  retries INT NOT NULL DEFAULT 0,
  scheduled_at DATETIME(6) NULL,
  started_at DATETIME(6) NULL,
  finished_at DATETIME(6) NULL,
  error TEXT NULL,
  unique_key_hash CHAR(64) NULL,
  unique_key_version VARCHAR(64) NULL,
  locked_until DATETIME(6) NULL,
  locked_by VARCHAR(100) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  INDEX idx_system_jobs_status_sched (status, scheduled_at),
  INDEX idx_system_jobs_locked_until (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === tax_rates ===
CREATE TABLE IF NOT EXISTS tax_rates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  country_iso2 CHAR(2) NOT NULL,
  category ENUM('ebook','physical') NOT NULL,
  rate DECIMAL(5,2) NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === tenant_domains ===
CREATE TABLE IF NOT EXISTS tenant_domains (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  domain VARCHAR(255) NOT NULL,
  domain_ci VARCHAR(255) GENERATED ALWAYS AS (LOWER(domain)) STORED,
  is_primary BOOLEAN NOT NULL DEFAULT 0,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT uq_tenant_domains UNIQUE (tenant_id, domain_ci)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === tenants ===
CREATE TABLE IF NOT EXISTS tenants (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  slug VARCHAR(200) NOT NULL,
  slug_ci VARCHAR(200) GENERATED ALWAYS AS (LOWER(slug)) STORED,
  status ENUM('active','suspended','deleted') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at DATETIME(6) NULL,
  is_live TINYINT(1) GENERATED ALWAYS AS (deleted_at IS NULL) STORED,
  CONSTRAINT chk_tenants_version CHECK (version >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === two_factor ===
CREATE TABLE IF NOT EXISTS two_factor (
  user_id BIGINT UNSIGNED NOT NULL,
  `method` VARCHAR(50) NOT NULL,
  secret VARBINARY(255) NULL,
  recovery_codes_enc LONGBLOB NULL,
  hotp_counter BIGINT UNSIGNED NULL,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  last_used_at DATETIME(6) NULL,
  PRIMARY KEY (user_id, `method`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === user_consents ===
CREATE TABLE IF NOT EXISTS user_consents (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  consent_type VARCHAR(50) NOT NULL,
  version VARCHAR(50) NOT NULL,
  granted BOOLEAN NOT NULL,
  granted_at DATETIME(6) NOT NULL,
  source VARCHAR(100) NULL,
  meta JSON NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === user_identities ===
CREATE TABLE IF NOT EXISTS user_identities (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(100) NOT NULL,
  provider_user_id VARCHAR(255) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY ux_provider_user (provider, provider_user_id),
  INDEX idx_user_identities_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === user_profiles ===
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id BIGINT UNSIGNED PRIMARY KEY,
  profile_enc LONGBLOB NULL,
  key_version VARCHAR(64) NULL,
  encryption_meta JSON NULL,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === users ===
CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email_hash BINARY(32) NULL,
  email_hash_key_version VARCHAR(64) NULL,
  password_hash VARCHAR(255) NOT NULL,
  password_algo VARCHAR(64) NULL,
  password_key_version VARCHAR(64) NULL,
  is_active BOOLEAN NOT NULL DEFAULT 0,
  is_locked BOOLEAN NOT NULL DEFAULT 0,
  failed_logins INT NOT NULL DEFAULT 0,
  must_change_password BOOLEAN NOT NULL DEFAULT 0,
  last_login_at DATETIME(6) NULL,
  last_login_ip_hash BINARY(32) NULL,
  last_login_ip_key_version VARCHAR(64) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at DATETIME(6) NULL,
  actor_role ENUM('customer','admin') NOT NULL DEFAULT 'customer',
  INDEX idx_users_last_login_at (last_login_at),
  INDEX idx_users_is_active (is_active),
  INDEX idx_users_actor_role (actor_role),
  INDEX idx_users_last_login_ip_hash (last_login_ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === vat_validations ===
CREATE TABLE IF NOT EXISTS vat_validations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  vat_id VARCHAR(50) NOT NULL,
  country_iso2 CHAR(2) NOT NULL,
  valid BOOLEAN NOT NULL,
  checked_at DATETIME(6) NOT NULL,
  raw JSON NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === verify_events ===
CREATE TABLE IF NOT EXISTS verify_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  `type` ENUM('verify_success','verify_failure') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  INDEX idx_ver_user (user_id),
  INDEX idx_ver_time (occurred_at),
  INDEX idx_ver_type_time (`type`, occurred_at),
  INDEX idx_ver_ip (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === webhook_outbox ===
CREATE TABLE IF NOT EXISTS webhook_outbox (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  event_type VARCHAR(100) NOT NULL,
  payload JSON NULL,
  status ENUM('pending','sent','failed') NOT NULL DEFAULT 'pending',
  retries INT NOT NULL DEFAULT 0,
  next_attempt_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  version INT UNSIGNED NOT NULL DEFAULT 0,
  INDEX idx_webhook_status_scheduled (status, next_attempt_at),
  INDEX idx_webhook_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === worker_locks ===
CREATE TABLE IF NOT EXISTS worker_locks (
  name VARCHAR(191) NOT NULL PRIMARY KEY,
  locked_until DATETIME(6) NOT NULL,
  INDEX idx_worker_locks_until (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


