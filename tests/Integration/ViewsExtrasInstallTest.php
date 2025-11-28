<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

/**
 * Ensures feature-module (040_views_modules.*) and join (040_views_joins.*) views
 * declared in schema files are actually present in the database after install.
 */
final class ViewsExtrasInstallTest extends TestCase
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /**
     * @return array<string> Lowercased view names in current schema/search_path.
     */
    private static function actualViews(): array
    {
        $db = self::db();
        if ($db->isMysql()) {
            $schema = (string)$db->fetchOne('SELECT DATABASE()');
            $rows = $db->fetchAll(
                "SELECT TABLE_NAME AS name
                 FROM information_schema.VIEWS
                 WHERE table_schema = :s",
                [':s' => $schema]
            );
            return array_map(fn($r) => strtolower((string)$r['name']), $rows);
        }

        // Postgres
        $rows = $db->fetchAll(
            "SELECT table_schema, table_name
             FROM information_schema.views
             WHERE table_schema = ANY (current_schemas(true))"
        );
        return array_map(
            fn($r) => strtolower((string)$r['table_name']),
            $rows
        );
    }

    /**
     * Parse view names from a SQL file (looks for CREATE VIEW ...).
     *
     * @return array<string>
     */
    private static function declaredViewsFromFile(string $path): array
    {
        $sql = (string)@file_get_contents($path);
        if ($sql === '') {
            return [];
        }
        $sql = ltrim($sql, "\xEF\xBB\xBF"); // strip BOM
        $names = [];
        if (preg_match_all(
            '~CREATE\\s+(?:OR\\s+REPLACE\\s+)?(?:ALGORITHM\\s*=\\s*\\w+\\s+|DEFINER\\s*=\\s*(?:`[^`]+`@`[^`]+`|[^ \\t]+)\\s+|SQL\\s+SECURITY\\s+\\w+\\s+)*(?:MATERIALIZED\\s+)?VIEW\\s+((?:`?"?[A-Za-z0-9_]+`?"?\\.)?`?"?[A-Za-z0-9_]+`?"?)~i',
            $sql,
            $m
        )) {
            foreach ($m[1] as $raw) {
                $clean = str_replace(['`','"'],'', (string)$raw);
                $base  = str_contains($clean, '.') ? substr($clean, (int)strrpos($clean, '.') + 1) : $clean;
                if ($base !== '') {
                    $names[] = strtolower($base);
                }
            }
        }
        return array_values(array_unique($names));
    }

    public function test_feature_views_present(): void
    {
        $db = self::db();
        // Feature views are only expected when env enables them.
        $includeFeature = getenv('BC_INCLUDE_FEATURE_VIEWS');
        if (!($includeFeature === '1' || strtolower((string)$includeFeature) === 'true')) {
            $this->markTestSkipped('BC_INCLUDE_FEATURE_VIEWS is not enabled.');
        }

        $dial = $db->isMysql() ? 'mysql' : 'postgres';
        $actual = self::actualViews();
        $missing = [];

        foreach (glob(__DIR__ . '/../../packages/*/schema/modules/*/040_views_modules.' . $dial . '.sql') ?: [] as $file) {
            foreach (self::declaredViewsFromFile($file) as $v) {
                if (!in_array($v, $actual, true)) {
                    $missing[] = basename($file) . ':' . $v;
                }
            }
        }

        $this->assertEmpty($missing, "Missing feature views in DB:\n - " . implode("\n - ", $missing));
    }

    public function test_join_views_present(): void
    {
        $db = self::db();
        if ($this->envOn('BC_INSTALLER_SKIP_JOINS')) {
            $this->markTestSkipped('BC_INSTALLER_SKIP_JOINS is set.');
        }
        $dial = $db->isMysql() ? 'mysql' : 'postgres';
        $actual = self::actualViews();
        $missing = [];

        foreach (glob(__DIR__ . '/../../packages/*/schema/040_views_joins.' . $dial . '.sql') ?: [] as $file) {
            foreach (self::declaredViewsFromFile($file) as $v) {
                if (!in_array($v, $actual, true)) {
                    $missing[] = basename($file) . ':' . $v;
                }
            }
        }

        $this->assertEmpty($missing, "Missing join views in DB:\n - " . implode("\n - ", $missing));
    }

    /** Simple env helper (stringy booleans). */
    private function envOn(string $name): bool
    {
        $v = getenv($name);
        return $v === '1' || strtolower((string)$v) === 'true';
    }
}
