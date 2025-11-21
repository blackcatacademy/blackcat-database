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

namespace BlackCat\Database\Outbox;

use BlackCat\Core\Database;
use BlackCat\Database\Events\CrudEvent;
use BlackCat\Database\Events\CrudEventDispatcher;
use BlackCat\Database\Support\Telemetry;

/**
 * OutboxConsumer
 *
 * Pulls events from the SQL outbox and dispatches them to an in-process dispatcher.
 * - Fully parameterized DB usage is delegated to {@see OutboxRepository}.
 * - Transaction per batch (BEGIN .. CLAIM .. DISPATCH .. ACK/FAIL .. COMMIT).
 * - Safe JSON decoding with clear error paths (malformed payload => fail row).
 * - Dev-friendly: clamps, explicit types, small helpers, robust rollback in finally.
 */
final class OutboxConsumer
{
    private const MAX_LIMIT = 1000;

    public function __construct(
        private Database $db,
        private OutboxRepository $repo,
        private CrudEventDispatcher $dispatcher
    ) {}

    /**
     * Consume up to $limit events once.
     *
     * @param positive-int $limit Upper bound of rows to claim (clamped to 1..1000)
     * @return int Number of successfully ACKed events.
     * @throws \Throwable If the batch-level transaction fails before we can rollback.
     */
    public function runOnce(int $limit = 100): int
    {
        $limit = \max(1, \min(self::MAX_LIMIT, $limit));
        $acked = 0;

        // TODO(crypto-integrations): Verify claimed rows carry DatabaseIngressAdapter
        // attestation metadata (context hash, manifest version) before dispatching.
        $this->db->beginTransaction();
        $committed = false;
        try {
            $rows = $this->repo->claimBatch($limit); // expected: SKIP LOCKED/FOR UPDATE under the hood
            if (!$rows) {
                $this->db->commit();
                $committed = true;
                return 0;
            }

            foreach ($rows as $row) {
                /** @var array{id:int|string, payload:string|null, routing_key?:string|null} $row */
                $id = (int)$row['id'];
                try {
                    $payload = $this->decodeJson((string)($row['payload'] ?? ''));
                    $event = $this->toCrudEvent($payload, (string)($row['routing_key'] ?? 'outbox'));
                    $this->dispatcher->dispatch($event);

                    $this->repo->ack($id);
                    $acked++;
                } catch (\Throwable $e) {
                    // Never let a single row break the whole batch; mark the row failed with a short reason
                    $msg = \substr($e->getMessage(), 0, 500);
                    Telemetry::error('Outbox consume failed', ['id' => $id, 'err' => $msg]);
                    $this->repo->fail($id, $msg, 60);
                }
            }

            $this->db->commit();
            $committed = true;
            return $acked;
        } finally {
            // Ensure no dangling tx on errors
            if (!$committed) {
                try { $this->db->rollback(); } catch (\Throwable) { /* swallow */ }
            }
        }
    }

    // -------------------------- internals --------------------------

    /**
     * Decode JSON payload (throws on error with compact message).
     * @return array<string,mixed>
     */
    private function decodeJson(string $json): array
    {
        $json = \trim($json);
        if ($json === '') {
            return [];
        }
        try {
            /** @var mixed $data */
            $data = \json_decode($json, true, flags: \JSON_THROW_ON_ERROR);
        } catch (\Throwable $e) {
            throw new \RuntimeException('Invalid JSON payload: ' . $e->getMessage(), 0, $e);
        }
        return \is_array($data) ? $data : [];
    }

    /**
     * Build a CrudEvent from a decoded payload.
     * If payload declares "__type" = "CrudEvent", we reconstruct it strictly;
     * otherwise we emit a generic "create" event carrying payload in "after".
     *
     * @param array<string,mixed> $payload
     */
    private function toCrudEvent(array $payload, string $routingKey): CrudEvent
    {
        if (($payload['__type'] ?? null) === 'CrudEvent') {
            return new CrudEvent(
                operation: (string)($payload['operation'] ?? CrudEvent::OP_CREATE),
                table:     (string)($payload['table']     ?? $routingKey ?: 'outbox'),
                id:        $payload['id']    ?? null,
                affected:  (int)($payload['affected'] ?? 1),
                before:    \is_array($payload['before'] ?? null) ? $payload['before'] : null,
                after:     \is_array($payload['after']  ?? null) ? $payload['after']  : null,
                context:   \is_array($payload['context']?? null) ? $payload['context']: []
            );
        }

        // Generic passthrough: use a valid CrudEvent operation (avoid custom values like "outbox")
        return new CrudEvent(
            operation: CrudEvent::OP_CREATE,
            table:     $routingKey !== '' ? $routingKey : 'outbox',
            id:        null,
            affected:  1,
            before:    null,
            after:     $payload,
            context:   ['source' => 'outbox']
        );
    }
}
