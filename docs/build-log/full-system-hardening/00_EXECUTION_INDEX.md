# Step 15 (Full-System Hardening) — Execution Index

**Prompt:** `CG-S15-HDN-001` (369, Full-System Hardening WBS Runtime Kickoff)
**Runtime output of:** `docs/ai-agent-build-prompt-package/15-hardening/369_FULL_SYSTEM_HARDENING_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Package document:** `CG-AABPP-HDN-369`, package version `0.16.0`
**Runtime state set by this checkpoint:** `FULL_SYSTEM_HARDENING_IN_PROGRESS`
**Owner (every row, this build's standing convention):** Claude Code (runtime build agent)
**Short code:** `HDN` (per every Step 15 prompt file's own self-declared `CG-S15-HDN-*` ID)

> **This file is the resume contract.** It, not any operator message, routes the next
> session. A session that disagrees with a row here must correct the row, with evidence,
> before acting on the disagreement.

---

## 1. Naming — two numbering schemes, deliberately not merged

| Scheme | Form | Meaning |
|---|---|---|
| Lane / build log | `HDN-369` … `HDN-389` | **The prompt number.** Fixed by each prompt file's own `Runtime build log:` line — e.g. `370_FULL_REGRESSION_PROMPT.md` names `HDN-370.md` in this directory. |
| Task ledger ID | `CG-S15-HDN-001` … `CG-S15-HDN-021` | **The sequential task number.** Fixed by each prompt file's own §1. |

`HDN-370` and `CG-S15-HDN-002` are the same task. Both are used below because both are
fixed by the package and neither can be renamed. No third scheme is introduced.

---

## 2. Checkpoint freeze (Prompt 369 step 1)

| Field | Value |
|---|---|
| Repository root | `/home/user/cargogrid.app` |
| Branch | `claude/step-15-hdn-369-kickoff-w6qren` |
| HEAD at session start (this checkpoint's base) | `e5da061866b3c90f434d0967fd9a4aa46b60773e` — merge of PR #65, `claude/supabase-cargogrid-migration-10qvt8` |
| Worktree at session start | clean (`git status --short` empty before this checkpoint's first file was written) |
| Checkpoint date | 2026-08-23 (**Sunday** — see §9, this matters for the fixture-flake class) |
| Package manager / runtime | `pnpm@10.33.0`, `node@v22.22.2`. `node_modules` did **not** exist at session start; `pnpm install --frozen-lockfile` this checkpoint (sandbox provisioning, not a repository change) |
| Local database | PostgreSQL 16.13 (Ubuntu). Not running at session start; `service postgresql start`, `apt-get install postgresql-16-postgis-3`, and a one-time local `postgres` role password matching `scripts/db-tests/run.sh`'s documented default were all required as sandbox provisioning |
| Migration files | **306** under `supabase/migrations/`, latest `20260809200000_harden_intelligence_iae039_closure_step_up_wiring.sql` |
| Live database | **`cargogrid.app` (`awdlicmwzdxquopwtcfd`), ap-northeast-1, PostgreSQL 17.6 — provisioned and fully migrated.** All 306 migrations applied cleanly; `supabase_migrations.schema_migrations` holds 306 rows in sync with `supabase/migrations/`. 603 tables, ~2,900 routines, 38 views, 17 types; RLS enabled on 568 tables, 448 policies. Evidence: `docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` |
| Schema state | `app` is **not** exposed through the Data API (`db_schema = public,graphql_public`), so no `app` table is reachable over PostgREST regardless of its RLS state |
| Feature flags | No runtime feature-flag service exists in this repository. Behaviour is gated by database configuration rows (per-tenant config, effective-dated), not by flags — so "flag state" is not a freezable axis here, and is recorded as *absent* rather than left implicit |
| Deployed environment | **None.** No Vercel deployment, no CI-driven deploy pipeline, no real sign-in flow. The live Supabase project is a migrated database, **not** a running system. This distinction governs every Step 15 gate that needs a live application (see §10) |
| Phase 0–9 status | `PHASE_0_VERIFIED` … `PHASE_9_VERIFIED` all set |
| Step 16/17 | `NOT_STARTED`, and out of scope for every prompt in this range (§12) |

### 2.1 State freeze correction — the "no live Supabase project" claim is stale

Prompt 369 step 1 freezes "database/schema state, migration state". That baseline changed
at PR #65 and the repository still asserted the old one in a load-bearing place. Corrected
this checkpoint rather than left to drift:

| Locus | Finding | Action |
|---|---|---|
| `scripts/db-tests/fixtures/auth-schema-stub.sql` | Header asserted "This repository has no live Supabase project yet (ADR-0010, PH0-094; still true as of PLT-107)". **Stale on both counts** | **Corrected.** Now states the live project exists and is fully migrated, records why the fixture is still required (a disposable bare Postgres has no Supabase-managed `auth` schema), and records that the ADR-0010/PH0-094 citation was itself wrong |
| `docs/adr/ADR-0010-secret-manager-mechanism.md` | **Carries no such statement.** Read directly and grepped for the claim in every phrasing — zero hits. It ratifies Vercel/Supabase-native secret storage and says nothing about a project existing | **No edit.** Reporting the absence is the honest result; inventing a correction here would be fabricating a defect |
| `docs/build-log/phase-00/PH0-94.md` | **Carries no such statement.** Same check, zero hits | **No edit**, same reasoning |
| `scripts/db-tests/lib/setup-disposable-db.sh` | **Already corrected** at `cdbccc7`. Its header now documents mirroring Supabase's database-level `search_path` and cites the live-migration report | **No edit needed** — verified by direct read, not assumed |
| `docs/runtime/CARGOGRID_BUILD_STATUS.md` "Latest environment verified" row | Asserted "no live Supabase project exists yet either" as **current** state | **Corrected** this checkpoint |

**Deliberately not touched:** historical build-log, ledger, handoff and error-ledger entries
that said "no live Supabase project" *at the checkpoint they describe*. Those are accurate
historical records; rewriting them would corrupt the evidence trail
(`docs/runtime/` is append-only by `AGENTS.md`). Only assertions about **current** state
were corrected. `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`'s "greenfield" language
is likewise a Phase 0 snapshot and stays.

### 2.2 Root-cause fixes already landed — the CI-mirrors-hosted property

Four defect classes were fixed at the root, not the call site, before this checkpoint
(`75278d3`, `11bd409`, `d82cd6f`, `cdbccc7`). Each fix exists so **CI can catch the class
itself**:

| # | Defect | Root fix | The property it establishes |
|---|---|---|---|
| 1 | pgcrypto resolved from the wrong schema (20 functions broken only at call time) | pgcrypto installed into `extensions` explicitly, schema created first so CI matches the hosted layout; `extensions` added to 39 functions' pinned search_path across 22 migrations | CI's extension layout mirrors hosted |
| 2 | Unpinned functions inherit the **caller's** search_path, not the session default | 7 functions pinned `set search_path = app, public, extensions, pg_temp` | Also closes the mutable-search_path advisory on those 7 |
| 3 | `auth.users.email` is `varchar(255)`, not `text` | 4 call sites cast `::text`; the stub's column types corrected | CI's `auth.users` shape mirrors hosted |
| 4 | 157 RLS policies re-evaluating `auth.uid()` per row | `auth.uid()` → `(select auth.uid())` at 228 call sites in 171 policy statements across 65 migrations | InitPlan, evaluated once per statement |

Plus the mirror-image fix: `setup-disposable-db.sh` now sets the database-level
`search_path` of `"$user", public, extensions` that Supabase sets and a stock Postgres does
not.

> **Standing constraint on every Step 15 lane.** The CI-mirrors-hosted property must be
> preserved **in both directions** — extension schema *and* database-level `search_path`. A
> hardening change that reintroduces that divergence re-blinds CI to the exact class the
> live migration exposed. This is not advice; it is a review item for every lane's Tier B
> walk, and is repeated in `HARDENING_MATRIX.md` as a cross-cutting row.

---

## 3. Runtime entry verdict — **PASS**

Prompt 369's entry gate requires `PHASE_9_VERIFIED` at the active checkpoint, plus the
executor having read the package manifest, confirmed decision register, source matrix,
conflict register, coverage matrix and Step 14 closure evidence — or the task stops with
`FULL_SYSTEM_HARDENING_BLOCKED`.

- **`PHASE_9_VERIFIED`: set.** Verified this checkpoint by direct read, not re-citation:
  - `docs/runtime/TASK_LEDGER.md` — `CG-S14-IAE-039` row, status `VERIFIED — sets PHASE_9_VERIFIED`, dated 2026-08-22.
  - `docs/runtime/CARGOGRID_BUILD_STATUS.md` — phase table row 9, `VERIFIED (PHASE_9_VERIFIED, closed 2026-08-22)`, 39/39 WBS rows.
  - `docs/runtime/HANDOFF.md` — run-status line and latest-checkpoint blockquote, both stating `PHASE_9_VERIFIED` set at `CG-S14-IAE-039`/Prompt 367.
- **Exact Step 14 closure artifact (recorded here as Prompt 369 requires):**
  **`docs/build-log/phase-09/INTELLIGENCE_ENTERPRISE_CLOSURE_REPORT.md`**, produced by
  `CG-S14-IAE-039` (Prompt 367, Closure Verification), 2026-08-22, on branch
  `claude/execute-prompt-349-368-zi0nqs`, merged to `main`. Index reference:
  `docs/build-log/phase-09/00_EXECUTION_INDEX.md` §21.
- **Phase 9's own disclosed closure exception, carried into Step 15 open-eyed:** Phase 9
  closed with **one unresolved High** (`ISS-2026-150`, IP-restriction wiring) explicitly
  ruled a first-of-its-kind accepted exception, whose named remedy **is Step 15**. It is
  seeded into `HDN-378`'s lane below and into `BLOCKER_LEDGER.md`. It must not be deferred
  again.
- **Registers read this checkpoint:** `00-control/02_CONFIRMED_DECISION_REGISTER.md`,
  `03_ASSUMPTION_REGISTER.md`, `04_CONFLICT_REGISTER.md`,
  `05_REQUIREMENT_COVERAGE_MATRIX.md`, `07_PROMPT_PACKAGE_MANIFEST.md`, plus all seven
  `docs/runtime/` context files and `docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md`.
- **Pre-flight collision check (`ISS-2026-002`, mandatory per `AGENTS.md`):**
  `mcp__github__list_pull_requests` (state=open) on `assujiar/cargogrid.app` → **zero open
  PRs**. `mcp__github__list_branches` → **46 branches**, none other than this session's own
  `claude/step-15-hdn-369-kickoff-w6qren` names or references the 368–389 prompt range,
  `step-15`, or `hardening`. No parallel-session collision risk.
- No `FULL_SYSTEM_HARDENING_BLOCKED` condition found.

**Verdict: entry gate PASSES.** `FULL_SYSTEM_HARDENING_IN_PROGRESS` is set by this
checkpoint. `FULL_SYSTEM_HARDENING_VERIFIED` is explicitly **not** set — only Prompt 389
may set it (§12).

---

## 4. WBS — 21 rows (Prompt 369 step 3)

Prompt 369 step 3 says "Build WBS tasks for Prompts 370–388 and mark only dependency-clean
tasks `READY`." Prompt 389 is included as row 21 for completeness — it is the only task
authorized to set the Step 15 completion flag, so omitting it would leave the closure
unrouted.

| # | Lane | Task ID | Prompt | Capability | Workstream | Depends on | State |
|---|---|---|---|---|---|---|---|
| 1 | `HDN-369` | `CG-S15-HDN-001` | 369 | Full-System Hardening WBS Runtime Kickoff | Hardening Governance | `PHASE_9_VERIFIED` | **`COMPLETED`** (this checkpoint; a kickoff is not entered into the `VERIFIED` capability chain — see §11) |
| 2 | `HDN-370` | `CG-S15-HDN-002` | 370 | Full Regression | Regression Assurance | `HDN-369` | **`VERIFIED`** — Tier C close complete (4 lenses, 2 live-proven defects fixed and re-verified, 8-file consistency sweep), independent full gate re-run green. `HDN-BLK-002` closed at the root; `HDN-BLK-007/008/009` opened, deferred to `HDN-387` with explicit interim guidance for the 3 lanes they actually touch |
| 3 | `HDN-371` | `CG-S15-HDN-003` | 371 | Cross-Module Transactional Integrity | Integrity Assurance | `HDN-370` **`VERIFIED`** | **`VERIFIED`** — Tier C closed (4 lenses, 3 High findings fixed — 2 superseded-migration citation errors, 1 false "dependency already satisfied" claim — plus a live-forced-and-confirmed race, corrected function count 9/20 not 7/19, corrected domain breakdown, 1 new Low issue registered). One systemic finding (`HDN-BLK-010`/`ISS-2026-162`, Medium, 9/20 boundary functions missing a race-safe idempotency pattern, deferred to `HDN-374`). See `HDN-371.md` |
| 4 | `HDN-372` | `CG-S15-HDN-004` | 372 | Tenant Isolation Audit | Security Assurance | `HDN-370` **`VERIFIED`** | **`VERIFIED`** — Tier C closed (4 lenses, 1 High finding fixed same checkpoint — 4 more live-forced functions of the identical shape the original 9-function fix missed — plus corrected function/total counts, a corrected test fix, a fabricated-evidence claim replaced with a genuine committed test, and a late-registered High blocker corrected). One High cross-tenant read defect class found and fixed at the root, twice (`HDN-BLK-011`, 13 functions, 24 protected); two same-shape findings deferred to `HDN-373` (`HDN-BLK-012`, 13 dashboard functions; `HDN-BLK-014`, ~24 candidates); one further High registered late and corrected (`HDN-BLK-013`); 13 further Medium/Low findings registered. See `HDN-372.md` |
| 5 | `HDN-373` | `CG-S15-HDN-005` | 373 | RLS and RBAC Audit | Security Assurance | `HDN-372` **`VERIFIED`** **(hard)** | **`VERIFIED`** |
| 6 | `HDN-374` | `CG-S15-HDN-006` | 374 | Financial Integrity Audit | Financial Assurance | `HDN-371` **(hard)** | `READY` |
| 7 | `HDN-375` | `CG-S15-HDN-007` | 375 | Data Lineage Audit | Integrity Assurance | `HDN-371` **(hard)** | `BLOCKED` |
| 8 | `HDN-376` | `CG-S15-HDN-008` | 376 | API Compatibility Audit | API Assurance | `HDN-371` **(hard)** | `BLOCKED` |
| 9 | `HDN-377` | `CG-S15-HDN-009` | 377 | Storage and Signed URL Audit | File Security Assurance | `HDN-372` **`VERIFIED`** | `READY` |
| 10 | `HDN-378` | `CG-S15-HDN-010` | 378 | Security Hardening | Security Assurance | `HDN-372` **(hard)**, `HDN-373..377` | `BLOCKED` |
| 11 | `HDN-379` | `CG-S15-HDN-011` | 379 | Performance and Scalability | Performance Assurance | `HDN-370` | `BLOCKED` |
| 12 | `HDN-380` | `CG-S15-HDN-012` | 380 | Accessibility | UX Assurance | `HDN-370` | `BLOCKED` |
| 13 | `HDN-381` | `CG-S15-HDN-013` | 381 | Browser and Device Compatibility | UX Assurance | `HDN-380` | `BLOCKED` |
| 14 | `HDN-382` | `CG-S15-HDN-014` | 382 | Observability | Reliability Assurance | `HDN-370` | `BLOCKED` |
| 15 | `HDN-383` | `CG-S15-HDN-015` | 383 | Backup and Restore | Reliability Assurance | `HDN-382` | `BLOCKED` |
| 16 | `HDN-384` | `CG-S15-HDN-016` | 384 | Disaster Recovery Rehearsal | Reliability Assurance | `HDN-383` | `BLOCKED` |
| 17 | `HDN-385` | `CG-S15-HDN-017` | 385 | Data Migration Rehearsal | Migration Assurance | `HDN-371` | `BLOCKED` |
| 18 | `HDN-386` | `CG-S15-HDN-018` | 386 | Integrated Verification | Hardening Closure | `HDN-370..385` **all `VERIFIED`** | `BLOCKED` |
| 19 | `HDN-387` | `CG-S15-HDN-019` | 387 | Release Blocker Triage and Remediation | Hardening Closure | `HDN-386` | `BLOCKED` |
| 20 | `HDN-388` | `CG-S15-HDN-020` | 388 | Documentation Handoff | Hardening Closure | `HDN-387` | `BLOCKED` |
| 21 | `HDN-389` | `CG-S15-HDN-021` | 389 | Closure Verification | Hardening Closure | `HDN-388` | `BLOCKED` |

**Tally: 21 rows — 1 `COMPLETED` (kickoff), 14 `BLOCKED`, 4 `VERIFIED` (`HDN-370`,
`HDN-371`, `HDN-372`, `HDN-373`), 2 `READY` (`HDN-374`, `HDN-377`).**

> **`HDN-371` is `VERIFIED`.** Every chain named in its charter is reconciled against live code
> and existing passing evidence, with one honestly disclosed gap (the loyalty/portal chain was
> not examined). One systemic finding (`HDN-BLK-010` / 9 of 20 cross-module boundary functions
> sharing an identical concurrent-idempotency gap, Medium, **live-forced and confirmed** by a
> real two-process race, deferred to `HDN-374`) was registered rather than fixed in-lane, per
> `00_EXECUTION_INDEX.md` §11.2's source-domain ownership rule. **Tier C review (four
> independent lenses) closed clean this same checkpoint** — 3 High findings fixed (two
> superseded-migration citation errors that would have misdirected `HDN-374`'s eventual fix; one
> false claim that `HDN-374`'s upstream dependency was "already satisfied" while `HDN-371` was
> still `COMPLETED`), plus 7 Medium and 9 Low findings fixed or explicitly registered with a
> named owner. Full disposition: `HDN-371.md` §12.1.

> **`HDN-372` is `VERIFIED`.** Four independent parallel adversarial investigations
> (DB/RLS/grants; API/service layer; storage/jobs/cache/reports; support/AI/webhooks/
> audit), each with its own live two-tenant fixture, found and **fixed at the root,
> same checkpoint**, `HDN-BLK-011`/`ISS-2026-164`: 9 `SECURITY DEFINER` functions
> evaluated authority against a client-supplied actor UUID instead of the verified
> session identity — live-forced against full employee PII and customer inventory
> data. **Tier C review (four independent lenses) closed clean this same
> checkpoint** — its own security/tenant lens ran a wider, independently live-tested
> sweep and found **4 more** functions of the identical shape (2 direct siblings of
> already-fixed functions), fixed in the same checkpoint rather than merely
> registered (this lane's own charter), bringing the total to **13 fixed directly, 24
> protected once transitive propagation is counted**. Also corrected at Tier C: a
> fabricated claim of a committed live spoof test (a genuine one now exists); a
> mis-stated test-fixture fix (corrected to the repository's own established `'{}'`
> idiom); a High finding (`ISS-2026-166`) that had no `BLOCKER_LEDGER` entry, now
> `HDN-BLK-013`; and a new `HDN-BLK-014` for ~24 further unverified candidates. Two
> precisely-scoped findings sharing the identical shape (`HDN-BLK-012`, 13 dashboard
> functions; `HDN-BLK-014`, ~24 candidates) were deliberately deferred to `HDN-373`
> with the exact fix patterns already established — both, plus `HDN-BLK-013`, remain
> genuine release blockers for Step 16 per §8.1 until fixed or explicitly accepted at
> `HDN-387`/`HDN-389`. 13 further Medium/Low findings registered with named owners.
> Independent full gate re-run green post-Tier-C. Full disposition: `HDN-372.md` §13.

**(hard)** marks the four dependencies stated as hard constraints by the operator
authorization for this range, over and above each prompt's own §9: *372 must be `VERIFIED`
before 373 and 378; 371 must be `VERIFIED` before 374–376.* They are recorded separately
because a future session reading only the prompt files would not find them there.

---

## 5. Dependency graph

```
                                   PHASE_9_VERIFIED
                                          |
                                     HDN-369  (kickoff, COMPLETED)
                                          |
                                     HDN-370  (full regression baseline)  <-- VERIFIED
                _________________________|______________________________
               |          |          |          |          |            |
           HDN-371     HDN-372    HDN-379    HDN-380     HDN-382         |
        (txn integ.) (tenant iso) (perf)     (a11y)      (observ.)       |
         VERIFIED --^   ^-- VERIFIED                                    |
          |    |   \       |   \                |            |           |
          |    |    \      |    \               |            |           |
      HDN-374  |     \  HDN-373  \           HDN-381      HDN-383        |
      (finance)|      \ (RLS/RBAC)\          (browser)    (backup)       |
               |       \           \                         |           |
           HDN-375   HDN-376     HDN-377                   HDN-384       |
           (lineage) (API compat)(storage)                  (DR)         |
                                     \                                   |
           HDN-385  <-- HDN-371       \                                  |
        (migration rehearsal)          \                                 |
                                        \                                |
                       HDN-373 + HDN-374..377 + HDN-372 --> HDN-378 (security hardening)
                                          |
             all of HDN-370..385 VERIFIED |
                                          v
                                     HDN-386  (integrated verification)
                                          |
                                     HDN-387  (blocker triage + bounded remediation)
                                          |
                                     HDN-388  (documentation handoff)
                                          |
                                     HDN-389  (closure verification)
                                          |
                              FULL_SYSTEM_HARDENING_VERIFIED
                                  (Prompt 389 only)
```

**The graph permits parallelism that this build will never exercise.** `AGENTS.md`
"Execution cadence" names Step 15 (368–389) in its **never batch** list. Execution is
therefore strictly **one checkpoint per session, in ascending prompt order**, each with its
own full Tier A + Tier B + Tier C treatment. The graph is recorded so that a blocked lane
can be reasoned about correctly — not as a licence to run lanes concurrently.

---

## 6. Execution cadence for this range (binding)

Per `AGENTS.md` "Execution cadence (batched review, from Prompt 257)":

1. **Never batch.** One prompt per session. `HDN-370` and `HDN-371` may not share a session
   even though both would fit a batch elsewhere.
2. **Tier A — every prompt, automated, blocking.** `pnpm run typecheck`, `pnpm run lint`,
   `pnpm run test`, `bash scripts/db-tests/run.sh`, `pnpm run docs:check`,
   `pnpm run security:check`, `pnpm run git:check-paths`; plus `next build` whenever the
   checkpoint touches `app/`, `components/`, or a `"use server"` module.
3. **Tier B — every prompt, blocking.** Walk
   `docs/standards/RECURRING_DEFECT_TAXONOMY.md` §4 against the checkpoint's own diff and
   record the result in that prompt's build log.
4. **Tier C — every prompt in this range** (not every five). Four parallel review lenses,
   then a fix pass with a propagation sweep, then a **full gate suite re-run performed
   independently by the orchestrating session**.
5. **`COMPLETED` means adversarially unreviewed.** Only the Tier C close moves a row to
   `VERIFIED`. **No later prompt may begin until the current one is `VERIFIED`.**
6. **Never accept a review lens's or a fix agent's self-report** on a gate result. The
   orchestrating session re-runs the suite itself before any Tier C close.

---

## 7. Severity policy (Prompt 369 step 5)

| Severity | Definition | Consequence |
|---|---|---|
| **Critical** | Reachable, unmitigated breach of a core invariant: cross-tenant **write**; authentication or authorization bypass; financial posting corruption or unbalanced/irreversible ledger state; data loss with no recovery path; production credential exposure. | **Release-blocking. Never accepted as residual risk.** Cuts the current checkpoint short immediately; work stops until contained. |
| **High** | A mandatory control that is absent, structurally unreachable, or unenforced on a real path; cross-tenant **read**; a plausible exploit path with no compensating control; an irreversible finance/lineage defect not yet reproduced end-to-end. | **Release-blocking.** May only reach Step 16 as an explicitly-ruled, owner-named, compensating-control-documented accepted exception decided at `HDN-387` or `HDN-389` — never silently, and never by the lane that found it. |
| **Medium** | A correctness or control gap with a real compensating control or a narrow reachability path; missing evidence for a mandatory gate where the underlying control is proven; a disclosed design deferral with a named owner. | Not release-blocking on its own. Must be registered with a named owner and a disposition. An accumulation of Mediums in one gate is itself a High finding for that gate. |
| **Low** | Hygiene, test-fixture fragility, documentation drift, non-manifesting defects, advisory noise. | Registered, owned, never allowed to silently disappear. |

**Severity is assigned from reachability and blast radius, not from how hard the fix is.**
A High that is expensive to fix stays High; it becomes an *accepted exception* by an
explicit ruling, never by re-grading. (`ISS-2026-150` is the standing precedent — Phase 9
ruled on it rather than downgrading it, and named Step 15 as the remedy.)

---

## 8. Release-blocker definition and accepted-risk handling

### 8.1 Release blockers (from `368_FULL_SYSTEM_HARDENING_README.md` "Non-negotiable gates")

A finding is a **release blocker** if it defeats any of these:

1. No critical/high tenant isolation defect.
2. No critical/high security defect.
3. No unresolved financial integrity issue.
4. No broken core E2E flow.
5. Migrations apply cleanly.
6. Backup and restore tested.
7. DR rehearsal completed according to gate.
8. Monitoring and alerting active.
9. Runbooks available.
10. No fake pass, hidden failure or disabled test.

### 8.2 Accepted-risk handling

An accepted risk is valid only when **all five** hold. Anything less is an unowned blocker,
not an accepted risk:

1. Severity is **High or below** — a Critical is never accepted.
2. An **explicit written ruling** exists stating why the risk is accepted, what was
   considered and rejected, and what the compensating control is.
3. A **named owner** and a named future task carry it.
4. It is registered in **`BLOCKER_LEDGER.md`** *and* `docs/runtime/KNOWN_ISSUES.md`.
5. It is accepted at **`HDN-387` or `HDN-389` only** — never by the lane that found it, and
   never by this kickoff.

**A gate that could not be run is not a passing gate.** It is a tracked evidence gap with an
owner, an exact missing command, and a stated risk — per each prompt's §22 alternative flow.
"Not triggered" is never reported as "verified".

---

## 9. Baseline gate status at this checkpoint

Run fresh this session on the frozen tree. Exact results, including the day the suite ran —
never a carried-forward figure:

| Gate | Result | Notes |
|---|---|---|
| `pnpm run typecheck` | **0 errors** | |
| `pnpm run lint` | **0 errors / 337 warnings** | Same pre-existing `@next/next/no-html-link-for-pages` class and identical count as Phase 9's own closure baseline — unchanged by this checkpoint |
| `pnpm run test` | **5394 / 5394 pass, 0 fail** | Pre-commit it was 5393/5394; the sole failure was the known checkpoint-state-dependent `checkWorktreeCollision` class, which resolved once this checkpoint's commit existed — the same class the Phase 8 and Phase 9 kickoff baselines disclosed. Detail: `HDN-369.md` §7.1/§7.4 |
| `bash scripts/db-tests/run.sh` | **`ALL PASSED` — 229 / 229 files** | Full unmodified suite, 306 migrations, fresh disposable database. Observed green **twice**: pre-commit, and again in full on the committed tree (`running 229 test file(s)` → `ALL PASSED`, exit 0). `HDN-369.md` §7.6 |
| `pnpm run docs:check` | **passed** | Caught two real forward-reference defects during authoring — citations to build logs that do not exist yet. Both fixed. `HDN-369.md` §7.5 |
| `pnpm run security:check` | **passed** | No secret-shaped pattern in any tracked file |
| `pnpm run git:check-paths` | **passed** | 10 files checked, 0 forbidden, 5 CAUTION flags — the five `docs/runtime/` ledgers, expected for an append-only path. No historical row deleted (verified by diff) |
| `next build` | **not run — not required** | This checkpoint touches no `app/`, `components/`, or `"use server"` module. Required from `HDN-380` onward and at any lane that repairs UI |

**Day-of-week disclosure (mandatory every checkpoint in this range).** This checkpoint ran
on **Sunday 2026-08-23, approximately 11:15-11:45 UTC.**

The registered fixture-flake class has **two distinct trigger dimensions**, and this run
exercised only one. Reporting "229/229 green" without that distinction would be the fake pass
this range exists to prevent:

| Issue | Trigger dimension | Exercised? |
|---|---|---|
| `ISS-2026-135` (`hris-shift-roster-scheduling.sql`) | day-of-week | **Yes — Sunday. Did not fire** |
| `ISS-2026-103`/`115` (`hris-overtime-timesheet.sql`, already fixed) | day-of-week | **Yes — Sunday. Did not fire.** First independent Sunday confirmation of the `cdbccc7` fix |
| `ISS-2026-077` (`hris-leave-permit-business-trip.sql`) | wall-clock **and** day-of-week | **Partly** — the day half was in play; the wall-clock half was uncontrolled |
| `ISS-2026-154` (`hris-attendance.sql`) | a ~1-hour real-UTC window after each day's 21:00 UTC shift-day boundary | **No — not exercised at all**, ~10 hours outside it |

**Verdict: the class was `PARTIAL`ly exercised — one dimension in play and not fired, one
dimension not exercised.** A green suite on one Sunday morning is **not** evidence of a
day-independent gate. `HDN-370` owns proving day-independence rather than observing it.
Every following checkpoint must make this same distinction explicitly.

---

## 10. Structural constraint every lane must plan around

**A migrated database is not a running system.** The live Supabase project holds the full
schema, but there is no deployed application, no real sign-in flow, and no CI-driven deploy.
Several Step 15 gates are written for a running system. Each affected lane must state up
front which of the three it is doing, and never blur them:

| Posture | Meaning | Valid? |
|---|---|---|
| **Executed** | Really run against a real target, results observed | Yes — always preferred |
| **Executed against a substitute** | Run against the disposable database or the live migrated project, with the substitution and its limits stated | Yes, when the substitution is disclosed |
| **Tracked gap** | Cannot be run here; recorded with owner, risk, and the exact missing command | Yes — and it is **not** a pass |

Lanes most affected: `HDN-380` (accessibility), `HDN-381` (browser/device), `HDN-382`
(observability), `HDN-383`/`HDN-384` (backup/restore, DR). This is the same constraint
`ISS-2026-140`/`ISS-2026-141`/`ISS-2026-148`/`ISS-2026-153` already register — Step 15 does
not get to rediscover it, and does not get to paper over it either.

---

## 11. Test strategy, source-domain ownership, rollback, runbooks

### 11.1 Test strategy

- **Baseline first, always.** Every lane re-establishes the Tier A baseline on its own tree
  before changing anything, so regression and pre-existing failure can be told apart with
  proof rather than assertion (`AGENTS.md`: "Separate pre-existing failures with baseline
  evidence").
- **Every repair carries a regression test** proving the defect cannot recur, or an
  explicit documented reason why one is impossible.
- **Negative tests are mandatory** wherever a control is claimed: cross-tenant, denied role,
  expired grant, replayed idempotency key, revoked session, malformed payload.
- **Never** disable, skip, quarantine, or weaken a test, lint rule, typecheck, RLS policy or
  validation to make a gate pass.
- **Mixed-checkpoint evidence is invalid.** Every result cited at `HDN-386` and `HDN-389`
  must come from one compatible checkpoint.

### 11.2 Source-domain ownership evidence plan

Step 15 audits nine already-`VERIFIED` phases. Findings will land in code owned by phases
that are closed. The rule for every lane:

1. **Identify the owning phase** of every finding by direct evidence (`git log`, the
   migration that created the object, the phase's build log) — never by inference.
2. **Fix only task-caused failures.** A pre-existing defect found by a Step 15 lane is
   registered in `docs/runtime/KNOWN_ISSUES.md` with a named owner — **neither silently
   repaired inside an unrelated checkpoint nor silently ignored.**
3. **Bounded repair is allowed where the lane's own charter names it** (e.g. `HDN-378` owns
   `ISS-2026-150`; `HDN-370` owns the fixture-flake class). Outside that, a finding becomes
   a `HDN-387` candidate, not an in-lane edit.
4. **Never edit an applied migration.** Repairs are additive migrations only, at most 1–3
   per lane, reversible and source-domain safe.

### 11.3 Rollback plan

| Scope | Mechanism |
|---|---|
| Any Step 15 checkpoint | `git revert` the checkpoint's single commit. One commit per prompt is the standing rollback granularity |
| A repair migration | Additive and reversible by design; a forward-fix migration, never an edit of the applied file |
| The live database | **No Step 15 lane mutates the live project's data.** Schema-affecting rehearsals run against a disposable database. `HDN-383`/`HDN-384`/`HDN-385` must state their target explicitly before executing |
| Last known good checkpoint | `e5da061` (merge of PR #65) until this checkpoint's own commit lands; thereafter this checkpoint's commit |

### 11.4 Runbook checklist (owner: `HDN-388`, evidence produced by the lane named)

| Runbook | Current state | Lane that must produce/refresh its evidence |
|---|---|---|
| Security incident response, key rotation | exists, needs Step 15 evidence | `HDN-378` |
| Performance/capacity | needs creation | `HDN-379` |
| Observability, alerting, on-call ownership | needs Step 15 evidence | `HDN-382` |
| Backup and restore | needs creation, incl. the teardown constraint in §13 | `HDN-383` |
| Disaster recovery | needs creation | `HDN-384` |
| Deployment / migration re-run guard | needs the non-idempotency statement in §13 | `HDN-385`, `HDN-388` |
| `docs/runbooks/gps-ingestion-database-outage.md` | exists, carries a stale "no live Supabase project exists yet" severity note | `HDN-382` (refresh with the current baseline) |

---

## 12. Step 16 eligibility criteria and the release boundary

**No Step 16 release, release-candidate, go-live, production, pilot, GA or market-ready work
is performed anywhere in Prompts 369–389** (Prompt 369 step 6, confirmed). Step 15 verifies,
attacks, repairs and documents. It does not ship.

Step 16 becomes eligible only when **all** hold:

1. `HDN-370` … `HDN-388` are all `VERIFIED` at one compatible checkpoint.
2. `HDN-389` has run and set **`FULL_SYSTEM_HARDENING_VERIFIED`**. **Prompt 389 is the only
   task authorized to set a Step 15 completion flag.**
3. Every one of the ten non-negotiable gates in §8.1 passes.
4. Zero unresolved Critical. Every High is either fixed with regression proof or is an
   accepted exception meeting all five conditions of §8.2.
5. `FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` exists in this directory and
   disposes of all 22 required-verification items of Prompt 389 explicitly — each one
   `PROVEN`, `PROVEN-with-disclosed-residual`, or explicitly ruled on. Silence on an item is
   a closure defect.
6. `FULL_SYSTEM_HARDENING_VERIFIED` is **not** a production/pilot/GA/market-ready claim
   (RPD-001/034/036), and no Step 15 artifact may imply it is.

The exact next command after Step 15 validation is `LANJUT STEP 16` — a package-level
instruction, not a licence for any prompt in this range to start Step 16 work.

---

## 13. Carry-forward items seeded into their lanes (Prompt 369 step 4 input)

These are **already-known evidence**, not discoveries for a Step 15 lane to re-make. Each is
seeded into `HARDENING_MATRIX.md` and `BLOCKER_LEDGER.md` and assigned to exactly one lane.
**Do not rediscover them, and do not let them drift.**

| Lane | Item | Disposition |
|---|---|---|
| `HDN-370` | **Day-of-week / wall-clock fixture flake class** — `ISS-2026-077` (`hris-leave-permit-business-trip.sql`), `ISS-2026-135` (`hris-shift-roster-scheduling.sql`), `ISS-2026-154` (`hris-attendance.sql`) | **Close the class.** `ISS-2026-103`/`115` (`hris-overtime-timesheet.sql`) is already closed by pinning the fixture to the most recent weekday — **reuse that pattern.** A regression baseline green only on some days of the week is not a release gate. |
| `HDN-378` | `ISS-2026-150` (**High**) — IP restriction structurally unreachable from any real mutation; no real client IP is threaded through the route-handler layer | **Must not be deferred again.** Phase 9's closure disclosed it as a deliberate exception and named Step 15 as the remedy. Needs route-handler IP extraction and threading, plus a ruling on service-role/background callers with no client IP. |
| `HDN-378` | `ISS-2026-151` (**Medium**) — step-up challenge unwired on `app.create_integration_connection`, 40+ call sites across 16 files | Deliberately left unwired at Phase 9 rather than risk a rushed mass edit. Wire it, or rule on it explicitly. |
| `HDN-378` | **postgis, pg_trgm and btree_gist live in `public`** | **Its own scoped task inside the lane — never folded into another edit.** Same root class as the fixed pgcrypto defect; clears 7 of the 8 non-noise security advisories including the only ERROR. But every `geometry`/`geography`/`ST_*` caller needs `extensions` in its search_path, a far larger blast radius than the pgcrypto change. |
| `HDN-379` | `rbac-enforcement.sql`'s `pg_proc` catalogue scan over ~2,900 functions (`ISS-2026-145`) | Passes locally; already exceeds a remote statement timeout; grows with the schema. Scope the scan before it bites CI. |
| `HDN-379` | **892 `unindexed_foreign_keys` advisories** | An **explicitly deferred, owner-named decision** — a design question needing real query patterns. **Neither drop them nor blindly index.** (The 982 `unused_index` advisories are noise: the database has served no queries.) |
| `HDN-383` / `HDN-384` | **Teardown must batch `drop schema app cascade` per transaction** — `53200: out of shared memory` at ~1,400 objects | The statement is atomic and rolls back cleanly, so nothing corrupts — but any teardown drops in batches, each in its own transaction. Belongs in the DR runbook. |
| `HDN-383` / `HDN-384` | **Migrations are not idempotent** — bare `create table`, no transaction wrapper | `supabase_migrations.schema_migrations` is the **only** re-run guard. State this explicitly in the deployment runbook. |
| `HDN-383` / `HDN-384` | **`auth.users` survives a schema reset** | It is Supabase's schema, untouched by dropping `app`. Any live test cycle must clear it in teardown or every rerun collides on `users_pkey`. |
| **All lanes** | **Preserve the CI-mirrors-hosted property in both directions** (extension schema *and* database-level `search_path`) | A hardening change that reintroduces that divergence re-blinds CI to the exact class the live migration exposed. Cross-cutting Tier B review item. |

---

## 14. Exact remediation / resume format (Prompt 369 step 5)

Every Step 15 finding is recorded in `BLOCKER_LEDGER.md` in exactly this shape. A finding
missing any field is not registered:

```
ID              HDN-BLK-<nnn>
Title           one line, states the defect, not the symptom
Found by        lane + review lens
Severity        Critical | High | Medium | Low   (per §7, from reachability and blast radius)
Owning phase    the phase that owns the code, by direct evidence
Owning lane     the Step 15 lane authorized to repair it, or HDN-387
Reachability    who can reach it, from where, with what credential
Reproduction    exact command / SQL / request, and the observed output
Blast radius    files, functions, call sites, tenants affected — measured, not estimated
Disposition     FIXED | ACCEPTED_EXCEPTION | DEFERRED_TO_HDN-387 | TRACKED_GAP
Regression test the test proving it cannot recur, or the documented reason none exists
Rollback        how to undo the repair
KNOWN_ISSUES    the ISS-2026-nnn row, if it has one
```

**Resume format.** Every Step 15 session ends by writing, in its build log and in this
index: the lane just closed and its state; the exact gate results observed (never carried
forward); the day of week and whether the flake class was exercised; the last known good
commit; and the **single** next eligible prompt. A session that cannot finish its lane
records `BLOCKED` with the allowed repair scope and the next safe action, and changes no row
to `VERIFIED`.

---

## 15. Checkpoint history

| Date | Lane | Task ID | Branch | Commit | Result |
|---|---|---|---|---|---|
| 2026-08-23 | `HDN-369` | `CG-S15-HDN-001` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-369.md` §2 | **`COMPLETED`** — sets `FULL_SYSTEM_HARDENING_IN_PROGRESS`. Docs-and-index kickoff; one comment-only source correction (§2.1). Zero migration, zero application code touched |
| 2026-08-23 | `HDN-370` | `CG-S15-HDN-002` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-370.md` | **`VERIFIED`** — full regression executed and reconciled, then Tier C closed. `HDN-BLK-002` **closed at the root**: three of its four issues were **misclassified** — `ISS-2026-077` is a timezone-boundary mismatch failing **29% of all instants (7 h/day)**, `ISS-2026-135` is a hardcoded calendar date armed on one date (`2026-08-18`, a Tuesday), and only `ISS-2026-103`/`115` was ever day-of-week. All three fixed and **proven by 672/2,016/30-instant sweeps** rather than a green re-run. **Opened `HDN-BLK-007` (High), `008`, `009`: all three CI jobs failed on the most recent push to `main`, and six governance steps — including the secret scan and the dependency vulnerability audit — have therefore never executed there on a push**, deferred to `HDN-387` with explicit interim guidance for the three lanes they actually touch. **Tier C review** (4 independent lenses) found and fixed: 4 of 7 governance gates never run locally (High), a NULL-fail-open in the attendance fixture live-proven by two lenses independently (Medium), `CARGOGRID_BUILD_STATUS.md` never updated (High), plus a consistency sweep across 8 files. Independent full gate re-run green: 229/229 db-tests, all 7 governance gates, 5394/5394 unit tests. Test fixtures only throughout — zero migration, zero application code |
| 2026-08-23 | `HDN-371` | `CG-S15-HDN-003` | `claude/step-15-hdn-369-kickoff-w6qren` | `23e3490` (initial), Tier C fix commit(s) — see `HDN-371.md` | **`VERIFIED`** — Tier C closed. Every named chain (lead→job, shipment→billing, actual cost→AP→settlement, invoice→journal/correction, WMS inbound→outbound, tickets) reconciled against live code and existing passing evidence — no ownership conflict found; the loyalty/portal chain was honestly disclosed as **not examined** rather than overclaimed. **One systemic finding**, from an exhaustive code-level sweep of all 306 migrations for the boundary-function shape, **corrected at Tier C review**: **9 of 20** (not the original 7/19 — the sweep's regex was blind to `create or replace` redefinitions and missed 2 members of its own class) cross-module `prepare_/convert_/link_/create_from_` functions across **5 domains** (5 Finance, 1 HRIS-Payroll, 1 Commercial, 1 Advanced TMS/WMS, 1 Platform/Auth — corrected from an imprecise "6 of 7 Finance-domain") share an identical concurrent-idempotency gap that a sibling, `prepare_wms_outbound_from_shipment`, already proves the fix for in this codebase ("design note 9(a)"). Bounded to **Medium** by direct verification against the live schema — all 8 distinct backing tables/partial-indexes carry a confirmed unique-enforcing object, so no duplicate record can be created; the real exposure — a raw `unique_violation` surfaced to a genuinely racing caller — is now **live-forced and confirmed** (not merely code-inferred) against `link_auth_identity`, independently reproduced twice with an identical observed error. Registered as `HDN-BLK-010`/`ISS-2026-162`, **deferred to `HDN-374`** as one batch, with the batch's 4-domain scope disclosed as an open question for `HDN-374`/`HDN-386` rather than silently assigned. **Tier C review (4 independent lenses) found and fixed 3 High findings** (5 of 7 originally-registered functions cited at superseded migrations — the conclusion survived, independently re-verified against the live bodies, but citations, file counts and 2 of 6 constraint names were wrong; the 2 missed functions above; a false claim in `BLOCKER_LEDGER.md` that `HDN-374`'s hard upstream dependency was "already satisfied" while `HDN-371` was still `COMPLETED` — the one finding with a direct never-batch-safety consequence), 7 Medium findings (missing Step 16 eligibility statement; blank gate-2 status token; `HARDENING_MATRIX.md` §5 excluding a non-Finance function from any lane's seed; the loyalty/portal overclaim; Prompt 371 §28 tests addressed by demonstrating a simpler, working, reusable concurrency-proof technique rather than by adding a permanent test file; a stale `HANDOFF.md` `READY` claim), and 9 Low findings (all fixed or explicitly registered — including one new, separate, pre-existing production defect, `ISS-2026-163`, found on a function outside `HDN-BLK-010`'s own set). Independent full gate re-run green: 5394/5394 unit tests, 229/229 db-tests, all 7 governance gates. Zero migration, zero application code, zero contract, zero route throughout — documentation and ledger evidence only, plus disposable probe-database use for live verification, all dropped afterward |
| 2026-08-23 | `HDN-372` | `CG-S15-HDN-004` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-372.md` | **`VERIFIED`** — Tier C closed. Four independent parallel adversarial investigations (DB/RLS/grants; API/service layer; storage/jobs/cache/reports; support/AI/webhooks/audit), each with its own live two-tenant fixture. **Found and fixed at the root, same checkpoint: `HDN-BLK-011`/`ISS-2026-164`** — 9 `SECURITY DEFINER` functions evaluated authority against a client-supplied actor UUID instead of the verified session identity, live-forced: `app.get_self_employee` (full employee PII including columns excluded from the table's own column-restricted grant) and the `ATW-023` family (customer inventory/warehouse/order data), plus the audit trail, notifications, and workflow/approval/shipment history. High, not Critical — live-confirmed against the real deployed project that `app` is not currently exposed via the Data API (`PGRST106`), disclosed as a pre-deployment state rather than a durable control since the app's own shipped code requires it exposed to function. **Tier C review (four independent lenses) closed clean this same checkpoint**: its own security/tenant lens ran a wider, independently live-tested sweep and found **4 more** functions of the identical shape (2 direct siblings of already-fixed functions in the same migration files) — fixed in the same checkpoint, this lane's own charter, bringing the total to **13 fixed directly (2 migrations), 24 protected once transitive propagation is counted (corrected from an original miscounted 12/21)**. Also fixed at Tier C: a fabricated claim of a committed live two-session spoof test (a genuine one now exists and fired clean on re-run); the `hris-employee-master.sql` test fix's own stated mechanism (was silently relying on an exception-swallow, corrected to the repository's own established `'{}'` idiom); the standing `ATW-032` sweep's own candidate-regex blind spot (broadened, not just its 2 known instances); the new regression gate's bare-substring weakness (rewritten position-aware). Also registered at Tier C: `HDN-BLK-013`/`ISS-2026-166` (High, the app-layer single-point-of-failure finding, which existed in `KNOWN_ISSUES.md` since this checkpoint's first commit but had no `BLOCKER_LEDGER` entry until Tier C corrected it) and `HDN-BLK-014`/`ISS-2026-179` (Medium, ~24 further boolean-oracle candidates, only 3 live-verified). **Two precisely-scoped findings sharing the identical shape** (`HDN-BLK-012`/`ISS-2026-165`, 13 dashboard functions; `HDN-BLK-014`/`ISS-2026-179`, ~24 candidates) deliberately deferred to `HDN-373` with the exact fix patterns already established — both, plus `HDN-BLK-013`, are release blockers for Step 16 per §8.1 until fixed or explicitly accepted. **13 further Medium/Low findings registered** with named owners across `HDN-373`/`376`/`377`/`378`/`379`/`382`. **No Critical finding anywhere** — every write path probed was correctly denied under a forged actor. Independent full gate re-run green post-Tier-C: 5394/5394 unit tests, 229/229 db-tests (308 migrations), all 7 governance gates clean. Two additive migrations, zero applied migration edited, zero application code, zero contract, zero route. Full disposition: `HDN-372.md` §13 |
| 2026-08-23 | `HDN-373` | `CG-S15-HDN-005` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-373.md` | **`VERIFIED`** — Tier C closed across two rounds. **Headline finding**: `app.evaluate_permission` (root RBAC gate, ~1,124 callers) never checked tenant membership — a revoked ex-member retained every role-based permission indefinitely, live-confirmed end to end. **Fixed** at `20260810300000` (`ISS-2026-180`). **Largest reachability defect found anywhere in Step 15 to date**: the entire Finance manual/period/config/import-export write surface — 152 functions once Tier C's own wider sweep completed the diagnosis — was `SECURITY INVOKER` instead of `SECURITY DEFINER`, completely unreachable by any real `authenticated` session since it shipped. **Fixed** at `20260810700000` (95 functions, `HDN-BLK-015`/`ISS-2026-182`) and `20260810900000` (57 more, found by this checkpoint's own first Tier C round's independent wider sweep). Companion findings fixed alongside: `ISS-2026-183` (`create_and_post_finance_system_journal` unchecked, then its own `FIN:Approve`-only gate found to regress two legitimate `FIN:Edit`-only callers and corrected to accept either), `ISS-2026-184` (`finance_journals`/`finance_journal_lines` `FIN:View` RLS bypass), `ISS-2026-181` (Finance journal self-approval, sharing `ISS-2026-139`'s shape), `ISS-2026-193` (a genuine new High Tier C found: `app.preview_finance_config_impact`/`app.validate_custom_field_values` disclosed another tenant's config data with no tenant check at all). **Carried forward from `HDN-372` and closed**: `HDN-BLK-012`/`ISS-2026-165` (13 dashboard functions); `HDN-BLK-014`/`ISS-2026-179` (16 of ~30 candidates confirmed terminal and fixed, ~14 confirmed genuinely shared with third-party call sites and re-registered narrower as `ISS-2026-186`, owner `HDN-387`, not blindly fixed); `ISS-2026-171`/`173` (own-row RLS gaps, plus one further instance found, `ISS-2026-185`); `ISS-2026-139` (loyalty maker/checker). **Tier C review found the checkpoint's own first fix pass incomplete** — an independent, deliberately wider schema-wide sweep (not scoped to Finance) found the 57 additional functions above; a fifth independent lens then re-ran that same sweep against the fully-fixed state (zero rows, confirmed complete across every domain, not just Finance) and adversarially re-verified all 3 corrections with fresh fixtures — all held. Also corrected at Tier C: `ISS-2026-165`'s stale `OPEN` status in `KNOWN_ISSUES.md`; `HDN-BLK-012`/`014`'s missing dated ledger amendments; 3 findings' hedged ownership (now `HDN-387`); 2 findings' missing severity-band justification. **Six further findings registered, not fixed**, each with a named forward owner (`HDN-378` or `HDN-387`): `ISS-2026-186`-`192` minus the fixed ones. **No Critical finding anywhere.** Independent full gate re-run green: `typecheck` 0, `lint` 0 errors/337 warnings, 229/229 db-tests (316 migrations), fresh disposable database with real grants, no superuser-only bypass. Eight new migrations, zero application code, zero contract, zero route. Full disposition: `HDN-373.md` §13/§13.1 |

---

## 16. Next eligible prompt

> ### **`HDN-374` (Financial Integrity Audit, `CG-S15-HDN-006`) is the single next eligible prompt**
>
> - **`HDN-373` is `VERIFIED`** — Tier C closed clean across two rounds (the first round
>   found and this checkpoint fixed a real completeness gap in its own fix pass; a fifth
>   independent lens then confirmed that correction itself complete and correct),
>   independent full gate re-run green. Full disposition: `HDN-373.md` §13/§13.1.
> - `HDN-374`'s own dependency (`HDN-371` **`VERIFIED`**, hard) has been satisfied since
>   before `HDN-373` began; it must run in its own separate session — it may not share a
>   session with `HDN-373`.
> - **`HDN-377` (Storage and Signed URL Audit) is also dependency-satisfied** and shows
>   `READY` in the WBS table above — noted for accuracy, not as a routing instruction.
>   This range's established cadence runs the numbered prompts in sequence; `HDN-374` is
>   the next one in that sequence and the one this section names as next.
> - **Carry-forward for `HDN-374`, so it does not discover these cold:**
>   1. **`HDN-BLK-010`/`ISS-2026-162`** (Medium, carried from `HDN-371`) — 9 of 20
>      cross-module boundary functions lack the race-safe idempotency pattern this
>      codebase already proves elsewhere (`prepare_wms_outbound_from_shipment`'s own
>      "design note 9(a)"), live-forced and confirmed for `link_auth_identity`. 6 are
>      Finance/HRIS-Payroll (squarely `HDN-374`'s own charter); 3 (Commercial, WMS,
>      Platform/Auth) are an open scope question for `HDN-374` to resolve explicitly, not
>      silently assign. Also close `ISS-2026-163` (`app.prepare_job_order`'s defective
>      exception handler) in the same session, same function family.
>   2. **`ISS-2026-186`** (Medium, owner `HDN-387` but touches RBAC primitives `HDN-374`
>      may itself call) — ~14 shared `SECURITY DEFINER` primitives genuinely called with
>      third-party actor arguments elsewhere in the schema; not this lane's charter to
>      fix, but worth knowing about if `HDN-374`'s own audit touches any of them.
> - **Do not cite CI as evidence for anything** — `HDN-BLK-007/008/009` remain open; every
>   result this lane produces must be a real local execution.

**Nothing after `HDN-374` may begin until `HDN-374` is `VERIFIED`.**
`FULL_SYSTEM_HARDENING_VERIFIED` is **not** set and may only ever be set by Prompt 389.

> **Standing warning for `HDN-386` and every lane before it:** CI is currently red on `main`
> on all three jobs (`HDN-BLK-007/008/009`). **No Step 15 lane may cite CI as evidence for any
> gate until those are resolved.** Local runs remain valid evidence and are what this range
> has been using — but the two are not interchangeable, and this lane proved they can be
> exact inverses of each other.
>
> **Amendment, Tier C review of `HDN-370` — this is more than a standing note, it is a real
> ordering problem, surfaced by the cross-prompt integration lens and not fully resolved by
> "defer to `HDN-387`" alone:**
>
> - `HDN-BLK-009`'s own record already names `HDN-380`/`HDN-381` (WBS rows 12–13) as needing
>   its fix, while `HDN-387` — the lane deferred to — is row 19, six rows later. Those two
>   lanes will run first and must decide for themselves, explicitly, whether they can produce
>   real evidence without it (§10's Executed / Executed-against-a-substitute / Tracked-gap
>   framework already gives them the vocabulary; `HARDENING_MATRIX.md` §11/§12 now cross-
>   reference this directly).
> - `HDN-386` (Integrated Verification, row 18) runs **before** `HDN-387` (row 19) but is
>   barred from citing CI by the warning above. Its own charter is confirming that Step 15's
>   gate evidence is current and not mixed-checkpoint — which now explicitly includes
>   confirming, per gate, whether that evidence is **Executed** (a real local run this lane
>   observed) or a **carried assumption that CI covers it**. `HDN-386` must not wave this
>   through as "not applicable because it's a CI problem" — three of the sixteen mandatory
>   gates (security hardening, accessibility, browser/device) have a real, load-bearing
>   dependency on exactly the surface that's blind right now.
> - `HDN-378` (Security Hardening) inherits `ISS-2026-007`'s original failure shape one level
>   up: the dependency-audit gate that fixed it does not currently run in CI on a push
>   (`HARDENING_MATRIX.md` §9 item 7). `HDN-378` must run `security:audit` itself and record
>   the result — CI's silence is not evidence it passed.
>
> **This is not a ruling.** Only `HDN-387`/`389` may set `ACCEPTED_EXCEPTION` under §8.2's five
> conditions, and this index does not attempt to. What it does: names the three lanes that
> actually touch this gap (`HDN-378`, `HDN-380`/`381`, `HDN-386`) so none of them discovers it
> cold, and requires each to produce a real disposition — Executed, Executed-against-a-
> substitute, or an explicitly widened `TRACKED_GAP` — rather than silently inheriting
> `HDN-370`'s finding as settled. If any of those three lanes concludes it genuinely cannot
> proceed without the CI fix, that is the trigger to escalate the repair ahead of `HDN-387`,
> not to wait for it.
