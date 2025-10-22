@{
  File   = 'src/Dto/[[DTO_CLASS]].php'
  Tokens = @(
    'NAMESPACE',             # např. BlackCat\Database\Packages\Users
    'DTO_CLASS',             # např. UserDto
    'DTO_CTOR_PARAMS'        # např. "public readonly int $id, public readonly ?string $emailHash, public readonly ?\DateTimeImmutable $createdAt"
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Dto;

/**
 * Jednoduché, neměnné DTO s veřejnými readonly vlastnostmi.
 * - Žádná logika; pouze nosič dat.
 * - Silné typy drží kontrakt napříč vrstvami.
 */
final class [[DTO_CLASS]] {
    public function __construct(
        [[DTO_CTOR_PARAMS]]
    ) {}

    /** Vhodné pro serializaci/logování (bez binárních/velkých blobů). */
    public function toArray(): array {
        // get_object_vars funguje dobře s public readonly vlastnostmi
        return get_object_vars($this);
    }
}
'@
}
