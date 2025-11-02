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

-- === authors ===
CREATE INDEX IF NOT EXISTS idx_authors_avg_rating ON authors (avg_rating);
CREATE INDEX IF NOT EXISTS idx_authors_books_count ON authors (books_count);

-- === book_assets ===
CREATE INDEX IF NOT EXISTS idx_book_assets_book ON book_assets (book_id);
CREATE INDEX IF NOT EXISTS idx_book_assets_type ON book_assets (asset_type);
CREATE UNIQUE INDEX IF NOT EXISTS ux_book_assets_unique ON book_assets (book_id, asset_type);

-- === book_categories ===
CREATE INDEX IF NOT EXISTS idx_book_categories_category ON book_categories (category_id);

-- === books ===
CREATE INDEX IF NOT EXISTS idx_books_author_id ON books (author_id);
CREATE INDEX IF NOT EXISTS idx_books_main_category_id ON books (main_category_id);
CREATE INDEX IF NOT EXISTS idx_books_sku ON books (sku);

-- === cart_items ===
CREATE INDEX IF NOT EXISTS idx_cart_items_cart_id ON cart_items (cart_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_cart_items ON cart_items (cart_id, book_id, sku);

-- === categories ===
CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories (parent_id);

-- === coupon_redemptions ===
CREATE INDEX IF NOT EXISTS idx_cr_coupon ON coupon_redemptions (coupon_id);
CREATE INDEX IF NOT EXISTS idx_cr_user   ON coupon_redemptions (user_id);
CREATE INDEX IF NOT EXISTS idx_cr_order  ON coupon_redemptions (order_id);

-- === email_verifications ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_ev_selector ON email_verifications (selector);
CREATE INDEX IF NOT EXISTS idx_ev_user ON email_verifications (user_id);
CREATE INDEX IF NOT EXISTS idx_ev_expires ON email_verifications (expires_at);

-- === encrypted_fields ===
CREATE INDEX IF NOT EXISTS idx_enc_entity ON encrypted_fields (entity_table, entity_pk);
CREATE INDEX IF NOT EXISTS idx_encrypted_fields_field ON encrypted_fields (field_name);

-- === encryption_events ===
CREATE INDEX IF NOT EXISTS idx_enc_events_entity ON encryption_events (entity_table, entity_pk, created_at);

-- === idempotency_keys ===
CREATE INDEX IF NOT EXISTS idx_idemp_payment ON idempotency_keys (payment_id);
CREATE INDEX IF NOT EXISTS idx_idemp_order ON idempotency_keys (order_id);
CREATE INDEX IF NOT EXISTS idx_idemp_created_at ON idempotency_keys (created_at);

-- === inventory_reservations ===
CREATE INDEX IF NOT EXISTS idx_res_book ON inventory_reservations (book_id);
CREATE INDEX IF NOT EXISTS idx_res_order ON inventory_reservations (order_id);
CREATE INDEX IF NOT EXISTS idx_res_status_until ON inventory_reservations (status, reserved_until);

-- === jwt_tokens ===
CREATE INDEX IF NOT EXISTS idx_jwt_user ON jwt_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_jwt_expires ON jwt_tokens (expires_at);
CREATE INDEX IF NOT EXISTS idx_jwt_revoked_user ON jwt_tokens (revoked, user_id);
CREATE INDEX IF NOT EXISTS idx_jwt_last_used ON jwt_tokens (last_used_at);
CREATE INDEX IF NOT EXISTS idx_jwt_replaced_by ON jwt_tokens (replaced_by);

-- === key_events ===
CREATE INDEX IF NOT EXISTS idx_key_events_key_created ON key_events (key_id, created_at);
CREATE INDEX IF NOT EXISTS idx_key_events_basename ON key_events (basename);

-- === key_rotation_jobs ===
CREATE INDEX IF NOT EXISTS idx_key_rotation_jobs_basename_sched ON key_rotation_jobs (basename, scheduled_at);

-- === kms_keys ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_kms_keys_provider_ref ON kms_keys (provider_id, external_key_ref);

-- === kms_providers ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_kms_providers_name ON kms_providers (name);

-- === login_attempts ===
CREATE INDEX IF NOT EXISTS idx_login_ip_success_time ON login_attempts (ip_hash, success, attempted_at);
CREATE INDEX IF NOT EXISTS idx_login_attempted_at ON login_attempts (attempted_at);
CREATE INDEX IF NOT EXISTS idx_login_username_hash ON login_attempts (username_hash);
CREATE INDEX IF NOT EXISTS idx_login_user_time ON login_attempts (user_id, attempted_at);

-- === newsletter_subscribers ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_ns_email_hash ON newsletter_subscribers (email_hash);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ns_confirm_selector ON newsletter_subscribers (confirm_selector);
CREATE INDEX IF NOT EXISTS idx_ns_user ON newsletter_subscribers (user_id);
CREATE INDEX IF NOT EXISTS idx_ns_confirm_expires ON newsletter_subscribers (confirm_expires);
CREATE INDEX IF NOT EXISTS idx_ns_unsubscribed_at ON newsletter_subscribers (unsubscribed_at);

-- === notifications ===
CREATE INDEX IF NOT EXISTS idx_notifications_status_scheduled ON notifications (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_notifications_next_attempt ON notifications (next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_notifications_locked_until ON notifications (locked_until);

-- === order_item_downloads ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_oid_triplet ON order_item_downloads (order_id, book_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_oid_download_token_hash ON order_item_downloads (download_token_hash);

-- === order_items ===
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_book_id ON order_items (book_id);

-- === orders ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_orders_uuid_bin ON orders (uuid_bin) WHERE uuid_bin IS NOT NULL AND length(uuid_bin) = 16;
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders (user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_orders_user_created ON orders (user_id, created_at);

-- === payment_gateway_notifications ===
CREATE INDEX IF NOT EXISTS idx_pg_notify_status_received ON payment_gateway_notifications (status, received_at);

-- === payment_webhooks ===
CREATE INDEX IF NOT EXISTS idx_payment_webhooks_payment ON payment_webhooks (payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_webhooks_gw_id ON payment_webhooks (gateway_event_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_webhooks_payload ON payment_webhooks (payload_hash);

-- === payments ===
CREATE INDEX IF NOT EXISTS idx_payments_order ON payments (order_id);
CREATE INDEX IF NOT EXISTS idx_payments_provider_event ON payments (provider_event_id);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments (created_at);

-- === refunds ===
CREATE INDEX IF NOT EXISTS idx_refunds_payment ON refunds (payment_id);

-- === register_events ===
CREATE INDEX IF NOT EXISTS idx_reg_user ON register_events (user_id);
CREATE INDEX IF NOT EXISTS idx_reg_time ON register_events (occurred_at);
CREATE INDEX IF NOT EXISTS idx_reg_type_time ON register_events (type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_reg_ip ON register_events (ip_hash);

-- === reviews ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_reviews_book_user ON reviews (book_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_book_id ON reviews (book_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON reviews (created_at);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews (user_id);

-- === session_audit ===
CREATE INDEX IF NOT EXISTS idx_session_audit_token ON session_audit (session_token);
CREATE INDEX IF NOT EXISTS idx_session_audit_session_id ON session_audit (session_id);
CREATE INDEX IF NOT EXISTS idx_session_audit_user_id ON session_audit (user_id);
CREATE INDEX IF NOT EXISTS idx_session_audit_created_at ON session_audit (created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_event ON session_audit (event);
CREATE INDEX IF NOT EXISTS idx_session_audit_ip_hash ON session_audit (ip_hash);
CREATE INDEX IF NOT EXISTS idx_session_audit_ip_key ON session_audit (ip_hash_key_version);
CREATE INDEX IF NOT EXISTS idx_session_audit_event_time ON session_audit (event, created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_user_event_time ON session_audit (user_id, event, created_at);
CREATE INDEX IF NOT EXISTS idx_session_audit_token_time ON session_audit (session_token, created_at);

-- === sessions ===
CREATE INDEX IF NOT EXISTS idx_sessions_user_created ON sessions (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_last_seen ON sessions (last_seen_at);
CREATE INDEX IF NOT EXISTS idx_sessions_token_hash_key ON sessions (token_hash_key_version);
CREATE INDEX IF NOT EXISTS idx_sessions_created_at ON sessions (created_at);

-- === system_errors ===
CREATE INDEX IF NOT EXISTS idx_err_level ON system_errors (level);
CREATE INDEX IF NOT EXISTS idx_err_time ON system_errors (created_at);
CREATE INDEX IF NOT EXISTS idx_err_user ON system_errors (user_id);
CREATE INDEX IF NOT EXISTS idx_err_ip ON system_errors (ip_hash);
CREATE INDEX IF NOT EXISTS idx_err_resolved ON system_errors (resolved);
CREATE INDEX IF NOT EXISTS idx_system_errors_last_seen ON system_errors (last_seen);

-- === system_jobs ===
CREATE INDEX IF NOT EXISTS idx_system_jobs_status_sched ON system_jobs (status, scheduled_at);

-- === tax_rates ===
CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_rates_country_cat_from ON tax_rates (country_iso2, category, valid_from);

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
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email_hash ON users (email_hash);

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


