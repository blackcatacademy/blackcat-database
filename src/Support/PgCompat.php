<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;

/**
 * PgCompat – compatibility helpers for PostgreSQL.
 *
 * Safety/ergonomics:
 * - Consistent quoting of schema-qualified identifiers (qi/qid).
 * - Resilient to schema-qualified inputs in informational queries.
 * - Enforces trigger name length (PG limit 63 bytes).
 * - Idempotent DDL (CREATE OR REPLACE, IF NOT EXISTS, existence detection).
 * - Sanitizes precision range (0..6).
 */
final class PgCompat
{
    public function __construct(private Database $db) {}

    /* =======================================================================
     *  INSTALL
     * ======================================================================= */

    public function install(): void
    {
        // Schema for helper functions.
        $this->db->exec("CREATE SCHEMA IF NOT EXISTS bc_compat");

        // last_insert_id() – similar to MySQL (current session sequence)
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.last_insert_id() RETURNS bigint
LANGUAGE sql VOLATILE STRICT AS $$ SELECT lastval()::bigint $$;
SQL);

        // curdate()
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.curdate() RETURNS date
LANGUAGE sql STABLE STRICT AS $$ SELECT CURRENT_DATE $$;
SQL);

        // unhex(hex TEXT) -> BYTEA
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.unhex(hex text) RETURNS bytea
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT ('\\x' || regexp_replace($1, '\\s', '', 'g'))::bytea
$$;
SQL);

        // hex(bytea) -> TEXT (lower hex)
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.hex(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT string_agg(lpad(to_hex(get_byte($1, g.i)), 2, '0'), '')
  FROM generate_series(0, length($1)-1) AS g(i)
$$;
SQL);

        // IPv4/IPv6 text -> 16B bytea (IPv4 mapped)
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.inet6_aton(addr text) RETURNS bytea
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
  ip inet := addr::inet;
  out_hex text := '';
  parts text[];
  left_right text[];
  hextets text[];
  missing int;
  i int;
BEGIN
  IF family(ip) = 4 THEN
    parts := regexp_split_to_array(host(ip), '\\.');
    out_hex := '00000000000000000000ffff'
      || lpad(to_hex(parts[1]::int),2,'0')
      || lpad(to_hex(parts[2]::int),2,'0')
      || lpad(to_hex(parts[3]::int),2,'0')
      || lpad(to_hex(parts[4]::int),2,'0');
    RETURN ('\\x' || out_hex)::bytea;
  END IF;

  left_right := regexp_split_to_array(host(ip), '::');
  IF array_length(left_right,1) = 1 THEN
    hextets := regexp_split_to_array(left_right[1], ':');
  ELSE
    hextets := COALESCE(regexp_split_to_array(left_right[1], ':'), ARRAY[]::text[]);
    missing := 8
      - COALESCE(array_length(regexp_split_to_array(left_right[1], ':'),1),0)
      - COALESCE(array_length(regexp_split_to_array(left_right[2], ':'),1),0);
    FOR i IN 1..missing LOOP
      hextets := array_append(hextets, '0');
    END LOOP;
    IF left_right[2] IS NOT NULL THEN
      hextets := hextets || regexp_split_to_array(left_right[2], ':');
    END IF;
  END IF;

  IF array_length(hextets,1) <> 8 THEN
    RAISE EXCEPTION 'invalid IPv6 address: %', host(ip);
  END IF;

  out_hex := '';
  FOR i IN 1..8 LOOP
    out_hex := out_hex || lpad(hextets[i], 4, '0');
  END LOOP;

  RETURN ('\\x' || out_hex)::bytea;
END $$;
SQL);

        // 16B bytea -> IPv4/IPv6 text
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.inet6_ntoa(b bytea) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
  a int; b2 int; c int; d int;
  is_v4mapped boolean;
BEGIN
  IF length(b) <> 16 THEN
    RAISE EXCEPTION 'inet6_ntoa expects 16 bytes, got %', length(b);
  END IF;

  is_v4mapped :=
    get_byte(b,0)=0 AND get_byte(b,1)=0 AND get_byte(b,2)=0 AND get_byte(b,3)=0 AND
    get_byte(b,4)=0 AND get_byte(b,5)=0 AND get_byte(b,6)=0 AND get_byte(b,7)=0 AND
    get_byte(b,8)=0 AND get_byte(b,9)=0 AND get_byte(b,10)=255 AND get_byte(b,11)=255;

  IF is_v4mapped THEN
    a := get_byte(b,12); b2 := get_byte(b,13); c := get_byte(b,14); d := get_byte(b,15);
    RETURN a::text || '.' || b2::text || '.' || c::text || '.' || d::text;
  END IF;

  RETURN
    lpad(to_hex(get_byte(b,0)*256 + get_byte(b,1)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,2)*256 + get_byte(b,3)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,4)*256 + get_byte(b,5)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,6)*256 + get_byte(b,7)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,8)*256 + get_byte(b,9)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,10)*256 + get_byte(b,11)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,12)*256 + get_byte(b,13)),4,'0') || ':' ||
    lpad(to_hex(get_byte(b,14)*256 + get_byte(b,15)),4,'0');
END $$;
SQL);

        // aliasy pro ip_pton / ip_ntop
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.ip_pton(addr text) RETURNS bytea
LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT bc_compat.inet6_aton($1) $$;
SQL);
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.ip_ntop(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT bc_compat.inet6_ntoa($1) $$;
SQL);

        // Trigger: always overwrite updated_at with NOW(6)
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.tg_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP(6);
  RETURN NEW;
END $$;
SQL);

        // Trigger: respect manual NEW.updated_at values
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.tg_touch_updated_at_if_unmodified() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
    NEW.updated_at := CURRENT_TIMESTAMP(6);
  END IF;
  RETURN NEW;
END $$;
SQL);

        // tg: row_version inkrement (optimistic locking)
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.tg_inc_row_version() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
  RETURN NEW;
END $$;
SQL);
    }

    /* =======================================================================
     *  PUBLIC HELPERS (timestamps / triggers / row version / touch / uuid_bin)
     * ======================================================================= */

    /**
     * Provide MySQL-like timestamps: created_at DEFAULT NOW(p), updated_at DEFAULT NOW(p) + auto-touch on UPDATE.
     * @param bool $respectManual  true = allows manual NEW.updated_at; otherwise always overwritten with NOW(p).
     */
    public function ensureTimestamps(
        string $table,
        string $createdCol = 'created_at',
        string $updatedCol = 'updated_at',
        bool $respectManual = false,
        int $precision = 6
    ): void {
        $precision = $this->clampPrecision($precision);
        [$schema, $tbl] = $this->splitSchemaAndName($table);

        $qiT = $this->qi($table);
        $qiC = $this->qid($createdCol);
        $qiU = $this->qid($updatedCol);

        // Add columns when missing
        $this->db->exec("
            ALTER TABLE {$qiT}
            ADD COLUMN IF NOT EXISTS {$qiC} timestamptz({$precision}) NOT NULL DEFAULT CURRENT_TIMESTAMP({$precision})
        ");
        $this->db->exec("
            ALTER TABLE {$qiT}
            ADD COLUMN IF NOT EXISTS {$qiU} timestamptz({$precision}) NOT NULL DEFAULT CURRENT_TIMESTAMP({$precision})
        ");

        // Align defaults when column existed without one
        $this->db->exec("ALTER TABLE {$qiT} ALTER COLUMN {$qiC} SET DEFAULT CURRENT_TIMESTAMP({$precision})");
        $this->db->exec("ALTER TABLE {$qiT} ALTER COLUMN {$qiU} SET DEFAULT CURRENT_TIMESTAMP({$precision})");

        // trigger pro auto-update updated_at
        $this->ensureUpdatedAtTrigger($table, $updatedCol, $respectManual);
    }

    /**
     * Create or refresh trigger that sets $column = NOW(6) on each row change.
     * @param bool $respectManual true = preserve explicit updated_at values provided by UPDATE.
     */
    public function ensureUpdatedAtTrigger(string $table, string $column = 'updated_at', bool $respectManual = false): void
    {
        [$schema, $tbl] = $this->splitSchemaAndName($table);

        // Validuj existenci sloupce (schema-aware).
        $exists = (bool)$this->db->fetchOne(
            "SELECT 1
             FROM information_schema.columns
             WHERE lower(table_name)=lower(:t)
               AND lower(column_name)=lower(:c)
               AND (:s IS NULL OR table_schema = :s)
             LIMIT 1",
            [':t'=>$tbl, ':c'=>$column, ':s'=>$schema]
        );
        if (!$exists) {
            return;
        }

        $trg = $this->safeTriggerName('bc_touch_' . $tbl . '_' . $column);
        $this->dropTriggerIfExists($trg, $table);

        $qiT  = $this->qi($table);
        $qiTr = $this->qid($trg);
        $fn   = $respectManual ? 'bc_compat.tg_touch_updated_at_if_unmodified' : 'bc_compat.tg_touch_updated_at';

        // Fire only when the row actually changes (replacement for MySQL ON UPDATE).
        $this->db->exec("
            CREATE TRIGGER {$qiTr}
            BEFORE UPDATE ON {$qiT}
            FOR EACH ROW
            WHEN (OLD IS DISTINCT FROM NEW)
            EXECUTE FUNCTION {$fn}()
        ");
    }

    /**
     * Add integer row_version (DEFAULT 0) plus trigger that increments it on each UPDATE.
     */
    public function ensureRowVersion(string $table, string $column = 'row_version'): void
    {
        [$schema, $tbl] = $this->splitSchemaAndName($table);

        $qiT  = $this->qi($table);
        $qiV  = $this->qid($column);

        $colExists = (bool)$this->db->fetchOne(
            "SELECT 1
             FROM information_schema.columns
             WHERE lower(table_name)=lower(:t)
               AND lower(column_name)=lower(:c)
               AND (:s IS NULL OR table_schema = :s)
             LIMIT 1",
            [':t'=>$tbl, ':c'=>$column, ':s'=>$schema]
        );

        if (!$colExists) {
            $this->db->exec("ALTER TABLE {$qiT} ADD COLUMN {$qiV} integer NOT NULL DEFAULT 0");
        } else {
            $this->db->exec("ALTER TABLE {$qiT} ALTER COLUMN {$qiV} SET DEFAULT 0");
        }

        $trg  = $this->safeTriggerName('bc_incver_' . $tbl . '_' . $column);
        $qiTr = $this->qid($trg);

        $this->dropTriggerIfExists($trg, $table);

        $this->db->exec("
            CREATE TRIGGER {$qiTr}
            BEFORE UPDATE ON {$qiT}
            FOR EACH ROW
            WHEN (OLD IS DISTINCT FROM NEW)
            EXECUTE FUNCTION bc_compat.tg_inc_row_version()
        ");
    }

    /**
     * Fast row touch – set updated_at = NOW(p) for given PK values.
     * Returns number of affected rows.
     */
    public function touch(
        string $table,
        array $ids,
        string $pk = 'id',
        string $updatedCol = 'updated_at',
        int $precision = 6
    ): int {
        if (!$ids) return 0;

        $precision = $this->clampPrecision($precision);
        $qiT = $this->qi($table);
        $qiU = $this->qid($updatedCol);

        [$inSql, $params] = $this->db->inClause($this->qid($pk), $ids, 'p', 500);
        return $this->db->exec("UPDATE {$qiT} SET {$qiU} = CURRENT_TIMESTAMP({$precision}) WHERE {$inSql}", $params);
    }

    /**
     * Ensure a generated uuid_bin (BYTEA) column from textual UUID plus unique index.
     * - Useful for faster comparisons and indexing of UUIDs.
     */
    public function ensureUuidBinComputed(string $table, string $uuidCol = 'uuid', string $uuidBinCol = 'uuid_bin'): void
    {
        [$schema, $tbl] = $this->splitSchemaAndName($table);

        $qiT  = $this->qi($table);
        $qiU  = $this->qid($uuidCol);
        $qiUB = $this->qid($uuidBinCol);

        $colExists = (bool)$this->db->fetchOne(
            "SELECT 1
             FROM information_schema.columns
             WHERE lower(table_name)=lower(:t)
               AND lower(column_name)=lower(:c)
               AND (:s IS NULL OR table_schema = :s)
             LIMIT 1",
            [':t'=>$tbl, ':c'=>$uuidBinCol, ':s'=>$schema]
        );
        if (!$colExists) {
            $this->db->exec("
                ALTER TABLE {$qiT}
                ADD COLUMN {$qiUB} bytea
                GENERATED ALWAYS AS (('\\x' || replace({$qiU}::text, '-', ''))::bytea) STORED
            ");
        }

        $idxName = $this->safeTriggerName('ux_' . $this->safeIdent($tbl) . '_' . $this->safeIdent($uuidBinCol));
        $qiIdx   = $this->qid($idxName);

        $this->db->exec("
            CREATE UNIQUE INDEX IF NOT EXISTS {$qiIdx}
            ON {$qiT} ({$qiUB})
        ");
    }

    /** @return list<string> Recommended initialization statements per session. */
    public function recommendedInitCommands(): array
    {
        return [
            "SET TIME ZONE 'UTC'",
            "SET search_path = public, bc_compat",
        ];
    }

    /* =======================================================================
     *  INTERNALS
     * ======================================================================= */

    /** Schema-aware DROP TRIGGER IF EXISTS implemented manually for PG syntax limitations. */
    private function dropTriggerIfExists(string $trigger, string $table): void
    {
        [$schema, $tbl] = $this->splitSchemaAndName($table);

        $row = $this->db->fetch(
            "SELECT 1
            FROM pg_trigger t
            JOIN pg_class   c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE NOT t.tgisinternal
              AND lower(t.tgname) = lower(:tr)
              AND lower(c.relname) = lower(:tbl)
              AND (:s IS NULL OR n.nspname = :s)
            LIMIT 1",
            [':tr'=>$trigger, ':tbl'=>$tbl, ':s'=>$schema]
        );

        if ($row) {
            $qiT  = $this->qi($table);
            $qiTr = $this->qid($trigger);
            $this->db->exec("DROP TRIGGER {$qiTr} ON {$qiT}");
        }
    }

    /** Safely quote schema-qualified names (split "schema.table" → "schema"."table"). */
    private function qi(string $ident): string
    {
        $parts = \explode('.', $ident);
        return \implode('.', \array_map(fn($p) => $this->qid($p), $parts));
    }

    /** Quote a single identifier with fallback + trim existing quotes. */
    private function qid(string $name): string
    {
        $raw = $this->stripQuotes($name);
        try {
            // Prefer driver-aware quoting when the DB provides custom logic
            return $this->db->quoteIdent($raw);
        } catch (\Throwable) {
            // Fallback pro PostgreSQL: "..."
            return '"' . \str_replace('"','""',$raw) . '"';
        }
    }

    /** Return [schema|null, table]; accepts 'schema.table' or plain 'table'. */
    private function splitSchemaAndName(string $table): array
    {
        $parts = \explode('.', $table, 2);
        if (\count($parts) === 2) {
            return [$this->stripQuotes($parts[0]), $this->stripQuotes($parts[1])];
        }
        return [null, $this->stripQuotes($parts[0])];
    }

    /** PG identifier limit is 63 bytes. */
    private function safeTriggerName(string $name): string
    {
        $n = $this->safeIdent($name);
        return \strlen($n) > 63 ? \substr($n, 0, 63) : $n;
    }

    /** Normalizace na [a-z0-9_]+, lowercased. */
    private function safeIdent(string $s): string
    {
        $x = \preg_replace('~[^a-z0-9_]+~i', '_', $s) ?? $s;
        return \strtolower(\trim($x, '_'));
    }

    /** Precision clamp (0..6). */
    private function clampPrecision(int $precision): int
    {
        return \max(0, \min(6, $precision));
    }

    /** Remove surrounding quotes "..." (when user supplies quoted input). */
    private function stripQuotes(string $id): string
    {
        $id = \trim($id);
        if (\strlen($id) >= 2 && $id[0] === '"' && \substr($id, -1) === '"') {
            return \substr($id, 1, -1);
        }
        return $id;
    }
}
