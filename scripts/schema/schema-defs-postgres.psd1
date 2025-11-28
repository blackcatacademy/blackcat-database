# ===========================================
# PostgreSQL Hints — version 1.1
# ===========================================
@{

FormatVersion = '1.1'
  Tables = @{

    app_settings = @{
      Summary = 'Application-wide key/value configuration.'
      Columns = @{
        setting_key   = @{ Description='Unique setting identifier (natural primary key).' }
        setting_value = @{ Description='Value as text (may contain JSON when type=json).' }
        type          = @{ Description='Datatype of the value.'; Enum=@('string','int','bool','json','secret') }
        section       = @{ Description='Logical group/namespace.' }
        description   = @{ Description='Human-readable description.' }
        is_protected  = @{ Description='Marks sensitive values for redaction in UIs.' }
        updated_at    = @{ Description='Last update timestamp (UTC).' }
        updated_by    = @{ Description='User who changed the setting (FK users.id).' }
      }
    }

    audit_log = @{
      Summary = 'Immutable trail of data changes across tables.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        table_name   = @{ Description='Target table name.' }
        record_id    = @{ Description='Primary key of the affected record.' }
        changed_by   = @{ Description='Actor user id (FK users.id) or NULL for system.' }
        change_type  = @{ Description='Type of change.'; Enum=@('INSERT','UPDATE','DELETE') }
        old_value    = @{ Description='JSON snapshot before change.' }
        new_value    = @{ Description='JSON snapshot after change.' }
        changed_at   = @{ Description='When change occurred (UTC).' }
        ip_bin       = @{ Description='Client IP (binary form).'; PII='plain' }
        user_agent   = @{ Description='Client user agent string.' }
        request_id   = @{ Description='Correlation/request id if available.' }
      }
    }

    auth_events = @{
      Summary = 'Authentication events (logins, resets, lockouts).'
      Columns = @{
        id                   = @{ Description='Surrogate primary key.' }
        user_id              = @{ Description='Related user (FK users.id).'}
        type                 = @{ Description='Auth event kind.'; Enum=@('login_success','login_failure','logout','password_reset','lockout') }
        ip_hash              = @{ Description='Hashed client IP.'; PII='hashed' }
        ip_hash_key_version  = @{ Description='Key version used for ip_hash.' }
        user_agent           = @{ Description='Client user agent.' }
        occurred_at          = @{ Description='When event happened (UTC).' }
        meta                 = @{ Description='Additional JSON metadata (e.g., email used).' }
        meta_email           = @{ Description='Generated/stored email extracted from meta for indexing/filtering.' }
      }
    }

    authors = @{
      Summary = 'Authors and aggregate rating counters.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        name            = @{ Description='Author display name.' }
        slug            = @{ Description='URL-friendly unique slug.' }
        bio             = @{ Description='Short biography.' }
        photo_url       = @{ Description='Profile photo URL.' }
        story           = @{ Description='Long-form story/notes.' }
        books_count     = @{ Description='Denormalized number of books.' }
        ratings_count   = @{ Description='Total ratings count.' }
        rating_sum      = @{ Description='Sum of rating values.' }
        avg_rating      = @{ Description='Average rating (derived).' }
        last_rating_at  = @{ Description='Timestamp of last rating.' }
        created_at      = @{ Description='Row creation time (UTC).' }
        updated_at      = @{ Description='Row update time (UTC).' }
        deleted_at      = @{ Description='Soft delete timestamp.' }
      }
    }

    book_assets = @{
      Summary = 'Binary and ancillary assets for books (covers, files, extras). UNIQUE (book_id, asset_type) — max. one asset of a given type per book.'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        book_id            = @{ Description='Book (FK books.id).' }
        asset_type         = @{ Description='Kind of asset.'; Enum=@('cover','pdf','epub','mobi','sample','extra') }
        filename           = @{ Description='Original file name.' }
        mime_type          = @{ Description='MIME type.' }
        size_bytes         = @{ Description='File size in bytes.' }
        storage_path       = @{ Description='Backend storage path or URI.' }
        content_hash       = @{ Description='Optional file content hash (hex).' }
        download_filename  = @{ Description='Suggested download file name.' }
        is_encrypted       = @{ Description='Whether asset is encrypted at rest.' }
        encryption_algo    = @{ Description='Algorithm identifier (e.g., AES-256-GCM).' }
        encryption_key_enc = @{ Description='Wrapped DEK or encrypted key blob.'; PII='encrypted' }
        encryption_iv      = @{ Description='IV/nonce used for encryption.' }
        encryption_tag     = @{ Description='Auth tag for AEAD ciphers.' }
        encryption_aad     = @{ Description='Associated data for AEAD ciphers.' }
        encryption_meta    = @{ Description='JSON metadata about encryption layers.' }
        key_version        = @{ Description='Local key version reference.' }
        key_id             = @{ Description='Optional link to crypto_keys.id.' }
        created_at         = @{ Description='Creation timestamp (UTC).' }
      }
    }

    book_categories = @{
      Summary = 'Many-to-many relationship between books and categories.'
      Columns = @{
        book_id     = @{ Description='Book (FK books.id).' }
        category_id = @{ Description='Category (FK categories.id).' }
      }
    }

    books = @{
      Summary = 'Books catalog with pricing and stock flags.'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        title              = @{ Description='Book title.' }
        slug               = @{ Description='URL-friendly unique slug.' }
        short_description  = @{ Description='Short blurb.' }
        full_description   = @{ Description='Long description (rich text allowed).' }
        price              = @{ Description='Current unit price.' }
        currency           = @{ Description='ISO 4217 currency code (3 letters).' }
        author_id          = @{ Description='Author (FK authors.id).' }
        main_category_id   = @{ Description='Primary category (FK categories.id).' }
        isbn               = @{ Description='ISBN identifier.' }
        language           = @{ Description='Language code (e.g., en, cs).' }
        pages              = @{ Description='Number of pages (if applicable).' }
        publisher          = @{ Description='Publisher name.' }
        published_at       = @{ Description='Publication date.' }
        sku                = @{ Description='Stock keeping unit.' }
        is_active          = @{ Description='Visible in catalog.' }
        is_available       = @{ Description='Available for purchase/download.' }
        stock_quantity     = @{ Description='Units in stock.' }
        created_at         = @{ Description='Creation timestamp (UTC).' }
        updated_at         = @{ Description='Update timestamp (UTC).' }
        deleted_at         = @{ Description='Soft delete timestamp.' }
      }
    }

    cart_items = @{
      Summary = 'Items added to shopping carts. UNIQUE (cart_id, book_id, sku) to prevent duplicate items in the cart.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        cart_id        = @{ Description='Cart identifier (UUID textual).' }
        book_id        = @{ Description='Book (FK books.id).' }
        sku            = @{ Description='SKU snapshot.' }
        variant        = @{ Description='JSON with selected variant/options.' }
        quantity       = @{ Description='Quantity > 0.' }
        unit_price     = @{ Description='Unit price at time of adding.' }
        price_snapshot = @{ Description='Cached line price for integrity.' }
        currency       = @{ Description='ISO 4217 currency code.' }
        meta           = @{ Description='Additional JSON metadata.' }
      }
    }

    carts = @{
      Summary = 'Carts keyed by UUID; may be anonymous or bound to user.'
      Columns = @{
        id         = @{ Description='Cart id (UUID textual).' }
        user_id    = @{ Description='User owner (FK users.id), optional.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
        updated_at = @{ Description='Update timestamp (UTC).' }
      }
    }

    categories = @{
      Summary = 'Hierarchical product categories.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        name       = @{ Description='Category name.' }
        slug       = @{ Description='Unique slug.' }
        parent_id  = @{ Description='Parent category (self-FK), nullable.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
        updated_at = @{ Description='Update timestamp (UTC).' }
        deleted_at = @{ Description='Soft delete timestamp.' }
      }
    }

    countries = @{
      Summary = 'Country reference list.'
      Columns = @{
        iso2 = @{ Description='ISO 3166-1 alpha-2 country code (upper case).' }
        name = @{ Description='Official short name.' }
      }
    }

    coupon_redemptions = @{
      Summary = 'Records of coupon usage per order and user.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        coupon_id      = @{ Description='Coupon (FK coupons.id).' }
        user_id        = @{ Description='User (FK users.id).' }
        order_id       = @{ Description='Order (FK orders.id).' }
        redeemed_at    = @{ Description='When coupon was redeemed (UTC).' }
        amount_applied = @{ Description='Applied discount amount.' }
      }
    }

    coupons = @{
      Summary = 'Discount coupons configuration.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        code             = @{ Description='Unique coupon code (case-sensitive).' }
        type             = @{ Description='Discount type.'; Enum=@('percent','fixed') }
        value            = @{ Description='Discount value (percent or fixed).' }
        currency         = @{ Description='ISO 4217 currency for fixed discounts; NULL for percent.' }
        starts_at        = @{ Description='Validity start (date).' }
        ends_at          = @{ Description='Validity end (date), nullable.' }
        max_redemptions  = @{ Description='Max total redemptions across users (0 = unlimited).' }
        min_order_amount = @{ Description='Minimum order subtotal to apply (optional).' }
        applies_to       = @{ Description='JSON targeting (SKUs, categories, users).' }
        is_active        = @{ Description='Whether coupon is currently active.' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
        updated_at       = @{ Description='Update timestamp (UTC).' }
      }
    }

    crypto_keys = @{
      Summary = 'Local key registry (DEKs, KEKs, HMAC, peppers).'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        basename           = @{ Description='Logical key basename.' }
        version            = @{ Description='Monotonic version per basename.' }
        filename           = @{ Description='Optional filename where stored.' }
        file_path          = @{ Description='Filesystem path or vault path.' }
        fingerprint        = @{ Description='Key fingerprint / digest.' }
        key_meta           = @{ Description='JSON metadata (key parameters).' }
        key_type           = @{ Description='Key purpose type.'; Enum=@('dek','kek','hmac','pepper') }
        algorithm          = @{ Description='Algorithm identifier.' }
        length_bits        = @{ Description='Key length in bits.' }
        origin             = @{ Description='Key origin.'; Enum=@('local','kms','imported') }
        usage              = @{ Description='Allowed operations (set/array of values: encrypt,decrypt,sign,verify,wrap,unwrap).' ; Enum=@('encrypt','decrypt','sign','verify','wrap','unwrap') }
        scope              = @{ Description='Business scope tag (e.g., orders).' }
        status             = @{ Description='Lifecycle state.'; Enum=@('active','retired','compromised','archived') }
        is_backup_encrypted= @{ Description='Backup blob is encrypted with KEK.' }
        backup_blob        = @{ Description='Encrypted backup (binary).'; PII='encrypted' }
        created_by         = @{ Description='Admin user who created key (FK users.id).' }
        created_at         = @{ Description='Creation timestamp (UTC).' }
        activated_at       = @{ Description='Activation timestamp.' }
        retired_at         = @{ Description='Retirement timestamp.' }
        replaced_by        = @{ Description='Next key id when rotated.' }
        notes              = @{ Description='Free-form notes.' }
      }
    }

    email_verifications = @{
      Summary = 'Email verification tokens for users.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        user_id          = @{ Description='Related user (FK users.id).' }
        token_hash       = @{ Description='Full token hash (hex/char).'; PII='token' }
        selector         = @{ Description='Short public selector (unique).' }
        validator_hash   = @{ Description='Hashed validator part.'; PII='hashed' }
        key_version      = @{ Description='Key version used for hashing/encryption.' }
        expires_at       = @{ Description='Expiration timestamp (UTC).' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
        used_at          = @{ Description='When token was used, if so.' }
      }
    }

    encrypted_fields = @{
      Summary = 'Per-field encryption store for arbitrary entities.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        entity_table= @{ Description='Referenced table name.' }
        entity_pk   = @{ Description='Referenced entity primary key (string).' }
        field_name  = @{ Description='Encrypted field name.' }
        ciphertext  = @{ Description='Encrypted payload.'; PII='encrypted' }
        meta        = @{ Description='Encryption metadata (JSON).' }
        created_at  = @{ Description='Creation timestamp (UTC).' }
        updated_at  = @{ Description='Update timestamp (UTC).' }
      }
    }

    encryption_events = @{
      Summary = 'Audit of cryptographic operations.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        entity_table     = @{ Description='Entity table name.' }
        entity_pk        = @{ Description='Entity primary key.' }
        field_name       = @{ Description='Target field.' }
        op               = @{ Description='Operation performed.'; Enum=@('encrypt','decrypt','rotate','rehash','unwrap','wrap') }
        policy_id        = @{ Description='Applied policy (FK encryption_policies.id), optional.' }
        local_key_version= @{ Description='Local key version used.' }
        layers           = @{ Description='JSON list of layers/steps.' }
        outcome          = @{ Description='Result.'; Enum=@('success','failure') }
        error_code       = @{ Description='Error code when failure.' }
        created_at       = @{ Description='Timestamp (UTC).' }
      }
    }

    encryption_policies = @{
      Summary = 'Encryption policy registry and parameters. policy_name is UNIQUE.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        policy_name    = @{ Description='Unique policy name (UNIQUE).' }
        mode           = @{ Description='Execution mode.'; Enum=@('local','kms','multi-kms') }
        layer_selection= @{ Description='Layer selection algorithm.'; Enum=@('defined','round_robin','random','hash_mod') }
        min_layers     = @{ Description='Minimum layers.' }
        max_layers     = @{ Description='Maximum layers.' }
        aad_template   = @{ Description='AAd JSON template.' }
        notes          = @{ Description='Free-form notes.' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    idempotency_keys = @{
      Summary = 'Idempotency keys to deduplicate external payment/API requests.'
      Columns = @{
        key_hash     = @{ Description='Key hash (natural PK).'; PII='token' }
        payment_id   = @{ Description='Related payment (FK payments.id), optional.' }
        order_id     = @{ Description='Related order (FK orders.id), optional.' }
        gateway_payload = @{ Description='Original payload JSON.' }
        redirect_url = @{ Description='Client redirect URL (if any).' }
        created_at   = @{ Description='Creation timestamp (UTC).' }
        ttl_seconds  = @{ Description='Time-to-live in seconds (> 0).' }
      }
    }

    inventory_reservations = @{
      Summary = 'Temporary stock reservations tied to orders.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        order_id       = @{ Description='Order (FK orders.id), optional.' }
        book_id        = @{ Description='Book (FK books.id).' }
        quantity       = @{ Description='Reserved quantity (> 0).' }
        reserved_until = @{ Description='Expiration timestamp (UTC).' }
        status         = @{ Description='Reservation state.'; Enum=@('pending','confirmed','expired','cancelled') }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    invoice_items = @{
      Summary = 'Normalized invoice line items.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        invoice_id  = @{ Description='Invoice (FK invoices.id).' }
        line_no     = @{ Description='Line number within invoice.' }
        description = @{ Description='Line description.' }
        unit_price  = @{ Description='Unit price excl. tax.' }
        quantity    = @{ Description='Quantity (> 0).' }
        tax_rate    = @{ Description='Tax rate % (0..100).' }
        tax_amount  = @{ Description='Tax amount.' }
        line_total  = @{ Description='Total incl. tax for line.' }
        currency    = @{ Description='ISO 4217 currency code.' }
      }
    }

    invoices = @{
      Summary = 'Issued invoices linked to orders. invoice_number is UNIQUE.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        order_id        = @{ Description='Order (FK orders.id), optional.' }
        invoice_number  = @{ Description='Unique invoice number (UNIQUE).' }
        variable_symbol = @{ Description='Local payment identifier/VS.' }
        issue_date      = @{ Description='Issue date.' }
        due_date        = @{ Description='Due date (optional).' }
        subtotal        = @{ Description='Subtotal excl. discounts & tax.' }
        discount_total  = @{ Description='Total discount amount.' }
        tax_total       = @{ Description='Total tax amount.' }
        total           = @{ Description='Grand total.' }
        currency        = @{ Description='ISO 4217 currency code.' }
        qr_data         = @{ Description='Encoded payment data (string/QR).' }
        created_at      = @{ Description='Creation timestamp (UTC).' }
      }
    }

    jwt_tokens = @{
      Summary = 'Refresh/API token registry with revocation support.'
      Columns = @{
        id                    = @{ Description='Surrogate primary key.' }
        jti                   = @{ Description='JWT ID (unique).' }
        user_id               = @{ Description='User (FK users.id), optional.' }
        token_hash            = @{ Description='Hashed token.'; PII='hashed' }
        token_hash_algo       = @{ Description='Hash algorithm.' }
        token_hash_key_version= @{ Description='Key version used for token hashing.' }
        type                  = @{ Description='Token kind.'; Enum=@('refresh','api') }
        scopes                = @{ Description='Space/comma separated scopes.' }
        created_at            = @{ Description='Creation timestamp (UTC).' }
        expires_at            = @{ Description='Expiration timestamp (UTC).' }
        last_used_at          = @{ Description='Last usage (UTC).' }
        ip_hash               = @{ Description='Hashed client IP.'; PII='hashed' }
        ip_hash_key_version   = @{ Description='Key version for ip_hash.' }
        replaced_by           = @{ Description='Newer token id (token rotation).' }
        revoked               = @{ Description='Revocation flag.' }
        meta                  = @{ Description='Additional JSON metadata.' }
      }
    }

    key_events = @{
      Summary = 'Operational log for crypto key lifecycle and usage.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        key_id     = @{ Description='Key (FK crypto_keys.id), optional.' }
        basename   = @{ Description='Key basename, if id not present.' }
        event_type = @{ Description='Event type.'; Enum=@('created','rotated','activated','retired','compromised','deleted','used_encrypt','used_decrypt','access_failed','backup','restore') }
        actor_id   = @{ Description='Actor (FK users.id), optional.' }
        job_id     = @{ Description='Batch/job id, optional.' }
        note       = @{ Description='Free-form note.' }
        meta       = @{ Description='JSON meta about event.' }
        source     = @{ Description='Origin of event.'; Enum=@('cron','admin','api','manual') }
        created_at = @{ Description='Timestamp (UTC).' }
      }
    }

    key_rotation_jobs = @{
      Summary = 'Planned and executed key rotation jobs.'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        basename      = @{ Description='Key basename to rotate.' }
        target_version= @{ Description='Desired target version (nullable).' }
        scheduled_at  = @{ Description='Scheduled time (UTC).' }
        started_at    = @{ Description='Start time (UTC).' }
        finished_at   = @{ Description='Finish time (UTC).' }
        status        = @{ Description='Job status.'; Enum=@('pending','running','done','failed','cancelled') }
        attempts      = @{ Description='Number of attempts.' }
        executed_by   = @{ Description='Operator user id (FK users.id), optional.' }
        result        = @{ Description='Result/summary text.' }
        created_at    = @{ Description='Creation timestamp (UTC).' }
      }
    }

    key_usage = @{
      Summary = 'Daily counters of key operations.'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        key_id        = @{ Description='Key (FK crypto_keys.id).' }
        date          = @{ Description='UTC date (yyyy-mm-dd).' }
        encrypt_count = @{ Description='Encrypt operations count.' }
        decrypt_count = @{ Description='Decrypt operations count.' }
        verify_count  = @{ Description='Verify operations count.' }
        last_used_at  = @{ Description='Last usage timestamp (UTC).' }
      }
    }

    kms_keys = @{
      Summary = 'External KMS key references. UNIQUE (provider_id, external_key_ref).'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        provider_id      = @{ Description='KMS provider (FK kms_providers.id).' }
        external_key_ref = @{ Description='Provider-specific key identifier. Part of UNIQUE (provider_id, external_key_ref).' }
        purpose          = @{ Description='Primary purpose.'; Enum=@('wrap','encrypt','both') }
        algorithm        = @{ Description='Algorithm or template id.' }
        status           = @{ Description='Lifecycle status.'; Enum=@('active','retired','disabled') }
        created_at       = @{ Description='Creation timestamp (UTC).' }
      }
    }

    kms_providers = @{
      Summary = 'Configured KMS providers. name is UNIQUE.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        name            = @{ Description='Display name (UNIQUE).' }
        provider        = @{ Description='Provider kind.'; Enum=@('gcp','aws','azure','vault') }
        location        = @{ Description='Region or location.' }
        project_tenant  = @{ Description='Project/tenant id.' }
        created_at      = @{ Description='Creation timestamp (UTC).' }
        is_enabled      = @{ Description='Whether provider is enabled.' }
      }
    }

    login_attempts = @{
      Summary = 'Login attempts per IP and (optional) user.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        ip_hash          = @{ Description='Hashed client IP.'; PII='hashed' }
        attempted_at     = @{ Description='Attempt time (UTC).' }
        success          = @{ Description='Whether authentication succeeded.' }
        user_id          = @{ Description='User (FK users.id), optional.' }
        username_hash    = @{ Description='Hashed username/email provided.'; PII='hashed' }
        auth_event_id    = @{ Description='Link to auth_events record, optional.' }
      }
    }

    newsletter_subscribers = @{
      Summary = 'Newsletter subscription registry with double opt-in. email_hash is UNIQUE; confirm_selector is UNIQUE.'
      Columns = @{
        id                          = @{ Description='Surrogate primary key.' }
        user_id                     = @{ Description='Related user (optional).' }
        email_hash                  = @{ Description='Hashed email value (UNIQUE).'; PII='hashed' }
        email_hash_key_version      = @{ Description='Key version for email_hash.' }
        email_enc                   = @{ Description='Encrypted email address.'; PII='encrypted' }
        email_key_version           = @{ Description='Key version for email_enc.' }
        confirm_selector            = @{ Description='Public selector for confirmation (UNIQUE).' }
        confirm_validator_hash      = @{ Description='Hashed validator token.'; PII='hashed' }
        confirm_key_version         = @{ Description='Key version for confirmation hash.' }
        confirm_expires             = @{ Description='Confirmation expiry (UTC).' }
        confirmed_at                = @{ Description='Confirmation timestamp (UTC).' }
        unsubscribe_token_hash      = @{ Description='Hashed unsubscribe token.'; PII='hashed' }
        unsubscribe_token_key_version= @{ Description='Key version for unsubscribe hash.' }
        unsubscribed_at             = @{ Description='Unsubscribe timestamp (UTC).' }
        origin                      = @{ Description='Acquisition source (e.g., form, import).' }
        ip_hash                     = @{ Description='Hashed IP of action.'; PII='hashed' }
        ip_hash_key_version         = @{ Description='Key version for ip_hash.' }
        meta                        = @{ Description='JSON metadata (UTM, tags).' }
        created_at                  = @{ Description='Creation timestamp (UTC).' }
        updated_at                  = @{ Description='Update timestamp (UTC).' }
      }
    }

    notifications = @{
      Summary = 'Outbox for templated user notifications.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        user_id          = @{ Description='Target user (optional).' }
        channel          = @{ Description='Delivery channel.'; Enum=@('email','push') }
        template         = @{ Description='Template identifier.' }
        payload          = @{ Description='JSON payload for template rendering.' }
        status           = @{ Description='Processing status.'; Enum=@('pending','processing','sent','failed') }
        retries          = @{ Description='Attempt counter.' }
        max_retries      = @{ Description='Maximum attempts.' }
        next_attempt_at  = @{ Description='Backoff until (UTC).' }
        scheduled_at     = @{ Description='Scheduled send time (UTC).' }
        sent_at          = @{ Description='Actual send time (UTC).' }
        error            = @{ Description='Last error message.' }
        last_attempt_at  = @{ Description='Last attempt time (UTC).' }
        locked_until     = @{ Description='Worker lock until (UTC).' }
        locked_by        = @{ Description='Worker id that holds the lock.' }
        priority         = @{ Description='Priority (higher = sooner).' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
        updated_at       = @{ Description='Update timestamp (UTC).' }
      }
    }

    order_item_downloads = @{
      Summary = 'Per-order download entitlements for digital items. UNIQUE (order_id, book_id, asset_id).'
      Columns = @{
        id                   = @{ Description='Surrogate primary key.' }
        order_id             = @{ Description='Order (FK orders.id).' }
        book_id              = @{ Description='Book (FK books.id).' }
        asset_id             = @{ Description='Asset (FK book_assets.id).' }
        download_token_hash  = @{ Description='Hashed download token (dedupe/lookup).'; PII='hashed' }
        token_key_version    = @{ Description='Key version used for download_token_hash.' }
        key_version          = @{ Description='Content encryption key version.' }
        max_uses             = @{ Description='Max allowed downloads.' }
        used                 = @{ Description='Number of uses so far.' }
        expires_at           = @{ Description='Expiry timestamp (UTC).' }
        last_used_at         = @{ Description='Last download timestamp (UTC).' }
        ip_hash              = @{ Description='Hashed IP of last usage.'; PII='hashed' }
        ip_hash_key_version  = @{ Description='Key version for ip_hash.' }
      }
    }

    order_items = @{
      Summary = 'Normalized order line items (snapshotted data).'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        order_id      = @{ Description='Order (FK orders.id).' }
        book_id       = @{ Description='Book (FK books.id), optional for non-book items.' }
        product_ref   = @{ Description='External product reference (optional).' }
        title_snapshot= @{ Description='Captured title at purchase time.' }
        sku_snapshot  = @{ Description='Captured SKU at purchase time.' }
        unit_price    = @{ Description='Unit price at purchase.' }
        quantity      = @{ Description='Quantity (> 0).' }
        tax_rate      = @{ Description='Tax rate % (0..100).' }
        currency      = @{ Description='ISO 4217 currency code.' }
      }
    }

    orders = @{
      Summary = 'Orders lifecycle, totals, and encrypted customer blob.'
      Columns = @{
        id                               = @{ Description='Surrogate primary key.' }
        uuid                             = @{ Description='Unique external order id (UUID text).' }
        uuid_bin                         = @{ Description='UUID binary form (unique, for compact lookups).' }
        public_order_no                  = @{ Description='Human-friendly order number.' }
        user_id                          = @{ Description='Customer (FK users.id), optional (guest checkout).' }
        status                           = @{ Description='Order state.'; Enum=@('pending','paid','failed','cancelled','refunded','completed') }
        encrypted_customer_blob          = @{ Description='Encrypted PII/customer details.'; PII='encrypted' }
        encrypted_customer_blob_key_version = @{ Description='Key version of encrypted blob.' }
        encryption_meta                  = @{ Description='JSON encryption metadata.' }
        currency                         = @{ Description='ISO 4217 currency code.' }
        metadata                         = @{ Description='JSON with auxiliary metadata.' }
        subtotal                         = @{ Description='Subtotal amount.' }
        discount_total                   = @{ Description='Discount total.' }
        tax_total                        = @{ Description='Tax total.' }
        total                            = @{ Description='Grand total.' }
        payment_method                   = @{ Description='Selected payment method.' }
        created_at                       = @{ Description='Creation timestamp (UTC).' }
        updated_at                       = @{ Description='Update timestamp (UTC).' }
      }
    }

    payment_gateway_notifications = @{
      Summary = 'Inbound notifications from payment gateways (webhooks, IPNs). transaction_id is REQUIRED and UNIQUE.'
      Columns = @{
        id                = @{ Description='Surrogate primary key.' }
        transaction_id    = @{ Description='Gateway transaction id (REQUIRED, UNIQUE).' }
        received_at       = @{ Description='When we received the notification (UTC).' }
        processing_by     = @{ Description='Worker name processing the event.' }
        processing_until  = @{ Description='Lease end.' }
        attempts          = @{ Description='Processing attempts.' }
        last_error        = @{ Description='Last error message.' }
        status            = @{ Description='Processing status.'; Enum=@('pending','processing','done','failed') }
      }
    }

    payment_logs = @{
      Summary = 'Plaintext logs per payment.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        payment_id = @{ Description='Payment (FK payments.id).' }
        log_at     = @{ Description='Log time (UTC).' }
        message    = @{ Description='Log message.' }
      }
    }

    payment_webhooks = @{
      Summary = 'Raw webhook payloads (deduplicated by payload_hash UNIQUE).'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        payment_id       = @{ Description='Payment (FK payments.id), optional.' }
        gateway_event_id = @{ Description='Gateway event id, optional.' }
        payload_hash     = @{ Description='Hash of payload for dedupe (UNIQUE).' }
        payload          = @{ Description='Original JSON payload.' }
        from_cache       = @{ Description='Marked if sourced from cache/retry.' }
        created_at       = @{ Description='Received at (UTC).' }
      }
    }

    payments = @{
      Summary = 'Payment attempts and final captures for orders.'
      Columns = @{
        id                = @{ Description='Surrogate primary key.' }
        order_id          = @{ Description='Order (FK orders.id).' }
        gateway           = @{ Description='Payment gateway key (e.g., stripe, gopay).' }
        transaction_id    = @{ Description='Provider transaction id (unique if provided).' }
        provider_event_id = @{ Description='Provider event id (optional).' }
        status            = @{ Description='Payment state.'; Enum=@('initiated','pending','authorized','paid','cancelled','partially_refunded','refunded','failed') }
        amount            = @{ Description='Payment amount. Must be >= 0.' }
        currency          = @{ Description='ISO 4217 currency code.' }
        details           = @{ Description='JSON with provider details/receipts.' }
        created_at        = @{ Description='Creation timestamp (UTC).' }
        updated_at        = @{ Description='Update timestamp (UTC).' }
      }
    }

    permissions = @{
      Summary = 'Application permission catalog.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        name        = @{ Description='Unique permission name.' }
        description = @{ Description='Human description.' }
        created_at  = @{ Description='Creation timestamp (UTC).' }
        updated_at  = @{ Description='Update timestamp (UTC).' }
      }
    }

    policy_kms_keys = @{
      Summary = 'KMS key assignments per encryption policy. PRIMARY KEY (policy_id, kms_key_id).'
      Columns = @{
        policy_id = @{ Description='Policy (FK encryption_policies.id).' }
        kms_key_id= @{ Description='KMS key (FK kms_keys.id).' }
        weight    = @{ Description='Weight for selection algorithms.' }
        priority  = @{ Description='Priority (higher first).' }
      }
    }

    refunds = @{
      Summary = 'Payment refunds and their status.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        payment_id = @{ Description='Payment (FK payments.id).' }
        amount     = @{ Description='Refund amount (>= 0).' }
        currency   = @{ Description='ISO 4217 currency code.' }
        reason     = @{ Description='Reason provided by operator/gateway.' }
        status     = @{ Description='Gateway/state status label.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
        details    = @{ Description='JSON details from provider.' }
      }
    }

    register_events = @{
      Summary = 'Registration related events (success/failure).'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        user_id            = @{ Description='User (FK users.id), optional.' }
        type               = @{ Description='Event type.'; Enum=@('register_success','register_failure') }
        ip_hash            = @{ Description='Hashed client IP.'; PII='hashed' }
        ip_hash_key_version= @{ Description='Key version for ip_hash.' }
        user_agent         = @{ Description='Client user agent.' }
        occurred_at        = @{ Description='When event occurred (UTC).' }
        meta               = @{ Description='JSON metadata.' }
      }
    }

    reviews = @{
      Summary = 'User reviews and ratings for books. UNIQUE (book_id, user_id) — one user can only rate a book once.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        book_id     = @{ Description='Book (FK books.id).' }
        user_id     = @{ Description='Authoring user (FK users.id), optional.' }
        rating      = @{ Description='Rating 1..5.' }
        review_text = @{ Description='Free-form review text.' }
        created_at  = @{ Description='Creation timestamp (UTC).' }
        updated_at  = @{ Description='Last update (UTC), optional.' }
      }
    }

    session_audit = @{
      Summary = 'Low-level session lifecycle and security events.'
      Columns = @{
        id                      = @{ Description='Surrogate primary key.' }
        session_token           = @{ Description='Hashed session token.'; PII='hashed' }
        session_token_key_version = @{ Description='Key version for session_token.' }
        csrf_key_version        = @{ Description='Key version for CSRF related data.' }
        session_id              = @{ Description='Framework session id (string).' }
        event                   = @{ Description='Event code (e.g., created, rotated, revoked).' }
        user_id                 = @{ Description='User (FK users.id), optional.' }
        ip_hash                 = @{ Description='Hashed IP.'; PII='hashed' }
        ip_hash_key_version     = @{ Description='Key version for ip_hash.' }
        user_agent              = @{ Description='Client user agent.' }
        meta_json               = @{ Description='JSON metadata.' }
        outcome                 = @{ Description='Outcome label (e.g., success, fail).' }
        created_at              = @{ Description='Event timestamp (UTC).' }
      }
    }

    sessions = @{
      Summary = 'Active/expired sessions and their lifecycle.'
      Columns = @{
        id                    = @{ Description='Surrogate primary key.' }
        token_hash            = @{ Description='Hashed session token.'; PII='hashed' }
        token_hash_key_version= @{ Description='Key version for token_hash.' }
        token_fingerprint     = @{ Description='Stable token fingerprint (hashed).'; PII='hashed' }
        token_issued_at       = @{ Description='Original token issue time (UTC).' }
        user_id               = @{ Description='User (FK users.id), optional.' }
        created_at            = @{ Description='Creation timestamp (UTC).' }
        last_seen_at          = @{ Description='Last activity timestamp (UTC).' }
        expires_at            = @{ Description='Expiration timestamp (UTC).' }
        failed_decrypt_count  = @{ Description='Number of failed decrypt attempts.' }
        last_failed_decrypt_at= @{ Description='Timestamp of last failed decrypt.' }
        revoked               = @{ Description='Revocation flag.' }
        ip_hash               = @{ Description='Hashed client IP.'; PII='hashed' }
        ip_hash_key_version   = @{ Description='Key version for ip_hash.' }
        user_agent            = @{ Description='Client user agent.' }
        session_blob          = @{ Description='Optional encrypted session payload.'; PII='encrypted' }
      }
    }

    system_errors = @{
      Summary = 'Application error/event log with grouping and resolution.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        level            = @{ Description='Severity level.'; Enum=@('notice','warning','error','critical') }
        message          = @{ Description='Error message.' }
        exception_class  = @{ Description='Exception class name (if any).' }
        file             = @{ Description='Source file path.' }
        line             = @{ Description='Source line number.' }
        stack_trace      = @{ Description='Long stack trace.' }
        token            = @{ Description='Correlated token/id.' }
        context          = @{ Description='JSON context (structured).' }
        fingerprint      = @{ Description='Deduplication fingerprint.' }
        occurrences      = @{ Description='Aggregate count of occurrences.' }
        user_id          = @{ Description='Related user (optional).' }
        ip_hash          = @{ Description='Hashed IP.'; PII='hashed' }
        ip_hash_key_version = @{ Description='Key version for ip_hash.' }
        ip_text          = @{ Description='Plaintext IP (if captured).' ; PII='plain' }
        ip_bin           = @{ Description='Binary IP (if captured).' }
        user_agent       = @{ Description='User agent string.' }
        url              = @{ Description='Request URL.' }
        method           = @{ Description='HTTP method.' }
        http_status      = @{ Description='HTTP status code.' }
        resolved         = @{ Description='Resolution flag.' }
        resolved_by      = @{ Description='Resolver user id (FK users.id), optional.' }
        resolved_at      = @{ Description='Resolution timestamp (UTC).' }
        created_at       = @{ Description='First occurrence (UTC).' }
        last_seen        = @{ Description='Most recent occurrence (UTC).' }
      }
    }

    system_jobs = @{
      Summary = 'Asynchronous background jobs (generic).'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        job_type     = @{ Description='Job type key.' }
        payload      = @{ Description='JSON payload.' }
        status       = @{ Description='Processing status.'; Enum=@('pending','processing','done','failed') }
        retries      = @{ Description='Retry count.' }
        scheduled_at = @{ Description='Schedule time (UTC).' }
        started_at   = @{ Description='Start time (UTC).' }
        finished_at  = @{ Description='Finish time (UTC).' }
        error        = @{ Description='Last error message.' }
        created_at   = @{ Description='Creation timestamp (UTC).' }
        updated_at   = @{ Description='Update timestamp (UTC).' }
      }
    }

    tax_rates = @{
      Summary = 'Tax rates per country and goods category. UNIQUE (country_iso2, category, valid_from).'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        country_iso2 = @{ Description='ISO 3166-1 alpha-2 country code.' }
        category     = @{ Description='Tax category.'; Enum=@('ebook','physical') }
        rate         = @{ Description='Tax rate %.' }
        valid_from   = @{ Description='Effective from (date).' }
        valid_to     = @{ Description='Effective to (date), optional.' }
      }
    }

    two_factor = @{
      Summary = 'Second factor configuration per user/method.'
      Columns = @{
        user_id            = @{ Description='User (FK users.id).' }
        method             = @{ Description='2FA method key (e.g., totp, hotp, webauthn).' }
        secret             = @{ Description='Shared secret (encrypted/encoded).'; PII='encrypted' }
        recovery_codes_enc = @{ Description='Encrypted recovery codes.'; PII='encrypted' }
        hotp_counter       = @{ Description='HOTP counter (if HOTP).' }
        enabled            = @{ Description='Whether method is enabled.' }
        created_at         = @{ Description='Creation timestamp (UTC).' }
        last_used_at       = @{ Description='Last successful use (UTC).' }
      }
    }

    user_consents = @{
      Summary = 'Captured consents per user and version. UNIQUE (user_id, consent_type, version).'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        user_id     = @{ Description='User (FK users.id).' }
        consent_type= @{ Description='Consent type key.' }
        version     = @{ Description='Document/policy version string.' }
        granted     = @{ Description='Granted flag (true/false).' }
        granted_at  = @{ Description='When consent was recorded (UTC).' }
        source      = @{ Description='Source (e.g., web, import).' }
        meta        = @{ Description='JSON meta (IP, UA, doc hash).' }
      }
    }

    user_identities = @{
      Summary = 'External identity links (OAuth/OpenID/etc.). One row per (provider, provider_user_id).'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        user_id          = @{ Description='User (FK users.id).' }
        provider         = @{ Description='Provider key (e.g., google, github). Part of UNIQUE (provider, provider_user_id).' }
        provider_user_id = @{ Description='User id at provider. Part of UNIQUE (provider, provider_user_id).' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
        updated_at       = @{ Description='Update timestamp (UTC).' }
      }
    }

    user_profiles = @{
      Summary = 'Encrypted user profile blob (optional).'
      Columns = @{
        user_id        = @{ Description='User (FK users.id), also PK.' }
        profile_enc    = @{ Description='Encrypted profile payload.'; PII='encrypted' }
        key_version    = @{ Description='Key version for profile_enc.' }
        encryption_meta= @{ Description='JSON meta of encryption.' }
        updated_at     = @{ Description='Last update timestamp (UTC).' }
      }
    }

    users = @{
      Summary = 'User accounts and authentication attributes.'
      Columns = @{
        id                       = @{ Description='Surrogate primary key.' }
        email_hash               = @{ Description='Hashed email (salted/peppered). UNIQUE.'; PII='hashed' }
        email_hash_key_version   = @{ Description='Key version for email_hash.' }
        password_hash            = @{ Description='Password hash string.'; PII='hashed' }
        password_algo            = @{ Description='Password hash algorithm id.' }
        password_key_version     = @{ Description='Key/pepper version for passwords.' }
        is_active                = @{ Description='Account enabled flag.' }
        is_locked                = @{ Description='Lock flag (manual/automatic).' }
        failed_logins            = @{ Description='Failed login counter.' }
        must_change_password     = @{ Description='Force password change at next login.' }
        last_login_at            = @{ Description='Last successful login (UTC).' }
        last_login_ip_hash       = @{ Description='Hashed last login IP.'; PII='hashed' }
        last_login_ip_key_version= @{ Description='Key version for last_login_ip_hash.' }
        created_at               = @{ Description='Creation timestamp (UTC).' }
        updated_at               = @{ Description='Update timestamp (UTC).' }
        deleted_at               = @{ Description='Soft delete timestamp.' }
        actor_role               = @{ Description='Role within application.'; Enum=@('customer','admin') }
      }
    }

    vat_validations = @{
      Summary = 'External VAT ID validation results (cache).'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        vat_id      = @{ Description='VAT identifier as provided.' }
        country_iso2= @{ Description='Country ISO2 of VAT id.' }
        valid       = @{ Description='Validation result (true/false).' }
        checked_at  = @{ Description='When checked (UTC).' }
        raw         = @{ Description='Raw JSON response payload.' }
      }
    }

    verify_events = @{
      Summary = 'Verification events (email/phone, other checks).'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        user_id            = @{ Description='Related user (FK users.id), optional.' }
        type               = @{ Description='Verification type.'; Enum=@('verify_success','verify_failure') }
        ip_hash            = @{ Description='Hashed IP.'; PII='hashed' }
        ip_hash_key_version= @{ Description='Key version for ip_hash.' }
        user_agent         = @{ Description='Client user agent.' }
        occurred_at        = @{ Description='When event occurred (UTC).' }
        meta               = @{ Description='JSON metadata.' }
      }
    }

    webhook_outbox = @{
      Summary = 'Outbox table for delivering webhooks.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        event_type      = @{ Description='Webhook event key.' }
        payload         = @{ Description='JSON payload.' }
        status          = @{ Description='Delivery status.'; Enum=@('pending','sent','failed') }
        retries         = @{ Description='Retry counter.' }
        next_attempt_at = @{ Description='Next attempt time (UTC).' }
        created_at      = @{ Description='Creation timestamp (UTC).' }
        updated_at      = @{ Description='Update timestamp (UTC).' }
      }
    }

    worker_locks = @{
      Summary = 'Distributed/DB-backed locks for background workers.'
      Columns = @{
        name         = @{ Description='Lock name (primary key).' }
        locked_until = @{ Description='Lease expiration time (UTC).' }
      }
    }

    api_keys = @{
      Summary = 'Tenant/user scoped API tokens stored only as hashed secrets.'
      Columns = @{
        id                    = @{ Description='Surrogate primary key.' }
        tenant_id             = @{ Description='Owning tenant (FK tenants.id).' }
        user_id               = @{ Description='User that created the token (FK users.id), optional.' }
        name                  = @{ Description='Human-friendly token label.' }
        name_ci               = @{ Description='Case-insensitive token label (generated).' }
        token_hash            = @{ Description='Hashed token payload.'; PII='hashed' }
        token_hash_key_version= @{ Description='Key version used when hashing the token.' }
        scopes                = @{ Description='JSON array with granted scopes.' }
        status                = @{ Description='Lifecycle status flag.'; Enum=@('active','revoked','disabled') }
        last_used_at          = @{ Description='Last usage timestamp (UTC).' }
        expires_at            = @{ Description='Optional expiration timestamp.' }
        created_at            = @{ Description='Creation timestamp (UTC).' }
        updated_at            = @{ Description='Last update timestamp (UTC).' }
      }
    }

    audit_chain = @{
      Summary = 'Hash chain built on top of audit_log entries for tamper evidence.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        audit_id    = @{ Description='Audit entry id (FK audit_log.id).' }
        chain_name  = @{ Description='Chain namespace (multiple chains may coexist).' }
        prev_hash   = @{ Description='Hash of the previous audit entry in the chain.' }
        hash        = @{ Description='Hash of the current entry.' }
        created_at  = @{ Description='Creation timestamp (UTC).' }
      }
    }

    crypto_algorithms = @{
      Summary = 'Catalog of supported cryptographic primitives.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        class       = @{ Description='Algorithm class.'; Enum=@('kem','sig','hash','symmetric') }
        name        = @{ Description='Canonical algorithm name (e.g., ML-KEM-768).' }
        variant     = @{ Description='Optional variant descriptor (hybrid, FIPS profile, etc.).' }
        nist_level  = @{ Description='Post-quantum NIST security level, if any.' }
        status      = @{ Description='Lifecycle flag.'; Enum=@('active','deprecated','experimental') }
        params      = @{ Description='JSON metadata with algorithm-specific parameters.' }
        created_at  = @{ Description='Catalog insertion timestamp (UTC).' }
      }
    }

    crypto_standard_aliases = @{
      Summary = 'Friendly aliases mapped to crypto_algorithms entries.'
      Columns = @{
        alias      = @{ Description='Alias string (primary key).' }
        algo_id    = @{ Description='Target algorithm id (FK crypto_algorithms.id).' }
        notes      = @{ Description='Optional documentation or rollout notes.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
      }
    }

    data_retention_policies = @{
      Summary = 'Declarative data-retention rules describing purge/anonymize actions.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        entity_table = @{ Description='Table affected by the policy.' }
        field_name   = @{ Description='Optional column restricted by the policy.' }
        action       = @{ Description='Retention action.'; Enum=@('delete','anonymize','hash','truncate') }
        keep_for     = @{ Description='Retention window (interval / textual duration).' }
        active       = @{ Description='Whether the policy is currently enforced.' }
        notes        = @{ Description='Operational notes or audit context.' }
        created_at   = @{ Description='Creation timestamp (UTC).' }
      }
    }

    deletion_jobs = @{
      Summary = 'Asynchronous deletion workflows coordinating cascading cleanup.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        entity_table = @{ Description='Target table for the deletion.' }
        entity_pk    = @{ Description='Primary key of the row to delete.' }
        reason       = @{ Description='Reason the deletion was requested.' }
        hard_delete  = @{ Description='Whether to permanently delete the row.' }
        scheduled_at = @{ Description='When the job should start.' }
        started_at   = @{ Description='Processing start timestamp (UTC).' }
        finished_at  = @{ Description='Completion timestamp (UTC).' }
        status       = @{ Description='Job status flag.'; Enum=@('pending','running','done','failed','cancelled') }
        error        = @{ Description='Failure description, if any.' }
        created_by   = @{ Description='User/admin that created the job.' }
        created_at   = @{ Description='Creation timestamp (UTC).' }
      }
    }

    device_fingerprints = @{
      Summary = 'Known device/browser fingerprints with derived risk scoring.'
      Columns = @{
        id                 = @{ Description='Surrogate primary key.' }
        user_id            = @{ Description='Related user (FK users.id), nullable.' }
        fingerprint_hash   = @{ Description='Stable hash of the fingerprint payload.'; PII='hashed' }
        attributes         = @{ Description='JSON blob with device characteristics.' }
        risk_score         = @{ Description='0-100 risk score derived from signals.' }
        first_seen         = @{ Description='Timestamp when the device first appeared.' }
        last_seen          = @{ Description='Last time the device was observed.' }
        last_ip_hash       = @{ Description='Hashed last known IP.'; PII='hashed' }
        last_ip_key_version= @{ Description='Key version used for last_ip_hash.' }
      }
    }

    encryption_bindings = @{
      Summary = 'Bindings assigning specific key wrappers to encrypted entity fields.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        entity_table   = @{ Description='Table name containing encrypted data.' }
        entity_pk      = @{ Description='Primary key value of the encrypted row.' }
        field_name     = @{ Description='Encrypted column name; NULL = whole row binding.' }
        key_wrapper_id = @{ Description='Assigned key wrapper (FK key_wrappers.id).' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    encryption_policy_bindings = @{
      Summary = 'History of which encryption policy applies to a field.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        entity_table   = @{ Description='Table name.' }
        field_name     = @{ Description='Column that the policy covers.' }
        policy_id      = @{ Description='Policy identifier (FK encryption_policies.id).' }
        effective_from = @{ Description='Timestamp when the policy becomes active.' }
        notes          = @{ Description='Documentation / rollout notes.' }
      }
    }

    entity_external_ids = @{
      Summary = 'Links between local entities and identifiers in external systems.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        entity_table = @{ Description='Local table name.' }
        entity_pk    = @{ Description='Primary key value of the local record.' }
        source       = @{ Description='External system identifier.' }
        external_id  = @{ Description='External ID for the record.' }
        created_at   = @{ Description='Creation timestamp (UTC).' }
      }
    }

    event_dlq = @{
      Summary = 'Dead-letter queue holding events that failed permanently.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        source         = @{ Description='Event source or producer system.' }
        event_key      = @{ Description='Event key / idempotency token.' }
        event          = @{ Description='Original event payload (JSON).' }
        error          = @{ Description='Error message explaining the failure.' }
        retryable      = @{ Description='Whether the event can be retried safely.' }
        attempts       = @{ Description='How many attempts were made.' }
        first_failed_at= @{ Description='Timestamp of the first failure.' }
        last_failed_at = @{ Description='Timestamp of the latest failure.' }
      }
    }

    event_inbox = @{
      Summary = 'Inbox table for inbound events awaiting processing.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        source       = @{ Description='Producer system identifier.' }
        event_key    = @{ Description='Event key used for idempotency.' }
        payload      = @{ Description='JSON payload to be processed.' }
        status       = @{ Description='Processing status flag.'; Enum=@('pending','processed','failed') }
        attempts     = @{ Description='Number of processing attempts.' }
        last_error   = @{ Description='Last error message written for the event.' }
        received_at  = @{ Description='When the event was received (UTC).' }
        processed_at = @{ Description='When processing finished (UTC).' }
      }
    }

    event_outbox = @{
      Summary = 'Outbox table for domain events waiting to be published downstream.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        event_key      = @{ Description='Event key / idempotency token.' }
        entity_table   = @{ Description='Originating table.' }
        entity_pk      = @{ Description='Primary key of the originating row.' }
        event_type     = @{ Description='Event type string.' }
        payload        = @{ Description='JSON payload delivered to consumers.' }
        status         = @{ Description='Delivery status.'; Enum=@('pending','sent','failed') }
        attempts       = @{ Description='Number of delivery attempts.' }
        next_attempt_at= @{ Description='When the next attempt is scheduled.' }
        processed_at   = @{ Description='When processing completed.' }
        producer_node  = @{ Description='Node that produced the event.' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    field_hash_policies = @{
      Summary = 'Effective hashing policy assignments for sensitive columns.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        entity_table   = @{ Description='Table where the field lives.' }
        field_name     = @{ Description='Column name.' }
        profile_id     = @{ Description='Hash profile applied (FK hash_profiles.id).' }
        effective_from = @{ Description='Timestamp when the policy takes effect.' }
        notes          = @{ Description='Documentation / migration context.' }
      }
    }

    global_id_registry = @{
      Summary = 'ULID/UUID registry for mapping global ids to local tables.'
      Columns = @{
        gid         = @{ Description='Primary ULID identifier.' }
        guid        = @{ Description='Optional UUID representation.' }
        entity_table= @{ Description='Local table name.' }
        entity_pk   = @{ Description='Local primary key value.' }
        created_at  = @{ Description='Creation timestamp (UTC).' }
      }
    }

    hash_profiles = @{
      Summary = 'Reusable hashing profiles (algorithm + parameters).'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        name        = @{ Description='Profile identifier.' }
        algo_id     = @{ Description='Hash algorithm (FK crypto_algorithms.id).' }
        output_len  = @{ Description='Optional truncated output length in bytes.' }
        params      = @{ Description='JSON with algorithm-specific tweaks.' }
        status      = @{ Description='Lifecycle flag.'; Enum=@('active','deprecated') }
        created_at  = @{ Description='Creation timestamp (UTC).' }
      }
    }

    key_wrapper_layers = @{
      Summary = 'Individual layers that compose a key wrapper.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        key_wrapper_id = @{ Description='Parent key wrapper (FK key_wrappers.id).' }
        layer_no       = @{ Description='Layer order (1..N).' }
        kms_key_id     = @{ Description='KMS key used for the layer, if any.' }
        kem_algo_id    = @{ Description='KEM algorithm used for wrapping (FK crypto_algorithms.id).' }
        kem_ciphertext = @{ Description='Ciphertext blob for the wrapped key material.' }
        encap_pubkey   = @{ Description='Optional encapsulated public key.' }
        aad            = @{ Description='JSON AAD metadata used during wrapping.' }
        meta           = @{ Description='Additional JSON metadata.' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    key_wrappers = @{
      Summary = 'Composite wrappers protecting DEKs with multiple KMS/crypto layers.'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        wrapper_uuid  = @{ Description='Stable UUID identifier.' }
        kms1_key_id   = @{ Description='Primary wrapping KMS key.' }
        kms2_key_id   = @{ Description='Secondary wrapping KMS key.' }
        crypto_suite  = @{ Description='JSON description of the crypto suite used.' }
        wrap_version  = @{ Description='Version number for the wrapper format.' }
        status        = @{ Description='Lifecycle flag.'; Enum=@('active','rotated','retired','invalid') }
        dek_wrap1     = @{ Description='First wrapped DEK blob.' }
        dek_wrap2     = @{ Description='Second wrapped DEK blob.' }
        created_at    = @{ Description='Creation timestamp (UTC).' }
        rotated_at    = @{ Description='When the wrapper was rotated, if ever.' }
      }
    }

    kms_health_checks = @{
      Summary = 'Periodic health probes for KMS providers/keys.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        provider_id = @{ Description='KMS provider being checked (FK kms_providers.id).' }
        kms_key_id  = @{ Description='Specific key being checked (FK kms_keys.id), optional.' }
        status      = @{ Description='Probe result.'; Enum=@('up','degraded','down') }
        latency_ms  = @{ Description='Measured latency in milliseconds.' }
        error       = @{ Description='Error string when degraded/down.' }
        checked_at  = @{ Description='Timestamp of the check (UTC).' }
      }
    }

    kms_routing_policies = @{
      Summary = 'Routing directives describing how tenants map to KMS providers.'
      Columns = @{
        id        = @{ Description='Surrogate primary key.' }
        name      = @{ Description='Policy name.' }
        priority  = @{ Description='Priority ordering (higher first).' }
        strategy  = @{ Description='Routing strategy.'; Enum=@('prefer','require','avoid') }
        match     = @{ Description='JSON filter describing when to apply the policy.' }
        providers = @{ Description='JSON list of provider options/weights.' }
        active    = @{ Description='Whether the policy is active.' }
        created_at= @{ Description='Creation timestamp (UTC).' }
      }
    }

    merkle_anchors = @{
      Summary = 'Anchors proving Merkle roots in external systems (files, blockchain, etc.).'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        merkle_root_id = @{ Description='Referenced Merkle root (FK merkle_roots.id).' }
        anchor_type    = @{ Description='Anchor medium.'; Enum=@('file','blockchain','notary') }
        anchor_ref     = @{ Description='Reference or locator for the anchor.' }
        anchored_at    = @{ Description='When the anchor was created.' }
        meta           = @{ Description='JSON metadata tied to the anchor.' }
      }
    }

    merkle_roots = @{
      Summary = 'Per-period Merkle root snapshots for append-only data.'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        subject_table = @{ Description='Table being summarized.' }
        period_start  = @{ Description='Start timestamp of the covered period.' }
        period_end    = @{ Description='End timestamp of the covered period.' }
        root_hash     = @{ Description='Merkle root hash (bytea).' }
        proof_uri     = @{ Description='Optional URI pointing to notarized proof bundles.' }
        status        = @{ Description='Lifecycle state of the Merkle root (pending/anchored/verified/failed).' }
        leaf_count    = @{ Description='Number of leaves included.' }
        created_at    = @{ Description='When the root was stored.' }
      }
    }

    migration_events = @{
      Summary = 'Records describing migrations between schema versions.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        system_name = @{ Description='System/component undergoing migration.' }
        from_version= @{ Description='Version migrated from.' }
        to_version  = @{ Description='Target version.' }
        status      = @{ Description='Migration status.'; Enum=@('pending','running','done','failed','cancelled') }
        started_at  = @{ Description='Migration start timestamp (UTC).' }
        finished_at = @{ Description='Completion timestamp (UTC).' }
        error       = @{ Description='Failure message, if any.' }
        meta        = @{ Description='JSON metadata or logs.' }
      }
    }

    peer_nodes = @{
      Summary = 'Known database/application peers for replication and sync.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        name       = @{ Description='Peer display name.' }
        type       = @{ Description='Peer type.'; Enum=@('postgres','mysql','app','service') }
        location   = @{ Description='Optional region / data center.' }
        status     = @{ Description='Health status.'; Enum=@('active','offline','degraded','disabled') }
        last_seen  = @{ Description='Last heartbeat timestamp.' }
        meta       = @{ Description='JSON metadata describing the peer.' }
        created_at = @{ Description='Registration timestamp (UTC).' }
      }
    }

    policy_algorithms = @{
      Summary = 'Weights and priorities for algorithms used within an encryption policy.'
      Columns = @{
        policy_id = @{ Description='Encryption policy id (FK encryption_policies.id).' }
        algo_id   = @{ Description='Algorithm id (FK crypto_algorithms.id).' }
        role      = @{ Description='Role played by the algorithm.'; Enum=@('kem','sig','hash','symmetric') }
        weight    = @{ Description='Selection weight.' }
        priority  = @{ Description='Fallback/ordering priority.' }
      }
    }

    pq_migration_jobs = @{
      Summary = 'Jobs that migrate stored data to PQ-safe hashing/encryption policies.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        scope            = @{ Description='What is being migrated (hashes, wrappers, signatures).' }
        target_policy_id = @{ Description='Target encryption policy id, optional.' }
        target_algo_id   = @{ Description='Target crypto algorithm id, optional.' }
        selection        = @{ Description='JSON selector describing the affected dataset.' }
        scheduled_at     = @{ Description='Scheduled start time.' }
        started_at       = @{ Description='When the job started.' }
        finished_at      = @{ Description='Completion timestamp.' }
        status           = @{ Description='Execution status.'; Enum=@('pending','running','done','failed','cancelled') }
        processed_count  = @{ Description='How many records were processed.' }
        error            = @{ Description='Failure cause, if any.' }
        created_by       = @{ Description='User who enqueued the job.' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
      }
    }

    privacy_requests = @{
      Summary = 'Data-subject privacy requests (access, erasure, portability, etc.).'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        user_id      = @{ Description='Subject user (FK users.id).' }
        type         = @{ Description='Request type.'; Enum=@('access','erasure','rectify','restrict','portability') }
        status       = @{ Description='Request status.'; Enum=@('pending','processing','done','failed','cancelled') }
        requested_at = @{ Description='When the request was submitted.' }
        processed_at = @{ Description='When it was completed.' }
        meta         = @{ Description='JSON blob with additional context.' }
      }
    }

    rate_limit_counters = @{
      Summary = 'Sliding-window counters for rate limiting enforcement.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        subject_type   = @{ Description='Entity type being limited (ip,user,api_key,tenant).' }
        subject_id     = @{ Description='Identifier of the subject (stringified).' }
        name           = @{ Description='Rate limiting bucket name.' }
        window_start   = @{ Description='Beginning of the measurement window.' }
        window_size_sec= @{ Description='Window length in seconds.' }
        count          = @{ Description='Number of hits recorded during the window.' }
        updated_at     = @{ Description='Last update timestamp (UTC).' }
      }
    }

    rate_limits = @{
      Summary = 'Configured rate-limiting rules at the application level.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        subject_type   = @{ Description='Entity type being limited.' }
        subject_id     = @{ Description='Identifier of the subject.' }
        name           = @{ Description='Rule/bucket name.' }
        window_size_sec= @{ Description='Window length in seconds.' }
        limit_count    = @{ Description='Number of allowed operations within the window.' }
        active         = @{ Description='Whether the rule is active.' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
      }
    }

    rbac_repositories = @{
      Summary = 'Sources of RBAC definitions (git repos, APIs, etc.).'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        name          = @{ Description='Repository identifier.' }
        url           = @{ Description='Optional URL/endpoint.' }
        signing_key_id= @{ Description='Signing key used to verify snapshots (FK signing_keys.id).' }
        status        = @{ Description='Repository status.'; Enum=@('active','disabled') }
        last_synced_at= @{ Description='Last successful sync time.' }
        last_commit   = @{ Description='Hash/identifier of the last synced commit.' }
        created_at    = @{ Description='Creation timestamp (UTC).' }
      }
    }

    rbac_repo_snapshots = @{
      Summary = 'Stored RBAC snapshots pulled from repositories.'
      Columns = @{
        id        = @{ Description='Surrogate primary key.' }
        repo_id   = @{ Description='Source repository (FK rbac_repositories.id).' }
        commit_id = @{ Description='Commit/version identifier stored.' }
        taken_at  = @{ Description='When the snapshot was taken.' }
        metadata  = @{ Description='JSON metadata associated with the snapshot.' }
      }
    }

    rbac_role_permissions = @{
      Summary = 'Permission rules bundled with RBAC roles.'
      Columns = @{
        role_id       = @{ Description='Role identifier (FK rbac_roles.id).' }
        permission_id = @{ Description='Permission identifier (FK permissions.id).' }
        effect        = @{ Description='Permit or deny flag.'; Enum=@('allow','deny') }
        source        = @{ Description='Whether the rule came from repo or local overrides.'; Enum=@('repo','local') }
        created_at    = @{ Description='Creation timestamp (UTC).' }
      }
    }

    rbac_roles = @{
      Summary = 'RBAC role definitions synchronized from repositories.'
      Columns = @{
        id          = @{ Description='Surrogate primary key.' }
        repo_id     = @{ Description='Owning repository (FK rbac_repositories.id).' }
        slug        = @{ Description='Stable role slug.' }
        name        = @{ Description='Human name of the role.' }
        description = @{ Description='Optional description.' }
        version     = @{ Description='Version number from the repo.' }
        status      = @{ Description='Lifecycle status.'; Enum=@('active','deprecated','archived') }
        created_at  = @{ Description='Creation timestamp (UTC).' }
        updated_at  = @{ Description='Last update timestamp (UTC).' }
      }
    }

    rbac_sync_cursors = @{
      Summary = 'Per-peer replication cursors for RBAC repositories.'
      Columns = @{
        repo_id        = @{ Description='Repository id (FK rbac_repositories.id).' }
        peer           = @{ Description='Consumer identifier (service name).' }
        last_commit    = @{ Description='Last processed commit hash.' }
        last_synced_at = @{ Description='Timestamp when the peer last synced.' }
      }
    }

    rbac_user_permissions = @{
      Summary = 'Direct permission grants to users (outside of roles).'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        user_id        = @{ Description='User receiving the grant (FK users.id).' }
        permission_id  = @{ Description='Permission id (FK permissions.id).' }
        tenant_id      = @{ Description='Tenant scope, optional.' }
        scope          = @{ Description='Additional scope qualifier (string).' }
        effect         = @{ Description='Allow or deny flag.'; Enum=@('allow','deny') }
        granted_by     = @{ Description='User/admin who granted the permission.' }
        granted_at     = @{ Description='Grant timestamp (UTC).' }
        expires_at     = @{ Description='Optional expiration time (UTC).' }
      }
    }

    rbac_user_roles = @{
      Summary = 'Assignments of RBAC roles to users.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        user_id    = @{ Description='User receiving the role (FK users.id).' }
        role_id    = @{ Description='Role granted (FK rbac_roles.id).' }
        tenant_id  = @{ Description='Tenant scope, optional.' }
        scope      = @{ Description='Additional scope qualifier.' }
        status     = @{ Description='Assignment status.'; Enum=@('active','revoked','expired') }
        granted_by = @{ Description='User/admin who granted the role.' }
        granted_at = @{ Description='Grant timestamp (UTC).' }
        expires_at = @{ Description='Optional expiration time (UTC).' }
      }
    }

    replication_lag_samples = @{
      Summary = 'Snapshot metrics measuring replication lag per peer.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        peer_id    = @{ Description='Peer being measured (FK peer_nodes.id).' }
        metric     = @{ Description='Metric name (apply_lag_ms, transport_lag_ms).' }
        value      = @{ Description='Measured value (ms).' }
        captured_at= @{ Description='Capture timestamp (UTC).' }
      }
    }

    retention_enforcement_jobs = @{
      Summary = 'Runs of data-retention enforcement tasks.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        policy_id       = @{ Description='Retention policy being enforced (FK data_retention_policies.id).' }
        scheduled_at    = @{ Description='Scheduled start time.' }
        started_at      = @{ Description='Execution start timestamp.' }
        finished_at     = @{ Description='Execution completion timestamp.' }
        status          = @{ Description='Job status.'; Enum=@('pending','running','done','failed','cancelled') }
        processed_count = @{ Description='How many rows were processed.' }
        error           = @{ Description='Failure details, if any.' }
        created_at      = @{ Description='Creation timestamp (UTC).' }
      }
    }

    rewrap_jobs = @{
      Summary = 'Key rewrap tasks that move ciphertexts to new key wrappers/KMS keys.'
      Columns = @{
        id                = @{ Description='Surrogate primary key.' }
        key_wrapper_id    = @{ Description='Wrapper being rewrapped (FK key_wrappers.id).' }
        target_kms1_key_id= @{ Description='Target primary KMS key.' }
        target_kms2_key_id= @{ Description='Target secondary KMS key.' }
        scheduled_at      = @{ Description='Scheduled start time.' }
        started_at        = @{ Description='Processing start timestamp.' }
        finished_at       = @{ Description='Processing completion timestamp.' }
        status            = @{ Description='Job status flag.'; Enum=@('pending','running','done','failed') }
        attempts          = @{ Description='Retry counter.' }
        last_error        = @{ Description='Last error message observed.' }
        created_at        = @{ Description='Creation timestamp (UTC).' }
      }
    }

    schema_registry = @{
      Summary = 'Registry of schema versions applied to various components.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        system_name  = @{ Description='System/service name.' }
        component    = @{ Description='Component name (db, api, etc.).' }
        version      = @{ Description='Version identifier.' }
        checksum     = @{ Description='Checksum/signature of the migration bundle.' }
        applied_at   = @{ Description='When the version was applied.' }
        meta         = @{ Description='JSON metadata with migration context.' }
      }
    }

    signatures = @{
      Summary = 'Digital signatures over critical entities for audit integrity.'
      Columns = @{
        id            = @{ Description='Surrogate primary key.' }
        subject_table = @{ Description='Table of the signed entity.' }
        subject_pk    = @{ Description='Primary key of the signed record.' }
        context       = @{ Description='Logical context (audit_chain, event_outbox, etc.).' }
        algo_id       = @{ Description='Signature algorithm (FK crypto_algorithms.id).' }
        signing_key_id= @{ Description='Signing key used (FK signing_keys.id).' }
        signature     = @{ Description='Binary signature blob.' }
        payload_hash  = @{ Description='Hash of the signed payload.' }
        hash_algo_id  = @{ Description='Hash algorithm used (FK crypto_algorithms.id).' }
        created_at    = @{ Description='Creation timestamp (UTC).' }
      }
    }

    signing_keys = @{
      Summary = 'Inventory of signing keys (local, KMS-backed, or imported).'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        algo_id        = @{ Description='Signature algorithm (FK crypto_algorithms.id).' }
        name           = @{ Description='Key name / identifier.' }
        public_key     = @{ Description='Public key bytes.' }
        private_key_enc= @{ Description='Encrypted private key blob.' }
        kms_key_id     = @{ Description='Backing KMS key if stored hardware-side.' }
        origin         = @{ Description='Key origin.'; Enum=@('local','kms','imported') }
        status         = @{ Description='Lifecycle status.'; Enum=@('active','retired','compromised') }
        scope          = @{ Description='Usage scope (audit, events, assets, ...).' }
        created_by     = @{ Description='User who created/uploaded the key.' }
        created_at     = @{ Description='Creation timestamp (UTC).' }
        activated_at   = @{ Description='Activation timestamp (UTC).' }
        retired_at     = @{ Description='Retirement timestamp (UTC).' }
        notes          = @{ Description='Operational notes.' }
      }
    }

    slo_status = @{
      Summary = 'Computed status entries for service-level objectives.'
      Columns = @{
        id           = @{ Description='Surrogate primary key.' }
        window_id    = @{ Description='SLO window (FK slo_windows.id).' }
        computed_at  = @{ Description='Timestamp when the SLO was evaluated.' }
        sli_value    = @{ Description='Measured SLI value.' }
        good_events  = @{ Description='Number of good events counted.' }
        total_events = @{ Description='Total events observed.' }
        status       = @{ Description='Evaluation result.'; Enum=@('good','breach','unknown') }
      }
    }

    slo_windows = @{
      Summary = 'Configured service-level objective windows/targets.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        name            = @{ Description='SLO identifier.' }
        objective       = @{ Description='JSON description of what is being measured.' }
        target_pct      = @{ Description='Target success percentage.' }
        window_interval = @{ Description='Interval over which the SLO is computed.' }
        created_at      = @{ Description='Creation timestamp (UTC).' }
      }
    }

    sync_batch_items = @{
      Summary = 'Individual entries inside sync batches.'
      Columns = @{
        id        = @{ Description='Surrogate primary key.' }
        batch_id  = @{ Description='Parent batch (FK sync_batches.id).' }
        event_key = @{ Description='Event identifier transported in the batch.' }
        status    = @{ Description='Item status.'; Enum=@('pending','sent','applied','failed','skipped') }
        error     = @{ Description='Failure reason, if applicable.' }
        created_at= @{ Description='Creation timestamp (UTC).' }
      }
    }

    sync_batches = @{
      Summary = 'Batches of events replicated between peers.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        channel          = @{ Description='Logical replication channel.' }
        producer_peer_id = @{ Description='Producing peer (FK peer_nodes.id).' }
        consumer_peer_id = @{ Description='Consuming peer (FK peer_nodes.id).' }
        status           = @{ Description='Batch status.'; Enum=@('pending','sending','completed','failed','cancelled') }
        items_total      = @{ Description='Total number of events in the batch.' }
        items_ok         = @{ Description='Number of events applied successfully.' }
        items_failed     = @{ Description='Number of events that failed.' }
        error            = @{ Description='Batch-level error, if any.' }
        created_at       = @{ Description='Creation timestamp (UTC).' }
        started_at       = @{ Description='Processing start timestamp.' }
        finished_at      = @{ Description='Processing completion timestamp.' }
      }
    }

    sync_errors = @{
      Summary = 'Errors raised while applying replication batches.'
      Columns = @{
        id        = @{ Description='Surrogate primary key.' }
        source    = @{ Description='Source subsystem/channel.' }
        event_key = @{ Description='Offending event key (if known).' }
        peer_id   = @{ Description='Peer involved (FK peer_nodes.id).' }
        error     = @{ Description='Error message.' }
        created_at= @{ Description='Timestamp when the error was recorded.' }
      }
    }

    tenant_domains = @{
      Summary = 'Tenant-owned domains used for routing/custom branding.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        tenant_id  = @{ Description='Owning tenant (FK tenants.id).' }
        domain     = @{ Description='Original domain string.' }
        domain_ci  = @{ Description='Lowercase domain used for uniqueness.' }
        is_primary = @{ Description='Whether this domain is the tenant primary.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
      }
    }

    tenants = @{
      Summary = 'Top-level tenant/organization records used for multi-tenancy.'
      Columns = @{
        id         = @{ Description='Surrogate primary key.' }
        name       = @{ Description='Tenant display name.' }
        slug       = @{ Description='Canonical slug (unique per tenant).' }
        slug_ci    = @{ Description='Lowercase slug used for case-insensitive uniqueness.' }
        status     = @{ Description='Tenant status.'; Enum=@('active','suspended','deleted') }
        version    = @{ Description='Optimistic locking version counter.' }
        deleted_at = @{ Description='Soft-delete timestamp.' }
        created_at = @{ Description='Creation timestamp (UTC).' }
        updated_at = @{ Description='Last update timestamp (UTC).' }
      }
    }

  }
}

<#
  NOTE: The PgDefaults/PgOverrides metadata uses script constructs that
  break Import-PowerShellDataFile. Keep it commented out until the docs
  tooling can consume it via a different mechanism.
  PgDefaults = @{
  Conventions = @(
    @{
      # *_at -> timestamptz(6)
      Match = '.*_at$'
      Pg    = @{ Type = 'timestamptz(6)' }
    },
    @{
      # JSON-ish -> jsonb
      Match = '^(meta(json)?|details|payload|gateway_payload|encryption_meta|aad_template|old_value|new_value|layers)$'
      Pg    = @{ Type = 'jsonb' }
    },
    @{
      # 32-byte binary digests -> bytea + length check
      Match = '.*(_hash|_token|_fingerprint)$'
      Pg    = @{ Type = 'bytea'; Check = 'octet_length({col}) = 32' }
    },
    @{
      # ISO currency
      Match = '^currency$'
      Pg    = @{ Type = 'char(3)'; Check = "{col} ~ '^[A-Z]{3}$'" }
    },
    @{
      # rating -> smallint
      Match = '^rating$'
      Pg    = @{ Type = 'smallint' }
    },
    @{
      # general rule: columns named uuid/jti -> uuid
      Match = '^(uuid|jti)$'
      Pg    = @{ Type = 'uuid' }
    },
    @{
      # ISO2 country code
      Match = '^iso2$'
      Pg    = @{ Type = 'char(2)'; Check = "{col} ~ '^[A-Z]{2}$'" }
    }
  )
  Identity = 'by default'
  }

# ===========================================
# Per-table overrides (v1.1)
# ===========================================
  PgOverrides = @{

  Tables = @{

    users = @{
      Pg = @{ Unique = @('email_hash') }
      Columns = @{
        id                   = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        email_hash           = @{ Pg = @{ Type='bytea'; Check='octet_length(email_hash)=32' } }
        last_login_ip_hash   = @{ Pg = @{ Type='bytea'; Check='octet_length(last_login_ip_hash)=32' } }
        last_login_at        = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at           = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at           = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        deleted_at           = @{ Pg = @{ Type='timestamptz(6)' } }
        actor_role           = @{ Pg = @{ Type='text'; Check="actor_role IN ('customer','admin')" } }
      }
    }

    login_attempts = @{
      Columns = @{
        id            = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        ip_hash       = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        attempted_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        username_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(username_hash)=32' } }
      }
    }

    user_profiles = @{
      Columns = @{
        user_id        = @{ Pg = @{ Type='bigint' } }
        profile_enc    = @{ Pg = @{ Type='bytea' } }
        encryption_meta= @{ Pg = @{ Type='jsonb' } }
        updated_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    user_identities = @{
      Pg = @{ Unique = @('provider, provider_user_id') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    permissions = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
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
        id            = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        session_token = @{ Pg = @{ Type='bytea'; Check='octet_length(session_token)=32' } }
        ip_hash       = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        meta_json     = @{ Pg = @{ Type='jsonb' } }
        created_at    = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    sessions = @{
      Pg = @{ Unique = @('token_hash') }
      Columns = @{
        id                 = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        token_hash         = @{ Pg = @{ Type='bytea'; Check='octet_length(token_hash)=32' } }
        token_fingerprint  = @{ Pg = @{ Type='bytea'; Check='octet_length(token_fingerprint)=32' } }
        token_issued_at    = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at         = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_seen_at       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at         = @{ Pg = @{ Type='timestamptz(6)' } }
        ip_hash            = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        session_blob       = @{ Pg = @{ Type='bytea' } }
      }
    }

    auth_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('login_success','login_failure','logout','password_reset','lockout')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
        meta_email  = @{ Pg = @{ Generated = "ALWAYS AS ((meta->>'email')) STORED" } }
      }
    }

    register_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('register_success','register_failure')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    verify_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type        = @{ Pg = @{ Type='text'; Check="type IN ('verify_success','verify_failure')" } }
        ip_hash     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        occurred_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    system_errors = @{
      Pg = @{ Unique = @('fingerprint') }
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        level       = @{ Pg = @{ Type='text'; Check="level IN ('notice','warning','error','critical')" } }
        context     = @{ Pg = @{ Type='jsonb' } }
        ip_text     = @{ Pg = @{ Type='inet' } }
        ip_bin      = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_bin)=16' } }
        http_status = @{ Pg = @{ Type='smallint' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_seen   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    user_consents = @{
      Pg = @{ Unique = @('user_id, consent_type, version') }
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
      Pg = @{ Unique = @('book_id, user_id') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        rating     = @{ Pg = @{ Type='smallint'; Check='rating BETWEEN 1 AND 5' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    crypto_keys = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        key_meta     = @{ Pg = @{ Type='jsonb' } }
        key_type     = @{ Pg = @{ Type='text'; Check="key_type IN ('dek','kek','hmac','pepper')" } }
        origin       = @{ Pg = @{ Type='text'; Check="origin IN ('local','kms','imported')" } }
        usage        = @{ Pg = @{ Type='text[]'; Check="(usage IS NULL) OR (usage <@ ARRAY['encrypt','decrypt','sign','verify','wrap','unwrap']::text[])" } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('active','retired','compromised','archived')" } }
        backup_blob  = @{ Pg = @{ Type='bytea' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        activated_at = @{ Pg = @{ Type='timestamptz(6)' } }
        retired_at   = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    key_events = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        event_type = @{ Pg = @{ Type='text'; Check="event_type IN ('created','rotated','activated','retired','compromised','deleted','used_encrypt','used_decrypt','access_failed','backup','restore')" } }
        source     = @{ Pg = @{ Type='text'; Check="source IN ('cron','admin','api','manual')" } }
        meta       = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_rotation_jobs = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        scheduled_at = @{ Pg = @{ Type='timestamptz(6)' } }
        started_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_usage = @{
      Pg = @{ Unique = @('key_id, date') }
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        date         = @{ Pg = @{ Type='date' } }
        last_used_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    jwt_tokens = @{
      Pg = @{ Unique = @('jti', 'token_hash') }
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        jti          = @{ Pg = @{ Type='uuid' } }
        token_hash   = @{ Pg = @{ Type='bytea'; Check='octet_length(token_hash)=32' } }
        ip_hash      = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        type         = @{ Pg = @{ Type='text'; Check="type IN ('refresh','api')" } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        last_used_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    book_assets = @{
      Pg = @{ Unique = @('book_id, asset_type') }
      Columns = @{
        id                 = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        asset_type         = @{ Pg = @{ Type='text'; Check="asset_type IN ('cover','pdf','epub','mobi','sample','extra')" } }
        encryption_key_enc = @{ Pg = @{ Type='bytea' } }
        encryption_iv      = @{ Pg = @{ Type='bytea'; Check='octet_length(encryption_iv)=12 OR octet_length(encryption_iv)=16 OR encryption_iv IS NULL' } }
        encryption_tag     = @{ Pg = @{ Type='bytea'; Check='octet_length(encryption_tag)=16 OR encryption_tag IS NULL' } }
        encryption_aad     = @{ Pg = @{ Type='bytea' } }
        encryption_meta    = @{ Pg = @{ Type='jsonb' } }
        key_version        = @{ Pg = @{ Type='varchar(64)' } }
        created_at         = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    book_categories = @{ }

    inventory_reservations = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
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
      Pg = @{ Unique = @('cart_id, book_id, sku') }
      Columns = @{
        id       = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        variant  = @{ Pg = @{ Type='jsonb' } }
        currency = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
      }
    }

    orders = @{
      Pg = @{ Unique = @('uuid'); TableChecks = @() }
      Columns = @{
        id                               = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        uuid                             = @{ Pg = @{ Type='uuid' } }
        uuid_bin                         = @{ Pg = @{ Drop = $true } }  # PG stores UUID natively (16 B)
        encrypted_customer_blob          = @{ Pg = @{ Type='bytea' } }
        encryption_meta                  = @{ Pg = @{ Type='jsonb' } }
        currency                         = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        created_at                       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at                       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    order_items = @{
      Columns = @{
        id       = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        currency = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        tax_rate = @{ Pg = @{ Check='tax_rate BETWEEN 0 AND 100' } }
      }
    }

    order_item_downloads = @{
      Pg = @{ Unique = @('order_id, book_id, asset_id') }
      Columns = @{
        id                  = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        download_token_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(download_token_hash)=32' } }
        ip_hash             = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        expires_at          = @{ Pg = @{ Type='timestamptz(6)' } }
        last_used_at        = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    invoices = @{
      Pg = @{ Unique = @('invoice_number') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        issue_date = @{ Pg = @{ Type='date' } }
        due_date   = @{ Pg = @{ Type='date' } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    invoice_items = @{
      Pg = @{ Unique = @('invoice_id, line_no') }
      Columns = @{
        id       = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        currency = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        tax_rate = @{ Pg = @{ Check='tax_rate BETWEEN 0 AND 100' } }
      }
    }

    payments = @{
      Pg = @{ Unique = @('transaction_id') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('initiated','pending','authorized','paid','cancelled','partially_refunded','refunded','failed')" } }
        amount     = @{ Pg = @{ Type='numeric(12,2)'; Check='amount >= 0' } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        details    = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_logs = @{
      Columns = @{
        id     = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        log_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_webhooks = @{
      Pg = @{ Unique = @('payload_hash') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        payload    = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    idempotency_keys = @{
      Pg = @{ TableChecks = @('ttl_seconds > 0') }
      Columns = @{
        # Exception from hash->bytea: keep 64 hex characters
        key_hash       = @{ Pg = @{ Type='char(64)' } }
        gateway_payload= @{ Pg = @{ Type='jsonb' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    refunds = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        amount     = @{ Pg = @{ Type='numeric(12,2)'; Check='amount >= 0' } }
        currency   = @{ Pg = @{ Type='char(3)'; Check="currency ~ '^[A-Z]{3}$'" } }
        details    = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    coupons = @{
      Pg = @{
        TableChecks = @(
          "(type = 'percent' AND value BETWEEN 0 AND 100 AND currency IS NULL)
           OR
           (type = 'fixed'   AND value >= 0 AND currency ~ '^[A-Z]{3}$')"
        )
      }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type       = @{ Pg = @{ Type='text'; Check="type IN ('percent','fixed')" } }
        value      = @{ Pg = @{ Type='numeric(12,2)' } }
        currency   = @{ Pg = @{ Type='char(3)' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    coupon_redemptions = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        redeemed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    countries = @{
      Columns = @{
        iso2 = @{ Pg = @{ Type='char(2)'; Check="iso2 ~ '^[A-Z]{2}$'" } }
      }
    }

    tax_rates = @{
      Pg = @{ Unique = @('country_iso2, category, valid_from') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        category   = @{ Pg = @{ Type='text'; Check="category IN ('ebook','physical')" } }
        rate       = @{ Pg = @{ Type='numeric(5,2)' } }
        valid_from = @{ Pg = @{ Type='date' } }
        valid_to   = @{ Pg = @{ Type='date' } }
      }
    }

    vat_validations = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
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
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        old_value  = @{ Pg = @{ Type='jsonb' } }
        new_value  = @{ Pg = @{ Type='jsonb' } }
        changed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        ip_bin     = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_bin)=16' } }
      }
    }

    webhook_outbox = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        payload        = @{ Pg = @{ Type='jsonb' } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('pending','sent','failed')" } }
        next_attempt_at= @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    payment_gateway_notifications = @{
      Pg = @{ Unique = @('transaction_id') }
      Columns = @{
        id               = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        transaction_id   = @{ Pg = @{ Type='varchar(255)'; Nullable=$false } }
        received_at      = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        processing_until = @{ Pg = @{ Type='timestamptz(6)' } }
        status           = @{ Pg = @{ Type='text'; Check="status IN ('pending','processing','done','failed')" } }
      }
    }

    email_verifications = @{
      Pg = @{ Unique = @('selector') }
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        token_hash     = @{ Pg = @{ Type='char(64)' } }  # Exception (hex string)
        validator_hash = @{ Pg = @{ Type='bytea'; Check='octet_length(validator_hash)=32' } }
        selector       = @{ Pg = @{ Type='char(12)' } }
        expires_at     = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        used_at        = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    notifications = @{
      Pg = @{ TableChecks = @('retries >= 0 AND max_retries >= 0') }
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
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
      Pg = @{ Unique = @('email_hash', 'confirm_selector') }
      Columns = @{
        id                      = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        email_hash              = @{ Pg = @{ Type='bytea'; Check='octet_length(email_hash)=32'; Nullable=$false } }
        email_enc               = @{ Pg = @{ Type='bytea' } }
        confirm_selector        = @{ Pg = @{ Type='char(12)' } }
        confirm_validator_hash  = @{ Pg = @{ Type='bytea'; Check='octet_length(confirm_validator_hash)=32' } }
        confirm_expires         = @{ Pg = @{ Type='timestamptz(6)' } }
        confirmed_at            = @{ Pg = @{ Type='timestamptz(6)' } }
        unsubscribe_token_hash  = @{ Pg = @{ Type='bytea'; Check='octet_length(unsubscribe_token_hash)=32' } }
        created_at              = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at              = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        ip_hash                 = @{ Pg = @{ Type='bytea'; Check='octet_length(ip_hash)=32' } }
        meta                    = @{ Pg = @{ Type='jsonb' } }
      }
    }

    system_jobs = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
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
      Pg = @{ Unique = @('entity_table, entity_pk, field_name') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        ciphertext = @{ Pg = @{ Type='bytea' } }
        meta       = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    kms_providers = @{
      Pg = @{ Unique = @('name') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        provider   = @{ Pg = @{ Type='text'; Check="provider IN ('gcp','aws','azure','vault')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    kms_keys = @{
      Pg = @{ Unique = @('provider_id, external_key_ref') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        purpose    = @{ Pg = @{ Type='text'; Check="purpose IN ('wrap','encrypt','both')" } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','retired','disabled')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    encryption_policies = @{
      Pg = @{ Unique = @('policy_name') }
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        mode           = @{ Pg = @{ Type='text'; Check="mode IN ('local','kms','multi-kms')" } }
        layer_selection= @{ Pg = @{ Type='text'; Check="layer_selection IN ('defined','round_robin','random','hash_mod')" } }
        aad_template   = @{ Pg = @{ Type='jsonb' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    policy_kms_keys = @{ }  # PK (policy_id, kms_key_id) already exists in the base schema

    encryption_events = @{
      Columns = @{
        id               = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        op               = @{ Pg = @{ Type='text'; Check="op IN ('encrypt','decrypt','rotate','rehash','unwrap','wrap')" } }
        layers           = @{ Pg = @{ Type='jsonb' } }
        created_at       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    api_keys = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        scopes     = @{ Pg = @{ Type='jsonb' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','revoked','disabled')" } }
        last_used_at = @{ Pg = @{ Type='timestamptz(6)' } }
        expires_at = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    audit_chain = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    crypto_algorithms = @{
      Pg = @{ Unique = @('class, name, variant','class, name, variant_norm') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        class      = @{ Pg = @{ Type='text'; Check="class IN ('kem','sig','hash','symmetric')" } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','deprecated','experimental')" } }
        params     = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    crypto_standard_aliases = @{
      Columns = @{
        alias     = @{ Pg = @{ Type='varchar(120)' } }
        notes     = @{ Pg = @{ Type='text' } }
        created_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    data_retention_policies = @{
      Pg = @{ Unique = @('entity_table, field_name, action, keep_for') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        action     = @{ Pg = @{ Type='text'; Check="action IN ('delete','anonymize','hash','truncate')" } }
        keep_for   = @{ Pg = @{ Type='interval' } }
        active     = @{ Pg = @{ Type='boolean'; Default='true' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    deletion_jobs = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        scheduled_at = @{ Pg = @{ Type='timestamptz(6)' } }
        started_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    device_fingerprints = @{
      Columns = @{
        id                 = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        attributes         = @{ Pg = @{ Type='jsonb' } }
        first_seen         = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_seen          = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    encryption_bindings = @{
      Pg = @{ Unique = @('entity_table, entity_pk, field_name','entity_table, entity_pk, field_name_norm') }
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    encryption_policy_bindings = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        effective_from = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    entity_external_ids = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    event_dlq = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        event          = @{ Pg = @{ Type='jsonb' } }
        retryable      = @{ Pg = @{ Type='boolean'; Default='false' } }
        attempts       = @{ Pg = @{ Type='integer'; Default='0' } }
        first_failed_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        last_failed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    event_inbox = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status      = @{ Pg = @{ Type='text'; Check="status IN ('pending','processed','failed')" } }
        attempts    = @{ Pg = @{ Type='integer'; Default='0' } }
        received_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        processed_at= @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    event_outbox = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('pending','sent','failed')" } }
        attempts       = @{ Pg = @{ Type='integer'; Default='0' } }
        next_attempt_at= @{ Pg = @{ Type='timestamptz(6)' } }
        processed_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    field_hash_policies = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        effective_from = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    global_id_registry = @{
      Columns = @{
        gid        = @{ Pg = @{ Type='char(26)' } }
        guid       = @{ Pg = @{ Type='uuid' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    hash_profiles = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        params     = @{ Pg = @{ Type='jsonb' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','deprecated')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_wrapper_layers = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        kem_ciphertext = @{ Pg = @{ Type='bytea' } }
        encap_pubkey   = @{ Pg = @{ Type='bytea' } }
        aad            = @{ Pg = @{ Type='jsonb' } }
        meta           = @{ Pg = @{ Type='jsonb' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    key_wrappers = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        crypto_suite = @{ Pg = @{ Type='jsonb' } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('active','rotated','retired','invalid')" } }
        dek_wrap1    = @{ Pg = @{ Type='bytea' } }
        dek_wrap2    = @{ Pg = @{ Type='bytea' } }
        created_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        rotated_at   = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    kms_health_checks = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('up','degraded','down')" } }
        checked_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    kms_routing_policies = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        strategy   = @{ Pg = @{ Type='text'; Check="strategy IN ('prefer','require','avoid')" } }
        match      = @{ Pg = @{ Type='jsonb' } }
        providers  = @{ Pg = @{ Type='jsonb' } }
        active     = @{ Pg = @{ Type='boolean'; Default='true' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    merkle_anchors = @{
      Pg = @{ Unique = @('anchor_ref, anchor_type, merkle_root_id') }
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        anchor_type    = @{ Pg = @{ Type='text'; Check="anchor_type IN ('file','blockchain','notary')" } }
        anchored_at    = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    merkle_roots = @{
      Columns = @{
        id            = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        period_start  = @{ Pg = @{ Type='timestamptz(6)' } }
        period_end    = @{ Pg = @{ Type='timestamptz(6)' } }
        proof_uri     = @{ Pg = @{ Type='varchar(512)' } }
        status        = @{ Pg = @{ Type='varchar(32)'; Default='pending' } }
        created_at    = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    migration_events = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status      = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        started_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at = @{ Pg = @{ Type='timestamptz(6)' } }
        meta        = @{ Pg = @{ Type='jsonb' } }
      }
    }

    peer_nodes = @{
      Columns = @{
        id        = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type      = @{ Pg = @{ Type='text'; Check="type IN ('postgres','mysql','app','service')" } }
        status    = @{ Pg = @{ Type='text'; Check="status IN ('active','offline','degraded','disabled')" } }
        meta      = @{ Pg = @{ Type='jsonb' } }
        created_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    policy_algorithms = @{
      Columns = @{
        role   = @{ Pg = @{ Type='text'; Check="role IN ('kem','sig','hash','symmetric')" } }
      }
    }

    pq_migration_jobs = @{
      Columns = @{
        id               = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        selection        = @{ Pg = @{ Type='jsonb' } }
        scheduled_at     = @{ Pg = @{ Type='timestamptz(6)' } }
        started_at       = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at      = @{ Pg = @{ Type='timestamptz(6)' } }
        status           = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        processed_count  = @{ Pg = @{ Type='bigint'; Default='0' } }
        created_at       = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    privacy_requests = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        type         = @{ Pg = @{ Type='text'; Check="type IN ('access','erasure','rectify','restrict','portability')" } }
        status       = @{ Pg = @{ Type='text'; Check="status IN ('pending','processing','done','failed','cancelled')" } }
        requested_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        processed_at = @{ Pg = @{ Type='timestamptz(6)' } }
        meta         = @{ Pg = @{ Type='jsonb' } }
      }
    }

    rate_limit_counters = @{
      Columns = @{
        id           = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        window_start = @{ Pg = @{ Type='timestamptz(6)' } }
        updated_at   = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rate_limits = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        window_size_sec= @{ Pg = @{ Type='integer'; Check='window_size_sec > 0' } }
        limit_count    = @{ Pg = @{ Type='integer'; Check='limit_count > 0' } }
        active         = @{ Pg = @{ Type='boolean'; Default='true' } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rbac_repo_snapshots = @{
      Columns = @{
        id        = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        taken_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        metadata  = @{ Pg = @{ Type='jsonb' } }
      }
    }

    rbac_repositories = @{
      Columns = @{
        id            = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status        = @{ Pg = @{ Type='text'; Check="status IN ('active','disabled')" } }
        last_synced_at= @{ Pg = @{ Type='timestamptz(6)' } }
        created_at    = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rbac_role_permissions = @{
      Columns = @{
        effect     = @{ Pg = @{ Type='text'; Check="effect IN ('allow','deny')" } }
        source     = @{ Pg = @{ Type='text'; Check="source IN ('repo','local')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rbac_roles = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','deprecated','archived')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rbac_sync_cursors = @{
      Columns = @{
        last_synced_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    rbac_user_permissions = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        effect     = @{ Pg = @{ Type='text'; Check="effect IN ('allow','deny')" } }
        granted_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    rbac_user_roles = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','revoked','expired')" } }
        granted_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        expires_at = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    replication_lag_samples = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        captured_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    retention_enforcement_jobs = @{
      Columns = @{
        id              = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        scheduled_at    = @{ Pg = @{ Type='timestamptz(6)' } }
        started_at      = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at     = @{ Pg = @{ Type='timestamptz(6)' } }
        status          = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed','cancelled')" } }
        processed_count = @{ Pg = @{ Type='bigint'; Default='0' } }
        created_at      = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    rewrap_jobs = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        scheduled_at= @{ Pg = @{ Type='timestamptz(6)' } }
        started_at  = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at = @{ Pg = @{ Type='timestamptz(6)' } }
        status      = @{ Pg = @{ Type='text'; Check="status IN ('pending','running','done','failed')" } }
        attempts    = @{ Pg = @{ Type='integer'; Default='0' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    schema_registry = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        applied_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        meta       = @{ Pg = @{ Type='jsonb' } }
      }
    }

    signatures = @{
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        signature   = @{ Pg = @{ Type='bytea' } }
        created_at  = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    signing_keys = @{
      Columns = @{
        id             = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        public_key     = @{ Pg = @{ Type='bytea' } }
        private_key_enc= @{ Pg = @{ Type='bytea' } }
        origin         = @{ Pg = @{ Type='text'; Check="origin IN ('local','kms','imported')" } }
        status         = @{ Pg = @{ Type='text'; Check="status IN ('active','retired','compromised')" } }
        created_at     = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        activated_at   = @{ Pg = @{ Type='timestamptz(6)' } }
        retired_at     = @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    slo_status = @{
      Pg = @{ Unique = @('window_id, computed_at') }
      Columns = @{
        id          = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        computed_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        status      = @{ Pg = @{ Type='text'; Check="status IN ('good','breach','unknown')" } }
      }
    }

    slo_windows = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        objective  = @{ Pg = @{ Type='jsonb' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    sync_batch_items = @{
      Columns = @{
        id        = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status    = @{ Pg = @{ Type='text'; Check="status IN ('pending','sent','applied','failed','skipped')" } }
        created_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    sync_batches = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('pending','sending','completed','failed','cancelled')" } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        started_at = @{ Pg = @{ Type='timestamptz(6)' } }
        finished_at= @{ Pg = @{ Type='timestamptz(6)' } }
      }
    }

    sync_errors = @{
      Columns = @{
        id        = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at= @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    tenants = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        status     = @{ Pg = @{ Type='text'; Check="status IN ('active','suspended','deleted')" } }
        deleted_at = @{ Pg = @{ Type='timestamptz(6)' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
        updated_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }

    tenant_domains = @{
      Columns = @{
        id         = @{ Pg = @{ Type='bigint'; Identity='by default' } }
        created_at = @{ Pg = @{ Type='timestamptz(6)'; Default='now()' } }
      }
    }
  }
}
#>
