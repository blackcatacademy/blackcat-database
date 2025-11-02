<?php
declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;

/**
 * PgCompat – podpůrná vrstva pro PostgreSQL:
 *  - vytvoří schéma `bc_compat` a sadu kompat funkcí (idempotentně)
 *  - poskytne helpery pro auto-updaty timestampů a UUID binární derivát
 *
 * Použití:
 *   $pg = new PgCompat(Database::getInstance());
 *   $pg->install(); // jednorázově při startu/instalaci
 *   // volitelně na vybrané tabulky:
 *   $pg->ensureUpdatedAtTrigger('sessions', 'updated_at');
 *   $pg->ensureUuidBinComputed('orders', 'uuid', 'uuid_bin');
 */
final class PgCompat
{
    public function __construct(private Database $db) {}

    /**
     * Nainstaluje bc_compat schema a kompatibilní funkce.
     * Idempotentní – volání opakovaně nevadí.
     */
    public function install(): void
    {
        // 1) schéma
        $this->db->exec("CREATE SCHEMA IF NOT EXISTS bc_compat");

        // 2) LAST_INSERT_ID() → lastval()
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.last_insert_id() RETURNS bigint
LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT lastval()::bigint $$;
SQL);

        // 3) CURDATE() – MySQL kompat, vrací DATE
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.curdate() RETURNS date
LANGUAGE sql STABLE STRICT AS $$ SELECT CURRENT_DATE $$;
SQL);

        // 4) HEX helpery (bez pgcrypto; čistě přes bytea/hex literal)
        //    unhex(text)  → bytea   ;   hex(bytea) → text( lower/upper si dořeš ve view )
        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.unhex(hex text) RETURNS bytea
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT ('\\x' || regexp_replace($1, '\\s', '', 'g'))::bytea
$$;
SQL);

        $this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.hex(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT string_agg(lpad(to_hex(get_byte($1, g.i)), 2, '0'), '')
  FROM generate_series(0, length($1)-1) AS g(i)
$$;
SQL);

        // 5) INET6_ATON / INET6_NTOA – VARBINARY16 styl (IPv4 → v6-mapped ::ffff.a.b.c.d)
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

  -- IPv6 canonical + expand ::
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

  -- ::ffff:0:0/96 (IPv4-mapped) detekuj byte-po-bytu
  is_v4mapped :=
    get_byte(b,0)=0 AND get_byte(b,1)=0 AND get_byte(b,2)=0 AND get_byte(b,3)=0 AND
    get_byte(b,4)=0 AND get_byte(b,5)=0 AND get_byte(b,6)=0 AND get_byte(b,7)=0 AND
    get_byte(b,8)=0 AND get_byte(b,9)=0 AND get_byte(b,10)=255 AND get_byte(b,11)=255;

  IF is_v4mapped THEN
    a := get_byte(b,12); b2 := get_byte(b,13); c := get_byte(b,14); d := get_byte(b,15);
    RETURN a::text || '.' || b2::text || '.' || c::text || '.' || d::text;
  END IF;

  -- prostý (nekomprimovaný) zápis IPv6
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

// 5b) Přátelštější aliasy ve stejném schématu (snadné volání z view/testů)
$this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.ip_pton(addr text) RETURNS bytea
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT bc_compat.inet6_aton($1)
$$;
SQL);

$this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.ip_ntop(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT bc_compat.inet6_ntoa($1)
$$;
SQL);

// 6) ON UPDATE CURRENT_TIMESTAMP -> univerzální trigger
$this->db->exec(<<<'SQL'
CREATE OR REPLACE FUNCTION bc_compat.tg_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP(6);
  RETURN NEW;
END $$;
SQL);
    }

    /**
     * Přidá/obnoví trigger pro automatický update TIMESTAMP sloupce (default 'updated_at').
     * (MySQL náhrada za "ON UPDATE CURRENT_TIMESTAMP")
     */
    public function ensureUpdatedAtTrigger(string $table, string $column = 'updated_at'): void
    {
        // pojmenujeme předvídatelně, ať lze snadno DROP/CREATE
        $trg = 'bc_touch_' . strtolower(preg_replace('~\\W+~', '_', $table)) . '_' . strtolower($column);

        // 1) pokud sloupec neexistuje, tiše skonči
        $exists = (bool)$this->db->fetchOne(
            "SELECT 1
             FROM information_schema.columns
             WHERE table_schema = ANY (current_schemas(true))
               AND lower(table_name) = lower(:t)
               AND lower(column_name) = lower(:c)
             LIMIT 1",
            [':t'=>$table, ':c'=>$column]
        );
        if (!$exists) return;

        // 2) nahodíme trigger (DROP IF EXISTS je až od PG 14 pro TRIGGER; obejdeme přes katalog)
        $this->dropTriggerIfExists($trg, $table);

        $qiT = $this->db->quoteIdent($table);
        $qiTr= $this->db->quoteIdent($trg);
        $this->db->exec("CREATE TRIGGER {$qiTr}
                         BEFORE UPDATE ON {$qiT}
                         FOR EACH ROW
                         WHEN (OLD.{$this->db->quoteIdent($column)} IS DISTINCT FROM NEW.{$this->db->quoteIdent($column)})
                         EXECUTE FUNCTION bc_compat.tg_touch_updated_at()");
    }

    /**
     * Doplní generovaný bytea sloupec z UUID textu – MySQL styl „uuid_bin“ (STORED).
     * Implementace bez pgcrypto: ('\\x'||replace(uuid,'-',''))::bytea
     */
    public function ensureUuidBinComputed(string $table, string $uuidCol = 'uuid', string $uuidBinCol = 'uuid_bin'): void
    {
        $qiT  = $this->db->quoteIdent($table);
        $qiU  = $this->db->quoteIdent($uuidCol);
        $qiUB = $this->db->quoteIdent($uuidBinCol);

        // přidej sloupec, pokud chybí
        $colExists = (bool)$this->db->fetchOne(
            "SELECT 1
             FROM information_schema.columns
             WHERE table_schema = ANY (current_schemas(true))
               AND lower(table_name)=lower(:t) AND lower(column_name)=lower(:c)
             LIMIT 1",
            [':t'=>$table, ':c'=>$uuidBinCol]
        );
        if (!$colExists) {
            $this->db->exec(
                "ALTER TABLE {$qiT}
                 ADD COLUMN {$qiUB} bytea
                 GENERATED ALWAYS AS (('\\x' || replace({$qiU}::text, '-', ''))::bytea) STORED"
            );
        }

        // volitelný unikátní index (pokud používáš v MySQL)
        $this->db->exec(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_{$this->safeIdent($table)}_{$this->safeIdent($uuidBinCol)}
             ON {$qiT} ({$qiUB})"
        );
    }

    /** Doporučené init příkazy pro Database::init(['init_commands'=>…]) */
    public function recommendedInitCommands(): array
    {
        return [
            "SET TIME ZONE 'UTC'",
            // dovol používat bc_compat bez kvalifikace: SELECT last_insert_id()
            "SET search_path = public, bc_compat",
        ];
    }

    /* ---------------- interní utilitky ---------------- */

    private function dropTriggerIfExists(string $trigger, string $table): void
    {
        $row = $this->db->fetch(
            "SELECT 1
             FROM pg_trigger t
             JOIN pg_class c ON c.oid=t.tgrelid
             JOIN pg_namespace n ON n.oid=c.relnamespace
             WHERE NOT t.tgisinternal
               AND lower(t.tgname)=lower(:tr)
               AND c.relname = :tbl
               AND n.nspname = ANY (current_schemas(true))
             LIMIT 1",
            [':tr'=>$trigger, ':tbl'=>$table]
        );
        if ($row) {
            $qiT  = $this->db->quoteIdent($table);
            $qiTr = $this->db->quoteIdent($trigger);
            $this->db->exec("DROP TRIGGER {$qiTr} ON {$qiT}");
        }
    }

    private function safeIdent(string $s): string
    {
        return strtolower(preg_replace('~[^a-z0-9_]+~i', '_', $s));
    }
}
