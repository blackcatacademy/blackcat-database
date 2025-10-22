@{
  File   = 'src/Exceptions.php'
  Tokens = @('NAMESPACE')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

class ModuleException extends \RuntimeException {}
class RepositoryException extends \RuntimeException {}
'@
}
