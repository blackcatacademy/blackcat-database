@{
  File   = 'src/Joins/[[CLASS]].php'  # např. UsersJoins.php
  Tokens = @('NAMESPACE','CLASS','JOIN_METHODS')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Joins;

/**
 * Metody generované z FK – generátor naplní těla do [[JOIN_METHODS]].
 * Vracená struktura: [string $sqlJoinFragment, array $params]
 */
final class [[CLASS]] {
[[JOIN_METHODS]]}
'@
}
