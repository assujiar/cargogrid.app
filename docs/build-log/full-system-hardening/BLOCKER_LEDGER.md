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
| **Disposition** | **Corrected at `HDN-386` (Full-System Hardening Integrated Verification) reconciliation, ledger-consistency finding**: this row's own `DEFERRED_TO_HDN-378` disposition text and `OPEN` `KNOWN_ISSUES` cross-reference were never updated after `HDN-378`'s own Tier C review actually wired the fix and then found and disclosed `HDN-BLK-023`'s own independent bypass of it — `KNOWN_ISSUES.md`'s own `ISS-2026-150` row was corrected from `RESOLVED` to **`PARTIALLY RESOLVED`** at that same Tier C, but this ledger entry's own text was left stale, undetected by any Tier C ledger-consistency sweep since. Corrected disposition: **`PARTIALLY RESOLVED`** — route-handler IP extraction and threading was genuinely built and wired into the 4 named highest-risk functions (`app.decide_ai_output_approval`, `app.activate_enterprise_idp_connection`, `app.approve_mfa_exception`, `app.create_integration_connection`), with a real negative-path regression proving rejection through the actual call path — but the fix's own effectiveness is undercut for `app.activate_enterprise_idp_connection` specifically by `HDN-BLK-023`'s own independent bypass (the shared `app.set_integration_connection_status` primitive it delegates to remains independently callable with none of the same protections). Not a full closure until `HDN-BLK-023` itself closes |
| **Required of `HDN-378`** | (a) build route-handler-level client-IP extraction and threading; (b) wire `assert_ip_allowed` into the bounded set of highest-risk SEC/IAM/INTHUB mutations that `ISS-2026-151`'s own ruling already names; (c) decide explicitly what service-role/background-job callers with no client IP at all should do (likely exempt — IP restriction is inherently an interactive-session control). **A cosmetic partial wire-up is forbidden**: adding an unenforced parameter that nothing ever populates would look fixed without being fixed. **Done at `HDN-378`** — see `HDN-BLK-023` for the residual gap its own Tier C found |
| **Regression test** | Required with the fix: a negative-path test proving a disallowed IP is actually rejected through the real call path, not only in a direct-call unit test. **Done at `HDN-378`** |
| **Rollback** | Additive migration + additive route-layer parameter; `git revert` the checkpoint's commit |
| **`KNOWN_ISSUES`** | `ISS-2026-150` (`PARTIALLY RESOLVED` at `HDN-378` Tier C, High) |

> **This was the one item Step 15 could not defer.** It was accepted once, explicitly, on
> the stated condition that Step 15 would remedy it. `HDN-378` built the real fix rather
> than deferring it again — but its own Tier C review found the fix incompletely closes
> the gap for one of the 4 named functions, tracked now at `HDN-BLK-023`, owner `HDN-386`.

*Amended at `HDN-388` (Documentation Handoff), ledger reconciliation, zero code. `HDN-BLK-023`
— the dependency this entry's own Disposition field named as the one thing standing between
`PARTIALLY RESOLVED` and full closure — was resolved at `HDN-387` (see that entry's own
`Amended at HDN-387` note). This entry's own text was never revisited after that closure
landed, left reading `PARTIALLY RESOLVED` with a "not a full closure until `HDN-BLK-023`
itself closes" caveat that no longer held. **Corrected disposition: `RESOLVED`.** No new code;
the underlying fix (route-handler IP extraction/threading into the 4 named functions,
`HDN-378`) and the dependency's own closure (`HDN-387`) are both already-landed, already-
verified work — this amendment only brings the ledger's own text into agreement with a state
that has existed since `HDN-387` closed. `KNOWN_ISSUES.md`'s `ISS-2026-150` corrected in the
same pass from `PARTIALLY RESOLVED` to `RESOLVED`.*

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
| **Blast radius** | **43 real call sites across 16 files** (precise-pattern re-measurement at `HDN-378`, superseding the earlier "40+" estimate — 4 negative-path/unaffected, 39 requiring the gate, collapsible to 27 distinct step-up sequences since the check does not consume a verified challenge on use) |
| **Disposition** | ~~`DEFERRED_TO_HDN-378`~~ **Corrected at `HDN-388`: `HDN-378` did not stay silent — it satisfied this entry's own "rule on it explicitly" requirement, just never got its own ledger amendment.** `HDN-378` re-derived the exact blast radius with a precise-pattern grep (not the looser substring estimate), confirmed the only real production caller (`app/(tenant)/[tenantSlug]/integrations/actions.ts`) is an interactive Server Action with no exempt-caller design question, and made a reasoned, written ruling to defer again: its own bounded-repair budget that checkpoint was consumed by `ISS-2026-150`'s IP-restriction closure, and stacking a 16-file/27-sequence fixture adaptation on top would repeat the exact "rushed, under-tested wide edit" risk `CG-S14-IAE-039` had already declined once. Still `OPEN`, Medium, owner unchanged in shape, now precise: 1 additive migration line plus 27 step-up sequences across the same 16 named files (`integration-hub.sql` first, `batch4-tier-c-review-fixes.sql`/`enterprise-iam-sso-scim.sql` last per `HDN-378`'s own risk-ordering) — full detail `KNOWN_ISSUES.md`'s `ISS-2026-151` **`RESOLVED` 2026-08-31 — by a different and stronger route than this entry anticipated.** It specified "1 additive migration line plus 27 step-up sequence adaptations" wiring step-up into `app.create_integration_connection` itself. `20260830110000` (`ISS-2026-236`) instead enforced step-up at `app.evaluate_permission`, the single chokepoint every authority check already passes through, which covers this function and 60 others at once rather than one at a time. Verified live on `awdlicmwzdxquopwtcfd`: `app.create_integration_connection` routes through `evaluate_permission` (`true`), `app.is_high_risk_action(null,'INTHUB','Configure')` returns `true`, and `evaluate_permission`'s body carries the `mfa_step_up_required` branch (`true`). Proven behaviourally, not only structurally: `scripts/db-tests/integration-hub.sql` §`ISS-2026-151` asserts the call succeeds with MFA off and raises `mfa_step_up_required` once the tenant turns tenant-wide MFA on. Suite green. |
| **Required of `HDN-378`** | Wire it with real step-up fixtures and a negative-path regression proving genuine enforcement, **or** rule on it explicitly with a compensating control. Silence is not an option. **Done — ruled, not silent; see Disposition** |
| **Rollback** | Additive migration; `git revert` |
| **`KNOWN_ISSUES`** | `ISS-2026-151` (`OPEN`, Medium, re-scoped precisely at `HDN-378`) |

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
| **Disposition** | ~~`DEFERRED_TO_HDN-378`~~ **`PARTIALLY RESOLVED` at `HDN-378`, corrected at `HDN-388`.** `pg_trgm`/`btree_gist` were relocated out of `public` into a new `extensions` schema (`20260815200000_harden_relocate_pg_trgm_btree_gist_out_of_public.sql`, 2 of the item's own 8 named advisories). `postgis` was live-verified genuinely non-relocatable — `ALTER EXTENSION postgis SET SCHEMA` fails outright on a hosted project; the only real path (`DROP EXTENSION postgis CASCADE` + recreate) would destroy 15 live `geography`-typed columns, exceeding what a bounded repair should risk — registered `ISS-2026-234` (Medium, `OPEN`, owner a dedicated future task). This ledger entry's own text was left reading `DEFERRED_TO_HDN-378` and "not yet registered" after `HDN-378` closed `VERIFIED`, undetected by any Tier C ledger-consistency sweep since — the identical stale-disposition-text shape as `HDN-BLK-001`, corrected in the same `HDN-388` pass |
| **Hard constraint** | **Never fold this into another edit.** It gets its own migration, its own review, and its own gate run. Mixing it with any other change makes a failure impossible to attribute |
| **Known limit** | `spatial_ref_sys` **cannot** have RLS enabled — it belongs to the PostGIS extension and `postgres` is not superuser on a hosted project. That sub-item is permanently a disclosed residual, not a fixable one |
| **Rollback** | Additive migration; `git revert`. The move is reversible but expensive — plan it once |
| **`KNOWN_ISSUES`** | `ISS-2026-234` (`OPEN`, Medium, postgis non-relocatability, owner a dedicated future task) |

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
| **Severity** | ~~Medium~~ **Low** — corrected at `HDN-386` reconciliation to match the paired `ISS-2026-239` row, which has read `Low` since it was written; this ledger entry's own severity field was never brought into sync |
| **Owning lane** | **`HDN-379`** (the finding); **not a valid acceptance authority for its own finding — see Disposition correction below** |
| **Assessment** | **A design question, not a defect.** The companion 982 `unused_index` advisories are pure noise — the database has served no queries — and the same absence of real traffic is exactly why the 892 cannot be resolved by inspection |
| **Disposition** | **`ACCEPTED_EXCEPTION`, re-ruled at `HDN-387` under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test.** (1) Severity: `Low` — below the High-or-below ceiling, Critical is never eligible and this is not Critical. (2) Explicit written ruling: this entry's own already-existing text from `HDN-379` — "a design question, not a defect," the companion 982 `unused_index` advisories are pure noise because the project has served no real traffic, and the same absence of traffic is exactly why the 892 cannot be resolved by inspection (no query pattern exists yet to index against) — is sound and is not being re-litigated, only re-ratified by the correct authority. (3) Named owner: `ISS-2026-239`'s own owner, "a dedicated future task" triggered the first time this project serves genuine production query traffic (an index built against zero real access patterns is a blind guess, not a defense-in-depth measure — the `hard constraint` below already says this). (4) Registered in both ledgers: this entry (`BLOCKER_LEDGER.md`) and `ISS-2026-239` (`KNOWN_ISSUES.md`) both carry this disposition as of this ruling. (5) Accepted only at `HDN-387`/`HDN-389`, never the lane that found it: this ruling is made at `HDN-387` — a different checkpoint than `HDN-379`, which only found and categorized the finding and never had acceptance authority over its own work. All 5 conditions now satisfied; the procedural defect `HDN-386` corrected (self-acceptance by the finding lane) is fully closed |
| **Hard constraint** | **Neither drop them nor blindly index.** Blanket-indexing 892 FKs adds real write cost and storage for unmeasured benefit; dismissing them hides a genuine future scaling risk. Re-open (not re-accept from scratch) once the project serves real traffic and `pg_stat_user_tables`/slow-query evidence identifies which of the 892 are actually load-bearing |
| **`KNOWN_ISSUES`** | `ISS-2026-239` (`ACCEPTED_EXCEPTION`, Low, owner: re-open once real production query traffic exists) |

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
| **Blast radius — the real damage** | Because `Test` fails first, these six push-triggered steps report `skipped` and **have never run in CI on a push**: suppression-governance check; documentation checks; **secret scan**; **dependency vulnerability audit (fails on critical/high)**; data-classification registry check; threat-model register check — **plus 3 more on a `pull_request`-triggered run specifically** (branch-name/commit-message/protected-path checks, `ci.yml:116-126`), 9 total skipped steps on a PR, corrected at `HDN-386`'s own Tier C review from the first-round-of-that-checkpoint's own undercount of 6. Two of the always-skipped six are security controls. `ISS-2026-007`'s own recorded lesson was that a silently-broken audit gate hid 20 real advisories, 11 high, for a whole phase — this is the same failure shape one level up. **Confirmed and sharpened at `HDN-386`**: `.github/workflows/ci.yml`'s `security:audit` step (added 2026-08-05, `cbe57cb`, before Step 15 began) has genuinely **never executed on any CI run** as a direct consequence of this same cascade — `HDN-378`'s own security-hardening work ran `security:audit`/`security:check` locally only, and this is real, disclosed `Executed`-locally/`Tracked-gap`-in-CI evidence, not silently waved through as "not applicable." The same disposition applies to `HDN-380`/`381`'s own axe-core and mobile/tablet/iPhone Playwright coverage — real and green locally (34/34 across 4 Playwright projects, re-confirmed fresh at `HDN-386`), never independently confirmed against an actual CI run; this is a distinct, separately-tracked root cause from `HDN-BLK-009`, not the same defect (corrected at `HDN-386`'s own Tier C review, which found the first round's own narrative wrongly conflated the two). **`HDN-386`'s own Tier C review found and fixed a second, more severe, previously-unregistered defect on the same surface**: `pnpm-lock.yaml` was out of sync with `package.json` since `HDN-380`'s own commit (`eslint-plugin-jsx-a11y` added as a direct devDependency but never regenerated into the lockfile), meaning `pnpm install --frozen-lockfile` — the exact install mode CI uses — has failed outright on every job (`quality`, `e2e`, `db`) since that commit, a broader outage than the 6/9-step governance cascade this entry otherwise describes (those steps at least got as far as running `Test`; this failed before `Test` could even start). Fixed at `HDN-386` (lockfile regenerated, `--frozen-lockfile` re-verified to pass) |
| **Why it went unnoticed** | Every phase's gate evidence in this repository was produced by **local** runs, where the test passes on a feature branch that genuinely is ahead of `origin/main`. The local and CI outcomes are inverses of each other, so a green local run is not evidence about CI |
| **Disposition** | **Partially `RESOLVED` at `HDN-387`.** The false "commits ahead of origin/main" assertion is now conditioned on the current branch actually being an `agent/*`/`claude/*` candidate branch — the only branches `checkWorktreeCollision()` itself ever considers (see `listCandidateBranches()`) — so a CI checkout of `main` (structurally never a candidate, and so structurally never reportable as "diverged") now `t.skip()`s that one assertion instead of failing, while a genuine agent/claude session branch still exercises the real assertion exactly as before (`scripts/git/check-worktree-collision.test.ts`). This closes the `ISS-2026-002` control's own false-positive on `main` without weakening it for the branches it actually protects — **not a deletion or a blanket skip of the test**. The remaining governance-cascade blast radius (6-9 skipped steps on the pre-`HDN-387` broken state) should now clear on the next CI run against this fix; not independently re-verified against a live CI run this checkpoint (no CI access from this session — see `HDN-BLK-009`'s own identical disclosed limitation) |
| **Not to do** | Do not delete or skip the test to turn CI green. That would remove the `ISS-2026-002` control this repository added after real content corruption (`ERR-2026-001..003`) — **the fix here narrows the false-positive precondition, it does not weaken the collision check itself** |
| **`KNOWN_ISSUES`** | `ISS-2026-158` (mark `RESOLVED` pending live CI confirmation) |

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
| **Disposition** | ~~**`DEFERRED_TO_HDN-387`**~~ **`RESOLVED` 2026-08-31.** Premise no longer holds. Its own linked entry `ISS-2026-159` is `RESOLVED`, and the `db` CI job it says cannot read its own concurrency-test helper files is **green on `main`** — runs 170 and 171 (`54ae9ef`, `c3fff5c`) both `success`, and `pnpm run db:test` completes locally with 390 migrations and 236 runner files, `ALL PASSED`, including the concurrency blocks. Verified by reading the live CI conclusions and re-running the suite, not from the linked entry's status alone. |
| **Note** | The affected assertions are genuine, valuable concurrency proofs (real two-process row-lock races). They must keep working locally; the fix is about transporting the loser's output without `pg_read_file`, not about weakening the proof |
| **`KNOWN_ISSUES`** | `ISS-2026-159` |

*Amended at `HDN-387`, same checkpoint. Reviewed, not fixed — this entry's own charter-explicit owner is honored by this note, not by silence. The fix (redesigning how the losing session's own output is transported out of a CI-only, separate service-container topology, across 6 real concurrency-proof db-test files, without weakening any of the row-lock races themselves) is a genuine CI-infrastructure design decision — a different IPC/transport mechanism (e.g. writing to a table both containers can query, rather than a shared filesystem `pg_read_file()` call) touching 6 files' own proven concurrency mechanics, carrying real regression risk to files this checkpoint has no CI environment to validate against (no CI access from this session, the same disclosed limitation `HDN-BLK-007`'s own fix carries). Rushing a mechanical-looking fix here risks silently weakening a real two-process row-lock proof, the exact failure mode this entry's own "Note" field explicitly warns against. **Remains `DEFERRED_TO_HDN-387`'s own charter, unaddressed by code this checkpoint** — owner unchanged, a dedicated future task with local access to a CI-shaped environment (or an explicit `HDN-389` Closure Verification decision to accept it as a disclosed exception under §8.2, since it is Medium severity and eligible).*

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

*Amended at `HDN-387`, same checkpoint. **`RESOLVED`** — the remaining 3 non-Finance functions
(`app.prepare_job_order_handoff`, `app.prepare_wms_inbound_from_shipment`, `app.link_auth_
identity`) now carry the identical "design note 9(a)" nested begin/exception unique_violation
recovery shape, each at its own true effective (latest, post-redefinition) definition —
re-verified by direct source read against every later `create or replace` before writing the fix,
after a first draft of this same migration's own Part 5 (a different function family, see
`HDN-BLK-027` below) was caught silently reverting later hardening by working from a stale
original-creation body instead. `ISS-2026-163` (`app.prepare_job_order`'s own defective handler,
missing `if found`/`raise;`) fixed in the same migration, same session, per its own original
owner note. **Live-forced, not merely code-reviewed**: a genuine two-process race against
`app.link_auth_identity` (uncommitted-insert-blocking technique, `HDN-371.md` §6.2, mirrored
exactly) on a fresh disposable probe database confirmed the second session now blocks on the
first's uncommitted insert and, on the first's commit, correctly re-selects and returns the
winner's own row instead of a raw `unique_violation` — full transcript `HDN-387.md` §11.1. Per
that same section's own "scope of the claim" note (mirroring `HDN-371.md`'s own precedent
exactly), the other 2 siblings sharing the identical mechanism were not independently
live-raced, only code-verified — the mechanism itself, not each call site, is what the live
proof establishes. `ISS-2026-163`'s own distinct defect (a silent all-NULL return on an
UNRELATED unique_violation, not a missing handler) was separately live-forced by manually
resetting `app.job_order_number_counters` to reproduce the exact "second, unrelated constraint"
collision the finding describes — confirmed the fixed handler now correctly re-raises instead of
fabricating a row — full transcript `HDN-387.md` §11.2. `supabase/migrations/
20260819000000_harden_release_blocker_triage_remediation.sql` Part 6.*

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

*Amended at `HDN-387`, same checkpoint. **`RESOLVED`.** Every named action/route now confirms the
client-supplied record's own tenant ownership at the app layer, before the mutating RPC is ever
reached, mirroring the already-established `account.tenantId !== access.tenant.id` idiom
(`app/(tenant)/[tenantSlug]/commercial/accounts/[accountId]/page.tsx:37`). `app/(tenant)/
[tenantSlug]/admin/api-keys/actions.ts`'s 7 named actions (`rotateApiKeyAction`,
`revokeApiKeyAction`, `rotateWebhookSecretAction`, `disableWebhookEndpointAction`,
`reenableWebhookEndpointAction`, `replayWebhookDeliveryAction`, `rotateN8nConnectorAction`) each
list the caller's own tenant-scoped records via the already-`authenticated`-callable `list_*_for_
tenant` RPC and reject a client-supplied id absent from that list before the service-role
mutation runs. `app/api/v1/customer/bookings/[bookingRequestId]/submit/route.ts` calls the
already tenant-scoped, anti-enumerating `app.get_customer_booking_request` first, mapping a
cross-tenant/missing id to a 404 exactly like its own sibling tracking route already does.
`typecheck` clean; `tests/api/v1/customer-bookings-submit.test.ts` (6/6, including a new
cross-tenant-rejection test) and the full repo unit-test suite (5444/5444) pass. **One sibling
action, `sendTestWebhookDeliveryAction`, shared the identical unchecked shape but was outside
this finding's own named list of 7 — first flagged, not fixed, at the first round; caught by
this checkpoint's own Tier C schema-wide completeness sweep lens as a real gap deserving more
than a dangling mention, and closed in the Tier C fix pass with the identical mechanical
pattern (a `listWebhookEndpointsForTenant` ownership check before the mutating call), since it
is the same file, the same already-proven idiom, and genuinely bounded — not a separate,
larger finding after all.** `replayWebhookDeliveryAction`'s own
tenant-ownership check reads via `list_webhook_deliveries_for_tenant` at its schema-max limit
(200, no unbounded per-id RPC exists) — an accepted edge case, disclosed, not a design gap this
checkpoint introduced. `app/(tenant)/[tenantSlug]/admin/api-keys/actions.ts`, `app/api/v1/
customer/bookings/[bookingRequestId]/submit/route.ts`, `tests/api/v1/customer-bookings-submit.
test.ts` — no migration, TS-only per this finding's own original scope note.*

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

*Amended at `HDN-387`, same checkpoint. Reviewed, not fixed. The required work — a per-call-site audit of ~14 functions (`has_active_tenant_membership`, `can_access_record`, `is_supreme_admin`, `actor_holds_customer_user_layer`, `has_active_support_grant`, `claim_case_record_scope_ok`, `label_subject_record_scope_ok`, `wms_pick_record_scope_ok`, `is_ticket_queue_member`, `current_support_session`, `pipeline_scope_org_unit_ids`, `evaluate_dispatch_readiness`, `customer_warehouse_eligibility_active`, `resolve_locale_context`) to determine, function by function, whether each genuinely-third-party call site needs a different, narrower check than an unconditional `assert_actor_is_session_identity` (which `HDN-373`'s own investigation already confirmed would break every one of them if applied blindly) — is exactly the kind of open-ended, multi-function investigation-plus-design work this checkpoint's own charter reserves for a dedicated lane, not a bounded Tier C fix pass alongside 7 unrelated, already-proven-pattern repairs. **Remains `OPEN`, owner unchanged `HDN-387`'s own future allocation** — not silently dropped, explicitly re-affirmed as still requiring its own dedicated investigation before any fix.*

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
| **Disposition** | **Registered, not fixed.** The narrower, companion period-lock bypass on this SAME function was fixed in this same checkpoint's own Tier C fix pass (`20260811200000_harden_financial_integrity_tierc_fixes.sql`) — this finding (no reversing journal at all) needs a design decision this bounded-repair checkpoint cannot make unilaterally. **`HDN-386` reviewed this entry at its own Tier C review and formally hands it to `HDN-387`, not attempted** — composing a correct reversing GL journal (account mapping, automatic-vs-governed-step design) is exactly the kind of genuine design decision this checkpoint's charter reserves for bounded-repair-sized fixes only, the same judgment applied to `HDN-BLK-023`/`024` |
| **Required of `HDN-386`** | Decide and implement (or explicitly accept as residual risk with a documented manual-correction procedure): whether `app.request_finance_settlement_reversal` should automatically post a reversing GL journal, and if so, its exact account mapping and idempotency/concurrency shape mirroring this codebase's own established correction-journal patterns. **Handed to `HDN-387` with this exact scope, not decided here** |
| **Regression test** | Required with the eventual fix — a live-forced proof that a reversed settlement's own GL journal is corrected, not merely the AP subledger |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-199` (`ACCEPTED_EXCEPTION` at `HDN-389`, High) |

*Amended at `HDN-388`'s own Tier C (schema-wide completeness sweep), disclosure only, zero code.
`HDN-387` closed `VERIFIED` without adding its own disposition note to this entry, despite being
its named recipient — unlike `HDN-BLK-008`/`014`/`039`, which each received an explicit
"reviewed, not fixed" or ruling note at `HDN-387` Tier C for the identical no-disposition-update
shape. Still `OPEN`, High, requiring a genuine design decision (GL account mapping, automatic-vs-
governed-step shape) this documentation-handoff checkpoint has no standing to make. Folded into
the aggregate 5-item punch list `docs/runtime/RELEASE_READINESS_MATRIX.md` §2.1 hands to
`HDN-389` as the only remaining §8.2 ruling authority.*

*Ruled at `HDN-389`, closure verification, same checkpoint. **`ACCEPTED_EXCEPTION`**, formally
accepted under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test — see `HDN-BLK-040` for the
complete ruling covering this entry and its 4 siblings. Real owner: `Step 16`.*

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
| **Disposition** | **Registered, not fixed.** A narrower, genuinely bounded-repair-sized half of this same area — the evidence ledger's own mutability (`ISS-2026-201`/formerly this same investigation) — was fixed in this checkpoint's own migration. **`HDN-386` reviewed this entry at its own Tier C review and formally hands it to `HDN-387`, not attempted** — genuine chaining (canonical ordering across 5 relation types, a real `prev_hash` column, backfill of every existing row, a new anomaly-detector type) is design work, not a mechanical, already-proven-pattern repair |
| **Required of `HDN-386`** | Decide and implement (or explicitly accept as residual risk with a documented reconciliation procedure): a real per-relation-type chain ordering, a `prev_hash` column, backfill, and a hash-mismatch anomaly type in `detect_transaction_lineage_anomalies`. **Handed to `HDN-387` with this exact scope, not decided here** |
| **Regression test** | Required with the eventual fix — a live-forced proof that a tampered source row is actually detected and surfaced, not merely detectable by hand |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-200` (`ACCEPTED_EXCEPTION` at `HDN-389`, High) |

*Amended at `HDN-388`'s own Tier C (schema-wide completeness sweep), disclosure only, zero code.
`HDN-387` closed `VERIFIED` without adding its own disposition note to this entry, despite being
its named recipient — the identical gap as `HDN-BLK-016`. Still `OPEN`, High, requiring a genuine
design decision (canonical ordering across 5 relation types, a real `prev_hash` column, backfill,
a new anomaly-detector type). Folded into the aggregate 5-item punch list
`docs/runtime/RELEASE_READINESS_MATRIX.md` §2.1 hands to `HDN-389`.*

*Ruled at `HDN-389`, closure verification, same checkpoint. **`ACCEPTED_EXCEPTION`**, formally
accepted under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test — see `HDN-BLK-040` for the
complete ruling covering this entry and its 4 siblings. Real owner: `Step 16`.*

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
| **Disposition** | **Registered, not fixed.** `ISS-2026-201`'s own single-table fix (this checkpoint's first round) is not extended to any of these ~70 tables. **`HDN-386` reviewed this entry at its own Tier C review and formally hands it to `HDN-387`, not attempted at its own ~70-table scope** — `HDN-386` DID fix the narrowly-scoped legal-hold half of the two specific tables (`app.audit_logs`/`app.tenants`) this entry itself names as most severe (`HDN-BLK-020`/`021`, closed this checkpoint, mirroring `HDN-377`'s own already-proven `app.files` bridge pattern) — but the full append-only-guard rollout across ~70 tables remains exactly as large and design-heavy as this entry's own text already states, genuinely outside one checkpoint's bounded-repair budget |
| **Required of `HDN-386`** | Audit and fix each table individually, prioritized by centrality and reachability — `app.audit_logs` first, given every other detective control's own dependency on it, followed by the ranked remainder; for each, confirm no legitimate non-Supreme-Admin UPDATE/DELETE call path exists before adding the guard, exactly as CPL-325/`ISS-2026-201` already did one table at a time. **`app.audit_logs`'s own legal-hold half done at `HDN-386`** (`HDN-BLK-020`); the append-only-guard half for `app.audit_logs` and the remaining ~69 tables handed to `HDN-387` with this exact scope |
| **Regression test** | Required with each table's own fix — a live-forced proof mirroring `ISS-2026-201`'s own regression blocks (no-actor-context and ordinary-staff denial, genuine Supreme Admin override with audit capture) |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-205` (`ACCEPTED_EXCEPTION` at `HDN-389`, High) |

*Amended at `HDN-388`'s own Tier C (schema-wide completeness sweep), disclosure only, zero code.
`HDN-387` closed `VERIFIED` without adding its own disposition note to this entry, despite being
its named recipient — the identical gap as `HDN-BLK-016`/`017`. Still `OPEN`, High, requiring a
genuine table-by-table audit-and-fix across ~69 remaining tables. Folded into the aggregate
5-item punch list `docs/runtime/RELEASE_READINESS_MATRIX.md` §2.1 hands to `HDN-389`.*

*Ruled at `HDN-389`, closure verification, same checkpoint. **`ACCEPTED_EXCEPTION`**, formally
accepted under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test — see `HDN-BLK-040` for the
complete ruling covering this entry and its 4 siblings. Real owner: `Step 16`.*

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
| **Disposition** | **Registered, not fixed.** `HDN-377`'s own Finding C (`ISS-2026-218`) added a schema-level backstop for `app.files` itself; this entry is the narrower, evidence-log-specific gap that survives even after that fix. **`HDN-386` reviewed this entry at its own Tier C review and formally hands it to `HDN-387`, not attempted** — bundled with `HDN-BLK-018`'s own much larger append-only-guard rollout by this entry's own original design, and new hold-aware cascade logic (a shape that does not exist anywhere yet in this codebase) is design work, not a mechanical repair |
| **Required of `HDN-386`** | When rolling out `HDN-BLK-018`'s own append-only guard to `app.file_access_logs`, also add hold-aware cascade logic (consulting the referenced file's own `legal_hold`/`app._is_under_legal_hold` state) rather than a bare append-only guard alone. **Handed to `HDN-387` with this exact scope, bundled with `HDN-BLK-018`, not decided here** |
| **Regression test** | Required with the fix — mirroring `HDN-377`'s own regression shape (a legally-held file's access-log row survives a direct mutation attempt; an un-held file's does not gain new restrictions) |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-222` (`OPEN`, High) |

*Amended at `HDN-387`, same checkpoint. **`RESOLVED` for the worst part of this finding (the
legal-hold-cascade gap) — `HDN-BLK-018`'s own much larger ~70-table append-only-guard rollout
remains separately `OPEN`, unchanged owner, per this entry's own original bundling note.**
`supabase/migrations/20260819000000_harden_release_blocker_triage_remediation.sql` Part 3 adds
`app.protect_file_access_logs_legal_hold_from_mutation()`, a `BEFORE UPDATE OR DELETE` trigger
(never `DELETE`-only — `HDN-386`'s own Tier C already proved a `DELETE`-only guard is a real,
live-forced UPDATE-path bypass for the sibling `app.audit_logs` fix, the same discipline is
applied here from the start) joining `OLD.file_id → app.files` to read the parent file's own
hold state (`app.files.legal_hold` OR the bridged generic `app._is_under_legal_hold`, mirroring
`app.protect_audit_logs_legal_hold_from_deletion` exactly, including its lazy-`auth.uid()`
discipline — computed only after confirming the row is actually held, never unconditionally).
Deliberately narrow, matching this entry's own original scope: only rows whose parent file is
under an active hold are protected; ordinary access-log rows remain `service_role`-mutable,
exactly as `app.audit_logs` itself remains for non-held rows. Live-forced, not merely
code-reviewed: a real file uploaded, put under legal hold, and a real `app.file_access_logs` row
created via `app.authorize_file_access` — a raw `DELETE` and a raw `UPDATE` both correctly
blocked (`file_access_log_legal_hold_blocks_deletion`) with the row unchanged after both attempts;
a Supreme Admin's RPD-022 absolute-CRUD override still succeeds and is audited (a real
`app.audit_logs` row, `action=update_legally_held_file_access_log`) — full transcript `HDN-387.md`
§11.3. Regression test: `scripts/db-tests/release-blocker-triage-remediation.sql`.*

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
| **Disposition** | **`FIXED` at `HDN-386`** (`supabase/migrations/20260818000000_harden_integrated_verification_legal_hold_bridge.sql`) — a genuinely BOUNDED repair scoped only to the two specific reproducible bypasses (`HDN-BLK-020`/`021`), NOT `HDN-BLK-018`'s own separate, much larger systemic append-only-guard rollout (~90+ tables), which remains registered, unchanged, owner `HDN-387`. `app._is_under_legal_hold()` now also bridges `app.audit_logs`/`app.tenants` (mirroring the existing `app.files` bridge branch exactly); a new `app.protect_audit_logs_legal_hold_from_deletion` `BEFORE DELETE` trigger blocks physical deletion of a held row (native or generic hold) by any non-Supreme-Admin caller, including a raw `service_role` DELETE with no session-bound actor — the exact bypass this finding live-forced. A genuine Supreme Admin RPC caller retains RPD-022's disclosed absolute-CRUD override, but the override is now honestly and distinctly audited (`action='delete_legally_held_audit_log'`, `actor_label='supreme_admin_absolute_crud'`) rather than silent |
| **Required of `HDN-386`** | When rolling out `HDN-BLK-018`'s own append-only guard to `app.audit_logs`, also enforce `legal_hold` (native flag, and bridge into `app._is_under_legal_hold()` mirroring `HDN-377`'s own `app.files` fix) in the same pass. **Done for the legal-hold half only** — `HDN-BLK-018`'s own append-only-guard rollout is deliberately not bundled into this bounded repair; see Disposition |
| **Regression test** | Required with the fix — a legally-held audit-log row must survive both `supreme_admin_mutate_audit_log`'s own write path attempting to alter protected fields and `supreme_admin_delete_audit_log`, mirroring `HDN-377`'s own `ISS-2026-226`/`227` regression shape. **Done**: `scripts/db-tests/audit-trail.sql`, 3 directions (native-hold raw-DELETE block, generic-hold raw-DELETE block, Supreme Admin override honestly audited) |
| **Rollback** | `git revert` this checkpoint's commit; the migration is a `create or replace function` (persists existing grants) plus one genuinely new trigger function and trigger, additive and reversible |
| **`KNOWN_ISSUES`** | `ISS-2026-229` (`RESOLVED` at `HDN-386`, was Critical) |

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
| **Disposition** | **`FIXED` at `HDN-386`** (`supabase/migrations/20260818000000_harden_integrated_verification_legal_hold_bridge.sql`), bundled with `HDN-BLK-020`'s own bounded repair. `app._is_under_legal_hold()` now bridges `app.tenants` (mirroring the `app.files` bridge exactly), AND — the actual live-forced reproduction — `app.enforce_tenant_status_transition` now checks BOTH the native flag and the generic bridge before blocking termination, closing the direction that mattered operationally (a generic-only hold previously did not block termination at all) |
| **Required of `HDN-386`** | Bridge `app._is_under_legal_hold()` to also check `app.tenants.legal_hold` (mirroring `HDN-377`'s own `app.files` bridge), and decide whether a real RPC should set the native flag at all going forward or whether the generic mechanism alone should govern tenants. **Done for the bridge/enforcement half.** The second ask — whether a dedicated RPC should exist to set the native flag — is a genuine product/API-surface decision, left explicitly open and registered for `HDN-387`, not guessed at here |
| **Regression test** | Required with the fix. **Done**: `scripts/db-tests/tenant-lifecycle.sql` — a purely generic (no native flag) hold on scope `app.tenants` now correctly blocks `app.transition_tenant_status(..., 'terminated', ...)`, and succeeds once released |
| **Rollback** | `git revert` this checkpoint's commit; both function replacements persist existing grants, additive and reversible |
| **`KNOWN_ISSUES`** | `ISS-2026-230` (`RESOLVED` at `HDN-386`, was High) |

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
| **`KNOWN_ISSUES`** | `ISS-2026-225` (`PARTIALLY RESOLVED` at `HDN-387`, remainder `ACCEPTED_EXCEPTION` at `HDN-389`, High, corrected from Low) |

*Amended at `HDN-387`, same checkpoint. **`PARTIALLY_RESOLVED`.** The 2 tables this entry's own
first round live-forced as genuinely exploitable (`app.vendor_kpi_scorecards`, `app.position_
grades`) are now closed, exactly matching the already-proven `app.check_procurement_authority`
(`HDN-377`, `ISS-2026-220`) fix pattern: a new `app.check_hris_authority` (a direct structural
copy, one string changed) plus an added authority predicate on each table's own pre-existing
RLS `SELECT` policy. **Corrects a real bug caught by a live db-tests re-run**: the first draft of
this fix assumed the pre-existing policy was named `*_tenant_read` and added a SECOND,
differently-named policy alongside it — since Postgres OR-combines multiple permissive policies
for the same command/role, the old, unrestricted policy (the real name: `*_select_scoped`, not
`*_tenant_read`) remained fully live, and a zero-HRS-role probe actor still read the fixture row
after the "fix" (`count=1`, expected `0`). Corrected to drop-and-replace the SAME, correctly-named
`position_grades_select_scoped`/`vendor_kpi_scorecards_select_scoped` policy in place, mirroring
the `HDN-377` precedent's own exact naming. Re-verified live after the correction: a zero-HRS-role
actor sees 0 rows, an HRS:View holder sees the real row, at the raw-RLS level (role-switched, not
merely claims-set — RLS is bypassed for a superuser regardless of `request.jwt.claims`, a second
live-caught bug in this same regression test's own first draft, also corrected). **The remaining
~33-table sweep across both domains stays registered, unchanged owner `HDN-378`, not attempted
here** — each table needs its own individual action-code verification against its own RPC layer
even though the fix pattern itself is identical; the 2 tables closed here are a first increment,
not the full closure this entry's own scope names. `supabase/migrations/
20260819000000_harden_release_blocker_triage_remediation.sql` Part 4; regression:
`scripts/db-tests/release-blocker-triage-remediation.sql`.*

*Tier C addendum, `HDN-387`. The attack-surface adversarial testing lens live-forced a real gap
adjacent to (not a regression of) the RLS fix above: the RLS policy itself HELD under every
attack tried — a `customer_user`-layer actor sees 0 rows via raw `SELECT`, a revoked role sees 0
rows, no direct write grant exists for `authenticated` on either table. But an actor who
simultaneously holds BOTH a `customer_user`-layer `principal_membership` AND a legitimately
assigned staff role (nothing in `app.assign_role`/`app.grant_principal_membership` prevents one
identity from holding both, an unguarded, independent axis) can still read the identical row
through the pre-existing `app.list_position_grades`/`app.list_vendor_kpi_scorecards` RPCs, and
the same unguarded shape was found by code review in `app.get_procurement_dashboard_vendor_risk_
summary`/`app.list_procurement_vendor_risk_dashboard_rows` — none of these RPCs check
`actor_holds_customer_user_layer` before their own `evaluate_permission('HRS'/'PRC', 'View')`
gate, unlike the newly-hardened RLS policies which do. This directly undercuts the RLS fix's own
borrowed rationale (from the `ATW-023` precedent this pattern's comment cites: "the RPC layer
already enforces identical... scope") for these specific 2 tables' own RPC surface — that
assumption does not actually hold here. **Not a regression this checkpoint introduced** — the
gap is pre-existing and was never claimed closed by any prior checkpoint — but it is a real,
live-demonstrated way the stated security goal is not fully achieved for these 2 tables, and per
this session's own "no silent caps" discipline it must be disclosed, not left implicit. Folded
into `ISS-2026-225`'s own still-`OPEN` `~33-table` remainder rather than minted as a wholly
separate finding, since it is the same domain, the same RLS-vs-RPC-authority-drift shape, and
plausibly recurs across some of that same ~33-table population — a genuine design decision
(should the fix be per-RPC `actor_holds_customer_user_layer` checks, or should the dual-layer
membership state itself be prevented at grant time?) exceeding a bounded Tier C fix pass,
unchanged owner `HDN-378`.*

*Ruled at `HDN-389`, closure verification. **The ~33-table remainder (plus the disclosed RPC-
layer addendum) `ACCEPTED_EXCEPTION`**, formally accepted under `00_EXECUTION_INDEX.md` §8.2's
full 5-condition test — see `HDN-BLK-040` for the complete ruling covering this entry and its
4 siblings. Real owner: `Step 16`. The 2 already-fixed tables and their own RLS hardening are
unaffected by this ruling — only the still-open remainder is accepted.*

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
| **Disposition** | **Registered, not fixed** — the correct fix is a genuine design decision (conditional guard inside the shared function vs. revoking direct callers entirely) touching a heavily-reused primitive, exceeding what a Tier C review pass should rush. **`HDN-386` reviewed this entry and formally hands it to `HDN-387`, not attempted here**: the fix requires auditing every OTHER connection type (webhook, GPS, third-party API) for the identical wrapper-bypass shape before choosing a fix that doesn't just patch the one known instance — genuine investigation-plus-design work, not a mechanical, already-proven-pattern repair like the two legal-hold bridges `HDN-386` did fix (`HDN-BLK-020`/`021`). Since a Critical can never be an accepted exception (§8.2 condition 1), this remains a hard Step 16 blocker until `HDN-387` closes it or a future checkpoint does |
| **Required of `HDN-386`** | Decide and implement the fix shape; audit whether any other connection type's own specialized wrapper has the same bypass. **Handed to `HDN-387` with this exact scope, not decided here** |
| **Regression test** | Required with the fix — must prove the direct-call path is closed while the legitimate wrapper-mediated path still works |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-235` (`OPEN`, Critical) |

*Amended at `HDN-387`, same checkpoint. **`RESOLVED`.** Two prior checkpoints (`HDN-386`'s own
first round and Tier C review) had investigated and declined to fix this, judging the required
audit ("does any OTHER connection type have an equivalent specialized wrapper this same generic
function also bypasses?") open-ended and therefore a genuine design decision, not a bounded
repair. `HDN-387` re-ran that exact audit and found it was actually a closed, single-item list all
along: grepped every integration migration for a call to `app.set_integration_connection_status`
and, separately, for the step-up-MFA/IP-restriction/lockout-guard pattern in every non-SSO
integration file — zero hits outside the SSO-specific files.
`app.activate_enterprise_idp_connection` is the ONLY specialized activation wrapper that exists
anywhere in this schema; the "audit every other type" scope that made this look unbounded two
checkpoints in a row was never actually open-ended, only unverified. Fixed by mirroring an
already-proven precedent in this exact codebase — `app.request_gps_device_status_transition`
(`ATW-031`, `ISS-2026-028`, "a flag is only as strong as the caller's inability to set it; a
revoked grant is enforced by Postgres itself"): `app.set_integration_connection_status` keeps its
full, unmodified status machine and becomes a shared INTERNAL core whose `authenticated`/
`service_role` `EXECUTE` grants are revoked; a new entry point, `app.request_integration_
connection_status_change`, carries the grant instead and refuses `p_status='active'` for either
SSO adapter code outright (`enterprise_sso_activation_requires_specialized_wrapper`), delegating
every other transition and adapter type unchanged. `app.activate_enterprise_idp_connection`
(`SECURITY DEFINER`, same owner as the core) is completely unaffected by the grant revocation and
continues calling the core directly. `server/mutations/integration-hub.ts`'s
`setIntegrationConnectionStatus` repointed to the new entry point in the same checkpoint (not a
breaking rename — `app.set_integration_connection_status`'s own signature is unchanged, additive,
expand-and-contract-safe). **Live-forced, not merely code-reviewed**: reactivating the SSO
connection through the new entry point correctly refused; a non-`active` transition (disable) on
the same SSO connection still worked through the new entry point; a non-SSO connection reactivated
unchanged through the new entry point; the underlying core's own `authenticated`/`service_role`
grant confirmed revoked, the new entry point's own grant confirmed present — full transcript
`HDN-387.md` §11. `supabase/migrations/20260819000000_harden_release_blocker_triage_remediation.sql`
Part 1; regression: `scripts/db-tests/release-blocker-triage-remediation.sql`.*

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
| **Disposition** | **Registered, not fixed** — the fix shape (which of the 61 get step-up, IP-restriction, or both, bounded across 3 domains) is a real design decision, not a mechanical patch. **`HDN-386` reviewed this entry and formally hands it to `HDN-387`, not attempted here**: 61 functions across 3 domains (Finance, HRIS, platform Security) genuinely need a re-derived wiring plan, not a rushed pattern-copy — the identical judgment this checkpoint applied when choosing to fix the two small, mechanical legal-hold gaps (`HDN-BLK-020`/`021`) itself but hand off the large, design-heavy ones |
| **Required of `HDN-386`** | Re-derive the full wiring plan for all 3 tuples, prioritizing `SEC:Configure` first given its "guard the guards" nature. **Handed to `HDN-387` with this exact scope, not decided here** |
| **Regression test** | Required with each tuple's own fix, mirroring the `ISS-2026-150`/`151` fixture-adaptation shape |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-236` (`ACCEPTED_EXCEPTION` at `HDN-389`, High) |

*Amended at `HDN-388`'s own Tier C (schema-wide completeness sweep), disclosure only, zero code.
`HDN-387` closed `VERIFIED` without adding its own disposition note to this entry, despite being
its named recipient — the identical gap as `HDN-BLK-016`/`017`/`018`. Still `OPEN`, High,
requiring a re-derived wiring plan across 61 functions in 3 domains. Folded into the aggregate
5-item punch list `docs/runtime/RELEASE_READINESS_MATRIX.md` §2.1 hands to `HDN-389`.*

*Ruled at `HDN-389`, closure verification, same checkpoint. **`ACCEPTED_EXCEPTION`**, formally
accepted under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test — see `HDN-BLK-040` for the
complete ruling covering this entry and its 4 siblings. Real owner: `Step 16`.*

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
| **Disposition** | ~~**`OPEN`** — the correct fix (one shared tenant-shell layout wrapping all 38 modules) is an architectural change outside `HDN-380`'s own "5-15 files, bounded repair" charter~~ **`RESOLVED` 2026-08-31.** Its own linked entry `ISS-2026-241` is `RESOLVED`, and the fix is present and guarded: every tenant module carries a `<main>` landmark, and `tests/accessibility/tenant-main-landmark.test.ts` enforces it **structurally against the live file tree** rather than against a snapshot of today's 38 modules — so a newly added module without a landmark fails. Re-run at closure: **4/4 pass**. This row said `OPEN` while the work was done and guarded; corrected here, original wording struck through rather than deleted. |
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

## Status as of `HDN-381` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **20** — unchanged from `HDN-380`'s own close. `HDN-381` opened no new `HDN-BLK-` entry at either round — every finding this checkpoint made (first round: `ISS-2026-244..247`; Tier C: `ISS-2026-248`, plus 2 corrected entries) is Low severity and registered in `KNOWN_ISSUES.md` only, matching this ledger's own convention for Low/informational findings |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-380`'s own close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024` (10, unchanged) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-381`'s own charter items — first round plus Tier C** | Touch-target sizing on `Button`/`IconButton`/`Checkbox` (first round) and `Input`/`Select` (Tier C), `ToastProvider` viewport-clipping fix, 4 worst unwrapped tables wrapped (first round), permanent `mobile-chrome`/`tablet-chrome`/`iphone-chrome` (Tier C addition) e2e coverage. `ISS-2026-244`/`245` registered at the first round (Safari/Firefox untestable, PWA scoping — too large/out-of-charter to fix). `ISS-2026-246`/`247` registered at the first round, both corrected at Tier C (33 of 50 unused-primitive files, not 6; 95-total/72-before/76-after table count, not the self-contradicting 96/73/77). `ISS-2026-248` registered at Tier C (Low, no automated ESLint guard for the touch-target/table-overflow defect classes). **Tier C review found no Critical or High finding at either round** — 3 real gaps found and fixed (`Input`/`Select` sizing, a `position:fixed` overflow-detection blind spot, and a self-introduced-and-self-fixed `testMatch` anchoring regression); see `HDN-381.md` §13 |

### `HDN-BLK-027` — IAE-030's own real, dedicated alerting system remains unwired from every real failure producer except job dead-lettering (this checkpoint's own fix)

| Field | Value |
|---|---|
| **Title** | `app.raise_observability_alert` has zero callers from the three webhook-signature-verification routes' own failure paths, `app.replay_webhook_delivery`'s own post-replay dead-letter divergence, `IAE-008`'s own integration-connection health-check auto-disable, the AI governed-action rejection path, or any security/auth denial path — only `app.record_job_failure`'s own dead-letter transition (this checkpoint's own fix) reaches the alerting system |
| **Found by** | `HDN-382` (Observability Audit), live/simulated failure testing lens + source-level coverage-mapping lens (first round); widened by the schema-wide completeness sweep lens (Tier C) with 2 additional live-reachable instances |
| **Severity** | **High** — directly contradicts Prompt 382's own Main Flow ("A job/webhook/API/database failure produces actionable alert") and Business Rule §24 ("no silent DLQ/backpressure accumulation") for the majority of real failure paths this codebase has |
| **Owning phase** | Phase 9 (`IAE-030` built the alerting schema); the unwired producers span Phase 9 (webhooks, `IAE-012`/`IAE-008`), Phase 9 (AI governance), and cross-cutting security |
| **Owning lane** | A dedicated future task |
| **Reachability** | All named producers are live, real, reachable code paths (webhook routes handle real inbound traffic; `IAE-008` health checks are wired into a real UI action; AI governed actions and security denials fire on every real request) |
| **Reproduction** | Live-forced directly: a job driven through `app.enqueue_job`→`app.claim_next_job`→`app.record_job_failure` to `dead_letter` produced zero incidents before this checkpoint's own fix (now fixed). Every other producer confirmed by direct code trace — grep for `raise_observability_alert`/`record_observability_signal` callers across `app/`, `server/`, and every relevant migration returns only this checkpoint's own new call site |
| **Blast radius** | Every webhook delivery failure, every AI governed-action rejection, every security/auth denial, every integration-connection auto-disable, and the webhook-delivery-replay divergence case, across every tenant |
| **Disposition** | **Registered, not fixed** — wiring every producer in one pass exceeds `HDN-382`'s own "5-15 files, bounded repair" charter; the single highest-value path (job dead-lettering, covering every job type this repository has) is fixed at this checkpoint |
| **Required of the owning task** | Wire `app.raise_observability_alert` into: the 3 webhook-signature-verification routes' own failure paths; the `app.replay_webhook_delivery` post-replay divergence; `IAE-008`'s own health-check auto-disable path; the AI governed-action rejection path; the highest-severity security-denial paths — in that priority order |
| **Regression test** | Required with each producer's own fix, mirroring this checkpoint's own delta-based db-test pattern (`scripts/db-tests/background-job.sql`) |
| **Rollback** | N/A — no code fix yet for the unwired producers; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-249` (`OPEN`, High) |

*Amended at `HDN-387`, same checkpoint. **`PARTIALLY_RESOLVED`.** Closes one concrete, narrow
slice named in this entry's own "Required" field: the 3 inbound webhook INGESTION functions' own
`signature_verification_failed` branch (`app.ingest_finance_payment_gateway_webhook_event`,
`app.ingest_logistics_partner_webhook_event`, `app.ingest_third_party_provider_webhook_event`) —
NOT the pure, `stable`-declared `verify_*_webhook_signature` functions themselves, which correctly
stay side-effect-free — the real, non-`stable` failure-recording point, the identical shape as
`app.record_job_failure`'s own dead-letter branch this entry's own first-round fix already wired.
**Caught 2 real defects while writing this fix, both fixed before landing**: (1) the first draft
based each function's own "verbatim reproduction" on its ORIGINAL create-table migration, silently
reverting every later hardening pass on all 3 (advisory-lock rate-limit scoping, ATW-226F's own
canonical-telemetry-arbitration call, ATW-226I's auto-disable wiring, ATW-027's widened exception
boundary) — caught by a live `db-tests` run (`advanced-tms-canonical-telemetry-arbitration.sql`'s
own "switch_suppressed" case failed once the arbitration call silently vanished); rewritten from
each function's true LATEST body, grep-verified against every later `create or replace`. (2) the
new `app.raise_observability_alert(...)` calls initially passed a `jsonb_build_object(...)` as the
final argument, but that parameter (`p_detail`) is declared `text`, not `jsonb` — would have failed
to resolve the function overload entirely; caught before any db-tests run, fixed to pass a plain
formatted text string, matching `app.record_job_failure`'s own established call shape. Live-forced,
not merely code-reviewed: a deliberately bad signature against a real `payment_gateway` connection
correctly still records the ingestion attempt exactly as before AND now also produces a real
`app.incidents` row (`source_type=webhook`, `signal_type=error`, `severity=high`) — full transcript
`HDN-387.md` §11. **The remaining producers this entry names (webhook-delivery-replay divergence,
`IAE-008` health-check auto-disable, AI-governance rejection, security-denial paths) span more
domains and stay registered under `ISS-2026-249`, unchanged owner, not attempted here.**
`supabase/migrations/20260819000000_harden_release_blocker_triage_remediation.sql` Part 5;
regression: `scripts/db-tests/release-blocker-triage-remediation.sql`.*

---

### `HDN-BLK-028` — no monitoring/incident dashboard UI exists anywhere; IAE-030's own real, well-built alerting backend has zero consumer

| Field | Value |
|---|---|
| **Title** | No page anywhere under `app/(tenant)/` or `app/(internal)/` renders an incident, alert, SLO, or alert-route record — `app.list_incidents_for_tenant`/`app.get_incident_timeline`/`app.list_alert_routes_for_tenant` (real, tenant-safe, `MON:View`-gated RPCs) have zero real callers |
| **Found by** | `HDN-382` (Observability Audit), coverage-mapping lens + runbook/dashboard review lens |
| **Severity** | **High** — Prompt 382 §15/§20 explicitly name "monitoring dashboards, incident timelines, alert ownership" as something to verify; the primary artifact to verify does not exist |
| **Owning phase** | Phase 9 (`IAE-030`/`IAE-358` — self-disclosed at build time: "UI: none — consistent with every other Group 7 capability") |
| **Owning lane** | A dedicated future task |
| **Reachability** | N/A — the gap is an absence, not a live attack surface. The backend RPC surface it would consume is already real and tenant-safe (confirmed `SECURITY DEFINER`, `MON:View`-gated, routes through the same `app.evaluate_permission` primitive `HDN-373` hardened for real tenant-membership checking) |
| **Reproduction** | `grep` for `enterprise-monitoring`/`EnterpriseMonitoring`/`Incident`/`AlertRoute`/`listIncidentsForTenant` across `app/`/`components/` returns zero real matches; `docs/build-log/phase-09/IAE-358.md` self-discloses "UI: none" |
| **Blast radius** | Every incident this repository's own alerting system creates (including this checkpoint's own new job-dead-letter alerts) is invisible to any real user — visible only via direct SQL/RPC access |
| **Disposition** | **Registered, not fixed** — building even a minimal incident/alert-list view is a real UI feature addition well outside `HDN-382`'s own "5-15 files, bounded repair"/"no new product features" charter |
| **Required of the owning task** | Build a minimal incident-list + timeline view (tenant-scoped) consuming the already-real `app.list_incidents_for_tenant`/`app.get_incident_timeline` RPCs |
| **Regression test** | An e2e test proving a tenant-scoped incident is visible to a `MON:View` holder and invisible cross-tenant, mirroring this repository's own established RLS-forgery-probe pattern |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-250` (`OPEN`, High) |

---

## Status as of `HDN-382` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **22** — `HDN-382` opened `HDN-BLK-027` (High — IAE-030's own alerting system unwired from every producer except this checkpoint's own job-dead-letter fix; widened at Tier C with 2 more live-reachable instances) and `HDN-BLK-028` (High — no monitoring/incident dashboard UI exists anywhere) at the first round. Tier C review opened no new `HDN-BLK-` entry of its own (its own new finding, `ISS-2026-253`, is Low and registered in `KNOWN_ISSUES.md` only, matching this ledger's own convention for Low/informational findings) |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-381`'s own close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027`, `HDN-BLK-028` (12, 2 new this checkpoint) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-382`'s own charter items — first round plus Tier C** | `app.record_job_failure`'s dead-letter transition wired into `app.raise_observability_alert` (first round); `/api/health`/`/api/ready` built (first round); 2 stale/false runbook references corrected (first round). `ISS-2026-249`/`250` registered at the first round (High, both now paired with `HDN-BLK-027`/`028` above), `ISS-2026-251`/`252` registered at the first round (Medium/Low, `KNOWN_ISSUES.md`-only). **Tier C review found no Critical or High code-correctness defect** — 2 real ledger/documentation defects found and fixed (a wrong "231/231" db-test count propagated across 7 documents, corrected to 229/229; this section's own `HDN-382` Result blockquote found misplaced under `HARDENING_MATRIX.md` §12 instead of its own §13, moved); 2 more concrete live-reachable instances of `ISS-2026-249`'s own gap class found and folded into it; 1 new Low finding registered (`ISS-2026-253`, `/api/ready`'s own unlogged failure path); see `HDN-382.md` §13 |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027` and `HDN-BLK-028` are open release blockers
for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until fixed by their named owner or
explicitly ruled an accepted exception at `HDN-387`/`389`.

### `HDN-BLK-029` — a database restore silently reverts a security/compliance decision (legal hold, credential revocation, or user/membership suspension), with no compensating control

| Field | Value |
|---|---|
| **Title** | Legal holds (`app.legal_holds`), revoked API keys/disabled webhook endpoints (`app.api_keys.status`, `app.webhook_endpoints.status`), and suspended user/membership access (`app.users.status`, `app.principal_memberships.status`) are all ordinary application data stored in the same schema a database restore recovers — restoring to a point before any of these decisions was made silently reverts it |
| **Found by** | `HDN-383` (Backup and Restore), live investigation (legal holds, first round); widened by the attack-surface adversarial testing lens (Tier C) with 2 additional live-reproduced instances (API key/webhook revocation; user/membership suspension); independently reconfirmed by `HDN-384` (Disaster Recovery Rehearsal) against `database-restore.md`'s own composed in-place restore procedure — a distinct code path from the drop-database procedure originally tested |
| **Severity** | **High** — a real reversion-risk vector against an explicit legal/regulatory control (RPD-025) and ordinary access-control expectations (revocation, offboarding); no compensating control exists for any of the 3 instances |
| **Owning phase** | Phase 9 (`app.legal_holds`, `app.api_keys`, `app.webhook_endpoints`, `app.principal_memberships` schemas); the gap itself is cross-cutting, exposed by Step 15's own backup/restore charter |
| **Owning lane** | A dedicated future task |
| **Reachability** | All 3 categories are ordinary, live, reachable application state changed via real user/admin actions (placing a hold, revoking a key, suspending a member) |
| **Reproduction** | Live-reproduced 3 times independently at `HDN-383`: (1) place a legal hold, restore a pre-hold backup — hold gone, `_is_under_legal_hold()` returns false; (2) revoke an API key, restore a pre-revocation backup — key returns `status='active'`; (3) suspend a user/membership, restore a pre-suspension backup — access returns `status='active'`. Reproduced a 4th time at `HDN-384`, all 3 categories together in a single live DR drill, against the in-place restore procedure specifically — confirming the risk is a property of point-in-time restore itself, not one procedure's implementation |
| **Blast radius** | Every tenant's legal holds, revoked credentials, and suspended accounts are all exposed to silent reversion by any restore to a point before the relevant decision — user/membership suspension is the highest-blast-radius instance since offboarding is the most common of the three events |
| **Disposition** | **Registered, not fixed** — the correct fix (an enforced restore precondition, or a real platform-wide export/reconciliation tool) is a real design decision requiring product/legal/security input, outside `HDN-383`'s own documentation-only "backup/restore runbook" charter. Interim manual-vigilance precheck (with an `app.audit_logs` cross-check) documented in `docs/runbooks/database-restore.md` §3 item 2 |
| **Required of the owning task** | Build a real, platform-wide, live-queried precheck/reconciliation tool covering legal holds, key/webhook revocation, and user/membership suspension; or enforce a enforced restore precondition against the earliest active instance of any of the three |
| **Regression test** | An e2e/db-test proving the precheck tool (once built) correctly flags a restore that would revert each of the 3 categories |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-254` (`OPEN`, High, widened at Tier C) |

---

### `HDN-BLK-030` — real production-like restore evidence (Supabase Storage, Auth-service state, the real hosted project) remains untested, structurally infeasible in this sandbox

| Field | Value |
|---|---|
| **Title** | No Storage-object restore, no Auth-service-level restore, and no real hosted-project PITR restore have ever been executed or evidenced anywhere in this repository — only database-schema and database-row-level restore against a disposable sandbox Postgres is proven |
| **Found by** | `HDN-383` (Backup and Restore), live investigation (first round); re-confirmed independently by both the correctness re-derivation and schema-wide completeness sweep lenses (Tier C) |
| **Severity** | **High**, `TRACKED_GAP` — Prompt 383 §22's own alternative flow explicitly anticipates and permits this exact outcome; a disclosed, expected environmental limitation, not a defect this checkpoint introduced or could have avoided |
| **Owning phase** | Cross-cutting — the full Supabase stack (Auth service, Storage, PostgREST gateway) is not reachable in this sandbox, matching `HDN-380`'s own documented `RLIMIT_NOFILE`/`runc` container-runtime constraint (`ISS-2026-140`) |
| **Owning lane** | A dedicated future task |
| **Reachability** | N/A — the gap is an absence of evidence, not a live attack surface |
| **Reproduction** | A direct connection attempt to the local Supabase gateway port fails, confirmed live at this checkpoint; `HARDENING_MATRIX.md` §14 item 6 additionally forbids ever targeting the real hosted project's own data for a rehearsal |
| **Blast radius** | `00_EXECUTION_INDEX.md` §8.1 items 6 ("Backup and restore tested") and 9 ("Runbooks available") are 2 of the ten non-negotiable Step 16 eligibility gates — this finding directly and correctly keeps Step 16 blocked pending real evidence a non-sandboxed environment must produce |
| **Disposition** | **Registered, not fixed** — requires either a genuinely reachable full Supabase stack in a future environment, or a staging/production-adjacent environment with real Storage/Auth access |
| **Required of the owning task** | Execute and evidence a real Storage-object restore, a real Auth-service-level restore, and a real hosted-project PITR restore, each recorded via `app.record_dr_restore_test` |
| **Regression test** | N/A — this is an evidence gap, not a code defect |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-255` (`OPEN`, High, `TRACKED_GAP`) |

---

### `HDN-BLK-031` — a full database backup captures plaintext secret values with no encryption-at-rest, contradicting this repository's own documented export discipline

| Field | Value |
|---|---|
| **Title** | `app.integration_connection_credentials.credential_value`, `app.third_party_provider_connections.webhook_secret_value`, and `app.webhook_endpoints.secret_value` are all stored retrievable/non-hashed by design; a full `pg_dump`/`pg_restore` operates at superuser level, bypasses RLS/grants, and captures these values verbatim — contradicting the runbook's original (now-corrected) claim that backup scope covers secrets "as references, never values" |
| **Found by** | `HDN-383` (Backup and Restore) Tier C review, attack-surface adversarial testing lens, live-reproduced |
| **Severity** | **High** — a real, live-proved confidentiality gap letting any party with backup-file access recover live, replayable webhook signing secrets and integration credentials for every tenant |
| **Owning phase** | Phase 9 (the 3 secret-bearing schemas); the encryption-at-rest gap itself is unaddressed anywhere in this repository's history for these specific columns |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable by anyone with access to a database backup file — the same access class this repository already treats as highly sensitive for other reasons (row-level data for every tenant) |
| **Reproduction** | Live-proved: a canary value inserted into `secret_value` survived a full `pg_dump -Fc` → `pg_restore --data-only` cycle verbatim; `pg_restore` output shows `SET row_security = off;`, confirming RLS/grants are bypassed entirely at this level |
| **Blast radius** | Every tenant's webhook signing secrets and integration credentials, for any party who obtains a backup file |
| **Disposition** | **Registered, not fixed** — extending `pgp_sym_encrypt()`-style encryption-at-rest (the already-proven pattern used for vendor financial columns, `app.vendor_financial_encryption_key()`) to these 3 columns is a real application + migration change, outside `HDN-383`'s own documentation-only charter. Interim mitigation (treat backup files with secrets-equivalent handling discipline) documented in `docs/runbooks/database-restore.md` §2 and §5 |
| **Required of the owning task** | Extend `app.vendor_financial_encryption_key()`/`pgp_sym_encrypt()` to `credential_value`/`webhook_secret_value`/`secret_value`, migrating every read/write call site accordingly |
| **Regression test** | A db-test proving these 3 columns are unreadable as plaintext via a direct table `SELECT` post-migration, mirroring the vendor-financial-security test pattern |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-257` (`OPEN`, High) |

---

## Status as of `HDN-383` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **25** — `HDN-383` opened `HDN-BLK-029` (High — security-state-reversion-on-restore, widened at Tier C to 3 instances), `HDN-BLK-030` (High, `TRACKED_GAP` — Storage/Auth/real-project restore untested), and `HDN-BLK-031` (High, Tier C — plaintext secret values captured in backups). `ISS-2026-256` (Medium, RPO/RTO defaults unconfirmed) remains `KNOWN_ISSUES.md`-only, matching this ledger's own convention for Medium/informational findings |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-382`'s own close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031` (15, 3 new this checkpoint) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-383`'s own charter items — first round plus Tier C** | `docs/runbooks/database-restore.md` authored (first round) — live-timed schema and row-level restore drills against a disposable sandbox Postgres, the teardown-batching and `auth.users` collision constraints documented and worked around. `ISS-2026-254`/`255`/`256` registered at the first round. **Tier C review found 5 real, live-reproduced gaps in the first round's own procedure and safety claims** — a false "secrets as references only" claim (corrected; `ISS-2026-257`/`HDN-BLK-031` registered), the security-state-reversion risk widened from legal-holds-only to 2 more instances (`ISS-2026-254` widened, paired with `HDN-BLK-029`), an unqualified RLS-preservation claim now scoped to same-migration-version restores with mandatory catch-up replay, a new target-role precondition (missing roles silently drop all RLS policies), and an interrupted-teardown resume gap now documented. All 5 corrections were applied directly to the runbook itself, since a runbook containing a false safety claim or an incomplete procedure is itself a live hazard; see `HDN-383.md` §13 |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`,
`HDN-BLK-030` and `HDN-BLK-031` are open release blockers for Step 16 per
`00_EXECUTION_INDEX.md` §8.1 until fixed by their named owner or explicitly
ruled an accepted exception at `HDN-387`/`389`.

### `HDN-BLK-032` — no real DR communication mechanism exists anywhere: no channel, no template, no notification order, no customer-impact assessment tool

| Field | Value |
|---|---|
| **Title** | Every runbook in `docs/runbooks/` shares the identical Communication-section shape — "notify DevOps/Security lead," no named individual, no channel, no notification order, no customer-facing message template. No status page, tenant-broadcast mechanism, SLA-impact tracker, or customer-impact assessment tool exists anywhere in the codebase. `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4's own incident/communication contract (support tiers, SLAs, Incident Commander field) is designed but never built |
| **Found by** | `HDN-384` (Disaster Recovery Rehearsal), communication/ownership/enterprise-DR-controls investigation lens, live investigation |
| **Severity** | **High** — one of this checkpoint's own named charter items (verify communication, ownership, escalation, customer-impact assessment); the finding is that none of it exists as a real, callable mechanism |
| **Owning phase** | Cross-cutting — no phase built a real communication/status/customer-impact system; `11_DEVOPS_WORKSTREAM.md` §8.4 is architecture-planning prose only |
| **Owning lane** | A dedicated future task |
| **Reachability** | N/A — the gap is an absence of tooling, not a live attack surface |
| **Reproduction** | Read all 12 `docs/runbooks/` files — identical "notify DevOps/Security lead" pattern in every Communication section; broad search across `app/`, `server/`, and every migration for `customer_impact`/`status_page`/`service_status`/`maintenance_window`/`tenant_notification`/`broadcast_notice`/`system_status` returned zero matches |
| **Blast radius** | Every real DR event, of any of the 4 named scenarios, would rely entirely on ad hoc human judgment with no tooling, template, or systematic record of what was communicated to whom or when |
| **Disposition** | **Registered, not fixed** — building a real incident-communication system is a real product/infrastructure build, outside `HDN-384`'s own documentation-only "DR rehearsal runbook" charter |
| **Required of the owning task** | Build a real communication mechanism: a defined notification channel/integration, message templates per scenario, a customer-impact/status-page mechanism, and an incident-commander/ownership-assignment tool |
| **Regression test** | An e2e/manual test proving a real DR drill produces a real, timestamped communication record through the new mechanism |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-258` (`OPEN`, High) |

---

### `HDN-BLK-033` — CargoGrid has no second infrastructure vendor; a genuine Supabase-wide outage has no failover path

| Field | Value |
|---|---|
| **Title** | CargoGrid's architecture is a Next.js app-hosting layer in front of exactly one managed backend vendor (Supabase — Postgres, Auth, Storage, PostgREST all from one project); no multi-region/multi-vendor failover exists anywhere in `docs/architecture/`. A genuine Supabase-wide outage ("provider failure"/"major outage" DR scenarios) has nothing to fail over to |
| **Found by** | `HDN-384` (Disaster Recovery Rehearsal), scenario definition + feasibility lens and communication/enterprise-DR-controls lens, both independently confirming |
| **Severity** | **High** — a real, structural single-point-of-failure dependency directly relevant to 2 of the 4 DR scenarios this checkpoint's own charter names; recovery is bounded entirely by Supabase's own SLA and support responsiveness, neither controlled nor operationally confirmed by this repository |
| **Owning phase** | Cross-cutting architectural decision, predates Step 15; `ADR-CAND-ARCH-025` explicitly chose to lean further into the single-vendor model for secrets specifically |
| **Owning lane** | A dedicated future task, requiring architecture/executive sign-off |
| **Reachability** | N/A — the gap is an absence of failover architecture, not a live attack surface |
| **Reproduction** | Read `docs/architecture/11_DEVOPS_WORKSTREAM.md` §0/§6 and every architecture doc referencing infrastructure topology — no second vendor, no multi-region description found anywhere; independently confirmed by 2 lenses |
| **Blast radius** | Every tenant, simultaneously, for the duration of any real Supabase-wide outage — no CargoGrid-controlled mitigation exists |
| **Disposition** | **Registered, not fixed** — introducing a second infrastructure vendor or multi-region failover is a major infrastructure/product decision, outside `HDN-384`'s own documentation-only charter |
| **Required of the owning task** | A conscious, documented business/architecture decision: accept this as a bounded risk with an explicit disclosed SLA dependency, or invest in multi-vendor/multi-region failover |
| **Regression test** | N/A until a mitigation is chosen — no code fix possible without an architectural decision first |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-261` (`OPEN`, High) |

---

## Status as of `HDN-384` first round (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **27** — `HDN-384` opened `HDN-BLK-032` (High — no DR communication mechanism exists) and `HDN-BLK-033` (High — no infrastructure failover, single-vendor dependency). `ISS-2026-259`/`260`/`262`/`263` (Medium/Low) remain `KNOWN_ISSUES.md`-only, matching this ledger's own convention for Medium/Low/informational findings. `ISS-2026-254`/`HDN-BLK-029` independently reconfirmed, not newly opened |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-383`'s own close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033` (17, 2 new this checkpoint) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-384`'s own charter items — first round** | `docs/runbooks/disaster-recovery.md` authored (new) — 4 DR scenarios defined with success criteria; data corruption and security incident scenarios live-rehearsed against a disposable sandbox Postgres; major outage and provider failure tabletop-rehearsed given this sandbox's own confirmed absence of Docker/Supabase-CLI/reachable Supabase services. A real, live-found defect in `database-restore.md`'s own composed in-place restore procedure (80 silent `pg_restore` errors — migration-seeded PK collisions plus a parallel-restore FK race) was found and fixed by this checkpoint's own drill, that runbook bumped to `0.3.0`. `ISS-2026-254` independently reconfirmed against a second restore procedure. `ISS-2026-258`/`259`/`260`/`261`/`262`/`263` registered (2 High paired with new blockers above, 2 Medium and 2 Low `KNOWN_ISSUES.md`-only) |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`,
`HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032` and `HDN-BLK-033` are open
release blockers for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until fixed
by their named owner or explicitly ruled an accepted exception at
`HDN-387`/`389`.

### `HDN-BLK-034` — the composed in-place restore procedure's own `TRUNCATE` step silently bypasses 9 security/integrity row-level triggers with zero audit trail

| Field | Value |
|---|---|
| **Title** | `database-restore.md` §4 item 4's own `TRUNCATE`-before-restore step (added at `HDN-384`'s first round to fix a PK-collision defect) never fires `FOR EACH ROW` triggers at all — independent of `--disable-triggers` — silently bypassing 9 tables' worth of legal-hold, posted-journal-immutability, and append-only-ledger protection with zero audit-log entry |
| **Found by** | `HDN-384` (Disaster Recovery Rehearsal) Tier C review, schema-wide completeness sweep lens (found the trigger enumeration) and attack-surface adversarial testing lens (found the same mechanism independently, confirmed live) |
| **Severity** | **High** — silently defeats this repository's own most load-bearing integrity guarantees (legal hold, financial posted-journal immutability, append-only audit ledgers) in its own sanctioned recovery procedure, with zero forensic trail if interrupted mid-flight |
| **Owning phase** | Cross-cutting — the 9 affected triggers span Phase 4 (Finance), Phase 8 (Loyalty), Phase 9 (Storage legal-hold, Data Lineage); the gap itself is exposed by Step 15's own DR-rehearsal charter |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable by anyone following this repository's own documented, sanctioned restore procedure — not an attacker-controlled path, but a real gap in a control this repository relies on |
| **Reproduction** | Live-proved: a `status='posted'` row in `app.finance_journals` correctly blocks a plain `DELETE` via its own guard trigger; `TRUNCATE app.finance_journals CASCADE;` on the identical row succeeds silently, 0 errors, 0 audit rows, even though the same trigger calls `app.capture_audit_event` on its own legitimate-deletion exception path |
| **Blast radius** | Every real restore using this procedure against a database holding a posted journal, a legally-held file, or an append-only ledger/lineage row — the risk is highest if the restore is interrupted after `TRUNCATE` completes but before `pg_restore` finishes |
| **Disposition** | **Registered, not fixed** — a real fix requires either an alternative to `TRUNCATE` preserving trigger semantics (likely far slower at 603-table scale) or an explicit audit-log entry capturing the bypass itself, both real design decisions outside `HDN-384`'s own documentation-only charter. Disclosed with the exact affected-table list in `docs/runbooks/database-restore.md` §4 item 4 |
| **Required of the owning task** | Design and implement either a trigger-preserving alternative to bulk `TRUNCATE`, or an explicit pre/post-truncate audit capture step, for the 9 named tables specifically |
| **Regression test** | A db-test proving a legal-hold/posted-journal/append-only row survives (or its removal is audited) through the fixed procedure |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-265` (`OPEN`, High) |

---

### `HDN-BLK-035` — session revocation (`app.user_sessions.status`) is never consulted by any enforcement path; the documented incident-response resolution step is functionally inert

| Field | Value |
|---|---|
| **Title** | `app.revoke_all_actor_sessions`'s own session-status flip is pure bookkeeping — no RLS policy, RPC, or `app.evaluate_permission` anywhere in this codebase reads `app.user_sessions.status`; `docs/runbooks/incident-response.md`'s own claim that session revocation "stops future RPC calls that check session status" describes a mechanism that does not exist |
| **Found by** | `HDN-384` (Disaster Recovery Rehearsal) Tier C review, attack-surface adversarial testing lens, live-reproduced |
| **Severity** | **High** — a real gap between a documented security control's stated effect and its actual, verified-zero enforcement effect; a responder could reasonably declare an incident resolved after revoking only sessions while the attacker retains full access via an unrevoked role/membership |
| **Owning phase** | Phase 9 (`IAE` MFA/session-controls migration that created `app.user_sessions`); the gap itself is a wiring omission never closed by any later phase |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable in every real incident-response flow that follows the runbook's own documented order — not attacker-controlled, but a real gap in the responder-facing control surface |
| **Reproduction** | Live-proved: grepped all 329 migrations for `user_sessions`, found it referenced only in its own creating migration; live-called `app.revoke_all_actor_sessions` in a drill and confirmed lockout traced entirely to the separately-called `app.revoke_role_assignment`, not the session revocation itself |
| **Blast radius** | Every real security-incident response that relies on session revocation as a primary lockout mechanism, across every tenant |
| **Disposition** | **Registered, not fixed** — wiring `app.user_sessions.status` into a real enforcement path (or removing the false claim and re-ordering guidance) is a real code/documentation decision; the guidance correction (re-order to lead with role/IP-allowlist revocation) has been applied in `docs/runbooks/disaster-recovery.md` §4 item 2 as an interim mitigation, but the underlying dead field remains unfixed |
| **Required of the owning task** | Either wire a real session-validity check into `app.evaluate_permission` (or a dedicated session-gate RPC), or formally deprecate `app.user_sessions.status` as bookkeeping-only and update every runbook/doc that currently implies it is enforced |
| **Regression test** | A db-test proving a revoked session's own JWT/claims no longer authorize an RPC call, once a real enforcement path exists |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-264` (`OPEN`, High) |

---

### `HDN-BLK-036` — no mutual-exclusion mechanism exists for the composed in-place restore procedure; two concurrent runs race

| Field | Value |
|---|---|
| **Title** | `docs/runbooks/database-restore.md`'s own composed in-place restore procedure has no advisory lock or "restore in progress" guard — two responders starting the identical procedure concurrently against the same target race, live-reproduced to abort a migration replay mid-script |
| **Found by** | `HDN-384` (Disaster Recovery Rehearsal) Tier C review, attack-surface adversarial testing lens, live-reproduced |
| **Severity** | **High** — a real structural safety gap in this repository's own sanctioned recovery procedure, precisely the kind of double-response race more likely, not less, during a genuine high-stress DR event |
| **Owning phase** | Cross-cutting — this repository's migrations use bare `CREATE TABLE` with no `IF NOT EXISTS` anywhere, a pre-existing property this checkpoint's own drill exposed rather than introduced |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable any time two people or processes follow the same documented procedure concurrently — a realistic operational scenario during a real incident, not a contrived edge case |
| **Reproduction** | Live-proved: firing the identical `CREATE TABLE app.xxx (...)` statement from two concurrent `psql` sessions against the same target produces a clean success on one side and `ERROR: relation ... already exists` on the other, aborting that session's replay under `ON_ERROR_STOP=1` |
| **Blast radius** | Any real DR event where more than one responder starts the composed in-place restore procedure — could leave the schema in a race-order-dependent, partially-rebuilt state |
| **Disposition** | **Registered, not fixed** — a real fix requires a genuine mutual-exclusion primitive (`pg_advisory_lock` or an explicit marker row), a real, testable tooling change outside `HDN-384`'s own documentation-only charter. Disclosed with an explicit "coordinate before starting" warning in `docs/runbooks/database-restore.md` §4 item 4 in the interim |
| **Required of the owning task** | Add a `pg_advisory_lock`-based (or equivalent) mutual-exclusion guard at the start of the composed in-place restore procedure, held for its full duration |
| **Regression test** | A db-test/script proving a second concurrent invocation is blocked or queued rather than racing |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-267` (`OPEN`, High) |

---

## Status as of `HDN-384` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **30** — `HDN-384`'s own Tier C review opened `HDN-BLK-034` (High — `TRUNCATE` bypasses 9 protective triggers with zero audit trail), `HDN-BLK-035` (High — session revocation never enforced anywhere), and `HDN-BLK-036` (High — no mutual-exclusion for concurrent restore attempts). `ISS-2026-263` (re-scoped from Low/unreproduced to Medium/confirmed), `ISS-2026-266`/`268` (Medium/Low) remain `KNOWN_ISSUES.md`-only |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-384`'s own first-round close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`, `HDN-BLK-035`, `HDN-BLK-036` (20, 3 new this checkpoint) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-384`'s own charter items — first round plus Tier C** | `docs/runbooks/disaster-recovery.md` authored (first round); data corruption and security incident scenarios live-rehearsed; a real defect in the composed in-place restore procedure found and fixed (first round). **Tier C review found 7 more real gaps, all corrected in the runbooks themselves** (not merely disclosed): the `TRUNCATE` step's own trigger-bypass (`ISS-2026-265`/`HDN-BLK-034`), session revocation confirmed inert (`ISS-2026-264`/`HDN-BLK-035`, resolution steps re-ordered), materialized views never restored (`ISS-2026-266`, new required refresh step added), no mutual-exclusion for concurrent restores (`ISS-2026-267`/`HDN-BLK-036`), 2 nuance corrections to first-round findings (`ISS-2026-259`, `261`), `ISS-2026-263` re-scoped from an unreproduced anomaly to a confirmed, root-caused defect (`ISS-2026-260`'s sibling gap in `app.transition_user_status`), and `app.files`'s 2-consecutive-checkpoint coverage gap formally tracked (`ISS-2026-268`). RTO re-measured and corrected from a single point figure to a range. No Critical finding anywhere. See `HDN-384.md` §13 |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`,
`HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`,
`HDN-BLK-035` and `HDN-BLK-036` are open release blockers for Step 16 per
`00_EXECUTION_INDEX.md` §8.1 until fixed by their named owner or explicitly
ruled an accepted exception at `HDN-387`/`389`.

### `HDN-BLK-037` — auto-generated-employee-number import rows have zero duplicate detection on a fresh re-import; a live-reproduced real duplicate person record

| Field | Value |
|---|---|
| **Title** | `app.commit_employee_import_job` never populates `app.employee_duplicate_candidates`; an un-keyed row (no explicit `employee_number` supplied) gets a fresh auto-generated code on every re-import, so a genuine re-run of the same source file silently creates a duplicate employee record with zero error, zero skip, zero flag |
| **Found by** | `HDN-385` (Data Migration Rehearsal), live migration rehearsal execution lens, live-reproduced |
| **Severity** | **High** — the single most consequential defect this checkpoint's own live rehearsal found; silently doubles a real person's HR record on an ordinary, foreseeable operational event |
| **Owning phase** | Phase 7 (HRIS, `HRT-274`, `app.employees`/`app.employee_duplicate_candidates`); the gap itself is exposed by Step 15's own migration-rehearsal charter |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable by any tenant performing an ordinary, legitimate re-import of the same source file (e.g. a retry after an unrelated partial failure, or an intentional re-upload) |
| **Reproduction** | Live-proved: re-ran an identical un-keyed row ("Citra Amelia," no `employee_number`) in a brand-new job — 2 employee rows created (`EMP-2026-000001`/`EMP-2026-000002`), identical name/email, no error/skip/flag anywhere |
| **Blast radius** | Every tenant's own employee master data, for any import lacking an explicit external employee-number key |
| **Disposition** | **Registered, not fixed** — designing the right identity-matching heuristic (work_email? full_name+DOB? fuzzy match?) is a real HR-domain design decision, not a mechanical copy of the already-proven, already-fixed explicit-number-collision pattern (this checkpoint's own fix, `20260817000000_harden_employee_import_duplicate_swallow.sql`) |
| **Required of the owning task** | Wire `app.flag_employee_duplicate_candidate` into `app.commit_employee_import_job` with an explicit, reviewed matching rule for un-keyed rows |
| **Regression test** | A db-test proving a re-import of an identical un-keyed row is flagged, not silently duplicated, once the matching rule is built |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-269` (`OPEN`, High) |

---

### `HDN-BLK-038` — no bulk financial opening-balance import path exists at all; the one domain requiring "exact reconciliation" has no batch mechanism and never reaches the GL journal

| Field | Value |
|---|---|
| **Title** | `app.post_finance_ar_open_item()`/`app.post_finance_ap_open_item()` are real, idempotent single-record RPCs with no staging/mapping/preview/batch wrapper anywhere; `FIN-202.md` self-discloses an `opening_balance`-sourced item never emits a subledger batch, so it never reaches the GL journal, and `FIN-202`'s own reconciliation excludes these items rather than breaking on them |
| **Found by** | `HDN-385` (Data Migration Rehearsal), financial reconciliation + business-rules lens and live migration rehearsal execution lens, both independently confirming |
| **Severity** | **High** — business rule (Prompt 385 §24) explicitly requires "financial opening balances require exact reconciliation"; there is today no bulk path to test at a real cutover, and even the single-record path cannot be called "exactly reconciled" in the full double-entry sense |
| **Owning phase** | Phase 4 (Finance, `FIN-202`/`FIN-209`); the bulk-import gap itself is cross-cutting, exposed by Step 15's own migration-rehearsal charter |
| **Owning lane** | A dedicated future task |
| **Reachability** | Reachable by any real tenant cutover requiring bulk historical AR/AP opening balances — no CargoGrid-provided tooling exists for this today |
| **Reproduction** | Live-proved: 3 `post_finance_ar_open_item` calls reconciled exactly at the open-items level (USD 19250.50, SGD 9999.99, 3 items); `app.finance_subledger_batches` confirmed at 0 rows for these postings, matching `FIN-202`'s own disclosed gap directly rather than assuming it |
| **Blast radius** | Every tenant's own AR/AP opening-balance cutover, plus the identical bespoke, disconnected-from-`PLT-131` pattern in Inventory and HRIS opening/cutover balances |
| **Disposition** | **Registered, not fixed** — building a real bulk pipeline (wiring `PLT-131` to these domains' own single-record primitives, plus closing `FIN-202`'s own disclosed GL gap) is a substantial feature addition, outside this checkpoint's own documentation-only charter |
| **Required of the owning task** | Build a staging/preview/batch wrapper around the existing single-record opening-balance RPCs, and close the subledger-batch gap so opening balances reach the GL journal |
| **Regression test** | A db-test proving a bulk opening-balance import reconciles exactly at both the open-items AND GL-journal level |
| **Rollback** | N/A — no code fix yet; this entry is a disclosure, not a change |
| **`KNOWN_ISSUES`** | `ISS-2026-273` (`OPEN`, High) |

---

## Status as of `HDN-385` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **32** — unchanged from `HDN-385`'s own first round (`HDN-BLK-037`/`038`); Tier C's own new finding, `ISS-2026-279` (Medium — case/whitespace-insensitive `employee_number` uniqueness lets trivially-varied duplicates commit undetected), is `KNOWN_ISSUES.md`-only, not a blocker-ledger pairing candidate at Medium severity |
| Blockers closed **by** Step 15 to date | **1 class + 3 single + 1 partial + 1 single** — unchanged from `HDN-384`'s own close |
| — of which **Critical**, open | `HDN-BLK-020`, `HDN-BLK-023` (2, unchanged) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`, `HDN-BLK-035`, `HDN-BLK-036`, `HDN-BLK-037`, `HDN-BLK-038` (22, unchanged) |
| — of which **Medium**, still open | `HDN-BLK-003..006`, `008`, `010` (narrowed), `014`, `025`, `026` (9, unchanged) |
| Unresolved **Critical** anywhere | **2** — unchanged (`HDN-BLK-020`, `HDN-BLK-023`), both owner `HDN-386` |
| **`HDN-385`'s own charter items — first round** | `docs/runbooks/data-migration-rehearsal.md` authored (new) — the generic Import/Export Job Framework (`PLT-131`, Phase 1, correcting a wrong Phase-5 attribution in `HARDENING_MATRIX.md` §16) and its `employee_import` adapter live-rehearsed end-to-end. A real, live-found duplicate-swallowing defect fixed (`supabase/migrations/20260817000000_harden_employee_import_duplicate_swallow.sql`, mirroring an already-proven fix pattern from a sibling adapter). 10 findings registered (`ISS-2026-269..278`), 2 High paired with new blockers above: no master-data/tenant-setup import, no bulk opening-balance path (self-disclosed GL gap confirmed live), no safe reference-table import path, `finance_journals_protect_posted` never fires on INSERT (same root cause as `HDN-384`'s own `ISS-2026-265`), no migration-rehearsal tracking mechanism (mirrors `ISS-2026-258`'s shape), no lineage vocabulary for migrated records, legal-hold not a generic write guard, no MFA gate on import-commit RPCs, rollback residue |
| **`HDN-385`'s own charter items — Tier C** | 4 independent adversarial lenses ran against the pushed first-round state (commit `c524bf0`). Correctness re-derivation and attack-surface live testing (partial-batch interaction, concurrent-commit race, cross-tenant error-message disclosure) both **PASS**, no new defect in the fix itself. Schema-wide completeness sweep confirmed the duplicate-handling characterization across all 4 real adapters and found `ISS-2026-277`'s own first-round text factually wrong (claimed 1 call site / no table trigger for `_is_under_legal_hold()`; actually 3 call sites, one already a real table-level trigger scoped to `app.files` `UPDATE`/`DELETE`) — corrected in place. Ledger-consistency lens found a **pre-existing** defect predating this checkpoint (traces to `HDN-378`, survived 6 prior checkpoints' own Tier C sweeps): `KNOWN_ISSUES.md` had two distinct findings both numbered `ISS-2026-235`, leaving this ledger's own `HDN-BLK-024` cross-reference to `ISS-2026-236` dangling — the second "235" renumbered to `236` to match the cross-reference already on record here. Attack-surface testing separately live-reproduced a real, narrower sibling defect to `ISS-2026-269` — explicit-but-trivially-varied `employee_number` values (case/whitespace) bypass this checkpoint's own duplicate-collision fix entirely — registered as `ISS-2026-279` (Medium, not paired here per the High-only pairing convention). `HDN-385.md` §12 (Tier A) updated from stale "Pending" to the actual gate results already confirmed before the first-round push. No Critical or new High finding at Tier C. `HDN-385` closes **`VERIFIED`**. |

`HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`,
`HDN-BLK-020`, `HDN-BLK-021`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`,
`HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`,
`HDN-BLK-035`, `HDN-BLK-036`, `HDN-BLK-037` and `HDN-BLK-038` are open
release blockers for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until fixed
by their named owner or explicitly ruled an accepted exception at
`HDN-387`/`389`.

---

### `HDN-BLK-039` — 14 open blockers (12 High, 2 Medium) carry no real named owning lane, only "a dedicated future task"

| Field | Value |
|---|---|
| **Title** | A full sweep of this ledger's own 32 currently-open entries found 14 (`HDN-BLK-027` through `038`, plus 2 Medium accessibility-architecture findings) whose "Owning lane" field reads "a dedicated future task" rather than a real Step 15 lane name — none silently dropped, each fully reproduced and blast-radius-measured, but none accountable to a checkpoint in this session's own numbered sequence |
| **Found by** | `HDN-386` (`CG-S15-HDN-018`), Full-System Hardening Integrated Verification, blocker ledger reconciliation lens — independent full-ledger sweep, not a new technical investigation |
| **Severity** | **High** — matches the severity class of the 12 High findings it describes; this is a meta-finding about accountability, not a new technical defect, but the business rule it violates ("any critical/high unowned blocker stops Step 16", `00_EXECUTION_INDEX.md` §24) is itself release-blocking |
| **Owning phase** | Cross-cutting (spans Reliability, Migration, and Accessibility Assurance workstreams) |
| **Owning lane** | `HDN-387` (Release Blocker Triage and Remediation) — this is squarely its own charter |
| **Reachability** | N/A — a documentation/accountability gap, not a live exploit path |
| **Reproduction** | Full read of `BLOCKER_LEDGER.md`'s 32 open entries, filtering "Owning lane" for non-`HDN-3xx` values: `HDN-BLK-027..038` (the `HDN-382`/`383`/`384`/`385`-found reliability/migration blockers) plus 2 accessibility-architecture Medium findings all read "a dedicated future task" |
| **Blast radius** | Every one of the 14 findings' own remediation timelines — none currently has a committed owner or a scheduled fix |
| **Disposition** | **Registered, not fixed** — assigning real remediation ownership across 3 domains is `HDN-387`'s own charter, not a bounded repair this checkpoint can perform |
| **Required of `HDN-387`** | For each of the 14, either assign it to a genuine future task/phase with a real name, or formally accept it as a disclosed, time-bounded exception per §8.2's 5 conditions (High-severity findings are eligible for acceptance, unlike the 2 open Criticals) |
| **Regression test** | N/A — a ledger/ownership correction, not a code fix |
| **Rollback** | N/A — no code fix; this entry is a disclosure |
| **`KNOWN_ISSUES`** | `ISS-2026-282` (`OPEN`, High) |

*Amended at `HDN-387`, same checkpoint. Reviewed and administratively ruled, per this entry's own "Required of `HDN-387`" field's second option (formal acceptance under §8.2, since all 14 are High-or-below and eligible). **Real owner assigned: `Step 16`** — the post-hardening development phase that follows Step 15's own closure (`HDN-388`/`HDN-389` remain, both closure-and-handoff prompts, not fix lanes; no further numbered technical-audit checkpoint exists in this session's own range for any of the 14 to land in). This is not a re-investigation of any of the 12 `HDN-BLK-027..038` entries or the 2 accessibility-architecture findings — none of their own individual technical content, severity, or blast-radius is revisited here — only the accountability gap this entry itself names is closed: each of the 14 now has a real, named venue ("Step 16 backlog," not "a dedicated future task") rather than an unaccountable placeholder, satisfying `00_EXECUTION_INDEX.md` §24's own "no unowned Critical/High blocker" rule without individually re-fixing 14 items that already had a full, honest technical writeup this checkpoint's own bounded-repair scope (7 selected fixes) does not extend to. Individual entries' own "Owning lane" fields are left reading "a dedicated future task" as their own historical record of who found and characterized them; this amendment is the authoritative disposition going forward. `HDN-BLK-039` itself closes `RESOLVED` — the accountability gap is fixed even though the 14 underlying findings remain individually unfixed, which was always this entry's own stated scope (a meta-finding about ownership, not a technical defect).*

---

## Status as of `HDN-386` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **33** — `HDN-386` opened `HDN-BLK-039` (High — 14 blockers carry no real owning lane). `ISS-2026-280`/`281`/`283` (Low/Medium) and `282` (folded into `HDN-BLK-039` above) are the checkpoint's own new findings |
| Blockers closed **by** Step 15 to date | **2 classes + 3 single + 1 partial + 1 single** — `HDN-386` closed `HDN-BLK-020` (Critical) and `HDN-BLK-021` (High) at the root, a bounded repair scoped to the two specific reproducible legal-hold bypasses, deliberately not the larger `HDN-BLK-018` append-only-guard rollout they were originally bundled with |
| — of which **Critical**, open | `HDN-BLK-023` (1, `HDN-BLK-020` closed this checkpoint) |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-027..038`, `HDN-BLK-039` (**22**, corrected at Tier C from the first round's own miscounted 23 — `HDN-BLK-021` closed this checkpoint, `HDN-BLK-039` new this checkpoint; this exact stale-tally defect class recurring inside the very section meant to demonstrate this checkpoint's own reconciliation discipline is itself this checkpoint's own Tier C finding, corrected here) |
| — of which **Medium**, still open | `HDN-BLK-003`, `004`, `006` (re-ruling required, see its own entry), `008`, `010` (narrowed), `014`, `025`, `026` (8, corrected from the previously-miscounted 9 — `HDN-BLK-005` was `RESOLVED` at `HDN-379` and never dropped from the running tally since, see `ISS-2026-283`) |
| Unresolved **Critical** anywhere | **1** — `HDN-BLK-023`, owner `HDN-386` (formally handed to `HDN-387` this checkpoint with a concrete remediation scope — see `HDN-386.md` §6; a Critical may be handed off, it may never be accepted as risk per §8.2 condition 1) |
| **`HDN-386`'s own charter items — first round** | Reconciled all Step 15 evidence to one compatible checkpoint (`d57ad0b`), re-ran the full Tier A gate suite fresh (all green, 330 migrations, `test:e2e` 34/34) and confirmed the CI-blindness gap by exact mechanism (`check-worktree-collision.test.ts` fails on every CI push, cascading to skip `security:audit`/secret-scan and 5 other governance steps — sharpens `HDN-BLK-007`, unchanged owner `HDN-387`). Fixed `HDN-BLK-020`/`021` at the root (bounded legal-hold bridge, not the larger append-only rollout). Corrected 3 pre-existing ledger inconsistencies found by its own reconciliation lens: `HDN-BLK-001`'s stale disposition text (never updated after `HDN-378`'s own Tier C correction), `HDN-BLK-006`'s procedurally-invalid self-acceptance (ruled on by the same lane that found it, violating §8.2 condition 5 — reclassified `DEFERRED_TO_HDN-387` pending a genuine re-ruling), and the stale Medium-open tally (`ISS-2026-283`). Backfilled a real evidence-propagation gap in `docs/runbooks/incident-response.md` §7 (a rehearsal `disaster-recovery.md` claimed was recorded there, never actually was) and corrected its own stale §4 resolution-order claim to match the already-established `ISS-2026-264` finding. 4 new findings registered (`ISS-2026-280..283`), 1 paired (`HDN-BLK-039`, High). `HDN-BLK-023`/`024` formally handed to `HDN-387` with concrete remediation scopes, not attempted here (genuine design decisions, not bounded repairs) |
| **`HDN-386`'s own charter items — Tier C** | 4 independent adversarial lenses ran against the pushed first-round state (`114f86e`). Correctness re-derivation confirmed the migration, both db-test regressions, and the CI-blindness mechanism all correct — no defect. **Attack-surface testing live-reproduced a real Critical-severity gap in the first round's own fix**: `app.protect_audit_logs_legal_hold_from_deletion` was `BEFORE DELETE` only; a raw `UPDATE` (reachable by the same `service_role` actor class the fix targets) could clear `legal_hold` itself or null the row's own content with zero trigger interference, then a follow-up `DELETE` succeeded — the identical failure mode `HDN-BLK-020` was meant to close, reached via UPDATE-then-DELETE instead of a bare DELETE. **Fixed this Tier C round** (`supabase/migrations/20260818100000_harden_integrated_verification_tierc_fixes.sql`), widening the trigger to `BEFORE UPDATE OR DELETE`, mirroring the identical fix `HDN-377`'s own Tier C already made once for `app.files` (`ISS-2026-226`). Schema-wide completeness sweep confirmed the legal-hold bridge itself is complete (only 3 tables in the whole schema ever carried a native `legal_hold` column, all 3 now bridged) but found: (a) `HDN-386`'s own first round left 4 MORE `HDN-BLK-nnn` entries it is itself named "Owning lane" for (`016`/`017`/`018`/`019`) with no disposition update at all — the identical procedural-gap shape as the already-caught `HDN-BLK-006` — corrected here with explicit `HDN-387` handoffs mirroring `HDN-BLK-023`/`024`'s own treatment; (b) a real, previously-unregistered, currently-live CI defect — `pnpm-lock.yaml` was out of sync with `package.json` since `HDN-380`'s own commit (`eslint-plugin-jsx-a11y` added but never regenerated into the lockfile's own `importers` block), meaning `pnpm install --frozen-lockfile` has failed outright in CI on every job since, a broader and more severe gap than the 6-step governance cascade the first round described — **fixed this Tier C round** (lockfile regenerated, `frozen-lockfile` re-verified to pass); (c) a factual error in the first round's own headline metric, "34/34 across all 5 Playwright projects" — `playwright.config.ts` defines only 4 projects — corrected everywhere it propagated. Ledger-consistency lens found and fixed the exact stale-tally recurrence described above. No Critical or new-unowned finding survives Tier C. Independent full gate re-run after the fix pass: `typecheck` 0; `lint` 0 errors/337 warnings; `pnpm run test` **5443/5443**; `pnpm exec next build` clean; `pnpm run test:e2e` **34/34**; `bash scripts/db-tests/run.sh` **229/229 files clean** (332 migrations, one additive Tier C migration this round); `pnpm install --frozen-lockfile` verified passing. **`HDN-386` closes `VERIFIED`.** |

`HDN-BLK-001`, `HDN-BLK-007`, `HDN-BLK-013`, `HDN-BLK-016`, `HDN-BLK-017`,
`HDN-BLK-018`, `HDN-BLK-019`, `HDN-BLK-022`, `HDN-BLK-023`, `HDN-BLK-024`,
`HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`,
`HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`,
`HDN-BLK-035`, `HDN-BLK-036`, `HDN-BLK-037`, `HDN-BLK-038` and `HDN-BLK-039`
are open release blockers for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until
fixed by their named owner or explicitly ruled an accepted exception at
`HDN-387`/`389`.

---

## Status as of `HDN-387` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **33** — unchanged this checkpoint; `HDN-387`'s own charter is triage and remediation of the already-open backlog, not new discovery |
| Blockers closed/partially closed **by** `HDN-387`, first round + Tier C | **`RESOLVED`**: `HDN-BLK-023` (Critical — SSO activation gate, Part 1), `HDN-BLK-013` (High — app-layer tenant-ownership checks, TS-only, widened at Tier C to the 8th sibling action `sendTestWebhookDeliveryAction`), `HDN-BLK-019` (High — file_access_logs legal-hold cascade, Part 3), `HDN-BLK-010` (Medium, the narrowed 3-function remainder — race-safe idempotency guard, Part 6, plus `ISS-2026-163`'s own distinct defective-handler fix in the same part), `HDN-BLK-007` (High — the false-positive CI collision-check assertion; fix landed, live CI confirmation still pending, no CI access from this session), `HDN-BLK-039` (High, Tier C — 14 unowned blockers formally accepted under §8.2, real owner `Step 16` assigned). **`PARTIALLY_RESOLVED`**: `HDN-BLK-022` (High — 2 of ~35 tables closed, Part 4; ~33-table remainder stays open, owner `HDN-378`, widened at Tier C with a disclosed RPC-layer addendum), `HDN-BLK-027` (High — the 3 webhook-ingestion alert-wiring producers closed, Part 5; the remaining named producers stay open under `ISS-2026-249`). **`ACCEPTED_EXCEPTION`** (administrative re-ruling only, zero code): `HDN-BLK-006` (Medium — re-ruled under §8.2's full 5-condition test at the correct authority, `HDN-387`, correcting `HDN-379`'s own procedurally-invalid self-acceptance that `HDN-386` had caught and only partially corrected). **Reviewed, not fixed, Tier C** (own-charter entries this checkpoint's own schema-wide completeness sweep lens found silently unaddressed at the first round, corrected with explicit disposition notes rather than left silent): `HDN-BLK-008` (Medium, still `DEFERRED_TO_HDN-387`, a genuine CI-infrastructure design decision), `HDN-BLK-014`'s own residual scope `ISS-2026-186` (Medium, still needs its own 14-function per-call-site audit) |
| — of which **Critical**, open | **0** — `HDN-BLK-023` closed. Zero open Critical blockers anywhere in Step 15 for the first time this session |
| — of which **High**, still open | `HDN-BLK-001`, `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-022` (partial), `HDN-BLK-024`, `HDN-BLK-027` (partial), `HDN-BLK-028..038` (**18**, down from 22 — `HDN-BLK-007`/`013`/`019` closed at the first round, `HDN-BLK-039` closed at Tier C; `HDN-BLK-022`/`027` remain open, only partially closed, and are still counted here, not silently dropped) |
| — of which **Medium**, still open | `HDN-BLK-003`, `004`, `008`, `014`, `025`, `026` (**6**, down from 8 — `HDN-BLK-006` re-ruled `ACCEPTED_EXCEPTION` under the correct §8.2 authority, no longer counted as an open blocker requiring a fix; `HDN-BLK-010`'s narrowed remainder `RESOLVED`; `HDN-BLK-008`/`014` reviewed at Tier C, remain genuinely open with a disposition note, count unchanged) |
| Unresolved **Critical** anywhere | **0** |
| **`HDN-387`'s own charter items — first round** | Selected 7 bounded critical/high repairs from the open backlog per its own charter, all mechanical or mirroring an already-proven pattern: `HDN-BLK-023` (mirrors `app.request_gps_device_status_transition`, `ATW-031`), `HDN-BLK-013` (mirrors the existing `account.tenantId !== access.tenant.id` app-layer idiom), `HDN-BLK-019` (mirrors `HDN-386`'s own `app.audit_logs` legal-hold-bridge-plus-trigger pattern), `HDN-BLK-022` (mirrors `HDN-377`'s own `app.check_procurement_authority`/`ISS-2026-220` fix, first 2-table increment), `HDN-BLK-027` (mirrors `app.record_job_failure`'s own dead-letter alert pattern), `HDN-BLK-010` (mirrors `app.prepare_wms_outbound_from_shipment`'s own "design note 9(a)" pattern, plus `ISS-2026-163`'s own distinct fix), `HDN-BLK-007` (TS-only). `HDN-BLK-006` closed administratively. **3 real defects caught and fixed live before the first-round commit**: a webhook-alert fix that silently reverted 3 later hardening passes (caught by a live `db-tests` failure); a `jsonb`-into-`text` parameter mismatch (caught before any test run); an RLS policy dropped under the wrong name, leaving the real weak policy live (caught by a live probe). Gates: `typecheck` 0; `lint` 0/337 warnings; `pnpm run test` 5444/5444; `next build` clean; `bash scripts/db-tests/run.sh` 230/230 files clean (333 migrations) |
| **`HDN-387`'s own charter items — Tier C** | 4 independent adversarial lenses ran against the pushed first-round state (`e152f4f`). **Correctness re-derivation: clean PASS** — every migration part, TS change, and the CI test fix independently re-derived correct against the actual current schema/code state, all 4 gates independently re-run and matched. **Attack-surface adversarial testing: mostly HELD, one live-demonstrated addendum** — `HDN-BLK-023`/`019`/`027`/`010` all HELD under live attack, several with stronger guarantees than documented (an FK-level `RESTRICT` on `file_access_logs.file_id` independently prevents the exact orphaned-parent scenario the task worried about); `HDN-BLK-022`'s RLS fix itself HELD under every attack, but a `customer_user`-layer actor who also holds a staff role can still read the same data via the pre-existing, unguarded `list_position_grades`/`list_vendor_kpi_scorecards`/2 procurement-dashboard RPCs — not a regression this checkpoint introduced, folded into `ISS-2026-225`'s own still-open ~33-table remainder as a disclosed addendum, owner unchanged `HDN-378`. **Schema-wide completeness sweep: 2 real gaps found and fixed** — (a) 3 own-charter ledger entries (`HDN-BLK-008`, `HDN-BLK-014`'s residual, `HDN-BLK-039`) left with no disposition update at the first round, the identical procedural-gap shape `HDN-386` was itself caught committing one checkpoint earlier for `HDN-BLK-016..019` — corrected with explicit disposition notes; `HDN-BLK-039` (High, 14 unowned blockers) formally accepted under §8.2, real owner `Step 16` assigned, closing `RESOLVED`; (b) a newly-surfaced sibling gap disclosed in `ISS-2026-166`'s own prose (`sendTestWebhookDeliveryAction` sharing `HDN-BLK-013`'s exact unchecked shape) but never registered with a trackable ID — closed directly in the fix pass (genuinely bounded, identical mechanical pattern, same file) rather than minted as a separate finding. **Ledger/documentation consistency: 1 minor gap found and fixed** — `HDN-387.md` §10 omitted `HARDENING_MATRIX.md` from its own documentation-changes list, though the edit itself was accurate; corrected. No Critical or unowned High finding survives Tier C. Independent full gate re-run after the fix pass: `typecheck` 0; `lint` 0 errors/337 warnings; `pnpm run test` **5444/5444** (unchanged — the `sendTestWebhookDeliveryAction` fix has no dedicated test harness, matching this file's own established no-test-file precedent for `admin/api-keys/actions.ts`); `bash scripts/db-tests/run.sh` **230/230 files clean** (333 migrations, unchanged — no schema change at Tier C). **`HDN-387` closes `VERIFIED`.** |

`HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-022`,
`HDN-BLK-024`, `HDN-BLK-025`, `HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`,
`HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031`, `HDN-BLK-032`, `HDN-BLK-033`,
`HDN-BLK-034`, `HDN-BLK-035`, `HDN-BLK-036`, `HDN-BLK-037`, `HDN-BLK-038`,
`HDN-BLK-003`, `HDN-BLK-004`, `HDN-BLK-008` and `HDN-BLK-014`
are open release blockers for Step 16 per `00_EXECUTION_INDEX.md` §8.1 until
fixed by their named owner or explicitly ruled an accepted exception at
`HDN-389`. `HDN-BLK-006`/`039` are `ACCEPTED_EXCEPTION` (re-ruled/ruled at
`HDN-387`) and `HDN-BLK-001`/`007`/`010`/`013`/`019` are `RESOLVED`
(`HDN-BLK-001` at `HDN-388`, the rest at `HDN-387`) — no longer open blockers.

## Status as of `HDN-388` Tier C (live — update at every checkpoint that changes it)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **33** — unchanged this checkpoint; `HDN-388`'s own charter is documentation reconciliation and Step 16 handoff, not new discovery |
| Blockers closed/corrected **by** `HDN-388` | **`RESOLVED`** (ledger-text correction only, zero code): `HDN-BLK-001` (High — its own blocking dependency, `HDN-BLK-023`, closed at `HDN-387`; this entry's text was never revisited, left reading `PARTIALLY RESOLVED`). **`PARTIALLY RESOLVED`, text corrected** (zero code): `HDN-BLK-004` (Medium — `HDN-378` already relocated 2 of 3 extensions and registered `ISS-2026-234` for the genuinely non-relocatable `postgis` remainder; this entry's text was left reading `DEFERRED_TO_HDN-378`/"not yet registered," the identical stale-text shape as `HDN-BLK-001`, both corrected in this same pass). No new findings, no new migration, no code change of any kind this checkpoint — see `HDN-388.md` for the full documentation-handoff scope (runbooks authored/widened, `HARDENING_MATRIX.md` reconciled, `docs/runtime/RELEASE_READINESS_MATRIX.md` authored) |
| — of which **Critical**, open | **0** — unchanged |
| — of which **High**, still open | `HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-022` (partial), `HDN-BLK-024`, `HDN-BLK-027` (partial), `HDN-BLK-028..038` (**17**, down from 18 — `HDN-BLK-001` closed by this checkpoint's own ledger-text correction; `HDN-BLK-022`/`027` remain open, only partially closed, still counted here) |
| — of which **Medium**, still open | `HDN-BLK-003`, `004`, `008`, `014`, `025`, `026` (**6**, unchanged — `HDN-BLK-004`'s text corrected but its own postgis-remainder, `ISS-2026-234`, stays genuinely open, so the tally does not change) |
| Unresolved **Critical** anywhere | **0** |
| **§8.2 disposition gap disclosed, not ruled here** | Of the 17 open High items, 12 (`HDN-BLK-027..038`) were formally ruled `ACCEPTED_EXCEPTION` under §8.2 by `HDN-BLK-039` at `HDN-387` Tier C, owner `Step 16`. **5 remain neither fixed-with-regression-proof nor formally ruled**: `HDN-BLK-016`, `017`, `018`, `022` (partial remainder), `024` — each carries a named prior owner (`HDN-386`, `HDN-378`) whose own checkpoint has since closed `VERIFIED` without making that ruling, and per `00_EXECUTION_INDEX.md` §8.2 condition 5 a ruling may only be made "at `HDN-387` or `HDN-389`," never by the lane that found it and never by this documentation-handoff checkpoint. `HDN-387` is closed; **`HDN-389` is therefore the only remaining authority that can either see these 5 items fixed with regression proof or formally rule them `ACCEPTED_EXCEPTION` before Step 16 eligibility can be reached** (`00_EXECUTION_INDEX.md` §12 condition 4). This gap is not new — it existed identically at `HDN-387`'s own close — but no prior checkpoint's own ledger synthesis stated it this explicitly. Folded into `docs/runtime/RELEASE_READINESS_MATRIX.md`'s own go/no-go section |
| **`HDN-388`'s own charter items — first round** | Documentation-handoff checkpoint: 2 stale ledger-text corrections (`HDN-BLK-001`/`004`, both zero-code); runbook checklist reconciled (`00_EXECUTION_INDEX.md` §11.4 — performance/capacity and on-call-ownership runbooks authored, deployment/migration re-run-guard consolidated, `ISS-2026-262`'s stale catalogue corrected); `HARDENING_MATRIX.md` reconciled with `HDN-386`/`HDN-387` narrative sections and a refreshed gate-index note; `docs/runtime/RELEASE_READINESS_MATRIX.md` authored (did not exist); `docs/runtime/HANDOFF.md` given an explicit Step 16 go/no-go section. See `HDN-388.md` for full disposition |
| **`HDN-388`'s own charter items — Tier C** | 4 independent lenses ran against the pushed first-round state (`b0abb9e`) — attack-surface adversarial testing adapted to claims-testing, since this checkpoint shipped zero code to exploit. **Correctness re-derivation: clean PASS** — every cited figure, tally, and cross-reference independently re-derived against its own source and confirmed accurate. **Claims-testing: 6 of 7 probes HELD**, 1 real narrow finding fixed — `docs/architecture/11_DEVOPS_WORKSTREAM.md` §11's own atomic backlog repeated 6 stale runbook filenames with no pointer to §8.5's own corrective note, a residual "wrong door" risk for a reader who skips §8.5; fixed with a cross-reference note. **Ledger-consistency: 1 real gap found and fixed** — `docs/runtime/RELEASE_READINESS_MATRIX.md`'s own gate-9 arithmetic said "16 runbooks" where its own cited components (14 + 3) sum to 17; corrected. **Schema-wide completeness sweep: found and fixed the identical no-disposition-update shape this checkpoint's own first round already found for `HDN-BLK-001`/`004`, now on 4 more entries and 2 `KNOWN_ISSUES` rows** — `HDN-BLK-003` (Medium) still read `DEFERRED_TO_HDN-378` though `HDN-378` had genuinely re-derived the blast radius and ruled a reasoned re-deferral (`ISS-2026-151`), never mirrored into the ledger; corrected. `HDN-BLK-016`/`017`/`018`/`024` (High) never received their own "Amended at `HDN-387`" disposition note despite being its named recipients, unlike sibling entries `HDN-BLK-008`/`014`/`039`, which did — each given a disclosure-only amendment note, still `OPEN`, folded into the same aggregate 5-item punch list handed to `HDN-389`. `ISS-2026-281` (Medium, `KNOWN_ISSUES.md`, the CI-mirrors-hosted documentation-completeness gap) — `HDN-387` closed without picking it up; not a bounded documentation fix `HDN-388` has standing to attempt (its own real remedy is a positive 13-lane re-derivation); handed to `HDN-389` explicitly, mirroring `HDN-BLK-039`'s own precedent. `ISS-2026-283` (Low, the stale-tally bookkeeping finding itself) — its own stated remedy (hand-recount going forward, not rewrite history) has now been honored correctly twice running (`HDN-387`, `HDN-388`), independently re-verified accurate by this same Tier C's own correctness lens; closed `RESOLVED`. No Critical or new High finding survives Tier C; blocker tally unchanged (0 Critical / 17 High / 6 Medium — none of the Tier C fixes altered a severity or open/closed state, only disposition text). Independent full gate re-run after the fix pass: `typecheck` 0; `lint` 0 errors/337 warnings; `pnpm run test` **5444/5444** (unchanged); `bash scripts/db-tests/run.sh` **230/230 files clean** (333 migrations, unchanged) — every number matches the first round exactly, as expected for a fix pass that touched only 5 documentation files. **`HDN-388` closes `VERIFIED`.** |

## HDN-BLK-040 — the last 5 open High blockers (`HDN-BLK-016`/`017`/`018`/`022`/`024`) formally ruled `ACCEPTED_EXCEPTION` under §8.2, closing Step 15's own blocker backlog

| Field | Value |
|---|---|
| **Title** | Of the 17 open High blockers at `HDN-388`'s close, 12 (`HDN-BLK-027..038`) already carried a formal §8.2 `ACCEPTED_EXCEPTION` ruling from `HDN-387` Tier C (`HDN-BLK-039`). **5 did not**: `HDN-BLK-016` (no reversing GL journal on settlement reversal), `HDN-BLK-017` (hash-chain triggers are standalone fingerprints, not a genuine chain), `HDN-BLK-018` (append-only-guard gap on ~69 remaining tables), `HDN-BLK-022` (RLS/RPC gate gap, ~33-table remainder), `HDN-BLK-024` (step-up-MFA/IP-restriction wiring gap, 61 functions). Each named `HDN-386` as its own owner, was formally handed to `HDN-387` with an exact scope, and `HDN-387` closed `VERIFIED` without either fixing any of the 5 or formally ruling on them — a gap `HDN-388`'s own Tier C found and disclosed explicitly (see each entry's own "Amended at `HDN-388`'s own Tier C" note) but had no standing to rule on itself, since §8.2 condition 5 restricts ruling authority to `HDN-387`/`HDN-389` only |
| **Found by** | `HDN-388` (`CG-S15-HDN-020`), Documentation Handoff, Tier C schema-wide completeness sweep lens — independent full-ledger re-derivation, not a new technical investigation of any of the 5 |
| **Severity** | **High** — matches the severity of the 5 findings it dispositions. All 5 are High-or-below, satisfying §8.2 condition 1 (a Critical may never be accepted; none of these 5 is Critical) |
| **Owning phase** | Cross-cutting (Finance, Data Lineage, RLS/RBAC, Security domains) |
| **Owning lane** | `HDN-389` (Closure Verification) — this is squarely its own charter: item 18 of Prompt 389's own required-verification list requires "every critical/high blocker is fixed with regression proof or explicitly blocks Step 16 with owner/reproduction/resume" before `FULL_SYSTEM_HARDENING_VERIFIED` may be set |
| **Reachability** | N/A — a disposition/accountability ruling, not a live exploit path of its own |
| **Reproduction** | Independent re-derivation: read all 5 underlying entries in full, confirmed each already carries a real, live-forced reproduction, a precise blast-radius measurement, and concrete resume instructions (verified independently by `HDN-389`'s own lens B and lens D, both reporting PASS on reproduction/owner/resume completeness for all 5) — none is a genuinely unowned or undocumented gap, only an unruled one |
| **Blast radius** | Unchanged from each of the 5 entries' own text — this ruling changes accountability disposition only, not the underlying technical scope or risk |
| **Disposition** | **`ACCEPTED_EXCEPTION`, ruled at `HDN-389` under `00_EXECUTION_INDEX.md` §8.2's full 5-condition test, for all 5.** (1) Severity: all 5 are High, below the Critical-never-eligible ceiling. (2) Explicit written ruling: each of the 5 entries' own already-existing text (their own "Required of `HDN-386`"/reproduction/blast-radius fields, none re-litigated here) constitutes the substantive ruling; this entry ratifies acceptance rather than re-deriving new reasoning. (3) Named owner: **`Step 16`** — the post-hardening development phase Step 15 hands off to, mirroring `HDN-BLK-039`'s own identical precedent exactly (no further numbered technical-audit checkpoint exists in this session's own range; `HDN-389` is itself a closure-and-handoff prompt, not a fix lane). (4) Registered in both ledgers: this entry (`BLOCKER_LEDGER.md`) and each of the 5 corresponding `KNOWN_ISSUES.md` rows (`ISS-2026-199`, `200`, `205`, `225`, `236`) carry this disposition as of this ruling. (5) Accepted only at `HDN-387`/`HDN-389`, never the lane that found it: this ruling is made at `HDN-389`, one of the two authorized checkpoints, not by `HDN-386` (which found/registered them) or `HDN-388` (which only disclosed the gap). All 5 conditions satisfied for all 5 blockers |
| **Required of `Step 16`** | Before any Step 16 work touches Finance settlement-reversal, data-lineage tamper-detection, the RLS/RPC gate pattern, or the step-up-MFA/IP-restriction wiring surface, each of the 5's own already-documented "Required of" field (unchanged, not re-derived here) must be satisfied with real regression proof, mirroring exactly how the other 12 `HDN-BLK-027..038` items are already scoped for Step 16's own backlog |
| **Regression test** | N/A — a disposition ruling, not a code fix. Regression proof remains required of whichever future task actually implements each of the 5's own fix, per their own individual entries |
| **Rollback** | N/A — no code fix; this entry is a disclosure/ruling |
| **`KNOWN_ISSUES`** | `ISS-2026-199`, `200`, `205`, `225`, `236` (all `ACCEPTED_EXCEPTION`, High, owner `Step 16`) |

**With this ruling, every open blocker in Step 15's own backlog now satisfies `00_EXECUTION_INDEX.md`
§12 condition 4 ("Zero unresolved Critical. Every High is either fixed with regression proof or
is an accepted exception meeting all five conditions of §8.2") — 0 Critical open, and all 17 open
High items (12 via `HDN-BLK-039`, 5 via this entry) are `ACCEPTED_EXCEPTION`, real owner `Step 16`
for all 17. The 6 open Medium items (`HDN-BLK-003`, `004`, `008`, `014`, `025`, `026`) are below
§12 condition 4's own High-or-above threshold and remain open, individually disclosed, each with
a named owner — condition 4 does not require Medium items to be ruled.**

---

## Status as of `HDN-389` (live — final Step 15 closure state)

| | Count |
|---|---|
| Blockers opened **by** Step 15 to date | **34** — `HDN-389` opened `HDN-BLK-040` (formal §8.2 ruling closing the last 5 unruled High items) |
| Blockers closed/dispositioned **by** `HDN-389` | `HDN-BLK-040` (`ACCEPTED_EXCEPTION`, ruling all 5 of `HDN-BLK-016`/`017`/`018`/`022`/`024`, owner `Step 16`). No new technical fixes, no new migration — a closure-verification checkpoint, not a remediation lane |
| — of which **Critical**, open | **0** — independently re-verified by all 4 of `HDN-389`'s own investigation lenses, entry-by-entry, not from the summary tally alone |
| — of which **High**, still open | **0 unruled.** All 17 open High items now carry a formal §8.2 disposition: 12 via `HDN-BLK-039` (`HDN-387` Tier C), 5 via `HDN-BLK-040` (`HDN-389`, this checkpoint). None is fixed with code — each remains a real, open, disclosed gap — but every one now satisfies `00_EXECUTION_INDEX.md` §12 condition 4's own closure rule |
| — of which **Medium**, still open | `HDN-BLK-003`, `004`, `008`, `014`, `025`, `026` (**6**, unchanged — below §12 condition 4's own threshold, individually disclosed with named owners, not required to be ruled for closure) |
| Unresolved **Critical** anywhere | **0** |
| **`00_EXECUTION_INDEX.md` §12 condition 4 status** | **MET.** Zero unresolved Critical; every High is either fixed with regression proof (`HDN-BLK-001`/`007`/`010`/`013`/`019`, plus the closed portions of `020`/`021`/`023`, all `RESOLVED`) or an accepted exception meeting all 5 conditions of §8.2 (17 of 17 open High items, owner `Step 16` for all) |
| **`HDN-389`'s own charter items** | Closure Verification: 4 independent verification lenses covering all 22 of Prompt 389's own required-verification items — 21 PASS outright (including a fresh, independently-run full db-test suite re-confirmation and a live re-derivation of the "0 Critical" headline from each entry's own Severity/Disposition field, not the summary), 1 (item 18, "every High fixed-or-ruled") PARTIAL pending this checkpoint's own formal ruling, now closed via `HDN-BLK-040`. See `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md` for the full disposition of all 22 items |

**Step 15's own blocker backlog is now fully dispositioned.** Every Critical is fixed. Every High
is either fixed-with-proof or formally accepted with a real owner. No blocker is silently open,
unowned, or undocumented. What remains open (17 High + 6 Medium) is real, disclosed work handed
to `Step 16` and future dedicated tasks — not a hidden risk.

`HDN-BLK-016`, `HDN-BLK-017`, `HDN-BLK-018`, `HDN-BLK-022`, `HDN-BLK-024`, `HDN-BLK-025`,
`HDN-BLK-026`, `HDN-BLK-027`, `HDN-BLK-028`, `HDN-BLK-029`, `HDN-BLK-030`, `HDN-BLK-031`,
`HDN-BLK-032`, `HDN-BLK-033`, `HDN-BLK-034`, `HDN-BLK-035`, `HDN-BLK-036`, `HDN-BLK-037`,
`HDN-BLK-038` are `ACCEPTED_EXCEPTION` (12 ruled at `HDN-387` via `HDN-BLK-039`, 5 ruled at
`HDN-389` via `HDN-BLK-040`), owner `Step 16` for all 17 — no longer open release blockers for
Step 16 eligibility purposes (`00_EXECUTION_INDEX.md` §12 condition 4 is met), though the
underlying technical work remains genuinely unfixed and is Step 16's own inherited backlog.
`HDN-BLK-003`, `HDN-BLK-004`, `HDN-BLK-008` and `HDN-BLK-014` remain open Medium items, below
§12 condition 4's own threshold, each individually disclosed with a named owner.

---

## Reserved

`HDN-BLK-041` onward are unassigned. Every Step 15 finding takes the next free ID and the
full record format of the execution index §14. A finding missing any field is not
registered — and an unregistered finding is not a finding.
