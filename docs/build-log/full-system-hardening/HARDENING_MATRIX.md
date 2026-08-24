# Step 15 — Hardening Matrix

**Produced by:** `CG-S15-HDN-001` (Prompt 369, Full-System Hardening WBS Runtime Kickoff)
**Governs:** `HDN-370` … `HDN-389`
**Companion files:** `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` (routing),
`docs/build-log/full-system-hardening/BLOCKER_LEDGER.md` (findings)

Prompt 369 step 4 requires a matrix for each of the 16 mandatory hardening gates. Each is
seeded below with the evidence that **already exists** at this checkpoint, so no lane starts
from zero and no lane rediscovers a known item.

**Status vocabulary — used strictly.** `NOT_RUN` is never reported as a pass, and
"not triggered" is never reported as "verified".

| Status | Meaning |
|---|---|
| `NOT_RUN` | The lane has not executed. Default for every gate at this checkpoint |
| `PASS` | Executed against a real target, observed green |
| `PASS_SUBSTITUTE` | Executed against a disclosed substitute (disposable DB / migrated-but-not-running live project), with the substitution's limits stated |
| `PARTIAL` | Executed, but one or more required dimensions were not exercised. **Not a pass** |
| `FAIL` | Executed, observed red |
| `TRACKED_GAP` | Cannot be executed here. Recorded with owner, risk and the exact missing command. **Not a pass** |

---

## Gate index

| # | Gate | Lane | Status at kickoff | Seeded evidence |
|---|---|---|---|---|
| 1 | Full regression | `HDN-370` **`VERIFIED`** | **`PARTIAL`** — all local gates green; **CI red on all 3 jobs**; `test:e2e` a `TRACKED_GAP` | §1 |
| 2 | Cross-module transactional integrity | `HDN-371` **`VERIFIED`** | **`PARTIAL`** — every named chain reconciled except loyalty/portal (not examined, tracked gap); one systemic finding (`HDN-BLK-010`, 9 functions, Medium), live-forced-race proven | §2 |
| 3 | Tenant isolation | `HDN-372` **`COMPLETED`** | **`PARTIAL`** — not a pass. One High cross-tenant read class found and fixed at the root, twice — first 9 functions, then 4 more found by this checkpoint's own Tier C review and fixed in the same checkpoint (`HDN-BLK-011`, 13 direct + 11 transitive = 24 functions total); two same-shape findings remain genuinely open (`HDN-BLK-012`, 13 dashboard functions; `HDN-BLK-014`, ~24 candidate functions, not individually live-verified — both deferred to `HDN-373`); one High app-layer finding registered late and corrected at Tier C (`HDN-BLK-013`); 13 further Medium/Low findings registered | §3 |
| 4 | RLS / RBAC | `HDN-373` **`COMPLETED`** | **`PARTIAL`** — not a pass, Tier C review pending. Root RBAC gate (`app.evaluate_permission`) never checked tenant membership — fixed (`ISS-2026-180`). The entire Finance manual/period/config/import-export write surface (95 functions) was `SECURITY INVOKER`, completely unreachable by any real session since it shipped — fixed (`HDN-BLK-015`/`ISS-2026-182`, the largest reachability defect found in Step 15 to date). `HDN-BLK-012` (13 dashboard functions, deferred from `HDN-372`) fixed; `HDN-BLK-014` (~30 candidates, deferred from `HDN-372`) narrowed to 16 fixed / ~14 residual (`ISS-2026-186`, owner a future checkpoint); `ISS-2026-139` (loyalty maker/checker) fixed; `ISS-2026-137` re-verified accurate, no change. 6 further findings registered with named forward owners | §4 |
| 5 | Financial integrity | `HDN-374` **`VERIFIED`** | **`PARTIAL`** — not a pass, Tier C closed. Quote-level tax silently doubled at invoicing — fixed (`ISS-2026-194`). A job order could reach `issued` on two full-amount invoices from two distinct handoffs — fixed at the actual AR/GL posting boundary, `app.issue_finance_invoice` (`ISS-2026-195`; the first fix draft, gating invoice preparation itself, was self-corrected before commit — it would have broken `OPS-181`'s own disclosed legitimate-re-handoff allowance). `HDN-BLK-010`/`ISS-2026-162`'s Finance/HRIS-Payroll scope resolved — 10 functions (6 named plus 4 more this checkpoint's own wider sweep found) fixed with the codebase's own "design note 9(a)" pattern, 2 mechanisms live-forced with a genuine two-process race each. `app.run_loyalty_expiry_sweep`'s own `p_as_of` was silently ignored — fixed (`ISS-2026-196`). **Tier C review found 5 more real, live-forced defects**: `app.lock_finance_period` shared the sweep's own missed shape (fixed); Finding 1's own fix dropped the quote's discount, overbilling (fixed); Finding 2's own guard had no backing constraint and did not survive genuine concurrency (fixed with a real partial unique index); `app.request_finance_settlement_reversal` bypassed period lock entirely (fixed) and posts no reversing GL journal at all (registered, `ISS-2026-199`/`HDN-BLK-016`, owner `HDN-386`). 2 findings registered, not fixed, owner `HDN-386` (`ISS-2026-197`: no FX/multi-currency conversion anywhere in the revenue chain; Operations' own job-profitability planned-vs-actual split). `HDN-BLK-010`'s residual 3 non-Finance functions plus `ISS-2026-163` handed to `HDN-387` | §5 |
| 6 | Data lineage | `HDN-375` **`VERIFIED`** | **`PARTIAL`** — not a pass, Tier C closed. Canonical lineage chain, downstream projection versioning, historical config preservation and permission-awareness all held clean at first round. `app.transaction_lineage_edges` had no `BEFORE UPDATE/DELETE` guard at all despite its own append-only contract — fixed (`ISS-2026-201`). `app.loyalty_earning_events`/`app.finance_journals` accepted a `source_id` with no DB-layer FK — fixed with a per-`source_type` validation trigger on each (`ISS-2026-202`). The 5 hash-chain triggers are standalone per-row fingerprints, not a genuine chain — registered, not fixed (`ISS-2026-200`/`HDN-BLK-017`, High, owner `HDN-386`). **Tier C found the append-only-guard pattern is genuinely needed on ~70 more tables schema-wide, including `app.audit_logs` itself** — registered, not fixed (`ISS-2026-205`/`HDN-BLK-018`, High, owner `HDN-386`); the orphan-`source_id` gap recurs on `finance_subledger_batches` and others — registered, not fixed (`ISS-2026-206`, Medium, owner `HDN-387`, after a fix draft was caught before commit breaking a pre-existing test file's own design) | §6 |
| 7 | API compatibility | `HDN-376` **`VERIFIED`** | **`PASS`** — Tier C closed. A Critical/High authentication bypass fixed on the inbound/outbound webhook signature verification path (`ISS-2026-209`/`210`, a NULL signature silently accepted as verified). 2 Low REST route error-code bugs fixed (`ISS-2026-211`/`212`). `ISS-2026-147` item 1 closed — 44 new route-level tests across all 9 REST `/v1` handlers, via a fetch-stubbing harness (no local PostgREST/Supabase stack available). GraphQL wording corrected (no surface exists). Tier C found and fixed 1 more real defect (`ISS-2026-215`, Low, 2 GET routes conflating a genuine internal RPC failure with the 404 not-found case) and corrected 1 documentation-citation error. 4 findings registered, not fixed: `ISS-2026-207`/`208` (Medium/Low, owner `HDN-387`); `ISS-2026-213`/`214` (both Low, owner `HDN-386`/`HDN-387`) | §7 |
| 8 | Storage / signed URL | `HDN-377` **`VERIFIED`** | **`PARTIAL`** — Tier C closed, not a full pass. First round: 2 Critical (`ISS-2026-216` storage_path exposure, `ISS-2026-217` dual legal-hold mechanisms) + 1 High (`ISS-2026-218` legal-hold DELETE backstop) + 3 Medium (`ISS-2026-219`/`220`/`221`) defects fixed. Tier C: 1 more Critical self-inflicted gap in the first round's own trigger fixed (`ISS-2026-226`), 1 more High fixed (`ISS-2026-227`), 1 Medium-High validation gap fixed (`ISS-2026-228`), 1 finding self-corrected before commit (`ISS-2026-231`). 6 findings registered, not fixed, all outside this checkpoint's own charter: `ISS-2026-222` High + `229` Critical + `230` High (owner `HDN-386`); `ISS-2026-223`/`225` (corrected High)/`232` (owner `HDN-378`); `ISS-2026-224` Medium (owner `HDN-387`) | §8 |
| 9 | Security hardening | `HDN-378` | `NOT_RUN` | §9 |
| 10 | Performance / scalability | `HDN-379` | `NOT_RUN` | §10 |
| 11 | Accessibility | `HDN-380` | `NOT_RUN` | §11 |
| 12 | Browser / device compatibility | `HDN-381` | `NOT_RUN` | §12 |
| 13 | Observability | `HDN-382` | `NOT_RUN` | §13 |
| 14 | Backup / restore | `HDN-383` | `NOT_RUN` | §14 |
| 15 | Disaster recovery rehearsal | `HDN-384` | `NOT_RUN` | §15 |
| 16 | Data migration rehearsal | `HDN-385` | `NOT_RUN` | §16 |
| X | **Cross-cutting: CI-mirrors-hosted** | **all lanes** | `PASS` at kickoff | §17 |

---

## 1. Full regression — `HDN-370`

> **Result, 2026-08-23 (`CG-S15-HDN-002`, Tier C `VERIFIED`): `PARTIAL` — not a pass.** This is
> the checkpoint's own final, adversarially-reviewed verdict on the gate itself — `HDN-370`
> being `VERIFIED` means its review was done correctly, not that the underlying gate is fully
> green. It is not.
> Local gates are green (`typecheck` 0, `lint` 0 errors, `test` **5394/5394**, `db-tests`
> **229/229 ALL PASSED**, `next build` **246 routes, 0 errors**, governance gates clean), and
> this lane's owned repair (`HDN-BLK-002`) is closed at the root and **proven by sweep**.
> But the gate is **not** a pass, for two reasons recorded rather than smoothed over:
> **(a)** all three CI jobs failed on the most recent push to `main` (#109, `e5da061`), with
> two further prior push-to-`main` runs also showing `failure` at the workflow level though not
> individually root-caused (`HDN-BLK-007/008/009`), so **six governance steps — including the
> secret scan and the dependency vulnerability audit — have never executed in CI on a push**
> (a further step, Protected-path check, is PR-only-gated and would be absent from a push
> regardless); **(b)** `test:e2e` could not
> be executed here and is a `TRACKED_GAP`. Full evidence: `HDN-370.md`.
>
> **`next build` is not wired into CI at all** — a Phase 0 (`PH0-88`) decision taken when the
> repository had no application code, now covering 228 page routes, 13 API routes and 136
> `"use server"` modules. It passes when run directly, so this is a coverage gap, not a live
> breakage. Owner: `HDN-387`, with the other three CI repairs.

**Objective.** Execute and reconcile the full regression suite across Platform, Commercial,
Operations, Finance, Advanced TMS/WMS, Procurement, HRIS/Ticketing, Customer Portal/Loyalty
and Intelligence/Enterprise.

| Dimension | Seeded state at kickoff | Required of `HDN-370` |
|---|---|---|
| `typecheck` | 0 errors | Re-run, exact result |
| `lint` | 0 errors / 337 warnings | Re-run; the 337 is the standing pre-existing `@next/next/no-html-link-for-pages` class — do not "fix" it inside this lane |
| `pnpm run test` | 5394 tests, 5393 pass, 1 fail — `checkWorktreeCollision`, the known checkpoint-state-dependent non-defect | Re-run; expect 5394/5394 once a commit exists |
| `bash scripts/db-tests/run.sh` | **229/229 `ALL PASSED`**, Sunday 2026-08-23, ~11:15–11:45 UTC, 306 migrations, disposable DB | Re-run; record day of week **and** UTC time of day |
| `next build` | not run — this checkpoint touches no `app/`, `components/`, `"use server"` | Run it; `HDN-370` exercises UI-adjacent regression |
| `docs:check`, `security:check`, `git:check-paths` | clean | Re-run |
| E2E / browser | No live sign-in flow exists; `e2e/` runs only against synthetic fixtures and two unauthenticated public routes | `TRACKED_GAP` with the exact missing prerequisite — never a substituted pass |

### 1.1 The day-of-week / wall-clock fixture flake class — this lane owns closing it

Four registered issues, one defect family: a `scripts/db-tests/*.sql` fixture silently
assumes something about real wall-clock time that is not always true.

| Issue | File | Trigger dimension | State |
|---|---|---|---|
| `ISS-2026-103` / `ISS-2026-115` | `scripts/db-tests/hris-overtime-timesheet.sql` | day-of-week (Sat/Sun) | **CLOSED** — fixture pinned to the most recent weekday (`cdbccc7`). **This is the pattern to reuse.** |
| `ISS-2026-077` | `scripts/db-tests/hris-leave-permit-business-trip.sql` | wall-clock **and** day-of-week | `OPEN` |
| `ISS-2026-135` | `scripts/db-tests/hris-shift-roster-scheduling.sql` | day-of-week (a coverage rule keyed to `extract(dow from current_date)` can auto-generate a real assignment, which an unconditional "always null" negative control cannot tolerate) | `OPEN` |
| `ISS-2026-154` | `scripts/db-tests/hris-attendance.sql` | **time-of-day**: a ~1-hour real-UTC window immediately after each day's 21:00 UTC (04:00 Asia/Jakarta) shift-day boundary | `OPEN` |

**Kickoff observation, stated precisely.** All four files executed and passed in this
checkpoint's full run. That is **not** proof the class is closed:

- `ISS-2026-135`'s day-of-week dimension **was genuinely in play** — the run was a Sunday —
  and did not fire.
- `ISS-2026-077`'s dimension is wall-clock *and* day-of-week; the day half was in play, the
  wall-clock half was not controlled for.
- `ISS-2026-154`'s dimension was **not exercised at all**: its trigger window is ~21:00–22:00
  UTC and this run was ~11:15–11:45 UTC, roughly ten hours outside it.

So the correct kickoff status for this class is **`PARTIAL` — one dimension exercised and
not fired, one dimension not exercised.** A green suite on one Sunday morning is not
evidence of a day-independent gate.

**Required of `HDN-370`:** make each fixture's temporal assumption explicit and pinned, then
**prove day-independence rather than observe it** — e.g. by driving the resolver's inputs
directly across all seven days and across the shift-day boundary window, not by re-running
the suite and hoping. A regression baseline green only on some days of the week is not a
release gate.

> ### Amendment, 2026-08-23 (`CG-S15-HDN-002`) — **the table above is wrong, and is kept for the record**
>
> `HDN-370` re-derived every member from live evidence instead of accepting its issue text, and
> **three of the four were misclassified.** The trigger dimensions recorded above are corrected as:
>
> | Issue | Recorded above as | **Actually** | Real exposure |
> |---|---|---|---|
> | `ISS-2026-077` | wall-clock and day-of-week | **Timezone-boundary mismatch** — `current_date` resolves in the session timezone (`Etc/UTC`), `work_date` in the tenant policy's (`Asia/Jakarta`) | **196 / 672 swept instants — 29%, exactly 7 h every day** |
> | `ISS-2026-135` | day-of-week, via a `extract(dow from current_date)` coverage rule | **A hardcoded calendar date.** That coverage rule is in a *different* file; this fixture has no wall-clock coupling at all | **1 / 30 swept dates — `2026-08-18`, a Tuesday** |
> | `ISS-2026-154` | time-of-day, 04:00 Jakarta boundary | Confirmed exactly as recorded | 84 / 2,016 swept instants — 1 h every day |
> | `ISS-2026-103`/`115` | day-of-week | Confirmed — the only genuine day-of-week member | already closed at `cdbccc7` |
>
> All three open members are **fixed at the root and proven by sweep** (0 failing instants
> after the fix, all 7 weekdays). `ISS-2026-077`/`135`/`154` → `RESOLVED`. `HDN-BLK-002` is
> closed. The correct name for this family is **temporal-frame coupling**, not day-of-week
> flakiness: in every case a date was compared across two different frames of reference —
> session vs policy timezone, shift-day vs calendar-day, literal vs wall-clock date — without
> normalizing. Full evidence: `HDN-370.md` §5, §8.

### 1.2 Other pre-existing test-suite items seeded here

| Issue | Item | Note |
|---|---|---|
| `ISS-2026-144` | `scripts/db-tests/procurement-vendor-performance.sql:978` intermittent Phase 6 assertion | Passed this checkpoint. Confirm or re-register |
| `ISS-2026-156` | `scripts/db-tests/n8n-integration.sql:204` lookup has no `ORDER BY` | Non-manifesting in real alphabetical order (position 161 vs 227 of 229). Fragility, not a live defect |
| `ISS-2026-147` | Zero test coverage for the 9 `/api/v1` REST route handlers | Medium. Relevant to `HDN-376` too |

---

## 2. Cross-module transactional integrity — `HDN-371`

> **Result, 2026-08-23 (`CG-S15-HDN-003`), corrected at Tier C review:** the flow-level
> chains are reconciled against existing, currently-passing evidence (below), with
> **one honestly disclosed gap** — the loyalty/portal chain was not examined — and
> **one systemic finding**, made by a direct code-level sweep and then **live-forced
> and confirmed** by a real two-process race (`HDN-371.md` §6.3): `HDN-BLK-010`/
> `ISS-2026-162` — **9** genuine cross-module boundary functions
> (`prepare_/convert_/link_/create_from_` shape, enumerated exhaustively from all 306
> migrations, correcting an original count of 7 that missed 2 members of its own class)
> share an identical concurrent-idempotency gap that a sibling function,
> `prepare_wms_outbound_from_shipment`, already proves the fix for in this exact
> codebase (its own migration names the pattern "design note 9(a)"). **Domain
> breakdown: 5 Finance, 1 HRIS-Payroll, 1 Commercial, 1 Advanced TMS/WMS, 1
> Platform/Auth** (corrected from an original, imprecise "6 of 7 Finance-domain").
> Bounded to **Medium**, not Critical/High, by direct verification against the live
> schema: all 8 distinct backing tables carry a confirmed unique constraint or partial
> unique index, so no duplicate financial, handoff, WMS-inbound or identity-link
> record can be created — the real consequence, now **observed live**, is a raw,
> uncaught `unique_violation` surfaced to a genuinely-racing second caller instead of
> the graceful "already created" response every other caller gets. **Deferred to
> `HDN-374`** as a single batch (not fixed here), with the cross-domain scope of that
> deferral disclosed explicitly rather than silently assumed. A second, smaller,
> pre-existing production defect was also found and registered: `ISS-2026-163`
> (`app.prepare_job_order`'s exception handler can silently return an all-NULL row on
> an unrelated violation, Low). Full evidence: `HDN-371.md` §4-§7, §12.

| Chain | Seeded state | Result |
|---|---|---|
| lead → quote → job | Built and `VERIFIED` across Phases 2–3 | **Reconciled** — `prepare_job_order_handoff`/`prepare_job_order` traced end to end; both idempotent on their own key (one lacks the race-safe exception handler, `HDN-BLK-010`; the other's handler is present but defective, `ISS-2026-163`); existing db-test coverage (`commercial-job-order-lineage.sql`, `operations-job-order.sql`) confirmed passing at `HDN-370`'s 229/229 full regression |
| shipment → ePOD → billing | Phases 3–4 | **Reconciled** — `prepare_finance_invoice_from_readiness` (effective definition: `20260730540000_harden_finance_lifecycle_exits_and_reconciliation_basis.sql`) traced: `v_subtotal`/`v_currency` are a direct, unmutated copy of the job's own governed `revenue_snapshot`, never independently recomputed. Idempotent on `(tenant_id, billing_readiness_handoff_id, status <> 'void')`, backed by the partial unique index `finance_invoices_handoff_active_unique`; lacks the race-safe exception handler (`HDN-BLK-010`) — **live-forced race proven on this exact mechanism**, `HDN-371.md` §6.3 |
| actual cost → AP → settlement | Phase 4 | **Reconciled** — `prepare_finance_vendor_bill_from_actual_cost` and `prepare_finance_settlement` (effective definitions: `20260730540000` and `20260730390000` respectively) both idempotent on a real unique-constrained key; both lack the race-safe exception handler (`HDN-BLK-010`) |
| invoice → receipt → journal, reversal/correction | Phase 4 | **Reconciled.** `prepare_finance_journal_reversal`/`_adjustment` (effective definitions: both `20260730390000`) verified genuinely additive by direct code read — zero `delete from` in either the original or current defining file; both take `p_original_journal_id` and produce a new correcting record referencing it, never mutating or removing the original. Both lack the race-safe exception handler (`HDN-BLK-010`) |
| WMS inbound → outbound | Phase 5 | **Reconciled, and the source of the fix pattern.** `prepare_wms_outbound_from_shipment` has the correct, documented race-safe pattern; `prepare_wms_inbound_from_shipment` (its own earlier-created sibling) does not — a full member of `HDN-BLK-010`'s function list (corrected at Tier C review: originally described as "folded in" without actually being added to the blocker's own records) |
| customer portal / loyalty / tickets | Phases 7–8 | **Tickets reconciled** — `link_ticket_record`/`link_ticket_portal_record` both have the race-safe pattern, not implicated in `HDN-BLK-010`. **Loyalty and portal not examined by this checkpoint** — corrected disclosure, replacing an original overclaim of full reconciliation; tracked as an open gap, no current owner |
| Idempotent retry at every module boundary | `ISS-2026-029` closed 27 functions / 29 idempotency short-circuits at `ATW-031` | **Re-proven, and a live gap found.** Sequential idempotency (retry returns the original, ignores new params) confirmed intact and enforced at existing call sites (~131 occurrences across ~60 files for the originally-named 7). Concurrent-race safety was the untested half — swept directly, 9/20 gapped (`HDN-BLK-010`) |
| Concurrent submission | Phase 9 Tier C re-reproduced concurrency/CHECK-bypass fixes | **Reconciled — live-proven.** `HDN-BLK-010` is exactly this dimension for the applicable cross-module boundary functions; a two-process race was forced and confirmed live against `link_auth_identity` (`HDN-371.md` §6.3), observing the exact raw `unique_violation` the finding predicts. Not re-run individually against all 9 functions — the mechanism is identical and confirmed by direct code read for the other 8 |
| Source-domain ownership conflicts | None open | **None found**, independently re-confirmed by two Tier C review lenses attempting to find a counterexample (including stress-testing the strongest candidate, `app.sourcing_requests`'s two writers, confirmed as genuine governed co-ownership). `HDN-BLK-010` is a defect (an inconsistently-applied safety pattern), not an ownership conflict — no two modules claim authority over the same canonical entity |

**Hard gate:** `HDN-371` must be `VERIFIED` before `HDN-374`, `HDN-375` and `HDN-376` begin.

---

## 3. Tenant isolation — `HDN-372`

> **Status: `PARTIAL`** — not a pass. See the gate-vocabulary table above.
>
> **Result, 2026-08-23 (`CG-S15-HDN-004`), amended at this same checkpoint's own Tier C
> review:** four independent parallel adversarial investigations (DB/RLS/grants;
> API/service layer; storage/jobs/cache/reports; support/AI/webhooks/audit), each with
> its own live two-tenant fixture, found and **fixed at the root, same checkpoint**, a
> real cross-tenant read defect class: **`HDN-BLK-011`/`ISS-2026-164`** — 13 `SECURITY
> DEFINER` functions (9 found first, 4 more found by this checkpoint's own Tier C
> security/tenant review and fixed in a second migration; protecting 24 total once 11
> further transitively-dependent functions are counted) evaluated authority against a
> client-supplied actor UUID rather than the verified session identity, live-forced
> against `app.get_self_employee` (full employee PII), the `ATW-023`/`ATW-016`
> owner-scope families (customer inventory/warehouse/order data), the audit trail,
> notifications, custom-field content, and approval steps. **High**, not Critical — no
> write path affected, and live-confirmed against the real deployed project that `app`
> is not currently exposed via the Data API (a pre-deployment state, not a durable
> control). Fixed at
> `supabase/migrations/20260810000000_harden_tenant_isolation_actor_identity_gaps.sql`
> and `..._round2.sql`, live re-verified post-fix (both direct and transitive) and now
> also backed by a genuine committed live two-session forced-spoof regression test (not
> only pasted console output), full 229-file db-test suite re-confirmed green after
> fixing two genuine pre-existing test-fixture regressions the fix surfaced. **Two
> same-shape findings remain genuinely open, both release-blocking for Step 16 per
> `00_EXECUTION_INDEX.md` §8.1 until fixed or explicitly ruled an accepted exception at
> `HDN-387`/`HDN-389`:** `HDN-BLK-012`/`ISS-2026-165` (13 dashboard functions, no common
> root) and `HDN-BLK-014`/`ISS-2026-179` (~24 further candidate functions, only 3
> individually live-verified) — both handed to `HDN-373` with the exact function
> lists and fix pattern already established. **One further High app-layer finding**
> (`HDN-BLK-013`/`ISS-2026-166`, the app layer's sole reliance on the database as a
> single point of failure on several high-privilege actions) was registered in
> `KNOWN_ISSUES.md` since this checkpoint's first commit but had no `BLOCKER_LEDGER`
> entry until this Tier C review corrected it — owner `HDN-378`, also release-blocking.
> **13 further Medium/Low findings** registered with named owners across
> `HDN-373`/`376`/`377`/`378`/`379`/`382` — see `HDN-372.md` §7-§9. Full evidence:
> `HDN-372.md`.

| Surface | Seeded state | Result |
|---|---|---|
| Database / RLS | 568 tables RLS-enabled, 448 policies on the live project | **Reconciled.** Whole-schema posture census: `authenticated` holds `SELECT` only on 407 tables, zero write grants anywhere in `app`; exhaustive tautology scan of all 448 policies found zero self-comparison bugs; every write necessarily routes through a `SECURITY DEFINER` function, which is why real risk concentrated in the function surface (`HDN-BLK-011`/`012`), not raw table grants |
| PostgREST exposure | `app` is **not** in the Data API's `db_schema` (`public,graphql_public`), so no `app` table is reachable over PostgREST regardless of RLS | **Confirmed still true, live, against the real deployed project** (`awdlicmwzdxquopwtcfd`) — `curl` with `Accept-Profile: app` → `PGRST106 Invalid schema: app`. Extended: this also means no `app.*` RPC is directly callable, not only tables — the finding this checkpoint's own note below explains why that is disclosed as a configuration state, not a substitute for RLS/identity checks |
| Storage, cache, queue, reports, exports, jobs, integrations, AI context | Built across Phases 1–9 | **Reconciled**, with 6 registered Low/Medium findings (`ISS-2026-171..176`) — no signed-URL machinery exists yet (nothing to bypass), no shared caching layer exists yet except one dormant untenanted cache key, job/queue tenant binding confirmed immutable and re-validated at every hop, report/export functions all tenant-filtered with zero `select("*")` C-17 defects found |
| Support / impersonation | Purpose- and time-bound, logged, revocable | **Reconciled** — live-tested structurally incapable of crossing a tenant boundary (`tenant_id`/`grantee_auth_user_id` both `NOT NULL` FKs); one granularity gap registered (`ISS-2026-177`, session-open events absent from the canonical audit surface) |
| Exception message leakage | **`ISS-2026-146`** — cross-tenant `tenant_id` disclosure via exception text, 2,087+ occurrences since Phase 6, reproduced live | **Re-confirmed and extended.** This checkpoint's own `ISS-2026-167` is the same defect class, live-proven end to end (`create_quotation_draft`) with an exact reproduction and the correct in-repo counter-pattern to copy (`app.get_customer_shipment_tracking`'s merged anti-enumerating error). Both issues describe the same root cause; `HDN-376` (API Compatibility Audit, `ISS-2026-167`'s named owner) should treat them as one remediation, not two |
| SSO config enumeration | **`ISS-2026-149`** — `app.resolve_enterprise_idp_by_email_domain` is an unthrottled, anonymous, cross-tenant enumeration oracle | Not re-examined this checkpoint (out of this lane's four investigation lenses' scope); remains seeded for `HDN-378` |

**Hard gate:** `HDN-372` must be `VERIFIED` before `HDN-373` and `HDN-378` begin.

---

## 4. RLS / RBAC — `HDN-373`

> **Status: `PARTIAL`** — not a pass, Tier C review pending. See the gate-vocabulary table
> above.
>
> **Result, 2026-08-23 (`CG-S15-HDN-005`), `COMPLETED`:** seven migrations, seven
> independent findings, each live-forced before being fixed. **Headline**:
> `app.evaluate_permission` (the root RBAC gate, ~1,124 callers) never checked tenant
> membership at all — `app.tenant_user_identities`/`app.has_active_tenant_membership`
> and `app.role_assignments` are separate tables with no FK/trigger cascade, and
> `app.revoke_auth_identity` touches only the former, so a genuinely revoked ex-member
> retained every role-based permission indefinitely. Live-confirmed end to end. **Fixed**
> at `supabase/migrations/20260810300000_harden_rbac_evaluator_tenant_membership_check.sql`
> (`ISS-2026-180`). **Largest finding of Step 15 to date**: the entire Finance
> manual/period/config/import-export write surface — 95 functions (76 top-level entry
> points plus 19 `check_finance_*_authority` helpers) plus `app.enqueue_job` — was
> `SECURITY INVOKER` instead of `SECURITY DEFINER`, completely unreachable by any real
> `authenticated` session since it shipped; live-forced against a genuine Finance
> Manager session refused three call frames inside `evaluate_permission` itself. **Fixed**
> at `supabase/migrations/20260810700000_harden_finance_authority_chain_security_definer.sql`
> (`HDN-BLK-015`/`ISS-2026-182`), together with two companion findings its own
> fix-and-verify cycle surfaced: `ISS-2026-183` (`create_and_post_finance_system_journal`
> had no authority check of its own) and, at
> `supabase/migrations/20260810800000_harden_finance_journal_view_gate_and_self_approval.sql`,
> `ISS-2026-184` (`finance_journals`/`finance_journal_lines` RLS bypassed `FIN:View`
> entirely) and `ISS-2026-181` (Finance journal self-approval, sharing `ISS-2026-139`'s
> shape). **Carried forward from `HDN-372` and closed**: `HDN-BLK-012`/`ISS-2026-165` (13
> dashboard functions, fixed — 5 of the 13 additionally closed a field-masking bypass,
> not merely a record-scope widening); `HDN-BLK-014`/`ISS-2026-179` (~30 candidates: 16
> confirmed terminal/self-referential and fixed; ~14 confirmed genuinely called with
> third-party actor arguments elsewhere in the schema, re-registered narrower as
> `ISS-2026-186`, not blindly fixed); `ISS-2026-171`/`173` (own-row RLS gaps on
> `notifications`/`saved_report_views`, fixed, plus one further instance found and fixed
> in the same migration — `ISS-2026-185`, `notification_preferences`). `ISS-2026-139`
> (loyalty redemption maker/checker collapse, seeded here) confirmed live-forced and
> fixed. `ISS-2026-137` independently re-verified — existing disposition (`OPEN`, Low,
> "no live vulnerability, only a missing correction path") confirmed accurate, no
> change. **Six further findings registered, not fixed, each with a named forward
> owner**: `ISS-2026-186` (~14 residual shared RBAC primitives); `ISS-2026-187`/`188`
> (support-access gaps, owner `HDN-378`); `ISS-2026-189` (`employees` column-grant,
> judgment call); `ISS-2026-190` (a sibling of `ISS-2026-184`'s exact shape on
> `performance_calibration_adjustments_select_scoped`, HRIS domain, out of this
> checkpoint's Finance scope); `ISS-2026-191` (doc-drift); `ISS-2026-192`
> (`principal_memberships` self-record variant, likely by design). Full 229-file
> `scripts/db-tests` suite passes clean against a fresh disposable database with real
> grants (no superuser-only bypass); `typecheck`/`lint` both clean. **`COMPLETED`, not
> `VERIFIED`** — Tier C review pending before this gate can close. Full evidence:
> `HDN-373.md`.

| Scope | Seeded state | Required |
|---|---|---|
| Four-layer access model | Supreme Admin, User Admin, internal hierarchy, Customer User — built at Platform Core | Positive **and** negative matrix per module/action/field/record/status/amount/scope |
| `SECURITY DEFINER` posture | 1,878 functions, **100% pinned search_path**, 0 with mutable search_path, 0 mutable + anon/auth-callable | Re-verify; this is a real, measured property, not an assumption |
| `function_search_path_mutable` advisories | 791 — **all `security invoker`**, so no privilege to escalate | Do not "fix" as a batch; confirm the invoker property still holds |
| `rls_enabled_no_policy` | 120 — INFO, default-deny by design | Confirm intent per table |
| Field masking (finance, payroll, personal, tax, bank, margin, support, AI evidence) | Built per phase | Verify |
| Supreme Admin absolute CRUD | **RPD-022 ratified accepted residual risk** | Must be **disclosed**, never weakened silently, and never described as tamper-proof or immutable-for-all |
| Maker/checker collapse | **`ISS-2026-139`** — `LYL:Edit` alone can submit **and** instantly auto-fulfill a `discount_voucher` redemption for any loyalty account in the tenant | **Fixed at `HDN-373`** — live-forced and confirmed exactly as described (a "Redemption Clerk" role holding only `LYL:View/Create/Edit`, explicitly not `Configure`, walked two unrelated accounts' real points into real vouchers in one session, zero second reviewer). `supabase/migrations/20260810600000_harden_loyalty_redemption_maker_checker.sql` requires `LYL:Configure` before the auto-compose branch proceeds, identical to the check `decide_loyalty_redemption` already performs; lacking it falls back gracefully to `pending_approval` via the existing established mechanism |
| Supreme-Admin-override gap | **`ISS-2026-137`** — `app.loyalty_account_tier_movements` missed from `ISS-2026-130`'s fix scope | **Independently re-verified at `HDN-373`** — the table is actually MORE locked down than its siblings (missing both the append-only trigger and any `UPDATE`/`DELETE` grant at all, so a Supreme Admin cannot correct tier history today), confirming the existing disposition (`OPEN`, Low, "no live vulnerability, only a missing correction path") is accurate. No change made |
| Actor-identity-forgery class, deferred from `HDN-372` | **`HDN-BLK-012`/`ISS-2026-165`** (High) — 13 dashboard functions (`app.get_ops_dashboard_*` ×6, `app.get_dashboard_*` ×7) share `HDN-BLK-011`'s exact defect shape (no `assert_actor_is_session_identity`), no common root to fix once. **`HDN-BLK-014`/`ISS-2026-179`** (Medium) — ~24 further boolean-oracle/narrow-scope candidate functions from a wider closure sweep, only 3 individually live-verified (`resolve_locale_context`, `has_active_tenant_membership`, `actor_holds_customer_user_layer`) | **`HDN-BLK-012` fixed at `HDN-373`** — `supabase/migrations/20260810200000_harden_dashboard_actor_identity_gaps.sql`, all 13 converted `language sql` → `plpgsql` carrying `assert_actor_is_session_identity`; 5 of the 13 additionally closed a genuine field-masking bypass (cost/margin/selling-price entitlements gated on the same forged parameter), not merely a record-scope widening. **`HDN-BLK-014` narrowed, not closed** — of ~30 candidates (not ~24; the candidate list grew once every actual call site was grepped), 16 confirmed terminal/self-referential and fixed at `supabase/migrations/20260810400000_harden_crm_ops_actor_identity_gaps.sql`; ~14 (`has_active_tenant_membership`, `can_access_record`, `is_supreme_admin`, `actor_holds_customer_user_layer`, and others) confirmed genuinely called with THIRD-PARTY actor arguments elsewhere in the schema — an unconditional assert would break those legitimate uses, so they are re-registered narrower as `ISS-2026-186`, needing a per-call-site audit, owner a future checkpoint. Full detail `HDN-373.md` §5, §6.1 |
| RLS gaps post-revocation, deferred from `HDN-372` | **`ISS-2026-171`** — `app.notifications` RLS has no tenant-membership conjunct, a revoked ex-member retains read access to past notifications. **`ISS-2026-173`** — same shape, `app.saved_report_views`. **`ISS-2026-176`** — 35 `authenticated`-readable views bypass base-table RLS by construction, structurally fragile (no current leak, no mechanical gate to catch a future regression) | **`171`/`173` fixed at `HDN-373`** — `supabase/migrations/20260810500000_harden_own_row_rls_membership_gap.sql` adds the missing tenant-membership conjunct, mirroring the already-correct `notification_contact_addresses_select_own` reference pattern; one further instance found and fixed in the same migration (`ISS-2026-185`, `app.notification_preferences`, identical shape). **`176` re-confirmed, unchanged** — 35/37 views correctly bypass base RLS by construction with a correct predicate of their own; still no mechanical sweep to catch a future regression, not built this checkpoint |

---

## 5. Financial integrity — `HDN-374`

| Dimension | Seeded state | Required |
|---|---|---|
| 24 financial-integrity scenarios (or repository equivalents) | Phase 4 `VERIFIED` | Run and reconcile |
| quote → cost → job → shipment → ePOD → invoice → payment → journal → AP → settlement → loyalty liability | Built | Reconcile end to end |
| Period lock, reversal, correction, duplicate retry, concurrency, rounding | Built | Test edges |
| Idempotency reversal defect | `ISS-2026-029`: `apply_finance_ar_allocation` / `reverse_finance_ar_allocation` wrote the same table under the same unique key, so reusing a key to **reverse** silently did nothing and returned success. Closed at `ATW-031` | **Regression-prove it stays closed** |
| Loyalty liability currency scoping | **`ISS-2026-136`** item 2 still `OPEN` | Seeded here |
| RPD-016 statutory gates | Indonesia tax/payroll requires current dated SME/legal evidence, configurable | Verify gating, do not activate without evidence |
| Concurrent-idempotency gap, 9 boundary functions across 5 domains (corrected at `HDN-371`'s own Tier C review from an original count of 6 Finance-only) | **`HDN-BLK-010` / `ISS-2026-162`**, found and bounded to Medium, **live-forced-race proven**, at `HDN-371` — `prepare_finance_invoice_from_readiness`, `_journal_adjustment`, `_journal_reversal`, `_payroll_disbursement_handoff_from_payroll_run` (HRIS-Payroll-owned), `_settlement`, `_vendor_bill_from_actual_cost` (5 Finance + 1 HRIS-Payroll), plus `prepare_job_order_handoff` (Commercial), `prepare_wms_inbound_from_shipment` (Advanced TMS/WMS) and `link_auth_identity` (Platform/Auth) each have an idempotency short-circuit with no `unique_violation` exception handler around the subsequent `insert`. Every target table has a confirmed backing unique constraint or partial unique index (no duplicate-truth risk); the exposure is a raw uncaught error for a genuinely racing caller — **observed directly**, `HDN-371.md` §6.3 | **Finance/HRIS-Payroll portion (6 functions) fixed at `HDN-374`, plus 4 more that checkpoint's own wider sweep found (10 total)** — the 3 non-Finance functions (Commercial/WMS/Platform-Auth) plus `ISS-2026-163` handed to `HDN-387`, explicitly out of `HDN-374`'s own Financial Integrity charter. Mirrored `prepare_wms_outbound_from_shipment`'s proven "design note 9(a)" nested-exception shape into each function, one additive migration, 2 mechanisms live-forced with a genuine two-process race each. Full evidence: `HDN-371.md` §4-§7, §12; `HDN-374.md` §6.3 |

> **Result, 2026-08-23 (`CG-S15-HDN-006`), `VERIFIED`, Tier C closed:** three additive
> migrations, four independent parallel investigation lenses, each required to
> live-force its own findings on disposable databases. Cost/AP chain, payment/journal
> reconciliation, period lock, reversal, correction, rounding, tax snapshotting,
> payroll-handoff aggregation, and RPD-016's statutory gates all held clean in the first
> round. **4 real, live-forced defects fixed**: `ISS-2026-194` (High, quote-level tax
> silently doubled at invoicing); `ISS-2026-195` (High, a job order could reach `issued`
> on two full-amount invoices from two distinct handoffs — the first fix draft was
> self-corrected before commit, since it would have broken `OPS-181`'s own disclosed
> legitimate-re-handoff allowance; the shipped fix gates `app.issue_finance_invoice`, the
> actual AR/GL posting boundary); closes `HDN-BLK-010`/`ISS-2026-162`'s Finance/HRIS-
> Payroll scope (10 functions, 2 mechanisms live-forced with a genuine two-process race
> each); `ISS-2026-196` (Medium, `app.run_loyalty_expiry_sweep`'s own `p_as_of` silently
> ignored, now threaded through). **Tier C review (4 independent adversarial lenses)
> found 5 more real, live-forced defects, 3 fixed same checkpoint**: `app.lock_finance_
> period` shared the sweep's own missed idempotency-race shape (Medium, fixed); Finding
> 1's own fix dropped the quote's own discount, overbilling by that amount (High, fixed
> — the genuine pre-tax base is `subtotalAmount - discountAmount`, not `subtotalAmount`
> alone); Finding 2's own new guard had no backing constraint and did not survive genuine
> concurrency, live-forced to still double-bill (High, fixed with a real backing partial
> unique index, `finance_invoices_job_order_issued_unique`); `app.request_finance_
> settlement_reversal` bypassed fiscal period lock entirely (High, fixed, mirroring
> `post_finance_settlement`'s own check) **and posts no reversing GL journal at all**,
> permanently desyncing GL from AP on every reversal (High, **registered, not fixed** —
> `ISS-2026-199`/`HDN-BLK-016`, owner `HDN-386`). One disclosure correction (`ISS-2026-198`,
> Medium, already fixed but undisclosed) and one ledger-consistency finding also
> corrected. **2 findings registered, not fixed** (`ISS-2026-197`, Low, owner `HDN-386`):
> no FX/multi-currency conversion anywhere in the revenue chain; Operations' own
> `app.calculate_job_profitability` planned-vs-actual figure split. No Critical finding
> anywhere. Independent full gate re-run green after the complete fix pass: `typecheck` 0,
> `lint` 0 errors/337 warnings, 5394/5394 unit tests, 229/229 db-tests (319 migrations).
> Full disposition: `HDN-374.md` §13.

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 6. Data lineage — `HDN-375`

| Dimension | Seeded state | Required |
|---|---|---|
| lead → payment → loyalty lineage | Built | Map canonically |
| Downstream projections reference source entity + version + refresh time | Per-phase | Verify each |
| Historical config preservation on critical transactions | Ratified: configuration is versioned/effective-dated; critical transactions retain the applied version | Verify |
| Transaction-lineage hash-chain triggers | 5 of them were among the 20 functions broken by the pgcrypto defect — now fixed | Re-prove they actually chain |
| Reports / dashboards / AI outputs / exports carry lineage metadata | Phase 9 | Inspect |
| Orphan records / projections | none known | Register as blockers |

> **Result, 2026-08-24 (`CG-S15-HDN-007`), `VERIFIED`, Tier C closed:** four independent
> parallel lenses (correctness re-derivation; schema-wide completeness sweep;
> ledger/documentation consistency; permission-awareness/attack-surface adversarial
> testing), each required to live-force its own findings on disposable databases. All 3
> first-round findings confirmed real and correctly disposed of; both shipped fixes
> confirmed solid under live adversarial attack — full role/permission matrix, `NULL`
> actor context, audit-capture correctness (fail-closed, not silently no-op-able), the
> theoretical-only `TRUNCATE`-bypass angle, and exhaustive `source_type` coverage all held.
> **1 documentation-completeness gap corrected**: §6.2's own first-round text had silently
> omitted `ISS-2026-203` (already registered in `KNOWN_ISSUES.md`) from its own outcome
> count. **1 repeated ledger inconsistency corrected**: 5 files conflated "3 fixture
> corrections" with "3 files" (the actual commit touched 2) — corrected in all 5.
> **2 new, real, in-charter findings found and registered, not fixed**: `ISS-2026-205`/
> `HDN-BLK-018` (High, owner `HDN-386`) — only 13 of ~90+ append-only/audit/ledger-shaped
> tables in schema `app` carry a real `BEFORE UPDATE/DELETE` guard trigger; ~70 more,
> live-forced-reachable, do not, most severely `app.audit_logs` itself (the audit trail
> every other detective control, including this checkpoint's own new guard, depends on);
> `ISS-2026-206` (Medium, owner `HDN-387`) — the orphan-`source_id` gap `ISS-2026-202`
> closed on 2 tables recurs on `app.finance_subledger_batches` and others. **A fix draft
> for the `finance_subledger_batches` gap was written, then discovered before commit to
> break `scripts/db-tests/finance-subledger.sql`'s own pre-existing, deliberate test
> design (~15 call sites exercising the posting primitive in isolation with synthetic
> source ids) — self-corrected, the draft discarded rather than shipped broken or
> hastily patched**, mirroring `HDN-374`'s own Finding-2 self-correction precedent. No
> Critical finding anywhere. Gate state unchanged from the first round since no code
> changed in this Tier C pass — re-confirmed independently by 2 of the 4 lenses' own live
> testing. Zero migration, zero application code, zero contract, zero route in this Tier
> C pass. Full disposition: `HDN-375.md` §13.

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 7. API compatibility — `HDN-376`

| Dimension | Seeded state | Required |
|---|---|---|
| REST `/v1` surface | 9 route handlers exist; **`ISS-2026-147`: zero test coverage for them** (Medium) | Seeded here — this gate cannot pass while its primary surface is untested |
| GraphQL parity | **Corrected at `HDN-376` (live-forced): no GraphQL surface exists in this repository at all** — no `graphql` package dependency, no schema, no resolvers, no `app/api/graphql` route. `server/policies/graphql-complexity.ts` is a depth/complexity-limiter policy module pre-built for a future GraphQL server that was never built. The prior "Ratified as developed together with REST" wording was misleading — there is nothing to hold parity with today, not a broken parity relationship | Not a defect (nothing is exposed, nothing is broken); disclosed precisely rather than implying an existing parity relationship. Re-verify at whichever future prompt actually ships a GraphQL server |
| Public / customer / vendor API | Phase 9 (`IAE`), built on `PLT-129` API-key primitives (hash-only storage, scope-narrowing via `app.evaluate_permission()`) | Compatibility + deprecation tests |
| Webhooks — outbound delivery worker on `app.jobs`; inbound third-party-GPS receiver kept separate | Phase 9 / `ADR-0025` B | Signing, replay, retry, DLQ |
| Idempotency, rate limit, error shapes, pagination | Built | Test |
| Schema/migration compatibility plan | Additive / expand-and-contract only | Verify |

> **Result, 2026-08-24 (`CG-S15-HDN-008`), `VERIFIED`, Tier C closed:** two additive
> migrations, four independent parallel investigation lenses in the first round plus four
> independent parallel adversarial lenses at Tier C, each required to live-force its own
> findings on disposable databases or real request/response construction. **Standout
> finding, Critical, fixed**: `app.verify_third_party_provider_webhook_signature`
> (inbound third-party GPS webhook gate) returned SQL `NULL`, not `false`, for a null
> signature — `if not verify_...()` silently treated that as verified, so a fully
> unsigned webhook was accepted as genuine; live-forced a real telemetry report inserted
> with `p_signature => null`, `anon`-reachable directly via PostgREST, entirely bypassing
> the app-layer check. Directly violated Prompt 376 §24 ("unsigned callbacks fail").
> Fixed by mirroring 2 sibling functions' own already-proven null/empty-signature guard
> (`ISS-2026-209`). The identical latent defect in `app.verify_webhook_signature`
> (PLT-129, not currently live-exploitable, zero live caller) also fixed for consistency
> (`ISS-2026-210`, High). **2 more real defects fixed** (`ISS-2026-211`/`212`, both Low):
> a webhook-domain error code leaking onto 2 non-webhook mutation routes; `stale_version`
> conflating a 400 malformed-input case with a real 409 conflict on 3 routes.
> **`ISS-2026-147` item 1 closed**: 9 REST `/v1` route handlers had zero dedicated
> HTTP-layer test coverage — built a shared, reusable fetch-stubbing test harness (this
> environment has no local PostgREST/Supabase stack, and `authorizeApiV1Request()`
> constructs a real, non-injectable Supabase client, so the harness stubs `globalThis.
> fetch` at the exact network boundary while every route's own real request
> parsing/validation/response-shaping logic runs for real) plus 44 new tests across all
> 9 routes. GraphQL wording corrected (live-forced: no GraphQL surface exists in this
> repository at all). **Tier C review found and fixed 1 more real defect**: `ISS-2026-215`
> (Low) — `GET /api/v1/vendor/rfqs/{id}` and `GET /api/v1/customer/shipments/{id}/
> tracking` both blanket-mapped every RPC failure to a 404 not-found response, silently
> conflating a genuine internal/transient RPC error with the real "does not exist" case;
> fixed by classifying `VendorApiError` (previously unclassified) and branching
> `CustomerShipmentTrackingQueryError` the same way its own already-classified
> `record_not_found`/`actor_identity_mismatch` codes imply 404, with 2 new regression
> tests. **1 documentation-citation error corrected**: the first-round migration's own
> `comment on function` mislabeled this checkpoint as "HDN-376 (Data Lineage/API
> Compatibility Audit)" — "Data Lineage Audit" is `HDN-375`'s own name; corrected via an
> additive `comment on function` restatement, no schema/behavior change. **4 findings
> registered, not fixed**: `ISS-2026-207` (Medium, owner `HDN-387`) — the `app.
> api_versions` deprecation registry has zero live effect on real requests, not a Step 16
> blocker since only `v1` exists and is active; `ISS-2026-208` (Low, owner `HDN-387`) —
> `accept`/`decline_vendor_assignment_invitation_via_vendor_api` lack an idempotency-key
> short-circuit, a fix draft was investigated and found NOT to mechanically mirror the
> established pattern (the table's own existing `idempotency_key` column already serves a
> different purpose); `ISS-2026-213` (Low, owner `HDN-386`) — 6 self-approval-shaped
> `SECURITY DEFINER` functions share the same equality-comparison shape as the fixed
> webhook defect but are confirmed safe today (an authority gate already excludes a NULL
> actor before reaching that comparison), registered as defense-in-depth after live-forcing
> found no bypass; `ISS-2026-214` (Low, owner `HDN-387`) — 4 routes leak a raw Zod
> validation-error shape instead of the repository's own standard error envelope. A
> pre-Step-15 migration-editing historical fact (3 commits, 86 files, predating `HDN-369`)
> reconciled against the additive-only rule with one acknowledging sentence in
> `00_EXECUTION_INDEX.md` §2.2, no fix required. No Critical finding residual anywhere.
> Independent full gate re-run green post-Tier-C: `typecheck` 0, `lint` 0 errors/337
> warnings, 5440/5440 unit tests (+2 new regression tests), db-tests **228/229 files
> clean** (322 migrations) — the 229th the same pre-existing, unrelated `ISS-2026-204`
> flake, re-confirmed still within its documented UTC `[1,4)` window. Full disposition:
> `HDN-376.md` §13.

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 8. Storage / signed URL — `HDN-377`

| Dimension | Seeded state | Required |
|---|---|---|
| Private file metadata | `PLT-128` — content bytes never stored in the database; `storage_path` is the object key | Inventory every upload/download/preview/OCR/export surface |
| Malware scan gate before release to another user | Ratified mandatory (RPD-032); `malware_scan_status` must be clean before `app.authorize_file_access()` grants a signed download to anyone but the uploader | **Block release on any unscanned downloadable private file** |
| Signed URL expiry, scope, revocation, replay resistance | Designed | Test |
| Real Supabase Storage integration | **Disclosed `NOT_RUN`** — no running application exists | `TRACKED_GAP`, not a substituted pass |
| Retention / legal hold (RPD-025) | **`ISS-2026-142`** — retention/legal-hold classification unbuilt for every Phase 8 Portal/Loyalty table incl. all 6 append-only Loyalty ledgers | Seeded here |

**Upstream:** `HDN-372`.

> **Result, 2026-08-24 (`CG-S15-HDN-009`), `VERIFIED`, Tier C closed:** two additive
> migrations, four independent parallel investigation lenses in the first round plus
> four independent parallel adversarial lenses at Tier C, each required to live-force
> its own findings. No live Supabase Storage integration exists anywhere in this
> repository (confirmed by exhaustive grep), narrowing several findings' exploitability
> to metadata/key disclosure today rather than actual byte exfiltration — several
> become live download-bypass primitives the moment Storage is wired up. **First round,
> 2 Critical fixed**: `app.files.storage_path` (the real Supabase Storage object key)
> carried a full table-level SELECT grant to `authenticated` with no column-level
> mask, found independently by 3 of 4 lenses — fixed mirroring `app.users`/`email`'s
> own proven column-level carve-out, plus a new `FileSummary` contract type
> (`ISS-2026-216`). Two independently-built legal-hold mechanisms for files
> (PLT-128-native vs IAE-031 generic) were unaware of each other in both directions —
> fixed by bridging `app._is_under_legal_hold()` (`ISS-2026-217`). **1 High fixed**:
> `app.files.legal_hold` enforced only inside one RPC with no schema-level backstop —
> fixed with a `BEFORE DELETE` guard trigger mirroring `HDN-375`'s own proven RPD-022
> pattern (`ISS-2026-218`). **3 Medium fixed**: vendor evidence-access RPCs leaking
> `file_id` on denial (`ISS-2026-219`); 2 Procurement tables' RLS bypassing
> `PRC:View`/`PRC:Download`, the same class `HDN-373` fixed for `app.finance_journals`
> (`ISS-2026-220`); a vendor-assessment upload wrong-client bug mirroring an
> already-fixed sibling (`ISS-2026-221`). **2 new taxonomy classes added**: C-25 (dual
> independently-built enforcement mechanisms unaware of each other) and C-26 (an
> RPC-level check with no schema-level backstop).
>
> **Tier C review found a Critical, self-inflicted bypass in the first round's own new
> trigger**: `app.protect_files_legal_hold_from_deletion()` checked only the native
> `legal_hold` flag, never the bridged generic mechanism the SAME migration added
> elsewhere — a generically-held file could still be physically destroyed via a raw
> `service_role` DELETE with zero audit trail; fixed same Tier C pass (`ISS-2026-226`).
> **2 more same-domain gaps fixed**: the legal-hold check had no backstop against the
> UPDATE-based soft-delete path (`ISS-2026-227`, High); `scope_record_table` was
> unvalidated free text, silently creating a non-protecting hold on a case/whitespace
> variant, now normalized and validated (`ISS-2026-228`, Medium-High). **1 finding
> drafted then self-corrected before commit**: a matching scan-status backstop trigger
> was found to break 4 pre-existing, deliberately-designed tests across other domains
> relying on a session-context-free raw-UPDATE correction path; discarded, registered
> instead (`ISS-2026-231`, Medium, owner `HDN-386`) — mirrors `HDN-374`/`375`'s own
> self-correction precedent. **2 new, real, out-of-charter findings registered**:
> `app.audit_logs.legal_hold` enforced nowhere, a legally-held audit row physically
> deleted (`ISS-2026-229`/`HDN-BLK-020`, Critical, owner `HDN-386`); `app.tenants.
> legal_hold` unbridged, a held tenant terminated successfully (`ISS-2026-230`/
> `HDN-BLK-021`, High, owner `HDN-386`). **1 first-round disposition corrected**: Tier C
> independently found 60 (not "most safe") Procurement/HR tables with a real
> `authenticated` grant, ~35 confirmed RLS-bypass-exploitable, 2 live-forced —
> `ISS-2026-225`/`HDN-BLK-022` corrected from Low to High, owner unchanged `HDN-378`.
> **1 more out-of-charter finding registered**: 3 more `token_hash` columns share
> `ISS-2026-216`'s own exposure class (`ISS-2026-232`, Medium, owner `HDN-378`).
> Several documentation miscounts corrected across 9 ledger files (a self-contradicting
> "2 Medium"/"3 Medium" line, a "6 files" miscount propagated into 5 documents, 2
> `CHANGE_MANIFEST.md` overcounts, 1 stale `BLOCKER_LEDGER.md` footer). No Critical
> finding fixed-vs-registered residual — the one registered Critical is a pre-existing,
> out-of-charter `app.audit_logs` gap bundled with the already-owned `HDN-BLK-018`
> work. Independent full gate re-run green post-Tier-C: `typecheck` 0, `lint` 0
> errors/337 warnings, 5440/5440 unit tests, db-tests **228/229 files clean** (324
> migrations) — the 229th the same pre-existing, unrelated `ISS-2026-204` flake. Full
> disposition: `HDN-377.md` §13.

---

## 9. Security hardening — `HDN-378`

**This lane carries the single most important carry-forward item in Step 15.**

| # | Item | Severity | Disposition required |
|---|---|---|---|
| 1 | **`ISS-2026-150` — IP restriction structurally unreachable.** RPD-023's enforcement is real and correct when called directly, but **no real client IP is threaded through the route-handler layer**, so a fully-configured `enforced`-mode allowlist gives zero real protection against a caller reaching the RPC layer directly (leaked service credential, compromised client bypassing the intended HTTP path). | **High** | **Must not be deferred again.** Phase 9's closure disclosed it as a deliberate first-of-its-kind accepted exception and **named Step 15 as the remedy**. Needs: (a) route-handler-level IP extraction and threading; (b) `assert_ip_allowed` wired into the bounded set of highest-risk SEC/IAM/INTHUB mutations; (c) an explicit ruling on service-role/background callers with no client IP (likely exempt — IP restriction is inherently an interactive-session control). A cosmetic partial wire-up is forbidden: an unenforced parameter nothing populates *looks* fixed without being fixed. — **`PARTIALLY RESOLVED`** (corrected from `RESOLVED` at Tier C). Wired into all 4 named target functions, but Tier C found `app.set_integration_connection_status` (the shared primitive behind `activate_enterprise_idp_connection`) independently bypasses the fix — see Result below and `ISS-2026-235`. |
| 2 | **`ISS-2026-151` — step-up challenge unwired** on `app.create_integration_connection` (**"40+" call sites across 16 files, corrected to a precise 43 at `HDN-378`, see Disposition**). 3 of 4 target functions were wired at `CG-S14-IAE-039` via migration `20260809200000`; this one was deliberately left rather than risk a rushed mass edit. | Medium | Wire it with real fixtures and a negative-path regression proving genuine enforcement, or rule on it explicitly. — **Re-scoped precisely at `HDN-378` (43 call sites / 27 sequences / 16 files, superseding the original "40+" estimate), deliberately deferred again** — see Result below. |
| 3 | **Move postgis, pg_trgm and btree_gist out of `public`.** Same root class as the fixed pgcrypto defect. Clears **7 of the 8 non-noise security advisories, including the only ERROR** (`rls_disabled_in_public` on PostGIS's own `spatial_ref_sys`, plus 3 `extension_in_public` and 6 `*_security_definer_function_executable` from `st_estimatedextent`). | Medium | **Its own scoped task inside this lane — never folded into another edit.** Every `geometry`/`geography`/`ST_*` caller needs `extensions` in its search_path: a far larger blast radius than pgcrypto's. Note `spatial_ref_sys` cannot have RLS enabled at all — it belongs to the extension and `postgres` is not superuser on a hosted project. — **Corrected and `PARTIALLY RESOLVED`: `postgis` is not relocatable at all (`relocatable = false`); clears 2 of 8, not 7 of 8** — see Result below and `ISS-2026-234`. |
| 4 | `ISS-2026-149` — anonymous cross-tenant SSO-config enumeration oracle | Low | Throttle or gate — **Reconfirmed unchanged, still deferred** (still dead code at the HTTP layer; building attempt-tracking infrastructure for a zero-caller resolver is disproportionate). |
| 5 | `ISS-2026-146` — `tenant_id` disclosure via exception text | Low | Re-assess reachability — **Reconfirmed and re-measured: 2,335 occurrences (up from 2,087), 10/10-sampled reachability, severity held at Low**, still deferred as a repository-wide sweep. |
| 6 | `auth_leaked_password_protection` advisory | Low | **Dashboard setting, not a migration.** Record as a deployment-runbook item — **Done**: `docs/runbooks/production-configuration-checklist.md`. |
| 7 | Dependency scan | — | `pnpm run security:check` / `security:audit`. Note `ISS-2026-007`'s lesson: a broken audit gate hid 20 real advisories, 11 high, for a whole phase. The gate now fails when the advisory service is unreachable — **keep that property**. **`HDN-BLK-007`/`ISS-2026-158` (High, added at `HDN-370`) means this exact gate does not run in CI on a push right now.** `HDN-378` cannot treat "the gate exists" as evidence it is enforced anywhere but a local run — it must run `security:audit` itself and record the result, the same gap this row's own note warns about one level up. Do not close this item on CI's silence being green; CI is not currently running it. — **Ran live: both clean.** `ISS-2026-158`'s CI-enforcement gap reconfirmed unchanged, owner unchanged `HDN-387`. |
| 8 | OWASP-style abuse: CSRF, XSS, SQLi, IDOR, SSRF, open redirect, file upload, API abuse, webhook spoofing, prompt injection | — | Test per Prompt 389 item 10 — **Done, live-forced across all 10 categories.** 9 HELD; 1 Medium finding (open-redirect control-character bypass) found and fixed (`ISS-2026-233`). |
| 9 | Service-role / secrets server-only; logs redacted | — | Verify — **Done.** `ISS-2026-168` fixed (ESLint import-boundary guard); audit-redaction spot-check clean; 2 more findings surfaced and fixed in the process (`ISS-2026-169`, `ISS-2026-232`). |
| 10 | Incident response, key rotation, privileged access audit | — | Test — **Done.** 3 new runbooks authored: `docs/runbooks/incident-response.md`, `key-rotation.md`, `privileged-access-audit.md`, each naming real, verified-to-exist primitives and disclosing the still-open gaps (`ISS-2026-151`, and 3-of-4 IP-restricted functions' own missing live HTTP route) rather than overstating coverage. |

**Upstream hard gate:** `HDN-372` `VERIFIED`. Also depends on `HDN-373..377`.

> **Result (`HDN-378`, Prompt 378, Security Hardening):** the checkpoint's own highest
> priority (`ISS-2026-150`, High, "must not be deferred again") is `RESOLVED` — all 4
> named platform-default high-risk functions (`decide_ai_output_approval`,
> `activate_enterprise_idp_connection`, `approve_mfa_exception`,
> `create_integration_connection`) now compose the previously-inert
> `app.assert_ip_allowed`/`app.has_active_ip_allowlist_bypass` primitives, scope
> `'admin'`, exempting a null client IP or an active bypass-grant holder. **A genuine
> implementation defect was caught and fixed before commit, not shipped**: a first
> `CREATE OR REPLACE FUNCTION` draft silently created a second overload per function
> instead of replacing it (Postgres does not treat an added trailing parameter as a
> signature match), which would have left every existing caller permanently bound to
> the OLD, un-gated version — corrected to an explicit `DROP FUNCTION` + `CREATE
> FUNCTION` + re-`GRANT EXECUTE` for all 4, re-verified (exactly one overload each,
> correct grants, 11 db-test files clean, full 229-file suite green). `ISS-2026-151`
> (the sibling step-up-MFA gap on the same `create_integration_connection` function)
> was re-scoped precisely — 43 real call sites, 27 distinct step-up sequences, across
> the same 16 files — and deliberately deferred again: stacking it onto this
> checkpoint's own IP-restriction migration would exceed the normal bounded-repair
> budget and repeat the exact "rushed, under-tested wide edit" risk `CG-S14-IAE-039`
> already declined once. `pg_trgm`/`btree_gist` relocated out of `public` (2 of the
> item 3 punch-list's own 8 advisories); `postgis` was found to be structurally
> non-relocatable (`relocatable = false` in its own control file — a `DROP EXTENSION
> CASCADE` would destroy 15 live `geography`-typed columns across 12 tables), so the
> matrix's own original "clears 7 of 8" framing is corrected here to "clears 2 of 8";
> the remaining 6, including the one ERROR advisory, are registered separately
> (`ISS-2026-234`, owner a dedicated future task). A full OWASP-style abuse-pattern
> sweep across SQL injection, IDOR, CSRF, XSS, rate limiting, API-key handling, webhook
> signature verification, file-upload validation, and AI-governed-action human-approval
> integrity was live-forced against a real disposable database and 9 of 10 categories
> held with zero findings; the 10th (open redirect) surfaced a real, latent
> control-character-injection bypass in `lib/auth/redirect-allowlist.ts` (not currently
> exploitable — its one live caller constrains input upstream — but a genuine gap in a
> documented general-purpose control), found and fixed same checkpoint
> (`ISS-2026-233`). `ISS-2026-168` (service-role import boundary) closed via a new
> ESLint `no-restricted-imports` rule scoped to an explicit allowlist of the 27 real
> legitimate importers. **2 more findings surfaced and fixed in the same pass, both
> pre-existing and already owned by this checkpoint**: `ISS-2026-169` (an anonymous
> vendor self-registration action still returned its raw tenant-existence discriminator
> on the wire even though the rendered message was already unified) and `ISS-2026-232`
> (3 more `token_hash` columns exposed via a blanket grant, the same class as
> `HDN-377`'s own `ISS-2026-216`) — fixing the latter required catching and fixing a
> **second** real regression in the same pass: two query functions used a bare
> `select("*")` against the now-column-restricted tables, one with a real live
> `authenticated`-session caller that would have started failing with a permission
> error. `ISS-2026-149`/`146` reconfirmed and re-measured, severity unchanged, both
> still deferred as out-of-bounded-scope repository-wide work. Dependency scan clean;
> `ISS-2026-158`'s CI-enforcement gap reconfirmed, unchanged, owner `HDN-387`. 4 new
> runbooks/checklists authored (items 6 and 10). First-round independent full gate
> re-run: `typecheck` 0, `lint` 0 errors/337 warnings, 5443/5443 unit tests, db-tests
> confirmed green by two independent full 229-file suite runs.
>
> **Tier C review (4 independent lenses) found 2 Critical + 1 High genuine bypass in
> this checkpoint's own first-round work, live-forced against a real disposable
> database, all fixed before `VERIFIED` close.** (1) `ISS-2026-232`'s own
> column-privilege fix was defeated by a second, more fundamental gap: all 3 "revoke"
> RPCs returned the full composite row type — including `token_hash` — via
> `RETURNING`/return value, which is not subject to column-level `SELECT` privileges at
> all. Fixed: each function now nulls `token_hash` on its own returned composite before
> `return` (taxonomy class `C-27`, new). (2) `ISS-2026-168`'s ESLint fix only inspected
> static `import`/`export ... from` declarations — `require()` and dynamic `import()`
> both evaded it undetected. Fixed: 2 new `no-restricted-syntax` selectors added to the
> same rule object. (3) The schema-wide completeness sweep independently found
> `app.validate_webhook_url` shares `ISS-2026-233`'s own control-character gap (not
> exploitable end-to-end, a dispatch-time backstop holds) — fixed in the same pass.
>
> **The checkpoint's own headline claim required a real correction.** Attack-surface
> testing found `app.set_integration_connection_status` — the shared, generic primitive
> `activate_enterprise_idp_connection` delegates to — is independently `EXECUTE`-granted
> to `authenticated`, gated only on a bare `INTHUB:Configure` check, none of the SSO
> wrapper's own extra protections (the pre-existing IAE-026 lockout guard, step-up-MFA,
> and this checkpoint's own IP-restriction). Live-forced: calling it directly, as an
> `INTHUB:Configure`-only actor, reactivated a live enterprise SSO connection with zero
> verified test login, zero step-up challenge, and zero client IP, defeating all 3
> layered protections in one call. `ISS-2026-150` corrected `RESOLVED` →
> `PARTIALLY RESOLVED`; registered as `ISS-2026-235`/`HDN-BLK-023` (Critical, owner
> `HDN-386`, taxonomy class `C-28`, new) — the correct fix is a design decision touching
> a heavily-reused shared primitive, exceeding what a Tier C pass should rush. The
> completeness sweep separately found 3 of `is_high_risk_action`'s own 7 hardcoded
> tuples (`SEC:Configure`, `FIN:Approve`, `HRS:Approve` — 61 real functions) never
> received either guard at all, across the entire prior lineage — registered as
> `ISS-2026-236`/`HDN-BLK-024` (High, owner `HDN-386`). A pre-existing (two-weeks-prior,
> unrelated-to-this-checkpoint) `select("*")`-vs-column-restriction defect was also
> found in `automation-rule.ts` — registered, not fixed, as `ISS-2026-237` (Medium,
> owner `HDN-387`), mirroring `HDN-377`'s own `ISS-2026-224` precedent. The
> ledger/documentation consistency lens found and this checkpoint fixed 5 real
> documentation miscounts in its own first-round propagation (commit `3fbf665`,
> including this row's own stale "40+"/"7 of 8" figures) before this Tier C close; a 6th
> claimed defect was resolved as not a real error. Independent full gate re-run after
> the fix pass: `typecheck` 0, `lint` 0 errors/337 warnings, 5443/5443 unit tests,
> db-tests confirmed green by the full 229-file suite against the final, Tier-C-fix-
> inclusive migration state (328 migrations). Full disposition: `HDN-378.md`.

---

## 10. Performance / scalability — `HDN-379`

| # | Item | Seeded state | Required |
|---|---|---|---|
| 1 | **`rbac-enforcement.sql`'s `pg_proc` catalogue scan** — walks every function in `app` calling `pg_get_functiondef()`. At ~2,900 functions (seed-time estimate; confirmed exactly **2,700** at `HDN-379` fix time) it **already exceeds a remote statement timeout**, takes 15–20+ minutes standalone (`ISS-2026-145`), and grows with the schema | `OPEN` | **Scope the scan** before it bites CI. It passes locally today; that is the last thing that is true about it — **`RESOLVED`.** O(n²) self-join rewritten to a one-pass extraction, matched-pair verified byte-identical, 300×-1200×+ speedup across 2 independent measurements — see Result below. |
| 2 | **892 `unindexed_foreign_keys` advisories** | `OPEN`, explicitly deferred | **An owner-named decision, not a defect.** A design question needing real query patterns. **Neither drop them nor blindly index.** Record the decision and its owner — **Categorized and deferred with a real decision framework, `ISS-2026-239`** — see Result below. |
| 3 | 982 `unused_index` advisories | noise | The database has served no queries. Not actionable until it has |
| 4 | 157 `auth_rls_initplan` warnings | **FIXED** — `auth.uid()` → `(select auth.uid())` at 228 call sites in 171 policy statements across 65 migrations | Regression-guard: a new policy using a bare `auth.uid()` reintroduces the class — **Re-verified clean, zero regression** (582 policy statements checked); 1 informational blind spot documented (`ISS-2026-240`). |
| 5 | Load/perf evidence | **`ISS-2026-141`** (Phase 8) and **`ISS-2026-148`** (Phase 9): zero load/performance-test evidence exists for any route or RPC at declared target volume | Seeded here. This gate cannot pass on assertion — **Reconfirmed unchanged, still deferred**; existing `scripts/load-tests/` harness re-confirmed live and green (8/8 scenarios), new `EXPLAIN` evidence gathered for 9 endpoints — see Result below. |
| 6 | p95, query count, payload size, job duration, queue depth, cache behavior | — | Measure or register a tracked gap — **Done, real evidence gathered** — see Result below. |
| 7 | No `SELECT *` in transactional APIs, no browser-loaded full dataset, no unbounded export/report/import/AI workload, no unsafe cross-tenant cache | ratified | Verify — **Verified. 1 genuine finding**: 3 routes load an entire tenant dataset with zero pagination (`ISS-2026-238`). Everything else (APIs, cache, queues) held clean. |

**Upstream hard gate:** `HDN-372..378` all `VERIFIED`.

> **Result (`HDN-379`, Prompt 379, Performance and Scalability):** the checkpoint's
> own highest-priority item, `ISS-2026-145` (the O(n²) `rbac-enforcement.sql` scan,
> 15-20+ minutes standalone), is `RESOLVED` — the `edge` CTE inside the
> ATW-032/`ISS-2026-032` block rewritten from an `fn c join fn e` self-join to a
> one-pass `regexp_matches()` extraction, mirroring this same file's own sibling
> ATW-032/`ISS-2026-033` pattern unmodified. Only edge construction changed; the
> `covered` recursive CTE's own multi-hop transitive-closure walk is byte-identical,
> so the invariant proved is unweakened. **Verified with a same-schema matched-pair
> run**, not a before/after comparison across two separate builds: original
> 692,092.8ms (~11.5 min), rewrite 556.4ms, verdicts byte-identical, **1244×
> speedup**. Full 229-file suite re-run clean, `ALL PASSED`. **892
> `unindexed_foreign_keys` advisories categorized and deferred** (`ISS-2026-239`):
> 4-bucket decision framework built from a 24-FK sample across 7 domains — zero
> high-confidence "index now" candidates found (every hot column already has a
> serving composite index; cold candidates are write-only/audit-lineage columns on
> high-write-volume tables where speculative indexing would be pure
> write-amplification), deferred pending real production query telemetry that does
> not exist anywhere in this system yet. **`auth_rls_initplan` regression guard
> re-verified clean**: 582 policy statements, 235 `auth.*()` call sites, zero bare
> calls, no regression since the original 65-migration fix; 1 informational blind
> spot documented (`ISS-2026-240`) — a `default auth.uid()` helper-function pattern,
> 72 occurrences across 35 migrations, invisible to text-grep-based tooling by
> construction, not a regression, the repository's own convention since day one.
> **Load/performance evidence**: the existing `scripts/load-tests/` harness
> (Phase 5/`CG-S10-ATW-024` scope) re-confirmed live, all 8 scenarios pass with real
> measured p50/p95/p99 latencies; new `EXPLAIN (ANALYZE, BUFFERS)` evidence gathered
> for 9 representative endpoints across 5 domains at a seeded realistic volume.
> `ISS-2026-141`/`148`'s own overall evidence-gap ruling reconfirmed unchanged, still
> correctly out of one checkpoint's bounded scope. **1 genuine new finding**
> (`ISS-2026-238`, Medium): 3 production routes (Commercial accounts/quotations/
> contracts) load an entire tenant-wide dataset to the browser with zero pagination,
> live-verified via real query-plan evidence at a seeded 25,000/10,000-row volume;
> ~10 lower-severity siblings on config/rate-shaped tables share the same code
> pattern. Self-disclosed only in a code comment before this checkpoint, never
> promoted to `KNOWN_ISSUES.md` — now properly registered. Everything else
> (API-response boundedness, cross-tenant cache safety, queue backpressure) verified
> clean by 2 independent lenses using different methods, zero findings. **No
> Critical or High finding anywhere.** Full gate: `typecheck` 0, `lint` 0
> errors/337 warnings, `pnpm run test` 5443/5443 (unchanged, no TS file touched),
> db-tests **229/229 files clean** (328 migrations, unchanged — no migration this
> checkpoint). Zero migrations, one test-infrastructure file changed
> (`scripts/db-tests/rbac-enforcement.sql`). First-round independent full gate
> re-run: `typecheck` 0, `lint` 0/337 warnings, 5443/5443 unit tests, db-tests
> 229/229 files clean (328 migrations).
>
> **Tier C review (4 independent lenses) found and fixed a real structural
> weakening in this checkpoint's own headline fix, live-forced against a real
> disposable database.** The first-draft `edge` CTE rewrite dropped two properties
> the original self-join carried "for free": a `\m` word-boundary anchor (so
> `webapp.foo(` could not be mistaken for a call to `app.foo`), and a real
> join-against-`fn` requirement (so `insert into app.<table> (...)` could not be
> mistaken for a call to a function named after the table). Live-forced: 876
> spurious edges on the real 2,700-function schema, zero of which collided with any
> real function name — the rewrite never produced a wrong verdict today, but a
> future function named after an existing table, or a `wordapp.<realname>(` call
> site, could have silently defeated the guard. Fixed by restoring both properties
> (regex now anchors `\mapp\.`, `where` clause adds `and m[1] in (select proname
> from fn)` — a hash semi-join against the already-materialized `fn` CTE, not a new
> cross join, confirmed the fix stays O(n)); re-timed at **1.66 seconds**. Live-
> reproduced with 3 scratch functions that both gaps are closed.
>
> **Timing-precision corrected**: an independent same-schema matched-pair
> re-measurement got 212,105.6ms/≈313× rather than the first round's own
> 692,092.8ms/1244× — both real, honest measurements; the ~3× spread reflects real
> sandbox contention variance at measurement time (the rewrite's own cost stayed
> close both times: 556ms vs. 677ms), not a methodology flaw. Cite "300×-1200×+" for
> this fix going forward, not a single fixed multiplier. Also corrected:
> `ISS-2026-239`'s claim that no RPC filters through `audit_logs.actor_auth_user_id`
> was factually wrong (`app.search_audit_logs` does, zero live UI callers today —
> the "don't index yet" conclusion is unchanged, the evidence was fixed).
> `ISS-2026-238` corrected and expanded: `listFilesForTenant` reclassified Medium
> (a polymorphic, transactional-volume attachment table, not a bounded config
> table as originally characterized); 5 new instances found by the completeness
> sweep folded in, most notably a 4-list unbounded fleet-assets page. 6 real
> documentation miscounts found and corrected by the ledger/documentation
> consistency lens (236→235 call sites, 73/~40→72/35 default-pattern occurrences, a
> stale "~2,900" figure, 2 never-updated `BLOCKER_LEDGER.md` entries, an ambiguous
> FK-table-count phrasing, a line-citation drift). Independent full gate re-run
> after the fix pass: `typecheck` 0, `lint` 0/337 warnings, 5443/5443 unit tests,
> db-tests **229/229 files clean** (328 migrations, unchanged — no migration at
> either round). Full disposition: `HDN-379.md` §13.

---

## 11. Accessibility — `HDN-380`

| Dimension | Seeded state | Required |
|---|---|---|
| Harness | Real, CI-wired Playwright + `@axe-core/playwright` exists (`e2e/smoke.spec.ts`, `e2e/tenant-admin-portal.spec.ts`, `e2e/vendor-registration.spec.ts`, `e2e/supreme-admin-portal.spec.ts`) | Reuse it |
| Coverage | **It has never run against any authenticated route.** Only synthetic inline HTML fixtures and two unauthenticated public routes (`/login`, `/vendor-intake/*`) | **`ISS-2026-140`** (~30 Customer Portal + 9 admin Loyalty routes), **`ISS-2026-153`** (~9 Phase 9 admin/reporting/automation/integration routes) |
| Root cause | No live sign-in flow: every guarded route needs a real authenticated session, which needs a running auth backend | Repository-wide constraint (§10 of the execution index), not this lane's to invent around |
| CI harness itself | **`HDN-BLK-009`/`ISS-2026-160` (Medium, added at `HDN-370`): the `e2e` CI job sets no environment, so `NEXT_PUBLIC_SUPABASE_URL` is unset and every guarded route 500s before any guard logic runs.** This is a *more specific and more fixable* fact than "no live sign-in flow" — it is a missing CI environment block, and it also raises a real product question (should the guard fail safe on missing config, or do the specs encode an intent the code never had?) that this lane, not `HDN-387` alone, is positioned to answer since it owns the accessibility evidence that question blocks | **Check whether `HDN-BLK-009` is still open when this lane runs.** If it is, this lane cannot get further than `ISS-2026-140`/`153` already are without either (a) provisioning its own local `.env` for the harness (a `HDN-380`-scoped workaround, not a CI fix) or (b) formally widening its own `TRACKED_GAP` to say so explicitly, rather than silently inheriting `HDN-370`'s finding as if it were new |
| WCAG 2.2 AA | ratified target | Keyboard, focus, labels, contrast, error summaries, denied states, responsive readability |
| Source-level evidence | `role="alert"`/`role="status"`, `aria-current="page"`, `label`/`htmlFor`, status by text+icon not colour alone | **Evidence of intent, explicitly not a substitute for a run audit** |

`next build` is required from this lane onward.

> **Result (`HDN-380` first round, `COMPLETED`, Tier C pending):** `HDN-BLK-009` was
> checked per this section's own instruction and found stale — `playwright.config.ts`'s
> own `webServer.env` block (added at `PLT-135`, after `HDN-370`) already made the
> "unset env var" premise moot. The real remaining symptom (5 `e2e/vendor-registration.spec.ts`
> failures) was live-forced to a Turbopack dev-mode hydration-timing race, not an
> application defect (new taxonomy class `C-30`) — fixed at the root by switching
> `webServer.command` to a production build (`next build && next start`, satisfying this
> section's own "`next build` is required from this lane onward" instruction directly).
> Full suite now 18/18, zero 500s. `ISS-2026-140`/`153`'s own root cause widened with a
> precise `RLIMIT_NOFILE`/`runc` container-runtime finding (Postgres boots cleanly in
> this sandbox; every non-Postgres Supabase service container does not) rather than left
> as the vaguer "no live sign-in flow" — the underlying constraint is unchanged and still
> not this lane's to fix. 6 real color-contrast token failures fixed (`app/globals.css`,
> WCAG-computed replacements) using the authority `DESIGN_SYSTEM.md` §2.1's own
> disclosed-pending-validation status provides. `eslint-plugin-jsx-a11y`'s `recommended`
> preset wired repository-wide (14 real errors found and fixed across 5 files); 454/454
> inline error displays app-wide now carry `role="alert"` (7 were missing it). 2 large
> architectural gaps found and registered, not fixed (out of this checkpoint's own
> bounded charter): `ISS-2026-241` (36 of 38 tenant modules have no `<main>` landmark),
> `ISS-2026-242` (accessible form primitives adopted in only ~2% of the 200 files that
> render a form). A prior "565 unlabeled form controls" figure did not reproduce under
> the authoritative rule for that exact check (now 0 errors app-wide) — corrected, not
> silently dropped. Full disposition: `HDN-380.md`.

---

## 12. Browser / device compatibility — `HDN-381`

| Dimension | Seeded state | Required |
|---|---|---|
| Matrix | Chrome, Edge, Safari, Firefox, tablet/mobile | Define it explicitly |
| Runtime | Chromium is available in this environment | Note which of the four can actually be driven here; the rest are tracked gaps |
| PWA posture | RPD-004: responsive **online-first**. Internal ERP desktop-first; customer/field flows mobile-friendly | **Never claim native or offline-sync behavior** |
| Auth/session, uploads/downloads, ePOD, dashboards, tables, modals, mobile forms | built | Exercise, or track the gap |

**Upstream:** `HDN-380`. Inherits `HDN-380`'s own `HDN-BLK-009` exposure — a harness that cannot reach a guarded route in `HDN-380` cannot reach one here either.

---

## 13. Observability — `HDN-382`

| Dimension | Seeded state | Required |
|---|---|---|
| Enterprise monitoring | Built at Phase 9 (`IAE-030`) | Map coverage: app, DB, queue, jobs, integrations, API, AI, storage, security events |
| Incident dedup defect | **`ISS-2026-155`** — a genuine breach of two different `job`-mapped workload types (e.g. `analytics` + `reports`) for the same tenant within the dedup window **collapses into one incident** | Seeded here. Medium — a monitoring gate that silently merges distinct incidents is an observability defect, not a cosmetic one |
| Region/service-capability matrix | **`ISS-2026-152`** — has zero run-time consequence on any data-plane function | Seeded here |
| Alerts actually firing | No deployed environment; no live alerting endpoint | Trigger or simulate; disclose which |
| Runbook links, severity workflow, alert ownership | partial | Verify |
| `docs/runbooks/gps-ingestion-database-outage.md` | Carries `NOT_YET_REHEARSED` and a now-stale "no live Supabase project exists yet" note | Refresh against the current baseline |

---

## 14. Backup / restore — `HDN-383`

| # | Constraint | Detail |
|---|---|---|
| 1 | **Teardown must batch `drop schema app cascade` per transaction** | `max_locks_per_transaction` is too low: fails with **`53200: out of shared memory` at ~1,400 objects**. The statement is atomic, so it rolls back cleanly and nothing corrupts — but any teardown must drop in batches, each in its own transaction |
| 2 | **Migrations are not idempotent** | Bare `create table`, no explicit transaction wrapper. Re-running any applied migration fails. `supabase_migrations.schema_migrations` is the **only** re-run guard — state this explicitly in the deployment runbook |
| 3 | **`auth.users` survives a schema reset** | It is Supabase's schema, untouched by dropping `app`. Any live test cycle must clear it in teardown, or **every rerun collides on `users_pkey`** |
| 4 | Scope | Database, files, configuration, secrets **references** (never secret values), jobs, deployment state |
| 5 | Evidence | An actual restore drill in a safe environment, reconciled on counts, integrity, RLS, files and jobs — plus RPO/RTO actuals versus the disclosed default |
| 6 | Target | **Never the live project's data.** State the target explicitly before executing |

**Block release if restore evidence is absent for required scope.**

---

## 15. Disaster recovery rehearsal — `HDN-384`

| Dimension | Seeded state | Required |
|---|---|---|
| Scenarios | major outage, data corruption, provider failure, security incident | Define success criteria per scenario |
| Inherited constraints | All three of §14's constraints apply verbatim to any DR teardown/rebuild | Carry them into the runbook |
| Enterprise DR controls | Built at Phase 9 (`IAE-035`) | Exercise or tabletop |
| Communication, ownership, escalation, customer impact | — | Verify |
| Recovery time / data loss | — | Measure where feasible; disclose where not |

**Upstream:** `HDN-383`.

---

## 16. Data migration rehearsal — `HDN-385`

| Dimension | Seeded state | Required |
|---|---|---|
| Real precedent | **306/306 migrations applied cleanly to a real hosted project**, ledger in sync — the strongest single piece of migration evidence this repository has | Cite it; do not re-derive it |
| Non-idempotency | §14 item 2 applies | Rollback/rerun idempotency must be tested honestly against it |
| Mapping, preview, validation, duplicate handling | Import/Export Job Framework (Phase 5) | Exercise |
| Commit + reconcile counts/totals/files/lineage | — | Rehearsal environment only |
| Do not fabricate historical data | ratified | Hard rule |

**Upstream:** `HDN-371`.

---

## 17. Cross-cutting — CI mirrors hosted, in both directions

**Status at kickoff: `PASS`.** This is the only gate already green, and it is the one most
easily broken by an unrelated edit.

| Direction | Mechanism | Regression risk |
|---|---|---|
| Extension schema | pgcrypto installed into `extensions` explicitly, schema created first, so a bare CI Postgres matches the hosted layout | A new `create extension` without an explicit schema recreates defect 1 |
| Function search_path | 39 pgcrypto callers pin `extensions`; 7 formerly-unpinned functions pinned (an unpinned function inherits the **caller's** search_path, not the session default) | A new unpinned `SECURITY DEFINER` function recreates defect 2 |
| `auth.users` column types | Stub declares `email`/`role` as `varchar(255)`, `phone` as `text` — matching real Supabase | Reverting to `text` recreates defect 3 |
| Database-level search_path | `setup-disposable-db.sh` sets `"$user", public, extensions`, mirroring what Supabase sets and stock Postgres does not | Removing it makes top-level `digest()`/`hmac()` calls fail locally while passing live |
| RLS InitPlan form | `(select auth.uid())`, not bare `auth.uid()` | A new policy with a bare call reintroduces per-row evaluation |

**Every lane's Tier B walk must check its own diff against this table.** A hardening change
that reintroduces the divergence re-blinds CI to the exact class the live migration exposed —
the one class that, by construction, no single environment can catch.
