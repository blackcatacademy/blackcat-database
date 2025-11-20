#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * BlackCat Scaffold CLI
 *
 * Commands:
 *   make:module <Name>
 *   make:test <Name>
 *   make:repository <Name>
 *   make:service <Name>
 *   make:criteria <Name>
 *   make:mapper <Name>
 *   make:dto <Name>
 *   make:migration <Name>
 *   make:view <Name>
 *   make:module-tests <Name>
 *   make:audit-module
 *   make:tenant-scope
 *   make:replica-router
 *   make:demo-data <Name> [count]
 *   make:howto
 *   make:all <Name>         # module + criteria + epic test suite + migration + view
 */

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This utility must run from the CLI.\n");
    exit(1);
}

$argv = $_SERVER['argv'] ?? [];
if (count($argv) < 2) {
    fail('Usage: php tools/scaffold.php <command> <Name?>');
}

$cmd = $argv[1];
$nameArg = $argv[2] ?? '';
$extraArgs = array_slice($argv, 3);

$paths = [
    'modules'   => realpath(__DIR__ . '/../src/Modules') ?: __DIR__ . '/../src/Modules',
    'tests'     => realpath(__DIR__ . '/../tests') ?: __DIR__ . '/../tests',
    'templates' => realpath(__DIR__ . '/../templates') ?: __DIR__ . '/../templates',
];

switch ($cmd) {
    case 'make:module':
        $n = requireName($nameArg);
        scaffoldModule($n, $paths);
        ok("Module scaffold created at src/Modules/{$n}");
        break;

    case 'make:test':
        $n = requireName($nameArg);
        scaffoldModuleSmokeTests($n, $paths);
        ok("Test scaffold created at tests/{$n}");
        break;

    case 'make:repository':
        $n = requireName($nameArg);
        scaffoldRepository($n, $paths);
        ok("Repository created at src/Modules/{$n}/{$n}Repository.php");
        break;

    case 'make:service':
        $n = requireName($nameArg);
        scaffoldService($n, $paths);
        ok("Service created at src/Modules/{$n}/{$n}Service.php");
        break;

    case 'make:criteria':
        $n = requireName($nameArg);
        scaffoldCriteria($n, $paths);
        ok("Criteria created at src/Modules/{$n}/{$n}Criteria.php");
        break;

    case 'make:mapper':
        $n = requireName($nameArg);
        scaffoldMapper($n, $paths);
        ok("RowMapper created at src/Modules/{$n}/{$n}RowMapper.php");
        break;

    case 'make:dto':
        $n = requireName($nameArg);
        scaffoldDto($n, $paths);
        ok("DTO created at src/DTO/{$n}.php");
        break;

    case 'make:migration':
        $n = requireName($nameArg);
        $file = scaffoldMigration($n);
        ok("Migration created at {$file}");
        break;

    case 'make:view':
        $n = requireName($nameArg);
        $file = scaffoldView($n);
        ok("View template created at {$file}");
        break;

    case 'make:module-tests':
        $n = requireName($nameArg);
        scaffoldEpicTests($n, $paths);
        ok("Epic tests created at tests/{$n}");
        break;

    case 'make:audit-module':
        scaffoldAuditModule();
        ok('Audit module created at src/Audit/AuditTrail.php');
        break;

    case 'make:tenant-scope':
        scaffoldTenantScope();
        ok('Tenancy scope created at src/Tenancy/TenantScope.php');
        break;

    case 'make:replica-router':
        scaffoldReplicaRouter();
        ok('Read-replica router created at src/ReadReplica/Router.php');
        break;

    case 'make:demo-data':
        $n = requireName($nameArg);
        $count = isset($extraArgs[0]) ? max(1, (int)$extraArgs[0]) : 100;
        $file = scaffoldDemoData($n, $count);
        ok("Demo data created at {$file} ({$count} rows)");
        break;

    case 'make:howto':
        scaffoldHowToDocs();
        ok('How-to guides generated in docs/howto/');
        break;

    case 'make:all':
        $n = requireName($nameArg);
        scaffoldModule($n, $paths);
        scaffoldCriteria($n, $paths);
        scaffoldEpicTests($n, $paths);
        scaffoldMigration('create_' . strtolower($n));
        scaffoldView(strtolower($n) . '_view');
        ok("make:all completed for {$n}");
        break;

    default:
        fail("Unknown command: {$cmd}");
}

// ----------------------------------------------------------------------

function fail(string $message, int $code = 1): void
{
    fwrite(STDERR, $message . PHP_EOL);
    exit($code);
}

function ok(string $message): void
{
    fwrite(STDOUT, $message . PHP_EOL);
}

function requireName(string $value): string
{
    $n = normName($value);
    if ($n === '') {
        fail('Name required');
    }
    return $n;
}

function normName(string $value): string
{
    return preg_replace('~[^A-Za-z0-9]+~', '', $value);
}

function ensureDir(string $dir): void
{
    if (is_dir($dir)) {
        return;
    }
    if (!@mkdir($dir, 0777, true) && !is_dir($dir)) {
        throw new RuntimeException("Unable to create directory: {$dir}");
    }
}

function putFile(string $path, string $content): void
{
    ensureDir(dirname($path));
    if (file_exists($path)) {
        throw new RuntimeException("File exists: {$path}");
    }
    file_put_contents($path, $content);
}

function loadTemplate(string $relative): string
{
    $path = __DIR__ . '/../templates/' . ltrim($relative, '/');
    if (!file_exists($path)) {
        throw new RuntimeException("Missing template: {$relative}");
    }
    return file_get_contents($path);
}

function renderTemplate(string $relative, array $vars): string
{
    $tpl = loadTemplate($relative);
    foreach ($vars as $key => $value) {
        $tpl = str_replace('{{' . $key . '}}', $value, $tpl);
    }
    return $tpl;
}

function scaffoldModule(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'name'      => strtolower($name),
        'Namespace' => "App\\Modules\\{$name}",
        'Table'     => strtolower($name),
    ];
    $base = $paths['modules'] . '/' . $name;
    ensureDir($base);
    putFile("{$base}/Module.php", renderTemplate('module/Module.php.tmpl', $vars));
    putFile("{$base}/{$name}Repository.php", renderTemplate('module/Repository.php.tmpl', $vars));
    putFile("{$base}/{$name}Service.php", renderTemplate('module/Service.php.tmpl', $vars));
}

function scaffoldModuleSmokeTests(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'Namespace' => "App\\Modules\\{$name}",
    ];
    $dir = $paths['tests'] . '/' . $name;
    ensureDir($dir);
    putFile("{$dir}/{$name}ModuleSmokeTest.php", renderTemplate('tests/ModuleSmokeTest.php.tmpl', $vars));
}

function scaffoldRepository(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'name'      => strtolower($name),
        'Namespace' => "App\\Modules\\{$name}",
        'Table'     => strtolower($name),
    ];
    $base = $paths['modules'] . '/' . $name;
    ensureDir($base);
    putFile("{$base}/{$name}Repository.php", renderTemplate('module/Repository.php.tmpl', $vars));
}

function scaffoldService(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'name'      => strtolower($name),
        'Namespace' => "App\\Modules\\{$name}",
        'Table'     => strtolower($name),
    ];
    $base = $paths['modules'] . '/' . $name;
    ensureDir($base);
    putFile("{$base}/{$name}Service.php", renderTemplate('module/Service.php.tmpl', $vars));
}

function scaffoldCriteria(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'Namespace' => "App\\Modules\\{$name}",
    ];
    $base = $paths['modules'] . '/' . $name;
    ensureDir($base);
    putFile("{$base}/{$name}Criteria.php", renderTemplate('criteria/Criteria.php.tmpl', $vars));
}

function scaffoldMapper(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'Namespace' => "App\\Modules\\{$name}",
    ];
    $base = $paths['modules'] . '/' . $name;
    ensureDir($base);
    putFile("{$base}/{$name}RowMapper.php", renderTemplate('mapper/RowMapper.php.tmpl', $vars));
}

function scaffoldDto(string $name, array $paths): void
{
    $vars = [
        'Name'      => $name,
        'Namespace' => 'App\\DTO',
    ];
    $base = __DIR__ . '/../src/DTO';
    ensureDir($base);
    putFile("{$base}/{$name}.php", renderTemplate('dto/Dto.php.tmpl', $vars));
}

function scaffoldMigration(string $name): string
{
    $ts = date('Ymd_His');
    $dir = __DIR__ . '/../migrations';
    ensureDir($dir);
    $path = "{$dir}/{$ts}_{$name}.sql";
    putFile($path, loadTemplate('migration/migration.sql.tmpl'));
    return "migrations/{$ts}_{$name}.sql";
}

function scaffoldView(string $name): string
{
    $dir = __DIR__ . '/../views';
    ensureDir($dir);
    $path = "{$dir}/{$name}.sql";
    putFile($path, loadTemplate('views/View.sql.tmpl'));
    return "views/{$name}.sql";
}

function scaffoldEpicTests(string $name, array $paths): void
{
    $dir = $paths['tests'] . '/' . $name;
    ensureDir($dir);
    $vars = [
        'Name'      => $name,
        'Namespace' => "App\\Modules\\{$name}",
        'Table'     => strtolower($name),
    ];

    $templates = [
        'tests/epic/UpsertParityTest.php.tmpl'          => "{$dir}/{$name}UpsertParityTest.php",
        'tests/epic/KeysetPaginationTest.php.tmpl'      => "{$dir}/{$name}KeysetPaginationTest.php",
        'tests/epic/LockModesTest.php.tmpl'             => "{$dir}/{$name}LockModesTest.php",
        'tests/epic/RetryPolicyTest.php.tmpl'           => "{$dir}/{$name}RetryPolicyTest.php",
        'tests/epic/JsonParityTest.php.tmpl'            => "{$dir}/{$name}JsonParityTest.php",
        'tests/epic/LikeEscapingTest.php.tmpl'          => "{$dir}/{$name}LikeEscapingTest.php",
        'tests/epic/DeterministicOrderTest.php.tmpl'    => "{$dir}/{$name}DeterministicOrderTest.php",
        'tests/epic/DdlGuardViewDirectivesTest.php.tmpl'=> "{$dir}/{$name}DdlGuardViewDirectivesTest.php",
        'tests/epic/UtcEnforcementTest.php.tmpl'        => "{$dir}/{$name}UtcEnforcementTest.php",
        'tests/epic/QueryCacheMetricsTest.php.tmpl'     => "{$dir}/{$name}QueryCacheMetricsTest.php",
        'tests/epic/OperationResultTraceTest.php.tmpl'  => "{$dir}/{$name}OperationResultTraceTest.php",
        'tests/epic/ObservabilityTest.php.tmpl'         => "{$dir}/{$name}ObservabilityTest.php",
    ];

    foreach ($templates as $tpl => $out) {
        putFile($out, renderTemplate($tpl, $vars));
    }
}

function scaffoldAuditModule(): void
{
    $code = <<<'PHP'
<?php
declare(strict_types=1);

namespace BlackCat\Audit;

use BlackCat\Core\Database;

final class AuditTrail
{
    public function __construct(private Database $db) {}

    public function record(
        string $table,
        string $pk,
        string $operation,
        ?array $before = null,
        ?array $after = null,
        ?string $actor = null
    ): void {
        $this->db->exec(
            "INSERT INTO changes(table_name, pk, op, before_data, after_data, actor, ts)
             VALUES (:t, :pk, :op, :b, :a, :actor, CURRENT_TIMESTAMP)",
            [
                ':t'    => $table,
                ':pk'   => $pk,
                ':op'   => $operation,
                ':b'    => $before ? json_encode($before) : null,
                ':a'    => $after ? json_encode($after) : null,
                ':actor'=> $actor,
            ]
        );
    }
}
PHP;

    $base = __DIR__ . '/../src/Audit';
    putFile("{$base}/AuditTrail.php", $code);
}

function scaffoldTenantScope(): void
{
    $code = <<<'PHP'
<?php
declare(strict_types=1);

namespace BlackCat\Tenancy;

use BlackCat\Database\Support\Criteria;

final class TenantScope
{
    public function __construct(private int|string $tenantId) {}

    public function apply(Criteria $criteria, string $column = 'tenant_id'): void
    {
        $criteria->andWhere("{$column} = :__tenant")
            ->bind(':__tenant', $this->tenantId);
    }
}
PHP;

    $base = __DIR__ . '/../src/Tenancy';
    putFile("{$base}/TenantScope.php", $code);
}

function scaffoldReplicaRouter(): void
{
    $code = <<<'PHP'
<?php
declare(strict_types=1);

namespace BlackCat\ReadReplica;

use BlackCat\Core\Database;

final class Router
{
    public function __construct(private Database $primary, private ?Database $replica = null) {}

    public function pick(string $sql): Database
    {
        if ($this->replica && preg_match('~^\s*select\b~i', $sql)) {
            return $this->replica;
        }
        return $this->primary;
    }
}
PHP;

    $base = __DIR__ . '/../src/ReadReplica';
    putFile("{$base}/Router.php", $code);
}

function scaffoldDemoData(string $name, int $count): string
{
    $table = strtolower($name);
    $dir = __DIR__ . '/../seeds';
    ensureDir($dir);
    $path = "{$dir}/{$table}_demo.sql";
    if (file_exists($path)) {
        throw new RuntimeException("File exists: {$path}");
    }
    $rows = [];
    for ($i = 1; $i <= $count; $i++) {
        $rows[] = sprintf('(%d, %s)', $i, var_export("Demo {$i}", true));
    }
    $sql = sprintf(
        "INSERT INTO %s (id, name) VALUES\n%s;\n",
        $table,
        implode(",\n", $rows)
    );
    file_put_contents($path, $sql);
    return "seeds/{$table}_demo.sql";
}

function scaffoldHowToDocs(): void
{
    $src = __DIR__ . '/../templates/howto';
    $dst = __DIR__ . '/../docs/howto';
    ensureDir($dst);
    if (!is_dir($src)) {
        throw new RuntimeException('Missing templates/howto');
    }

    $files = array_values(
        array_filter(
            scandir($src) ?: [],
            static fn ($f) => str_ends_with((string)$f, '.md.tmpl')
        )
    );
    sort($files);

    $order = 1;
    foreach ($files as $file) {
        $content = file_get_contents("{$src}/{$file}");
        $prefix = str_pad((string)$order, 2, '0', STR_PAD_LEFT);
        $target = "{$dst}/{$prefix}_" . basename($file, '.tmpl');
        if (file_exists($target)) {
            throw new RuntimeException("File exists: {$target}");
        }
        file_put_contents($target, $content);
        $order++;
    }

    $readme = "# How-to Guides\n\nGenerated from templates. Order is prefixed with numbers.\n";
    file_put_contents("{$dst}/README.md", $readme);
}
