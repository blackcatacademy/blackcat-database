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

namespace BlackCat\Database\Events;

/**
 * Lightweight adapter to PSR-14 without a hard dependency.
 *
 * Pass any object that provides a public method:
 *   - dispatch(object $event): object
 *
 * Notes:
 * - This dispatcher is **best-effort** and **MUST NEVER throw** (exceptions are swallowed).
 * - The PSR-14 return value is ignored intentionally.
 * - We avoid importing the PSR interface to keep this package decoupled.
 *
 * @phpstan-type Psr14Dispatcher object
 */
final class Psr14CrudEventDispatcher implements CrudEventDispatcher
{
    /** Pre-bound invoker or null if the provided object is not compatible. */
    private readonly ?\Closure $invoke;

    /**
     * @param object $psr14Dispatcher Any object exposing `dispatch(object $event): object`.
     */
    public function __construct(object $psr14Dispatcher)
    {
        // Precompute a safe invoker; no reflection on each call.
        if (\method_exists($psr14Dispatcher, 'dispatch') && \is_callable([$psr14Dispatcher, 'dispatch'])) {
            /** @var \Closure(object): object $fn */
            $fn = static function (object $event) use ($psr14Dispatcher) {
                /** @phpstan-ignore-next-line ignore PSR return type; not used */
                return $psr14Dispatcher->dispatch($event);
            };
            $this->invoke = $fn;
        } else {
            // Not a compatible dispatcher -> no-op
            $this->invoke = null;
        }
    }

    /**
     * Convenience factory: returns no-op dispatcher when the candidate is not compatible.
     */
    public static function wrap(?object $candidate): CrudEventDispatcher
    {
        if ($candidate !== null
            && \method_exists($candidate, 'dispatch')
            && \is_callable([$candidate, 'dispatch'])) {
            return new self($candidate);
        }
        return NullCrudEventDispatcher::instance();
    }

    /** @inheritDoc */
    public function dispatch(#[\SensitiveParameter] CrudEvent $event): void
    {
        try {
            if ($this->invoke !== null) {
                ($this->invoke)($event);
            }
        } catch (\Throwable) {
            // Best-effort: swallow exceptions to never break writes / critical paths.
        }
    }
}
