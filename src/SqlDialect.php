<?php
declare(strict_types=1);

namespace BlackCat\Database;

enum SqlDialect: string { case mysql='mysql'; case postgres='postgres';
    public function isMysql(): bool { return $this === self::mysql; }
    public function isPg(): bool { return $this === self::postgres; }
}