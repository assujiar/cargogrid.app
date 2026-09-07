# Remediation backlog — `CG-AUDIT-2026-09-02` independent launch-readiness audit

**Declared as a backlog-remediation task under `ADR-0027` Part A.** The project owner's own
instruction for this effort ("lanjut dan perbaiki semua gap/issue yg sudah teridentifikasi dr hasil
audit secara tuntas" — continue and fix every gap/issue identified by the audit, to completion) is
the same class of instruction `ADR-0027` Part B already quotes and acts on for the prior
`KNOWN_ISSUES.md` backlog ("kerjakan semuanya sampai selesai, jika ada yg tidak bisa, kasih tau apa
yg tdk bisa kenapa dan risikonya apa"). Per Part A's own mechanism ("declared in its own build log
and commit message, not assumed"), this document is that declaration for a second, distinct backlog:
the findings of `docs/audit/2026-09-02-independent-launch-readiness-audit.md`.

**What this changes.** Per `AGENTS.md`'s own cross-reference to `ADR-0027` Part A: the per-task size
cap ("one feature slice, 1-3 migrations, 5-15 files") does not apply here. The bound moves to
**one backlog item = one bounded change = one commit = its own evidence**. A single work session may
touch many domains; each individual change stays small, independently reviewable, and independently
revertible.

**What does not change — Part C, unchanged, restated here.** Tenant isolation, RLS/RBAC, canonical
data integrity, financial correctness, and migration safety are never traded for velocity. No gate is
disabled, weakened, or relabelled to obtain a green result. No applied migration is edited —
corrective migrations only. No test is skipped, quarantined, or deleted to close an item. Every item
is closed only when fixed and re-verified (full Tier A gates: `typecheck`, `lint`, `test`, `db:test`,
`git:check-paths`, `security:check`, `next build` where applicable), or honestly dispositioned as out
of bounded scope — never by assertion.

**Reversal condition.** This declaration expires when every item below reaches `DONE` or an honest
terminal disposition (`DEFERRED_LARGE` / `NEEDS_PRODUCT_DECISION` / `NEEDS_HUMAN_GATE`) — matching
Part A §3's own reversal condition for the original backlog.

## Fixability classes (reusing `BACKLOG_INVENTORY.md`'s own vocabulary)

- `CODE` — a real, bounded code/schema/migration fix, executable and testable in-session.
- `CODE-BIG` — a real fix, but large enough (many files, many functions, or genuinely new subsystem
  wiring) that it is tracked as its own multi-batch effort rather than one commit.
- `PRODUCT` — the underlying gap is real, but closing it requires a product/business decision this
  session cannot make on its own (what CargoGrid's scope actually is, a pricing/workflow policy).
- `INFRA` — requires real external infrastructure, a vendor, or credentials this session cannot reach.

## Status legend

`TODO` · `IN_PROGRESS` · `DONE` (commit hash recorded) · `DEFERRED_LARGE` (real `CODE-BIG` item,
scoped and left for a dedicated follow-up session) · `NEEDS_PRODUCT_DECISION` · `NEEDS_HUMAN_GATE`

---

## Ø — The schema-exposure defect (highest priority; everything else sits on top of it)

| ID | Item | Class | Status | Commit |
|---|---|---|---|---|
| Ø1-tenant-admin | `tenant-admin-guard-deps.server.ts` `.from()` → RPC | `CODE` | **DONE** | `80b81ce` |
| Ø1-remaining-guards | `customer-ticket-guard-deps.server.ts`, `register-login-session-deps.server.ts` `.from()` → RPC | `CODE` | **DONE** | (this commit) |
| Ø1-customer-portal-guard + Ø2 | `customer-portal-guard-deps.server.ts` `.from()` → RPC, paired with a customer-layer-aware resolver that actually admits `customer_user` (the Ø2 lockout fix) | `CODE` | **DONE** | (this commit) |
| Ø1-query-layer | Convert the remaining ~160 `.from()` reads across ~65 `server/queries/*.ts` / `app/**/*.tsx` files to RPC (existing wrapper where one exists, new `app.*`+`public.*` wrapper where none does) | `CODE-BIG` | `DEFERRED_LARGE` (recon complete) | |

## B1 — `issue_finance_invoice` / `lock_finance_period` are `SECURITY INVOKER`

| ID | Item | Class | Status | Commit |
|---|---|---|---|---|
| B1 | Convert both `app.*` functions (and their already-existing `public.*` wrappers) to `SECURITY DEFINER`, pinning `search_path` on the `app.*` side (currently unpinned) | `CODE` | **DONE** | `130d49c` |

## D — Security and identity (all independently CRITICAL, each bounded)

| ID | Item | Class | Status | Commit |
|---|---|---|---|---|
| D3c | Session cookie ships `httpOnly:false`, 400-day `maxAge` — library defaults win over the app's own correct options because of spread order | `CODE` | **DONE** | `76b611e` |
| D2 | Cross-tenant guard in `run_next_route_planning_job` is swallowed by its own exception handler | `CODE` | **DONE** | `4fa9dff` |
| D3b | Suspending a user does not cut access — `resolve_access_context`/`has_active_tenant_membership` never read `app.users.status` | `CODE` | **DONE** | `1b9b8fc` |
| D3d | An enqueued job can leak another tenant's data — 4 of 5 workers never compare the payload's embedded ids back to the job's own tenant | `CODE` | **DONE** | `b9c1663` |
| D3 | IP allowlist bypass — `integrations/actions.ts:76` takes `x-forwarded-for` first-hop instead of last-hop | `CODE` | **DONE** | `f5f0878` |
| B8 | Finance `company_id` is caller-supplied and never validated against the caller's tenant across ≥8 reachable RPCs | `CODE` | **DONE** | (this commit) |
| D1 | MFA switched off; `verify_mfa_step_up_challenge` validates no real factor | `CODE` (challenge validation) + `INFRA` (enabling a real TOTP provider is a Supabase project auth-config change) | TODO | |
| D4 | `integration_secrets_encryption_key()` GUC never configured outside db-test fixtures | `INFRA` (real secret provisioning, not a code change) | NEEDS_HUMAN_GATE | |

## B — Money (beyond B1/B8, already tracked above)

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| B5 | Withholding tax added instead of deducted on customer invoices | `CODE` | **DONE** | (this commit) |
| B2 | GL is write-only — no trial balance/account balance/P&L/balance sheet | `CODE-BIG` | DEFERRED_LARGE | real report-building effort, weeks per the audit's own estimate |
| B3 | No credit notes; one issued invoice per job order, hard-capped | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | needs a billing-model decision (partial/milestone billing) before schema work |
| B4 | Multi-currency postings summed as raw numbers, no FX/base-amount columns | `CODE-BIG` | DEFERRED_LARGE | schema redesign across `finance_journals`/`finance_journal_lines` |
| B6 | Cost/cash never auto-post to GL | `CODE-BIG` | DEFERRED_LARGE | |
| B7 | Invoicing keyed off a hand-copied UUID; no credit control | `CODE-BIG` | DEFERRED_LARGE | needs a billable-jobs worklist UI |

## C — Indonesia

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| C3 | Tax console shows 11% as "0.11%" — display bug only, calculator is correct | `CODE` | **DONE** (`57fc8fe`) | trivial, high-value |
| C1 | No NPWP on tenant/org unit; no faktur pajak/NSFP/e-Faktur at all | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | compliance-domain modeling, needs a tax SME |
| C2 | PPh 21 uncomputable — no PTKP/bracket/NPWP columns | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | same |

## A — Operability

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| A3 | Publishing a role version silently revokes it from every holder (assignment pinned to `role_version_id`, publish never migrates it) | `CODE` | **DONE** | (this commit) |
| E2 | One-vehicle-one-shipment is an unlocked `EXISTS` check — racily bypassable | `CODE` | **DONE** | (this commit) — bundled `app.milestone_codes` seeding sub-finding NOT closed, see Housekeeping |
| F1 | No `error.tsx`/`not-found.tsx`/`global-error.tsx` anywhere; 2 reproduced uncaught 500s | `CODE` | **DONE** | (this commit) |
| F3 | 13 finance list RPCs hard-cap at 200 rows, no cursor param (101 other list RPCs already have one) | `CODE` | **DONE** | (this commit) |
| F5 | Shipment-order list and dispatch board each double-scan (`count:"exact"`) with an unindexed sort | `CODE` | **DONE** | (this commit) |
| F2 (multi-select) | `multi-select.tsx` options are keyboard-inaccessible (`onMouseDown` only, no key handler) | `CODE` | **DONE** | (this commit) |
| A5 | No scheduler ever invokes `scripts/jobs/supervisor.ts` in production | `CODE` (a cron entry point) + `INFRA` (actually provisioning the schedule) | **PARTIAL** | CODE half done (this commit); INFRA half (setting `CRON_SECRET` on the live Vercel project) is an operator step this repository cannot perform, see execution log |
| A1 | No cross-module navigation; 81/238 routes have no inbound link | `CODE-BIG` | DEFERRED_LARGE | weeks, UI over existing capability |
| A2 | Tenant creation, user invite, role assignment, master-data entry all lack UI | `CODE-BIG` | DEFERRED_LARGE | weeks |
| A2b | Customer portal has no sign-in route; no vendor principal layer exists at all | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | vendor layer is a schema-level product decision |
| A3b | No approval definition can ever be published (no UI); 8 flows hard-fail without one | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | needs approval-authoring UI, or a deliberate seeded-default policy decision |
| A4 | No import UI over 12 working import schemas | `CODE-BIG` | DEFERRED_LARGE | weeks |
| A6 | No Storage bucket/policies; uploads never store bytes; malware-scan status never advances, deadlocking 3+ flows | `CODE-BIG` | DEFERRED_LARGE | bucket+policy migration is boundable; full upload/scan wiring across the app is not |
| A7 | No PDF/print library; no printable document of any kind | `CODE-BIG` | DEFERRED_LARGE | weeks |
| F4 | `has_active_tenant_membership` costs ~138µs/row, unindexable, no caching layer anywhere | `CODE-BIG` (research) | DEFERRED_LARGE | needs a load-bearing-function redesign, not a quick patch |

## E — Domain modeling (all `PRODUCT`-gated per the audit's own framing, "decide what CargoGrid is")

| ID | Item | Class | Status |
|---|---|---|---|
| E1 | Every job order must originate from a quotation; no contract/repeat order path | `PRODUCT` | NEEDS_PRODUCT_DECISION |
| E3 | No UoM on stock; free-text locations; warehouse billing has no invoice FK | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE |
| E4 | Whole cost/document domains absent (fixed assets, maintenance, customs, BOM, …) | `PRODUCT` | NEEDS_PRODUCT_DECISION |
| E5 | Telematics: device can never reach `installed` (blocked by A6); ETA is straight-line/40kmh | `CODE-BIG` | DEFERRED_LARGE |
| E6 | No webhook publisher; no GraphQL/OpenAPI surface | `CODE-BIG` | DEFERRED_LARGE |

## New findings discovered during remediation (not in the original audit)

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| NEW-1 | `app.claim_next_job`'s own audit-trail write (`capture_audit_event`) attributes the claim event to the job's ORIGINAL requester (`v_job.requested_by_auth_user_id`), not the calling worker -- so under a genuine (non-null) session identity, `capture_audit_event`'s own `assert_actor_is_session_identity` check raises `actor_identity_mismatch` for ANY caller who is not that exact original requester, before any of the job-type-specific authority guards (e.g. D2's) are ever reached. Discovered while writing a behavioral regression test for D2 in `advanced-tms-route-load-planning.sql` -- confirmed live, not theoretical. In production this is masked because the only real caller today is the job supervisor's service-role client (null session identity, which the check exempts), but it means NO job-claiming RPC in this family can currently be correctly exercised, or safely called, by any genuine authenticated session other than the job's own creator -- over-blocking legitimate cross-user operation of the SAME tenant's own queue, not just closing off cross-tenant abuse. | `CODE` | **DONE** | (this commit) |

## Housekeeping

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| LINT-1 | `scripts/jobs/supervisor.ts:50` trips the service-role import guard — pre-existing, confirmed via `git stash` baseline comparison before the Ø1 commit | `CODE` | **DONE** (`57fc8fe`) | quick, unblocks a red Tier A gate |
| E2-seed | `app.milestone_codes` ships with 0 rows and no seed (bundled in E2's own audit paragraph) — a live, reproducible dead-end dropdown (`ingest-milestone-event-form.tsx`) on a fresh install | `CODE` | TODO | attempted and reverted during E2 (this session): a migration-time direct-insert seed (mirroring `finance_tax_codes`/`config_types`) collided with ≥16 existing `scripts/db-tests/*.sql` fixtures that already `register_milestone_code` their own definitions for names an obvious baseline set would need (`delivered`, `departed_origin`, `out_for_delivery`, `customs_hold` among them) — `app.milestone_codes` is genuinely platform-wide (no `tenant_id`) and `register_milestone_code` is idempotent, so a pre-seeded row silently pre-empts a later fixture's own intended `is_customer_visible`/`affects_eta`/`is_terminal` values (confirmed live: `operations-milestone-management.sql`'s own internal-only `customs_hold` regressed to customer-visible). Needs a full audit of every existing `register_milestone_code` call site first (exact code/name/category/visibility each test expects) before a seed can be written without silently breaking one of them. |

---

## Execution log

- 2026-09-06 — Ø1-tenant-admin closed (`80b81ce`). See that commit for full gate evidence.
- 2026-09-07 — this document created; declaring backlog-remediation mode; beginning B1.
- 2026-09-07 — Ø1-query-layer recon complete (8-cluster parallel sweep, 158 call sites across
  66 files, `CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json`): **154 need a brand-new `app.*` +
  `public.*` SECURITY DEFINER function authored from scratch, 3 unclear, only 1 swappable onto an
  existing RPC.** This confirms Ø1-query-layer is genuinely `CODE-BIG` — realistically dozens of
  small, individually-verified migrations (each new function mirroring the correct tenant/RLS/
  authority semantics for its table, adversarially checked, one or a few per commit), not a single
  session's work. Dispositioned `DEFERRED_LARGE` with the recon itself as the scoped starting point
  for that follow-up effort; the classification file names every call site so no further rediscovery
  is needed before starting.
- 2026-09-07 — B1 closed (`130d49c`); LINT-1 + C3 closed together (`57fc8fe`).
- 2026-09-07 — D3c closed (`76b611e`).
- 2026-09-07 — D2 closed (`4fa9dff`).
- 2026-09-07 — D3d closed (`b9c1663`).
- 2026-09-07 — D3b closed (`1b9b8fc`). Discovered and resolved a genuine tension with the
  pre-existing, deliberate HRT-295 (ISS-2026-104) design (5 self-service RPCs must keep working
  through a suspension) via a principled split: a new, narrower `app.has_active_identity_link`
  (the exact prior `has_active_tenant_membership` body) preserves that behavior, while
  `has_active_tenant_membership`/`resolve_access_context` themselves now correctly deny a
  suspended/revoked `app.users` row everywhere else (450+ RLS policies, `evaluate_permission`).
- 2026-09-07 — D3 closed (`f5f0878`). Widened beyond the audit's own stated count (2 call sites)
  after a repository-wide grep found 9 real occurrences of the vulnerable
  `x-forwarded-for.split(",")[0]` pattern; all 9 fixed.
- 2026-09-07 — B8 closed (`85be6c9`). Fifteen finance write RPCs (not the audit's own "≥8"
  estimate — a systematic `pg_get_function_identity_arguments` sweep found the true count) now
  validate a caller-supplied `p_company_id` via a new shared `app.assert_finance_company_org_unit`
  precondition (same-tenant, `unit_type = 'company'`, checked after authority/IP-allowlist,
  before any other business-logic validation). New findings this pass: none.
- 2026-09-07 — B5 closed (`d2e95ad`). `app.calculate_finance_tax` now discloses the resolved
  rule's own `tax_type`; a new `finance_invoices.withholding_tax_amount` column carries a
  withholding-type tax's own withheld amount instead of `tax_amount`, leaving `total_amount`
  unaffected; `app.issue_finance_invoice` posts the AR open item/AR-control debit net of the
  withheld amount and DEBITS (never credits) the tax rule's own governed `recoverable_account_id`
  (or the `withholding_tax_receivable_default` posting-map fallback). Also found and fixed, while
  writing this fix's own regression test, a latent pre-existing bug in the SAME branch logic: a
  plpgsql row variable's own `IS NOT NULL` requires every field non-null (never merely "was a row
  found"), so `v_tax_rule is not null` silently read false whenever the fetched rule had any other
  nullable column set to null (e.g. `currency`) — unexercised by any test before this one, since no
  prior fixture ever configured a real `output_account_id`/`recoverable_account_id` on a tax rule.
  Fixed by checking each row's own guaranteed-NOT-NULL `id` column instead.
- 2026-09-07 — E2 closed (this commit). A real partial unique index,
  `resource_assignments_active_resource_unique` on `(tenant_id, resource_id) where is_current and
  status = 'active'`, makes "one vehicle, one shipment" a genuine database-level invariant;
  `app.assign_resource`/`app.reassign_resource`/`app.resume_resource_assignment` all now catch a
  real concurrent violation of it (`GET STACKED DIAGNOSTICS`, mirroring
  `app.start_vendor_assessment`'s own established pattern) and re-raise the same named errors
  their own sequential pre-checks already gave, never a raw `unique_violation`; `resume_resource_
  assignment` also gained the sequential pre-check it never had at all. Proven via a real
  two-process concurrent race in `operations-resource-assignment.sql`. The new hard invariant made
  an existing fixture (`advanced-tms-shipment-tracking-health-writer.sql`) unconstructible — it had
  deliberately bypassed `app.assign_resource` via a raw insert to give two shipments the SAME
  active vehicle assignment, to exercise `app.arbitrate_and_project_vehicle_position`'s own
  defensive multi-row loop against a state the RPC itself already blocked but a future path
  "might" someday produce; that fixture now gives the second shipment its own, separate vehicle
  instead, with every dependent assertion adapted accordingly. The bundled `app.milestone_codes`
  seeding sub-finding was attempted and reverted — see the new `E2-seed` Housekeeping row for why
  and what a real fix needs.
- 2026-09-07 — Ø1-remaining-guards and Ø1-customer-portal-guard + Ø2 closed together (this commit),
  since all three broken call sites share one root cause and one fix. Ø1:
  `customer-ticket-guard-deps.server.ts`, `customer-portal-guard-deps.server.ts`, and
  `register-login-session-deps.server.ts` all still ran `supabase.from("tenants")...` against schema
  `app`, which PostgREST never exposes — the same defect `Ø1-tenant-admin` already fixed for
  `tenant-admin-guard-deps.server.ts`. Ø2: `20260906090000`'s own resolver,
  `app.resolve_tenant_by_slug_for_actor`, could not be reused for any of the three — it deliberately
  mirrors `app.tenants`' own `tenants_select_own_tenant` RLS policy
  (`has_active_tenant_membership(id) AND NOT actor_holds_customer_user_layer(id)`), which structurally
  excludes every `customer_user` by construction. Two of the three guards admit ONLY `customer_user`
  (the exact Ø2 lockout, just reached through this RPC instead of a raw table read), and the third
  (login-session tracking) needs both layers, since it fires from the one shared `app/(public)/login/`
  route for every principal layer. Fix: one new resolver, `app.resolve_tenant_by_slug_for_member`
  (`20260907150000`), identical to `resolve_tenant_by_slug_for_actor` except it omits the
  customer-layer exclusion — `20260730560000`'s own migration already proved, in a disposable
  database, that a `customer_user` principal satisfies `has_active_tenant_membership` on its own (it
  is the tenant-admin guard's own additional `AND NOT actor_holds_customer_user_layer` line that
  excludes them, not `has_active_tenant_membership` itself). Plus its `public.*` Option-2 wrapper with
  an identical grant set (`service_role`, `authenticated` only). All three TS call sites' pure-logic
  interfaces (`customer-ticket-guard.ts`, `customer-portal-guard.ts`, `register-login-session.ts`) and
  their real `deps.server.ts` wirings were updated to thread the caller's `authUserId` through to the
  new RPC. No `db-test` file needed changes — `scripts/db-tests/public-api-wrapper-regression.sql`'s
  own assertions are catalog-derived (every externally-callable `app.*` function, not a hardcoded
  list), so the new function and its wrapper are verified by the existing, unmodified test
  automatically.
- 2026-09-07 — F1 closed (this commit). Added `app/error.tsx`, `app/global-error.tsx`, and
  `app/not-found.tsx` — the root-level boundaries the audit found 0 of anywhere (195 `loading.tsx`
  existed, but no error/not-found equivalent). `error.tsx`/`global-error.tsx` follow
  `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5's Error-state contract (human-readable
  message + a request id + retry, never the raw exception) — `error.digest` (Next's own
  production-safe correlation id for a Server Component throw) is shown as the request id, reusing
  the existing `components/ui/error-state.tsx` primitive already used by 218 pages for their own
  known-query-failure states, so an uncaught throw now renders consistently with every already-
  handled one. `global-error.tsx` renders its own `<html>`/`<body>` deliberately unstyled (no
  design-system primitives) since it exists specifically to survive the root layout itself failing.
  Also root-caused and fixed both of the audit's own reproduced 500s: (1) `/api/v1/status` — all 9
  `app/api/v1/**` route handlers call `recordApiV1Success()` AFTER already computing a successful
  response, with no try/catch around it, so a transient failure in the audit-log write itself
  (`record_api_request` erroring) propagated as an uncaught exception, discarding an
  already-succeeded (for a mutation route, already-COMMITTED) result; fixed at the one shared
  function (`lib/api-gateway/authenticate.server.ts`) rather than at each of the 9 call sites, so
  audit logging can never again override a response the gateway already decided to return — the
  same "best-effort, never a precondition" posture `register-login-session.ts`/`resolveRequestClientIp`
  already establish. Regression test added (`tests/api/v1/status.test.ts`), confirmed to fail without
  the fix and pass with it. (2) `/tracking/{token}` — `app.lookup_public_shipment_tracking` itself is
  designed to never raise, but this route's own TS layer (`lookupPublicShipmentTracking()`) can still
  throw `PublicTrackingQueryError` on a real RPC/network error or a row that fails its zod schema;
  since this route is unauthenticated and outside every portal guard (no session/tenant context to
  fall back on), the lookup is now wrapped in try/catch and degrades to the same "Tracking
  unavailable" copy a bad token already renders. Verified via a full `npx next build` (the same
  "booted build" condition the audit itself reproduced against) — builds clean, `/_not-found`
  registered, zero errors.
- 2026-09-07 — F3 closed (this commit). All 13 finance list functions (`app.list_finance_
  ar_open_items`/`ap_open_items`/`invoices`/`journals`/`receipts`/`settlements`/`bank_accounts`/
  `bank_transactions`/`vendor_bills`/`period_locks`/`reconciliation_runs`/`subledger_batches`/
  `journal_corrections`) gained `p_limit integer default 200`/`p_after_id uuid default null`,
  mirroring the `p_after_id` keyset idiom `app.list_attendance_correction_requests` and 100 other
  list/search RPCs already use; each fetches `limit + 1` rows so the TS query layer can trim and
  detect truncation the same way `server/queries/bounded-list.ts#toBoundedList` already does for
  direct-table reads. The anchor-row lookup is additionally scoped `and tenant_id = p_tenant_id`
  (a hardening beyond the `list_attendance_correction_requests` precedent, which doesn't tenant-
  scope its own anchor) — closes a narrow cross-tenant sort-key oracle a foreign `p_after_id`
  could otherwise open. Deeply tested for both distinct sort-order shapes (ascending `due_date`+id
  tie-break for AR open items, descending `created_at`+id tie-break for reconciliation runs) in a
  new file, `scripts/db-tests/finance-list-cursor-pagination.sql`; the remaining 11 share the
  identical two code shapes (verified by direct code review) and are exercised without error by
  their own existing, unmodified db-test files (the new parameters are optional). All 13
  `server/queries/*.ts` wrapper functions gained the same optional, additive `limit`/`afterId`
  input fields — return type and default behavior unchanged for every existing caller; no
  page.tsx "Load more" UI wiring was added in this bounded change (the audit's own F3 paragraph is
  about the RPC signature specifically; its separately-stated "only 10 of 238 tenant pages offer
  any pagination control" finding is independent, repo-wide, and out of this item's scope).
  Two same-pass, live-caught bugs in the migration's own first draft, both found by re-running
  `pnpm run db:test` (never assumed fixed): (1) each `DROP + CREATE` (required since the
  parameter list changes — Postgres doesn't allow `CREATE OR REPLACE` to add parameters) silently
  reset the recreated function's privileges to Postgres's own implicit PUBLIC-execute default,
  re-opening the exact class of gap `ERR-2026-004`/`PLT-118` closed repository-wide — caught by
  `finance-accounts-payable.sql`'s own pre-existing "anon holds zero EXECUTE" assertion; fixed by
  adding the standing `revoke execute on all functions in schema app from public` once per
  recreated function. (2) all 13 were recreated plain `language plpgsql stable`, copied from their
  own 2026-07-29 creation migrations — but `20260810900000_harden_finance_authority_chain_tierc_
  completeness.sql` had already widened every one of them to `security definer` with `set
  search_path to 'app', 'pg_temp'`, the CURRENT authoritative shape a migration-built database
  actually has; recreating from the pre-hardening shape silently reverted that hardening, exactly
  the app.\<name\>/public.\<name\> security-mode drift class `20260826010000`'s own header comment
  documents as an RLS-bypass-by-wrapper risk. Caught by `public-api-wrapper-regression.sql`'s own
  exhaustive `prosecdef` parity assertion failing against all 13; fixed by adding `security
  definer` + `set search_path = app, pg_temp` to each (body/filter/sort logic otherwise
  byte-identical, verified line by line against `20260810900000`'s own current text).
- 2026-09-07 — F5 closed (this commit). The shipment-order list and dispatch board
  (`server/queries/shipment-order.ts#listShipmentOrders`, `basic-dispatch.ts#
  listDispatchReadyQueue`) each ran `.select("*", { count: "exact" }).range(from, to)` with no
  supporting index for their own `ORDER BY` column — `app.shipment_orders` carried 9 indexes,
  none leading with `created_at` (only `(tenant_id, updated_at desc, id desc)`, added for a
  different query) and none at all for `planned_pickup_at`, forcing a full scan-and-sort of every
  tenant row on both the count pass and the data pass, every page load. The dispatch board
  compounded this: `app.dispatch_ready_queue` runs `app.evaluate_dispatch_readiness` (a ~40-line
  `SECURITY DEFINER` function) once per matching row via a `LATERAL` join, on BOTH passes (Postgres
  cannot prove the lateral output is unused just because `count(*)` doesn't reference it). Two
  fixes: (1) two new additive covering indexes, mirroring an existing precedent's own shape exactly
  — `shipment_orders_tenant_created_at_id_idx (tenant_id, created_at desc, id desc)` for the
  shipment-order list, and a PARTIAL `shipment_orders_tenant_assigned_pickup_id_idx (tenant_id,
  planned_pickup_at nulls last, id) where status = 'assigned'` for the dispatch board, scoped to
  exactly the row set `app.dispatch_ready_queue`'s own `WHERE` clause reads. (2)
  `listDispatchReadyQueue` now takes its exact count as a SEPARATE, plain HEAD request against
  `app.shipment_orders` directly (`tenant_id` + `status = 'assigned'`), never touching the view or
  the lateral join for the count pass — provably equivalent, not approximated:
  `shipment_orders_select_scoped` (the base table's own RLS policy) is the IDENTICAL predicate the
  view's own `WHERE` clause uses, and neither the view's filter nor the row count depends on
  `r.is_ready`/`r.blockers` at all. Live-proven with a new assertion appended to
  `scripts/db-tests/operations-basic-dispatch.sql`: under the SAME real, RLS-scoped authenticated
  session, a plain base-table count and a count through the view are asserted equal. Net effect:
  the readiness function now runs exactly `pageSize` times per dispatch-board page load, not
  `pageSize + totalCount`. `listShipmentOrders` keeps its existing single `count: exact` query as-is
  (no `LATERAL` join to make asymmetric there) — only the missing index was the gap for that screen.
  These two screens are 2 of 10 files across the codebase sharing the `count: exact` shape (the
  audit's own count); a wholesale redesign of all ten, or of the numbered-jump-to-page
  `components/tables/pagination.tsx` UI they all feed (which genuinely needs an exact total to
  render page-number links — switching away from `count: exact` everywhere is a real UX trade-off,
  not a drop-in change), is out of this bounded item's scope.
- 2026-09-07 — A3 closed (this commit). `app.role_assignments.role_version_id` binds an
  assignment to one SPECIFIC version, never the role in general, and `app.evaluate_permission`
  requires that version's own `status = 'published'` — its own header comment already conceded
  this exact defect as a "disclosed, bounded limitation... not an oversight." `app.
  publish_role_version` archived the prior published version but never touched `app.
  role_assignments` at all, so every real holder lost every permission the role granted the
  moment anyone republished a new version of the SAME role. `app.publish_role_version` now
  migrates every ACTIVE assignment still bound to the version it is about to archive onto the
  version it is publishing, in the same transaction as the publish itself — safe as a plain
  `UPDATE` (can never violate `role_assignments_active_unique`: nobody could hold an active
  assignment on the version being published before this function runs, since `app.assign_role`
  requires `status = 'published'` to assign at all, and that version was still a `draft` until the
  status flip a few lines above). A new `role_lifecycle_history` event, `version_migrated`, is
  recorded once per migrated assignment, mirroring `assigned`/`revoked`'s own per-row convention.
  `CREATE OR REPLACE FUNCTION` — unchanged signature, no `DROP + CREATE`, no `public.*` wrapper
  touch needed; confirmed via the F3-taught check (grepping for a later `ALTER FUNCTION`/`CREATE
  OR REPLACE` touching this function's own security mode) that `app.publish_role_version` was
  never widened to `SECURITY DEFINER` or given a pinned `search_path` by any later migration, so
  there was nothing to preserve this time. Live-proven with a new assertion appended to
  `scripts/db-tests/role-permission.sql`: republishing a role's second version migrates an active
  assignment bound to the first (now-archived) version onto the second, `app.evaluate_permission`
  keeps granting the same permission the identity already held (proving the fix end to end, not
  just the row-level bookkeeping), and exactly one `version_migrated` event is recorded, scoped to
  that one assignment; a second sub-case proves the negative — republishing a role nobody has ever
  been assigned to fabricates zero `version_migrated` events. Deliberately narrow, matching the
  audit's own A3 finding exactly — does not touch any OTHER "published version" binding pattern
  elsewhere in the repository (automation rules, workflow definitions, approval definitions); the
  evaluator's own comment already disclosed "no auto-reassignment... anywhere in this repository"
  as a repository-wide posture, and this migration deliberately closes it for role_assignments/
  role_versions only, the one the audit named and reproduced. `scripts/db-tests/rbac-
  enforcement.sql` had its own pre-existing "a stale assignment ... fails closed" block, which
  encoded the audit-confirmed A3 bug itself as this test's own intended contract — caught live by
  re-running `pnpm run db:test` after the migration (never assumed fixed): `expected the stale
  assignment to deny, got allowed=t reason=role_grant`. Rewrote the block to assert the CORRECTED
  contract instead (republishing migrates the assignment, `evaluate_permission` keeps granting it),
  removed the old block's own now-meaningless "re-assigning restores access" recovery step, and
  re-verified the entire 1600+-line file end to end — several much-later blocks (HRT-295's own
  "grantee still holds active FIN:Approve" baseline foremost) depend on this identity's assignment
  surviving in an active, granting state all the way through the file, and all passed unmodified.
- 2026-09-07 — F2 closed (this commit). `components/forms/multi-select.tsx`'s `<li role="option">`
  elements had `onMouseDown` as their only handler — no key handler, no `tabIndex`, no
  `aria-activedescendant` — so an option could never be reached from the keyboard at all (WCAG
  2.1.1 Level A, exactly as the audit found). Fixed by adopting this repository's own already-
  correct sibling pattern, `components/forms/combobox.tsx`'s WAI-ARIA combobox implementation,
  verbatim rather than inventing a second one: real DOM focus stays on the text input the entire
  time; `role="combobox"`/`aria-expanded`/`aria-controls`/`aria-activedescendant` on the input,
  plus a new `handleKeyDown` for ArrowDown/ArrowUp/Enter/Escape, tell an assistive-technology user
  which option is virtually focused and let them act on it without ever moving focus onto an
  `<li>` — the same reason neither this fix nor `Combobox` puts `tabIndex` on the options
  themselves. Enter adds the active option and clears the query (mirroring this component's own
  multi-value `add()`, precisely as `onMouseDown` already did) rather than committing-and-closing
  like `Combobox`'s single-value case. The one real consumer (`api-keys-admin-panel.tsx`'s n8n
  connector scope picker) needed no changes — same props, same behavior for a mouse user.
  Live-verified in a real browser per this session's own standing UI-verification requirement:
  built and started the app (`next build && next start --port 3100`) and drove a temporary,
  backend-independent scratch page under the existing unauthenticated `(internal)` route group
  (mirroring the accepted `internal/design-system/components` showcase pattern, since no live
  Supabase project exists in this sandbox to exercise the component through its one real
  authenticated consumer) with a Playwright script: confirmed Tab reaches the input, focusing it
  opens the list with `aria-activedescendant` already on the first option, ArrowDown/ArrowUp move
  `aria-activedescendant` across options without ever moving real DOM focus off the input, Enter
  adds the active option as a chip and updates the bound value, and Escape closes the dropdown
  without altering the selection — then deleted the scratch page before committing (it is not part
  of this change; only `components/forms/multi-select.tsx` is touched). No test runner exists for
  `.tsx` files in this repository yet (confirmed by `pagination.tsx`'s own header comment), so no
  new automated test accompanies this fix — `typecheck`/`lint`/`ui:check` all pass, and the full
  `pnpm run test` (5949 tests), `db:test` (sanity pass; no migration or db-test file touched), `git:
  check-paths`, and `security:check` gates all pass unchanged. `check-release-freeze.ts` needed no
  amendment (no `supabase/migrations/*.sql` or `scripts/db-tests/*.sql` file touched by this item).
- 2026-09-07 — A5 PARTIAL (this commit), the CODE half only, exactly as the item's own
  classification disclosed up front (`CODE` + `INFRA`, "attempt a bounded first slice"). The audit's
  finding was precise: `scripts/jobs/supervisor.ts` is "correct and installs nothing," and this
  repository's actual deploy target is serverless — "no Vercel crons, no Edge Functions, no
  scheduled workflow, and `pg_cron` is never created in any migration... on a serverless deploy
  target with no long-lived host." There is no long-lived process to point a scheduler AT; the fix
  has to be an HTTP entry point plus a Vercel Cron schedule calling it. Added `app/api/cron/
  supervisor-tick/route.ts`: a `GET` route that calls `supervisor.ts`'s own exported `runTick`
  (the identical function `--once` mode already calls) for exactly one tick — every lane
  (scheduler, database-jobs, and all five external-handoff workers) keeps the same per-lane
  isolation and authority model `supervisor.ts`'s own header already documents; nothing about the
  job/schedule authority logic was reimplemented, only a caller was added. Authorization mirrors
  Vercel's own documented Cron Jobs contract exactly: Vercel signs its own invocations with
  `Authorization: Bearer <CRON_SECRET>` once that variable is set on the project, checked here with
  `crypto.timingSafeEqual` (never `===`, so a byte-by-byte mismatch can't leak how many leading
  bytes matched); an unset `CRON_SECRET` fails every request closed, never open — there is no
  "unauthenticated but allowed" mode for a route that runs privileged, service-role-authenticated
  writes. `vercel.json` now carries the `crons` entry itself (`*/5 * * * *`, matching the cadence
  the audit's own `docs/runbooks/human-execution-pack.md` §6 table already recommended for the
  shortest-interval sweeps), so the schedule ships as code, not a dashboard click. `CRON_SECRET`
  is now a properly declared, `secret`-classified `scripts/env/schema.ts` entry — the FIRST entry
  in that registry to actually use `requiredIn` (required only in `production`, since that is the
  one tier `vercel.json`'s `crons` entry actually targets); added a new regression test in
  `scripts/env/validate.test.ts` proving env-class-conditional requiredness actually works
  end-to-end (local accepts it missing, production rejects it missing), since no prior test had
  ever exercised that code path at all — every existing `ENV_REGISTRY` entry before this one was
  unconditionally required everywhere. Also registered the new secret in
  `scripts/data-classification/registry.ts` (`env:CRON_SECRET`) so `pnpm run data-classification:
  check`'s own adoption gate doesn't flag it as unclassified, and added the new route file to
  `eslint.config.js`'s `serviceRoleImportGuard` allowlist (the existing, deliberately manual gate on
  every legitimate service-role importer) alongside the other Route Handlers already on it. New
  route-level test suite (`tests/api/cron/supervisor-tick.test.ts`, using the existing
  `installRpcFetchStub` HTTP-layer harness `tests/api/v1/support/rpc-fetch-stub.ts` already
  provides): unset secret and wrong/missing `Authorization` all deny with 401 AND never call any
  RPC at all (proving fail-closed, not merely fail-*something*); a correct secret runs a real tick
  end to end and reports all 7 lanes; a simulated `run_due_jobs` failure proves the route surfaces
  `runTick`'s own per-lane isolation as 207 (that ONE lane failed, every other lane still ran) rather
  than collapsing to a 500. **What remains open, and why it is not closed here:** setting the actual
  `CRON_SECRET` value on the live Vercel project is an operator action against infrastructure this
  repository has no access to from inside a coding session — exactly the boundary `docs/runbooks/
  human-execution-pack.md` §6 already draws ("whoever owns the deployment," "about an hour, once").
  Marked `PARTIAL` rather than `DONE`: the code path is real, tested, and fails closed by
  construction, but the schedule does not actually run in production until that one secret is set.
- 2026-09-07 — NEW-1 closed (this commit). Root-caused precisely by live reproduction against a
  disposable database (not static reading alone -- a static read of `app.capture_audit_event`'s
  own body does not show the actual mechanism): `capture_audit_event`'s IAE-037 fix defaults
  `p_support_access_grant_id` from `app.current_support_session(p_tenant_id, p_actor_auth_user_
  id)`, whose own FIRST statement is `perform app.assert_actor_is_session_identity(p_actor_auth_
  user_id)` -- correct for the ~1735 other call sites across this repository, where the passed
  actor genuinely IS the caller's own session identity by construction, but wrong for `app.
  claim_next_job` and (found during this same investigation, identical bug, identical fix)
  `app.complete_job`: neither has any real actor-identity parameter of its own, and both
  substituted `v_job.requested_by_auth_user_id` -- the job's ORIGINAL requester -- for the
  identity-asserted actor. Live-reproduced end to end against a disposable database before
  writing the fix: enqueued a job as one genuine tenant member (a rep), then claimed/ran it as a
  second, equally genuine, active member of the SAME tenant (a manager, via `app.
  run_next_route_planning_job`) -- reliably raised `actor_identity_mismatch` every time, exactly
  as the audit finding described. Fixed in `20260907190000_fix_job_claim_complete_audit_actor_
  mismatch_new1.sql`: both functions now pass `auth.uid()` (the CALLER's own real session
  identity -- null for service-role/nested-SECURITY-DEFINER-only calls, exactly preserving
  today's production behavior; the genuine session identity when invoked from within an
  authenticated user's own SECURITY DEFINER wrapper, trivially satisfying the assertion since the
  two values are now identical by construction) as the identity-asserted actor, never `v_job.
  requested_by_auth_user_id` -- which is preserved as event metadata instead of being discarded.
  `auth.uid()` is read defensively (`begin`/`exception`), mirroring `app.assert_actor_is_session_
  identity`'s own established idiom, rather than bare -- this was not paranoia: while writing this
  fix's own db-test regression, a genuinely different, previously-undetected quirk surfaced live
  (documented in detail in the release-freeze HUNDRED-AND-THIRTEENTH PASS comment and in `scripts/
  db-tests/background-job.sql`'s own new test) -- a custom/placeholder GUC like `request.jwt.
  claims` set via `SET LOCAL` outside an explicit transaction block does not revert to unset once
  the block ends, it reverts to an empty string, which is not valid JSON, and neither function had
  ever read that GUC before this fix (so no prior code path could ever have surfaced it). The
  defensive read degrades a leaked '' to a null actor exactly like never having set it at all,
  rather than crashing a job-queue primitive on malformed session state. `CREATE OR REPLACE
  FUNCTION` for both -- unchanged signatures, no `DROP + CREATE`; confirmed via the F3-taught
  check that neither function was ever touched by any later migration, so no security-mode
  hardening to preserve. New regression in `scripts/db-tests/background-job.sql` proves the fix
  end to end (a genuinely different same-tenant teammate claims and completes another identity's
  job without raising, and the resulting `app.audit_logs` rows correctly attribute the calling
  identity while preserving the original requester as metadata); `scripts/db-tests/advanced-tms-
  route-load-planning.sql`'s own pre-existing D2 regression comment (which had disclosed this
  exact NEW-1 limitation as blocking a real end-to-end cross-session exercise of that guard) was
  corrected to say so is now fixed, without adding a redundant cross-tenant case there (would need
  a second tenant that file has never otherwise needed; the general cross-user proof already lives
  in `background-job.sql`). Full `pnpm run db:test` re-run twice end to end (once mid-investigation
  against the correct file order via the real `run.sh` glob, once as the final sanity pass) --
  `ALL PASSED` both times, alongside `typecheck`/`lint`/full `pnpm run test` (5955 tests)/`git:
  check-paths`/`security:check`.
