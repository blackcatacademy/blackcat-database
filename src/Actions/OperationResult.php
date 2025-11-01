<?php
declare(strict_types=1);

namespace BlackCat\Database\Actions;

final class OperationResult implements \JsonSerializable
{
    public function __construct(
        public readonly bool $ok,
        public readonly ?string $message = null,
        /** @var array<string,mixed> */
        public readonly array $data = []
    ) {}

    /** @param array<string,mixed> $data */
    public static function ok(array $data = [], ?string $msg = null): self { return new self(true, $msg, $data); }
    /** @param array<string,mixed> $data */
    public static function fail(string $msg, array $data = []): self { return new self(false, $msg, $data); }

    public function jsonSerialize(): mixed { return ['ok'=>$this->ok,'message'=>$this->message,'data'=>$this->data]; }
}
