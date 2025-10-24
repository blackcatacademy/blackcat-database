<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use PHPUnit\Framework\Assert;
use BlackCat\Core\Database;

final class AssertSql
{
    public static function tableExists(string $table): void
    {
        [$dial] = DbHarness::dialect();
        $db = Database::getInstance();
        $cnt = (int)$db->fetchOne(
            $dial->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t"
              : "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name=:t",
            [':t'=>$table]
        );
        Assert::assertSame(1, $cnt, "Table $table not found");
    }

    public static function viewExists(string $view): void
    {
        [$dial] = DbHarness::dialect();
        $db = Database::getInstance();
        $cnt = (int)$db->fetchOne(
            $dial->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :v"
              : "SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_views WHERE viewname = :v) THEN 1 ELSE 0 END",
            [':v'=>$view]
        );
        Assert::assertSame(1, $cnt, "View $view not found");
    }
}
