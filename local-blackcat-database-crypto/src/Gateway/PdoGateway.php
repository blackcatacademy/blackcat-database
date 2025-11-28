<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Gateway;

use PDO;
use PDOException;

final class PdoGateway implements DatabaseGatewayInterface
{
    public function __construct(private readonly PDO $pdo)
    {
        $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    }

    public function insert(string $table, array $payload, array $options = []): mixed
    {
        $columns = array_keys($payload);
        $placeholders = array_map(static fn (string $col) => ':' . $col, $columns);
        $sql = sprintf(
            'INSERT INTO %s (%s) VALUES (%s)',
            $table,
            implode(', ', $columns),
            implode(', ', $placeholders)
        );
        $stmt = $this->pdo->prepare($sql);
        foreach ($payload as $col => $value) {
            $stmt->bindValue(':' . $col, $value);
        }
        $stmt->execute();
        return $stmt;
    }

    public function update(string $table, array $payload, array $criteria, array $options = []): mixed
    {
        if ($criteria === []) {
            throw new \InvalidArgumentException('Update requires criteria to avoid mass writes');
        }

        $sets = [];
        foreach ($payload as $col => $value) {
            $sets[] = sprintf('%s = :set_%s', $col, $col);
        }
        $wheres = [];
        foreach ($criteria as $col => $value) {
            $wheres[] = sprintf('%s = :where_%s', $col, $col);
        }
        $sql = sprintf(
            'UPDATE %s SET %s WHERE %s',
            $table,
            implode(', ', $sets),
            implode(' AND ', $wheres)
        );
        $stmt = $this->pdo->prepare($sql);
        foreach ($payload as $col => $value) {
            $stmt->bindValue(':set_' . $col, $value);
        }
        foreach ($criteria as $col => $value) {
            $stmt->bindValue(':where_' . $col, $value);
        }
        $stmt->execute();
        return $stmt;
    }
}
