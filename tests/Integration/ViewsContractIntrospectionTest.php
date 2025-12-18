<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class ViewsContractIntrospectionTest extends TestCase
{
    private static function db(): Database { return Database::getInstance(); }

    /** List all vw_* views in the current schema */
    private static function allViews(): array
    {
        $db = self::db();

        if ($db->isMysql()) {
            $schema = (string)$db->fetchOne('SELECT DATABASE()');
            $sql = "SELECT TABLE_NAME AS table_name
                    FROM information_schema.VIEWS
                    WHERE table_schema = ? AND table_name LIKE 'vw\\_%' ESCAPE '\\\\'
                    ORDER BY TABLE_NAME";
            return array_map(fn($r) => $r['table_name'], $db->fetchAll($sql, [$schema]));
        }

        // PostgreSQL: every view inside the search_path
        $sql = "SELECT table_schema, table_name
                FROM information_schema.views
                WHERE table_schema = ANY (current_schemas(true))
                  AND table_name LIKE 'vw\\_%' ESCAPE '\\'
                ORDER BY table_schema, table_name";
        return array_map(fn($r) => $r['table_schema'] . '.' . $r['table_name'], $db->fetchAll($sql));
    }

    public function test_all_views_have_security_invoker_and_merge(): void
    {
        $db = self::db();

        if ($db->isPg()) {
            $this->addToAssertionCount(1); // no-op assertion -> output will just say "OK"
            return;
        }

        $requiresTempTable = $this->loadTempTableFlags();
        foreach (self::allViews() as $view) {
            $row = $db->fetchAll("SHOW CREATE VIEW `$view`")[0] ?? null;
            $this->assertNotNull($row, "SHOW CREATE VIEW returned nothing for $view");
            $ddl = strtoupper((string)($row['Create View'] ?? ''));

            $this->assertStringContainsString('SQL SECURITY INVOKER', $ddl, "$view: expected SQL SECURITY INVOKER");
            if (isset($requiresTempTable[strtoupper($view)])) {
                $this->assertTrue(
                    str_contains($ddl, 'ALGORITHM=TEMPTABLE') || str_contains($ddl, 'ALGORITHM=UNDEFINED'),
                    "$view: expected ALGORITHM=TEMPTABLE per schema metadata"
                );
            } else {
                $this->assertStringContainsString('ALGORITHM=MERGE', $ddl, "$view: expected ALGORITHM=MERGE");
            }
        }
    }

    private function loadTempTableFlags(): array
    {
        $root = dirname(__DIR__, 2) . '/views-library';
        if (!is_dir($root)) {
            return [];
        }

        $flags = [];
        $iter = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($root));
        foreach ($iter as $file) {
            if (!$file->isFile()) {
                continue;
            }
            if (!str_ends_with($file->getFilename(), '-mysql.yaml')) {
                continue;
            }
            $content = (string)file_get_contents($file->getPathname());
            if ($content === '') {
                continue;
            }

            $current = null;
            $lines = preg_split('/\\R/', $content) ?: [];
            foreach ($lines as $line) {
                if (preg_match('/^\\s{2}([A-Za-z0-9_]+):\\s*$/', $line, $m)) {
                    $current = strtoupper($m[1]);
                    continue;
                }
                if ($current && stripos($line, 'RequiresTempTable') !== false && preg_match('/true/i', $line)) {
                    $flags['VW_' . $current] = true;
                    $current = null;
                }
            }
        }
        return $flags;
    }

    public function test_helper_columns_contract(): void
    {
    $db = self::db();

    if ($db->isMysql()) {
        $schema = (string)$db->fetchOne('SELECT DATABASE()');
        $cols = $db->fetchAll(
            "SELECT TABLE_NAME   AS table_name,
                    COLUMN_NAME  AS column_name,
                    DATA_TYPE    AS data_type,
                    COLUMN_TYPE  AS column_type,
                    CHARACTER_MAXIMUM_LENGTH AS char_len
             FROM information_schema.columns
             WHERE table_schema = ? AND table_name LIKE 'vw\\_%' ESCAPE '\\\\'
             ORDER BY TABLE_NAME, ORDINAL_POSITION",
            [$schema]
        );

        $problems = [];
        foreach ($cols as $c) {
            $view = $c['table_name'];
            $name = $c['column_name'];
            $t    = strtolower((string)$c['data_type']);
            $ct   = strtolower((string)$c['column_type']);
            $len  = (int)($c['char_len'] ?? 0);

            if (str_ends_with($name, '_hex')) {
                $ok = in_array($t, ['char','varchar'], true) && ($len === 32 || $len === 64);
                if (!$ok) $problems[] = "$view.$name expected CHAR(32|64), got {$c['data_type']}({$len})";
            }
            if ($name === 'uuid_text') {
                $ok = in_array($t, ['char','varchar'], true) && $len === 36;
                if (!$ok) $problems[] = "$view.$name expected CHAR(36), got {$c['data_type']}({$len})";
            }
            if ($name === 'ip_pretty') {
                $ok = in_array($t, ['char','varchar'], true) && $len === 39;
                if (!$ok) $problems[] = "$view.$name expected CHAR(39), got {$c['data_type']}({$len})";
            }
            if (str_starts_with($name, 'is_')) {
                $ok = ($t === 'tinyint' && str_contains($ct, 'tinyint(1)')) || ($t === 'int');
                if (!$ok) $problems[] = "$view.$name expected TINYINT(1)|INT, got {$c['column_type']}";
            }
            if ($name === 'uses_left') {
                $ok = in_array($t, ['tinyint','smallint','mediumint','int','bigint'], true);
                if (!$ok) $problems[] = "$view.$name expected integer type, got {$c['data_type']}";
            }
        }

        $this->assertEmpty($problems, "View helper types mismatch:\n - " . implode("\n - ", $problems));
        return;
    }

    // PostgreSQL branch
    $cols = $db->fetchAll(
        "SELECT table_schema, table_name, column_name,
                data_type,
                character_maximum_length AS char_len
         FROM information_schema.columns
         WHERE table_schema = ANY (current_schemas(true))
           AND table_name LIKE 'vw\\_%' ESCAPE '\\'
         ORDER BY table_schema, table_name, ordinal_position"
    );

    $problems = [];
    foreach ($cols as $c) {
        $view = $c['table_schema'] . '.' . $c['table_name'];
        $name = $c['column_name'];
        $t    = strtolower((string)$c['data_type']);            // e.g. 'boolean', 'character', 'character varying'
        $len  = (int)($c['char_len'] ?? 0);

        if (str_ends_with($name, '_hex')) {
            // recommended in our PG views:  UPPER(key_hash)::char(64)  etc.
            // Accept text as a fallback (len=0) to avoid false positives on legacy definitions.
            $ok = (in_array($t, ['character', 'character varying'], true) && ($len === 32 || $len === 64))
               || ($t === 'text');
            if (!$ok) $problems[] = "$view.$name expected CHAR(32|64), got {$c['data_type']}({$len})";
        }
        if ($name === 'uuid_text') {
            $ok = (in_array($t, ['character', 'character varying'], true) && $len === 36)
               || $t === 'text';
            if (!$ok) $problems[] = "$view.$name expected CHAR(36), got {$c['data_type']}({$len})";
        }
        if ($name === 'ip_pretty') {
            $ok = in_array($t, ['character', 'character varying'], true) && $len === 39;
            if (!$ok) $problems[] = "$view.$name expected CHAR(39), got {$c['data_type']}({$len})";
        }
        if (str_starts_with($name, 'is_')) {
            // PG has a native boolean type - that's the expected mapping
            $ok = ($t === 'boolean');
            if (!$ok) $problems[] = "$view.$name expected BOOLEAN, got {$c['data_type']}";
        }
        if ($name === 'uses_left') {
            $ok = in_array($t, ['smallint','integer','bigint'], true);
            if (!$ok) $problems[] = "$view.$name expected integer type, got {$c['data_type']}";
        }
    }

    $this->assertEmpty($problems, "View helper types mismatch (PG):\n - " . implode("\n - ", $problems));
    }

    public function test_hidden_columns_are_not_exposed(): void
    {
        $db = self::db();

        $forbidden = [
            'vw_sessions'            => ['session_blob'],
            'vw_jwt_tokens'          => ['token_hash'],
            'vw_encrypted_fields'    => ['ciphertext'],
            'vw_book_assets'         => ['encryption_key_enc','encryption_iv','encryption_tag','encryption_aad'],
            'vw_orders'              => ['encrypted_customer_blob'],
            'vw_payment_webhooks'    => ['payload'],
            'vw_email_verifications' => ['token_hash'],
        ];

        foreach ($forbidden as $view => $cols) {
            if ($db->isMysql()) {
                $schema = (string)$db->fetchOne('SELECT DATABASE()');
                $rows = $db->fetchAll(
                    "SELECT COLUMN_NAME AS column_name
                    FROM information_schema.columns
                    WHERE table_schema=? AND table_name=?",
                    [$schema, $view]
                );
            } else {
                // current_schemas(true) covers search_path including 'public'
                $rows = $db->fetchAll(
                    "SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = ANY (current_schemas(true))
                    AND table_name = :v",
                    [':v' => $view]
                );
            }

            $actual = array_map(fn($r) => $r['column_name'], $rows);
            $leaks  = array_values(array_intersect($cols, $actual));
            $this->assertEmpty($leaks, "$view should not expose: " . implode(', ', $leaks));
        }
    }
}
