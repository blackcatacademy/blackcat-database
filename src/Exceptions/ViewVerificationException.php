<?php
declare(strict_types=1);

namespace BlackCat\Database\Exceptions;

final class ViewVerificationException extends DdlException
{
    public static function drift(string $view, array $got, array $expect): self
    {
        return new self(
            "View directives mismatch for '{$view}': got=" . json_encode($got) .
            " expect=" . json_encode($expect)
        );
    }
}
