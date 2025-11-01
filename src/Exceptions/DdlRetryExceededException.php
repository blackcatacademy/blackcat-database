<?php
declare(strict_types=1);

namespace BlackCat\Database\Exceptions;

final class DdlRetryExceededException extends DdlException
{
    public function __construct(string $what, int $attempts, ?\Throwable $prev = null)
    {
        parent::__construct("DDL retries exceeded for {$what} (attempts={$attempts})", 0, $prev);
    }
}
