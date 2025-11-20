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

namespace BlackCat\Database\Support;

use BlackCat\Core\Database\QueryCache;

/**
 * Trait for convenient QueryCache prefix invalidation after repository writes.
 *
 * Goals:
 * - avoid conflicts with host class properties (trait DOES NOT define one),
 * - prefix detection order: $override → static::cachePrefix() → "table-{$table}:",
 * - support local and shared invalidation (when QueryCache supports it),
 * - safely resolve Definitions::table() via def() on the repository,
 * - silent best-effort behavior (cache errors never block writes).
 *
 * Host class requirements (one of):
 *  - public/protected property `protected ?QueryCache $qcache`,
 *  - or method `getQueryCache(): ?QueryCache`,
 *  - optionally `public static function cachePrefix(): string`,
 *  - optionally `public function def(): class-string` returning Definitions FQCN with `static function table(): string`.
 */
trait RepositoryCacheInvalidationTrait
{
    /**
     * Invalidate cache prefix.
     *
     * @param string      $table           table name (fallback for prefix)
     * @param string|null $overridePrefix  when provided, use this prefix directly
     */
    protected function invalidateTablePrefix(string $table, ?string $overridePrefix = null): void
    {
        $qcache = $this->resolveQueryCache();
        if (!$qcache) {
            return;
        }

        $prefix = $this->detectCachePrefix($table, $overridePrefix);
        if ($prefix === '') {
            return;
        }

        // Local invalidation
        try {
            $qcache->invalidatePrefix($prefix);
        } catch (\Throwable $_) {
            // best-effort
        }

        // Cross-process invalidation (when available)
        try {
            if (\method_exists($qcache, 'invalidatePrefixShared')) {
                $qcache->invalidatePrefixShared($prefix);
            }
        } catch (\Throwable $_) {
            // best-effort
        }
    }

    /**
     * Short alias: invalidate prefix for the current table via Definitions::table().
     * Table resolution:
     *  - if the host implements def() and returns an FQCN with table(), use that table;
     *  - otherwise no invalidation happens (safe no-op).
     */
    protected function invalidateSelfCache(): void
    {
        $table = $this->detectRepositoryTable();
        if ($table !== null && $table !== '') {
            $this->invalidateTablePrefix($table);
        }
    }

    /* ============================ Internal helpers ============================ */

    /** Fetch QueryCache from the host class (property or getter). */
    private function resolveQueryCache(): ?QueryCache
    {
        // Prefer getter when available
        if (\method_exists($this, 'getQueryCache')) {
            try {
                /** @var mixed $qc */
                $qc = $this->getQueryCache();
                return $qc instanceof QueryCache ? $qc : null;
            } catch (\Throwable) {
                return null;
            }
        }

        // Safely read the property if present (avoid dynamic property collisions)
        if (\property_exists($this, 'qcache')) {
            /** @var mixed $qc */
            $qc = $this->{'qcache'};
            return $qc instanceof QueryCache ? $qc : null;
        }

        return null;
    }

    /** Determine appropriate prefix for invalidation. */
    private function detectCachePrefix(string $table, ?string $override): string
    {
        if ($override !== null && $override !== '') {
            return $override;
        }

        // Prefer custom prefix from repository (static or instance method)
        try {
            if (\is_callable([static::class, 'cachePrefix'])) {
                /** @var mixed $p */
                $p = \call_user_func([static::class, 'cachePrefix']);
                if (\is_string($p) && $p !== '') {
                    return $p;
                }
            } elseif (\method_exists($this, 'cachePrefix')) {
                /** @phpstan-ignore-next-line */
                $p = (string) $this->cachePrefix();
                if ($p !== '') {
                    return $p;
                }
            }
        } catch (\Throwable $_) {
            // fall through
        }

        // Fallback: table-<table>:
        return 'table-' . $table . ':';
    }

    /** Attempt to derive table name from Definitions (repo->def()::table()). */
    private function detectRepositoryTable(): ?string
    {
        try {
            if (!\method_exists($this, 'def')) {
                return null;
            }
            /** @var mixed $fqn */
            $fqn = $this->def();
            if (!\is_string($fqn) || $fqn === '' || !\class_exists($fqn)) {
                return null;
            }
            if (!\method_exists($fqn, 'table')) {
                return null;
            }
            /** @var mixed $t */
            $t = $fqn::table();
            return \is_string($t) && $t !== '' ? $t : null;
        } catch (\Throwable) {
            return null;
        }
    }
}
