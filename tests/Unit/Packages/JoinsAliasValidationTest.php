<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Packages;

use PHPUnit\Framework\TestCase;

final class JoinsAliasValidationTest extends TestCase
{
    public function test_app_settings_join_users_alias_ok_and_contains_AS(): void
    {
        $class = 'BlackCat\\Database\\Packages\\AppSettings\\Joins\\AppSettingsJoins';
        if (!class_exists($class)) $this->markTestSkipped('Joins class not found');

        $j = new $class();
        [$sql] = $j->joinUsers('t', 'j0');
        $this->assertStringContainsString(' LEFT JOIN ', $sql);
        $this->assertStringContainsString(' AS j0 ', $sql);
        $this->assertStringContainsString(' ON j0.id = t.updated_by ', $sql);
    }

    public function test_alias_must_differ(): void
    {
        $class = 'BlackCat\\Database\\Packages\\AppSettings\\Joins\\AppSettingsJoins';
        if (!class_exists($class)) $this->markTestSkipped('Joins class not found');
        $this->expectException(\InvalidArgumentException::class);
        (new $class())->joinUsers('t', 't');
    }

    public function test_alias_validation_rejects_invalid_names(): void
    {
        $class = 'BlackCat\\Database\\Packages\\JwtTokens\\Joins\\JwtTokensJoins';
        if (!class_exists($class)) $this->markTestSkipped('Joins class not found');
        $this->expectException(\InvalidArgumentException::class);
        (new $class())->joinUsers('t', '0bad'); // invalid alias
    }
}
