<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Fakes;

use Psr\SimpleCache\CacheInterface;
use DateInterval;

final class ArrayCache implements CacheInterface
{
    private array $data = [];

    public function get(string $key, mixed $default = null): mixed {
        $e = $this->data[$key] ?? null;
        if (!$e) return $default;
        if ($e['ttl'] !== null && $e['ttl'] < time()) { unset($this->data[$key]); return $default; }
        return $e['val'];
    }
    public function set(string $key, mixed $value, DateInterval|int|null $ttl = null): bool {
        $sec = $ttl instanceof DateInterval ? (new \DateTimeImmutable())->add($ttl)->getTimestamp() - time() : ($ttl ?? null);
        $this->data[$key] = ['val'=>$value, 'ttl'=>$sec !== null ? time()+ (int)$sec : null];
        return true;
    }
    public function delete(string $key): bool { unset($this->data[$key]); return true; }
    public function clear(): bool { $this->data = []; return true; }
    public function getMultiple(iterable $keys, mixed $default = null): iterable {
        $out = [];
        foreach ($keys as $k) $out[$k] = $this->get($k, $default);
        return $out;
    }
    public function setMultiple(iterable $values, DateInterval|int|null $ttl = null): bool {
        foreach ($values as $k=>$v) $this->set((string)$k, $v, $ttl);
        return true;
    }
    public function deleteMultiple(iterable $keys): bool {
        foreach ($keys as $k) $this->delete((string)$k);
        return true;
    }
    public function has(string $key): bool {
        $e = $this->data[$key] ?? null;
        return $e !== null && ($e['ttl'] === null || $e['ttl'] >= time());
    }
}
