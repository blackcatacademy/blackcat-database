<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use ReflectionClass;

final class GenericCrudServiceTemplateTest extends TestCase
{
    /**
     * These assertions ensure the generated thin CRUD services expose the
     * bulk/revive helpers introduced in the template. We only introspect
     * class metadata; no database or repository is instantiated.
     */
    #[DataProvider('crudServiceClasses')]
    public function testHelpersArePresentAndTyped(string $class): void
    {
        if (!class_exists($class)) {
            $this->fail("Generated class missing: {$class}");
        }
        $rc = new ReflectionClass($class);

        $this->assertTrue($rc->hasMethod('upsertMany'), 'upsertMany missing on ' . $class);
        $this->assertTrue($rc->hasMethod('upsertRevive'), 'upsertRevive missing on ' . $class);
        $this->assertTrue($rc->hasMethod('upsertManyRevive'), 'upsertManyRevive missing on ' . $class);

        $opResult = 'BlackCat\\Database\\Support\\OperationResult';

        foreach (['upsertMany', 'upsertRevive', 'upsertManyRevive'] as $method) {
            $rm = $rc->getMethod($method);
            $ret = $rm->getReturnType();
            $this->assertNotNull($ret, "$method return type missing on $class");
            $this->assertSame($opResult, $ret instanceof \ReflectionNamedType ? $ret->getName() : null);
        }
    }

    /**
     * @return array<array{0:string}>
     */
    public static function crudServiceClasses(): array
    {
        return [
            ['BlackCat\\Database\\Packages\\DeletionJobs\\Service\\GenericCrudService'],
            ['BlackCat\\Database\\Packages\\Users\\Service\\GenericCrudService'],
        ];
    }
}
