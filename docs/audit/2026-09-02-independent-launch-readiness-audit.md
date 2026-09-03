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

**On the evidence available, no tenant page has ever loaded for a real signed-in user against the live
hosted project.**

Every server-side data read in this codebase — 163 call sites — is a Supabase `.from("table")` call
against tables that exist only in schema `app`. The hosted project exposes only `public` and
`graphql_public` to its Data API, confirmed live against the real deployed project in the repository's
own build log. Every one of those 163 reads, including the tenant-slug lookup every tenant, customer
portal and login guard performs first, has no target and returns nothing. No test in the repository
catches this: the SQL suite talks to Postgres directly and every E2E spec runs against a backend the
tests themselves call "unreachable." This is not a missing feature — it is the mechanism every other
finding in this report assumes still works. See §4 Ø for the full evidence.

Underneath that: the database and service layer are, in places, stronger than most commercial ERPs. The
product layer built on top of it cannot be operated even once the read path is fixed — a tenant cannot
be created, a user cannot be invited, a role cannot be assigned, nothing can be imported, no document
can be printed, no uploaded file is actually stored, no background job ever runs, a customer invoice
cannot be issued, and even a genuine customer account is independently locked out by its own RLS
policy. Each of these is independently sufficient to block a first customer from going live.

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

### Ø — The defect every other finding sits on top of

Verified independently of the sweep that first surfaced it: read the client factories, queried the live
schema directly, and cross-checked against the repository's own prior incident record for the RPC half
of this exact bug class.

**Ø1 · Every table read targets a schema the Data API does not expose.** Four tenant-resolution guards —
the admin portal, the customer portal, the customer ticket portal, and login/session registration itself
— call `supabase.from("tenants").select(...)` on the RLS-scoped client with no schema override anywhere
in the client factory. Live: schema `public` holds exactly two base tables and zero views, neither named
`tenants`; every one of the 106 distinct table names referenced across 163 `.from()` call sites in this
codebase exists only in schema `app`. `supabase/config.toml` exposes only `public, graphql_public` — and
the repository's own remediation record for the closely related RPC version of this bug
(`docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md`) confirms this is not a
local-template artefact: it was reproduced with `curl` against the real hosted project
(`awdlicmwzdxquopwtcfd`) and its exact `db_schema` setting. That remediation built a `public.*` wrapper
function for every externally-called RPC — it did not, and structurally cannot without becoming a second
full schema, cover a direct `.from()` table read. Those 163 call sites, this codebase's entire read
path, were never touched by it.

```
public schema:  2 base tables (raw_mutation_tripwire_log, security_state_snapshots), 0 views — no "tenants"
supabase/config.toml:13   schemas = ["public", "graphql_public"]

RGL-BLK-002-OPTION2-REMEDIATION.md — live against the real hosted project (awdlicmwzdxquopwtcfd):
  POST /rest/v1/rpc/ping                (no override)   -> 404 PGRST202
  POST /rest/v1/rpc/ping  Accept-Profile: app            -> 406 PGRST106 "Invalid schema: app"
  "app was never exposed to PostgREST ... every single server-side RPC call this application makes
   has been unreachable via the Data API since the first client factory was written, entirely
   invisible to this build's own test suite" -- confirmed true of every .rpc() call; the wrapper
   fix that followed covers RPCs only

lib/portal/tenant-admin-guard-deps.server.ts:26      supabase.from("tenants").select(...)
lib/portal/customer-portal-guard-deps.server.ts:23   supabase.from("tenants").select(...)
lib/portal/customer-ticket-guard-deps.server.ts:23   supabase.from("tenants").select(...)
lib/auth/register-login-session-deps.server.ts:21    supabase.from("tenants").select(...)

grep -rn '\.from("' lib server app components  ->  163 call sites, 70 files, 106 distinct tables, 0 in "public"
```

**Ø2 · Fixing the schema exposure would not fix the customer portal — its own RLS policy locks customers
out by construction.** The sole policy on `app.tenants` is
`(app.has_active_tenant_membership(id) AND (NOT app.actor_holds_customer_user_layer(id)))`.
`actor_holds_customer_user_layer` is true exactly for the population the customer portal serves — a
customer account holder — which makes the policy's own `AND NOT` clause false for every genuine
customer, deterministically, not merely as an observed empirical outcome. This is independent of Ø1:
even a correctly schema-routed client, running as a real customer, is denied by the database itself
before RLS ever reaches a row.

```
tenants_select_own_tenant | SELECT | (app.has_active_tenant_membership(id) AND (NOT app.actor_holds_customer_user_layer(id)))
  -- true for a customer_user membership == the AND NOT clause is false == zero rows, always
supabase/migrations/20260730560000_harden_customer_user_layer_default_deny.sql:325-326
```

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

**A2b · The customer portal has no front door — and, separately, no vendor portal exists at all.**
Thirty customer-portal pages and twelve action modules exist and are queried correctly (see §4 Ø2 for
the RLS lockout underneath them). Nothing routes a customer there: sign-in has exactly two branches,
`` `/{slug}/admin` `` or `/supreme`. `acceptCustomerPortalInvite` and
`grantInitialCustomerPortalAccountAdmin` — the only two functions that could ever activate a customer's
membership, the second explicitly written as the one deliberate bootstrap exception — both have zero
callers anywhere in the product. A tenant can build its entire customer-facing portal and no customer
can ever sign in to see it, then create the first account admin who could invite anyone else.
Subcontracted carriers fare worse: there is no vendor principal layer at all —
`principal_memberships_layer_check` allows only `supreme_admin | tenant_admin | org_user | customer_user`
— so a vendor's only access to the platform is an API key someone hands them out of band; the
repository's own build status discloses the vendor portal as permanently `BLOCKED`.

```
login/actions.ts:66   const target = tenantSlug ? `/${tenantSlug}/admin` : "/supreme";   -- no third branch
acceptCustomerPortalInvite               UI callers: 0
grantInitialCustomerPortalAccountAdmin   UI callers: 0
principal_memberships_layer_check   CHECK (layer = ANY (ARRAY['supreme_admin','tenant_admin','org_user','customer_user']))
CARGOGRID_BUILD_STATUS.md:1008   "CG-S11-PRC-018 (Optional Vendor Portal) remains BLOCKED, disclosed not silently dropped."
```

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

**A6 · Uploading a file stores no file, and the scan gate deadlocks flows that are otherwise fully
wired.** No migration creates a Storage bucket or `storage.objects` policy; no code calls
`.storage.from()`, `.upload()` or `createSignedUrl()`. `server/mutations/document.ts:141`:
*"content bytes are never stored here"*. Every upload is inserted with `malware_scan_status='pending'`,
and `recordFileScanResult` — the only function that ever advances that status — has zero production
callers, so no file ever leaves `pending`. This is not latent: **57 functions** gate on that column, and
at least three fully-wired flows hard-fail on it every time — vendor compliance document submission,
ticket-reply attachments, and any shipment whose mandatory document checklist pins a required file.

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

**B8 · The finance company_id dimension is caller-supplied and validated nowhere — an ordinary user can
plant a foreign-tenant reference.** At least eight reachable finance RPCs, including
`create_finance_journal_draft`, insert the caller's `p_company_id` straight into a financial record
after checking tenant authority and line-level account scoping but never once checking that the company
itself belongs to the caller's tenant or is even a company-type org unit. Every `company_id` foreign key
in the finance schema is a plain single-column reference to `app.org_units(id)`; there is no composite
`(tenant_id, org_unit)` key anywhere, and no trigger fills the gap. Number counters compound it: they
run one sequence per company per year while invoice numbers are unique only per tenant, so a second
company's first invoice of a year collides with the first company's. Both are reachable by an ordinary
`FIN:Edit` user in their own tenant, not an admin, independent of any UI gap.

```
create_finance_journal_draft — tenant_id and FIN:Edit checked; each line's account tenant-filtered;
  insert into app.finance_journals (tenant_id, company_id, ...) values (p_tenant_id, p_company_id, ...)
  -- p_company_id: zero lookup, no trigger on finance_journals validates it
18 FKs of the form  FOREIGN KEY (company_id) REFERENCES app.org_units(id)   -- no tenant predicate
org_units: 0 (tenant_id, id) unique index · org_units_unit_type_check allows company|branch|department|business_unit|team
finance_invoice_number_counters_scope_unique  (tenant_id, COALESCE(company_id,'000...0'), year)
finance_invoices_tenant_number_unique         (tenant_id, invoice_number)
```

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

**D3b · Suspending a user does not cut access — reproduced live.** `app.transition_user_status` revokes
the identity link and principal membership only on `'revoked'`; the `'suspended'` branch strips role
assignments and nothing else. Neither `app.resolve_access_context` — the gate every tenant page calls —
nor `app.has_active_tenant_membership` — the RLS predicate — reads `app.users.status` at all. I
suspended a test user through the governed RPC (in a rolled-back transaction) and re-asked every gate:
`resolve_access_context` still returned `tenant_admin`, `has_active_tenant_membership` still returned
`true`, and a read of `app.accounts` under the victim's own JWT still returned the row. Off-boarding a
compromised or departed employee by suspending them — the softer, more common action — leaves every
credential and every RLS-gated table open.

```
app.transition_user_status
  if p_new_status = 'revoked' then perform app.revoke_auth_identity(...); ... end if;  -- 'suspended' skips this
app.resolve_access_context      -- grep for "app.users" -> 0 matches
app.has_active_tenant_membership
  select exists (select 1 from app.tenant_user_identities where ... status = 'active')
    or is_supreme_admin(...) or has_active_support_grant(...)
  -- no app.users.status check anywhere in the chain

live probe after suspend:  resolve_access_context          -> tenant_admin (unchanged)
                            has_active_tenant_membership    -> true
                            select legal_name from app.accounts (as victim JWT) -> row returned
```

**D3c · The session cookie ships readable by JavaScript and lasts 400 days — the exact inverse of the
repo's own tested contract.** The repo's own cookie-attribute module states the requirement plainly:
*"httpOnly: always true — a session cookie must never be readable from client-side JavaScript."* The
installed `@supabase/ssr` library's own default options set `httpOnly:false` and a 400-day `maxAge`,
force-resetting `maxAge` even when a caller supplies one. The client factory's cookie-write callback
spreads the library's options object *last* — `{...sessionCookieOptions, ...options}` — so the
library's insecure defaults win over the app's own correct ones on every cookie this app sets. No test
catches it: the existing unit test asserts only the pure options-builder function's return value, never
the actual composition that runs in `server.ts`. No known live XSS vector exists in the codebase today
— a mitigating fact, not an exculpatory one, since any future injection point would immediately
weaponize a JS-readable, 400-day session credential.

```
session-cookie-options.ts   "httpOnly: always true -- a session cookie must never be readable
                              from client-side JavaScript (XSS exfiltration resistance)."
@supabase/ssr@0.12.3 constants.js
  DEFAULT_COOKIE_OPTIONS = { path:'/', sameSite:'lax', httpOnly:false, maxAge: 400*24*60*60 }
  applyServerStorage: { ...DEFAULT_COOKIE_OPTIONS, ...cookieOptions, maxAge: DEFAULT_COOKIE_OPTIONS.maxAge }
lib/supabase/server.ts:45   setAll: (name, value, options) =>
                               cookieStore.set(name, value, { ...sessionCookieOptions, ...options })
                               -- "options" (the library's) spread LAST, wins on httpOnly and maxAge
session-cookie-options.test.ts   asserts only buildSessionCookieOptions()'s return value, never server.ts's composition
```

**D3d · An enqueued background job can leak another tenant's credentials and data — reproduced live end
to end.** `public.enqueue_job` is a thin `SECURITY DEFINER` pass-through to `app.enqueue_job`, both
callable by any `authenticated` session; the only gates are that the actor equals the session identity
and holds membership in whatever tenant the caller names — nothing validates any id the caller embeds
inside the JSON payload. A fresh fixture built in a rolled-back transaction, called as a genuine
authenticated session with an arbitrary foreign `connection_id` in the payload, returned a real
`status='pending'` job naming that foreign id, no error. Four of the five workers that later process
such a job — external sync, notification delivery, logistics-partner sync, finance bank-feed sync —
resolve the connection or notification from the payload and then read or dispatch under *its* tenant,
never comparing that tenant back to the job's own; only the webhook worker checks. The precondition
this needs (job reachability) is proven live, not assumed.

```
public.enqueue_job / app.enqueue_job — SECURITY DEFINER, EXECUTE granted to authenticated
  gates: assert_actor_is_session_identity(actor) + has_active_tenant_membership(caller's own p_tenant_id)
  -- zero validation of any id inside p_payload
live exploit, rolled back: enqueue_job('<own tenant>','external_sync','{"connection_id":"<foreign uuid>",...}',...)
  -> real job row returned, status='pending', naming the foreign connection_id, no error
4 of 5 workers: resolve connection/notification from payload, dispatch/record under ITS tenant,
  never compare to job.tenantId -- only lib/webhooks/process-webhook-delivery-job.server.ts:103-108 checks
```

**D4 · Support access and integration credentials have no working path.** No UI calls any support-access
grant/approve/revoke. `select app.integration_secrets_encryption_key();` raises
`encryption_key_not_configured`, and the GUC is set nowhere outside db-test fixtures.

### E — The operating model does not match the industry

**E1 · Every job order must be born from a quotation.** `app.job_orders.quotation_id` and
`source_handoff_id` are both `NOT NULL` with FKs. There is no contract-based, repeat or standing order.
`getEffectiveCustomerPrice` — the contracted-tariff lookup — has no caller, so customer contracts never
price anything.

**E2 · One vehicle, one shipment.** `app.assign_resource` rejects a second active assignment for the
same resource — but the check is an unlocked `EXISTS` read-then-write with no row lock and no exclusion
constraint behind it, an independently confirmed race: two concurrent assignment requests can both pass
before either commits, so the rule holds in the common case and is racily bypassable under load. No trip
or consolidation entity exists regardless, so multi-drop, groupage/LTL and backhaul cannot be
represented. `app.milestone_codes` — a global registry — ships with **0 rows** and no seed (independently
confirmed as a shipped, dead-end dropdown on a live screen), so no shipment event can be recorded on a
fresh install.

**E3 · Stock has no unit of measure; places are free text.** `app.inventory_balances` has no `uom`
column, and no dimension key, trigger or constraint anywhere ties a movement's UoM to the item's base
unit — independently confirmed and reproduced against the live function body: a receipt line posted in
dozens and an issue line posted in pieces hit the same balance row and net arithmetically, with no
exception raised. There is no location, port or address master; origins, destinations and stops are
strings. Warehouse revenue has nowhere to go either: `app.warehouse_billing_handoffs` carries **no
foreign key to an invoice**, so "handoff" is a terminal status flag and storage, handling and
value-added charges can never be billed.

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

A 27-lens agent sweep ran alongside this audit. **Nineteen of twenty-seven lenses completed full
adversarial verification** — an independent skeptic re-ran every cited query and reopened every cited
file, empowered to refute — producing **over 300 confirmed findings** across three review rounds; the
remaining lenses (chiefly performance/scale) raised findings whose verification stage did not complete
before this report's publication and were treated as unverified leads rather than fact. Every CRITICAL
claim from every lens, verified or not, was independently re-checked by hand — mine included — before
appearing here. Several were wrong: that 1,128 internet-reachable RPCs permit impersonation through a
caller-supplied actor id (the guard sits one call level below where the scan looked, and a transitive
call-graph analysis over all 2,860 `app` functions shows it covers 1,872 of 1,873 exposed functions),
that `anon` retains Supabase's default grants, that a customer API key's account binding is unenforced,
and that the tax console's rate error runs the other way. The most consequential finding in this
report — §4 Ø, the schema-exposure defect underneath everything else — was additionally re-derived from
scratch: every client factory read directly, the live schema queried independently, and the result
cross-checked against the repository's own prior incident record for the closely related RPC half of
the same bug class before it was accepted. **Nothing in this report rests on an unverified claim.**

The traffic went both ways. One completed verification pass caught an error in an earlier draft of this
document: it had reported that no vehicle or driver could be registered, on the evidence that
`createMasterRecord` has no caller. It does not, but `register_vehicle_operational_profile` calls it
internally and is wired to a real form — §4 A2 carries the corrected, narrower claim. The completed
passes also surfaced findings serious enough to independently re-verify and add here: that suspending a
user leaves every credential and every RLS-gated table open (§4 D3b, reproduced live in a rolled-back
transaction), that the customer portal has no route a customer can sign in through (§4 A2b), and that
the one-resource-one-shipment rule (§4 E2) is enforced by an unlocked check rather than a constraint.
