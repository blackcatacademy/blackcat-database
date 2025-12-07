<?php
// Auto-generated PHPStan stub for BlackCat\Core\Database

namespace BlackCat\Core;

use PHPUnit\Framework\MockObject\Builder\InvocationMocker;
use PHPUnit\Framework\MockObject\MockObject;

class DatabaseException extends \RuntimeException {}
class DeadlockException extends DatabaseException {}
class LockTimeoutException extends DatabaseException {}
class SerializationFailureException extends DatabaseException {}
class ConnectionGoneException extends DatabaseException {}

final class Database implements MockObject
{
    public static ?Database $instance = null;
    /**
     * @param mixed $invocationRule
     * @return InvocationMocker<Database>
     */
    public function expects(mixed $invocationRule): InvocationMocker {}
    /**
     * @param mixed $constraint
     * @return InvocationMocker<Database>
     */
    public function method(mixed $constraint): InvocationMocker {}
    public static function init(mixed ...$args): mixed {}
    public static function getInstance(mixed ...$args): Database {}
    public function getPdo(mixed ...$args): mixed {}
    public function hasReplica(mixed ...$args): mixed {}
    public function setLogger(mixed ...$args): mixed {}
    public function getLogger(mixed ...$args): mixed {}
    public static function isInitialized(mixed ...$args): mixed {}
    public function close(mixed ...$args): mixed {}
    public function dialect(mixed ...$args): mixed {}
    public function enableDebug(mixed ...$args): mixed {}
    public function enableDangerousSqlGuard(mixed ...$args): mixed {}
    public function enableAutoExplain(mixed ...$args): mixed {}
    public function enablePlaceholderGuard(mixed ...$args): mixed {}
    public function addObserver(mixed ...$args): mixed {}
    public function setLastQueriesMax(mixed ...$args): mixed {}
    public function getLastQueries(mixed ...$args): mixed {}
    public function enableNPlusOneDetector(mixed ...$args): mixed {}
    public function n1Stats(mixed ...$args): mixed {}
    public function exec(mixed ...$args): mixed {}
    public function execWithMeta(mixed ...$args): mixed {}
    public function fetchRowWithMeta(mixed ...$args): mixed {}
    public function fetchAllWithMeta(mixed ...$args): mixed {}
    public function fetchValueWithMeta(mixed ...$args): mixed {}
    public function existsWithMeta(mixed ...$args): mixed {}
    public function txWithMeta(mixed ...$args): mixed {}
    public function txRoWithMeta(mixed ...$args): mixed {}
    public function id(mixed ...$args): mixed {}
    public function serverVersion(mixed ...$args): mixed {}
    public function quote(mixed ...$args): mixed {}
    public function withStatement(mixed ...$args): mixed {}
    public function fetchOne(mixed ...$args): mixed {}
    public function iterateColumn(mixed ...$args): mixed {}
    public static function isTransientPdo(mixed ...$args): mixed {}
    public function withAdvisoryLock(mixed ...$args): mixed {}
    public function withStatementTimeout(mixed ...$args): mixed {}
    public function withIsolationLevel(mixed ...$args): mixed {}
    public function withIsolationLevelStrict(mixed ...$args): mixed {}
    public function explainPlan(mixed ...$args): mixed {}
    public function quoteIdent(mixed ...$args): mixed {}
    public function inClause(mixed ...$args): mixed {}
    public function transactionReadOnly(mixed ...$args): mixed {}
    public function paginateKeyset(mixed ...$args): mixed {}
    public function fetchWithRetry(mixed ...$args): mixed {}
    public function fetchAllWithRetry(mixed ...$args): mixed {}
    public function fetchValueWithRetry(mixed ...$args): mixed {}
    public function execWithRetry(mixed ...$args): mixed {}
    public function explainJson(mixed ...$args): mixed {}
    public function fetchPairsEx(mixed ...$args): mixed {}
    public function insertMany(mixed ...$args): mixed {}
    public function upsert(mixed ...$args): mixed {}
    public function replicaStatus(mixed ...$args): mixed {}
    public function getStickAfterWriteMs(mixed ...$args): mixed {}
    public function executeWithRetry(mixed ...$args): mixed {}
    public function executeOne(mixed ...$args): mixed {}
    public function driver(mixed ...$args): mixed {}
    public function isMysql(mixed ...$args): mixed {}
    public function isPg(mixed ...$args): mixed {}
    public function isMariaDb(mixed ...$args): mixed {}
    public function setReplicaHealthChecker(mixed ...$args): mixed {}
    public function setReplicaMaxLagMs(mixed ...$args): mixed {}
    public function setReplicaHealthCheckSec(mixed ...$args): mixed {}
    public function withPrimary(mixed ...$args): mixed {}
    public function withReplica(mixed ...$args): mixed {}
    public function waitForReplica(mixed ...$args): mixed {}
    public function requireSqlComment(mixed ...$args): mixed {}
    public function prepareAndRun(mixed ...$args): mixed {}
    public function query(mixed ...$args): mixed {}
    public function executeRaw(mixed ...$args): mixed {}
    public function transaction(mixed ...$args): mixed {}
    public function inTransaction(mixed ...$args): mixed {}
    public function fetch(mixed ...$args): mixed {}
    public function fetchAll(mixed ...$args): mixed {}
    public function iterate(mixed ...$args): mixed {}
    public function execute(mixed ...$args): mixed {}
    public function beginTransaction(mixed ...$args): mixed {}
    public function commit(mixed ...$args): mixed {}
    public function rollback(mixed ...$args): mixed {}
    public function lastInsertId(mixed ...$args): mixed {}
    public function setSlowQueryThresholdMs(mixed ...$args): mixed {}
    public function __wakeup(mixed ...$args): mixed {}
    public function ping(mixed ...$args): mixed {}
    public function fetchValue(mixed ...$args): mixed {}
    public function fetchColumn(mixed ...$args): mixed {}
    public function fetchPairs(mixed ...$args): mixed {}
    public function exists(mixed ...$args): mixed {}
    public function existsFast(mixed ...$args): mixed {}
    public function withEmulation(mixed ...$args): mixed {}
    public function paginate(mixed ...$args): mixed {}
    public function enableReadOnlyGuard(mixed ...$args): mixed {}
    public function isReadOnlyGuardEnabled(mixed ...$args): mixed {}
    public static function encodeCursor(mixed ...$args): mixed {}
    public static function decodeCursor(mixed ...$args): mixed {}
    public function configureCircuit(mixed ...$args): mixed {}
}
