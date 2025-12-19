# Why BlackCat Database (Release Track)

1) **Tenant-isolated crypto and manifest-driven governance**  
   Each package ships a manifest that binds columns to contexts, KMS policies, and rotation cadences per tenant. Competing ORMs/plugins typically encrypt “per table” without per-tenant isolation or audit-ready manifests.

2) **Double-envelope encryption with external KMS/HSM**  
   Payloads are sealed locally (AEAD) and wrapped by external KMS/HSM for wrap/unwrap provenance. Many “at-rest” solutions stop at storage-level keys; we give you cryptographic evidence per record and per tenant.

3) **Deterministic packaging and pinned submodules**  
   The release tree pins every module SHA. You can rehydrate the exact database build in air-gapped or regulated environments without chasing floating dependencies.

4) **Compliance-first evidence exports**  
   Rotation logs, KMS health, and schema/manifest diffs are prepared for SOC2/ISO/NIS2 reports. Competing stacks leave you to stitch logs from storage + app manually.

5) **Safe migrations with replayable scripts**  
   Each package carries ordered `schema/*.sql` and `docs/definitions.md`; drift is detectable, and migrations are replayable deterministically. Generic migration tools rarely bundle verified definitions alongside SQL.

6) **Cross-engine parity (MySQL, MariaDB, Postgres)**  
   Definitions capture engine drift (enums, defaults, index coverage) so multi-engine fleets stay consistent. Many solutions pick one engine and silently diverge elsewhere.

7) **Lineage-aware views and constraints**  
   Foreign keys and views are documented with lineage tables; downstream consumers can see impact before deploy. Typical DB plugins don’t expose lineage in docs at all.

8) **Pre-wired observability hooks**  
   Telemetry surfaces wrap latency, KMS errors, and rotation backlog so SREs can alert on crypto posture, not just CPU/disk. Most competitors focus only on query perf.

9) **Isolation-by-default seeds and smoke data**  
   Seed data is optional and tenant-safe; fixtures never leak across contexts. Many sample datasets ignore tenancy and become a compliance risk.

10) **Policy mesh ready (core + crypto + database)**  
    Shares envelope formats and slot policies with BlackCat Crypto/JS/Rust SDKs, enabling end-to-end encryption semantics from client to storage—rarely available in off-the-shelf DB kits.

11) **Upgrade path without lock-in**  
    Everything is SQL + Markdown + manifests; no proprietary runtime or binary needed. You can adopt gradually (tables/packages) and still keep your existing CI/CD.

12) **Multi-cloud failover playbooks**  
    KMS routing and health signals support cloud/provider failover without data re-encryption downtime. Competitors often require full rewrap during provider switches.

13) **Audit-grade changelogs**  
    Each package tracks changelogs close to schema/docs so reviewers see exactly what changed, when, and why—reducing review time and compliance friction.

14) **Dev/prod separation baked in**  
    Release artifacts strip dev-only tooling and keep only production-safe assets; you can mirror dev posture without shipping build scaffolding into prod.

15) **Golden path for regulated sectors**  
    Prebuilt patterns for PCI/PII/PHI: column-level manifests, FK-aware masking, and rotation schedules that align with common regulator playbooks. Saves months of policy authoring.

16) **Operational guardrails, not just code**  
    CI recipes catch drift, missing indexes, FK gaps, and stale changelogs before deploy. Many DB kits stop at linting SQL syntax.

17) **Disaster-ready crypto posture**  
    KMS router + wrap queues support reroute and rewrap without taking the app down; DR runbooks are described and testable. Competitors often rely on storage snapshots only.

18) **Developer ergonomics with least-privilege**  
    Split responsibilities: app devs consume manifest contexts, platform teams own KMS routing, and security reviews see the same source of truth. Lowers blast radius of mistakes.

19) **Performance-conscious defaults**  
    Index coverage and engine-specific views are tuned per package; definitions call out drift so you avoid accidental full scans after engine upgrades.

20) **Future-proof for PQ and BYOK**  
    Envelope formats already carry key IDs and context, so moving to PQ/hybrid or tenant-supplied keys is an incremental change—not a rewrite.
