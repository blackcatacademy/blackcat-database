@{
  File    = "src/Joins/[[CLASS]].php"
  Tokens  = @('NAMESPACE','CLASS','JOIN_METHODS','DATABASE_FQN')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Joins;

use BlackCat\Database\Support\SqlIdentifier as Ident;
use [[DATABASE_FQN]] as Database;

/**
 * Methods generated from foreign keys.
 *
 * Return structure: [string $sqlJoinFragment, array $params]
 * Join policy:
 *   - -JoinPolicy left  => always LEFT JOIN (default)
 *   - -JoinPolicy all   => INNER JOIN if ALL local FK columns are NOT NULL
 *   - -JoinPolicy any   => INNER JOIN if AT LEAST ONE local FK column is NOT NULL
 */
final class [[CLASS]] {

    /** @internal */
    private function qi(?Database $db, string $ident): string {
        return $db ? Ident::qi($db, $ident) : $ident;
    }

    /** @internal */
    private function q(?Database $db, string $ident): string {
        return $db ? Ident::q($db, $ident) : $ident;
    }

    /** @internal Short SQL alias validation (guards against invalid input). */
    private function assertAlias(string $s): string {
        if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $s)) {
            throw new \InvalidArgumentException("Invalid SQL alias: {$s}");
        }
        return $s;
    }

    /** @internal Validate both aliases and ensure they differ. */
    private function assertAliasPair(string $alias, string $as): array {
        $alias = $this->assertAlias($alias);
        $as    = $this->assertAlias($as);
        if ($alias === $as) {
            throw new \InvalidArgumentException("Join alias must differ from base alias: {$alias}");
        }
        return [$alias, $as];
    }

[[JOIN_METHODS]]
}
'@
}
