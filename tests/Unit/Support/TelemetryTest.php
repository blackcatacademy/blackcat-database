<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\Telemetry;
use Psr\Log\LoggerInterface;

final class TelemetryTest extends TestCase
{
    protected function tearDown(): void
    {
        Telemetry::setLogger(null);
        Telemetry::setDefaultContext([]);
        Telemetry::setMinLevel(null);
    }

    public function testHonorsMinLevelAndDefaultContext(): void
    {
        $logger = new class implements LoggerInterface {
            public array $lines = [];
            public function log($level, $message, array $context = []): void { $this->lines[] = [$level,$message,$context]; }
            public function emergency($message, array $context = []): void { $this->log('emergency',$message,$context); }
            public function alert($message, array $context = []): void { $this->log('alert',$message,$context); }
            public function critical($message, array $context = []): void { $this->log('critical',$message,$context); }
            public function error($message, array $context = []): void { $this->log('error',$message,$context); }
            public function warning($message, array $context = []): void { $this->log('warning',$message,$context); }
            public function notice($message, array $context = []): void { $this->log('notice',$message,$context); }
            public function info($message, array $context = []): void { $this->log('info',$message,$context); }
            public function debug($message, array $context = []): void { $this->log('debug',$message,$context); }
        };

        Telemetry::setLogger($logger);
        Telemetry::setDefaultContext(['svc' => 'test']);
        Telemetry::setMinLevel('warning');

        Telemetry::info('ignored');
        Telemetry::error('boom', ['corr' => 'abc']);

        $this->assertCount(1, $logger->lines);
        $this->assertSame('error', $logger->lines[0][0]);
        $this->assertSame('test', $logger->lines[0][2]['svc']);
    }

    public function testErrorFieldsAndSampling(): void
    {
        $pdoe = new PDOException('fail', 0);
        $pdoe->errorInfo = ['40001', 123, 'deadlock'];
        $e = new RuntimeException('wrap', 0, $pdoe);
        $fields = Telemetry::errorFields($e);
        $this->assertSame('40001', $fields['sqlstate'] ?? ($fields['cause']['sqlstate'] ?? null));

        $sampled = Telemetry::shouldSample(['sample' => 0.0]);
        $this->assertFalse($sampled);
        $this->assertTrue(Telemetry::shouldSample(['sample' => 1.0]));
    }
}
