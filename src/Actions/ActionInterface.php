<?php
declare(strict_types=1);

namespace BlackCat\Database\Actions;

use BlackCat\Database\Runtime;

interface ActionInterface
{
    /**
     * @param array<string,mixed> $input
     */
    public function __invoke(Runtime $rt, array $input): OperationResult;
}
