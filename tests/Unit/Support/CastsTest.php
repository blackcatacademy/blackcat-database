<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\Casts;

final class CastsTest extends TestCase
{
    public function testToBoolHandlesCommonRepresentations(): void
    {
        $this->assertTrue(Casts::toBool('yes'));
        $this->assertFalse(Casts::toBool('off'));
        $this->assertNull(Casts::toBool('maybe'));
        $this->assertTrue(Casts::toBool(2));
    }

    public function testToIntAndFloatRespectSanitization(): void
    {
        $this->assertSame(42, Casts::toInt('42'));
        $this->assertSame(-3, Casts::toInt('-3.7'));
        $this->assertNull(Casts::toInt('3e2foo'));

        $this->assertSame(3.14, Casts::toFloat('3,14'));
        $this->assertSame(0.5, Casts::toFloat('.5'));
        $this->assertNull(Casts::toFloat('abc'));
    }

    public function testToDateSupportsEpochAndStrings(): void
    {
        $tz = new DateTimeZone('UTC');
        $dt = Casts::toDate('2024-01-02T03:04:05+00:00', $tz);
        $this->assertInstanceOf(DateTimeImmutable::class, $dt);
        $this->assertSame('2024-01-02 03:04:05', $dt?->format('Y-m-d H:i:s'));

        $ms = (int)(1700000000 * 1000);
        $epoch = Casts::toDate((string)$ms, $tz);
        $this->assertSame(1700000000, $epoch?->getTimestamp());
    }
}
