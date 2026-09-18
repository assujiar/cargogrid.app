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
| Ø1-query-layer | Convert the remaining ~160 `.from()` reads across ~65 `server/queries/*.ts` / `app/**/*.tsx` files to RPC (existing wrapper where one exists, new `app.*`+`public.*` wrapper where none does) | `CODE-BIG` | **DONE** (all 8 clusters, 0 through 7, FULLY closed — cluster 2/`hris-identity-access` closed in full, not merely a first batch, per the recon's own 10-row cluster manifest; cluster 3/`operations-tms-core`, all 4 batches, 20 tables / 28 call sites, **FULLY DONE**; cluster 4/`telematics-tracking`, both batches, 12 call sites, **FULLY DONE**; cluster 5/`procurement-document`, 5 call sites (4 new function pairs + 1 reused function), **FULLY DONE**; cluster 6/`platform-intelligence-reports`, all 4 batches, 30/30 call sites, **FULLY DONE**; cluster 7/`page-level-direct-reads`, the full cluster in one commit, 10/10 call sites, **FULLY DONE** — see below. The entire Ø1-query-layer defect (every broken `.from()`/direct-table read against an `app.*` table, across `server/queries/*.ts` AND `page.tsx` files) is now closed) | (this commit) |

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
| B2 | GL is write-only — no trial balance/account balance/P&L/balance sheet | `CODE-BIG` | **PARTIAL** | a dedicated research pass (the same "verify before trusting a deferred label" discipline that found B7's own real bounded core) found the original "weeks of report-building effort" estimate accurate for P&L/balance sheet/year-end close, but NOT for a trial balance/account balance -- every hard part (double-entry enforcement guaranteeing debits always equal credits, chart-of-accounts account_type/normal_balance classification, fiscal periods, the `public.*` wrapper convention, even a working precedent for the exact summation math in `app.get_finance_cash_position`) already existed and was already correct; this was assembly, not invention. Closed: `app.get_finance_trial_balance` -- every account for the tenant/company, joined against posted, dated-eligible `finance_journal_lines`, one row per (account, currency actually posted against it) rather than a silently-blended cross-currency sum (a real, disclosed limitation tying to the still-open B4 finding: `finance_journals.currency` is one field per whole journal, and `finance_accounts.currency_restriction` is defined but never enforced at posting time). Still open: P&L, balance sheet, GL report, and year-end close -- these need period-scoped net-income roll-up, account-hierarchy subtotaling, and a real reporting-currency/FX conversion layer that does not exist anywhere in this schema today (ties to B4), genuinely larger work; B2 remains PARTIAL, not DONE |
| B3 | No credit notes; one issued invoice per job order, hard-capped | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | needs a billing-model decision (partial/milestone billing) before schema work |
| B4 | Multi-currency postings summed as raw numbers, no FX/base-amount columns | `CODE-BIG` | **PARTIAL** | AR/AP exposure-summary cross-currency blend bug closed with honest per-currency + base-currency figures; `finance_journal_lines` retroactive FX persistence, `currency_restriction` enforcement at posting time, and true consolidated multi-currency financial statements remain deferred |
| B6 | Cost/cash never auto-post to GL | `CODE` (AR/AP half) / `NEEDS_PRODUCT_DECISION` (internal-cost half) | **PARTIAL** | a dedicated recon pass found this MEDIUM overall, not CODE-BIG: 3 of 4 AR/AP allocation-reversal paths already post to the GL correctly; only reversed AR (`app.request_finance_receipt_deallocation`) was a genuine open gap, now fixed (B6a). Internal-source actual cost (no vendor bill) still has no path to the GL at all -- but the vendor-sourced path's own real precedent (`prepare_finance_vendor_bill_from_actual_cost`) never posts directly either: it stages a Finance-owned vendor-bill DRAFT that goes through Finance's own full review/approve/post lifecycle before it ever reaches the GL, honoring `app.shipment_actual_costs`' own explicit disclosed design boundary ("non-authoritative-for-payment operational figures," its creating migration's own words). A same-shape fix for internal cost needs an equivalent Finance-owned, Finance-reviewed document type to stage into -- none exists today, and inventing one (what document, what lifecycle, does it need its own approval step, which account absorbs it) is a real product decision, not a database migration a session can make unilaterally; a thin function posting internal-cost components straight to the GL would bypass that same governance model and treat internal cost as LESS governed than vendor cost, a new inconsistency worse than the gap it would close. See execution log |
| B7 | Invoicing keyed off a hand-copied UUID; no credit control | `CODE-BIG` | **DONE** | the worklist-UI half: `finance/invoices/page.tsx` now shows every still-billable job (a new `app.list_billable_readiness_handoffs`) with a per-row "Prepare invoice" form -- the free-text BillingReadinessHandoff-ID field is gone. The credit-control half: `app.check_customer_credit` was never a stub -- it already read a real `app.credit_profiles`/`app.credit_profile_overrides` row and persisted every outcome -- but never consulted actual AR exposure (only the static approved limit) and was dead-gated code (reachable only via its own manual "Check eligibility" widget, never from any order-acceptance path). Now fixed: it sums real `app.finance_ar_open_items.open_amount` (status <> paid, same currency) into the comparison, and `app.prepare_job_order_handoff` (the correct singular acceptance-moment gate point) evaluates credit for the converted account and the quotation's own real total, raising `credit_blocked` for an affirmative credit-control decision already in force -- deliberately not for `blocked_no_profile` (credit profiles are opt-in, not mandatory). The decision core was factored into a new internal `app._evaluate_customer_credit` (no authority check of its own) after a full `db:test` run caught a real regression: a first draft called the public, COM:View-gated `check_customer_credit` directly, which broke a db-test fixture whose staff role holds COM:Edit but not COM:View -- fixed by having the internal function carry the logic and only the public wrapper add the authority check |

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
| A1 | No cross-module navigation; 81/238 routes have no inbound link | `CODE-BIG` | **DONE** | (this commit) — new shared `components/domain/tenant-portal-nav.tsx` cross-module switcher wired into all 16 tenant-internal module layouts (14 previously-bare stub layouts upgraded to real access-checked shells, admin/commercial's own existing submenus kept alongside it) plus a new tenant Home landing page (`app/(tenant)/[tenantSlug]/page.tsx`, previously a bare 404) and a login-redirect fix (every tenant member landed on `/{slug}/admin`, a `tenant_admin`-only route that 403s any ordinary `org_user`) |
| A2 | Tenant creation, user invite, role assignment, master-data entry all lack UI | `CODE-BIG` | **DONE** | (this commit) — `app/(supreme)/supreme/tenants/` (create-tenant form calling `provisionTenant`), `app/(tenant)/[tenantSlug]/admin/users/` (invite-user form calling a new `supabase.auth.admin.inviteUserByEmail` wrapper + `inviteUser`, since `inviteUser` alone only links an already-existing Auth identity), `app/(tenant)/[tenantSlug]/admin/roles/` (role create/version/permission/publish/assign/revoke UI, plus 4 new read RPCs — `list_role_versions`/`list_role_version_permissions`/`list_role_assignments_for_role`/`list_active_tenant_users_for_role_assignment` — the write RPCs had no way to see their own results again after a reload), and `app/(tenant)/[tenantSlug]/admin/organization/` (org-unit create/rename/move/activate-deactivate UI) all newly built over already-existing, already-tested backend capability |
| A2b | Customer portal has no sign-in route; no vendor principal layer exists at all | `CODE-BIG` / `PRODUCT` | **PARTIAL** | customer-portal-sign-in half closed -- the two CPL-300 RPCs (staff bootstrap grant, invitee accept) now have real UI callers, plus a new self-scoped RPC letting an invited identity discover its own pending invite. Vendor principal layer stays DEFERRED_LARGE -- a real, deliberately ratified PRODUCT decision (ADR-0022/PRC-267/ADR-0025 Part A), not an oversight |
| A3b | No approval definition can ever be published (no UI); 8 flows hard-fail without one | `CODE-BIG` / `PRODUCT` | **FIXED** | `admin/approvals/` now publishes a tenant-scoped approval definition (`config_type_code='approval'`) via the existing, already-tested `publishApprovalDefinition`. One generic definition satisfies all 8 named dependent flows -- `app._resolve_approval_config_type_code` falls back to the plain `'approval'` type whenever no narrower per-domain override has been published. Zero new backend needed |
| A4 | No import UI over 12 working import schemas | `CODE-BIG` | **DONE** | all twelve schemas (`finance_opening_balance_import`, `employee_import`, `vendor_import`, `vendor_rate_import`, `customer_import`, `item_import`, `attendance_device_import`, `timesheet_import`, `leave_opening_balance_import`, `payroll_loan_cutover_import`, `position_crosswalk_import`, `inventory_opening_balance_import`) now have a real, complete UI end to end (bootstrap, upload+scan, stage+validate, review, commit) at `finance/imports/opening-balances/`, `hris/imports/employees/`, `procurement/imports/vendors/`, `procurement/imports/vendor-rates/`, `commercial/imports/customers/`, `operations/imports/items/`, `hris/imports/attendance-devices/`, `hris/imports/timesheet/`, `hris/imports/leave-opening-balance/`, `hris/imports/payroll-loans/`, `hris/imports/position-crosswalk/`, and `operations/imports/inventory-opening-balance/` |
| A6 | No Storage bucket/policies; uploads never store bytes; malware-scan status never advances, deadlocking 3+ flows | `CODE-BIG` | **DONE** | All 4 real evidence-upload flows in this codebase now have real upload + real bytes stored + a malware scan enqueued: vendor compliance document submission/renewal, shipment document checklist uploads, ticket-reply attachments (previously an outright, reproducible hard failure: `app.reply_to_ticket` raises `evidence_file_not_scanned` for any attachment that never reaches `malware_scan_status='clean'`, and nothing ever wired real bytes/scanning), and ePOD evidence capture (previously read plain TEXT filename fields and called `uploadShipmentDocumentFile` with a HARDCODED mimeType/sizeBytes -- no real File ever reached the action, so no evidence file could ever leave `malware_scan_status='pending'`). All four now share one `lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts` helper. Signed download is now wired for all 4: vendor compliance evidence (`app.access_vendor_compliance_document_evidence_for_download`), shipment document checklist evidence (`app.access_shipment_document_checklist_item_evidence_for_download`, gated on the previously-seeded-but-never-used `OPS:Download` permission action code), ticket-reply attachments (`app.access_ticket_attachment_evidence_for_download`, gated on the existing `app.can_access_ticket` baseline plus the linked reply's own `public`/`internal` visibility), and ePOD signature/photo evidence (`app.access_epod_evidence_for_download`, gated on `OPS:Download` plus the parent shipment order's own `app.can_access_record` scope -- the same bar its document checklist sibling already uses). Closing the ePOD slice also surfaced and fixed a more fundamental gap: the `epod` document type itself was never registered by any real (non-db-test) migration anywhere in this repository, so a genuinely fresh tenant's first ePOD evidence upload would have failed immediately with `document_type_not_configured` in spite of every RPC being fully wired and tested -- fixed by the same global-catalogue-registration migration that adds the signed-download RPC. Out of A6's own scope, tracked separately under D4: every scan still fails closed on D4's own still-open GUC gap until an operator configures both the encryption key and a real VirusTotal API key |
| A7 | No PDF/print library; no printable document of any kind | `CODE-BIG` | **PARTIAL** | the PDF-generation infrastructure (`@react-pdf/renderer`, chosen for Vercel serverless compatibility -- pure JS, no headless-browser dependency) and five printable documents, surat jalan (delivery note), POD (proof of delivery), purchase order, invoice, and packing list, now exist end to end (`server/documents/`, five new Route Handlers, wired into their respective detail/list pages), per the audit's own §6 step 4 ("the printable document set, surat jalan first"). POD now embeds the real signature/photo evidence images (NEW-2, a follow-on unblocked once A6's own signed-download capability closed) rather than the text-only summary it originally shipped with. Invoice required one new RPC (`app.get_finance_invoice`, no single-invoice-by-id read existed before) and prints directly from the invoice list row (no invoice detail page exists in this codebase). Packing list required a from-scratch, standalone internal page (`operations/packing-tasks/[packingTaskId]/`) -- ATW-018's own domain (`server/queries/wms-packing.ts`) was real and fully tested but had zero pages/actions anywhere, confirmed by repo-wide search; no host list page for `wms_outbound_orders`/packing tasks exists anywhere in this codebase (a genuinely separate, larger gap -- an internal outbound-order/pick-pack worklist -- out of this slice's own scope), so the new page is reached directly by a packing task id, mirroring `finance/config/page.tsx`'s/`inventory-opening-balance`'s own standalone-and-unlinked precedent. Still open: faktur pajak, gated on new backend RPC work and the tax-SME judgment calls flagged elsewhere in this backlog (C1/C2) |
| F4 | `has_active_tenant_membership` costs ~138µs/row, unindexable, no caching layer anywhere | `CODE-BIG` (research) | DEFERRED_LARGE | needs a load-bearing-function redesign, not a quick patch |

## E — Domain modeling (all `PRODUCT`-gated per the audit's own framing, "decide what CargoGrid is")

| ID | Item | Class | Status |
|---|---|---|---|
| E1 | Every job order must originate from a quotation; no contract/repeat order path | `PRODUCT` | NEEDS_PRODUCT_DECISION |
| E3 | No UoM on stock; free-text locations; warehouse billing has no invoice FK | `CODE-BIG` / `PRODUCT` | **PARTIAL** | "no UoM on stock" was overstated -- a real cross-UOM balance-corruption bug in `app.post_inventory_movement` is now closed (piece 1). "Free-text locations" confirmed FALSE for warehouse locations (already structured/FK-enforced); the real free-text gap is `app.shipment_orders.origin`/`.destination`, a separate TMS-side finding out of this scope. Still open (piece 2, re-dispositioned `DEFERRED_LARGE` after a closer schema check): `app.warehouse_billing_handoffs` has no `invoice_id`/FK to `app.finance_invoices` -- closing it for real needs widening `finance_invoices`' own mandatory `job_order_id`/`billing_readiness_handoff_id` structural invariants (or a second, parallel invoicing primitive), a real product/schema decision, not a quick FK addition |
| E4 | Whole cost/document domains absent (fixed assets, maintenance, customs, BOM, …) | `PRODUCT` | NEEDS_PRODUCT_DECISION |
| E5 | Telematics: device can never reach `installed` (blocked by A6); ETA is straight-line/40kmh | `CODE` (installation-evidence upload wiring) + `CODE-BIG` (ETA) | **PARTIAL** | Split: the "device can never reach `installed`" half is now fixed -- `app.record_gps_device_installation` (ATW-226B) and its own db-test already fully built and exercised the evidenced-installation RPC; the real blocker was that no real migration ever registered the `gps_device_installation` document type (only six different db-test fixtures' own throwaway registrations did), so every real tenant's first upload would have failed `document_type_not_configured` before ever reaching its own per-tenant publish step, and no Server Action/UI ever called the upload+store+scan sequence at all. Both fixed: a new catalogue-registration migration plus a real "record installation" upload form in `fleet-panel.tsx`. The "ETA is straight-line/40kmh" half remains DEFERRED_LARGE -- a genuinely separate, larger algorithmic gap (road-network/traffic-aware routing or a mapping-API integration, touching 3+ existing capabilities), unrelated to A6's storage/malware-scan gap |
| E6 | No webhook publisher; no GraphQL/OpenAPI surface | `CODE-BIG` | **PARTIAL** | the webhook half was closed after a dedicated research pass found the original audit's own literal finding ("`app.queue_webhook_delivery` is referenced by 0 other database functions") true on exactly one narrow point, not "no webhook publisher" wholesale: real schema, HMAC-SHA256 signing, SSRF guarding at both registration and dispatch time, the real outbound HTTP worker, job-type registration, wiring into the production supervisor loop, and a reachable tenant admin UI all already existed and were already tested (`20260719150000_create_api_key_webhook_primitives.sql`, `20260804040000_create_intelligence_webhook_management.sql`) -- it was simply dead-gated, never called from any real business event. Closed by adding one `app._enqueue_webhook_delivery` call (a new internal, authority-check-free decision core extracted from `app.queue_webhook_delivery`, mirroring B7's own `app._evaluate_customer_credit` precedent) to each of the three event types the schema's own seed data already anticipated -- `shipment.status_changed` (`app.transition_shipment_order`), `ticket.created` (`app._create_ticket`, covering all three channels: internal/customer/helpdesk), and `invoice.issued` (`app.issue_finance_invoice`). Still open: GraphQL/OpenAPI -- genuinely, confirmedly absent (no `graphql` package dependency, no resolver, no spec file), independently confirmed by two later release-readiness checkpoints; a real, separate REST-based external API surface does already exist (`app/api/v1/*`, API-key gateway, rate limiting, versioning) that could be documented with an OpenAPI spec far more cheaply than building GraphQL, but that is a product/scope call this session does not make unilaterally |

## New findings discovered during remediation (not in the original audit)

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| NEW-1 | `app.claim_next_job`'s own audit-trail write (`capture_audit_event`) attributes the claim event to the job's ORIGINAL requester (`v_job.requested_by_auth_user_id`), not the calling worker -- so under a genuine (non-null) session identity, `capture_audit_event`'s own `assert_actor_is_session_identity` check raises `actor_identity_mismatch` for ANY caller who is not that exact original requester, before any of the job-type-specific authority guards (e.g. D2's) are ever reached. Discovered while writing a behavioral regression test for D2 in `advanced-tms-route-load-planning.sql` -- confirmed live, not theoretical. In production this is masked because the only real caller today is the job supervisor's service-role client (null session identity, which the check exempts), but it means NO job-claiming RPC in this family can currently be correctly exercised, or safely called, by any genuine authenticated session other than the job's own creator -- over-blocking legitimate cross-user operation of the SAME tenant's own queue, not just closing off cross-tenant abuse. | `CODE` | **DONE** | (this commit) |
| NEW-2 | POD (proof of delivery) PDF printed text-only evidence metadata (filenames, no actual images) -- deliberately deferred at the time A7's POD printable was built because A6's own ePOD signed-download RPC did not exist yet. | `CODE` | **DONE** | A6 closed first (`app.access_epod_evidence_for_download`); this follow-on then embedded the real signature/photo images: `generate-pod.server.ts` now calls `getEpodEvidenceSignedDownloadUrl` (service_role-only) per evidence file and passes the resulting short-lived signed URL straight into `@react-pdf/renderer`'s `Image` component -- no bytes ever pass through this codebase's own memory, `@react-pdf/renderer` fetches the URL directly while rendering, well inside its 300s TTL. A per-file failure (denied access, a since-deleted file) degrades to the original text note rather than failing the whole document |

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
  **Cluster 2 (`hris-identity-access`, identity/HRIS access, 5 tables, 10 call sites) is now
  fully `DONE` — in its entirety, not merely a first batch**: cross-checked against
  `CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json`'s own 10-row manifest for this cluster, of
  which 2 rows needed no action (`server/queries/employee.ts` was already fully RPC-backed;
  `server/queries/field-access.ts`'s `can_access_record` call was already `.rpc()`, never
  `.from()`) and the other 8 (this batch's 7 plus `server/queries/leave.ts`'s
  `app.approval_requests` read, already closed by the earlier `34dada1` commit reusing cluster
  0's `get_approval_requests_entity_refs`) are now all fixed — no remaining `hris-identity-access`
  call site needs a second batch. Still open: clusters 3-7 (86 more call sites across
  operations-tms-core/telematics-tracking/procurement-document/platform-intelligence-reports/
  page-level-direct-reads) — next up under the same "lanjut sampe siap launching" mandate.

- 2026-09-11 — Ø1-query-layer cluster 3 (`operations-tms-core`) batch 1 closed (this commit),
  continuing the same user-directed ("lanjut sampe siap launching") mandate. Opens cluster 3 (28
  call sites across 20 tables/views, per the recon's own manifest) and closes its first batch — 7
  call sites across 4 tables/views: `app.shipment_orders` (count only) + `app.dispatch_ready_queue`
  (view) in `server/queries/basic-dispatch.ts`'s `listDispatchReadyQueue`,
  `app.dispatch_board_queue` (view) in `dispatch-board.ts`'s `listDispatchBoard`,
  `app.job_orders_directory` (view, 3 call sites: `getJobOrder`, `getJobOrderForHandoff`,
  `listJobOrders`) in `job-order.ts`, and `app.job_order_handoffs_directory` (view, 2 call sites:
  `getJobOrderHandoffForQuotation`, `listJobOrderHandoffs`) in `job-order-lineage.ts`. New
  migration `20260911000000_close_o1_query_layer_cluster3_batch1_dispatch_job_order_views.sql`
  adds 9 new `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix
  pipeline clusters 0-2 established (RULE A/B/C baked into both stages), completed via parallel
  Agent-tool design/verify calls (the Workflow tool's own subagent-spawning path remained broken
  this session).
  **Real cross-tenant-leak risk found and fixed by the independent verify pass, before this
  migration was ever applied to any database**: `app.get_job_order_for_handoff` and
  `app.get_job_order_handoff_for_quotation` both originally used a silent
  `order by created_at desc limit 1` fallback for a hypothetical (schema-legal but
  application-unreachable today) multi-row match on a non-bare-unique lookup column
  (`source_handoff_id`/`quotation_id`, each only part of a composite unique constraint). Since
  such a match would mean two rows disagreeing about which TENANT a handoff/quotation belongs to,
  silently picking "the newest" risked handing a caller a different tenant's data — not merely a
  nondeterministic pick. Both functions now COUNT matches and RAISE `ambiguous_context`
  (`check_violation`) instead, matching `.maybeSingle()`'s own throw-on-conflict contract and this
  codebase's established count-then-raise idiom (`app.resolve_access_context`, PLT-108). The
  db-test's own adversarial fixture (a raw, service_role-bypass insert producing a genuine
  duplicate row) confirmed this RAISE actually fires against a real database, on two independent
  fresh-database runs.
  **Notable design decision, independently re-verified**: `app.list_dispatch_ready_queue`/
  `app.list_dispatch_board` keep their exact count as a SEPARATE, lateral-free function
  (`app.count_dispatch_ready_shipment_orders`/`app.count_dispatch_board_shipment_orders`) rather
  than the `count(*) over()` single-query shape `app.list_portal_users` established — both
  underlying views cross-join the ~40-line `app.evaluate_dispatch_readiness` per row, so a
  window-function count would reintroduce the exact O(N) lateral-evaluation cost
  CG-AUDIT-2026-09-02 F5 (`20260907170000`) already eliminated for this same screen; this
  migration extends that same fix to `app.dispatch_board_queue` for the first time (never itself
  named by F5, but sharing the identical LATERAL join, confirmed by reading the view body
  directly, not merely trusting its own header's "RLS-scoped identically" claim).
  Two minor documentation-accuracy defects were found and fixed during verify (no SQL logic
  changed): a RULE B citation undercount (two files → three, one of them prose-only) and an
  off-by-one in the `dispatch_board_queue` projection-column count (10 → 11) in a header comment.
  This batch's own db-test (`scripts/db-tests/o1-query-layer-cluster3-batch1.sql`) passed cleanly
  on two independent fresh-database runs — no fixture-setup defect indicated any bug in the
  migration's own function logic (three minor fixture issues, e.g. a nonexistent `min(uuid)`
  aggregate and a unique-constraint collision needing two distinct driver `master_records`, were
  fixed in the test file only).
  All 4 affected TS query files (`server/queries/basic-dispatch.ts`, `dispatch-board.ts`,
  `job-order.ts`, `job-order-lineage.ts`) and every real call site (7 `page.tsx` files:
  `operations/dispatch`, `operations/dispatch-board`, `operations/job-orders`,
  `operations/job-orders/[jobOrderId]`, `operations/job-orders/convert`,
  `operations/shipment-orders/create`, `commercial/quotations/[quotationId]`) switched from
  `.from()` to `.rpc()` in this same commit. Full Tier A gate suite re-run clean: `typecheck`,
  `lint` (0 errors), the 6,000-test unit suite, `check-rls-initplan.ts` (0 findings), a full
  `pnpm run db:test` (`ALL PASSED`, 522 migrations / 266 db-test files), `git:check-paths`,
  `security:check`, and a real `next build`. `scripts/release/check-release-freeze.ts` amended
  (HUNDRED-AND-TWENTY-FIFTH PASS, `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027
  Part A authority.
  **Cluster 3 (`operations-tms-core`) batch 1 (4/20 tables, 7/28 call sites) is now `DONE`.**
  Still open: this cluster's other 16 tables (21 call sites: milestone codes, shipment-leg
  tracking policies/sessions, multi-leg shipment legs/cargo/custody, route-load-planning's 6
  tables, shipment orders, shipment mode profiles, vehicle capacity reservations, exceptions
  directory), plus clusters 4-7 (58 more call sites across telematics-tracking/
  procurement-document/platform-intelligence-reports/page-level-direct-reads) — next up under
  the same "lanjut sampe siap launching" mandate.

- 2026-09-11 — Ø1-query-layer cluster 3 (`operations-tms-core`) batch 2 closed (this commit),
  continuing the same user-directed ("lanjut sampe siap launching") mandate. Closes 6 call sites
  across 6 tables: `app.milestone_codes` (`list_milestone_codes`) in
  `server/queries/milestone-management.ts`, `app.shipment_leg_tracking_policies`
  (`get_shipment_leg_tracking_policy`) and `app.shipment_leg_tracking_sessions`
  (`get_current_shipment_leg_tracking_session`) in `mile-orchestration.ts`, and
  `app.shipment_legs` (`list_shipment_legs`), `app.shipment_leg_cargo_allocations`
  (`get_shipment_leg_cargo_allocation`), `app.shipment_leg_custody_events`
  (`list_shipment_leg_custody_events`) in `multi-leg-shipment.ts`. New migration
  `20260911010000_close_o1_query_layer_cluster3_batch2_milestone_leg_tracking_multileg.sql` adds
  6 new `app.*`+`public.*` Option-2 wrapper pairs via the same adversarial Design→Verify→Fix
  pipeline clusters 0-2 and cluster 3 batch 1 established (RULE A/B/C baked into every draft),
  completed via parallel Agent-tool design/verify calls (the Workflow tool's own
  subagent-spawning path remained broken this session). Two independent verify agents hit a
  session-wide rate limit mid-run this pass; rather than wait idle, the verify work for both
  drafts was completed directly with the same rigor (independent case-insensitive repo-wide
  greps against primary sources for every RULE A/B/C claim) once the rate limit reset.
  **Notable design decision, independently re-verified**: this migration deliberately uses TWO
  DIFFERENT security postures for its 6 functions, both correct for their own table's real
  authority shape. `app.list_milestone_codes` (a genuinely non-tenant-scoped, `using (true)`-to-
  authenticated reference table, mirroring cluster 1 batch 1's `app.list_finance_currencies`
  precedent) and `app.get_shipment_leg_tracking_policy`/`app.get_current_shipment_leg_tracking_
  session` (mirroring this exact table family's own pre-existing, already-live sibling read,
  `app.get_shipment_leg_tracking_sessions`) are all `SECURITY INVOKER` with NO actor parameter,
  relying entirely on the calling session's own real RLS — independently confirmed safe against
  `service_role`'s own BYPASSRLS: `service_role` already holds a direct SELECT grant on all 3
  tables, independent of these new functions, so no new capability is created, and for a genuine
  `authenticated` caller INVOKER is the MOST faithful reproduction of the original
  (never-reachable) RLS-scoped read, with no separate "claimed actor" decoupled from session
  identity for RULE A to protect against — unlike cluster 3 batch 1's dispatch functions, which
  take an EXPLICIT actor parameter specifically because `service_role` calls those ON BEHALF OF
  an arbitrary end user with no session identity of its own. `app.list_shipment_legs`/
  `app.get_shipment_leg_cargo_allocation`/`app.list_shipment_leg_custody_events`, by contrast,
  ARE `SECURITY DEFINER` + explicit `p_actor_auth_user_id` (the dominant convention), since their
  own RLS varies per-shipment-order and an INVOKER function would leak unfiltered rows to a
  `service_role` caller under BYPASSRLS — exactly cluster 3 batch 1's own already-identified
  failure mode.
  A domain investigation (not a defect fix) determined `listShipmentLegs`' own "non-cancelled-
  first" TS comment describes neither an exclusion nor a same-slot reordering rule (a cancelled
  leg permanently reserves its own sequence_no under a plain, non-partial unique constraint,
  making a same-slot replacement schema-impossible) — the new function reproduces the original
  `.from()` call byte-for-byte (every leg, including cancelled ones, in plain ascending
  sequence_no order). Two pre-existing, out-of-scope gaps were disclosed, not fixed: `app.
  get_shipment_leg_stops` (SECURITY INVOKER, no actor param) is called from inside a SECURITY
  DEFINER public wrapper with no table in this family carrying `FORCE ROW LEVEL SECURITY`, a
  plausible already-shipped RLS-bypass gap; and `app.add_shipment_leg`'s own pre-flight
  duplicate-sequence check tests `leg_status <> 'cancelled'` against a base unique constraint
  that carries no such carve-out.
  This batch's own db-test (`scripts/db-tests/o1-query-layer-cluster3-batch2.sql`) genuinely
  forces a real session identity (`set local role authenticated; set local request.jwt.claims`)
  to test the two SECURITY INVOKER functions, never merely an actor-parameter substitute, since
  neither takes an actor parameter at all — confirmed for owner, shared-org-unit member, denied
  same-tenant member, cross-tenant member, and a zero-membership Supreme Admin. One fixture issue
  (a nonexistent `created_by` column on the append-only `app.shipment_leg_custody_events` table,
  should have been `recorded_by`) was fixed in the test file only — no defect in the migration's
  own function logic.
  All 3 affected TS query files (`server/queries/milestone-management.ts`, `mile-orchestration.ts`,
  `multi-leg-shipment.ts`) and every real call site (1 `page.tsx` file,
  `operations/shipment-orders/[shipmentOrderId]`, covering all 6 call sites) switched from
  `.from()` to `.rpc()` in this same commit. Full Tier A gate suite re-run clean: `typecheck`,
  `lint` (0 errors), the 6,008-test unit suite, `check-rls-initplan.ts` (0 findings), a full
  `pnpm run db:test` (`ALL PASSED`, 523 migrations / 267 db-test files), `git:check-paths`,
  `security:check`, and a real `next build`. `scripts/release/check-release-freeze.ts` amended
  (HUNDRED-AND-TWENTY-SIXTH PASS, `migrationSetSha256`/`dbTestSetSha256`) per this same ADR-0027
  Part A authority.
  **Cluster 3 batches 1-2 (10/20 tables, 13/28 call sites) are now `DONE`.** Still open: this
  cluster's other 10 tables (15 call sites: route-load-planning's 6 tables/8 call sites, shipment
  orders/3, shipment mode profiles/1, vehicle capacity reservations/2, exceptions directory/1),
  plus clusters 4-7 (58 more call sites across telematics-tracking/procurement-document/
  platform-intelligence-reports/page-level-direct-reads) — next up under the same "lanjut sampe
  siap launching" mandate.

- 2026-09-11 — Corrective fix (this commit) to the batch 2 migration above, found by cluster 3
  batch 3's own adversarial verify pass before that batch's own migration was ever written.
  `app.get_shipment_leg_tracking_policy`/`app.get_current_shipment_leg_tracking_session` (both
  app.*/public.* pairs) were declared `returns app.<table>` (a bare, non-SETOF composite return)
  on the incorrect premise that a non-SETOF SQL function returns NULL for a zero-row match.
  Empirically verified against a live Postgres 16 instance: it instead returns ONE row with every
  column NULL, which the TS layer's `row ? parse(row) : null` unwrap treats as truthy — both
  functions would have thrown an uncaught `ZodError` for the ordinary "no policy/session defined
  yet" case, a real functional regression in already-pushed code (`075a0eb`).
  An initial attempt fixed this by editing the already-committed migration file in place,
  reasoning that since it had never been applied to any real/hosted database (only disposable
  local test databases), doing so was safe. That attempt was itself corrected before being
  committed: `pnpm run git:check-paths` is a machine-enforced, no-exceptions gate that flags ANY
  edit to an already-committed migration file, independent of whether a real database has
  consumed it — `AGENTS.md` states this as a bright line ("Never edit an applied migration; add a
  new migration") specifically to remove this exact kind of case-by-case judgment call. The
  in-place edit was reverted and a genuine new migration
  (`20260911020000_fix_o1_cluster3_batch2_composite_return_null_bug.sql`) authored instead. Since
  Postgres's `CREATE OR REPLACE FUNCTION` does not allow changing a function's return type, this
  migration DROPs and recreates all 4 declarations (`returns setof app.<table>` instead of
  `returns app.<table>`), every function body/authority reasoning/grant otherwise byte-for-byte
  identical to the original. No TS code change was needed: the existing
  `Array.isArray(data) ? data[0] : data` unwrap already handles a SETOF-returning function's
  empty-array result correctly. Independently re-verified: applied the new migration to a fresh
  disposable database on top of the full existing migration set (clean apply), empirically
  confirmed all 4 functions now return 0 rows on a miss, re-ran cluster 3 batch 2's own full
  db-test (`ALL PASSED`, no other assertion affected), and confirmed via a dedicated repo-wide
  grep that no other function in the entire Ø1-query-layer series (clusters 0 through 3 batch 2)
  carries this same bare-composite-return defect. Full Tier A gate suite re-run clean, including
  `git:check-paths` (now clean). `scripts/release/check-release-freeze.ts` amended
  (HUNDRED-AND-TWENTY-SEVENTH PASS, `migrationSetSha256` only — `dbTestSetSha256` unchanged).

- 2026-09-11 — Ø1-query-layer cluster 3 (`operations-tms-core`) batch 3 closed (this commit),
  continuing the same "lanjut sampe siap launching" mandate. Closes the LAST 8 broken `.from()`
  call sites in `server/queries/route-load-planning.ts` (ATW-224, CG-S10-ATW-005): new migration
  `20260911030000_close_o1_query_layer_cluster3_batch3_route_planning.sql` adds 8 new
  app.\*/public.\* Option-2 wrapper pairs (16 functions) against `app.route_planning_scenarios` /
  `app.route_planning_constraints` / `app.route_planning_candidate_plans` /
  `app.route_planning_score_components` / `app.route_planning_selected_plans` /
  `app.route_planning_replan_events` (6 tables). Assembled from two independently designed and
  independently verified scratchpad drafts, cross-checked before assembly to confirm no
  function-name collisions and 6 distinct target tables between them. All 8 functions are SECURITY
  INVOKER with ZERO actor parameter, independently re-derived by BOTH drafts against this exact
  table family's own two already-live sibling reads in the same underlying migration
  (`app.get_route_planning_stops` / `app.get_canonical_position_for_planning`) — the decisive test
  in both cases was tracing every real call site's actual Supabase client construction code (all
  use `createSupabaseServerClient()`, none use `createSupabaseServiceRoleClient()` to claim an
  actor decoupled from its own session identity), not merely an appeal to a shared security mode.
  This batch independently caught and fixed, BEFORE this migration was ever written or committed,
  the identical non-SETOF bare-composite-return defect class the prior commit's corrective
  migration fixed in already-pushed code: `app.get_route_planning_scenario` was found and fixed by
  its own draft's own adversarial verify pass; `app.get_current_route_planning_selection`'s
  identical defect was initially MISSED by its own draft's verify pass — despite the sibling
  draft's verify catching the analogous case in the very same batch — and was caught during a
  final cross-draft review before assembly, with the fix's own comment explicitly citing
  `20260911020000`'s corrective migration as precedent. Both 0-or-1-row lookups (bounded
  respectively by the table's own primary key and by a partial unique index on `(scenario_id)
  WHERE is_current`) are declared `returns setof app.<table>`. Because both instances of this
  defect class were fixed before this migration's first commit, no corrective follow-up migration
  was needed for this batch, unlike batch 2's own history — itself now a standing lesson this
  session applies going forward: every future single-row lookup's return type is explicitly
  double-checked for `returns setof` (never a bare composite) as part of every verify pass, since
  this defect class has now appeared three times in one session.
  `server/queries/route-load-planning.ts`: all 8 functions converted from `.from()` to `.rpc()`,
  all 8 signatures unchanged (non-breaking). `RouteLoadPlanningQueryTableClient` deliberately stays
  `Pick<SupabaseClient, "from" | "rpc">` (unlike cluster 3 batch 2's file-wide narrowing to
  `Pick<SupabaseClient, "rpc">`), since the file's other functions (the 2 pre-existing RPC-backed
  reads) remain in the file. A repo-wide grep confirmed the one real call site
  (`app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/route-planning/page.tsx`,
  all 6 of its call sites) needed no change beyond the internal client-method swap (all signatures
  non-breaking), and that `listRoutePlanningSelections`/`listRoutePlanningReplanEvents` have zero
  current callers anywhere in the app. `server/queries/route-load-planning.test.ts`: the existing
  `listRoutePlanningScenarios` block converted from `.from()` to `.rpc()` mocking; 7 new describe
  blocks added for the other 7 functions (none had any prior coverage), mirroring this file's own
  established fake-`.rpc()`-client pattern.
  Full Tier A gate suite re-run clean: `typecheck`, `lint` (0 errors), the 6,017-test unit suite (14
  new tests for this file), `check-rls-initplan.ts` (0 findings — this migration adds no RLS
  policy), a full `pnpm run db:test` (`ALL PASSED`, 525 migrations / 268 db-test files, including
  the new `o1-query-layer-cluster3-batch3.sql`: owner/shared-org-unit/denied-member/cross-tenant/
  Supreme-Admin visibility across all 8 functions' 1/2/3-hop RLS join depths, both 0-or-1-row
  getters proven to return a genuinely empty result — never a row of nulls — on their miss case,
  ordering fidelity for all 3 ordered functions proven against deliberately out-of-order fixture
  inserts, the replan-events column-semantics derivation (`scenario_id` vs `previous_scenario_id`)
  proven directly, anon denial on all 16 functions via real call attempts, and a service_role
  BYPASSRLS smoke check), `git:check-paths` (clean, 4 files checked), `security:check`, and a real
  `next build`. `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTY-EIGHTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **CORRECTION (caught while preparing the next entry below, not by an external reviewer):** the
  line immediately above originally claimed cluster 3 was "FULLY `DONE`: all 20 tables, all 28 call
  sites closed" after batches 1-3 alone. That was factually premature and wrong at the time it was
  written — batches 1-3 close 16/20 tables and 21/28 call sites (4+6+6 tables, 7+6+8 call sites),
  not all 20/28. Batch 3 closes route-load-planning.ts's 6 tables/8 call sites; the remaining 4
  tables/7 call sites (shipment-order.ts, shipment-mode-baseline.ts, capacity-utilization.ts,
  exception-escalation.ts) are batch 4's own scope, entered separately below. Left uncorrected in
  place above (not silently rewritten) per this same file's own standing practice of documenting a
  mistake rather than erasing it — the correct, verified state of cluster 3 as of batch 3 alone is
  **batches 1-3 DONE (16/20 tables, 21/28 call sites); batch 4 (4 tables/7 call sites) still open**.

- 2026-09-11 — Ø1-query-layer cluster 3 (`operations-tms-core`) batch 4 closed (this commit),
  continuing the same "lanjut sampe siap launching" mandate. This is the FINAL batch of cluster 3.
  Closes the LAST 7 broken `.from()` call sites in this cluster: `server/queries/shipment-order.ts`
  (3 call sites: `getShipmentOrder`, `listShipmentOrdersForJobOrder`, `listShipmentOrders`),
  `shipment-mode-baseline.ts` (1: `getShipmentModeProfile`), `capacity-utilization.ts` (2:
  `listCapacityReservationsForLeg`, `listActiveCapacityReservationsForVehicle`), and
  `exception-escalation.ts` (1: `listShipmentExceptions`). New migration
  `20260911040000_close_o1_query_layer_cluster3_batch4_shipment_order_capacity_exceptions.sql` adds
  7 new app.\*/public.\* Option-2 wrapper pairs (14 functions) against `app.shipment_orders` /
  `app.shipment_mode_profiles` / `app.vehicle_capacity_reservations` / `app.exceptions_directory` (4
  relations), assembled from two independently designed and independently verified scratchpad
  drafts, cross-checked before assembly to confirm no function-name collision and 4 distinct target
  relations between them.
  This batch spans 3 genuinely distinct authority shapes, each independently re-derived rather than
  assumed to transfer from a sibling table: (1) `app.shipment_orders`/`app.shipment_mode_profiles`
  use the standard `app.can_access_record(auth.uid(), tenant_id, owner_user_id, org_unit_ids, null)`
  predicate, confirmed independently against the "critical prior research finding" that
  `app.get_customer_shipment_order`/`app.list_customer_shipment_orders` gate on a DIFFERENT,
  narrower `resolve_customer_account_scope` predicate and return a hand-picked customer-safe
  projection missing 10 columns the internal-ops callers need — brand-new functions were required,
  not reuse; (2) `app.vehicle_capacity_reservations` uses a tenant-membership predicate —
  `(app.has_active_tenant_membership(tenant_id) AND NOT app.actor_holds_customer_user_layer(tenant_id))
  OR app.is_supreme_admin()` — independently re-verified via a fresh RULE B grep (the original
  `CREATE POLICY` was later superseded by an `ALTER POLICY`), deliberately not conflated with the
  can_access_record shape used everywhere else in this batch; (3) `app.exceptions_directory` is a
  VIEW whose own row-visibility WHERE clause is a plain, self-contained `can_access_record(auth.uid(),
  ...)` predicate plus `app.has_view_exception_cost`-gated column masking — safe under SECURITY
  INVOKER specifically because the predicate is keyed on `auth.uid()` (a per-request GUC) rather
  than delegated to base-table RLS pass-through, independently distinguished from the
  `app.users_directory`/PLT-114 defect this same codebase already documents
  (`20260716113048_create_audit_trail.sql`) for a view that DID have that unsafe shape.
  All 7 functions are SECURITY INVOKER with zero actor parameter, via this series' own decisive
  test (every real call site of all 7 TS functions uses `createSupabaseServerClient()` only, or a
  hand-rolled test fake for the 3 functions with zero current production callers — none uses
  `createSupabaseServiceRoleClient()` to claim a decoupled actor). `app.get_shipment_order` and
  `app.get_shipment_mode_profile` (both 0-or-1-row lookups) are declared `returns setof
  app.<table>`, never a bare composite — the standing defect-class check this series has run on
  every batch since it first surfaced, applied cleanly here with no corrective follow-up needed.
  `app.list_shipment_orders` is a new server-paginated function mirroring `app.list_portal_users`'
  own established `count(*) over()` idiom exactly; disclosed one inherited, non-novel
  characteristic (an out-of-range page reports `total_count` 0 rather than the true total, matching
  `server/queries/portal-users.ts:80`'s own already-shipped handling of the identical case).
  A real, pre-existing data-completeness defect was found and documented, not fixed (out of this
  batch's wrapper-only scope): `app.exceptions_directory`'s own view body was never widened to
  project the 4 provenance columns (`source_class`/`source_confidence_score`/
  `source_freshness_status`/`source_signal_id`) added to `app.operational_exceptions` at ATW-228 —
  every row read through the view always reports these 4 fields as null, even when the underlying
  table has real values; does not break parsing (the Zod schema treats them as nullable).
  All 4 TS query files converted from `.from()` to `.rpc()` with unchanged (non-breaking) call
  signatures; 6 real call sites across 4 `page.tsx` files needed no changes beyond the internal
  client-method swap. `shipment-mode-baseline.ts`'s and `exception-escalation.ts`'s client types
  were narrowed to `Pick<SupabaseClient, "rpc">` (each file's only `.from()`-backed function
  converts here); `shipment-order.ts`'s and `capacity-utilization.ts`'s wider `"from" | "rpc"` types
  are left unchanged per this series' own established convention, since each still carries other
  RPC-only functions in the same file.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,017-test unit suite
  (4 test files converted from `.from()`-mocking to `.rpc()`-mocking), `check-rls-initplan.ts` (0
  findings), a full `pnpm run db:test` (`ALL PASSED`, 526 migrations / 269 db-test files, including
  the new `o1-query-layer-cluster3-batch4.sql`: a full owner/shared-org-unit/denied-member/
  cross-tenant/Supreme-Admin visibility matrix across all 3 authority shapes, both 0-or-1-row
  getters' genuinely-empty-on-miss proof, full pagination coverage for `list_shipment_orders`
  (page 1/page 2/out-of-range/page_size clamp) with a consistent `total_count`, the tenant-membership
  shape's own customer-layer-exclusion proof via a real customer_user-layer principal, and the
  cost-masking proof for `list_shipment_exceptions` — an owner holding OPS:View cost sees real
  sensitive fields, a shared-org-unit viewer lacking that permission sees them nulled with
  `sensitive_masked=true` despite full row-level access, and a Supreme Admin sees real values via
  `evaluate_permission`'s own `supreme_admin_exception` branch with zero explicit grant),
  `git:check-paths` (clean, 10 files checked), `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-TWENTY-NINTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **Cluster 3 (`operations-tms-core`) is now FULLY, FINALLY `DONE`: all 20 tables, all 28 call sites
  closed** (batches 1-4, this time genuinely — see the CORRECTION note above for why batch 3's own
  identical claim was premature). Remaining across the whole Ø1-query-layer effort: clusters 4-7
  (58 call sites across telematics-tracking/procurement-document/platform-intelligence-reports/
  page-level-direct-reads) — next up under the same "lanjut sampe siap launching" mandate.

- 2026-09-13 — Ø1-query-layer cluster 4 (`telematics-tracking`), both batches, closed in the same
  working session (this commit), continuing the same "lanjut sampe siap launching" mandate. This is
  the FIRST cluster in this whole series where two batches are closed together under one commit and
  one release-freeze pass, since both were designed, verified, and bug-fixed before either was
  individually committed. Closes all 12 broken `.from()` call sites in this cluster: `server/queries/
  fleet-driver-device.ts` (7 call sites, batch 1) and `driver-mobile-tracking.ts` (1) /
  `gps-device-installation.ts` (2) / `tracking-source-policy.ts` (1) / `public-tracking.ts` (1) (5
  call sites across 4 files, batch 2). Two new migrations —
  `20260911050000_close_o1_query_layer_cluster4_batch1_fleet_driver_device.sql` and
  `20260911060000_close_o1_query_layer_cluster4_batch2_tracking_security.sql` — add 12 new
  `app.*`/`public.*` Option-2 wrapper pairs (24 functions), each assembled from two independently
  designed and independently verified scratchpad drafts, one per batch.
  Batch 1 (7 functions over `app.vehicle_operational_profiles`/`driver_operational_profiles`/
  `gps_devices`/`sim_cards`/`device_vehicle_assignments`/`provider_vehicle_mappings`/
  `vehicle_tracking_source_priorities`) are all SECURITY INVOKER, zero actor parameter, sharing one
  tenant-membership RLS predicate — `(app.has_active_tenant_membership(tenant_id) AND NOT
  app.actor_holds_customer_user_layer(tenant_id)) OR app.is_supreme_admin()` — the same shape cluster
  3 batch 4's own `app.vehicle_capacity_reservations` functions already established as INVOKER-safe.
  A genuine KEY FINDING corrected a plausible-but-wrong first-pass assumption: 3 of the 7 tables
  (`device_vehicle_assignments`/`provider_vehicle_mappings`/`vehicle_tracking_source_priorities`) are
  filtered in their own RPC call by `device_id`/`vehicle_master_id`, not `tenant_id` — independently
  re-derived from each table's own `create table`/`create policy` statements that this is NOT a
  join-derived authority chain: all 3 carry their own, physically independent `tenant_id` column, and
  their RLS predicate is a plain check on that column, with no `EXISTS`/join to `app.gps_devices` or
  `app.master_records` anywhere in any of their 14 policy statements.
  Batch 2 (5 functions over `app.driver_mobile_tracking_sessions`/`gps_device_installations`/
  `tenant_tracking_source_policies`/`shipment_tracking_tokens`) spans 3 distinct authority shapes: 2
  SECURITY DEFINER functions (`app.get_driver_mobile_tracking_session`, `app.get_active_shipment_
  tracking_token`) taking an explicit `p_actor_auth_user_id` + RULE A guard, required because
  ISS-2026-232 already revoked `authenticated`'s table-level SELECT on both underlying tables in
  favor of an explicit column-level grant excluding `token_hash` — both new functions use `returns
  table (...)` with the same explicit safe-column list their original `.from()` calls used, never
  `returns setof app.<table>` (which would leak `token_hash` back into the composite); and 3 SECURITY
  INVOKER functions (`app.list_gps_device_installations`, `app.get_gps_device_installation_for_
  assignment`, `app.get_tenant_tracking_source_policy`) over 2 tables never touched by ISS-2026-232,
  sharing the same tenant-membership predicate as batch 1. An adversarial verify pass surfaced and
  corrected the batch brief's own overstated mechanism for why DEFINER was required (Postgres grants
  SELECT per-column, not only per-table, so a same-column-list INVOKER function would in fact pass
  the privilege check today) — DEFINER was retained anyway for two independent, still-valid reasons
  (drift protection against a future bare-grant regression re-opening the exact gap ISS-2026-232
  closed, and consistency with this table family's own write-side DEFINER precedent), with the
  corrected reasoning documented rather than the overstated claim repeated uncritically.
  Both 0-or-1-row lookups outside the DEFINER pair (`app.get_gps_device_installation_for_assignment`,
  `app.get_tenant_tracking_source_policy`) are declared `returns setof app.<table>`, never a bare
  composite — the standing defect-class check, applied cleanly with no corrective follow-up needed in
  either batch.
  All 5 TS query files converted from `.from()` to `.rpc()`. `fleet-driver-device.ts`'s and
  `gps-device-installation.ts`'s client types were narrowed to `Pick<SupabaseClient, "rpc">` (each
  file's entire `.from()`-backed surface converts in this pass); `driver-mobile-tracking.ts`,
  `tracking-source-policy.ts`, and `public-tracking.ts` already carried `"rpc"` in their client types
  and are left unchanged per this series' own established convention. Two genuinely NEW, disclosed
  breaking parameters were added (RULE A, batch 2 only): `getDriverMobileTrackingSession` and
  `getActiveShipmentTrackingToken` both gained an `actorAuthUserId` parameter — the former has zero
  real production callers today (only a unit test), the latter has exactly one real call site
  (`app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx:258`), updated to
  pass the page's own already-in-scope `access.authUserId`, already threaded into every one of that
  page's ~12 sibling query calls.
  A real, independently-caught db-test bug was found and fixed during this pass's own verification,
  not merely accepted from the drafting agent's self-report: cluster 4 batch 1's own db-test file
  initially resolved several fixture-row ids via subqueries filtered ONLY by an enum-shaped column
  (`source_type`/`provider_code`/a free-text `reason` string) with no scoping to the specific
  `vehicle_master_id`/`device_id` under test — this passed cleanly when the file was run standalone
  (the only rows of that shape in an otherwise-empty disposable database) but failed with a genuine
  `more than one row returned by a subquery` error the first time it ran inside the FULL `pnpm run
  db:test` suite, where other db-test files' own fixtures share one database and can carry rows with
  the same enum value on a different vehicle/device. Fixed by adding the missing `vehicle_master_id`/
  `device_id` scope to every one of the 8 affected subqueries (both the tenant-member and Supreme
  Admin test sessions) — re-verified with a full `pnpm run db:test` run afterward, ALL PASSED. This is
  a new failure mode for this series (prior batches' db-test files happened not to trigger it) and is
  flagged here as a standing lesson, applied going forward: a db-test file passing in isolation is NOT
  sufficient evidence it is correct under the shared-database full-suite run — the full suite must be
  run before considering a batch's db-test file verified, not merely the standalone `psql -f`
  invocation used during iteration.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,022-test unit suite (5
  test files converted from `.from()`-mocking to `.rpc()`-mocking, 2 new describe blocks added for
  `fleet-driver-device.ts`'s previously-untested functions), `check-rls-initplan.ts` (0 findings —
  neither migration adds an RLS policy), a full `pnpm run db:test` (`ALL PASSED`, 528 migrations / 271
  db-test files, including both new cluster-4 db-test files: a full owner/customer-user-layer/
  cross-tenant/Supreme-Admin visibility matrix across all 12 functions and both authority shapes, the
  RULE A forged-actor-rejection proof for both SECURITY DEFINER functions — a session authenticated
  as one actor claiming a different actor's identity is genuinely rejected via
  `actor_identity_mismatch` before any lookup runs — explicit `to_jsonb(row) ? 'token_hash'` proofs
  that neither DEFINER function's own response shape ever carries the sensitive column,
  genuinely-empty-on-miss proofs for every 0-or-1-row lookup, and ordering-fidelity proofs against
  fixture rows deliberately inserted out of order), `git:check-paths` (clean, 16 files checked),
  `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTIETH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **Cluster 4 (`telematics-tracking`) is now FULLY `DONE`: all 12 call sites closed** (batches 1-2).
  Remaining across the whole Ø1-query-layer effort: clusters 5-7 (46 call sites across
  procurement-document/platform-intelligence-reports/page-level-direct-reads) — next up under the
  same "lanjut sampe siap launching" mandate.

- 2026-09-13 — Ø1-query-layer cluster 5 (`procurement-document`), the FULL cluster, closed in one
  migration (this commit), continuing the same "lanjut sampe siap launching" mandate. Closes 4 of
  this cluster's 5 broken `.from()` call sites: `server/queries/procurement-approval.ts:49`
  (`listProcurementApprovalPolicyVersions`), `server/queries/procurement-dashboard.ts:110`
  (`listActiveProcurementMetricDefinitions`), `server/queries/document-requirement.ts:77`
  (`listDocumentRequirementDefinitions`), `server/queries/document.ts:94` (`listDocumentTypes`). New
  migration `20260913000000_close_o1_query_layer_cluster5_procurement_document.sql` adds 4 new
  `app.*`/`public.*` Option-2 wrapper pairs (8 functions) across 4 relations, spanning 2 distinct
  authority shapes: 2 SECURITY DEFINER functions (`list_procurement_approval_policy_versions`,
  `list_document_requirement_definitions`) taking an explicit `p_tenant_id` + `p_actor_auth_user_id`,
  RULE A-guarded, reproducing each table's own CURRENT tenant-membership RLS predicate and RAISING
  `insufficient_authority` on total denial — mirroring `app.list_quotation_approval_rule_versions`'
  own established precedent (cluster 0 batch 4) rather than a silent empty list, a deliberate,
  disclosed tightening over the original RLS-filtered `.from()` reads' own behavior; and 2 SECURITY
  INVOKER, zero-actor-param functions (`list_active_procurement_metric_definitions`,
  `list_document_types`) over tables with either no RLS at all (a plain `grant select ... to
  authenticated, service_role`) or a genuinely open `using (true)` policy, mirroring
  `app.list_milestone_codes`' own established precedent (cluster 3 batch 2).
  The fifth call site (`procurement-approval.ts:136`, `listProcurementApprovalInboxForActor`) needed
  NO new SQL at all: an adversarial re-check of the `CG-AUDIT-2026-09-02-O1-QUERY-LAYER-RECON.json`
  manifest's own `NEEDS_NEW_FUNCTION` classification for this call site found it stale —
  `app.get_approval_requests_entity_refs(uuid[], uuid)`, already shipped by cluster 0 batch 3 for the
  byte-for-byte identical read shape on the exact same table (same 3-column projection, same
  "no `p_tenant_id`, authority evaluated per-row against each candidate row's own `tenant_id`" contract),
  already covers it — confirmed via a fresh RULE C grep that it is still that function's own only
  body. This is a pure TS-side swap (`.from("approval_requests")` → the existing RPC, mirroring
  `server/queries/quotation-approval.ts`'s own identical `listQuotationApprovalInboxForActor` shape
  exactly), never a new function — the original recon was run before cluster 0 batch 3 existed and
  could not have known that function would ship by the time this cluster was closed.
  A real, independently-caught db-test defect was found and fixed during this pass's own
  verification, not merely accepted from a first draft: an early version of this pass's own db-test
  file committed 2 new `is_current=true` rows into `app.procurement_metric_definitions` to exercise
  the `is_current`/`status` filter — but that table is platform-wide and already has an EXACT
  `count(*)` assertion against it in `scripts/db-tests/procurement-vendor-dashboard-reports.sql`
  (`expected exactly 11 current metric definitions`), which broke the moment the FULL `pnpm run
  db:test` suite ran (`got 14`) — the standalone single-file run never surfaces this, since it never
  runs that other file in the same shared database. Fixed by wrapping that one test block's fixture
  inserts and assertions in an explicit `begin ... rollback` instead of letting them commit — the
  block still fully proves the exclusion behavior (it reads its own uncommitted fixture rows before
  rolling them back), but leaves the shared table exactly as every other db-test file in the suite
  expects it, in any run order. Re-verified with a full `pnpm run db:test` run afterward, ALL PASSED
  (both this file and the previously-broken sibling). This is a genuinely NEW shape of the cross-file
  fixture-collision defect class cluster 4 batch 1 first identified for this series (there, an
  underscoped subquery inside the SAME file collided with another file's fixture rows; here, this
  file's OWN fixture rows broke an exact-count assertion inside a DIFFERENT file) — restated here as
  the same standing lesson, generalized: the full `pnpm run db:test` suite, never a standalone
  `psql -f` invocation, is the only real verification for a shared-database db-test file, and the
  collision can run in either direction.
  All 4 TS query files converted from `.from()` to `.rpc()`; `procurement-approval.ts` converts its
  one remaining `.from()` call site too (the entity-refs swap above), so
  `ProcurementApprovalQueryClient`, `ProcurementDashboardQueryClient`, and
  `DocumentRequirementQueryClient` all narrow from `Pick<SupabaseClient, "from" | "rpc">` to
  `Pick<SupabaseClient, "rpc">` — each file's own only `"from"` usage(s) converted here.
  `document.ts`'s own `DocumentTypeLookupClient` (a hand-written interface, not a `SupabaseClient`
  pick) changes from a `from()`-shaped interface to an `rpc()`-shaped one. Two disclosed,
  non-breaking-in-practice signature changes: `listProcurementApprovalPolicyVersions` gains a
  required `actorAuthUserId` parameter — its one real call site
  (`app/(tenant)/[tenantSlug]/procurement/approvals/page.tsx:36`) already had `access.authUserId` in
  scope (passed to the inbox call on the line above); `listDocumentRequirementDefinitions`' input
  gains a required `actorAuthUserId` field — zero real production callers today (only a unit test), a
  safe addition.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,023-test unit suite (5
  test files converted from `.from()`-mocking to `.rpc()`-mocking; `procurement-dashboard.test.ts`'s
  now-dead `recordingFromClient` helper removed, not left unused), `check-rls-initplan.ts` (0
  findings — this migration adds no RLS policy), a full `pnpm run db:test` (`ALL PASSED`, 529
  migrations / 272 db-test files, including the new cluster-5 db-test file: a full
  member/customer-user-layer/cross-tenant/Supreme-Admin visibility matrix on both DEFINER functions
  including the `insufficient_authority`-raises-on-denial proof, the RULE A forged-actor-rejection
  proof for both, and existence-based, never exact-count, proofs for both INVOKER functions'
  filter/ordering/exclusion behavior against the shared platform-wide tables), `git:check-paths`
  (clean, 12 files checked), `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-FIRST PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **Cluster 5 (`procurement-document`) is now FULLY `DONE`: all 5 call sites closed** in one
  migration. Remaining across the whole Ø1-query-layer effort: clusters 6-7 (46 call sites across
  platform-intelligence-reports/page-level-direct-reads) — next up under the same "lanjut sampe siap
  launching" mandate.

- 2026-09-13 — Ø1-query-layer cluster 6 (`platform-intelligence-reports`) batch 1 of N closed
  (this commit), continuing the same "lanjut sampe siap launching" mandate. Closes 9 of this
  cluster's 30 broken `.from()` call sites across `server/queries/analytics.ts` (3:
  `listAnalyticsViews`, `getLatestAnalyticsRefreshRun`, `listAnalyticsRefreshRuns`) and
  `server/queries/automation-rule.ts` (6: `listAutomationRules`, `getAutomationRuleById`,
  `listAutomationRuleVersions`, `listAutomationRuleExecutions`,
  `getLatestAutomationRulePublishApprovalRequest`, `listApprovalRequestSteps`). New migration
  `20260913010000_close_o1_query_layer_cluster6_batch1_analytics_automation.sql` adds 9 new
  `app.*`/`public.*` Option-2 wrapper pairs (18 functions), ALL SECURITY INVOKER with ZERO actor
  parameter — every real call site of all 9 TS functions uses `createSupabaseServerClient()` only,
  never a decoupled service-role actor.
  Three distinct grant/RLS shapes, none satisfiable by a bare `select *`: (1) `app.analytics_view_
  registry` — no RLS at all, a plain, never-narrowed full-row grant; (2) `app.analytics_refresh_runs`
  — no RLS, but COLUMN-restricted (ISS-2026-174) — an adversarial correction of the recon manifest's
  own stale "zero grant to authenticated" claim, which cited only the table's original migration and
  missed a LATER harden migration (`20260827030000_harden_analytics_refresh_runs_grant.sql`) that
  re-granted a narrower 8-column list after revoking the full-row grant; both new functions select
  exactly those 8 columns and explicitly cast `row_count_before`/`triggered_by_auth_user_id`/
  `triggered_by_label` to null — confirmed zero UI regression via a repo-wide grep (none of the 3 is
  rendered anywhere in `app/**/*.tsx`); (3) `app.automation_rules`/`app.automation_rule_versions`/
  `app.automation_rule_executions`/`app.approval_requests`/`app.approval_request_steps` — RLS-scoped
  tenant-membership predicates, with the first 3 carrying NO explicit `OR is_supreme_admin()`
  disjunct at the policy level (unlike several sibling tables this series already closed) — verified
  LIVE in this pass's own db-test, not merely cited, that `app.has_active_tenant_membership`'s own
  current body already admits a Supreme Admin internally via its own `or app.is_supreme_admin(...)`
  branch, so the policy-level omission carries no functional gap. `app.approval_requests` is
  additionally COLUMN-restricted (`ended_reason` excluded since `20260731210000`, Finding 5
  CRITICAL) — the new function selects the exact same explicit 15-column list
  `server/queries/automation-rule.ts`'s own pre-existing TS code already used. Every 0-or-1-row
  lookup is declared `returns setof app.<table>`, never a bare composite.
  All TS signatures are unchanged — zero disclosed breaking parameter additions in this batch (every
  function already had exactly the parameters its new RPC needs).
  A real, independently-caught db-test bug was found and fixed during this pass's own verification:
  an early version of this batch's db-test file resolved `automation_rule_versions` fixture rows via
  a subquery filtered only by `version_number`, with no `automation_rule_id` scope — this passed
  standalone but failed with `more than one row returned by a subquery` the first time it ran inside
  the FULL `pnpm run db:test` suite, because `scripts/db-tests/automation-rule-engine.sql` (the
  pre-existing sibling test for this exact table) also creates `version_number=1`/`2` rows for its
  own rules. This is the SAME cross-file fixture-collision defect class cluster 4 batch 1 first
  identified for this series, in its original shape (an underscoped subquery inside this file, not
  an exact-count assertion in a different file, which was cluster 5's own instance of it) — fixed by
  adding the missing `automation_rule_id` scope to all 4 affected subqueries; re-verified with a full
  `pnpm run db:test` run afterward, ALL PASSED. Restated for a third time as this series' own
  standing lesson: the full suite, never a standalone `psql -f` invocation, is the only real
  verification for a shared-database db-test file.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,023-test unit suite (2
  test files converted from `.from()`-mocking to `.rpc()`-mocking), `check-rls-initplan.ts` (0
  findings — this migration adds no RLS policy), a full `pnpm run db:test` (`ALL PASSED`, 530
  migrations / 273 db-test files, including the new cluster-6-batch-1 db-test file: a full
  member/customer-user-layer/cross-tenant/Supreme-Admin visibility matrix across both RLS shapes,
  ordering-fidelity proofs against fixture rows deliberately inserted out of order, and explicit
  proof that a REAL, non-null `ended_reason`/`row_count_before`/`triggered_by_auth_user_id`/
  `triggered_by_label` written directly to fixture rows all come back genuinely null through the new
  functions), `git:check-paths` (clean, 7 files checked), `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-SECOND PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  Cluster 6 (`platform-intelligence-reports`) remains `IN_PROGRESS`: 9/30 call sites closed. Still
  open in this cluster: `server/queries/integration-hub.ts` (4), `server/queries/third-party-
  provider-adapter.ts` (1), `server/queries/report.ts` (5), `server/queries/saved-report-view.ts`
  (1), `server/queries/scheduled-report.ts` (4), `server/queries/supreme-tenants.ts` (1),
  `server/queries/tenant-dashboard.ts` (5) — next up under the same "lanjut sampe siap launching"
  mandate. Plus cluster 7 (16 call sites) after that.

- 2026-09-13 — Ø1-query-layer cluster 6 (`platform-intelligence-reports`) batch 2 of N closed
  (this commit), continuing the same "lanjut sampe siap launching" mandate. Closes 5 more of this
  cluster's remaining broken `.from()` call sites across `server/queries/integration-hub.ts` (4:
  `listIntegrationAdapters`, `listIntegrationConnections`, `getIntegrationConnectionById`,
  `listIntegrationHealthChecks`) and `server/queries/third-party-provider-adapter.ts` (1:
  `getThirdPartyProviderConnection`) — 14/30 cumulative for the cluster. New migration
  `20260913020000_close_o1_query_layer_cluster6_batch2_integration_hub.sql` adds 5 new
  `app.*`/`public.*` Option-2 wrapper pairs (10 functions), ALL SECURITY INVOKER, zero actor
  parameter.
  Three grant/RLS shapes: (1) `app.integration_adapters` — no RLS at all, a plain, never-narrowed
  full-row grant; (2) `app.integration_connections`/`app.integration_health_checks` — RLS-scoped
  tenant-membership, with NO explicit `OR is_supreme_admin()` disjunct at the policy level — the
  SAME shape cluster 6 batch 1's own `app.automation_rules` family used — re-verified LIVE in
  THIS batch's own db-test, not merely assumed to carry over, that `app.has_active_tenant_
  membership`'s own internal Supreme Admin branch still admits a zero-membership Supreme Admin;
  (3) `app.third_party_provider_connections` — RLS-scoped with an explicit `OR is_supreme_admin()`
  disjunct, plus a live schema-evolution wrinkle independently traced rather than assumed from the
  recon's own 14-column citation: the table's original `webhook_secret_value` column was later
  DROPPED entirely and replaced by a new `webhook_secret_value_encrypted bytea` column that
  appears in NO grant statement whatsoever (confirmed via a full grant/revoke history grep across
  every migration mentioning this table). The new function selects all 15 of the table's current
  visible columns (structurally required for `returns setof <table>`) and explicitly casts the
  ungranted 15th to null — proven live against a real, non-null bytea value deliberately written
  to the fixture row. Every 0-or-1-row lookup declared `returns setof app.<table>`, never a bare
  composite. Zero disclosed breaking parameter changes.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,023-test unit suite
  (2 test files converted from `.from()`-mocking to `.rpc()`-mocking), `check-rls-initplan.ts` (0
  findings — this migration adds no RLS policy), a full `pnpm run db:test` (`ALL PASSED`, 531
  migrations / 274 db-test files, including the new cluster-6-batch-2 db-test file: a full
  member/customer-user-layer/cross-tenant/Supreme-Admin visibility matrix across all 3 shapes,
  ordering-fidelity proofs against fixture rows deliberately inserted out of order, and an
  explicit null-cast proof for `webhook_secret_value_encrypted`), `git:check-paths` (clean, 7
  files checked), `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-THIRD PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  Cluster 6 (`platform-intelligence-reports`) remains `IN_PROGRESS`: 14/30 call sites closed. Still
  open: `server/queries/report.ts` (5), `server/queries/saved-report-view.ts` (1),
  `server/queries/scheduled-report.ts` (4), `server/queries/supreme-tenants.ts` (1),
  `server/queries/tenant-dashboard.ts` (5) — next up under the same "lanjut sampe siap launching"
  mandate. Plus cluster 7 (16 call sites) after that.

- 2026-09-13 — Ø1-query-layer cluster 6 (`platform-intelligence-reports`) batch 3 of N closed
  (this commit), continuing the same "lanjut sampe siap launching" mandate. Closes 6 more of this
  cluster's remaining broken `.from()` call sites across `server/queries/report.ts` (5:
  `listActiveReportTypes`, `getReportTypeByCode`, `listReportRuns`, `listReportRunsForType`,
  `listReportTypeVersions`) and `server/queries/saved-report-view.ts` (1:
  `getSavedReportViewById`) — 20/30 cumulative for the cluster. New migration
  `20260913030000_close_o1_query_layer_cluster6_batch3_reports.sql` adds 5 new
  `app.*`/`public.*` Option-2 wrapper pairs (10 functions), ALL SECURITY INVOKER, zero actor
  parameter. `listReportRuns`/`listReportRunsForType` deliberately share ONE new function
  (`app.list_report_runs`, a nullable `p_report_type_code` parameter) rather than two
  near-duplicates, a disclosed implementation choice.
  Three grant/RLS shapes: (1) `app.report_types`/`app.report_type_versions` — no RLS, full-row
  grant, platform-wide; (2) `app.report_runs` — RLS-scoped tenant-membership with an explicit
  `OR is_supreme_admin()` disjunct; (3) `app.saved_report_views` — a genuinely 3-branch
  predicate (supreme-admin bypass, owner-row-plus-membership, or tenant-shared-row-plus-
  membership), whose CURRENT text was traced through a DROP-AND-RECREATE, a different RULE B
  mechanism than every other finding in this series so far
  (`20260810500000_harden_own_row_rls_membership_gap.sql:83-92`). The new function relies
  ENTIRELY on live RLS rather than re-implementing the 3-branch logic — proven live with a
  SECOND real tenant member who is NOT the view owner, confirmed to see a tenant-shared view
  but be genuinely denied a private one, the exact distinction a hand-rolled reproduction could
  get subtly wrong.
  A real, independently-caught db-test bug was found and fixed during this pass's own
  verification: an early draft's fixture inserted a new `app.report_types` row with no matching
  `app.report_type_versions` row, which broke `scripts/db-tests/reporting-engine.sql`'s own
  pre-existing assertion that every `report_types` row has a backfilled version 1 — tracing the
  CURRENT `app.register_report_type` body confirmed this is a real, currently-enforced
  production invariant ("every report type … always has a real version history from the moment
  it exists"), not merely another file's own arbitrary assumption. Fixed by adding the missing
  version row, matching what the real registration function would always do. Re-verified with a
  full `pnpm run db:test` run afterward, ALL PASSED. A third instance of this series' own
  standing cross-file-collision lesson, in a third distinct shape.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors), the 6,023-test unit
  suite (2 test files converted from `.from()`-mocking to `.rpc()`-mocking), `check-rls-initplan.ts`
  (0 findings — this migration adds no RLS policy), a full `pnpm run db:test` (`ALL PASSED`, 532
  migrations / 275 db-test files, including the new cluster-6-batch-3 db-test file: existence
  proofs for the platform-wide tables, the get-by-code-vs-list-active distinction, the
  `p_report_type_code` filter narrowing correctly, and the full 3-branch `saved_report_views`
  visibility matrix with a genuine non-owner tenant member persona), `git:check-paths` (clean, 7
  files checked), `security:check`, and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-FOURTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  Cluster 6 (`platform-intelligence-reports`) remains `IN_PROGRESS`: 20/30 call sites closed. Still
  open: `server/queries/scheduled-report.ts` (4), `server/queries/supreme-tenants.ts` (1),
  `server/queries/tenant-dashboard.ts` (5) — next up under the same "lanjut sampe siap launching"
  mandate. Plus cluster 7 (16 call sites) after that.

- 2026-09-13 — Ø1-query-layer cluster 6 (`platform-intelligence-reports`) batch 4 of 4 closed
  (this commit), continuing the same "lanjut sampe siap launching" mandate. Closes the LAST 10
  call sites of this cluster across `server/queries/scheduled-report.ts` (4: `listScheduledReports`,
  `getScheduledReportById`, `listScheduledReportRecipients`, `listScheduledReportRuns`),
  `server/queries/supreme-tenants.ts` (1: `listSupremeTenants`), and
  `server/queries/tenant-dashboard.ts` (5: `listTenantDashboards`, `getTenantDashboardById`,
  `listTenantDashboardVersions`, `getTenantDashboardVersionById`, `listDashboardWidgets`) — 30/30
  cumulative for the cluster, which is now **FULLY DONE**. New migration
  `20260913040000_close_o1_query_layer_cluster6_batch4_scheduled_reports_dashboards.sql` adds 10
  new `app.*`/`public.*` Option-2 wrapper pairs (20 functions), ALL SECURITY INVOKER, zero actor
  parameter — every real call site of all 10 TS functions uses `createSupabaseServerClient()` only.
  Two grant/RLS shapes: (1) 6 tables (`scheduled_reports`/`scheduled_report_recipients`/
  `scheduled_report_runs`/`tenant_dashboards`/`tenant_dashboard_versions`/
  `tenant_dashboard_widgets`) — a tenant-membership predicate WITH an explicit
  `OR is_supreme_admin()` disjunct, RULE B re-verified live (exactly one `create policy`, no later
  `alter policy`, for all 6); (2) `app.list_supreme_tenants` over `app.tenants` — NO explicit
  `is_supreme_admin()` disjunct at the policy level (`tenants_select_own_tenant`'s CURRENT text,
  re-verified live post its own `20260730560000` `alter policy`:
  `has_active_tenant_membership(id) AND NOT actor_holds_customer_user_layer(id)`). This migration's
  own recon flagged `list_supreme_tenants` for "extra scrutiny" and suggested a more cautious
  SECURITY DEFINER design with an in-function `is_supreme_admin()` check; independently re-derived
  (and confirmed via this query file's own pre-existing module-header comment) that SECURITY
  INVOKER with zero actor param is correct and sufficient, since `app.has_active_tenant_membership`'s
  own current body already returns true for ANY `tenant_id` whenever the caller is a Supreme
  Admin — a disclosed, deliberate departure from the recon's own more cautious suggestion,
  documented at length in the migration's own header. Every 0-or-1-row lookup declared
  `returns setof app.<table>`, never a bare composite. RULE A does not apply to any of the 10
  functions in this batch: none takes an actor parameter.
  A real, independently-caught db-test bug was found and fixed during this pass's own fixture
  authoring: an early draft's `app.scheduled_report_runs` INSERT omitted the table's own NOT NULL
  `occurrence_at` column (added by a later migration,
  `20260802060000_harden_intelligence_batch1_tier_c_review_fixes.sql`, not present in the table's
  original `CREATE TABLE`) — caught immediately by the insert's own NOT NULL violation, fixed by
  adding `occurrence_at` to the fixture INSERT. Re-verified with a full `pnpm run db:test` run
  afterward, ALL PASSED.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only pre-existing
  warnings), the 6,024-test unit suite (3 test files converted from `.from()`-mocking to
  `.rpc()`-mocking: `scheduled-report.test.ts`, `supreme-tenants.test.ts`,
  `tenant-dashboard.test.ts`), `git:check-paths` (clean), `security:check` (clean), a full
  `pnpm run db:test` (`ALL PASSED`, 533 migrations / 276 db-test files, including the new
  cluster-6-batch-4 db-test file: ordering-fidelity proofs for all 9 SHAPE 1 functions, a full
  5-persona visibility matrix — owner, a real non-owner tenant member proving tenant-wide not
  owner-scoped visibility, a customer_user-layer principal denied despite membership, a
  cross-tenant admin denied, a Supreme Admin with ZERO membership admitted via the explicit
  policy-level disjunct — across both families including the TWO-LEVEL EXISTS join for
  `tenant_dashboard_widgets`, and a dynamic pagination proof for `app.list_supreme_tenants` that
  computes its own expected page count from a live raw count rather than assuming a fixed global
  tenant total across the shared full-suite database's 267+ other tenant-provisioning db-test
  files), and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-FIFTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **Cluster 6 (`platform-intelligence-reports`) is now FULLY DONE: all 30 call sites closed.**
  Remaining: cluster 7 (`page-level-direct-reads`, 16 call sites), not yet started — next up under
  the same "lanjut sampe siap launching" mandate.

- 2026-09-14 — Ø1-query-layer cluster 7 (`page-level-direct-reads`), the FULL cluster, closed in
  one commit, continuing the same "lanjut sampe siap launching" mandate. **This is the LAST
  cluster of the entire Ø1-query-layer defect.** Unlike every prior cluster (all `server/queries/
  *.ts`), every one of this cluster's 10 broken `.from()` reads is embedded DIRECTLY in a Server
  Component `page.tsx` file across 6 files: `hris/employees/[masterRecordId]/page.tsx` (2:
  `files`, `org_units`), `hris/positions/[positionId]/page.tsx` (2: `org_units`,
  `employee_position_assignments`), `hris/positions/bulk-reassign/page.tsx` (1: `org_units`),
  `hris/positions/page.tsx` (1: `org_units`), `hris/recruitment/applications/[applicationId]/
  page.tsx` (1: `job_offers`), `operations/warehouses/[warehouseId]/locations/page.tsx` (1:
  `warehouse_locations`), `procurement/approvals/[stepId]/page.tsx` (2: `approval_request_steps`,
  `approval_requests`). New migration
  `20260913050000_close_o1_query_layer_cluster7_page_level_direct_reads.sql` adds 7 new
  `app.*`/`public.*` Option-2 wrapper pairs (14 functions) — the 5 `org_units` call sites
  (functionally identical flat picker lists) share ONE new function
  (`app.list_org_units`), a disclosed implementation choice matching the recon's own suggestion.
  Grant/RLS shapes, each independently re-derived: `app.list_files_for_record` (SECURITY DEFINER,
  mirrors `app.list_files_for_tenant`'s per-row `app.authorize_file_access` audit-log composition
  exactly, scoped by `(tenant_id, record_type, record_id)`); `app.list_org_units` (SECURITY
  INVOKER, RLS excludes `customer_user`-layer, domain-agnostic — "any active tenant member",
  matching all 5 call sites' own access guards regardless of domain); `app.list_position_
  incumbents` (SECURITY DEFINER, HRS:View + `app.has_view_personal_data` masking, mirrors the
  CURRENT post-lineage-column-fix bodies of `app.get_employee_current_assignment`/`app.get_
  employee_position_assignment_history` exactly, including projecting the table's own full
  CURRENT 24-column shape rather than assuming any column is grantable); `app.get_job_offer_for_
  application` (SECURITY INVOKER — a DELIBERATE DEPARTURE from the recon's own suggested
  SECURITY-DEFINER-plus-`can_view_job_offer` design, since `app.job_offers`' own RLS is STRICTLY
  BROADER than `can_view_job_offer`'s HRS:View-first branch — every HRS:View holder is already an
  active tenant member); `app.get_warehouse_location` (SECURITY DEFINER, mirrors `app.get_
  warehouse_location_deactivation_impact`'s own OPS:View + `can_access_record` scope chain
  exactly); `app.get_approval_request_step` (SECURITY INVOKER, full-row grant, the same
  already-proven-safe EXISTS-join RLS shape `app.list_approval_request_steps` established in
  cluster 6 batch 1); `app.get_approval_request_by_id` (SECURITY INVOKER — a second DELIBERATE
  DEPARTURE from the recon's own suggested design, since the suggested `app.check_approval_
  request_authority` helper was ALREADY independently found stale by cluster 0 batch 3 relative
  to this table's own CURRENT RLS predicate; column-restricted grant, `ended_reason` cast to null
  in its correct 13th-of-16 physical position).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only pre-existing
  warnings), the 6,046-test unit suite (6 query modules extended with new function coverage:
  `document.ts`, `org-hierarchy.ts`, `position.ts`, `recruitment.ts`, `bin-racking.ts`,
  `approval.ts`, each with matching test-file additions), `git:check-paths` (clean),
  `security:check` (clean), a full `pnpm run db:test` (`ALL PASSED`, 534 migrations / 277
  db-test files, including the new cluster-7 db-test file: a 5-persona sweep — an HRS:View +
  OPS:View staff member via a real role assignment, a plain member with no special role, a
  customer_user-layer principal, a zero-membership Supreme Admin, and a cross-tenant actor in a
  second tenant — across all 7 new functions; a genuine masking proof for both `app.list_
  position_incumbents` (`reason_note`/`decided_reason` nulled for the HRS:View-only persona
  despite real non-null values written to the fixture row, unmasked for the Supreme Admin via
  `app.has_view_personal_data`'s own `is_supreme_admin` bypass) and `app.get_approval_request_
  by_id` (`ended_reason` nulled despite a real non-null value written)), and a real `next build`.
  A real, independently-caught bug was found and fixed during this pass's own fixture authoring:
  an early draft used `location_type='zone'` for a `warehouse_locations` fixture row, which is
  not one of the 6 values `warehouse_locations_location_type_check` actually permits
  (`rack`/`shelf`/`floor`/`staging`/`dock`/`bin`) — caught immediately by the insert's own CHECK
  violation, fixed by using `'floor'`. A second, unrelated finding during this pass's own
  full-suite verification: a transient failure in the PRE-EXISTING, unrelated
  `commercial-dashboard.sql` (its own `"due_today"` activity-bucket assertion, sensitive to
  `current_date` at the exact moment `db:test` happened to run across a real midnight boundary,
  2026-09-13 into 2026-09-14) was independently reproduced by stashing every one of this pass's
  own changes and re-running the full suite against the unmodified prior commit — confirming the
  failure was never caused by this batch, before restoring the stash and re-running to a clean
  ALL PASSED.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-SIXTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  **Cluster 7 (`page-level-direct-reads`) is now FULLY DONE: all 10 call sites closed. The entire
  CG-AUDIT-2026-09-02 O1-query-layer remediation (all 8 clusters, 0 through 7 — every broken
  `.from()`/direct-table read against an `app.*` table across both `server/queries/*.ts` and
  `page.tsx` files) is now FULLY DONE.**
- 2026-09-14 — A1 + A2 closed together (this commit), per the audit's own §6 "Remediation, in
  dependency order" step 3 ("Tenant shell + cross-module navigation + landing page; tenant
  provisioning, user invitation, role creation/assignment, master-data entry") and the Product
  Charter's own §41 MVP Must-Have list. Both findings shared one root cause: every mutation this
  step needed (`provisionTenant`, `inviteUser`, `createRole`/`createRoleVersion`/
  `setRoleVersionPermissions`/`publishRoleVersion`/`assignRole`/`revokeRoleAssignment`,
  `createOrgUnit`/`moveOrgUnit`/`renameOrgUnit`/`setOrgUnitStatus`) already existed, fully
  implemented and tested, with zero callers anywhere in the product — this was a UI-and-missing-
  read-RPC gap, not new business logic.
  **A1** (`components/domain/tenant-portal-nav.tsx`, a shared client nav mirroring the pre-existing
  `customer-portal-nav.tsx` pattern): 14 of 16 tenant-internal module layouts
  (`operations`/`finance`/`hris`/`procurement`/`tickets`/`helpdesk`/`knowledge-base`/`analytics`/
  `automation-rules`/`integrations`/`reports`/`dashboards`/`saved-views`/`scheduled-reports`) were
  bare `<TenantMain>` pass-throughs with NO access check and NO chrome at all — upgraded to the
  same guard-then-chrome shape `admin`/`commercial` already established, each reusing the exact
  access resolver its own pages already call (`resolveTicketAccessForRequest` for
  tickets/helpdesk/knowledge-base, `resolveCommercialAccessForRequest` — genuinely domain-agnostic,
  "any active tenant member" — for the other 8, each module's own dedicated resolver otherwise).
  `admin`/`commercial` kept their own existing in-module submenus, with the new cross-module
  switcher added as a second header row. New `app/(tenant)/[tenantSlug]/page.tsx` (no `page.tsx`
  existed at the bare tenant root at all — a confirmed live 404) is a real Home landing page: a
  quick-links grid into every module plus a genuine "pending approvals" summary via the pre-existing
  `listPendingApprovalStepsForActor` (the one piece of the Product Charter's own TNT-HOM-001 "Internal
  Home Dashboard" spec with an existing, tested, cross-domain read model behind it already — a full
  role-based KPI/widget dashboard has no aggregation layer built yet and stays explicitly out of this
  slice's scope, not faked here). `app/(public)/login/actions.ts`'s own redirect target was hardcoded
  to `/{slug}/admin` for every tenant member regardless of layer — since `resolveTenantAdminAccess`
  requires `tenant_admin` specifically, every ordinary `org_user` was landing straight into a 403 on
  their very first post-login page load; changed to redirect to the new Home page instead.
  **A2**: `app/(supreme)/supreme/tenants/` gained a create-tenant form (`provisionTenant`, its own
  idempotency key derived deterministically from the slug — `provision-tenant:{slug}` — so an
  accidental double-submit is a genuine no-op, never a duplicate). `app/(tenant)/[tenantSlug]/
  admin/users/` gained an invite-user form — discovered along the way that `inviteUser` alone was
  insufficient: it only links an tenant to an ALREADY-EXISTING Supabase Auth identity (`authUserId`
  is a required parameter, never generated), and repo-wide grep confirmed zero callers anywhere of
  `admin.createUser`/`inviteUserByEmail`/`generateLink`/`signUp()` — so the new `actions.ts` first
  calls `supabase.auth.admin.inviteUserByEmail` (service-role client) to create the identity and send
  the real invite email, then calls `inviteUser` against the id it returns; deliberately does not
  attempt to reconcile "this email already has an Auth identity" (surfaced verbatim rather than
  guessed at, since there is no `getUserByEmail` in the Admin API to safely resolve it).
  `app/(tenant)/[tenantSlug]/admin/roles/` is the largest single piece: discovered that
  `listTenantRoles`/`listPermissionsForModule` (already RPC-backed from the O1 cluster-2 pass) were
  the ONLY read paths that existed — nothing exposed a role's own versions, a version's own bound
  permissions, or who currently holds a role, so a UI built only on the existing write RPCs could
  create data it could never show again after a reload. New migration
  `20260914010000_add_role_permission_management_read_rpcs.sql` adds exactly the 4 missing reads:
  `app.list_role_versions`/`app.list_role_assignments_for_role` (SECURITY INVOKER, no actor
  parameter — `app.role_versions`/`app.role_assignments` both already carry a live RLS policy and an
  `authenticated` grant, current predicate re-verified against its most recent `alter policy`
  — `20260730560000` — before writing this migration, not assumed from the original `20260716105512`
  wording); `app.list_role_version_permissions` (SECURITY DEFINER, RULE A guard — `app.
  role_version_permissions` had `enable row level security` run but repo-wide grep confirmed ZERO
  policy and ZERO `authenticated` grant were ever added for it, so SECURITY INVOKER would return zero
  rows for every real caller; authority predicate manually reproduces `role_versions_select_own_
  tenant`'s own current predicate, the same shape `app.list_permissions_for_module` already
  established for the sibling ungranted table `app.permissions` in cluster 2); `app.
  list_active_tenant_users_for_role_assignment` (SECURITY DEFINER, RULE A guard — added because `app.
  role_assignments.auth_user_id` references `auth.users(id)` directly, a genuinely different value
  from `app.users.id`, a separate surrogate key, and `app.list_portal_users`'s own `returns table`
  projects no such column; a small, single-purpose function was the lower-risk choice over a
  drop+create of an already-shipped, already-db-tested function, matching this schema's own dominant
  one-RPC-per-real-need pattern). A real, independently-caught bug in this same migration: both
  SECURITY INVOKER functions were missing their own `revoke execute ... from public` statement
  (present on the other two, and on every INVOKER precedent this pass's own header cites) — caught by
  `scripts/db-tests/public-api-wrapper-regression.sql`'s own exhaustive "no `public.*` wrapper grants
  a role its `app.*` counterpart does not" check, fixed, and re-verified with a second full
  `pnpm run db:test`, ALL PASSED. `app/(tenant)/[tenantSlug]/admin/organization/` (org-unit
  create/rename/move/activate-deactivate UI) needed no new migration at all — `list_org_units`
  (already `authenticated`-callable from cluster 7) already returns every column; only a new
  `listOrgUnitsFull` projection (full `OrgUnit` instead of the narrow 3-field picker summary
  `OrgUnitSummary` already in use elsewhere) was needed on the TypeScript side.
  Every new privileged Server Action uses the service-role client (all of `provisionTenant`/
  `inviteUser`/the entire role-permission mutation family/the entire org-hierarchy mutation family
  are `service_role`-only per their own migrations' grants) via a `toXxxRpcClient` adapter added to
  each mutation/query module — the same `async (fn, args) => await client.rpc(fn, args)` idiom this
  whole remediation series already established for the thenable-vs-`Promise` mismatch between a real
  Supabase client and this codebase's own hand-written narrow RPC-client interfaces.
  Full Tier A gate suite verified clean across all four pieces: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,053 tests passing — `role-permission.ts` and
  `org-hierarchy.ts` each extended with new function coverage and matching test-file additions), a
  full `pnpm run db:test` (`ALL PASSED`, 535 migrations / 277 db-test files, extending the existing
  `scripts/db-tests/role-permission.sql` with a 4-actor sweep — active tenant member, a
  customer_user-layer principal, a cross-tenant actor, and a genuine RULE A actor-identity-spoofing
  rejection proof — across all 4 new read RPCs), `git:check-paths` (clean), `security:check` (clean),
  and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-SEVENTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
- 2026-09-14 — A7 partially closed (this commit): the first printable document, surat jalan
  (Indonesian delivery note), per the audit's own §6 dependency-ordered remediation step 4 ("the
  printable document set, surat jalan first"). `package.json` genuinely carried zero PDF/print
  library before this pass, confirmed live (grep, not assumed).
  Library choice: `@react-pdf/renderer` (pure JS, pdfkit-based, no headless-browser dependency) --
  the production deployment target is Vercel serverless (confirmed: this repository's own
  `vercel.json`), where a Playwright/Puppeteer-style headless-Chromium approach would risk
  serverless function size/cold-start limits; this repository's only other browser-adjacent
  dependency, `@playwright/test`, is a devDependency for `test:e2e` only, never meant to ship.
  Architecture: `server/documents/surat-jalan-labeled-values.ts` (pure, JSX-free logic —
  `toLabeledValues`, converting an arbitrary JSON object's own keys into a label/value list, real
  unit-tested) + `server/documents/surat-jalan-document.tsx` (the `@react-pdf/renderer` JSX layout,
  a pure presentation component taking an already-assembled plain data object, zero database/RPC
  knowledge) + `server/documents/generate-surat-jalan.server.ts` (assembles that data from three
  already-existing, already-tested read queries — `getShipmentOrder`, `getAccountById`,
  `getResourceAssignmentHistory` for the current vehicle/driver assignment — no new schema, no new
  RPC at all) + a new Route Handler
  (`app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/surat-jalan/route.ts`,
  not a Server Action, since a Server Action cannot return a raw binary HTTP response with a
  `Content-Type`/`Content-Disposition` header — reuses the exact same
  `resolveOperationsAccessForRequest` guard the sibling `page.tsx` already uses) + a "Print surat
  jalan" link wired into the shipment order detail page.
  `consigneeSnapshot`/`cargoServiceSnapshot`/the shipper account's `billingAddress` are rendered as
  a generic label/value list rather than named fields: all three are deliberately unstructured
  JSONB with no fixed schema anywhere in this codebase (confirmed against
  `20260727100000_create_operations_shipment_order.sql`'s own header) — hardcoding specific field
  names would silently drop whatever a caller actually stored.
  Genuinely verified, not merely typechecked: `node --experimental-strip-types` cannot load a
  `.tsx` file's JSX at all (confirmed live, `ERR_UNKNOWN_FILE_EXTENSION`) — a standalone
  `renderToBuffer` smoke test was run by pre-transpiling the component with the TypeScript compiler
  directly, producing a real PDF buffer whose first 5 bytes are the literal `%PDF-` magic bytes.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only pre-existing
  warnings), the unit test suite (6,057 tests passing — a new `surat-jalan-document.test.ts` for
  `toLabeledValues`), `git:check-paths` (clean), `security:check` (clean), and a real `next build`
  (confirms the new route). No migration/db-test change — `db:test` unaffected.
  A real, independently-caught bug was found and fixed during this pass's own test authoring: an
  early draft test asserted `"Contact phone"` for the label derived from `contactPhone`, but the
  implementation's own (correct) Title-Case-per-camelCase-boundary behavior produces `"Contact
  Phone"` — the test's own expectation was wrong, not the code; fixed by correcting the assertion.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-EIGHTH PASS,
  `lockfileSha256` only — `pnpm add @react-pdf/renderer` changed `pnpm-lock.yaml`).
  Still open under A7: invoice, faktur pajak, packing list, POD, and purchase order printables —
  each is now a bounded "one new document template + generator + route" slice over the same
  infrastructure, not a from-scratch build.
- 2026-09-14 — A7 second printable document: Proof of Delivery (POD), built on
  `getEpodCaptureHistory` (OPS-177) — no new schema, no new RPC. Chosen instead of invoice: invoice
  was investigated first, but `server/queries/invoice.ts` has only `listFinanceInvoices` (a bounded
  list) and `getFinanceInvoiceLines`, no single-invoice-by-id read RPC, and no `[invoiceId]` detail
  route exists anywhere — building it would mean a new RPC/migration, out of scope for this slice.
  POD needed none, so it was built first; invoice/faktur pajak remain open with that scoping now
  written down for whoever picks them up next.
  Architecture, mirroring the surat jalan precedent exactly: `server/documents/pod-document.tsx`
  (the `@react-pdf/renderer` JSX layout — POD's data is already flat and strongly typed via
  `EpodCaptureSchema`, so no `toLabeledValues`-style generic label/value transform is needed here)
  + `server/documents/generate-pod.server.ts` (assembles `PodData` from `getShipmentOrder` and
  `getEpodCaptureHistory`, selecting `history.find((c) => c.isLatestVersion)` — the exact same
  "current version" definition `epod-panel.tsx` already uses — returning `null`, the caller's 404,
  when a shipment has no ePOD capture at all yet) + a new Route Handler
  (`app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/pod/route.ts`, identical
  shape to the surat-jalan route) + a "Print POD" link on the shipment order detail page, shown only
  when `epodHistory.length > 0` (no point linking to a route that would 404).
  Deliberately scoped text-only, disclosed in the file's own header comment: `EpodCapture` carries
  `signatureFileId`/`photoFileIds` referencing real captured evidence in `app.files`, but a
  repo-wide grep for `createSignedUrl`/`storage.from(...).download` confirms no signed-download
  capability exists anywhere in this codebase yet — the only hit is the malware-scan job's own
  internal download, never anything user-facing (this is A6's own still-open "wire upload + signed
  download + scanning" scope; only upload and scanning are done). Embedding actual signature/photo
  images is real future work once that exists, not something to fake with an unauthenticated or
  public URL; the document is still genuinely useful as a receiver-identity/timestamp/review-status
  summary without the images, and says so explicitly in its own closing line.
  Genuinely verified, not merely typechecked: the same pre-transpile-then-run technique used for
  surat jalan produced two real PDF buffers (one with full capture data, one with every nullable
  field null and `status: "draft"`), both starting with the literal `%PDF-` magic bytes.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only pre-existing warnings,
  confirmed none of the new files/lines introduced any), the unit test suite (6,057 tests passing,
  unchanged — no pure-logic helper needed extracting this time, so no new test file), `git:check-paths`
  (clean), `security:check` (clean), and a real `next build` (confirms the new `/pod` route
  alongside `/surat-jalan`). No migration/db-test/lockfile change — `db:test` and
  `check-release-freeze` both unaffected.
  Still open under A7: invoice, faktur pajak, packing list, and purchase order printables.
- 2026-09-14 — A6 third piece: signed download for vendor compliance evidence, closing
  the audit's own step-4 wording ("wire upload + signed download + scanning") for that
  one record type. Upload and scanning were already wired by an earlier pass; signed
  download never was, for ANY record type in this codebase -- confirmed by a repo-wide
  grep for `createSignedUrl`/`storage.from(...).download` finding only the malware-scan
  job's own internal download, never anything user-facing (the same gap this session's
  A7 POD document disclosed and deliberately worked around rather than faked).
  Why not simply reuse the existing `app.access_vendor_compliance_document_evidence`:
  that RPC already accepts `p_access_type='signed_url_issued'` and already runs the
  right authorization (PRC:Download + `app.authorize_vendor_evidence_file_access`'s
  malware-scan/classification gate), but by deliberate prior design (Finding A,
  `20260814000000_harden_storage_signed_url_audit_findings.sql`) it can never return
  `storage_path` -- `app.files.storage_path` carries no column grant to `authenticated`
  at all, and that RPC is granted to `authenticated`. Minting a signed URL genuinely
  needs the raw storage key, so the fix is a new, narrowly-scoped, `service_role`-only
  sibling RPC that performs the identical authorization dance and only returns
  `storage_path`/`bucket_id` once granted.
  New migration `20260914020000_a6_vendor_compliance_signed_download.sql`:
  `app.access_vendor_compliance_document_evidence_for_download` (service_role only,
  never authenticated/anon) plus its required `public.*` PostgREST pass-through wrapper
  (`app` is not exposed to PostgREST at all — confirmed via `supabase/config.toml`'s own
  `schemas = ["public", "graphql_public"]` — so every RPC callable from application code
  needs a matching `public.*` wrapper, the standing convention
  `20260826000000_create_public_api_data_wrappers.sql` established and
  `scripts/db-tests/public-api-wrapper-regression.sql` enforces exhaustively, catalog-
  derived, every externally-callable `app.*` function, every run). Deliberately NOT a
  refactor sharing a body with the existing RPC across the authenticated/service_role
  grant boundary: a reviewer reading the new function alone sees its complete grant
  surface without tracing an EXECUTE grant through a second function with a wider grant.
  App layer: `server/contracts/vendor-compliance/vendor-compliance.ts` gained the raw-row
  parse type (`VendorComplianceDocumentEvidenceDownloadSource`, never re-exported past
  the mutation function that parses it) and the public-facing result type
  (`VendorComplianceDocumentSignedDownload`, carries only the already-signed URL, never
  `storage_path`/`bucket_id`). `server/mutations/vendor-compliance.ts` gained
  `getVendorComplianceDocumentSignedDownloadUrl`, which calls the new RPC first and only
  calls `.storage.from(bucketId).createSignedUrl(storagePath, 300)` (5-minute TTL) once
  `accessResult === 'granted'` -- storage_path/bucketId never leave this one function.
  `app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts` gained
  `downloadVendorComplianceDocumentEvidenceAction`, using the service-role client (the
  same `toDocumentClient`-style cast-adapter pattern this file's own
  `initiate_file_upload` caller already established, since this RPC is service_role-only
  for the identical reason). `document-version-panel.tsx` gained a second, independent
  "Get download link" form/button per version row (a second `useActionState`, since two
  independent server actions in one row need two `<form>` elements -- HTML forbids
  nesting) rendering `<a href={signedUrl} target="_blank">` once granted, or the denial
  reason inline once denied, mirroring the existing "View evidence" row's own pattern.
  A genuine, live-reproduced defect found and fixed while writing db-test coverage (not
  merely typechecked): `information_schema.parameters.specific_name` is synthesized as
  `<function_name>_<oid>` and silently clipped to NAMEDATALEN-1 (63) bytes TOTAL --
  for this function's own OID that clips the 55-character function name itself
  mid-word, to `..._for_downloa_<oid>` (missing the final "d"). A first draft of the
  "no storage_path on the metadata_view sibling" exclusion assertion pattern-matched
  `specific_name not like '%_for_download%'`, which can never match the clipped value
  and left the original assertion still failing (live-reproduced: `pnpm run db:test`
  failed with the pre-existing "expected no storage_path" assertion, not a new one).
  Fixed by joining through `information_schema.routines.routine_name` instead, which is
  the real, unclipped name -- applied to both the original exclusion check and the new
  inclusion check for the new function's own return shape.
  `scripts/db-tests/procurement-vendor-compliance.sql` extended (no new file): granted
  (real `storage_path`/`bucket_id='tenant-documents'`)/insufficient_authority (viewer
  lacking PRC:Download)/ISS-2026-146-shaped cross-tenant not-found/denied-not-raised-
  with-storage_path-nulled-once-infected/`app.file_access_logs` recording under
  `access_type='signed_url_issued'`/storage_path-present-in-return-shape coverage for
  the new RPC, plus schema-privilege regression guards (zero anon/authenticated EXECUTE
  on both the `app.*` function and its `public.*` wrapper, unlike its sibling which IS
  granted to authenticated).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only pre-existing
  warnings, confirmed none from this slice), the unit test suite (6,057 tests passing,
  unchanged file count), a full `pnpm run db:test` (`ALL PASSED`, 536 migrations / 277
  db-test files), `git:check-paths` (clean), `security:check` (clean), and a real
  `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-THIRTY-NINTH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both — the new migration file and the extended
  db-test file).
  Still open under A6: ticket-reply attachments and shipment document checklists have
  neither upload nor download wired (the pattern now exists for both); D4's own GUC gap
  (encryption key + a real VirusTotal API key) still fails every scan closed until an
  operator configures both.
- 2026-09-14 — A6, second of the audit's own 3 named deadlocked flows: shipment
  document checklist uploads. Live-confirmed, not assumed, before fixing: the checklist
  upload form (`document-checklist-panel.tsx`) never had a real `<input type="file">`
  at all -- three plain text/number fields (`originalFilename`, `mimeType`, `sizeBytes`)
  fed straight into `app.initiate_file_upload`'s metadata row, with a hardcoded
  `defaultValue={102400}` size. No File object ever existed anywhere in this flow, so
  no bytes could ever be stored and no scan could ever be queued -- the exact
  `malware_scan_status='pending'` forever gap A6 names, now confirmed for this second
  flow specifically (the same header comment on the old action even said so: "No live
  storage backend exists in this sandbox").
  Extracted `lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts` from
  `procurement/compliance/vendors/actions.ts`'s own `storeEvidenceBytesAndEnqueueScan`
  (that file's first real caller of the upload-bytes-then-enqueue-scan sequence) once a
  second, genuinely identical caller needed it -- a third from-scratch copy of
  security-relevant upload+compensate logic risked drift between copies. The vendor-
  compliance file's own function is now a thin same-name wrapper delegating to the
  shared helper (kept so neither of that file's own two call sites needed to change);
  its behavior is unchanged, re-verified by the full test/lint/typecheck/build pass
  below.
  `uploadAndLinkDocumentAction` (shipment-orders `actions.ts`) now reads a real
  `formData.get("file")` (rejecting a missing/empty file up front), derives
  `originalFilename`/`mimeType`/`sizeBytes` from the real `File` object instead of
  operator-typed text, calls the shared helper to store real bytes and enqueue a
  `malware_scan` job, and only links the checklist item to the file once storage
  genuinely succeeded (a storage failure now returns an inline error instead of
  silently linking a checklist item to bytes that were never stored). UI: the three
  fake fields replaced with one real `<input type="file" name="file" required>`,
  mirroring vendor compliance's own identical evidence-upload markup exactly.
  New unit tests: `lib/malware-scan/store-file-bytes-and-enqueue-scan.test.ts` (4
  cases: real upload + enqueue succeeds; upload failure compensates with a soft
  `app.request_file_deletion` and returns an inline error; upload failure where the
  compensating deletion ALSO fails still returns the original error rather than
  throwing; bytes stored successfully but the scan enqueue itself fails still returns
  an inline error, never silently drops the file into an unscanned state).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,061 tests passing, +4 new),
  `git:check-paths` (clean), `security:check` (clean), and a real `next build`. No
  migration/db-test/lockfile change — `db:test` and `check-release-freeze` both
  unaffected.
  Still open under A6: ticket-reply attachments (neither upload nor download wired);
  shipment document checklist and ePOD evidence still lack signed download (the
  pattern from vendor compliance's own signed-download slice is directly reusable);
  ePOD evidence capture's own UI still fabricates a filename/fixed-size File-free
  metadata row (`setEpodEvidenceAction`) -- a separate, larger gap than this slice's
  own scope, since it needs a genuine signature-pad/photo-capture UI, not just a file
  input, disclosed here rather than folded into this bounded fix; D4's own GUC gap
  still fails every scan closed until an operator configures both the encryption key
  and a real VirusTotal API key.
- 2026-09-14 — A6, third and LAST of the audit's own 3 named deadlocked flows:
  ticket-reply attachments. Investigated with a parallel research pass before
  fixing (survey findings preserved in this entry, not just the fix). Live-confirmed
  this flow was actually WORSE than the other two: the UI already had a real
  `<input type="file" multiple>` and the Server Action already extracted real
  `File` objects, and `app.initiate_ticket_attachment_upload` was already
  correctly requester-or-staff-gated -- but `app.reply_to_ticket` itself
  (`20260731270000_harden_ticketing_internal_replayable_review_fixes_hrt295.sql:422`)
  raises `evidence_file_not_scanned` for any attached file whose
  `malware_scan_status` isn't `'clean'`, and since nothing ever stored real bytes
  or enqueued a scan for a ticket attachment, no file could ever reach `'clean'`.
  This meant every real attempt to post a ticket reply with an attachment
  hard-failed today, not merely sat in a silent unscanned limbo like the other two
  flows did before their own fixes.
  Why this needed a new RPC rather than a straight copy of the checklist/vendor-
  compliance fix: `app.initiate_ticket_attachment_upload` is deliberately
  `authenticated`-callable (it carries its own per-ticket requester-or-staff
  authority check inline) and, exactly like the metadata-view vendor-compliance
  RPC, deliberately returns a `storage_path`-less `FileSummary` for that reason --
  `storage_path` still carries no column grant to `authenticated` at all. New
  migration `20260914030000_a6_ticket_attachment_upload_scan.sql` adds
  `app.get_ticket_attachment_storage_path(file_id, actor)` (service_role only) --
  deliberately NOT a re-derivation of the per-ticket authority check (the actor
  already passed it the moment `initiate_ticket_attachment_upload` itself
  succeeded, in the same request); just a plain `uploaded_by_auth_user_id =
  actor` ownership lookup for a file the same actor just staged -- plus its
  required `public.*` wrapper.
  App layer: `server/mutations/ticketing.ts` gained `getTicketAttachmentStoragePath`
  and a new `ticket_attachment_not_found` error code.
  `replyToTicketAction` (`app/(tenant)/[tenantSlug]/tickets/actions.ts`) now
  calls the shared `lib/malware-scan/store-file-bytes-and-enqueue-scan.server.ts`
  helper (this session's own third caller, after vendor compliance and shipment
  checklist) right after each `initiateTicketAttachmentUpload` call, storing
  real bytes and enqueuing a `malware_scan` job before moving to the next file --
  a failed upload OR a failed store still aborts the whole reply before
  `reply_to_ticket` is ever called, preserving the existing "never post with only
  some attachments" invariant. `eslint.config.js`'s `serviceRoleImportGuard`
  gained this file's entry. `ticket-detail-panel.tsx`'s own disclosure text
  updated to no longer claim "no Storage integration exists" (false as of this
  fix) while still honestly disclosing that D4's own GUC gap means every scan
  fails closed until an operator configures real credentials.
  `scripts/db-tests/ticketing-internal.sql` section 17 extended (no new file):
  the uploader gets their own real `storage_path`; a non-uploading actor (even
  ticket staff, who could legitimately stage their OWN attachment but not read
  this one) and a nonexistent file id both get the identical
  `ticket_attachment_not_found`; schema-privilege guards confirm both `anon`
  AND `authenticated` carry zero EXECUTE on the new RPC and its wrapper, unlike
  its `authenticated`-grantable sibling `app.initiate_ticket_attachment_upload`.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,061 tests passing, unchanged
  count), a full `pnpm run db:test` (`ALL PASSED`, 537 migrations / 277 db-test
  files), `git:check-paths` (clean), `security:check` (clean), and a real
  `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-FORTIETH PASS,
  `migrationSetSha256`/`dbTestSetSha256` both).
  This closes all 3 of A6's own named deadlocked flows for real upload+scan.
  Still open under A6: signed download for shipment document checklist, ePOD
  evidence, and ticket attachments (vendor compliance's own signed-download RPC,
  `20260914020000_a6_vendor_compliance_signed_download.sql`, is a directly
  reusable pattern for each -- research this session already scoped the exact
  new-RPC shape for the checklist case: a new `app.authorize_shipment_document_
  evidence_file_access` sibling of `app.authorize_vendor_evidence_file_access`,
  gated by the currently-unused `'OPS', 'Download'` permission action code);
  ePOD evidence capture's own UI (`setEpodEvidenceAction`) still fabricates a
  filename/fixed-size File-free metadata row, a separate and larger gap since it
  needs a genuine signature-pad/photo-capture UI, not just a file input; D4's own
  GUC gap still fails every scan closed until an operator configures both the
  encryption key and a real VirusTotal API key.
- 2026-09-14 — F4 (`has_active_tenant_membership` performance) investigated in
  depth via a parallel research pass; disposition unchanged (`DEFERRED_LARGE`),
  but now backed by concrete findings rather than the audit's own summary alone.
  The function's own three internal lookups (`app.tenant_user_identities`,
  `app.users`, `app.principal_memberships`, `app.support_access_grants`/
  `app.support_access_sessions`) are ALL already covered by existing unique
  constraints/indexes -- there is no missing index to add anywhere in the
  function's own dependency chain. The real cost driver is that Postgres never
  inlines a `SECURITY DEFINER` function, so every RLS policy clause calling it
  is an opaque, single-argument boolean the planner can never decompose into an
  index condition against the protected table's own `tenant_id` column -- when a
  query supplies no tenant filter and relies on RLS alone, the result is a full
  `Seq Scan` with the function evaluated as a row-by-row `Filter`, exactly the
  audit's own reproduced `explain analyze` output shows. Confirmed this is
  directionally honest, not overstated: 1,944+ call sites and 267+ RLS policy
  clauses reference it across the migration history. Two things would actually
  fix the root cause -- rewriting ~267+ RLS policy clauses to a sargable form
  (large by blast radius, needs per-table isolation-test re-verification) or
  adding trigger-maintained caching underneath the single function gating
  tenant isolation for the entire schema (small in file count but carries
  stale-access-window risk this session cannot adequately verify at this
  scale) -- both genuinely architecture-level, matching the backlog's own
  "needs a load-bearing-function redesign" framing. No code changed for this
  finding; recommendation is to leave it deferred rather than attempt a partial
  fix that does not address the measured pathological case.
- 2026-09-14 — A7 third printable document: purchase order, built on a parallel
  research pass that confirmed it needed zero new backend, unlike invoice/faktur
  pajak (no single-invoice-by-id read exists) or packing list (a real, tested
  backend domain, `server/queries/wms-packing.ts`, but with zero pages/actions
  anywhere in `app/` -- nothing for a user to have ever created a packing task
  through, so nothing would exist to print in the live system).
  Architecture, mirroring the surat-jalan/POD precedent exactly:
  `server/documents/purchase-order-document.tsx` (the `@react-pdf/renderer` JSX
  layout -- PO data is already flat/typed via `PurchaseOrderSchema`, no generic
  label/value transform needed) + `server/documents/generate-purchase-order.server.ts`
  (assembles the data from `getPurchaseOrder` + `listPurchaseOrderLines` +
  `getVendorProfile` + `listVendorAddresses` -- all already-existing,
  already-tested reads, zero new RPC) + a new Route Handler
  (`app/(tenant)/[tenantSlug]/procurement/purchase-orders/[purchaseOrderId]/print/route.ts`)
  + a "Print purchase order" link on the detail page.
  `costMasked` (PRC-260's own access rule 26: a viewer without `PRC:View cost`
  authority never sees amounts/payment terms/commercial terms) is honored
  exactly the way `purchase-order-detail-panel.tsx` already renders it
  on-screen -- "Masked" text, never a blank or a substituted zero. Vendor
  address picks the vendor's own `legal` address (falling back to `billing`,
  then any address on file, then "—") -- `app.vendor_addresses` carries no
  single "primary" flag.
  Genuinely verified, not merely typechecked: the same pre-transpile-then-run
  technique used for surat jalan/POD produced two real PDF buffers (one with
  full line-item/cost data, one with `costMasked: true` and every nullable
  field null), both starting with the literal `%PDF-` magic bytes.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,061 tests passing, unchanged
  count -- no pure-logic helper needed extracting this time), `git:check-paths`
  (clean), `security:check` (clean), and a real `next build` (confirms the new
  `/print` route). No migration/db-test/lockfile change — `db:test` and
  `check-release-freeze` both unaffected.
  Still open under A7: invoice, faktur pajak, and packing list printables.
- 2026-09-14 — A6: signed download for shipment document checklist evidence,
  extending the vendor-compliance signed-download pattern
  (`20260914020000_a6_vendor_compliance_signed_download.sql`) to
  `app.shipment_document_checklist_items`. Upload+scan for this record type was
  already wired by an earlier pass this session, so evidence a reviewer
  approves/rejects is real, malware-scanned bytes; there was simply no way to
  ever fetch those bytes back out again.
  New migration `20260914040000_a6_shipment_document_checklist_signed_download.sql`
  adds `app.authorize_shipment_document_evidence_file_access` (a narrowly-scoped
  sibling of `app.authorize_vendor_evidence_file_access` -- identical
  malware-scan/deleted-file/restricted-classification gates; the record-scope
  gate is deliberately omitted since the caller already independently verifies
  module authority plus the parent shipment order's own scope) and
  `app.access_shipment_document_checklist_item_evidence_for_download`
  (service_role only), gated on `app.evaluate_permission(..., 'OPS', 'Download')`
  -- the permission action code seeded since `20260716103445_create_roles_
  permissions.sql` but, confirmed live across every migration, never once
  actually checked by any RPC until now, a ready-made seam exactly like
  `'PRC', 'Download'` was before the vendor-compliance evidence RPCs started
  using it -- plus the same `app.can_access_record` record-scope check its
  siblings `app.link_document_to_checklist_item`/
  `app.review_document_checklist_item` already use. No tenant holds
  `OPS:Download` on any role by default; granting it is a tenant-admin action
  via `/admin/roles/`, not something a migration pre-populates.
  One deliberate improvement over those same two pre-existing sibling
  functions (both UNCHANGED by this migration -- Part C, no applied migration
  edited): they raise their `evaluate_permission`-driven `insufficient_authority`
  (which interpolates the real `tenant_id`) before ever checking whether the
  actor has any membership at all in the checklist item's own tenant -- the
  exact ISS-2026-146 tenant-id-disclosure defect class this repository's many
  `harden_tenant_id_disclosure_*` migrations already fixed elsewhere. The new
  function folds that membership check into its own initial not-found branch
  instead, so it does not reintroduce a known, already-fixed-elsewhere defect
  in brand-new code -- disclosed in the migration's own header, not backported
  into the two older functions (a separate, out-of-scope finding).
  App layer: `server/contracts/document-requirement/document-requirement.ts`
  gained the parsed RPC-row schema plus a public-facing
  `ShipmentDocumentChecklistItemSignedDownload` type (only `signedUrl`/
  `originalFilename`/result/reason -- storage_path and bucket_id never leave
  the mutation function). `server/mutations/document-requirement.ts` gained
  `getShipmentDocumentChecklistItemSignedDownloadUrl`, which calls the RPC and
  mints a 5-minute signed URL via `.storage.from("tenant-documents")
  .createSignedUrl(...)` only once `accessResult === "granted"`, mirroring the
  vendor-compliance mutation exactly. `downloadChecklistItemEvidenceAction`
  (shipment-orders `actions.ts`) and a new "Get download link" form in
  `document-checklist-panel.tsx` (per checklist item, gated on `item.fileId`)
  wire it into the UI, rendering the signed link on grant or a denial badge
  with the real `accessReason` otherwise.
  `scripts/db-tests/operations-document-requirement.sql` gained a new
  top-level section: insufficient_authority before `OPS:Download` is granted
  (via a real role-version publish + the A3 publish-migrates-assignments fix,
  no raw `assign_role` re-call needed) and denied afterward for a view-only
  actor; the granted path's real `storage_path`/`bucket_id`/`original_filename`;
  an ISS-2026-146-shaped `document_checklist_item_not_found` for a
  zero-membership cross-tenant actor; denied-not-raised with
  `storage_path`/`bucket_id` nulled once the file is marked infected;
  `document_checklist_no_linked_file` for a freshly-pinned, never-linked
  checklist item; an `app.file_access_logs` audit-trail count proof; and
  schema-privilege guards confirming both `anon` and `authenticated` carry
  zero EXECUTE on either new function or its `public.*` wrapper.
  A first `pnpm run db:test` attempt caught a real, self-inflicted bug: the new
  `app.authorize_shipment_document_evidence_file_access` was granted `EXECUTE`
  to `service_role` but its matching `public.*` wrapper was initially omitted
  -- `scripts/db-tests/public-api-wrapper-regression.sql`'s own exhaustive,
  catalog-derived check (every `app.*` function holding any real grant needs a
  `public.*` wrapper, not just ones deemed "externally callable") caught it
  immediately rather than letting it ship silently. Fixed by adding the
  wrapper, matching `app.authorize_vendor_evidence_file_access`'s own
  invoker-mode security shape exactly (no `security definer`, since the
  underlying `app.*` function is itself invoker-mode and the wrapper-regression
  suite separately asserts a wrapper's security mode never differs from its
  `app.*` counterpart); re-verified clean.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,061 tests passing, unchanged
  count), a full `pnpm run db:test` (`ALL PASSED`, 538 migrations / 277
  db-test files), `git:check-paths` (clean, 8 files checked), `security:check`
  (clean), and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-FORTY-FIRST
  PASS, `migrationSetSha256`/`dbTestSetSha256` both).
  Still open under A6: signed download for ePOD evidence and ticket
  attachments (the same reusable pattern applies to both); ePOD evidence
  capture's own UI (`setEpodEvidenceAction`) still fabricates a
  filename/fixed-size File-free metadata row, a separate and larger gap since
  it needs a genuine signature-pad/photo-capture UI, not just a file input;
  D4's own GUC gap still fails every scan closed until an operator configures
  both the encryption key and a real VirusTotal API key.
- 2026-09-14 — A6: signed download for ticket-reply attachments -- the third
  and final flow of the vendor-compliance/shipment-checklist/ticket-attachment
  trio to gain signed download. Upload+scan for this record type was already
  wired (`20260914030000_a6_ticket_attachment_upload_scan.sql`), so an
  attachment posted to a reply is real, malware-scanned bytes; there was
  simply no way to ever fetch it back out again --
  `ticket-detail-panel.tsx` did not even render an attachment's filename,
  confirmed live before writing this migration.
  Unlike the vendor-compliance/shipment-checklist pair, this record type had
  no unused permission-action seam to reach for (`OPS:Download` was exactly
  that seam for shipment checklists). New migration
  `20260914050000_a6_ticket_attachment_signed_download.sql` instead reuses
  two primitives ticket reads already depend on:
  `app.can_access_ticket` (staff OR the ticket's own requester OR an active
  watcher -- the SAME baseline `app.list_ticket_messages`/`app.list_customer_
  ticket_messages` already apply) and the linked `ticket_messages` row's own
  `visibility` column (`public` vs. `internal`-staff-only -- the SAME
  predicate those two functions already filter message rows by). A
  helpdesk-channel Supreme-Admin-only hard block mirrors
  `app.list_ticket_messages`'s own identical restriction. No new authority
  concept was introduced for this slice.
  `app.authorize_ticket_attachment_evidence_file_access` is a narrowly-scoped
  sibling of the vendor-compliance/shipment-checklist pair (identical
  malware-scan/deleted-file/classification gates, record-scope omitted since
  the caller already verifies `can_access_ticket` + message visibility).
  `app.access_ticket_attachment_evidence_for_download` (service_role only)
  resolves the file, its parent ticket, and the ONE `ticket_messages` row
  that actually references the file id in its `attachment_file_ids` array --
  a file staged but never attached to any message (e.g. a reply that failed
  after staging) is refused with a new, distinct `ticket_attachment_not_linked`
  rather than being silently granted or folded into `ticket_attachment_not_found`.
  Deliberately NOT the `app.actor_holds_customer_user_layer` exclusion
  `app.list_ticket_messages` also applies: that exclusion exists so a
  customer-layer caller cannot consume the STAFF-facing listing wholesale --
  this function is not a listing, it authorizes exactly one already-known
  file id against exactly one already-resolved message's own visibility, so
  the same protection falls out of the visibility gate naturally. This also
  means the one RPC is usable, unmodified, by a future customer-portal-side
  download action too (`customer-ticket-detail-panel.tsx` has no attachment
  UI at all today, confirmed live -- out of scope for this migration, which
  wires the staff-facing panel only).
  App layer: `server/contracts/ticketing/ticketing.ts` gained the parsed
  RPC-row schema plus a public-facing `TicketAttachmentSignedDownload` type
  (only `signedUrl`/`originalFilename`/result/reason, storage_path/bucketId
  never leave the mutation function). `server/mutations/ticketing.ts` gained
  `getTicketAttachmentSignedDownloadUrl`, mirroring
  `getShipmentDocumentChecklistItemSignedDownloadUrl` exactly, plus the new
  `ticket_attachment_not_linked` error code.
  `downloadTicketAttachmentAction` (`app/(tenant)/[tenantSlug]/tickets/
  actions.ts`) and a new "Get download link" control per attachment in
  `ticket-detail-panel.tsx`'s `MessageBubble` wire it into the UI. No read
  RPC in this app projects an attachment's original filename today, and
  widening either hardened, privacy-critical `list_ticket_messages`/
  `list_customer_ticket_messages` function was judged out of scope for this
  slice (larger blast radius on already-carefully-hardened code, CPL-325's
  own file-privacy fix among it) -- so each attachment renders as a generic
  "Attachment N" button; the REAL original filename appears in the link text
  only once a download is actually granted, mirroring
  `document-checklist-panel.tsx`'s own established pattern.
  `scripts/db-tests/ticketing-internal.sql` gained a new top-level section 18:
  a requester and staff both granted a real storage_path/bucket_id/
  original_filename for a public-visibility message's attachment; the
  requester denied (folded into `ticket_attachment_not_found`) for an
  internal-only staff note's attachment, staff still granted; a bystander
  denied, then granted once a real watcher (but still denied for the
  internal-only attachment); a cross-tenant identity denied; an orphan file
  refused with the distinct `ticket_attachment_not_linked`; the malware-scan
  gate underneath still denies-not-raises an infected file with
  storage_path/bucket_id nulled; a real `app.file_access_logs` audit-trail
  count proof; and schema-privilege guards (`anon`/`authenticated` hold zero
  EXECUTE on either new function or its `public.*` wrapper).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,061 tests passing, unchanged
  count), a full `pnpm run db:test` (`ALL PASSED`, 539 migrations / 277
  db-test files), `git:check-paths` (clean, 8 files checked), `security:check`
  (clean), and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-FORTY-SECOND
  PASS, `migrationSetSha256`/`dbTestSetSha256` both).
  **This closes A6's own "signed download" gap for all 3 of the audit's own
  named deadlocked flows.** Still open under A6: signed download for ePOD
  evidence (same reusable pattern, but ePOD evidence capture's own UI is a
  separate, larger gap needing a genuine signature-pad/photo-capture UI, not
  just wiring); customer-portal-side ticket-attachment download UI (the new
  RPC is ready, `customer-ticket-detail-panel.tsx` still has no attachment UI
  at all); D4's own GUC gap still fails every scan closed until an operator
  configures both the encryption key and a real VirusTotal API key.
- 2026-09-14 — E5 (installation-evidence half only): "Telematics: device can
  never reach `installed` (blocked by A6)". Scoped by a parallel research
  pass before writing any code: `app.record_gps_device_installation`
  (ATW-226B, `20260729350000_create_advanced_tms_device_installation_
  evidence.sql`) and its own db-test
  (`scripts/db-tests/advanced-tms-device-installation-evidence.sql`, 326
  lines) already fully build and exercise the evidenced-installation RPC end
  to end -- malware-scan gating, OPS:Edit authority (reused from
  `app.transition_gps_device_status`), the ATW-031/ISS-2026-028 bypass
  closure (the generic status-transition control cannot reach `installed`
  directly). The DB layer needed zero new RPC.
  The actual, concrete blocker: no real migration ever registered the
  `gps_device_installation` document type. `app.resolve_document_type_
  definition` (PLT-128, called by every `app.initiate_file_upload`) raises
  `document_type_not_configured` whenever no tenant has ever published a
  `document:<code>` config_object for that type -- and a tenant can never
  publish one until the matching `app.config_types` catalogue row exists.
  Confirmed via repo-wide grep before writing the fix: SIX different db-test
  fixtures (`advanced-tms-device-installation-evidence.sql`,
  `advanced-tms-canonical-telemetry-arbitration.sql`,
  `advanced-tms-geofence-route-deviation-signals.sql`,
  `advanced-tms-gps-gateway-ingestion.sql`,
  `advanced-tms-wms-integrated-verification.sql`, and a related-but-different
  code in `advanced-tms-claim-incident-operations.sql`) each independently
  call `app.register_document_type('gps_device_installation', ...,
  'DOC', ...)` against their own disposable databases, but zero real
  migration ever did the same -- every real tenant's first upload attempt
  would have failed immediately, before its own per-tenant publish step.
  Also confirmed: no Server Action or UI anywhere ever called the
  upload+store+scan sequence at all (`fleet-panel.tsx` rendered a dead-end
  message instead), even though the typed mutation wrapper
  (`recordGpsDeviceInstallation`) already existed with zero callers.
  New migration
  `20260914060000_register_gps_device_installation_document_type.sql`
  mirrors `20260901020000_register_loyalty_reward_terms_document_type.sql`'s
  own precedent exactly: two additive, idempotent catalogue inserts
  (`app.document_types`/`app.config_types`), `owner_primitive_code='DOC'`
  matching every one of those six db-test fixtures' own identical call
  byte-for-byte (the generic Document and File Engine primitive, like
  `epod`/`pod`, not a single business-module owner like `ticket_attachment`'s
  `TKT`).
  App layer: `server/mutations/gps-device-installation.ts` gained
  `uploadGpsDeviceInstallationEvidenceFile`, calling the shared
  `app.initiate_file_upload` (PLT-128) primitive directly (service_role
  only, `record_type='gps_device'`/`document_type_code='gps_device_
  installation'` fixed server-side) -- unlike the ticket/shipment-checklist
  `*_upload` RPCs built earlier this session, this raw primitive already
  returns the file's real `storage_path` (it is service_role-only itself),
  so no separate storage-path lookup RPC was needed before
  `storeFileBytesAndEnqueueScan`.
  `recordGpsDeviceInstallationAction`
  (`app/(tenant)/[tenantSlug]/operations/fleet/actions.ts`) wires
  upload -> `storeFileBytesAndEnqueueScan` -> `recordGpsDeviceInstallation`
  (the latter is `authenticated`-callable and re-checks OPS:Edit itself via
  the reused `app.transition_gps_device_status` gate, so it runs through the
  ordinary RLS-scoped client like every other write in that file).
  `fleet-panel.tsx`'s `DeviceRow` gained a real "Record installation" upload
  form (evidence photo + technician name + optional notes) replacing the
  previous dead-end message, gated on the device's real CURRENT
  `device_vehicle_assignment_id` (fetched fresh via the existing
  `listDeviceVehicleAssignmentHistory` query in `page.tsx` -- `GpsDevice`
  itself carries no such field, since `app.gps_devices` and
  `app.device_vehicle_assignments` are deliberately separate,
  append-only-history tables).
  `scripts/db-tests/advanced-tms-device-installation-evidence.sql` gained a
  regression section proving the migration's own idempotent insert agrees
  byte-for-byte with the fixture's own independent registration call
  (mirroring the loyalty precedent's own identical regression-test shape).
  `server/mutations/gps-device-installation.test.ts` gained 2 new unit tests
  for the upload wrapper.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,063 tests passing, +2 from
  this slice), a full `pnpm run db:test` (`ALL PASSED`, 540 migrations / 277
  db-test files), `git:check-paths` (clean, 9 files checked), `security:check`
  (clean), and a real `next build`.
  `scripts/release/check-release-freeze.ts` amended (HUNDRED-AND-FORTY-THIRD
  PASS, `migrationSetSha256`/`dbTestSetSha256` both).
  E5's own ETA half ("straight-line/40kmh") remains DEFERRED_LARGE, confirmed
  correct by the same research pass: the 40 km/h constant
  (`app.route_planning_default_speed_kmh()`) is an explicitly disclosed
  coarse fallback, reused verbatim across 3+ existing capabilities (route
  planning, route-deviation geofencing, leg-remaining-stop ETA) alongside a
  separate, already-built AI-governed predictive-ETA path -- replacing it
  with a real road-network/traffic-aware calculation is a genuine, separate
  algorithmic undertaking with no relationship to A6's storage/malware-scan
  gap.
- 2026-09-14 — A6: fixed ePOD evidence capture's fabricated-upload gap,
  found via a parallel research pass before writing code. `setEpodEvidenceAction`
  (`app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/actions.ts`)
  previously read two plain TEXT fields (`signatureFilename`/`photoFilename`
  in `epod-panel.tsx`, `<input type="text">`, never a `File` object) and
  called `uploadShipmentDocumentFile` with a HARDCODED `mimeType`
  (`image/png`/`image/jpeg`) and HARDCODED `sizeBytes` (20480/102400) --
  never derived from any real file, and never called
  `storeFileBytesAndEnqueueScan`. No evidence file could ever leave
  `malware_scan_status='pending'`.
  Research confirmed nothing in the schema or RPCs (`app.set_epod_evidence`,
  `app.submit_epod_capture`) structurally requires a signature-pad canvas or
  live camera capture -- both treat `signature_file_id`/`photo_file_ids` as
  ordinary nullable `app.files` references, validated only for
  tenant/record-type/record-id match (at `set_epod_evidence` time) and
  `malware_scan_status='clean'` (at `submit_epod_capture` time). A plain
  `<input type="file">` producing a real `File` satisfies every real
  constraint; a richer capture UX (signature pad, live geolocation/camera)
  is purely later UI polish, not a prerequisite.
  Fix: `epod-panel.tsx`'s two text inputs replaced with real
  `<input type="file" accept="image/*">` fields (`signatureFile`/`photoFile`);
  `setEpodEvidenceAction` now derives `originalFilename`/`mimeType`/
  `sizeBytes` from the real `File` and calls the SAME upload+store+scan
  sequence `uploadAndLinkDocumentAction` already established for checklist
  evidence (`uploadShipmentDocumentFile` then `storeFileBytesAndEnqueueScan`,
  reusing that file's own existing `toShipmentDocumentStoreClient`/
  `toShipmentDocumentBackgroundJobClient` cast helpers -- no new helper
  needed). `latitude`/`longitude`/`capturedAt` are unchanged (already plain,
  schema-compatible scalar inputs). No new RPC or migration -- this was a
  pure app-layer fix.
  **This closes the upload+scan half of A6 for all 4 real evidence-capture
  flows in this codebase** (vendor compliance, shipment document checklist,
  ticket-reply attachments, and now ePOD). ePOD evidence signed download
  remains the one still-open A6 gap, now genuinely just RPC + wiring work
  (the same reusable pattern used 3 times already) with no UI blocker behind
  it anymore.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,063 tests passing, unchanged
  count -- Server Actions in this codebase are not directly unit-tested),
  `git:check-paths` (clean, 2 files checked), `security:check` (clean), and a
  real `next build`. No migration/db-test/lockfile change --
  `check-release-freeze` unaffected.
- 2026-09-14 — A6: wired the customer-portal side of ticket-attachment
  signed download, closing the gap explicitly disclosed as out of scope in
  this session's own earlier ticket-attachment slice
  (`customer-ticket-detail-panel.tsx` had zero attachment UI at all).
  Research confirmed `app.access_ticket_attachment_evidence_for_download`
  (this session's own RPC) needed NO changes to serve this caller: it
  already gates on `app.can_access_ticket` (which a genuine customer
  requester/watcher already satisfies) plus the linked message's own
  `public`/`internal` visibility, and deliberately carries no
  `app.actor_holds_customer_user_layer` exclusion (that exclusion exists
  only on the STAFF listing RPC, to keep a customer-layer caller off
  internal-note visibility wholesale -- this RPC authorizes one
  already-known file id against one already-resolved message's own
  visibility instead, so the same protection already falls out of the
  visibility gate). `attachmentFileIds` was already flowing end-to-end
  through `CustomerTicketMessageRowSchema` -- only the panel's own rendering
  was missing.
  `app/(tenant)/[tenantSlug]/customer-tickets/actions.ts` gained
  `getCustomerTicketAttachmentDownloadLinkAction`, calling the SAME
  `getTicketAttachmentSignedDownloadUrl` mutation wrapper the staff side
  already uses, gated by `resolveCustomerTicketAccessForRequest`.
  `customer-ticket-detail-panel.tsx`'s `MessageBubble` gained a per-attachment
  "Get download link" control mirroring the staff panel's own established
  `AttachmentRow` pattern exactly (a generic "Attachment N" placeholder
  button; the real filename appears in the link text only once granted,
  since no read RPC here projects a filename either).
  Disclosed, not fixed (separate, larger gap, out of scope for this slice):
  `replyToCustomerTicketAction` hardcodes `attachmentFileIds: null` --
  customers cannot attach a file to their OWN reply at all today. This is a
  genuine upload-side gap analogous to the ones already fixed for
  vendor-compliance/shipment-checklist/staff-ticket-attachments, but a
  distinct piece of work (a real file-input reply form on the customer
  portal side) from the download-side gap this slice closed.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,063 tests passing, unchanged
  count), `git:check-paths` (clean, 4 files checked), `security:check`
  (clean), and a real `next build`. No migration/db-test/lockfile change --
  `check-release-freeze` unaffected.
- 2026-09-14 — A7 fourth printable document: invoice, the last of the three
  documents this finding's own entry named as needing new backend RPC work
  (invoice, faktur pajak; packing list separately needs UI/mutation wiring
  first). No single-invoice-by-id read existed before this slice --
  `listFinanceInvoices` was the only invoice query in the codebase.
  New `app.get_finance_invoice(p_invoice_id, p_actor_auth_user_id)` mirrors
  `app.get_finance_invoice_lines`'s CURRENT (hardened) shape byte-for-byte,
  not its original creation-migration shape: SECURITY DEFINER (added by
  `20260810900000_harden_finance_authority_chain_tierc_completeness.sql`)
  with the not-found branch folding `app.has_active_tenant_membership`
  (added by `20260902100000_harden_tenant_id_disclosure_finance.sql`,
  the ISS-2026-146 pattern) so a cross-tenant caller and a nonexistent id
  both raise the same `finance_invoice_not_found`, never leaking which case
  applied. Authority is gated behind a single `FIN:View` predicate via
  `app.check_finance_invoice_authority` -- confirmed by re-reading that
  function's body that, unlike purchase orders' `PRC:View cost` split,
  invoices have no cost-masking concept; a caller either has `FIN:View` for
  the tenant or gets nothing. Plus a matching `public.get_finance_invoice`
  SQL wrapper (verified against the new
  `scripts/db-tests/public-api-wrapper-regression.sql` security-mode-match
  test added earlier this session) and a `server/queries/invoice.ts`
  `getFinanceInvoice` wrapper (handles both plain-row and
  Postgres-composite-array-wrapped return shapes, matching
  `getFinanceInvoiceLines`'s established pattern).
  `server/documents/invoice-document.tsx` + `generate-invoice.server.ts`
  follow the surat-jalan/POD/purchase-order precedent exactly (assembling
  `getFinanceInvoice` + `getFinanceInvoiceLines` + `getAccountById`, all
  already-existing, already-tested reads beyond the one new RPC). The
  totals block needed a correction mid-design: `app.finance_invoices.
  total_amount` is a GENERATED column (`subtotal_amount + tax_amount`) --
  it is NOT reduced by `withholding_tax_amount` (this session's own earlier
  B5 fix), because withholding is cash withheld by the customer at source
  and remitted directly to the tax authority, a separate deduction applied
  only at actual cash collection, never baked into the invoice's own face
  value. The document therefore renders Subtotal/Tax/Total first, and only
  when `withholdingTaxAmount > 0` adds two further lines after Total:
  "Less: withholding tax" and "Net amount due" (`total - withholding`),
  with a footnote about bukti potong certificates -- never folding
  withholding into Total itself.
  No invoice detail page exists in this codebase (unlike surat-jalan/POD/
  purchase-order's own precedents, which print from a detail page) --
  printing wires directly from a new "Print" column on the existing
  invoice list row (`finance/invoices/page.tsx`), the narrowest fix that
  closes the finding without building a new detail page nobody asked for.
  New Route Handler `finance/invoices/[invoiceId]/print/route.ts` maps
  `finance_invoice_not_found` to a 404, mirroring the other three print
  routes' own error-mapping shape.
  Genuinely verified, not merely typechecked: the same pre-transpile-then-run
  technique used for surat jalan/POD/purchase order produced a real PDF
  buffer (including a withholding-tax line) starting with the literal
  `%PDF-` magic bytes.
  New `scripts/db-tests/finance-invoice.sql` section covers
  `app.get_finance_invoice`: a plain user without `FIN:View` is denied
  `insufficient_authority`; the tenant's own Finance Manager gets the real
  unmasked row; a cross-tenant Finance Manager and a nonexistent invoice id
  both get the identical `finance_invoice_not_found`; `get_finance_invoice`
  was added to the existing schema-privilege anon-EXECUTE-zero function
  list.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,067 tests passing, +4 for
  `getFinanceInvoice`), `db:test` (`ALL PASSED`, run twice), `git:check-paths`
  (clean, 9 files checked), `security:check` (clean), and a real
  `next build` (confirms the new `/finance/invoices/[invoiceId]/print`
  route). `check-release-freeze`'s self-test digests updated for the new
  migration and db-test file (HUNDRED-AND-FORTY-FOURTH PASS).
  Still open under A7: faktur pajak and packing list printables (packing
  list still blocked on the same zero-UI gap noted in the third-document
  entry above).
- 2026-09-14 — A3b closed: a generic approval-definition authoring page
  (`admin/approvals/`), following a research pass that confirmed A3b was
  over-classified DEFERRED_LARGE the same way A1/A2/E5 were. An approval
  *definition* is not its own row type -- it is a PLT-121 ConfigVersion/
  config_items object with `config_type_code='approval'` (the approval
  engine migration's own header), so authoring it needed zero new backend:
  `app.publish_approval_definition` (PLT-123) and the generic
  `app.create_config_draft`/`app.set_config_items` (PLT-121) already existed,
  fully implemented and tested (`scripts/db-tests/approval.sql:95-263`
  exercises the exact same create-draft -> set-items -> publish sequence,
  every structural failure mode included). The one open question worth
  research was whether A3b's own 8 named dependent functions
  (`_request_procurement_entity_approval`, `request_approval`,
  `request_customer_credit_profile`, `submit_job_offer_for_approval`,
  `submit_leave_request`, `submit_onboarding_case_for_finalize_approval`,
  `submit_payroll_run_for_finalization`, `submit_quotation`) each needed
  their own definition -- confirmed no: `app._resolve_approval_config_type_code`
  (`20260831250000_scope_approval_routing_per_domain.sql:104-122`) falls back
  to the plain `'approval'` config type whenever a tenant has not published a
  narrower per-domain override, so one tenant-scoped generic definition
  unblocks all 8 at once.
  The definition's structural shape (`pattern`, `steps`,
  `threshold_required_steps`, `allow_self_approval`) is authored as one JSON
  object rather than a bespoke step-builder UI, mirroring
  `finance/config/finance-config-forms.tsx`'s own `FinanceConfigItemsForm`
  precedent exactly -- `app.validate_approval_definition` already performs
  full structural validation server-side regardless of input source, so this
  is genuinely real authoring, not a fake stand-in for one. The page also
  lists every existing version (draft/published/archived) and every tenant
  role (id + name, since a step's `role_id` must be typed into the JSON) as
  a reference table, plus a rollback-to-published-version form mirroring
  `finance/config`'s own `RollbackFinanceConfigVersionForm`.
  **Two real, previously-undiscovered bugs found while getting the new
  page's client choice right, both fixed in this same slice**: verified live
  against a disposable test database (`has_function_privilege`, not just
  reading migration text) that `app.list_config_versions`,
  `app.create_config_draft`, `app.set_config_items`, and
  `app.publish_config_version` (and their `public.*` wrappers) are granted to
  `service_role` only, never `authenticated`. (1) `finance/config/page.tsx`
  called `listFinanceConfigVersions` (wrapping `list_config_versions`) with
  the RLS-scoped client -- every real Finance Manager visit threw
  permission-denied, caught as `loadFailed`, so the page always rendered
  ErrorState regardless of class or actual version history. Fixed by reading
  that one call through the service-role client (authority is still enforced
  in-body via `app.check_config_object_authority` against the explicitly
  passed actor, so this does not widen who can read the list).
  (2) `procurement/vendors/intake/actions.ts`'s
  `setVendorSelfRegistrationEnabledAction` called the generic
  `createConfigDraft`/`setConfigItems`/`publishConfigVersion` with the same
  RLS-scoped client -- every real tenant admin's self-registration toggle
  failed the same way, silently swallowed into a returned form error. Fixed
  the same way (service-role client for those three calls only). Both bugs
  predate this session's own work on either file.
  Also added a generic `listConfigVersions` to `server/queries/config.ts`
  (mirroring `finance-config.ts`'s own `configTypeCode`-narrowed
  `listFinanceConfigVersions`, but for any config type) since no
  type-agnostic version-listing read existed before this slice -- reused by
  the new page, and available to any future non-Finance Configuration Engine
  UI.
  `eslint.config.js`'s `serviceRoleImportGuard` ignore-list gained the 4 new
  service-role-importing files this slice touches
  (`admin/approvals/actions.ts`, `admin/approvals/page.tsx`,
  `finance/config/page.tsx`, `procurement/vendors/intake/actions.ts`).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,070 tests passing, +3 for
  the new `listConfigVersions`), `db:test` (`ALL PASSED`), `git:check-paths`
  (clean, 9 files checked), `security:check` (clean), and a real `next build`
  (confirms the new `/admin/approvals` route). No migration/db-test change --
  `check-release-freeze` unaffected (digests unchanged from the
  HUNDRED-AND-FORTY-FOURTH PASS).
- 2026-09-15 — A4 narrowed and partially closed: a real, complete UI for one
  of the audit's own "12 working import schemas" -- `finance_opening_balance_
  import` -- chosen because a prior research pass confirmed its own domain
  adapter (`app.validate_finance_opening_balance_import_row`/
  `app.commit_finance_opening_balance_import_job`, ISS-2026-273) was already
  fully built and tested, needing zero new business-logic RPC work, matching
  the same "UI over an already-working backend" shape as A1/A2/A3b/E5.
  Two real, previously-undiscovered gaps found and fixed in the same slice
  (this session's now-established pattern of verifying every assumption
  against a live disposable database rather than trusting migration-text
  alone):
  (1) `finance_opening_balance_source` (the DOCUMENT TYPE for the raw CSV
  file itself, a different catalogue from the import_export SCHEMA
  registration -- that one was already real, `20260830130000`'s own lines
  495-501) was registered only by `scripts/db-tests/finance-subledger.sql:903`,
  never a real migration -- the exact E5 pattern. Every real tenant's first
  source-file upload would have failed `document_type_not_configured`.
  Fixed by `20260914080000_register_finance_opening_balance_source_
  document_type.sql`, mirroring E5's own two-insert shape exactly.
  (2) No read RPC existed to show a reviewer which staged row failed
  validation and why (`app.preview_import_job` returns only 4 aggregate
  counts), and `app.jobs`' own documented "direct-table RLS for
  authenticated" is genuinely real but was unreachable through this
  application's actual PostgREST surface ("app is not exposed to
  PostgREST," confirmed by grep -- no `public.jobs` view exists, and
  `createSupabaseServerClient()`'s `.from()` only ever resolves against
  `public`). A real import UI could not recover "which job is in progress,
  what state is it in" across a page reload without a new read. Fixed by
  `20260914090000_create_import_export_job_detail_read_rpcs.sql`'s
  `app.list_import_staging_rows` and `app.get_import_export_job`, both
  mirroring `app.preview_import_job`'s own SECURITY DEFINER/authority shape
  (job requester or tenant support/Supreme authority) exactly.
  A genuine anon-EXECUTE-widening bug was introduced and caught by this
  slice's own `db:test` run: both new `public.*` wrappers' revoke statements
  said `from public` only, not `from anon, authenticated, service_role,
  public` -- the exact ISS-2026-309 defect class (Supabase's own `ALTER
  DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated,
  service_role` grants `anon` a real, direct privilege at function-creation
  time that `revoke ... from public` -- the PUBLIC pseudo-role, not the
  `anon` role -- never touches), except this time in a migration written
  AFTER `20260830200000_correct_public_wrapper_grant_parity.sql`'s own
  historical bulk-fix swept every wrapper that existed at that time, so the
  new one was not automatically covered. Fixed by adding `anon` to both
  revoke statements explicitly, matching every OTHER migration this session
  wrote correctly the first time (confirmed via grep across all of this
  session's own `20260914*` migrations -- an isolated slip in one file,
  never a misunderstanding of the convention, exactly as the ISS-2026-309
  postmortem itself observed about its own two-file slip).
  New `server/policies/csv-import-parse.ts` (RFC 4180 parser, no dependency
  added -- `stage_import_rows` takes pre-parsed JSON rows, never a raw CSV
  file itself) and `server/mutations/finance-opening-balance-import.ts`
  (the two domain-adapter wrappers, reusing the generic PLT-131 parsers
  since both RPCs return the same composite types as their generic
  siblings). The page (`finance/imports/opening-balances/`) is a real,
  multi-step state machine reflecting the actual job lifecycle -- bootstrap
  (one-time per-tenant publish of both the document-type file-upload rules
  and the schema's column definition) -> upload+scan (reusing this
  session's own A6 `storeFileBytesAndEnqueueScan` helper) -> stage+validate
  (downloads the SAME already-scanned bytes back from Storage rather than
  re-accepting a fresh file, so staged rows can never diverge from what was
  actually scanned; resumable -- never re-stages an already-staged job,
  which would duplicate every row) -> review (every row's own status/error)
  -> commit (`allowPartial` explicit, never silently skips invalid rows).
  Disclosed prerequisite, not a new gap: `app.stage_import_rows` hard-blocks
  on an unscanned file, and this schema's own malware scanning is genuinely
  asynchronous in this environment (no live worker process) -- the page
  surfaces this as a plain retry-after-a-moment message, the same
  established "Scan status: ... blocked until clean" pattern
  `document-checklist-panel.tsx` already uses, rather than inventing new UX.
  No nav entry, mirroring `finance/config`'s own precedent (neither page is
  linked from elsewhere in this codebase either).
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,091 tests passing, +21 for
  the CSV parser/new mutation wrapper/two new query functions), `db:test`
  (`ALL PASSED`, re-verified after the anon-widening fix, migrations 541 ->
  543, db-test files unchanged at 277), `git:check-paths` (clean, 15 files
  checked), `security:check` (clean), and a real `next build` (confirms the
  new `/finance/imports/opening-balances` route). `check-release-freeze`'s
  self-test digests updated (HUNDRED-AND-FORTY-FIFTH PASS).
  Still open under A4: the other 10 import schemas' own UIs (each costs
  roughly one wrapper + one document-type registration + one route per this
  slice's own template, no new pattern needed).
- 2026-09-17 — B7 (worklist half) closed: `finance/invoices/page.tsx` gained
  a "Billable jobs" worklist table above the invoice queue, replacing the
  free-text `BillingReadinessHandoff ID` input `invoice-forms.tsx` used to
  require. `app.billing_readiness_handoffs` is append-only with no status
  column at all, and the only existing read,
  `app.list_billing_readiness_handoffs` (O1 remediation), is scoped to ONE
  job order -- exactly the id Finance does not have without already knowing
  which job order to look up, so it could not serve as a tenant-wide
  worklist. New migration
  `20260915010000_create_list_billable_readiness_handoffs.sql` adds
  `app.list_billable_readiness_handoffs`: every handoff with no live
  (non-void) `app.finance_invoices` row yet, joined to `app.job_orders`/
  `app.accounts` for `job_number`/customer legal name. Amount/currency reuse
  `app.prepare_finance_invoice_from_readiness`'s own exact revenue-snapshot
  arithmetic (`subtotalAmount - discountAmount`, the job order's own
  currency) rather than inventing a second calculation -- a worklist that
  showed a different number than what preparing the invoice will actually
  charge would be worse than showing none. Amount is masked behind
  `app.has_view_selling_price`, mirroring `app.list_job_orders`'s own
  precedent exactly (a Finance viewer with `FIN:View` but not Commercial's
  "View selling price" sees every handoff but not its amount, "Masked" text,
  the same convention purchase orders' own `PRC:View cost` split
  established). Gated on `app.check_finance_invoice_authority('View', ...)`,
  the same gate `app.list_finance_invoices`/`app.get_finance_invoice`
  already use -- no `app.assert_actor_is_session_identity` call, since that
  RULE A pattern is specific to the OPS-domain `app.can_access_record`
  functions (confirmed by re-reading `list_finance_invoices`/
  `get_finance_invoice`'s own bodies, neither of which calls it either).
  `prepareFinanceInvoiceFromReadinessAction`'s `billingReadinessHandoffId`
  is now a bound positional arg (the worklist's own per-row form binds it),
  the same pattern every lifecycle action on this page already used for
  `invoiceId` -- not a hand-typed FormData field.
  The second half of B7 (`app.check_customer_credit` never reads AR open
  items, so credit control cannot compute exposure, and no order-acceptance
  path calls it) is untouched -- a separate, larger, deliberately deferred
  piece of work, out of this slice's scope.
  Applied this session's own HUNDRED-AND-FORTY-FIFTH-PASS lesson
  proactively this time: verified the new `public.*` wrapper's revoke
  statement explicitly names `anon, authenticated, service_role` (not just
  `from public`) BEFORE running `db:test`, then re-confirmed with
  `has_function_privilege` against a live disposable database that `anon`
  holds zero EXECUTE on either the `app.*` or `public.*` function -- no
  repeat of the ISS-2026-309 defect class this time.
  New db-test section in `scripts/db-tests/finance-invoice.sql` reuses the
  fixture's own existing handoffs: the first (already consumed by an issued
  invoice) is confirmed EXCLUDED; the second (whose only invoice was
  discarded/voided in an earlier test) is confirmed to reappear as billable,
  masked for Finance Manager A (`FIN:View`, no `COM:View selling price`) and
  correctly unmasked (15,000,000 IDR, real `job_number`, real customer
  legal name) for Rep A (holds both); a third, genuinely fresh handoff is
  confirmed to appear exactly once; Plain User A and a cross-tenant Finance
  Manager B are both denied `insufficient_authority`.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings), the unit test suite (6,094 tests passing, +3 for
  `listBillableReadinessHandoffs`), `db:test` (`ALL PASSED`), `git:check-paths`
  (clean, 9 files checked), `security:check` (clean), and a real `next build`
  (confirms `/finance/invoices` still builds with the new worklist).
  `check-release-freeze`'s self-test digests updated (HUNDRED-AND-FORTY-SIXTH
  PASS, migrations 543 -> 544, db-test files unchanged at 277).
- 2026-09-17 — A4 (`employee_import`, second import schema) closed: a
  near-mechanical port of `finance/imports/opening-balances/`'s own trio to
  `hris/imports/employees/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic
  `stageImportRows`/`listImportStagingRows`/`getImportExportJob` verbatim.
  No new migration needed -- unlike `finance_opening_balance_source`, both
  the `employee_document` document type and the `employee_import` schema
  are already registered as real GLOBAL catalog rows directly by
  `20260730830000_create_hris_employee_master.sql`; each tenant still
  separately publishes its own `document:employee_document` and
  `import_export:employee_import` config VERSIONS (the same one-time
  per-tenant bootstrap step every PLT-131 adopter requires), confirmed by
  reading `scripts/db-tests/hris-employee-master.sql`'s own fixture setup
  for the exact 10-column shape and `default_classification: 'confidential'`
  convention (reused verbatim here rather than finance's `'internal'`,
  matching the more sensitive nature of employee PII).
  Two real, previously-undiscovered "minor parity gaps" this slice closes in
  `server/mutations/employee.ts`, both flagged by this session's own prior
  scoping pass rather than found fresh here: (1)
  `app.commit_employee_import_job` gained an optional `p_client_ip` param at
  `20260903122000_harden_tenant_id_disclosure_hris_payroll_import_commit.sql`
  (enforcing the tenant's own IP allowlist when supplied, composed with a
  real MFA step-up requirement for HRS:Import) but the TS wrapper never
  passed it -- fixed by adding `clientIp` to
  `CommitEmployeeImportJobInputSchema` (nullable, defaulting to `null`) and
  threading it through, mirroring `commitOpeningBalanceImportAction`'s own
  `resolveRequestClientIp()` call; (2)
  `EMPLOYEE_KNOWN_MUTATION_ERROR_CODES` was missing
  `employee_import_duplicate_employee_number` (HDN-385's own named,
  loud-abort error for a genuine explicit `employee_number` collision),
  `ip_not_allowed`, and `mfa_step_up_required` -- all three now reachable,
  real error codes rather than falling through to a generic
  `unclassified_error`. Both RPC-level behaviors (the IP allowlist
  enforcement and the MFA step-up requirement) were already fully covered
  by `scripts/db-tests/hris-employee-master.sql`'s own ISS-2026-278
  regression section -- this slice only closes the TS-side wrapper/
  classification gap, so no new db-test coverage or migration was needed.
  The employee directory page (`hris/employees/page.tsx`) gained a "Bulk
  import from CSV" nav link next to its header -- unlike finance's
  standalone unlinked opening-balances page, HR's own directory has a
  natural integration point (a bulk-onboarding entry point next to the
  one-at-a-time create form), so this slice links it rather than leaving it
  orphaned.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list, mirroring the
  opening-balances precedent exactly), the unit test suite (6,097 tests
  passing, +6 for the `clientIp`/new-error-code coverage in
  `employee.test.ts`), `db:test` (`ALL PASSED`, unchanged -- no SQL touched
  this slice), `git:check-paths` (clean, 8 files checked), `security:check`
  (clean), and a real `next build` (confirms the new
  `/[tenantSlug]/hris/imports/employees` route). `check-release-freeze`'s
  self-test digests are unchanged from the HUNDRED-AND-FORTY-SIXTH PASS --
  no migration or db-test file was added or modified this slice.
  Still open under A4 as of this slice: the other 9 import schemas' own UIs
  (attendance_device_import, timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  vendor_rate_import under PRC; customer_import under COM; item_import,
  inventory_opening_balance_import under OPS), each estimated at the same
  one-wrapper-plus-one-route cost as this slice and the finance one before
  it. (vendor_import itself closed next, see below.)
- 2026-09-17 — B6 re-scoped, B6a closed: a dedicated recon pass (before any
  code was written) found the audit's own literal claims true but its
  `CODE-BIG`/`DEFERRED_LARGE` classification overstated -- the only backlog
  row in this whole document with a completely empty Notes column, unlike
  every sibling `DEFERRED_LARGE` item, which was itself the tell. Verified
  against the LIVE current bodies of every function the audit named (not the
  2026-09-02 audit text alone, since ~2 weeks of remediation had already
  moved this code):
  (1) 12 of the audit's "13 actual_cost functions" were never candidates to
  post to the GL at all (reads/permission checks/arithmetic/a trigger),
  explicitly disclosed as out of scope in their own creating migration's
  header. The 13th, `app.prepare_finance_vendor_bill_from_actual_cost`,
  already has a complete, working, GL-wired path for vendor-sourced cost via
  the ordinary vendor-bill lifecycle (`post_finance_vendor_bill` posts to
  the GL). Internal-source (no-vendor) actual cost genuinely has no path to
  the GL at all, automatic or dedicated-manual -- a real, narrower gap left
  open (see below), distinct from "no cost ever posts."
  (2) `allocate_finance_receipt` and `apply_finance_ap_settlement` both
  already post correctly (confirmed via their real call sites, not the
  isolated low-level mutators the audit named). `reverse_finance_ap_settlement`
  was ALSO already fixed, pre-audit, by
  `20260826030000_harden_finance_settlement_reversal_gl_journal_and_reachability.sql`
  (RGL-BLK-009) -- its only caller, `app.request_finance_settlement_reversal`,
  posts a real reversing GL journal. Only `reverse_finance_ar_allocation`'s
  own caller, `app.request_finance_receipt_deallocation`, was never given
  the mirror-image fix -- confirmed by reading all 3 of its redefinitions
  since creation (SECURITY DEFINER hardening, IP-allowlist wiring), none of
  which touched the GL side.
  (3) `app.purchase_order_lines` still has no unit price/amount/currency
  column, confirmed unchanged -- a real, narrow, but separate procurement
  data-model gap, unconnected to GL posting (POs do not post to GL in this
  codebase at all) and left open, not blocking.
  (4) A fully working MANUAL GL posting path already exists
  (`create_finance_journal_draft` -> submit -> approve -> `post_finance_journal`)
  -- B6 was a "no automation yet" gap, never a "money unaccounted for with
  no recovery path" emergency.
  B6a (the one real, narrow, closeable gap) fixed: new migration
  `20260917010000_fix_finance_receipt_deallocation_gl_reversal.sql`
  re-creates `app.request_finance_receipt_deallocation` to post a real
  reversing GL journal (a `finance_journal_corrections` row, `correction_type
  ='reversal'`, posted via the existing `create_and_post_finance_system_journal`
  with `lock_scope='ar'`) before calling the existing
  `app.reverse_finance_ar_allocation` -- closing the exact mirror-image of
  RGL-BLK-009 on the AR side. One real wrinkle the AP precedent did not have
  to solve, found and resolved during implementation: `allocate_finance_receipt`
  posts ONE subledger batch/GL journal per ALLOCATE CALL (which can cover
  several AR open items across several `finance_receipt_allocations` rows),
  while deallocation reverses exactly ONE allocation row at a time --
  reversing the shared journal in full (the AP function's own technique,
  correct there only because one settlement always owns exactly one journal)
  would misstate every OTHER still-applied allocation from the same batch.
  Fixed by flipping the original journal's own 2 lines (landing on the exact
  same accounts, never re-resolving a posting-map key -- the same principle
  the AP precedent's own comment states) but substituting this one
  allocation's own amount for each line's amount, and deliberately leaving
  the original subledger batch's own status at `'posted'` (never
  `'reversed'`) since other allocations from it may still stand -- the new
  correction journal is the GL's actual source of truth;
  `app.finance_subledger_batches` is a lineage/traceability record, never
  itself read by any balance computation in this codebase. No wrapper change
  needed (`public.request_finance_receipt_deallocation`'s signature is
  unchanged). New db-test assertions extend the EXISTING "governed
  deallocation" fixture in `scripts/db-tests/finance-receipt-allocation.sql`
  (no new file) which already, by coincidence, exercises the exact "one
  batch, two allocations, reverse only one" scenario the fix targets:
  confirm the original batch stays `posted`, a posted correction links to
  its journal, the new reversal journal is balanced at exactly the reversed
  allocation's own amount (never the whole batch total), and its 2 lines
  land on the same 2 accounts as the original with direction flipped.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; no TS/frontend files touched), the unit test suite
  (6,097 tests, unchanged -- SQL-only slice), `db:test` (`ALL PASSED` twice
  in a row -- the finance-domain files plus a full-suite run; one unrelated,
  pre-existing flake reproduced once in
  `customer-loyalty-liability-reconciliation.sql`'s own real three-process
  timing-sensitive atomicity race test, gone on immediate re-run, confirmed
  unrelated to this slice), `git:check-paths` (clean, 3 files checked),
  `security:check` (clean). `next build` not run -- no TypeScript/frontend
  file changed. `check-release-freeze`'s self-test digests updated
  (HUNDRED-AND-FORTY-SEVENTH PASS, migrations 544 -> 545, db-test files
  unchanged at 277).
  Still open under B6, and NOT attempted this slice after closer reading
  disclosed a real reason not to: this session's own initial B6b plan (a
  thin `app.post_actual_cost_to_gl` posting internal-source cost components
  straight to the GL via 1-2 new `finance_posting_map` keys, mechanically
  modeled on `post_finance_vendor_bill`'s own posting shape) was abandoned
  after re-reading `20260728110000_create_operations_actual_cost.sql`'s own
  header, which explicitly discloses `app.shipment_actual_costs`/
  `_components` as "non-authoritative-for-payment operational figures" --
  and confirming that the vendor-sourced path's own real precedent,
  `app.prepare_finance_vendor_bill_from_actual_cost`, honors exactly that
  boundary: it never posts anything itself, it stages a Finance-owned
  vendor-bill DRAFT that must independently pass through Finance's own full
  review/approve/post lifecycle before the actual-cost figures become
  authoritative. A same-shape fix for internal cost needs an equivalent
  Finance-owned, Finance-reviewed staging document -- none exists today, and
  what it should be (a new document type? does it need its own approval
  step? which account absorbs an internal cost with no vendor bill to
  anchor it?) is a real product decision this session should not make
  unilaterally inside a database migration. Implementing the originally-
  planned thin direct-post function would have posted internal cost with
  LESS governance than vendor cost gets today -- a new inconsistency, not a
  fix, and exactly the kind of shortcut Part C's own "financial correctness
  never traded for velocity" rule exists to prevent. Correctly re-
  dispositioned as `NEEDS_PRODUCT_DECISION`, not implemented, per Part A's
  own "if there's a real ambiguity requiring a decision this session cannot
  make, disposition it honestly rather than plowing ahead" doctrine.
  `app.purchase_order_lines` still has no unit price/amount/currency
  column, confirmed narrow and non-blocking (nothing in this codebase reads
  it for GL purposes, since POs never post to GL at all) but also NOT added
  speculatively this slice -- no real consumer exists yet to justify the
  columns, and adding unused schema ahead of a genuine need is exactly the
  kind of premature design this session's own standing instructions warn
  against. Left open for whichever future slice actually needs it.
- 2026-09-17 — A4 (`vendor_import`, third import schema) closed: a
  near-mechanical port of `hris/imports/employees/`'s own trio to
  `procurement/imports/vendors/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic `stageImportRows`/
  `listImportStagingRows`/`getImportExportJob` verbatim. Unlike
  `employee_import`, only the `import_export:vendor_import` SCHEMA was
  already a real global catalog row
  (`20260830100000_create_vendor_import_adapter.sql`) -- the
  `vendor_import_source` DOCUMENT TYPE was never registered by any real
  migration, only by `scripts/db-tests/procurement-vendor-registration.sql`'s
  own fixture (confirmed by repo-wide grep before writing anything), the
  exact `finance_opening_balance_source` gap repeated a third time. Fixed by
  new migration `20260917020000_register_vendor_import_source_document_type.sql`,
  mirroring `20260914080000`'s own shape verbatim.
  `server/mutations/vendor-profile.ts` had ZERO wrapper for
  `validate_vendor_import_row`/`commit_vendor_import_job` at all (a
  from-scratch build, not a parity-gap patch like `employee_import`'s own
  two small fixes) -- both new functions reuse the generic PLT-131 parsers
  (`parseImportStagingRow`/`parseImportExportJob`) directly rather than a
  raw `Record<string, unknown>` return, matching
  `finance-opening-balance-import.ts`'s own newer, stronger-typed
  convention (never `employee.ts`'s older one, which predates that reusable-
  parser pattern) since this was fresh code with no existing convention to
  preserve. `commit_vendor_import_job` composes a stricter, additive
  authority gate than `employee_import`/`finance_opening_balance_import`
  (`is_support_grant_authority` AND `PRC:Import`, never either alone) and
  runs two duplicate-candidate sweeps (trigram legal-name match, exact
  `business_registration_number` match) that flag for human review but
  never block the commit -- both documented in the wizard's own copy
  (`page.tsx`'s "Import completed" state and the pre-commit review section)
  rather than left as a silent surprise.
  Incidentally found and fixed in the same slice (discovered while reading
  `finance-opening-balance-import.ts` as this slice's own template, not
  something this slice's own scope was expanded to search for):
  `FINANCE_OPENING_BALANCE_IMPORT_KNOWN_MUTATION_ERROR_CODES` was missing
  `import_export_wrong_schema`, a real prefix
  `app.commit_finance_opening_balance_import_job`'s own same-schema guard
  (`20260830130000:698`) raises -- added there too, with a matching new
  unit test, since it was a one-line, zero-risk fix directly in the
  neighborhood of what this slice was already reading.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit test
  suite (6,103 tests passing, +6 for `validateVendorImportRow`/
  `commitVendorImportJob` plus the `import_export_wrong_schema`
  regression), `db:test` (`ALL PASSED` -- no new db-test file needed, since
  `procurement-vendor-registration.sql`'s own existing fixture already
  fully covers both RPCs' real behavior; this slice only adds TS-side
  wrapper/UI surface with no independent database behavior to regress),
  `git:check-paths` (clean, 12 files checked), `security:check` (clean),
  and a real `next build` (confirms the new
  `/[tenantSlug]/procurement/imports/vendors` route). `check-release-freeze`'s
  self-test digests updated (HUNDRED-AND-FORTY-EIGHTH PASS, migrations
  545 -> 546, db-test files unchanged at 277).
  Still open under A4 as of this slice: the other 8 import schemas' own UIs
  (attendance_device_import, timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  customer_import under COM; item_import, inventory_opening_balance_import
  under OPS), each estimated at the same one-wrapper-plus-one-route cost as
  this slice and the three before it. (vendor_rate_import itself closed
  next, see below.)
- 2026-09-17 — A4 (`vendor_rate_import`, fourth import schema) closed: a
  near-mechanical port of `procurement/imports/vendors/`'s own trio to
  `procurement/imports/vendor-rates/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic `stageImportRows`/
  `listImportStagingRows`/`getImportExportJob` verbatim. Unlike
  `vendor_import`, the `import_export:vendor_rate_import` SCHEMA was already
  a real global catalog row
  (`20260730620000_extend_commercial_vendor_rate_for_procurement.sql`) --
  only the `vendor_rate_import_source` DOCUMENT TYPE was never registered
  by any real migration, only by
  `scripts/db-tests/procurement-vendor-rate-tiers.sql`'s own fixture
  (confirmed by repo-wide grep before writing anything), the exact
  `vendor_import_source` gap repeated a third time. Fixed by new migration
  `20260917030000_register_vendor_rate_import_source_document_type.sql`,
  mirroring `20260917020000`'s own shape verbatim.
  Unlike `vendor_import` (whose TS wrapper had to be built from scratch),
  `server/mutations/procurement-rate.ts` already exported a complete
  `validateVendorRateImportRow`/`commitVendorRateImportJob` wrapper before
  this slice -- this slice only closed two small parity gaps in it, the
  exact class `employee_import`'s own scoping found in
  `server/mutations/employee.ts`: `commitVendorRateImportJob` never passed
  the RPC's own `p_client_ip` param (added to
  `app.commit_vendor_rate_import_job` at
  `20260902200000_harden_tenant_id_disclosure_commercial.sql`, composing
  `app.assert_ip_allowed` and a PRC:Import MFA step-up gate), and
  `PROCUREMENT_RATE_KNOWN_MUTATION_ERROR_CODES` was missing
  `ip_not_allowed`/`mfa_step_up_required`. The bootstrap action publishes
  the FULL 31-column contract already exported as
  `VENDOR_RATE_IMPORT_COLUMNS` in
  `server/contracts/procurement-rate/procurement-rate.ts` (13 flat fields
  plus 3 tier blocks of 6 fields each) rather than hand-rolling a column
  list inline the way the three prior slices had to -- the contract already
  existed, reused directly.
  `app.commit_vendor_rate_import_job`'s own authority composition matches
  `vendor_import`'s (`is_support_grant_authority` AND `PRC:Import`,
  additive, never either alone); imported rates land as `pending_approval`
  exactly like manually-created ones, never auto-approved by import, both
  documented in the wizard's own copy.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit test
  suite (6,105 tests passing, +4 for the `clientIp`/new-error-code coverage
  in `procurement-rate.test.ts`), `db:test` (`ALL PASSED` -- no new db-test
  file needed, since `procurement-vendor-rate-tiers.sql`'s own existing
  fixture already fully covers both RPCs' real behavior), `git:check-paths`
  (clean, 10 files checked), `security:check` (clean), and a real
  `next build` (confirms the new
  `/[tenantSlug]/procurement/imports/vendor-rates` route).
  `check-release-freeze`'s self-test digests updated (HUNDRED-AND-FORTY-NINTH
  PASS, migrations 546 -> 547, db-test files unchanged at 277).
  Still open under A4 as of this slice: the other 7 import schemas' own UIs
  (attendance_device_import, timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  item_import, inventory_opening_balance_import under OPS), each estimated
  at the same one-wrapper-plus-one-route cost as this slice and the four
  before it -- item_import's own document-type registration is already
  done as a side effect of this slice (see below). (customer_import itself
  closed next, see below.)
- 2026-09-17 — A4 (`customer_import`, fifth import schema) closed: a
  near-mechanical port of `procurement/imports/vendors/`'s own trio to
  `commercial/imports/customers/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic `stageImportRows`/
  `listImportStagingRows`/`getImportExportJob` verbatim. Like `vendor_import`
  (and unlike `vendor_rate_import`), `server/mutations/account.ts` had ZERO
  wrapper for `validate_customer_import_row`/`commit_customer_import_job`
  at all -- both new functions were built from scratch, reusing the generic
  PLT-131 parsers directly. The `import_export:customer_import` SCHEMA was
  already a real global catalog row
  (`20260830120000_create_customer_and_item_import_adapters.sql`, which
  ALSO registers `item_import`'s own schema kind in the same migration --
  the two are siblings) -- only the `master_data_import_source` DOCUMENT
  TYPE (shared by BOTH schemas) was never registered by any real migration,
  only by `scripts/db-tests/master-data-import.sql`'s own fixture, the
  exact gap repeated a fourth time. Fixed by new migration
  `20260917040000_register_master_data_import_source_document_type.sql`,
  which -- since it registers a document type shared with `item_import` --
  incidentally clears that schema's own future UI slice of needing a
  document-type migration of its own.
  `app.commit_customer_import_job`'s own authority composition matches
  `vendor_import`'s (`is_support_grant_authority` AND `COM:Import`,
  additive, never either alone), but its duplicate handling is a genuinely
  different shape: create-or-link, not flag-for-review -- a row matching an
  existing account by legal name/tax ID (the same fingerprint-normalization
  `app.create_customer_account_direct` already used for `convert_quotation_
  to_account`) resolves to that account and is counted as linked, never
  blocked, unless the resolved account is under legal hold
  (`import_blocked_legal_hold`, ISS-2026-277), which aborts the whole
  commit -- both documented in the wizard's own copy rather than described
  as "duplicates flagged" the way `vendor_import`'s copy does. The accounts
  list page (`commercial/accounts/page.tsx`) had no header row at all
  (a bare `<h1>`) -- restructured into the same `flex` header pattern every
  other list page in this slice's own lineage already uses, then linked.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit test
  suite (6,110 tests passing, +9 for `validateCustomerImportRow`/
  `commitCustomerImportJob`), `db:test` (`ALL PASSED` -- no new db-test file
  needed, since `master-data-import.sql`'s own existing fixture already
  fully covers both RPCs' real behavior), `git:check-paths` (clean, 10 files
  checked), `security:check` (clean), and a real `next build` (confirms the
  new `/[tenantSlug]/commercial/imports/customers` route).
  `check-release-freeze`'s self-test digests updated (HUNDRED-AND-FIFTIETH
  PASS, migrations 547 -> 548, db-test files unchanged at 277).
  Still open under A4 as of this slice: the other 6 import schemas' own UIs
  (attendance_device_import, timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  inventory_opening_balance_import under OPS), each estimated at the same
  one-wrapper-plus-one-route cost as this slice and the five before it.
  (item_import itself closed next, see below.)
- 2026-09-17 — A4 (`item_import`, sixth import schema) closed: a
  near-mechanical port of `commercial/imports/customers/`'s own trio to
  `operations/imports/items/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic `stageImportRows`/
  `listImportStagingRows`/`getImportExportJob` verbatim. The cheapest slice
  of the six so far: NO new migration was needed at all. Both the
  `import_export:item_import` SCHEMA and the `master_data_import_source`
  DOCUMENT TYPE (shared with `customer_import`) were already real, global
  catalog rows before this slice started -- `20260830120000_create_
  customer_and_item_import_adapters.sql` registers `customer_import` and
  `item_import`'s own schema kinds together in one statement, and this
  session's own `customer_import` slice
  (`20260917040000_register_master_data_import_source_document_type.sql`)
  had already, deliberately, registered the shared document type
  additively and idempotently, anticipating exactly this slice.
  `server/mutations/item-uom-master.ts` had ZERO wrapper for
  `validate_item_import_row`/`commit_item_import_job` at all (a
  from-scratch build, like `vendor_import`'s/`customer_import`'s own
  slices) -- both new functions reuse the generic PLT-131 parsers
  directly. `app.commit_item_import_job`'s own authority composition
  matches `vendor_import`'s/`customer_import`'s (`is_support_grant_authority`
  AND `OPS:Import`, additive, never either alone); its duplicate handling is
  create-or-link, the same shape as `customer_import`'s, but the owner
  resolution has a genuinely different wrinkle: every item master belongs
  to exactly one customer account (`owner_account_tax_id`/
  `owner_account_legal_name` in the CSV), re-resolved at COMMIT time (not
  carried from validation, since the account could have been merged or
  deactivated in between) -- an ambiguous or now-unresolvable match raises
  a hard, named error (`import_owner_account_not_found`), never a silent
  pick, since misattributing one customer's items to another is a
  confidentiality problem, not a tidiness one.
  No item/SKU master-data page exists anywhere in this codebase yet
  (confirmed by repo-wide search before writing anything) -- unlike the
  five prior slices, this page has no host list page to link from, so it is
  standalone and unlinked, mirroring `finance/config/page.tsx`'s own
  precedent rather than inventing navigation for a page that does not
  exist.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit test
  suite (6,115 tests passing, +13 for `validateItemImportRow`/
  `commitItemImportJob`), `db:test` (`ALL PASSED` -- no new db-test file
  needed, since `scripts/db-tests/master-data-import.sql`'s own existing
  fixture already fully covers both RPCs' real behavior), `git:check-paths`
  (clean, 7 files checked), `security:check` (clean), and a real
  `next build` (confirms the new `/[tenantSlug]/operations/imports/items`
  route). `check-release-freeze`'s self-test digests are UNCHANGED from the
  HUNDRED-AND-FIFTIETH PASS -- no migration or db-test file was added or
  modified this slice, the first A4 slice not to need a digest update.
  Still open under A4: the other 6 import schemas' own UIs
  (attendance_device_import, timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  inventory_opening_balance_import under OPS), each estimated at the same
  one-wrapper-plus-one-route cost as this slice and the five before it.
- 2026-09-17 — A4 (`attendance_device_import`, seventh import schema)
  closed: a near-mechanical port of `hris/imports/employees/`'s own trio to
  `hris/imports/attendance-devices/`, reusing `server/policies/csv-import-
  parse.ts`, `storeFileBytesAndEnqueueScan`, and the generic
  `stageImportRows`/`listImportStagingRows`/`getImportExportJob` verbatim.
  Like `item_import`, NO new migration was needed: both the
  `attendance_device_import_source` DOCUMENT TYPE and the
  `attendance_device_import` SCHEMA kind were already real, global catalog
  rows, registered directly by `20260730900000_create_hris_attendance.sql`.
  `server/mutations/attendance.ts` had ZERO wrapper for
  `validate_attendance_device_import_row`/`commit_attendance_device_import_job`
  at all (a from-scratch build) -- both new functions reuse the generic
  PLT-131 parsers directly, the SAME composite types
  (`app.import_staging_rows`/`app.jobs`) the generic RPCs themselves return.
  This schema's own commit RPC composes the richest authority stack of any
  import schema in this backlog so far: tenant membership, then `HRS:Import`,
  then a CONDITIONAL MFA step-up (a strict no-op unless the tenant opted
  (HRS, Import) into its own additional_high_risk_actions), then a
  CONDITIONAL IP allowlist check -- three new error codes
  (`job_actor_unauthorized`/`mfa_step_up_required`/`ip_not_allowed`) were
  added to this file's own known-error allowlist, alongside the five
  `import_export_*` prefixes that were already pre-added but previously
  unused. Duplicate handling here has no precedent among the six prior
  slices: attendance events are not master records with a create-or-link
  concept, so an already-committed staging row (`source_import_staging_row_id`
  already bound) is simply skipped as a plain idempotent replay --
  `app.commit_attendance_device_import_job` feeds each valid row through
  `app._ingest_attendance_event`, the SAME engine the live self-service clock
  path uses, never a bespoke import-only write path. This document type's own
  `default_classification` is `confidential`, not the `internal` every prior
  A4 slice used, matching `scripts/db-tests/hris-attendance.sql`'s own
  fixture verbatim -- biometric/clock-event data tied to an individual
  employee genuinely warrants tighter default handling than a roster or
  price list. The host page (`hris/attendance/page.tsx`, previously opening
  straight into `<AttendanceAdminPanel>` with no header row at all) was
  restructured with the same header-row treatment `commercial/accounts/
  page.tsx` got in the `customer_import` slice.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to `eslint.config.
  js`'s `serviceRoleImportGuard` ignores list), the unit test suite (6,119
  tests passing, +4 for `validateAttendanceDeviceImportRow`/
  `commitAttendanceDeviceImportJob`), `db:test` (`ALL PASSED`, including the
  pre-existing ISS-2026-278 IP-allowlist regression in
  `hris-attendance.sql` -- no new db-test file needed, since that file's own
  existing fixture already fully covers both RPCs' real behavior),
  `git:check-paths` (clean, 9 files checked), `security:check` (clean), and
  a real `next build` (confirms the new
  `/[tenantSlug]/hris/imports/attendance-devices` route). `check-release-
  freeze`'s self-test digests are UNCHANGED from the HUNDRED-AND-FIFTIETH
  PASS -- no migration or db-test file was added or modified this slice, the
  second A4 slice in a row not to need a digest update.
  Still open under A4: the other 5 import schemas' own UIs
  (timesheet_import, leave_opening_balance_import,
  payroll_loan_cutover_import, position_crosswalk_import under HRS;
  inventory_opening_balance_import under OPS), each estimated at the same
  one-wrapper-plus-one-route cost as this slice and the six before it.
- 2026-09-17 — A4 (`timesheet_import`, ninth import schema) closed: a
  near-mechanical port of `hris/imports/attendance-devices/`'s own trio to
  `hris/imports/timesheet/`, reusing `server/policies/csv-import-parse.ts`,
  `storeFileBytesAndEnqueueScan`, and the generic `stageImportRows`/
  `listImportStagingRows`/`getImportExportJob` verbatim. Like `item_import`
  and `attendance_device_import`, NO new migration was needed: both the
  `timesheet_import_source` DOCUMENT TYPE and the `timesheet_import` SCHEMA
  kind were already real, global catalog rows, registered directly by
  `20260730980000_create_hris_overtime_timesheet.sql`.
  `server/mutations/overtime-timesheet.ts` (a file with 20+ existing
  overtime/timesheet mutation wrappers, but ZERO for
  `validate_timesheet_import_row`/`commit_timesheet_import_job`) gained both
  as a from-scratch addition, reusing the generic PLT-131 parsers directly --
  the SAME composite types (`app.import_staging_rows`/`app.jobs`) the generic
  RPCs themselves return. `app.commit_timesheet_import_job`'s own latest
  redefinition composes the identical authority stack
  `commit_attendance_device_import_job` does (tenant membership, then
  `HRS:Import`, then a conditional MFA step-up, then a conditional IP
  allowlist check) -- the same three error codes
  (`job_actor_unauthorized`/`mfa_step_up_required`/`ip_not_allowed`) were
  added to this file's own known-error allowlist. Duplicate handling has the
  same shape as `attendance_device_import`'s: timesheet entries are not
  master records with a create-or-link concept, so an already-committed
  staging row (`source_import_staging_row_id` already bound on an
  `app.timesheet_entries` row) is simply skipped as a plain idempotent
  replay -- `app.commit_timesheet_import_job` feeds each valid row through
  `app._create_timesheet_entry` with `source='import'`, the SAME engine the
  manual timesheet-entry path uses. `validate_timesheet_import_row` has two
  FK-style resolutions beyond `employee_number` that no prior A4 slice
  needed: optional `job_number`/`shipment_number` columns, each resolved
  against `app.job_orders`/`app.shipment_orders` if present in the row. Like
  `attendance_device_import`, this document type's own
  `default_classification` is `confidential`, not the `internal` norm.
  The host page (`hris/overtime-timesheet/page.tsx`, previously opening
  straight into `<OvertimeTimesheetAdminPanel>` with no header row at all)
  was restructured with the same header-row treatment `hris/attendance/
  page.tsx` got in the `attendance_device_import` slice.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to `eslint.config.
  js`'s `serviceRoleImportGuard` ignores list), the unit test suite (6,123
  tests passing, +4 for `validateTimesheetImportRow`/
  `commitTimesheetImportJob`), `db:test` (`ALL PASSED`, including the
  pre-existing ISS-2026-278 IP-allowlist regression in
  `hris-overtime-timesheet.sql` -- no new db-test file needed, since that
  file's own existing fixture already fully covers both RPCs' real
  behavior), `git:check-paths` (clean, 8 files checked), `security:check`
  (clean), and a real `next build` (confirms the new
  `/[tenantSlug]/hris/imports/timesheet` route). `check-release-freeze`'s
  self-test digests are UNCHANGED from the HUNDRED-AND-FIFTIETH PASS -- no
  migration or db-test file was added or modified this slice, the third A4
  slice in a row not to need a digest update.
  Still open under A4: the other 4 import schemas' own UIs
  (leave_opening_balance_import, payroll_loan_cutover_import,
  position_crosswalk_import under HRS; inventory_opening_balance_import
  under OPS), each estimated at the same one-wrapper-plus-one-route cost as
  this slice and the seven before it.
- 2026-09-17 — A4 (`leave_opening_balance_import`, tenth import schema)
  closed: a near-mechanical port of
  `hris/imports/timesheet/`'s own trio to
  `hris/imports/leave-opening-balance/`, reusing
  `server/policies/csv-import-parse.ts`, `storeFileBytesAndEnqueueScan`, and
  the generic `stageImportRows`/`listImportStagingRows`/`getImportExportJob`
  verbatim. Unlike `item_import`/`attendance_device_import`/
  `timesheet_import` (each already fully catalogued before its own slice),
  this schema's `import_export_schemas` row was already real
  (`20260831260000_create_inventory_and_leave_opening_balance_import_adapters.sql`)
  but NO document type for the raw source file had ever been registered
  anywhere -- not even in a db-test fixture (the one existing db-test,
  `scripts/db-tests/hris-leave-permit-business-trip.sql`, bootstraps its own
  fixture against the generic, COM-owned `master_data_import_source`
  document type this session's own `customer_import` slice registered,
  rather than a dedicated one). Rather than reuse that generic type for a
  genuinely HRS-owned, employee-linked opening-balance cutover file, new
  migration
  `20260917050000_register_leave_opening_balance_import_source_document_type.sql`
  instead registers a dedicated `leave_opening_balance_import_source`
  document type, mirroring `timesheet_import_source`'s/
  `attendance_device_import_source`'s own one-document-type-per-schema
  precedent -- a real scoping decision, not settled by any existing code,
  made for internal consistency within the HRS domain.
  `server/mutations/leave.ts` (20+ existing overtime/leave mutation
  wrappers, but ZERO for `validate_leave_opening_balance_import_row`/
  `commit_leave_opening_balance_import_job`) gained both as a from-scratch
  addition, reusing the generic PLT-131 parsers directly.
  `app.commit_leave_opening_balance_import_job` composes the richest
  authority stack of any A4 import schema so far: BOTH
  `app.is_support_grant_authority` (Supreme Admin or tenant_admin) AND
  `HRS:Import` (additive, never either-or), plus the same conditional MFA
  step-up and IP-allowlist gates `attendance_device_import`/
  `timesheet_import` carry -- a plain HR staffer holding only `HRS:Import`
  is refused. Duplicate handling follows `finance_opening_balance_import`'s
  own convention (the very first A4 slice this session built), not
  attendance/timesheet's "not a master record" shape: the idempotency key is
  derived from the staging row's own id, so re-running the SAME job is a
  safe no-op, but `app.leave_balance_ledger` is append-only -- a corrected
  re-upload posts a brand-new entry on top of a wrong one rather than
  overwriting it. The wizard's own copy surfaces this plainly: a one-time
  cutover action, not a routine batch import, and correcting a mistake
  requires the separate `app.adjust_leave_balance` path outside this wizard
  entirely.
  The host page (`hris/leave/page.tsx`, previously opening straight into
  `<LeaveAdminPanel>` with no header row at all) was restructured with the
  same header-row treatment `hris/overtime-timesheet/page.tsx` got in the
  `timesheet_import` slice.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors, only
  pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit test
  suite (6,128 tests passing, +5 for
  `validateLeaveOpeningBalanceImportRow`/
  `commitLeaveOpeningBalanceImportJob`), `db:test` (`ALL PASSED` -- no new
  db-test file needed, since `hris-leave-permit-business-trip.sql`'s own
  existing ISS-2026-303 fixture already fully covers both RPCs' real
  behavior), `git:check-paths` (clean, 9 files checked), `security:check`
  (clean), and a real `next build` (confirms the new
  `/[tenantSlug]/hris/imports/leave-opening-balance` route).
  `check-release-freeze`'s self-test digests were updated this slice (the
  new document-type migration changed `migrationSetSha256`, HUNDRED-AND-
  FIFTY-FIRST PASS, 549 files; `dbTestSetSha256` unchanged at 277 files,
  no db-test file added), independently re-verified via `pnpm run
  release:check-freeze` passing clean.
  Still open under A4: the other 3 import schemas' own UIs
  (payroll_loan_cutover_import, position_crosswalk_import under HRS;
  inventory_opening_balance_import under OPS), each estimated at the same
  one-wrapper-plus-one-route cost as this slice and the eight before it,
  though `payroll_loan_cutover_import`'s and `position_crosswalk_import`'s
  own document-type-registration state has not yet been directly confirmed
  and should not be assumed to match this slice's own "already fully
  catalogued" precedent without checking.
- 2026-09-17 — A4 (`payroll_loan_cutover_import`, eleventh import schema)
  closed: a near-mechanical port of `hris/imports/leave-opening-balance/`'s
  own trio to `hris/imports/payroll-loans/`, reusing
  `server/policies/csv-import-parse.ts`, `storeFileBytesAndEnqueueScan`, and
  the generic `stageImportRows`/`listImportStagingRows`/`getImportExportJob`
  verbatim. Directly confirmed (per the prior slice's own note not to
  assume) rather than extrapolated: the `import_export_schemas` row was
  already real
  (`20260901010000_create_payroll_loan_cutover_import_adapter.sql`), but no
  document type for the raw source file existed anywhere -- the one
  existing db-test, `scripts/db-tests/hris-payroll.sql`, reuses the same
  generic `master_data_import_source` type the prior slice's own db-test
  reused. New migration
  `20260917060000_register_payroll_loan_cutover_import_source_document_type.sql`
  registers a dedicated `payroll_loan_cutover_import_source` document type
  instead, applying the exact same reasoning the immediately preceding
  `leave_opening_balance_import` slice established: payroll loan balances
  are personal debt/financial obligation data tied to an individual
  employee, at least as sensitive as leave balances, and do not belong
  under a generic commercial-master-data type.
  `server/mutations/payroll.ts` (20+ existing payroll mutation wrappers,
  but ZERO for `validate_payroll_loan_cutover_import_row`/
  `commit_payroll_loan_cutover_import_job`) gained both as a from-scratch
  addition, reusing the generic PLT-131 parsers directly -- this file's own
  pre-existing convention (plain TS object inputs, no Zod, an
  internally-derived error `code`, no explicit `code` param on its
  `PayrollMutationError`) was kept for its other 20+ functions, but the two
  new import wrappers instead follow the cross-slice A4 convention (a
  Zod-validated `CommitPayrollLoanCutoverImportJobInputSchema` in the
  shared `import-export.ts` contracts file) for consistency with every
  other A4 slice's own commit-input shape, matching this session's own
  established precedent of privileging cross-slice A4 consistency over a
  host file's own local style.
  `app.commit_payroll_loan_cutover_import_job` composes the richest
  authority stack of any A4 import schema so far:
  `app.is_support_grant_authority` (Supreme Admin or tenant_admin) AND
  `HRS:Import` AND `HRS:Approve` (additive, never either-or) --
  `HRS:Approve` is required because `app.issue_payroll_loan` itself demands
  it of every caller issuing a loan, and bulk import is not exempt from
  that rule, plus the same conditional MFA step-up and IP-allowlist gates
  `leave_opening_balance_import`/`attendance_device_import`/
  `timesheet_import` carry. Duplicate handling mirrors
  `finance_opening_balance_import`'s/`leave_opening_balance_import`'s own
  idempotency-key-derived-from-staging-row-id convention (backed by a
  partial unique index on `app.payroll_loans` this time, not an
  append-only ledger check) -- a corrected re-upload creates a brand-new
  loan rather than correcting a wrong one. No bespoke write path: every
  valid row calls `app.issue_payroll_loan`, the SAME primitive the manual
  "Issue Loan" form uses, with `p_is_opening_balance=true`, writing one
  `app.payroll_loans` row plus a tail of `app.payroll_loan_installments`
  rows (numbered `(term_count - remaining + 1)..term_count`, never
  renumbered from 1).
  The host page (`hris/payroll/payroll-admin-panel.tsx`) already had its
  own internal `<header>` (unlike attendance/overtime-timesheet/leave's
  prior "no header at all" state) -- this slice threaded a new `tenantSlug`
  prop through `page.tsx` and added the import link inside that existing
  header, rather than adding a redundant second one.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors,
  only pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit
  test suite (6,133 tests passing, +5 for
  `validatePayrollLoanCutoverImportRow`/
  `commitPayrollLoanCutoverImportJob`), `db:test` (`ALL PASSED` -- no new
  db-test file needed, since `hris-payroll.sql`'s own existing fixture
  already fully covers both RPCs' real behavior, including the
  ISS-2026-278 MFA step-up regression), `git:check-paths` (clean, 10 files
  checked), `security:check` (clean), and a real `next build` (confirms
  the new `/[tenantSlug]/hris/imports/payroll-loans` route).
  `check-release-freeze`'s self-test digests were updated this slice (the
  new document-type migration changed `migrationSetSha256`, HUNDRED-AND-
  FIFTY-SECOND PASS, 550 files; `dbTestSetSha256` unchanged at 277 files,
  no db-test file added), independently re-verified via `pnpm run
  release:check-freeze` passing clean.
  Still open under A4: the other 2 import schemas' own UIs
  (position_crosswalk_import under HRS; inventory_opening_balance_import
  under OPS), each estimated at the same one-wrapper-plus-one-route cost as
  this slice and the nine before it -- their own document-type-registration
  state has not yet been directly confirmed and should not be assumed
  either way without checking.
- 2026-09-17 — A4 (`position_crosswalk_import`, twelfth of 12 import
  schemas -- the last one under HRS) closed: a near-mechanical port of
  `hris/imports/payroll-loans/`'s own trio to
  `hris/imports/position-crosswalk/`, reusing
  `server/policies/csv-import-parse.ts`, `storeFileBytesAndEnqueueScan`, and
  the generic `stageImportRows`/`listImportStagingRows`/`getImportExportJob`
  verbatim. Unlike the two immediately preceding slices, this one needed NO
  new migration at all: BOTH the `import_export_schemas` row AND the
  document type it uses were already real, global catalog rows before this
  slice started
  (`20260902040000_create_position_crosswalk_import_adapter.sql`). This
  schema deliberately reuses the existing, shared `employee_document`
  document type (the SAME one `employee_import`'s own bootstrap action
  already publishes) rather than minting its own -- confirmed directly, not
  assumed, per the backlog's own standing note not to extrapolate from
  either of the prior two slices' outcomes.
  `server/mutations/position.ts` (a large pre-existing file covering
  position/grade CRUD and the full propose/decide/cancel employee-position-
  assignment workflow, but ZERO wrapper for
  `validate_position_crosswalk_import_row`/
  `commit_position_crosswalk_import_job`) gained both as a from-scratch
  addition, reusing the generic PLT-131 parsers directly.
  This is the first A4 import whose committed rows are never immediately
  effective: `app.commit_position_crosswalk_import_job` calls
  `app.propose_employee_position_assignment` per valid row -- the SAME
  primitive the single-employee manual wizard at
  `/hris/employees/[masterRecordId]/positions` uses -- landing each as a
  real `pending_approval` proposal, reviewed and decided through that same
  existing wizard; no new approval UI exists or was built for this slice.
  Authority composition requires BOTH `HRS:Import` AND `HRS:Edit`
  (additive, never either-or) -- `HRS:Edit` is required because
  `propose_employee_position_assignment` itself independently demands it of
  every caller -- plus the same conditional MFA step-up and IP-allowlist
  gates every recent HRS slice carries. Notably, this is the first HRS
  import slice whose commit RPC does NOT compose
  `app.is_support_grant_authority`: the migration's own header explains
  that because every row only ever creates a proposal (never an
  auto-effective write), the blast radius is judged low enough that
  `HRS:Import + HRS:Edit` alone is sufficient, unlike the opening-balance
  and payroll-loan-cutover slices' own administrative-gate requirement.
  The host page (`hris/positions/page.tsx`) already had its own header with
  two existing links (`Bulk reorganization`, `View organization tree`) --
  this slice added a third link inside that same header, using this file's
  own pre-existing plain `<a>` tag convention rather than importing `Link`.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors,
  only pre-existing warnings after fixing one new unescaped-apostrophe
  error in the wizard's own copy; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit
  test suite (6,139 tests passing, +6 for
  `validatePositionCrosswalkImportRow`/`commitPositionCrosswalkImportJob`),
  `db:test` (`ALL PASSED`, including the existing ISS-2026-066 item 3
  regression block covering both RPCs' real behavior end to end -- no new
  db-test file needed), `git:check-paths` (clean, 8 files checked),
  `security:check` (clean), and a real `next build` (confirms the new
  `/[tenantSlug]/hris/imports/position-crosswalk` route).
  `check-release-freeze`'s self-test digests are UNCHANGED from the
  HUNDRED-AND-FIFTY-SECOND PASS -- no migration or db-test file was added
  or modified this slice, independently re-verified via `pnpm run
  release:check-freeze` passing clean.
  **A4 is now down to its final schema**: `inventory_opening_balance_import`
  under OPS -- the only remaining import schema without a UI. Its own
  document-type-registration state has not yet been directly confirmed and
  should not be assumed either way without checking, per this backlog's own
  standing lesson from the last three slices.
- 2026-09-17 — A4 (`inventory_opening_balance_import`, twelfth and FINAL
  import schema) closed: **A4 is now fully DONE**, all 12 import schemas
  finally have a real, complete UI end to end. A near-mechanical port of
  `hris/imports/payroll-loans/`'s own trio to
  `operations/imports/inventory-opening-balance/`, reusing
  `server/policies/csv-import-parse.ts`, `storeFileBytesAndEnqueueScan`,
  and the generic `stageImportRows`/`listImportStagingRows`/
  `getImportExportJob` verbatim. Directly confirmed (never assumed): the
  `import_export_schemas` row was already real, registered in
  `20260831260000_create_inventory_and_leave_opening_balance_import_adapters.sql`
  -- the SAME migration that also created `leave_opening_balance_import`'s
  own schema kind -- but no document type for the raw source file existed
  anywhere; the one existing db-test,
  `scripts/db-tests/master-data-import.sql`, reuses the generic
  `master_data_import_source` type. New migration `20260917070000`
  registers a dedicated, OPS-owned `inventory_opening_balance_import_source`
  document type instead, applying the identical reasoning the two
  immediately preceding slices established.
  `server/mutations/inventory-ledger.ts` (5 existing WMS mutation wrappers
  -- post/reserve/release/consume/reverse -- but ZERO for
  `validate_inventory_opening_balance_import_row`/
  `commit_inventory_opening_balance_import_job`) gained both as a
  from-scratch addition, reusing the generic PLT-131 parsers directly.
  `app.commit_inventory_opening_balance_import_job` composes the same
  authority stack `commit_payroll_loan_cutover_import_job`/
  `commit_leave_opening_balance_import_job` compose: BOTH
  `app.is_support_grant_authority` AND `OPS:Import` (additive), plus a
  conditional MFA step-up and IP-allowlist gate. The importer also needs
  genuine record scope over each row's own warehouse --
  `app.post_inventory_movement` checks `app.can_access_record` against the
  warehouse's own company org unit, invisible in this RPC's own guard list
  since it lives inside the primitive itself. Duplicate handling mirrors
  the same idempotency-key-derived-from-staging-row-id convention every
  opening-balance-style A4 slice uses -- a corrected re-upload posts a
  brand-new, additive stock movement rather than correcting a wrong one; a
  genuine correction requires `app.reverse_inventory_movement` outside this
  wizard entirely. No bespoke write path: every valid row calls
  `app.post_inventory_movement`, the SAME primitive every other WMS write
  composes.
  No warehouse/inventory-management admin page exists anywhere in this
  codebase yet (confirmed by repo-wide search, mirroring `item_import`'s
  own identical situation) -- this page is standalone and unlinked,
  mirroring `finance/config/page.tsx`'s own precedent.
  Full Tier A gate suite verified clean: `typecheck`, `lint` (0 errors,
  only pre-existing warnings; two new server-only files added to
  `eslint.config.js`'s `serviceRoleImportGuard` ignores list), the unit
  test suite (6,145 tests passing, +6 for
  `validateInventoryOpeningBalanceImportRow`/
  `commitInventoryOpeningBalanceImportJob`), `db:test` (`ALL PASSED`,
  including `master-data-import.sql`'s own inventory-adapter regression --
  no new db-test file needed), `git:check-paths` (clean, 8 files checked),
  `security:check` (clean), and a real `next build` (confirms the new
  `/[tenantSlug]/operations/imports/inventory-opening-balance` route).
  `check-release-freeze`'s self-test digests were updated this slice (the
  new document-type migration changed `migrationSetSha256`, HUNDRED-AND-
  FIFTY-THIRD PASS, 551 files; `dbTestSetSha256` unchanged at 277 files, no
  db-test file added), independently re-verified via `pnpm run
  release:check-freeze` passing clean.
  **A4 ("No import UI over 12 working import schemas") is now DONE.** All
  12 import schemas -- `finance_opening_balance_import`, `employee_import`,
  `vendor_import`, `vendor_rate_import`, `customer_import`, `item_import`,
  `attendance_device_import`, `timesheet_import`,
  `leave_opening_balance_import`, `payroll_loan_cutover_import`,
  `position_crosswalk_import`, and `inventory_opening_balance_import` --
  have a real, complete, Tier-A-gate-verified UI end to end (bootstrap,
  upload+scan, stage+validate, review, commit), built across twelve
  narrow, independently-verified slices this session.

- 2026-09-17 — A6 (ePOD evidence signed download, the 4th and final of the
  audit's own named deadlocked upload/download flows) closed. ePOD's own
  upload side was already fixed by an earlier pass this session
  (real signature/photo `File` objects, real bytes stored, a real malware
  scan enqueued); `epod-panel.tsx` still never rendered
  `capture.signatureFileId`/`photoFileIds` at all, so there was no way to
  ever fetch that evidence back out. Scoping this slice surfaced a second,
  more fundamental gap: repo-wide grep confirmed the `epod` document type
  itself was never registered by any real (non-db-test) migration --
  every one of 10+ `scripts/db-tests/*.sql` fixtures registers it
  independently, against its own disposable database, and nothing else
  ever did. Since `app.resolve_document_type_definition` (the function
  `app.initiate_file_upload` always calls first) raises
  `document_type_not_configured` whenever no tenant has ever published a
  `document:<code>` config object, and a tenant can never publish one
  until the matching `app.config_types` row exists, a genuinely fresh
  tenant's first ePOD evidence upload would have failed immediately in
  spite of `app.set_epod_evidence`/`app.initiate_file_upload` both being
  fully wired and fully tested -- the exact same class of gap
  `20260914060000_register_gps_device_installation_document_type.sql`
  already fixed for `gps_device_installation` (that migration's own
  comment explicitly name-drops `epod`/`pod` as a same-shaped example
  still outstanding at the time it was written).
  Fix: new migration `20260917080000_a6_epod_evidence_signed_download.sql`
  registers `epod`/`document:epod` as real global catalogue rows
  (mirroring `20260914060000`'s own shape verbatim), then adds
  `app.authorize_epod_evidence_file_access` (a narrowly-scoped sibling of
  `app.authorize_shipment_document_evidence_file_access`/
  `app.authorize_ticket_attachment_evidence_file_access`) and
  `app.access_epod_evidence_for_download`, parameterized by `p_file_id`
  (the ticket-attachment precedent's own shape, since
  `app.epod_captures` carries both a single `signature_file_id` and a
  `photo_file_ids` array). Gated on `app.evaluate_permission(..., 'OPS',
  'Download')` plus `app.can_access_record` against the parent shipment
  order's own `owner_user_id`/`lead_record_scope_org_unit_ids` -- the
  SAME record-scope bar the shipment document checklist's own sibling RPC
  already uses, since ePOD evidence has no narrower record-scope concept
  of its own. ISS-2026-146-safe from birth: the initial not-found branch
  folds `app.has_active_tenant_membership` in, so a zero-relationship
  cross-tenant probe against a real `file_id` never sees this tenant's
  real `tenant_id` interpolated into a later `insufficient_authority`
  message. Plus matching `public.*` wrappers for both new functions
  (RGL-394 Option-2).
  `server/mutations/epod-capture-review.ts` gained
  `getEpodEvidenceSignedDownloadUrl` (mirrors
  `getShipmentDocumentChecklistItemSignedDownloadUrl`/
  `getTicketAttachmentSignedDownloadUrl` exactly: calls the RPC first,
  only mints a real Storage signed URL once `accessResult='granted'`,
  `storage_path`/`bucketId` never leave the function) plus two new
  classified error codes and 4 new unit tests (all passing).
  `server/contracts/epod-capture-review/epod-capture-review.ts` gained
  the matching `EpodEvidenceDownloadSource`/`EpodEvidenceSignedDownload`
  schema pair. `actions.ts` (already on `eslint.config.js`'s
  `serviceRoleImportGuard` ignores list -- no `eslint.config.js` edit
  needed) gained `downloadEpodEvidenceAction`; `epod-panel.tsx` now
  renders a "Get signature/photo download link" control per evidence
  file on every capture version in history (not just the latest, since
  full version history -- including rejected versions' own evidence --
  remains inspectable by design), mirroring `DocumentChecklistPanel`'s
  own "Get download link" form exactly.
  Full Tier A gate suite verified clean: `typecheck`, targeted + full
  `lint` (0 errors, only pre-existing warnings), the unit test suite
  (+4 new tests, 6149/6149 pass), `db:test` (`ALL PASSED` -- no new
  db-test file needed, since every existing fixture that registers
  `epod` itself continues to do so unaffected by this migration's own
  idempotent `on conflict (code) do nothing`), `git:check-paths` (clean,
  8 files checked), `security:check` (clean), `release:check-freeze`
  (self-test digests updated -- the new migration changed
  `migrationSetSha256`, HUNDRED-AND-FIFTY-FOURTH PASS, 552 files;
  `dbTestSetSha256` unchanged at 277 files, no db-test file added --
  independently re-verified via `pnpm run release:check-freeze` passing
  clean), and a real `next build`.
  **A6 ("No Storage bucket/policies; uploads never store bytes;
  malware-scan status never advances, deadlocking 3+ flows") is now
  DONE.** All 4 real evidence-upload flows -- vendor compliance, shipment
  document checklist, ticket-reply attachments, and ePOD -- now have real
  upload+scan AND real signed download. Out of A6's own scope, tracked
  separately under D4: every scan still fails closed until an operator
  configures the platform integration encryption key and a real
  VirusTotal API key.

- 2026-09-17 — A7 (packing list, the 5th printable document) closed. A
  scoping pass confirmed ATW-018's own domain
  (`app.wms_packing_tasks`/`app.wms_packages`/`app.wms_package_lines`,
  `server/queries/wms-packing.ts` and its own real, tested
  `server/mutations/wms-packing.ts`) was genuinely real and mutation-backed
  -- not a read-only derived view -- but had zero pages/actions anywhere
  in `app/`, confirmed by repo-wide grep for `wms-packing`/`packing-list`/
  the RPC names themselves. Unlike invoice (which printed directly from an
  existing list row), there was no host page anywhere to attach a print
  link to at all: `operations/` has only a warehouse/zone topology page,
  and the only page touching `wms_outbound_orders` is the customer-facing
  portal, which by explicit prior design decision must never show
  packing/pick internals to customers -- wrong authority domain and wrong
  audience.
  Fix: `server/documents/packing-list-document.tsx` (pure `@react-pdf/
  renderer` presentation component, mirroring purchase-order-document.tsx's
  own header+line-table+totals+signature-block shape, repeated once per
  physical package since a warehouse worker checks off one carton/pallet
  at a time against its own printed section) and
  `server/documents/generate-packing-list.server.ts` (assembles the data
  from `getWmsPackingTask`/`listWmsPackages`/`listWmsPackageLines`/
  `getWmsOutboundOrder`/`listTenantWarehouses`/`getAccountById`/
  `getItemMaster` -- no new schema, no new RPC; item code/name is resolved
  once per distinct `itemMasterId` across every line via a `Map` cache,
  never once per line, since the same item is frequently packed into more
  than one package/line on a real outbound order; warehouse label is
  resolved by fetching the caller's own scoped `listTenantWarehouses` and
  matching by id, the only read query this codebase has for warehouse
  identity, mirroring purchase-order's own "fetch the scoped list, pick
  the matching row" precedent for vendor address). New Route Handler
  `operations/packing-tasks/[packingTaskId]/print/route.ts`, gated by
  `resolveOperationsAccessForRequest` exactly like the purchase-order/
  surat-jalan/POD routes, mapping `packing_task_not_found` to a real 404.
  New standalone page `operations/packing-tasks/[packingTaskId]/page.tsx`
  (read-only: a packing task's header plus its packages table and the
  print link) -- unlinked from any other page, mirroring `finance/config/
  page.tsx`'s/`inventory-opening-balance`'s own standalone precedent,
  since no host list page for packing tasks exists anywhere yet (a
  genuinely separate, larger gap -- a real internal outbound-order/
  pick-pack worklist -- explicitly out of this printable-document slice's
  own scope). Neither new page/route needed adding to `eslint.config.js`'s
  `serviceRoleImportGuard` ignores list -- both use the RLS-scoped
  `createSupabaseServerClient`, never the service-role client.
  Rendering verified directly with a throwaway `renderToBuffer` smoke
  script against representative fake data (both a confirmed package with
  lines and an open, empty package) before this commit -- 5320 real PDF
  bytes produced, no react-pdf runtime style error (a class of bug
  `tsc`/`eslint` cannot catch, since `StyleSheet.create` values are only
  validated by react-pdf itself at render time).
  Full Tier A gate suite verified clean: `typecheck`, targeted + full
  `lint` (0 errors, only pre-existing warnings), the full unit test suite,
  `db:test` (`ALL PASSED` -- no schema change, so no new db-test file
  needed), `git:check-paths`, `security:check`, `release:check-freeze`
  (unchanged -- no new migration, no new db-test file, so neither digest
  moves), and a real `next build` confirming the two new routes compile.
  A7 remains PARTIAL: faktur pajak is still gated on new backend RPC work
  and the tax-SME product decisions tracked elsewhere in this backlog
  (C1/C2) -- not actionable without a product ruling.

- 2026-09-17 — NEW-2 closed: POD (proof of delivery) now embeds the real
  signature/photo evidence images, the follow-on A6's own closure
  unblocked. `generate-pod.server.ts` gained a second, required
  `serviceRoleClient` parameter (typed `EpodEvidenceDownloadClient`) --
  every existing read (shipment order, ePOD capture history) still goes
  through the caller's own RLS-scoped `client`; only the new
  `getEpodEvidenceSignedDownloadUrl` call (service_role-only, mirroring
  `downloadEpodEvidenceAction`'s own identical reasoning) uses the new
  client. A per-file failure (denied access, a since-deleted file, a
  transient error) degrades to `null`/an empty array rather than
  throwing -- `resolveEvidenceImageUrl`'s own try/catch -- so one bad
  evidence file never blocks printing the rest of an otherwise real,
  already-approved POD. `pod-document.tsx` renders each resolved signed
  URL straight into `@react-pdf/renderer`'s `Image` component (a
  dedicated Signature section plus a wrapped Delivery photos row);
  falling back to the original text note when an image could not be
  resolved. `Image` needed two targeted `eslint-disable-next-line
  jsx-a11y/alt-text` comments -- react-pdf's own `Image` renders into a
  PDF, not the DOM, and its `ImageProps` type carries no `alt` prop at
  all, confirmed by reading its own `.d.ts` before adding the disables
  rather than guessing. `pod/route.ts` now also constructs a
  service-role client (added to `eslint.config.js`'s
  `serviceRoleImportGuard` ignores list, alphabetically after this same
  route's own sibling `actions.ts`).
  Rendering verified directly with a throwaway `renderToBuffer` smoke
  script, once with fake image data URIs attached and once without, to
  prove both the image-embedding path and the graceful-fallback path
  actually render (a class of bug `tsc`/`eslint` cannot catch, since
  react-pdf validates `Image`/style values only at render time).
  Full Tier A gate suite verified clean: `typecheck`, targeted + full
  `lint` (0 errors, only pre-existing warnings, after fixing the two
  `jsx-a11y/alt-text` findings above), the full unit test suite,
  `db:test` (`ALL PASSED` -- no schema change), `git:check-paths`,
  `security:check`, `release:check-freeze` (unchanged), and a real
  `next build`.

- 2026-09-17 — B7 (credit-control half, "Invoicing keyed off a hand-copied
  UUID; no credit control") closed -- the worklist-UI half was fixed
  earlier this session; this half was explicitly named at the time as
  "a separate, larger, deliberately excluded piece of work, untouched
  here." `app.check_customer_credit` (COM-157) was confirmed, by reading
  its own live function body rather than assuming, to NOT be a stub: it
  already read a real `app.credit_profiles`/`app.credit_profile_overrides`
  row and persisted every outcome to `app.credit_check_snapshots`. Two
  real gaps remained: (1) it never consulted actual AR exposure, only the
  static approved limit, so a customer already at their limit from prior
  unpaid invoices could still be approved for a brand-new request that
  alone sat under the limit; (2) it was dead-gated code -- reachable only
  through its own manual "Check eligibility" widget on the Account detail
  page, never from any order-acceptance path (every real candidate --
  `app.prepare_job_order_handoff`/`app.confirm_job_order`/`app.create_
  shipment_order_from_job`/`app.confirm_shipment_order` -- confirmed to
  call no credit check at all).
  Fix: new migration `20260917090000_b7_credit_control_ar_exposure_and_
  job_order_handoff_gate.sql`. `check_customer_credit` now sums real
  `app.finance_ar_open_items.open_amount` (FIN-196, `status <> paid`,
  same currency) and adds it to the requested amount before comparing
  against the effective limit -- reading the base table directly, not
  `app.get_finance_ar_exposure_summary` (which hard-gates on `FIN:View`
  and would force a permission regression onto every credit check).
  `app.prepare_job_order_handoff` -- the correct singular acceptance-moment
  gate point, matching `check_customer_credit`'s own "the one
  deterministic, reproducible pre-conversion check" framing, and NOT
  `confirm_job_order`/`confirm_shipment_order` (pure status transitions
  with no new financial-exposure decision) -- now evaluates credit for the
  converted account and the quotation's own real total, raising
  `credit_blocked` for an affirmative credit-control decision already in
  force (`blocked_limit`/`blocked_hold`/`blocked_not_active`/`blocked_
  currency_mismatch`). Deliberately does NOT block on `blocked_no_profile`:
  credit profiles are opt-in in this product (`app.request_customer_
  credit_profile` is user-initiated, never automatic), confirmed live that
  `scripts/db-tests/commercial-job-order-lineage.sql`'s own existing
  happy-path tests never set one up at all -- hard-blocking every account
  that has simply never engaged credit control would have retroactively
  made a credit profile mandatory before ANY job order could ever be
  accepted for ANY account, a far larger, undisclosed product-shape change
  than "the limit a tenant already approved should actually be enforced."
  A real, load-bearing design correction happened mid-slice: a first draft
  had `prepare_job_order_handoff` call the PUBLIC `check_customer_credit`
  directly, reasoning "every COM:Edit role already holds COM:View." That
  untested assumption broke live -- a full `pnpm run db:test` pass (this
  repository's own 60+ existing `prepare_job_order_handoff` callers, not
  just this slice's own two files) failed on `scripts/db-tests/customer-
  booking-requests.sql`, whose staff role holds COM:Edit but not COM:View.
  Fixed by extracting the decision core into a new internal
  `app._evaluate_customer_credit` (no authority check of its own, always
  unmasked -- masking is the caller's concern), which the public
  `app.check_customer_credit` now delegates to (adding the COM:View gate
  plus per-caller masking) and `app.prepare_job_order_handoff` calls
  directly (already gated on COM:Edit, no second transitive check) --
  re-verified clean via a second full `db:test` pass afterward. This is
  exactly the kind of regression this session's own "run the real gates,
  never assume" discipline exists to catch.
  `scripts/db-tests/commercial-credit-commercial-control.sql` gained a new
  test block (a real AR open item posted for an account already under an
  active override, proving the exposure-aware `blocked_limit` outcome is
  additive, not "any AR at all blocks everything," plus a real
  `prepare_job_order_handoff` call proving the new gate raises
  `credit_blocked` and creates no `app.job_order_handoffs` row) --
  including a new `pg_temp` fixture helper mirroring `finance-accounts-
  receivable.sql`'s own precedent for minting a real, AR-postable invoice.
  `scripts/db-tests/commercial-job-order-lineage.sql` had one existing
  assertion genuinely UPDATED, not weakened: the payload's own "credit"
  field, previously always null for an account that had never been
  checked, is now genuinely populated with a real `blocked_no_profile`
  snapshot, since `prepare_job_order_handoff` performs a real check on
  every call -- the assertion now expects that real, disclosed value.
  `server/mutations/job-order-lineage.ts` gained the `credit_blocked`
  error code plus a new unit test.
  Full Tier A gates verified clean: `typecheck`, targeted + full `lint`
  (0 errors, only pre-existing warnings), the full unit test suite
  (6150/6150, including the release-freeze self-test after its digest
  update), `db:test` (`ALL PASSED` across all 280+ files, including both
  extended fixtures and the one that initially broke),
  `git:check-paths` (6 files), `security:check`,
  `release:check-freeze` (HUNDRED-AND-FIFTY-FIFTH PASS, both digests
  updated -- a new migration file and two extended db-test fixtures), and
  a real `next build`.
  **B7 ("Invoicing keyed off a hand-copied UUID; no credit control") is
  now DONE** -- both the worklist-UI half and the credit-control half.
- 2026-09-18 — B2a ("GL is write-only -- no trial balance/account balance")
  scoped and closed via a dedicated research pass, the same "verify before
  trusting a deferred label" discipline that found B7's own real bounded
  core. The original DEFERRED_LARGE disposition was copied verbatim from
  the audit's own summary text and had never itself been independently
  re-verified (unlike F4/E5-ETA-half, which had already received a
  dedicated pass). Findings, all confirmed by reading the actual schema and
  code, never assumed: `app.finance_journals`/`app.finance_journal_lines`
  (FIN-203) is a real, enforced double-entry ledger --
  `app.validate_finance_journal_line_balance` is the one shared rule both
  the manual and every system/subledger-sourced posting path call, so no
  unbalanced journal can exist, and a posted journal is never edited in
  place (reversal always posts a new offsetting journal, confirmed via
  20260826030000 and yesterday's own 20260917010000 fix), so summing
  `finance_journal_lines` directly for any posted, dated cutoff is sound.
  `app.finance_accounts` (FIN-192) already carries a hard-constrained
  `account_type` (asset/liability/equity/revenue/expense) and
  `normal_balance` -- exactly the classification a trial balance needs, a
  hard DB constraint, not inferred. `app.get_finance_cash_position`
  (20260729250000) already does the exact "sum debit-minus-credit, as of a
  cutoff date" query shape once, for one hardcoded bank-reconciliation
  account against the subledger view -- a direct precedent to adapt,
  generalized here to every account in the chart and to the canonical GL
  directly. Closed: new migration
  `20260918000000_b2a_finance_trial_balance.sql` adds
  `app.get_finance_trial_balance(p_tenant_id, p_company_id, p_as_of_date,
  p_actor_auth_user_id)` (+ its `public.*` wrapper, RGL-394 Option-2) --
  FIN:View-gated, joins every `finance_accounts` row for the tenant/company
  against posted, dated-eligible `finance_journal_lines`, returns
  `debit_balance`/`credit_balance` net and mutually exclusive per the
  standard trial-balance columnar convention. Real, disclosed limitation
  carried forward (ties to the still-open B4 finding, "multi-currency
  postings summed as raw numbers"): `finance_journals.currency` is one
  field per whole journal, `finance_journal_lines` carries no currency of
  its own, and `finance_accounts.currency_restriction` is defined but never
  enforced at posting time (checked: neither
  `app.create_finance_journal_draft` nor `app.post_finance_subledger_batch`
  validates a line's journal currency against its account's
  `currency_restriction`) -- nothing stops the same GL account from
  receiving lines from journals in different currencies. Rather than hide
  this behind a silently-blended sum, `app.get_finance_trial_balance`
  groups by (account, journal currency actually posted against it) and
  returns one row per currency in play -- an account touched by exactly one
  currency (the normal case) yields exactly one row, no different from a
  single blended figure; an account touched by more than one currency
  yields one row per currency rather than a silently-wrong blended total.
  A single reporting-currency figure would require a functional-currency
  conversion layer that does not exist anywhere in this schema today --
  genuinely out of this slice's own bounded scope.
  New db-test file `scripts/db-tests/finance-trial-balance.sql` proves the
  FIN:View authority gate, cross-tenant isolation, that only posted
  journals on/before `p_as_of_date` count (a draft-only journal and a
  future-dated posted journal are each excluded from a `2026-03-31`
  as-of-date read and only included once the cutoff moves past them), the
  multi-currency one-row-per-currency behavior directly (an account touched
  by both USD and EUR postings yields two separate rows, never a blended
  80 for a 50 USD + 30 EUR case), that a zero-activity account still
  appears at 0/0 with a null currency, that company scoping mirrors
  `app.list_finance_accounts`' own established `company_id is not distinct
  from p_company_id` semantics, and that `p_as_of_date` is required, never
  silently treated as "no cutoff".
  Still open under B2: P&L, balance sheet, GL report, and year-end close --
  these need period-scoped net-income roll-up (a materially different
  query shape than a point-in-time trial balance), account-hierarchy
  subtotaling (a `parent_account_id` hierarchy exists but nothing walks it
  to sum children into a control-account subtotal yet), and a real
  reporting-currency/FX conversion layer tied to the still-open B4 finding
  -- genuinely larger, multi-part work matching the original "weeks"
  framing when scoped to those four together. B2 is PARTIAL, not DONE.
  Full Tier A gates verified clean: `typecheck`, full `lint` (0 errors,
  only pre-existing warnings), the full unit test suite (including the
  release-freeze self-test after its digest update), a full `pnpm run
  db:test` (`ALL PASSED`), `git:check-paths`, `security:check`, and
  `release:check-freeze` (HUNDRED-AND-FIFTY-SIXTH PASS, both digests
  updated -- one new migration file, one new db-test file).
- 2026-09-18 — E6 (webhook half) closed via a dedicated research pass, the
  same "verify before trusting a deferred label" discipline that found
  B7's and B2a's own real bounded cores. The original finding ("Outbound
  webhooks have no publisher. `app.queue_webhook_delivery` is referenced
  by 0 other database functions and nothing outside its own module")
  turned out true on exactly one narrow point -- confirmed by reading the
  actual current code, never assumed: `supabase/migrations/20260719150000_
  create_api_key_webhook_primitives.sql` already defines a real,
  complete schema (`app.webhook_endpoints`/`webhook_subscriptions`/
  `webhook_deliveries`/`webhook_delivery_attempts`, HMAC-SHA256 signing,
  an SSRF guard at registration); `20260804040000_create_intelligence_
  webhook_management.sql` (IAE-012) already extended `app.queue_webhook_
  delivery` to enqueue a real `app.jobs` `webhook_retry` job per genuinely
  new delivery; `lib/webhooks/process-webhook-delivery-job.server.ts`
  already is a real outbound HTTP client (fetch with a 10s timeout, HMAC
  headers, a dispatch-time SSRF re-check catching DNS rebinding, a
  tenant-id cross-check closing ISS-2026-178) already wired into the
  production `scripts/jobs/supervisor.ts` own "webhook-delivery" lane
  (the same real dispatch loop A5 already wired up for every other job
  type); and `app/(tenant)/[tenantSlug]/admin/api-keys/` already gives a
  tenant admin a real, reachable UI to register an endpoint, rotate its
  secret, send a test delivery, and replay a dead-lettered one. The one
  real, confirmed gap: zero business-logic call sites anywhere in this
  repository ever called `app.queue_webhook_delivery` from a real domain
  mutation -- reachable only from its own test file and the manual
  "send test" console action, precisely the same "real, tested, dead-
  gated" shape B7's own `check_customer_credit` had.
  Closed: new migration
  `20260918010000_e6_wire_webhook_delivery_triggers.sql` adds `app.
  _enqueue_webhook_delivery` -- a new internal, authority-check-free
  decision/fan-out core extracted from `app.queue_webhook_delivery`
  (mirrors B7's own `app._evaluate_customer_credit` precedent exactly):
  `app.queue_webhook_delivery`'s own `app.check_webhook_trigger_
  authority` gate (requiring the calling identity to hold active tenant
  membership) is correct for its own existing callers (the manual
  send-test/replay console actions, where the acting identity IS the
  literal caller), but would be the WRONG gate to transitively impose on
  a business-event trigger fired from inside an already-authorized
  mutation -- each of `app._create_ticket`/`app.issue_finance_invoice`/
  `app.transition_shipment_order` already enforces its own correct
  authority model for the underlying action (including a customer-channel
  ticket, filed by a `customer_user`-layer identity whose own membership
  shape this migration does not need to, and must not, reason about to
  fire a webhook side effect of an already-authorized action).
  `app.queue_webhook_delivery` itself becomes a thin wrapper (check
  authority, then delegate) -- its own existing callers and grants are
  entirely unaffected. One additional `perform app._enqueue_webhook_
  delivery(...)` call was added to each of the three event types the
  schema's own IAE-012 seed data already anticipated, at their natural,
  already-existing, already-tested trigger points: `shipment.status_
  changed` in `app.transition_shipment_order` (idempotency-keyed per
  transition, since one shipment order fires this many times over its
  life -- never deduped against a prior transition on the same order);
  `ticket.created` in `app._create_ticket` (the one shared engine behind
  all three channels -- internal/customer/helpdesk -- so wiring it once
  covers every channel); `invoice.issued` in `app.issue_finance_invoice`
  (a curated field set, never the raw row, sent to a tenant-registered
  external endpoint).
  Self-caught regression during authoring, fixed before commit, not after
  a test failure alone caught it downstream: an initial grep for
  `transition_shipment_order`'s own current live definition used a
  lowercase-only pattern and missed two later hardening migrations that
  use uppercase `CREATE OR REPLACE FUNCTION`
  (`20260730520000_harden_stale_version_no_op_and_swallowed_idempotency_
  guard.sql`, the ATW-032/ISS-2026-034 fix for a swallowed lost-update
  bug, and `20260902201000_harden_tenant_id_disclosure_operations.sql`,
  the ISS-2026-146 fold-in that prevents a zero-membership caller from
  ever reaching a tenant-id-disclosing `insufficient_authority` branch) --
  a full `db:test` run caught the live symptom directly (a cross-tenant
  isolation assertion in `operations-shipment-lifecycle.sql` expecting a
  generic `shipment_order_not_found` instead got the older, tenant-id-
  disclosing `insufficient_authority` branch). Fixed by re-deriving the
  function from a case-insensitive search and byte-for-byte diffing all
  three replaced functions (`app._create_ticket`, `app.issue_finance_
  invoice`, `app.transition_shipment_order`) against their true latest
  live bodies (two dropped, purely cosmetic comments were also restored)
  before this migration was committed -- the same "never assume, always
  verify with the real full gate suite" discipline this session has
  applied throughout.
  New db-test file `scripts/db-tests/webhook-business-event-triggers.sql`
  proves: a real helpdesk-channel ticket creation, a real customer-channel
  ticket creation, a real invoice issuance, and a real shipment order
  transition each genuinely enqueue a real `app.webhook_deliveries` row
  whose payload matches the real mutated entity (never merely a
  hypothetical wiring); the customer-channel ticket fires the event
  without being blocked by a second, unrelated authority check (this
  migration's own central design claim, directly exercised); a shipment
  order transitioning twice (`draft` -> `confirmed` -> `cancelled`) fires
  two distinct deliveries, never deduped against each other; cross-tenant
  isolation (tenant B's own endpoint never receives tenant A's events);
  a tenant with zero registered webhook endpoints incurs no error creating
  a ticket (a safe no-op, zero delivery rows produced); and that `app.
  queue_webhook_delivery`'s own public authority gate still denies a
  non-member actor, unaffected by the refactor.
  Still open under E6: GraphQL/OpenAPI. Genuinely, confirmedly absent --
  no `graphql`/`apollo` package dependency, no resolver files, no `/api/
  graphql` route, no OpenAPI spec file anywhere in the repository, self-
  disclosed by `server/policies/graphql-complexity.ts`'s own header and
  independently confirmed by two later release-readiness checkpoints
  (`docs/build-log/release-go-live/RGL-396.md`, `RGL-397.md`). A real,
  separate REST-based external API surface does already exist
  (`20260804010000_create_intelligence_public_api_platform.sql`'s own
  API-key gateway with atomic rate limiting and a versioned `app.
  api_versions` registry, plus 8 real route handlers under `app/api/v1/`)
  that could be documented with an OpenAPI spec far more cheaply than
  building GraphQL from scratch, but whether that REST-plus-OpenAPI
  surface is an acceptable substitute for the audit's own literal
  GraphQL requirement is a product/scope decision this session does not
  make unilaterally. E6 is PARTIAL, not DONE.
  Full Tier A gates verified clean: `typecheck`, full `lint` (0 errors,
  only pre-existing warnings), the full unit test suite (6150/6150,
  including the release-freeze self-test after its digest update), a full
  `pnpm run db:test` (`ALL PASSED` across 280+ files, including the one
  that caught the self-corrected regression above), `git:check-paths`,
  `security:check`, `release:check-freeze` (HUNDRED-AND-FIFTY-SEVENTH
  PASS, both digests updated -- one new migration file, one new db-test
  file), and a real `next build`.
- 2026-09-18 — B4 (bounded core) closed via a dedicated research pass, the
  same "verify before trusting a deferred label" discipline that found
  B7's/B2a's/E6's own real bounded cores. The original finding
  ("Multi-currency postings summed as raw numbers, no FX/base-amount
  columns") was carried as one undivided `DEFERRED_LARGE` item ("schema
  redesign across `finance_journals`/`finance_journal_lines`") and had
  never itself been independently re-verified.
  What the research found, all confirmed by reading the actual current
  code, never assumed: `app.get_finance_ar_exposure_summary`/`app.
  get_finance_ap_exposure_summary` (live since 20260729100000/
  20260729130000, last touched by `20260810900000_harden_finance_
  authority_chain_tierc_completeness.sql` -- confirmed via a case-
  insensitive search this time, after E6's own earlier miss on exactly
  this class of mistake) summed `app.finance_ar_open_items.open_amount`/
  `app.finance_ap_open_items.open_amount` with NO currency filter or
  grouping at all. Both are called live by `server/queries/accounts-
  receivable.ts`/`server/queries/accounts-payable.ts` and rendered as a
  "credit exposure" figure a real Finance user sees today -- any
  customer/vendor with open items in more than one currency got a
  financially meaningless blended total. A genuine, live, shipped bug,
  not a theoretical schema gap, matching the severity class of this
  session's own earlier B5/D3-series fixes -- and not a rare edge case,
  since `app.finance_accounts.currency_restriction` is confirmed
  unenforced at posting time (B2a's own research, re-confirmed here), so
  any multi-currency tenant posts to the SAME tenant-wide AR/AP control
  account regardless of currency.
  The "no FX/base-amount columns" half of the finding did NOT require
  inventing new FX machinery or redesigning `finance_journal_lines`, as
  the backlog's own "schema redesign" phrase implied. `app.finance_
  currency_exchange_rate` (FIN-194, 20260728230000) already provides a
  real, governed, versioned (draft->approved->archived), date-effective
  rate registry -- `app.resolve_finance_exchange_rate(tenant, rate_type,
  source_currency, target_currency, as_of)` deterministically resolves a
  real rate with NO authority check of its own (a pure SQL read, already
  the correct shape to call from inside another gated function), and it
  is already proven, exercised, non-theoretical machinery: `app.resolve_
  operations_fx_conversion` (job-profitability) and the loyalty-liability
  consolidated-rollup capability already use the identical "convert each
  currency-scoped total, sum only what actually converted, mark what
  didn't rather than fabricate a rate" pattern this fix mirrors. `app.
  tenant_locale_versions.default_currency` (PLT-119, resolved via `app.
  resolve_tenant_locale`) is already, in practice, this repository's own
  real "base/reporting currency" concept -- already load-bearing for
  exactly this purpose in job profitability and loyalty liability,
  despite that migration's own header disclaiming it as "display
  preference only." This fix reuses it the same way, not a new concept.
  Closed: new migration `20260918020000_b4_ar_ap_exposure_currency_fix.
  sql` widens both functions from a single blended `jsonb` object to a
  real, honest per-currency breakdown (`setof table`, one row per
  currency actually in play -- the same "never blend, group by currency"
  discipline B2a's own trial balance already established), PLUS a
  base-currency-converted figure on each row using the tenant's own
  resolved `default_currency` and the real, already-proven FX machinery
  above. A currency that already matches the tenant's base currency needs
  no rate (`fx_status='identity'`, mirrors `app.resolve_operations_fx_
  conversion`'s own identity fast path); a currency with no published
  rate covering "now" returns `fx_status='rate_unavailable'` with a null
  `base_total_open`/`base_overdue_open` -- NEVER a fabricated or
  silently-zeroed figure, the same discipline the loyalty-liability
  reconciliation's own `partial_rate_unavailable` already established.
  Rolling the honest per-currency figures up into one further grand total
  (if ever wanted) is left as a caller-side decision to the TS/UI layer
  rather than baked into the RPC, so the RPC itself never silently
  presents a partial (some-currencies-unconverted) result as complete.
  Both functions required `DROP FUNCTION` + `CREATE FUNCTION` (a genuine
  return-type change, `jsonb` -> `table(...)`, which `CREATE OR REPLACE`
  cannot perform), so the migration explicitly re-revokes PUBLIC execute
  on schema `app` afterward per this session's own established default-
  privilege convention, plus DROP+CREATE `public.*` pass-through wrappers
  with the full `anon`/`authenticated`/`service_role`/`public` revoke
  pattern (RGL-394 Option-2). The full TS/UI blast radius was updated to
  match the new per-currency array shape: `server/contracts/accounts-
  receivable(-payable)/*.ts` (widened schema plus a shared `fxStatus`
  enum, each module keeping its own independent copy per this codebase's
  established no-cross-import convention between AR and AP), `server/
  queries/accounts-receivable(-payable).ts` (return type now an array),
  both modules' `actions.ts`/`*-forms.tsx` (a per-currency list with an
  empty-state and an `fx_status`-conditional note replacing the old
  single blended figure), and all four corresponding unit test files.
  This intentionally changes the RPCs' observable behavior for a
  zero-open-items caller from one row of zeroes to an empty array --
  disclosed here, not silent, and the UI layer's new empty-state handles
  it directly.
  New db-test coverage added to the existing `finance-accounts-
  receivable.sql`/`finance-accounts-payable.sql` fixture files (mirrored
  pair, no new db-test file needed): the existing exposure-summary test
  rewritten for the new per-row shape, plus a new multi-currency/FX block
  that mints a second open item in a different currency, first proving
  the `rate_unavailable` degrade path with no published rate, then
  publishing and approving a real rate via the governed FIN-194 lifecycle
  (`create_finance_exchange_rate_draft` -> `approve_finance_exchange_
  rate`) and proving exact `converted` base-currency arithmetic, and
  proving exactly two distinct per-currency rows are ever returned --
  never blended into one.
  Still deferred, correctly out of this bounded core's scope: retroactive
  FX-rate persistence on `finance_journal_lines` itself (so a posted
  entry's base-currency value is fixed at posting time rather than
  recomputed live at query time against whatever rate is current then --
  the "true" double-entry-accounting fix), enforcement of `app.finance_
  accounts.currency_restriction` at posting time (a real, separate,
  still-open hardening gap, confirmed unenforced by both B2a's and this
  research pass), and true consolidated multi-currency financial
  statements (trial balance / balance sheet / income statement rolled
  into one reporting currency across every account, not just the two
  AR/AP exposure summaries closed here). B4 is PARTIAL, not DONE.
  Full Tier A gates verified clean: `typecheck`, full `lint` (0 errors,
  only pre-existing warnings), the full unit test suite (6154/6154,
  including the release-freeze self-test after its digest update), a full
  `pnpm run db:test` (`ALL PASSED`, confirmed via grep that no other
  db-test file besides the two directly updated calls either function),
  `git:check-paths`, `security:check`, `release:check-freeze` (HUNDRED-
  AND-FIFTY-EIGHTH PASS, both digests updated -- one new migration file,
  zero new db-test files, two existing db-test files gaining real new
  coverage), and a real `next build`.
- 2026-09-18 — A2b (customer-portal-sign-in half) closed via a dedicated
  research pass, the same "verify before trusting a deferred label"
  discipline that found B7's/B2a's/E6's/B4's own real bounded cores. The
  original finding ("Customer portal has no sign-in route; no vendor
  principal layer exists at all") was carried as one undivided
  `DEFERRED_LARGE` item ("vendor layer is a schema-level product
  decision") and bundles two genuinely different situations.
  The vendor principal layer half is confirmed, by direct evidence this
  session had not previously surfaced, to be a real, deliberately
  RATIFIED PRODUCT decision, not an oversight: `docs/build-log/phase-06/
  PRC-267.md` ("Optional Vendor Portal") is explicitly `BLOCKED` --
  pending a Platform-level external-identity ADR (`docs/adr/ADR-0022`)
  that was never ratified -- and `docs/adr/ADR-0025` Part A instead
  ratifies the alternative actually shipped: vendor (and customer) API
  keys reuse `app.api_keys`, data-scoped never actor-scoped, staff-issued
  only, confirmed by `20260804030000_create_intelligence_vendor_api.sql`'s
  own header ("No fifth principal layer... no login/session concept at
  all"). The routes this session itself had just seen in a `next build`
  (`/vendor-intake/[token]`, `/api/v1/vendor/assignments/...`) are exactly
  this deliberate substitute, not a persistent vendor login -- confirmed
  live: no `app.vendor_users`/`app.vendor_principals` exists anywhere.
  `DEFERRED_LARGE` stays accurate for the vendor half; this migration does
  not touch that boundary.
  The customer-portal-sign-in half was stale, not accurate. The
  `customer_user` principal layer (ADR-0024) is real, extensive, and
  already load-bearing -- ~90 migrations, dozens of `server/contracts|
  mutations|queries/customer-portal-*` files, real sign-in via the shared
  `app/(public)/login/actions.ts` entry point every layer uses. What was
  genuinely still missing was narrow and mechanical, not a product/schema
  decision: CPL-300 (`20260801010000_create_customer_portal_account_
  scope.sql`) shipped `app.grant_initial_customer_portal_account_admin`
  (tenant-admin-only bootstrap seeding the first account_admin on a
  brand-new account) and `app.accept_customer_portal_invite` (an invited
  identity accepting a subsequent self-service invite) with real, tested
  RPCs and typed `server/mutations/customer-portal-scope.ts` wrappers --
  but that migration's own §9 deliberately chartered "the full Customer
  User Management UI" to CPL-315, which built the self-service invite/
  role/status/access-review UI for an ALREADY-active account_admin, never
  a caller for either of these two RPCs. Confirmed by a repo-wide grep:
  zero non-test/non-contract call sites for either function anywhere in
  `app/`, `server/`, or `lib/` before this migration.
  A deeper, previously-undisclosed gap the research surfaced: there was no
  way for an invited-but-not-yet-accepted identity to ever DISCOVER their
  own pending membership id/version to accept it. `app.get_customer_
  portal_scope_context`/`app.resolve_customer_account_scope` both
  intentionally scope to ACTIVE memberships only (the customer_user-layer
  principal marker is granted at ACCEPT time, not invite time, per `app.
  accept_customer_portal_invite`'s own Tier C review fix comment), and
  `app.list_customer_portal_account_memberships` is account_admin-only --
  an invited-but-not-active member cannot call it, by definition.
  `lib/portal/customer-portal-guard.ts`'s own "forbidden" branch is
  exactly the state an invited identity was stuck in: `customer-portal/
  page.tsx` rendered a generic denied message with no path forward.
  Closed: new migration `20260918030000_a2b_customer_portal_sign_in_
  entry_points.sql` adds `app.list_my_pending_customer_portal_invites` --
  the one deliberate exception to "only an active customer_user may read
  its own scope" (mirrors `app.grant_initial_customer_portal_account_
  admin`'s own documented exception to "Layer-4-only, never staff RBAC"),
  self-identity-checked only (`app.assert_actor_is_session_identity`), no
  further authority/layer check needed since the result is already scoped
  to the caller's own `auth_user_id` -- a caller with zero genuine pending
  invites gets a real empty array, never an error, mirroring every other
  self-scoped "list my own X" RPC in this repository. RGL-394 Option-2
  `public.*` wrapper included, with the ERR-2026-004 `anon`/`authenticated`/
  `service_role`/`public` explicit revoke this session has repeatedly had
  to apply to a fresh standalone-migration wrapper (the platform-level
  `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public` rule
  otherwise silently leaves an `anon` grant behind) -- caught immediately
  by `public-api-wrapper-regression.sql`'s own zero-tolerance grant-set
  check on the first quick-iteration run, fixed before it ever reached the
  full suite.
  The TS/UI blast radius: `server/contracts/customer-portal-scope/
  customer-portal-scope.ts` (`CustomerPortalPendingInviteSchema`), `server/
  queries/customer-portal-scope.ts` (`listMyPendingCustomerPortalInvites`)
  -- `customer-portal/page.tsx`'s own "forbidden" branch now independently
  checks for a real pending invite (via a direct `supabase.auth.getUser()`
  call, deliberately NOT through the shared guard's own "forbidden" state,
  which carries no `authUserId` and is reused by 30+ other customer-portal
  pages this fix does not touch) and renders a new "Accept invite" panel
  (`pending-invites-panel.tsx` + a new `accept-invite-actions.ts` Server
  Action composing the already-existing, already-tested
  `acceptCustomerPortalInvite` mutation wrapper) instead of the generic
  denied message when one exists; `commercial/accounts/[accountId]/
  page.tsx` (the natural staff-facing home for account-scoped actions,
  already carrying `CreditPanel`) gains a new "Customer portal access"
  panel wired to the already-existing `grantInitialCustomerPortalAccount
  Admin` mutation wrapper via a new `customer-portal-actions.ts` Server
  Action, gated purely by the RPC's own `CPT:Create` check (seeded since
  CPL-300, never used from any UI until now, the identical "ready-made
  seam" shape `OPS:Download` was before A6 wired it up) -- no client-side
  authority re-derivation.
  New db-test coverage: `scripts/db-tests/customer-portal-scope.sql`
  gained a dedicated test block proving `list_my_pending_customer_portal_
  invites`' own substantive behavior (returns the exact pending row for
  the invited identity with the right account name/role, excludes an
  already-active membership, cross-tenant isolation, a genuinely unrelated
  identity gets a real empty array) plus the identical actor-identity-
  mismatch impersonation-rejection assertion its four CPL-300 read-RPC
  siblings already carry, and the raw-grant defense-in-depth check
  extended from 8 to 9 functions; `scripts/db-tests/rbac-enforcement.sql`
  gained the new function in the ATW-032 SECURITY DEFINER authority-
  surface sweep's own reviewed-and-justified list (a written reason
  mirroring `app.accept_customer_portal_invite`'s own identical raw
  self-row-identity-equality justification immediately above it) and in
  the CPL-300 Tier C Finding-1 named-list check requiring it call `app.
  assert_actor_is_session_identity` directly, not merely transitively.
  Deliberately left out of this bounded core, disclosed rather than
  silently skipped: `app/(tenant)/[tenantSlug]/page.tsx`'s own post-login
  landing behavior for a `customer_user` identity -- today it resolves
  "forbidden" via the staff-only `app.resolve_access_context` (which
  requires an active `app.tenant_user_identities` row, a staff-membership
  concept a `customer_user` identity's own linkage semantics were never
  written for) and shows a generic denied page rather than redirecting to
  `/customer-portal`. Investigating this surfaced real entanglement with
  `app.resolve_access_context`'s own load-bearing, 15+-consumer semantics
  -- not a quick, safely bounded addition alongside this fix. A
  `customer_user` who already knows the `/{tenantSlug}/customer-portal`
  URL (from an invite email, an account admin, or this fix's own
  bootstrap/accept flow) is unaffected. A2b is PARTIAL, not DONE.
  Full Tier A gates verified clean: `typecheck`, full `lint` (0 errors,
  only pre-existing warnings), the full unit test suite (6160/6160,
  including the release-freeze self-test after its digest update), a full
  `pnpm run db:test` (`ALL PASSED`), `git:check-paths`, `security:check`,
  `release:check-freeze` (HUNDRED-AND-FIFTY-NINTH PASS, both digests
  updated -- one new migration file, zero new db-test files, two existing
  db-test files gaining real new coverage), and a real `next build`.
- 2026-09-18 — E3 (bounded core, piece 1 of 2) closed via a dedicated
  research pass, the same "verify before trusting a deferred label"
  discipline that found B7's/B2a's/E6's/B4's/A2b's own real bounded cores.
  The original finding ("No UoM on stock; free-text locations; warehouse
  billing has no invoice FK") was carried as one undivided `DEFERRED_LARGE`
  item and turned out to bundle three genuinely different, independently-
  verifiable claims.
  "No UoM on stock" was itself overstated: a real, governed UOM registry
  (`app.uoms`/`app.uom_conversions`/`app.convert_uom_quantity`, ATW-011A,
  `20260730160000_create_advanced_tms_item_uom_master.sql`) and `app.
  item_masters.base_uom_code` have existed since before this audit was
  even written, and `app.inventory_movement_lines.uom_code` is already
  `not null references app.uoms(code)`, validated on every post. But a
  real, live, reachable bug survived inside that framing: `app.post_
  inventory_movement` (confirmed via a case-insensitive search this time,
  after E6's own earlier miss on exactly this class of mistake -- the true
  current version last redefined in `20260730530000_harden_operations_
  inventory_tracking_record_scope.sql`) validated a posted line's
  `uom_code` is a real, registered ACTIVE code, but never checked it
  matches the item's own `base_uom_code`, and never converted -- it added
  the raw `signed_quantity` straight onto `app.inventory_balances.
  on_hand`. `app.inventory_balances`' own dimension key carries no
  `uom_code` column at all, so two movements against the identical balance
  row (same tenant/warehouse/owner/item/location/lot/serial/status) posted
  in DIFFERENT UOMs were summed as if they were the same unit -- 5 DOZ + 50
  PCS read back as `on_hand=55`, not the true 110 PCS. Not a rare edge
  case: `20260831260000_create_inventory_and_leave_opening_balance_import_
  adapters.sql` (this session's own A4 work) passes the import file's raw,
  user-chosen `uom_code` straight through to `app.post_inventory_movement`
  after only checking it is a registered ACTIVE code, never that it
  matches the item's own base unit.
  Closed: new migration `20260918040000_e3_uom_normalization_inventory_
  balance.sql` converts each line's as-posted quantity into the item's own
  `base_uom_code` via the already-existing, already-proven `app.convert_
  uom_quantity` BEFORE it is used in any on_hand arithmetic --
  `inventory_balances.on_hand` is now always expressed consistently in the
  item's own base unit, regardless of which registered unit any individual
  movement was posted in. `app.inventory_movement_lines`' own `signed_
  quantity`/`uom_code` columns stay the as-posted, as-reported transaction
  record, unchanged -- only the balance arithmetic is normalized. A
  movement already posted in the item's own base unit (confirmed the
  overwhelming common case by the research) is a complete no-op:
  `convert_uom_quantity`'s own early-return short-circuits to the
  identical raw quantity, so this fix changes zero observable behavior for
  every existing caller already using the base unit. A genuine cross-
  category mismatch (e.g. a weight-category UOM against a count-controlled
  item) now fails closed with the already-established `uom_conversion_not_
  registered` rather than silently corrupting the balance -- a strict
  hardening, never a new capability. `CREATE OR REPLACE FUNCTION`, not
  DROP+CREATE (the return type is unchanged), so the existing grant set
  was preserved automatically.
  "Free-text locations," the second half of E3's own original bundled
  claim, was confirmed FALSE for warehouse locations as re-verified here:
  `app.warehouse_locations` is a fully structured, hierarchical, FK-
  enforced table (code/name/location_type/parent_id/path/depth/zone/
  capacity), unchanged and already correct -- not touched by this
  migration. The genuine free-text-location gap the original audit
  paragraph actually described (`app.shipment_orders.origin`/`.
  destination`, plain `text not null` columns) is a separate, TMS-side
  finding, not part of this WMS-scoped bounded core, and stays out of
  scope here.
  New db-test coverage: `scripts/db-tests/advanced-tms-inventory-ledger.
  sql` gained a dedicated test block proving the conversion end to end -- a
  fresh item posted 100 PCS (base unit, a no-op conversion) then a second
  movement posted in DOZ (2 DOZ = 24 PCS via the seeded `app.uom_
  conversions` row) proves the balance reads 124, not the pre-fix 102; the
  movement line's own as-posted `signed_quantity`/`uom_code` (2/DOZ) is
  proven unchanged; a cross-category UOM (KG against a PCS item) is proven
  to fail closed with `uom_conversion_not_registered` without mutating the
  balance. The full `db:test` suite (every other caller of this shared
  posting primitive, the opening-balance-import adapter's own `master-
  data-import.sql` included) confirmed `ALL PASSED` with zero regressions.
  Still open: E3 piece 2, `app.warehouse_billing_handoffs` has no
  `invoice_id`/FK to `app.finance_invoices` despite a fully shipped,
  reachable billing lifecycle (rate components -> capture -> calculate ->
  hold/review/approve -> handoff -> reconciliation outcome) reaching a
  terminal reconciled state with nowhere to go -- confirmed real. A
  follow-up direct check of `app.finance_invoices`' own schema (not done by
  the original research pass) found this is NOT the small, mechanical "one
  FK column plus one linking RPC" fix it first looked like: `finance_
  invoices.job_order_id`/`.billing_readiness_handoff_id` are both mandatory
  (`not null`, the latter also `unique (tenant_id, billing_readiness_
  handoff_id)`), and `app.finance_ar_open_items.source_document_type`'s own
  CHECK constraint admits only `('invoice', 'opening_balance')` -- there is
  structurally no way today to create an invoice, or an AR open item, for a
  charge that has no corresponding job order at all, which a pure storage/
  handling 3PL charge genuinely does not. Closing this for real means
  either widening `finance_invoices`' own core structural invariants (a
  nullable job-order source alongside a new nullable warehouse-billing
  source, with a check ensuring exactly one is set -- a change to a table
  A7's own invoice PDF and every AR report already depend on) or a second,
  parallel invoicing primitive for warehouse-only billing -- genuinely
  `CODE-BIG`, and which shape is correct is a real product/schema decision
  this session should not make unilaterally, the same class of judgment
  call B6b's own internal-cost-to-GL gap was correctly left to a future
  decision for. E3 piece 2 is re-dispositioned `DEFERRED_LARGE` on this
  more accurate understanding, not closeable as a quick follow-on. E3
  overall is PARTIAL, not DONE.
  Full Tier A gates verified clean: `typecheck`, full `lint` (0 errors,
  only pre-existing warnings), the full unit test suite (6160/6160,
  unaffected -- this is a pure database-level fix with no TS/UI blast
  radius), a full `pnpm run db:test` (`ALL PASSED`), `git:check-paths`,
  `security:check`, `release:check-freeze` (HUNDRED-AND-SIXTIETH PASS,
  both digests updated -- one new migration file, zero new db-test files,
  one existing db-test file gaining real new coverage), and a real `next
  build`.
