<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\Observability;
use PDOException;
use RuntimeException;
use BlackCat\Core\Database;

final class ObservabilityTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
    }

    public function testSqlCommentAndWithDefaults(): void
    {
        $db = Database::getInstance();
        $meta = Observability::withDefaults(['svc'=>'svc','op'=>'op'], $db);
        $cmt  = Observability::sqlComment($meta);
        $this->assertNotSame('', $cmt);
        $this->assertStringContainsString('svc=svc', $cmt);
        $this->assertStringContainsString('op=op', $cmt);
    }

    public function testEnsureCorrAndMsAndShouldSample(): void
    {
        $m = Observability::ensureCorr([]);
        $this->assertArrayHasKey('corr', $m);

        $t0 = microtime(true);
        usleep(1000);
        $ms = Observability::ms($t0);
        $this->assertGreaterThanOrEqual(1, $ms);

        putenv('BC_OBS_SAMPLE=0');  $this->assertFalse(Observability::shouldSample([]));
        putenv('BC_OBS_SAMPLE=1');  $this->assertTrue(Observability::shouldSample([]));
        putenv('BC_OBS_SAMPLE'); // unset
    }

    public function testErrorFields(): void
    {
        $pdoe = new PDOException('x');
        $pdoe->errorInfo = ['40001', 0, 'serialization'];
        $e = new RuntimeException('wrap', 0, $pdoe);
        $f = Observability::errorFields($e);
        $this->assertSame('40001', $f['sqlstate']);
    }
}
