# How-to: Retry & Backoff

```php
require __DIR__.'/scripts/support/Backoff.php';
$result = Backoff::withRetry(function(int $attempt) use ($pdo) {
  // execute a transient error-prone statement
  $pdo->exec("SELECT 1");
  return true;
}, maxAttempts: 5, baseMs: 50, capMs: 2000);
```
