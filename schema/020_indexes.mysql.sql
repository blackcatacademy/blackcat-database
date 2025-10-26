-- === audit_log ===
CREATE INDEX idx_audit_table_record ON audit_log (table_name, record_id, changed_at);
CREATE INDEX idx_audit_changed_at   ON audit_log (changed_at);
CREATE INDEX idx_audit_request_id   ON audit_log (request_id);

-- === book_assets ===
CREATE UNIQUE INDEX ux_book_assets_unique ON book_assets (book_id, asset_type);

-- === cart_items ===
CREATE UNIQUE INDEX ux_cart_items ON cart_items (cart_id, book_id, sku);

-- === coupon_redemptions ===
CREATE INDEX idx_cr_coupon ON coupon_redemptions (coupon_id);
CREATE INDEX idx_cr_user   ON coupon_redemptions (user_id);
CREATE INDEX idx_cr_order  ON coupon_redemptions (order_id);

-- === encrypted_fields ===
CREATE INDEX idx_encrypted_fields_field ON encrypted_fields (field_name);

-- === inventory_reservations ===
CREATE INDEX idx_inventory_reservations_order ON inventory_reservations (order_id);

-- === jwt_tokens ===
CREATE INDEX idx_jwt_replaced_by ON jwt_tokens (replaced_by);

-- === key_events ===
CREATE INDEX idx_key_events_basename ON key_events (basename);

-- === kms_keys ===
CREATE UNIQUE INDEX ux_kms_keys_provider_ref ON kms_keys (provider_id, external_key_ref);

-- === kms_providers ===
CREATE UNIQUE INDEX ux_kms_providers_name ON kms_providers (name);

-- === order_item_downloads ===
CREATE UNIQUE INDEX ux_oid_triplet ON order_item_downloads (order_id, book_id, asset_id);

-- === orders ===
CREATE INDEX idx_orders_created_at ON orders (created_at);
CREATE INDEX idx_orders_user_created ON orders (user_id, created_at);

-- === payment_webhooks ===
CREATE UNIQUE INDEX ux_payment_webhooks_payload ON payment_webhooks (payload_hash);

-- === payments ===
CREATE INDEX idx_payments_created_at ON payments (created_at);

-- === refunds ===
CREATE INDEX idx_refunds_payment ON refunds (payment_id);

-- === reviews ===
CREATE UNIQUE INDEX ux_reviews_book_user ON reviews (book_id, user_id);
CREATE INDEX idx_reviews_user_id ON reviews (user_id);

-- === sessions ===
CREATE INDEX idx_sessions_created_at ON sessions (created_at);

-- === system_errors ===
CREATE INDEX idx_system_errors_last_seen ON system_errors (last_seen);

-- === tax_rates ===
CREATE UNIQUE INDEX ux_tax_rates_country_cat_from ON tax_rates (country_iso2, category, valid_from);

-- === user_consents ===
CREATE INDEX idx_user_consents_user ON user_consents (user_id);
CREATE UNIQUE INDEX ux_user_consents ON user_consents (user_id, consent_type, version);

-- === users ===
CREATE UNIQUE INDEX ux_users_email_hash ON users (email_hash);


