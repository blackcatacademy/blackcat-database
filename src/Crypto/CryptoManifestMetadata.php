<?php
declare(strict_types=1);

namespace BlackCat\Database\Crypto;

/**
 * Utility for generating manifest fingerprint metadata for CRUD/outbox events.
 * In the absence of a real manifest fingerprint provider, we compute a stable
 * hash based on table/operation/column set. Once Vault exposes official IDs,
 * this helper can be swapped to call that API.
 */
final class CryptoManifestMetadata
{
    /**
     * @param array<int,string> $columns
     * @return array<string,mixed>|null
     */
    public static function build(string $table, string $operation, array $columns): ?array
    {
        $table = \trim($table);
        if ($table === '') {
            return null;
        }
        $operation = \strtolower(\trim($operation));
        \sort($columns);
        $fingerprint = \hash('sha256', $table . '|' . $operation . '|' . \json_encode($columns));

        return [
            'table'       => $table,
            'operation'   => $operation,
            'columns'     => $columns,
            'fingerprint' => $fingerprint,
        ];
    }
}
