@{
  File   = 'src/Support/OperationResult.php'
  Tokens = @(
    'NAMESPACE'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Support;

final class OperationResult
{
    public function __construct(
        public readonly bool $ok,
        public readonly ?string $message = null,
        /** @var array<string,mixed> */
        public readonly array $data = []
    ) {}
    public static function ok(array $data = [], ?string $msg = null): self { return new self(true, $msg, $data); }
    public static function fail(string $msg, array $data = []): self { return new self(false, $msg, $data); }
}
'@
}