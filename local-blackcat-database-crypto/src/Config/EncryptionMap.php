<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Config;

final class EncryptionMap
{
    /** @var array<string,mixed> */
    private array $tables;

    private function __construct(array $tables)
    {
        $this->tables = $tables;
    }

    public static function fromArray(array $config): self
    {
        $tables = $config['tables'] ?? [];
        if (!is_array($tables)) {
            throw new \InvalidArgumentException('encryption map: tables must be array');
        }

        $normalized = [];
        foreach ($tables as $table => $definition) {
            if (!is_array($definition)) {
                continue;
            }
            $columns = $definition['columns'] ?? [];
            if (!is_array($columns)) {
                continue;
            }
            $normalized[strtolower((string)$table)] = array_change_key_case($columns, CASE_LOWER);
        }

        return new self($normalized);
    }

    public static function fromFile(string $path): self
    {
        if (!is_file($path)) {
            throw new \RuntimeException('encryption map file not found: ' . $path);
        }

        $json = file_get_contents($path);
        if ($json === false) {
            throw new \RuntimeException('unable to read encryption map: ' . $path);
        }

        $data = json_decode($json, true);
        if (!is_array($data)) {
            throw new \RuntimeException('invalid encryption map JSON');
        }

        return self::fromArray($data);
    }

    /**
     * @return array<string,mixed>|null
     */
    public function columnsFor(string $table): ?array
    {
        return $this->tables[strtolower($table)] ?? null;
    }

    /**
     * @return array<string,array<string,mixed>>
     */
    public function all(): array
    {
        return $this->tables;
    }
}
