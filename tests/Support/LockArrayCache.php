<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Cache\LockingCacheInterface;

final class LockArrayCache extends ArrayCache implements LockingCacheInterface
{
    /** @var array<string,array{token:string,expires:int}> */
    private array $locks = [];

    public function acquireLock(string $name, int $ttlSeconds = 10): ?string
    {
        $now = time();
        $entry = $this->locks[$name] ?? null;
        if ($entry !== null && $entry['expires'] > $now) {
            return null;
        }

        $token = bin2hex(random_bytes(6));
        $this->locks[$name] = [
            'token' => $token,
            'expires' => $now + max(1, $ttlSeconds),
        ];
        return $token;
    }

    public function releaseLock(string $name, string $token): bool
    {
        $entry = $this->locks[$name] ?? null;
        if ($entry === null || $entry['token'] !== $token) {
            return false;
        }
        unset($this->locks[$name]);
        return true;
    }

    public function forceHold(string $name, int $seconds): string
    {
        $token = bin2hex(random_bytes(6));
        $this->locks[$name] = ['token' => $token, 'expires' => time() + max(1, $seconds)];
        return $token;
    }

    public function forceRelease(string $name): void
    {
        unset($this->locks[$name]);
    }
}
