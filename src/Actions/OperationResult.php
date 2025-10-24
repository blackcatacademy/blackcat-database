<?php
declare(strict_types=1);

namespace BlackCat\Database\Actions;

final class OperationResult implements \JsonSerializable
{
    public function __construct(
        public bool $ok,
        public ?string $message = null,
        public array $data = []
    ) {}

    public static function ok(array $data=[], ?string $msg=null): self { return new self(true, $msg, $data); }
    public static function fail(string $msg, array $data=[]): self { return new self(false, $msg, $data); }

    public function jsonSerialize(): array { return ['ok'=>$this->ok,'message'=>$this->message,'data'=>$this->data]; }
}
