<?php
declare(strict_types=1);

namespace BlackCat\Database\Exceptions;

final class InstallerException extends \RuntimeException
{
    public static function dependencyCycle(string $at): self
    {
        return new self("Dependency cycle detected at '{$at}'.");
    }

    public static function invalidRegistry(string $message): self
    {
        return new self("Schema registry error: {$message}");
    }
}
