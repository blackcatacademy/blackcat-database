```mermaid
%%{init: {"theme":"forest","themeVariables":{"primaryColor":"#0b1021","primaryBorderColor":"#4ade80","primaryTextColor":"#e2e8f0","edgeLabelBackground":"#0b1021","tertiaryColor":"#111827","tertiaryTextColor":"#cbd5e1","lineColor":"#67e8f9","nodeBorder":"#38bdf8","textColor":"#e2e8f0"}} }%%
%% ERD generated from scripts/schema/schema-map-postgres.yaml (engine: postgres)
erDiagram
  %% direction: LR
  api_keys {
    BIGSERIAL id
    BIGINT tenant_id
    BIGINT user_id
    VARCHAR(120) name
    TEXT name_ci
    BYTEA token_hash
    VARCHAR(64) token_hash_key_version
    JSONB scopes
    VARCHAR(20) status
    TIMESTAMPTZ(6) last_used_at
    TIMESTAMPTZ(6) expires_at
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  app_settings {
    VARCHAR(100) setting_key
    TEXT setting_value
    TEXT type
    VARCHAR(100) section
    TEXT description
    BOOLEAN is_protected
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    BIGINT updated_by
  }
  audit_chain {
    BIGINT id
    BIGINT audit_id
    VARCHAR(100) chain_name
    BYTEA prev_hash
    BYTEA hash
    TIMESTAMPTZ(6) created_at
  }
  audit_log {
    BIGINT id
    VARCHAR(100) table_name
    BIGINT record_id
    BIGINT changed_by
    TEXT change_type
    JSONB old_value
    JSONB new_value
    TIMESTAMPTZ(6) changed_at
    BYTEA ip_bin
    VARCHAR(1024) user_agent
    VARCHAR(100) request_id
  }
  auth_events {
    BIGINT id
    BIGINT user_id
    TEXT type
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(1024) user_agent
    TIMESTAMPTZ(6) occurred_at
    JSONB meta
    TEXT meta_email
  }
  authors {
    BIGINT id
    BIGINT tenant_id
    VARCHAR(255) name
    TEXT name_ci
    VARCHAR(255) slug
    TEXT slug_ci
    TEXT bio
    VARCHAR(255) photo_url
    TEXT story
    INTEGER books_count
    INTEGER ratings_count
    INTEGER rating_sum
    NUMERIC(3) avg_rating
    TIMESTAMPTZ(6) last_rating_at
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    TIMESTAMPTZ(6) deleted_at
    BOOLEAN is_live
  }
  book_assets {
    BIGINT id
    BIGINT tenant_id
    BIGINT book_id
    TEXT asset_type
    VARCHAR(255) filename
    VARCHAR(100) mime_type
    BIGINT size_bytes
    TEXT storage_path
    VARCHAR(64) content_hash
    VARCHAR(255) download_filename
    BOOLEAN is_encrypted
    VARCHAR(50) encryption_algo
    BYTEA encryption_key_enc
    BYTEA encryption_iv
    BYTEA encryption_tag
    BYTEA encryption_aad
    JSONB encryption_meta
    VARCHAR(64) key_version
    BIGINT key_id
    TIMESTAMPTZ(6) created_at
  }
  book_categories {
    BIGINT tenant_id
    BIGINT book_id
    BIGINT category_id
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  books {
    BIGINT id
    BIGINT tenant_id
    VARCHAR(255) title
    VARCHAR(255) slug
    TEXT slug_ci
    VARCHAR(512) short_description
    TEXT full_description
    NUMERIC(12) price
    CHAR(3) currency
    BIGINT author_id
    BIGINT main_category_id
    VARCHAR(32) isbn
    CHAR(5) language
    INTEGER pages
    VARCHAR(255) publisher
    DATE published_at
    VARCHAR(64) sku
    BOOLEAN is_active
    BOOLEAN is_available
    INTEGER stock_quantity
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    TIMESTAMPTZ(6) deleted_at
    BOOLEAN is_live
  }
  cart_items {
    BIGINT id
    BIGINT tenant_id
    CHAR(36) cart_id
    BIGINT book_id
    VARCHAR(64) sku
    VARCHAR(64) sku_norm
    JSONB variant
    INTEGER quantity
    NUMERIC(12) unit_price
    NUMERIC(12) price_snapshot
    CHAR(3) currency
    JSONB meta
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  carts {
    CHAR(36) id
    BIGINT tenant_id
    BIGINT user_id
    VARCHAR(200) note
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  categories {
    BIGINT id
    BIGINT tenant_id
    VARCHAR(255) name
    TEXT name_ci
    VARCHAR(255) slug
    TEXT slug_ci
    BIGINT parent_id
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    TIMESTAMPTZ(6) deleted_at
    BOOLEAN is_live
  }
  countries {
    CHAR(2) iso2
    VARCHAR(100) name
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  coupon_redemptions {
    BIGINT id
    BIGINT tenant_id
    BIGINT coupon_id
    BIGINT user_id
    BIGINT order_id
    TIMESTAMPTZ(6) redeemed_at
    NUMERIC(12) amount_applied
  }
  coupons {
    BIGINT id
    BIGINT tenant_id
    VARCHAR(100) code
    TEXT code_ci
    TEXT type
    NUMERIC(12) value
    CHAR(3) currency
    DATE starts_at
    DATE ends_at
    INTEGER max_redemptions
    NUMERIC(12) min_order_amount
    JSONB applies_to
    BOOLEAN is_active
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  crypto_algorithms {
    BIGINT id
    TEXT class
    VARCHAR(120) name
    VARCHAR(80) variant
    TEXT variant_norm
    SMALLINT nist_level
    TEXT status
    JSONB params
    TIMESTAMPTZ(6) created_at
  }
  crypto_keys {
    BIGINT id
    VARCHAR(100) basename
    INTEGER version
    VARCHAR(255) filename
    VARCHAR(1024) file_path
    CHAR(64) fingerprint
    JSONB key_meta
    TEXT key_type
    VARCHAR(64) algorithm
    SMALLINT length_bits
    TEXT origin
    TEXT[] usage
    VARCHAR(100) scope
    TEXT status
    BOOLEAN is_backup_encrypted
    BYTEA backup_blob
    BIGINT created_by
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) activated_at
    TIMESTAMPTZ(6) retired_at
    BIGINT replaced_by
    TEXT notes
  }
  crypto_standard_aliases {
    VARCHAR(120) alias
    BIGINT algo_id
    TEXT notes
    TIMESTAMPTZ(6) created_at
  }
  data_retention_policies {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) field_name
    TEXT action
    VARCHAR(64) keep_for
    BOOLEAN active
    TEXT notes
    TIMESTAMPTZ(6) created_at
  }
  deletion_jobs {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    TEXT reason
    BOOLEAN hard_delete
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT status
    TEXT error
    BIGINT created_by
    TIMESTAMPTZ(6) created_at
  }
  device_fingerprints {
    BIGINT id
    BIGINT user_id
    BYTEA fingerprint_hash
    JSONB attributes
    SMALLINT risk_score
    TIMESTAMPTZ(6) first_seen
    TIMESTAMPTZ(6) last_seen
    BYTEA last_ip_hash
    VARCHAR(64) last_ip_key_version
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  email_verifications {
    BIGINT id
    BIGINT user_id
    CHAR(64) token_hash
    CHAR(12) selector
    BYTEA validator_hash
    VARCHAR(64) key_version
    TIMESTAMPTZ(6) expires_at
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) used_at
  }
  encrypted_fields {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    VARCHAR(64) field_name
    BYTEA ciphertext
    JSONB meta
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  encryption_bindings {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    VARCHAR(64) field_name
    VARCHAR(64) field_name_norm
    BIGINT key_wrapper_id
    TIMESTAMPTZ(6) created_at
  }
  encryption_events {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    VARCHAR(64) field_name
    TEXT op
    BIGINT policy_id
    VARCHAR(64) local_key_version
    JSONB layers
    TEXT outcome
    VARCHAR(64) error_code
    TIMESTAMPTZ(6) created_at
  }
  encryption_policies {
    BIGINT id
    VARCHAR(100) policy_name
    TEXT mode
    TEXT layer_selection
    SMALLINT min_layers
    SMALLINT max_layers
    JSONB aad_template
    TEXT notes
    TIMESTAMPTZ(6) created_at
  }
  encryption_policy_bindings {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) field_name
    BIGINT policy_id
    TIMESTAMPTZ(6) effective_from
    TEXT notes
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  entity_external_ids {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    VARCHAR(100) source
    VARCHAR(200) external_id
    TIMESTAMPTZ(6) created_at
  }
  event_dlq {
    BIGINT id
    VARCHAR(100) source
    CHAR(36) event_key
    JSONB event
    TEXT error
    BOOLEAN retryable
    INTEGER attempts
    TIMESTAMPTZ(6) first_failed_at
    TIMESTAMPTZ(6) last_failed_at
  }
  event_inbox {
    BIGINT id
    VARCHAR(100) source
    CHAR(36) event_key
    JSONB payload
    TEXT status
    INTEGER attempts
    TEXT last_error
    TIMESTAMPTZ(6) received_at
    TIMESTAMPTZ(6) processed_at
  }
  event_outbox {
    BIGINT id
    CHAR(36) event_key
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    VARCHAR(100) event_type
    JSONB payload
    TEXT status
    INTEGER attempts
    TIMESTAMPTZ(6) next_attempt_at
    TIMESTAMPTZ(6) processed_at
    VARCHAR(100) producer_node
    TIMESTAMPTZ(6) created_at
  }
  field_hash_policies {
    BIGINT id
    VARCHAR(64) entity_table
    VARCHAR(64) field_name
    BIGINT profile_id
    TIMESTAMPTZ(6) effective_from
    TEXT notes
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  global_id_registry {
    CHAR(26) gid
    UUID guid
    VARCHAR(64) entity_table
    VARCHAR(64) entity_pk
    TIMESTAMPTZ(6) created_at
  }
  hash_profiles {
    BIGINT id
    VARCHAR(120) name
    BIGINT algo_id
    SMALLINT output_len
    JSONB params
    TEXT status
    TIMESTAMPTZ(6) created_at
  }
  idempotency_keys {
    CHAR(64) key_hash
    BIGINT tenant_id
    BIGINT payment_id
    BIGINT order_id
    JSONB gateway_payload
    VARCHAR(1024) redirect_url
    TIMESTAMPTZ(6) created_at
    INTEGER ttl_seconds
  }
  inventory_reservations {
    BIGINT id
    BIGINT tenant_id
    BIGINT order_id
    BIGINT book_id
    INTEGER quantity
    TIMESTAMPTZ(6) reserved_until
    TEXT status
    TIMESTAMPTZ(6) created_at
    INTEGER version
  }
  invoice_items {
    BIGINT id
    BIGINT tenant_id
    BIGINT invoice_id
    INTEGER line_no
    TEXT description
    NUMERIC(12) unit_price
    INTEGER quantity
    NUMERIC(5) tax_rate
    NUMERIC(12) tax_amount
    NUMERIC(12) line_total
    CHAR(3) currency
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  invoices {
    BIGINT id
    BIGINT tenant_id
    BIGINT order_id
    VARCHAR(100) invoice_number
    VARCHAR(50) variable_symbol
    DATE issue_date
    DATE due_date
    NUMERIC(12) subtotal
    NUMERIC(12) discount_total
    NUMERIC(12) tax_total
    NUMERIC(12) total
    CHAR(3) currency
    TEXT qr_data
    TIMESTAMPTZ(6) created_at
  }
  jwt_tokens {
    BIGINT id
    CHAR(36) jti
    BIGINT user_id
    BYTEA token_hash
    VARCHAR(50) token_hash_algo
    VARCHAR(64) token_hash_key_version
    TEXT type
    VARCHAR(255) scopes
    TIMESTAMPTZ(6) created_at
    INTEGER version
    TIMESTAMPTZ(6) expires_at
    TIMESTAMPTZ(6) last_used_at
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    BIGINT replaced_by
    BOOLEAN revoked
    JSONB meta
  }
  key_events {
    BIGINT id
    BIGINT key_id
    VARCHAR(100) basename
    TEXT event_type
    BIGINT actor_id
    BIGINT job_id
    TEXT note
    JSONB meta
    TEXT source
    TIMESTAMPTZ(6) created_at
  }
  key_rotation_jobs {
    BIGINT id
    VARCHAR(100) basename
    INTEGER target_version
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT status
    INTEGER attempts
    BIGINT executed_by
    TEXT result
    TIMESTAMPTZ(6) created_at
  }
  key_usage {
    BIGINT id
    BIGINT key_id
    DATE usage_date
    INTEGER encrypt_count
    INTEGER decrypt_count
    INTEGER verify_count
    TIMESTAMPTZ(6) last_used_at
  }
  key_wrapper_layers {
    BIGINT id
    BIGINT key_wrapper_id
    SMALLINT layer_no
    BIGINT kms_key_id
    BIGINT kem_algo_id
    BYTEA kem_ciphertext
    BYTEA encap_pubkey
    JSONB aad
    JSONB meta
    TIMESTAMPTZ(6) created_at
  }
  key_wrappers {
    BIGINT id
    CHAR(36) wrapper_uuid
    BIGINT kms1_key_id
    BIGINT kms2_key_id
    BYTEA dek_wrap1
    BYTEA dek_wrap2
    JSONB crypto_suite
    INTEGER wrap_version
    TEXT status
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) rotated_at
  }
  kms_health_checks {
    BIGINT id
    BIGINT provider_id
    BIGINT kms_key_id
    TEXT status
    INTEGER latency_ms
    TEXT error
    TIMESTAMPTZ(6) checked_at
  }
  kms_keys {
    BIGINT id
    BIGINT provider_id
    VARCHAR(512) external_key_ref
    TEXT purpose
    VARCHAR(64) algorithm
    TEXT status
    TIMESTAMPTZ(6) created_at
  }
  kms_providers {
    BIGINT id
    VARCHAR(100) name
    TEXT provider
    VARCHAR(100) location
    VARCHAR(150) project_tenant
    TIMESTAMPTZ(6) created_at
    BOOLEAN is_enabled
  }
  kms_routing_policies {
    BIGINT id
    VARCHAR(120) name
    INTEGER priority
    TEXT strategy
    JSONB match
    JSONB providers
    BOOLEAN active
    TIMESTAMPTZ(6) created_at
  }
  login_attempts {
    BIGINT id
    BYTEA ip_hash
    TIMESTAMPTZ(6) attempted_at
    BOOLEAN success
    BIGINT user_id
    BYTEA username_hash
    BIGINT auth_event_id
  }
  merkle_anchors {
    BIGINT id
    BIGINT merkle_root_id
    TEXT anchor_type
    VARCHAR(512) anchor_ref
    TIMESTAMPTZ(6) anchored_at
    JSONB meta
  }
  merkle_roots {
    BIGINT id
    VARCHAR(64) subject_table
    TIMESTAMPTZ(6) period_start
    TIMESTAMPTZ(6) period_end
    BYTEA root_hash
    VARCHAR(512) proof_uri
    VARCHAR(32) status
    BIGINT leaf_count
    TIMESTAMPTZ(6) created_at
  }
  migration_events {
    BIGINT id
    VARCHAR(120) system_name
    VARCHAR(64) from_version
    VARCHAR(64) to_version
    TEXT status
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT error
    JSONB meta
  }
  newsletter_subscribers {
    BIGINT id
    BIGINT tenant_id
    BIGINT user_id
    BYTEA email_hash
    VARCHAR(64) email_hash_key_version
    BYTEA email_enc
    VARCHAR(64) email_key_version
    CHAR(12) confirm_selector
    BYTEA confirm_validator_hash
    VARCHAR(64) confirm_key_version
    TIMESTAMPTZ(6) confirm_expires
    TIMESTAMPTZ(6) confirmed_at
    BYTEA unsubscribe_token_hash
    VARCHAR(64) unsubscribe_token_key_version
    TIMESTAMPTZ(6) unsubscribed_at
    VARCHAR(100) origin
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    JSONB meta
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  notifications {
    BIGINT id
    BIGINT tenant_id
    BIGINT user_id
    TEXT channel
    VARCHAR(100) template
    JSONB payload
    TEXT status
    INTEGER retries
    INTEGER max_retries
    TIMESTAMPTZ(6) next_attempt_at
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) sent_at
    TEXT error
    TIMESTAMPTZ(6) last_attempt_at
    TIMESTAMPTZ(6) locked_until
    VARCHAR(100) locked_by
    INTEGER priority
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  order_item_downloads {
    BIGINT id
    BIGINT tenant_id
    BIGINT order_id
    BIGINT book_id
    BIGINT asset_id
    BYTEA download_token_hash
    VARCHAR(64) token_key_version
    VARCHAR(64) key_version
    INTEGER max_uses
    INTEGER used
    BOOLEAN is_active
    TIMESTAMPTZ(6) expires_at
    TIMESTAMPTZ(6) last_used_at
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
  }
  order_items {
    BIGINT id
    BIGINT tenant_id
    BIGINT order_id
    BIGINT book_id
    INTEGER product_ref
    VARCHAR(255) title_snapshot
    VARCHAR(64) sku_snapshot
    NUMERIC(12) unit_price
    INTEGER quantity
    NUMERIC(5) tax_rate
    CHAR(3) currency
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  orders {
    BIGINT id
    BIGINT tenant_id
    CHAR(36) uuid
    BYTEA uuid_bin
    VARCHAR(64) public_order_no
    BIGINT user_id
    TEXT status
    BYTEA encrypted_customer_blob
    VARCHAR(64) encrypted_customer_blob_key_version
    JSONB encryption_meta
    CHAR(3) currency
    JSONB metadata
    NUMERIC(12) subtotal
    NUMERIC(12) discount_total
    NUMERIC(12) tax_total
    NUMERIC(12) total
    VARCHAR(100) payment_method
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  payment_gateway_notifications {
    BIGINT id
    VARCHAR(255) transaction_id
    BIGINT tenant_id
    TIMESTAMPTZ(6) received_at
    INTEGER version
    VARCHAR(100) processing_by
    TIMESTAMPTZ(6) processing_until
    INTEGER attempts
    VARCHAR(255) last_error
    TEXT status
  }
  payment_logs {
    BIGINT id
    BIGINT payment_id
    TIMESTAMPTZ(6) log_at
    TEXT message
  }
  payment_webhooks {
    BIGINT id
    BIGINT payment_id
    VARCHAR(255) gateway_event_id
    CHAR(64) payload_hash
    JSONB payload
    BOOLEAN from_cache
    TIMESTAMPTZ(6) created_at
  }
  payments {
    BIGINT id
    BIGINT tenant_id
    BIGINT order_id
    VARCHAR(100) gateway
    VARCHAR(255) transaction_id
    VARCHAR(255) provider_event_id
    TEXT status
    NUMERIC(12) amount
    CHAR(3) currency
    JSONB details
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  peer_nodes {
    BIGINT id
    VARCHAR(120) name
    TEXT type
    VARCHAR(120) location
    TEXT status
    TIMESTAMPTZ(6) last_seen
    JSONB meta
    TIMESTAMPTZ(6) created_at
  }
  permissions {
    BIGINT id
    VARCHAR(100) name
    TEXT description
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  policy_algorithms {
    BIGINT policy_id
    BIGINT algo_id
    TEXT role
    INTEGER weight
    INTEGER priority
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  policy_kms_keys {
    BIGINT policy_id
    BIGINT kms_key_id
    INTEGER weight
    INTEGER priority
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  pq_migration_jobs {
    BIGINT id
    TEXT scope
    BIGINT target_policy_id
    BIGINT target_algo_id
    JSONB selection
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT status
    BIGINT processed_count
    TEXT error
    BIGINT created_by
    TIMESTAMPTZ(6) created_at
  }
  privacy_requests {
    BIGINT id
    BIGINT user_id
    TEXT type
    TEXT status
    TIMESTAMPTZ(6) requested_at
    TIMESTAMPTZ(6) processed_at
    JSONB meta
  }
  rate_limit_counters {
    BIGINT id
    TEXT subject_type
    VARCHAR(128) subject_id
    VARCHAR(120) name
    TIMESTAMPTZ(6) window_start
    INTEGER window_size_sec
    INTEGER count
    TIMESTAMPTZ(6) updated_at
  }
  rate_limits {
    BIGINT id
    TEXT subject_type
    VARCHAR(128) subject_id
    VARCHAR(120) name
    INTEGER window_size_sec
    INTEGER limit_count
    BOOLEAN active
    TIMESTAMPTZ(6) created_at
  }
  rbac_repo_snapshots {
    BIGINT id
    BIGINT repo_id
    VARCHAR(128) commit_id
    TIMESTAMPTZ(6) taken_at
    JSONB metadata
  }
  rbac_repositories {
    BIGINT id
    VARCHAR(120) name
    VARCHAR(1024) url
    BIGINT signing_key_id
    TEXT status
    TIMESTAMPTZ(6) last_synced_at
    VARCHAR(128) last_commit
    TIMESTAMPTZ(6) created_at
  }
  rbac_role_permissions {
    BIGINT role_id
    BIGINT permission_id
    TEXT effect
    TEXT source
    TIMESTAMPTZ(6) created_at
  }
  rbac_roles {
    BIGINT id
    BIGINT repo_id
    VARCHAR(120) slug
    VARCHAR(200) name
    TEXT description
    INTEGER version
    TEXT status
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  rbac_sync_cursors {
    BIGINT repo_id
    VARCHAR(120) peer
    VARCHAR(128) last_commit
    TIMESTAMPTZ(6) last_synced_at
  }
  rbac_user_permissions {
    BIGINT id
    BIGINT user_id
    BIGINT permission_id
    BIGINT tenant_id
    VARCHAR(120) scope
    TEXT effect
    BIGINT granted_by
    TIMESTAMPTZ(6) granted_at
    TIMESTAMPTZ(6) expires_at
  }
  rbac_user_roles {
    BIGINT id
    BIGINT user_id
    BIGINT role_id
    BIGINT tenant_id
    VARCHAR(120) scope
    TEXT status
    BIGINT granted_by
    TIMESTAMPTZ(6) granted_at
    TIMESTAMPTZ(6) expires_at
  }
  refunds {
    BIGINT id
    BIGINT tenant_id
    BIGINT payment_id
    NUMERIC(12) amount
    CHAR(3) currency
    TEXT reason
    VARCHAR(50) status
    TIMESTAMPTZ(6) created_at
    JSONB details
  }
  register_events {
    BIGINT id
    BIGINT user_id
    TEXT type
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(1024) user_agent
    TIMESTAMPTZ(6) occurred_at
    JSONB meta
  }
  replication_lag_samples {
    BIGINT id
    BIGINT peer_id
    TEXT metric
    BIGINT value
    TIMESTAMPTZ(6) captured_at
  }
  retention_enforcement_jobs {
    BIGINT id
    BIGINT policy_id
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT status
    BIGINT processed_count
    TEXT error
    TIMESTAMPTZ(6) created_at
  }
  reviews {
    BIGINT id
    BIGINT tenant_id
    BIGINT book_id
    BIGINT user_id
    SMALLINT rating
    TEXT review_text
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  rewrap_jobs {
    BIGINT id
    BIGINT key_wrapper_id
    BIGINT target_kms1_key_id
    BIGINT target_kms2_key_id
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT status
    INTEGER attempts
    TEXT last_error
    TIMESTAMPTZ(6) created_at
  }
  session_audit {
    BIGINT id
    BYTEA session_token_hash
    VARCHAR(64) session_token_key_version
    BYTEA csrf_token_hash
    VARCHAR(64) csrf_key_version
    VARCHAR(128) session_id
    VARCHAR(64) event
    BIGINT user_id
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(1024) user_agent
    JSONB meta_json
    VARCHAR(32) outcome
    TIMESTAMPTZ(6) created_at
  }
  sessions {
    BIGINT id
    BYTEA token_hash
    VARCHAR(64) token_hash_key_version
    BYTEA token_fingerprint
    TIMESTAMPTZ(6) token_issued_at
    BIGINT user_id
    TIMESTAMPTZ(6) created_at
    INTEGER version
    TIMESTAMPTZ(6) last_seen_at
    TIMESTAMPTZ(6) expires_at
    INTEGER failed_decrypt_count
    TIMESTAMPTZ(6) last_failed_decrypt_at
    BOOLEAN revoked
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(1024) user_agent
    BYTEA session_blob
  }
  schema_registry {
    BIGINT id
    VARCHAR(120) system_name
    VARCHAR(120) component
    VARCHAR(64) version
    VARCHAR(64) checksum
    TIMESTAMPTZ(6) applied_at
    JSONB meta
  }
  signatures {
    BIGINT id
    VARCHAR(64) subject_table
    VARCHAR(64) subject_pk
    VARCHAR(64) context
    BIGINT algo_id
    BIGINT signing_key_id
    BYTEA signature
    BYTEA payload_hash
    BIGINT hash_algo_id
    TIMESTAMPTZ(6) created_at
  }
  signing_keys {
    BIGINT id
    BIGINT algo_id
    VARCHAR(120) name
    BYTEA public_key
    BYTEA private_key_enc
    BIGINT kms_key_id
    TEXT origin
    TEXT status
    VARCHAR(120) scope
    BIGINT created_by
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) activated_at
    TIMESTAMPTZ(6) retired_at
    TEXT notes
  }
  slo_status {
    BIGINT id
    BIGINT window_id
    TIMESTAMPTZ(6) computed_at
    NUMERIC(18) sli_value
    BIGINT good_events
    BIGINT total_events
    TEXT status
  }
  slo_windows {
    BIGINT id
    VARCHAR(120) name
    JSONB objective
    NUMERIC(5) target_pct
    INTERVAL window_interval
    TIMESTAMPTZ(6) created_at
  }
  sync_batch_items {
    BIGINT id
    BIGINT batch_id
    CHAR(36) event_key
    TEXT status
    TEXT error
    TIMESTAMPTZ(6) created_at
  }
  sync_batches {
    BIGINT id
    VARCHAR(120) channel
    BIGINT producer_peer_id
    BIGINT consumer_peer_id
    TEXT status
    INTEGER items_total
    INTEGER items_ok
    INTEGER items_failed
    TEXT error
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
  }
  sync_errors {
    BIGINT id
    VARCHAR(100) source
    CHAR(36) event_key
    BIGINT peer_id
    TEXT error
    TIMESTAMPTZ(6) created_at
  }
  system_errors {
    BIGINT id
    TEXT level
    TEXT message
    VARCHAR(255) exception_class
    VARCHAR(1024) file
    INTEGER line
    TEXT stack_trace
    VARCHAR(255) token
    JSONB context
    VARCHAR(64) fingerprint
    INTEGER occurrences
    BIGINT user_id
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(45) ip_text
    BYTEA ip_bin
    VARCHAR(1024) user_agent
    VARCHAR(2048) url
    VARCHAR(10) method
    SMALLINT http_status
    BOOLEAN resolved
    BIGINT resolved_by
    TIMESTAMPTZ(6) resolved_at
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) last_seen
  }
  system_jobs {
    BIGINT id
    VARCHAR(100) job_type
    JSONB payload
    TEXT status
    INTEGER retries
    TIMESTAMPTZ(6) scheduled_at
    TIMESTAMPTZ(6) started_at
    TIMESTAMPTZ(6) finished_at
    TEXT error
    CHAR(64) unique_key_hash
    VARCHAR(64) unique_key_version
    TIMESTAMPTZ(6) locked_until
    VARCHAR(100) locked_by
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  tax_rates {
    BIGINT id
    CHAR(2) country_iso2
    TEXT category
    NUMERIC(5) rate
    DATE valid_from
    DATE valid_to
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  tenant_domains {
    BIGINT id
    BIGINT tenant_id
    VARCHAR(255) domain
    TEXT domain_ci
    BOOLEAN is_primary
    TIMESTAMPTZ(6) created_at
  }
  tenants {
    BIGINT id
    VARCHAR(200) name
    VARCHAR(200) slug
    TEXT slug_ci
    TEXT status
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    TIMESTAMPTZ(6) deleted_at
    BOOLEAN is_live
  }
  two_factor {
    BIGINT user_id
    VARCHAR(50) method
    BYTEA secret
    BYTEA recovery_codes_enc
    BIGINT hotp_counter
    BOOLEAN enabled
    TIMESTAMPTZ(6) created_at
    INTEGER version
    TIMESTAMPTZ(6) last_used_at
  }
  user_consents {
    BIGINT id
    BIGINT user_id
    VARCHAR(50) consent_type
    VARCHAR(50) version
    BOOLEAN granted
    TIMESTAMPTZ(6) granted_at
    VARCHAR(100) source
    JSONB meta
  }
  user_identities {
    BIGINT id
    BIGINT user_id
    VARCHAR(100) provider
    VARCHAR(255) provider_user_id
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
  user_profiles {
    BIGINT user_id
    BYTEA profile_enc
    VARCHAR(64) key_version
    JSONB encryption_meta
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  users {
    BIGINT id
    BYTEA email_hash
    VARCHAR(64) email_hash_key_version
    VARCHAR(255) password_hash
    VARCHAR(64) password_algo
    VARCHAR(64) password_key_version
    BOOLEAN is_active
    BOOLEAN is_locked
    INTEGER failed_logins
    BOOLEAN must_change_password
    TIMESTAMPTZ(6) last_login_at
    BYTEA last_login_ip_hash
    VARCHAR(64) last_login_ip_key_version
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
    TIMESTAMPTZ(6) deleted_at
    TEXT actor_role
  }
  vat_validations {
    BIGINT id
    VARCHAR(50) vat_id
    CHAR(2) country_iso2
    BOOLEAN valid
    TIMESTAMPTZ(6) checked_at
    JSONB raw
  }
  verify_events {
    BIGINT id
    BIGINT user_id
    TEXT type
    BYTEA ip_hash
    VARCHAR(64) ip_hash_key_version
    VARCHAR(1024) user_agent
    TIMESTAMPTZ(6) occurred_at
    JSONB meta
  }
  webhook_outbox {
    BIGINT id
    VARCHAR(100) event_type
    JSONB payload
    TEXT status
    INTEGER retries
    TIMESTAMPTZ(6) next_attempt_at
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
    INTEGER version
  }
  worker_locks {
    VARCHAR(191) name
    TIMESTAMPTZ(6) locked_until
    TIMESTAMPTZ(6) created_at
    TIMESTAMPTZ(6) updated_at
  }
api_keys }o--|| tenants : fk_api_keys_tenant
api_keys }o--|| users : fk_api_keys_user
app_settings }o--|| users : fk_app_settings_user
audit_chain }o--|| audit_log : fk_audit_chain_audit
audit_log }o--|| users : fk_audit_log_user
auth_events }o--|| users : fk_auth_user
authors }o--|| tenants : fk_authors_tenant
book_assets }o--|| books : fk_book_assets_book
book_assets }o--|| crypto_keys : fk_book_assets_key
book_assets }o--|| tenants : fk_book_assets_tenant
book_categories }o--|| books : fk_book_categories_book
book_categories }o--|| categories : fk_book_categories_category
books }o--|| authors : fk_books_author
books }o--|| categories : fk_books_category
books }o--|| tenants : fk_books_tenant
cart_items }o--|| books : fk_cart_items_book
cart_items }o--|| carts : fk_cart_items_cart
cart_items }o--|| tenants : fk_cart_items_tenant
carts }o--|| tenants : fk_carts_tenant
carts }o--|| users : fk_carts_user
categories }o--|| categories : fk_categories_parent
categories }o--|| tenants : fk_categories_tenant
coupon_redemptions }o--|| coupons : fk_cr_coupon
coupon_redemptions }o--|| orders : fk_cr_order
coupon_redemptions }o--|| tenants : fk_cr_tenant
coupon_redemptions }o--|| users : fk_cr_user
coupons }o--|| tenants : fk_coupons_tenant
crypto_keys }o--|| crypto_keys : fk_keys_replaced_by
crypto_keys }o--|| users : fk_keys_created_by
crypto_standard_aliases }o--|| crypto_algorithms : fk_crypto_alias_algo
deletion_jobs }o--|| users : fk_dj_user
device_fingerprints }o--|| users : fk_df_user
email_verifications }o--|| users : fk_ev_user
encryption_bindings }o--|| key_wrappers : fk_enc_bind_kw
encryption_policy_bindings }o--|| encryption_policies : fk_enc_pol_bind_policy
field_hash_policies }o--|| hash_profiles : fk_fhp_profile
hash_profiles }o--|| crypto_algorithms : fk_hp_algo
idempotency_keys }o--|| orders : fk_idemp_order
idempotency_keys }o--|| payments : fk_idemp_payment
idempotency_keys }o--|| tenants : fk_idemp_tenant
inventory_reservations }o--|| books : fk_res_book
inventory_reservations }o--|| orders : fk_res_order
inventory_reservations }o--|| tenants : fk_res_tenant
invoice_items }o--|| invoices : fk_invoice_items_invoice
invoices }o--|| orders : fk_invoices_order
invoices }o--|| tenants : fk_invoices_tenant
jwt_tokens }o--|| jwt_tokens : fk_jwt_tokens_replaced_by
jwt_tokens }o--|| users : fk_jwt_tokens_user
key_events }o--|| crypto_keys : fk_key_events_key
key_events }o--|| users : fk_key_events_actor
key_rotation_jobs }o--|| users : fk_key_rotation_jobs_user
key_usage }o--|| crypto_keys : fk_key_usage_key
key_wrapper_layers }o--|| crypto_algorithms : fk_kwl_algo
key_wrapper_layers }o--|| key_wrappers : fk_kwl_kw
key_wrapper_layers }o--|| kms_keys : fk_kwl_kms
key_wrappers }o--|| kms_keys : fk_kw_kms1
key_wrappers }o--|| kms_keys : fk_kw_kms2
kms_health_checks }o--|| kms_keys : fk_kms_hc_key
kms_health_checks }o--|| kms_providers : fk_kms_hc_provider
kms_keys }o--|| kms_providers : fk_kms_keys_provider
login_attempts }o--|| auth_events : fk_login_attempts_auth_event
login_attempts }o--|| users : fk_login_attempts_user
merkle_anchors }o--|| merkle_roots : fk_merkle_anchor_root
newsletter_subscribers }o--|| tenants : fk_ns_tenant
newsletter_subscribers }o--|| users : fk_ns_user
notifications }o--|| tenants : fk_notifications_tenant
notifications }o--|| users : fk_notifications_user
order_item_downloads }o--|| book_assets : fk_oid_asset
order_item_downloads }o--|| books : fk_oid_book
order_item_downloads }o--|| orders : fk_oid_order
order_item_downloads }o--|| tenants : fk_oid_tenant
order_items }o--|| books : fk_order_items_book
order_items }o--|| orders : fk_order_items_order
order_items }o--|| tenants : fk_order_items_tenant
orders }o--|| tenants : fk_orders_tenant
orders }o--|| users : fk_orders_user
payment_gateway_notifications }o--|| payments : fk_pg_notify_payment
payment_gateway_notifications }o--|| tenants : fk_pg_notify_tenant
payment_logs }o--|| payments : fk_payment_logs_payment
payment_webhooks }o--|| payments : fk_payment_webhooks_payment
payments }o--|| orders : fk_payments_order
payments }o--|| tenants : fk_payments_tenant
policy_algorithms }o--|| crypto_algorithms : fk_pa_algo
policy_algorithms }o--|| encryption_policies : fk_pa_policy
policy_kms_keys }o--|| encryption_policies : fk_policy_kms_keys_policy
policy_kms_keys }o--|| kms_keys : fk_policy_kms_keys_key
pq_migration_jobs }o--|| crypto_algorithms : fk_pq_mig_algo
pq_migration_jobs }o--|| encryption_policies : fk_pq_mig_policy
pq_migration_jobs }o--|| users : fk_pq_mig_user
privacy_requests }o--|| users : fk_pr_user
rbac_repo_snapshots }o--|| rbac_repositories : fk_rbac_snap_repo
rbac_repositories }o--|| signing_keys : fk_rbac_repos_sign_key
rbac_role_permissions }o--|| permissions : fk_rbac_rp_perm
rbac_role_permissions }o--|| rbac_roles : fk_rbac_rp_role
rbac_roles }o--|| rbac_repositories : fk_rbac_roles_repo
rbac_sync_cursors }o--|| rbac_repositories : fk_rbac_cursors_repo
rbac_user_permissions }o--|| permissions : fk_rbac_up_perm
rbac_user_permissions }o--|| tenants : fk_rbac_up_tenant
rbac_user_permissions }o--|| users : fk_rbac_up_grant
rbac_user_permissions }o--|| users : fk_rbac_up_user
rbac_user_roles }o--|| rbac_roles : fk_rbac_ur_role
rbac_user_roles }o--|| tenants : fk_rbac_ur_tenant
rbac_user_roles }o--|| users : fk_rbac_ur_grant
rbac_user_roles }o--|| users : fk_rbac_ur_user
refunds }o--|| payments : fk_refunds_payment
refunds }o--|| tenants : fk_refunds_tenant
register_events }o--|| users : fk_register_user
replication_lag_samples }o--|| peer_nodes : fk_lag_peer
retention_enforcement_jobs }o--|| data_retention_policies : fk_rej_policy
reviews }o--|| books : fk_reviews_book
reviews }o--|| tenants : fk_reviews_tenant
reviews }o--|| users : fk_reviews_user
rewrap_jobs }o--|| key_wrappers : fk_rewrap_kw
rewrap_jobs }o--|| kms_keys : fk_rewrap_tk1
rewrap_jobs }o--|| kms_keys : fk_rewrap_tk2
session_audit }o--|| users : fk_session_audit_user
sessions }o--|| users : fk_sessions_user
signatures }o--|| crypto_algorithms : fk_sigs_algo
signatures }o--|| crypto_algorithms : fk_sigs_hash
signatures }o--|| signing_keys : fk_sigs_skey
signing_keys }o--|| crypto_algorithms : fk_sk_algo
signing_keys }o--|| kms_keys : fk_sk_kms
signing_keys }o--|| users : fk_sk_user
slo_status }o--|| slo_windows : fk_slo_status_window
sync_batch_items }o--|| sync_batches : fk_sbi_batch
sync_batches }o--|| peer_nodes : fk_sb_consumer
sync_batches }o--|| peer_nodes : fk_sb_producer
sync_errors }o--|| peer_nodes : fk_sync_err_peer
system_errors }o--|| users : fk_err_resolved_by
system_errors }o--|| users : fk_err_user
tax_rates }o--|| countries : fk_tax_rates_country
tenant_domains }o--|| tenants : fk_tenant_domains_tenant
two_factor }o--|| users : fk_two_factor_user
user_consents }o--|| users : fk_user_consents_user
user_identities }o--|| users : fk_user_identities_user
user_profiles }o--|| users : fk_user_profiles_user
vat_validations }o--|| countries : fk_vat_validations_country
verify_events }o--|| users : fk_verify_user
  %% styling
  classDef linked fill:#0b1021,stroke:#38bdf8,stroke-width:2px,color:#e2e8f0;
  classDef orphan fill:#111827,stroke:#94a3b8,stroke-width:1px,color:#cbd5e1;
  classDef hub fill:#0f172a,stroke:#f59e0b,stroke-width:3px,color:#fef3c7;
  class api_keys linked;
  class tenants hub;
  class users hub;
  class app_settings linked;
  class audit_chain linked;
  class audit_log linked;
  class auth_events linked;
  class authors linked;
  class book_assets hub;
  class books hub;
  class crypto_keys hub;
  class book_categories linked;
  class categories hub;
  class cart_items hub;
  class carts hub;
  class coupon_redemptions hub;
  class coupons linked;
  class orders hub;
  class crypto_standard_aliases linked;
  class crypto_algorithms hub;
  class deletion_jobs linked;
  class device_fingerprints linked;
  class email_verifications linked;
  class encryption_bindings linked;
  class key_wrappers hub;
  class encryption_policy_bindings linked;
  class encryption_policies hub;
  class field_hash_policies linked;
  class hash_profiles linked;
  class idempotency_keys hub;
  class payments hub;
  class inventory_reservations hub;
  class invoice_items linked;
  class invoices hub;
  class jwt_tokens hub;
  class key_events linked;
  class key_rotation_jobs linked;
  class key_usage linked;
  class key_wrapper_layers hub;
  class kms_keys hub;
  class kms_health_checks linked;
  class kms_providers linked;
  class login_attempts linked;
  class merkle_anchors linked;
  class merkle_roots linked;
  class newsletter_subscribers linked;
  class notifications linked;
  class order_item_downloads hub;
  class order_items hub;
  class payment_gateway_notifications linked;
  class payment_logs linked;
  class payment_webhooks linked;
  class policy_algorithms linked;
  class policy_kms_keys linked;
  class pq_migration_jobs hub;
  class privacy_requests linked;
  class rbac_repo_snapshots linked;
  class rbac_repositories hub;
  class signing_keys hub;
  class rbac_role_permissions linked;
  class rbac_roles hub;
  class permissions linked;
  class rbac_sync_cursors linked;
  class rbac_user_permissions hub;
  class rbac_user_roles hub;
  class refunds linked;
  class register_events linked;
  class replication_lag_samples linked;
  class peer_nodes hub;
  class retention_enforcement_jobs linked;
  class data_retention_policies linked;
  class reviews hub;
  class rewrap_jobs hub;
  class session_audit linked;
  class sessions linked;
  class signatures hub;
  class slo_status linked;
  class slo_windows linked;
  class sync_batch_items linked;
  class sync_batches hub;
  class sync_errors linked;
  class system_errors linked;
  class tax_rates linked;
  class countries linked;
  class tenant_domains linked;
  class two_factor linked;
  class user_consents linked;
  class user_identities linked;
  class user_profiles linked;
  class vat_validations linked;
  class verify_events linked;
  class encrypted_fields orphan;
  class encryption_events orphan;
  class entity_external_ids orphan;
  class event_dlq orphan;
  class event_inbox orphan;
  class event_outbox orphan;
  class global_id_registry orphan;
  class kms_routing_policies orphan;
  class migration_events orphan;
  class rate_limit_counters orphan;
  class rate_limits orphan;
  class schema_registry orphan;
  class system_jobs orphan;
  class webhook_outbox orphan;
  class worker_locks orphan;
  %% Summary: tables=106, edges=138, linked=58, orphans=15, hubs=33, generated=2025-12-08T22:33:23+01:00
```
