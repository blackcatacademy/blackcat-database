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
        self::$bootAttempted = true;
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
        $packagesLoaderClass = '\\BlackCat\\DatabaseCrypto\\Config\\PackagesEncryptionMapLoader';
        $cryptoConfigClass = '\\BlackCat\\Crypto\\Config\\CryptoConfig';
        $cryptoManagerClass = '\\BlackCat\\Crypto\\CryptoManager';
        $adapterClass = '\\BlackCat\\DatabaseCrypto\\Adapter\\DatabaseCryptoAdapter';
        $ingressClass = '\\BlackCat\\DatabaseCrypto\\Ingress\\DatabaseIngressAdapter';
        $gatewayInterface = '\\BlackCat\\DatabaseCrypto\\Gateway\\DatabaseGatewayInterface';

        if (
            !class_exists($packagesLoaderClass) ||
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
            $map = $packagesLoaderClass::fromAutodetectedBlackcatDatabaseRoot();
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
}
