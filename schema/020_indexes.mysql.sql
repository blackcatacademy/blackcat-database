-- === encrypted_fields ===
CREATE INDEX idx_encrypted_fields_field ON encrypted_fields (field_name);

-- === inventory_reservations ===
CREATE INDEX idx_inventory_reservations_order ON inventory_reservations (order_id);

-- === key_events ===
CREATE INDEX idx_key_events_basename ON key_events (basename);

-- === orders ===
CREATE INDEX idx_orders_created_at ON orders (created_at);

-- === payments ===
CREATE INDEX idx_payments_created_at ON payments (created_at);

-- === sessions ===
CREATE INDEX idx_sessions_created_at ON sessions (created_at);

-- === system_errors ===
CREATE INDEX idx_system_errors_last_seen ON system_errors (last_seen);

-- === user_consents ===
CREATE INDEX idx_user_consents_user ON user_consents (user_id);

-- === users ===
CREATE UNIQUE INDEX ux_users_email_hash ON users (email_hash);


