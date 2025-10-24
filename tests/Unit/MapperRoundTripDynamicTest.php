<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit;

use PHPUnit\Framework\TestCase;
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
        $root = realpath(__DIR__ . '/../../packages');
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if ($f->isFile() && preg_match('~/packages/([^/]+)/src/Mapper/([A-Za-z0-9_]+)Mapper\.php$~', $f->getPathname(), $m)) {
                $pkg = $m[1]; $mapperClass = "BlackCat\\Database\\Packages\\".implode('', array_map('ucfirst', preg_split('/[_-]/',$pkg)))."\\Mapper\\{$m[2]}Mapper";
                require_once $f->getPathname();
                if (class_exists($mapperClass)) $out[] = [$pkg, $mapperClass];
            }
        }
        return $out;
    }

    /**
     * @dataProvider dtoMappersProvider
     */
    public function test_round_trip_for_known_columns(string $pkg, string $mapperClass): void
    {
        $defsClass = "BlackCat\\Database\\Packages\\".implode('', array_map('ucfirst', preg_split('/[_-]/',$pkg)))."\\Definitions";
        if (!class_exists($defsClass)) $this->markTestSkipped("defs missing for $pkg");

        /** @var string[] $cols */
        $cols = $defsClass::columns();
        $table= $defsClass::table();

        // sestav "syntetický" řádek podle typů v DB
        $types = [];
        foreach (DbHarness::columns($table) as $c) { $types[$c['name']] = $c; }

        $row = [];
        foreach ($cols as $c) {
            $meta = $types[$c] ?? ['type'=>'text','full_type'=>'text','nullable'=>true,'col_default'=>null,'is_identity'=>false];
            if ($meta['is_identity']) continue;
            $row[$c] = RowFactory::makeSample($table)[0][$c] ?? RowFactory::dummyValue($meta);
        }

        // row -> DTO -> row
        $dto = $mapperClass::fromRow($row);
        $this->assertIsObject($dto);
        $row2 = $mapperClass::toRow($dto);
        $this->assertIsArray($row2);
        // zkontroluj alespoň podmnožinu, že typicky povinné sloupce “přežily”
        foreach ($row as $k=>$v) {
            if (is_array($v)) continue; // json se serializuje
            $this->assertArrayHasKey($k, $row2);
        }
    }
}
