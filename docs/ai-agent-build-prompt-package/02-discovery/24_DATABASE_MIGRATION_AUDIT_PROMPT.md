# Prompt 24 — Database, Supabase, and Migration Audit

**Prompt ID:** `CG-S2-DISC-004`  
**Package document:** `CG-AABPP-DISC-024`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Database, migration, tenancy, and persistence baseline  
**Runtime output:** `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`

## Objective and business value

Establish the existing PostgreSQL/Supabase schema and migration truth, applied-history evidence, RLS/grant/storage/function posture, generated-type consistency, seed/backfill risk, PostGIS/job primitives, and drift uncertainty without applying or modifying any database state. This prevents destructive planning and preserves upgrade paths.

## Source requirements

- Master Prompt Step 2 and §§11–13, 17, 19–20.
- CPD-004/006/007/017–023; RPD-011/012/014/015/020/022/025/032/033/039.
- GOV-010 tenant/data/finance/migration rules; GOV-011 database rules.
- Technical Architecture §§8–12, 17, 22–25, 29, 31–33, 37–39.
- Delivery Plan §§16–18, 20–24, 27.

## Preconditions and authorization

Prompts 21–23 are complete at one trusted checkpoint. Read migration SQL, schema files, Supabase config, generated types, database access code, tests, seed/backfill scripts, and documentation. Database CLI/status queries are allowed only when proven read-only and connected to an approved disposable/local or explicitly authorized read-only environment.

Forbidden: `db reset`, migration apply/repair/squash, schema push/pull that writes files, seed/backfill, SQL write, function invocation with side effects, type generation, remote linkage changes, secret printing, or production data access.

## Mandatory pre-flight

- Reconfirm HEAD/worktree and prompt 23 safe-command classifications.
- Detect Supabase/project linkage and environment without revealing project refs, credentials, or connection strings beyond approved redacted identifiers.
- Treat any unknown or production-linked database as prohibited.
- If applied migration history cannot be inspected safely, use repository evidence and classify runtime drift `UNKNOWN`; do not guess.

## Detailed tasks

### A. Migration inventory and integrity

- Inventory migrations in deterministic order with path, timestamp/version, hash, purpose inferred from SQL, and dependencies.
- Detect duplicate/out-of-order identifiers, edited/apparently squashed history, irreversible/destructive SQL, long-lock risks, broad table rewrites, unbounded backfills, missing transaction/recovery notes, and environment-conditional behavior.
- Compare repository history with safely available applied-history metadata. Never expose database credentials or tenant data.
- Mark already-applied migrations as immutable planning inputs.

### B. Schema inventory

- Extract tables, schemas, enums, columns, defaults, constraints, FKs, unique/check constraints, indexes, views/materialized views, functions, triggers, extensions, publications/realtime, sequences, storage buckets/policies, auth hooks, and grants from authoritative migration/schema files.
- Identify tenant-scoped tables and tenant-aware FK/index patterns.
- Detect direct balance fields, ledger/event structures, audit tables, configuration versions/effective dates, idempotency keys, soft-delete/archive fields, and retention metadata.

### C. RLS, grants, and privileged paths

- Map RLS enabled/forced state and policies by table/action/role.
- Identify tables with no RLS, permissive/wildcard policies, policy recursion, missing tenant predicate, unsafe JWT claims, service-role/bypass paths, `SECURITY DEFINER` functions, mutable `search_path`, public execution grants, and storage-policy gaps.
- Distinguish the ratified Supreme Admin absolute-CRUD requirement from accidental service-role/browser bypass. Do not describe audit/ledger as tamper-proof.

### D. Data access and contract alignment

- Map ORM/query clients, generated TypeScript types, SQL functions/RPC, REST/PostgREST, GraphQL, server actions/handlers, jobs, reports, and integrations to schema ownership.
- Detect stale generated types, schema duplication, raw SQL outside governed layers, `SELECT *`, missing pagination/index support, cross-tenant cache/job/report risk, and live-OLTP dashboard queries without guards.

### E. Required foundations

Assess evidence for PostGIS, PostgreSQL durable queue/job tables/functions, audit metadata, file/document records and malware-scan state, idempotency, API credential storage, configuration snapshots, and finance/ledger controls. Classification is evidence-based; do not create missing objects.

### F. Seed, fixtures, dumps, and data safety

- Inventory seeds/fixtures/backfills/dumps by filename and metadata.
- Identify real-tenant/PII/finance/payroll/banking indicators without copying values.
- Classify scripts by idempotency, environment protection, destructive behavior, and whether they are safe for local testing.

## Suggested safe inspection

Use `rg`, file parsing, hashes, and repository SQL inspection. Read-only status/list commands may be used only after verifying target and side effects. Do not start Supabase, reset a DB, or generate types merely to improve evidence.

## Required output structure

1. Checkpoint, environment/linkage classification, limitations.
2. Migration inventory with hashes and applied-history confidence.
3. Destructive/lock/backfill/recovery risk table.
4. Schema/object inventory and canonical-domain mapping.
5. Tenant-table, RLS, policy, grant, function, storage, and negative-test matrix.
6. Index/FK/constraint/concurrency/idempotency findings.
7. Audit/ledger/finance/retention findings with Supreme Admin disclosure.
8. PostGIS, queue, reporting/search, file-scan, API credential foundations.
9. Generated-type/data-access/schema-contract drift findings.
10. Seed/fixture/dump safety inventory.
11. Database trust classification: `TRUSTED_REPOSITORY_ONLY`, `TRUSTED_LOCAL`, `DRIFT_SUSPECTED`, `UNKNOWN`, or `UNTRUSTED`.
12. Blockers, ADR/migration/security/test follow-ups, evidence appendix, output hash.

## Acceptance criteria and Definition of Done

- Every migration and authoritative schema source is inventoried or explicitly blocked.
- Tenant/RLS/grant/function/storage coverage is mapped without active exploitation.
- Applied-history and drift confidence are explicit.
- Destructive/financial/data risks are logged; no remediation occurs.
- No database, migration, generated type, seed, config, lockfile, or external state changes.
- Persistent documentation and ledgers are reconciled.

## Failure and recovery

If a command connects to an unauthorized/production target, changes data/files, or exposes a secret/tenant record, terminate it, redact evidence, record an Error/Incident entry, preserve the worktree, and require trust restoration before continuation.

## Completion and next prompt

Report migration count/hash status, database trust, schema/RLS gaps, critical risks, commands/results, files written, limitations, and next prompt.

Next: `CG-S2-DISC-005` — Route and Module Inventory.
