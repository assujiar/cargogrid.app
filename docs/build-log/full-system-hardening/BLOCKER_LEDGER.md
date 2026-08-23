# Step 15 — Release Blocker Ledger

**Produced by:** `CG-S15-HDN-001` (Prompt 369, Full-System Hardening WBS Runtime Kickoff)
**Governs:** `HDN-370` … `HDN-389`
**Severity policy, accepted-risk rules and the record format:**
`docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` §7, §8, §14

> **Append-only.** Entries are never deleted or silently re-graded. A change of severity or
> disposition is recorded as a dated amendment inside the entry, with the evidence that
> justified it. Re-grading a finding to make a gate pass is the exact failure mode this
> ledger exists to prevent.

---

## Conventions

- **`HDN-BLK-nnn`** is this ledger's own ID. Where a finding also has a
  `docs/runtime/KNOWN_ISSUES.md` row, both IDs are recorded and neither replaces the other.
- **Only `HDN-387` or `HDN-389` may set `ACCEPTED_EXCEPTION`**, and only when all five
  conditions of the execution index §8.2 hold. No lane may accept its own finding.
- **A Critical is never accepted.** It blocks until fixed or contained.
- **`TRACKED_GAP` is not a pass.** It is a gate that could not be run, recorded with owner,
  risk and the exact missing command.

---

## Status at kickoff (`HDN-369`, historical — not updated afterward)

| | Count |
|---|---|
| Blockers opened **by** Step 15 | **0** — the kickoff performs no audit work |
| Carried-forward entries seeded below | **6** |
| — of which **High** | **1** (`HDN-BLK-001`) |
| — of which **Medium** | **5** (`HDN-BLK-002..006`) |
| — of which class-level | **1** (`HDN-BLK-002`, four issues in one defect family) |
| Unresolved **Critical** anywhere | **0** |

## Status as of `HDN-370` (historical snapshot — superseded by the table below)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **3** — `HDN-BLK-007` (High), `HDN-BLK-008` (Medium), `HDN-BLK-009` (Medium), all at `HDN-370` |
| Blockers closed **by** Step 15 to date | **1 class** — `HDN-BLK-002` (all four member issues `RESOLVED`) |
| Total open entries | **8** — `HDN-BLK-001`, `003..009` (`002` closed) |
| — of which **High** | **2** (`HDN-BLK-001`, `HDN-BLK-007`) |
| — of which **Medium** | **6** (`HDN-BLK-003..006`, `008`, `009`) |
| Unresolved **Critical** anywhere | **0** |

## Status as of `HDN-371` (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **4** — `HDN-BLK-007` (High), `HDN-BLK-008` (Medium), `HDN-BLK-009` (Medium) at `HDN-370`; `HDN-BLK-010` (Medium) at `HDN-371` |
| Blockers closed **by** Step 15 to date | **1 class** — `HDN-BLK-002` (all four member issues `RESOLVED`) |
| Total open entries | **9** — `HDN-BLK-001`, `003..010` (`002` closed) |
| — of which **High** | **2** (`HDN-BLK-001`, `HDN-BLK-007`) |
| — of which **Medium** | **7** (`HDN-BLK-003..006`, `008`, `009`, `010`) |
| Unresolved **Critical** anywhere | **0** |

The seeded entries are **not** Step 15 discoveries. They are already-registered items with
existing evidence, promoted into this ledger so that Step 15 starts from evidence and so
that none of them can quietly drift out of scope. Each names the single lane that owns it.

---

## HDN-BLK-001 — IP restriction is structurally unreachable from any real mutation

| Field | Value |
|---|---|
| **Title** | RPD-023's IP-restriction enforcement is real and correct when called directly, but no real client IP is threaded through the route-handler layer, so it is unreachable from any real business mutation |
| **Found by** | Phase 9, `CG-S14-IAE-037` (Prompt 365, Security/AI Hardening), enterprise IAM/hardening lens |
| **Severity** | **High** |
| **Owning phase** | Cross-phase; the gap predates Phase 9 — it originates at Platform Core / RPD-023 |
| **Owning lane** | **`HDN-378`** (Security Hardening) |
| **Reachability** | A fully-configured, `enforced`-mode IP allowlist currently provides **zero** real protection against any caller that reaches the RPC layer directly — e.g. via a leaked service credential, or a compromised client bypassing the intended HTTP path |
| **Reproduction** | Call any IP-restricted mutation through the TypeScript mutation layer: no client IP is ever populated, so `assert_ip_allowed` is never reached with a real value. The function itself passes its own direct-call tests |
| **Blast radius** | The route-handler layer plus the TypeScript mutation layer — a cross-layer change, materially larger than a migration-only fix |
| **Disposition** | **`DEFERRED_TO_HDN-378`.** Phase 9 ruled it an explicit, transparent, **first-of-its-kind accepted exception** to this repository's own zero-Critical/High closure precedent, and **named Step 15 as the remedy**. Full reasoning: `docs/build-log/phase-09/INTELLIGENCE_ENTERPRISE_CLOSURE_REPORT.md` §2 |
| **Required of `HDN-378`** | (a) build route-handler-level client-IP extraction and threading; (b) wire `assert_ip_allowed` into the bounded set of highest-risk SEC/IAM/INTHUB mutations that `ISS-2026-151`'s own ruling already names; (c) decide explicitly what service-role/background-job callers with no client IP at all should do (likely exempt — IP restriction is inherently an interactive-session control). **A cosmetic partial wire-up is forbidden**: adding an unenforced parameter that nothing ever populates would look fixed without being fixed |
| **Regression test** | Required with the fix: a negative-path test proving a disallowed IP is actually rejected through the real call path, not only in a direct-call unit test |
| **Rollback** | Additive migration + additive route-layer parameter; `git revert` the checkpoint's commit |
| **`KNOWN_ISSUES`** | `ISS-2026-150` (`OPEN`, High) |

> **This is the one item Step 15 cannot defer.** It was accepted once, explicitly, on the
> stated condition that Step 15 would remedy it. Deferring it again would convert a
> disclosed, time-bounded exception into a permanent silent one — precisely what the
> Phase 9 ruling refused to do.

---

## HDN-BLK-002 — The day-of-week / wall-clock db-test fixture flake class

| Field | Value |
|---|---|
| **Title** | Four `scripts/db-tests/*.sql` fixtures silently assume something about real wall-clock time that is not always true, so the regression baseline is green only on some days and at some times |
| **Found by** | Phases 7–9, repeatedly, across four separate checkpoints |
| **Severity** | **Medium** as a class (each individual issue is registered Low; the class is Medium because it defeats gate #1's own reliability) |
| **Owning phase** | Phase 7 (HRIS) for all four fixtures |
| **Owning lane** | **`HDN-370`** (Full Regression) |
| **Reachability** | Any run of `bash scripts/db-tests/run.sh`. `set -euo pipefail` means the suite **halts** at the failing file, so every file sorted after it never runs |
| **Members** | `ISS-2026-103`/`115` — `hris-overtime-timesheet.sql`, day-of-week — **CLOSED** at `cdbccc7` by pinning the fixture to the most recent weekday. `ISS-2026-077` — `hris-leave-permit-business-trip.sql`, actually a timezone-boundary mismatch, not day-of-week — **`RESOLVED`** at `HDN-370`. `ISS-2026-135` — `hris-shift-roster-scheduling.sql`, actually a hardcoded calendar date, not day-of-week — **`RESOLVED`** at `HDN-370`. `ISS-2026-154` — `hris-attendance.sql`, a ~1-hour real-UTC window after each day's 21:00 UTC (04:00 Asia/Jakarta) shift-day boundary, confirmed as registered — **`RESOLVED`** at `HDN-370` |
| **Reproduction** | Run the suite on the triggering day / in the triggering window. Each issue records its own exact trigger |
| **Kickoff observation** | All four executed and **passed** on Sunday 2026-08-23, ~11:15–11:45 UTC. **This is not proof the class is closed**: `ISS-2026-135`'s day-of-week dimension was genuinely in play and did not fire; `ISS-2026-154`'s time-of-day dimension was **not exercised at all** (~10 hours outside its window). Status: **`PARTIAL`** |
| **Disposition** | **`FIXED` at `HDN-370` (2026-08-23).** See the amendment below — the class as registered did not exist |
| **Regression test** | The pinning itself is the regression guard; a day-parameterised test is the proof |
| **Rollback** | Test-fixture-only changes; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-077`, `ISS-2026-135`, `ISS-2026-154` (all `RESOLVED` at `HDN-370`); `ISS-2026-103`/`115` (closed earlier at `cdbccc7`) |

**A regression baseline green only on some days of the week is not a release gate.**

### Amendment, 2026-08-23 (`CG-S15-HDN-002`, Prompt 370) — the class was misclassified

Each member was re-derived from live evidence against a fully-migrated probe database rather
than accepted from its issue text. **Three of the four are not day-of-week defects**, and two
were materially worse than recorded:

| Issue | Registered as | Actually | Real exposure |
|---|---|---|---|
| `ISS-2026-077` | day-of-week / wall-clock | **Timezone-boundary mismatch.** `current_date` evaluates in the session timezone (`Etc/UTC`); `work_date` resolves in the tenant policy's timezone (`Asia/Jakarta`). The fixture seeds on one and asserts on the other | **7 hours every day** (17:00–24:00 UTC) — **196 of 672 swept instants, 29%** |
| `ISS-2026-154` | day-of-week class, time-of-day trigger | Confirmed: shift-day boundary at 04:00 Asia/Jakarta | **1 hour every day** — 84 of 2,016 swept instants |
| `ISS-2026-135` | day-of-week | **A hardcoded calendar date.** emp3 is given a published roster assignment on the literal `2026-08-18`, then the fixture asserts "no assignment covering today" | **Exactly 1 date in 30 swept — `2026-08-18`, a Tuesday** |
| `ISS-2026-103`/`115` | day-of-week | Confirmed genuinely day-of-week | Sat/Sun — already fixed at `cdbccc7` |

The registered root cause for `ISS-2026-077` (that the negative-control employee lacks a
`schedule_assignments` row) is **wrong**: late-exception detection never reads
`schedule_assignments`. Measured directly, not inferred.

`ISS-2026-135` is not "already past" either — it re-arms the moment anyone refreshes the
fixture's literal dates forward, which is ordinary maintenance.

**All three fixed at the root**, each proven by exhaustive sweep rather than a green re-run:
0 failing instants after the fix, across all 7 weekdays. Full evidence and the sweep queries:
`docs/build-log/full-system-hardening/HDN-370.md` §5, §8. Fixes are test-fixture-only — in all
three cases the code under test was correct and the fixture's temporal assumption was wrong.

`ISS-2026-077`, `ISS-2026-135`, `ISS-2026-154` → `RESOLVED`.

---

## HDN-BLK-003 — Step-up challenge unwired on `app.create_integration_connection`

| Field | Value |
|---|---|
| **Title** | `app.assert_current_step_up_authorization` is real and correct but has no live caller on `app.create_integration_connection` |
| **Found by** | Phase 9, `CG-S14-IAE-037` (Prompt 365); partially resolved at `CG-S14-IAE-039` (Prompt 367) |
| **Severity** | **Medium** (re-graded High → Medium at Prompt 367 **on evidence**, not for convenience: 3 of the 4 originally-affected functions were genuinely wired via migration `20260809200000`, with real fixture adaptations and a negative-path regression proving enforcement) |
| **Owning phase** | Phase 9 (`IAE-027`) |
| **Owning lane** | **`HDN-378`** |
| **Reachability** | A privileged integration-connection creation proceeds without a step-up challenge that RPD-023 requires |
| **Blast radius** | **40+ call sites across 16 files** — measured at Prompt 367, not estimated. This is why it was deliberately left rather than mass-edited under time pressure |
| **Disposition** | **`DEFERRED_TO_HDN-378`** |
| **Required of `HDN-378`** | Wire it with real step-up fixtures and a negative-path regression proving genuine enforcement, **or** rule on it explicitly with a compensating control. Silence is not an option |
| **Rollback** | Additive migration; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-151` (`PARTIALLY RESOLVED`, Medium) |

---

## HDN-BLK-004 — postgis, pg_trgm and btree_gist live in `public`

| Field | Value |
|---|---|
| **Title** | Three extensions sit in `public` rather than `extensions` — the same root-cause class as the fixed pgcrypto defect |
| **Found by** | Live Supabase migration, 2026-08-23 (`docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` open item 2) |
| **Severity** | **Medium** |
| **Owning phase** | Platform Core (PostGIS enabled from Platform Core per the ratified stack baseline) |
| **Owning lane** | **`HDN-378`**, as **its own scoped task** |
| **Reachability** | Advisory-level. It exposes PostGIS's own `st_estimatedextent` as a `SECURITY DEFINER` function and leaves `spatial_ref_sys` without RLS |
| **Value of fixing** | Clears **7 of the 8 non-noise security advisories, including the only ERROR**: 3 × `extension_in_public`, 6 × `*_security_definer_function_executable`, 1 × `rls_disabled_in_public` (ERROR) |
| **Blast radius** | **Every function touching `geometry`/`geography` types or any `ST_*` call needs `extensions` added to its search_path.** Far larger than the pgcrypto change, which already spanned 39 functions across 22 migrations |
| **Disposition** | **`DEFERRED_TO_HDN-378`** |
| **Hard constraint** | **Never fold this into another edit.** It gets its own migration, its own review, and its own gate run. Mixing it with any other change makes a failure impossible to attribute |
| **Known limit** | `spatial_ref_sys` **cannot** have RLS enabled — it belongs to the PostGIS extension and `postgres` is not superuser on a hosted project. That sub-item is permanently a disclosed residual, not a fixable one |
| **Rollback** | Additive migration; `git revert`. The move is reversible but expensive — plan it once |
| **`KNOWN_ISSUES`** | Not yet registered as an `ISS-2026-nnn` row; registered here and to be given one when `HDN-378` opens it |

---

## HDN-BLK-005 — `rbac-enforcement.sql`'s catalogue scan is outgrowing its budget

| Field | Value |
|---|---|
| **Title** | `scripts/db-tests/rbac-enforcement.sql` walks `pg_proc` calling `pg_get_functiondef()` on every function in `app`; at ~2,900 functions it already exceeds a remote statement timeout and takes 15–20+ minutes standalone |
| **Found by** | Phase 9 `CG-S14-IAE-002` (`ISS-2026-145`); re-confirmed by the live migration run |
| **Severity** | **Medium** |
| **Owning phase** | Phase 5 (`ATW-032` / `ISS-2026-032` actor-identity call-graph sweep) |
| **Owning lane** | **`HDN-379`** (Performance and Scalability) |
| **Reachability** | Every CI run. It passes locally today — that is the last thing that is still true about it |
| **Trend** | The schema only grows. ~2,398 functions at Prompt 330, ~2,900 now |
| **Disposition** | **`DEFERRED_TO_HDN-379`** |
| **Required** | Scope the scan (incremental, sampled by risk class, or narrowed to functions the sweep actually needs) **without weakening what it proves** — it is a real security sweep, not a lint |
| **`KNOWN_ISSUES`** | `ISS-2026-145` (`OPEN`, Low — the class is graded Medium here because it now threatens a mandatory gate) |

---

## HDN-BLK-006 — 892 `unindexed_foreign_keys` advisories: an owner-named deferral

| Field | Value |
|---|---|
| **Title** | 892 foreign keys have no covering index on the live project |
| **Found by** | Live Supabase migration advisors, 2026-08-23 |
| **Severity** | **Medium** |
| **Owning lane** | **`HDN-379`** |
| **Assessment** | **A design question, not a defect.** The companion 982 `unused_index` advisories are pure noise — the database has served no queries — and the same absence of real traffic is exactly why the 892 cannot be resolved by inspection |
| **Disposition** | **`ACCEPTED_EXCEPTION` — explicitly deferred with a named owner.** Recorded here at kickoff so the deferral is visible rather than implicit |
| **Hard constraint** | **Neither drop them nor blindly index.** Blanket-indexing 892 FKs adds real write cost and storage for unmeasured benefit; dismissing them hides a genuine future scaling risk |
| **Required of `HDN-379`** | State the decision, its owner, and the measurement that would settle it (real query patterns at target volume). Index only where a measured pattern justifies it |
| **`KNOWN_ISSUES`** | To be registered by `HDN-379` when it rules |

---

## HDN-BLK-007 — CI is red on every push, and 6 governance gates never execute there

| Field | Value |
|---|---|
| **Title** | `scripts/git/check-worktree-collision.test.ts` asserts the current branch has commits ahead of `origin/main`, which is structurally impossible in CI — so the `quality` job's `Test` step fails on every run, and the seven governance steps ordered after it are **skipped** |
| **Found by** | `HDN-370` (`CG-S15-HDN-002`), full-regression CI reconciliation |
| **Severity** | **High** |
| **Owning phase** | Phase 0 governance tooling |
| **Owning lane** | **`HDN-387`** (Release Blocker Triage and Remediation) |
| **Reachability** | Every CI run, `push` and `pull_request` alike. Verified: runs #105–#109 all `failure`; #109 is `main` at `e5da061` |
| **Reproduction** | `scripts/git/check-worktree-collision.test.ts:40` — `assert.ok(current, 'expected ${branch} to have commits ahead of origin/main')`. A CI checkout of `main` **is** `origin/main`, so `commitsAheadOfMain` is 0. There is no CI guard and no skip in the file |
| **Blast radius — the real damage** | Because `Test` fails first, these six steps report `skipped` and **have never run in CI on a push**: suppression-governance check; documentation checks; **secret scan**; **dependency vulnerability audit (fails on critical/high)**; data-classification registry check; threat-model register check. Two of those are security controls. `ISS-2026-007`'s own recorded lesson was that a silently-broken audit gate hid 20 real advisories, 11 high, for a whole phase — this is the same failure shape one level up. (A seventh step, protected-path check, is `if: github.event_name == 'pull_request'`-gated and is correctly absent from any push regardless of this failure — corrected at Tier C review, which caught it listed here in error) |
| **Why it went unnoticed** | Every phase's gate evidence in this repository was produced by **local** runs, where the test passes on a feature branch that genuinely is ahead of `origin/main`. The local and CI outcomes are inverses of each other, so a green local run is not evidence about CI |
| **Disposition** | **`DEFERRED_TO_HDN-387`** — not fixed here. It is a governance test whose intent (catching the `ISS-2026-002` collision class) is real; deciding what it should assert *in CI* is a design call, not a side-edit inside a regression-baseline lane |
| **Not to do** | Do not delete or skip the test to turn CI green. That would remove the `ISS-2026-002` control this repository added after real content corruption (`ERR-2026-001..003`) |
| **`KNOWN_ISSUES`** | `ISS-2026-158` |

---

## HDN-BLK-008 — the `db` CI job cannot read the helper files its concurrency tests write

| Field | Value |
|---|---|
| **Title** | Concurrency tests write helper output to `/tmp` on the runner and read it back with `pg_read_file()`, which reads the **server's** filesystem — a separate Docker service container in CI |
| **Found by** | `HDN-370`, CI reconciliation |
| **Severity** | **Medium** |
| **Owning phase** | Phase 5 (Advanced TMS/WMS concurrency proofs) |
| **Owning lane** | **`HDN-387`** |
| **Reproduction** | CI run #109, `db` job: `ERROR: could not open file "/tmp/cargogrid-wms-outbound-race-a.out" for reading: No such file or directory`, from `select pg_read_file(...) \|\| pg_read_file(...)` |
| **Why local passes** | Locally Postgres runs on the same host as the harness, so `/tmp` is shared. In CI the `postgis/postgis` service container has its own filesystem |
| **Blast radius** | **Re-measured fresh at Tier C review, per §14's own "measured, not estimated" requirement — the original entry carried the live-migration report's older figure rather than counting the current tree.** `grep -l '\! bash' scripts/db-tests/*.sql` → **19 files** use the shell-escape helper pattern generally; of those, `grep -l pg_read_file` → **6 files** actually call `pg_read_file()` and are exposed to this specific defect (`advanced-tms-wms-outbound.sql`, `-packing.sql`, `-picking.sql`, `automation-rule-engine.sql`, `procurement-vendor-contract.sql`, `public-api-platform.sql`). The other 13 `\! bash` files use the helper for a different purpose and are not exposed to this class. `run.sh` aborts at the first failure, so **every file sorted after the first exposed one never runs in CI** |
| **Disposition** | **`DEFERRED_TO_HDN-387`** |
| **Note** | The affected assertions are genuine, valuable concurrency proofs (real two-process row-lock races). They must keep working locally; the fix is about transporting the loser's output without `pg_read_file`, not about weakening the proof |
| **`KNOWN_ISSUES`** | `ISS-2026-159` |

---

## HDN-BLK-009 — the `e2e` CI job has no environment, so guarded routes 500

| Field | Value |
|---|---|
| **Title** | The `e2e` job sets no environment variables, so `NEXT_PUBLIC_SUPABASE_URL` is unset and every guarded route throws at env validation, returning 500 where the specs assert `< 500` plus a fail-safe redirect |
| **Found by** | `HDN-370`, reproduced locally and confirmed against the CI job definition |
| **Severity** | **Medium** |
| **Owning phase** | Phase 1 (portal guards) / Phase 0 (CI) |
| **Owning lane** | **`HDN-387`**, with input from `HDN-380`/`HDN-381` |
| **Reproduction** | `pnpm run test:e2e` with no `.env`: `Error: NEXT_PUBLIC_SUPABASE_URL is not set -- see .env.example` at `lib/supabase/server.ts:27`, then `GET /supreme 500`. The CI `e2e` job has no `env:` block and no secrets |
| **The design question** | Several specs are *named* for a "no-live-Supabase-project condition" and assert the guard **redirects** rather than crashing. Today it crashes, because env validation throws before any guard logic. So either the guard should fail safe on missing configuration, or the specs encode an intent the code never had. **That is a real product question, not a CI-wiring detail** |
| **Disposition** | **`DEFERRED_TO_HDN-387`** |
| **`KNOWN_ISSUES`** | `ISS-2026-160` |

---

## HDN-BLK-010 — 7 of 19 cross-module boundary functions lack the race-safe idempotency pattern this codebase already proves elsewhere, 6 of them in Finance

| Field | Value |
|---|---|
| **Title** | A systematic sweep of every genuine cross-module `prepare_/convert_/link_/create_from_` boundary function found 7 whose idempotent check-then-insert has no exception handler for a genuine concurrent race, unlike 12 siblings that do — including one, `prepare_wms_outbound_from_shipment`, that documents the fix explicitly as "design note 9(a)" |
| **Found by** | `HDN-371` (`CG-S15-HDN-003`), Cross-Module Transactional Integrity, via a full code-level sweep of all 306 migrations for the boundary-function shape, cross-checked against each target table's actual constraints |
| **Severity** | **Medium.** Bounded by direct verification: all 7 target tables carry a confirmed backing `unique` constraint, so **no duplicate financial or handoff record can be created**. The real consequence is narrower — a genuinely concurrent second caller (double-click, client retry racing its own in-flight request) receives a raw, uncaught `unique_violation` instead of the graceful "here is the record already created" every other caller gets |
| **Owning phase** | Phase 4 (Finance, 6 of 7 functions) and Phase 2 (Commercial, 1 function: `prepare_job_order_handoff`) |
| **Owning lane** | **`HDN-374`** (Financial Integrity Audit) — its own charter is exactly this domain, and it is the next Finance-focused lane; `HDN-371`(this lane) is its own hard upstream dependency, already satisfied |
| **Reachability** | Any two near-simultaneous calls to the same one of these 7 functions with the same idempotency-defining argument (e.g. the same `billing_readiness_handoff_id`, `original_journal_id`, `payroll_run_id`, `actual_cost_id`, or `quotation_id`/`purpose` pair) |
| **Reproduction** | Code-verified directly: each of the 7 functions' bodies contain `if found then return ...;` followed later by a bare `insert into ... returning * into ...` with no enclosing `begin ... exception when unique_violation ... end` block. Cross-referenced against `prepare_wms_outbound_from_shipment` (`20260730230000_create_advanced_tms_wms_outbound_order.sql`), which has exactly this pattern correctly implemented and documented |
| **Blast radius — measured, not estimated** | `app.prepare_finance_invoice_from_readiness`, `app.prepare_finance_journal_adjustment`, `app.prepare_finance_journal_reversal`, `app.prepare_finance_payroll_disbursement_handoff_from_payroll_run`, `app.prepare_finance_settlement`, `app.prepare_finance_vendor_bill_from_actual_cost`, `app.prepare_job_order_handoff` — 7 functions, 5 migration files. Existing sequential-idempotency test coverage: 118 call sites across 58 db-test files, none exercising genuine two-process concurrency for these 7 |
| **Disposition** | **`DEFERRED_TO_HDN-374`** — not fixed here. Six of seven affected functions are Finance-domain; `AGENTS.md` names "any prompt touching finance posting" as needing its own dedicated treatment, not a bundled fix inside an audit lane |
| **Required of `HDN-374`** | Mirror `prepare_wms_outbound_from_shipment`'s own already-proven "design note 9(a)" nested-exception-handler shape into each of the 7 functions, one additive migration, each paired with a real two-process concurrency regression test (the `\!`-based helper pattern `advanced-tms-wms-outbound.sql` already establishes) proving the race resolves gracefully rather than erroring |
| **Regression test** | Required with the fix: a genuine two-process race per function, proving the loser gets the already-created record, never a raw `unique_violation` |
| **Rollback** | Additive migration only; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-162` (`OPEN`, Medium) |

---

## Reserved

`HDN-BLK-011` onward are unassigned. Every Step 15 finding takes the next free ID and the
full record format of the execution index §14. A finding missing any field is not
registered — and an unregistered finding is not a finding.
