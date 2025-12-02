<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\BinaryCodec;

final class BinaryCodecTest extends TestCase
{
    public function testDecodesPgMysqlAndSqlLiteral(): void
    {
        $pg = BinaryCodec::toBinary('\\x414243');
        $this->assertSame('ABC', $pg);

        $mysql = BinaryCodec::fromBinary('0x444546');
        $this->assertSame('DEF', $mysql);

        $sql = BinaryCodec::toBinary("x'4748 49'");
        $this->assertSame('GHI', $sql);
    }

    public function testDecodesBase64AndDataUri(): void
    {
        $b64 = BinaryCodec::toBinary('SGVsbG8=');
        $this->assertSame('Hello', $b64);

        $uri = BinaryCodec::fromBinary('data:text/plain;base64,V29ybGQ=');
        $this->assertSame('World', $uri);
    }

    public function testDecodesStreamsAndObjects(): void
    {
        $stream = fopen('php://temp', 'rb+');
        $this->assertNotFalse($stream, 'Failed to open temp stream');
        $this->assertIsResource($stream);
        fwrite($stream, 'abcd');
        rewind($stream);
        $this->assertSame('abcd', BinaryCodec::toBinary($stream));
        fclose($stream);

        $obj = new class {
            public function __toString(): string { return 'xyz'; }
        };
        $this->assertSame('xyz', BinaryCodec::toBinary($obj));
    }

    public function testReturnsNullForEmptyOrInvalid(): void
    {
        $this->assertNull(BinaryCodec::toBinary(''));
        $this->assertNull(BinaryCodec::fromBinary(null));
        // Unknown format → original string returned
        $this->assertSame('plain', BinaryCodec::toBinary('plain'));
    }
}
