BEGIN;

-- === app_settings ===
-- Operational defaults (no real secrets)
INSERT INTO app_settings (setting_key, setting_value, type, section, description, is_protected)
VALUES
  (''site.name'',                  ''BlackCat Bookstore'', ''string'', ''site'',     ''Public site name'',                           FALSE),
  (''site.currency_default'',      ''EUR'',                ''string'', ''site'',     ''Default currency code (ISO 4217)'',           FALSE),
  (''tax.prices_include_vat'',     ''0'',                  ''bool'',   ''tax'',      ''If true, catalog prices are VAT-inclusive'',  FALSE),
  (''security.password.min_length'',''12'',                ''int'',    ''security'', ''Minimum password length'',                    TRUE),
  (''security.two_factor.required_for_admins'',''1'',      ''bool'',   ''security'', ''Admins must have 2FA enabled'',               TRUE),
  (''orders.public_number_prefix'', ''ORD-'',              ''string'', ''orders'',   ''Prefix for public order numbers'',            FALSE),
  (''mail.from_address'',           ''no-reply@example.test'',''string'',''mail'',   ''Default From: address for outbound mail'',    TRUE)
ON CONFLICT (setting_key) DO UPDATE
  SET setting_value = EXCLUDED.setting_value,
      type          = EXCLUDED.type,
      section       = EXCLUDED.section,
      description   = EXCLUDED.description,
      is_protected  = EXCLUDED.is_protected,
      updated_at    = CURRENT_TIMESTAMP(6);

-- === authors ===
-- Fallback author
INSERT INTO authors (name, slug, bio, photo_url, story, created_at)
VALUES (''Unknown Author'', ''unknown'', NULL, NULL, NULL, CURRENT_TIMESTAMP(6))
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      deleted_at = NULL;

-- === categories ===
-- Baseline categories (use slug as stable identifier)
INSERT INTO categories (name, slug, parent_id)
VALUES
  (''Uncategorized'', ''uncategorized'', NULL),
  (''E-books'',       ''ebooks'',        NULL)
ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      deleted_at = NULL;

-- === countries ===
-- Minimal countries (idempotent)
INSERT INTO countries (iso2, name) VALUES
  (''SK'', ''Slovakia''),
  (''CZ'', ''Czechia'')
ON CONFLICT (iso2) DO UPDATE SET name = EXCLUDED.name;

-- === encryption_policies ===
-- Default encryption policy for development
INSERT INTO encryption_policies
  (policy_name, mode,  layer_selection, min_layers, max_layers, aad_template, notes)
VALUES
  (''default'',   ''local'', ''defined'', 1, 1, NULL, ''Local single-layer encryption for dev'')
ON CONFLICT (policy_name) DO UPDATE
  SET mode            = EXCLUDED.mode,
      layer_selection = EXCLUDED.layer_selection,
      min_layers      = EXCLUDED.min_layers,
      max_layers      = EXCLUDED.max_layers,
      aad_template    = EXCLUDED.aad_template,
      notes           = EXCLUDED.notes;

-- === permissions ===
-- Baseline permission set
INSERT INTO permissions (name, description) VALUES
  (''admin:full_access'', ''Grants all administration privileges''),
  (''users:read'',        ''View users''),
  (''users:manage'',      ''Create/update/lock users''),
  (''books:manage'',      ''Manage catalog: authors, books, assets''),
  (''orders:read'',       ''View orders''),
  (''orders:manage'',     ''Create/update/cancel orders''),
  (''payments:refund'',   ''Issue refunds'')
ON CONFLICT (name) DO UPDATE
  SET description = EXCLUDED.description,
      updated_at  = CURRENT_TIMESTAMP(6);

-- === tax_rates ===
-- Minimal VAT placeholders (adjust to legal reality)
-- Consider UNIQUE(country_iso2, category, valid_from) for stronger idempotency.

-- Slovakia
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT ''SK'',''ebook'',    20.00, DATE ''2000-01-01'', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM tax_rates WHERE country_iso2=''SK'' AND category=''ebook''
);

INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT ''SK'',''physical'', 20.00, DATE ''2000-01-01'', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM tax_rates WHERE country_iso2=''SK'' AND category=''physical''
);

-- Czechia
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT ''CZ'',''ebook'',    21.00, DATE ''2000-01-01'', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM tax_rates WHERE country_iso2=''CZ'' AND category=''ebook''
);

INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT ''CZ'',''physical'', 21.00, DATE ''2000-01-01'', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM tax_rates WHERE country_iso2=''CZ'' AND category=''physical''
);

COMMIT;

