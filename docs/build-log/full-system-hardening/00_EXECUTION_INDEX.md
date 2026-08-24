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

> **Additive-migration-only rule reconciliation, added at `HDN-376`.** `75278d3`,
> `11bd409` and `d82cd6f` above each edited already-applied migration files in place (86
> unique files total, spanning `20260716075355` through `20260809100000`) rather than
> landing a new forward-fixing migration — the fixes themselves are correct and already
> disclosed in the table above, but this specific fact (an exception to the "additive/
> expand-and-contract only, never edit an applied migration" rule every Step 15 prompt's
> own §19 states) was never explicitly assessed against that rule until `HDN-376`'s own
> Tier A investigation found it. Pre-dates Step 15 entirely (all three commits landed
> before `HDN-369`'s own kickoff) — not a Step-15-lane violation, and re-doing that
> history now would be pure churn, not a real repair. Disposition: **no fix, standing
> exception acknowledged here** — the rule itself is unchanged and binding on every Step
> 15 lane from `HDN-369` onward; nothing before that kickoff is grandfathered into a
> future audit re-litigating this same fact.

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
| 6 | `HDN-374` | `CG-S15-HDN-006` | 374 | Financial Integrity Audit | Financial Assurance | `HDN-371` **(hard)** | **`VERIFIED`** — Tier C closed, 5 more findings found (3 fixed same checkpoint, 2 registered — `HDN-BLK-016`/`ISS-2026-199`, owner `HDN-386`); see `HDN-374.md` |
| 7 | `HDN-375` | `CG-S15-HDN-007` | 375 | Data Lineage Audit | Integrity Assurance | `HDN-371` **(hard)** | **`VERIFIED`** — Tier C closed. 2 real defects fixed (`ISS-2026-201` High, `app.transaction_lineage_edges` freely mutable; `ISS-2026-202` Medium, orphan `source_id` on loyalty/finance journals); 4 more findings found at Tier C (1 documentation-completeness gap corrected, 1 repeated ledger inconsistency corrected, 2 new in-charter findings registered — `HDN-BLK-018`/`ISS-2026-205`, High, systemic append-only-guard gap; `ISS-2026-206`, Medium, recurring orphan-source-id gap); plus `HDN-BLK-017`/`ISS-2026-200` (High, hash-chain not genuine) and `ISS-2026-203` (Low) registered, all owner `HDN-386`; see `HDN-375.md` |
| 8 | `HDN-376` | `CG-S15-HDN-008` | 376 | API Compatibility Audit | API Assurance | `HDN-371` **(hard)** | **`VERIFIED`** — Tier C closed. 4 lenses, 2 Critical/High security defects fixed (`ISS-2026-209` Critical, `ISS-2026-210` High, NULL-signature bypass on inbound/outbound webhook verification), 2 Low route defects fixed (`ISS-2026-211`/`212`), `ISS-2026-147` item 1 closed (44 new route-level tests). Tier C found 1 more real defect fixed same checkpoint (`ISS-2026-215`, Low, 2 GET routes conflating a genuine internal RPC failure with the domain 404 not-found case), a documentation-citation date fix, and 4 findings registered (`ISS-2026-207`/`208` Medium+Low owner `HDN-387`; `ISS-2026-213` Low owner `HDN-386`, 6-function defense-in-depth gap; `ISS-2026-214` Low owner `HDN-387`, Zod-error leak on 4 routes); see `HDN-376.md` |
| 9 | `HDN-377` | `CG-S15-HDN-009` | 377 | Storage and Signed URL Audit | File Security Assurance | `HDN-372` **`VERIFIED`** | **`VERIFIED`** — Tier C closed. 4 lenses, first round: 2 Critical + 1 High + 3 Medium defects fixed (`ISS-2026-216` storage_path exposure; `ISS-2026-217` dual legal-hold mechanisms; `ISS-2026-218` legal-hold DELETE backstop; `ISS-2026-219`/`220`/`221`). Tier C: 1 more Critical self-inflicted gap fixed in the first round's own trigger (`ISS-2026-226`), 1 more High fixed (`ISS-2026-227`), 1 Medium-High validation gap fixed (`ISS-2026-228`), 1 finding self-corrected before commit (`ISS-2026-231`), 6 findings registered (`ISS-2026-222` High + `229` Critical + `230` High, all owner `HDN-386`; `ISS-2026-223`/`225`(corrected High)/`232` owner `HDN-378`; `ISS-2026-224` Medium owner `HDN-387`); see `HDN-377.md` |
| 10 | `HDN-378` | `CG-S15-HDN-010` | 378 | Security Hardening | Security Assurance | `HDN-372` **(hard)** `VERIFIED`, `HDN-373..377` **all `VERIFIED`** | `VERIFIED` — Tier C closed. `ISS-2026-150` (High, "must not be deferred again") wired across all 4 named functions, corrected `RESOLVED` → `PARTIALLY RESOLVED` at Tier C once `app.set_integration_connection_status`'s own independent bypass was found; a self-caught `CREATE OR REPLACE` overload defect corrected before commit (`C-29`); `pg_trgm`/`btree_gist` relocated (`postgis` found non-relocatable, `ISS-2026-234`); OWASP sweep fixed 1 finding (`ISS-2026-233`); `ISS-2026-168`/`169`/`232` fixed first round, `ISS-2026-168`/`232` each had a further Tier C-found bypass fixed same close (`C-27`); `ISS-2026-151`/`149`/`146` reconfirmed and deferred again; 4 runbooks authored. Tier C found and fixed 2 Critical + 1 High genuine bypass in this checkpoint's own work; registered 2 new findings with owner `HDN-386` (`ISS-2026-235`/`HDN-BLK-023` Critical, `ISS-2026-236`/`HDN-BLK-024` High, `C-28`) and 1 with owner `HDN-387` (`ISS-2026-237` Medium). See `HDN-378.md` §13 |
| 11 | `HDN-379` | `CG-S15-HDN-011` | 379 | Performance and Scalability | Performance Assurance | `HDN-370` | `VERIFIED` — Tier C closed. `ISS-2026-145` (the O(n²) `rbac-enforcement.sql` scan) `RESOLVED`, matched-pair verified twice (300×-1200×+ speedup); a real structural weakening in the fix itself found and closed at Tier C; 892 unindexed-FK advisories categorized and deferred (`ISS-2026-239`); `auth_rls_initplan` regression guard re-verified clean; `ISS-2026-238` (Medium) expanded from 3 to 4 confirmed routes plus 5 new siblings found at Tier C. See `HDN-379.md` §13 |
| 12 | `HDN-380` | `CG-S15-HDN-012` | 380 | Accessibility | UX Assurance | `HDN-370` | `VERIFIED` — Tier C closed, no Critical/High finding at either round. 6 color-contrast tokens fixed; `eslint-plugin-jsx-a11y` `recommended` wired repository-wide, 14 real errors fixed; 463/463 error displays carry `role="alert"` (7 missed by the first round's own narrower sweep, found and fixed at Tier C); `HDN-BLK-009`/`ISS-2026-160` root-caused (Turbopack dev-mode hydration race, `C-30`) and `RESOLVED` (harness 18/18); `ISS-2026-241`/`242` registered (landmark gap, form-primitive under-adoption); `ISS-2026-243` registered at Tier C (`reuseExistingServer` stale-build footgun). See `HDN-380.md` §13 |
| 13 | `HDN-381` | `CG-S15-HDN-013` | 381 | Browser and Device Compatibility | UX Assurance | `HDN-380` | `READY` — `HDN-380` (`CG-S15-HDN-012`) now `VERIFIED` |
| 14 | `HDN-382` | `CG-S15-HDN-014` | 382 | Observability | Reliability Assurance | `HDN-370` | `BLOCKED` |
| 15 | `HDN-383` | `CG-S15-HDN-015` | 383 | Backup and Restore | Reliability Assurance | `HDN-382` | `BLOCKED` |
| 16 | `HDN-384` | `CG-S15-HDN-016` | 384 | Disaster Recovery Rehearsal | Reliability Assurance | `HDN-383` | `BLOCKED` |
| 17 | `HDN-385` | `CG-S15-HDN-017` | 385 | Data Migration Rehearsal | Migration Assurance | `HDN-371` | `BLOCKED` |
| 18 | `HDN-386` | `CG-S15-HDN-018` | 386 | Integrated Verification | Hardening Closure | `HDN-370..385` **all `VERIFIED`** | `BLOCKED` |
| 19 | `HDN-387` | `CG-S15-HDN-019` | 387 | Release Blocker Triage and Remediation | Hardening Closure | `HDN-386` | `BLOCKED` |
| 20 | `HDN-388` | `CG-S15-HDN-020` | 388 | Documentation Handoff | Hardening Closure | `HDN-387` | `BLOCKED` |
| 21 | `HDN-389` | `CG-S15-HDN-021` | 389 | Closure Verification | Hardening Closure | `HDN-388` | `BLOCKED` |

**Tally: 21 rows — 1 `COMPLETED` (kickoff), 8 `BLOCKED`, 1 `READY` (`HDN-381`),
11 `VERIFIED` (`HDN-370`, `HDN-371`, `HDN-372`, `HDN-373`, `HDN-374`, `HDN-375`, `HDN-376`, `HDN-377`, `HDN-378`, `HDN-379`, `HDN-380`).**

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
| 2026-08-23 | `HDN-374` | `CG-S15-HDN-006` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-374.md` | **`VERIFIED`** — Tier C closed. Four independent parallel investigation lenses (revenue chain; cost/AP chain; period lock/reversal/concurrency/rounding; loyalty liability/payroll/tax/statutory), each required to live-force its own findings on disposable databases. Cost/AP chain, payment/journal reconciliation, period lock, reversal, correction, rounding, tax snapshotting, payroll-handoff aggregation, and RPD-016's statutory gates all held clean in the first round. **4 real, live-forced defects fixed** at `20260811000000_harden_financial_integrity_invoicing_and_idempotency.sql`: `ISS-2026-194` (High, quote-level tax silently double-applied at invoicing); `ISS-2026-195` (High, a job order could reach `issued` on two full-amount invoices from two distinct handoffs — **the first fix draft was self-corrected before commit**: it gated invoice preparation itself, which would have broken `OPS-181`'s own disclosed legitimate-re-handoff allowance and an existing db-test fixture; the shipped fix gates `app.issue_finance_invoice`, the actual AR/GL posting boundary, instead); closes `ISS-2026-162`'s Finance/HRIS-Payroll scope (Medium, 10 functions, 2 mechanisms live-forced with a genuine two-process race each); `ISS-2026-196` (Medium, `app.run_loyalty_expiry_sweep`'s own `p_as_of` parameter was silently ignored, now threaded through). **Tier C review (four independent adversarial lenses) found 5 more real, live-forced defects**: `app.lock_finance_period` shared the exact idempotency-race shape the checkpoint's own sweep missed (Medium, fixed); Finding 1's own fix dropped the quote's own discount, overbilling by that amount (High, fixed — `subtotalAmount` is the raw pre-discount gross, the genuine base is `subtotalAmount - discountAmount`); Finding 2's own new guard had no backing constraint and did not survive genuine concurrency, live-forced to still double-bill under a real two-process race (High, fixed with a real backing partial unique index, `finance_invoices_job_order_issued_unique`); `app.request_finance_settlement_reversal` bypassed fiscal period lock entirely (High, fixed, mirroring `post_finance_settlement`'s own check) and **posts no reversing GL journal at all**, permanently desyncing GL from AP on every reversal (High, **registered, not fixed** — `ISS-2026-199`/`HDN-BLK-016`, owner `HDN-386`, a design decision outside this bounded-repair checkpoint's own scope). One further disclosure correction (`ISS-2026-198`, Medium, already fixed but undisclosed — `app.prepare_finance_vendor_bill_from_actual_cost`'s own idempotency predicate) and one ledger-consistency finding (`CARGOGRID_BUILD_STATUS.md`'s own stale summary row) also corrected. Fixing the two fixture files that broke against the new `finance_invoices_job_order_issued_unique` invariant (`customer-invoice-billing-visibility.sql`/`customer-payment-visibility.sql`, each giving 3 issued invoices their own distinct job order) changed nothing either file actually tests — `job_order_id` is a purely internal FK neither file's own customer-portal READ layer ever surfaces. `ISS-2026-197` (Low, owner `HDN-386`, no FX/multi-currency conversion anywhere in the revenue chain; Operations' own job-profitability planned-vs-actual split) and `ISS-2026-162`'s residual 3 non-Finance functions plus `ISS-2026-163` (owner `HDN-387`) remain registered, not fixed, explicitly out of this lane's own charter. Independent full gate re-run green after the complete fix pass: `typecheck` 0, `lint` 0 errors/337 warnings, 5394/5394 unit tests, 229/229 db-tests (319 migrations), fresh disposable database with real grants. Three additive migrations total, 7 existing db-test files extended with new regression coverage, zero application code, zero contract, zero route. Full disposition: `HDN-374.md` §6/§12/§13 |
| 2026-08-24 | `HDN-375` | `CG-S15-HDN-007` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-375.md` | **`COMPLETED`** — Tier C review pending. Four independent parallel investigation lenses (canonical lineage chain lead→loyalty; downstream projection versioning; hash-chain triggers and historical config preservation; orphan records and no-silent-reentry), each required to live-force its own findings on disposable databases. Canonical lineage, projection versioning, historical config preservation, and permission-awareness all held clean. **2 real, live-forced defects fixed** at `20260812000000_harden_data_lineage_audit_findings.sql`: `ISS-2026-201` (High, `app.transaction_lineage_edges` — OPS-184's own lineage-evidence ledger — had no `BEFORE UPDATE/DELETE` guard at all despite its own "append-only, never-updated, never-deleted" contract; fixed by mirroring CPL-325's own proven append-only-guard pattern, scoped to this one table); `ISS-2026-202` (Medium, `app.loyalty_earning_events`/`app.finance_journals` accept a `source_id` with no DB-layer FK, enforced only by RPC discipline; fixed with a `BEFORE INSERT OR UPDATE` per-`source_type` validation trigger on each table). **1 finding registered, not fixed** (`ISS-2026-200`/`HDN-BLK-017`, High, owner `HDN-386`): the 5 "hash-chain" lineage triggers are standalone per-row content fingerprints, not a genuine `H_n = f(H_{n-1}, content_n)` chain, and `app.detect_transaction_lineage_anomalies` has no hash-mismatch/tamper-detection anomaly type — a design decision outside this bounded-repair checkpoint's own scope. Gates: `typecheck` 0, `lint` 0 errors/337 warnings, 5394/5394 unit tests, db-tests **228/229 files clean** (320 migrations) — the 229th, `procurement-vendor-performance.sql`, hit a pre-existing, unrelated, incidentally-found wall-clock/day-window defect confirmed independent of this checkpoint's own migration (registered `ISS-2026-204`, owner `HDN-387`, not this lane's charter), fresh disposable database with real grants. One additive migration, 3 pre-existing fixtures corrected/extended across 2 db-test files, zero application code, zero contract, zero route. Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-375.md` §6/§12 |
| 2026-08-24 | `HDN-375` | `CG-S15-HDN-007` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-375.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel lenses (correctness re-derivation; schema-wide completeness sweep; ledger/documentation consistency; permission-awareness/attack-surface adversarial testing), each required to live-force its own findings on disposable databases. All 3 first-round findings confirmed real and correctly disposed of; both shipped fixes confirmed solid under live adversarial attack (full role/permission matrix, `NULL`-actor-context, audit-capture correctness, `TRUNCATE`-bypass angle, exhaustive `source_type` coverage — no bypass found). **1 documentation-completeness gap corrected**: this build log's own §6.2 had silently omitted `ISS-2026-203` (already registered in `KNOWN_ISSUES.md`, a genuine Lens-2 finding) from its own outcome count — corrected. **1 repeated ledger inconsistency corrected**: 5 files stated "3 existing db-test files corrected/extended," conflating 3 fixture corrections with 3 files (the actual commit touched 2) — corrected in all 5. **2 new, real, in-charter findings found and registered, not fixed**: `ISS-2026-205`/`HDN-BLK-018` (High, owner `HDN-386`) — only 13 of ~90+ append-only/audit/ledger-shaped tables in schema `app` carry a real `BEFORE UPDATE/DELETE` guard trigger; ~70 more, live-forced-reachable, do not, most severely `app.audit_logs` itself (the audit trail every other detective control depends on, including this checkpoint's own new guard); `ISS-2026-206` (Medium, owner `HDN-387`) — the orphan-`source_id` gap `ISS-2026-202` closed on 2 tables recurs on `app.finance_subledger_batches` and others; **a fix draft for the first of these was written, then discovered before commit to break `scripts/db-tests/finance-subledger.sql`'s own pre-existing, deliberate test design (~15 call sites exercising the posting primitive in isolation with synthetic source ids) — self-corrected, the draft discarded rather than shipped broken or hastily patched**, mirroring `HDN-374`'s own Finding-2 self-correction precedent. No Critical finding anywhere. Gate state unchanged from the first round (§12) since no code changed in this Tier C pass — re-confirmed independently by 2 of the 4 lenses' own live testing against fresh disposable databases. Zero migration, zero application code, zero contract, zero route in this Tier C pass — documentation and ledger evidence only. **`CG-S15-HDN-007` is `VERIFIED`.** `CG-S15-HDN-008` (`HDN-376`, Prompt 376, API Compatibility Audit) is now the next eligible prompt. Full disposition: `HDN-375.md` §13 |
| 2026-08-24 | `HDN-376` | `CG-S15-HDN-008` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-376.md` | **`COMPLETED`** — Tier C review pending. Four independent parallel investigation lenses (REST/GraphQL contract parity; webhook signing/retry/replay/DLQ and idempotency; schema/migration compatibility and cross-cutting idempotency/rate-limit/error-shape/pagination consistency; public/customer/vendor API and deprecation), each required to live-force its own findings. **Standout finding, Critical, fixed**: `app.verify_third_party_provider_webhook_signature` (inbound third-party GPS webhook gate) returned SQL NULL, not false, for a null signature, so `if not verify_...()` silently accepted a fully unsigned webhook as genuine — live-forced a real telemetry report inserted with `p_signature => null`, `anon`-reachable directly via PostgREST, bypassing the app-layer check entirely (`ISS-2026-209`). Fixed by mirroring 2 sibling functions' own already-proven null/empty-signature guard. The identical latent defect in `app.verify_webhook_signature` (PLT-129, not currently live-exploitable) also fixed for consistency (`ISS-2026-210`, High). **2 more real defects fixed** (`ISS-2026-211`/`212`, both Low): a webhook-domain error code leaking onto 2 non-webhook mutation routes; `stale_version` conflating a 400 malformed-input case with a real 409 conflict on 3 routes. **`ISS-2026-147` item 1 closed**: 9 REST `/v1` route handlers had zero dedicated test coverage; built a shared fetch-stubbing harness (no local PostgREST/Supabase stack available) plus 44 new route-level tests across all 9 handlers. `HARDENING_MATRIX.md` §7's GraphQL wording corrected (live-forced: no GraphQL surface exists in this repository at all). **2 findings registered, not fixed**: `ISS-2026-207` (Medium, owner `HDN-387`) — the `app.api_versions` deprecation registry has zero live effect on real requests, not a Step 16 blocker since only v1 exists; `ISS-2026-208` (Low, owner `HDN-387`) — `accept`/`decline_vendor_assignment_invitation_via_vendor_api` lack an idempotency-key short-circuit, investigated for a same-checkpoint fix and found not bounded-repair-sized (the table's own existing idempotency_key column serves a different purpose). A pre-Step-15 migration-editing historical fact (3 commits, 86 files, predating HDN-369) reconciled against the additive-only rule with one acknowledging sentence, no fix required. No Critical finding residual anywhere. Gates: `typecheck` 0, `lint` 0 errors/337 warnings, 5438/5438 unit tests (+44 new), db-tests 228/229 files clean (321 migrations) — the 229th the same pre-existing `ISS-2026-204` flake. One additive migration, 2 db-test files gained regression blocks, 5 route TS files fixed, 10 new test files. Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-376.md` §6/§12 |
| 2026-08-24 | `HDN-376` | `CG-S15-HDN-008` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-376.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel lenses (correctness re-derivation; schema-wide completeness sweep for the same defect classes; ledger/documentation consistency; attack-surface adversarial testing), each required to live-force its own findings. Both first-round Critical/High webhook fixes confirmed solid under live adversarial re-attack. **1 new real defect found and fixed same checkpoint**: `ISS-2026-215` (Low) — `GET /api/v1/vendor/rfqs/{id}` and `GET /api/v1/customer/shipments/{id}/tracking` both blanket-mapped every RPC failure to a 404 not-found response, silently conflating a genuine internal/transient RPC error (e.g. a serialization failure) with the real "does not exist" case; live-forced via a mocked non-domain RPC error on each route. Fixed by classifying `VendorApiError` (previously unclassified — verified its sole consumer, `getRfqForVendorApi`, before touching it) and branching `CustomerShipmentTrackingQueryError` the same way `record_not_found`/`actor_identity_mismatch` already imply 404. **1 documentation-citation error corrected**: the first-round migration's own `comment on function` for `app.verify_third_party_provider_webhook_signature` mislabeled this checkpoint as "HDN-376 (Data Lineage/API Compatibility Audit)" — "Data Lineage Audit" is `HDN-375`'s own name; corrected via an additive `comment on function` restatement, no schema/behavior change. `00_EXECUTION_INDEX.md` §2.2's own additive-migration-only reconciliation note's date citation also corrected (`20260804030000` → `20260809100000`). **2 findings registered, not fixed**: `ISS-2026-213` (Low, owner `HDN-386`) — 6 self-approval-shaped `SECURITY DEFINER` functions share the same equality-comparison shape as the fixed webhook defect, but are confirmed safe today because an authority gate already excludes a NULL actor before reaching that comparison; registered as defense-in-depth rather than fixed, live-forced to confirm no live bypass exists; `ISS-2026-214` (Low, owner `HDN-387`) — 4 routes leak a raw Zod validation-error shape to the caller instead of the repository's own standard error envelope. No Critical finding anywhere. Independent full gate re-run green: `typecheck` 0, `lint` 0 errors/337 warnings, 5440/5440 unit tests (+2 new regression tests), db-tests 228/229 files clean (322 migrations) — the 229th the same pre-existing `ISS-2026-204` flake, re-confirmed still within its documented UTC `[1,4)` window. One additive migration (`20260813100000`), 2 route TS files fixed, 1 query file gained error classification, 2 existing test files corrected and extended. **`CG-S15-HDN-008` is `VERIFIED`.** `CG-S15-HDN-009` (`HDN-377`, Prompt 377, Storage and Signed URL Audit) is now the next eligible prompt. Full disposition: `HDN-376.md` §13 |
| 2026-08-24 | `HDN-377` | `CG-S15-HDN-009` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-377.md` | **`COMPLETED`** — Tier C review pending. Four independent parallel investigation lenses (upload/scan/quarantine gate; signed URL expiry/scope/revocation/replay resistance; file access audit and retention/legal hold; cross-tenant/RLS on file-shaped tables), each required to live-force its own findings. **2 Critical findings fixed**: `ISS-2026-216` — `app.files.storage_path` (the real Supabase Storage object key) carried a full table-level SELECT grant to `authenticated` with no column-level mask, found independently by 3 of 4 lenses; live-forced, `pending`/`infected` files both still returned the key; fixed mirroring `app.users`/`email`'s own proven column-level carve-out, plus a new `FileSummary` contract type and 2 TS call sites (the HRIS employee-document page shipped it to the browser via Client Component props, the only such surface in the repo). `ISS-2026-217` — two independently-built legal-hold mechanisms for files (PLT-128-native vs IAE-031 generic) were unaware of each other in both directions, live-forced; fixed by bridging `app._is_under_legal_hold()`. **1 High fixed**: `ISS-2026-218` — `app.files.legal_hold` enforced only inside one RPC, no schema-level backstop against a raw DELETE; fixed with a narrowly-scoped BEFORE DELETE guard trigger mirroring HDN-375's own proven RPD-022 pattern. **3 Medium fixed**: `ISS-2026-219` (vendor evidence-access RPCs leaked file_id on their own content-gate denial branch), `ISS-2026-220` (2 Procurement file-shaped tables' RLS bypassed PRC:View/Download, same class HDN-373 fixed for finance_journals), `ISS-2026-221` (vendor-assessment evidence upload called a service_role-only RPC through the wrong client, mirroring an already-fixed sibling). **2 new taxonomy classes added** to `RECURRING_DEFECT_TAXONOMY.md` per its own §6 mandate: C-25 (dual independently-built enforcement mechanisms unaware of each other) and C-26 (RPC-level check with no schema-level backstop). **4 findings registered, not fixed**: `ISS-2026-222` (High, owner `HDN-386`) — legal hold does not extend to protect a file's own access-log rows, cross-references `HDN-BLK-018`, own new `HDN-BLK-019` entry; `ISS-2026-223` (Low, owner `HDN-378`) — ordinary tenant_admin bypasses file gates via a misused `is_support_grant_authority` predicate, a repository-wide ~35-domain convention question, not a bounded repair; `ISS-2026-224` (Medium, owner `HDN-387`) — `can_access_record` over-restricts legitimate Procurement evidence reviewers; `ISS-2026-225` (Low, owner `HDN-378`) — the same coarse-RLS-plus-fine-RPC-gate pattern recurs across ~69 Procurement/~17 HR tables, most safe by construction, full sweep out of scope. No Critical finding residual anywhere. Gates: `typecheck` 0, `lint` 0 errors/337 warnings, 5440/5440 unit tests, db-tests 228/229 files clean (323 migrations) — the 229th the same pre-existing `ISS-2026-204` flake. One additive migration, 4 db-test files gained regression blocks, 3 route/action TS files fixed, 2 contract/query TS files changed. Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-377.md` §6/§12 |
| 2026-08-24 | `HDN-377` | `CG-S15-HDN-009` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-377.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel adversarial lenses (correctness re-derivation; schema-wide completeness sweep for the same defect classes; ledger/documentation consistency; attack-surface adversarial testing) ran against the committed first-round state (`b537866`). All 6 first-round fixed findings independently re-derived and confirmed solid, including 2 edge cases the shipped regression suite itself left untested. **1 Critical, self-inflicted bypass found and fixed**: `ISS-2026-226` — the first round's own new `BEFORE DELETE` guard trigger checked only the native `legal_hold` flag, never the bridged generic hold mechanism the SAME migration added elsewhere in the same commit; a generically-held file could still be physically destroyed via a raw `service_role` DELETE, with no exception raised and no audit event captured. **2 more same-domain gaps fixed**: `ISS-2026-227` (High) — the legal-hold check had no schema backstop against the UPDATE-based soft-delete path, only the physical DELETE; `ISS-2026-228` (Medium-High) — `scope_record_table` was unvalidated free text, a case/whitespace variant silently created a non-protecting hold, now normalized and validated. **1 finding drafted then self-corrected before commit**: a matching scan-status backstop trigger broke 4 pre-existing, deliberately-designed tests across other domains that rely on a session-context-free raw-UPDATE correction path; discarded, registered instead (`ISS-2026-231`, Medium, owner `HDN-386`). **2 new, real, out-of-charter findings registered**: `ISS-2026-229`/`HDN-BLK-020` (Critical, owner `HDN-386`) — `app.audit_logs.legal_hold` enforced nowhere, a legally-held audit row was physically deleted; `ISS-2026-230`/`HDN-BLK-021` (High, owner `HDN-386`) — `app.tenants.legal_hold` unbridged, a held tenant was terminated successfully. **1 first-round disposition corrected**: `ISS-2026-225`/`HDN-BLK-022` — Tier C independently found 60 (not "most safe") Procurement/HR tables with a real `authenticated` grant, ~35 confirmed RLS-bypass-exploitable, 2 live-forced; corrected from Low to High. **1 more out-of-charter finding registered**: `ISS-2026-232` (Medium, owner `HDN-378`) — 3 more `token_hash` columns share `ISS-2026-216`'s own exposure class. **Several documentation miscounts corrected** across 9 ledger files (a self-contradicting "2 Medium"/"3 Medium" line, a "6 db-test files"/"6 TS files" miscount that had propagated into 5 documents, 2 `CHANGE_MANIFEST.md` overcounts, 1 stale `BLOCKER_LEDGER.md` footer). No Critical finding fixed-vs-registered residual — the one registered Critical is a pre-existing, out-of-charter `app.audit_logs` gap bundled with the already-owned `HDN-BLK-018` work. Independent full gate re-run green: `typecheck` 0, `lint` 0 errors/337 warnings, 5440/5440 unit tests, db-tests 228/229 files clean (324 migrations) — the 229th the same pre-existing `ISS-2026-204` flake. One more additive migration (`20260814100000`), `document-file.sql` gained 3 more regression blocks. **`CG-S15-HDN-009` is `VERIFIED`.** `CG-S15-HDN-010` (`HDN-378`, Prompt 378, Security Hardening) is now the next eligible prompt. Full disposition: `HDN-377.md` §13 |
| 2026-08-24 | `HDN-378` | `CG-S15-HDN-010` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-378.md` | **`COMPLETED`** — first round only, Tier C review pending. Four independent parallel investigation lenses (IP-restriction route-handler wiring feasibility; `create_integration_connection`'s own remaining step-up-MFA gap scoping; OWASP-style abuse-pattern sweep across 10 categories; extension relocation/dependency-scan/secrets-redaction/runbook infra items), each required to live-force its own findings on a disposable database. **The checkpoint's own single highest-priority item, `ISS-2026-150` (High, "must not be deferred again"), is `RESOLVED`** at `20260815000000_harden_ip_restriction_iss150_closure_wiring.sql`: `app.assert_ip_allowed`/`app.has_active_ip_allowlist_bypass` composed into all 4 platform-default high-risk functions (`decide_ai_output_approval`, `activate_enterprise_idp_connection`, `approve_mfa_exception`, `create_integration_connection`), trailing `p_client_ip` param, scope `'admin'`. **A genuine implementation defect was caught and fixed before commit, not shipped**: a first `CREATE OR REPLACE FUNCTION` draft silently created a second overload per function instead of replacing it (Postgres does not treat an added trailing parameter as a signature match), which would have left every existing caller permanently bound to the OLD, un-gated version — corrected to an explicit `DROP FUNCTION` + `CREATE FUNCTION` + re-`GRANT EXECUTE` for all 4 (verified against each function's own origin migration), re-verified (exactly one overload each, correct grants, 11 db-test files clean). `ISS-2026-151` (the sibling step-up gap on the same function) re-scoped precisely — 43 real call sites, 27 distinct step-up sequences, across the same 16 files — and deliberately deferred again rather than stack it onto this checkpoint's own bounded-repair budget. `pg_trgm`/`btree_gist` relocated out of `public`; `postgis` found structurally non-relocatable (`relocatable = false`, would destroy 15 live `geography` columns across 12 tables if forced) — the matrix's own "clears 7 of 8" claim corrected to "clears 2 of 8", the remaining 6 registered separately (`ISS-2026-234`). Full OWASP-style abuse sweep across 10 categories: 9 held (SQLi, IDOR, CSRF, XSS, rate limiting, API-key handling, webhook signature verification, file-upload validation, AI-governed-action human approval); 1 Medium finding (open-redirect control-character bypass) found and fixed (`ISS-2026-233`). `ISS-2026-168` (service-role import boundary) closed via a new ESLint `no-restricted-imports` rule scoped to the 27 real legitimate importers. **2 more findings surfaced and fixed, both pre-existing and already owned by this checkpoint, neither covered by any of the 4 lenses**: `ISS-2026-169` (a vendor self-registration action's already-unified error message still leaked its raw tenant-existence discriminator on the wire) and `ISS-2026-232` (3 more `token_hash` columns exposed via a blanket grant, `20260815300000_harden_token_hash_column_privilege_iss232_closure.sql`) — fixing the latter required catching and fixing a **second** real regression: 2 query functions used a bare `select("*")` against the now-column-restricted tables, one with a real live `authenticated`-session caller that would have started failing with a permission error. `ISS-2026-149`/`146` reconfirmed and re-measured (2,335 occurrences, up from 2,087), severity unchanged, both still deferred. Dependency scan clean; `ISS-2026-158`'s CI-enforcement gap reconfirmed, unchanged, owner `HDN-387`. 4 new runbooks/checklists authored. **No Critical finding anywhere.** Full gate: `typecheck` 0, `lint` 0 errors/337 warnings, `pnpm run test` 5443/5443, db-tests **229/229 files clean** (327 migrations) — confirmed by two independent full-suite runs. Three additive migrations, 4 db-test files gained new regression blocks, 16 application-layer files changed (15 TS + eslint.config.js), 4 new runbook docs. Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-378.md` |
| 2026-08-24 | `HDN-378` | `CG-S15-HDN-010` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-378.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel adversarial lenses (correctness re-derivation; schema-wide completeness sweep; ledger/documentation consistency; attack-surface adversarial testing) ran against the committed first-round state (`ca7f300`). Lens 1 independently re-derived all 7 first-round claims and found no defect; full gates re-run clean. Lens 3 found and this checkpoint corrected 5 real documentation miscounts in its own first-round propagation (commit `3fbf665`, before this close): an entry-gate unit-test count that contradicted its own close-gate figure, a stale "40+ call sites" left beside its own "43" correction, a "9 TS files changed" undercount (real: 16) propagated into 5 documents, a self-contradicting db-test file count, and a "26 vs. actual 27" ESLint-importer count propagated into 7 documents. **2 Critical + 1 High genuine bypass found in this checkpoint's own first-round work, all fixed before close** (`supabase/migrations/20260815400000_harden_ip_restriction_tierc_fixes.sql`): `ISS-2026-232`'s own column-privilege fix was defeated by a second, more fundamental gap — all 3 "revoke" RPCs returned the full composite row including `token_hash` via `RETURNING`/return value, not subject to column-level `SELECT` privileges at all (taxonomy class `C-27`, new); `ISS-2026-168`'s ESLint fix only inspected static `import`/`export` declarations, evaded by `require()`/dynamic `import()`; the schema-wide sweep independently found `app.validate_webhook_url` shares `ISS-2026-233`'s own control-character gap (not exploitable end-to-end, fixed anyway). **The checkpoint's own headline claim required correction**: attack-surface testing found `app.set_integration_connection_status` — the shared, generic primitive `activate_enterprise_idp_connection` delegates to — independently bypasses the IP-restriction fix, the pre-existing IAE-026 lockout guard, and step-up-MFA simultaneously (live-forced end to end); `ISS-2026-150` corrected `RESOLVED` → `PARTIALLY RESOLVED`, registered as `ISS-2026-235`/`HDN-BLK-023` (Critical, owner `HDN-386`, taxonomy class `C-28`, new) — a design decision touching a heavily-reused shared primitive, exceeding what a Tier C pass should rush. The same sweep independently found 3 of `app.is_high_risk_action`'s own 7 hardcoded tuples (`SEC:Configure`, `FIN:Approve`, `HRS:Approve` — 61 real functions) never received step-up-MFA or IP-restriction wiring across the entire prior lineage, registered as `ISS-2026-236`/`HDN-BLK-024` (High, owner `HDN-386`). A pre-existing (two-weeks-prior, unrelated) `select("*")`-vs-column-restriction defect found in `automation-rule.ts`, registered as `ISS-2026-237` (Medium, owner `HDN-387`), mirroring `HDN-377`'s own `ISS-2026-224` precedent. Also corrected: `ISS-2026-150`'s own mis-cited taxonomy class (`C-24`, wrong — the real, new class for the earlier `CREATE OR REPLACE`-overload self-correction is `C-29`). 3 new taxonomy classes added per §6's own mandate: `C-27`, `C-28`, `C-29`. Independent full gate re-run after the fix pass: `typecheck` 0, `lint` 0 errors/337 warnings, 5443/5443 unit tests, db-tests **229/229 files clean** (328 migrations). One more additive migration (`20260815400000`). **`CG-S15-HDN-010` is `VERIFIED`.** `CG-S15-HDN-011` (`HDN-379`, Prompt 379, Performance and Scalability) is now the next eligible prompt. Full disposition: `HDN-378.md` §13 |
| 2026-08-24 | `HDN-379` | `CG-S15-HDN-011` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-379.md` | **`COMPLETED`** — first round only, Tier C review pending. Four independent parallel investigation lenses (`rbac-enforcement.sql` ATW-032 O(n²) scan performance; 892 unindexed-FK triage; load/performance-test evidence; `auth_rls_initplan` regression guard + API-boundedness/cross-tenant-cache verification), each required to live-force its own findings. **`ISS-2026-145` (the O(n²) scan, matrix §10 item 1) is `RESOLVED`**: the `edge` CTE rewritten from an `fn c join fn e` self-join to a one-pass `regexp_matches()` extraction, mirroring this same file's own sibling ATW-032/`ISS-2026-033` pattern unmodified — only edge construction changed, the `covered` recursive CTE's own transitive-closure walk untouched. Verified with a same-schema matched-pair run (original vs. rewrite, one transaction, one disposable database, no rebuild in between): original 692,092.8ms (~11.5 min), rewrite 556.4ms, verdicts byte-identical, **1244× speedup**. Full 229-file suite re-run clean. **892 `unindexed_foreign_keys` advisories categorized and deferred** (`ISS-2026-239`): a 4-bucket decision framework built from a 24-FK sample across 7 domains — zero high-confidence "index now" candidates (every hot column already has a serving composite index; cold candidates are write-only/audit-lineage columns where speculative indexing would be pure write-amplification on high-write-volume tables), deferred pending real production query telemetry that does not exist anywhere in this system yet. **`auth_rls_initplan` regression guard re-verified clean** (582 policy statements, 235 call sites, zero regression since the original 65-migration fix); 1 informational blind spot documented (`ISS-2026-240`) — a `default auth.uid()` helper-function pattern, 72 occurrences across 35 migrations, invisible to text-grep-based tooling by construction, the repository's own convention since day one, not a regression. **1 genuine new finding**: 3 production routes (Commercial accounts/quotations/contracts) load an entire tenant-wide dataset to the browser with zero pagination, live-verified via real `EXPLAIN (ANALYZE, BUFFERS)` evidence at a seeded 25,000/10,000-row volume — self-disclosed only in a code comment before this checkpoint, never promoted to `KNOWN_ISSUES.md` (`ISS-2026-238`, Medium, ~10 lower-severity siblings named). Existing `scripts/load-tests/` harness (Phase 5 scope) re-confirmed live and green, 8/8 scenarios, real p50/p95/p99 evidence; new `EXPLAIN` evidence gathered for 9 endpoints across 5 domains. `ISS-2026-141`/`148`'s own overall evidence-gap ruling reconfirmed unchanged. No unbounded `/api/v1`/webhook response, no cross-tenant cache key gap, no queue-backpressure gap found — all verified clean by 2 independent lenses. **No Critical or High finding anywhere.** Full gate: `typecheck` 0, `lint` 0 errors/337 warnings, `pnpm run test` 5443/5443 (unchanged), db-tests **229/229 files clean** (328 migrations, unchanged). Zero migrations, one test-infrastructure file changed (`scripts/db-tests/rbac-enforcement.sql`). Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-379.md` |
| 2026-08-24 | `HDN-379` | `CG-S15-HDN-011` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-379.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel adversarial lenses (correctness re-derivation; schema-wide completeness sweep; ledger/documentation consistency; attack-surface adversarial testing) ran against the committed first-round state (`57ce9fb`). **Lens 4 (attack-surface) found and this checkpoint fixed a real structural weakening in the checkpoint's own headline fix**: the first-draft `edge` CTE rewrite dropped a `\m` word-boundary anchor and a real join-against-`fn` requirement the original self-join carried "for free" — live-forced 876 spurious edges on the real 2,700-function schema (zero colliding with any real function name, so no wrong verdict today, but a future collision could have silently defeated the guard); fixed by restoring both properties (`and m[1] in (select proname from fn)`, a hash semi-join, not a new cross join), re-timed at **1.66 seconds**, both gaps confirmed closed via live reproduction with 3 scratch functions. **Lens 1 (correctness re-derivation) found the first round's own timing precision did not reproduce**: an independent same-schema matched-pair re-measurement got 212,105.6ms/≈313× rather than 692,092.8ms/1244× — both real, honest measurements, the ~3× spread reflects real sandbox contention variance at measurement time, not a methodology flaw; cite "300×-1200×+" for this fix going forward. Also found `ISS-2026-239`'s claim that no RPC filters through `audit_logs.actor_auth_user_id` was factually wrong — `app.search_audit_logs` does (zero live UI callers today, so the "don't index yet" conclusion is unchanged, the evidence was fixed). **Lens 2 (schema-wide completeness sweep) found 5 new unbounded-dataset instances** `ISS-2026-238` missed, most notably a 4-list unbounded fleet-assets page (`listVehicleOperationalProfiles`/`listDriverOperationalProfiles`/`listGpsDevices`/`listSimCards`); everything else (more O(n²) self-joins, an independent unindexed-FK sample, other RLS-performance patterns, cache/backpressure) came back clean. **Lens 3 (ledger/documentation consistency) found and this checkpoint corrected 6 real documentation miscounts**: `auth.*()` call-site count (236→235), `default auth.uid()` pattern count (73/~40→72/35), a stale "~2,900 functions" figure left beside its own "2,700" correction, 2 never-updated `BLOCKER_LEDGER.md` entries (`HDN-BLK-005`/`006`, both resolved/ruled on this checkpoint), a misleading "1,766 FKs across 424 tables" phrasing (424 is the unindexed-FK-only table count; the full population spans ~570 tables), and a minor line-citation drift. **`ISS-2026-238` corrected and expanded**: `listFilesForTenant` reclassified Medium (a polymorphic, transactional-volume attachment table, not the bounded config table it was originally characterized as) — now 4 confirmed Medium routes, plus 5 new Lens-2-found siblings folded in. No Critical or High finding at either round. Independent full gate re-run after the fix pass: `typecheck` 0, `lint` 0 errors/337 warnings, `pnpm run test` 5443/5443, db-tests **229/229 files clean** (328 migrations, unchanged — zero migrations at either round). **`CG-S15-HDN-011` is `VERIFIED`.** `CG-S15-HDN-012` (`HDN-380`, Prompt 380, Accessibility) is now the next eligible prompt. Full disposition: `HDN-379.md` §13 |
| 2026-08-24 | `HDN-380` | `CG-S15-HDN-012` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-380.md` | **`COMPLETED`** — first round only, Tier C review pending. Three independent parallel investigation lenses (live-authenticated axe-core feasibility; source-level static-evidence sweep; live axe-core run against reachable routes). 6 color-contrast token failures fixed (`app/globals.css`, WCAG-computed replacements — `--color-primary`/`-hover`, `--color-neutral-400`/`-500`, `--color-success`, `--color-warning`), using the authority `DESIGN_SYSTEM.md` §2.1's own disclosed-pending-validation status provides. `eslint-plugin-jsx-a11y`'s `recommended` preset wired repository-wide (`eslint.config.js`, referencing the plugin `next`'s own config already registers to avoid a flat-config plugin-redefinition collision), surfacing exactly 14 real errors app-wide, all fixed across 5 files (13 `label-has-associated-control`, 1 `no-autofocus`). 454/454 inline error displays app-wide now carry `role="alert"` (7 were missing it, one fix also correcting a dead `text-danger-600` Tailwind class with no backing token). **`HDN-BLK-009`/`ISS-2026-160` root-caused precisely and `RESOLVED`**: 5 `e2e/vendor-registration.spec.ts` failures were live-forced via a standalone reproduction script to a Turbopack dev-mode hydration-timing race (new taxonomy class `C-30`), not an application defect — the identical click resolved in under 500ms against a production build. Fixed at the root by switching `playwright.config.ts`'s `webServer.command` from `next dev` to `next build && next start` (timeout raised 60s→180s); full suite now **18/18**, zero 500s, zero hangs, up from 13 passed/5 failed — directly serves this lane's own "`next build` required from this lane onward" instruction. `ISS-2026-140`/`153` tracked gap widened with a precise `RLIMIT_NOFILE`/`runc` container-runtime root cause (Postgres boots cleanly in this sandbox; every non-Postgres Supabase service container does not) rather than left as the vaguer inherited "no live sign-in flow" description. 2 large architectural gaps found and registered, not fixed (out of this checkpoint's own "5-15 files, bounded repair" charter): `ISS-2026-241` (36 of 38 tenant modules have no `<main>` landmark, independently re-derived directly against the file tree — 38 module directories, only `admin`/`commercial` have one), `ISS-2026-242` (accessible form primitives `FormField`/validation-message adopted in only ~2% of the 200 files that render a form; `aria-invalid` in only 5 files app-wide). A prior investigation's "565 unlabeled form controls across 101 files" figure did not reproduce under the authoritative rule for that exact check (`jsx-a11y/label-has-associated-control`, 0 errors app-wide after this checkpoint's own 14 fixes) — a broader trial with the wrong rule (`control-has-associated-label`, which does not recognize `htmlFor`/`id` pairing) produced 1040 false-positive-heavy flags instead; corrected here rather than silently propagated. No Critical or High finding anywhere. Independent full gate: `typecheck` 0, `lint` 0 errors/337 warnings, `pnpm run test` **5443/5443**, `pnpm exec next build` clean, `pnpm run test:e2e` **18/18**, `bash scripts/db-tests/run.sh` **229/229 `ALL PASSED`** (328 migrations, unchanged — no schema change). Taxonomy: `C-30` added (dev-mode-only e2e harness hang masquerading as an application defect). **`CG-S15-HDN-012` first round `COMPLETED`.** Tier C review (§13) required before `VERIFIED`. Full disposition: `HDN-380.md` |
| 2026-08-24 | `HDN-380` | `CG-S15-HDN-012` | `claude/step-15-hdn-369-kickoff-w6qren` | see `HDN-380.md` §13 | **`VERIFIED`** — Tier C closed. Four independent parallel adversarial lenses (correctness re-derivation; schema-wide completeness sweep; ledger/documentation consistency; attack-surface adversarial testing) ran against the committed first-round state (`4c5802f`). **No Critical or High finding at either round** — unlike `HDN-378`'s and `HDN-379`'s own Tier C passes, all 5 of the attack-surface lens's own attacks held up (label/id collision risk; the `command-menu.tsx` autoFocus→useEffect fix live-tested with a real Playwright script against a real browser, confirmed redundant-but-harmless given Radix's own `FocusScope`; background-vs-foreground contrast interaction, computed real; the feared `next build` env-var-inlining gap checked directly against real build output and found not to apply to this codebase; the `role="alert"` conditional-mount pattern confirmed as this codebase's own pre-existing convention, not a checkpoint-introduced gap). The correctness lens independently re-derived all 6 first-round claims exactly (including a skeptical dev-vs-prod test: temporarily reverted `playwright.config.ts` to `next dev`, reproduced the original hang, restored the committed state exactly, confirmed via `git diff`), surviving one connection-error interruption on its own final check with no work lost on relaunch. **The schema-wide completeness sweep found and this checkpoint fixed 3 small, real gaps**: 6 more missing `role="alert"` instances in `vendor-detail-panel.tsx` (used `<span>` not `<p>`, missed by the first round's own narrower sweep regex — re-swept afterward with a broadened pattern, 463/463, 0 missing); a stale doc comment in `e2e/tenant-admin-portal.spec.ts` still describing the harness as a real `next dev`; `C-30`'s own evidence section missing a cross-reference to an earlier, unrecognized precedent already recorded at `HDN-370` (a dev-runtime `RangeError: Map maximum size exceeded` crash, filed only as a secondary detail under `ISS-2026-160` at the time, never named its own class). **The ledger/documentation consistency lens found and this checkpoint fixed 1 more inconsistency**: `HARDENING_MATRIX.md`'s own top-level Gate index table still showed `NOT_RUN` for this lane despite that same document's own §11 recording it `COMPLETED` — also found stale, pre-existing, for rows 9 (`HDN-378`) and 10 (`HDN-379`); all 3 rows corrected together to match the pattern rows 1-8 already use. **The attack-surface lens found 1 new Low finding, registered not fixed**: switching `webServer.command` to a production build makes the pre-existing `reuseExistingServer` setting a real local-dev stale-build footgun — a leftover server now silently serves a frozen, un-rebuilt bundle instead of self-refreshing as `next dev` did (`ISS-2026-243`, owner a dedicated future task; `playwright.config.ts`'s own comment strengthened to name the risk explicitly). Independent full gate re-run after the fix pass: `typecheck` 0; `lint` 0 errors/337 warnings; `pnpm run test` **5443/5443** (unchanged); `pnpm exec next build` clean; `pnpm run test:e2e` **18/18** (unchanged); `bash scripts/db-tests/run.sh` **229/229 files clean** (328 migrations, unchanged — no schema change at either round). **`CG-S15-HDN-012` is `VERIFIED`.** `CG-S15-HDN-013` (`HDN-381`, Prompt 381, Browser and Device Compatibility) is now the next eligible prompt. Full disposition: `HDN-380.md` §13 |

---

## 16. Next eligible prompt

> ### `HDN-381` (Browser and Device Compatibility, `CG-S15-HDN-013`) is next eligible
>
> - **`HDN-380` (Accessibility) is `VERIFIED`.** 6 color-contrast token failures
>   fixed (`app/globals.css`, WCAG-computed replacements) using the authority
>   `DESIGN_SYSTEM.md` §2.1's own disclosed-pending-validation status provides —
>   `--color-primary`/`-hover`, `--color-neutral-400`/`-500`, `--color-success`,
>   `--color-warning`. `eslint-plugin-jsx-a11y`'s `recommended` preset wired
>   repository-wide (`eslint.config.js`, referencing the plugin `next`'s own
>   config already registers rather than re-registering it), surfacing exactly
>   14 real errors app-wide, all fixed across 5 files (13
>   `label-has-associated-control`, 1 `no-autofocus`). 454/454 inline error
>   displays app-wide now carry `role="alert"` (7 were missing it). **`HDN-BLK-
>   009`/`ISS-2026-160` root-caused precisely and `RESOLVED`**: 5
>   `e2e/vendor-registration.spec.ts` failures were live-forced to a Turbopack
>   dev-mode hydration-timing race (new taxonomy class `C-30`), not an
>   application defect — the identical click resolved instantly under a
>   production build. Fixed at the root by switching
>   `playwright.config.ts`'s `webServer.command` from `next dev` to
>   `next build && next start`; the full suite now passes **18/18**, zero 500s,
>   zero hangs (up from 13 passed/5 failed). `ISS-2026-140`/`153` widened with a
>   precise `RLIMIT_NOFILE`/`runc` container-runtime root cause (Postgres boots
>   cleanly in this sandbox; every non-Postgres Supabase service container does
>   not). 2 large architectural gaps found and registered, not fixed (out of
>   this checkpoint's own "5-15 files, bounded repair" charter):
>   `ISS-2026-241` (36 of 38 tenant modules have no `<main>` landmark,
>   independently re-derived against the file tree), `ISS-2026-242`
>   (accessible form primitives adopted in only ~2% of the 200 files that
>   render a form). A prior "565 unlabeled form controls" figure did not
>   reproduce under the authoritative rule for that exact check (0 errors
>   app-wide after this checkpoint's fixes) — corrected, not silently dropped.
>   No Critical or High finding at the first round. **Tier C review (4
>   independent adversarial lenses against commit `4c5802f`) found no Critical
>   or High finding at either round** — unlike `HDN-378`'s and `HDN-379`'s own
>   Tier C passes, every attack held up (label/id collision risk, the
>   `command-menu.tsx` focus-race live-tested with a real Playwright script,
>   background-contrast interaction, the `next build` env-inlining fear
>   checked against real build output, the `role="alert"` conditional-mount
>   pattern). 3 small, real gaps found and fixed same pass: 6 more missing
>   `role="alert"` instances in `vendor-detail-panel.tsx` (used `<span>` not
>   `<p>`, missed by the first round's own narrower sweep regex); a stale doc
>   comment in `e2e/tenant-admin-portal.spec.ts` still describing the harness
>   as `next dev`; `C-30`'s own evidence section missing a cross-reference to
>   an earlier, unrecognized precedent already recorded at `HDN-370` (a
>   dev-runtime `RangeError` crash, filed only under `ISS-2026-160` at the
>   time). 1 more ledger inconsistency found and fixed:
>   `HARDENING_MATRIX.md`'s own top-level Gate index table still showed
>   `NOT_RUN` for this lane (and, found stale pre-existing, for `HDN-378`/
>   `HDN-379` too) despite each being `COMPLETED`/`VERIFIED` in its own
>   detailed section — all 3 rows corrected together. 1 new Low finding
>   registered: `ISS-2026-243` (switching the e2e harness to a production
>   build makes the pre-existing `reuseExistingServer` setting a real
>   local-dev stale-build footgun, owner a dedicated future task). Broadened
>   `role="alert"` completeness re-sweep: 463/463, 0 missing. Independent full
>   gate re-run after the Tier C fix pass: `typecheck` 0, `lint` 0/337
>   warnings, 5443/5443 unit tests, `next build` clean, `test:e2e` 18/18,
>   229/229 db-tests (328 migrations, unchanged — no schema change at either
>   round). Full disposition: `HDN-380.md` §13.
> - **`CG-S15-HDN-013` (`HDN-381`, Prompt 381, Browser and Device Compatibility) may now begin.**
> - **Prior checkpoint summary (`HDN-379`, Performance and Scalability) — is
>   `VERIFIED`.** `ISS-2026-145` (the O(n²) `rbac-enforcement.sql` scan)
>   `RESOLVED`, matched-pair verified twice (300×-1200×+ speedup); a real
>   structural weakening in the fix itself found and closed at Tier C; 892
>   unindexed-FK advisories categorized and deferred (`ISS-2026-239`);
>   `auth_rls_initplan` regression guard re-verified clean; `ISS-2026-238`
>   (Medium) expanded from 3 to 4 confirmed routes plus 5 new siblings found at
>   Tier C. Full disposition: `HDN-379.md` §13.
> - **Prior checkpoint summary (`HDN-378`, Security Hardening) — is `VERIFIED`.**
>   First round wired
>   `app.assert_ip_allowed`/`app.has_active_ip_allowlist_bypass` into all 4 named
>   platform-default high-risk functions, closing a self-caught `CREATE OR REPLACE`
>   overload defect before commit (`C-29`); relocated `pg_trgm`/`btree_gist`
>   (`postgis` non-relocatable, `ISS-2026-234`); fixed 1 OWASP finding
>   (`ISS-2026-233`); fixed `ISS-2026-168`/`169`/`232`; reconfirmed and re-deferred
>   `ISS-2026-151`/`149`/`146`; authored 4 runbooks. **Tier C review found and fixed 2
>   Critical + 1 High genuine bypass in this checkpoint's own first-round work**: the
>   token_hash `RETURNING`-clause leak on `ISS-2026-232`'s own 3 "revoke" RPCs
>   (`C-27`, new), the `require()`/dynamic-`import()` gap in `ISS-2026-168`'s ESLint
>   fix, and `app.validate_webhook_url`'s own control-character sibling gap. **The
>   checkpoint's own headline claim required correction**: `ISS-2026-150`
>   `RESOLVED` → `PARTIALLY RESOLVED` once Tier C found `app.set_integration_
>   connection_status` — the shared primitive `activate_enterprise_idp_connection`
>   delegates to — independently bypasses the IP-restriction fix, the pre-existing
>   IAE-026 lockout guard, and step-up-MFA simultaneously; registered
>   `ISS-2026-235`/`HDN-BLK-023` (Critical, owner `HDN-386`, `C-28`, new). Also
>   registered: `ISS-2026-236`/`HDN-BLK-024` (High, owner `HDN-386` — 61 functions
>   across 3 of `is_high_risk_action`'s own 7 tuples never wired at all) and
>   `ISS-2026-237` (Medium, owner `HDN-387` — a pre-existing, two-weeks-prior
>   `automation-rule.ts` over-restriction, not this checkpoint's own regression). 5
>   real documentation miscounts in the first round's own ledger propagation found
>   and corrected before this Tier C close (commit `3fbf665`). Independent full gate
>   re-run green after the fix pass: `typecheck` 0, `lint` 0/337 warnings, 5443/5443
>   unit tests, 229/229 db-tests (328 migrations). Full disposition: `HDN-378.md` §13.
> - **Carry-forward, still open, not `HDN-380`'s own to resolve unless squarely in its own
>   charter** (`HDN-BLK-018`/`ISS-2026-205`, `ISS-2026-206`, `HDN-BLK-016`/`ISS-2026-199`,
>   `ISS-2026-186`, `ISS-2026-197`, `HDN-BLK-010`'s residual 3 non-Finance functions plus
>   `ISS-2026-163`, `ISS-2026-207`/`208`, `ISS-2026-213`/`214`, `ISS-2026-222`/`224`,
>   `HDN-BLK-020`/`ISS-2026-229`, `HDN-BLK-021`/`ISS-2026-230`, `ISS-2026-231`,
>   `HDN-BLK-022`/`ISS-2026-225`, `ISS-2026-223`, `ISS-2026-151`, `ISS-2026-234`,
>   `HDN-BLK-023`/`ISS-2026-235`, `HDN-BLK-024`/`ISS-2026-236`, `ISS-2026-237`,
>   `ISS-2026-238`, `ISS-2026-239`, `ISS-2026-240`, `ISS-2026-141`/`148`) — each
>   remains registered at its already-named owner (`HDN-386` for the security-domain
>   Critical/High residuals, `HDN-387` for the general regression backlog, a
>   dedicated future task for the performance-domain residuals).
> - **Do not cite CI as evidence for anything** — `HDN-BLK-007/008/009` remain open; every
>   result this lane produces must be a real local execution.

**`HDN-380` is `VERIFIED`. Nothing after `HDN-381` may begin until `HDN-381` is `VERIFIED`.**
`FULL_SYSTEM_HARDENING_VERIFIED` is **not** set and may only ever be set by Prompt 389.

> **Standing warning for `HDN-386` and every lane before it, updated at `HDN-380`:** CI was
> red on `main` on all three jobs (`HDN-BLK-007/008/009`) as of `HDN-370`. **`HDN-BLK-009`
> is `RESOLVED` as of `HDN-380`** — the `e2e` job's own failure mode was root-caused to a
> Turbopack dev-mode hydration-timing race (`ISS-2026-160`, `C-30`), not the CI job's missing
> `env:` block as originally described, and fixed by pointing `playwright.config.ts`'s
> `webServer` at a production build; since CI runs the identical `pnpm run test:e2e` command
> against the identical config, this job should go green on `main` once this checkpoint's
> commit lands and CI actually re-runs against it — **not yet independently confirmed against
> a real CI run**, since this lane has no CI access, only local reproduction. `HDN-BLK-007`
> (governance-step skip cascade) and `HDN-BLK-008` (`db` job's cross-container
> `pg_read_file()`) remain open and unresolved. **No Step 15 lane may cite CI as evidence for
> the `db`/`quality` jobs' own gates until those two are resolved**, and no lane should assume
> the `e2e` job is actually green in CI without checking — local runs remain the valid
> evidence this range has been using throughout.
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
