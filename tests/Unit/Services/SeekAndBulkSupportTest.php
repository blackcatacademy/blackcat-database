<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Services\Features\SeekAndBulkSupport;
use BlackCat\Database\Contracts\SeekPaginableRepository;
use BlackCat\Database\Contracts\BulkUpsertRepository;
use RuntimeException;

final class SeekHost
{
    use SeekAndBulkSupport;
    public int $txnCalls = 0;
    public array $lockCalls = [];

    public function __construct(public object $repo, private bool $hasLock)
    {
    }

    public function paginate(object $criteria): array
    {
        return ['items' => [['id' => 1], ['id' => 2]]];
    }

    public function txn(callable $fn): mixed
    {
        $this->txnCalls++;
        return $fn();
    }

    public function withRowLock(mixed $id, callable $fn, string $mode = 'wait'): mixed
    {
        if (!$this->hasLock) {
            throw new RuntimeException('lock not available');
        }
        $this->lockCalls[] = [$id, $mode];
        return $fn(['id' => $id], null);
    }
}

final class SeekAndBulkSupportTest extends TestCase
{
    private function host(object $repo, bool $hasLock = true): SeekHost
    {
        return new SeekHost($repo, $hasLock);
    }

    public function testPaginateBySeekDelegatesWhenSupported(): void
    {
        $repo = new class implements SeekPaginableRepository {
            public array $args = [];
            public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array
            {
                $this->args = [$criteria,$order,$cursor,$limit];
                return [[['id' => 5]], ['colValue' => 1, 'pkValue' => 5]];
            }
        };
        $host = $this->host($repo);
        [$items] = $host->paginateBySeek((object)[], ['col' => 'id', 'dir' => 'asc', 'pk' => 'id'], null, 10);
        $this->assertSame(5, $items[0]['id']);
    }

    public function testPaginateBySeekNormalizesPkArrayToString(): void
    {
        $repo = new class implements SeekPaginableRepository {
            public array $orderSpec = [];
            public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array
            {
                $this->orderSpec = $order;
                return [[], null];
            }
        };
        $host = $this->host($repo);
        $host->paginateBySeek((object)[], ['col' => 'id', 'dir' => 'asc', 'pk' => ['id']], null, 10);
        $this->assertSame('id', $repo->orderSpec['pk']);
    }

    public function testPaginateBySeekFallsBackToPaginate(): void
    {
        $host = $this->host(new stdClass());
        [$items, $cursor] = $host->paginateBySeek((object)[], ['col'=>'id','dir'=>'asc','pk'=>'id'], null, 1);
        $this->assertCount(1, $items);
        $this->assertNull($cursor);
    }

    public function testBulkUpsertPrefersRepoAndFallsBack(): void
    {
        $repo = new class implements BulkUpsertRepository {
            public array $rows = [];
            public function upsertMany(array $rows, array $keys = [], array $updateColumns = []): void { $this->rows = $rows; }
        };
        $host = $this->host($repo);
        $host->bulkUpsert([['id' => 1]]);
        $this->assertSame([['id' => 1]], $repo->rows);

        $fallbackRepo = new class {
            public array $calls = [];
            public function upsert(array $row): void { $this->calls[] = $row; }
        };
        $host2 = $this->host($fallbackRepo);
        $host2->bulkUpsert([['id' => 2], ['id' => 3]]);
        $this->assertSame(1, $host2->txnCalls);
        $this->assertCount(2, $fallbackRepo->calls);
    }

    public function testTryWithRowLockUsesHostCapability(): void
    {
        $repo = new class {};
        $host = $this->host($repo, hasLock: true);
        $res = $host->tryWithRowLock(5, fn($row) => $row['id'] ?? null);
        $this->assertSame(5, $res);
        $this->assertSame([[5, 'skip_locked']], $host->lockCalls);

        $hostNoLock = $this->host($repo, hasLock: false);
        $res2 = $hostNoLock->tryWithRowLock(7, fn($row) => $row);
        $this->assertNull($res2); // fallback closure receives null
    }
}
