-- === app_settings ===
CREATE TABLE IF NOT EXISTS app_settings (
  setting_key VARCHAR(100) PRIMARY KEY,
  setting_value TEXT NULL,
  type ENUM('string','int','bool','json','secret') NOT NULL,
  section VARCHAR(100) NULL,
  description TEXT NULL,
  is_protected BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_by BIGINT UNSIGNED NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  type ENUM('login_success','login_failure','logout','password_reset','lockout') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  meta_email VARCHAR(255) GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(meta, '$.email'))) STORED,
  INDEX idx_auth_meta_email (meta_email),
  INDEX idx_auth_user (user_id),
  INDEX idx_auth_time (occurred_at),
  INDEX idx_auth_type_time (type, occurred_at),
  INDEX idx_auth_ip_hash (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === authors ===
CREATE TABLE IF NOT EXISTS authors (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL UNIQUE,
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
  deleted_at DATETIME(6) NULL,
  INDEX idx_authors_avg_rating (avg_rating),
  INDEX idx_authors_books_count (books_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === book_assets ===
CREATE TABLE IF NOT EXISTS book_assets (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  book_id BIGINT UNSIGNED NOT NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (book_id, category_id),
  INDEX idx_book_categories_category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === books ===
CREATE TABLE IF NOT EXISTS books (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL UNIQUE,
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
  deleted_at DATETIME(6) NULL,
  INDEX idx_books_author_id (author_id),
  INDEX idx_books_main_category_id (main_category_id),
  INDEX idx_books_sku (sku),
  CONSTRAINT chk_books_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === cart_items ===
CREATE TABLE IF NOT EXISTS cart_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === carts ===
CREATE TABLE IF NOT EXISTS carts (
  id CHAR(36) PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === categories ===
CREATE TABLE IF NOT EXISTS categories (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL UNIQUE,
  parent_id BIGINT UNSIGNED NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  deleted_at DATETIME(6) NULL,
  INDEX idx_categories_parent (parent_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === countries ===
CREATE TABLE IF NOT EXISTS countries (
  iso2 CHAR(2) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  CONSTRAINT chk_countries_iso2 CHECK (iso2 REGEXP '^[A-Z]{2}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === coupon_redemptions ===
CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  coupon_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  redeemed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  amount_applied DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === coupons ===
CREATE TABLE IF NOT EXISTS coupons (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(100) NOT NULL UNIQUE,
  type ENUM('percent','fixed') NOT NULL,
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
    (type='percent' AND value BETWEEN 0 AND 100 AND currency IS NULL)
    OR (type='fixed' AND value >= 0 AND (currency REGEXP '^[A-Z]{3}$')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === idempotency_keys ===
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key_hash CHAR(64) NOT NULL PRIMARY KEY,
  payment_id BIGINT UNSIGNED NULL DEFAULT NULL,
  order_id BIGINT UNSIGNED NULL DEFAULT NULL,
  gateway_payload JSON NULL,
  redirect_url VARCHAR(1024) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  ttl_seconds INT NOT NULL DEFAULT 86400,
  INDEX idx_idemp_payment (payment_id),
  INDEX idx_idemp_order (order_id),
  INDEX idx_idemp_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === inventory_reservations ===
CREATE TABLE IF NOT EXISTS inventory_reservations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  quantity INT UNSIGNED NOT NULL,
  reserved_until DATETIME(6) NOT NULL,
  status ENUM('pending','confirmed','expired','cancelled') NOT NULL DEFAULT 'pending',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_res_book (book_id),
  INDEX idx_res_order (order_id),
  INDEX idx_res_status_until (status, reserved_until),
  CONSTRAINT chk_res_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === invoice_items ===
CREATE TABLE IF NOT EXISTS invoice_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  CONSTRAINT chk_invoice_items_currency CHECK (currency REGEXP '^[A-Z]{3}$'),
  CONSTRAINT chk_invoice_items_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === invoices ===
CREATE TABLE IF NOT EXISTS invoices (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NULL,
  invoice_number VARCHAR(100) NOT NULL UNIQUE,
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
  CONSTRAINT chk_invoices_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === jwt_tokens ===
CREATE TABLE IF NOT EXISTS jwt_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  jti CHAR(36) NOT NULL UNIQUE,
  user_id BIGINT UNSIGNED NULL,
  token_hash BINARY(32) NOT NULL,
  token_hash_algo VARCHAR(50) NULL,
  token_hash_key_version VARCHAR(64) NULL,
  type ENUM('refresh','api') NOT NULL DEFAULT 'refresh',
  scopes VARCHAR(255) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
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
  `date` DATE NOT NULL,
  encrypt_count INT NOT NULL DEFAULT 0,
  decrypt_count INT NOT NULL DEFAULT 0,
  verify_count INT NOT NULL DEFAULT 0,
  last_used_at DATETIME(6) NULL,
  UNIQUE KEY uq_key_usage_key_date (key_id, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === kms_keys ===
CREATE TABLE IF NOT EXISTS kms_keys (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider_id BIGINT UNSIGNED NOT NULL,
  external_key_ref VARCHAR(512) NOT NULL,
  purpose ENUM('wrap','encrypt','both') NOT NULL DEFAULT 'wrap',
  algorithm VARCHAR(64) NULL,
  status ENUM('active','retired','disabled') NOT NULL DEFAULT 'active',
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === kms_providers ===
CREATE TABLE IF NOT EXISTS kms_providers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  provider ENUM('gcp','aws','azure','vault') NOT NULL,
  location VARCHAR(100) NULL,
  project_tenant VARCHAR(150) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  INDEX idx_login_user_time (user_id, attempted_at),
  CONSTRAINT chk_login_success CHECK (success IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === newsletter_subscribers ===
CREATE TABLE IF NOT EXISTS newsletter_subscribers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  email_hash BINARY(32) NULL,
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
  UNIQUE KEY ux_ns_email_hash (email_hash),
  UNIQUE KEY ux_ns_confirm_selector (confirm_selector),
  INDEX idx_ns_user (user_id),
  INDEX idx_ns_confirm_expires (confirm_expires),
  INDEX idx_ns_unsubscribed_at (unsubscribed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === notifications ===
CREATE TABLE IF NOT EXISTS notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  INDEX idx_notifications_status_scheduled (status, scheduled_at),
  INDEX idx_notifications_next_attempt (next_attempt_at),
  INDEX idx_notifications_locked_until (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === order_item_downloads ===
CREATE TABLE IF NOT EXISTS order_item_downloads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  asset_id BIGINT UNSIGNED NOT NULL,
  download_token_hash BINARY(32) NULL,
  token_key_version VARCHAR(64) NULL,
  key_version VARCHAR(64) NULL,
  max_uses INT NOT NULL,
  used INT NOT NULL DEFAULT 0,
  expires_at DATETIME(6) NOT NULL,
  last_used_at DATETIME(6) NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  INDEX idx_oid_download_token_hash (download_token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === order_items ===
CREATE TABLE IF NOT EXISTS order_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  CONSTRAINT chk_order_items_qty CHECK (quantity > 0),
  CONSTRAINT chk_order_items_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === orders ===
CREATE TABLE IF NOT EXISTS orders (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  INDEX idx_orders_user_id (user_id),
  INDEX idx_orders_status (status),
  INDEX idx_orders_user_status (user_id, status),
  INDEX idx_orders_uuid (uuid),
  UNIQUE KEY ux_orders_uuid_bin (uuid_bin),
  CONSTRAINT chk_orders_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === payment_gateway_notifications ===
CREATE TABLE IF NOT EXISTS payment_gateway_notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  transaction_id VARCHAR(255) NULL,
  received_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  processing_by VARCHAR(100) NULL,
  processing_until DATETIME(6) NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 0,
  last_error VARCHAR(255) NULL,
  status ENUM('pending','processing','done','failed') NOT NULL DEFAULT 'pending',
  UNIQUE KEY ux_pg_notify_tx (transaction_id),
  INDEX idx_pg_notify_status_received (status, received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === payment_logs ===
CREATE TABLE IF NOT EXISTS payment_logs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  payment_id BIGINT UNSIGNED NOT NULL,
  log_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  message TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  INDEX idx_payment_webhooks_gw_id (gateway_event_id),
  INDEX idx_payment_webhooks_hash (payload_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === payments ===
CREATE TABLE IF NOT EXISTS payments (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
  UNIQUE KEY uq_payments_transaction_id (transaction_id),
  INDEX idx_payments_order (order_id),
  INDEX idx_payments_provider_event (provider_event_id),
  CONSTRAINT chk_payments_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === permissions ===
CREATE TABLE IF NOT EXISTS permissions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  description TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === policy_kms_keys ===
CREATE TABLE IF NOT EXISTS policy_kms_keys (
  policy_id BIGINT UNSIGNED NOT NULL,
  kms_key_id BIGINT UNSIGNED NOT NULL,
  weight INT NOT NULL DEFAULT 1,
  priority INT NOT NULL DEFAULT 0,
  PRIMARY KEY (policy_id, kms_key_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === refunds ===
CREATE TABLE IF NOT EXISTS refunds (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  payment_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  reason TEXT NULL,
  status VARCHAR(50) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  details JSON NULL,
  CONSTRAINT chk_refunds_currency CHECK (currency REGEXP '^[A-Z]{3}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === register_events ===
CREATE TABLE IF NOT EXISTS register_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  type ENUM('register_success','register_failure') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  INDEX idx_reg_user (user_id),
  INDEX idx_reg_time (occurred_at),
  INDEX idx_reg_type_time (type, occurred_at),
  INDEX idx_reg_ip (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === reviews ===
CREATE TABLE IF NOT EXISTS reviews (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  book_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  rating TINYINT UNSIGNED NOT NULL,
  review_text TEXT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NULL ON UPDATE CURRENT_TIMESTAMP(6),
  INDEX idx_reviews_book_id (book_id),
  INDEX idx_reviews_created_at (created_at),
  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === session_audit ===
CREATE TABLE IF NOT EXISTS session_audit (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_token BINARY(32) NULL,
  session_token_key_version VARCHAR(64) NULL,
  csrf_key_version VARCHAR(64) NULL,
  session_id VARCHAR(128) NULL,
  event VARCHAR(64) NOT NULL,
  user_id BIGINT UNSIGNED NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  meta_json JSON NULL,
  outcome VARCHAR(32) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  INDEX idx_session_audit_token (session_token),
  INDEX idx_session_audit_session_id (session_id),
  INDEX idx_session_audit_user_id (user_id),
  INDEX idx_session_audit_created_at (created_at),
  INDEX idx_session_audit_event (event),
  INDEX idx_session_audit_ip_hash (ip_hash),
  INDEX idx_session_audit_ip_key (ip_hash_key_version),
  INDEX idx_session_audit_event_time (event, created_at),
  INDEX idx_session_audit_user_event_time (user_id, event, created_at),
  INDEX idx_session_audit_token_time (session_token, created_at)
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
  method VARCHAR(10) NULL,
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
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  INDEX idx_system_jobs_status_sched (status, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === tax_rates ===
CREATE TABLE IF NOT EXISTS tax_rates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  country_iso2 CHAR(2) NOT NULL,
  category ENUM('ebook','physical') NOT NULL,
  rate DECIMAL(5,2) NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === two_factor ===
CREATE TABLE IF NOT EXISTS two_factor (
  user_id BIGINT UNSIGNED NOT NULL,
  method VARCHAR(50) NOT NULL,
  secret VARBINARY(255) NULL,
  recovery_codes_enc LONGBLOB NULL,
  hotp_counter BIGINT UNSIGNED NULL,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_used_at DATETIME(6) NULL,
  PRIMARY KEY (user_id, method)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === user_profiles ===
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id BIGINT UNSIGNED PRIMARY KEY,
  profile_enc LONGBLOB NULL,
  key_version VARCHAR(64) NULL,
  encryption_meta JSON NULL,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  deleted_at DATETIME(6) NULL,
  actor_role ENUM('customer','admin') NOT NULL DEFAULT 'customer',
  INDEX idx_users_last_login_at (last_login_at),
  INDEX idx_users_is_active (is_active),
  INDEX idx_users_actor_role (actor_role),
  INDEX idx_users_last_login_ip_hash (last_login_ip_hash),
  INDEX idx_users_email_hash (email_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === vat_validations ===
CREATE TABLE IF NOT EXISTS vat_validations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  vat_id VARCHAR(50) NOT NULL,
  country_iso2 CHAR(2) NOT NULL,
  valid BOOLEAN NOT NULL,
  checked_at DATETIME(6) NOT NULL,
  raw JSON NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- === verify_events ===
CREATE TABLE IF NOT EXISTS verify_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  type ENUM('verify_success','verify_failure') NOT NULL,
  ip_hash BINARY(32) NULL,
  ip_hash_key_version VARCHAR(64) NULL,
  user_agent VARCHAR(1024) NULL,
  occurred_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  INDEX idx_ver_user (user_id),
  INDEX idx_ver_time (occurred_at),
  INDEX idx_ver_type_time (type, occurred_at),
  INDEX idx_ver_ip (ip_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  INDEX idx_webhook_status_scheduled (status, next_attempt_at),
  INDEX idx_webhook_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- === worker_locks ===
CREATE TABLE IF NOT EXISTS worker_locks (
  name VARCHAR(191) NOT NULL PRIMARY KEY,
  locked_until DATETIME(6) NOT NULL,
  INDEX idx_worker_locks_until (locked_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


