<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;

final class RepositoryWritePathEncryptionTest extends TestCase
{
    public function testRepositoryTemplateDoUpsertByKeysMergesKeysBeforeIngressEncryption(): void
    {
        $root = \dirname(__DIR__, 3);
        $tpl = $root . '/scripts/templates/php/repository-template.yaml';
        self::assertFileExists($tpl);

        $src = (string)\file_get_contents($tpl);

        $start = \strpos($src, 'private function doUpsertByKeys');
        self::assertIsInt($start);
        self::assertNotFalse($start);

        $end = \strpos($src, '/** Batch upsert - default', $start);
        self::assertIsInt($end);
        self::assertNotFalse($end);

        $block = \substr($src, $start, $end - $start);

        self::assertStringNotContainsString('$this->filterCols($this->normalizeInputRow($row))', $block);
        self::assertStringContainsString('if (!$row && !$keys) return;', $block);
        self::assertStringContainsString('$row = $this->normalizeInputRow($row);', $block);
        self::assertStringContainsString('$row  = $this->filterCols($row);', $block);

        $posNormalize = \strpos($block, '$row = $this->normalizeInputRow($row);');
        $posFilter = \strpos($block, '$row  = $this->filterCols($row);');
        self::assertIsInt($posNormalize);
        self::assertIsInt($posFilter);
        self::assertNotFalse($posNormalize);
        self::assertNotFalse($posFilter);
        self::assertLessThan($posFilter, $posNormalize, 'normalizeInputRow() must occur before filterCols().');
    }

    public function testRepositoryTemplateUpsertManyRevivePreprocessesRowsBeforeBulkHelper(): void
    {
        $root = \dirname(__DIR__, 3);
        $tpl = $root . '/scripts/templates/php/repository-template.yaml';
        self::assertFileExists($tpl);

        $src = (string)\file_get_contents($tpl);

        $start = \strpos($src, 'public function upsertManyRevive');
        self::assertIsInt($start);
        self::assertNotFalse($start);

        $end = \strpos($src, '// --- UPDATE / DELETE / RESTORE', $start);
        self::assertIsInt($end);
        self::assertNotFalse($end);

        $block = \substr($src, $start, $end - $start);

        self::assertStringContainsString('$soft = Definitions::softDeleteColumn();', $block);
        self::assertStringContainsString('$r = $this->normalizeInputRow($r);', $block);
        self::assertStringContainsString('if ($soft) { $r[$soft] = null; }', $block);
        self::assertStringContainsString('$r = $this->filterCols($r);', $block);
        self::assertStringContainsString('$bulk->upsertMany($rows, $helperKeys, $updCols);', $block);
    }

    public function testRepositoryTemplateGetByUniqueAppliesIngressCriteriaTransform(): void
    {
        $root = \dirname(__DIR__, 3);
        $tpl = $root . '/scripts/templates/php/repository-template.yaml';
        self::assertFileExists($tpl);

        $src = (string)\file_get_contents($tpl);

        $start = \strpos($src, 'public function getByUnique');
        self::assertIsInt($start);
        self::assertNotFalse($start);

        $end = \strpos($src, 'public function exists', $start);
        self::assertIsInt($end);
        self::assertNotFalse($end);

        $block = \substr($src, $start, $end - $start);

        self::assertStringContainsString('$keyValues = $this->ingressCriteriaTransform($keyValues);', $block);

        $posTransform = \strpos($block, '$keyValues = $this->ingressCriteriaTransform($keyValues);');
        $posWhere = \strpos($block, 'foreach ($keyValues as $col => $val)');
        self::assertIsInt($posTransform);
        self::assertIsInt($posWhere);
        self::assertNotFalse($posTransform);
        self::assertNotFalse($posWhere);
        self::assertLessThan($posWhere, $posTransform, 'criteria transform must run before building WHERE.');
    }

    public function testGeneratedRepositoriesDoNotBypassIngressEncryptionInUpsertByKeysOrReviveBulk(): void
    {
        $root = \dirname(__DIR__, 3);
        $repoFiles = \glob($root . '/packages/*/src/Repository/*Repository.php') ?: [];
        self::assertNotEmpty($repoFiles, 'No generated repositories found under packages/*/src/Repository.');

        foreach ($repoFiles as $file) {
            $src = (string)\file_get_contents($file);

            // doUpsertByKeys: key values must be merged before filterCols()
            if (\strpos($src, 'private function doUpsertByKeys') !== false) {
                $start = \strpos($src, 'private function doUpsertByKeys');
                $end = \strpos($src, '/** Batch upsert - default', $start);
                self::assertIsInt($start);
                self::assertIsInt($end);
                self::assertNotFalse($start);
                self::assertNotFalse($end);

                $block = \substr($src, $start, $end - $start);
                self::assertStringNotContainsString('$this->filterCols($this->normalizeInputRow($row))', $block, $file);
                self::assertStringContainsString('$row = $this->normalizeInputRow($row);', $block, $file);
                self::assertStringContainsString('$row  = $this->filterCols($row);', $block, $file);
            }

            // upsertManyRevive: bulk helper path must preprocess rows (normalize + soft-delete NULL + filterCols)
            if (\strpos($src, 'Optimized helper (revive mode)') !== false) {
                self::assertStringContainsString('$soft = Definitions::softDeleteColumn();', $src, $file);
                self::assertStringContainsString('$r = $this->normalizeInputRow($r);', $src, $file);
                self::assertStringContainsString('if ($soft) { $r[$soft] = null; }', $src, $file);
                self::assertStringContainsString('$r = $this->filterCols($r);', $src, $file);
            }

            // getByUnique: deterministic criteria transform (HMAC-only) must happen before building WHERE
            if (\strpos($src, 'public function getByUnique') !== false) {
                self::assertStringContainsString('$keyValues = $this->ingressCriteriaTransform($keyValues);', $src, $file);
            }
        }
    }
}
