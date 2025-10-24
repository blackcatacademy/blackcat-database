# ===========================================
# PostgreSQL Hints (to merge with your schema
# ===========================================
@{

FormatVersion = '1.0'

$PgDefaults = @{
  # -- Global column name based conventions ------------------------
  # Applied by your generator when no explicit Pg override exists.

  Conventions = @(
    @{
      # All *_at timestamps -> timestamptz(6); NOW() default on created/updated
      Match = '.*_at$'
      Pg    = @{ Type = 'timestamptz(6)' }
    },
    @{
      # Common JSON columns -> jsonb
      Match = '^(meta(json)?|details|payload|gateway_payload|encryption_meta|aad_template|old_value|new_value|layers)$'
      Pg    = @{ Type = 'jsonb' }
    },
    @{
      # 32-byte hashes (binary) -> bytea with length check
      Match = '.*(_hash|_token|_fingerprint)$'
      Pg    = @{ Type = 'bytea'; Check = 'octet_length({col}) = 32' } # replace {col} with column name
    },
    @{
      # Currency codes -> char(3) + regex check
      Match = '^currency$'
      Pg    = @{ Type = 'char(3)'; Check = "{col} ~ '^[A-Z]{3}$'" }
    },
    @{
      # Rating-like tiny ints -> smallint
      Match = '^rating$'
      Pg    = @{ Type = 'smallint' }
    }
  )

  # -- Helpers your generator may use ------------------------------
  # Identity preference for MySQL AUTO_INCREMENT cols
  Identity = 'by default' # or 'always'
}

# ===========================================
# Per-table overrides (only the tricky bits)
# ===========================================
$PgOverrides = @{

  Tables = @{

    users = @{
      Columns = @{
        id = @{ Pg = @{ Type = 'bigint'; Identity = $PgDefaults.Identity } }  # AUTO_INCREMENT -> IDENTITY
        email_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(email_hash)=32' } }
        last_login_ip_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(last_login_ip_hash)=32' } }
        last_login_at = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }  # keep trigger in SQL to auto-update
        deleted_at = @{ Pg = @{ Type='timestamptz(6)' } }
        actor_role = @{ Pg = @{ Type='text'; Check="actor_role IN ('customer','admin')" } }
      }
    }

    login_attempts = @{
      Columns = @{
        id = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        ip_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        attempted_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        username_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(username_hash)=32' } }
      }
    }

    user_profiles = @{
      Columns = @{
        user_id     = @{ Pg = @{ Type='bigint' } }
        profile_enc = @{ Pg = @{ Type='bytea' } }
        encryption_meta = @{ Pg = @{ Type='jsonb' } }
        updated_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    user_identities = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    permissions = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    two_factor = @{
      Columns = @{
        secret             = @{ Pg = @{ Type='bytea' } }
        recovery_codes_enc = @{ Pg = @{ Type='bytea' } }
        hotp_counter       = @{ Pg = @{ Type='bigint' } }
        created_at         = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_used_at       = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    session_audit = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        session_token= @{ Pg = @{ Type='bytea'; Check='octet_length(session_token)=32' } }
        ip_hash      = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        meta_json    = @{ Pg = @{ Type='jsonb' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    sessions = @{
      Columns = @{
        id                  = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        token_hash          = @{ Pg = @{ Type='bytea'; Check='octet_length(token_hash)=32' } }
        token_fingerprint   = @{ Pg = @{ Type='bytea'; Check='octet_length(token_fingerprint)=32' } }
        token_issued_at     = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at          = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_seen_at        = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at          = @{ Pg = @{ Type='timestamptz(6)' } }
        ip_hash             = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        session_blob        = @{ Pg = @{ Type='bytea' } }
      }
    }

    auth_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('login_success','login_failure','logout','password_reset','lockout')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
        meta_email  = @{ Pg = @{ Generated = "ALWAYS AS ((meta->>'email')) STORED" } }
      }
    }

    register_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('register_success','register_failure')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    verify_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('verify_success','verify_failure')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    system_errors = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        level       = @{ Pg = @{ Type='text'; Check="level IN ('notice','warning','error','critical')" } }
        context     = @{ Pg = @{ Type='jsonb' } }
        ip_text     = @{ Pg = @{ Type='inet' } }
        ip_bin      = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_bin)=16' } }  # keep if you still need it
        http_status = @{ Pg = @{ Type='smallint' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_seen   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    user_consents = @{
      Columns = @{
        granted_at = @{ Pg = @{ Type='timestamptz(6)' } }
        meta       = @{ Pg = @{ Type='jsonb' } }
      }
    }

    authors = @{
      Columns = @{
        avg_rating     = @{ Pg = @{ Type='numeric(3,2)' } }
        last_rating_at = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        deleted_at     = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    categories = @{
      Columns = @{
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        deleted_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    books = @{
      Columns = @{
        price      = @{ Pg = @{ Type='numeric(12,2)' } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        deleted_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    reviews = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        rating     = @{ Pg = @{ Type='smallint'; Check='rating BETWEEN 1 AND 5' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    crypto_keys = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        key_meta     = @{ Pg = @{ Type='jsonb' } }
        key_type     = @{ Pg = @{ Type='text'; Check="key_type IN ('dek','kek','hmac','pepper')" } }
        origin       = @{ Pg = @{ Type='text'; Check="origin IN ('local','kms','imported')" } }
        usage        = @{ Pg = @{
          # MySQL SET -> text[]; enforce subset of allowed literals
          Type  = 'text[]'
          Check = "(usage IS NULL) OR (usage <@ ARRAY['encrypt','decrypt','sign','verify','wrap','unwrap']::text[])"
        } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('active','retired','compromised','archived')" } }
        backup_blob  = @{ Pg = @{ Type='bytea' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        activated_at = @{ Pg = @{ Type='timestamptz(6)' } }
        retired_at   = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    key_events = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        event_type = @{ Pg = @{ Type='text'; Check="event_type IN ('created','rotated','activated','retired','compromised','deleted','used_encrypt','used_decrypt','access_failed','backup','restore')" } }
        source     = @{ Pg = @{ Type='text'; Check="source IN ('cron','admin','api','manual')" } }
        meta       = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_rotation_jobs = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        scheduled_at = @{ Pg = @{ Type='timestamptz(6)' } }
        started_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_usage = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        date        = @{ Pg = @{ Type='date' } }
        last_used_at= @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    jwt_tokens = @{
      Columns = @{
        id                 = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        jti                = @{ Pg = @{ Type='uuid' } }
        token_hash         = @{ Pg = @{ Type='bytea'; Check='octet_length(token_hash)=32' } }
        ip_hash            = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        type               = @{ Pg = @{ Type='text'; Check="type IN ('refresh','api')" } }
        created_at         = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at         = @{ Pg = @{ Type='timestamptz(6)' } }
        last_used_at       = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    book_assets = @{
      Columns = @{
        id                = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        asset_type        = @{ Pg = @{ Type='text'; Check="asset_type IN ('cover','pdf','epub','mobi','sample','extra')" } }
        encryption_key_enc= @{ Pg = @{ Type='bytea' } }
        encryption_iv     = @{ Pg = @{ Type='bytea'; Check='octet_length(encryption_iv)=12 OR octet_length(encryption_iv)=16 OR encryption_iv IS NULL' } } # typical AEAD sizes
        encryption_tag    = @{ Pg = @{ Type='bytea'; Check='octet_length(encryption_tag)=16 OR encryption_tag IS NULL' } }
        encryption_aad    = @{ Pg = @{ Type='bytea' } }
        encryption_meta   = @{ Pg = @{ Type='jsonb' } }
        key_version       = @{ Pg = @{ Type='varchar(64)' } }
        created_at        = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    book_categories = @{ } # no special needs

    inventory_reservations = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        reserved_until = @{ Pg = @{ Type='timestamptz(6)' } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('pending','confirmed','expired','cancelled')" } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    carts = @{
      Columns = @{
        id         = @{ Pg = @{ Type='uuid' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    cart_items = @{
      Columns = @{
        id            = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        variant       = @{ Pg = @{ Type='jsonb' } }
        currency      = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
      }
    }

    orders = @{
      Pg = @{
        # Cross-column check stays at table level
        TableChecks = @()
      }
      Columns = @{
        id                               = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        uuid                             = @{ Pg = @{ Type='uuid' } }
        uuid_bin                         = @{ Pg = @{ Drop = $true } }  # PG stores uuid as 16B internally
        encrypted_customer_blob          = @{ Pg = @{ Type='bytea' } }
        encryption_meta                  = @{ Pg = @{ Type='jsonb' } }
        currency                         = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        created_at                       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at                       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    order_items = @{
      Columns = @{
        id        = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        currency  = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
      }
    }

    order_item_downloads = @{
      Columns = @{
        id                  = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        download_token_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(download_token_hash)=32' } }
        ip_hash             = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        expires_at          = @{ Pg = @{ Type='timestamptz(6)' } }
        last_used_at        = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    invoices = @{
      Columns = @{
        id            = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        issue_date    = @{ Pg = @{ Type='date' } }
        due_date      = @{ Pg = @{ Type='date' } }
        currency      = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        created_at    = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    invoice_items = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
      }
    }

    payments = @{
      Columns = @{
        id                = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        status            = @{ Pg = @{ Type='text'; Check="status IN ('initiated','pending','authorized','paid','cancelled','partially_refunded','refunded','failed')" } }
        amount            = @{ Pg = @{ Type='numeric(12,2)' } }
        currency          = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        details           = @{ Pg = @{ Type='jsonb' } }
        created_at        = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at        = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_logs = @{
      Columns = @{
        id     = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        log_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_webhooks = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        payload     = @{ Pg = @{ Type='jsonb' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    idempotency_keys = @{
      Columns = @{
        gateway_payload = @{ Pg = @{ Type='jsonb' } }
        created_at      = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    refunds = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        details    = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    coupons = @{
      Pg = @{
        TableChecks = @(
          # Percent vs fixed logic in PG dialect
          "(type = 'percent' AND value BETWEEN 0 AND 100 AND currency IS NULL)
           OR
           (type = 'fixed'   AND value >= 0 AND currency ~ '^[A-Z]{3}$')"
        )
      }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        type       = @{ Pg = @{ Type='text'; Check="type IN ('percent','fixed')" } }
        value      = @{ Pg = @{ Type='numeric(12,2)' } }
        currency   = @{ Pg = @{ Type='char(3)' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    coupon_redemptions = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        redeemed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    countries = @{
      Columns = @{
        iso2 = @{ Pg = @{ Type='char(2)'; Check="iso2 ~ '^[A-Z]{2}$'" } }
      }
    }

    tax_rates = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        category     = @{ Pg = @{ Type='text'; Check="category IN ('ebook','physical')" } }
        rate         = @{ Pg = @{ Type='numeric(5,2)' } }
        valid_from   = @{ Pg = @{ Type='date' } }
        valid_to     = @{ Pg = @{ Type='date' } }
      }
    }

    vat_validations = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        checked_at = @{ Pg = @{ Type='timestamptz(6)' } }
        raw        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    app_settings = @{
      Columns = @{
        type       = @{ Pg = @{ Type='text'; Check="type IN ('string','int','bool','json','secret')" } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    audit_log = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        old_value  = @{ Pg = @{ Type='jsonb' } }
        new_value  = @{ Pg = @{ Type='jsonb' } }
        changed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        ip_bin     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_bin)=16' } }
      }
    }

    webhook_outbox = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        payload        = @{ Pg = @{ Type='jsonb' } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('pending','sent','failed')" } }
        next_attempt_at= @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_gateway_notifications = @{
      Columns = @{
        id               = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        received_at      = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        processing_until = @{ Pg = @{ Type='timestamptz(6)' } }
        status           = @{ Pg = @{ Type='text'; Check="status IN ('pending','processing','done','failed')" } }
      }
    }

    email_verifications = @{
      Columns = @{
        id              = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        token_hash      = @{ Pg = @{ Type='char(64)' } }
        validator_hash  = @{ Pg = @{ Type='bytea'; Check='octet_length(validator_hash)=32' } }
        selector        = @{ Pg = @{ Type='char(12)' } }
        expires_at      = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at      = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        used_at         = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    notifications = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        channel        = @{ Pg = @{ Type='text'; Check="channel IN ('email','push')" } }
        payload        = @{ Pg = @{ Type='jsonb' } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('pending','processing','sent','failed')" } }
        next_attempt_at= @{ Pg = @{ Type='timestamptz(6)' } }
        scheduled_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        sent_at        = @{ Pg = @{ Type='timestamptz(6)' } }
        last_attempt_at= @{ Pg = @{ Type='timestamptz(6)' } }
        locked_until   = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    newsletter_subscribers = @{
      Columns = @{
        id                         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        email_hash                 = @{ Pg = @{ Type='bytea'; Check='octet_length(email_hash)=32' } }
        email_enc                  = @{ Pg = @{ Type='bytea' } }
        confirm_selector           = @{ Pg = @{ Type='char(12)' } }
        confirm_validator_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(confirm_validator_hash)=32' } }
        confirm_expires            = @{ Pg = @{ Type='timestamptz(6)' } }
        confirmed_at               = @{ Pg = @{ Type='timestamptz(6)' } }
        unsubscribe_token_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(unsubscribe_token_hash)=32' } }
        created_at                 = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at                 = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        ip_hash                    = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        meta                       = @{ Pg = @{ Type='jsonb' } }
      }
    }

    system_jobs = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        payload     = @{ Pg = @{ Type='jsonb' } }
        status      = @{ Pg = @{ Type='text'; Check="status IN ('pending','processing','done','failed')" } }
        scheduled_at= @{ Pg = @{ Type='timestamptz(6)' } }
        started_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    worker_locks = @{
      Columns = @{
        locked_until = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    encrypted_fields = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        ciphertext = @{ Pg = @{ Type='bytea' } }
        meta       = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    kms_providers = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        provider   = @{ Pg = @{ Type='text'; Check="provider IN ('gcp','aws','azure','vault')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    kms_keys = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        purpose    = @{ Pg = @{ Type='text'; Check="purpose IN ('wrap','encrypt','both')" } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','retired','disabled')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    encryption_policies = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        mode           = @{ Pg = @{ Type='text'; Check="mode IN ('local','kms','multi-kms')" } }
        layer_selection= @{ Pg = @{ Type='text'; Check="layer_selection IN ('defined','round_robin','random','hash_mod')" } }
        aad_template   = @{ Pg = @{ Type='jsonb' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    policy_kms_keys = @{ } # nothing special

    encryption_events = @{
      Columns = @{
        id               = @{ Pg = @{ Type='bigint'; Identity=$PgDefaults.Identity } }
        op               = @{ Pg = @{ Type='text'; Check="op IN ('encrypt','decrypt','rotate','rehash','unwrap','wrap')" } }
        layers           = @{ Pg = @{ Type='jsonb' } }
        created_at       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }
  }
}
}
# (Optional) attach these objects to your main definition before generation:
# $Definition.PgDefaults = $PgDefaults
# $Definition.PgOverrides = $PgOverrides
