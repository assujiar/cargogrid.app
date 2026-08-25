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

## `RGL-BLK-005` — CI has been red on `main` for at least 30 consecutive runs; the `db` job dies at test file 34 of 230, so 196 database test files have never run in CI

| Field | Value |
|---|---|
| Severity (proposed) | **Critical — release-gate integrity** |
| Status | `OPEN` |
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

## Status summary as of `RGL-391`

| Severity (proposed) | Open | IDs |
|---|---|---|
| Critical | **2** | `RGL-BLK-001`, `RGL-BLK-005` |
| High | **3** | `RGL-BLK-002`, `RGL-BLK-003`, `RGL-BLK-004` |
| Medium | 0 | — |

**No entry above has been ruled on.** `RGL-394` owns binding severity; `RGL-404` and `RGL-412` are
the only acceptance authorities (§8.2 condition 5).
