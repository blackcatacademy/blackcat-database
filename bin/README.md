# bin

Utility CLI entry points that interact with a bootstrapped `BlackCat\Core\Database`
instance.

| Script | Purpose |
| --- | --- |
| `dbctl.php` | Multi-tool for pinging the DB, explaining queries, routing via primary/replica, waiting for replicas, or dumping the last executed queries. |
| `dbdoctor.php` | Prints a quick health snapshot (driver, server version, replication status, ping result). |
| `dbtrace.php` | Dumps in-flight query trace data captured by `Database::getLastQueries()`. |
| `outbox-worker.php` | Long-running worker that drains the application outbox table and dispatches payloads (stdout/webhook). |

All scripts expect your application bootstrap to call `Database::init(...)`
before execution (or to receive DSN credentials through environment variables
for the outbox worker).
