@{
  FormatVersion = '1.1'

  Tables = @{

    countries = @{
      seed = @'
-- Minimal countries (idempotent)
INSERT INTO countries (iso2, name) VALUES
  (''SK'', ''Slovakia''),
  (''CZ'', ''Czechia'')
AS new
ON DUPLICATE KEY UPDATE
  name = new.name;
'@
    }

    permissions = @{
      seed = @'
-- Baseline RBAC (+ rozšíření pro nové entity)
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
AS new
ON DUPLICATE KEY UPDATE
  description = new.description;
'@
    }

    categories = @{
      seed = @'
-- Baseline categories; revive if soft-deleted
INSERT INTO categories (name, slug, parent_id)
VALUES
  (''Uncategorized'', ''uncategorized'', NULL),
  (''E-books'',       ''ebooks'',        NULL)
AS new
ON DUPLICATE KEY UPDATE
  name       = new.name,
  parent_id  = new.parent_id,
  deleted_at = NULL;
'@
    }

    authors = @{
      seed = @'
-- Fallback author
INSERT INTO authors (name, slug, bio, photo_url, story, created_at)
VALUES (''Unknown Author'', ''unknown'', NULL, NULL, NULL, CURRENT_TIMESTAMP(6))
AS new
ON DUPLICATE KEY UPDATE
  name       = new.name,
  deleted_at = NULL;
'@
    }

    app_settings = @{
      seed = @'
-- Operational defaults (neukládej reálná tajemství)
INSERT INTO app_settings (setting_key, setting_value, type, section, description, is_protected, updated_at) VALUES
  (''site.name'',                          ''BlackCat Bookstore'', ''string'', ''site'',     ''Public site name'',                          0, CURRENT_TIMESTAMP(6)),
  (''site.currency_default'',              ''EUR'',                ''string'', ''site'',     ''Default currency code (ISO 4217)'',          0, CURRENT_TIMESTAMP(6)),
  (''tax.prices_include_vat'',             ''0'',                  ''bool'',   ''tax'',      ''If true, catalog prices are VAT-inclusive'', 0, CURRENT_TIMESTAMP(6)),
  (''security.password.min_length'',       ''12'',                 ''int'',    ''security'', ''Minimum password length'',                   1, CURRENT_TIMESTAMP(6)),
  (''security.two_factor.required_for_admins'',''1'',              ''bool'',   ''security'', ''Admins must have 2FA enabled'',              1, CURRENT_TIMESTAMP(6)),
  (''sessions.max_lifetime_seconds'',      ''1209600'',            ''int'',    ''security'', ''Max session lifetime (14d)'',                0, CURRENT_TIMESTAMP(6)),
  (''notifications.max_retries'',          ''6'',                  ''int'',    ''notify'',   ''Max retry attempts for notifications'',      0, CURRENT_TIMESTAMP(6)),
  (''security.jwt.refresh_ttl_days'',      ''30'',                 ''int'',    ''security'', ''Refresh token TTL in days'',                 1, CURRENT_TIMESTAMP(6)),
  (''orders.public_number_prefix'',        ''ORD-'',               ''string'', ''orders'',   ''Prefix for public order numbers'',           0, CURRENT_TIMESTAMP(6)),
  (''mail.from_address'',                  ''no-reply@example.test'',''string'',''mail'',    ''Default From address'',                      1, CURRENT_TIMESTAMP(6))
AS new
ON DUPLICATE KEY UPDATE
  setting_value = new.setting_value,
  type          = new.type,
  section       = new.section,
  description   = new.description,
  is_protected  = new.is_protected,
  updated_at    = CURRENT_TIMESTAMP(6),
  updated_by    = updated_by;
'@
    }

    encryption_policies = @{
      seed = @'
-- Default encryption policy for dev
INSERT INTO encryption_policies
  (policy_name, mode,  layer_selection, min_layers, max_layers, aad_template, notes)
VALUES
  (''default'', ''local'', ''defined'', 1, 1, NULL, ''Local single-layer encryption for dev'')
AS new
ON DUPLICATE KEY UPDATE
  mode            = new.mode,
  layer_selection = new.layer_selection,
  min_layers      = new.min_layers,
  max_layers      = new.max_layers,
  aad_template    = new.aad_template,
  notes           = new.notes;
'@
    }

    tax_rates = @{
      seed = @'
-- Minimal VAT placeholders (idempotent via upsert)
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to) VALUES
  (''SK'', ''ebook'',    20.00, ''2000-01-01'', NULL),
  (''SK'', ''physical'', 20.00, ''2000-01-01'', NULL),
  (''CZ'', ''ebook'',    21.00, ''2000-01-01'', NULL),
  (''CZ'', ''physical'', 21.00, ''2000-01-01'', NULL)
AS new
ON DUPLICATE KEY UPDATE
  rate     = new.rate,
  valid_to = new.valid_to;
'@
    }

  } # /Tables
}
