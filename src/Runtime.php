<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use Psr\Log\LoggerInterface;
use BlackCat\Core\Database\QueryCache;

final class Runtime
{
    public function __construct(
        private Database $db,
        private SqlDialect $dialect,
        private ?LoggerInterface $logger = null,
        private ?QueryCache $qcache = null
    ) {}

    public function db(): Database { return $this->db; }
    public function dialect(): SqlDialect { return $this->dialect; }
    public function logger(): ?LoggerInterface { return $this->logger; }
    public function qcache(): ?QueryCache { return $this->qcache; }
}
