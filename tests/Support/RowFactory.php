<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

/**
 * Generates minimally valid rows:
 * - required (NOT NULL without default) FKs are resolved recursively (parents via Repository),
 * - other required columns receive deterministic dummy values (never null),
 * - ALWAYS fills columns of the FIRST available unique key (Definitions ∪ Schema) limited to allowed columns.
 */
final class RowFactory
{
    private const MAX_DEPTH = 8;
    // --- DEBUG helpers ---
    private static function isDebug(): bool
    {
        $v = $_ENV['BC_DEBUG'] ?? getenv('BC_DEBUG') ?? '';
        return $v === '1' || strcasecmp((string)$v, 'true') === 0;
    }

    private static function dbg(string $fmt, mixed ...$args): void
    {
        if (!self::isDebug()) return;
        error_log('[RowFactory] ' . vsprintf($fmt, $args));
    }

    /**
     * If a MySQL/MariaDB table uses CHECK(json_valid(col)),
     * ensure the generated sample stores a valid JSON string in those columns.
     */
    private static function coerceJsonForMysql(string $table, array &$row): void
    {
        if (DbHarness::isPg()) return; // PG does not need this

        $must = DbHarness::jsonValidatedColumns($table);
        if (!$must) {
            // Also treat native JSON columns as requiring valid JSON.
            $must = [];
            foreach (DbHarness::columns($table) as $c) {
                $type = strtolower((string)($c['type'] ?? ''));
                $full = strtolower((string)($c['full_type'] ?? ''));
                if ($type === 'json' || str_contains($full, 'json')) {
                    $must[] = (string)$c['name'];
                }
            }
        }
        if (!$must) return;
        $mustJson = array_fill_keys($must, true);

        // Map payload keys (case-insensitive)
        $mapRow = [];
        foreach (array_keys($row) as $k) $mapRow[strtolower($k)] = $k;

        foreach (array_keys($mustJson) as $lc) {
            $k = $mapRow[$lc] ?? $lc;            // keep original casing or fall back to lowercase
            $v = $row[$k] ?? null;

            if (is_array($v) || is_object($v)) {
                $row[$k] = json_encode($v, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
                continue;
            }
            $s  = is_string($v) ? $v : '';
            $ok = ($s !== '' && json_decode($s, true) !== null);
            if (!$ok) {
                $row[$k] = '{}';                  // simple valid JSON
            }
        }
    }

    /**
     * @param array $overrides optional preset values (e.g., ['user_id'=>123])
     * @return array{0:?array,1:array<int,string>,2:array<int,string>}
     */
    public static function makeSample(string $table, array $overrides = []): array
    {
        $cols = DbHarness::columns($table);
        self::dbg('makeSample(%s): start', $table);
                // Hard gate - if DbHarness marks the table as "unsafe", skip it entirely.
        if (!DbHarness::isInsertSafe($table)) {
            self::dbg('makeSample(%s): unsafe by DbHarness::safetyProfile -> skip', $table);
            return [null, [], []];
        }
        if (!$cols) {
            self::dbg('makeSample(%s): no columns from information_schema -> skip', $table);
            return [null, [], []];
        }
        $pk = DbHarness::primaryKey($table);
        $pkMeta = null; foreach ($cols as $c) { if (strcasecmp((string)$c['name'],$pk)===0) { $pkMeta=$c; break; } }
        $pkIsIdentity = (bool)($pkMeta['is_identity'] ?? false);
        self::dbg('makeSample(%s): pk=%s identity=%s', $table, $pk ?? '(?)', $pkIsIdentity ? 'yes' : 'no');
        // 1) Safe mode (handles required FKs)
        try {
            [$row, $upd, $uk] = self::buildRow($table, $overrides, 0, []);
            if ($row !== null) {
                $byName = self::indexByName($cols);
                $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row) ?: $uk;
                // trim to allowed columns (repo filter) - case-insensitive just like the fallback
                $allowed     = DbHarness::allowedColumns($table);
                $allowedSet  = array_fill_keys($allowed, true);
                $allowedSetLc= array_fill_keys(array_map('strtolower', $allowed), true);
                $beforeKeys = implode(',', array_keys($row));
                self::dbg('makeSample(%s): safe candidate keys before whitelist=[%s]', $table, $beforeKeys);

                $row = array_filter(
                    $row,
                    fn($v, $k) => isset($allowedSet[$k]) || isset($allowedSetLc[strtolower($k)]),
                    ARRAY_FILTER_USE_BOTH
                );

                $afterKeys = implode(',', array_keys($row));
                self::dbg('makeSample(%s): after whitelist keys=[%s]', $table, $afterKeys);

                if (empty($row) && !empty($upd)) {
                    $colsByName = self::indexByName($cols);
                    $first = $upd[0];
                    $meta  = $colsByName[strtolower($first)] ?? ['name'=>$first,'type'=>'text'];
                    self::dbg('makeSample(%s): payload empty after whitelist, seeding first updatable=%s', $table, $first);
                    $row[$first] = self::dummyValue($meta);
                    $uk = self::ensureFirstResolvedUniqueFilled($table, $colsByName, $row) ?: $uk;
                }
                self::dbg('makeSample(%s): SAFE mode success (keys=[%s])', $table, implode(',', array_keys($row)));
                self::coerceJsonForMysql($table, $row);
                return [$row, $upd, $uk];
            }
            else {
                self::dbg('makeSample(%s): SAFE mode returned null -> fallback', $table);
            }
        } catch (\Throwable $ex) {
            self::dbg('makeSample(%s): SAFE mode exception: %s', $table, $ex->getMessage());
        }

        // 2) Fallback – jen ne-FK required + doplnit unique key
        $fkCols = array_map('strtolower', DbHarness::foreignKeyColumns($table));
        $fkSet  = array_fill_keys($fkCols, true);
        $allowed     = DbHarness::allowedColumns($table);
        $allowedSet  = array_fill_keys($allowed, true);
        $allowedSetLc= array_fill_keys(array_map('strtolower', $allowed), true);
        $enumMap = DbHarness::enumChoices($table);

        // [SAFETY GATE] If the table has enum-like CHECK columns but the repository cannot write them,
        // the table cannot be safely inserted through the repository -> skip it.
        $colsByName = self::indexByName($cols);
        $requiredByCheck = DbHarness::requiredByCheck($table); // [lower(col)=>true]
        foreach ($enumMap as $col => $_) {
            $lc = strtolower($col);
            $notAllowed = !isset($allowedSet[$col]) && !isset($allowedSetLc[$lc]);
            $isRequired = isset($requiredByCheck[$lc]) || isset($requiredByCheck[$col]);
            if ($notAllowed && $isRequired) {
                $meta = $colsByName[$lc] ?? null;
                $hasNonNullDefault = $meta && array_key_exists('col_default', $meta) && $meta['col_default'] !== null;
                if (!$hasNonNullDefault) {
                    self::dbg("makeSample(%s): GATE#1 enum-like required column '%s' not allowed by repo and no DEFAULT -> skip", $table, $col);
                    return [null, [], []];
                }
            }
        }

        // [SAFETY GATE #2] If the repository forbids typical enum-like columns and they lack a non-null DEFAULT,
        // the table is not "safe" for generating a sample row via the repository.
        foreach (['type','status','state','level','mode','channel','event'] as $sus) {
            if (!isset($colsByName[$sus])) continue;
            if (isset($allowedSet[$sus]) || isset($allowedSetLc[$sus])) continue;
            $isRequired = isset($requiredByCheck[$sus]) || isset($requiredByCheck[strtolower($sus)]);
            if (!$isRequired) continue; // not required -> do not exclude the table
            $meta = $colsByName[$sus];
            $hasNonNullDefault = array_key_exists('col_default', $meta) && $meta['col_default'] !== null;
            if (!$hasNonNullDefault) {
                self::dbg("makeSample(%s): GATE#2 required '%s' not allowed by repo and no DEFAULT -> skip", $table, $sus);
                return [null, [], []];
            }
        }
        $row = []; $updatable = [];
        foreach ($cols as $c) {
            $name = (string)$c['name'];
            $nameLc = strtolower($name);
            if (!empty($c['is_identity'])) continue;
            // skip PK only when it is identity; keep natural PK for filling
            if ($pkIsIdentity && strcasecmp($name, $pk) === 0) continue;
            
            if (self::isRequired($c) && !isset($fkSet[$nameLc]) && (isset($allowedSet[$name]) || isset($allowedSetLc[$nameLc]))) {
                if (array_key_exists($name, $overrides)) {
                    $row[$name] = self::coerceEnumIfNeeded($enumMap, $name, $overrides[$name]);
                } else {
                    $choices = self::enumChoicesFor($enumMap, $name);
                    if ($choices) {
                        $row[$name] = $choices[0];
                    } else {
                        $row[$name] = self::dummyValue($c);
                    }
                }
            }

            $isDatetime = (bool)preg_match('/(date|time)/i', (string)($c['type'] ?? ''));
            $isEnum = (self::enumChoicesFor($enumMap, $name) !== null)
                   || preg_match('/^enum\(/i', (string)($c['full_type'] ?? ''));
            if (!preg_match('/^(id|'.preg_quote(DbHarness::primaryKey($table),'/').'|created_at|updated_at|deleted_at)$/i', $name)
                && !$isDatetime && !$isEnum && strcasecmp($name, 'version') !== 0
                && (isset($allowedSet[$name]) || isset($allowedSetLc[$nameLc]))) {
                $updatable[] = $name;
            }
        }

        $byName = self::indexByName($cols);
        self::dbg('makeSample(%s): FALLBACK candidate requiredKeys=[%s], updatable=[%s]',
            $table,
            implode(',', array_keys($row)),
            implode(',', $updatable)
        );
        $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row);
        // [ADD] fill missing enum-like columns (PG CHECK may require non-null)
        $rowLc = array_change_key_case($row, CASE_LOWER);
        foreach ($enumMap as $col => $choices) {
            if (!isset($allowedSet[$col]) && !isset($allowedSetLc[strtolower($col)])) continue;
            if (!array_key_exists($col, $row) && !isset($rowLc[strtolower($col)]) && $choices) {
                $row[$col] = (string)$choices[0];
            }
        }

        // [ADD] coerce invalid enum-like values when necessary
        foreach (array_keys($row) as $col) {
            $row[$col] = self::coerceEnumIfNeeded($enumMap, $col, $row[$col]);
        }
        // Case-insensitive filtr na allowed columns
        $beforeKeys = implode(',', array_keys($row));
        $row = array_filter(
            $row,
            fn($v, $k) => isset($allowedSet[$k]) || isset($allowedSetLc[strtolower($k)]),
            ARRAY_FILTER_USE_BOTH
        );
        self::dbg('makeSample(%s): FALLBACK after whitelist keys=[%s]', $table, implode(',', array_keys($row)));
        // Same safeguard also applies in the fallback
        if (empty($row)) {
            if (!empty($updatable)) {
                $colsByName = self::indexByName($cols);
                $first = $updatable[0];
                $meta  = $colsByName[strtolower($first)] ?? ['name'=>$first,'type'=>'text'];
                self::dbg('makeSample(%s): FALLBACK seeding first updatable=%s', $table, $first);
                $row[$first] = self::dummyValue($meta);
                $uk = self::ensureFirstResolvedUniqueFilled($table, $colsByName, $row) ?? $uk ?? [];
                self::dbg('makeSample(%s): FALLBACK after seeding, keys=[%s]', $table, implode(',', array_keys($row)));
            } else {
                self::dbg('makeSample(%s): FALLBACK empty payload and no updatable columns -> skip', $table);
                return [null, [], []];
            }
        }
        self::dbg('makeSample(%s): FALLBACK success (keys=[%s])', $table, implode(',', array_keys($row)));
        self::coerceJsonForMysql($table, $row);
        return [$row, array_values(array_unique($updatable)), $uk ?? []];
    }

    /** Recursive construction of an insertable row including required FK parents. */
    private static function buildRow(string $table, array $overrides, int $depth, array $stack): array
    {
        if ($depth > self::MAX_DEPTH) {
            self::dbg('buildRow(%s): hit MAX_DEPTH=%d stack=%s', $table, self::MAX_DEPTH, implode(' > ', $stack));
            return [null, [], []];
        }
        if (in_array($table, $stack, true)) {
            self::dbg('buildRow(%s): cycle detected stack=%s', $table, implode(' > ', $stack));
            return [null, [], []];
        }

        $cols = DbHarness::columns($table);
        if (!$cols) {
            self::dbg('buildRow(%s): no columns -> abort', $table);
            return [null, [], []];
        }

        $byName = self::indexByName($cols);
        $allowed     = DbHarness::allowedColumns($table);
        $allowedSet  = array_fill_keys($allowed, true);
        $allowedSetLc= array_fill_keys(array_map('strtolower', $allowed), true);
        $enumMap = DbHarness::enumChoices($table);  // PG CHECK/enum map (col => [allowed,...])
        $row = [];
        $pk = DbHarness::primaryKey($table);
        $pkIsIdentity = (bool)(($byName[strtolower($pk)]['is_identity'] ?? false));

        // 1) required single-column FKs. Multi-column required FKs -> fail instead of guessing.
        $fks = DbHarness::foreignKeysDetailed($table);
        foreach ($fks as $fk) {
            $local   = $fk['cols'];
            $refTIn  = (string)$fk['ref_table'];
            // Logical name to work with the repository:
            $refT    = DbHarness::logicalFromPhysical($refTIn);
            $refCols = $fk['ref_cols'];


            if (count($local) !== 1 || count($refCols) !== 1) {
                $allRequired = true;
                foreach ($local as $lc) {
                    $meta = $byName[strtolower($lc)] ?? null;
                    if (!$meta || !self::isRequired($meta)) { $allRequired = false; break; }
                }
                if ($allRequired) {
                    self::dbg('buildRow(%s): REQUIRED multi-column FK %s -> skip (won’t guess composites)', $table, $fk['name'] ?? '(?)');
                    return [null, [], []];
                }
                continue;
            }

            $lc = $local[0];
            $meta = $byName[strtolower($lc)] ?? null;
            if (!$meta) continue;

            // override pro FK sloupec:
            if (array_key_exists($lc, $overrides)) {
                $useOverride = false;
                if (self::isRequired($meta)) {
                    // verify the parent actually exists (query the PHYSICAL table)
                    $refPk   = DbHarness::primaryKey($refT);
                    $refPhys = DbHarness::physicalName($refT);
                    $db      = \BlackCat\Core\Database::getInstance();

                    $exists = $db->fetchOne(
                        "SELECT 1 FROM {$db->quoteIdent($refPhys)} WHERE {$db->quoteIdent($refPk)} = :id LIMIT 1",
                        [':id' => $overrides[$lc]]
                    );
                    $useOverride = ($exists !== null);
                } else {
                    $useOverride = true;
                }

                if ($useOverride) {
                    if (isset($allowedSet[$lc]) || isset($allowedSetLc[strtolower($lc)])) {
                        $row[$lc] = $overrides[$lc];
                    }
                } else {
                    // create the parent
                    [$parentRow] = self::buildRow($refT, [], $depth + 1, array_merge($stack, [$table]));
                    if ($parentRow === null) return [null, [], []];

                    if (method_exists(DbHarness::class, 'coerceForPg')) {
                        $parentRow = DbHarness::coerceForPg($refT, $parentRow);
                    }
                    $ins = DbHarness::insertAndReturnId($refT, $parentRow);
                    if ($ins === null) {
                        self::dbg('buildRow(%s): parent insert for %s failed (FK=%s)', $table, $refT, $lc ?? '(?)');
                        return [null, [], []];
                    }
                    if (isset($allowedSet[$lc]) || isset($allowedSetLc[strtolower($lc)])) {
                        $row[$lc] = $ins['pk'];
                    }
                }
                continue;
            }

            // without overrides: if the FK is required, create the parent
            if (self::isRequired($meta)) {
                [$parentRow] = self::buildRow($refT, [], $depth + 1, array_merge($stack, [$table]));
                if ($parentRow === null) return [null, [], []];

                if (method_exists(DbHarness::class, 'coerceForPg')) {
                    $parentRow = DbHarness::coerceForPg($refT, $parentRow);
                }
                $ins = DbHarness::insertAndReturnId($refT, $parentRow);
                if ($ins === null) {
                    self::dbg('buildRow(%s): parent insert for %s failed (FK=%s)', $table, $refT, $lc ?? '(?)');
                    return [null, [], []];
                }
                if (isset($allowedSet[$lc]) || isset($allowedSetLc[strtolower($lc)])) {
                    $row[$lc] = $ins['pk'];
                }
            }
        }
        // 2) fill remaining required non-FK columns (excluding identity)
        for ($i=0, $n=count($cols); $i<$n; $i++) {
            $c = $cols[$i];
            $name = (string)$c['name'];
            if (!self::isRequired($c)) continue;
            if (!empty($c['is_identity'])) continue;
            if (!empty($c['is_generated'])) continue;
            if ($pkIsIdentity && strcasecmp($name, $pk) === 0) continue;
            if (array_key_exists($name, $row)) continue;
            if (!isset($allowedSet[$name]) && !isset($allowedSetLc[strtolower($name)])) continue;

            if (array_key_exists($name, $overrides)) {
                $row[$name] = self::coerceEnumIfNeeded($enumMap, $name, $overrides[$name]);
            } else {
                $choices = self::enumChoicesFor($enumMap, $name);
                if ($choices) {
                    $row[$name] = $choices[0];
                } else {
                    $row[$name] = self::dummyValue($c);
                }
            }
        }

        // 3) updatable - skip PK/ID/timestamps/datetime/enum/version
        $upd = [];
        foreach ($cols as $c) {
            $n = (string)$c['name'];
            if (!empty($c['is_generated'])) continue;
            $isDatetime = (bool)preg_match('/(date|time)/i', (string)($c['type'] ?? ''));
            $isEnum = (self::enumChoicesFor($enumMap, $n) !== null)
                   || preg_match('/^enum\(/i', (string)($c['full_type'] ?? ''));
            if ($isDatetime) continue;
            if (!isset($allowedSet[$n]) && !isset($allowedSetLc[strtolower($n)])) continue;
            if (preg_match('/^('.preg_quote($pk,'/').'|id|created_at|updated_at|deleted_at)$/i', $n)) continue;
            if (strcasecmp($n, 'version') === 0) continue;
            if ($isEnum) continue;
            $upd[] = $n;
        }

        // 4) fill the FIRST resolved unique key
        $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row) ?? [];

        // [ADD] 5) ensure valid values for enum-like columns (PG CHECK may require non-null + exact values)
        $rowLc = array_change_key_case($row, CASE_LOWER);
        foreach ($enumMap as $col => $choices) {
            if (!isset($allowedSet[$col]) && !isset($allowedSetLc[strtolower($col)])) continue;
            if (!array_key_exists($col, $row) && !isset($rowLc[strtolower($col)])) {
                // missing -> set the first allowed value
                if ($choices) { $row[$col] = (string)$choices[0]; }
            } else {
                // already filled -> coerce to an allowed value if needed
                $row[$col] = self::coerceEnumIfNeeded($enumMap, $col, $row[$col]);
            }
        }
        self::dbg('buildRow(%s): success; payloadKeys=[%s]; updatable=[%s]; uk=[%s]',
            $table,
            implode(',', array_keys($row)),
            implode(',', array_unique($upd)),
            implode(',', $uk ?? [])
        );
        return [$row, array_values(array_unique($upd)), $uk];
    }

    /** Return true when the column is NOT NULL without a default. */
    private static function isRequired(array $col): bool
    {
        $notNull = !(bool)($col['nullable'] ?? true);
        $hasDef  = array_key_exists('col_default', $col) && $col['col_default'] !== null;
        return $notNull && !$hasDef;
    }

    /** index [lower(name) => meta] */
    private static function indexByName(array $cols): array
    {
        $by = [];
        foreach ($cols as $c) $by[strtolower((string)$c['name'])] = $c;
        return $by;
    }

    /**
     * Fill $row with all columns of the FIRST resolved unique key (Definitions ∪ Schema),
     * that is a subset of allowedColumns. Returns the list of columns or null.
     */
    private static function ensureFirstResolvedUniqueFilled(string $table, array $colsByName, array &$row): ?array
    {
        $allowed      = DbHarness::allowedColumns($table);
        $allowedSet   = array_fill_keys($allowed, true);
        $allowedSetLc = array_fill_keys(array_map('strtolower', $allowed), true);
        $pk           = DbHarness::primaryKey($table);
        $pkIsIdentity = (bool)(($colsByName[strtolower($pk)]['is_identity'] ?? false));

        // FK set (local column names, lowercased)
        $fkSet = [];
        foreach (DbHarness::foreignKeysDetailed($table) as $fk) {
            foreach ($fk['cols'] as $lc) { $fkSet[strtolower($lc)] = true; }
        }

        $rowLc = array_change_key_case($row, CASE_LOWER);

        foreach (DbHarness::resolvedUniqueKeys($table) as $uk) {
            if (!$uk) continue;

            $ukStr = implode(',', (array)$uk);
            self::dbg('ensureUK(%s): considering UK=[%s]', $table, $ukStr);

            // skip [PK], pokud je identity
            if ($pkIsIdentity && count($uk) === 1 && strcasecmp($uk[0], $pk) === 0) {
                self::dbg('ensureUK(%s): skip identity PK', $table);
                continue;
            }

            // must be a subset of allowed
            $subset = true; $offender = null;
            foreach ($uk as $c) {
                if (!isset($allowedSet[$c]) && !isset($allowedSetLc[strtolower($c)])) {
                    $subset = false; $offender = $c; break;
                }
            }
            if (!$subset) {
                self::dbg("ensureUK(%s): skip UK=[%s] – column '%s' not allowed by repo", $table, $ukStr, $offender ?? '?');
                continue;
            }

            // if the unique key contains an FK column not yet in $row -> skip it
            $hasUnfilledFk = false; $fkOff = null;
            foreach ($uk as $c) {
                $lc = strtolower($c);
                if (isset($fkSet[$lc]) && !array_key_exists($c, $row) && !isset($rowLc[$lc])) {
                    $hasUnfilledFk = true; $fkOff = $c; break;
                }
            }
            if ($hasUnfilledFk) {
                self::dbg("ensureUK(%s): skip UK=[%s] – unfilled FK column '%s'", $table, $ukStr, $fkOff ?? '?');
                continue;
            }

            // fill missing non-FK unique key columns (respecting the casing stored in $row)
            $rowLc = array_change_key_case($row, CASE_LOWER);
            $filledNow = [];
            foreach ($uk as $c) {
                if (!array_key_exists($c, $row) && !isset($rowLc[strtolower($c)])) {
                    $meta = $colsByName[strtolower($c)] ?? ['name'=>$c,'type'=>'text','full_type'=>'text','nullable'=>true,'is_identity'=>false];
                    $row[$c] = self::dummyValue($meta);
                    $filledNow[] = $c;
                }
            }

            self::dbg('ensureUK(%s): picked UK=[%s]; filled=[%s]', $table, $ukStr, implode(',', $filledNow));
            return $uk;
        }

        self::dbg('ensureUK(%s): no suitable UK found', $table);
        return null;
    }

    /**
     * Deterministic reasonable value per type (never null).
     * - For *_id chooses the appropriate type (int/string/uuid).
     */
    public static function dummyValue(array $c): mixed
    {
        $name   = trim((string)($c['name'] ?? ''));
        $nameLc = strtolower($name);
        $type   = strtolower(trim((string)($c['type'] ?? '')));
        $full   = strtolower(trim((string)($c['full_type'] ?? $type)));
        static $seq = 1;

        // *_id / id - always non-null and type-safe
        if (preg_match('/(^id$|_id$)/i', $nameLc)) {
            if (str_contains($type, 'uuid')) {
                $n = str_pad((string)$seq++, 12, '0', STR_PAD_LEFT);
                return "00000000-0000-4000-8000-" . substr($n, -12);
            }
            if (preg_match('/(char|text|name|varchar)/', $type)) return '1';
            return 1;
        }

        // name-based datetime
        if (preg_match('/(^|_)(created|updated|deleted|processed|verified|expires|expiry|valid|paid|refunded|locked|scheduled|published|completed|available|sent|received)(_|$)at$/', $nameLc)
            || preg_match('/(_on|_time|_date|^date_|^time_|_until|_expiry|_expires)$/', $nameLc)) {
            return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }

        // ENUM/SET
        if (preg_match('/^(enum|set)\((.+)\)$/i', $full, $m)) {
            $raw = $m[2];
            if (preg_match_all("/'((?:\\\\'|[^'])*)'/", $raw, $mm)) {
                $vals = array_map(fn($s)=>str_replace("\\'", "'", $s), $mm[1]);
                if ($vals) return $vals[0];
            }
        }

        // BINARY
        if (preg_match('/\b(var)?binary\((\d+)\)/i', $full, $m)) {
            $n = (int)$m[2]; return random_bytes(max(1, $n));
        }
        if (preg_match('/\bblob\b/', $type)) { return random_bytes(16); }

        // Naming heuristics
        if ($name === 'currency') return 'USD';
        if ($name === 'iso2')     return 'US';
        if ($name === 'iso3')     return 'USA';
        if (preg_match('/slug$/', $name)) { return 't-'.bin2hex(random_bytes(6)).'-'.$seq++; }

        // CHAR/VARCHAR(n)
        if (preg_match('/\b(char|varchar)\((\d+)\)/i', $full, $m)) {
            $n = (int)$m[2];
            if (preg_match('/(hash|token|signature)$/', $nameLc)) {
                $hex = bin2hex(random_bytes(intdiv($n + 1, 2)));
                return substr($hex, 0, $n);
            }
            return substr('t-'.$seq++, 0, max(1, $n));
        }

        // hashes/tokens without a declared size
        if (preg_match('/(hash|token|signature)$/', $nameLc)) {
            $target = match ($nameLc) {
                'password_hash' => 60,
                'ip_hash'       => 32,
                default         => 32,
            };
            $hex = bin2hex(random_bytes(intdiv($target + 1, 2)));
            return substr($hex, 0, $target);
        }

        if (preg_match('/^(email|email_address)$/', $name)) {
            return 'john.doe.'.$seq++.'@example.test';
        }
        if (preg_match('/(_ms|_sec|_count|_qty|_attempts|_number|_total|_amount)$/', $name)) {
            return '1'; // DECIMAL/NUMERIC safely returned as string
        }
        if (preg_match('/^(status|state)$/', $name)) {
            return 'new';
        }

        // Type-specific heuristics
        if (str_contains($type, 'json')) {
            return '{}';
        }
        if (preg_match('/(date|time)/', $type)) {
            return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }
        if (preg_match('/(int|serial|year)/', $type)) {
            return 1;
        }
        if (preg_match('/(decimal|numeric|double|float|real)/', $type)) {
            return '1.00';
        }
        if (preg_match('/(char|text|uuid|name)/', $type)) {
            return 't-'.$seq++;
        }
        if (preg_match('/(bool|tinyint\(1\))/', $type)) {
            return 1;
        }

        return 'x'; // nikdy null
    }

    /** If a column has a CHECK-enum and the value is not allowed, return the first allowed value; otherwise keep the original. */
    private static function coerceEnumIfNeeded(array $enumMap, string $col, mixed $val): mixed
    {
        $choices = self::enumChoicesFor($enumMap, $col);
        if ($choices) {
            // compare strictly as string (PG returns text)
            $allowed = array_map('strval', $choices);
            $asStr = is_scalar($val) ? (string)$val : '';
            if (!in_array($asStr, $allowed, true)) {
                return $allowed[0];
            }
        }
        return $val;
    }

    private static function enumChoicesFor(array $map, string $name): ?array {
        return $map[$name] ?? $map[strtolower($name)] ?? null;
    }
    /**
     * Optional helper: create a sample and insert it into the DB, returning the PK.
     * @return array{row:array, pkCol:string, pk:mixed}
     */
    public static function insertSample(string $table, array $overrides = []): array
    {
        [$row] = self::makeSample($table, $overrides);
        if ($row === null) {
            self::dbg('insertSample(%s): makeSample returned null -> throw', $table);
            throw new \RuntimeException("Cannot construct safe sample row for '$table'");
        }
        if (method_exists(DbHarness::class, 'coerceForPg')) {
            $row = DbHarness::coerceForPg($table, $row);
        }
        $ins = DbHarness::insertAndReturnId($table, $row);
        if ($ins === null) {
            throw new \RuntimeException("Insert succeeded but PK could not be determined for '$table'");
        }
        return ['row' => $row, 'pkCol' => $ins['pkCol'], 'pk' => $ins['pk']];
    }
}
