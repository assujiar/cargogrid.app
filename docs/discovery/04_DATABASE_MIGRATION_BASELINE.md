# 04 — Database, Supabase, and Migration Baseline

**Prompt:** `CG-S2-DISC-004` (`CG-AABPP-DISC-024` v0.3.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/02-discovery/24_DATABASE_MIGRATION_AUDIT_PROMPT.md`
**Status:** `VERIFIED`

## 1. Checkpoint, environment/linkage classification, limitations

Checkpoint: branch `claude/eloquent-mayer-s40hn4`, HEAD `d587445`. No Supabase project, connection string, `supabase/` folder, or database credential of any kind is present in the tracked tree or session environment. No database CLI/status query was run — there is no target to query, and running one against an undeclared/ambient service would violate the "treat any unknown or production-linked database as prohibited" rule. **Database trust classification: `TRUSTED_REPOSITORY_ONLY`** (no live database exists to be untrusted; the repository itself contains no schema).

## 2. Migration inventory

Zero migration files exist (`git ls-files | grep -iE '\.sql$'` → none; no `supabase/migrations/` or equivalent directory). No hash/timestamp/purpose/dependency can be recorded because no migration exists. Applied-history comparison is not applicable — there is no environment to have applied anything.

## 3. Destructive/lock/backfill/recovery risk table

Not applicable — empty by construction (no SQL exists).

## 4. Schema/object inventory and canonical-domain mapping

No tables, enums, columns, constraints, indexes, views, functions, triggers, extensions, publications, sequences, storage buckets, auth hooks, or grants exist. No tenant-scoped table, ledger/event structure, audit table, configuration-version table, idempotency-key table, or retention field exists yet.

## 5. Tenant-table, RLS, policy, grant, function, storage, negative-test matrix

| Control | Finding |
|---|---|
| RLS enabled/forced state | N/A — no tables |
| Policies by table/action/role | N/A |
| Tables with no RLS / permissive policy / recursion | N/A |
| Service-role bypass paths | N/A — no service exists |
| `SECURITY DEFINER` functions / mutable `search_path` | N/A |
| Storage-policy gaps | N/A — no storage bucket exists |
| Supreme Admin absolute-CRUD implementation (RPD-022) | Not yet implemented; requirement correctly recorded as *ratified target*, not fact, in `AGENTS.md`/`CARGOGRID_CONTEXT.md` |

## 6. Index/FK/constraint/concurrency/idempotency findings

None — no schema exists.

## 7. Audit/ledger/finance/retention findings with Supreme Admin disclosure

No audit, ledger, or retention mechanism is implemented. The ratified exception (RPD-022: Supreme Admin has absolute CRUD, including over audit/ledger/final records, and this must never be described as tamper-proof) is accurately and consistently recorded in `AGENTS.md` §"Supreme Admin risk rule" and `KNOWN_ISSUES.md` §1 (RPD-022 row). No document was found overstating tamper-proof/immutability guarantees.

## 8. PostGIS, queue, reporting/search, file-scan, API credential foundations

| Foundation | Ratified target | Implementation evidence |
|---|---|---|
| PostGIS | From Platform Core (`CARGOGRID_CONTEXT.md` §3) | none |
| PostgreSQL durable queue | First, before worker separation | none |
| Live-OLTP dashboard reads | Read-only, budgeted, timeout, paginated, cached | none |
| Upload malware scanning | Every upload scanned before release to another user | none |
| API credential storage | Server-only, never in source/fixtures/logs/client bundle | none (no credential exists yet) |

All `none` — expected for greenfield; classification only, no object created.

## 9. Generated-type/data-access/schema-contract drift findings

Not applicable — no generated types, ORM client, PostgREST/GraphQL layer, or server action exists to drift from a schema that also does not exist.

## 10. Seed/fixture/dump safety inventory

`git ls-files | grep -iE '(seed|fixture|dump|backfill)'` → no matches. No seed/fixture/dump/backfill script of any kind is tracked. No real-tenant/PII/finance/payroll/banking indicator was found (consistent with `docs/discovery/01_REPOSITORY_INVENTORY.md` §7).

## 11. Database trust classification

**`TRUSTED_REPOSITORY_ONLY`** — the repository contains no database artifacts to distrust, and no live/linked database was contacted or assumed. This classification must be re-evaluated the moment any `supabase/` config, migration, or connection reference is introduced (Phase 0 / Database Schema Workstream, Prompt 40).

## 12. Blockers, follow-ups, evidence appendix, output hash

- No blocker. Follow-up: Phase 0 must establish `supabase/` project linkage, initial migration, and RLS-by-default policy before any tenant-scoped table is created (per `AGENTS.md` "Database and migration rules").
- Evidence: `git ls-files | grep -iE '\.sql$|supabase|migrations'` → no matches (command run this task, exit 0/no-match).
- Output hash: `docs/discovery/04_DATABASE_MIGRATION_BASELINE.sha256`.

## Acceptance / Definition of Done

- Every migration/schema source inventoried or explicitly blocked (none exist → empty inventory is the finding). ✔
- Tenant/RLS/grant/function/storage coverage mapped without exploitation (all N/A, correctly stated). ✔
- Applied-history/drift confidence explicit (`TRUSTED_REPOSITORY_ONLY`, no live target). ✔
- No database/migration/generated-type/seed/config/lockfile/external-state change occurred. ✔

## Completion report

- **Migration count/hash status:** 0 migrations.
- **Database trust:** `TRUSTED_REPOSITORY_ONLY`.
- **Schema/RLS gaps:** total (nothing implemented yet); not a defect at greenfield.
- **Critical risks:** none new.
- **Commands/results:** read-only name-pattern searches only, all exit 0/no-match.
- **Files written:** `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` (+ sha256).
- **Limitations:** no live database exists to inspect further.
- **Next eligible prompt:** `CG-S2-DISC-005` — Route and Module Inventory.
