# Deployment and migration re-run guard — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 15 (`HDN-383`/`HDN-384`, Prompts 383/384 Backup and Restore / Disaster Recovery Rehearsal — facts first live-verified there; consolidated as a dedicated runbook at `HDN-388`, Prompt 388 Documentation Handoff)
**Severity class:** Not incident-shaped — this is a **standing constraint reference**, consulted before any migration replay, teardown, or re-run cycle, not a trigger-driven response. §1 below is read as "what makes this relevant," not an alert.

> **This runbook's job is narrow and deliberate.** `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §13's own carry-forward table names three migration/deployment facts and says "state this explicitly in the deployment runbook" — before this checkpoint, that statement existed only as prose buried inside `docs/runbooks/database-restore.md` §3, with no dedicated home. This file is now that dedicated home for the re-run-guard statement itself. It does **not** duplicate the fuller restore/rehearsal procedures — for the actual step-by-step teardown/restore mechanics, read `docs/runbooks/database-restore.md` (schema/row-level backup and restore, with real measured timings) and `docs/runbooks/data-migration-rehearsal.md` (the Import/Export Job Framework rehearsal, `HDN-385`'s own deliverable) instead.

## 1. Symptom / trigger

Consult this runbook before: replaying migrations against a target that already has some migrations applied, tearing down and rebuilding a database (disposable or otherwise), or planning any deployment step that assumes a migration or a schema reset is safely re-runnable. It is also the canonical citation target for any other runbook or document that needs to state these constraints rather than re-deriving or re-quoting them.

## 2. Impact

Getting any of the three facts below wrong does not "usually still work" — each one fails in a specific, previously-live-reproduced way (a duplicate-key error, an `out of shared memory` error, or a silent partial state), documented exactly in `docs/runbooks/database-restore.md` §3/§4's own live drills. This runbook exists so those three facts are found by name, not rediscovered by hitting the failure.

## 3. Diagnosis steps — the three re-run-guard facts, and their real source

**1. Migrations are NOT idempotent — `supabase_migrations.schema_migrations` is the only re-run guard.** Every migration in `supabase/migrations/*.sql` uses a bare `create table`/`create function`/etc., not `create table if not exists` or an equivalent idempotent form, and no migration is wrapped in its own transaction. Quoted exactly from the two places this fact is already established in this repository:

   - `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §13's carry-forward table: *"**Migrations are not idempotent** — bare `create table`, no transaction wrapper" → "`supabase_migrations.schema_migrations` is the **only** re-run guard. State this explicitly in the deployment runbook."*
   - `docs/runbooks/database-restore.md` §3 item 3: *"**Migrations are not idempotent** (`HARDENING_MATRIX.md` §14 item 2, unchanged) — `supabase_migrations.schema_migrations` is the only re-run guard."*

   **Practical consequence**: replaying a migration file against a target that has already applied it (outside the normal Supabase migration-tracking flow, e.g. a manual `psql -f` invocation) will fail on the first `create table`/`create function` collision, not silently no-op. The `schema_migrations` table (populated by the normal Supabase CLI / migration-runner flow) is what prevents a tracked migration from being replayed a second time through that flow — there is no in-SQL idempotency of any kind to fall back on if that tracking is bypassed.

**2. Teardown must batch `DROP SCHEMA app CASCADE` per transaction — a single-transaction drop fails at scale.** Quoted from `00_EXECUTION_INDEX.md` §13: *"**Teardown must batch `drop schema app cascade` per transaction** — `53200: out of shared memory` at ~1,400 objects" → "The statement is atomic and rolls back cleanly, so nothing corrupts — but any teardown drops in batches, each in its own transaction. Belongs in the DR runbook."* Live-reproduced and quantified at `HDN-383` (`docs/runbooks/database-restore.md` §3 item 3): the ~1,400-object figure is now stale and understated — a live schema census found 603 tables, 2,149 indexes, 4,636 constraints, 2,701 functions, 305 triggers, 37 views, 1 materialized view, 448 RLS policies (tables+indexes+views+matviews+sequences+triggers alone already total 3,098). `DROP SCHEMA app CASCADE` in one transaction reproduces `ERROR: 53200: out of shared memory` identically today, rolling back cleanly (nothing corrupts — the statement is atomic). The working, live-tested batching strategy: order all tables by **ascending inbound-FK count** (leaves first, `app.tenants` last), issue one `DROP TABLE IF EXISTS ... CASCADE;` per table as a separate auto-committed statement, then a final `DROP SCHEMA app CASCADE` sweep for remaining free-standing objects — measured **1.96s, 0 errors**. Full procedural detail, including the interrupted-teardown resume procedure and circular-FK handling, is in `docs/runbooks/database-restore.md` §3 item 3 — this entry states the constraint and its citation, not the full mechanics.

**3. `auth.users` survives an `app`-schema reset and reruns collide on `users_pkey`.** Quoted from `00_EXECUTION_INDEX.md` §13: *"**`auth.users` survives a schema reset** — It is Supabase's schema, untouched by dropping `app`. Any live test cycle must clear it in teardown or every rerun collides on `users_pkey`."* Live-reproduced exactly at `HDN-383` (`docs/runbooks/database-restore.md` §3 item 3): after a batched `app`-only teardown (schema `app` fully removed, `auth` untouched) and a full migration replay, re-inserting the same `auth.users` id/email fails with `ERROR: duplicate key value violates unique constraint "users_pkey"`. Any restore/rerun cycle must explicitly clear colliding `auth.users` rows in teardown, **before** replaying migrations, not after.

## 4. Resolution steps

1. Before any migration replay against a possibly-already-migrated target: confirm `supabase_migrations.schema_migrations`' own state for that target rather than assuming a fresh database. There is no other guard.
2. Before any full-schema teardown: use the ascending-inbound-FK-count, per-table, auto-committed batching strategy (§3 item 2) — never a single-transaction `DROP SCHEMA app CASCADE` against a schema at or near current scale.
3. Before replaying migrations after a teardown that is meant to fully reset state: explicitly clear colliding `auth.users` rows first (§3 item 3) — migration replay alone will not do this, since `auth` is untouched by an `app`-only teardown.
4. For the full composed restore procedure that applies all three of the above together (plus the additional `TRUNCATE`/materialized-view-refresh/target-role steps a real in-place restore also needs), follow `docs/runbooks/database-restore.md` §4 item 4 — do not re-derive a shorter version here.
5. For a rehearsed, end-to-end data-migration/import cycle (as opposed to a schema teardown/restore), follow `docs/runbooks/data-migration-rehearsal.md` instead — a different mechanism (the Import/Export Job Framework) with its own real rehearsal evidence.

Rollback procedure if any step above fails mid-way: per §3 item 2, an interrupted batched teardown is safe to resume by re-running the entire per-table batch script from scratch (every statement is `IF EXISTS`, so already-dropped tables are free no-ops), then the final sweep — live-verified at `database-restore.md` §3 item 3. Never leave a partially-torn-down `app` schema serving traffic.

## 5. Communication

None beyond the normal DevOps/on-call channel for any deployment-adjacent action — this runbook records a standing constraint, not an incident.

## 6. Post-incident

Not applicable in the incident sense — if a real deployment or migration event needed this runbook, record which of the three constraints applied and whether the resolution steps in §4 were followed, cross-referencing `docs/runbooks/database-restore.md` §6/§7 if the event was a restore.

## 7. Rehearsal history

| Date | Type | Outcome | Evidence |
|---|---|---|---|
| 2026-08-24 (`HDN-383`) | Live rehearsal — teardown-batching strategy | **PASS**, 1.96s, 0 errors, live-tested against a real circular-FK pair with no defect | `docs/runbooks/database-restore.md` §3 item 3; `docs/build-log/full-system-hardening/HDN-383.md` |
| 2026-08-24 (`HDN-383`) | Live reproduction — `auth.users`/`users_pkey` collision | **Reproduced exactly as documented** | `docs/runbooks/database-restore.md` §3 item 3; `docs/build-log/full-system-hardening/HDN-383.md` |
| 2026-08-24 (`HDN-384`) | Live reproduction — interrupted-teardown resume, single-transaction `DROP SCHEMA` failure | **Reproduced identically (`53200: out of shared memory`), clean rollback confirmed** | `docs/runbooks/disaster-recovery.md` §4 item 3; `docs/runbooks/database-restore.md` §3 item 3 |

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-24 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `HDN-388` (Step 15 Full-System-Hardening, Documentation Handoff), consolidating the three re-run-guard facts `00_EXECUTION_INDEX.md` §13 names into a single dedicated home, per that section's own instruction ("state this explicitly in the deployment runbook") — previously these facts existed only inside `docs/runbooks/database-restore.md` §3's own prose. No new live verification performed by this checkpoint; every fact and figure above is quoted or directly reproduced from an already-existing, previously-live-verified source, cited inline. | Claude Code (runtime build agent) |
