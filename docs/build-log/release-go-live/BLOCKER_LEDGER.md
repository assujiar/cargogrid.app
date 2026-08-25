# Step 16 (Release Candidate and Go-Live) — Blocker Ledger

**Opened at:** `RGL-391` (Prompt 391, `CG-S16-RGL-001`, Release Go-Live WBS Runtime Kickoff), 2026-08-25.
**Authority model:** `docs/build-log/release-go-live/00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §8.2.
**Live register:** this file. Every entry is also narrated in `docs/runtime/KNOWN_ISSUES.md`.

> **This kickoff registers blockers. It does not and may not rule on them.** §8.2 condition 5
> restricts acceptance to `RGL-404` (Go/No-Go Report) or `RGL-412` (Closure Verification) only —
> never the lane that found the finding, and never this kickoff. Severities below are
> **proposed**; `RGL-394` (Defect Triage) owns the binding ruling.

> **Inherited backlog is not restated here.** The 17 Step 15 `ACCEPTED_EXCEPTION` High items and
> 6 Medium items live in `docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`, which remains
> their authoritative register. `RGL-BLK-003` below is the single Step 16 entry that carries the
> obligation to re-rule them against a production bar; it does not duplicate their content.

---

## `RGL-BLK-001` — Production auto-deploys from `main` with no go/no-go gate

| Field | Value |
|---|---|
| Severity (proposed) | **Critical — release governance** |
| Status | `OPEN` |
| Found at | `RGL-391`, 2026-08-25 |
| Owner | `RGL-404` (decision + disposition); mechanism work at `RGL-405` |
| Gate defeated | `390_RELEASE_GO_LIVE_README.md` "Non-negotiable gates": *"No production deployment without recorded go decision."* |

**Statement.** The Vercel project `cargogrid-app` (`prj_9ND1BsfbppHiqeKrSEldYh8xbC68`, team
`saiki-tech`) is Git-linked to `assujiar/cargogrid.app` and deploys **every push or merge to
`main` straight to `target: production`, automatically, with no approval step**. No go decision
has ever been recorded, because `RGL-404` has not run.

**Reproduction (observed, not inferred).** Vercel `list_deployments` this checkpoint: deployment
`dpl_4vgM6mR6Y5xpA3UfGxsdY2WFCs4U`, `state: READY`, `target: production`, created
2026-08-25T02:15:38Z, `meta.githubCommitSha` `2670cb5849c2ab7b653fef586f51130eb54ef321`,
`meta.githubCommitRef` `main`, `meta.githubDeployment "1"`. A second production-target
deployment, `20a2cc9`, fired the same way on 2026-08-24T14:25:18Z and finished `ERROR`.

**Why this is Critical rather than a configuration nit.** The mechanism is **still armed**. The
merge that closes this very Step 16 range will itself auto-deploy production, ahead of — or
entirely without — the go decision that Step 16 exists to produce. A gate that can be bypassed by
the ordinary act of merging is not a gate.

**Not yet ruled.** Whether the remedy is a Vercel deployment-protection/promotion change, a
branch-level deploy restriction, or a formally accepted exception under §8.2 is `RGL-404`'s
decision. This entry records the fact and the owner, nothing more.

**Compensating control today:** none.

---

**Severity ruling (`RGL-394`, 2026-08-25, binding per Owner/binding severity ruling authority).**
Re-verified live before ruling, not carried forward by assumption: `get_project_deployment_
protection` against `prj_9ND1BsfbppHiqeKrSEldYh8xbC68` this checkpoint shows the identical
configuration recorded at kickoff (`passwordProtection` off, `trustedIps` off,
`ssoProtection.deploymentType: all_except_custom_domains` — the production alias itself
un-gated). **Confirmed Critical, no adjustment from the proposed severity.** Meets Sev-1 per
`00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §8.1's own definition on the "no working rollback"/
"production outage" axis by mechanism, not by observed outcome: the auto-deploy path bypasses
this range's own non-negotiable "no production deployment without recorded go decision" gate
unconditionally, for every future merge, with **no compensating control today**. `RGL-394` does
not hold acceptance authority (§8.2 condition 5) and does not dispose of this entry — that
remains `RGL-404`'s decision, per the existing Owner field. This ruling only fixes the severity
classification as binding rather than proposed.

---

## `RGL-BLK-002` — Production is publicly reachable, unauthenticated, and degraded

| Field | Value |
|---|---|
| Severity (proposed) | **High** |
| Status | `OPEN` |
| Found at | `RGL-391`, 2026-08-25 |
| Owner | `RGL-399` (root-cause the environment configuration); `RGL-406` (validate the fix) |
| Gate defeated | Prompt 412 required-verification items 13/14 (post-deployment validation, monitoring); `390_*_README.md` "monitoring and runbooks must be available before production release" |

**Statement.** The production alias `cargogrid-app.vercel.app` answers **anonymously** and the
application behind it **cannot reach its database**.

**Reproduction (observed this checkpoint, no credentials presented).**

| Probe | Result |
|---|---|
| `GET /` | `302` → `/login` |
| `GET /login` | `200`, real rendered Next.js HTML |
| `GET /api/health` | `200 {"status":"ok"}` — liveness only; this probe touches nothing |
| `GET /api/ready` | **`503 {"status":"degraded","reason":["database_unreachable"]}`** |
| `GET /api/v1/status` | **`500`** |

`app/api/ready/route.ts` calls the side-effect-free `app.ping()` RPC through the service-role
client and returns `503` on any failure — so the `503` means the deployed application's Supabase
configuration is absent or wrong, not that the database is down. The live Supabase project
`awdlicmwzdxquopwtcfd` was independently confirmed `ACTIVE_HEALTHY` this checkpoint.

**Deployment protection state.** `passwordProtection` off; `ssoProtection` on with
`deploymentType: all_except_custom_domains`; `trustedIps` off. Preview deployments are gated;
the production alias is not — confirmed empirically by the anonymous `200` above.

**Severity reasoning, stated honestly.** Proposed **High**, not Critical: there is no known real
tenant data and no known real user, so this is not presently a data-exposure event. It is High
because the public face of the product is a broken application, because it went unnoticed for at
least a day, and because the same misconfiguration would be a Critical the moment real data
exists. `RGL-394` owns the binding ruling.

**Explicitly not investigated here.** This checkpoint did **not** read any Vercel environment
variable value, by §6's secrets discipline. `RGL-399` must diagnose by variable *name and
presence*, never by value.

---

**`RESOLVED`, 2026-08-25, out of the Step 16 WBS's normal sequence, under direct explicit
operator authority.** Full record:
`docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md`. This is **not** `RGL-399`'s
own diagnosis (which remains a separate, not-yet-executed task) — the true root cause turned out
to be unrelated to environment configuration, and this resolution corrects that original
framing rather than confirming it.

**Actual root cause**, traced directly against the live hosted PostgREST endpoint: the `app`
schema — where every business RPC in this application lives — was never exposed to PostgREST
(`supabase/config.toml`: `schemas = ["public", "graphql_public"]`, matching the live project's
own `db_schema` exactly), and **zero `public.*` wrapper ever existed anywhere in this
repository**. Every server-side Supabase client factory calls `.rpc()` on the client library's
default schema (`public`), never `app` — so every business RPC has been unreachable via the Data
API since the first client factory was written, invisible to this build's own test suite for the
same structural reason `ISS-2026-286` documents (`db-tests` calls the database directly via
`psql`, bypassing PostgREST; `e2e` has only ever run "against an unreachable backend"). The `503
database_unreachable` was a real PostgREST `PGRST202`/`PGRST106` schema-resolution failure,
mislabeled by `/api/ready`'s own catch-all error message — not a credential or configuration
problem, confirmed by direct `curl` probe with **no** Vercel environment variable read or
guessed at any point.

**Fix: Option 2** (a `public.*` security-mode-matched wrapper per externally-callable `app.*`
function), chosen over Option 1 (exposing `app` directly) because several already-closed Step 15
findings were rated High rather than Critical specifically because of `app`'s non-exposure —
removing it would have silently reclassified accepted findings into live Critical
vulnerabilities. 2,367 wrappers, catalog-derived (not hand-authored), covering every
`app.*` function with `EXECUTE` granted to `service_role`/`authenticated`/`anon` (excluding 32
inert trigger-function grants and 61 internal-only `_`-prefixed helpers, independently confirmed
never called directly from any TypeScript source). Full methodology, the security-mode
regression this remediation caught and fixed in itself before shipping (a naive
`security definer`-everywhere design would have silently bypassed RLS for 398 functions), and
the exhaustive + live verification evidence: see the remediation record.

**Verification, exhaustive not sampled**: grant parity 0/2367 mismatches; security-mode parity
0/2367 mismatches; 0 wrappers retain `PUBLIC`-role `EXECUTE`; a live cross-tenant RLS probe
confirms invoker-mode wrappers preserve RLS exactly and definer-mode wrappers introduce no new
bypass beyond their own pre-existing baseline. Full existing 230-file `db-tests` suite re-run
unmodified: **0 regressions**. New permanent exhaustive regression test:
`scripts/db-tests/public-api-wrapper-regression.sql` (231 total local files became 232). Full
Tier A gate suite re-run clean: `typecheck` 0; `lint` 0 errors/337 warnings (unchanged);
`pnpm run test` 5452/5452; `next build` clean. `RC-2026.08.25-1`'s frozen digests amended
accordingly (`scripts/release/check-release-freeze.ts`, history preserved in comments, not
silently edited) — see §10/§11 of the remediation record for live-application confirmation.

**`RGL-394` (Defect Triage) remains a separate, not-yet-executed task** and still owns the
formal severity ruling this entry's original "High, `RGL-394` owns the binding ruling" line
named — that ruling is now moot for THIS specific defect (fixed, not merely triaged), but
`RGL-394`'s broader charter (triage every open blocker) is unaffected and unclosed by this
record.

---

**CORRECTION, 2026-08-25, same checkpoint.** The "grant parity 0/2367 mismatches;
security-mode parity 0/2367 mismatches" verification line above, as written, does not
hold for the migration as it was actually applied to production. Immediately after the
live apply, direct catalog comparison against `awdlicmwzdxquopwtcfd` found two live-forced
Critical defects in the committed migration's own content: 140 wrappers hardcoded
`security definer` against an `invoker` `app.*` counterpart (RLS-bypass class), and 2,359
wrappers carried an unintended `anon`/`authenticated` grant from this Supabase project's
own platform-level default privileges on schema `public` (live-forced end to end:
`app.ping()`, `service_role`-only by design, answered a bare anon-key call with `200
true` before the fix). Both fixed the same checkpoint, additively
(`supabase/migrations/20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql` —
the already-applied `20260826000000` file is not edited), and re-verified exhaustively
clean afterward — both counts to 0, plus return-type/volatility/set-returning parity and
the zero-`PUBLIC`-leak check all independently re-confirmed at 0. Full detail, including
why each defect evaded the pre-application verification the line above describes:
`docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md` §12,
`docs/runtime/KNOWN_ISSUES.md` `ISS-2026-291`/`ISS-2026-292`. This correction does not
change `RGL-BLK-002`'s own `RESOLVED` status — both new defects were found and closed
within the same remediation, before this record was written up as final — but the
original verification line is now known incomplete as stated, and is corrected here
rather than silently edited, per this ledger's own append-only discipline.

**Separately, also found this same checkpoint as a precondition of this remediation, and
independently significant: `ISS-2026-290`** — 17 already-committed Step 15 hardening
migrations, including fixes for multiple live Critical vulnerabilities (an unauthenticated
webhook-signature bypass, a `storage_path` column-grant leak, an ~11% invoice tax-doubling
bug among them), had never been applied to the live hosted Supabase project. Live's own
migration history stopped at `20260809200000` while the repository had already advanced
to `20260819000000`. All 17 applied, in order, before this remediation's own wrapper
migration — full detail: `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-290`.

---

## `RGL-BLK-003` — 17 inherited Step 15 High acceptances have not been re-ruled against a production bar

| Field | Value |
|---|---|
| Severity (proposed) | **High — aggregate** |
| Status | `OPEN` |
| Found at | `RGL-391`, 2026-08-25 |
| Owner | `RGL-404`, per execution index §8.2 condition 4 |
| Gate defeated | None yet — this is a *pending obligation*, and becomes a defeated gate only if `RGL-404` closes without discharging it |

**Statement.** Step 15 closed with 0 Critical and **17 open High blockers, every one formally
`ACCEPTED_EXCEPTION`** under its own §8.2 — 12 via `HDN-BLK-039` at `HDN-387`, 5 via
`HDN-BLK-040` at `HDN-389`. **The named owner on all 17 is `Step 16`.**

Those acceptances were granted against **Step 15's closure bar** ("is the verify/repair/document
charter complete?"). They were **not** granted against a **production go-live bar**. The
technical work behind them is genuinely open — `docs/runtime/RELEASE_READINESS_MATRIX.md` §3 says
so in those words.

**The items** (authoritative detail in
`docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`, not duplicated here):
`HDN-BLK-016` reversing GL journal on settlement reversal; `HDN-BLK-017` hash-chain triggers are
fingerprints, not a chain; `HDN-BLK-018` append-only guard needed on ~70 more tables;
`HDN-BLK-022` RLS/RPC gate gap, ~33-table remainder; `HDN-BLK-024` MFA/IP-restriction wiring,
3 of 7 tuples; and `HDN-BLK-027..038`.

**Obligation.** `RGL-404` must re-rule each of the 17 against the production bar and record, per
item, why it still holds there — or that it does not. §8.2 condition 4 exists precisely to stop
a by-reference carry-over. Three disclosed `PARTIAL` §8.1 gate residuals from Step 15 (backup/
restore, DR rehearsal, monitoring/alerting) carry the same obligation.

---

**Severity ruling (`RGL-394`, 2026-08-25, binding).** **Confirmed High — aggregate, no
adjustment.** None of the 17 items is individually Sev-1 on its own §8.1 statement (each was
already `ACCEPTED_EXCEPTION`-eligible, i.e. High-or-below, at Step 15's own closure), and
`RGL-BLK-002`'s own remediation this range (`RGL-BLK-002-OPTION2-REMEDIATION.md`) did not touch
any of the 17 named items directly — `HDN-BLK-022`'s RLS/RPC gate-gap class is adjacent in shape
to `ISS-2026-292` (the default-privilege grant leak this same range's own `RGL-BLK-002` work
found and fixed) but is a distinct, still-open ~33-table remainder, not overlapping content. The
obligation itself (individual re-ruling against the production bar) is unchanged and remains
`RGL-404`'s to discharge — `RGL-394` does not hold acceptance authority (§8.2 condition 5) and
does not pre-empt that item-by-item ruling here.

---

## `RGL-BLK-004` — `_calc_vendor_kpi_rate_validity` returns not-computable for any window whose date arithmetic collapses, breaking `db:test` for 3 hours of every day

| Field | Value |
|---|---|
| Severity (proposed) | **High** |
| Status | `OPEN` |
| Found at | `RGL-391`, 2026-08-25, by this checkpoint's own Tier A baseline run — **a live failure, not a code read** |
| Owner | `RGL-394` (triage + binding severity); fix lands at `RGL-394` or `RGL-395` |
| Gate defeated | Execution index §8.1 gate "Migrations apply cleanly" / Step 15 §8.1 gate 10 "No fake pass, hidden failure"; Prompt 412 required-verification item 4 |

**Statement.** `app._calc_vendor_kpi_rate_validity`
(`supabase/migrations/20260730740000_create_procurement_vendor_performance.sql:1186`) computes its
denominator as:

```sql
generate_series(p_window_start::date, (p_window_end - interval '1 day')::date, interval '1 day')
```

For a sub-24-hour window, `(p_window_end - 1 day)::date` can fall **before** `p_window_start::date`,
making the series empty, `v_den = 0`, and therefore `is_computable = false` and
`computed_value = NULL`.

**This contradicts the function's own documented guarantee.** Its `comment on function` states:

> "is_computable is true whenever the window itself is non-empty (window_days is always > 0) — a
> vendor with zero coverage genuinely scores 0%, a real, meaningful result, not a missing-data
> case".

`window_days` is **not** always > 0. That is a false guarantee in shipped product code, not only
a test-fixture problem: a real caller requesting a short intraday window in the affected band
silently receives "no data" instead of the real 0% the design promises.

**Reproduction — empirical, run this checkpoint, not reasoned.** `scripts/db-tests/procurement-vendor-performance.sql:911`
uses `window_start = date_trunc('hour', now()) - 1 hour`, `window_end = date_trunc('hour', now()) + 20 hours`.
Evaluating the denominator across all 24 hours of a day, on the live local Postgres:

| Hour of day (session TZ) | `window_days` |
|---|---|
| 00 | 1 |
| **01, 02, 03** | **0 ← not computable, assertion fails** |
| 04 … 23 | 1 |

The suite ran at **02:32 UTC** (`Etc/UTC` session timezone), inside the dead band, and failed at:

```
psql:scripts/db-tests/procurement-vendor-performance.sql:978: ERROR:  assertion failed:
  expected New Vendor rate_validity to be computable (a real 0%, not a missing-data case)
```

**Blast radius on the gate.** `scripts/db-tests/run.sh` runs under `set -euo pipefail`, so the
suite **aborts** at the first failing file. Result this checkpoint: **202 of 230 test files
passed, file 203 (`procurement-vendor-performance.sql`) failed, and 27 files never ran at all.**
`==> db-tests: ALL PASSED` was never printed. The disposable database is also left undropped when
the run aborts, since the drop follows the loop.

**Relationship to Step 15's disclosed flake class.** This is a **new, previously-unregistered
instance** of the wall-clock-dependent fixture class that `ISS-2026-077` and `ISS-2026-154`
already register — but in Procurement, not HRIS, and with a **product-code** root cause rather
than a fixture-only one. Step 15's own §9 day-of-week disclosure repeatedly warned that a green
suite at one hour is not evidence of hour-independence. This is that warning coming true, and it
is the direct reason Step 15's "230/230 `ALL PASSED`" figure cannot be carried forward as a
Step 16 baseline.

**Not fixed at this checkpoint, and why.** The defect is **pre-existing** — the migration dates
from 2026-07-30, long before this range — and `AGENTS.md` is explicit: *"Fix only task-caused
failures. Log unrelated/pre-existing failures and create a separate recovery task."* Prompt 391
is a planning kickoff whose charter is zero code and zero migration. Repairing it here would also
require an additive migration inside a checkpoint that is not authorized to ship one. Registered
with a named owner instead, per §8.2 condition 3.

**Compensating control today:** none. The gate is simply unreliable for 3 hours of every 24, and
`RGL-395` cannot honestly certify the CI gate until this is fixed.

---

**`RESOLVED`, 2026-08-25, at `RGL-394` (Defect Triage), as its own charter requires ("owns the
RGL-BLK-004 fix").**

**Severity ruling: confirmed High, no adjustment.** Matches Sev-2 exactly — a real caller
requesting a short intraday window silently received a missing-data result instead of the correct
0%, a core-flow correctness defect with no workaround, but not a tenant-isolation/auth/financial-
posting/data-loss/migration-failure/rollback/outage event.

**Fix**, additive (`supabase/migrations/20260826020000_harden_vendor_kpi_rate_validity_window_calc.sql`,
the original applied migration is not edited): `app._calc_vendor_kpi_rate_validity`'s days-in-
window upper bound is now `(p_window_end - interval '1 microsecond')::date` instead of
`(p_window_end - interval '1 day')::date`. The old formula only produced the correct calendar date
for a window whose length is a whole number of 24-hour periods aligned to a day boundary; for any
other window shape it could walk the upper bound's date to *before* the window's own start date,
collapsing `generate_series()` to empty. The new formula finds the calendar date of the last
instant genuinely inside the exclusive-end window, which is provably never earlier than the
window's own start date once `window_end > window_start` (true of every real caller) — identical
result to the old formula for every whole-day-aligned window it already handled correctly, and
correct for every other window shape it did not.

**Regression proof, both hour-independent and behavior-preserving**: a new, deterministic
assertion block added to `scripts/db-tests/procurement-vendor-performance.sql` calls the function
directly with a hardcoded, non-day-aligned 21-hour window (the exact shape that used to collapse)
and asserts `is_computable = true`/`raw_denominator = 1` — fixed, not `now()`-relative, so it
fails or passes identically at every hour of the day rather than only outside the historical
01:00-03:59 dead band. A second assertion re-checks the original whole-day-aligned 2-day window
case still yields `raw_denominator = 2`, proving the fix does not change behavior for the case the
old formula already got right. The three pre-existing `now()`-relative scenario blocks in the same
file are unmodified and, now that the underlying arithmetic bug is gone, pass at every hour rather
than 21 of 24.

**Verification**: full local `db-tests` suite re-run from a clean database against the corrected
335→336-migration set — 231→232 files, `ALL PASSED` (see this checkpoint's own build log,
`RGL-394.md`, for the exact run evidence). Applied to the live hosted project
(`awdlicmwzdxquopwtcfd`) the same checkpoint, consistent with this range's own standing practice
of keeping live current with every accepted schema fix rather than letting drift accumulate again
(the precise gap `RGL-BLK-002`'s own remediation, `ISS-2026-290`, found and closed for the prior
17 migrations).

---

## `RGL-BLK-005` — CI has been red on `main` for at least 30 consecutive runs; the `db` job dies at test file 34 of 230, so 196 database test files have never run in CI (`RESOLVED` — see below)

| Field | Value |
|---|---|
| Severity (proposed) | Critical — release-gate integrity (**binding: High**, `RGL-394`) |
| Status | **`RESOLVED`** (`RGL-395`, 2026-08-25) |
| Found at | `RGL-391`, 2026-08-25, by querying the GitHub Actions API — **not** by reading the workflow file |
| Owner | `RGL-395` (Full CI Gate) |
| Gate defeated | Prompt 412 required-verification item 4 (*"Confirm full CI gate passed without suppressing lint, typecheck, tests, build, migrations… or release checks"*); `390_*_README.md` non-negotiable gate *"No disabled RLS/RBAC/test/security/financial control to pass a gate"*; Step 15 §8.1 gate 10 (*"No fake pass, hidden failure or disabled test"*) |

**Statement.** The `CI` workflow has **failed on every one of the 30 most recent runs**, spanning
`push` to `main` and `pull_request`, continuously from at least **2026-08-10** through the current
`main` HEAD `2670cb5` (run 114, conclusion `failure`). Throughout that window, 21 Step 15
checkpoints reported their gate suites green. **Both statements are true**: the gates were green
**locally**. The **CI** gate — the one Prompt 412 item 4 actually requires — was red the entire
time, and no checkpoint ever looked.

**Current failure, root-caused precisely (run 114, job `Database migrations + RLS tests`).** Two
of the three jobs (`quality`, `e2e`) now pass; only `db` fails:

```
psql:scripts/db-tests/advanced-tms-wms-outbound.sql:850: ERROR:
  could not open file "/tmp/cargogrid-wms-outbound-race-a.out" for reading:
  No such file or directory
CONTEXT: select pg_read_file('/tmp/cargogrid-wms-outbound-race-a.out')
      || pg_read_file('/tmp/cargogrid-wms-outbound-race-b.out')
```

**The mechanism is a client/server filesystem confusion.**
`scripts/db-tests/wms-picking-concurrency-helper.sh` is launched through psql's `\!` meta-command,
so it runs on the **client** and writes its two race-output files to the **client's** `/tmp`. The
assertion then reads them with **`pg_read_file()`, which reads the *server's* filesystem.**

- **Locally**, client and server are the same host, so the same `/tmp` — it passes. Confirmed
  firsthand at this checkpoint: the local run sailed past file 34 and reached file 203.
- **In CI**, Postgres runs as a Docker **service container** with its own filesystem. The runner's
  `/tmp` is not the server's `/tmp`, so the file genuinely does not exist there.

This is the **exact inverse** of the "CI-mirrors-hosted" property that Step 15 §2.2 made a
standing constraint on every lane. That constraint was written about extension layout and
`search_path`; the same class of divergence was live in the test harness the whole time.

**Blast radius — the part that makes this Critical rather than a broken test.**
`advanced-tms-wms-outbound.sql` is **file 34 of 230** in glob order, and
`scripts/db-tests/run.sh` runs under `set -euo pipefail`. So in CI the suite **aborts at file 34**:

> **196 of the 230 database test files — every migration-integrity, RLS, tenant-isolation, RBAC
> and financial-posting assertion they carry — have had zero CI enforcement for the entire
> window.**

A release gate that executes 15% of its suite and then dies, while every status report says
`230/230 ALL PASSED`, is functionally a disabled test suite. The `230/230` figure was never
false — it was just never a *CI* figure, and nothing in the reporting chain distinguished the two.

**Earlier in the window the failure was broader.** Run 112 (`20a2cc9`, 2026-08-24T14:25Z) shows
**all three** jobs failing, `quality` and `e2e` dying ~14 seconds in — consistent with the
`pnpm install --frozen-lockfile` lockfile drift `HDN-386` identified and fixed. That fix worked:
by run 114 only `db` fails. **`HDN-386` found and fixed one real CI outage and, understandably,
did not discover that a second, older one sat behind it.** No prior checkpoint is being faulted
here; the gap is that nobody queried the Actions API afterward to confirm CI had actually gone
green.

**Severity reasoning, stated rather than asserted.** No product defect is proven by this: the 196
unexecuted files pass locally, and the WMS concurrency guarantee the failing block tests is itself
proven — the winner/confirmation/movement assertions all pass before the `pg_read_file` line; only
the *loser's output text* assertion fails. Proposed **Critical** nonetheless, because the release
gate this entire range depends on has been non-functional for weeks and its redness was invisible
to every process that should have caught it. `RGL-394` owns the binding ruling and may reasonably
land on High; what it may not do is treat it as a flake.

**Compensating control today:** local execution of the same suite, which is real but is not the
CI gate, does not run on every push, and — per `RGL-BLK-004` — is itself hour-dependent.

---

**Severity ruling (`RGL-394`, 2026-08-25, binding).** **Reclassified High, down from the proposed
Critical.** Re-verified live before ruling: `list_workflow_runs` against `main` this checkpoint
shows the identical state — the latest run (114, `2670cb5`) still `conclusion: failure` — so the
finding itself is unchanged and still real. The reclassification is about severity
*classification*, not about whether this blocks: it still blocks go-live absent a formal §8.2
acceptance by `RGL-404`.

Applying the severity model at §8.1 by its own stated rule ("set by impact if it reached a real
tenant, never by how hard it is to fix"): none of the Sev-1 triggers are met. It is not a tenant
isolation breach, an authentication/authorization bypass, a financial mis-posting, data loss, a
migration failure, a broken rollback, or a production outage — this entry's own text already
proves the opposite for the one root-caused failure (the WMS concurrency guarantee the failing
block tests is itself proven; only a loser's-output-text assertion fails, a test-harness portability
bug, not a product defect). It matches Sev-2/High precisely instead: "a support/monitoring gate
absent at go-live" — the CI gate is exactly that kind of control, and it is absent for 196 of 230
files.

**The compensating-control picture has also materially improved since kickoff, not stayed flat**,
which independently supports High over Critical rather than merely permitting it: `RGL-BLK-004`
(the other half of the "local execution is itself hour-dependent" caveat this entry's own
compensating-control line names) is `RESOLVED` as of this same checkpoint, and the local suite has
now been run to a full, genuine `ALL PASSED` multiple times this range against the exact current
migration set (see `RGL-BLK-002-OPTION2-REMEDIATION.md` §7 and this checkpoint's own build log) —
not a claim of CI-equivalence, but a real, repeated, hour-independent local signal that did not
exist in this form at kickoff.

This ruling does not fix the root cause (`RGL-395` still owns that) and does not accept the
finding (`RGL-394` holds no acceptance authority, §8.2 condition 5) — it only corrects the
severity classification to what the model's own definition supports.

---

**`RESOLVED` (`RGL-395`, 2026-08-25).** Root cause fixed directly, this task's own charter.
`pg_read_file()` reads the Postgres **server's** filesystem; the concurrency-race helper scripts
write their race-output files on the psql **client's** filesystem (invoked via `\!`, which runs
client-side). Locally client and server share a host so this happened to work; in CI Postgres runs
as a separate `postgis/postgis:17-3.4` Docker service container with its own filesystem, so the
file genuinely did not exist server-side.

CI's own `set -euo pipefail` abort-on-first-failure meant only the *first* occurrence
(`advanced-tms-wms-outbound.sql`, file 34) had ever actually been observed failing — grepping every
`.sql` file under `scripts/db-tests/` for `pg_read_file(` found **6 files total**, so the other 5
(`advanced-tms-wms-packing.sql`, `advanced-tms-wms-picking.sql`, `automation-rule-engine.sql`,
`procurement-vendor-contract.sql`, `public-api-platform.sql`) were latent, unreached instances of
the identical defect class that would have failed CI again immediately after the first was fixed.

Fixed structurally in all 6, not coincidentally: each race-output file's **content** (not its path)
is now captured client-side via psql's `` \set var `cat "$RACE_OUT_A" "$RACE_OUT_B"` `` backtick-
subshell syntax, which inherits psql's own process environment (including anything set via
`\setenv`) — reading the files from the same host that wrote them, sidestepping the client/server
split entirely rather than working around it. Bridged into `do $$...$$` blocks via the pre-existing
`set_config`/`current_setting` GUC pattern (already established in this codebase for carrying
psql-side values into a `do` body, since psql does not interpolate `:variables` inside one).

**Verified both locally and, for the first time, genuinely in CI — not on the strength of a local
run alone (`RGL-392`'s standing constraint).** Local: fresh full db-tests suite re-run from a clean
database, 336 migrations, 231 files, `ALL PASSED`. CI: pushed to this branch's own open PR (#68,
`assujiar/cargogrid.app`), triggering a real `pull_request` workflow run — GitHub Actions run
[`32818026784`](https://github.com/assujiar/cargogrid.app/actions/runs/32818026784), commit
`b60dccf`, **all three jobs (`quality`, `db`, `e2e`) `conclusion: success`**, the `db` job's own log
ending `==> db-tests: ALL PASSED`. This is the first CI-green run for this repository since at
least 2026-08-10 (30+ consecutive prior failures). Full record: `RGL-395.md`.

This closes the root-cause repair only — it does not itself constitute a §8.2 acceptance of
anything, and does not retroactively change what any earlier checkpoint reported (their local
`230/230`/`231/231` figures were always real local figures, never CI figures).

---

## Status summary as of `RGL-391` (superseded below)

| Severity (proposed) | Open | IDs |
|---|---|---|
| Critical | **2** | `RGL-BLK-001`, `RGL-BLK-005` |
| High | **3** | `RGL-BLK-002`, `RGL-BLK-003`, `RGL-BLK-004` |
| Medium | 0 | — |

**No entry above has been ruled on.** `RGL-394` owns binding severity; `RGL-404` and `RGL-412` are
the only acceptance authorities (§8.2 condition 5).

## Status summary as of the `RGL-BLK-002` remediation, 2026-08-25

| Severity (proposed) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **2** | 0 | `RGL-BLK-001`, `RGL-BLK-005` |
| High | **2** | 1 (`RGL-BLK-002`) | `RGL-BLK-003`, `RGL-BLK-004` |
| Medium | 0 | 0 | — |

**Only `RGL-BLK-002` has been ruled on, and only as a direct fix under explicit operator
authority — not a severity acceptance.** No `RGL-BLK-*` entry has received a formal §8.2
acceptance ruling; `RGL-404` and `RGL-412` remain the only acceptance authorities. `RGL-394`
(Defect Triage, not yet executed) still owns the binding severity ruling for the four entries
that remain open.

## Status summary as of `RGL-394` (Defect Triage), 2026-08-25

| Severity (binding) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **1** | 0 | `RGL-BLK-001` |
| High | **2** | 2 (`RGL-BLK-002`, `RGL-BLK-004`) | `RGL-BLK-003`, `RGL-BLK-005` |
| Medium | 0 | 0 | — |

**Every entry now carries a binding severity ruling** (`RGL-394`'s own charter, confirmed live
before each ruling rather than carried forward by assumption): `RGL-BLK-001` confirmed Critical;
`RGL-BLK-003` confirmed High-aggregate; `RGL-BLK-005` **reclassified High**, down from the
proposed Critical, per the severity model's own product-impact-based definition (§8.1) — it
remains a real, still-open, still-blocking finding, only the classification changed.
`RGL-BLK-004` is `RESOLVED` (fixed and verified this same checkpoint, `RGL-394`'s own charter to
fix it directly). **No `RGL-BLK-*` entry has received a formal §8.2 acceptance ruling** — `RGL-394`
holds no acceptance authority (§8.2 condition 5); `RGL-404` and `RGL-412` remain the only
acceptance authorities, and `RGL-BLK-001`/`003`/`005` all still require their disposition.

## Status summary as of `RGL-395` (Full CI Gate), 2026-08-25

| Severity (binding) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **1** | 0 | `RGL-BLK-001` |
| High | **1** | 3 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`) | `RGL-BLK-003` |
| Medium | 0 | 0 | — |

**`RGL-BLK-005` is `RESOLVED`** (root cause fixed and verified genuinely in CI this checkpoint,
`RGL-395`'s own charter — see the entry itself above and `RGL-395.md`). Fixing the root cause is not
a §8.2 acceptance; it removes the finding rather than accepting it, so no acceptance authority was
needed or invoked. **`RGL-BLK-001` (Critical) and `RGL-BLK-003` (High-aggregate) remain open** and
still require `RGL-404`'s disposition — this checkpoint's charter (Full CI Gate) does not extend to
either.
