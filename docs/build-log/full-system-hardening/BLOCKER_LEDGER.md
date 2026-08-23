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

## Status at kickoff

| | Count |
|---|---|
| Blockers opened **by** Step 15 | **0** — this kickoff performs no audit work |
| Carried-forward entries seeded below | **6** |
| — of which **High** | **1** (`HDN-BLK-001`) |
| — of which **Medium** | **4** |
| — of which class-level | **1** (`HDN-BLK-002`, four issues in one defect family) |
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
| **Members** | `ISS-2026-103`/`115` — `hris-overtime-timesheet.sql`, day-of-week — **CLOSED** at `cdbccc7` by pinning the fixture to the most recent weekday. `ISS-2026-077` — `hris-leave-permit-business-trip.sql`, wall-clock **and** day-of-week — `OPEN`. `ISS-2026-135` — `hris-shift-roster-scheduling.sql`, day-of-week — `OPEN`. `ISS-2026-154` — `hris-attendance.sql`, a ~1-hour real-UTC window after each day's 21:00 UTC (04:00 Asia/Jakarta) shift-day boundary — `OPEN` |
| **Reproduction** | Run the suite on the triggering day / in the triggering window. Each issue records its own exact trigger |
| **Kickoff observation** | All four executed and **passed** on Sunday 2026-08-23, ~11:15–11:45 UTC. **This is not proof the class is closed**: `ISS-2026-135`'s day-of-week dimension was genuinely in play and did not fire; `ISS-2026-154`'s time-of-day dimension was **not exercised at all** (~10 hours outside its window). Status: **`PARTIAL`** |
| **Disposition** | **`DEFERRED_TO_HDN-370`** |
| **Required of `HDN-370`** | Reuse the already-proven most-recent-weekday pinning pattern, then **prove day-independence rather than observe it** — drive each fixture's temporal inputs across all seven days and across the shift-day boundary window directly. Re-running the suite and getting green is not evidence |
| **Regression test** | The pinning itself is the regression guard; a day-parameterised test is the proof |
| **Rollback** | Test-fixture-only changes; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-077`, `ISS-2026-135`, `ISS-2026-154` (`OPEN`); `ISS-2026-103`/`115` (closed) |

**A regression baseline green only on some days of the week is not a release gate.**

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

## Reserved

`HDN-BLK-007` onward are unassigned. Every Step 15 finding takes the next free ID and the
full record format of the execution index §14. A finding missing any field is not
registered — and an unregistered finding is not a finding.
