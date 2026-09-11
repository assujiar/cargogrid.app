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
| Ø1-query-layer | Convert the remaining ~160 `.from()` reads across ~65 `server/queries/*.ts` / `app/**/*.tsx` files to RPC (existing wrapper where one exists, new `app.*`+`public.*` wrapper where none does) | `CODE-BIG` | `IN_PROGRESS` (clusters 0-1, 38 tables, **DONE**; cluster 2 batch 1, 5 tables / 10 call sites, **DONE**; clusters 2 remainder-7, 86 call sites, remain — see below) | (this commit) |

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
| D1 | MFA switched off; `verify_mfa_step_up_challenge` validates no real factor | `CODE` (challenge validation) + `INFRA` (enabling a real TOTP provider is a Supabase project auth-config change) | **PARTIAL** | CODE half done (this commit) — now requires the calling session itself to be authenticated at AAL2; INFRA half (enabling a real TOTP/phone provider, building the client-side `challengeAndVerify()` UI) is an operator/product task this repository cannot perform, see execution log |
| D4 | `integration_secrets_encryption_key()` GUC never configured outside db-test fixtures | `INFRA` (real secret provisioning, not a code change) | NEEDS_HUMAN_GATE | a new real consumer now depends on this GUC being set: `app.platform_integration_secrets` (this commit, user-directed A6 extension) fails closed with `encryption_key_not_configured` until it is |

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
| A6 | No Storage bucket/policies; uploads never store bytes; malware-scan status never advances, deadlocking 3+ flows | `CODE-BIG` | **PARTIAL** | user-directed, part 2 of 2: a real private Storage bucket, a real `malware_scan` job type/worker, and a real VirusTotal scan adapter now exist, and one of the 3 named deadlocked flows (vendor compliance document submission/renewal) is wired end to end. Still bounded, not DONE: ticket-reply attachments and shipment document checklists are not wired (the pattern now exists for them to reuse); every scan still fails closed on D4's own still-open GUC gap until an operator configures both the encryption key and a real VirusTotal API key |
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
| E2-seed | `app.milestone_codes` ships with 0 rows and no seed (bundled in E2's own audit paragraph) — a live, reproducible dead-end dropdown (`ingest-milestone-event-form.tsx`) on a fresh install | `CODE` | **DONE** | (this commit) — see execution log for the full call-site audit and the two codes deliberately excluded |

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
- 2026-09-07 — E2-seed closed (this commit). The prior attempt's own mistake wasn't the
  approach (a migration-time direct-insert seed, mirroring `finance_tax_codes`) -- it was
  skipping the audit before guessing values. This attempt started from one: `grep -rn
  register_milestone_code scripts/db-tests/*.sql` across all 11 files that use the registry
  (33 real call sites), grouped by `code`, comparing every occurrence's own `name`/`category`/
  `is_customer_visible`/`affects_eta`/`is_terminal` tuple byte-for-byte. Two REAL, independent
  cross-file disagreements turned up -- not the prior attempt's own wrong guess, but two
  actual different tests wanting two different things for the identical code: `delivery_
  arrival` (`advanced-tms-geofence-route-deviation-signals.sql` wants affects_eta=false/
  is_terminal=false; `advanced-tms-wms-integrated-verification.sql` wants both true) and
  `delivered` (`operations-integrated-verification.sql` and `operations-milestone-
  management.sql` both want affects_eta=true; `operations-public-tracking.sql` wants false).
  Both excluded from the seed -- no value this migration could pick would avoid silently
  breaking one of those files' own current, passing assertions, and register_milestone_code's
  idempotent-first-wins semantics mean a seed's own value always wins over whichever test runs
  first. Every OTHER code was confirmed identical across every one of its own call sites --
  `picked_up` alone recurs identically in 4 separate files -- and is now seeded in
  `20260907200000_seed_milestone_codes_baseline_e2_seed.sql`: `pickup_arrival`, `pickup_
  departure`, `picked_up`, `departed_origin`, `in_transit`, `customs_hold`, `out_for_delivery`,
  `delivery_departure` (8 of the ~10 unprefixed, production-meaningful codes the audit itself
  implicitly expected; file-prefixed synthetic test codes like `customer_tracking_*`/
  `iaeeta_*`/`vperf_*`/`iss146b_*` were excluded on purpose -- not a real baseline). Notably,
  re-deriving `customs_hold` this time found it was NEVER actually in conflict --
  `operations-milestone-management.sql` and `operations-public-tracking.sql` both already
  wanted `is_customer_visible=false`; the PRIOR attempt's own regression was its own wrong
  guess (customer-visible=true), not an inherent test disagreement, so `customs_hold` is
  safely seeded this time with the value both files already shared. `scripts/release/check-
  release-freeze.ts`'s HUNDRED-AND-FOURTEENTH PASS documents the full reasoning inline. Full
  `pnpm run db:test` re-run twice (once immediately after writing the migration, once as the
  final sanity pass after the release-freeze update) -- `ALL PASSED` both times, confirming
  none of the 11 dependent db-test files' own assertions changed, alongside `typecheck`/
  `lint`/full `pnpm run test` (5955 tests)/`git:check-paths`/`security:check`.
- 2026-09-07 — D1 PARTIAL (this commit), the CODE half only, following the same "attempt a
  bounded first slice" disposition A5 already established for a `CODE` + `INFRA` item. The
  audit's own finding was precise: `app.verify_mfa_step_up_challenge` accepts no OTP, factor
  id or assertion at all -- the constrained principal satisfies it itself. That is not an
  oversight the function's own creation (`20260807100000`, IAE-027) missed: its own header
  already discloses, as a deliberate design boundary, that real TOTP secret crypto is
  Supabase Auth's own external infrastructure this repository never fabricates a parallel
  copy of. The REAL, narrower gap the audit actually found: nothing confirmed a genuine
  Supabase-side MFA check ever happened before this function recorded "verified" -- it is
  granted directly to `authenticated`, reachable from the app's real API surface with zero
  real second factor, and `server/mutations/enterprise-mfa.ts`'s own `verifyMfaStepUpChallenge`
  is confirmed to be a thin RPC pass-through with no prior real `supabase.auth.mfa.
  challengeAndVerify()` call anywhere in this repository. Fixed in
  `20260907210000_require_real_aal2_session_mfa_step_up_iss_d1.sql`: the function now requires
  the CALLING session itself to already be authenticated at AAL2 -- `auth.jwt() ->> 'aal' =
  'aal2'`, Supabase's own Authenticator Assurance Level claim, stamped into a session's JWT
  only after GoTrue has actually verified a real second factor, entirely independent of
  anything this repository's own schema could fabricate. Gated on `auth.uid() is not null`
  (mirroring `app.assert_actor_is_session_identity`'s own established "engages only for a
  genuine authenticated session" idiom verbatim) after a full audit of every one of the ~30
  real `app.verify_mfa_step_up_challenge` call sites across the 12 `scripts/db-tests/*.sql`
  files that depend on it as a precondition for some OTHER high-risk action under test found
  that every single one calls it with a null session identity already (the same service-
  role-equivalent exemption this repository's whole authority model already relies on for
  db-tests) -- so this gate needed zero changes to any of those 12 files, confirmed by a full
  `pnpm run db:test` re-run twice (`ALL PASSED` both times). In real production, PostgREST
  always populates a real session's JWT for every authenticated request, so there is no
  realistic external path to this function with a null session identity -- the gate engages
  on exactly the one channel the audit's own finding is about. Live-caught while writing this
  fix's own db-test regression: the identical class of bug `20260907190000`'s (NEW-1) own
  migration already documents in detail -- a leaked empty-string `request.jwt.claims` GUC --
  bit again here because calling `auth.uid()` BARE a second time (rather than relying solely
  on the one call already safely wrapped inside `assert_actor_is_session_identity`) crashed on
  exactly that leaked state; both `auth.uid()` and the newly-added `auth.jwt()` are now read
  defensively (`begin`/`exception`) inside this function. New regression appended to
  `scripts/db-tests/enterprise-mfa-session-controls.sql` proves a genuine AAL1 session (no
  `aal` claim at all, and an explicit `"aal": "aal1"`) is rejected without consuming the
  challenge, a genuine AAL2 session still succeeds, and a null-session caller remains
  unaffected. `scripts/db-tests/fixtures/auth-schema-stub.sql` gained `auth.jwt()` (Supabase's
  own real reference implementation) to make this exercisable at all. `server/mutations/
  enterprise-mfa.ts`'s known-error-code registry and its own test file were extended for the
  new `mfa_step_up_requires_real_aal2_session` classification. **What remains open, and why it
  is not closed here:** actually enabling a real TOTP/phone factor provider
  (`supabase/config.toml`'s currently-disabled `[auth.mfa.totp]`/`[auth.mfa.phone]` sections)
  is a Supabase project auth-config change an operator must make against the live project, and
  no client-side UI in this repository yet calls Supabase's real `challengeAndVerify()` before
  invoking this RPC -- building that enrollment/challenge UI and turning on a real provider is
  a separate, larger product/infra task, not attempted here. Marked `PARTIAL` rather than
  `DONE`: the database gate now genuinely fails closed for the one channel it is reachable
  through, but no real second factor can be verified in production until both remaining pieces
  exist.
- 2026-09-08 — A6/D4 extension, part 1 of 2 (this commit): platform integration secrets
  infrastructure. User-directed: after discussing A6's own malware-scan gap, the user asked for
  a VirusTotal API key to close it, entered via the Supreme Admin UI, generalized so any FUTURE
  platform-level (not tenant-owned) third-party API key is added the same way rather than as an
  environment variable requiring a redeploy. Every existing secret-bearing table in this
  repository (`app.integration_connection_credentials` and its siblings) is tenant-scoped -- a
  tenant's own credential for its own third-party account; there was no shape for a secret the
  PLATFORM ITSELF holds to call an outbound service on every tenant's behalf. New migration
  `20260908000000_create_platform_integration_secrets.sql` adds exactly that shape --
  `app.platform_integration_secrets` (`app.set_platform_integration_secret`/`app.
  get_platform_integration_secret`/`app.list_platform_integration_secrets`) -- reusing the
  EXISTING `app._encrypt_integration_secret`/`_decrypt_integration_secret` pgcrypto mechanism
  (`20260826050000`) rather than inventing a second one, and mirroring `app.
  platform_scheduled_task_definitions` (`20260902020000`) as the established "platform-wide, no
  tenant_id, Supreme-Admin-only" shape. New Supreme Admin UI at `/supreme/integrations`
  (`page.tsx`/`actions.ts`/a form component, mirroring `supreme/helpdesk`'s own shape exactly)
  lists configured keys (name/description/who/when -- NEVER a value, encrypted or otherwise --
  structurally impossible to leak back out since `list_platform_integration_secrets`'s own
  `RETURNS TABLE` shape has no such column) and a form to add or rotate one.
  Live-caught and fixed during this migration's own authoring: ISS-2026-309's exact regression
  class -- `revoke execute on function public.X(...) from public` does NOT revoke the direct
  `anon`/`authenticated`/`service_role` grants Supabase's own `ALTER DEFAULT PRIVILEGES` rule
  gives every new `public.*` function at CREATE time (only `scripts/db-tests/lib/setup-
  disposable-db.sh`'s own mirror of that rule, added specifically for this class of bug, caught
  it locally rather than only on a live project) -- fixed by revoking from all three named roles
  plus PUBLIC explicitly, per `20260830200000`'s own established correction, before every one of
  the 3 new `public.*` wrappers this migration adds. Also re-confirmed, mid-investigation, that
  every EARLIER fix this session (A3/A5/NEW-1/D1 -- all `CREATE OR REPLACE` on unchanged
  signatures) remains correctly reachable in production: each already had a pre-existing
  `public.*` wrapper (a pure pass-through) that needed no change at all.
  Deliberately gated by, not working around, CG-AUDIT-2026-09-02 D4's own disclosed gap: every
  write and read through this table calls `app.integration_secrets_encryption_key()`, which
  raises `encryption_key_not_configured` while that GUC is unset (true in every environment
  today) -- the Supreme Admin UI's own error message names this plainly rather than failing
  silently or falling back to plaintext. New `scripts/db-tests/platform-integration-secrets.sql`
  proves the full CRUD/authority/encryption surface, including the fail-closed D4 path and the
  ISS-2026-309 grant-parity fix, against a real disposable database. Full `pnpm run db:test`
  re-run twice (once immediately after authoring, once as the final sanity pass after the
  release-freeze update) -- `ALL PASSED` both times, alongside `typecheck`/`lint`/full `pnpm run
  test` (5969 tests)/`git:check-paths`/`security:check`/a real `next build` (route registers)/a
  real-browser check confirming the new page redirects unauthenticated exactly like the
  pre-existing `/supreme/helpdesk` page. Part 2 (the actual A6 deadlock fix -- Storage bucket +
  RLS policies, the VirusTotal scan adapter, and wiring one real upload flow end to end) follows
  in a separate commit.
- 2026-09-08 — A6/D4 extension, part 2 of 2 (this commit): the actual A6 deadlock fix. New
  migration `20260908010000_close_a6_storage_bucket_and_malware_scan_job_type.sql` provisions a
  real, private `tenant-documents` Storage bucket (`insert into storage.buckets`, `public =
  false`) -- closing the audit's own literal "no migration creates a Storage bucket" finding --
  and asserts RLS is enabled on `storage.objects` explicitly rather than relying on it silently
  (zero permissive policies + RLS enabled already denies every caller but `service_role`, which
  bypasses RLS via the Storage API's own service-key posture -- mirrors `app.files.storage_path`'s
  own service_role-only precedent; no signed-URL issuance is added, staying inside the same
  disclosed boundary `20260801080000`'s own header already established). The same migration adds
  a new `malware_scan` `job_type`, widened on BOTH of ATW-031's sources of truth (the `app.jobs`
  CHECK constraint and `app.generic_job_types()`, the latter a `CREATE OR REPLACE` on an unchanged
  signature needing no new `public.*` wrapper) plus their two TypeScript mirrors
  (`GENERIC_JOB_TYPES`, `IMPORT_EXPORT_JOB_TYPES`) and the two SQL-side drift-gate literals in
  `scripts/db-tests/background-job.sql` -- every place ATW-031's own history proved a new job type
  can silently drift out of sync was updated together, not just the one that happened to be
  exercised first.
  A new sixth external-handoff worker, `scripts/jobs/malware-scan-worker.ts`, mirrors the existing
  five workers' own shape exactly and is wired into `scripts/jobs/supervisor.ts`'s `ALL_LANES` --
  picked up automatically by A5's cron route with no route change. It claims `malware_scan` jobs
  and calls `lib/malware-scan/process-malware-scan-job.server.ts`, the first real caller anywhere
  in this repository of `app.record_file_scan_result` (that function's own header, at
  `20260719140000_create_document_file_engine.sql:558`, names itself the bounded adapter interface
  "a future scan-provider webhook/job would call" -- this is that job). It downloads the uploaded
  bytes from Storage, reads a VirusTotal API key via `app.get_platform_integration_secret` (part 1
  of this extension), and calls the new `lib/malware-scan/scan-file-with-virustotal.server.ts` --
  a real, bounded (a request timeout on every fetch, and a bounded number of poll attempts rather
  than blocking indefinitely on VirusTotal's own asynchronous analysis) outbound multipart
  file-upload HTTP client, the first one anywhere in this repository (every prior outbound `fetch`
  here — webhooks, notifications, geocoding, tax lookups, e-invoicing — sends JSON, never a real
  file body). Two failure classes are handled deliberately differently, disclosed in the file's own
  header: "could not even attempt a scan" (no API key configured yet, or a storage download
  failure) retries via the job framework's own exponential backoff, leaving the file `pending`
  exactly as before; "a scan was attempted and produced some real, actionable answer" (a completed
  verdict, or VirusTotal never finishing within the bounded poll window, or an unparseable
  response) always resolves the file OFF `pending` for good via `app.record_file_scan_result`,
  never leaving it in limbo.
  One real flow is wired end to end in this same commit, exactly as disclosed in part 1's own
  entry and in the backlog row above: vendor compliance document submission/renewal
  (`app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts`) now reads the real
  uploaded bytes, stores them via `.storage.from().upload()` behind
  `app.initiate_file_upload`'s own server-generated `storage_path` (compensating with a soft
  `app.request_file_deletion` on a storage failure, matching this repository's own established
  compensating-action convention), and enqueues the `malware_scan` job with the real, already-
  authority-checked submitter as its actor. The audit's other two named deadlocked flows
  (ticket-reply attachments, shipment document checklists) are deliberately NOT wired here --
  still bounded to one flow, per this checkpoint's own disclosed scope -- but the pattern
  (initiate upload → store bytes → enqueue `malware_scan` → worker resolves the status) now exists
  for them to reuse without re-deriving it.
  New `scripts/db-tests/fixtures/storage-schema-stub.sql` (mirroring `auth-schema-stub.sql`'s own
  rationale: no Supabase-managed `storage` schema exists in a bare disposable Postgres) and new
  `scripts/db-tests/tenant-documents-storage-malware-scan.sql` prove, against a real disposable
  database: the bucket exists/is private/RLS is enabled; a real enqueue → claim →
  `app.record_file_scan_result` → complete cycle moves a real `app.files` row from `pending` to
  `clean`; `document_scan_already_resolved` still refuses a different re-resolution; and an
  infected verdict quarantines even the file's own uploader via `app.authorize_file_access`. New
  `lib/malware-scan/scan-file-with-virustotal.server.test.ts` exercises the VirusTotal adapter
  against a real local loopback HTTP server (not a mocked `fetch`), and new
  `lib/malware-scan/process-malware-scan-job.server.test.ts` /
  `scripts/jobs/malware-scan-worker.test.ts` cover the job processor and worker loop with an
  injectable scanner dependency, mirroring `processWebhookDeliveryJob`'s own
  injected-`checkUrlSafety` pattern. Full `pnpm run db:test` -- `ALL PASSED` -- alongside
  `typecheck`/`lint`/full `pnpm run test` (5990 tests)/`git:check-paths`/`security:check`/a real
  `next build`.
  Still PARTIAL, not DONE, disclosed plainly rather than claimed closed: 2 of the audit's 3 named
  deadlocked flows remain unwired, and every scan — including the one now-wired flow — still fails
  closed on D4's own still-open gap (`encryption_key_not_configured`) until an operator configures
  both the encryption key GUC and a real VirusTotal API key via `/supreme/integrations`; a file
  that VirusTotal genuinely cannot resolve within `max_attempts` dead-letters and needs a
  support-authority `app.requeue_dead_letter_job` call, the same residual-gap class A5/D4 already
  disclose for their own bounded scopes.
- 2026-09-08 — Ø1-query-layer cluster 0 batch 1 closed (this commit), user-directed ("lanjut sampe
  siap launching") continuation past the 2026-09-07 recon's own `DEFERRED_LARGE` disposition.
  Reassessed severity first: every one of the 158 recon-catalogued `.from()` reads against `app.*`
  tables has NEVER worked in production (confirmed live: `supabase/config.toml` exposes only
  `public`/`graphql_public` to PostgREST, `app` is completely invisible to it), and cluster 0 (CRM/
  commercial, 54 sites / 32 tables) sits behind real, reachable pages
  (`/commercial/accounts`, `/contacts`, `/contracts`, `/costing-requests`, `/opportunities`,
  `/quotations`, `/leads`, `/prospects`) — this is a live, currently-broken read path, not merely
  the architectural backlog the prior framing implied, and is now treated as the top launch-
  blocking priority. This batch closes the first 8 of cluster 0's 32 tables: app.accounts,
  app.account_conversions, app.contacts, app.activities, app.customer_contracts,
  app.customer_contract_price_components_directory, app.costing_requests,
  app.costing_request_components. New migration
  `20260908020000_close_o1_query_layer_cluster0_batch1_crm_core.sql` adds 15 new `app.*`+`public.*`
  Option-2 wrapper pairs (see that migration's own header and per-function comments for the full
  authority-derivation reasoning). Every function was drafted via an adversarial design→verify→fix
  pipeline before ever touching a database, checked against three explicit rules baked into both
  the design and verify prompts: RULE A (`app.assert_actor_is_session_identity` as the first
  executable statement, the ATW-031/032 actor-impersonation guard — 5 of the first 8 drafts were
  caught missing it and fixed before commit), RULE B (reproducing the CURRENT RLS predicate for a
  table, not its original pre-hardening text — `20260730560000`'s `customer_user`-layer exclusion
  on `app.accounts`/`app.customer_contracts`/`app.customer_contract_price_components_directory` was
  caught missing from one draft this way), and RULE C (citing the most recent `create or replace`
  of a precedent function, never its original body). Beyond the adversarial pipeline, this pass's
  own db-test (`scripts/db-tests/o1-query-layer-cluster0-batch1.sql`, run against a real disposable
  database) caught two further, genuine defects the pipeline's own verify stage had missed (both
  introduced in a later fix-and-reverify round the pipeline never re-ran adversarially after a
  session-capacity interruption): `app.list_contacts` and `app.get_contact_by_id` had both
  reintroduced `normalized_email`/`normalized_phone`/`duplicate_fingerprint` into their return
  shape — a PII-correlation leak the recon's own instructions explicitly required excluding, caught
  via an `information_schema.parameters` introspection of the functions' own OUT parameters rather
  than a sample-row check. Both fixed directly in the migration before it was ever applied outside
  a disposable test database. All 4 affected TS query files (`server/queries/account.ts`,
  `contact.ts`, `contract.ts`, `costing.ts`) and every real call site (11 `page.tsx` files) were
  switched from `.from()` to `.rpc()` in this same commit, per this migration's own embedded "TS
  INTEGRATION" notes — nothing was left half-migrated. `server/queries/account.test.ts`,
  `contact.test.ts`, `contract.test.ts`, `costing.test.ts` updated to mock `.rpc()` instead of
  `.from()` for every migrated function. Full Tier A gate suite re-run clean: `typecheck`, `lint`
  (0 errors), the 5,992-test unit suite, a full `pnpm run db:test` (`ALL PASSED`, 515 migrations /
  259 db-test files), `git:check-paths`, `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-EIGHTEENTH PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  Still `IN_PROGRESS`, not `DONE`: 24 of cluster 0's 32 tables remain, plus clusters 1-7 (104 more
  call sites across finance/identity/dispatch/tracking/documents/analytics/misc) — the same
  Design→Verify→Fix pipeline with RULE A/B/C baked in is the established, working pattern for the
  remaining batches, not a new approach to derive.
- 2026-09-09 — Ø1-query-layer cluster 0 batch 2 closed (this commit), continuing the same
  user-directed ("lanjut sampe siap launching") mandate. Closes 9 of the remaining 24 tables:
  `app.margin_rule_versions`, `app.margin_calculations_directory`, `app.opportunities_directory`,
  `app.opportunity_stage_history`, `app.sales_plans`, `app.sales_targets`, `app.forecast_snapshots`,
  `app.pipeline_categories`, `app.win_loss_reasons` (`server/queries/margin.ts`, `opportunity.ts`,
  `pipeline.ts`). New migration
  `20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_opportunity.sql` adds 12 new
  `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix pipeline batch
  1 established (RULE A/B/C baked into both the design and verify prompts). 8 of 9 tables passed
  independent re-verification against the live repo on the first draft; `app.opportunities_directory`
  had a documentation/audit-trail-integrity defect caught and fixed before commit (a false "never
  replaced" RULE C claim in its own header comment, citing 4 sibling functions as unreplaced when 4 of
  5 actually have later rewrites — the authority predicate itself, independently re-read against every
  current body, was unaffected and remained correct; this was a citation-accuracy defect, not a live
  security bug).
  A genuine, live-verified finding surfaced by this pass's own db-test
  (`scripts/db-tests/o1-query-layer-cluster0-batch2.sql`), not by the design/verify pipeline: a first
  version of the test wrongly assumed `app.pipeline_categories`/`app.win_loss_reasons` (whose own
  predicates carry no separate `is_supreme_admin()` clause) would deny a global Supreme Admin with
  zero tenant membership. In fact `app.has_active_tenant_membership`'s own CURRENT body
  (`20260907110000_fix_suspended_user_retains_access_iss_d3b.sql`) already ORs in
  `app.is_supreme_admin(...)` internally, so a Supreme Admin transitively passes EVERY function gated
  by that helper — including these two, just via a different path than `app.margin_rule_versions`'s
  own explicit outer `OR is_supreme_admin()`. The test's assertions and two migration header comments
  that had claimed "no supreme-admin bypass" were both corrected to describe this transitive behavior
  accurately, confirmed live against a real disposable database rather than assumed either way. All 3
  affected TS query files and every real call site (8 `page.tsx` files) switched from `.from()` to
  `.rpc()` in this same commit. Full Tier A gate suite re-run clean: `typecheck`, `lint` (0 errors),
  the 5,992-test unit suite — including a fixed false positive in `check-rls-initplan.ts`'s own
  regression guard, whose naive "match `create|alter policy`, then take everything up to the next
  semicolon as the policy body" heuristic misread this migration's own header/comment prose (which
  happened to contain the literal phrase "alter policy" followed by a bare `auth.uid()`/
  `app.is_supreme_admin(p_auth_user_id)`-shaped mention within the same `comment on function ... is
  '...'` string) as a live RLS policy clause; reworded the prose (never suppressed or weakened the
  guard itself), reverified 0 findings — a full `pnpm run db:test` (`ALL PASSED`, 516 migrations / 260
  db-test files), `git:check-paths`, `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-NINETEENTH PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  Still `IN_PROGRESS`, not `DONE`: 15 of cluster 0's 32 tables remain (credit/approval/costing-
  response reads, leads/prospects/quotations, vendor-rate directory reads), plus clusters 1-7 (104
  more call sites across finance/identity/dispatch/tracking/documents/analytics/misc).
- 2026-09-09 — Ø1-query-layer cluster 0 batch 3 closed (this commit), continuing the same
  user-directed ("lanjut sampe siap launching") mandate. Closes 5 of the remaining 15 tables:
  `app.costing_responses_directory` (`list_costing_responses_for_request`),
  `app.costing_response_components_directory` (`list_costing_response_components`),
  `app.credit_profiles_directory` (`list_credit_profiles`, `get_credit_profile_for_account`,
  `get_credit_profile_by_id`), `app.credit_profile_overrides` (`list_credit_profile_overrides`), and
  a single `app.approval_requests` entity-ref lookup (`get_approval_requests_entity_refs`, taking
  `p_ids uuid[]`) deliberately shared by both the credit-profile approval inbox
  (`server/queries/credit.ts`) and the pre-existing quotation approval inbox
  (`server/queries/quotation-approval.ts`) rather than adding two near-identical single-purpose
  functions for the same table. New migration
  `20260909010000_close_o1_query_layer_cluster0_batch3_costing_credit_approval.sql` adds 7 new
  `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix pipeline
  batches 1-2 established (RULE A/B/C baked into both the design and verify prompts). Unlike either
  prior batch, this one's independent verify stage found zero issues across all 5 tables on the
  first draft, and this pass's own db-test (`scripts/db-tests/o1-query-layer-cluster0-batch3.sql`,
  287 lines) passed completely on its first full run against a real disposable database — no
  defect surfaced by testing that the design/verify pipeline had missed, the first batch of this
  cluster where that held true. `list_costing_response_components` preserves the pre-existing
  "all-or-nothing" masking posture for cost-restricted callers (zero rows for every line item on a
  cost-masked response, never a masked-but-visible row), distinct from the column-level
  `*_masked` flag pattern used by the credit-profile and margin functions. Proactively reworded
  this migration's own header/comment prose before writing the db-test (learning applied from the
  HUNDRED-AND-NINETEENTH PASS) to avoid `check-rls-initplan.ts`'s known "alter policy"/bare-auth-
  call false-positive class — caught one instance at `list_costing_responses_for_request`'s own
  comment ("no later ALTER POLICY exists" + bare `auth.uid()` mentions) before it was ever run
  against the guard, reworded, reverified 0 findings. All 3 affected TS query files
  (`server/queries/costing.ts`, `credit.ts`, `quotation-approval.ts`) and every real call site (3
  `page.tsx` files) switched from `.from()` to `.rpc()` in this same commit;
  `quotation-approval.ts`'s own `QuotationApprovalQueryClient` type intentionally keeps both
  `"from"` and `"rpc"` since its sibling `listQuotationApprovalRuleVersions` still legitimately
  reads `app.quotation_approval_rules` directly (an out-of-scope table for this batch). Full Tier A
  gate suite re-run clean: `typecheck`, `lint` (0 errors), the 5,992-test unit suite,
  `check-rls-initplan.ts` (0 findings), a full `pnpm run db:test` (`ALL PASSED`, 517 migrations /
  261 db-test files), `git:check-paths`, `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTIETH PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  Still `IN_PROGRESS`, not `DONE`: 10 of cluster 0's 32 tables remain (leads, prospects,
  quotations_directory, quotation_lines_directory, quotation_approval_rules,
  quotation_acceptance_tokens, vendor_rate_versions_directory, v_active_vendor_rates,
  rate_selections_directory, vendor_rate_tiers_directory — args already prepared for batches 4 and
  5), plus clusters 1-7 (104 more call sites across finance/identity/dispatch/tracking/documents/
  analytics/misc).
- 2026-09-09 — Ø1-query-layer cluster 0 batch 4 closed (this commit), continuing the same
  user-directed ("lanjut sampe siap launching") mandate. Closes 6 of the remaining 10 tables:
  `app.leads` (`list_leads`, `get_lead_by_id`), `app.prospects` (`list_prospects`,
  `get_prospect_by_id`), `app.quotations_directory` (`get_quotation_by_id`,
  `list_quotation_versions`, `list_quotations_for_opportunity`, `list_quotations_for_tenant`),
  `app.quotation_lines_directory` (`list_quotation_lines`), `app.quotation_approval_rules`
  (`list_quotation_approval_rule_versions`), `app.quotation_acceptance_tokens`
  (`list_quotation_acceptance_tokens`). New migration
  `20260909020000_close_o1_query_layer_cluster0_batch4_leads_prospects_quotation_directory.sql`
  adds 11 new `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial
  Design→Verify→Fix pipeline batches 1-3 established (RULE A/B/C baked into both stages).
  **Infra note**: the Workflow tool's own subagent-spawning path failed twice in a row during
  this batch's design stage with a permission-handler schema-validation bug (a session/
  harness-level defect confirmed by testing that the plain Agent tool worked correctly in the
  same session — not a code or prompt-design issue). Rather than keep retrying the broken
  path, this batch was completed via 6 parallel design agents plus 6 independent verify
  agents launched directly through the Agent tool, applying the identical RULE A/B/C
  discipline the Workflow pipeline itself encodes — the pipeline's rigor, not merely its
  automation, is what actually matters, and it survived the substitution intact.
  Two real, security/data-relevant issues were found and fixed during the independent verify
  pass, before this migration was ever applied to any database: (1) `app.prospects`' first
  draft returned all 26 physical columns, including `normalized_legal_name`/
  `normalized_tax_id`/`duplicate_fingerprint`/`disqualified_at`/`archived_at` — none of which
  is part of the real `ProspectSchema`/`parseProspect` contract (`server/contracts/prospect/
  prospect.ts`). Fixed to exclude all five, matching the "return exactly what the TS contract
  consumes" discipline batch 1's `app.contacts` and this same batch's own `app.leads` already
  established (`app.leads` keeps its own `duplicate_fingerprint` only because `LeadSchema`
  explicitly requires it; `ProspectSchema` has no such field, so it does not qualify for that
  exception). (2) `app.quotations_directory` had a documentation-only miscount — the header
  prose claimed the replaced view's current column count was 39; independently recounting the
  live view's own `SELECT` list found 40. The actual reproduced column lists in every function
  body and `RETURNS TABLE` clause were already correct throughout — a citation-accuracy
  defect, not a masking or authority bug — corrected for accuracy. The other 4 tables
  (`app.leads`, `app.quotation_lines_directory`, `app.quotation_approval_rules`,
  `app.quotation_acceptance_tokens`) passed independent adversarial re-verification with zero
  issues found. This pass's own db-test (`scripts/db-tests/o1-query-layer-cluster0-batch4.sql`)
  passed completely on the first full run against a real disposable database — no defect
  surfaced by testing that the design/verify pipeline had missed.
  **Residual findings, disclosed not fixed** (out of scope for this read-only batch, flagged
  for whoever owns the mutation surface): `app.assign_lead`'s and
  `app.convert_lead_to_prospect`'s current bodies (`20260902200000_harden_tenant_id_
  disclosure_commercial.sql`) both lack the `assert_actor_is_session_identity` RULE A guard —
  `app.assign_lead` had it added by an earlier ATW-032 patch (`20260730510000`) but a later,
  unrelated fix silently dropped it again; `app.convert_lead_to_prospect` never had it in any
  version. Similarly, `app.add_quotation_line`/`app.remove_quotation_line` (quotation line
  mutations) still lack the same guard in their latest bodies. Both are live RULE A gaps in
  already-shipped mutation code, not introduced or touched by this migration — recorded here
  rather than silently left for someone to rediscover.
  All 5 affected TS query files (`server/queries/lead.ts`, `prospect.ts`, `quotation.ts`,
  `quotation-approval.ts`, `quotation-acceptance.ts`) and every real call site (9 `page.tsx`
  files) switched from `.from()` to `.rpc()` in this same commit. Full Tier A gate suite
  re-run clean: `typecheck`, `lint` (0 errors), the 5,993-test unit suite,
  `check-rls-initplan.ts` (0 findings), a full `pnpm run db:test` (`ALL PASSED`, 518
  migrations / 262 db-test files), `git:check-paths`, `security:check`, and a real `next
  build`. `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTY-FIRST PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  Still `IN_PROGRESS`, not `DONE`: 4 of cluster 0's 32 tables remain (vendor_rate_versions_
  directory, v_active_vendor_rates, rate_selections_directory, vendor_rate_tiers_directory —
  args already prepared for batch 5), plus clusters 1-7 (104 more call sites across finance/
  identity/dispatch/tracking/documents/analytics/misc).

- 2026-09-09 — Ø1-query-layer cluster 0 batch 5 closed (this commit), continuing the same
  user-directed ("lanjut sampe siap launching") mandate. Closes the **last** 4 tables of
  cluster 0's 32: `app.vendor_rate_versions_directory` (`list_rate_versions_for_master_record`,
  `get_rate_version_by_id`, `list_pending_rate_versions`,
  `list_procurement_linked_vendor_rate_versions`, `list_vendor_rate_versions_for_vendor`),
  `app.v_active_vendor_rates` (`list_active_vendor_rates`), `app.rate_selections_directory`
  (`list_rate_selections_for_request`), and `app.vendor_rate_tiers_directory`
  (`list_vendor_rate_tiers`). New migration
  `20260909030000_close_o1_query_layer_cluster0_batch5_vendor_rate_directories.sql` adds 8 new
  `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix pipeline
  batches 1-4 established (RULE A/B/C baked into both stages), again completed via parallel
  Agent-tool design/verify calls rather than the Workflow tool (whose subagent-spawning path
  remained broken this session — same infra defect noted in batch 4's entry above).
  `list_active_vendor_rates` is a deliberately **new** function rather than a thin wrapper
  reusing `app.search_vendor_rates`: that RPC requires `app.evaluate_permission(actor, tenant,
  'COM', 'View')`, a dynamically tenant-configured permission not guaranteed for every
  actively-membered staff role, and has different ordering/default-limit behavior — reusing it
  would have either over- or under-restricted this read relative to the view's own real RLS
  predicate. This decision was independently re-derived and confirmed by the verify stage, not
  assumed from the design draft.
  Two comment-only issues were found and fixed during the independent verify pass, before this
  migration was ever applied to any database: (1) `app.vendor_rate_versions_directory`'s header
  comment justified keeping `list_procurement_linked_vendor_rate_versions`/
  `list_vendor_rate_versions_for_vendor` as two separate functions with a factually false claim
  ("not nested/subset forms of each other" — `vendor_master_id = value` mathematically **does**
  imply `vendor_master_id IS NOT NULL` under SQL three-valued logic). Corrected to state the
  true reasoning (this codebase's own convention of preferring distinct, self-documenting
  single-purpose RPCs over one function whose row set pivots on an optional parameter) while
  keeping the actual decision (5 separate functions, not merged) unchanged — no SQL logic in
  any of the 8 functions needed correction beyond this one comment. (2) A third occurrence of
  the established `check-rls-initplan.ts` "ALTER POLICY"/bare-auth-call false-positive class
  (first seen in batch 3, recurring in batch 4's own migration prose too), this time in
  `app.list_rate_selections_for_request`'s own `comment on function` string ("no later ALTER
  POLICY exists on this policy" plus bare `auth.uid()` mentions). Reworded, not suppressed
  ("no later ALTER POLICY exists" → "no later rewrite of this policy exists"; bare
  `auth.uid()` mentions de-parenthesized), and reverified 0 findings.
  This pass's own db-test (`scripts/db-tests/o1-query-layer-cluster0-batch5.sql`) passed
  completely on the first full run against a real disposable database — no defect surfaced by
  testing that the design/verify pipeline had missed.
  Both affected TS query files (`server/queries/rate.ts`, `procurement-rate.ts`) and every real
  call site (5 `page.tsx` files: `commercial/costing-requests/[requestId]`,
  `commercial/rates`, `commercial/rates/[rateVersionId]`, `procurement/rates`,
  `procurement/rates/[rateVersionId]`) switched from `.from()` to `.rpc()` in this same commit.
  `listVendorRateVersionsForVendor` has no live `page.tsx` caller today (test-only) but was
  converted for consistency and to keep the whole file on one calling convention.
  Full Tier A gate suite re-run clean: `typecheck`, `lint` (0 errors), the 5,993-test unit
  suite, `check-rls-initplan.ts` (0 findings), a full `pnpm run db:test` (`ALL PASSED`, 519
  migrations / 263 db-test files), `git:check-paths`, `security:check`, and a real `next
  build`. `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTY-SECOND PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  **Cluster 0 (CRM/commercial, 32/32 tables) is now fully `DONE`.** Still open: clusters 1-7
  (104 more call sites across finance/identity/dispatch/tracking/documents/analytics/misc) —
  next up under the same "lanjut sampe siap launching" mandate.

- 2026-09-10 — Ø1-query-layer cluster 1 (finance) batch 1 closed (this commit), continuing the
  same user-directed ("lanjut sampe siap launching") mandate. Opens cluster 1 and closes it
  **completely** in this single batch — all 8 of cluster 1's call sites across 6 tables/views:
  `app.shipment_actual_costs_directory` (`get_shipment_actual_cost`),
  `app.billing_readiness_evaluations` (`get_current_billing_readiness_evaluation`,
  `list_billing_readiness_evaluations` — kept as two separate functions, matching the existing
  TS layer's own two-function shape rather than merging via an `only_current` flag),
  `app.billing_readiness_handoffs` (`list_billing_readiness_handoffs`),
  `app.finance_currencies` (`list_finance_currencies`), `app.finance_rounding_modes`
  (`list_finance_rounding_modes`), `app.finance_period_close_checklist_items`
  (`list_finance_period_checklist_items`), and `app.job_profitability_directory`
  (`get_job_profitability_directory`). New migration
  `20260910000000_close_o1_query_layer_cluster1_batch1_finance_reads.sql` adds 8 new
  `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix pipeline
  cluster 0's batches established (RULE A/B/C baked into both stages), again completed via
  parallel Agent-tool design/verify calls rather than the Workflow tool (whose
  subagent-spawning path remained broken this session — the design stage was interrupted twice
  by session/weekly rate limits mid-run and resumed via `SendMessage` from each agent's own
  prior transcript, preserving all research already done, exactly as established in cluster 0's
  batch 4).
  **Notable design decision, independently re-verified**: `app.list_finance_currencies`/
  `app.list_finance_rounding_modes` are declared `SECURITY INVOKER` (the unmarked default),
  not `SECURITY DEFINER` like every other function in this remediation series — both tables
  carry a bare `using (true)` SELECT policy for role `authenticated` plus a direct table-level
  grant, matching the established live precedent for this exact "global reference table, zero
  actor param" shape (`app.list_api_versions`/`app.list_webhook_event_types`). The independent
  verify pass confirmed this decision against the real table grants (not merely the precedent
  functions' own declarations) and proved it under a real `authenticated`-role session in the
  db-test, before this migration was ever applied to any database.
  One citation-only defect was found and fixed during verify (before the migration was ever
  applied): a precedent citation for `app.list_webhook_event_types` pointed at the migration
  that creates the underlying TABLE, not the one that declares the function itself.
  **Disclosed, out-of-scope findings** (a different table/cluster; recorded so they are not
  silently rediscovered): a dangling forward citation to `app.list_finance_currencies` in
  `20260830140000_create_incident_communication.sql` (now retroactively true), and a genuinely
  broken `app.list_incident_communication_audiences`/`public.list_incident_communication_
  audiences` pair — both declared invoker, but the underlying table has RLS enabled with NO
  create policy at all and revokes SELECT from `authenticated` — an `authenticated` caller
  would hit a real Postgres permission-denied error, not return rows. Neither fixed here
  (different table, different cluster of this same Ø1 effort).
  This pass also reworded one header-comment citation of
  `app.evaluate_permission(..., 'OPS', 'View cost')` (a pre-existing, Operations-only call,
  quoted only for RULE C citation, not new enforcement) after it tripped
  `scripts/data-classification/check-registry.test.ts`'s own quoted-literal scan of every
  "finance"-named migration file for the FIN action "View cost" — the same reword-not-suppress
  discipline this series already applies to `check-rls-initplan.ts`'s comment-prose false
  positives, applied here to a different, sibling static-analysis guard that this migration's
  own filename (containing "finance") happened to make newly reachable.
  This pass's own db-test (`scripts/db-tests/o1-query-layer-cluster1-batch1.sql`) passed on the
  second full run — the first run surfaced two real fixture-setup gaps (a missing NOT NULL
  `duplicate_fingerprint` column on the fixture's own `app.accounts` insert, and a missing
  `tenant_admin` layer grant needed only to publish the `finance_close_policy` config/generate
  the fiscal calendar, per `app.check_config_object_authority`'s own real requirement), neither
  a defect in any of the 8 new functions themselves.
  All 6 affected TS query files (`server/queries/actual-cost.ts`, `billing-readiness.ts`,
  `currency-exchange-rate.ts`, `finance-config.ts`, `fiscal-period.ts`,
  `job-profitability.ts`) and every real call site (4 `page.tsx` files:
  `operations/job-orders/[jobOrderId]`, `operations/shipment-orders/[shipmentOrderId]`,
  `finance/fiscal-periods/[periodId]`, plus `finance/exchange-rates` which needed no code
  change since `listFinanceCurrencies`'s own signature is unchanged) switched from `.from()`
  to `.rpc()` in this same commit. Full Tier A gate suite re-run clean: `typecheck`, `lint` (0
  errors), the 5,993-test unit suite, `check-rls-initplan.ts` (0 findings), a full
  `pnpm run db:test` (`ALL PASSED`, 520 migrations / 264 db-test files), `git:check-paths`,
  `security:check`, and a real `next build`. `scripts/release/check-release-freeze.ts` amended
  (HUNDRED-AND-TWENTY-THIRD PASS, `migrationSetSha256`/`dbTestSetSha256`) per this same
  ADR-0027 Part A authority.
  **Cluster 1 (finance, 6/6 tables, 8/8 call sites) is now fully `DONE`.** Still open: clusters
  2-7 (96 more call sites across identity/dispatch/tracking/documents/analytics/misc) — next up
  under the same "lanjut sampe siap launching" mandate.

- 2026-09-10 — Ø1-query-layer cluster 2 (identity/HRIS access) batch 1 closed (this commit),
  continuing the same user-directed ("lanjut sampe siap launching") mandate. Opens cluster 2 and
  closes its first batch **completely** — all 10 of this batch's call sites across 5
  tables/views: `app.tenant_user_identities` (`list_identity_tenant_links`), `app.users`
  (`list_tenant_users`), `app.users_directory` (`list_user_directory_email_projections`,
  `list_portal_users`, `list_user_directory` — 3 separate call sites onto the same view, matching
  the existing TS layer's own 3-caller shape), `app.permissions` (`list_permissions_for_module`),
  and `app.roles` (`list_tenant_roles`). New migration
  `20260910010000_close_o1_query_layer_cluster2_batch1_identity_access.sql` adds 7 new
  `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix pipeline
  clusters 0-1 established (RULE A/B/C baked into both stages), again completed via parallel
  Agent-tool design/verify calls rather than the Workflow tool (whose subagent-spawning path
  remained broken this session).
  **Real, previously-latent security drift found and closed by the independent verify pass,
  before this migration was ever applied to any database**: `app.users_directory`'s own WHERE
  clause had never been patched with the `customer_user`-layer exclusion its sibling table
  `app.users` received in an earlier hardening pass — a `customer_user`-layer principal would
  have been able to see internal staff directory rows (including the email-masking decision)
  through all 3 of this view's new RPCs. Fixed by adding
  `and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id)` to all 3
  functions' WHERE clauses — the CURRENT, most-hardened predicate (RULE B), not the view's own
  stale one, since this read path was never reachable in production (`app` schema not exposed to
  PostgREST) and so has no live behavior to preserve.
  **Two genuinely novel design categories, resolved through evidence-based research and
  independently re-derived at verify, not assumed**: (1) `app.permissions` had NEVER had any
  grant beyond `service_role` (repo-wide grep confirmed zero create-policy/grant-to-authenticated
  ever existed) — exposing it to `authenticated` for the first time is a genuine widening
  decision, not a reproduction of existing RLS. Resolved by requiring an active
  `app.principal_memberships` row for the caller (reusing the exact "does this identity hold any
  real standing" primitive `app.resolve_access_context`'s own unscoped-request branch already
  relies on) — closing the gap where a revoked/never-onboarded identity could otherwise retain a
  live JWT with zero current standing (`app.revoke_auth_identity` only flips
  `tenant_user_identities.status`, it never bans the underlying `auth.users` row). (2)
  `app.list_identity_tenant_links`'s self-lookup-only design (single `p_actor_auth_user_id`
  parameter, no separate subject parameter) was confirmed via (a) zero production callers found
  by repo-wide grep, (b) the function's own doc-comment framing, (c) `app.tenant_user_identities`'
  own current RLS predicate having no `auth_user_id` axis at all (ruling out a built-in
  admin/support envelope), and (d) direct precedent from the `app.get_self_employee`/`app.
  get_my_employee_profile` self-service function family — independently re-verified against
  `app.resolve_access_context`'s own real login-time resolver, which uses the identical bare
  `auth_user_id = p_auth_user_id` row filter shape for this exact table.
  **Full-suite regression caught and fixed by `pnpm run db:test` itself, not by design/verify**:
  `scripts/db-tests/rbac-enforcement.sql`'s ATW-032 SECURITY DEFINER authority-surface sweep
  flagged both `app.list_identity_tenant_links` and `app.list_permissions_for_module` as granted
  to `authenticated` with no authority check its closure query could detect. Both are genuinely
  correct-by-design (re-verified independently, not merely asserted): the former is the identical
  "raw self-row-identity equality shape" `app.get_self_employee`/`app.is_ticket_queue_member`/
  `app.accept_customer_portal_invite` already document and are exempted for; the latter carries a
  real, load-bearing standing gate (the active `app.principal_memberships` check above) that is
  simply inlined as a direct `exists` rather than expressed through one of the sweep's own named
  keyword primitives, so the closure does not credit it automatically. Both added to
  `rbac-enforcement.sql`'s own `v_expected` reviewed-and-justified list with full written reasons,
  matching this file's own established escape-hatch convention — no gate weakened, no check
  removed.
  This batch's own db-test (`scripts/db-tests/o1-query-layer-cluster2-batch1.sql`) passed on the
  third full run — the first two runs surfaced two real fixture-setup gaps (a self-escalation
  rejection from having an identity grant itself a protected-permission role, fixed by using a
  separate granting actor; and a role-count assertion that forgot the masking-setup "PII Viewer"
  role also counts alongside the intentionally-created "Ops Coordinator" role), neither a defect
  in any of the 7 new functions themselves.
  All 5 affected TS query files (`server/queries/auth-identity.ts`, `user-lifecycle.ts`,
  `portal-users.ts`, `field-access.ts`, `role-permission.ts`) switched from `.from()` to `.rpc()`
  in this same commit. Only `portal-users.ts` has a real production call site
  (`app/(tenant)/[tenantSlug]/admin/users/page.tsx`, updated to pass the new `actorAuthUserId`
  argument) — the other 4 functions have zero live callers today (repo-wide grep, confirmed by
  both the design and verify passes), converted for consistency and to keep every file on one
  calling convention.
  Full Tier A gate suite re-run clean: `typecheck`, `lint` (0 errors), the 5,993-test unit suite,
  `check-rls-initplan.ts` (0 findings), a full `pnpm run db:test` (`ALL PASSED`, 521 migrations /
  265 db-test files), `git:check-paths`, `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTY-FOURTH PASS,
  `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027 Part A authority.
  **Cluster 2 batch 1 (identity/HRIS access, 5 tables, 10 call sites) is now fully `DONE`.** Still
  open: clusters 2 remainder-7 (86 more call sites across dispatch/tracking/documents/
  analytics/misc) — next up under the same "lanjut sampe siap launching" mandate.
