-- === app_settings ===
ALTER TABLE app_settings ADD CONSTRAINT fk_app_settings_user FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

-- === audit_log ===
ALTER TABLE audit_log ADD CONSTRAINT fk_audit_log_user FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL;

-- === auth_events ===
ALTER TABLE auth_events ADD CONSTRAINT fk_auth_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === book_assets ===
ALTER TABLE book_assets ADD CONSTRAINT fk_book_assets_key FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL;
ALTER TABLE book_assets ADD CONSTRAINT fk_book_assets_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;

-- === book_categories ===
ALTER TABLE book_categories ADD CONSTRAINT fk_book_categories_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;
ALTER TABLE book_categories ADD CONSTRAINT fk_book_categories_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE;

-- === books ===
ALTER TABLE books ADD CONSTRAINT fk_books_author FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE RESTRICT;
ALTER TABLE books ADD CONSTRAINT fk_books_category FOREIGN KEY (main_category_id) REFERENCES categories(id) ON DELETE RESTRICT;

-- === cart_items ===
ALTER TABLE cart_items ADD CONSTRAINT fk_cart_items_cart FOREIGN KEY (cart_id) REFERENCES carts(id) ON DELETE CASCADE;
ALTER TABLE cart_items ADD CONSTRAINT fk_cart_items_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;

-- === carts ===
ALTER TABLE carts ADD CONSTRAINT fk_carts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === categories ===
ALTER TABLE categories ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL;

-- === coupon_redemptions ===
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_coupon FOREIGN KEY (coupon_id) REFERENCES coupons(id) ON DELETE CASCADE;
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;

-- === crypto_keys ===
ALTER TABLE crypto_keys ADD CONSTRAINT fk_keys_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE crypto_keys ADD CONSTRAINT fk_keys_replaced_by FOREIGN KEY (replaced_by) REFERENCES crypto_keys(id) ON DELETE SET NULL;

-- === email_verifications ===
ALTER TABLE email_verifications ADD CONSTRAINT fk_ev_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === idempotency_keys ===
ALTER TABLE idempotency_keys ADD CONSTRAINT fk_idemp_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE SET NULL;

-- === inventory_reservations ===
ALTER TABLE inventory_reservations ADD CONSTRAINT fk_res_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;

-- === invoice_items ===
ALTER TABLE invoice_items ADD CONSTRAINT fk_invoice_items_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE;

-- === invoices ===
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;

-- === jwt_tokens ===
ALTER TABLE jwt_tokens ADD CONSTRAINT fk_jwt_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE jwt_tokens ADD CONSTRAINT fk_jwt_tokens_replaced_by FOREIGN KEY (replaced_by) REFERENCES jwt_tokens(id) ON DELETE SET NULL;

-- === key_events ===
ALTER TABLE key_events ADD CONSTRAINT fk_key_events_key FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL;
ALTER TABLE key_events ADD CONSTRAINT fk_key_events_actor FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL;

-- === key_rotation_jobs ===
ALTER TABLE key_rotation_jobs ADD CONSTRAINT fk_key_rotation_jobs_user FOREIGN KEY (executed_by) REFERENCES users(id) ON DELETE SET NULL;

-- === key_usage ===
ALTER TABLE key_usage ADD CONSTRAINT fk_key_usage_key FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE;

-- === kms_keys ===
ALTER TABLE kms_keys ADD CONSTRAINT fk_kms_keys_provider FOREIGN KEY (provider_id) REFERENCES kms_providers(id) ON DELETE CASCADE;

-- === login_attempts ===
ALTER TABLE login_attempts ADD CONSTRAINT fk_login_attempts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE login_attempts ADD CONSTRAINT fk_login_attempts_auth_event FOREIGN KEY (auth_event_id) REFERENCES auth_events(id) ON DELETE SET NULL;

-- === newsletter_subscribers ===
ALTER TABLE newsletter_subscribers ADD CONSTRAINT fk_ns_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === notifications ===
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === order_item_downloads ===
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_asset FOREIGN KEY (asset_id) REFERENCES book_assets(id) ON DELETE CASCADE;

-- === order_items ===
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE SET NULL;

-- === orders ===
ALTER TABLE orders ADD CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === payment_gateway_notifications ===
ALTER TABLE payment_gateway_notifications ADD CONSTRAINT fk_pg_notify_payment FOREIGN KEY (transaction_id) REFERENCES payments(transaction_id) ON DELETE CASCADE;

-- === payment_logs ===
ALTER TABLE payment_logs ADD CONSTRAINT fk_payment_logs_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE;

-- === payment_webhooks ===
ALTER TABLE payment_webhooks ADD CONSTRAINT fk_payment_webhooks_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE SET NULL;

-- === payments ===
ALTER TABLE payments ADD CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;

-- === policy_kms_keys ===
ALTER TABLE policy_kms_keys ADD CONSTRAINT fk_policy_kms_keys_policy FOREIGN KEY (policy_id) REFERENCES encryption_policies(id) ON DELETE CASCADE;
ALTER TABLE policy_kms_keys ADD CONSTRAINT fk_policy_kms_keys_key FOREIGN KEY (kms_key_id) REFERENCES kms_keys(id) ON DELETE CASCADE;

-- === refunds ===
ALTER TABLE refunds ADD CONSTRAINT fk_refunds_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE;

-- === register_events ===
ALTER TABLE register_events ADD CONSTRAINT fk_register_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === reviews ===
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_book FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE;
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === session_audit ===
ALTER TABLE session_audit ADD CONSTRAINT fk_session_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === sessions ===
ALTER TABLE sessions ADD CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === system_errors ===
ALTER TABLE system_errors ADD CONSTRAINT fk_err_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE system_errors ADD CONSTRAINT fk_err_resolved_by FOREIGN KEY (resolved_by) REFERENCES users(id) ON DELETE SET NULL;

-- === tax_rates ===
ALTER TABLE tax_rates ADD CONSTRAINT fk_tax_rates_country FOREIGN KEY (country_iso2) REFERENCES countries(iso2) ON DELETE CASCADE;

-- === two_factor ===
ALTER TABLE two_factor ADD CONSTRAINT fk_two_factor_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === user_consents ===
ALTER TABLE user_consents ADD CONSTRAINT fk_user_consents_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === user_identities ===
ALTER TABLE user_identities ADD CONSTRAINT fk_user_identities_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === user_profiles ===
ALTER TABLE user_profiles ADD CONSTRAINT fk_user_profiles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === vat_validations ===
ALTER TABLE vat_validations ADD CONSTRAINT fk_vat_validations_country FOREIGN KEY (country_iso2) REFERENCES countries(iso2) ON DELETE CASCADE;

-- === verify_events ===
ALTER TABLE verify_events ADD CONSTRAINT fk_verify_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;


