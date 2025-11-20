-- === api_keys ===
CREATE INDEX IF NOT EXISTS idx_api_keys_tenant ON api_keys (tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_user   ON api_keys (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_api_keys_token ON api_keys (token_hash);
CREATE UNIQUE INDEX IF NOT EXISTS ux_api_keys_tenant_name ON api_keys (tenant_id, name_ci);

-- === audit_chain ===
CREATE INDEX IF NOT EXISTS idx_audit_chain_name_time ON audit_chain (chain_name, created_at);

-- === audit_log ===
CREATE INDEX IF NOT EXISTS idx_audit_table_record ON audit_log (table_name, record_id, changed_at);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at   ON audit_log (changed_at);
CREATE INDEX IF NOT EXISTS idx_audit_request_id   ON audit_log (request_id);

-- === auth_events ===
CREATE INDEX IF NOT EXISTS idx_auth_meta_email ON auth_events (meta_email);
CREATE INDEX IF NOT EXISTS idx_auth_user ON auth_events (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_time ON auth_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_auth_type_time ON auth_events (type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_auth_ip_hash ON auth_events (ip_hash);
CREATE INDEX IF NOT EXISTS gin_auth_events_meta ON auth_events   USING GIN (meta jsonb_path_ops);

-- === authors ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_authors_tenant_slug_live_ci ON authors (tenant_id, slug_ci) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_authors_tenant_id ON authors (tenant_id, id);
CREATE INDEX IF NOT EXISTS idx_authors_avg_rating ON authors (avg_rating);
CREATE INDEX IF NOT EXISTS idx_authors_books_count ON authors (books_count);
CREATE INDEX IF NOT EXISTS idx_authors_name_ci   ON authors (lower(name));

-- === book_assets ===
CREATE INDEX IF NOT EXISTS idx_book_assets_book ON book_assets (book_id);
CREATE INDEX IF NOT EXISTS idx_book_assets_type ON book_assets (asset_type);
CREATE INDEX IF NOT EXISTS gin_book_assets_enc_meta ON book_assets USING GIN (encryption_meta jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_book_assets_tenant ON book_assets (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_book_assets_tenant_unique ON book_assets (tenant_id, book_id, asset_type);
CREATE UNIQUE INDEX IF NOT EXISTS ux_book_assets_tenant_id ON book_assets (tenant_id, id);

-- === book_categories ===
CREATE INDEX IF NOT EXISTS idx_book_categories_category ON book_categories (category_id);
CREATE INDEX IF NOT EXISTS idx_book_categories_book ON book_categories (book_id);
CREATE INDEX IF NOT EXISTS idx_book_categories_tenant ON book_categories (tenant_id);

-- === books ===
CREATE INDEX IF NOT EXISTS idx_books_author_id ON books (author_id);
CREATE INDEX IF NOT EXISTS idx_books_main_category_id ON books (main_category_id);
CREATE INDEX IF NOT EXISTS idx_books_sku ON books (sku);
CREATE UNIQUE INDEX IF NOT EXISTS ux_books_tenant_slug_live_ci ON books (tenant_id, slug_ci) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_books_tenant_isbn ON books (tenant_id, isbn) WHERE isbn IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_books_tenant_id ON books (tenant_id, id);
CREATE INDEX IF NOT EXISTS idx_books_tenant_author ON books (tenant_id, author_id);
CREATE INDEX IF NOT EXISTS idx_books_tenant_category ON books (tenant_id, main_category_id);

-- === cart_items ===
CREATE INDEX IF NOT EXISTS idx_cart_items_cart_id ON cart_items (cart_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_cart_items_tenant_norm ON cart_items (tenant_id, cart_id, book_id, COALESCE(sku, ''));
CREATE INDEX IF NOT EXISTS idx_cart_items_tenant_cart ON cart_items (tenant_id, cart_id);

-- === carts ===
CREATE INDEX IF NOT EXISTS idx_carts_tenant ON carts (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_carts_tenant_id ON carts (tenant_id, id);

-- === categories ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_tenant_slug_live_ci ON categories (tenant_id, slug_ci) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_tenant_id ON categories (tenant_id, id);
CREATE INDEX IF NOT EXISTS idx_categories_tenant_parent ON categories (tenant_id, parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories (parent_id);
CREATE INDEX IF NOT EXISTS idx_categories_name_ci ON categories (lower(name));

-- === coupon_redemptions ===
CREATE INDEX IF NOT EXISTS idx_cr_coupon ON coupon_redemptions (coupon_id);
CREATE INDEX IF NOT EXISTS idx_cr_user   ON coupon_redemptions (user_id);
CREATE INDEX IF NOT EXISTS idx_cr_order  ON coupon_redemptions (order_id);
CREATE INDEX IF NOT EXISTS idx_cr_tenant_coupon ON coupon_redemptions (tenant_id, coupon_id);
CREATE INDEX IF NOT EXISTS idx_cr_tenant_user   ON coupon_redemptions (tenant_id, user_id);
CREATE INDEX IF NOT EXISTS idx_cr_tenant_order  ON coupon_redemptions (tenant_id, order_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_cr_tenant_order_coupon ON coupon_redemptions (tenant_id, order_id, coupon_id);

-- === coupons ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_coupons_tenant_code_ci ON coupons (tenant_id, code_ci);
CREATE INDEX IF NOT EXISTS idx_coupons_tenant_active ON coupons (tenant_id, is_active);

-- === crypto_algorithms ===
CREATE INDEX IF NOT EXISTS idx_ca_class_status ON crypto_algorithms (class, status);

-- === crypto_standard_aliases ===
CREATE INDEX IF NOT EXISTS idx_crypto_alias_algo ON crypto_standard_aliases (algo_id);

-- === data_retention_policies ===
CREATE INDEX IF NOT EXISTS idx_drp_entity ON data_retention_policies (entity_table, field_name);
CREATE INDEX IF NOT EXISTS idx_drp_active ON data_retention_policies (active);

-- === deletion_jobs ===
CREATE INDEX IF NOT EXISTS idx_dj_status_sched ON deletion_jobs (status, scheduled_at);

-- === device_fingerprints ===
CREATE INDEX IF NOT EXISTS idx_df_user ON device_fingerprints (user_id);
CREATE INDEX IF NOT EXISTS idx_df_last_seen ON device_fingerprints (last_seen);

-- === email_verifications ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_ev_selector ON email_verifications (selector);
CREATE INDEX IF NOT EXISTS idx_ev_user ON email_verifications (user_id);
CREATE INDEX IF NOT EXISTS idx_ev_expires ON email_verifications (expires_at);

-- === encrypted_fields ===
CREATE INDEX IF NOT EXISTS idx_enc_entity ON encrypted_fields (entity_table, entity_pk);
CREATE INDEX IF NOT EXISTS idx_encrypted_fields_field ON encrypted_fields (field_name);
CREATE INDEX IF NOT EXISTS gin_encrypted_fields_meta ON encrypted_fields USING GIN (meta jsonb_path_ops);

-- === encryption_bindings ===
CREATE INDEX IF NOT EXISTS idx_enc_bind_entity ON encryption_bindings (entity_table, entity_pk, created_at);

-- === encryption_events ===
CREATE INDEX IF NOT EXISTS idx_enc_events_entity ON encryption_events (entity_table, entity_pk, created_at);

-- === encryption_policy_bindings ===
CREATE INDEX IF NOT EXISTS idx_enc_pol_bind_entity ON encryption_policy_bindings (entity_table, field_name, effective_from);

-- === entity_external_ids ===
CREATE INDEX IF NOT EXISTS idx_ext_ids_source ON entity_external_ids (source);
CREATE INDEX IF NOT EXISTS idx_ext_ids_external_id ON entity_external_ids (external_id);

-- === event_dlq ===
CREATE INDEX IF NOT EXISTS idx_event_dlq_source_time ON event_dlq (source, last_failed_at);

-- === event_inbox ===
CREATE INDEX IF NOT EXISTS idx_event_inbox_status_received ON event_inbox (status, received_at);
CREATE INDEX IF NOT EXISTS idx_event_inbox_processed ON event_inbox (processed_at);
CREATE INDEX IF NOT EXISTS gin_event_inbox_payload ON event_inbox USING GIN (payload jsonb_path_ops);

-- === event_outbox ===
CREATE INDEX IF NOT EXISTS idx_event_outbox_status_sched ON event_outbox (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_event_outbox_entity_time ON event_outbox (entity_table, entity_pk, created_at);
CREATE INDEX IF NOT EXISTS idx_event_outbox_created_at ON event_outbox (created_at);
CREATE INDEX IF NOT EXISTS gin_event_outbox_payload ON event_outbox USING GIN (payload jsonb_path_ops);

-- === field_hash_policies ===
CREATE INDEX IF NOT EXISTS idx_fhp_entity_field ON field_hash_policies (entity_table, field_name, effective_from);

-- === global_id_registry ===
CREATE INDEX IF NOT EXISTS idx_gid_table ON global_id_registry (entity_table);
CREATE INDEX IF NOT EXISTS idx_gid_guid ON global_id_registry (guid);

-- === hash_profiles ===
CREATE INDEX IF NOT EXISTS idx_hp_algo_status ON hash_profiles (algo_id, status);

-- === idempotency_keys ===
CREATE INDEX IF NOT EXISTS idx_idemp_payment ON idempotency_keys (payment_id);
CREATE INDEX IF NOT EXISTS idx_idemp_order ON idempotency_keys (order_id);
CREATE INDEX IF NOT EXISTS idx_idemp_created_at ON idempotency_keys (created_at);
CREATE INDEX IF NOT EXISTS idx_idemp_tenant_payment ON idempotency_keys (tenant_id, payment_id);
CREATE INDEX IF NOT EXISTS idx_idemp_tenant_order   ON idempotency_keys (tenant_id, order_id);

-- === inventory_reservations ===
CREATE INDEX IF NOT EXISTS idx_res_book ON inventory_reservations (book_id);
CREATE INDEX IF NOT EXISTS idx_res_order ON inventory_reservations (order_id);
CREATE INDEX IF NOT EXISTS idx_res_status_until ON inventory_reservations (status, reserved_until);
CREATE INDEX IF NOT EXISTS idx_res_tenant_status_until ON inventory_reservations (tenant_id, status, reserved_until);

-- === invoice_items ===
CREATE INDEX IF NOT EXISTS idx_invoice_items_tenant_invoice ON invoice_items (tenant_id, invoice_id);

-- === invoices ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_tenant_no ON invoices (tenant_id, invoice_number);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_order ON invoices (tenant_id, order_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_tenant_id ON invoices (tenant_id, id);

-- === jwt_tokens ===
CREATE INDEX IF NOT EXISTS idx_jwt_user ON jwt_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_jwt_expires ON jwt_tokens (expires_at);
CREATE INDEX IF NOT EXISTS idx_jwt_revoked_user ON jwt_tokens (revoked, user_id);
CREATE INDEX IF NOT EXISTS idx_jwt_last_used ON jwt_tokens (last_used_at);
CREATE INDEX IF NOT EXISTS idx_jwt_replaced_by ON jwt_tokens (replaced_by);
CREATE INDEX IF NOT EXISTS idx_jwt_active_sweep ON jwt_tokens (revoked, expires_at);

-- === key_events ===
CREATE INDEX IF NOT EXISTS idx_key_events_key_created ON key_events (key_id, created_at);
CREATE INDEX IF NOT EXISTS idx_key_events_basename ON key_events (basename);

-- === key_rotation_jobs ===
CREATE INDEX IF NOT EXISTS idx_key_rotation_jobs_basename_sched ON key_rotation_jobs (basename, scheduled_at);

-- === key_wrapper_layers ===
CREATE INDEX IF NOT EXISTS idx_kwl_kw ON key_wrapper_layers (key_wrapper_id);
CREATE INDEX IF NOT EXISTS idx_kwl_algo ON key_wrapper_layers (kem_algo_id);

-- === key_wrappers ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_kw_k1_k2_version ON key_wrappers (kms1_key_id, kms2_key_id, wrap_version);
CREATE INDEX IF NOT EXISTS idx_kw_status_created ON key_wrappers (status, created_at);

-- === kms_health_checks ===
CREATE INDEX IF NOT EXISTS idx_kms_hc_provider_time ON kms_health_checks (provider_id, checked_at);
CREATE INDEX IF NOT EXISTS idx_kms_hc_key_time ON kms_health_checks (kms_key_id, checked_at);

-- === kms_keys ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_kms_keys_provider_ref ON kms_keys (provider_id, external_key_ref);

-- === kms_providers ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_kms_providers_name ON kms_providers (name);

-- === kms_routing_policies ===
CREATE INDEX IF NOT EXISTS idx_kms_route_active ON kms_routing_policies (active, priority DESC);

-- === login_attempts ===
CREATE INDEX IF NOT EXISTS idx_login_ip_success_time ON login_attempts (ip_hash, success, attempted_at);
CREATE INDEX IF NOT EXISTS idx_login_attempted_at ON login_attempts (attempted_at);
CREATE INDEX IF NOT EXISTS idx_login_username_hash ON login_attempts (username_hash);
CREATE INDEX IF NOT EXISTS idx_login_user_time ON login_attempts (user_id, attempted_at);

-- === merkle_anchors ===
CREATE INDEX IF NOT EXISTS idx_merkle_anchors_mrid ON merkle_anchors (merkle_root_id);

-- === merkle_roots ===
CREATE INDEX IF NOT EXISTS idx_merkle_subject ON merkle_roots (subject_table);
CREATE INDEX IF NOT EXISTS idx_merkle_created ON merkle_roots (created_at);

-- === migration_events ===
CREATE INDEX IF NOT EXISTS idx_mig_system_status ON migration_events (system_name, status);
CREATE INDEX IF NOT EXISTS idx_mig_started ON migration_events (started_at);

-- === newsletter_subscribers ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_ns_tenant_email_hash ON newsletter_subscribers (tenant_id, email_hash);
CREATE INDEX IF NOT EXISTS idx_ns_tenant ON newsletter_subscribers (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ns_confirm_selector ON newsletter_subscribers (confirm_selector);
CREATE INDEX IF NOT EXISTS idx_ns_user ON newsletter_subscribers (user_id);
CREATE INDEX IF NOT EXISTS idx_ns_confirm_expires ON newsletter_subscribers (confirm_expires);
CREATE INDEX IF NOT EXISTS idx_ns_unsubscribed_at ON newsletter_subscribers (unsubscribed_at);
CREATE INDEX IF NOT EXISTS idx_ns_confirmed_at ON newsletter_subscribers (confirmed_at);

-- === notifications ===
CREATE INDEX IF NOT EXISTS idx_notifications_status_scheduled ON notifications (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_notifications_next_attempt ON notifications (next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_notifications_locked_until_active ON notifications (locked_until) WHERE status IN ('pending','processing');
CREATE INDEX IF NOT EXISTS gin_notifications_payload ON notifications USING GIN (payload jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_notifications_tenant_status_sched ON notifications (tenant_id, status, scheduled_at);

-- === order_item_downloads ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_oid_tenant_triplet ON order_item_downloads (tenant_id, order_id, book_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_oid_tenant_expires_active ON order_item_downloads (tenant_id, expires_at) WHERE used < max_uses;
CREATE INDEX IF NOT EXISTS idx_oid_download_token_hash ON order_item_downloads (download_token_hash);

-- === order_items ===
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_book_id ON order_items (book_id);
CREATE INDEX IF NOT EXISTS idx_order_items_tenant_order ON order_items (tenant_id, order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_tenant_book  ON order_items (tenant_id, book_id);

-- === orders ===
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders (user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_orders_user_created ON orders (user_id, created_at);
CREATE INDEX IF NOT EXISTS gin_orders_metadata      ON orders USING GIN (metadata jsonb_path_ops);
CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_tenant_uuid_bin ON orders (tenant_id, uuid_bin) WHERE uuid_bin IS NOT NULL AND length(uuid_bin) = 16;
CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_tenant_public_no ON orders (tenant_id, public_order_no) WHERE public_order_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_tenant ON orders (tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_tenant_user_created ON orders (tenant_id, user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_tenant_id ON orders (tenant_id, id);

-- === payment_gateway_notifications ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_pg_notify_tenant_tx ON payment_gateway_notifications (tenant_id, transaction_id);
CREATE INDEX IF NOT EXISTS idx_pg_notify_tenant_status_received ON payment_gateway_notifications (tenant_id, status, received_at);

-- === payment_logs ===
CREATE INDEX IF NOT EXISTS idx_payment_logs_payment ON payment_logs (payment_id, log_at DESC);

-- === payment_webhooks ===
CREATE INDEX IF NOT EXISTS idx_payment_webhooks_payment ON payment_webhooks (payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_webhooks_gw_id ON payment_webhooks (gateway_event_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_webhooks_payload ON payment_webhooks (payload_hash);

-- === payments ===
CREATE INDEX IF NOT EXISTS idx_payments_order ON payments (order_id);
CREATE INDEX IF NOT EXISTS idx_payments_provider_event ON payments (provider_event_id);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments (created_at);
CREATE INDEX IF NOT EXISTS gin_payments_details     ON payments      USING GIN (details jsonb_path_ops);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_tenant_tx ON payments (tenant_id, transaction_id);
CREATE INDEX IF NOT EXISTS idx_payments_tenant_order ON payments (tenant_id, order_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_tenant_id ON payments (tenant_id, id);

-- === peer_nodes ===
CREATE INDEX IF NOT EXISTS idx_peer_nodes_status ON peer_nodes (status);
CREATE INDEX IF NOT EXISTS idx_peer_nodes_last_seen ON peer_nodes (last_seen);

-- === pq_migration_jobs ===
CREATE INDEX IF NOT EXISTS idx_pq_mig_status_sched ON pq_migration_jobs (status, scheduled_at);

-- === privacy_requests ===
CREATE INDEX IF NOT EXISTS idx_pr_user ON privacy_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_pr_type_status ON privacy_requests (type, status);

-- === rate_limit_counters ===
CREATE INDEX IF NOT EXISTS idx_rlc_window ON rate_limit_counters (name, window_start);
CREATE INDEX IF NOT EXISTS idx_rlc_subject ON rate_limit_counters (subject_type, subject_id);

-- === rate_limits ===
CREATE INDEX IF NOT EXISTS idx_rate_limits_active ON rate_limits (active);

-- === rbac_repositories ===
CREATE INDEX IF NOT EXISTS idx_rbac_repos_status ON rbac_repositories (status);

-- === rbac_roles ===
CREATE INDEX IF NOT EXISTS idx_rbac_roles_repo ON rbac_roles (repo_id);
CREATE INDEX IF NOT EXISTS idx_rbac_roles_status ON rbac_roles (status);

-- === rbac_user_permissions ===
CREATE INDEX IF NOT EXISTS idx_rbac_up_user ON rbac_user_permissions (user_id);
CREATE INDEX IF NOT EXISTS idx_rbac_up_perm ON rbac_user_permissions (permission_id);

-- === rbac_user_roles ===
CREATE INDEX IF NOT EXISTS idx_rbac_user_roles_user ON rbac_user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_rbac_user_roles_role ON rbac_user_roles (role_id);
CREATE INDEX IF NOT EXISTS idx_rbac_user_roles_tenant ON rbac_user_roles (tenant_id);

-- === refunds ===
CREATE INDEX IF NOT EXISTS idx_refunds_payment ON refunds (payment_id);
CREATE INDEX IF NOT EXISTS idx_refunds_tenant_payment ON refunds (tenant_id, payment_id);

-- === register_events ===
CREATE INDEX IF NOT EXISTS idx_reg_user ON register_events (user_id);
CREATE INDEX IF NOT EXISTS idx_reg_time ON register_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_reg_type_time ON register_events (type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_reg_ip ON register_events (ip_hash);

-- === replication_lag_samples ===
CREATE INDEX IF NOT EXISTS idx_lag_peer_time ON replication_lag_samples (peer_id, captured_at);

-- === retention_enforcement_jobs ===
CREATE INDEX IF NOT EXISTS idx_rej_status_sched ON retention_enforcement_jobs (status, scheduled_at);

-- === reviews ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_reviews_tenant_book_user ON reviews (tenant_id, book_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_tenant_book ON reviews (tenant_id, book_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews (created_at);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews (user_id);

-- === rewrap_jobs ===
CREATE INDEX IF NOT EXISTS idx_rewrap_status_sched ON rewrap_jobs (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_rewrap_kw ON rewrap_jobs (key_wrapper_id);

-- === session_audit ===
CREATE INDEX IF NOT EXISTS idx_session_audit_token_hash ON session_audit (session_token_hash);
CREATE INDEX IF NOT EXISTS idx_session_audit_session_id ON session_audit (session_id);
CREATE INDEX IF NOT EXISTS idx_session_audit_user_id ON session_audit (user_id);
CREATE INDEX IF NOT EXISTS idx_session_audit_created_at ON session_audit (created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_event ON session_audit (event);
CREATE INDEX IF NOT EXISTS idx_session_audit_ip_hash ON session_audit (ip_hash);
CREATE INDEX IF NOT EXISTS idx_session_audit_event_time ON session_audit (event, created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_user_event_time ON session_audit (user_id, event, created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_token_time ON session_audit (session_token_hash, created_at);
CREATE INDEX IF NOT EXISTS gin_session_audit_meta ON session_audit USING GIN (meta_json jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_session_audit_event_user_time ON session_audit (event, user_id, created_at DESC);

-- === sessions ===
CREATE INDEX IF NOT EXISTS idx_sessions_user_created ON sessions (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_last_seen ON sessions (last_seen_at);
CREATE INDEX IF NOT EXISTS idx_sessions_token_hash_key ON sessions (token_hash_key_version);
CREATE INDEX IF NOT EXISTS idx_sessions_created_at ON sessions (created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions (revoked, expires_at, user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_revoked_seen ON sessions (user_id, revoked, last_seen_at DESC);

-- === schema_registry ===
CREATE INDEX IF NOT EXISTS idx_schema_component ON schema_registry (system_name, component);

-- === signatures ===
CREATE INDEX IF NOT EXISTS idx_sigs_subject ON signatures (subject_table, subject_pk, context, created_at);

-- === signing_keys ===
CREATE INDEX IF NOT EXISTS idx_sk_algo_status ON signing_keys (algo_id, status);

-- === slo_status ===
CREATE INDEX IF NOT EXISTS idx_slo_status_window ON slo_status (window_id, computed_at);

-- === sync_batch_items ===
CREATE INDEX IF NOT EXISTS idx_sbi_batch ON sync_batch_items (batch_id);
CREATE INDEX IF NOT EXISTS idx_sbi_status ON sync_batch_items (status);

-- === sync_batches ===
CREATE INDEX IF NOT EXISTS idx_sync_batches_status ON sync_batches (status);
CREATE INDEX IF NOT EXISTS idx_sync_batches_created ON sync_batches (created_at);

-- === sync_errors ===
CREATE INDEX IF NOT EXISTS idx_sync_errors_peer ON sync_errors (peer_id);
CREATE INDEX IF NOT EXISTS idx_sync_errors_created ON sync_errors (created_at);

-- === system_errors ===
CREATE INDEX IF NOT EXISTS idx_err_level ON system_errors (level);
CREATE INDEX IF NOT EXISTS idx_err_time ON system_errors (created_at);
CREATE INDEX IF NOT EXISTS idx_err_user ON system_errors (user_id);
CREATE INDEX IF NOT EXISTS idx_err_ip ON system_errors (ip_hash);
CREATE INDEX IF NOT EXISTS idx_err_resolved ON system_errors (resolved);
CREATE INDEX IF NOT EXISTS idx_system_errors_last_seen ON system_errors (last_seen);
CREATE INDEX IF NOT EXISTS gin_system_errors_ctx    ON system_errors USING GIN (context jsonb_path_ops);

-- === system_jobs ===
CREATE INDEX IF NOT EXISTS idx_system_jobs_status_sched ON system_jobs (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_system_jobs_locked_until ON system_jobs (locked_until) WHERE status = 'processing';
CREATE UNIQUE INDEX IF NOT EXISTS ux_system_jobs_unique_key_live ON system_jobs (unique_key_hash) WHERE unique_key_hash IS NOT NULL AND status IN ('pending','processing');

-- === tax_rates ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_rates_country_cat_from ON tax_rates (country_iso2, category, valid_from);

-- === tenant_domains ===
CREATE INDEX IF NOT EXISTS idx_tenant_domains_tenant ON tenant_domains (tenant_id);

-- === tenants ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_tenants_slug_live_ci ON tenants (slug_ci) WHERE deleted_at IS NULL;

-- === user_consents ===
CREATE INDEX IF NOT EXISTS idx_user_consents_user ON user_consents (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_user_consents ON user_consents (user_id, consent_type, version);

-- === user_identities ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_provider_user ON user_identities (provider, provider_user_id);
CREATE INDEX IF NOT EXISTS idx_user_identities_user ON user_identities (user_id);

-- === users ===
CREATE INDEX IF NOT EXISTS idx_users_last_login_at ON users (last_login_at);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users (is_active);
CREATE INDEX IF NOT EXISTS idx_users_actor_role ON users (actor_role);
CREATE INDEX IF NOT EXISTS idx_users_last_login_ip_hash ON users (last_login_ip_hash);
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email_hash_live ON users (email_hash) WHERE deleted_at IS NULL;

-- === verify_events ===
CREATE INDEX IF NOT EXISTS idx_ver_user ON verify_events (user_id);
CREATE INDEX IF NOT EXISTS idx_ver_time ON verify_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_ver_type_time ON verify_events (type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_ver_ip ON verify_events (ip_hash);

-- === webhook_outbox ===
CREATE INDEX IF NOT EXISTS idx_webhook_status_scheduled ON webhook_outbox (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_webhook_created_at ON webhook_outbox (created_at);

-- === worker_locks ===
CREATE INDEX IF NOT EXISTS idx_worker_locks_until ON worker_locks (locked_until);


