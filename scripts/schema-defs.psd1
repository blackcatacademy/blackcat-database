@{
  FormatVersion = '1.0'

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
        ip_bin       = @{ Description='Client IP (binary form).' }
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
        meta_email           = @{ Description='Generated: email extracted from meta (for indexing).' }
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
      Summary = 'Binary and ancillary assets for books (covers, files, extras).'
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
      Summary = 'Items added to shopping carts.'
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
        usage              = @{ Description='Allowed operations (SET field).'; Enum=@('encrypt','decrypt','sign','verify','wrap','unwrap') }
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
      Summary = 'Encryption policy registry and parameters.'
      Columns = @{
        id             = @{ Description='Surrogate primary key.' }
        policy_name    = @{ Description='Unique policy name.' }
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
        ttl_seconds  = @{ Description='Time-to-live in seconds.' }
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
        tax_rate    = @{ Description='Tax rate %.' }
        tax_amount  = @{ Description='Tax amount.' }
        line_total  = @{ Description='Total incl. tax for line.' }
        currency    = @{ Description='ISO 4217 currency code.' }
      }
    }

    invoices = @{
      Summary = 'Issued invoices linked to orders.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        order_id        = @{ Description='Order (FK orders.id), optional.' }
        invoice_number  = @{ Description='Unique invoice number.' }
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
      Summary = 'External KMS key references.'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        provider_id      = @{ Description='KMS provider (FK kms_providers.id).' }
        external_key_ref = @{ Description='Provider-specific key identifier.' }
        purpose          = @{ Description='Primary purpose.'; Enum=@('wrap','encrypt','both') }
        algorithm        = @{ Description='Algorithm or template id.' }
        status           = @{ Description='Lifecycle status.'; Enum=@('active','retired','disabled') }
        created_at       = @{ Description='Creation timestamp (UTC).' }
      }
    }

    kms_providers = @{
      Summary = 'Configured KMS providers.'
      Columns = @{
        id              = @{ Description='Surrogate primary key.' }
        name            = @{ Description='Display name.' }
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
      Summary = 'Newsletter subscription registry with double opt-in.'
      Columns = @{
        id                          = @{ Description='Surrogate primary key.' }
        user_id                     = @{ Description='Related user (optional).' }
        email_hash                  = @{ Description='Hashed email value.'; PII='hashed' }
        email_hash_key_version      = @{ Description='Key version for email_hash.' }
        email_enc                   = @{ Description='Encrypted email address.'; PII='encrypted' }
        email_key_version           = @{ Description='Key version for email_enc.' }
        confirm_selector            = @{ Description='Public selector for confirmation (unique).' }
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
      Summary = 'Per-order download entitlements for digital items.'
      Columns = @{
        id                   = @{ Description='Surrogate primary key.' }
        order_id             = @{ Description='Order (FK orders.id).' }
        book_id              = @{ Description='Book (FK books.id).' }
        asset_id             = @{ Description='Asset (FK book_assets.id).' }
        download_token_hash  = @{ Description='Hashed download token.'; PII='hashed' }
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
        tax_rate      = @{ Description='Tax rate %.' }
        currency      = @{ Description='ISO 4217 currency code.' }
      }
    }

    orders = @{
      Summary = 'Orders lifecycle, totals, and encrypted customer blob.'
      Columns = @{
        id                               = @{ Description='Surrogate primary key.' }
        uuid                             = @{ Description='Unique external order id (UUID text).' }
        uuid_bin                         = @{ Description='UUID binary form (unique).' }
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
      Summary = 'Inbound notifications from payment gateways (webhooks, IPNs).'
      Columns = @{
        id                = @{ Description='Surrogate primary key.' }
        transaction_id    = @{ Description='Gateway transaction id (unique if provided).' }
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
      Summary = 'Raw webhook payloads (deduplicated by payload_hash).'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        payment_id       = @{ Description='Payment (FK payments.id), optional.' }
        gateway_event_id = @{ Description='Gateway event id, optional.' }
        payload_hash     = @{ Description='Hash of payload for dedupe.' }
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
        amount            = @{ Description='Payment amount.' }
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
      Summary = 'KMS key assignments per encryption policy.'
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
        amount     = @{ Description='Refund amount.' }
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
      Summary = 'User reviews and ratings for books.'
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
      Summary = 'Tax rates per country and goods category.'
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
      Summary = 'Captured consents per user and version.'
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
      Summary = 'External identity links (OAuth/OpenID/etc.).'
      Columns = @{
        id               = @{ Description='Surrogate primary key.' }
        user_id          = @{ Description='User (FK users.id).' }
        provider         = @{ Description='Provider key (e.g., google, github).' }
        provider_user_id = @{ Description='User id at provider (unique per provider).' }
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
        email_hash               = @{ Description='Hashed email (salted/peppered).'; PII='hashed' }
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

  }
}