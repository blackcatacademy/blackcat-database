@{
  FormatVersion = '1.0'

  Tables = @{

    countries = @{
      seed = @'
-- Minimal countries for bootstrapping (idempotent)
INSERT INTO countries (iso2, name) VALUES
  ('SK', 'Slovakia'),
  ('CZ', 'Czechia')
ON DUPLICATE KEY UPDATE name = VALUES(name);
'@
    }

    permissions = @{
      seed = @'
-- Baseline permission set (extend per your RBAC needs)
INSERT INTO permissions (name, description) VALUES
  ('admin:full_access', 'Grants all administration privileges'),
  ('users:read',        'View users'),
  ('users:manage',      'Create/update/lock users'),
  ('books:manage',      'Manage catalog: authors, books, assets'),
  ('orders:read',       'View orders'),
  ('orders:manage',     'Create/update/cancel orders'),
  ('payments:refund',   'Issue refunds')
ON DUPLICATE KEY UPDATE description = VALUES(description);
'@
    }

    categories = @{
      seed = @'
-- Baseline categories (keep it lean; use slugs as stable identifiers)
INSERT INTO categories (name, slug, parent_id)
VALUES
  ('Uncategorized', 'uncategorized', NULL),
  ('E-books',       'ebooks',        NULL)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  deleted_at = NULL; -- revive if previously soft-deleted
'@
    }

    authors = @{
      seed = @'
-- Fallback author to attach items with missing/unknown authors
INSERT INTO authors (name, slug, bio, photo_url, story, created_at)
VALUES ('Unknown Author', 'unknown', NULL, NULL, NULL, CURRENT_TIMESTAMP(6))
ON DUPLICATE KEY UPDATE name = VALUES(name);
'@
    }

    app_settings = @{
      seed = @'
-- Operational defaults (do NOT store real secrets here)
-- Values are strings; types drive casting/validation at application layer.
INSERT INTO app_settings (setting_key, setting_value, type, section, description, is_protected) VALUES
  ('site.name',                         'BlackCat Bookstore', 'string', 'site',     'Public site name',                          0),
  ('site.currency_default',             'EUR',                'string', 'site',     'Default currency code (ISO 4217)',          0),
  ('tax.prices_include_vat',            '0',                  'bool',   'tax',      'If true, catalog prices are VAT-inclusive', 0),
  ('security.password.min_length',      '12',                 'int',    'security', 'Minimum password length',                   1),
  ('security.two_factor.required_for_admins','1',             'bool',   'security', 'Admins must have 2FA enabled',              1),
  ('orders.public_number_prefix',       'ORD-',               'string', 'orders',   'Prefix for public order numbers',           0),
  ('mail.from_address',                 'no-reply@example.test','string','mail',    'Default From: address for outbound mail',   1)
ON DUPLICATE KEY UPDATE
  setting_value = VALUES(setting_value),
  type          = VALUES(type),
  section       = VALUES(section),
  description   = VALUES(description),
  is_protected  = VALUES(is_protected),
  updated_at    = CURRENT_TIMESTAMP(6);
'@
    }

    encryption_policies = @{
      seed = @'
-- Default encryption policy for development (local, single layer).
-- Adjust/extend before enabling KMS in production.
INSERT INTO encryption_policies
  (policy_name, mode,  layer_selection, min_layers, max_layers, aad_template, notes)
VALUES
  ('default',   'local','defined',      1,          1,          NULL,         'Local single-layer encryption for dev')
ON DUPLICATE KEY UPDATE
  mode            = VALUES(mode),
  layer_selection = VALUES(layer_selection),
  min_layers      = VALUES(min_layers),
  max_layers      = VALUES(max_layers),
  aad_template    = VALUES(aad_template),
  notes           = VALUES(notes);
'@
    }

    tax_rates = @{
      seed = @'
-- Minimal VAT placeholders (adjust to legal reality in your target markets).
-- Uses NOT EXISTS to remain idempotent without a unique constraint.
-- Tip: consider adding a UNIQUE index on (country_iso2, category, valid_from) to harden this.

-- Slovakia, baseline 20% for both categories (placeholder)
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT 'SK','ebook',   20.00, '2000-01-01', NULL
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE country_iso2='SK' AND category='ebook');

INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT 'SK','physical',20.00, '2000-01-01', NULL
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE country_iso2='SK' AND category='physical');

-- Czechia, baseline 21% for both categories (placeholder)
INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT 'CZ','ebook',   21.00, '2000-01-01', NULL
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE country_iso2='CZ' AND category='ebook');

INSERT INTO tax_rates (country_iso2, category, rate, valid_from, valid_to)
SELECT 'CZ','physical',21.00, '2000-01-01', NULL
WHERE NOT EXISTS (SELECT 1 FROM tax_rates WHERE country_iso2='CZ' AND category='physical');
'@
    }

  } # /Tables
}
