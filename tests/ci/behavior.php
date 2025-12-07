<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require __DIR__ . '/bootstrap.php';

/* ---- DSN bootstrap (same as in run.php) ---- */
$which = getenv('BC_DB') ?: 'mysql';
if ($which === 'mysql') {
    $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
    $user = getenv('MYSQL_USER') ?: 'root';
    $pass = getenv('MYSQL_PASS') ?: 'root';
} else {
    $dsn  = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
    $user = getenv('PG_USER') ?: 'postgres';
    $pass = getenv('PG_PASS') ?: 'postgres';
}
Database::init([
    'dsn' => $dsn, 'user'=> $user, 'pass'=> $pass,
    'init_commands' => ["SET timezone TO 'UTC'"]
]);
$db = Database::getInstance();

$fail = 0;
function ok(string $msg): void { echo "[OK] $msg\n"; }
function ng(string $msg): void { echo "[FAIL] $msg\n"; global $fail; $fail++; }

/* 1) View masking: app_settings.type='secret' must return NULL in the view */
try {
    $db->execute("DELETE FROM app_settings WHERE setting_key IN ('t_secret','t_plain')");
    $db->execute("INSERT INTO app_settings (setting_key, setting_value, type) VALUES (:k,:v,:t)", [
        ':k'=>'t_secret', ':v'=>'s3cr3t', ':t'=>'secret'
    ]);
    $db->execute("INSERT INTO app_settings (setting_key, setting_value, type) VALUES (:k,:v,:t)", [
        ':k'=>'t_plain', ':v'=>'hello', ':t'=>'string'
    ]);
    $v1 = $db->fetchValue("SELECT setting_value FROM vw_app_settings WHERE setting_key = :k", [':k'=>'t_secret']);
    $v2 = $db->fetchValue("SELECT setting_value FROM vw_app_settings WHERE setting_key = :k", [':k'=>'t_plain']);
    $raw= $db->fetchValue("SELECT setting_value FROM app_settings WHERE setting_key = :k", [':k'=>'t_secret']);
    ($v1 === null && $v2 === 'hello' && $raw === 's3cr3t')
        ? ok("vw_app_settings masks secret and leaves other values intact")
        : ng("vw_app_settings masking does not match expectations");
} catch (Throwable $e) { ng("app_settings view test: ".$e->getMessage()); }

/* 2) UNIQUE constraint: crypto_keys.uq_keys_basename_version */
try {
    $db->execute("DELETE FROM crypto_keys WHERE basename IN ('t_base')");
    $db->execute("INSERT INTO crypto_keys (basename, version) VALUES (:b,:v)", [':b'=>'t_base', ':v'=>1]);
    $dupOk = false;
    try {
        $db->execute("INSERT INTO crypto_keys (basename, version) VALUES (:b,:v)", [':b'=>'t_base', ':v'=>1]);
        $dupOk = true; // should not have succeeded
    } catch(Throwable $e) { /* expected */ }
    $dupOk ? ng("crypto_keys UNIQUE nevyhodil chybu") : ok("crypto_keys UNIQUE funguje");
} catch (Throwable $e) { ng("crypto_keys UNIQUE test: ".$e->getMessage()); }

/* 3) FK SET NULL: key_events.key_id -> crypto_keys(id) ON DELETE SET NULL */
try {
    $db->execute("DELETE FROM key_events WHERE basename = 't_base'");
    $db->execute("DELETE FROM crypto_keys WHERE basename = 't_base'");
    $db->execute("INSERT INTO crypto_keys (basename, version) VALUES ('t_base', 2)");
    $kid = (int)$db->lastInsertId() ?: (int)$db->fetchValue("SELECT id FROM crypto_keys WHERE basename='t_base' AND version=2");
    // minimal event_type NOT NULL + defaults for other fields
    $db->execute("INSERT INTO key_events (key_id, basename, event_type) VALUES (:k,'t_base','created')", [':k'=>$kid]);
    $eid = (int)$db->lastInsertId() ?: (int)$db->fetchValue("SELECT id FROM key_events WHERE basename='t_base' ORDER BY id DESC LIMIT 1");
    $db->execute("DELETE FROM crypto_keys WHERE id = :id", [':id'=>$kid]);
    $after = $db->fetchValue("SELECT key_id FROM key_events WHERE id = :eid", [':eid'=>$eid]);
    ($after === null) ? ok("FK ON DELETE SET NULL works (key_events.key_id)") : ng("FK SET NULL failed, key_id=$after");
} catch (Throwable $e) { ng("key_events FK test: ".$e->getMessage()); }

/* 4) CHECK constraint: app_settings.type jen z whitelistu */
try {
    $threw = false;
    try {
        $db->execute("INSERT INTO app_settings (setting_key, type) VALUES ('t_bad','not-allowed')");
    } catch (Throwable $e) { $threw = true; }
    $threw ? ok("CHECK (app_settings.type) vynucen") : ng("CHECK (app_settings.type) nebyl vynucen");
} catch (Throwable $e) { ng("app_settings CHECK test: ".$e->getMessage()); }

/* 5) Defaults: updated_at in app_settings must populate without explicit insert */
try {
    $db->execute("INSERT INTO app_settings (setting_key, type) VALUES ('t_default','string')");
    $ts = (string)$db->fetchValue("SELECT updated_at FROM app_settings WHERE setting_key='t_default'");
    ($ts !== '') ? ok("DEFAULT timestamp populated (app_settings.updated_at)") : ng("DEFAULT timestamp not populated");
} catch (Throwable $e) { ng("app_settings default timestamp: ".$e->getMessage()); }

/** @var int $fail */
if ((int)$fail > 0) { echo "FAILED behavior tests: $fail\n"; exit(20); }
echo "ALL GREEN (behavior)\n";
