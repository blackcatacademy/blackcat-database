<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Support\Observability;
use Psr\Log\LoggerInterface;

/**
 * Runtime is a thin contextual wrapper around the Database, dialect, logger and (optional) query cache.
 * - Immutable (readonly properties)
 * - DX helpers (with*, isPg/isMysql, id, serverVersion, requireQcache)
 * - Provides safe observability metadata via contextMeta()
 * - TODO(crypto-integrations): extend contextMeta() once VaultCoverageTracker feeds manifest
 *   fingerprints so every DB runtime call automatically tags encryption coverage.
 */
final class Runtime
{
    public function __construct(
        private readonly Database $db,
        private readonly SqlDialect $dialect,
        private readonly ?LoggerInterface $logger = null,
        private readonly ?QueryCache $qcache = null
    ) {
        // Dialect should match the actual driver; log mismatches but do not fail construction.
        try {
            $real = $this->db->dialect(); // BlackCat\Core\Database::dialect(): SqlDialect
            if ($real !== $this->dialect) {
                $this->logger?->warning('runtime-dialect-mismatch', [
                    'runtime' => $this->dialect->value,
                    'actual'  => $real->value,
                    'dbId'    => $this->db->id(),
                ]);
            }
        } catch (\Throwable $_) {
            // Ignore – we do not want to interrupt construction.
        }
    }

    /** Convenience factory that derives the dialect and logger from the Database instance. */
    public static function fromDb(
        Database $db,
        ?LoggerInterface $logger = null,
        ?QueryCache $qcache = null
    ): self {
        try {
            $logger = $logger ?? $db->getLogger();
        } catch (\Throwable) {
            // keep null
        }
        return new self($db, $db->dialect(), $logger, $qcache);
    }

    public function db(): Database { return $this->db; }
    public function dialect(): SqlDialect { return $this->dialect; }
    public function logger(): ?LoggerInterface { return $this->logger; }
    public function qcache(): ?QueryCache { return $this->qcache; }

    // --- Ergonomics / convenience shortcuts ---
    public function isPg(): bool { return $this->dialect->isPg(); }
    public function isMysql(): bool { return $this->dialect->isMysql(); }
    public function id(): string { return $this->db->id(); }
    public function serverVersion(): ?string { return $this->db->serverVersion(); }

    /** Require that a query cache is configured, otherwise throw with a clear message. */
    public function requireQcache(): QueryCache
    {
        if ($this->qcache === null) {
            throw new \LogicException('QueryCache is not configured for this Runtime.');
        }
        return $this->qcache;
    }

    /** Safely augments observability metadata (corr/db/driver plus optional svc/op/actor). */
    public function contextMeta(array $extra = []): array
    {
        return Observability::withDefaults($extra, $this->db);
    }

    /** Immutable copy-style with* helpers. */
    public function withDb(Database $db): self
    {
        return new self($db, $db->dialect(), $this->logger, $this->qcache);
    }
    public function withDialect(SqlDialect $dialect): self
    {
        return new self($this->db, $dialect, $this->logger, $this->qcache);
    }
    public function withLogger(?LoggerInterface $logger): self
    {
        return new self($this->db, $this->dialect, $logger, $this->qcache);
    }
    public function withQcache(?QueryCache $qcache): self
    {
        return new self($this->db, $this->dialect, $this->logger, $qcache);
    }

    /** Lightweight logging/debug helper without serializing dependencies. */
    public function toArray(): array
    {
        return [
            'dbId'    => $this->id(),
            'dialect' => $this->dialect->value,
            'hasLogger' => $this->logger !== null,
            'hasQcache' => $this->qcache !== null,
            'serverVersion' => $this->serverVersion(),
        ];
    }
}
