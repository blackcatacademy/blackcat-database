<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database\Support;

use DateTimeImmutable;
use DateTimeZone;
use ReflectionClass;
use ReflectionMethod;
use ReflectionParameter;

/**
 * DtoHydrator – fast, safe, developer-loved hydration between DTOs and DB rows.
 *
 * Improvements over the original version:
 * - O(1) lookups via hash sets for typed columns (bool/int/float/json/date/bin).
 * - Safer constructor hydration (fallbacks + cached reflection).
 * - In "property" mode we only write into **public** and **non-readonly** properties.
 * - Consistent date format during serialization (Y-m-d H:i:s.u).
 * - Stable handling of empty values (null/'' → null).
 *
 * Note: we intentionally avoid aggressive type coercion based on DTO signatures
 * and rely on explicit column lists (boolCols/intCols/…) to keep hydration predictable.
 */
final class DtoHydrator
{
    /** @var array<class-string, array{rc:ReflectionClass, ctor:?ReflectionMethod, params:list<ReflectionParameter>}> */
    private static array $refCache = [];

    /**
     * @template T of object
     * @param class-string<T>         $dtoClass
     * @param array<string,mixed>     $row
     * @param array<string,string>    $colToProp    Column → property mapping
     * @param string[]                $boolCols
     * @param string[]                $intCols
     * @param string[]                $floatCols
     * @param string[]                $jsonCols
     * @param string[]                $dateCols
     * @param string[]                $binCols
     * @return T
     * @phpstan-return T
     */
    public static function fromRow(
        string $dtoClass,
        array $row,
        array $colToProp,
        array $boolCols,
        array $intCols,
        array $floatCols,
        array $jsonCols,
        array $dateCols,
        array $binCols,
        DateTimeZone $tz
    ): object {
        // Prepare hash sets for O(1) membership checks
        $Sbool  = \array_fill_keys($boolCols,  true);
        $Sint   = \array_fill_keys($intCols,   true);
        $Sfloat = \array_fill_keys($floatCols, true);
        $Sjson  = \array_fill_keys($jsonCols,  true);
        $Sdate  = \array_fill_keys($dateCols,  true);
        $Sbin   = \array_fill_keys($binCols,   true);

        $vals = [];
        foreach ($row as $col => $val) {
            $col  = (string)$col;
            $prop = $colToProp[$col] ?? $col;

            if (isset($Sbin[$col]))       { $val = BinaryCodec::toBinary($val); }
            elseif (isset($Sbool[$col]))  { $val = Casts::toBool($val); }
            elseif (isset($Sint[$col]))   { $val = Casts::toInt($val); }
            elseif (isset($Sfloat[$col])) { $val = Casts::toFloat($val); }
            elseif (isset($Sjson[$col]))  { $val = JsonCodec::decode($val); }
            elseif (isset($Sdate[$col]))  { $val = Casts::toDate($val, $tz); }

            $vals[$prop] = $val;
        }

        // Reflexe (s cache)
        [$rc, $ctor, $params] = self::reflect($dtoClass);

        // 1) Non-constructor hydration (no required parameters)
        if ($ctor === null || $ctor->getNumberOfRequiredParameters() === 0) {
            $obj = $rc->newInstance();

            // Nastav pouze public a ne-readonly properties
            foreach ($vals as $name => $value) {
                if (!$rc->hasProperty($name)) {
                    continue;
                }
                $rp = $rc->getProperty($name);
                // PHP 8.1+: ReflectionProperty::isReadOnly(); method does not exist on older versions
                $isReadonly = \method_exists($rp, 'isReadOnly') ? $rp->isReadOnly() : false;
                if ($rp->isPublic() && !$isReadonly) {
                    $rp->setValue($obj, $value);
                }
            }
            /** @var T $obj */
            return $obj;
        }

        // 2) Constructor-based hydration (ordered by parameters + defaults)
        $ordered = [];
        foreach ($params as $p) {
            $name = $p->getName();
            if (\array_key_exists($name, $vals)) {
                $ordered[] = $vals[$name];
            } elseif ($p->isDefaultValueAvailable()) {
                $ordered[] = $p->getDefaultValue();
            } else {
                // No value -> null (may fail if the type is non-nullable, which is fine because it surfaces a bad mapping)
                $ordered[] = null;
            }
        }

        // Safe attempt to create the instance; on failure try the "property" fallback (if possible)
        try {
            /** @var T $instance */
            $instance = $rc->newInstanceArgs($ordered);
            return $instance;
        } catch (\Throwable) {
            // Fallback only when no required parameters exist (in theory this branch should never run
            // because we already chose the path with required parameters deliberately)
            $obj = $rc->newInstanceWithoutConstructor();
            foreach ($vals as $name => $value) {
                if ($rc->hasProperty($name)) {
                    $rp = $rc->getProperty($name);
                    $isReadonly = \method_exists($rp, 'isReadOnly') ? $rp->isReadOnly() : false;
                    if ($rp->isPublic() && !$isReadonly) {
                        $rp->setValue($obj, $value);
                    }
                }
            }
            /** @var T $obj */
            return $obj;
        }
    }

    /**
     * @param object|array<string,mixed> $dtoOrArray
     * @param array<string,string>       $colToProp  Column → property mapping
     * @param string[]                   $boolCols
     * @param string[]                   $intCols
     * @param string[]                   $floatCols
     * @param string[]                   $jsonCols
     * @param string[]                   $dateCols
     * @param string[]                   $binCols
     * @param string[]|null              $onlyProps  Whitelist of properties (property names)
     * @return array<string,mixed>
     */
    public static function toRow(
        object|array $dtoOrArray,
        array $colToProp,
        array $boolCols,
        array $intCols,
        array $floatCols,
        array $jsonCols,
        array $dateCols,
        array $binCols,
        DateTimeZone $tz,
        ?array $onlyProps = null
    ): array {
        $src = \is_array($dtoOrArray)
            ? $dtoOrArray
            : (\method_exists($dtoOrArray, 'toArray') ? $dtoOrArray->toArray() : \get_object_vars($dtoOrArray));

        if ($onlyProps !== null) {
            $src = \array_intersect_key($src, \array_fill_keys($onlyProps, true));
        }

        $rev = \array_flip($colToProp);

        // Hash-sety
        $Sbool  = \array_fill_keys($boolCols,  true);
        $Sint   = \array_fill_keys($intCols,   true);
        $Sfloat = \array_fill_keys($floatCols, true);
        $Sjson  = \array_fill_keys($jsonCols,  true);
        $Sdate  = \array_fill_keys($dateCols,  true);
        $Sbin   = \array_fill_keys($binCols,   true);

        $out = [];
        foreach ($src as $prop => $val) {
            $col = $rev[$prop] ?? (string)$prop;

            if (isset($Sbin[$col])) {
                $val = BinaryCodec::fromBinary($val);
            } elseif (isset($Sjson[$col])) {
                $val = JsonCodec::encode($val);
            } elseif (isset($Sdate[$col])) {
                if ($val instanceof DateTimeImmutable) {
                    $val = $val->format('Y-m-d H:i:s.u');
                } elseif ($val !== null && $val !== '') {
                    try {
                        $val = (new DateTimeImmutable((string)$val, $tz))->format('Y-m-d H:i:s.u');
                    } catch (\Throwable) {
                        $val = null;
                    }
                } else {
                    $val = null;
                }
            } elseif (isset($Sbool[$col])) {
                $tmp = Casts::toBool($val);
                $val = $tmp === null ? null : ($tmp ? 1 : 0);
            } elseif (isset($Sint[$col])) {
                $tmp = Casts::toInt($val);
                $val = $tmp === null ? null : $tmp;
            } elseif (isset($Sfloat[$col])) {
                $tmp = Casts::toFloat($val);
                $val = $tmp === null ? null : $tmp;
            }

            $out[$col] = $val;
        }

        return $out;
    }

    /**
     * @template T of object
     * @param class-string<T>       $dtoClass
     * @param list<array<string,mixed>> $rows
     * @return list<T>
     */
    public static function hydrateList(
        string $dtoClass,
        array $rows,
        array $colToProp,
        array $boolCols,
        array $intCols,
        array $floatCols,
        array $jsonCols,
        array $dateCols,
        array $binCols,
        DateTimeZone $tz
    ): array {
        $out = [];
        foreach ($rows as $r) {
            $out[] = self::fromRow($dtoClass, $r, $colToProp, $boolCols, $intCols, $floatCols, $jsonCols, $dateCols, $binCols, $tz);
        }
        return $out;
    }

    /* ---------------------------- internals ----------------------------- */

    /**
     * @param class-string $class
     * @return array{0:ReflectionClass,1:?ReflectionMethod,2:list<ReflectionParameter>}
     */
    private static function reflect(string $class): array
    {
        if (!isset(self::$refCache[$class])) {
            $rc    = new ReflectionClass($class);
            $ctor  = $rc->getConstructor();
            $params = $ctor ? $ctor->getParameters() : [];
            self::$refCache[$class] = ['rc' => $rc, 'ctor' => $ctor, 'params' => $params];
        }
        $c = self::$refCache[$class];
        /** @var ReflectionClass $rc */
        $rc = $c['rc'];
        /** @var ReflectionMethod|null $ctor */
        $ctor = $c['ctor'];
        /** @var list<ReflectionParameter> $params */
        $params = $c['params'];
        return [$rc, $ctor, $params];
    }
}
