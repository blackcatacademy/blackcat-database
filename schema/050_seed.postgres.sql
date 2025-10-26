BEGIN;

-- === app_settings ===
-- Operational defaults (bez skutečných tajemství)
INSERT INTO app_settings
  (setting_key, setting_value, "type", section, description, is_protected)
VALUES
  (''site.name'',                          ''BlackCat Bookstore'', ''string'', ''site'',     ''Public site name'',                          false),
  (''site.currency_default'',              ''EUR'',                ''string'', ''site'',     ''Default currency code (ISO 4217)'',          false),
  (''tax.prices_include_vat'',             ''0'',                  ''bool'',   ''tax'',      ''If true, catalog prices are VAT-inclusive'', false),
  (''security.password.min_length'',       ''12'',                 ''int'',    ''security'', ''Minimum password length'',                   true),
  (''security.two_factor.required_for_admins'',''1'',              ''bool'',   ''security'', ''Admins must have 2FA enabled'',              true),
  (''sessions.max_lifetime_seconds'',      ''1209600'',            ''int'',    ''security'', ''Max session lifetime (14d)'',                false),
  (''notifications.max_retries'',          ''6'',                  ''int'',    ''notify'',   ''Max retry attempts for notifications'',      false),
  (''security.jwt.refresh_ttl_days'',      ''30'',                 ''int'',    ''security'', ''Refresh token TTL in days'',                 true),
  (''orders.public_number_prefix'',        ''ORD-'',               ''string'', ''orders'',   ''Prefix for public order numbers'',           false),
  (''mail.from_address'',                  ''no-reply@example.test'',''string'',''mail'',    ''Default From address'',                      true)
ON CONFLICT (setting_key) DO UPDATE
  SET setting_value = EXCLUDED.setting_value,
      "type"        = EXCLUDED."type",
      section       = EXCLUDED.section,
      description   = EXCLUDED.description,
      is_protected  = EXCLUDED.is_protected,
      updated_at    = now();

-- === authors ===
-- Fallback author
INSERT INTO authors (name, slug, bio, photo_url, story, created_at)
VALUES (''Unknown Author'', ''unknown'', NULL, NULL, NULL, now())
ON CONFLICT (slug) DO UPDATE
  SET name       = EXCLUDED.name,
      deleted_at = NULL;

-- === categories ===
-- Baseline categories; revive if soft-deleted
INSERT INTO categories (name, slug, parent_id)
VALUES
  (''Uncategorized'', ''uncategorized'', NULL),
  (''E-books'',       ''ebooks'',        NULL)
ON CONFLICT (slug) DO UPDATE
  SET name       = EXCLUDED.name,
      parent_id  = EXCLUDED.parent_id,
      deleted_at = NULL;

-- === countries ===
-- Minimal countries (idempotent)
INSERT INTO countries (iso2, name) VALUES
  (''SK'', ''Slovakia''),
  (''CZ'', ''Czechia'')
ON CONFLICT (iso2) DO UPDATE
  SET name = EXCLUDED.name;

-- === encryption_policies ===
-- Default encryption policy for dev
INSERT INTO encryption_policies
  (policy_name, mode, layer_selection, min_layers, max_layers, aad_template, notes)
VALUES
  (''default'', ''local'', ''defined'', 1, 1, NULL, ''Local single-layer encryption for dev'')
ON CONFLICT (policy_name) DO UPDATE
  SET mode            = EXCLUDED.mode,
      layer_selection = EXCLUDED.layer_selection,
      min_layers      = EXCLUDED.min_layers,
      max_layers      = EXCLUDED.max_layers,
      aad_template    = EXCLUDED.aad_template,
      notes           = EXCLUDED.notes;

-- === permissions ===
-- Baseline RBAC (rozšířeno pro nové entity)
INSERT INTO permissions (name, description) VALUES
  (''admin:full_access'',          ''Grants all administration privileges''),
  (''users:read'',                 ''View users''),
  (''users:manage'',               ''Create/update/lock users''),
  (''books:manage'',               ''Manage catalog: authors, books, assets''),
  (''orders:read'',                ''View orders''),
  (''orders:manage'',              ''Create/update/cancel orders''),
  (''payments:read'',              ''View payments''),
  (''payments:refund'',            ''Issue refunds''),
  (''invoices:manage'',            ''Create and edit invoices''),
  (''coupons:manage'',             ''Manage coupons and redemptions''),
  (''notifications:manage'',       ''Manage outbound notifications''),
  (''webhooks:replay'',            ''Replay webhook deliveries''),
  (''jobs:run'',                   ''Run/inspect background jobs''),
  (''settings:manage'',            ''Edit application settings''),
  (''keys:manage'',                ''Manage local crypto keys''),
  (''kms:manage'',                 ''Manage KMS providers/keys''),
  (''encryption_policies:manage'', ''Manage encryption policies''),
  (''errors:triage'',              ''Triage and resolve system errors''),
  (''audit:read'',                 ''Read audit log'')
ON CONFLICT (name) DO UPDATE
  SET description = EXCLUDED.description,
      updated_at  = now();

-- === tax_rates ===
-- Minimal VAT placeholders (idempotent via upsert)
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to) VALUES
  (''SK'', ''ebook'',    20.00, DATE ''2000-01-01'', NULL),
  (''SK'', ''physical'', 20.00, DATE ''2000-01-01'', NULL),
  (''CZ'', ''ebook'',    21.00, DATE ''2000-01-01'', NULL),
  (''CZ'', ''physical'', 21.00, DATE ''2000-01-01'', NULL)
ON CONFLICT (country_iso2, category, valid_from) DO UPDATE
  SET rate     = EXCLUDED.rate,
      valid_to = EXCLUDED.valid_to;

COMMIT;

