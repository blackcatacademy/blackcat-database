<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Database\Support\Criteria;

final class DummyCriteria extends Criteria
{
    protected function filterable(): array
    {
        return ['id', 'tenant_id', 'status', 'created_at', 'name'];
    }

    protected function searchable(): array
    {
        return ['name'];
    }

    protected function defaultPerPage(): int
    {
        return 10;
    }

    protected function maxPerPage(): int
    {
        return 50;
    }
}
