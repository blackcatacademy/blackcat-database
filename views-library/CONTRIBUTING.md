# Contributing to BlackCat View Library

This library is a declarative companion to **BlackCat Database** and **BlackCat Installer**. It is treated as a security-sensitive artifact: installer safety checks, DDL guard rules, and profile/tag filtering rely on predictable content. Please follow these rules when proposing changes:

1. **No executable code** – Only declarative view maps (`*.psd1`). Do not add PHP/Python/JS.
2. **Keep metadata complete** – Every view entry must have `Owner`, `Tags`, `Requires`, and `create` SQL with explicit ALGORITHM / SQL SECURITY when applicable.
3. **Profiles/Tags** – Align new files with `profiles.psd1` (or propose updates) so installers can select safe subsets.
4. **Safety checks** – Expect automated validation (hash/signature, DDL guard, lint). Submissions that bypass these checks will be rejected.
5. **Licensing** – The project is proprietary. Do not copy content from third-party sources without explicit permission.

If you contribute from another repo, reference the related change in `blackcat-database` / `blackcat-installer` so we can keep the ecosystem in sync.
