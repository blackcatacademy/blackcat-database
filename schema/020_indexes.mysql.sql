-- === api_keys ===
CREATE UNIQUE INDEX ux_api_keys_tenant_name ON api_keys (tenant_id, name_ci);

-- === audit_chain ===
CREATE INDEX idx_audit_chain_name_time ON audit_chain (chain_name, created_at);

-- === audit_log ===
CREATE INDEX idx_audit_table_record ON audit_log (table_name, record_id, changed_at);
CREATE INDEX idx_audit_changed_at   ON audit_log (changed_at);
CREATE INDEX idx_audit_request_id   ON audit_log (request_id);

-- === authors ===
CREATE UNIQUE INDEX ux_authors_tenant_slug_live_ci ON authors (tenant_id, slug_ci, is_live);
CREATE UNIQUE INDEX ux_authors_tenant_id ON authors (tenant_id, id);
CREATE INDEX idx_authors_name_ci ON authors (tenant_id, (LOWER(name)));

-- === book_assets ===
CREATE INDEX idx_book_assets_tenant ON book_assets (tenant_id);
CREATE UNIQUE INDEX ux_book_assets_tenant_unique ON book_assets (tenant_id, book_id, asset_type);
CREATE UNIQUE INDEX ux_book_assets_tenant_id ON book_assets (tenant_id, id);

-- === book_categories ===
CREATE INDEX idx_book_categories_book ON book_categories (book_id);
CREATE INDEX idx_book_categories_tenant ON book_categories (tenant_id);

-- === books ===
CREATE UNIQUE INDEX ux_books_tenant_slug_live_ci ON books (tenant_id, slug_ci, is_live);
CREATE UNIQUE INDEX ux_books_tenant_isbn ON books (tenant_id, isbn);
CREATE UNIQUE INDEX ux_books_tenant_id ON books (tenant_id, id);
CREATE INDEX idx_books_tenant_author ON books (tenant_id, author_id);
CREATE INDEX idx_books_tenant_category ON books (tenant_id, main_category_id);

-- === cart_items ===
CREATE UNIQUE INDEX ux_cart_items ON cart_items (tenant_id, cart_id, book_id, sku);
CREATE INDEX idx_cart_items_tenant_book ON cart_items (tenant_id, book_id);

-- === carts ===
CREATE UNIQUE INDEX ux_carts_tenant_id ON carts (tenant_id, id);
CREATE INDEX idx_carts_tenant ON carts (tenant_id);

-- === categories ===
CREATE UNIQUE INDEX ux_categories_tenant_slug_live_ci ON categories (tenant_id, slug_ci, is_live);
CREATE UNIQUE INDEX ux_categories_tenant_id ON categories (tenant_id, id);
CREATE INDEX idx_categories_tenant_parent ON categories (tenant_id, parent_id);
CREATE INDEX idx_categories_name_ci ON categories (tenant_id, (LOWER(name)));

-- === coupon_redemptions ===
CREATE INDEX idx_cr_coupon ON coupon_redemptions (coupon_id);
CREATE INDEX idx_cr_user   ON coupon_redemptions (user_id);
CREATE INDEX idx_cr_order  ON coupon_redemptions (order_id);
CREATE INDEX idx_cr_tenant_coupon ON coupon_redemptions (tenant_id, coupon_id);
CREATE INDEX idx_cr_tenant_user   ON coupon_redemptions (tenant_id, user_id);
CREATE INDEX idx_cr_tenant_order  ON coupon_redemptions (tenant_id, order_id);
CREATE UNIQUE INDEX ux_cr_tenant_order_coupon ON coupon_redemptions (tenant_id, order_id, coupon_id);

-- === coupons ===
CREATE UNIQUE INDEX ux_coupons_tenant_code_ci ON coupons (tenant_id, code_ci);
CREATE INDEX idx_coupons_tenant_active ON coupons (tenant_id, is_active);
CREATE INDEX idx_coupons_tenant_id ON coupons (tenant_id, id);

-- === crypto_algorithms ===
CREATE INDEX idx_ca_class_status ON crypto_algorithms (class, status);

-- === crypto_standard_aliases ===
CREATE INDEX idx_crypto_alias_algo ON crypto_standard_aliases (algo_id);

-- === device_fingerprints ===
CREATE INDEX idx_df_user_last_seen ON device_fingerprints (user_id, last_seen);

-- === encrypted_fields ===
CREATE INDEX idx_encrypted_fields_field ON encrypted_fields (field_name);

-- === encryption_bindings ===
CREATE INDEX idx_enc_bind_entity ON encryption_bindings (entity_table, entity_pk, created_at);

-- === encryption_policy_bindings ===
CREATE INDEX idx_enc_pol_bind_entity ON encryption_policy_bindings (entity_table, field_name, effective_from);

-- === entity_external_ids ===
CREATE INDEX idx_ext_ids_source ON entity_external_ids (source);
CREATE INDEX idx_ext_ids_external_id ON entity_external_ids (external_id);

-- === event_dlq ===
CREATE INDEX idx_event_dlq_source_time ON event_dlq (source, last_failed_at);

-- === event_inbox ===
CREATE INDEX idx_event_inbox_status_received ON event_inbox (status, received_at);
CREATE INDEX idx_event_inbox_processed ON event_inbox (processed_at);

-- === event_outbox ===
CREATE INDEX idx_event_outbox_status_sched ON event_outbox (status, next_attempt_at);
CREATE INDEX idx_event_outbox_entity_time ON event_outbox (entity_table, entity_pk, created_at);
CREATE INDEX idx_event_outbox_created_at ON event_outbox (created_at);

-- === field_hash_policies ===
CREATE INDEX idx_fhp_entity_field ON field_hash_policies (entity_table, field_name, effective_from);

-- === hash_profiles ===
CREATE INDEX idx_hp_algo_status ON hash_profiles (algo_id, status);

-- === inventory_reservations ===
CREATE INDEX idx_inventory_reservations_order ON inventory_reservations (order_id);
CREATE INDEX idx_res_book_status ON inventory_reservations (book_id, status);
CREATE INDEX idx_res_tenant_status_until ON inventory_reservations (tenant_id, status, reserved_until);

-- === jwt_tokens ===
CREATE INDEX idx_jwt_replaced_by ON jwt_tokens (replaced_by);

-- === key_events ===
CREATE INDEX idx_key_events_basename ON key_events (basename);

-- === key_wrapper_layers ===
CREATE INDEX idx_kwl_kw ON key_wrapper_layers (key_wrapper_id);
CREATE INDEX idx_kwl_algo ON key_wrapper_layers (kem_algo_id);

-- === key_wrappers ===
CREATE UNIQUE INDEX ux_kw_k1_k2_version ON key_wrappers (kms1_key_id, kms2_key_id, wrap_version);
CREATE INDEX idx_kw_status_created ON key_wrappers (status, created_at);

-- === kms_health_checks ===
CREATE INDEX idx_kms_hc_provider_time ON kms_health_checks (provider_id, checked_at);
CREATE INDEX idx_kms_hc_key_time ON kms_health_checks (kms_key_id, checked_at);

-- === kms_keys ===
CREATE UNIQUE INDEX ux_kms_keys_provider_ref ON kms_keys (provider_id, external_key_ref);

-- === kms_providers ===
CREATE UNIQUE INDEX ux_kms_providers_name ON kms_providers (name);

-- === order_item_downloads ===
CREATE UNIQUE INDEX ux_oid_tenant_triplet ON order_item_downloads (tenant_id, order_id, book_id, asset_id);
CREATE INDEX idx_oid_tenant_expires_active ON order_item_downloads (tenant_id, expires_at, is_active);

-- === orders ===
CREATE INDEX idx_orders_created_at ON orders (created_at);
CREATE INDEX idx_orders_user_created ON orders (user_id, created_at);
CREATE INDEX idx_orders_tenant_user_created ON orders (tenant_id, user_id, created_at);

-- === payment_webhooks ===
CREATE UNIQUE INDEX ux_payment_webhooks_payload ON payment_webhooks (payload_hash);

-- === payments ===
CREATE INDEX idx_payments_created_at ON payments (created_at);
CREATE INDEX idx_payments_order_created ON payments (order_id, created_at);

-- === peer_nodes ===
CREATE INDEX idx_peer_nodes_status    ON peer_nodes (status);
CREATE INDEX idx_peer_nodes_last_seen ON peer_nodes (last_seen);

-- === rbac_repositories ===
CREATE INDEX idx_rbac_repos_status ON rbac_repositories (status);

-- === rbac_roles ===
CREATE INDEX idx_rbac_roles_repo ON rbac_roles (repo_id);
CREATE INDEX idx_rbac_roles_status ON rbac_roles (status);

-- === rbac_user_permissions ===
CREATE INDEX idx_rbac_up_user ON rbac_user_permissions (user_id);
CREATE INDEX idx_rbac_up_perm ON rbac_user_permissions (permission_id);

-- === rbac_user_roles ===
CREATE INDEX idx_rbac_user_roles_user ON rbac_user_roles (user_id);
CREATE INDEX idx_rbac_user_roles_role ON rbac_user_roles (role_id);
CREATE INDEX idx_rbac_user_roles_tenant ON rbac_user_roles (tenant_id);

-- === refunds ===
CREATE INDEX idx_refunds_payment ON refunds (payment_id);

-- === reviews ===
CREATE UNIQUE INDEX ux_reviews_tenant_book_user ON reviews (tenant_id, book_id, user_id);
CREATE INDEX idx_reviews_user_id ON reviews (tenant_id, user_id);
CREATE INDEX idx_reviews_tenant_book ON reviews (tenant_id, book_id);

-- === rewrap_jobs ===
CREATE INDEX idx_rewrap_status_sched ON rewrap_jobs (status, scheduled_at);
CREATE INDEX idx_rewrap_kw ON rewrap_jobs (key_wrapper_id);

-- === sessions ===
CREATE INDEX idx_sessions_created_at ON sessions (created_at);

-- === signatures ===
CREATE INDEX idx_sigs_subject ON signatures (subject_table, subject_pk, `context`, created_at);

-- === signing_keys ===
CREATE INDEX idx_sk_algo_status ON signing_keys (algo_id, status);

-- === system_errors ===
CREATE INDEX idx_system_errors_last_seen ON system_errors (last_seen);

-- === tax_rates ===
CREATE UNIQUE INDEX ux_tax_rates_country_cat_from ON tax_rates (country_iso2, category, valid_from);

-- === tenant_domains ===
CREATE INDEX idx_tenant_domains_tenant ON tenant_domains (tenant_id);

-- === tenants ===
CREATE UNIQUE INDEX ux_tenants_slug_live_ci ON tenants (slug_ci, is_live);

-- === user_consents ===
CREATE INDEX idx_user_consents_user ON user_consents (user_id);
CREATE UNIQUE INDEX ux_user_consents ON user_consents (user_id, consent_type, version);

-- === users ===
CREATE UNIQUE INDEX ux_users_email_hash_live ON users (email_hash);


