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

**Disposition ruling (`RGL-404`, Go/No-Go Report, 2026-08-25, the only authority §8.2 condition 5
permits to accept or reject this entry).** **NOT ACCEPTED. Remains `OPEN`, Critical, blocking.**

Re-verified live before ruling, not carried forward: `get_project_deployment_protection` against
`prj_9ND1BsfbppHiqeKrSEldYh8xbC68` this checkpoint shows the **identical** configuration recorded
at kickoff and at `RGL-394`'s own re-check — `passwordProtection` off, `trustedIps` off,
`ssoProtection.deploymentType: all_except_custom_domains` (the production alias itself still
un-gated). `get_commit` against `main` confirms it is still at `2670cb5` (the same commit recorded
at kickoff) — this entire Step 16 range's own work has not yet been merged, so the mechanism has
not fired again since kickoff, but remains **fully armed** for the merge that closes this range.
`list_branches` re-confirms `protected: false` on sampled branches, unchanged from `RGL-393`'s own
audit.

Per `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §8.1: **"Sev-1/Critical... Absolute no-go. Never
accepted, never risk-accepted, at any authority."** This is not a judgment call — the definition
is unconditional. A Critical, open, unmitigated finding cannot be waved through by any ruling this
checkpoint or any other could issue. **This alone is sufficient to force `NO_GO` for this
checkpoint** — see `RGL-404.md`/`GO_NO_GO_REPORT.md` for the full decision record — independent of
every other finding's own disposition below.

**What would change this ruling.** The mechanism itself must be fixed — GitHub branch protection
on `main` requiring a status check/review before merge, and/or Vercel deployment-protection
configured to gate the production target on an explicit promotion step — before any future
`RGL-404` re-run could rule differently. This is infrastructure/governance configuration work,
named `RGL-405`'s own charter per this entry's Owner field, but `RGL-405` is itself gated on `14`
(this checkpoint) in the WBS — so under a `NO_GO` verdict, `RGL-405` does not run, and fixing this
mechanism requires either a future `RGL-404` re-run explicitly scoped to unblock it, or direct
operator action outside this agent-run pipeline. **Escalated to the operator** — see this
session's own end-of-turn report.

---

**OPERATOR RISK ACCEPTANCE, 2026-08-25, same checkpoint — status changed from `OPEN` to
`ACCEPTED (operator override)`.** Following the disposition ruling above and its own escalation
to the operator, the actual human operator of this build (not an in-pipeline `RGL-404`/`RGL-412`
ruling — a party outside and above that simulated authority chain entirely) gave a direct,
explicit instruction in this session: *"yg auto deploy gapapa ke production itu, gausa dijadiin
blocking"* — "the auto-deploy to production thing is fine, don't make it blocking."

**Recorded honestly, not fabricated as §8.2-compliant.** §8.1 states Critical findings are
*"Never accepted, never risk-accepted, at any authority"* — that sentence is this framework's own
policy, written by this same pipeline to bind rulings issued **within** it (`RGL-394`'s severity
ruling, `RGL-404`'s disposition ruling above). It does not, and cannot, bind the actual human
principal who commissions this entire build and who has real authority over the real GitHub
repository and the real Vercel project this finding concerns — that authority precedes and is
senior to any rule this pipeline writes about itself. This entry does not pretend the operator's
instruction is an `RGL-404` ruling that satisfies §8.2's five conditions (it plainly does not
attempt condition 2's "considered and rejected" analysis, because the operator did not need to
justify the decision to this pipeline) — it is a distinct, out-of-band override, and is recorded
as exactly that.

**What is actually being accepted, stated plainly so the record does not understate it.** The
production auto-deploy mechanism remains fully armed and unfixed: any push or merge to `main`
still deploys straight to `target: production` with no approval step, no branch protection, and
no deployment-promotion gate — nothing about the underlying mechanism in §"Reproduction" above has
changed. What has changed is that the actual product owner has weighed that risk directly and
decided it is acceptable for this release, superseding this pipeline's own more conservative
default policy for Critical items.

**Effect on this checkpoint's verdict.** `RGL-BLK-001` no longer independently forces `NO_GO`.
See the updated status summary below and `GO_NO_GO_REPORT.md`'s own addendum for whether any other
open item still does.

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

**Disposition ruling (`RGL-404`, Go/No-Go Report, 2026-08-25) — the item-by-item re-ruling §8.2
condition 4 and this entry's own "Obligation" field require.** Each of the 17 read in full
(`docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`), re-examined against a production bar
rather than Step 15's own closure bar, not carried forward by reference.

**Two items do not clear a production bar as currently disclosed — escalated, not silently
re-accepted:**

- **`HDN-BLK-016`** (`app.request_finance_settlement_reversal` posts no reversing GL journal —
  live-forced, permanent, unbounded GL/AP desync on **every** settlement reversal, reachable by
  any ordinary `FIN:Approve` holder). Re-examined: this is not a coverage gap or a residual risk
  with a workaround — it is a **live-forced, deterministic financial mis-posting**, the exact
  phrase `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §8.1 uses to define **Critical**, not High.
  Step 15's own "High" classification was correct against *its own* charter (a bounded-repair
  lane's severity model, before any real-money production launch was in view); re-classified here,
  independently, against the production bar this checkpoint's own charter requires. **Escalated
  and registered as `RGL-BLK-009` below — Critical, `OPEN`, not accepted.**
- **`HDN-BLK-035`** (session revocation, `app.user_sessions.status`, is never consulted by any
  enforcement path — the documented incident-response resolution step is functionally inert).
  Re-examined: this is a security **incident-response** control that silently does not work — an
  operator who revokes a session (e.g. departed employee, compromised credential, security
  incident) has no actual effect, discoverable only by someone independently testing it. Kept at
  High (not escalated to Critical — no session is granted access it should not have; the control
  that is supposed to *remove* already-granted access is what fails), but **not accepted as
  routine residual risk** given it is exactly the kind of control a production launch's own
  incident-response runbook (`docs/runbooks/incident-response.md`) would be relied on to actually
  work. **Escalated and registered as `RGL-BLK-010` below — High, `OPEN`, not accepted.**

**The remaining 15 items** (`HDN-BLK-017`, `018`, `022`, `024`, `027`–`034`, `036`–`038`) —
audit-tamper-evidence gaps, an RLS/RPC gate gap on a ~33-table remainder reachable only by an
unusual dual-role (`customer_user` who also holds a staff role) actor shape, MFA/IP-restriction
wiring on 61 functions, alerting/monitoring/dashboard gaps, and DR/backup/restore/data-quality
gaps — **share one real, material, but time-limited compensating factor this checkpoint applies
explicitly, not silently**: production holds **zero real tenant rows** (`RGL-398`, re-confirmed
`RGL-402`/`RGL-403`) — every tenant-scoped table is empty. None of these 15 findings can cause
real tenant harm *today*, because there is no real tenant data or user to harm. **Conditionally
re-accepted on that basis, all 5 §8.2 conditions applied explicitly**: (1) all High-or-below,
none Critical; (2) this paragraph is the explicit written ruling — what was considered (fixing
all 15 before go-live) and rejected (infeasible within this range's own bounded-evidence,
no-new-features scope; each is a capability-sized remediation); compensating control: the
empty-production-data fact itself, not a design mitigation; (3) named owner: `Step 16`
(unchanged) for continued remediation, and **explicitly `RGL-406`/`RGL-408`** for the specific
new obligation this ruling adds — re-examine every one of these 15 before, or immediately upon,
the first real tenant's data entering production (a "tenant zero" gate, not previously named
anywhere in this range, added here); (4) re-examined against the production bar, not carried
over by reference — this paragraph *is* that re-examination, and the reason it still holds is the
empty-data fact stated above, which is new evidence Step 15's own ruling never had; (5) ruled at
`RGL-404`, the correct authority. **Priority ordering for the "tenant zero" re-examination,
highest first**: `HDN-BLK-022` (access-control gap) and `HDN-BLK-024` (MFA/IP-restriction gap) —
both directly tenant/security-facing; then `HDN-BLK-017`/`018` (audit-integrity); then the
DR/backup/restore cluster (`029`–`034`, `036`); then the operational/data-quality items
(`027`/`028`, `037`/`038`).

**This ruling does not itself dispose of `RGL-BLK-003` as `RESOLVED`** — it is the required
re-examination, not a fix. `RGL-BLK-003` remains `OPEN` as an aggregate tracking entry; its own
17 named items now each carry an explicit, dated, production-bar disposition (2 escalated and
newly registered below, 15 conditionally re-accepted with a new tenant-zero re-examination gate)
rather than an inherited Step 15 citation.

---

## `RGL-BLK-009` — Escalated from `HDN-BLK-016`: live-forced, deterministic financial mis-posting on every settlement reversal — meets §8.1's own Critical definition verbatim; fixed and deployed live to the hosted project the same checkpoint

| Field | Value |
|---|---|
| Severity | **Critical** (escalated from Step 15's own "High" — re-classified against the production bar, not a Step 15 correction) |
| Status | **`RESOLVED`, live-fixed** — applied directly to the hosted project (`awdlicmwzdxquopwtcfd`) via `apply_migration`, in effect immediately, not merely committed to this branch |
| Found at | Originally `HDN-374` (2026-08-23); escalated at `RGL-404` (Go/No-Go Report), 2026-08-25; fixed same checkpoint following an explicit operator instruction to run all available fixes |
| Owner | Unchanged technical owner: a design decision for the correct reversing-journal account mapping and idempotency shape (originally handed `HDN-386`→`HDN-387`, never implemented). Acceptance/severity authority: `RGL-404`/`RGL-412` only |

**Statement.** `app.request_finance_settlement_reversal` mutates only
`app.finance_ap_open_items`'s own `settled_amount`/`status` and logs an event — it never calls
`app.create_and_post_finance_system_journal` or any other GL-posting primitive. Reversing a posted
settlement reopens the AP subledger while the GL still shows the original payment as posted, with
no system-generated correction path to reconcile them. Live-forced at `HDN-374`'s own Tier C
review: a posted settlement (real GL journal, debit AP/credit cash) reversed via this governed
path — AP open item correctly returned to `open`; the original GL journal remained `posted`,
unchanged; zero correction/reversal journals existed anywhere afterward. Reachable by any ordinary
`FIN:Approve` holder, on every occurrence, not a rare edge case.

**Why Critical, re-classified from Step 15's own High.** `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md`
§8.1 defines Critical as including, verbatim, **"financial mis-posting"** — this finding is
exactly that: a deterministic, unbounded, live-forced GL/AP desync source, not a coverage gap or a
security-posture weakness with a workaround. Step 15's own "High" classification was made against
that lane's own charter and severity model, before a production go-live decision was in view; this
re-classification does not retroactively edit that historical record (`docs/build-log/full-system-
hardening/BLOCKER_LEDGER.md`'s own `HDN-BLK-016` entry is unchanged) — it applies this range's own
binding severity model to the same underlying, still-unfixed technical fact.

**Not accepted as risk — fixed instead.** Per §8.1, Critical is never risk-accepted at any
authority, so this item was closed by actually fixing it rather than by any acceptance ruling.

**Fix, applied live the same checkpoint.** `app.request_finance_settlement_reversal` now locates
the settlement's own posted GL journal (via its `app.finance_subledger_batches` row), reads that
journal's own lines, flips debit↔credit (the identical technique `app.post_finance_correction`
already uses for a general journal reversal — no new account-mapping logic invented), and posts
the flipped lines as a new `'correction'`-sourced journal via the same
`app.create_and_post_finance_system_journal` this codebase already uses for every other governed
posting path. A `app.finance_journal_corrections` row is written (status `posted` immediately —
a single FIN:Approve-gated atomic call, not a separate maker/checker workflow requiring a
different authority the caller was never expected to hold) so the correction ledger and
`app.get_finance_correction_chain` remain complete either way. Design decision made explicitly,
per `HDN-BLK-016`'s own "Required of `HDN-386`" field ("automatic vs. a separate governed step"):
**automatic**, to avoid reintroducing the exact "AP reversed but GL not yet" partial-state window
this fix exists to close.

**A second, previously undiscovered live defect was found and fixed in the same pass.** Live
catalog inspection (`select prosecdef from pg_proc where proname='request_finance_settlement_
reversal'`) showed the function was `SECURITY INVOKER`, not `SECURITY DEFINER` — `20260811200000`
(a later, same-day migration fixing this function's own period-lock bypass, `HDN-374` Tier C
finding 3) re-created it via `CREATE OR REPLACE FUNCTION` without restating `SECURITY DEFINER`,
silently reverting `RGL-397`'s own DEFINER-conversion fix for this one function immediately after
it shipped. Consequence: since `authenticated` holds no direct grant on the underlying tables,
**this function has been completely unreachable by any real authenticated tenant user** since
`20260811200000` shipped — the identical "Finance write RPC unreachable" bug class `RGL-397`/
`RGL-BLK-006` already found and fixed for 95 other functions, recurring here via a different
mechanism. Fixed in the same `CREATE OR REPLACE`, restoring `SECURITY DEFINER`. The `public.*`
wrapper (Option 2 remediation) was also mismatched as a consequence (created `SECURITY INVOKER`
to match app.*'s own then-broken state) — fixed to match, closing the zero-tolerance
security-mode regression guard (`scripts/db-tests/public-api-wrapper-regression.sql`) this
mismatch correctly flagged during local verification.

**Verification.** New db-test regression added (`scripts/db-tests/finance-settlement.sql`):
reverses a posted settlement and asserts the original journal stays posted/untouched, a new
correction-sourced reversal journal exists with every line direction flipped on the identical
account/amount, the subledger batch is marked `reversed`, a posted `finance_journal_corrections`
row records the chain, and `authenticated` retains `EXECUTE` on the now-restored `SECURITY
DEFINER` function. Found and fixed one genuine defect in the fix's own first draft during this
same verification pass (using `current_date` for the reversal's posting date made success depend
on whichever fiscal period happens to be open on the wall-clock day the call is made — corrected
to reuse `v_settlement.settlement_date`, already validated open by this function's own pre-existing
period-lock check). Full local `db-tests` suite re-run from a clean database: **`ALL PASSED`**.
Live-verified `prosecdef=true` on both `app.*` and `public.*` after the fix.

**Migration:** `supabase/migrations/20260826030000_harden_finance_settlement_reversal_gl_journal_
and_reachability.sql` (this branch's own committed record — applied live via `apply_migration`
across 3 calls during this checkpoint's own iterative fix-and-verify pass: the initial fix, the
date correction, and the wrapper security-mode fix; the committed file reflects the final,
corrected, single coherent version, not each intermediate step).

---

## `RGL-BLK-010` — Escalated from `HDN-BLK-035`: session revocation is never consulted by any enforcement path — but the documented incident-response procedure was already corrected at `HDN-384`, before this escalation; re-ruled down, see the correction below

| Field | Value |
|---|---|
| Severity | **Medium** (corrected below — the runbook fix this entry originally demanded already exists) |
| Status | **`RESOLVED` at the documentation layer since `HDN-384`** (prior to this range); underlying enforcement-wiring gap remains `OPEN`, Medium, non-blocking — see correction below |
| Found at | Originally `HDN-386` (Step 15, exact prior checkpoint not further re-derived here); escalated for explicit non-acceptance at `RGL-404` (Go/No-Go Report), 2026-08-25 |
| Owner | Unchanged technical owner: wiring session-status checks into the real enforcement path (`Step 16` backlog per `HDN-BLK-040`'s own ruling). Acceptance/severity authority: `RGL-404`/`RGL-412` only |

**Statement.** `app.user_sessions.status` (the field this codebase's own session-revocation
mechanism sets) is never consulted by any request-time enforcement path — a session marked
`revoked` continues to function exactly as before. `docs/runbooks/incident-response.md`'s own
documented resolution step for a compromised-credential or departed-employee scenario ("revoke the
session") is therefore inert: an operator who follows that runbook step believes they have
contained the incident, but has not.

**Why not accepted as routine residual risk.** Unlike a coverage gap with a known, disclosed
limitation, this is a control this codebase's own documentation actively represents as working —
a false safety claim, not merely an absent one. An incident-response procedure that silently does
not do what it says is a materially different risk shape than "we have not built X yet."

**Not accepted at production bar without one of**: (a) the enforcement path actually checking
`app.user_sessions.status` before honoring a session (the real fix), or (b) `docs/runbooks/
incident-response.md` explicitly corrected to state the true interim procedure (e.g., direct
credential rotation / API-key revocation via an already-working path) until the real fix ships,
so no operator relies on a documented step that does not work. Neither is attempted by this
checkpoint — Prompt 404 §12 forbids new-capability code changes in this prompt; a runbook
correction is plausibly in-scope for a future bounded checkpoint but is not attempted here either,
to keep this ruling's own record from quietly under-scoping the real fix as "just update the
docs."

**Compensating control today:** production holds zero real users/sessions yet (`RGL-398`), which
limits *current* blast radius. Given this item's own High (not Critical) classification, this
compensating factor is a legitimate, disclosed reason it does not independently force `NO_GO` the
way `RGL-BLK-001`/`RGL-BLK-009` do — but it must be resolved (real fix or corrected runbook) before
real users exist, named explicitly as part of the same "tenant zero" gate `RGL-BLK-003`'s own
ruling above establishes.

---

**Correction, same checkpoint, before this branch was pushed.** Option (b) above — *"the runbook
explicitly corrected to state the true interim procedure... so no operator relies on a documented
step that does not work"* — was written as if still open. It is not: re-reading
`docs/runbooks/incident-response.md` §4 in full (not merely re-citing `ISS-2026-264`'s own prose)
shows this correction was **already made at `HDN-384` Tier C**, before Step 16 began. §4 item 1 is
titled *"Pull authority the identity should not have — do this FIRST, it is the layer that is
actually enforced"*; item 2 (session/API-key revocation) is titled *"audit-trail hygiene, not the
primary lockout"* and carries the exact disclosure this entry's own statement describes verbatim,
plus guidance to escalate to the Supabase Admin API for real JWT/refresh-token invalidation when
one is suspected compromised. **The "false safety claim" this entry's own "why not accepted"
reasoning turns on does not exist in the current runbook** — an operator following §4 in order is
correctly told the true mechanism at every step.

**Re-ruled down accordingly.** `RGL-BLK-010` is **not** a fresh, unaddressed gap this checkpoint
discovered — it is `ISS-2026-264`'s own already-`HDN-384`-mitigated finding, re-escalated here on
an incomplete read of the runbook's current state (this checkpoint's own error, corrected in
place rather than silently). **Reclassified: `RESOLVED` at the documentation layer (has been since
`HDN-384`, prior to this range), with the underlying `app.user_sessions.status`
enforcement-wiring gap remaining open as a genuine, but now correctly Medium-shaped, disclosed,
non-blocking hardening item** — folded into the same 15-item "tenant zero" conditional-acceptance
group `RGL-BLK-003`'s own ruling already covers, not a separate High blocker. This does not change
this checkpoint's own `NO_GO` verdict (`RGL-BLK-001`/`RGL-BLK-009` remain independently sufficient)
but does correct the record: `RGL-BLK-010` should not be cited as an open High blocker by any
later checkpoint.

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

## `RGL-BLK-006` — `ISS-2026-290`'s original "17 already-committed migrations behind" undercounted by 10; live production was missing real security and financial-integrity fixes, including a total Finance-write outage for genuine users (`RESOLVED` — found and fixed same checkpoint)

| Field | Value |
|---|---|
| Severity | **Critical** |
| Status | **`RESOLVED`** (`RGL-397`, 2026-08-25, same checkpoint as discovery) |
| Found at | `RGL-397` (Migration Validation), 2026-08-25, by a full name-for-name diff of every migration filename against live `supabase_migrations.schema_migrations`, not by reading `ISS-2026-290`'s own prior count and trusting it |
| Owner | `RGL-397` (Migration Validation) — fixed directly, this task's own charter |

**Statement.** `RGL-BLK-002`'s Option 2 remediation (`ISS-2026-290`, this same range, earlier the
same day) found and applied "17 already-committed Step 15 hardening migrations" that existed in
the repository but had never reached the live hosted project. This checkpoint's own migration
validation — comparing every one of the 336 local migration filenames against live's migration
registry by name, not merely by counting rows — found that **10 more already-committed,
already-reviewed Step 15 migrations, dated `20260810200000` through `20260811200000`, sitting
chronologically INSIDE the exact window `ISS-2026-290` itself described (`20260810000000` through
`20260819000000`), were also never applied.** `ISS-2026-290`'s own "17" count was an undercount,
not a stale fact that later became true again — these 10 files existed in the repository at the
time `ISS-2026-290` was written (confirmed via `git log --follow`, each committed at `HDN-373`/
`HDN-374`, well before this session began) and were simply not among the files that checkpoint's
own enumeration caught.

**What was actually missing from production, by content, not merely by filename:**

| Migration | What was live-unpatched until this checkpoint |
|---|---|
| `..._harden_tenant_isolation_actor_identity_gaps` (headline, `app.evaluate_permission`) | The single RBAC gate ~1,124 functions in this schema call transitively **never checked whether the claimed actor was still an active member of the tenant at all** — a revoked ex-member retained every role-based read/write permission they held at the moment of revocation, indefinitely, until someone separately cleaned up their `role_assignments` rows too (nothing in this codebase ever did). Live-forced and confirmed by the original investigation before this checkpoint re-applied it. |
| `harden_dashboard_actor_identity_gaps` / `harden_crm_ops_actor_identity_gaps` (29 functions) | Actor-identity-forgery: any authenticated session could pass another identity's UUID into 29 `SECURITY DEFINER` dashboard/CRM functions and read that identity's own record-scoped data — for cost/margin/selling-price-masked dashboard aggregates, this let a caller with no view-cost grant of their own see real unmasked financial figures by forging a UUID known to hold that grant. |
| `harden_own_row_rls_membership_gap` | A revoked ex-member retained RLS-level read access to their own past `notifications`/`notification_preferences`/`saved_report_views` rows indefinitely — the one gap in this schema's otherwise-universal "membership revocation fails closed" convention. |
| `harden_loyalty_redemption_maker_checker` | A maker/checker collapse: any identity holding only `LYL:Edit` (not the higher `LYL:Configure` tier) could submit AND instantly, synchronously fulfill a `discount_voucher` loyalty redemption for any account in the tenant in one call, zero second approver — live-forced, confirmed real dollar-denominated voucher entitlements were walked through with zero review. |
| `harden_finance_authority_chain_security_definer` (95 functions) + its own Tier C completeness fix (57 more) | **The most severe item.** 95 Finance-domain functions (journal, period close/lock, exchange rate, tax, invoice, AP/AR, cash, settlement, vendor bill, correction, reconciliation, account, bank statement) plus the generic `app.enqueue_job` were `SECURITY INVOKER` instead of `SECURITY DEFINER`, unlike virtually every other client-callable RPC in this schema. Because `authenticated` holds no direct grant on the underlying `app.permissions`/`app.role_assignments` tables or the Finance domain tables themselves, **every one of these Finance write RPCs, and every background job enqueued through the generic path, was completely unreachable by any real tenant user since it shipped** — not merely a security gap, a functional Finance-write outage for genuine users. The pre-existing `db-tests` suite never caught this because it runs every test as the Postgres superuser, bypassing the exact grant chain this defect broke. |
| `harden_finance_journal_view_gate_and_self_approval` | `app.finance_journals`/`app.finance_journal_lines`'s own `SELECT` RLS policy was membership-only, no `FIN:View` predicate — any tenant member with zero Finance permissions could read every real journal row and line directly via RLS, bypassing the RPC layer's own correct gate entirely. Also closed a self-approval gap on `app.create_and_post_finance_system_journal` (independently, directly granted to `authenticated` across 4 migrations, with no authority check of its own once reachability was restored). |
| `harden_finance_period_lock_idempotency_race` / `harden_financial_integrity_tierc_fixes` | A real concurrency race on `app.lock_finance_period` (two concurrent first-time locks could both pass the not-found check), plus 3 further Tier C financial-integrity fixes including a quote discount/tax billing defect that would have overbilled by the discount amount. |

**Fix.** All 10 pre-existing, already-committed, already-reviewed migration files applied to live
(`awdlicmwzdxquopwtcfd`) in exact chronological order via `apply_migration`, each read in full
immediately before applying. Two of the ten (`harden_finance_authority_chain_security_definer`,
249KB/5,192 lines, and `harden_finance_authority_chain_tierc_completeness`, 104KB/2,386 lines)
exceeded the model's own single-response output-token limit when reproduced whole, so each was
split at clean top-level SQL statement boundaries into 6 and 3 sequential `apply_migration` calls
respectively (`_p1`..`_p6`/`_p1`..`_p3`), applied strictly in order — a chunking technique, not a
content change; the identical, complete file content was applied either way, just via more calls.
This means live's migration registry now carries 17 rows for these 10 files (326 → 343), not a
clean 10 — disclosed here rather than presented as if one row per file, and functionally
immaterial (Postgres applied the exact same DDL regardless of how many `apply_migration` calls
carried it).

**Verification.** Live migration count: 326 → 343 rows (17 new: 5 single-file + 6 + 1 + 3 + 1 + 1
chunks/files). Functional spot-checks, all confirmed live via direct catalog/RLS inspection, not
assumed from the applied SQL text alone: `app.evaluate_permission`'s body now contains the
`not_active_tenant_member` check; `app.create_finance_journal_draft`, `app.check_finance_journal_authority`
and `app.create_and_post_finance_system_journal` are now `prosecdef = true`; the self-approval gate
literal (`check_finance_journal_authority(...Approve...)`) is present in
`create_and_post_finance_system_journal`'s live body; `app.finance_journals`'s own RLS policy now
reads `check_finance_journal_authority('View', ...)` instead of membership-only; `app.notifications`'s
own-row policy now carries `has_active_tenant_membership`; `app.submit_loyalty_redemption`'s body
now contains the `LYL`/`Configure` gate. Security advisors re-pulled after all 10: 1 pre-existing
`ERROR` (`spatial_ref_sys`, PostGIS's own public-schema table, unrelated to this batch, already
disclosed at `RGL-BLK-002`'s own advisor review); `WARN`-level `authenticated_security_definer_function_executable`
count is consistent with the intentional DEFINER conversion (expected to grow, not a new defect
class); no new `ERROR`-level finding attributable to this batch.

**Why Critical.** The Finance-write reachability gap alone means genuine tenant users could not
create, submit, approve, post, or reconcile real Finance records in production — a functional
outage on the entire Finance domain, not merely a security posture gap — for the entire window
between each fix's original merge (Step 15, `HDN-373`/`HDN-374`) and this checkpoint. Combined with
the actor-identity-forgery, RBAC-persistence-after-revocation, and maker/checker-collapse findings,
this is a materially more severe instance of exactly the class `ISS-2026-290`/`RGL-BLK-002`
already registered Critical for the other 17 — corrected and closed here rather than left as a
silent gap in that earlier count.

**Not a §8.2 acceptance.** Fixing a root cause removes the finding rather than accepting it; this
checkpoint holds no acceptance authority regardless (§8.2 condition 5 restricts that to
`RGL-404`/`RGL-412`).

---

## `RGL-BLK-007` — Every `app/api/v1/**` route returns an uncaught `500` for any invalid/unrecognized Bearer key instead of a clean `401`, live-forced in production (`RESOLVED in code, not yet deployed` — found and fixed same checkpoint)

| Field | Value |
|---|---|
| Severity | **High** |
| Status | **`RESOLVED` in code on this branch, `NOT YET DEPLOYED` to production** (`RGL-401`, 2026-08-25, same checkpoint as discovery) |
| Found at | `RGL-401` (Smoke Test), 2026-08-25, by live-probing `/api/v1/status` with a range of Bearer-token states as a genuine external API consumer would, not merely reasoning about the code |
| Owner | `RGL-401` (Smoke Test) — root-caused and fixed directly, this task's own charter; `RGL-015` (Production Deployment) owns actually shipping the fix live |

**Statement.** `GET https://cargogrid-app.vercel.app/api/v1/status` with
`Authorization: Bearer <any never-issued key>` returned an uncaught `500` with an empty body in
live production, instead of the intended clean `401 {"error":{"code":"unauthenticated"}}`. The
same request with no `Authorization` header at all correctly returned `401` — only the
present-but-unrecognized-key path was broken, arguably the single most common real-world failure
mode for any API consumer (a typo'd, expired, or revoked key).

**Root cause, isolated via direct SQL against the live hosted project, not guessed at.**
`lib/api-gateway/authenticate.server.ts`'s denial-logging branch unconditionally logged
`actorType: "api_key"` for every denied request. `app.api_logs`'s own
`api_logs_actor_shape_check` CHECK constraint requires a non-null `api_key_id` whenever
`actor_type = 'api_key'`. For `rate_limited`/`forbidden_scope` denials this is correct — the key
was found, so `api_key_id` is always resolved. For `unauthenticated`, the key was never found at
all, so `api_key_id` is genuinely `null` — logging `"api_key"` against a `null` id threw
`23514` inside `recordApiRequest()`, an exception the caller did not catch, surfacing as Next.js's
generic `500`. Confirmed live by calling `public.record_api_request(...)` directly with the exact
pre-fix parameter shape and observing the same `23514` error.

**Blast radius.** `authorizeApiV1Request()` is the one shared gateway function every `/v1` route
calls (its own header comment: "the one place... IAE-010/011/012's own `/v1` routes reuse...
instead of re-deriving auth/rate-limit/error-shape logic per capability"). Confirmed via
`grep -rln "authorizeApiV1Request" app/api/v1` — **all 9** route files under `app/api/v1/**`
shared this identical defect against any invalid key.

**Why this class of bug was invisible to existing tests.** `tests/api/v1/support/rpc-fetch-stub.ts`'s
own header comment discloses `record_api_request` "always succeeds trivially in these tests" — the
Node unit-test layer never exercised the real constraint. `scripts/db-tests/public-api-platform.sql`
only ever calls `app.authenticate_and_authorize_api_request` in isolation, never the full
route-handler sequence of auth-check-then-log-denial that actually triggers this.

**Fix.** One line, `lib/api-gateway/authenticate.server.ts`: `actorType: "api_key"` →
`actorType: authResult.apiKeyId ? "api_key" : "anon"` — derives the logged actor type from
whether a real key was actually resolved, matching both the constraint and
`app.authenticate_and_authorize_api_request`'s own real contract. No migration, no schema change —
the constraint itself is correct; the application code violated it.

**Verification.** New regression test (`tests/api/v1/status.test.ts`) pins the previously-broken
case; two adjacent existing tests (`rate_limited`, `forbidden_scope`) tightened to use realistic
non-null `apiKeyId` fixtures matching the real DB contract. `node --experimental-strip-types --test
tests/api/v1/status.test.ts`: 5/5 pass. Full suite: `pnpm run test` — 5453/5453 pass. Fix's exact
live database interaction re-verified directly against the hosted project
(`public.record_api_request(..., 'anon', null::uuid, ...)` succeeds cleanly); the one synthetic
`app.api_logs` row this verification created was deleted immediately after, leaving production's
table exactly as found otherwise. Full detail: `docs/build-log/release-go-live/RGL-401.md`.

**Why High, not Critical.** No tenant data, financial record, or security boundary is broken or
bypassed — the constraint that fired is doing exactly its job (rejecting a bad denial-log shape);
the defect is a reliability/contract break in the public REST API's own error-handling path (a
`500` where a documented `401` is the contract), not a data-integrity, tenant-isolation, or
financial-correctness failure. It is registered High because it breaks the error contract for the
single most common real-world API-consumer failure mode across the entire public `/v1` surface (9
routes), not a narrow edge case.

**Why `RESOLVED` here does not mean closed.** The fix is committed to
`claude/step-16-prompt-390-412-okbd6v` and merges into the release candidate, but **production's
running application binary is unchanged by this checkpoint** (Prompt 401 §12 forbids production
mutation/deployment in this prompt) — the defect remains live in production until `RGL-015` ships
this branch. `RGL-404`/`RGL-015` must account for this as an outstanding "fix ready, not yet
deployed" item, not treat `RESOLVED` here as "no longer present in production."

**Not a §8.2 acceptance.** Fixing a root cause removes the finding rather than accepting it; this
checkpoint holds no acceptance authority regardless (§8.2 condition 5 restricts that to
`RGL-404`/`RGL-412`).

---

## `RGL-BLK-008` — all 3 externally-reachable, unauthenticated webhook ingestion routes crashed with an uncaught `500` on a malformed `connectionId`, live-forced in production (`RESOLVED in code, not yet deployed` — found and fixed same checkpoint)

| Field | Value |
|---|---|
| Severity | **High** |
| Status | **`RESOLVED` in code on this branch, `NOT YET DEPLOYED` to production** (`RGL-402`, 2026-08-25, same checkpoint as discovery) |
| Found at | `RGL-402` (Penetration Test Evidence), 2026-08-25, by live-probing the third-party-gps webhook route with a SQL-injection-shaped and a path-traversal-shaped `connectionId`, as a genuine anonymous internet caller could |
| Owner | `RGL-402` (Penetration Test Evidence) — root-caused and fixed directly, this task's own charter; `RGL-015` (Production Deployment) owns actually shipping the fix live |

**Statement.** `POST https://cargogrid-app.vercel.app/api/webhooks/third-party-gps/<connectionId>`
with a `connectionId` path segment that is not a well-formed UUID (e.g. `1' OR '1'='1`, or
`..%2f..%2fetc%2fpasswd`) returned an uncaught, empty-body `500` in live production, instead of the
clean `400 {"ingestStatus":"invalid"}` the route's own header comment already documents as its
contract. **This route requires no credentials at all at the HTTP layer** — a third-party
provider's authenticity is established entirely by an HMAC signature verified inside the RPC, not
by any Bearer token or session — so any anonymous caller on the internet can trigger this.

**Root cause, found by direct code inspection following the live reproduction.** The route passes
the raw, unvalidated URL path segment straight into `ingestThirdPartyProviderWebhookEvent()`
(`server/mutations/third-party-provider-adapter.ts`), which begins with a **throwing** Zod
`.parse()` call whose schema validates `connectionId` as `z.string().uuid()`. A malformed value
fails this validation before any RPC call is even attempted, throwing a `ZodError` the route's own
call site never wrapped in `try`/`catch` — uncaught, it surfaced as Next.js's generic `500`.

**Not the same root cause as `RGL-BLK-007`** (a Postgres check-constraint violation inside a
completed RPC call) — but the same failure *class*: an uncaught exception converting an intended
clean `4xx` denial into a generic `500`. **Not an actual SQL-injection vulnerability**: every
domain call in this codebase is a parameterized RPC call, so no query text is ever constructed
from caller input; what this finding demonstrates is unhandled-exception / insufficient
error-handling around input validation, not injection.

**Blast radius: all 3 externally-reachable webhook ingestion routes**, confirmed identical by
direct code inspection (not each individually live-reproduced a second/third time, since the code
is byte-for-byte identical in shape): `app/api/webhooks/third-party-gps/[connectionId]/route.ts`,
`app/api/webhooks/finance-payment-gateway/[connectionId]/route.ts`,
`app/api/webhooks/logistics-partner/[connectionId]/route.ts` — each calling its own sibling
mutation function with an identical `z.string().uuid()`-validated, throwing-parse `connectionId`
field, none wrapped in a local `try`/`catch` at the route layer.

**Why this class was invisible to existing tests.** No route-level HTTP-layer test existed for any
of the 3 webhook routes before this checkpoint (`find tests -iname "*webhook*"` returned only the
unrelated `webhook-event-types.test.ts`). The `db-tests` suite exercises the underlying RPC
directly with well-formed UUIDs, never through the TypeScript route layer where this defect lives.

**Fix.** Wrapped each route's own ingest call in a local `try`/`catch`, returning the same
`{ ingestStatus: "invalid" }`, `400` shape each route already uses for its other early-rejection
cases (missing signature/timestamp/empty body) — the smallest, most local fix, touching no
contract, mutation function, or migration.

**Verification.** New test files for all 3 routes (`tests/api/webhooks/*.test.ts`, none existed
before), 4 tests each: a non-UUID `connectionId` never reaches the RPC and returns `400`; a
path-traversal-shaped one likewise; a well-formed UUID with an `ok` RPC outcome still returns `200`
(no happy-path regression); a well-formed UUID with an `invalid` RPC outcome still returns `401`
(denial-status mapping unchanged). `node --experimental-strip-types --test tests/api/webhooks/*.test.ts`:
10/10 pass. Full suite: `pnpm run test` — 5463/5463 pass. Full detail:
`docs/build-log/release-go-live/RGL-402.md`.

**Why High, not Critical.** No data is mutated, no auth boundary is bypassed, and no injection
actually executes — the defect is a reliability/error-handling break on 3 externally-reachable,
**unauthenticated** production endpoints, for a failure mode (malformed input) any anonymous
caller, bot, or misconfigured client can trigger with zero credentials. Registered High to match
`RGL-BLK-007`'s own reasoning, with a note that this finding's reachability is wider (zero
credentials required, vs. `RGL-BLK-007`'s "any presented key").

**Why `RESOLVED` here does not mean closed.** The fix is committed to
`claude/step-16-prompt-390-412-okbd6v` and merges into the release candidate, but **production's
running application binary is unchanged by this checkpoint** (Prompt 402 §12 forbids production
mutation/deployment in this prompt) — the defect remains live in production until `RGL-015` ships
this branch. `RGL-404`/`RGL-015` must account for this, alongside `RGL-BLK-007`, as an outstanding
"fix ready, not yet deployed" item.

**Not a §8.2 acceptance.** Fixing a root cause removes the finding rather than accepting it; this
checkpoint holds no acceptance authority regardless (§8.2 condition 5 restricts that to
`RGL-404`/`RGL-412`).

---

**Disposition ruling on `RGL-BLK-007`/`RGL-BLK-008` (`RGL-404`, Go/No-Go Report, 2026-08-25).**
Both **`ACCEPTED` as fixed-not-yet-deployed** — not a §8.2 risk acceptance of an unmitigated
finding, since the underlying defect is genuinely fixed in the release-candidate content
(`RC-2026.08.25-1` includes both fixes) and regression-tested; the only remaining step is
`RGL-405` actually shipping this branch to production. Neither independently blocks a future
`GO_DECIDED` on its own technical merits. **They remain relevant to this checkpoint's own verdict
only as evidence that `RGL-015` must deploy this exact branch, not merely "whatever is on `main`
today"** — a distinct requirement from, and smaller than, `RGL-BLK-001`'s own governance gap.

---

## Status summary as of `RGL-404` (Go/No-Go Report, including its own fix-pass follow-up), 2026-08-25

| Severity (binding) | Open | Resolved/Accepted | IDs (open) |
|---|---|---|---|
| Critical | **1** | 2 (`RGL-BLK-006`, `RGL-BLK-009` — fixed and deployed live) | `RGL-BLK-001` |
| High | **1** | 7 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`, `RGL-BLK-007`, `RGL-BLK-008` — both fixed-not-deployed; `RGL-BLK-003` — ruled/re-examined, 15 of 17 items conditionally re-accepted) | `RGL-BLK-003` (aggregate, ruled) |
| Medium | 1 (`RGL-BLK-010`, re-ruled down from High — docs-layer already resolved at `HDN-384`, enforcement-wiring gap remains, folded into `RGL-BLK-003`'s own 15-item group) | 0 | `RGL-BLK-010` |

**Verdict: `NO_GO` — unchanged, but now forced by one reason, not two.** Following an explicit
operator instruction to run all available fixes, this checkpoint fixed `RGL-BLK-009` directly and
deployed it live to the hosted project (see the entry itself) — genuinely closing that Critical
finding, not merely ruling on it. `RGL-BLK-001` (ungated production auto-deploy) **could not be
fixed**: no tool available in this session's toolset can configure GitHub branch protection rules
or a Vercel deployment-promotion gate (`update_project_deployment_protection` only offers
password/SSO/trusted-IP auth-gating, which would solve a different problem and would break real
customer access if misapplied to production — the wrong fix). `RGL-BLK-001` remains open,
Critical, and per §8.1 is never risk-accepted at any authority — this alone still forces `NO_GO`.
Full decision record: `docs/build-log/release-go-live/RGL-404.md`,
`docs/build-log/release-go-live/GO_NO_GO_REPORT.md`.

---

## Status summary as of `RGL-404`'s operator-override addendum, 2026-08-25

| Severity (binding) | Open | Resolved/Accepted | IDs (open) |
|---|---|---|---|
| Critical | **0** | 3 (`RGL-BLK-006`, `RGL-BLK-009` — fixed and deployed live; `RGL-BLK-001` — accepted by direct operator override, mechanism itself still unfixed) | — |
| High | **1** | 7 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`, `RGL-BLK-007`, `RGL-BLK-008` — both fixed-not-deployed; `RGL-BLK-003` — ruled/re-examined, 15 of 17 items conditionally re-accepted) | `RGL-BLK-003` (aggregate, ruled) |
| Medium | 1 (`RGL-BLK-010`, folded into `RGL-BLK-003`'s own 15-item group) | 0 | `RGL-BLK-010` |

**Verdict: `NO_GO` still stands, but no open Critical or unruled High blocker remains.** With
`RGL-BLK-001` accepted directly by the operator (see the entry's own "OPERATOR RISK ACCEPTANCE"
section above) and `RGL-BLK-009` fixed and deployed live, **zero open Critical findings remain**,
and the sole open High entry (`RGL-BLK-003`) is an aggregate tracking record for items already
individually ruled (2 dispositioned above, 15 conditionally re-accepted under the "tenant zero"
gate) — not a fresh, unruled blocker. This is **not by itself a `GO_DECIDED`**: `GO_NO_GO_REPORT.md`
§3.4 already named three tracked gaps — no staging tier, no named UAT acceptor (`UAT_ACCEPTED`
cannot be set by any agent), no licensed external penetration-test engagement — as **independently
sufficient** reasons a `GO_DECIDED` would be premature "even setting `RGL-BLK-001`/`009` aside
entirely." Those three gaps are unchanged by this addendum; none of them was raised by, or
resolved by, the operator's `RGL-BLK-001` instruction. **`NO_GO` continues to hold on the strength
of §3.4's three tracked gaps alone.** Full updated decision record:
`docs/build-log/release-go-live/GO_NO_GO_REPORT.md`'s own second addendum.

**Further update, same checkpoint.** Asked directly how to handle the three tracked gaps, the
operator instructed they be accepted the same way as `RGL-BLK-001` — see
`GO_NO_GO_REPORT.md` §3.4's own third addendum. **Mechanically, nothing left in this ledger
continues to force `NO_GO`.** This report nonetheless keeps the verdict at `NO_GO`, now by
deliberate choice: declaring `GO_DECIDED` would make `RGL-405` eligible against a still-armed
auto-deploy mechanism, and the operator's own next instruction (given in the same turn) was to
resolve the full historical project-wide issue backlog (`docs/runtime/KNOWN_ISSUES.md`, every
prior phase, not only this range), not to deploy. **`RGL-405`–`412` remain `BLOCKED` pending an
explicit, separate operator instruction to proceed to `GO_DECIDED`.** See `RGL-404.md`'s own new
section for the backlog survey and remediation work this instruction produced.

**Historical-issue-backlog remediation progress note, 2026-08-25 onward.** Per the operator's
"seluruh issue ... harus solved semua tanpa terkecuali" instruction, the 15-item conditionally-
accepted group above is being worked genuinely, not merely left accepted. `HDN-BLK-036`
(`ISS-2026-267`, no mutual-exclusion mechanism for the composed in-place restore procedure) is now
**`RESOLVED`** — see `docs/runtime/KNOWN_ISSUES.md`'s own `ISS-2026-267` entry and
`docs/build-log/release-go-live/RGL-404.md`'s backlog section for full detail; not duplicated here
in full to keep this ledger's own append-only growth manageable across what both the operator and
this ledger anticipate will be a long remediation. Progress tracked going forward in `RGL-404.md`
and `docs/runtime/CHANGE_MANIFEST.md`, referenced from here rather than repeated.

---

## Status summary as of `RGL-402` (Penetration Test Evidence), 2026-08-25

| Severity (binding) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **1** | 1 (`RGL-BLK-006`) | `RGL-BLK-001` |
| High | **1** | 5 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`, `RGL-BLK-007`, `RGL-BLK-008`) | `RGL-BLK-003` |
| Medium | 0 | 0 | — |

**`RGL-BLK-008` (High, new this checkpoint) is `RESOLVED` in code, `NOT YET DEPLOYED`** — found and
fixed the same checkpoint (`RGL-402`'s own charter, Penetration Test Evidence), alongside the
already-registered `RGL-BLK-007` (`RGL-401`) in the same "fixed, not yet shipped" state; both ship
live only at `RGL-015`. `RGL-BLK-001` (Critical, ungated Vercel auto-deploy) and `RGL-BLK-003`
(High-aggregate, 17 inherited Step 15 acceptances) remain open, both `RGL-404`'s to dispose of;
neither is touched by this checkpoint. A new tracked gap (no licensed third-party penetration-test
engagement exists) is also recorded, owner `RGL-404`/`RGL-412` — see `RGL-402.md` §6.

---

## Status summary as of `RGL-401` (Smoke Test), 2026-08-25

| Severity (binding) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **1** | 1 (`RGL-BLK-006`) | `RGL-BLK-001` |
| High | **1** | 4 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`, `RGL-BLK-007`) | `RGL-BLK-003` |
| Medium | 0 | 0 | — |

**`RGL-BLK-007` (High, new this checkpoint) is `RESOLVED` in code, `NOT YET DEPLOYED`** — found and
fixed the same checkpoint (`RGL-401`'s own charter, Smoke Test), but the fix ships live only at
`RGL-015`; `RGL-404` must treat it as an outstanding deployment item, not a closed matter.
`RGL-BLK-001` (Critical, ungated Vercel auto-deploy) and `RGL-BLK-003` (High-aggregate, 17
inherited Step 15 acceptances) remain open, both `RGL-404`'s to dispose of; neither is touched by
this checkpoint.

---

## Status summary as of `RGL-397` (Migration Validation), 2026-08-25

| Severity (binding) | Open | Resolved | IDs (open) |
|---|---|---|---|
| Critical | **1** | 1 (`RGL-BLK-006`) | `RGL-BLK-001` |
| High | **1** | 3 (`RGL-BLK-002`, `RGL-BLK-004`, `RGL-BLK-005`) | `RGL-BLK-003` |
| Medium | 0 | 0 | — |

**`RGL-BLK-006` (Critical, new this checkpoint) is `RESOLVED`** — found and fixed the same
checkpoint (`RGL-397`'s own charter, Migration Validation). `RGL-BLK-001` (Critical, ungated Vercel
auto-deploy) and `RGL-BLK-003` (High-aggregate, 17 inherited Step 15 acceptances) remain open,
both `RGL-404`'s to dispose of; neither is touched by this checkpoint.

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
