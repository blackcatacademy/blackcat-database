# examples

Reference snippets that show how higher-level services compose repositories,
helpers, and runtime primitives from the BlackCat database layer.

Current catalog:

- `UserRegisterService.php` – end-to-end registration flow that showcases
  `ServiceHelpers`, distributed locking, retries, transactional writes, and
  inter-module communication between the `Users` and `UserProfiles` packages.

Use these samples as inspiration when wiring your own domain services or when
writing quick PoCs.
