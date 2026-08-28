# Deployment Rollback — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** Support, DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps/SRE (Infrastructure-escalation tier, `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4)
**Since:** Step 16 (`CG-S16-RGL-017`, Prompt 407, Rollback Decision)
**Severity class:** Aligned to the incident that triggers it — a rollback itself is not a severity level; see §1

> A runbook describes a real, previously-observed or deliberately-rehearsed operational scenario.
> **This one is deliberately honest about what has and has not been rehearsed**: the application
> code (Vercel) rollback mechanism is confirmed live and available (§4.1, verified 2026-08-28 —
> a real `isRollbackCandidate: true` prior deployment exists in the project's own deployment
> history right now), but no end-to-end rollback has ever actually been *executed* against this
> project — marked `NOT_YET_REHEARSED` in §7, not fabricated as tested.

## 0. Why this file exists

`docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.5 named `deployment-rollback.md` in its own
Phase-0 planning catalogue of 9 runbooks. `ISS-2026-262` (found at `HDN-384`, `RESOLVED` at
`HDN-388`) confirmed the file was never authored — the underlying doctrine existed only as prose
reproduced across `docs/architecture/10_TESTING_WORKSTREAM.md` §10.2 and
`11_DEVOPS_WORKSTREAM.md` §4.4/§8.3, both themselves reproducing Tech Arch §28.3 and Blueprint
§24.5/§26.2/§26.3 verbatim, with no single operational document a support/on-call engineer could
open during an actual incident. This file closes that gap for the deployment/cutover-rollback
case specifically (the file `11_*.md` §8.5 named `deployment-rollback.md` for). It does **not**
re-author any policy — every rule below is reproduced by reference from an already-ratified
source, cited at each step, per this repository's own "one rollback procedure, not two
independently-authored ones that could drift" discipline (`11_*.md` §4.4).

**Scope boundary, explicit**: this file covers rolling back a **bad application/infrastructure
deployment** (a Vercel build, a schema migration, a configuration change) — the layers named in
Tech Arch §28.3's own per-layer table (§1 below). It does **not** cover restoring from a database
disaster (`docs/runbooks/database-restore.md`), a business-transaction correction (never a
destructive data rollback — §1's own Data row), or a security incident's own containment steps
(`docs/runbooks/incident-response.md`) — those are distinct runbooks for distinct trigger shapes,
cross-referenced where they intersect, not duplicated here. `migration-rollback.md` and
`cutover-rollback.md`, the other two files `11_*.md` §8.5 named, remain genuinely unbuilt under
their own names as of this checkpoint — their own distinct procedures (§8.3 below) are
consolidated into this file instead, since in practice a CargoGrid deploy always bundles an
application build with zero or more additive migrations in the same release candidate, and a real
rollback decision has to reason about both together, not as two separate documents a responder
has to cross-reference under time pressure.

## 1. Symptom / trigger

A rollback is considered — not automatically executed — when any of the following hold, reproduced
verbatim from Tech Arch §28.3's per-layer table (`11_*.md` §4.4) and Blueprint §26.2's
rollback-consideration list (`10_*.md` §10.2):

| Layer | Trigger shape | Rollback action |
|---|---|---|
| Frontend | A deployed build serves a broken UI, a client-side crash loop, or a regression a smoke test should have caught but didn't | Re-deploy the previous known-good Vercel build (§4.1) |
| API | A REST/GraphQL/webhook contract change breaks an existing consumer outside its own approved deprecation window (`08_*.md` §11) | Revert to the previous versioned endpoint/deploy |
| DB schema | A migration is live-broken (wrong constraint, a function regression, a lost grant) | **Forward-fix preferred** — a new corrective migration, never editing the applied one (`AGENTS.md`). A down-migration is used only if verified safe (§4.2) |
| Config | A `07_*.md` §10 config-version change produces wrong behavior | Config rollback via version — the config-version model is itself the rollback mechanism, no separate tool |
| Feature | A specific capability behind a feature flag misbehaves | Disable the flag — the fastest, most targeted layer to roll back, since it needs no redeploy |
| Data | Tenant data was corrupted by a bad deploy | **Restore only for genuine disaster** (`database-restore.md`); a routine bad-posting/business-transaction error gets a business correction, never a destructive data rollback (Tech Arch §28.3, verbatim — this row is a hard constraint, not a preference) |

**Not every failure triggers every layer.** A responder identifies which layer(s) actually broke
(§3) before acting — rolling back the Frontend layer for a pure DB-schema regression wastes the
one thing a P1 incident cannot afford (Blueprint §30.2's 15-minute response clock), and reaching
for the Data row when a Config rollback would have sufficed violates the "never a destructive data
rollback for a routine posting error" constraint outright.

## 2. Impact

Same classification Blueprint §30.2 already uses for every incident (`11_*.md` §8.4, verbatim):
P1 Critical (production down, tenant leak, financial corruption, severe security issue) — 15-minute
response, continuous work until mitigation, RCA required, status every 30-60 min; P2 High — 1-hour
response; P3 Medium — 4-business-hour response; P4 Low — 1-business-day response. A deployment
rollback is almost always a P1/P2-triggering event by construction (it means a release already
reached Production and is now suspected bad) — classify using the actual blast radius (one tenant,
all tenants, one module, data integrity) established during diagnosis (§3), not the mere fact that
a rollback is being considered.

**Tenant-isolation/financial-integrity implications**: a Frontend/API/Config/Feature rollback is
tenant-symmetric (every tenant reverts together, since CargoGrid has no per-tenant deploy
target). A DB-schema forward-fix is likewise tenant-symmetric. The Data row is the one layer where
tenant-scoping matters most acutely — restoring one tenant's data from a shared-database backup
without disturbing every other tenant's post-backup writes is the exact hard problem
`database-restore.md` §3/§4 already documents in full; this file does not re-derive it.

## 3. Diagnosis steps

1. Confirm the report against real signals before acting — `on-call-ownership.md`'s own alert
   catalogue (job dead-letter, webhook signature failures) plus `11_*.md` §6.1's 11 dashboards
   and 8 named alerts (API p95 latency, error rate, DB CPU/connection saturation, slow query,
   queue backlog, webhook failure, cross-tenant policy test failure, storage signed-URL anomaly).
   Live-pull the actual signal: for this project, `mcp__Vercel__get_runtime_errors` (grouped error
   clusters, since/until window) and `mcp__Vercel__get_runtime_logs` (raw request logs, filterable
   by status code/route/level) — both verified reachable and functioning during this runbook's own
   authoring (2026-08-28: zero runtime errors in the trailing 24h against the then-current
   production deployment).
2. Identify which release introduced the regression. `mcp__Vercel__list_deployments` (this
   project: `prj_9ND1BsfbppHiqeKrSEldYh8xbC68`, team `team_jYIRP8E0gAnewOGS5H7yD3BL`) returns every
   deployment with its `target`, `state`, `githubCommitSha`, and — critically — an
   `isRollbackCandidate` flag Vercel itself computes; the immediately-prior `target: "production"`
   deployment with `isRollbackCandidate: true` is the default rollback target unless diagnosis
   (step 3) points further back.
3. Map the regression to a §1 layer. Cross-check `docs/runtime/CHANGE_MANIFEST.md` for what the
   suspect release actually touched (migrations, contracts, config, feature flags) — a release
   that touched only `app/`/`server/` TypeScript is a pure Frontend/API-layer question; a release
   that applied a migration (`docs/runtime/CHANGE_MANIFEST.md`'s own `Migration` field, cross-
   referenced against `supabase/migrations/`) requires the DB-schema row's own forward-fix-first
   reasoning (§4.2), never a same-only-Frontend rollback that leaves a live schema mismatch behind.
4. Confirm scope: one tenant, a subset, or all tenants (`X-CargoGrid-Request-Id`/`correlation_id`,
   `11_*.md` §6.2 — every dashboard supports a `tenant_id` filter). A single-tenant-scoped symptom
   is rarely a deployment-rollback case at all (CargoGrid has no per-tenant deploy target) — it is
   more likely a data or entitlement issue within that tenant, redirect to the appropriate
   domain runbook instead of rolling back a release that is working correctly for every other
   tenant.

## 4. Resolution steps

### 4.1 Frontend/API layer — Vercel application rollback

CargoGrid's Vercel project auto-deploys `main` to Production on every merge (`RGL-BLK-001`,
accepted risk — `docs/build-log/release-go-live/BLOCKER_LEDGER.md`). Two real, verified
mechanisms exist, in order of preference:

1. **Vercel instant rollback** (the fast path, no rebuild). Every `target: "production"`
   deployment carries `isRollbackCandidate: true`/`false`; promoting a prior `READY` production
   deployment back to the alias (`cargogrid-app.vercel.app`) is a Vercel platform operation, not a
   git operation — it does **not** create a new commit, does **not** revert `main`, and takes
   effect in seconds. This is the correct first response for a Frontend/API-layer-only
   regression with no accompanying schema change (§4.2 governs when a schema change is also
   involved).
2. **Git revert + redeploy** (when the bad commit must also stop being `main`'s own HEAD, e.g. to
   prevent a second, unrelated merge from re-introducing the regression). `git revert
   <bad-commit>` on `main`, pushed normally — never `git reset --hard`/force-push on shared
   history (`AGENTS.md`) — triggers a fresh Vercel Production deploy of the reverted state. Slower
   than instant rollback (a full build), but leaves `main` itself consistent with what is actually
   running.

**A Vercel rollback alone never touches the Supabase database.** If the release also applied a
migration, §4.2 governs before or alongside this step — an instant Vercel rollback that leaves a
newer schema in place can itself break the reverted (older) application code if that code assumed
the pre-migration schema shape. Confirm compatibility (does the older code still function against
the current schema?) before relying on Vercel rollback alone; if not, forward-fix the schema
issue first (§4.2), or accept a short, communicated (§5) outage window while both layers are
brought back into a mutually-compatible state.

### 4.2 DB schema layer — forward-fix preferred, down-migration only if safe

Reproduces Tech Arch §28.3's DB-schema row exactly, applied to this repository's own migration
discipline (`AGENTS.md`: "Never edit an applied migration; add a new migration"):

1. **Default: forward-fix.** Author a new, additive `supabase/migrations/<timestamp>_harden_*.sql`
   correcting the defect — this is the pattern every `harden_*.sql` migration in this repository's
   own history already follows (see any `RGL-404.md` §12 entry for the established shape: root
   cause, `CREATE OR REPLACE` against the true latest body, live-verified grants, a regression
   test). Apply via the same `apply_migration` mechanism and the same live-verification discipline
   (grants, security mode, `get_advisors`) as any other migration — a rollback-triggered migration
   is not exempt from the ordinary quality bar.
2. **Down-migration only if independently verified safe.** A destructive `DROP`/reverse-migration
   is authorized only when (a) no tenant has written data depending on the new shape since it
   applied, confirmed by a live row-count/timestamp check, not assumed, and (b) the reversal
   itself is tested against a fresh disposable database before being applied live, exactly like
   any other migration. This is rarely the right choice for a schema already serving live traffic
   — forward-fix almost always wins in practice, which is why it is listed first, not merely
   alphabetically.
3. Never a bare `supabase db push`/replay-based "undo" — this repository's own `ISS-2026-300`
   finding (migration-ledger version drift on this exact hosted project) is a live, disclosed
   example of why blind ledger-based replay tooling is unsafe here without first reconciling the
   ledger; a rollback under incident pressure is the worst time to discover that gap.

### 4.3 Config and Feature layers

Config: revert to the prior config version (`07_*.md` §10's model) — the version history is
itself the rollback mechanism, no separate backup/restore tool. Feature: disable the responsible
feature flag — the fastest single action available, since it requires no redeploy and no schema
change, and should be the **first** action taken for any regression traced to a specific,
flag-gated capability, ahead of a full Frontend/API rollback.

### 4.4 Data layer

**Never a destructive rollback for a routine error.** A business-transaction posting error gets a
business correction (a new, correctly-signed reversing/correcting transaction) — the same
discipline RPD-022 already establishes for financial/audit records generally ("CargoGrid must
never claim audit or financial records are immutable... only that an audit trail exists"). Data
restoration is reserved for genuine disaster and is `database-restore.md`'s own scope, not
re-derived here — follow that runbook directly if this is the actual scenario.

## 5. Communication

Reproduces Blueprint §26.3's cutover-rollback procedure and §30.3's incident flow (`11_*.md`
§8.3/§8.4, verbatim structure): stop/freeze the affected access path if the regression is
actively harmful → **communicate status** (parallel to the fix/workaround work, never
sequenced after it) → validate the rollback resolved the symptom → communicate resolution.
Use the same 12-field incident record Blueprint §30.4 already specifies (Incident ID, Tenant,
Module, Severity, Impact, Start time, Owner/Incident Commander, Status, Root cause, Workaround,
Resolution, RCA, Preventive action) — a rollback does not get a separate, lighter-weight record;
it is tracked exactly like any other P1/P2 incident it was triggered by.

## 6. Post-incident

**RCA is mandatory, no exception** — "production rollback" is one of the six explicitly-named
mandatory-RCA triggers in Blueprint §30.5 (`11_*.md` §8.4), alongside P1, security incident,
tenant-isolation failure, financial posting/data corruption, and major data-migration failure.
Capture: which layer(s) actually rolled back, the true root cause (not merely "the new deploy"),
whether the forward-fix-vs-down-migration choice (§4.2) was correct in hindsight, and a preventive
action that would have caught the regression before Production (a missing smoke-test case, a gap
in the release freeze digest's own coverage, an untested migration edge case). File the RCA and
the resulting preventive action as a new `docs/runtime/KNOWN_ISSUES.md` entry if the root cause is
a genuine, previously-undisclosed gap — matching this repository's own standing discipline that a
real defect found during operations gets tracked the same way one found during development does.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-28 | `NOT_YET_REHEARSED` — mechanism verified, not exercised | The Vercel instant-rollback mechanism was confirmed live and available (a real `isRollbackCandidate: true` prior production deployment existed for this project at authoring time) and production was confirmed healthy (0 runtime errors in the trailing 24h via `get_runtime_errors`, `/api/health`/`/api/ready` both `200`, `get_advisors` security sweep showing only the pre-existing, already-accepted `spatial_ref_sys` finding) — **no rollback was indicated or executed**. This is a decision record (`RGL-407`), not a rehearsal. | `docs/build-log/release-go-live/RGL-407.md` |

**No end-to-end rollback (Vercel instant-rollback promotion, a forward-fix migration under
simulated incident conditions, or a full cutover-rollback drill) has ever actually been executed
against this project.** Per `10_*.md` §7.4/`11_*.md` §8.2's own quarterly recovery-testing cadence
(`ADR-CAND-ARCH-023`), a config-rollback test and an incident-runbook test are both named,
required rehearsal items — this file's own procedure should be exercised at the next scheduled
DR-rehearsal cycle, not left as a paper-only doctrine indefinitely. Marked here honestly rather
than fabricated as tested, matching this repository's own "do not author a runbook for a
hypothetical incident with no rehearsal evidence" discipline (this template's own header note) —
the procedure itself is real (every step reproduces an already-ratified, cited source), only its
live execution is not yet evidenced.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-28 | `0.1.0` | Initial — authored at `RGL-407` (Prompt 407, Rollback Decision), closing the `deployment-rollback.md` half of `ISS-2026-262`'s own disclosed gap (the other 5 named-but-unbuilt files — `migration-rollback.md`/`cutover-rollback.md` consolidated into this one per §0's own scope note; `tenant-isolation-failure.md`, `webhook-endpoint-recovery.md`, `job-dlq-requeue.md` remain genuinely unbuilt, unchanged disposition, out of this checkpoint's own narrower Rollback Decision charter). | Claude Code |
