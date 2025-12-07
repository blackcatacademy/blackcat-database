<?php
declare(strict_types=1);

namespace BlackCat\Database\Crypto\Gateway;

/**
 * Lightweight stub to satisfy Database crypto gateway resolution during static analysis.
 * External packages may provide a richer implementation; this keeps typehints intact.
 *
 * Extend the legacy DatabaseCrypto interface so adapters expecting the old namespace
 * accept implementations from the new namespace.
 */
interface DatabaseGatewayInterface extends \BlackCat\DatabaseCrypto\Gateway\DatabaseGatewayInterface
{
}
