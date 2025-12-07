<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Packages;

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\DataProvider;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

final class MapperRoundTripDynamicTest extends TestCase
{
    public static function dtoMappersProvider(): array
    {
        $out = [];
        $root = realpath(__DIR__ . '/../../../packages');
        if ($root === false) {
            return [];
        }
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if ($f->isFile() && preg_match('~/packages/([^/]+)/src/Mapper/([A-Za-z0-9_]+)Mapper\.php$~', $f->getPathname(), $m)) {
                $pkg = $m[1];
                $parts = preg_split('/[_-]/',$pkg) ?: [];
                $mapperClass = "BlackCat\\Database\\Packages\\".implode('', array_map('ucfirst', $parts))."\\Mapper\\{$m[2]}Mapper";
                if (class_exists($mapperClass)) $out[] = [$pkg, $mapperClass];
            }
        }
        return $out;
    }

    #[DataProvider('dtoMappersProvider')]
    public function test_round_trip_for_known_columns(string $pkg, string $mapperClass): void
    {
        $parts = preg_split('/[_-]/', $pkg) ?: [];
        $defsClass = "BlackCat\\Database\\Packages\\".implode('', array_map('ucfirst', $parts))."\\Definitions";
        if (!class_exists($defsClass)) $this->markTestSkipped("defs missing for $pkg");

        /** @var string[] $cols */
        $cols  = $defsClass::columns();
        $table = $defsClass::table();

        // types from DB
        $types = [];
        foreach (DbHarness::columns($table) as $c) { $types[strtolower($c['name'])] = $c; }

        // sample from RowFactory (may be missing)
        $sample   = RowFactory::makeSample($table)[0] ?? [];
        $sampleLc = array_change_key_case($sample, CASE_LOWER);

        // JSON columns per definitions (mapper expects arrays)
        $jsonCols = method_exists($defsClass, 'jsonColumns') ? array_fill_keys($defsClass::jsonColumns(), true) : [];

        // alias helpers
        $toCamel = static function(string $snake): string {
            return lcfirst(str_replace(' ', '', ucwords(strtolower($snake), '_')));
        };
        $toSegmentCamelSnake = static function(string $snake): string {
            $parts = explode('_', strtolower($snake));
            $out = array_shift($parts);
            if ($out === '') return $snake;
            foreach ($parts as $p) { $out .= '_'.ucfirst($p); }
            return $out;
        };

        $row = [];
        foreach ($cols as $exact) {
            $lc   = strtolower($exact);
            $meta = $types[$lc] ?? ['type'=>'text','full_type'=>'text','nullable'=>true,'col_default'=>null,'is_identity'=>false];
            if (!empty($meta['is_identity'])) continue;

            // value - prefer sample, otherwise dummy
            $val = $sample[$exact] ?? $sampleLc[$lc] ?? RowFactory::dummyValue($meta);

            // JSON columns as arrays (EncryptedFieldDto $meta etc.)
            if (isset($jsonCols[$exact]) || isset($jsonCols[$lc])) {
                if (!is_array($val)) { $val = []; }
            }
            // DATETIME/TIMESTAMP/DATE/TIME -> convert to DateTimeImmutable upfront (mapper just passes it through)
            // (1) type-based: column has a date/time type in DB
            // (2) name-based: common suffixes (_at/_on/_time/_date/_until) + special case for *_seen (_at optional)
            // (3) legacy whitelist (created/updated/...)
            $isDateLike =
                (bool)preg_match('/(date|time)/i', (string)($meta['type'] ?? ''))                                   // ➊
                || (bool)preg_match('/(_at$|_on$|_time$|_date$|_until$)/i', $lc)                                     // ➋
                || (bool)preg_match('/(^|_)(first|last)_seen(_|$)(at)?$/i', $lc)                                     // ➋
                || (bool)preg_match('/(^|_)(created|updated|deleted|attempted|received|checked|occurred|log|locked)(_|$)at$/i', $lc); // ➌
                    if ($isDateLike) {
                        if (!$val instanceof \DateTimeImmutable) {
                            $val = new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
                        }
                    }
            // primary key (exact name)
            $row[$exact] = $val;

            // aliases commonly accepted by mappers
            $row[$lc]                           = $val;                 // snake lower
            $row[$toCamel($exact)]              = $val;                 // camelCase
            $row[$toSegmentCamelSnake($exact)]  = $val;                 // user_Id / created_At
        }

        // round-trip
        $dto = $mapperClass::fromRow($row);
        $this->assertIsObject($dto);
        $row2 = $mapperClass::toRow($dto);
        $this->assertIsArray($row2);

        // verification: for each known column accept any variant
        $hasAnyKey = static function(array $arr, string $col) use ($toCamel, $toSegmentCamelSnake): bool {
            foreach ([$col, strtolower($col), $toCamel($col), $toSegmentCamelSnake($col)] as $k) {
                if (array_key_exists($k, $arr)) return true;
            }
            return false;
        };

        foreach ($cols as $c) {
            $this->assertTrue($hasAnyKey($row2, $c), "Expected some form of '{$c}' in toRow()");
        }
    }
}
