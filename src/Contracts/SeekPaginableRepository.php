<?php
declare(strict_types=1);

namespace BlackCat\Database\Contracts;

/**
 * Optional capability for repositories that support keyset (seek) pagination.
 */
interface SeekPaginableRepository
{
    /**
     * @param object $criteria arbitrary criteria object (often extends Criteria)
     * @param array{col:string,dir:'asc'|'desc',pk:string} $order
     * @param array{colValue:mixed,pkValue:mixed}|null $cursor
     * @return array{0:array<int,array<string,mixed>>,1:array{colValue:mixed,pkValue:mixed}|null}
     */
    public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array;
}
