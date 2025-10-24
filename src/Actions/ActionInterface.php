<?php
declare(strict_types=1);

namespace BlackCat\Database\Actions;

use BlackCat\Database\Runtime;

interface ActionInterface
{
    /** @return OperationResult */
    public function __invoke(Runtime $rt, array $input): OperationResult;
}
