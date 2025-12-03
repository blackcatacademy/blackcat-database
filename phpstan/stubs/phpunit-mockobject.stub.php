<?php

namespace PHPUnit\Framework\MockObject;

use PHPUnit\Framework\MockObject\Builder\InvocationMocker;

/**
 * @template TMockedClass
 */
interface MockObject
{
    /**
     * @param mixed $invocationRule
     * @return InvocationMocker<TMockedClass>
     */
    public function expects($invocationRule): InvocationMocker;

    /**
     * @param mixed $constraint
     * @return InvocationMocker<TMockedClass>
     */
    public function method($constraint): InvocationMocker;
}
