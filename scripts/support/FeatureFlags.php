<?php
declare(strict_types=1);
final class FeatureFlags
{
    private \PDO $db;
    private array $cache = [];
    private int $ttl;
    private int $loadedAt = 0;
    public function __construct(\PDO $db, int $ttlSeconds = 30) { $this->db = $db; $this->ttl = $ttlSeconds; }
    public function get(string $key, ?string $default = null): ?string {
        $now = time();
        if ($now - $this->loadedAt > $this->ttl) { $this->reload(); }
        return $this->cache[$key] ?? $default;
    }
    public function set(string $key, string $value): void {
        $stmt = $this->db->prepare("INSERT INTO flags (key, value, updated_at) VALUES (:k,:v,NOW()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=NOW()");
        $stmt->execute([':k'=>$key, ':v'=>$value]);
        $this->cache[$key] = $value; $this->loadedAt = time();
    }
    private function reload(): void {
        $this->cache = [];
        $q = $this->db->query("SELECT key, value FROM flags");
        foreach ($q->fetchAll(\PDO::FETCH_ASSOC) as $r) { $this->cache[$r['key']] = $r['value']; }
        $this->loadedAt = time();
    }
}
