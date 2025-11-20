-- === api_keys ===
ALTER TABLE api_keys ADD CONSTRAINT fk_api_keys_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id);
ALTER TABLE api_keys ADD CONSTRAINT fk_api_keys_user   FOREIGN KEY (user_id)   REFERENCES users(id);

-- === app_settings ===
ALTER TABLE app_settings ADD CONSTRAINT fk_app_settings_user FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

-- === audit_chain ===
ALTER TABLE audit_chain ADD CONSTRAINT fk_audit_chain_audit FOREIGN KEY (audit_id) REFERENCES audit_log(id) ON DELETE CASCADE;

-- === audit_log ===
ALTER TABLE audit_log ADD CONSTRAINT fk_audit_log_user FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL;

-- === auth_events ===
ALTER TABLE auth_events ADD CONSTRAINT fk_auth_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === authors ===
ALTER TABLE authors ADD CONSTRAINT fk_authors_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === book_assets ===
ALTER TABLE book_assets ADD CONSTRAINT fk_book_assets_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE book_assets ADD CONSTRAINT fk_book_assets_book FOREIGN KEY (tenant_id, book_id) REFERENCES books(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE book_assets ADD CONSTRAINT fk_book_assets_key FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL;

-- === book_categories ===
ALTER TABLE book_categories ADD CONSTRAINT fk_book_categories_book FOREIGN KEY (tenant_id, book_id) REFERENCES books(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE book_categories ADD CONSTRAINT fk_book_categories_category FOREIGN KEY (tenant_id, category_id) REFERENCES categories(tenant_id, id) ON DELETE CASCADE;

-- === books ===
ALTER TABLE books ADD CONSTRAINT fk_books_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE books ADD CONSTRAINT fk_books_author FOREIGN KEY (tenant_id, author_id) REFERENCES authors(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE books ADD CONSTRAINT fk_books_category FOREIGN KEY (tenant_id, main_category_id) REFERENCES categories(tenant_id, id) ON DELETE RESTRICT;

-- === cart_items ===
ALTER TABLE cart_items ADD CONSTRAINT fk_cart_items_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE cart_items ADD CONSTRAINT fk_cart_items_cart  FOREIGN KEY (tenant_id, cart_id) REFERENCES carts(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE cart_items ADD CONSTRAINT fk_cart_items_book  FOREIGN KEY (tenant_id, book_id) REFERENCES books(tenant_id, id) ON DELETE CASCADE;

-- === carts ===
ALTER TABLE carts ADD CONSTRAINT fk_carts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE carts ADD CONSTRAINT fk_carts_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === categories ===
ALTER TABLE categories ADD CONSTRAINT fk_categories_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE categories ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL;

-- === coupon_redemptions ===
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_coupon FOREIGN KEY (tenant_id, coupon_id) REFERENCES coupons(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_order  FOREIGN KEY (tenant_id, order_id)  REFERENCES orders(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE coupon_redemptions ADD CONSTRAINT fk_cr_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === coupons ===
ALTER TABLE coupons ADD CONSTRAINT fk_coupons_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === crypto_keys ===
ALTER TABLE crypto_keys ADD CONSTRAINT fk_keys_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE crypto_keys ADD CONSTRAINT fk_keys_replaced_by FOREIGN KEY (replaced_by) REFERENCES crypto_keys(id) ON DELETE SET NULL;

-- === crypto_standard_aliases ===
ALTER TABLE crypto_standard_aliases ADD CONSTRAINT fk_crypto_alias_algo FOREIGN KEY (algo_id) REFERENCES crypto_algorithms(id) ON DELETE CASCADE;

-- === deletion_jobs ===
ALTER TABLE deletion_jobs ADD CONSTRAINT fk_dj_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

-- === device_fingerprints ===
ALTER TABLE device_fingerprints ADD CONSTRAINT fk_df_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === email_verifications ===
ALTER TABLE email_verifications ADD CONSTRAINT fk_ev_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- === encryption_bindings ===
ALTER TABLE encryption_bindings ADD CONSTRAINT fk_enc_bind_kw FOREIGN KEY (key_wrapper_id) REFERENCES key_wrappers(id) ON DELETE RESTRICT;

-- === encryption_policy_bindings ===
ALTER TABLE encryption_policy_bindings ADD CONSTRAINT fk_enc_pol_bind_policy FOREIGN KEY (policy_id) REFERENCES encryption_policies(id) ON DELETE CASCADE;

-- === field_hash_policies ===
ALTER TABLE field_hash_policies ADD CONSTRAINT fk_fhp_profile FOREIGN KEY (profile_id) REFERENCES hash_profiles(id) ON DELETE RESTRICT;

-- === hash_profiles ===
ALTER TABLE hash_profiles ADD CONSTRAINT fk_hp_algo FOREIGN KEY (algo_id) REFERENCES crypto_algorithms(id) ON DELETE RESTRICT;

-- === idempotency_keys ===
ALTER TABLE idempotency_keys ADD CONSTRAINT fk_idemp_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE idempotency_keys ADD CONSTRAINT fk_idemp_payment FOREIGN KEY (tenant_id, payment_id) REFERENCES payments(tenant_id, id) ON DELETE SET NULL;
ALTER TABLE idempotency_keys ADD CONSTRAINT fk_idemp_order   FOREIGN KEY (tenant_id, order_id)   REFERENCES orders(tenant_id, id) ON DELETE SET NULL;
ALTER TABLE idempotency_keys ADD CONSTRAINT chk_idemp_ttl CHECK (ttl_seconds > 0);

-- === inventory_reservations ===
ALTER TABLE inventory_reservations ADD CONSTRAINT fk_res_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE inventory_reservations ADD CONSTRAINT fk_res_book  FOREIGN KEY (tenant_id, book_id)  REFERENCES books(tenant_id, id)  ON DELETE CASCADE;
ALTER TABLE inventory_reservations ADD CONSTRAINT fk_res_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE SET NULL;

-- === invoice_items ===
ALTER TABLE invoice_items ADD CONSTRAINT fk_invoice_items_invoice FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoices(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE invoice_items ADD CONSTRAINT chk_invoice_items_tax_rate CHECK (tax_rate BETWEEN 0 AND 100);

-- === invoices ===
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE SET NULL;

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

-- === key_wrapper_layers ===
ALTER TABLE key_wrapper_layers ADD CONSTRAINT fk_kwl_kw   FOREIGN KEY (key_wrapper_id) REFERENCES key_wrappers(id) ON DELETE CASCADE;
ALTER TABLE key_wrapper_layers ADD CONSTRAINT fk_kwl_kms  FOREIGN KEY (kms_key_id)     REFERENCES kms_keys(id) ON DELETE SET NULL;
ALTER TABLE key_wrapper_layers ADD CONSTRAINT fk_kwl_algo FOREIGN KEY (kem_algo_id)    REFERENCES crypto_algorithms(id) ON DELETE RESTRICT;

-- === key_wrappers ===
ALTER TABLE key_wrappers ADD CONSTRAINT fk_kw_kms1 FOREIGN KEY (kms1_key_id) REFERENCES kms_keys(id) ON DELETE RESTRICT;
ALTER TABLE key_wrappers ADD CONSTRAINT fk_kw_kms2 FOREIGN KEY (kms2_key_id) REFERENCES kms_keys(id) ON DELETE RESTRICT;

-- === kms_health_checks ===
ALTER TABLE kms_health_checks ADD CONSTRAINT fk_kms_hc_provider FOREIGN KEY (provider_id) REFERENCES kms_providers(id) ON DELETE SET NULL;
ALTER TABLE kms_health_checks ADD CONSTRAINT fk_kms_hc_key      FOREIGN KEY (kms_key_id)  REFERENCES kms_keys(id) ON DELETE SET NULL;

-- === kms_keys ===
ALTER TABLE kms_keys ADD CONSTRAINT fk_kms_keys_provider FOREIGN KEY (provider_id) REFERENCES kms_providers(id) ON DELETE CASCADE;

-- === login_attempts ===
ALTER TABLE login_attempts ADD CONSTRAINT fk_login_attempts_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE login_attempts ADD CONSTRAINT fk_login_attempts_auth_event FOREIGN KEY (auth_event_id) REFERENCES auth_events(id) ON DELETE SET NULL;

-- === merkle_anchors ===
ALTER TABLE merkle_anchors ADD CONSTRAINT fk_merkle_anchor_root FOREIGN KEY (merkle_root_id) REFERENCES merkle_roots(id) ON DELETE CASCADE;

-- === newsletter_subscribers ===
ALTER TABLE newsletter_subscribers ADD CONSTRAINT fk_ns_user   FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE newsletter_subscribers ADD CONSTRAINT fk_ns_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === notifications ===
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE notifications ADD CONSTRAINT chk_notifications_retries CHECK (retries >= 0 AND max_retries >= 0);
ALTER TABLE notifications ADD CONSTRAINT fk_notifications_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === order_item_downloads ===
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_book  FOREIGN KEY (tenant_id, book_id)  REFERENCES books(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE order_item_downloads ADD CONSTRAINT fk_oid_asset FOREIGN KEY (tenant_id, asset_id) REFERENCES book_assets(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE order_item_downloads ADD CONSTRAINT chk_oid_uses CHECK (max_uses > 0 AND used >= 0 AND used <= max_uses);

-- === order_items ===
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE order_items ADD CONSTRAINT fk_order_items_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE order_items ADD  CONSTRAINT fk_order_items_book  FOREIGN KEY (tenant_id, book_id) REFERENCES books(tenant_id, id) ON DELETE SET NULL;

-- === orders ===
ALTER TABLE orders ADD CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE orders ADD CONSTRAINT fk_orders_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

-- === payment_gateway_notifications ===
ALTER TABLE payment_gateway_notifications ADD CONSTRAINT fk_pg_notify_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE payment_gateway_notifications ADD CONSTRAINT fk_pg_notify_payment FOREIGN KEY (tenant_id, transaction_id) REFERENCES payments(tenant_id, transaction_id) ON DELETE CASCADE;

-- === payment_logs ===
ALTER TABLE payment_logs ADD CONSTRAINT fk_payment_logs_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE;

-- === payment_webhooks ===
ALTER TABLE payment_webhooks ADD CONSTRAINT fk_payment_webhooks_payment FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE SET NULL;

-- === payments ===
ALTER TABLE payments ADD CONSTRAINT fk_payments_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE payments ADD CONSTRAINT fk_payments_order FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id) ON DELETE SET NULL;
ALTER TABLE payments ADD CONSTRAINT chk_payments_amount CHECK (amount >= 0);

-- === policy_algorithms ===
ALTER TABLE policy_algorithms ADD CONSTRAINT fk_pa_policy FOREIGN KEY (policy_id) REFERENCES encryption_policies(id) ON DELETE CASCADE;
ALTER TABLE policy_algorithms ADD CONSTRAINT fk_pa_algo   FOREIGN KEY (algo_id)   REFERENCES crypto_algorithms(id) ON DELETE CASCADE;

-- === policy_kms_keys ===
ALTER TABLE policy_kms_keys ADD CONSTRAINT fk_policy_kms_keys_policy FOREIGN KEY (policy_id) REFERENCES encryption_policies(id) ON DELETE CASCADE;
ALTER TABLE policy_kms_keys ADD CONSTRAINT fk_policy_kms_keys_key FOREIGN KEY (kms_key_id) REFERENCES kms_keys(id) ON DELETE CASCADE;

-- === pq_migration_jobs ===
ALTER TABLE pq_migration_jobs ADD CONSTRAINT fk_pq_mig_policy FOREIGN KEY (target_policy_id) REFERENCES encryption_policies(id) ON DELETE SET NULL;
ALTER TABLE pq_migration_jobs ADD CONSTRAINT fk_pq_mig_algo   FOREIGN KEY (target_algo_id)   REFERENCES crypto_algorithms(id) ON DELETE SET NULL;
ALTER TABLE pq_migration_jobs ADD CONSTRAINT fk_pq_mig_user   FOREIGN KEY (created_by)       REFERENCES users(id) ON DELETE SET NULL;

-- === privacy_requests ===
ALTER TABLE privacy_requests ADD CONSTRAINT fk_pr_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === rbac_repo_snapshots ===
ALTER TABLE rbac_repo_snapshots ADD CONSTRAINT fk_rbac_snap_repo FOREIGN KEY (repo_id) REFERENCES rbac_repositories(id) ON DELETE CASCADE;

-- === rbac_repositories ===
ALTER TABLE rbac_repositories ADD CONSTRAINT fk_rbac_repos_sign_key FOREIGN KEY (signing_key_id) REFERENCES signing_keys(id) ON DELETE SET NULL;

-- === rbac_role_permissions ===
ALTER TABLE rbac_role_permissions ADD CONSTRAINT fk_rbac_rp_role FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;
ALTER TABLE rbac_role_permissions ADD CONSTRAINT fk_rbac_rp_perm FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;

-- === rbac_roles ===
ALTER TABLE rbac_roles ADD CONSTRAINT fk_rbac_roles_repo FOREIGN KEY (repo_id) REFERENCES rbac_repositories(id) ON DELETE SET NULL;

-- === rbac_sync_cursors ===
ALTER TABLE rbac_sync_cursors ADD CONSTRAINT fk_rbac_cursors_repo FOREIGN KEY (repo_id) REFERENCES rbac_repositories(id) ON DELETE CASCADE;

-- === rbac_user_permissions ===
ALTER TABLE rbac_user_permissions ADD CONSTRAINT fk_rbac_up_user  FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE rbac_user_permissions ADD CONSTRAINT fk_rbac_up_perm  FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
ALTER TABLE rbac_user_permissions ADD CONSTRAINT fk_rbac_up_grant FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE rbac_user_permissions ADD CONSTRAINT fk_rbac_up_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;

-- === rbac_user_roles ===
ALTER TABLE rbac_user_roles ADD CONSTRAINT fk_rbac_ur_user   FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE rbac_user_roles ADD CONSTRAINT fk_rbac_ur_role   FOREIGN KEY (role_id)  REFERENCES rbac_roles(id) ON DELETE CASCADE;
ALTER TABLE rbac_user_roles ADD CONSTRAINT fk_rbac_ur_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE rbac_user_roles ADD CONSTRAINT fk_rbac_ur_grant  FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL;

-- === refunds ===
ALTER TABLE refunds ADD CONSTRAINT fk_refunds_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE refunds ADD CONSTRAINT fk_refunds_payment FOREIGN KEY (tenant_id, payment_id) REFERENCES payments(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE refunds ADD CONSTRAINT chk_refunds_amount CHECK (amount >= 0);

-- === register_events ===
ALTER TABLE register_events ADD CONSTRAINT fk_register_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === replication_lag_samples ===
ALTER TABLE replication_lag_samples ADD CONSTRAINT fk_lag_peer FOREIGN KEY (peer_id) REFERENCES peer_nodes(id) ON DELETE CASCADE;

-- === retention_enforcement_jobs ===
ALTER TABLE retention_enforcement_jobs ADD CONSTRAINT fk_rej_policy FOREIGN KEY (policy_id) REFERENCES data_retention_policies(id) ON DELETE CASCADE;

-- === reviews ===
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_book FOREIGN KEY (tenant_id, book_id) REFERENCES books(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === rewrap_jobs ===
ALTER TABLE rewrap_jobs ADD CONSTRAINT fk_rewrap_kw FOREIGN KEY (key_wrapper_id) REFERENCES key_wrappers(id) ON DELETE CASCADE;
ALTER TABLE rewrap_jobs ADD CONSTRAINT fk_rewrap_tk1 FOREIGN KEY (target_kms1_key_id) REFERENCES kms_keys(id) ON DELETE SET NULL;
ALTER TABLE rewrap_jobs ADD CONSTRAINT fk_rewrap_tk2 FOREIGN KEY (target_kms2_key_id) REFERENCES kms_keys(id) ON DELETE SET NULL;

-- === session_audit ===
ALTER TABLE session_audit ADD CONSTRAINT fk_session_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === sessions ===
ALTER TABLE sessions ADD CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- === signatures ===
ALTER TABLE signatures ADD CONSTRAINT fk_sigs_algo   FOREIGN KEY (algo_id)        REFERENCES crypto_algorithms(id) ON DELETE RESTRICT;
ALTER TABLE signatures ADD CONSTRAINT fk_sigs_hash   FOREIGN KEY (hash_algo_id)   REFERENCES crypto_algorithms(id) ON DELETE RESTRICT;
ALTER TABLE signatures ADD CONSTRAINT fk_sigs_skey   FOREIGN KEY (signing_key_id) REFERENCES signing_keys(id) ON DELETE SET NULL;

-- === signing_keys ===
ALTER TABLE signing_keys ADD CONSTRAINT fk_sk_algo  FOREIGN KEY (algo_id)  REFERENCES crypto_algorithms(id) ON DELETE RESTRICT;
ALTER TABLE signing_keys ADD CONSTRAINT fk_sk_kms   FOREIGN KEY (kms_key_id) REFERENCES kms_keys(id) ON DELETE SET NULL;
ALTER TABLE signing_keys ADD CONSTRAINT fk_sk_user  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

-- === slo_status ===
ALTER TABLE slo_status ADD CONSTRAINT fk_slo_status_window FOREIGN KEY (window_id) REFERENCES slo_windows(id) ON DELETE CASCADE;

-- === sync_batch_items ===
ALTER TABLE sync_batch_items ADD CONSTRAINT fk_sbi_batch FOREIGN KEY (batch_id) REFERENCES sync_batches(id) ON DELETE CASCADE;

-- === sync_batches ===
ALTER TABLE sync_batches ADD CONSTRAINT fk_sb_producer FOREIGN KEY (producer_peer_id) REFERENCES peer_nodes(id) ON DELETE RESTRICT;
ALTER TABLE sync_batches ADD CONSTRAINT fk_sb_consumer FOREIGN KEY (consumer_peer_id) REFERENCES peer_nodes(id) ON DELETE RESTRICT;

-- === sync_errors ===
ALTER TABLE sync_errors ADD CONSTRAINT fk_sync_err_peer FOREIGN KEY (peer_id) REFERENCES peer_nodes(id) ON DELETE SET NULL;

-- === system_errors ===
ALTER TABLE system_errors ADD CONSTRAINT fk_err_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE system_errors ADD CONSTRAINT fk_err_resolved_by FOREIGN KEY (resolved_by) REFERENCES users(id) ON DELETE SET NULL;

-- === tax_rates ===
ALTER TABLE tax_rates ADD CONSTRAINT fk_tax_rates_country FOREIGN KEY (country_iso2) REFERENCES countries(iso2) ON DELETE CASCADE;
ALTER TABLE tax_rates ADD CONSTRAINT chk_tax_rates_rate CHECK (rate BETWEEN 0 AND 100);

-- === tenant_domains ===
ALTER TABLE tenant_domains ADD CONSTRAINT fk_tenant_domains_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;

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


