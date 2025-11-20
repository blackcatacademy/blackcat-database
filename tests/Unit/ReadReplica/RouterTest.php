<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\ReadReplica\Router;
use BlackCat\Core\Database;

final class RouterTest extends TestCase
{
    /**
     * @return \PHPUnit\Framework\MockObject\MockObject&Database
     */
    private function mockDb(): Database
    {
        $db = $this->getMockBuilder(Database::class)
            ->disableOriginalConstructor()
            ->onlyMethods(['inTransaction','execWithMeta','fetchAllWithMeta','fetchRowWithMeta','fetchValueWithMeta','existsWithMeta'])
            ->getMock();
        $db->method('inTransaction')->willReturn(false);
        return $db;
    }

    public function testReadQueriesHitReplicaWhenAvailable(): void
    {
        $primary = $this->mockDb();
        $replica = $this->mockDb();
        $replica->expects($this->once())
            ->method('fetchAllWithMeta')
            ->with($this->stringContains('SELECT'))
            ->willReturn([]);

        $router = new Router($primary, $replica);
        $router->fetchAllWithMeta('SELECT * FROM demo', [], ['corr' => 'c1']);
    }

    public function testStickyAfterWriteKeepsReadsOnPrimary(): void
    {
        $primary = $this->mockDb();
        $replica = $this->mockDb();
        $primary->expects($this->once())
            ->method('execWithMeta')
            ->willReturn(1);
        $primary->expects($this->once())
            ->method('fetchValueWithMeta')
            ->willReturn(1);
        $replica->expects($this->never())->method('fetchValueWithMeta');

        $router = new Router($primary, $replica, 5000);
        $router->execWithMeta('INSERT INTO demo VALUES (1)', [], ['corr' => 'sticky']);
        $router->fetchValueWithMeta('SELECT COUNT(*) FROM demo', [], null, ['corr' => 'sticky']);
    }
}
