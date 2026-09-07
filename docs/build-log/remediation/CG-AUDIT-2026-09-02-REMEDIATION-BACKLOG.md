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
| Ø1-remaining-guards | `customer-ticket-guard-deps.server.ts`, `register-login-session-deps.server.ts` `.from()` → RPC | `CODE` | TODO | |
| Ø1-customer-portal-guard + Ø2 | `customer-portal-guard-deps.server.ts` `.from()` → RPC, paired with a customer-layer-aware resolver that actually admits `customer_user` (the Ø2 lockout fix) | `CODE` | TODO | |
| Ø1-query-layer | Convert the remaining ~160 `.from()` reads across ~65 `server/queries/*.ts` / `app/**/*.tsx` files to RPC (existing wrapper where one exists, new `app.*`+`public.*` wrapper where none does) | `CODE-BIG` | `DEFERRED_LARGE` (recon complete) | |

## B1 — `issue_finance_invoice` / `lock_finance_period` are `SECURITY INVOKER`

| ID | Item | Class | Status | Commit |
|---|---|---|---|---|
| B1 | Convert both `app.*` functions (and their already-existing `public.*` wrappers) to `SECURITY DEFINER`, pinning `search_path` on the `app.*` side (currently unpinned) | `CODE` | TODO | |

## D — Security and identity (all independently CRITICAL, each bounded)

| ID | Item | Class | Status | Commit |
|---|---|---|---|---|
| D3c | Session cookie ships `httpOnly:false`, 400-day `maxAge` — library defaults win over the app's own correct options because of spread order | `CODE` | TODO | |
| D2 | Cross-tenant guard in `run_next_route_planning_job` is swallowed by its own exception handler | `CODE` | TODO | |
| D3b | Suspending a user does not cut access — `resolve_access_context`/`has_active_tenant_membership` never read `app.users.status` | `CODE` | TODO | |
| D3d | An enqueued job can leak another tenant's data — 4 of 5 workers never compare the payload's embedded ids back to the job's own tenant | `CODE` | TODO | |
| D3 | IP allowlist bypass — `integrations/actions.ts:76` takes `x-forwarded-for` first-hop instead of last-hop | `CODE` | TODO | |
| B8 | Finance `company_id` is caller-supplied and never validated against the caller's tenant across ≥8 reachable RPCs | `CODE` | TODO | |
| D1 | MFA switched off; `verify_mfa_step_up_challenge` validates no real factor | `CODE` (challenge validation) + `INFRA` (enabling a real TOTP provider is a Supabase project auth-config change) | TODO | |
| D4 | `integration_secrets_encryption_key()` GUC never configured outside db-test fixtures | `INFRA` (real secret provisioning, not a code change) | NEEDS_HUMAN_GATE | |

## B — Money (beyond B1/B8, already tracked above)

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| B5 | Withholding tax added instead of deducted on customer invoices | `CODE` | TODO | |
| B2 | GL is write-only — no trial balance/account balance/P&L/balance sheet | `CODE-BIG` | DEFERRED_LARGE | real report-building effort, weeks per the audit's own estimate |
| B3 | No credit notes; one issued invoice per job order, hard-capped | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | needs a billing-model decision (partial/milestone billing) before schema work |
| B4 | Multi-currency postings summed as raw numbers, no FX/base-amount columns | `CODE-BIG` | DEFERRED_LARGE | schema redesign across `finance_journals`/`finance_journal_lines` |
| B6 | Cost/cash never auto-post to GL | `CODE-BIG` | DEFERRED_LARGE | |
| B7 | Invoicing keyed off a hand-copied UUID; no credit control | `CODE-BIG` | DEFERRED_LARGE | needs a billable-jobs worklist UI |

## C — Indonesia

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| C3 | Tax console shows 11% as "0.11%" — display bug only, calculator is correct | `CODE` | TODO | trivial, high-value |
| C1 | No NPWP on tenant/org unit; no faktur pajak/NSFP/e-Faktur at all | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | compliance-domain modeling, needs a tax SME |
| C2 | PPh 21 uncomputable — no PTKP/bracket/NPWP columns | `CODE-BIG` / `PRODUCT` | DEFERRED_LARGE | same |

## A — Operability

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| A3 | Publishing a role version silently revokes it from every holder (assignment pinned to `role_version_id`, publish never migrates it) | `CODE` | TODO | bounded, real fix identified |
| E2 | One-vehicle-one-shipment is an unlocked `EXISTS` check — racily bypassable | `CODE` | TODO | bounded, add row lock / exclusion constraint |
| F1 | No `error.tsx`/`not-found.tsx`/`global-error.tsx` anywhere; 2 reproduced uncaught 500s | `CODE` | TODO | mechanical, bounded |
| F3 | 13 finance list RPCs hard-cap at 200 rows, no cursor param (101 other list RPCs already have one) | `CODE` | TODO | bounded, mirrors an existing in-repo pattern |
| F5 | Shipment-order list and dispatch board each double-scan (`count:"exact"`) with an unindexed sort | `CODE` | TODO | bounded |
| F2 (multi-select) | `multi-select.tsx` options are keyboard-inaccessible (`onMouseDown` only, no key handler) | `CODE` | TODO | bounded, one component |
| A5 | No scheduler ever invokes `scripts/jobs/supervisor.ts` in production | `CODE` (a cron entry point) + `INFRA` (actually provisioning the schedule) | TODO | attempt a bounded first slice |
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

## Housekeeping

| ID | Item | Class | Status | Notes |
|---|---|---|---|---|
| LINT-1 | `scripts/jobs/supervisor.ts:50` trips the service-role import guard — pre-existing, confirmed via `git stash` baseline comparison before the Ø1 commit | `CODE` | TODO | quick, unblocks a red Tier A gate |

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
