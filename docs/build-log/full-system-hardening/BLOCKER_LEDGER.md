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
| **Disposition** | **`RESOLVED` at `HDN-379`.** The `edge` CTE rewritten from an O(n²) self-join to a one-pass `regexp_matches()` extraction, mirroring this same file's own sibling ATW-032/`ISS-2026-033` pattern; verified with a same-schema matched-pair run (original 692,092.8ms, rewrite 556.4ms, byte-identical verdicts, 1244× speedup); full 229-file suite re-run clean. What it proves is unweakened — only `edge` construction changed, the `covered` recursive CTE's own transitive-closure walk is untouched |
| **Required** | Scope the scan (incremental, sampled by risk class, or narrowed to functions the sweep actually needs) **without weakening what it proves** — it is a real security sweep, not a lint — **done, see Disposition** |
| **`KNOWN_ISSUES`** | `ISS-2026-145` (`RESOLVED` at `HDN-379`) |

---

## HDN-BLK-006 — 892 `unindexed_foreign_keys` advisories: an owner-named deferral

| Field | Value |
|---|---|
| **Title** | 892 foreign keys have no covering index on the live project |
| **Found by** | Live Supabase migration advisors, 2026-08-23 |
| **Severity** | **Medium** |
| **Owning lane** | **`HDN-379`** |
| **Assessment** | **A design question, not a defect.** The companion 982 `unused_index` advisories are pure noise — the database has served no queries — and the same absence of real traffic is exactly why the 892 cannot be resolved by inspection |
| **Disposition** | **`ACCEPTED_EXCEPTION` — explicitly deferred with a named owner, ruled on at `HDN-379`.** Categorized into a 4-bucket decision framework from a 24-FK sample across 7 domains (60% genuinely bare, 23% tenant-composite-covered, 10% self-scoping `tenant_id`, 7% self-referencing lineage) — zero high-confidence "index now" candidates found; every column with confirmed hot usage already has a serving composite index, and the genuinely cold candidates are write-only/audit-lineage columns on high-write-volume tables |
| **Hard constraint** | **Neither drop them nor blindly index.** Blanket-indexing 892 FKs adds real write cost and storage for unmeasured benefit; dismissing them hides a genuine future scaling risk |
| **Required of `HDN-379`** | State the decision, its owner, and the measurement that would settle it (real query patterns at target volume). Index only where a measured pattern justifies it — **done, see Disposition**: deferred pending real production query telemetry, which does not exist anywhere in this system yet |
| **`KNOWN_ISSUES`** | `ISS-2026-239` (`OPEN`, Low, owner a dedicated future task) |

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
| **Severity** | Medium (was) |
| **Owning phase** | Phase 1 (portal guards) / Phase 0 (CI) |
| **Owning lane** | **`HDN-387`**, with input from `HDN-380`/`HDN-381` |
| **Reproduction (historical — no longer reproduces)** | `pnpm run test:e2e` with no `.env`: `Error: NEXT_PUBLIC_SUPABASE_URL is not set -- see .env.example` at `lib/supabase/server.ts:27`, then `GET /supreme 500`. The CI `e2e` job has no `env:` block and no secrets |
| **The design question** | Several specs are *named* for a "no-live-Supabase-project condition" and assert the guard **redirects** rather than crashing. Today it crashes, because env validation throws before any guard logic. So either the guard should fail safe on missing configuration, or the specs encode an intent the code never had. **That is a real product question, not a CI-wiring detail** — this part is still open, see `KNOWN_ISSUES.md` `ISS-2026-160`'s own `HDN-380` correction |
| **Disposition** | **`RESOLVED at HDN-380`** — `playwright.config.ts`'s own `webServer.env` block (added at `PLT-135`, after this entry was found) already made the "unset env var" premise stale; the remaining real symptom (5 `e2e/vendor-registration.spec.ts` failures, live-forced to a Turbopack dev-mode hydration-race hang, not a 500) was fixed this checkpoint by switching `webServer.command` from `next dev` to `next build && next start`. Full suite now passes 18/18 with zero 500s. Full narrative: `KNOWN_ISSUES.md` `ISS-2026-160` |
| **`KNOWN_ISSUES`** | `ISS-2026-160` |

---

## HDN-BLK-010 — 9 of 20 cross-module boundary functions lack the race-safe idempotency pattern this codebase already proves elsewhere, live-forced and confirmed for one of them

*Amended at `HDN-371`'s own Tier C review (2026-08-23), same checkpoint. Original text found 7
functions across 5 files, all cited at their original migrations, and stated a false claim
about `HDN-374`'s dependency status — four independent review lenses caught these
independently; corrected below rather than left standing. See `HDN-371.md` §12.1 for the full
finding-by-finding disposition.*

| Field | Value |
|---|---|
| **Title** | A systematic sweep of every genuine cross-module `prepare_/convert_/link_/create_from_` boundary function found 9 (corrected from 7) whose idempotent check-then-insert has no exception handler for a genuine concurrent race, unlike 11 siblings that do — including one, `prepare_wms_outbound_from_shipment`, that documents the fix explicitly as "design note 9(a)". **Live-forced and confirmed** by a real two-process race against one of the 9 (`link_auth_identity`) |
| **Found by** | `HDN-371` (`CG-S15-HDN-003`), Cross-Module Transactional Integrity, via a full code-level sweep of all 306 migrations for the boundary-function shape (re-run redefinition-aware at Tier C review after the original sweep's regex proved blind to `create or replace function`), cross-checked against each target table's actual live constraints, and a live-forced two-process race |
| **Severity** | **Medium — unchanged.** Bounded by direct verification against the *live* schema: all 8 distinct backing tables/partial-indexes carry a confirmed unique-enforcing object, so **no duplicate financial, handoff, WMS-inbound, or identity-link record can be created**. The real consequence, **now observed live** rather than only inferred: a genuinely concurrent second caller (double-click, client retry racing its own in-flight request) receives a raw, uncaught `unique_violation` instead of the graceful "here is the record already created" every other caller gets |
| **Owning phase** | Phase 4 (Finance, 5 functions), Phase 7 (HRIS-Payroll, 1 function — Finance-*named*, HRIS-*owned* per its own migration's table comment), Phase 2 (Commercial, 1 function), Phase 5 (Advanced TMS/WMS, 1 function), Phase 1 (Platform/Auth, 1 function) |
| **Owning lane** | **`HDN-374`** (Financial Integrity Audit) for the 6 Finance/HRIS-Payroll functions — its own charter is exactly this domain. **The 3 non-Finance functions (Commercial, WMS, Platform/Auth) are disclosed as an open scope question, not silently assigned**: `HDN-374` may fix all 9 as one coherent batch (mirroring the precedent this very finding already set by bundling a Commercial function in), or hand the 3 to their own domain owners — a decision for `HDN-374` or `HDN-386` to make explicitly. **`HDN-371` (this lane) is `VERIFIED` as of this same checkpoint's own Tier C close — the hard-gate dependency is now genuinely satisfied, not merely asserted as it was before this amendment corrected a false claim to that effect** |
| **Reachability** | Any two near-simultaneous calls to the same one of these 9 functions with the same idempotency-defining argument (e.g. the same `billing_readiness_handoff_id`, `original_journal_id`, `payroll_run_id`, `quotation_id`/`purpose` pair, `source_shipment_order_id`, or `(auth_user_id, tenant_id)` pair) |
| **Reproduction** | **Live-forced and confirmed** for `link_auth_identity`: an uncommitted conflicting `insert` held open in one session forces a second session's call to block on the live unique index, then raise `duplicate key value violates unique constraint "tenant_user_identities_identity_tenant_unique"` on the first session's commit — exact technique and output in `HDN-371.md` §6.2-6.3, independently reproduced by two parties (a Tier C review lens, then the orchestrating session on its own fresh probe database). **Code-verified directly for the other 8**: each function's body contains `if found then return ...;` followed later by a bare `insert into ... returning * into ...` with no enclosing `begin ... exception when unique_violation ... end` block, checked at each function's **effective** (current, post-redefinition) definition — cross-referenced against `prepare_wms_outbound_from_shipment` (`20260730230000_create_advanced_tms_wms_outbound_order.sql`), which has exactly this pattern correctly implemented and documented |
| **Blast radius — measured, not estimated** | `app.prepare_finance_invoice_from_readiness` (effective def: `20260730540000`), `app.prepare_finance_journal_adjustment` (`20260730390000`), `app.prepare_finance_journal_reversal` (`20260730390000`), `app.prepare_finance_payroll_disbursement_handoff_from_payroll_run` (`20260731020000`), `app.prepare_finance_settlement` (`20260730390000`), `app.prepare_finance_vendor_bill_from_actual_cost` (`20260730540000`), `app.prepare_job_order_handoff` (`20260724340000`), `app.prepare_wms_inbound_from_shipment` (`20260730180000`), `app.link_auth_identity` (`20260716095343`) — **9 functions, 7 distinct migration files at their effective definitions**. Existing sequential-idempotency test coverage: ~131 call-site occurrences across ~60 db-test files for the originally-named 7 (re-measured; an earlier "118/58" figure did not reproduce), none exercising genuine two-process concurrency prior to this checkpoint's own §6.3 proof |
| **Disposition** | **`DEFERRED_TO_HDN-374`** — not fixed here. Kept as one batch across its 5 domains rather than split, per the scope disclosure above |
| **Required of `HDN-374`** | Mirror `prepare_wms_outbound_from_shipment`'s own already-proven "design note 9(a)" nested-exception-handler shape into each of the 9 functions **at its effective migration** (not the original creating migration — 5 of 9 have been redefined since creation; working from the original body would silently revert prior hardening migrations `ATW-031`/`ATW-032`), one additive migration each, each paired with a real two-process concurrency regression test using the **uncommitted-insert-blocking technique** (`HDN-371.md` §6.2 — proven to work on the first attempt, corrected from an original recommendation to use the repository's more fragile `\!`-based helper pattern). Also add a `tenant_id` predicate to the payroll function's idempotency short-circuit (currently untenant-scoped; not currently exploitable, but a defense-in-depth gap in the same function). Also close `ISS-2026-163` (`app.prepare_job_order`'s defective exception handler — no `if found`/`raise;`) in the same session, same function family |
| **Regression test** | Required with the fix: a genuine two-process race per function, proving the loser gets the already-created record, never a raw `unique_violation`. §6.2's technique is the recommended pattern |
| **Rollback** | Additive migration only; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-162` (`OPEN`, Medium); `ISS-2026-163` (`OPEN`, Low, related but separate — a different function, a different failure mode) |

*Amended at `HDN-374` (2026-08-23), same checkpoint. The 6 Finance/HRIS-Payroll functions are
now `RESOLVED` — see `ISS-2026-162`'s own amendment for the full disposition, including 4 more
Finance functions this checkpoint's own wider sweep found sharing the identical shape (10 fixed
total) and 2 live-forced two-process race proofs confirming the fix. The 3 non-Finance functions
(`app.prepare_job_order_handoff`, `app.prepare_wms_inbound_from_shipment`, `app.link_auth_
identity`) plus `app.prepare_job_order`'s own `ISS-2026-163` remain `OPEN`, explicitly handed to
`HDN-387` (Release Blocker Triage and Remediation) rather than silently dropped or force-fit into
this checkpoint's own Financial Integrity charter.*

---

## HDN-BLK-011 — 13 `SECURITY DEFINER` functions evaluated authority against a client-supplied actor UUID — cross-tenant PII/inventory/audit/notification read, live-forced, FIXED same checkpoint

*Amended at `HDN-372`'s own Tier C review (2026-08-23), same checkpoint. Original text found and
fixed 9 functions (12-member family claimed, 10 actually named, 21 total protected claimed). The
Tier C security/tenant lens ran a wider, independently-live-tested closure sweep and found 4 more
live-forced functions of the identical shape — fixed in the same checkpoint (this lane's own
charter), not deferred. Corrected below rather than left standing; see `HDN-372.md` §5.6 for the
full finding-by-finding disposition.*

| Field | Value |
|---|---|
| **Title** | The `ATW-032` sweep's own "STABLE/IMMUTABLE reads are exempt" premise is false for a `SECURITY DEFINER` function — it bypasses RLS, so a forged actor is exactly what lets a caller read what they could not otherwise. 13 functions (corrected from 9) evaluated authority against a claimed actor with no `assert_actor_is_session_identity` check anywhere in their call graph — 2 direct roots of 2 small transitive families, plus 11 independent |
| **Found by** | `HDN-372` (`CG-S15-HDN-004`), Tenant Isolation Audit — 9 by the original four parallel investigations (DB/RLS/grants; API/service layer; storage/jobs/cache/reports; support/AI/webhooks/audit), 4 more by this same checkpoint's own Tier C security/tenant lens running an independent, wider closure sweep, live-tested on its own fresh probe database |
| **Severity** | **High.** Cross-tenant read (per `00_EXECUTION_INDEX.md` §7), live-forced against a real, non-superuser `authenticated` session (methodology per §4.1) for all 13. Not Critical: no write path affected; live-confirmed against the real deployed project (`awdlicmwzdxquopwtcfd`) that `app` is not currently exposed via the Data API (`PGRST106`), so the class is not reachable at this exact checkpoint — disclosed as a pre-deployment configuration state, not accepted as a durable compensating control, since the application's own shipped code requires `app` exposed to function |
| **Owning phase** | Cross-cutting — Phase 1 (Platform, `resolve_customer_owner_account_scope`/`resolve_actor_owner_account_scope` own root classes mirror `CPL-300`), Phase 3 (HRIS, `get_self_employee`), Phase 4 (Finance-adjacent, audit trail), Phase 5 (WMS, customer inventory family), Phase 8 (approval engine, custom fields), Phase 9 (notifications, workflow/approval history) |
| **Owning lane** | **`HDN-372`(this lane) — fixed, not deferred.** Squarely this lane's own charter (tenant isolation, cross-tenant read), the fix pattern is mechanical and already proven repeatedly in this exact codebase (`ATW-031`/`ATW-032`/`CPL-300`/this checkpoint's own first pass), and Prompt 372's own business rules require blocking release on Critical/High isolation failures — including ones this lane's own review surfaces after its first fix has already landed |
| **Reachability** | Any `authenticated` session that knows a victim tenant's own real member's `auth_user_id` (trivially obtainable intra-tenant via `app.users`; cross-tenant requires the victim's own tenant_id and a real member's UUID, e.g. from a prior interaction, a support ticket, a data breach elsewhere) |
| **Reproduction** | **Live-forced**, by independent investigation lenses (original 9) and this checkpoint's own Tier C security/tenant lens (4 more), each verifying `current_user = authenticated` before trusting a result (the §4.1 methodology trap), plus re-verified by the orchestrating session post-fix and committed as a genuine regression test (`scripts/db-tests/rbac-enforcement.sql`, not merely pasted console output). Exact technique and output: `HDN-372.md` §5.1-§5.4, §5.6 |
| **Blast radius — measured, not estimated** | 13 functions fixed directly (9 in `20260810000000`, 4 more in `20260810100000`); 11 more protected transitively — 10 via `resolve_customer_owner_account_scope` (the `ATW-023` family, corrected from a claimed 12 to the 10 actually named), 1 (`actor_can_view_owner_scoped_row`) via `resolve_actor_owner_account_scope` — **24 functions total**. Full list: `HDN-372.md` §5.2, §5.6 |
| **Disposition** | **`FIXED`** — `supabase/migrations/20260810000000_harden_tenant_isolation_actor_identity_gaps.sql` (9), `supabase/migrations/20260810100000_harden_tenant_isolation_actor_identity_gaps_round2.sql` (4), same checkpoint |
| **Regression test** | `scripts/db-tests/rbac-enforcement.sql`'s named-list check (§ "HDN-372") proving all 13 fixed functions call `app.assert_actor_is_session_identity` as their first statement (position-aware, corrected from an original bare substring match); a genuine live two-session forced-spoof assertion actually calling 4 of the 13 from a real `authenticated`-claiming session and confirming `actor_identity_mismatch`, plus a positive own-identity control; live-forced attack re-run post-fix confirming `actor_identity_mismatch` on all tested paths, both direct and transitive; full 229-file db-test suite re-confirmed green |
| **Rollback** | Additive migrations only (`create or replace function`, no schema change); `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-164` (`RESOLVED` same checkpoint, was High) |

---

## HDN-BLK-012 — 13 dashboard read functions share the identical actor-forgery shape as `HDN-BLK-011`, no common root — FIXED at `HDN-373`

*Amended at `HDN-373` (2026-08-23), same checkpoint that closed it. Fixed at
`20260810200000_harden_dashboard_actor_identity_gaps.sql`: each of the 13 converted
`language sql` → `language plpgsql` carrying `perform app.assert_actor_is_session_identity
(p_actor_auth_user_id);` as its first statement, identical to `HDN-BLK-011`'s own pattern.
A position-aware named-list regression check plus a live two-session forced-spoof test
(3 representative functions, including one of the 5 that also gate a field-masking
entitlement on the same forged parameter — a genuine unmasking bypass, not merely a
record-scope widening, sharpening this finding's own severity reasoning) were added to
`scripts/db-tests/rbac-enforcement.sql`. Full disposition: `docs/build-log/full-system-
hardening/HDN-373.md` §6; `docs/runtime/KNOWN_ISSUES.md`'s `ISS-2026-165` updated to
`RESOLVED` in the same amendment.*

| Field | Value |
|---|---|
| **Title** | `app.get_ops_dashboard_*` (6) and `app.get_dashboard_*` (7) each independently call `app.can_access_record(p_actor_auth_user_id, ...)` inline with no identity check anywhere in the chain — the same root cause as `HDN-BLK-011`, but with no shared primitive to fix once |
| **Found by** | `HDN-372` (`CG-S15-HDN-004`), Tenant Isolation Audit — investigation lens 3, confirmed directly by the orchestrating session against the live catalogue |
| **Severity** | **High** (same reachability/blast-radius reasoning as `HDN-BLK-011` — cross-tenant read, not currently reachable via the Data API per the same disclosed caveat) |
| **Owning phase** | Phase 3 (Operations dashboard), Phase 2 (Commercial dashboard) |
| **Owning lane** | **`HDN-373`** (RLS/RBAC Audit) — the very next lane in this range, the closest charter match; `HDN-372` (this lane) is not deferring this to hide it but because 13 independent `language sql` → `language plpgsql` conversions is a larger, separately-reviewable unit of work than bundling into an already-large 9-function migration |
| **Reachability** | Same as `HDN-BLK-011` |
| **Reproduction** | Code-verified directly against the live catalogue for all 13: `p_actor_auth_user_id uuid default auth.uid()`, `has_assert=false`, `has_can_access=true` — full query and output `HDN-372.md` §5.5 |
| **Blast radius — measured, not estimated** | 13 functions, 2 migration files (`20260728150000_create_operations_dashboard.sql`, `20260724320000_create_commercial_dashboard.sql`), exact function list in `HDN-372.md` §5.5 |
| **Disposition** | **FIXED at `HDN-373`** — see amendment note above |
| **Required of `HDN-373`** | Done — see amendment note above |
| **Regression test** | Done — position-aware named-list check plus a live two-session forced-spoof test, `scripts/db-tests/rbac-enforcement.sql` |
| **Rollback** | Additive migration only; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-165` (`RESOLVED`, High) |

---

## HDN-BLK-013 — app layer's only defense on several high-privilege actions is the database, single point of failure — registered late, corrected at this checkpoint's own Tier C review

| Field | Value |
|---|---|
| **Title** | `admin/api-keys/actions.ts` (rotate/revoke API key, rotate webhook secret, disable/re-enable endpoint, replay delivery, rotate n8n connector) and `POST /api/v1/customer/bookings/{id}/submit` verify the caller's membership in the URL-slug tenant but never that the *target record* belongs to that tenant — the database (`app.check_api_webhook_admin_authority` and friends) is the only control standing between a same-tenant `authenticated` caller and a cross-tenant write on these specific paths |
| **Found by** | `HDN-372` (`CG-S15-HDN-004`), Tenant Isolation Audit, investigation lens 2 (API/service layer) |
| **Severity** | **High** — a mandatory second control is structurally absent on a real, currently-reachable path, per `00_EXECUTION_INDEX.md` §7 ("a mandatory control that is absent... on a real path"). **Live-verified not currently exploitable**: the database-layer check correctly denies every cross-tenant attempt tried. High reflects the absent control, not a live breach — this is the distinction §7 draws between High and Critical, not a reason to grade it lower |
| **Owning phase** | Cross-cutting — Phase 1 (Platform, API keys/webhooks admin), Phase 6 (Customer Portal, booking submission) |
| **Owning lane** | **`HDN-378`** (Security Hardening) — the closest charter match for app-layer defense-in-depth additions; **not this lane's own charter** (`HDN-372` is a tenant-isolation *audit*, and the finding is disclosed and fixed at the database layer already; the app-layer gap is a hardening addition, not a repair of a live isolation breach) |
| **Reachability** | Any `authenticated` session that is a genuine member of *some* tenant, on a route that accepts a client-supplied record ID for one of the named actions, if the database-layer check were ever removed or weakened |
| **Reproduction** | Live-verified: forged cross-tenant `keyId`/`bookingRequestId` correctly denied at the database layer (`insufficient_authority`, `HDN-372.md` §7 A1/A2) — the finding is the absent second control, not a working exploit |
| **Blast radius — measured, not estimated** | 2 route/action files, 6 named actions plus 1 `/v1` route — exact call sites `HDN-372.md` §7 A1/A2 |
| **Disposition** | **Registered, not fixed** — `ISS-2026-166` existed in `docs/runtime/KNOWN_ISSUES.md` since this checkpoint's own first commit but, unlike every other Medium-or-above finding this checkpoint produced, was never given a `BLOCKER_LEDGER` entry until this Tier C amendment. Corrected here rather than left as an unowned High — see `00_EXECUTION_INDEX.md` §8.2 condition 4 |
| **Required of `HDN-378`** | Add an explicit `record.tenantId === access.tenant.id` assertion (or equivalent) in application code before each named action proceeds, as defense-in-depth alongside the existing, already-correct database-layer check |
| **Regression test** | Required with the fix: an app-layer unit/integration test asserting the new check rejects a cross-tenant record ID before any database call is made |
| **Rollback** | N/A — no fix landed yet |
| **`KNOWN_ISSUES`** | `ISS-2026-166` (`OPEN`, High, owner `HDN-378`) |

---

## HDN-BLK-014 — roughly 24 further `SECURITY DEFINER` boolean-oracle / narrow-scope functions share `HDN-BLK-011`'s shape — PARTIALLY RESOLVED at `HDN-373`, residual scope narrowed and re-owned

*Amended at `HDN-373` (2026-08-23), same checkpoint. `HDN-373` independently grepped every
candidate's actual call sites before fixing anything (per this entry's own explicit
instruction not to treat the sweep as proof): 16 of the ~30 candidates (`HDN-372`'s own
Tier C review had already refined "~24" to a fuller list before this checkpoint began) were
confirmed terminal/self-referential (the actor parameter is never mutated or substituted
before reaching any downstream call) and fixed at `20260810400000_harden_crm_ops_actor_
identity_gaps.sql` (773 lines, one `perform app.assert_actor_is_session_identity(...)`
inserted per function). The remaining ~14 (`has_active_tenant_membership`,
`can_access_record`, `is_supreme_admin`, `actor_holds_customer_user_layer`,
`has_active_support_grant`, `claim_case_record_scope_ok`, `label_subject_record_scope_ok`,
`wms_pick_record_scope_ok`, `is_ticket_queue_member`, `current_support_session`,
`pipeline_scope_org_unit_ids`, `evaluate_dispatch_readiness`,
`customer_warehouse_eligibility_active`, `resolve_locale_context`) were confirmed genuinely
called with THIRD-PARTY actor arguments elsewhere in the schema — an unconditional assert
would break every one of those legitimate uses — and are **not fixed**, re-registered
narrower as `ISS-2026-186` with owner `HDN-387` (no dedicated RLS/RBAC-audit lane remains
in Step 15 after `HDN-373`). Full disposition: `docs/build-log/full-system-hardening/
HDN-373.md` §6.*

| Field | Value |
|---|---|
| **Title** | A wider closure sweep than `HDN-BLK-011`'s own bounded, evidence-driven list surfaced roughly 24 more `SECURITY DEFINER` functions granted `EXECUTE` to `authenticated`, taking a claimed-actor parameter, reaching neither `app.evaluate_permission` nor `app.assert_actor_is_session_identity` in their call graph — mostly boolean/narrow-oracle primitives (`can_access_record`, `has_active_tenant_membership`, `actor_holds_customer_user_layer`, `claim_case_record_scope_ok`, `label_subject_record_scope_ok`, `wms_pick_record_scope_ok`, `is_supreme_admin`, plus the 6 named in `20260810000000`'s own header comment: `current_support_session`, `has_active_support_grant`, `is_ticket_queue_member`, `pipeline_scope_org_unit_ids`, `evaluate_dispatch_readiness`, `customer_warehouse_eligibility_active`) and CRM readiness/duplicate-detection helpers (`compute_sales_metric_count`, `evaluate_quotation_approval_requirement`, `find_duplicate_accounts/contacts/leads/prospects`, `find_existing_accounts_for_lead/prospect`, `get_account_conversion_readiness`, `get_job_order_conversion_readiness`, `get_job_shipment_allocation_balance`, `get_opportunity_costing_readiness`, `get_quotation_submission_readiness`, `get_sales_target_actual`, `resolve_locale_context`, `resolve_warehouse_location_by_barcode`) |
| **Found by** | `HDN-372` (`CG-S15-HDN-004`), Tenant Isolation Audit, Tier C security/tenant lens (live-tested), by an independent transitive-closure sweep over the applied catalogue wider than the original checkpoint's own bounded list |
| **Severity** | **Medium** — each returns a boolean or a narrow scalar/array oracle rather than record content, per `00_EXECUTION_INDEX.md` §7's Medium band ("a correctness or control gap with... a narrow reachability path"); not High like `HDN-BLK-011`/`012`, whose functions return full record content |
| **Owning phase** | Cross-cutting — CRM/Commercial (most of the readiness/duplicate-detection functions), Support (queue/session primitives), WMS/Ticketing (scope-check primitives) |
| **Owning lane** | **`HDN-373`** (RLS/RBAC Audit) — the same next-lane charter match as `HDN-BLK-012`; grouping both deferred tenant-isolation classes under one successor lane rather than splitting across more lanes |
| **Reachability** | Same shape as `HDN-BLK-011`/`012` — any `authenticated` session that knows a victim tenant's own real member's `auth_user_id` |
| **Reproduction** | **Not uniformly live-verified.** 3 of the ~24 were spot-checked live by the Tier C lens (`resolve_locale_context`, `has_active_tenant_membership`, `actor_holds_customer_user_layer`) and did reproduce the shape — though `resolve_locale_context`'s own disclosed nature (tenant display/locale configuration, not PII or business data) makes its real-world sensitivity materially lower than the others, which is why it stays on the pre-existing `ATW-032` "anon-facing by design" exemption list rather than being pulled onto this list for an app-layer fix. The remaining ~21 are statically identified by an `app`-schema-wide closure sweep only — **`HDN-373` must independently verify reachability and exploitability per function before fixing, not assume the sweep's candidate list is itself proof** |
| **Blast radius — measured, not estimated** | ~24 functions across the domains named above — exact candidate list and the sweep query `HDN-372.md` §5.7 |
| **Disposition** | **`PARTIALLY_RESOLVED` at `HDN-373`** — 16 fixed, ~14 re-registered narrower as `ISS-2026-186` (owner `HDN-387`), not blindly fixed. See amendment note above |
| **Required of `HDN-373`** | Done for the 16 confirmed-terminal candidates. The residual ~14 need a per-call-site audit (self-referential vs. genuinely third-party call sites, and whether third-party ones need a different check such as `assert_session_identity_in_tenant`) — carried to `ISS-2026-186`, owner `HDN-387` |
| **Regression test** | Done for the 16 fixed — a position-aware named-list check plus a live two-session forced-spoof test, `scripts/db-tests/rbac-enforcement.sql` |
| **Rollback** | Additive migration only for the 16 fixed; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-179` (`PARTIALLY RESOLVED`, Medium); residual scope `ISS-2026-186` (`OPEN`, Medium, owner `HDN-387`) |

---

## Status as of `HDN-372` (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **8** — `HDN-BLK-007` (High), `008` (Medium), `009` (Medium) at `HDN-370`; `HDN-BLK-010` (Medium) at `HDN-371`; `HDN-BLK-011` (High, closed same checkpoint), `HDN-BLK-012` (High), `HDN-BLK-013` (High), and `HDN-BLK-014` (Medium) at `HDN-372` |
| Blockers closed **by** Step 15 to date | **1 class + 1 single** — `HDN-BLK-002` (all four member issues `RESOLVED`); `HDN-BLK-011` (fixed same checkpoint) |
| Total open entries | **12** — `HDN-BLK-001`, `003..010`, `012`, `013`, `014` (`002` and `011` closed) |
| — of which **High** | **4** (`HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-012`, `HDN-BLK-013`) |
| — of which **Medium** | **8** (`HDN-BLK-003..006`, `008`, `009`, `010`, `014`) |
| Unresolved **Critical** anywhere | **0** |

**Two open Highs from this checkpoint (`HDN-BLK-012`, `HDN-BLK-013`) are release blockers for
Step 16 per `00_EXECUTION_INDEX.md` §8.1 items 1-2 until fixed by their named owner or explicitly
ruled an accepted exception at `HDN-387`/`HDN-389`** — carried forward here, not silently left to
be rediscovered.

---

## HDN-BLK-015 — the entire Finance manual/period/config/import-export write surface (95+57 functions) was `SECURITY INVOKER`, unreachable by any real session since it shipped

*Amended at `HDN-373`'s own Tier C review (2026-08-23), same checkpoint. The original
95-function diagnosis was incomplete: an independent, deliberately wider schema-wide sweep
found **57 more functions** sharing the identical shape (54 further Finance-domain, plus
2 generic Config-Engine functions and 1 Integration-domain function), root-caused to the
same mechanism (only 1 of the 19 `check_finance_*_authority` helpers had been granted
`authenticated` directly). Independently re-derived, live-forced (18 representative
functions), and fixed at `20260810900000_harden_finance_authority_chain_tierc_
completeness.sql`, with the closure re-run against the fixed state and confirmed to
converge at zero further matches. The same migration also corrects a live-forced
regression Tier C found in the original `ISS-2026-183` fix (the `FIN:Approve`-only gate on
`app.create_and_post_finance_system_journal` blocked two legitimate `FIN:Edit`-only
callers — now accepts either) and fixes a genuine new High finding the sweep surfaced,
`ISS-2026-193` (`app.preview_finance_config_impact`/`app.validate_custom_field_values`
disclosed another tenant's config data with no tenant check at all). Full disposition:
`docs/build-log/full-system-hardening/HDN-373.md` §6/§13.*

| Field | Value |
|---|---|
| **Title** | 76 top-level Finance (journal, period, exchange rate, tax, invoice, AP/AR, cash, settlement, vendor bill, correction, reconciliation, account, bank) RPCs plus `app.enqueue_job`, each already granted `EXECUTE` directly to `authenticated`, were `SECURITY INVOKER` -- Postgres' implicit default -- instead of `SECURITY DEFINER` like this schema's other 1,878 RPCs. Every nested call in each chain (down to `app.evaluate_permission`'s own internal reads, and the table `INSERT`/`UPDATE` itself) therefore executed as `authenticated`, which holds no grant on `app.permissions`, most Finance authority-check helpers, or DML on `app.finance_journals` and siblings (by design -- identical to every other domain, whose RPCs are correctly `SECURITY DEFINER`) |
| **Found by** | `HDN-373` (`CG-S15-HDN-005`), RLS and RBAC Audit, investigation Lens 2 (access-matrix/`SECURITY DEFINER` posture) and Lens 3 (maker/checker), independently corroborating |
| **Severity** | **High** -- per `00_EXECUTION_INDEX.md` §7, a mandatory control (the entire Finance write surface's RBAC gate) was not merely absent but completely non-functional on a real, currently-shipped, `authenticated`-granted path, live-forced end to end |
| **Owning phase** | Finance (all sub-domains) plus the generic background-job path |
| **Owning lane** | `HDN-373` (own charter -- RLS/RBAC reachability is squarely this lane's audit scope) |
| **Reachability** | Every real Finance-domain `authenticated` session, for every write RPC in the affected list -- not narrow, not requiring any special knowledge or forged identity |
| **Reproduction** | Live-forced: a genuine, non-superuser Finance Manager session calling `app.create_finance_journal_draft` for their own tenant refused with `permission denied for table permissions`, three frames inside `evaluate_permission`. Full transcript `HDN-373.md` §6 |
| **Blast radius — measured, not exhaustively re-derived** | 152 functions total (95 original + 57 found by Tier C's own wider sweep) -- exact lists `20260810700000_harden_finance_authority_chain_security_definer.sql`'s and `20260810900000_harden_finance_authority_chain_tierc_completeness.sql`'s own headers |
| **Disposition** | **FIXED, same checkpoint** -- `20260810700000` (the original 95-function `SECURITY DEFINER` conversion, plus `ISS-2026-183`), `20260810800000` (the `FIN:View` RLS gate `ISS-2026-184` and the journal self-approval guard `ISS-2026-181`), and `20260810900000` (Tier C completeness: the 57 more functions, the `ISS-2026-183` gate correction, and `ISS-2026-193`'s cross-tenant config disclosure fix) -- all mechanically generated from live `pg_get_functiondef` output, diffed byte-identical elsewhere |
| **Required of `HDN-373`** | Done -- full 229-file `scripts/db-tests` suite run clean against a fresh database with real grants (no superuser bypass) after every fix, including the pre-existing ATW-031/032 authority-surface and optimistic-concurrency sweeps; the closure sweep itself re-run against the fully-fixed state and confirmed to converge at zero further matches |
| **Regression test** | `finance-journal.sql`'s own new HDN-373 blocks (self-approval deny-then-allow with a genuinely distinct actor; live authenticated-session `FIN:View` RLS proof, zero-permission member denied); 4 other Finance test files' own pre-existing fixtures updated to use two distinct actors per the new self-approval guard (`finance-lifecycle-state-control.sql`, `finance-period-lock.sql`, `finance-posted-journal-integrity.sql`, `finance-reversal-adjustment.sql`); live-forced cross-tenant attack + legitimate-access control for `ISS-2026-193`; `rbac-enforcement.sql`'s `v_expected` exemption list updated with a written reason for the 2 functions confirmed correct-by-design |
| **Rollback** | Revert the three migrations; `git revert` is clean since nothing downstream depends on the new column/grants |
| **`KNOWN_ISSUES`** | `ISS-2026-182` (root cause, this entry), `ISS-2026-181`, `ISS-2026-183`, `ISS-2026-184`, `ISS-2026-193` (companion fixes) |

---

## Status as of `HDN-373` (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **9** — `HDN-BLK-007` (High), `008` (Medium), `009` (Medium) at `HDN-370`; `HDN-BLK-010` (Medium) at `HDN-371`; `HDN-BLK-011` (High, closed same checkpoint), `HDN-BLK-012` (High), `HDN-BLK-013` (High), `HDN-BLK-014` (Medium) at `HDN-372`; `HDN-BLK-015` (High, closed same checkpoint) at `HDN-373` |
| Blockers closed **by** Step 15 to date | **1 class + 3 single** — `HDN-BLK-002` (all four member issues `RESOLVED`); `HDN-BLK-011` (fixed at `HDN-372`), `HDN-BLK-012` (its 13 dashboard functions fixed at `HDN-373` via `20260810200000_harden_dashboard_actor_identity_gaps.sql`, `ISS-2026-165`), `HDN-BLK-015` (fixed same checkpoint) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013` (3) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `009`, `010`, `014` (8, `014` narrowed to its residual ~14-function scope -- `ISS-2026-186`) |
| Unresolved **Critical** anywhere | **0** |

`HDN-BLK-013` remains an open release blocker for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until
fixed by its named owner or explicitly ruled an accepted exception at `HDN-387`/`389`.

---

## HDN-BLK-016 — `app.request_finance_settlement_reversal` posts no reversing GL journal at all, permanently desyncing GL from the AP subledger on every settlement reversal

*Found at `HDN-374`'s own Tier C review (2026-08-23), same checkpoint — an independent
adversarial lens live-forcing areas the checkpoint's own 4 investigation lenses had called
"clean" (period lock, reversal/correction). A companion, narrower defect on the same
function (a complete period-lock bypass) was found by the same lens and fixed in the same
Tier C fix pass; this one is registered, not fixed, since it needs a larger design decision.
Full disposition: `HDN-374.md` §13.3, `KNOWN_ISSUES.md` `ISS-2026-199`.*

| Field | Value |
|---|---|
| **Title** | `app.request_finance_settlement_reversal` mutates only `app.finance_ap_open_items`'s own `settled_amount`/`status` and logs an event — it never calls `app.create_and_post_finance_system_journal` or any other GL-posting primitive, so reversing a posted settlement reopens the AP subledger while the GL still shows the original payment as posted, with no system-generated correction path to reconcile them |
| **Found by** | `HDN-374` (`CG-S15-HDN-006`), Financial Integrity Audit, Tier C adversarial review lens (wider financial-integrity sweep) — live-forced, not code-inferred |
| **Severity** | **High** — a real, live-forced, permanent GL/AP reconciliation break, squarely the "every financial flow reconciles to exact source-linked totals... at one checkpoint" business rule this lane's own charter states (Prompt 374 §21), reachable by any ordinary FIN:Approve holder |
| **Owning phase** | Finance (AP settlement/reversal) |
| **Owning lane** | Registered by `HDN-374`; owned by `HDN-386` (Full-System Hardening Integrated Verification) — composing a correct automatic reversing journal is a design decision (account mapping, automatic vs. a separate governed step mirroring `app.prepare_finance_journal_reversal`'s own maker/checker shape) outside this bounded-repair checkpoint's own scope |
| **Reachability** | Any FIN:Approve holder calling `app.request_finance_settlement_reversal` against any posted settlement |
| **Reproduction** | Live-forced: a posted settlement (real GL journal, debit AP/credit cash) reversed via this governed path — AP open item correctly returned to `open`; the original GL journal remained `posted`, unchanged; zero correction/reversal journals existed anywhere afterward. Full transcript `HDN-374.md` §13.3 |
| **Blast radius** | Every settlement reversal in this codebase, past and future, until fixed — an unbounded, ongoing GL/AP desync source, not a one-time data-quality issue |
| **Disposition** | **Registered, not fixed.** The narrower, companion period-lock bypass on this SAME function was fixed in this same checkpoint's own Tier C fix pass (`20260811200000_harden_financial_integrity_tierc_fixes.sql`) — this finding (no reversing journal at all) needs a design decision this bounded-repair checkpoint cannot make unilaterally |
| **Required of `HDN-386`** | Decide and implement (or explicitly accept as residual risk with a documented manual-correction procedure): whether `app.request_finance_settlement_reversal` should automatically post a reversing GL journal, and if so, its exact account mapping and idempotency/concurrency shape mirroring this codebase's own established correction-journal patterns |
| **Regression test** | Required with the eventual fix — a live-forced proof that a reversed settlement's own GL journal is corrected, not merely the AP subledger |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-199` (`OPEN`, High) |

---

## Status as of `HDN-374` (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **10** — `HDN-374`'s own Tier C review opened `HDN-BLK-016` (High, registered not fixed) |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial** — `HDN-BLK-002` (all four member issues `RESOLVED`); `HDN-BLK-011`, `HDN-BLK-012`, `HDN-BLK-015` (fixed); `HDN-BLK-010` **partially** (Finance/HRIS-Payroll portion `RESOLVED` at `HDN-374`, 3 non-Finance functions + `ISS-2026-163` handed to `HDN-387`) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016` (4) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `009`, `010` (narrowed), `014` (8, unchanged count — `010`'s own scope narrowed rather than closed) |
| Unresolved **Critical** anywhere | **0** |

`HDN-BLK-013` and `HDN-BLK-016` are open release blockers for Step 16 per `00_EXECUTION_INDEX.md`
§8.1 until fixed by their named owner or explicitly ruled an accepted exception at `HDN-387`/`389`.

---

## HDN-BLK-017 — the 5 "hash-chain" transaction-lineage triggers are standalone content fingerprints, not a genuine tamper-evident chain, and no reconciliation ever recomputes or compares them

*Found at `HDN-375`'s own investigation (2026-08-24), same checkpoint. Full disposition:
`HDN-375.md` §6, `KNOWN_ISSUES.md` `ISS-2026-200`.*

| Field | Value |
|---|---|
| **Title** | `app.trg_capture_lineage_job_to_shipment`/`_shipment_to_epod`/`_shipment_to_cost`/`_job_to_profitability`/`_job_to_billing_readiness` (OPS-184) each compute a standalone SHA-256 fingerprint of one row's own content, with no reference to any prior edge's own hash — not a genuine `H_n = f(H_{n-1}, content_n)` chain, despite being named and documented as one. `app.detect_transaction_lineage_anomalies` has no hash-mismatch/tamper-detection anomaly type at all; `source_version_hash` is write-only and display-only everywhere in the repository |
| **Found by** | `HDN-375` (`CG-S15-HDN-007`), Data Lineage Audit, investigation lens (hash-chain triggers and historical config preservation) — live-forced: a raw tamper to a source row produces a detectable mismatch on manual recomputation, but nothing in the product ever recomputes or compares it |
| **Severity** | **High** — per `00_EXECUTION_INDEX.md` §7, this lane's own charter states the business value as "make CargoGrid explainable, auditable and recoverable from source to report," and no mechanism anywhere would ever surface a tampered source record or a tampered lineage row to a human. Not Critical: no UI/documentation surfaces "hash chain" to an end user as a tamper-proof guarantee, and RPD-022/the threat model never claims any repository ledger is tamper-proof |
| **Owning phase** | Operations (transaction lineage, OPS-184) |
| **Owning lane** | Registered by `HDN-375`; owned by `HDN-386` (Full-System Hardening Integrated Verification) — implementing genuine chaining (canonical ordering, a real `prev_hash` column, backfill of every existing row, extending the anomaly detector) is a design decision outside this bounded-repair checkpoint's own scope |
| **Reachability** | N/A (a detection/integrity gap, not an access-control reachability issue) — any historical or future tamper to a lineage-tracked source row goes undetected regardless of actor |
| **Reproduction** | Live-forced: `UPDATE`d a source row's own content directly (bypassing every RPC); manually recomputed `source_version_hash` and confirmed a real mismatch against the stored value; confirmed `detect_transaction_lineage_anomalies`'s own 4 anomaly types never check this. Full transcript `HDN-375.md` §6 |
| **Blast radius** | Every one of OPS-184's own 5 hash-chained relation types, past and future, until fixed |
| **Disposition** | **Registered, not fixed.** A narrower, genuinely bounded-repair-sized half of this same area — the evidence ledger's own mutability (`ISS-2026-201`/formerly this same investigation) — was fixed in this checkpoint's own migration |
| **Required of `HDN-386`** | Decide and implement (or explicitly accept as residual risk with a documented reconciliation procedure): a real per-relation-type chain ordering, a `prev_hash` column, backfill, and a hash-mismatch anomaly type in `detect_transaction_lineage_anomalies` |
| **Regression test** | Required with the eventual fix — a live-forced proof that a tampered source row is actually detected and surfaced, not merely detectable by hand |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-200` (`OPEN`, High) |

---

## HDN-BLK-018 — the append-only-guard pattern `HDN-BLK-017`'s own sibling finding (`ISS-2026-201`) applied to one table is genuinely needed on roughly 70 more tables schema-wide, including `app.audit_logs` itself

*Found at `HDN-375`'s own Tier C review (2026-08-24), same checkpoint, by the
completeness-sweep lens. Full disposition: `HDN-375.md` §13.2, `KNOWN_ISSUES.md`
`ISS-2026-205`.*

| Field | Value |
|---|---|
| **Title** | Only 13 tables in the entire `app` schema carry a real `BEFORE UPDATE/DELETE` append-only guard trigger. At minimum ~70 more tables are documented as append-only/immutable/"never updated, never deleted" or are functionally an audit/event/ledger/history table by name and role, carry no such guard, and have `service_role` holding live `UPDATE`/`DELETE` grants — genuinely reachable, not merely a naming-pattern match already protected by revoked grants |
| **Found by** | `HDN-375` (`CG-S15-HDN-007`), Data Lineage Audit, Tier C completeness-sweep lens — live-forced via direct `pg_trigger`/`information_schema.role_table_grants` queries against a fresh disposable database, not a grep sweep alone |
| **Severity** | **High** — the same vulnerability class already rated High for one table (`ISS-2026-201`), now shown to span a materially larger, more central surface. Most severe live-forced instance: `app.audit_logs` itself — the canonical, tenant-wide audit trail every `app.capture_audit_event()` call writes to, including `ISS-2026-201`'s own new exception-path evidence — freely `UPDATE`/`DELETE`-able by `service_role` with zero guard, despite already having its own RPC-level Supreme-Admin discipline (`app.supreme_admin_mutate_audit_log`/`app.supreme_admin_delete_audit_log`, RPD-022) with no schema-level backstop. Second: `app.inventory_movements`, the exact table CPL-325's own migration header already disclosed as not covered, still unguarded |
| **Owning phase** | Cross-cutting — spans Platform Core (`audit_logs`), Advanced TMS/WMS (`inventory_movements` and ~15 more), Finance, Commercial, Operations, HRIS, Procurement, Customer Portal/Loyalty, and Phase 9 domains |
| **Owning lane** | Registered by `HDN-375`; owned by `HDN-386` (Full-System Hardening Integrated Verification) — blanket-applying an append-only guard to ~70 tables is behavior-RESTRICTING (unlike a validation trigger, which can never block a legitimate write), so each table needs its own legitimate-write-path audit before a guard can be safely added, mirroring the one-table-at-a-time discipline CPL-325 and this checkpoint's own Finding 1 already used — a genuinely larger undertaking than one Tier C session's own bounded-repair budget |
| **Reachability** | Any `service_role`-mediated write (i.e. any `SECURITY DEFINER` function, or a compromised service-role key) against any of the ~70 unguarded tables |
| **Reproduction** | Live-forced against `app.audit_logs`: `SET ROLE service_role; INSERT ...; UPDATE ... SET reason='TAMPERED...', result='success'; DELETE ...` — all three succeeded silently. Live-forced against `app.inventory_movements`: insert, then `UPDATE`/`DELETE` both succeeded with no error. Full table list and catalogue-query method: `HDN-375.md` §13.2 |
| **Blast radius** | Every one of the ~70 tables' own historical and future rows, until each is individually audited and fixed — most significantly, every other detective/audit-based control in this codebase (including `HDN-BLK-017`'s own sibling fix, `ISS-2026-201`) that relies on `app.audit_logs` as its evidence of record |
| **Disposition** | **Registered, not fixed.** `ISS-2026-201`'s own single-table fix (this checkpoint's first round) is not extended to any of these ~70 tables |
| **Required of `HDN-386`** | Audit and fix each table individually, prioritized by centrality and reachability — `app.audit_logs` first, given every other detective control's own dependency on it, followed by the ranked remainder; for each, confirm no legitimate non-Supreme-Admin UPDATE/DELETE call path exists before adding the guard, exactly as CPL-325/`ISS-2026-201` already did one table at a time |
| **Regression test** | Required with each table's own fix — a live-forced proof mirroring `ISS-2026-201`'s own regression blocks (no-actor-context and ordinary-staff denial, genuine Supreme Admin override with audit capture) |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-205` (`OPEN`, High) |

---

## Status as of `HDN-375` (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **12** — `HDN-375`'s own first round opened `HDN-BLK-017` (High, registered not fixed); its own Tier C review opened `HDN-BLK-018` (High, registered not fixed). Its Tier C review also registered a further Medium finding, `ISS-2026-206` (orphan-`source_id` gap recurring on `finance_subledger_batches` and others), which did not receive its own ledger entry — Medium, non-systemic-scale, no release-blocker designation, matching this ledger's own established convention (e.g. `ISS-2026-186`/`197`) |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial** — unchanged from `HDN-374`'s own close (`HDN-BLK-017`/`018` are newly registered, not closed) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018` (6) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `009`, `010` (narrowed), `014` (8, unchanged) |
| Unresolved **Critical** anywhere | **0** |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017` and `HDN-BLK-018` are open release blockers
for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until fixed by their named owner or
explicitly ruled an accepted exception at `HDN-387`/`389`.

## HDN-BLK-019 — a legal hold placed on a file does not extend to protect that file's own `app.file_access_logs` evidence rows, the same missing-guard root cause as `HDN-BLK-018` plus an unbuilt hold-cascade

*Found at `HDN-377` (2026-08-24), same checkpoint, by the file-access-audit-and-
retention lens. Full disposition: `HDN-377.md` §6, `KNOWN_ISSUES.md` `ISS-2026-222`.*

| Field | Value |
|---|---|
| **Title** | `app.file_access_logs` carries zero triggers at all (not even a `BEFORE UPDATE` `touch_row`), and `service_role` holds live `UPDATE`/`DELETE` on the table — so even a file under an active legal hold (via either of `HDN-377`'s own now-bridged hold mechanisms, `ISS-2026-217`) has its own access-log evidence rows freely mutable/deletable, with no cascade logic anywhere consulting the parent file's hold state |
| **Found by** | `HDN-377` (`CG-S15-HDN-009`), Storage and Signed URL Audit, file-access-audit-and-retention lens — live-forced: inserted a real access-log row for a legally-held file, then `delete from app.file_access_logs where id = ...` succeeded unconditionally |
| **Severity** | **High** — a real, live-forced gap in retention/legal-hold coverage for evidence data, directly relevant to RPD-025's "tested across database, files, **logs**, reports, exports, AI evidence and audit" requirement, but not independently exploitable beyond what `HDN-BLK-018` already discloses (the same missing-trigger population covers this exact table) |
| **Owning phase** | Platform Core / Storage (PLT-128's own `app.file_access_logs`) |
| **Owning lane** | `HDN-386` (Full-System Hardening Integrated Verification) — same owner as `HDN-BLK-018`, since the fix requires both (a) the generic append-only guard `HDN-BLK-018` already scopes this table into, and (b) new hold-cascade logic (a guard trigger consulting the parent file's `legal_hold`/`app._is_under_legal_hold` state before permitting mutation) that does not exist yet for any table in this codebase — bundled with the same guard-rollout charter rather than fixed as a one-off |
| **Reachability** | Any `service_role`-mediated write (i.e. any `SECURITY DEFINER` function, or a compromised service-role key) against `app.file_access_logs`, regardless of the parent file's own hold state |
| **Reproduction** | Live-forced: file with `legal_hold=true`; inserted a real `app.file_access_logs` row for a granted download of it; `delete from app.file_access_logs where id = ...` succeeded with no error. Full detail: `HDN-377.md` §6 |
| **Blast radius** | The access-log evidence trail for every legally-held file, until `app.file_access_logs` receives both a real guard trigger and hold-aware cascade logic |
| **Disposition** | **Registered, not fixed.** `HDN-377`'s own Finding C (`ISS-2026-218`) added a schema-level backstop for `app.files` itself; this entry is the narrower, evidence-log-specific gap that survives even after that fix |
| **Required of `HDN-386`** | When rolling out `HDN-BLK-018`'s own append-only guard to `app.file_access_logs`, also add hold-aware cascade logic (consulting the referenced file's own `legal_hold`/`app._is_under_legal_hold` state) rather than a bare append-only guard alone |
| **Regression test** | Required with the fix — mirroring `HDN-377`'s own regression shape (a legally-held file's access-log row survives a direct mutation attempt; an un-held file's does not gain new restrictions) |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-222` (`OPEN`, High) |

---

## HDN-BLK-020 — `app.audit_logs.legal_hold` is enforced nowhere: neither the native flag nor the generic (IAE-031) hold mechanism is checked before physical deletion of the platform's own canonical audit trail

*Found at `HDN-377`'s own Tier C review (2026-08-24), same checkpoint, by the
completeness-sweep lens. Full disposition: `HDN-377.md` §13.2, `KNOWN_ISSUES.md`
`ISS-2026-229`.*

| Field | Value |
|---|---|
| **Title** | `app.audit_logs.legal_hold` has its own dedicated setter (`app.supreme_admin_mutate_audit_log`), but its own deletion RPC (`app.supreme_admin_delete_audit_log`) never checks it at all — not the native flag, not the generic `app._is_under_legal_hold()` mechanism (never bridged to `app.audit_logs`, unlike `app.files` after this checkpoint's own fix). A dead invariant at both layers simultaneously, on the audit trail every other detective control in this codebase depends on as evidence of record |
| **Found by** | `HDN-377` (`CG-S15-HDN-009`), Storage and Signed URL Audit, Tier C completeness-sweep lens — live-forced: set `legal_hold=true` on a real audit row via the native setter, then called `app.supreme_admin_delete_audit_log` — the row was physically deleted |
| **Severity** | **Critical** — the most severe instance of the dual-mechanism-drift class (`RECURRING_DEFECT_TAXONOMY.md` C-25) found anywhere this checkpoint. Supreme-Admin-reachable and self-serving (the same authority both sets and bypasses the hold), against the exact table every other detective control in this codebase relies on as its own evidence of record, including this checkpoint's own new triggers' own audit captures |
| **Owning phase** | Platform Core (`app.audit_logs`, `20260716113048_create_audit_trail.sql`) |
| **Owning lane** | `HDN-386` (Full-System Hardening Integrated Verification) — bundled with the already-registered `HDN-BLK-018` (the general append-only-guard rollout gap covering this exact table): the two invariants, append-only and legal-hold, should be added to `app.audit_logs` together, not as two separate passes |
| **Reachability** | Any actor holding Supreme Admin (the same authority the native setter itself requires), or any `service_role`-mediated write bypassing `app.supreme_admin_delete_audit_log` entirely |
| **Reproduction** | Live-forced: `perform app.supreme_admin_mutate_audit_log(..., legal_hold => true, ...)` on a real row; `perform app.supreme_admin_delete_audit_log(...)` on the same row succeeded, row gone. Full detail: `HDN-377.md` §13.2 |
| **Blast radius** | Every audit-log row ever placed under legal hold, until `app.audit_logs` receives both a real guard trigger and legal-hold enforcement |
| **Disposition** | **Registered, not fixed.** Not a file/storage table — outside this checkpoint's own charter |
| **Required of `HDN-386`** | When rolling out `HDN-BLK-018`'s own append-only guard to `app.audit_logs`, also enforce `legal_hold` (native flag, and bridge into `app._is_under_legal_hold()` mirroring `HDN-377`'s own `app.files` fix) in the same pass |
| **Regression test** | Required with the fix — a legally-held audit-log row must survive both `supreme_admin_mutate_audit_log`'s own write path attempting to alter protected fields and `supreme_admin_delete_audit_log`, mirroring `HDN-377`'s own `ISS-2026-226`/`227` regression shape |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-229` (`OPEN`, Critical) |

---

## HDN-BLK-021 — `app.tenants.legal_hold` is invisible to the generic (IAE-031) legal-hold mechanism in both directions, and no RPC exists to set the native flag at all

*Found at `HDN-377`'s own Tier C review (2026-08-24), same checkpoint, by the
completeness-sweep lens. Full disposition: `HDN-377.md` §13.2, `KNOWN_ISSUES.md`
`ISS-2026-230`.*

| Field | Value |
|---|---|
| **Title** | `app.tenants.legal_hold`'s own native trigger (`app.enforce_tenant_status_transition`) correctly blocks termination when the native flag is true, but no RPC anywhere sets that column (reachable only via a raw superuser/service_role UPDATE), and it was never bridged into the generic `app.legal_holds`/`app._is_under_legal_hold()` mechanism in either direction |
| **Found by** | `HDN-377` (`CG-S15-HDN-009`), Storage and Signed URL Audit, Tier C completeness-sweep lens — live-forced: a generic hold on scope `app.tenants` did not prevent `app.transition_tenant_status(..., 'terminated', ...)` from succeeding |
| **Severity** | **High** — Supreme-Admin/service-role-reachable; the practical exposure is narrower than `HDN-BLK-020`'s audit-log instance (no legitimate RPC path sets the native flag at all today), but a tenant terminated mid-hold is a severe failure mode when it does occur |
| **Owning phase** | Platform Core (`app.tenants`, `20260716075355_create_tenants.sql`) |
| **Owning lane** | `HDN-386` (Full-System Hardening Integrated Verification) — bundled with `HDN-BLK-020`'s own C-25 reconciliation work; a single pass should decide which native-hold-shaped columns (`app.tenants`, `app.audit_logs`, any others found) get bridged into `app.legal_holds`, rather than one-table patches |
| **Reachability** | Any Supreme Admin or `service_role`-mediated write |
| **Reproduction** | Live-forced: `app.request_legal_hold(scope='app.tenants', tenant.id)` recorded active; `app.transition_tenant_status(..., 'terminated', ...)` succeeded regardless. Full detail: `HDN-377.md` §13.2 |
| **Blast radius** | Every tenant ever placed under a generic legal hold, until this bridge exists |
| **Disposition** | **Registered, not fixed.** Not a file/storage table — outside this checkpoint's own charter |
| **Required of `HDN-386`** | Bridge `app._is_under_legal_hold()` to also check `app.tenants.legal_hold` (mirroring `HDN-377`'s own `app.files` bridge), and decide whether a real RPC should set the native flag at all going forward or whether the generic mechanism alone should govern tenants |
| **Regression test** | Required with the fix |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-230` (`OPEN`, High) |

---

## HDN-BLK-022 — the coarse-tenant-membership-RLS-plus-fine-RPC-gate pattern recurs across at least ~35 more Procurement/HR tables, live-forced exploitable — corrects `HDN-377`'s own first-round disposition of `ISS-2026-225` from Low/"safe by construction" to High

*Found at `HDN-377`'s own Tier C review (2026-08-24), same checkpoint, by the
completeness-sweep lens, correcting the first round's own under-count. Full
disposition: `HDN-377.md` §13.2, `KNOWN_ISSUES.md` `ISS-2026-225` (corrected).*

| Field | Value |
|---|---|
| **Title** | The RLS bypass shape `HDN-377`'s own `ISS-2026-220` fixed for 2 Procurement tables recurs across ~35 more Procurement/HR tables that DO carry a real `authenticated` SELECT grant (not "most carry no grant, safe by construction" as the first round's own `ISS-2026-225` disclosed) — each correctly gates its own RPC read path on `PRC:View`/`HRS:View` while RLS remains bare tenant-membership |
| **Found by** | `HDN-377` (`CG-S15-HDN-009`), Storage and Signed URL Audit, Tier C completeness-sweep lens — queried `information_schema.role_table_grants` for every Procurement/HR table with a real `authenticated` grant (60 found, not "most safe"), cross-referenced `pg_policies` (58 of 60 gate on bare tenant membership), sampled 51 for RPC-layer module-permission requirements (~35 confirmed), live-forced 2 (`app.vendor_kpi_scorecards`, `app.position_grades`) |
| **Severity** | **High** (corrected from the first round's own Low) — live-forced genuine exploitability against real vendor-performance and HR-recruitment data, not a coverage/completeness gap as originally disclosed |
| **Owning phase** | Procurement (Phase 6) and HRIS (Phase 7) |
| **Owning lane** | `HDN-378` (Security Hardening) — unchanged owner from the first round's own disposition, only the severity and scope are corrected |
| **Reachability** | Any active tenant member holding zero PRC/HRS role assignment |
| **Reproduction** | Live-forced: zero-PRC-role tenant member direct-`SELECT`ed all 4 `app.vendor_kpi_scorecards` rows (real `composite_score`/`band` data) while `list_vendor_kpi_scorecards` correctly denied the identical actor; zero-HRS-role `org_user` direct-`SELECT`ed the seeded `app.position_grades` row in full while `list_position_grades` correctly denied it. Full detail and the named ~35-table list: `HDN-377.md` §13.2 |
| **Blast radius** | Every one of the ~35+ tables' own current and future rows, for any zero-permission active tenant member |
| **Disposition** | **Registered, not fixed** — still not bounded-repair-sized for a storage-audit checkpoint (~35+ tables across two domains), but the severity/scope correction itself is recorded now rather than left understated |
| **Required of `HDN-378`** | A dedicated sweep-and-fix pass across the named table population, mirroring `HDN-377`'s own `app.check_procurement_authority`/`ISS-2026-220` fix pattern (or the HR-domain equivalent) |
| **Regression test** | Required with each table's own fix — mirroring `ISS-2026-220`'s own regression shape (zero-role actor denied via RLS; role-holding actor unaffected) |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-225` (`OPEN`, High, corrected from Low) |

---

### `HDN-BLK-023` — `app.set_integration_connection_status` independently bypasses `ISS-2026-150`'s own IP-restriction fix, IAE-026's lockout guard, and step-up-MFA simultaneously

| Field | Value |
|---|---|
| **Title** | The generic, shared status-setter behind `app.activate_enterprise_idp_connection` (this checkpoint's own hardened IP-restriction wrapper) is independently `EXECUTE`-granted to `authenticated`, gated only on a bare `INTHUB:Configure` check — none of the SSO wrapper's own extra protections (lockout guard, step-up-MFA, IP-restriction) |
| **Found by** | `HDN-378` (`CG-S15-HDN-010`), Security Hardening, Tier C attack-surface adversarial testing lens — live-forced end to end against a real disposable database |
| **Severity** | **Critical** — fully defeats 3 independently-shipped, already-`VERIFIED` security controls for a tenant-wide SSO login-routing reconfiguration (one of RPD-023's own named highest-consequence action classes) via a single direct RPC call |
| **Owning phase** | Phase 9 (Intelligence, Automation and Enterprise Expansion) — `app.set_integration_connection_status` created at Prompt 336 (IAE-008), the SSO-specific wrapper's own extra protections added by IAE-026, `CG-S14-IAE-039`, and this checkpoint, none of which closed the loophole in the shared generic primitive |
| **Owning lane** | `HDN-386` (Integrated Verification) |
| **Reachability** | Any actor holding a legitimately-granted `INTHUB:Configure` permission for the target tenant — not zero authority, but not `IAM:Configure` or any of the SSO wrapper's own extra checks either |
| **Reproduction** | Created a disabled enterprise SSO connection with zero verified test logins, tenant under an `enforced`-mode IP allowlist; the hardened wrapper correctly denied an `INTHUB:Configure`-only actor with no in-range IP; calling `app.set_integration_connection_status(conn.id, 'active', ...)` directly, as that same actor, succeeded — reactivating the connection with zero client IP supplied |
| **Blast radius** | Every enterprise SSO connection activation/reactivation across every tenant; potentially every other connection type's own equivalent specialized wrapper, not yet audited |
| **Disposition** | **Registered, not fixed** — the correct fix is a genuine design decision (conditional guard inside the shared function vs. revoking direct callers entirely) touching a heavily-reused primitive, exceeding what a Tier C review pass should rush |
| **Required of `HDN-386`** | Decide and implement the fix shape; audit whether any other connection type's own specialized wrapper has the same bypass |
| **Regression test** | Required with the fix — must prove the direct-call path is closed while the legitimate wrapper-mediated path still works |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-235` (`OPEN`, Critical) |

---

### `HDN-BLK-024` — 3 of `app.is_high_risk_action`'s own 7 hardcoded platform-default high-risk tuples (61 real functions) never received step-up-MFA or IP-restriction wiring

| Field | Value |
|---|---|
| **Title** | `SEC:Configure` (7 functions, including the very functions that configure MFA/IP enforcement itself — a "guard the guards" gap), `FIN:Approve` (32 functions), `HRS:Approve` (22 functions) never appear in the `IAE-037` → `CG-S14-IAE-039` → `HDN-378` step-up-MFA/IP-restriction wiring lineage at all |
| **Found by** | `HDN-378` (`CG-S15-HDN-010`), Security Hardening, Tier C schema-wide completeness sweep lens — live `pg_proc.prosrc` inspection across the whole `app` schema, cross-referenced against real TS Server Action callers |
| **Severity** | **High** — the same missing-control shape `ISS-2026-150`/`151` were rated for 1-4 functions apiece, found here across 61 additional live, reachable functions never previously disclosed |
| **Owning phase** | Phase 4 (Finance), Phase 7 (HRIS), Phase 9 (enterprise security config) — `is_high_risk_action`'s own tuple list is Phase 9 (`IAE-037`) |
| **Owning lane** | `HDN-386` (Integrated Verification), extending/superseding the `ISS-2026-150`/`151` lineage |
| **Reachability** | Any actor holding the relevant module permission (`FIN:Approve`, `HRS:Approve`, or `SEC:Configure`) for the target tenant — all 61 functions confirmed `authenticated`-executable and TS-caller-reachable, not dead code |
| **Reproduction** | Direct `pg_proc.prosrc` grep for a call to `assert_current_step_up_authorization`/`assert_ip_allowed` inside every function gating on one of the 3 tuples — 0 of 61 call either guard; sample TS callers confirmed for `approve_finance_invoice`, `close_finance_period`, `decide_overtime_request`, `set_mfa_tenant_policy`, `revoke_user_session`, `set_ip_allowlist_enforcement_mode` |
| **Blast radius** | 32 Finance approval/posting/period-close functions, 22 HRIS approval functions, 7 platform Security-configuration functions (including the enforcement-mode togglers and bypass-grant self-service functions) across every tenant |
| **Disposition** | **Registered, not fixed** — the fix shape (which of the 61 get step-up, IP-restriction, or both, bounded across 3 domains) is a real design decision, not a mechanical patch |
| **Required of `HDN-386`** | Re-derive the full wiring plan for all 3 tuples, prioritizing `SEC:Configure` first given its "guard the guards" nature |
| **Regression test** | Required with each tuple's own fix, mirroring the `ISS-2026-150`/`151` fixture-adaptation shape |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-236` (`OPEN`, High) |

---

## Status as of `HDN-378` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **18** — `HDN-378`'s own first round opened zero new formal entries (its Medium findings, `ISS-2026-233`/`234`, are registered in `KNOWN_ISSUES.md` only, matching this ledger's own convention). Its Tier C review opened `HDN-BLK-023` (Critical — `app.set_integration_connection_status` independently bypasses this checkpoint's own IP-restriction fix, the pre-existing IAE-026 lockout guard, and step-up-MFA) and `HDN-BLK-024` (High — 3 of `is_high_risk_action`'s own 7 hardcoded tuples, 61 functions, never wired) |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial** — unchanged; none of the open `HDN-BLK-` entries were this checkpoint's own to close (`HDN-BLK-020..024` all owned by `HDN-386`) |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, `HDN-BLK-023` new this checkpoint's own Tier C) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024` (10, `HDN-BLK-024` new this checkpoint's own Tier C) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `009`, `010` (narrowed), `014` (8, unchanged) |
| Unresolved **Critical** anywhere | **2** — `HDN-BLK-020` (`app.audit_logs.legal_hold` unenforced) and `HDN-BLK-023` (`app.set_integration_connection_status` bypass), both registered not fixed, both owner `HDN-386` |
| **`HDN-378`'s own charter items — first round vs Tier C correction** | `ISS-2026-150` (IP restriction structurally unreachable, High) first-round-`RESOLVED`, **corrected to `PARTIALLY RESOLVED` at Tier C** once `HDN-BLK-023`'s own wrapper-bypass was found — the 4 named functions' own IP-restriction check is real and correctly enforced when reached, but is not the only path to the same effect for `activate_enterprise_idp_connection`. `ISS-2026-168`/`ISS-2026-232` both first-round-`RESOLVED`, **each had a further Tier C-found bypass fixed the same pass** (see `KNOWN_ISSUES.md`) and remain `RESOLVED`. `ISS-2026-233` first-round-`RESOLVED`, held clean under 2 further independent adversarial lenses; its SQL-side sibling gap (`app.validate_webhook_url`) found and fixed the same Tier C pass |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023` and `HDN-BLK-024` are open
release blockers for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until fixed by their
named owner or explicitly ruled an accepted exception at `HDN-387`/`389`.

## HDN-BLK-025 — 36 of 38 tenant-module routes render with no `<main>` landmark

| Field | Value |
|---|---|
| **Title** | 36 of 38 tenant-module top-level routes have no `<main>`/`role="main"` landmark anywhere in their render tree — no shared tenant-shell layout exists to provide one |
| **Found by** | `HDN-380` (Accessibility Audit), source-evidence sweep, independently re-derived directly against the file tree |
| **Severity** | Medium |
| **Owning phase** | Step 15 (Accessibility) / a future dedicated frontend-architecture task |
| **Owning lane** | A dedicated future task |
| **Reproduction** | Grepped `<main` across every `layout.tsx`/`page.tsx` under each of `app/(tenant)/[tenantSlug]/`'s 38 top-level module directories: only `admin` and `commercial` have one. `app/(tenant)/[tenantSlug]/layout.tsx` does not exist; no shared `PortalShell`-style component provides one elsewhere |
| **Disposition** | **`OPEN`** — the correct fix (one shared tenant-shell layout wrapping all 38 modules) is an architectural change outside `HDN-380`'s own "5-15 files, bounded repair" charter |
| **`KNOWN_ISSUES`** | `ISS-2026-241` |

## HDN-BLK-026 — accessible form primitives (`FormField`/validation-message) adopted in only a handful of 200 form-bearing files

| Field | Value |
|---|---|
| **Title** | `components/forms/form-field.tsx`/`validation-message.tsx` are referenced by only 3-4 of the 200 `.tsx` files that render a `<form>`; `aria-invalid` appears in only 5 files app-wide |
| **Found by** | `HDN-380` (Accessibility Audit), source-evidence sweep, independently re-derived directly against the source tree |
| **Severity** | Medium |
| **Owning phase** | Step 15 (Accessibility) / a future dedicated frontend-architecture task |
| **Owning lane** | A dedicated future task |
| **Reproduction** | `grep -rl "<form" app --include="*.tsx" \| wc -l` → 200; `grep -rl "FormField"` → 3; `grep -rl "ValidationSummary\|validation-message usage"` → 1; `grep -rl "aria-invalid"` → 5 |
| **Disposition** | **`OPEN`** — retrofitting field-level error association onto ~200 hand-rolled forms is a large, wide-blast-radius undertaking outside `HDN-380`'s own bounded charter |
| **`KNOWN_ISSUES`** | `ISS-2026-242` |

## Status as of `HDN-380` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **20** — `HDN-380` opened `HDN-BLK-025` (Medium, missing `<main>` landmarks) and `HDN-BLK-026` (Medium, accessible-form-primitive under-adoption) at the first round; Tier C review opened no new `HDN-BLK-` entry (its own 1 new finding, `ISS-2026-243`, is Low and registered in `KNOWN_ISSUES.md` only, matching this ledger's own convention for Low/informational findings) |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged set from `HDN-378`'s own close, plus `HDN-BLK-009` **resolved at the first round** (the `e2e` harness's dev-mode hang, `ISS-2026-160`), unchanged by Tier C |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024` (10, unchanged) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged from the first round) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-380`'s own charter items — first round plus Tier C** | Color-contrast token fixes (6 tokens, `app/globals.css`), `eslint-plugin-jsx-a11y` `recommended` enablement + 14 real errors fixed, 13 total missing `role="alert"` additions (7 first round + 6 more found and fixed at Tier C, `vendor-detail-panel.tsx`), `HDN-BLK-009` root-caused and fixed at the first round (harness 18/18 green, unchanged by Tier C), `ISS-2026-241`/`242` registered at the first round (too large to fix this checkpoint), `ISS-2026-243` registered at Tier C (Low, `reuseExistingServer` stale-build footgun). **Tier C review found no Critical or High finding at either round** — unlike `HDN-378`'s and `HDN-379`'s own Tier C passes, no genuine bypass or structural weakening was found in this checkpoint's own headline fix; only small, mechanically-fixable gaps (see `HDN-380.md` §13) |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025` and `HDN-BLK-026` are open release blockers for Step 16 per
`00_EXECUTION_INDEX.md` §8.1 until fixed by their named owner or explicitly ruled an
accepted exception at `HDN-387`/`389`.

## Reserved

`HDN-BLK-027` onward are unassigned. Every Step 15 finding takes the next free ID and the
full record format of the execution index §14. A finding missing any field is not
registered — and an unregistered finding is not a finding.
