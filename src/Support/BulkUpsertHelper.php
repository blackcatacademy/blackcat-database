<?php

declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\BulkUpsertRepository;

/**
 * Lightweight helper to perform bulk UPSERTs using only Database + Definitions FQN.
 * Used by generated repositories when available.
 */
final class BulkUpsertHelper implements BulkUpsertRepository
{
    use BulkUpsertTrait;

    /**
     * @param class-string $definitionClass
     */
    /**
     * @param class-string $definitionClass
     */
    public function __construct(
        private Database $db,
        /** @var class-string */
        private string $definitionClass
    ) {}

    public function db(): Database
    {
        return $this->db;
    }

    /** @return class-string */
    public function def(): string
    {
        return $this->definitionClass;
    }
}
