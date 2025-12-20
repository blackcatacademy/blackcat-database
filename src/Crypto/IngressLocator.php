<?php
declare(strict_types=1);

namespace BlackCat\Database\Crypto;

use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;

/**
 * Lazy loader for manifest-driven ingress adapters.
 *
 * This keeps the core package decoupled from blackcat-database-crypto while still
 * allowing repositories/services to benefit from deterministic encryption when the
 * optional packages + env configuration are present.
 */
final class IngressLocator
{
    private static bool $bootAttempted = false;
    private static ?DatabaseIngressAdapterInterface $adapter = null;
    private static ?string $bootFailureReason = null;
    /** @var callable|null */
    private static $coverageReporter = null;
    /** @var callable|null */
    private static $telemetryCallback = null;
    private static ?string $keysDirOverride = null;
    /** @var callable|null */
    private static $gatewayFactory = null;

    /**
     * Get the ingress adapter (fail-closed).
     *
     * This is the security core: if crypto ingress cannot boot, throw.
     */
    public static function adapter(): DatabaseIngressAdapterInterface
    {
        if (!self::$bootAttempted) {
            self::boot();
        }
        if (self::$adapter === null) {
            throw new \RuntimeException(self::requiredErrorMessage());
        }
        return self::$adapter;
    }

    /**
     * Return the ingress adapter or throw with a helpful error.
     */
    public static function requireAdapter(): DatabaseIngressAdapterInterface
    {
        return self::adapter();
    }

    public static function setAdapter(?DatabaseIngressAdapterInterface $adapter): void
    {
        self::$adapter = $adapter;
        self::$bootAttempted = ($adapter !== null);
        self::$bootFailureReason = null;
    }

    public static function configure(?string $mapPath = null, ?string $keysDir = null): void
    {
        // Map source is intentionally hardcoded to blackcat-database packages.
        self::$keysDirOverride = $keysDir;
        self::$bootAttempted = false;
        self::$adapter = null;
        self::$bootFailureReason = null;
    }

    /**
     * @param callable|null $factory fn(): \BlackCat\Database\Crypto\Gateway\DatabaseGatewayInterface
     */
    public static function setGatewayFactory(?callable $factory): void
    {
        self::$gatewayFactory = $factory;
    }

    public static function setCoverageReporter(?callable $reporter): void
    {
        self::$coverageReporter = $reporter;
    }

    public static function setTelemetryCallback(?callable $callback): void
    {
        self::$telemetryCallback = $callback;
    }

    private static function boot(): void
    {
        self::$bootAttempted = true;
        self::$bootFailureReason = null;

        $keysDir = self::$keysDirOverride ?? (getenv('BLACKCAT_KEYS_DIR') ?: getenv('APP_KEYS_DIR'));
        if (empty($keysDir)) {
            self::$bootFailureReason = 'BLACKCAT_KEYS_DIR is not set';
            return;
        }

        self::ensureAutoloaders();

        $mapClass = '\\BlackCat\\DatabaseCrypto\\Config\\EncryptionMap';
        $cryptoConfigClass = '\\BlackCat\\Crypto\\Config\\CryptoConfig';
        $cryptoManagerClass = '\\BlackCat\\Crypto\\CryptoManager';
        $adapterClass = '\\BlackCat\\DatabaseCrypto\\Adapter\\DatabaseCryptoAdapter';
        $ingressClass = '\\BlackCat\\DatabaseCrypto\\Ingress\\DatabaseIngressAdapter';
        $gatewayInterface = '\\BlackCat\\DatabaseCrypto\\Gateway\\DatabaseGatewayInterface';

        if (
            !class_exists($mapClass) ||
            !class_exists($cryptoConfigClass) ||
            !class_exists($cryptoManagerClass) ||
            !class_exists($adapterClass) ||
            !class_exists($ingressClass) ||
            !interface_exists($gatewayInterface)
        ) {
            self::$bootFailureReason = 'crypto ingress dependencies missing (install blackcat-crypto + blackcat-database-crypto)';
            return;
        }

        try {
            // Single source of truth: blackcat-database packages/*/schema/encryption-map.json.
            $map = self::loadEncryptionMapFromPackages($mapClass);
            if ($map->all() === []) {
                throw new \RuntimeException('no package encryption maps found (expected packages/*/schema/encryption-map.json)');
            }
        } catch (\Throwable $e) {
            self::$bootFailureReason = 'failed to load encryption map: ' . $e->getMessage();
            return;
        }

        try {
            $env = array_merge((array)getenv(), $_ENV, $_SERVER);
            $env['BLACKCAT_KEYS_DIR'] = $keysDir;
            $config = $cryptoConfigClass::fromEnv($env);
            $crypto = $cryptoManagerClass::boot($config);
        } catch (\Throwable $e) {
            self::$bootFailureReason = 'failed to boot CryptoManager: ' . $e->getMessage();
            return;
        }

        try {
            $gateway = self::resolveGateway();
            $dbAdapter = new $adapterClass($crypto, $map, $gateway);
            $reporter = null;
            if (self::$coverageReporter) {
                $reporter = self::wrapTelemetry(self::$coverageReporter);
            } elseif (\is_callable(self::$telemetryCallback)) {
                // Allow consumers to register only the telemetry callback without an explicit coverage reporter.
                $reporter = self::$telemetryCallback;
            }
            self::$adapter = new $ingressClass($dbAdapter, $map, true, $reporter);
        } catch (\Throwable $e) {
            self::$adapter = null;
            self::$bootFailureReason = 'failed to boot ingress adapter: ' . $e->getMessage();
        }
    }

    private static function requiredErrorMessage(): string
    {
        $reason = self::$bootFailureReason ? (' Reason: ' . self::$bootFailureReason . '.') : '';

        return 'DB crypto ingress is not available.'
            . $reason
            . ' Set BLACKCAT_KEYS_DIR and BLACKCAT_CRYPTO_MANIFEST, ensure packages/*/schema/encryption-map.json are available,'
            . ' and install blackcat-crypto + blackcat-database-crypto.';
    }

    private static function wrapTelemetry(callable $reporter): callable
    {
        $cb = self::$telemetryCallback;
        if (!\is_callable($cb)) {
            return $reporter;
        }
        return function (string $table, string $operation, array $columns) use ($reporter) {
            try {
                $reporter($table, $operation, $columns);
                $cb = self::$telemetryCallback;
                if (\is_callable($cb)) {
                    $cb($table, $operation, $columns);
                }
            } catch (\Throwable) {
            }
        };
    }

    private static function ensureAutoloaders(): void
    {
        static $registered = false;
        if ($registered) {
            return;
        }

        $workspace = dirname(__DIR__, 2);

        self::registerPsr4('BlackCat\\DatabaseCrypto\\', dirname($workspace) . '/blackcat-database-crypto/src');
        self::registerPsr4('BlackCat\\Crypto\\', dirname($workspace) . '/blackcat-crypto/src');
        self::registerPsr4('BlackCat\\Core\\', dirname($workspace) . '/blackcat-core/src');

        $registered = true;
    }

    private static function registerPsr4(string $prefix, string $dir): void
    {
        if (!is_dir($dir)) {
            return;
        }

        spl_autoload_register(static function (string $class) use ($prefix, $dir): void {
            if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
                return;
            }
            $relative = substr($class, strlen($prefix));
            $path = $dir . '/' . str_replace('\\', '/', $relative) . '.php';
            if (is_file($path)) {
                require $path;
            }
        }, true, true);
    }

    private static function resolveGateway(): \BlackCat\Database\Crypto\Gateway\DatabaseGatewayInterface
    {
        if (self::$gatewayFactory) {
            try {
                $gw = (self::$gatewayFactory)();
                if ($gw instanceof \BlackCat\Database\Crypto\Gateway\DatabaseGatewayInterface) {
                    return $gw;
                }
            } catch (\Throwable) {
            }
        }

        // Best effort default: when blackcat-database-crypto is installed and Database is initialized,
        // provide a real gateway over BlackCat\Core\Database (no raw PDO).
        $coreGatewayFqn = '\\BlackCat\\DatabaseCrypto\\Gateway\\CoreDatabaseGateway';
        if (\class_exists($coreGatewayFqn) && \class_exists('\\BlackCat\\Core\\Database') && \BlackCat\Core\Database::isInitialized()) {
            try {
                $db = \BlackCat\Core\Database::getInstance();
                $gw = new $coreGatewayFqn($db);
                if ($gw instanceof \BlackCat\Database\Crypto\Gateway\DatabaseGatewayInterface) {
                    return $gw;
                }
            } catch (\Throwable) {
            }
        }

        return new class implements \BlackCat\Database\Crypto\Gateway\DatabaseGatewayInterface {
            public function insert(string $table, array $payload, array $options = []): mixed
            {
                return $payload;
            }

            public function update(string $table, array $payload, array $criteria, array $options = []): mixed
            {
                return $payload;
            }
        };
    }

    private static function loadEncryptionMapFromPackages(string $mapClass): object
    {
        $packagesDir = rtrim(self::detectBlackcatDatabaseRootDir(), '/\\') . '/packages';
        if (!is_dir($packagesDir)) {
            throw new \RuntimeException('packages directory not found: ' . $packagesDir);
        }

        $merged = [];

        $definitionPaths = glob(rtrim($packagesDir, '/\\') . '/*/src/Definitions.php') ?: [];
        foreach ($definitionPaths as $definitionPath) {
            if (!is_file($definitionPath)) {
                continue;
            }

            $packageDir = dirname($definitionPath, 2);
            $mapPath = $packageDir . '/schema/encryption-map.json';

            $fqn = self::parseClassFqnFromFile($definitionPath);
            if ($fqn === null) {
                throw new \RuntimeException('Unable to detect package Definitions FQN: ' . $definitionPath);
            }

            if (!class_exists($fqn)) {
                require_once $definitionPath;
            }
            if (!class_exists($fqn) || !is_callable([$fqn, 'table']) || !is_callable([$fqn, 'columns'])) {
                throw new \RuntimeException('Invalid package Definitions class: ' . $fqn . ' (' . $definitionPath . ')');
            }

            /** @var mixed $table */
            $table = $fqn::table();
            /** @var mixed $columns */
            $columns = $fqn::columns();

            if (!is_string($table) || $table === '' || !is_array($columns)) {
                throw new \RuntimeException('Invalid package Definitions::table()/columns(): ' . $fqn);
            }

            $tableKey = strtolower($table);
            $expectedCols = array_values(array_map(static fn($c) => strtolower((string)$c), $columns));

            if (!is_file($mapPath)) {
                throw new \RuntimeException(sprintf('Missing encryption map for package table "%s": %s', $tableKey, $mapPath));
            }

            $config = self::readJsonFile($mapPath);
            [$mapTableKey, $mapCols] = self::extractSingleTableColumns($config, $mapPath);

            if ($mapTableKey !== $tableKey) {
                throw new \RuntimeException(
                    sprintf(
                        'Encryption map table mismatch in %s (expected "%s", found "%s")',
                        $mapPath,
                        $tableKey,
                        $mapTableKey
                    )
                );
            }

            self::validateColumnCoverage($tableKey, $expectedCols, $mapCols, $mapPath);
            self::validateColumnSpecs($tableKey, $mapCols, $expectedCols, $mapPath);
            self::validateUniqueKeysDoNotUseEncrypt($fqn, $tableKey, $mapCols, $mapPath);

            if (isset($merged[$tableKey])) {
                throw new \RuntimeException('Duplicate table in discovered encryption maps: ' . $tableKey);
            }

            $merged[$tableKey] = $mapCols;
        }

        /** @var class-string $mapClass */
        return $mapClass::fromArray([
            'tables' => array_map(static fn(array $cols): array => ['columns' => $cols], $merged),
        ]);
    }

    private static function detectBlackcatDatabaseRootDir(): string
    {
        $probe = '\\BlackCat\\Database\\Registry';
        if (!class_exists($probe)) {
            throw new \RuntimeException('blackcat-database is not autoloadable (missing ' . $probe . ')');
        }

        $file = (new \ReflectionClass($probe))->getFileName();
        if ($file === false) {
            throw new \RuntimeException('Cannot locate blackcat-database root directory');
        }

        return dirname($file, 2);
    }

    /**
     * @return array<string,mixed>
     */
    private static function readJsonFile(string $path): array
    {
        $json = file_get_contents($path);
        if ($json === false) {
            throw new \RuntimeException('Unable to read encryption map: ' . $path);
        }

        $data = json_decode($json, true);
        if (!is_array($data)) {
            throw new \RuntimeException('Invalid encryption map JSON: ' . $path);
        }

        /** @var array<string,mixed> $data */
        return $data;
    }

    /**
     * @param array<string,mixed> $config
     * @return array{0:string,1:array<string,array<string,mixed>>} [table, columns]
     */
    private static function extractSingleTableColumns(array $config, string $sourcePath): array
    {
        $tables = $config['tables'] ?? null;
        if (!is_array($tables) || $tables === []) {
            throw new \RuntimeException('Encryption map must contain non-empty "tables": ' . $sourcePath);
        }

        $tableNames = array_keys($tables);
        if (count($tableNames) !== 1) {
            throw new \RuntimeException('Per-package encryption map must define exactly 1 table: ' . $sourcePath);
        }

        $tableName = (string)$tableNames[0];
        $tableKey = strtolower($tableName);
        if ($tableKey === '') {
            throw new \RuntimeException('Invalid table name in encryption map: ' . $sourcePath);
        }

        $tableDef = $tables[$tableName] ?? null;
        if (!is_array($tableDef)) {
            throw new \RuntimeException('Invalid table definition in encryption map: ' . $sourcePath);
        }

        $columns = $tableDef['columns'] ?? null;
        if (!is_array($columns)) {
            throw new \RuntimeException('Encryption map table must contain "columns" object: ' . $sourcePath);
        }

        $out = [];
        foreach ($columns as $colName => $spec) {
            $colKey = strtolower((string)$colName);
            if ($colKey === '' || !is_array($spec)) {
                throw new \RuntimeException('Invalid column definition for ' . $tableKey . '.' . (string)$colName . ' in ' . $sourcePath);
            }

            /** @var array<string,mixed> $spec */
            $out[$colKey] = array_change_key_case($spec, CASE_LOWER);
        }

        ksort($out);
        return [$tableKey, $out];
    }

    /**
     * @param list<string> $expectedCols
     * @param array<string,array<string,mixed>> $mapCols
     */
    private static function validateColumnCoverage(string $table, array $expectedCols, array $mapCols, string $sourcePath): void
    {
        $expectedSet = array_fill_keys($expectedCols, true);
        $mapSet = array_fill_keys(array_keys($mapCols), true);

        $missing = array_values(array_diff(array_keys($expectedSet), array_keys($mapSet)));
        $extra = array_values(array_diff(array_keys($mapSet), array_keys($expectedSet)));

        sort($missing);
        sort($extra);

        if ($missing !== []) {
            throw new \RuntimeException(
                sprintf(
                    'Encryption map missing columns for %s in %s: %s',
                    $table,
                    $sourcePath,
                    implode(', ', $missing)
                )
            );
        }
        if ($extra !== []) {
            throw new \RuntimeException(
                sprintf(
                    'Encryption map contains unknown columns for %s in %s: %s',
                    $table,
                    $sourcePath,
                    implode(', ', $extra)
                )
            );
        }
    }

    /**
     * @param array<string,array<string,mixed>> $mapCols
     * @param list<string> $allColumns
     */
    private static function validateColumnSpecs(string $table, array $mapCols, array $allColumns, string $sourcePath): void
    {
        $allowedStrategies = ['encrypt', 'hmac', 'passthrough'];
        $allowedEncodings = ['raw', 'hex', 'base64'];
        $columnSet = array_fill_keys($allColumns, true);

        foreach ($mapCols as $column => $spec) {
            $strategyRaw = $spec['strategy'] ?? null;
            if (!is_string($strategyRaw) || $strategyRaw === '') {
                throw new \RuntimeException(sprintf('Missing "strategy" for %s.%s in %s', $table, $column, $sourcePath));
            }

            $strategy = strtolower($strategyRaw);
            if (!in_array($strategy, $allowedStrategies, true)) {
                throw new \RuntimeException(sprintf('Unknown strategy "%s" for %s.%s in %s', $strategy, $table, $column, $sourcePath));
            }

            $contextRaw = $spec['context'] ?? null;
            $context = is_string($contextRaw) ? trim($contextRaw) : '';

            if (in_array($strategy, ['encrypt', 'hmac'], true) && $context === '') {
                throw new \RuntimeException(sprintf('Missing "context" for %s.%s (strategy=%s) in %s', $table, $column, $strategy, $sourcePath));
            }

            $encodingRaw = $spec['encoding'] ?? null;
            if ($encodingRaw !== null) {
                if ($strategy !== 'hmac') {
                    throw new \RuntimeException(sprintf('Field "encoding" is only allowed for strategy=hmac (%s.%s in %s)', $table, $column, $sourcePath));
                }
                if (!is_string($encodingRaw) || trim($encodingRaw) === '') {
                    throw new \RuntimeException(sprintf('Invalid "encoding" for %s.%s in %s', $table, $column, $sourcePath));
                }
                $encoding = strtolower(trim($encodingRaw));
                $encoding = match ($encoding) {
                    'bin', 'binary' => 'raw',
                    'b64' => 'base64',
                    default => $encoding,
                };
                if (!in_array($encoding, $allowedEncodings, true)) {
                    throw new \RuntimeException(sprintf('Unknown "encoding" value "%s" for %s.%s in %s', $encoding, $table, $column, $sourcePath));
                }
            }

            $wrapCountRaw = $spec['wrap_count'] ?? null;
            if ($wrapCountRaw !== null) {
                if ($strategy !== 'encrypt') {
                    throw new \RuntimeException(sprintf('Field "wrap_count" is only allowed for strategy=encrypt (%s.%s in %s)', $table, $column, $sourcePath));
                }
                if (!is_int($wrapCountRaw) && !(is_string($wrapCountRaw) && ctype_digit($wrapCountRaw))) {
                    throw new \RuntimeException(sprintf('Invalid "wrap_count" for %s.%s in %s', $table, $column, $sourcePath));
                }
            }

            $writeKeyVersion = $spec['write_key_version'] ?? null;
            if ($writeKeyVersion !== null && !is_bool($writeKeyVersion)) {
                throw new \RuntimeException(sprintf('Invalid "write_key_version" for %s.%s in %s', $table, $column, $sourcePath));
            }
            if ($writeKeyVersion === true) {
                $kvc = $spec['key_version_column'] ?? ($column . '_key_version');
                if (!is_string($kvc) || trim($kvc) === '') {
                    throw new \RuntimeException(sprintf('Invalid "key_version_column" for %s.%s in %s', $table, $column, $sourcePath));
                }
                $kvcKey = strtolower(trim($kvc));
                if (!isset($columnSet[$kvcKey])) {
                    throw new \RuntimeException(
                        sprintf('Missing key version column "%s" in schema for %s.%s (map: %s)', $kvcKey, $table, $column, $sourcePath)
                    );
                }
                $kvcSpec = $mapCols[$kvcKey] ?? null;
                $kvcStrategy = is_array($kvcSpec) ? strtolower((string)($kvcSpec['strategy'] ?? '')) : '';
                if ($kvcStrategy !== 'passthrough') {
                    throw new \RuntimeException(
                        sprintf(
                            'Key version column "%s" must use strategy=passthrough for %s.%s (map: %s)',
                            $kvcKey,
                            $table,
                            $column,
                            $sourcePath
                        )
                    );
                }
            }

            $writeMeta = $spec['write_encryption_meta'] ?? null;
            if ($writeMeta !== null && !is_bool($writeMeta)) {
                throw new \RuntimeException(sprintf('Invalid "write_encryption_meta" for %s.%s in %s', $table, $column, $sourcePath));
            }
            if ($writeMeta === true) {
                $metaCol = $spec['encryption_meta_column'] ?? 'encryption_meta';
                if (!is_string($metaCol) || trim($metaCol) === '') {
                    throw new \RuntimeException(sprintf('Invalid "encryption_meta_column" for %s.%s in %s', $table, $column, $sourcePath));
                }
                $metaColKey = strtolower(trim($metaCol));
                if (!isset($columnSet[$metaColKey])) {
                    throw new \RuntimeException(
                        sprintf('Missing encryption meta column "%s" in schema for %s.%s (map: %s)', $metaColKey, $table, $column, $sourcePath)
                    );
                }
                $metaSpec = $mapCols[$metaColKey] ?? null;
                $metaStrategy = is_array($metaSpec) ? strtolower((string)($metaSpec['strategy'] ?? '')) : '';
                if ($metaStrategy !== 'passthrough') {
                    throw new \RuntimeException(
                        sprintf(
                            'Encryption meta column "%s" must use strategy=passthrough for %s.%s (map: %s)',
                            $metaColKey,
                            $table,
                            $column,
                            $sourcePath
                        )
                    );
                }
            }
        }
    }

    /**
     * @param class-string $definitionsFqn
     * @param array<string,array<string,mixed>> $mapCols
     */
    private static function validateUniqueKeysDoNotUseEncrypt(string $definitionsFqn, string $table, array $mapCols, string $sourcePath): void
    {
        if (!is_callable([$definitionsFqn, 'uniqueKeys'])) {
            return;
        }

        /** @var mixed $unique */
        $unique = $definitionsFqn::uniqueKeys();
        if (!is_array($unique)) {
            throw new \RuntimeException('Invalid Definitions::uniqueKeys() for table ' . $table . ' (' . $sourcePath . ')');
        }

        foreach ($unique as $keyCols) {
            if (!is_array($keyCols) || $keyCols === []) {
                continue;
            }

            $cols = [];
            foreach ($keyCols as $c) {
                $colKey = strtolower(trim((string)$c));
                if ($colKey !== '') {
                    $cols[] = $colKey;
                }
            }
            if ($cols === []) {
                continue;
            }

            foreach ($cols as $colKey) {
                $spec = $mapCols[$colKey] ?? null;
                if (!is_array($spec)) {
                    continue;
                }
                $strategy = strtolower((string)($spec['strategy'] ?? ''));
                if ($strategy === 'encrypt') {
                    throw new \RuntimeException(
                        sprintf(
                            'Unique key (%s) for table "%s" includes "%s" with strategy=encrypt (non-deterministic). Use hmac/passthrough instead. Map: %s',
                            implode(',', $cols),
                            $table,
                            $colKey,
                            $sourcePath
                        )
                    );
                }
            }
        }
    }

    private static function parseClassFqnFromFile(string $path): ?string
    {
        $src = file_get_contents($path);
        if ($src === false || $src === '') {
            return null;
        }

        $tokens = token_get_all($src);
        $namespace = '';
        $class = '';

        $count = count($tokens);
        for ($i = 0; $i < $count; $i++) {
            $tok = $tokens[$i];
            if (!is_array($tok)) {
                continue;
            }

            if ($tok[0] === T_NAMESPACE) {
                $nsParts = [];
                for ($j = $i + 1; $j < $count; $j++) {
                    $t = $tokens[$j];
                    if (is_array($t) && ($t[0] === T_STRING || $t[0] === T_NAME_QUALIFIED || $t[0] === T_NS_SEPARATOR)) {
                        $nsParts[] = $t[1];
                        continue;
                    }
                    if ($t === ';') {
                        break;
                    }
                }
                $namespace = trim(implode('', $nsParts), '\\');
            }

            if ($tok[0] === T_CLASS) {
                for ($j = $i + 1; $j < $count; $j++) {
                    $t = $tokens[$j];
                    if (is_array($t) && $t[0] === T_STRING) {
                        $class = $t[1];
                        break;
                    }
                }
            }
        }

        if ($class === '') {
            return null;
        }
        if ($namespace === '') {
            return $class;
        }
        return $namespace . '\\' . $class;
    }
}
