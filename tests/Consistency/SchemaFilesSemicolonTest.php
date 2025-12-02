<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Consistency;

use PHPUnit\Framework\TestCase;

final class SchemaFilesSemicolonTest extends TestCase
{
    public function testAllSchemaFilesEndWithSemicolon(): void
    {
        $root = \realpath(__DIR__ . '/../../'); // project root = tests/.. (two levels up)
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
            // optional: skip empty/comment-only files
            $raw = @file_get_contents($fn);
            if ($raw === false) {
                $missing[] = [$fn, 'unreadable'];
                continue;
            }

            // remove BOM and trim trailing whitespace
            $raw = preg_replace('/^\xEF\xBB\xBF/', '', $raw);
            $trimmed = rtrim((string)$raw);

            // skip if the file is empty after filtering (or comments only)
            if ($this->isEffectivelyEmptySql($trimmed)) {
                continue;
            }

            // last non-whitespace character must be ';'
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
     * Heuristic: ignore files that after stripping whitespace
     * and comments (SQL -- and /* * /) contain no statements.
     */
    private function isEffectivelyEmptySql(string $sql): bool
    {
        $s = $sql;

        // remove block comments /* ... */
        $s = preg_replace('#/\*.*?\*/#s', '', $s) ?? '';
        // remove single-line comments -- ... at EOL
        $s = preg_replace('/--[^\n\r]*/', '', $s) ?? '';

        // empty after removing comments and whitespace?
        return trim((string)$s) === '';
    }
}
