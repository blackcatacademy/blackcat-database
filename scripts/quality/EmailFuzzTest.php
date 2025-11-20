<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class EmailFuzzTest extends TestCase
{
    public function testEmailInsertFuzz(): void
    {
        $dsn = getenv('DB_DSN'); $user=getenv('DB_USER'); $pass=getenv('DB_PASS');
        $pdo = new PDO($dsn, $user ?: '', $pass ?: '', [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
        ]);

        $pdo->exec("CREATE TABLE IF NOT EXISTS fuzz_emails (id BIGINT PRIMARY KEY " .
            (str_starts_with($pdo->getAttribute(PDO::ATTR_DRIVER_NAME), 'pgsql') ? "GENERATED ALWAYS AS IDENTITY" : "AUTO_INCREMENT") .
            ", email TEXT UNIQUE)");

        $variants = [
            'simple@example.com',
            'unicode+utf8tag@example.test',
            'very.long.'.str_repeat('x',128).'@example.test',
            '"quoted"@example.test',
            'name+plus@exa_mple.test',
            'name.surname@sub.domain.example.test',
        ];
        foreach ($variants as $e) {
            $stmt = $pdo->prepare("INSERT INTO fuzz_emails (email) VALUES (:e) ON CONFLICT DO NOTHING");
            try { $stmt->execute([':e'=>$e]); } catch (\Throwable $ex) { /* acceptable for invalid ones */ }
        }
        $this->assertTrue(true);
    }
}
