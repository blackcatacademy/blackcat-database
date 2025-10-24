<?php
declare(strict_types=1);

namespace BlackCat\Database\Examples;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Database\Actions\OperationResult;
use BlackCat\Database\Runtime;
// Repozitáře dle tvého generatoru:
use BlackCat\Database\Packages\Users\Repository as UsersRepo;
use BlackCat\Database\Packages\UserProfiles\Repository as ProfilesRepo;

final class UserRegisterService
{
    use ServiceHelpers;

    public function __construct(
        private Database $db,
        private UsersRepo $users,
        private ProfilesRepo $profiles,
        private ?QueryCache $qcache = null
    ) {}

    /** hlavní API pro FE – jedna volání = registrace */
    public function register(array $input): OperationResult
    {
        return $this->withLock('user:register:'.mb_strtolower($input['email'] ?? ''), 5, function() use ($input) {
            return $this->withTimeout(3000, function() use ($input) {
                return $this->retry(3, function() use ($input) {
                    return $this->txn(function() use ($input) {
                        $email = trim((string)($input['email'] ?? ''));
                        if ($email === '') return OperationResult::fail('Email required');

                        // unikátnost (db-level unique je ještě důležitější)
                        $exists = $this->db()->exists("SELECT 1 FROM users WHERE email = :e LIMIT 1", [':e'=>$email]);
                        if ($exists) return OperationResult::fail('Email already registered');

                        $now = (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s.u');
                        $this->users->insert([
                            'email' => $email,
                            'password_hash' => password_hash((string)($input['password'] ?? ''), PASSWORD_DEFAULT),
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);
                        $uid = $this->db()->lastInsertId();

                        $this->profiles->insert([
                            'user_id' => (int)$uid,
                            'display_name' => (string)($input['name'] ?? ''),
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);

                        return OperationResult::ok(['user_id'=>$uid], 'registered');
                    });
                });
            });
        });
    }
}
