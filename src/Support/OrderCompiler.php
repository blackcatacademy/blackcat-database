<?php
declare(strict_types=1);

namespace BlackCat\Database\Support;

/**
 * OrderCompiler – univerzální ORDER BY pro MySQL/MariaDB, PostgreSQL, SQLite, SQL Server.
 *
 * DSL: "created_at DESC NULLS LAST, id DESC"
 *  - směr: ASC|DESC (default ASC)
 *  - NULLS FIRST|LAST (Postgres nativně; ostatní fallback přes CASE)
 */
final class OrderCompiler
{
    public static function compile(string|array|null $order, string $dialect, ?string $alias = null, ?string $tiePk = null, bool $stable = false): string
    {
        $items = self::parseItems($order);
        if (!$items) {
            if ($stable && $tiePk) {
                $pkExpr = self::maybePrefix($tiePk, $alias);
                return " ORDER BY {$pkExpr} ASC";
            }
            return '';
        }

        $isPg  = self::isPostgres($dialect);
        $parts = [];
        $hasPk = false;

        foreach ($items as $it) {
            $expr  = self::maybePrefix($it['expr'], $alias);
            $dir   = $it['dir'] ?? 'ASC';
            $nulls = $it['nulls'] ?? 'AUTO';

            if ($tiePk && self::exprEquals($it['expr'], $tiePk, $alias)) {
                $hasPk = true;
            }

            if ($nulls !== 'AUTO') {
                if ($isPg) {
                    $parts[] = "{$expr} {$dir} NULLS {$nulls}";
                } else {
                    if ($nulls === 'LAST') {
                        $parts[] = "CASE WHEN {$expr} IS NULL THEN 1 ELSE 0 END ASC";
                    } else {
                        $parts[] = "CASE WHEN {$expr} IS NULL THEN 0 ELSE 1 END ASC";
                    }
                    $parts[] = "{$expr} {$dir}";
                }
            } else {
                $parts[] = "{$expr} {$dir}";
            }
        }

        if ($stable && $tiePk && !$hasPk) {
            $dirForPk = self::guessTieBreakerDir($items) ?? 'ASC';
            $pkExpr   = self::maybePrefix($tiePk, $alias);
            $parts[]  = "{$pkExpr} {$dirForPk}";
        }

        return ' ORDER BY ' . implode(', ', $parts);
    }

    public static function parseItems(string|array|null $order): array
    {
        if (is_array($order)) {
            $out = [];
            foreach ($order as $it) {
                if (!is_array($it) || empty($it['expr'])) continue;
                $out[] = [
                    'expr'  => trim($it['expr']),
                    'dir'   => isset($it['dir'])   ? strtoupper(trim($it['dir']))   : 'ASC',
                    'nulls' => isset($it['nulls']) ? strtoupper(trim($it['nulls'])) : 'AUTO',
                ];
            }
            return $out;
        }

        $s = trim((string)$order);
        if ($s === '') return [];

        $pieces = self::splitTopLevelCommas($s);
        $out    = [];

        foreach ($pieces as $raw) {
            $item = trim($raw);
            if ($item === '') continue;

            $dir = 'ASC';
            if (preg_match('/\b(ASC|DESC)\b/i', $item, $m)) {
                $dir = strtoupper($m[1]);
            }

            $nulls = 'AUTO';
            if (preg_match('/\bNULLS\s+(FIRST|LAST)\b/i', $item, $nm)) {
                $nulls = strtoupper($nm[1]);
            }

            $expr = preg_replace([
                '/\bNULLS\s+(FIRST|LAST)\b/i',
                '/\b(ASC|DESC)\b/i'
            ], '', $item);
            $expr = trim(preg_replace('/\s+/', ' ', (string)$expr));

            if ($expr !== '') {
                $out[] = ['expr' => $expr, 'dir' => $dir, 'nulls' => $nulls];
            }
        }
        return $out;
    }

    private static function guessTieBreakerDir(array $items): ?string
    {
        if (!$items) return null;
        $last = end($items);
        if (!is_array($last)) return null;
        return ($last['dir'] ?? 'ASC') === 'DESC' ? 'DESC' : 'ASC';
    }

    private static function maybePrefix(string $expr, ?string $alias): string
    {
        if (!$alias) return $expr;
        if (preg_match('/^[a-z_][a-z0-9_]*$/i', $expr)) {
            return "{$alias}.{$expr}";
        }
        return $expr;
    }

    private static function exprEquals(string $expr, string $pk, ?string $alias): bool
    {
        $expr = trim($expr);
        if (strcasecmp($expr, $pk) === 0) return true;
        if ($alias && strcasecmp($expr, "{$alias}.{$pk}") === 0) return true;
        return false;
    }

    private static function isPostgres(string $dialect): bool
    {
        $d = strtolower($dialect);
        return $d === 'pgsql' || $d === 'postgres' || $d === 'postgresql';
    }

    private static function splitTopLevelCommas(string $s): array
    {
        $out = [];
        $buf = '';
        $depth = 0;
        $q = null;
        $len = strlen($s);

        for ($i = 0; $i < $len; $i++) {
            $ch = $s[$i];
            $nx = $i + 1 < $len ? $s[$i + 1] : null;

            if ($q !== null) {
                $buf .= $ch;
                if ($q === "'" && $ch === "'" && $nx === "'") { $buf .= $nx; $i++; continue; }
                if ($q === '"' && $ch === '"' && $nx === '"') { $buf .= $nx; $i++; continue; }
                if ($q === '`' && $ch === '`' && $nx === '`') { $buf .= $nx; $i++; continue; }
                if ($q === '[' && $ch === ']') { $q = null; continue; }
                if (in_array($q, ["'", '"', '`'], true) && $ch === $q) { $q = null; }
                continue;
            }

            if ($ch === "'" || $ch === '"' || $ch === '`' || $ch === '[') { $q = $ch; $buf .= $ch; continue; }
            if ($ch === '(') { $depth++; $buf .= $ch; continue; }
            if ($ch === ')') { $depth = max(0, $depth - 1); $buf .= $ch; continue; }
            if ($ch === ',' && $depth === 0) { $out[] = $buf; $buf = ''; continue; }

            $buf .= $ch;
        }

        if ($buf !== '') $out[] = $buf;
        return $out;
    }
}
