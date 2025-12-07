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
    /** @var callable|null */
    private static $coverageReporter = null;
    /** @var callable|null */
    private static $telemetryCallback = null;
    private static ?string $mapPathOverride = null;
    private static ?string $keysDirOverride = null;
    /** @var callable|null */
    private static $gatewayFactory = null;

    public static function adapter(): ?DatabaseIngressAdapterInterface
    {
        if (!self::$bootAttempted) {
            self::boot();
        }
        return self::$adapter;
    }

    public static function setAdapter(?DatabaseIngressAdapterInterface $adapter): void
    {
        self::$adapter = $adapter;
        self::$bootAttempted = true;
    }

    public static function configure(?string $mapPath = null, ?string $keysDir = null): void
    {
        self::$mapPathOverride = $mapPath;
        self::$keysDirOverride = $keysDir;
        self::$bootAttempted = false;
        self::$adapter = null;
    }

    /**
     * @param callable|null $factory fn(): DatabaseGatewayInterface
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

        $mapPath = self::$mapPathOverride ?? self::resolvePath(getenv('BLACKCAT_DB_ENCRYPTION_MAP') ?: null);
        if ($mapPath === null || !is_file($mapPath)) {
            return;
        }

        $keysDir = self::$keysDirOverride ?? (getenv('BLACKCAT_KEYS_DIR') ?: getenv('APP_KEYS_DIR'));
        if (empty($keysDir)) {
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
            return;
        }

        try {
            $map = $mapClass::fromFile($mapPath);
            $config = $cryptoConfigClass::fromEnv();
            $crypto = $cryptoManagerClass::boot($config);
        } catch (\Throwable) {
            return;
        }

        try {
            $gateway = self::resolveGateway();
            $dbAdapter = new $adapterClass($crypto, $map, $gateway);
            $reporter = self::$coverageReporter ? self::wrapTelemetry(self::$coverageReporter) : null;
            self::$adapter = new $ingressClass($dbAdapter, $map, true, $reporter);
        } catch (\Throwable) {
            self::$adapter = null;
        }
    }

    private static function resolvePath(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if ($path[0] === '/' || preg_match('/^[A-Za-z]:\\\\/', $path) === 1) {
            return $path;
        }
        $base = dirname(__DIR__, 2);
        $candidate = $base . '/' . ltrim($path, '/');
        $real = realpath($candidate);
        return $real !== false ? $real : $candidate;
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
