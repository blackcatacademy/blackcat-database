<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class ViewsContractIntrospectionTest extends TestCase
{
    private static function db(): Database { return Database::getInstance(); }

    /** Seznam všech view vw_* v aktuálním schématu */
    private static function allViews(): array
    {
        $db = self::db();
        $schema = (string)$db->fetchOne('SELECT DATABASE()');
        $sql = "SELECT TABLE_NAME AS table_name
                FROM information_schema.VIEWS
                WHERE table_schema = ? AND table_name LIKE 'vw\\_%' ESCAPE '\\\\'
                ORDER BY TABLE_NAME";
        return array_map(fn($r)=>$r['table_name'], $db->fetchAll($sql, [$schema]));
    }

    public function test_all_views_have_security_invoker_and_merge(): void
    {
        $db = self::db();
        $exceptions = []; // prázdné, až vše sjednotíš na MERGE; dočasně sem můžeš dát seznam výjimek

        foreach (self::allViews() as $view) {
            $row = $db->fetchAll("SHOW CREATE VIEW `$view`")[0] ?? null;
            $this->assertNotNull($row, "SHOW CREATE VIEW returned nothing for $view");
            $ddl = strtoupper((string)($row['Create View'] ?? '')); // normalizace kvůli porovnání

            $this->assertStringContainsString('SQL SECURITY INVOKER', $ddl, "$view: expected SQL SECURITY INVOKER");

            if (!in_array($view, $exceptions, true)) {
                $this->assertStringContainsString('ALGORITHM=MERGE', $ddl, "$view: expected ALGORITHM=MERGE");
            }
        }
    }

    public function test_helper_columns_contract(): void
    {
        $db = self::db();
        $schema = (string)$db->fetchOne('SELECT DATABASE()');

        $cols = $db->fetchAll(
            "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, CHARACTER_MAXIMUM_LENGTH
             FROM information_schema.columns
             WHERE table_schema = ? AND table_name LIKE 'vw\\_%' ESCAPE '\\\\'
             ORDER BY TABLE_NAME, ORDINAL_POSITION",
             [$schema]
        );

        $problems = [];

        foreach ($cols as $c) {
            $view = $c['TABLE_NAME'];
            $name = $c['COLUMN_NAME'];
            $t    = strtolower((string)$c['DATA_TYPE']);
            $ct   = strtolower((string)$c['COLUMN_TYPE']);
            $len  = (int)($c['CHARACTER_MAXIMUM_LENGTH'] ?? 0);

            if (str_ends_with($name, '_hex')) {
                $ok = in_array($t, ['char','varchar'], true) && ($len === 32 || $len === 64);
                if (!$ok) $problems[] = "$view.$name expected CHAR(32|64), got {$c['DATA_TYPE']}({$len})";
            }
            if ($name === 'uuid_text') {
                $ok = in_array($t, ['char','varchar'], true) && $len === 36;
                if (!$ok) $problems[] = "$view.$name expected CHAR(36), got {$c['DATA_TYPE']}({$len})";
            }
            if ($name === 'ip_pretty') {
                $ok = in_array($t, ['char','varchar'], true) && $len === 39;
                if (!$ok) $problems[] = "$view.$name expected CHAR(39), got {$c['DATA_TYPE']}({$len})";
            }
            if (str_starts_with($name, 'is_')) {
                $ok = ($t === 'tinyint' && str_contains($ct, 'tinyint(1)'))
                // view výrazy: MySQL je reportuje jako INT (nebo po CASTu BIGINT UNSIGNED)
                || ($t === 'int');
                if (!$ok) $problems[] = "$view.$name expected TINYINT(1)|INT, got {$c['COLUMN_TYPE']}";
            }
            if ($name === 'uses_left') {
                $ok = in_array($t, ['tinyint','smallint','mediumint','int','bigint'], true);
                if (!$ok) $problems[] = "$view.$name expected integer type, got {$c['DATA_TYPE']}";
            }
        }

        $this->assertEmpty($problems, "View helper types mismatch:\n - ".implode("\n - ", $problems));
    }

    public function test_hidden_columns_are_not_exposed(): void
    {
        $db = self::db();
        $schema = (string)$db->fetchOne('SELECT DATABASE()');

        // mapa view => sloupce, které NESMÍ být ve view
        $forbidden = [
            'vw_users'                   => ['password_hash','password_algo','password_key_version'],
            'vw_sessions'                => ['token_hash','session_blob'],
            'vw_jwt_tokens'              => ['token_hash'],
            'vw_encrypted_fields'        => ['ciphertext'],
            'vw_book_assets'             => ['encryption_key_enc','encryption_iv','encryption_tag','encryption_aad'],
            'vw_orders'                  => ['encrypted_customer_blob'],
            'vw_payment_webhooks'        => ['payload'], // expose jen has_payload
            'vw_email_verifications'     => ['token_hash','validator_hash'],
        ];

        foreach ($forbidden as $view => $cols) {
            // načti dostupné sloupce ve view
            $rows = $db->fetchAll(
                "SELECT COLUMN_NAME FROM information_schema.columns
                 WHERE table_schema=? AND table_name=?",
                 [$schema, $view]
            );
            $actual = array_map(fn($r)=>$r['COLUMN_NAME'], $rows);

            $leaks = array_values(array_intersect($cols, $actual));
            $this->assertEmpty($leaks, "$view should not expose: ".implode(', ', $leaks));
        }
    }
}
