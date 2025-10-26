@{
  File   = 'src/Exceptions.php'
  Tokens = @('NAMESPACE')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

class ModuleException extends \RuntimeException {}
class RepositoryException extends \RuntimeException {}

class NotFoundException extends RepositoryException {}
class ConflictException extends RepositoryException {}          // duplicitní klíč, apod.
class ConcurrencyException extends RepositoryException {}       // optimistic lock
class ValidationException extends ModuleException {}
class TransactionException extends ModuleException {}
'@
}
