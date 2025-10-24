-- === auth_events ===
CREATE INDEX idx_auth_meta_email ON auth_events (meta_email);
CREATE INDEX idx_auth_user ON auth_events (user_id);
CREATE INDEX idx_auth_time ON auth_events (occurred_at);
CREATE INDEX idx_auth_type_time ON auth_events (type, occurred_at);
CREATE INDEX idx_auth_ip_hash ON auth_events (ip_hash);

-- === authors ===
CREATE INDEX idx_authors_avg_rating ON authors (avg_rating);
CREATE INDEX idx_authors_books_count ON authors (books_count);

-- === book_assets ===
CREATE INDEX idx_book_assets_book ON book_assets (book_id);
CREATE INDEX idx_book_assets_type ON book_assets (asset_type);

-- === book_categories ===
CREATE INDEX idx_book_categories_category ON book_categories (category_id);

-- === books ===
CREATE INDEX idx_books_author_id ON books (author_id);
CREATE INDEX idx_books_main_category_id ON books (main_category_id);
CREATE INDEX idx_books_sku ON books (sku);

-- === cart_items ===
CREATE INDEX idx_cart_items_cart_id ON cart_items (cart_id);

-- === categories ===
CREATE INDEX idx_categories_parent ON categories (parent_id);

-- === email_verifications ===
CREATE UNIQUE INDEX ux_ev_selector ON email_verifications (selector);
CREATE INDEX idx_ev_user ON email_verifications (user_id);
CREATE INDEX idx_ev_expires ON email_verifications (expires_at);

-- === encrypted_fields ===
CREATE INDEX idx_enc_entity ON encrypted_fields (entity_table, entity_pk);
CREATE INDEX idx_encrypted_fields_field ON encrypted_fields (field_name);

-- === encryption_events ===
CREATE INDEX idx_enc_events_entity ON encryption_events (entity_table, entity_pk, created_at);

-- === idempotency_keys ===
CREATE INDEX idx_idemp_payment ON idempotency_keys (payment_id);
CREATE INDEX idx_idemp_order ON idempotency_keys (order_id);
CREATE INDEX idx_idemp_created_at ON idempotency_keys (created_at);

-- === inventory_reservations ===
CREATE INDEX idx_res_book ON inventory_reservations (book_id);
CREATE INDEX idx_res_order ON inventory_reservations (order_id);
CREATE INDEX idx_res_status_until ON inventory_reservations (status, reserved_until);

-- === jwt_tokens ===
CREATE INDEX idx_jwt_user ON jwt_tokens (user_id);
CREATE INDEX idx_jwt_expires ON jwt_tokens (expires_at);
CREATE INDEX idx_jwt_revoked_user ON jwt_tokens (revoked, user_id);
CREATE INDEX idx_jwt_last_used ON jwt_tokens (last_used_at);

-- === key_events ===
CREATE INDEX idx_key_events_key_created ON key_events (key_id, created_at);
CREATE INDEX idx_key_events_basename ON key_events (basename);

-- === key_rotation_jobs ===
CREATE INDEX idx_key_rotation_jobs_basename_sched ON key_rotation_jobs (basename, scheduled_at);

-- === login_attempts ===
CREATE INDEX idx_login_ip_success_time ON login_attempts (ip_hash, success, attempted_at);
CREATE INDEX idx_login_attempted_at ON login_attempts (attempted_at);
CREATE INDEX idx_login_username_hash ON login_attempts (username_hash);
CREATE INDEX idx_login_user_time ON login_attempts (user_id, attempted_at);

-- === newsletter_subscribers ===
CREATE UNIQUE INDEX ux_ns_email_hash ON newsletter_subscribers (email_hash);
CREATE UNIQUE INDEX ux_ns_confirm_selector ON newsletter_subscribers (confirm_selector);
CREATE INDEX idx_ns_user ON newsletter_subscribers (user_id);
CREATE INDEX idx_ns_confirm_expires ON newsletter_subscribers (confirm_expires);
CREATE INDEX idx_ns_unsubscribed_at ON newsletter_subscribers (unsubscribed_at);

-- === notifications ===
CREATE INDEX idx_notifications_status_scheduled ON notifications (status, scheduled_at);
CREATE INDEX idx_notifications_next_attempt ON notifications (next_attempt_at);
CREATE INDEX idx_notifications_locked_until ON notifications (locked_until);

-- === order_item_downloads ===
CREATE INDEX idx_oid_download_token_hash ON order_item_downloads (download_token_hash);

-- === order_items ===
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_book_id ON order_items (book_id);

-- === orders ===
CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
CREATE INDEX idx_orders_uuid ON orders (uuid);
CREATE INDEX idx_orders_created_at ON orders (created_at);

-- === payment_gateway_notifications ===
CREATE INDEX idx_pg_notify_status_received ON payment_gateway_notifications (status, received_at);

-- === payment_webhooks ===
CREATE INDEX idx_payment_webhooks_payment ON payment_webhooks (payment_id);
CREATE INDEX idx_payment_webhooks_gw_id ON payment_webhooks (gateway_event_id);
CREATE INDEX idx_payment_webhooks_hash ON payment_webhooks (payload_hash);

-- === payments ===
CREATE INDEX idx_payments_order ON payments (order_id);
CREATE INDEX idx_payments_provider_event ON payments (provider_event_id);
CREATE INDEX idx_payments_created_at ON payments (created_at);

-- === register_events ===
CREATE INDEX idx_reg_user ON register_events (user_id);
CREATE INDEX idx_reg_time ON register_events (occurred_at);
CREATE INDEX idx_reg_type_time ON register_events (type, occurred_at);
CREATE INDEX idx_reg_ip ON register_events (ip_hash);

-- === reviews ===
CREATE INDEX idx_reviews_book_id ON reviews (book_id);
CREATE INDEX idx_reviews_created_at ON reviews (created_at);

-- === session_audit ===
CREATE INDEX idx_session_audit_token ON session_audit (session_token);
CREATE INDEX idx_session_audit_session_id ON session_audit (session_id);
CREATE INDEX idx_session_audit_user_id ON session_audit (user_id);
CREATE INDEX idx_session_audit_created_at ON session_audit (created_at);
CREATE INDEX idx_session_audit_event ON session_audit (event);
CREATE INDEX idx_session_audit_ip_hash ON session_audit (ip_hash);
CREATE INDEX idx_session_audit_ip_key ON session_audit (ip_hash_key_version);
CREATE INDEX idx_session_audit_event_time ON session_audit (event, created_at);
CREATE INDEX idx_session_audit_user_event_time ON session_audit (user_id, event, created_at);
CREATE INDEX idx_session_audit_token_time ON session_audit (session_token, created_at);

-- === sessions ===
CREATE INDEX idx_sessions_user_created ON sessions (user_id, created_at);
CREATE INDEX idx_sessions_user ON sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON sessions (expires_at);
CREATE INDEX idx_sessions_last_seen ON sessions (last_seen_at);
CREATE INDEX idx_sessions_token_hash_key ON sessions (token_hash_key_version);
CREATE INDEX idx_sessions_created_at ON sessions (created_at);

-- === system_errors ===
CREATE INDEX idx_err_level ON system_errors (level);
CREATE INDEX idx_err_time ON system_errors (created_at);
CREATE INDEX idx_err_user ON system_errors (user_id);
CREATE INDEX idx_err_ip ON system_errors (ip_hash);
CREATE INDEX idx_err_resolved ON system_errors (resolved);
CREATE INDEX idx_system_errors_last_seen ON system_errors (last_seen);

-- === system_jobs ===
CREATE INDEX idx_system_jobs_status_sched ON system_jobs (status, scheduled_at);

-- === user_consents ===
CREATE INDEX idx_user_consents_user ON user_consents (user_id);

-- === user_identities ===
CREATE UNIQUE INDEX ux_provider_user ON user_identities (provider, provider_user_id);
CREATE INDEX idx_user_identities_user ON user_identities (user_id);

-- === users ===
CREATE INDEX idx_users_last_login_at ON users (last_login_at);
CREATE INDEX idx_users_is_active ON users (is_active);
CREATE INDEX idx_users_actor_role ON users (actor_role);
CREATE INDEX idx_users_last_login_ip_hash ON users (last_login_ip_hash);
CREATE UNIQUE INDEX ux_users_email_hash ON users (email_hash);

-- === verify_events ===
CREATE INDEX idx_ver_user ON verify_events (user_id);
CREATE INDEX idx_ver_time ON verify_events (occurred_at);
CREATE INDEX idx_ver_type_time ON verify_events (type, occurred_at);
CREATE INDEX idx_ver_ip ON verify_events (ip_hash);

-- === webhook_outbox ===
CREATE INDEX idx_webhook_status_scheduled ON webhook_outbox (status, next_attempt_at);
CREATE INDEX idx_webhook_created_at ON webhook_outbox (created_at);

-- === worker_locks ===
CREATE INDEX idx_worker_locks_until ON worker_locks (locked_until);


