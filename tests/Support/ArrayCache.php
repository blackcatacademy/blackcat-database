<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use Psr\SimpleCache\CacheInterface;
use Psr\SimpleCache\InvalidArgumentException;

class ArrayCache implements CacheInterface
{
    /** @var array<string,array{value:mixed,expires:?int}> */
    private array $store = [];

    public function __construct(private int $maxKeyLength = 0) {}

    private function now(): int
    {
        return time();
    }

    /**
     * @throws InvalidArgumentException
     */
    private function assertKey(string $key): void
    {
        if ($key === '') {
            throw new ArrayCacheInvalidArgumentException('Cache key must not be empty.');
        }
        if ($this->maxKeyLength > 0 && strlen($key) > $this->maxKeyLength) {
            throw new ArrayCacheInvalidArgumentException('Cache key exceeds maximum length.');
        }
        if (preg_match('/[\x00-\x1F]/', $key)) {
            throw new ArrayCacheInvalidArgumentException('Cache key contains control characters.');
        }
    }

    private function normalizeTtl(null|int|\DateInterval $ttl): ?int
    {
        if ($ttl === null) {
            return null;
        }
        if ($ttl instanceof \DateInterval) {
            $base = new \DateTimeImmutable('@' . $this->now());
            return $base->add($ttl)->getTimestamp();
        }
        if (!is_int($ttl)) {
            return $this->now();
        }
        return $ttl <= 0 ? $this->now() : $this->now() + $ttl;
    }

    private function getRecord(string $key): mixed
    {
        $record = $this->store[$key] ?? null;
        if ($record === null) {
            return null;
        }
        if ($record['expires'] !== null && $record['expires'] <= $this->now()) {
            unset($this->store[$key]);
            return null;
        }
        return $record['value'];
    }

    public function get($key, $default = null): mixed
    {
        $this->assertKey((string)$key);
        $value = $this->getRecord((string)$key);
        return $value ?? $default;
    }

    public function set($key, $value, $ttl = null): bool
    {
        $this->assertKey((string)$key);
        $expires = $this->normalizeTtl($ttl);
        $this->store[(string)$key] = ['value' => $value, 'expires' => $expires];
        return true;
    }

    public function delete($key): bool
    {
        $this->assertKey((string)$key);
        unset($this->store[(string)$key]);
        return true;
    }

    public function clear(): bool
    {
        $this->store = [];
        return true;
    }

    public function getMultiple($keys, $default = null): iterable
    {
        $results = [];
        foreach ($keys as $key) {
            $results[$key] = $this->get($key, $default);
        }
        return $results;
    }

    public function setMultiple($values, $ttl = null): bool
    {
        foreach ($values as $key => $value) {
            $this->set((string)$key, $value, $ttl);
        }
        return true;
    }

    public function deleteMultiple($keys): bool
    {
        foreach ($keys as $key) {
            $this->delete((string)$key);
        }
        return true;
    }

    public function has($key): bool
    {
        $this->assertKey((string)$key);
        return $this->getRecord((string)$key) !== null;
    }
}

final class ArrayCacheInvalidArgumentException extends \InvalidArgumentException implements InvalidArgumentException
{
}
