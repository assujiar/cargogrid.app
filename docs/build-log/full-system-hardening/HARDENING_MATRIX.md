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
| 5 | Financial integrity | `HDN-374` **`COMPLETED`** | **`PARTIAL`** — not a pass, Tier C review pending. Quote-level tax silently doubled at invoicing — fixed (`ISS-2026-194`). A job order could reach `issued` on two full-amount invoices from two distinct handoffs — fixed at the actual AR/GL posting boundary, `app.issue_finance_invoice` (`ISS-2026-195`; the first fix draft, gating invoice preparation itself, was self-corrected before commit — it would have broken `OPS-181`'s own disclosed legitimate-re-handoff allowance). `HDN-BLK-010`/`ISS-2026-162`'s Finance/HRIS-Payroll scope resolved — 10 functions (6 named plus 4 more this checkpoint's own wider sweep found) fixed with the codebase's own "design note 9(a)" pattern, 2 mechanisms live-forced with a genuine two-process race each. `app.run_loyalty_expiry_sweep`'s own `p_as_of` was silently ignored — fixed (`ISS-2026-196`). 2 findings registered, not fixed, owner `HDN-386` (`ISS-2026-197`: no FX/multi-currency conversion anywhere in the revenue chain; Operations' own job-profitability planned-vs-actual split). `HDN-BLK-010`'s residual 3 non-Finance functions plus `ISS-2026-163` handed to `HDN-387` | §5 |
| 6 | Data lineage | `HDN-375` | `NOT_RUN` | §6 |
| 7 | API compatibility | `HDN-376` | `NOT_RUN` | §7 |
| 8 | Storage / signed URL | `HDN-377` | `NOT_RUN` | §8 |
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

> **Result, 2026-08-23 (`CG-S15-HDN-006`), `COMPLETED`, Tier C review pending:** one
> additive migration, four independent parallel investigation lenses, each required to
> live-force its own findings on disposable databases. Cost/AP chain, payment/journal
> reconciliation, period lock, reversal, correction, rounding, tax snapshotting,
> payroll-handoff aggregation, and RPD-016's statutory gates all held clean. **4 real,
> live-forced defects fixed**: `ISS-2026-194` (High, quote-level tax silently doubled at
> invoicing); `ISS-2026-195` (High, a job order could reach `issued` on two full-amount
> invoices from two distinct handoffs — the first fix draft was self-corrected before
> commit, since it would have broken `OPS-181`'s own disclosed legitimate-re-handoff
> allowance; the shipped fix gates `app.issue_finance_invoice`, the actual AR/GL posting
> boundary); closes `HDN-BLK-010`/`ISS-2026-162`'s Finance/HRIS-Payroll scope (10
> functions, 2 mechanisms live-forced with a genuine two-process race each); `ISS-2026-196`
> (Medium, `app.run_loyalty_expiry_sweep`'s own `p_as_of` silently ignored, now threaded
> through). **2 findings registered, not fixed** (`ISS-2026-197`, Low, owner `HDN-386`):
> no FX/multi-currency conversion anywhere in the revenue chain; Operations' own
> `app.calculate_job_profitability` planned-vs-actual figure split. No Critical finding
> anywhere. Fresh full gate run green: `typecheck` 0, `lint` 0 errors/337 warnings,
> 5394/5394 unit tests, 229/229 db-tests (317 migrations). Full disposition:
> `HDN-374.md`.

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

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 7. API compatibility — `HDN-376`

| Dimension | Seeded state | Required |
|---|---|---|
| REST `/v1` surface | 9 route handlers exist; **`ISS-2026-147`: zero test coverage for them** (Medium) | Seeded here — this gate cannot pass while its primary surface is untested |
| GraphQL parity | Ratified as developed together with REST | Verify parity or register the gap |
| Public / customer / vendor API | Phase 9 (`IAE`), built on `PLT-129` API-key primitives (hash-only storage, scope-narrowing via `app.evaluate_permission()`) | Compatibility + deprecation tests |
| Webhooks — outbound delivery worker on `app.jobs`; inbound third-party-GPS receiver kept separate | Phase 9 / `ADR-0025` B | Signing, replay, retry, DLQ |
| Idempotency, rate limit, error shapes, pagination | Built | Test |
| Schema/migration compatibility plan | Additive / expand-and-contract only | Verify |

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

---

## 9. Security hardening — `HDN-378`

**This lane carries the single most important carry-forward item in Step 15.**

| # | Item | Severity | Disposition required |
|---|---|---|---|
| 1 | **`ISS-2026-150` — IP restriction structurally unreachable.** RPD-023's enforcement is real and correct when called directly, but **no real client IP is threaded through the route-handler layer**, so a fully-configured `enforced`-mode allowlist gives zero real protection against a caller reaching the RPC layer directly (leaked service credential, compromised client bypassing the intended HTTP path). | **High** | **Must not be deferred again.** Phase 9's closure disclosed it as a deliberate first-of-its-kind accepted exception and **named Step 15 as the remedy**. Needs: (a) route-handler-level IP extraction and threading; (b) `assert_ip_allowed` wired into the bounded set of highest-risk SEC/IAM/INTHUB mutations; (c) an explicit ruling on service-role/background callers with no client IP (likely exempt — IP restriction is inherently an interactive-session control). A cosmetic partial wire-up is forbidden: an unenforced parameter nothing populates *looks* fixed without being fixed. |
| 2 | **`ISS-2026-151` — step-up challenge unwired** on `app.create_integration_connection` (**40+ call sites across 16 files**). 3 of 4 target functions were wired at `CG-S14-IAE-039` via migration `20260809200000`; this one was deliberately left rather than risk a rushed mass edit. | Medium | Wire it with real fixtures and a negative-path regression proving genuine enforcement, or rule on it explicitly. |
| 3 | **Move postgis, pg_trgm and btree_gist out of `public`.** Same root class as the fixed pgcrypto defect. Clears **7 of the 8 non-noise security advisories, including the only ERROR** (`rls_disabled_in_public` on PostGIS's own `spatial_ref_sys`, plus 3 `extension_in_public` and 6 `*_security_definer_function_executable` from `st_estimatedextent`). | Medium | **Its own scoped task inside this lane — never folded into another edit.** Every `geometry`/`geography`/`ST_*` caller needs `extensions` in its search_path: a far larger blast radius than pgcrypto's. Note `spatial_ref_sys` cannot have RLS enabled at all — it belongs to the extension and `postgres` is not superuser on a hosted project. |
| 4 | `ISS-2026-149` — anonymous cross-tenant SSO-config enumeration oracle | Low | Throttle or gate |
| 5 | `ISS-2026-146` — `tenant_id` disclosure via exception text | Low | Re-assess reachability |
| 6 | `auth_leaked_password_protection` advisory | Low | **Dashboard setting, not a migration.** Record as a deployment-runbook item |
| 7 | Dependency scan | — | `pnpm run security:check` / `security:audit`. Note `ISS-2026-007`'s lesson: a broken audit gate hid 20 real advisories, 11 high, for a whole phase. The gate now fails when the advisory service is unreachable — **keep that property**. **`HDN-BLK-007`/`ISS-2026-158` (High, added at `HDN-370`) means this exact gate does not run in CI on a push right now.** `HDN-378` cannot treat "the gate exists" as evidence it is enforced anywhere but a local run — it must run `security:audit` itself and record the result, the same gap this row's own note warns about one level up. Do not close this item on CI's silence being green; CI is not currently running it. |
| 8 | OWASP-style abuse: CSRF, XSS, SQLi, IDOR, SSRF, open redirect, file upload, API abuse, webhook spoofing, prompt injection | — | Test per Prompt 389 item 10 |
| 9 | Service-role / secrets server-only; logs redacted | — | Verify |
| 10 | Incident response, key rotation, privileged access audit | — | Test |

**Upstream hard gate:** `HDN-372` `VERIFIED`. Also depends on `HDN-373..377`.

---

## 10. Performance / scalability — `HDN-379`

| # | Item | Seeded state | Required |
|---|---|---|---|
| 1 | **`rbac-enforcement.sql`'s `pg_proc` catalogue scan** — walks every function in `app` calling `pg_get_functiondef()`. At ~2,900 functions it **already exceeds a remote statement timeout**, takes 15–20+ minutes standalone (`ISS-2026-145`), and grows with the schema | `OPEN` | **Scope the scan** before it bites CI. It passes locally today; that is the last thing that is true about it |
| 2 | **892 `unindexed_foreign_keys` advisories** | `OPEN`, explicitly deferred | **An owner-named decision, not a defect.** A design question needing real query patterns. **Neither drop them nor blindly index.** Record the decision and its owner |
| 3 | 982 `unused_index` advisories | noise | The database has served no queries. Not actionable until it has |
| 4 | 157 `auth_rls_initplan` warnings | **FIXED** — `auth.uid()` → `(select auth.uid())` at 228 call sites in 171 policy statements across 65 migrations | Regression-guard: a new policy using a bare `auth.uid()` reintroduces the class |
| 5 | Load/perf evidence | **`ISS-2026-141`** (Phase 8) and **`ISS-2026-148`** (Phase 9): zero load/performance-test evidence exists for any route or RPC at declared target volume | Seeded here. This gate cannot pass on assertion |
| 6 | p95, query count, payload size, job duration, queue depth, cache behavior | — | Measure or register a tracked gap |
| 7 | No `SELECT *` in transactional APIs, no browser-loaded full dataset, no unbounded export/report/import/AI workload, no unsafe cross-tenant cache | ratified | Verify |

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
