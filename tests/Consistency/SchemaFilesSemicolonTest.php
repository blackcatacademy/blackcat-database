<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Consistency;

use PHPUnit\Framework\TestCase;

final class SchemaFilesSemicolonTest extends TestCase
{
    public function testAllSchemaFilesEndWithSemicolon(): void
    {
        $root = \realpath(__DIR__ . '/../../'); // projekt root = tests/.. (dvě úrovně nahoru)
        $this->assertNotFalse($root, 'Cannot resolve project root');
        $packages = $root . '/packages';
        $this->assertDirectoryExists($packages, "Missing directory: $packages");

        $missing = [];
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator(
                $packages,
                \FilesystemIterator::SKIP_DOTS | \FilesystemIterator::CURRENT_AS_FILEINFO
            ),
            \RecursiveIteratorIterator::LEAVES_ONLY
        );

        /** @var \SplFileInfo $f */
        foreach ($it as $f) {
            if (!$f->isFile()) {
                continue;
            }
            $fn = $f->getRealPath();
            if ($fn === false) {
                continue;
            }
            // pouze schema *.sql soubory
            if (substr($fn, -4) !== '.sql') {
                continue;
            }
            // optional: vynecháme prázdné/komentářové soubory
            $raw = @file_get_contents($fn);
            if ($raw === false) {
                $missing[] = [$fn, 'unreadable'];
                continue;
            }

            // odstranit BOM a oříznout whitespace na konci
            $raw = preg_replace('/^\xEF\xBB\xBF/', '', $raw);
            $trimmed = rtrim($raw);

            // pokud je soubor po odfiltrování prázdný (nebo jen komentáře), přeskoč
            if ($this->isEffectivelyEmptySql($trimmed)) {
                continue;
            }

            // poslední non-whitespace znak musí být ';'
            $endsWithSemicolon = (bool)preg_match('/;\s*$/', $trimmed);

            if (!$endsWithSemicolon) {
                $tail = mb_substr($trimmed, max(0, mb_strlen($trimmed) - 80));
                $missing[] = [$fn, $tail];
            }
        }

        $this->assertEmpty(
            $missing,
            "These SQL files do not end with semicolon:\n" .
            implode(
                "\n",
                array_map(
                    fn(array $m) => "- {$m[0]}\n  tail: " . $m[1],
                    $missing
                )
            )
        );
    }

    /**
     * Heuristika: ignoruj soubory, které po odstranění whitespace
     * a komentářů (SQL -- a /* * /) neobsahují žádný příkaz.
     */
    private function isEffectivelyEmptySql(string $sql): bool
    {
        $s = $sql;

        // odstranění block komentářů /* ... */
        $s = preg_replace('#/\*.*?\*/#s', '', $s);
        // odstranění single-line komentářů -- ... na konci řádku
        $s = preg_replace('/--[^\n\r]*/', '', $s);

        // po odstranění komentářů a whitespace je prázdné?
        return trim($s) === '';
    }
}
