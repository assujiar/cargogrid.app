# Independent launch-readiness audit — CargoGrid

**Reference:** `CG-AUDIT-2026-09-02`
**Commit audited:** `8eb1498afdae32f55faf88b833ffef9408924d80` (identical to `origin/main` at the time of audit)
**Release candidate on record:** `RC-2026.08.25-1`; `GO_DECISION.json` authorizes `a9459f3`
**Scope:** the whole product — functions, UI, API, flows, canonical data, atomicity, data dependencies,
RLS, RBAC, configuration completeness, flexibility — against its stated market of 3PL, cargo/freight
forwarding, trucking, and manufacturers running in-house logistics.

**Status of this document.** It is an *independent* audit produced outside the Step 16/17 release
lineage. It deliberately does **not** edit `docs/runtime/` ledgers, the prompt package, or any
build-log record, and it claims no authority over the release state those artifacts govern. It is
evidence, offered to whoever next rules on that state.

**Method.** Every claim below was reproduced against a live PostgreSQL 16 + PostGIS database with all
498 migrations applied from zero, against a production build of the application booted and probed, or
against the code at the cited line. Repository documentation was treated as a hypothesis to test, never
as evidence; where a document and the code disagreed, the code decided.

---

## 1. Verdict

**Not ready for a paying customer.**

The database and service layer are, in places, stronger than most commercial ERPs. The product layer
above them cannot yet be operated: a tenant cannot be created, a user cannot be invited, a role cannot
be assigned, nothing can be imported, no document can be printed, no uploaded file is actually stored,
no background job ever runs, a customer invoice cannot be issued at all, and there is no navigation to
reach most of what does work. Each of those independently prevents a first customer from going live.

---

## 2. Gates, run live on this tree

| Gate | Result | Detail |
|---|---|---|
| `pnpm run typecheck` | **PASS** | exit 0 |
| `pnpm run lint` | **FAIL** | exit 1 — 1 error, 407 warnings. `scripts/jobs/supervisor.ts:50` trips the repo's own service-role import guard. The frozen record claims "0 errors / 337 warnings". |
| `pnpm run test` | **PASS** | 5,939 / 5,939 across 2,524 suites (record says 5,452) |
| `pnpm exec next build` | **PASS** | compiled in 41 s |
| `bash scripts/db-tests/run.sh` | **PASS** | "ALL PASSED" — 498 migrations from zero, 250 SQL test files |
| `pnpm exec playwright test --project=chromium` | **PASS** | 170 / 170 in 3.0 m (after aliasing the sandbox's Chromium revision — an environment issue, not a product defect) |
| 13 governance gates | **PASS** | paths, standards, docs, package, issues, secrets, ui, data-classification, threat-model, freeze, env-facts, dependency audit, migration collision |
| `pnpm run preflight` | fails | `CARGOGRID_ENV` unset in the audit sandbox; not a product defect |

Three gate-level observations:

- **Those green gates do not cover the code that talks to the hardware.** The always-on GPS listener at
  `services/gps-gateway` is a separate package with its own `typecheck` and `test` scripts. The root
  `tsconfig.json` sets `"exclude": [… "services/**"]`; the root test glob covers only `scripts`,
  `server`, `lib` and `tests`; and CI never invokes the package's own scripts. The one component that
  speaks to real trucks has never been checked by any gate anyone runs.

- **The E2E suite is green and tests no business flow.** Its 66 specs assert static render,
  accessibility of public pages, and that guards redirect when the backend is unreachable.
  `e2e/smoke.spec.ts` says so itself ("not a test of any real CargoGrid page or component"), as does
  `e2e/tenant-admin-portal.spec.ts` ("It does not exercise a real sign-in or a real `allowed` guard
  result").
- **No commit can reach production through Git.** `vercel.json` sets
  `git.deploymentEnabled.main = false`, and `scripts/release/check-go-decision.ts` requires the commit
  being built to equal `GO_DECISION.json.authorizedCommitSha`. At `HEAD` (`8eb1498`) the file
  authorizes `a9459f3`; at `a9459f3` it authorizes `d48b589`. Both are refused. The commit carrying a
  go decision can never be the commit it authorizes. The only remaining path, a manual `vercel --prod`,
  bypasses `ignoreCommand` entirely — so the control does not cover the path that is actually usable.

---

## 3. How much of the build is reachable

Measured by a full identifier-reachability scan over every non-test `.ts`/`.tsx` file:

- exported mutations: **1,285** — **408 (31.8 %) have no caller anywhere** but their own unit test
- exported queries: **927** — **322 (34.7 %) have no caller anywhere**
- 192 mutation modules: **41 are 100 % dead**, 64 partially dead, 87 fully wired

| Module | mutations | wired | % |
|---|---:|---:|---:|
| Warehouse (WMS) | 122 | 3 | **2 %** |
| Enterprise controls (IAM/SSO, MFA, IP, monitoring, DR) | 45 | 1 | **2 %** |
| Platform & admin (tenant, identity, users, roles, master data, engines, import, jobs) | 124 | 26 | **21 %** |
| Telematics / GPS | 23 | 12 | 52 % |
| Intelligence & API | 80 | 52 | 65 % |
| Operations / TMS | 101 | 73 | 72 % |
| Commercial / CRM | 67 | 53 | 79 % |
| Customer portal | 24 | 19 | 79 % |
| HRIS & payroll | 250 | 219 | 88 % |
| Finance (GL/AR/AP) | 81 | 73 | 90 % |
| Ticketing / helpdesk | 73 | 67 | 92 % |
| Procurement / vendor | 194 | 190 | 98 % |

The pattern is chronological. The modules built *first* — Platform Core, then WMS — are the ones whose
UI was deferred "to a later, separately-scoped slice", and that slice was never executed.

---

## 4. Findings

### A — The product cannot be operated

**A1 · There is no navigation.** `app/(public)/login/actions.ts:66` sends every tenant user to
`/{slug}/admin`, whose nav offers 14 links — five admin pages and nine loyalty pages. Eighteen of the
twenty module layouts (Operations, Finance, HRIS, Procurement, Tickets, …) are ten-line pass-throughs
with no links; `/{tenantSlug}` itself 404s. An independent href-graph scan finds **81 of 238 routes
with no inbound link anywhere in the source**, including the entry page of nearly every module. The 407
lint warnings are all raw `<a>` tags, so the navigation that exists reloads the page on every click.

**A2 · A tenant cannot be created, and its people cannot be given access.** `provisionTenant` has no
caller; the Supreme tenants page is read-only. `app.roles` seeds 0 rows against 105 seeded permission
codes, and `createRole` / `assignRole` / `revokeRoleAssignment` have no caller. No code path anywhere
calls `admin.createUser`, `inviteUserByEmail`, `generateLink` or `signUp()`, so a login cannot be
created in-product at all. `app/(tenant)/[tenantSlug]/admin/users/page.tsx` states the gap in its own
header.

Master data is a partial exception, stated precisely: vehicles and drivers **can** be registered from
`operations/fleet`, because `app.register_vehicle_operational_profile` and
`app.register_driver_operational_profile` call `app.create_master_record` internally and are wired to a
real form. That page is nonetheless one of the 81 with no inbound link; the generic
`createMasterRecord` wrapper has no caller and its RPC is granted to `postgres`/`service_role` only;
and `mergeMasterRecords` — the only deduplication path in the system — has no caller at all.

**A3 · Publishing a role version silently revokes it from everyone holding it.**
`app.role_assignments.role_version_id` binds an assignment to one version; `app.evaluate_permission`
joins `role_versions … and rv.status = 'published'`; `app.publish_role_version` never touches
`role_assignments`. The evaluator's own comment concedes it.

**A3b · No approval routing can be published, so approval-gated flows fail on a new tenant.** Eight
functions raise when the approval definition they require is absent — `_request_procurement_entity_
approval`, `request_approval`, `request_customer_credit_profile`, `submit_job_offer_for_approval`,
`submit_leave_request`, `submit_onboarding_case_for_finalize_approval`,
`submit_payroll_run_for_finalization`, `submit_quotation`. `publishApprovalDefinition` has **no caller
anywhere**, so no definition can be created in the product. The approval engine is real, tested and
unreachable.

**A4 · Nothing can be imported.** Twelve import schemas exist and work in the database, including
opening balances for finance, inventory and leave. `createImportExportJob`, `stageImportRows`,
`validateStagingRow` and `commitImportJob` all have zero UI callers, and no page matches "import".

**A5 · Nothing runs background jobs or schedules in production.** `scripts/jobs/supervisor.ts` is
correct and installs nothing ("Pointing a process manager … stays an operator decision"). There are no
Vercel crons, no Edge Functions, no scheduled workflow, and `pg_cron` is never created in any
migration — on a serverless deploy target with no long-lived host.
`20260831090000_create_tenant_configurable_task_scheduler.sql:534` says "Nothing calls this
automatically yet."

**A6 · Uploading a file stores no file.** No migration creates a Storage bucket or `storage.objects`
policy; no code calls `.storage.from()`, `.upload()` or `createSignedUrl()`.
`server/mutations/document.ts:141`: *"content bytes are never stored here"*. `recordFileScanResult` and
`authorizeFileAccess` have zero callers, so nothing is ever marked clean and nothing can be served
back — while seven UI panels render a file input.

**A7 · No printable document of any kind exists.** `package.json` carries no PDF/print/document
library. No invoice, faktur pajak, delivery order, surat jalan, packing list, POD or purchase order can
be produced.

### B — Money

**B1 · A customer invoice cannot be issued; a fiscal period cannot be locked.** Reproduced live:

```
begin; set local role authenticated;
select app.issue_finance_invoice(…);
ERROR:  permission denied for table finance_invoices
CONTEXT: SQL statement "select * from app.finance_invoices where id = p_invoice_id for update"
         PL/pgSQL function app.issue_finance_invoice(uuid,integer,date,uuid,text,text) line 14
```

`issue_finance_invoice` and `lock_finance_period` are the only two *writers* left `SECURITY INVOKER`
among the 99 invoker functions granted to `authenticated`, in a database where `authenticated` holds no
table privileges by design. Both UI actions use `createSupabaseServerClient`, not the service-role
client.

**B2 · The general ledger is write-only.** Eight functions reference `finance_journal_lines`; none
aggregates them. No trial balance, account balance, P&L, balance sheet, GL report or year-end close.

**B3 · An issued invoice can never be corrected, and there can only be one per job.** Zero credit-note
tables and functions; `void` is reachable only from `draft`/`submitted`. `finance_invoices_job_order_
issued_unique (tenant_id, job_order_id) WHERE status='issued'` caps a job at one issued invoice, so no
partial, milestone, supplementary or itemised billing is possible.

**B4 · Multi-currency postings are summed as raw numbers.** `finance_journals` has `currency` and
`total_amount`; `finance_journal_lines` has only `amount`. No base/functional amount and no FX rate on
GL, AR, AP or settlement rows. Cross-currency receipt allocation is hard-rejected.

**B5 · Withholding tax is added to a customer invoice instead of deducted.** `PPH21`, `PPH23`,
`PPH4_2` are seeded with `tax_type='withholding'`; `app.calculate_finance_tax` returns
`base × rate` positive with no branch on tax type; `prepare_finance_invoice_from_readiness` writes it
as a positive `'tax'` line. The tax code field is free text
(`finance/invoices/invoice-forms.tsx:39`).

**B6 · Cost and cash never reach the ledger on their own.** None of the 13 `actual_cost` functions
posts to the GL. `allocate_finance_receipt` posts a subledger batch, but `apply_`/`reverse_finance_ar_
allocation` and `apply_`/`reverse_finance_ap_settlement` do not. `app.purchase_order_lines` has no unit
price, amount or currency at all.

**B7 · Invoicing is driven by a hand-copied UUID.** `finance/invoices/invoice-forms.tsx:26` requires a
`BillingReadinessHandoff ID` typed into a plain text input; Finance has no billable-jobs worklist.
`app.check_customer_credit` never reads AR open items, so credit control cannot compute exposure, and
no order-acceptance path calls it.

**B8 · Numbering collides in a multi-company tenant; the company key is unvalidated.** Counters are
unique on `(tenant_id, COALESCE(company_id,…), year)` while invoice numbers are unique on
`(tenant_id, invoice_number)`. `finance_journals_company_id_fkey` is a plain single-column FK to
`app.org_units(id)`; there is not one composite `(tenant_id, org_unit)` FK in the finance schema.

### C — Indonesia

**C1 · The selling company has no NPWP, and no faktur pajak exists.** `tax_id` is modelled on
`accounts`, `prospects` and `vendor_tax_identities`; `app.tenants` and `app.org_units` carry none.
Nothing anywhere matches `faktur` — no NSFP numbering, no faktur number on an invoice, no e-Faktur or
Coretax payload.

**C2 · PPh 21 cannot be computed.** `payroll_component_versions_method_check` allows only
`fixed_amount`, `hourly_rate`, `percentage_of_component`, `manual_per_run`. Columns matching
`ptkp|tax_status|bracket|npwp` in schema `app`: **0**.

**C3 · The tax console shows an 11 % rate as "0.11 %".** `CHECK (rate_basis <> 'percentage' OR
rate_value <= 1)` fixes the stored value as a fraction and the calculator is correct;
`admin/tax-settings/tax-settings-admin-panel.tsx:28` appends `%` to the fraction. The entry form offers
a bare "Rate value" number field with no unit hint. Separately and correctly, the seeded PPN rule is
`rate_value = 0`, labelled "EXAMPLE FIXTURE ONLY — NOT A VERIFIED RATE", and cannot be approved — so
VAT is uncomputable until a tax adviser configures it.

### D — Security and identity

**D1 · MFA is switched off, and step-up verification proves nothing.** `supabase/config.toml:307-315`
disables TOTP and phone factors. `app.verify_mfa_step_up_challenge(p_challenge_id, p_actor_auth_user_id,
p_actor_label)` accepts no OTP, factor id or assertion — the constrained principal satisfies it itself.

**D2 · A cross-tenant guard is swallowed by its own exception handler.** In
`app.run_next_route_planning_job`, `perform app.assert_session_identity_in_tenant(…)` sits inside a
`begin … exception when others then …` block whose handler marks the scenario `failed` and records a
job failure. Its own comment claims the transaction rolls back; the handler catches it instead. Any
authenticated user in any tenant can claim and fail another tenant's planning jobs.

**D3 · The IP allowlist is spoofable and mostly not fed.** `lib/security/client-ip.ts` correctly takes
the *last* `x-forwarded-for` hop; `app/(tenant)/[tenantSlug]/integrations/actions.ts:76` bypasses it and
takes `split(",")[0]`. Only **2** call sites in all of `app/` pass a client IP at all.

**D4 · Support access and integration credentials have no working path.** No UI calls any support-access
grant/approve/revoke. `select app.integration_secrets_encryption_key();` raises
`encryption_key_not_configured`, and the GUC is set nowhere outside db-test fixtures.

### E — The operating model does not match the industry

**E1 · Every job order must be born from a quotation.** `app.job_orders.quotation_id` and
`source_handoff_id` are both `NOT NULL` with FKs. There is no contract-based, repeat or standing order.
`getEffectiveCustomerPrice` — the contracted-tariff lookup — has no caller, so customer contracts never
price anything.

**E2 · One vehicle, one shipment.** `app.assign_resource` rejects a second active assignment for the
same resource; no trip or consolidation entity exists, so multi-drop, groupage/LTL and backhaul cannot
be represented. `app.milestone_codes` — a global registry — ships with **0 rows** and no seed, so no
shipment event can be recorded on a fresh install.

**E3 · Stock has no unit of measure; places are free text.** `app.inventory_balances` has no `uom`
column. There is no location, port or address master; origins, destinations and stops are strings.
Warehouse revenue has nowhere to go either: `app.warehouse_billing_handoffs` carries **no foreign key
to an invoice**, so "handoff" is a terminal status flag and storage, handling and value-added charges
can never be billed.

**E4 · Whole cost and document domains do not exist.** Zero tables for: fixed assets and depreciation,
vehicle maintenance, fuel, tyres, budget and cost centre, container and depot, demurrage and detention,
manifest, bill of lading, air waybill, customs declaration, insurance policy, surcharge and accessorial,
BOM, production order, material requisition. No chargeable or volumetric weight anywhere.

**E5 · The telematics story does not survive contact with a truck.** An independently verified lens
established that a GPS device can never reach `installed` — the sole route demands a scan-clean
evidence file of a document type the product cannot produce (see A6) — and `active` is reachable only
from `installed`, so both hardware channels are closed. Route planning and ETA are straight-line
distance divided by a hard-coded 40 km/h, with stops never re-sequenced. Driver licence expiry and
vehicle serviceability are checked at neither assignment nor dispatch. No fleet or telematics work is
registered as a job type at all, so overdue-arrival detection is not merely unscheduled but
unenqueueable. "Multi-provider" third-party GPS accepts exactly one proprietary payload shape and
CargoGrid's own HMAC scheme.

**E6 · Outbound webhooks have no publisher.** `app.queue_webhook_delivery` is referenced by 0 other
database functions and nothing outside its own module. No GraphQL surface and no OpenAPI document
exist, against a ratified baseline requiring both.

### F — Interface quality

**F1 · The error state does not exist as a boundary.** `loading.tsx` 195; `error.tsx` **0**;
`not-found.tsx` **0**; `global-error.tsx` **0**. Two uncaught throws reproduced against a booted build:
`/api/v1/status` → 500 when its own request logging fails; `/tracking/{token}` → 500 on an unresolvable
token.

**F2 · Accessibility and form-state requirements are largely unmet.**
`components/forms/multi-select.tsx:106` — each option is an `<li role="option">` whose only handler is
`onMouseDown`; no key handler, no `tabIndex`, no `aria-activedescendant` (WCAG 2.1.1 Level A). The
mandated unsaved-changes guard is used by 6 of 254 form-bearing files.

**F3 · Finance lists stop at row 200; 99 tenant tables lack a leading index.** Thirteen finance list
RPCs carry a literal `limit 200` with no cursor, offset or date filter. Of 550 tenant-scoped tables, 99
have no index leading on `tenant_id`, including `vehicle_current_positions`, `ticket_events`, the
route-deviation and geofence state tables, and the WMS order-line tables.

---

## 5. What is genuinely sound

- **The schema holds.** 498 migrations apply cleanly from zero; the 250-file SQL suite passes end to
  end, including cross-tenant negative tests. 1,828 foreign keys, 2,243 indexes, no floating-point money
  column anywhere, `record_version` optimistic concurrency throughout.
- **Authorization lives in the database, deliberately.** 457 policies in schema `app`, **456 of them
  `SELECT`** — `authenticated` has no direct write path to any table; every write goes through a
  `SECURITY DEFINER` RPC that asserts authority itself. Coherent architecture, not an accident.
- **The impersonation class is closed.** Of 1,873 `SECURITY DEFINER` functions exposed to
  `authenticated` that take `p_actor_auth_user_id`, a transitive call-graph analysis over all 2,860
  `app` functions shows **1,872 reach `app.assert_actor_is_session_identity`**, which rejects any
  mismatch with `auth.uid()`. The single exception is a read-only status getter.
- **Every definer function pins its `search_path`** — 2,148 of 2,148. `anon` holds EXECUTE on 10
  functions and **0** table write grants.
- **The posting gate is properly built.** `app.post_finance_journal` checks `FIN:Approve`, denies
  self-approval, enforces the expected record version, requires approved status, validates line balance,
  resolves the fiscal period and asserts it open, allocates a gap-free number, and is unique on an
  idempotency key — behind posted-row protection and raw-mutation tripwire triggers.
- **Guards are on every page, not in a layout.** All 214 tenant pages resolve access server-side inline;
  the tenant layout does no authorization and says so.
- **The public API is small but properly built.** API-key scope, a required idempotency key on
  mutations, per-key rate limiting, correlation ids, a consistent error envelope, versioned response
  headers, and an SSRF guard reused across webhook and notification dispatch.
- **Customer scoping is enforced where it counts.** The gateway does not carry a customer account
  binding, but `app.create_customer_booking_request_draft` resolves the caller's account scope and
  refuses any account outside it. No cross-customer write is possible.
- **The tax engine refuses to lie** — see C3.

---

## 6. Remediation, in dependency order

| # | Step | Effort |
|---|---|---|
| 1 | Change `issue_finance_invoice` and `lock_finance_period` to `SECURITY DEFINER` | hours, one migration |
| 2 | Point a scheduler (cron or `pg_cron`) at `scripts/jobs/supervisor.ts` | days, configuration only |
| 3 | Tenant shell + cross-module navigation + landing page; tenant provisioning, user invitation, role creation/assignment, master-data entry | weeks, UI over existing capability |
| 4 | Create Storage buckets/policies, wire upload + signed download + scanning to `app.files`; then the printable document set, surat jalan first | weeks |
| 5 | Close the ledger: trial balance and account balances, credit notes, functional currency and FX, the withholding sign, AR/AP posting to GL, actual-cost posting, a price on PO lines, per-tenant number uniqueness | weeks to months |
| 6 | Security: enable and enforce MFA with a real factor check; migrate role assignments on publish; feed and trust the client IP; move the route-planning guard out of its exception handler; provision the integration encryption key; give support access a console | days to weeks, mostly independent |
| 7 | Decide what CargoGrid *is*, then build or descope — WMS, forwarding documents, trucking cost domains, fixed assets and budgeting are each a quarter or more | months; a product decision first |
| 8 | Workflow assumptions: contract/repeat orders without a quotation each time; a trip or consolidation entity; seeded milestone codes; a UoM on inventory balances; a location/port master; chargeable and volumetric weight | weeks to months |

---

## 7. What this audit does not cover

The live hosted project's behaviour; load and capacity at real volume; a browser-driven pass over the
interface; Safari and Firefox; and a review of the roughly 40,000 lines of SQL no lens reached. Absence
of a finding in those areas is not evidence of correctness.

A 27-lens agent sweep ran alongside this audit; 20 lenses produced findings and, for all but one, the
adversarial verification stage did not complete. Their output was treated as unverified leads and every
CRITICAL claim was re-checked by hand. Several were refuted — most importantly the claim that 1,128
internet-reachable RPCs permit impersonation through a caller-supplied actor id, which is wrong (the
guard sits one call level below where the scan looked, and a transitive call-graph analysis over all
2,860 `app` functions shows it covers 1,872 of 1,873 exposed functions), plus the claims that `anon`
retains Supabase's default grants, that a customer API key's account binding is unenforced, and that
the tax console's rate error runs the other way. **Nothing in this report rests on an unverified agent
finding.**

The traffic went both ways. The one lens whose verification did complete caught an error in an earlier
draft of this document: it had reported that no vehicle or driver could be registered, on the evidence
that `createMasterRecord` has no caller. It does not, but `register_vehicle_operational_profile` calls
it internally and is wired to a real form. §4 A2 carries the corrected, narrower claim.
