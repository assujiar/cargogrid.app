# 00 — ADVISORY Phase 6 (Procurement and Vendor) Preparation Brief

> **STATUS: `ADVISORY_PRE_PLAN`. THIS IS NOT A RUNTIME ARTIFACT.**
>
> - This document is **not** the output of Prompt 250. Prompt 250's only outputs are
>   `docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md` and its sibling WBS.
>   Neither exists yet and this document does not substitute for either.
> - This document sets **no** task status. It marks nothing `READY`, `VERIFIED`, or
>   `BLOCKED`. It does not set `PHASE_6_IN_PROGRESS`. Only Prompt 271 may ever set
>   `PHASE_6_VERIFIED`.
> - It changes **no** schema, service, API, or UI file, and adds no migration.
> - **Prompt 250 supersedes this document on every point where they differ.** Prompt 250
>   must re-derive its hierarchy from live repository inspection per its own §"Required
>   work" item 2 ("Never infer paths from this package"). Where that re-derivation
>   contradicts anything below, this document is wrong and Prompt 250 is right.
> - Authored while Phase 5 is still `PHASE_5_IN_PROGRESS` (Prompts 246–248 outstanding).
>   Phase 6's entry gate is therefore **not open** — see §2.

**Purpose:** front-load the expensive, one-time repository discovery that every Phase 6
task would otherwise repeat, so an implementing agent spends its budget on implementation
and adversarial review rather than on rediscovering the same canonical roots 21 times.

**Read §4 (open decisions), §5 (recurring defect classes) and §6 (dependency risk and
regression safety) before writing any Phase 6 code.** Phase 6 is the first phase that
writes into roots already `VERIFIED` and already consumed by Phases 2, 3 and 5 — §6.1
measures that blast radius precisely.

**Authored:** 2026-08-05, on branch `claude/prompt-249-plan-implement-56ioc5`.
**Repository state at authoring:** `PHASE_5_IN_PROGRESS`; 134 migrations applied;
`origin/main`@`c2f66db`; no open pull requests; working tree clean apart from this file.
**Mutation performed by this document:** none beyond its own creation.

---

## 1. Phase shape

Phase 6 is **23 package files, 22 runtime tasks**, all under `CG-S11-PRC-*`.

| Prompt | Task ID | Capability | Runtime output |
|---|---|---|---|
| 249 | — (README, no task) | Package README | none |
| 250 | `CG-S11-PRC-001` | WBS and runtime kickoff | `PROCUREMENT_VENDOR_EXECUTION_INDEX.md` |
| 251 | `CG-S11-PRC-002` | Vendor registration and onboarding | `PRC-251.md` |
| 252 | `CG-S11-PRC-003` | Vendor assessment | `PRC-252.md` |
| 253 | `CG-S11-PRC-004` | Compliance and document expiry | `PRC-253.md` |
| 254 | `CG-S11-PRC-005` | Vendor banking and tax security | `PRC-254.md` |
| 255 | `CG-S11-PRC-006` | Vendor rate and pricelist | `PRC-255.md` |
| 256 | `CG-S11-PRC-007` | Sourcing | `PRC-256.md` |
| 257 | `CG-S11-PRC-008` | Procurement RFQ | `PRC-257.md` |
| 258 | `CG-S11-PRC-009` | Vendor comparison | `PRC-258.md` |
| 259 | `CG-S11-PRC-010` | Procurement approval | `PRC-259.md` |
| 260 | `CG-S11-PRC-011` | Purchase order | `PRC-260.md` |
| 261 | `CG-S11-PRC-012` | Vendor contract | `PRC-261.md` |
| 262 | `CG-S11-PRC-013` | Vendor capacity and availability | `PRC-262.md` |
| 263 | `CG-S11-PRC-014` | Vendor assignment | `PRC-263.md` |
| 264 | `CG-S11-PRC-015` | Vendor performance | `PRC-264.md` |
| 265 | `CG-S11-PRC-016` | Vendor invoice matching | `PRC-265.md` |
| 266 | `CG-S11-PRC-017` | Procurement dashboard and reports | `PRC-266.md` |
| 267 | `CG-S11-PRC-018` | Optional vendor portal | `PRC-267.md` |
| 268 | `CG-S11-PRC-019` | Integrated verification | `PRC-268.md` |
| 269 | `CG-S11-PRC-020` | Integrity/security/financial hardening | `PRC-269.md` |
| 270 | `CG-S11-PRC-021` | Documentation and handoff | `PRC-270.md` |
| 271 | `CG-S11-PRC-022` | Independent closure | `PROCUREMENT_VENDOR_CLOSURE_REPORT.md` |

### 1.1 Critical path — Phase 6 is one chain, not two lanes

Every capability prompt 252–267 declares its §9 upstream **cumulatively** (`PRC-251..252`,
`PRC-251..253`, … `PRC-251..266`). Read literally, Phase 6 is a **single strictly
sequential chain of 21 tasks** with zero parallelism.

This is a material difference from Phase 5, which had two genuinely independent lanes
(Transportation `ATW-221` and Warehouse `ATW-229`) converging only at `ATW-238`/`ATW-243`.
Phase 6 has no such split. Planning consequence:

- **Do not plan for concurrent Phase 6 branches.** There is no dependency-clean second
  lane to open, and `ISS-2026-002` (single-writer discipline) already cost this repository
  real content corruption five times.
- The *declared* chain is conservative. Prompt 250 may find the *real* dependency edges
  narrower — e.g. 262 (capacity) substantively needs 261 (contract) and Phase 5 capacity,
  not all of 251–261; 264 (performance) needs evidence sources more than it needs 263. Any
  such relaxation is Prompt 250's call to make **with evidence**, following the Phase 5
  precedent where the operator explicitly resequenced 231 → 234 → 232 → 233.
- Therefore the throughput lever in Phase 6 is **per-task speed**, not fan-out. That is
  exactly what this brief is for.

---

## 2. Entry gate — currently CLOSED

Prompt 250 §"Mandatory entry gate" requires one active checkpoint proving all of:

| Gate | State at authoring | Evidence |
|---|---|---|
| `RUNTIME_DISCOVERY_VERIFIED` | ✔ | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` |
| `RUNTIME_ARCHITECTURE_VERIFIED` | ✔ | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` |
| `PHASE_0_VERIFIED` | ✔ | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| `PHASE_1_VERIFIED` | ✔ | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| `PHASE_2_VERIFIED` | ✔ | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` |
| `PHASE_3_VERIFIED` | ✔ | `docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md` |
| `PHASE_4_VERIFIED` | ✔ | `docs/build-log/phase-04/FINANCE_CLOSURE_REPORT.md` |
| `PHASE_5_VERIFIED` | **✘ NOT YET** | only Prompt 248 may set it; 246/247/248 outstanding |

**Consequence: if Prompt 250 is started today it must stop with `PHASE_6_BLOCKED`.** That
is the correct behavior, not a failure. The remaining Phase 5 work is:

- Prompt 246 → `CG-S10-ATW-027`, integrity/security hardening. Already has a real inbound
  work list: `ISS-2026-021` (four documentation-bookkeeping gaps), `ISS-2026-022` (a false
  "currently unreachable in practice" migration comment in `ATW-224`'s
  `20260729320000_create_advanced_tms_route_load_planning.sql`, fixable additively with
  `COMMENT ON FUNCTION`), `ISS-2026-023` (`scripts/db-tests/wms-picking-concurrency-helper.sh`
  writes to hardcoded non-unique global tmp paths, causing spurious cross-run failures
  under two concurrent `db:test` invocations).
- Prompt 247 → `CG-S10-ATW-028`, documentation and handoff. **This is the task that should
  produce the Phase 5 → Phase 6 contract documents.** Phase 4 set the naming precedent with
  `FINANCE_CLOSURE_REPORT.md` / `FINANCE_HANDOFF_PACKAGE.md` / `FINANCE_DOWNSTREAM_CONTRACTS.md`;
  no equivalent `ADVANCED_TMS_WMS_*` trio exists yet. Phase 6 Prompts 262/263/265 all
  consume Phase 5 contracts, so 247 doing this properly directly reduces Phase 6 cost.
- Prompt 248 → `CG-S10-ATW-029`, independent closure, sets `PHASE_5_VERIFIED`.

**Nothing in this brief authorizes starting any of 246–248, 250, or any later prompt.**
Each still needs its own explicit operator authorization, per this repository's standing
per-task/per-range authorization discipline.

---

## 3. Repository ground truth (the expensive discovery, pre-done)

Everything in this section was verified by direct inspection of `supabase/migrations/**`,
`docs/adr/**`, and `package.json` at `c2f66db`. An implementing agent should still
re-confirm any specific fact it depends on, but should not need to *search* for it.

### 3.1 The single most important finding: there is no `app.vendors` table

**Vendor identity today lives in `app.master_records`, not in a dedicated vendor table.**

- `supabase/migrations/20260717120000_create_master_data.sql` (`PLT-120`) seeds a
  master type row `('vendor_rate', 'Vendor Rate', 'tenant', 'PRC', 'platform-core-foundation')`.
  `owner_module_code = 'PRC'` is **documentation-only metadata**, not an enforced write
  block — no `PRC` authority exists anywhere in the repository yet.
- `supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql` (`COM-149`)
  adds exactly one child table, `app.vendor_rate_versions`, keyed by
  `master_record_id references app.master_records(id)` with `master_type_code` constrained
  to `'vendor_rate'`, plus the read view `app.v_active_vendor_rates` and the snapshot table
  `app.rate_selections`.
- A direct `CREATE TABLE` sweep across all 134 applied migrations finds **no**
  `app.vendors`, `app.suppliers`, `app.partners`, or `app.business_partners`.

Existing Phase 2 rate surface, all reusable by Phase 6:

| Object | Kind | Note |
|---|---|---|
| `app.vendor_rate_versions` | table | structured, indexable rate-version detail |
| `app.vendor_rate_versions_directory` | table | directory/lookup companion |
| `app.v_active_vendor_rates` | view | approved + within validity + tenant-scoped |
| `app.rate_selections` / `app.rate_selections_directory` | table | selection-time snapshot (no-reentry) |
| `app.search_vendor_rates` | function | bounded shortlist lookup, capped, **not** paginated browse |
| `app.select_vendor_rate` | function | snapshots exact rate detail at selection time |
| `app.create_rate_version` / `app.approve_rate_version` / `app.reject_rate_version` / `app.withdraw_rate_version` | functions | approval lifecycle |

### 3.2 Platform primitives Phase 6 must reuse, never re-create

| Primitive | Migration | Used by Phase 6 prompt |
|---|---|---|
| Tenants / RLS tenant policies | `20260716075355`, `20260716105512` | all |
| Principal memberships / users / org units | `20260716100825`, `20260716102620`, `20260716101726` | 251, 259, 267 |
| Roles, permissions, RBAC evaluator | `20260716103445`, `20260716104519` | all |
| Field/record access | `20260716110430` | 254, 258, 264, 266 |
| Support access (purpose/time-bound) | `20260716111315` | 254, 267 |
| Audit trail (`app.capture_audit_event`) | `20260716113048` | all |
| Master data (`app.master_types` / `app.master_records`) | `20260717120000` | 251, 255 |
| Configuration engine | `20260717130000` | 252, 253, 259, 265 |
| Workflow engine | `20260717140000` | 251, 259 |
| **Approval engine** | `20260719090000` | 251–254, 258–261, 265 |
| Status engine | `20260719100000` | 251, 260, 261 |
| Numbering engine | `20260719110000` | 257, 260, 261 |
| Form / custom field builder | `20260719120000` | 252, 257 |
| Notification engine | `20260719130000` | 253, 257, 261, 264 |
| **Document/file engine** | `20260719140000` | 253, 257, 261, 267 |
| API key / webhook primitives | `20260719150000` | 267 |
| API foundation | `20260719160000` | all (REST `/v1` + GraphQL parity) |
| Import/export job framework | `20260719170000` | 255, 257, 266 |
| **Background job framework (`app.jobs`)** | `20260719180000` | 253, 257, 258, 264, 265, 266 |
| Feature flags / entitlements | `20260721090000`, `20260716094432` | 267 |
| White-label / custom domain | `20260717090512`, `20260717103015` | 267 |

`app.jobs` is the shared durable queue and has been widened additively before (`'print_label'`
in `ATW-021`). Phase 6 job kinds (expiry evaluation, RFQ invitation, comparison, scorecard,
match batch) should widen it the same way — never fork a second queue.

### 3.3 Upstream domain roots Phase 6 extends but must never fork

| Root | Migration | Consumed by |
|---|---|---|
| `app.job_orders` | `20260727090000` | 256 (demand source) |
| `app.shipment_orders` | `20260727100000` | 263, 265 |
| Shipment lifecycle / milestones / exceptions | `20260727110000`, `20260727140000`, `20260727150000` | 263, 264 |
| **Resource assignment** | `20260727130000` | 263 — extend, do not duplicate status |
| ePOD capture/review | `20260728100000` | 265 |
| **Actual cost** | `20260728110000` | 264, 265 |
| Billing readiness | `20260728140000` | 265 |
| Transaction lineage | `20260728170000` | 263, 265 |
| Finance chart of accounts | `20260728210000` | 265 (read only) |
| **Finance accounts payable** (`app.finance_ap_open_items`, `app.finance_ap_open_item_events`) | `20260729130000` | 265 — Finance owns; Procurement never writes |
| **Finance vendor bill** (`app.finance_vendor_bills`, `app.finance_vendor_bill_lines`, `app.finance_vendor_bill_number_counters`) | `20260729140000` | 265 — the canonical bill root; matching references it, never duplicates it |
| Finance currency / exchange rate | `20260728230000` | 255, 258, 260 |
| Advanced TMS capacity and utilization | `20260730120000` | 262 |
| Advanced TMS claim/incident | `20260730340000` | 264 |

`ADR-0018` fixes the canonical account entity shape; `ADR-0019` fixes canonical item/SKU
and UOM identity. Both are binding on Phase 6 line-item and UOM modelling.

### 3.4 Commands (verified from `package.json`)

```
pnpm run typecheck                     # tsc --noEmit
pnpm run lint                          # eslint .
pnpm run test                          # node:test across scripts/ server/ lib/ tests/
pnpm run test:e2e                      # playwright
pnpm run db:test                       # bash scripts/db-tests/run.sh (Postgres 16 + PostGIS 3)
pnpm run docs:check
pnpm run security:check
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check
pnpm run git:check                     # worktree collision + branch name
pnpm run git:check-paths               # protected-path guard
pnpm exec next build
```

Toolchain: pnpm `10.33.0`, Node `>=22.11.0`, Next `16.2.10`, React `19.2.7`, Zod `4.4.3`,
Supabase JS `2.110.5`. Pins are governed by `ADR-0002`. Do not upgrade opportunistically.

`pnpm run git:check-paths` enforces: `docs/blueprint/**` and
`docs/ai-agent-build-prompt-package/**` are **FORBIDDEN** to edit; an already-existing
migration file is **FORBIDDEN** to modify (a newly added one is fine); `docs/architecture/**`
and `docs/runtime/**` are **CAUTION** (additive/append-only, visible supersession only).

---

## 4. The three decisions Phase 6 must make before it writes code

These are genuinely open. An implementing agent that starts coding without resolving them
will build the wrong thing. Prompt 251 §20 task 1 already anticipates the first
("Prove canonical Phase 2 vendor/rate ownership and publish an ADR if ambiguous").

### D1 — Canonical vendor identity root

**The question.** Today `'vendor_rate'` master records conflate *vendor identity* and
*rate identity* in one row. Phase 6 needs a real vendor entity with legal identity,
contacts, addresses, categories, services, coverage, compliance, lifecycle states and bank
accounts. Prompt 249 §5 forbids "a second vendor master, rate store, service/coverage
truth". So: extend `app.master_records`, or create `app.vendors`?

**What is already ratified.** `ADR-0015` §Consequences §"Downstream impact / what remains
open" says explicitly that Phase 6's own kickoff must decide "the full vendor lifecycle
tables (`vendors`, `vendor_contacts`, `vendor_assessments`, `purchase_orders`,
`vendor_performance_scores`) that **extend, but do not replace**, the `vendor_rate`
master-data registration and its Phase 2 child table". `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md`
lines 75/190 name the same table set.

**Recommendation (for Prompt 250/251 to accept or reject on evidence).** Create
`app.vendors` as the canonical vendor root, and re-parent rates additively: add a nullable
`vendor_id` FK to `app.vendor_rate_versions`, backfill from the existing
`master_record_id` lineage, and keep the `'vendor_rate'` master record as the registration
/ source-lineage anchor rather than deleting it. This is expand-and-contract, satisfies
"extends but does not replace", and avoids both failure modes — it is not a second vendor
master (there was never a first one; `master_records` holds a *registration*, not a vendor
profile), and it is not a rate-data migration (`ADR-0015` explicitly warns against that).

This needs a **new ADR (next free number: `ADR-0020`)** authored at Prompt 251, citing
`ADR-0015` as its source. Do not implement 251 without it.

### D2 — `PRC`-specific write authority

**The question.** Rate writes are currently gated on `app.is_support_grant_authority`
(tenant-admin/support-grant), reused unchanged from `PLT-115`. `ADR-0015` explicitly
flags this as an interim arrangement to re-examine at Phase 6: today *any*
tenant-admin-authorized actor can write rate data.

**Recommendation.** Introduce narrower `PRC:*` permissions in the existing RBAC evaluator
(`20260716104519`) rather than a new authority model, and widen — never replace — the
existing gate: `is_support_grant_authority(...) OR has_prc_authority(...)`. `ADR-0015`
already characterizes this as "an additive, expand-and-contract change to the authority
layer only, never a data migration". Decide at Prompt 250, implement at Prompt 251, so
that 252–267 inherit one consistent authority story.

### D3 — External vendor identity (blocks 267 only)

**The question.** Prompt 249 §5 forbids inventing "a fifth access layer", and Prompt 267
§20 task 1 requires resolving "four-layer external vendor identity/membership ownership;
block if ambiguous".

**Recommendation.** Treat this as genuinely blocking for **Prompt 267 alone**. Prompt 249
§5 says so directly: "If that runtime ownership is unresolved, block the vendor-portal task
while internal procurement continues." So 251–266 and 268–271 proceed regardless; 267 is
allowed to close as `BLOCKED` with a recorded ADR requirement, and 268's verification must
then record the portal gap as a disclosed limitation rather than a failure. Plan for that
outcome; do not let it stall the phase.

**Corollary for every prompt 251–266:** each has vendor-facing access rules in its §26
(vendor users answering assessments, uploading evidence, submitting RFQ responses,
acknowledging POs, managing capacity offers, disputing matches). Until D3 is resolved,
**build the internal half and the scoped-token half, and feature-gate the
authenticated-vendor-user half.** This mirrors how `ATW-222` shipped dispatch with
tracking columns feature-gated behind an unbuilt `ATW-226F`.

---

## 5. Defect classes this repository keeps re-introducing

Taken from the Phase 5 execution index and per-task build logs. These are not
hypotheticals — each was live-reproduced in this codebase, several more than once. Every
Phase 6 task should treat this as a pre-implementation checklist **and** as the adversarial
reviewer's opening test list.

1. **Cross-target idempotency-key misattribution — 4 separate occurrences** (`ATW-020`
   twice, `ATW-021` twice more, `ATW-022` once as a live cross-owner financial-data leak).
   An idempotency key scoped to the operation but not to the *target row* lets one
   subject's write be silently attributed to a different subject. Phase 6 is dense with
   this shape: RFQ invitations per vendor, PO lines per item, match cases per bill line,
   scorecards per vendor. **Scope every idempotency key by tenant + target identity.**
2. **Authorization after idempotent-replay short-circuit** (`ATW-013`, critical
   cross-tenant RBAC bypass; `ATW-016A`, same class, low severity). A replay path that
   returns the cached business record *before* running authorization leaks live data.
   **Authorize first, then check for replay.**
3. **Owner/account-scoped RLS fail-open on read RPCs** (`ATW-016`, live-proven cross-owner
   data leak — a customer-portal actor read every other owner's lot/serial/policy data in
   the same tenant; `ATW-017`, same class again). Tenant scoping is not owner scoping.
   Phase 6 has an explicit owner axis on nearly every table (the vendor). **Every read RPC
   needs both.**
4. **Masked/blind field leaking through a mutation RPC's return value** (`ATW-020`, high
   severity — self-assign/self-count/self-freeze each returned the true expected quantity
   and defeated blind counting). Phase 6 equivalents: bank/tax fields (254), competitor
   offers (258), cost fields (260, 263). **Redact on the way out of mutations, not only in
   read views.**
5. **Missing per-subject record-scope check on a subject-referencing RPC** (`ATW-021`,
   live-reproduced: a branch-scoped actor could label an out-of-scope warehouse's subject).
   Phase 6: any RPC taking a `vendor_id`, `po_id`, or `bill_id` parameter.
6. **`record_version` not bumped on a partial mutation** (`ATW-020` found this in the
   already-`VERIFIED` `ATW-015` ledger; `ATW-016` found it on policy publish). Optimistic
   concurrency silently stops working. **Bump the version on every mutating path,
   including the ones that only touch one column.**
7. **Ancestor/graph walks that lock only their endpoints** (`ATW-018`, critical — two
   disjoint concurrent reparent calls each passed their own cycle check and together
   committed a real cycle). Phase 6: PO amendment chains, contract renewal chains,
   comparison hierarchies. **Lock every visited node.**
8. **Aggregate races across sibling records** (`ATW-019`, an order split across shipments;
   fixed with a per-order advisory lock). Phase 6: partial receipts against one PO,
   multiple bills against one PO. **Advisory-lock the aggregate root.**
9. **State flag not flipped on reversal** (`ATW-022`, critical — a reversed warehouse
   billing event could be handed to Finance a second time). Phase 6: PO cancellation,
   contract termination, match reversal, dispute resolution.

Standing conventions that exist precisely because they were learned the hard way:

- Every migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
  FROM PUBLIC` before its final grants (`ERR-2026-004`, standing since `PLT-118`).
- Masked views are `security_invoker = false` with their own explicit row filter — an
  invoker-mode view cannot read a column-`REVOKE`d field at all (proven in `COM-147`;
  re-learned in `COM-148`; do not discover it a third time).
- Every write calls `app.capture_audit_event`, same convention as
  `create_master_record`/`update_master_record`.
- A new child table's RLS mirrors its parent's already-verified policy, tenant-aware.
- Never edit an applied migration. Add a new one — including when widening a policy
  (`ATW-017` widened `ATW-016A`'s policies via `DROP POLICY`/`CREATE POLICY` inside a new
  migration file, never by editing the applied one).
- Default task size (AGENTS.md): one feature slice, one module boundary, 1–3 migrations,
  ~5–15 changed files.

---

## 6. Dependency risk and regression safety

Phase 6 is the first phase that writes into tables **already `VERIFIED` and already in
production use by three earlier phases**. Phases 3, 4 and 5 were largely greenfield for
their own roots; Phase 6 is not. This section is the register of what can break and how to
keep it from breaking.

### 6.1 Measured blast radius

Verified by direct dependency sweep at `c2f66db`, not estimated.

| Shared root Phase 6 touches | Written by | Existing consumers found | Phases at regression risk |
|---|---|---|---|
| `app.vendor_rate_versions`, `app.v_active_vendor_rates`, `app.rate_selections`, `app.select_vendor_rate` | D1 (§4), Prompt 255 | **9 application/server files** (`server/contracts/rate/`, `server/queries/rate.ts`, `server/mutations/rate.ts`, `server/mutations/credit.ts`, `server/queries/contract.ts`, 4 `app/(tenant)/…/commercial/**` routes) + **8 migrations** (`20260724180000` margin, `20260724290000` account conversion, `20260724300000` contract pricing, `20260724310000` credit control, `20260728110000` **Operations actual cost**, `20260730140000` **Phase 5 warehouse zone**, `20260717120000` master data, `20260724150000` itself) | **2, 3, 5** |
| Operations resource assignment (`20260727130000`) | Prompt 263 | **12 migrations**, including `20260728110000` actual cost and 10 Phase 5 Advanced-TMS migrations (multi-leg, dispatch board, fleet/driver/device, mile orchestration, telemetry arbitration, geofence, control tower, capacity/utilization, milestone/exception telemetry, tracking-health writer, claim/incident) | **3, 5** |
| `app.jobs` shared queue (`20260719180000`) | Prompts 253, 257, 258, 264, 265, 266 | every phase that enqueues work | **1–5** |
| `app.master_records` / `app.master_types` (`20260717120000`) | D1, Prompt 251 | master-data consumers across all phases | **1–5** |
| `app.finance_vendor_bills`, `app.finance_ap_open_items` | Prompt 265 — **read only** | Finance AP/posting/settlement | **4** |
| Approval engine (`20260719090000`) | Prompts 251–254, 258–261, 265 | Commercial quotation approval (`20260724270000`), Operations, Finance | **2, 3, 4** |

The rate surface is the dangerous one. It is read by live Commercial costing/quotation code
**and** by Operations actual-cost **and** by a Phase 5 warehouse migration. A careless
change there regresses three verified phases at once.

### 6.2 Risk register

**R1 — D1 vendor-root re-parenting regresses Phase 2 costing.** Adding a vendor root and
re-parenting `app.vendor_rate_versions` touches a table with 17 live consumers.
*Mitigation:* strictly expand-and-contract. Add `vendor_id` as **nullable** with no default
behavior change, backfill in the same migration, and leave every existing column, index,
view definition and function signature untouched. Do not add `NOT NULL` in the same
migration that introduces the column. Do not change `app.select_vendor_rate`'s or
`app.search_vendor_rates`' signature or return shape — Commercial's `server/contracts/rate/`
compiles against them. Run `server/**/rate*.test.ts`, `server/mutations/credit.ts`'s tests
and the Commercial db-tests as an explicit regression gate, not as an afterthought.

**R2 — Prompt 255's new rate dimensions break existing rows.** 255 adds many columns to the
same table (zone/distance, fleet/container, tiers, lead time, capacity terms, accessorials).
*Mitigation:* every new column nullable or defaulted; no new `CHECK` that existing rows
would violate; no new required input to an existing function. If a constraint must
eventually be strict, land it as a separate later migration after backfill is proven.

**R3 — RPD-040 snapshot violation.** `app.rate_selections` holds the applied rate version
for already-issued quotes. Re-parenting or repricing must **not** alter historical selection
snapshots. *Mitigation:* treat `app.rate_selections` rows as immutable evidence; assert in
a db-test that the pre-migration and post-migration snapshot payloads are byte-identical for
a fixture set. This is the exact class of correctness Phase 2 built the table to protect.

**R4 — Prompt 263 regresses Phase 3 *and* Phase 5 at once.** Resource assignment feeds 12
migrations including live dispatch, capacity, milestone-telemetry and claim handling.
*Mitigation:* 263 **extends** with new procurement columns/tables and adds **no second
status machine**. Any change to existing assignment status semantics is out of scope and
requires its own ADR. Regression gate: the Phase 5 transport golden path and the dispatch/
capacity db-tests, re-run in full.

**R5 — `app.jobs` job-type widening silently drops earlier job types.** The established
mechanic (`ATW-224`, repeated at `ATW-021`) is `DROP CONSTRAINT jobs_job_type_check` /
`ADD CONSTRAINT` with the full list, **plus** `CREATE OR REPLACE app.enqueue_job` with an
identical body whose `v_valid_job_types` array matches. Two lists must stay in sync, and the
base must be copied from **the most recent migration that widened it**, not from an older
one. Copying an older base silently removes every job type added since.
*Mitigation:* before widening, run
`grep -rn "jobs_job_type_check" supabase/migrations/ | tail -1` to find the true latest
base; diff the resulting two lists; add a db-test asserting every previously valid job type
is still accepted. Current valid list at `c2f66db` ends with `'route_load_planning',
'print_label'`.

**R6 — RLS widening reverts an earlier widening.** `ATW-017` widened `ATW-016A`'s policies
via `DROP POLICY`/`CREATE POLICY` in a new migration. A later task that re-drops and
re-creates from a stale base would silently revert that fix. *Mitigation:* read the **live**
policy definition (`pg_policies`) immediately before replacing it, never the definition in
the original migration file.

**R7 — Approval retrofit at 259 unwinds 251–258.** 259 arrives after eight tasks already
needed approvals. If each invents a local shortcut, 259 becomes a rewrite of eight verified
tasks. *Mitigation:* Prompt 250 records the binding rule up front — **251 onward bind
directly to the Platform approval engine** (`20260719090000`), and 259 adds only the
Procurement policy-binding layer on top. No local approval tables before 259.

**R8 — A defect found at 268 invalidates evidence from 251.** In a 21-task linear chain,
late integrated verification can retroactively falsify early `VERIFIED` rows.
*Mitigation:* 268 must register **invalidated evidence** explicitly per finding (its §20
requires exactly this), and 269 must re-verify the affected early tasks, not just patch the
symptom. Budget for it: `ATW-026` → `ATW-027` had the same shape.

**R9 — Concurrent sessions corrupt shared docs.** `ISS-2026-002`, five occurrences,
`ERR-2026-001..003` of real content corruption. Phase 6 has no parallel lane (§1.1), so
there is no legitimate reason to run two writing sessions. *Mitigation:* the mandatory
pre-flight open-PR/branch check before every task.

**R10 — Migration timestamp ordering.** 134 migrations, strictly ascending; the latest is
`20260730340000`. Phase 6 migrations must sort **after** whatever Prompts 246–248 add.
*Mitigation:* re-read `ls supabase/migrations/ | tail -1` at the start of each task rather
than reusing a number planned earlier in the phase.

**R11 — Cross-phase test-suite drift.** The suite is large (3084 `node:test` cases and 137
`scripts/db-tests/` files at the `ATW-026` checkpoint). A Phase 6 change that breaks a
Phase 2 test can look like a pre-existing failure. *Mitigation:* capture the baseline
**before** the first edit of every task (AGENTS.md §"Required pre-flight"), and diff against
it. AGENTS.md is explicit: fix only task-caused failures; log pre-existing ones separately
with baseline evidence.

### 6.3 Per-task regression protocol

Every Phase 6 task, without exception:

1. **Baseline first.** Before the first edit: `pnpm run typecheck`, `lint`, `test`,
   `db:test`, and `next build`. Record the exact numbers in the task build log. A gate that
   was already failing is a pre-existing failure only if the baseline proves it.
2. **Declare the blast radius in the task's own build log**, using §6.1: which shared roots
   this task writes, and which earlier phases those roots feed.
3. **Additive-only against verified roots.** New column nullable/defaulted; new constraint
   only after backfill; never edit an applied migration; never change an existing function's
   signature or return shape that another phase compiles against.
4. **Targeted regression gate, chosen from the blast radius** — not just the task's own new
   tests. Touching rates means running the Commercial rate/credit/contract suites. Touching
   assignment means running the Phase 5 transport golden path.
5. **Full gate suite after**, all twelve commands from §3.4, compared line-by-line against
   the baseline from step 1.
6. **Adversarial review against §5's list**, then fix, then independently re-verify. Do not
   mark `VERIFIED` on the implementer's own say-so — every Phase 5 task from `ATW-013`
   onward found real defects at this step.
7. **Rollback stated concretely.** For a docs-only task, `git revert`. For a migration,
   the explicit down path or the disclosed reason there isn't one.

### 6.4 What makes this phase safe overall

- The declared dependency chain (§1.1) is conservative by design. Following it in ascending
  order is the low-risk path; any resequencing needs Prompt 250's evidence-backed decision,
  the way Phase 5 justified 231 → 234 → 232 → 233.
- Three of the four riskiest changes are concentrated in two tasks (D1/251 and 255, both
  against the rate surface) and one task (263, against assignment). Those three deserve
  disproportionate review budget; most of the remaining 18 are genuinely additive greenfield.
- 265 — the highest-stakes boundary — is safe by construction if the `ATW-022` precedent is
  followed: read Finance, write nothing into Finance, hand off a source-linked input.

---

## 7. Per-task preparation cards

Each card is the pre-digested brief for one prompt. **The prompt file remains
authoritative** — these cards summarize and add repository grounding, they do not replace
the 36 mandatory fields. Path convention below: `PKG` =
`docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/`.

---

### `CG-S11-PRC-001` — Prompt 250, WBS and runtime kickoff

- **Source:** `PKG/250_PROCUREMENT_VENDOR_WBS_RUNTIME_KICKOFF_PROMPT.md`
- **Blocked by:** `PHASE_5_VERIFIED` (Prompt 248). See §2.
- **Produces:** `docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md` plus a WBS
  sibling, following the `00_ADVANCED_TMS_WMS_WBS.md` / `00_FINANCE_WBS.md` precedent.
- **Required index columns (23, verbatim from §"Required execution-index columns"):**
  `task_id`, `parent_prompt`, `workstream`, `epic`, `capability`, `feature_slice`,
  `atomic_objective`, `source_ids`, `upstream`, `downstream`, `allowed_paths`,
  `forbidden_paths`, `migration_ids`, `api_contracts`, `access_controls`,
  `vendor_rate_po_match_invariants`, `tests`, `commands`, `evidence`, `rollback`, `owner`,
  `status`, `resume_point`.
- **Must resolve:** D1, D2 (§4). Must scope D3 as blocking 267 only.
- **Must not:** implement anything; set `PHASE_6_VERIFIED`; infer paths from the package
  (§"Required work" item 2 forbids it — inspect the repository).
- **Gotcha:** Phase 5's kickoff decomposed Prompt 226 into nine children because the prompt
  itself prescribed it. Nothing in Phase 6 prescribes a decomposition — but 260 (PO), 265
  (matching) and 267 (portal) are the plausible candidates on size. Decide on evidence, and
  record the reasoning either way.

---

### `CG-S11-PRC-002` — Prompt 251, Vendor registration and onboarding

- **Source:** `PKG/251_VENDOR_REGISTRATION_ONBOARDING_PROMPT.md`
- **Upstream:** `PRC-250`; verified Phase 2 vendor/rate ownership; Platform identity,
  document and approval foundations.
- **Extends:** `app.master_records` (`'vendor_rate'`), `app.vendor_rate_versions`,
  approval engine, status engine, workflow engine, document engine, RBAC evaluator.
- **DB:** canonical vendor with legal identity, category, contacts/addresses, services,
  coverage, owned-resource references, payment-term reference, intake source, duplicate-review
  lineage, and canonical `Draft → Submitted → Review → Approved → Active →
  Suspended/Archived` states.
- **Blocking prerequisite:** publish `ADR-0020` resolving D1 **before** writing the
  migration. §20 task 1 requires it. Also settle D2 here so 252–267 inherit it.
- **Invariants:** fuzzy duplicate review **never** auto-merges legal entities;
  self-registration is tenant-configurable under BP-A08 and never globally public by
  default; intake tokens are scoped, expiring, and non-authoritative; onboarding approval
  is what creates or links the canonical vendor; vendor-owned fleet/driver/warehouse
  references point at Phase 5 roots and never duplicate them; employee truth stays in
  Step 12.
- **Watch:** defect classes 1, 2, 3, 5 (§5). Intake tokens are exactly the shape that
  produced `ATW-013`'s replay-before-authorize bypass.
- **Regression risk: HIGH (R1, R3).** If D1 re-parents `app.vendor_rate_versions`, this task
  touches a root with 17 live consumers across Phases 2/3/5. Mandatory targeted gate beyond
  this task's own tests: `server/**/rate*.test.ts`, `server/mutations/credit.ts` coverage,
  `server/queries/contract.ts` coverage, the four `app/(tenant)/…/commercial/**` rate routes,
  and a db-test asserting `app.rate_selections` snapshots are byte-identical pre/post.

---

### `CG-S11-PRC-003` — Prompt 252, Vendor assessment

- **Source:** `PKG/252_VENDOR_ASSESSMENT_PROMPT.md`
- **Upstream:** `PRC-251`; Platform configuration and approval; verified vendor identity.
- **Extends:** configuration engine (template versions), form/custom-field builder
  (questions/criteria), approval engine (maker-checker), document engine (evidence).
- **DB:** assessment template/version, scope/type, questions/criteria/weights, evidence,
  assessor, score/band, findings, corrective actions, approval, expiry/reassessment,
  vendor eligibility outcome.
- **Invariants:** scoring is **exact and explainable** — formula, weights and version are
  reproducible from stored data, never recomputed from live config; expiry/reassessment
  changes vendor status through a governed path, **never silently**.
- **Watch:** defect classes 4 (assessor-visible vs. approver-only sections), 6
  (`record_version` on score recalculation), 9 (expiry flipping eligibility).

---

### `CG-S11-PRC-004` — Prompt 253, Compliance and document expiry

- **Source:** `PKG/253_COMPLIANCE_DOCUMENT_EXPIRY_PROMPT.md`
- **Upstream:** `PRC-251..252`; verified document/file engine.
- **Extends:** document/file engine (`20260719140000`), notification engine, `app.jobs`,
  Operations document requirement (`20260728090000`) as the nearest precedent pattern.
- **DB:** versioned compliance requirement by vendor category/service/coverage, document
  metadata/version, verification result, effective/expiry dates, reminder/escalation,
  waiver, corrective action, legal hold, eligibility impact.
- **Invariants:** documents are private, classified, and **malware-scanned before release**;
  access uses short-lived signed URLs plus field/record scope plus download audit; expiry,
  legal hold and RPD-025 retention are explicit; Operations/Finance receive the
  *eligibility result*, not unrestricted files.
- **Watch:** the expiry evaluation job is a durable `app.jobs` kind — needs chunking,
  retry, DLQ, cancellation and reconciliation. Defect class 9 (expiry must actually flip
  downstream eligibility, and un-flip on renewal).

---

### `CG-S11-PRC-005` — Prompt 254, Vendor banking and tax security

- **Source:** `PKG/254_VENDOR_BANKING_TAX_SECURITY_PROMPT.md`
- **Upstream:** `PRC-251..253`; verified Finance tax/payment-term and privileged-access
  contracts.
- **Extends:** field/record access (`20260716110430`), support access (`20260716111315`),
  approval engine (dual approval), Finance payment-term contracts.
- **DB:** encrypted/masked bank-account versions, ownership/verification status, tax
  identity hashes/versions, payment-term references, effective dates, change request, dual
  approval, hold, downstream usage snapshot.
- **Hard constraints:** RPD-016 forbids guessed tax behavior — statutory verification needs
  **current, dated Finance/legal SME evidence**; RPD-038 requires case-specific bank/e-sign/
  compliance adapters in the shared product codebase, with no generic provider abstraction.
  Sensitive changes require maker-checker, current authorization, privileged MFA where
  applicable (RPD-023), before/after evidence, and downstream hold/reverification.
- **Blocking risk:** if no dated SME/legal evidence for Indonesian tax identity handling is
  available at execution time, **record the task `BLOCKED` on that evidence** rather than
  inventing behavior. AGENTS.md §"Stop and escalate when" covers this case explicitly.
- **Watch:** defect class 4 is the headline risk here. Masked values must not leak through
  any mutation return value, list endpoint, export, report, or realtime channel.

---

### `CG-S11-PRC-006` — Prompt 255, Vendor rate and pricelist

- **Source:** `PKG/255_VENDOR_RATE_PRICELIST_PROMPT.md`
- **Upstream:** `PRC-251..254`; verified Phase 2 rate ownership, Finance currency/tax,
  Platform master/config.
- **Extends:** `app.vendor_rate_versions` **directly** — this is the prompt that fulfils
  `ADR-0015`'s "Phase 6 extends this same table set". Also `app.v_active_vendor_rates`,
  `app.search_vendor_rates`, `app.select_vendor_rate`, `app.rate_selections`,
  `app.finance_exchange_rates` (`20260728230000`), import/export job framework.
- **DB:** quotation/pricelist/version, service/mode, origin/destination/zone/distance,
  fleet/container, weight/volume/UOM tiers, currency/tax, surcharge/accessorial, minimum
  charge, validity, lead time, capacity terms, approval, source/config snapshots.
- **Invariants:** exact decimal/conversion/rounding rules; **RPD-040** protects the applied
  source/config/rate version on active costing, shipment, PO and invoice-match records —
  reprice or migration is explicit, authorized and auditable, never implicit. Overlapping
  rate windows need an unambiguous resolution rule.
- **Gotcha:** `app.search_vendor_rates` is deliberately a bounded shortlist lookup (capped,
  no cursor pagination), **not** a catalogue browse — that is `app.search_master_records`'s
  job. Prompt 255 needs a genuinely paginated pricelist browse; add it as a new function
  rather than changing the existing lookup's contract.
- **Watch:** UOM conversion correctness against `ADR-0019`; rounding must match Finance's
  existing primitives, not a second implementation.
- **Regression risk: HIGH (R2, R3).** Same 17-consumer surface as 251. Every new column
  nullable or defaulted; no new `CHECK` an existing row would violate; no signature change
  to `app.select_vendor_rate` or `app.search_vendor_rates`. Same targeted gate as 251.

---

### `CG-S11-PRC-007` — Prompt 256, Sourcing

- **Source:** `PKG/256_SOURCING_PROMPT.md`
- **Upstream:** `PRC-251..255`; verified Commercial costing request
  (`20260724090000`) and Operations demand contracts (`app.job_orders`,
  `app.shipment_orders`).
- **DB:** sourcing request/version, demand source, service/lane/mode/fleet/capacity/schedule/
  cargo constraints, budget/currency, candidate longlist, eligibility result/reasons,
  owner/SLA/status, selection lineage.
- **Invariants:** **no re-entry** — demand comes from the canonical costing request or job
  order, never re-keyed. Eligibility is the configured intersection of active status,
  service/coverage, compliance, contract/rate validity, capacity/availability, risk/blacklist
  and operational constraints; overrides require reason, approval, expiry and evidence.
  Sourcing is **decision support** — an authorized human selects the vendor.
- **Watch:** the eligibility query is the phase's hottest read path (it fans across 251–255
  plus 262). Server-side filter/sort/search/cursor pagination, tenant-aware indexes,
  RPD-014 live-OLTP budgets. No `SELECT *`.

---

### `CG-S11-PRC-008` — Prompt 257, Procurement RFQ

- **Source:** `PKG/257_PROCUREMENT_RFQ_PROMPT.md`
- **Upstream:** `PRC-251..256`; verified notification/file/job/API primitives.
- **Extends:** numbering engine (RFQ number), notification engine, document engine,
  `app.jobs` (invitation dispatch), form builder (requirement lines).
- **DB:** RFQ root/version/number, sourcing/demand source, requirement lines,
  invitation/vendor scope, issued/deadline/clarification, response/version/attachments,
  commercial terms, decline/no-response, status, comparison eligibility.
- **Invariants:** vendor eligibility is evaluated **at issue time** and snapshotted;
  confidentiality is absolute — no invited vendor may observe another's response,
  identity, or existence; invitation channel is a scoped token or (post-D3) a portal
  membership, never a broad grant; notification delivery is durable with bounded retry.
- **Watch:** defect class 1 — one idempotency key per (RFQ, vendor), never per RFQ.
  Defect class 3 — response reads must be vendor-owner scoped, not merely tenant scoped.

---

### `CG-S11-PRC-009` — Prompt 258, Vendor comparison

- **Source:** `PKG/258_VENDOR_COMPARISON_PROMPT.md`
- **Upstream:** `PRC-251..257`; verified exact rate engine and assessment/compliance.
- **DB:** comparison root/version, RFQ/sourcing source, normalized offers/components,
  currency/UOM/tax/rounding conversions, non-price criteria/weights, exclusions,
  score/rank, recommendation, reviewer override, selected proposal lineage.
- **Invariants:** normalization must use the **canonical rate engine** from 255, not a
  second calculator; criteria, exclusions, normalization and score version must be
  explainable and reproducible; recommendation is decision support and an authorized human
  selects; AI recommendation depth is Step 14 and out of scope.
- **Watch:** source staleness — a comparison built on an offer that was later superseded
  must be detectably stale, not silently wrong. Defect class 4 — competitor data must never
  reach a vendor-scoped reader through any surface.

---

### `CG-S11-PRC-010` — Prompt 259, Procurement approval

- **Source:** `PKG/259_PROCUREMENT_APPROVAL_PROMPT.md`
- **Upstream:** `PRC-251..258`; verified Platform approval/config/organization contracts.
- **DB:** **only** Procurement approval-policy bindings, context snapshots,
  threshold/dimension inputs, required approver groups, task references,
  delegation/escalation, decision linkage. **No second approval engine.**
- **Invariants:** every Phase 6 decision maps to an existing approval-engine policy
  binding (`20260719090000`); separation of duties (no self-approval); stale-source
  invalidation — if the underlying record changed after the approval context was
  snapshotted, the decision is invalid; admins may configure published policies but
  **cannot silently rewrite an active decision context**.
- **Note:** this prompt arrives *after* 251–258 have already needed approvals. Those tasks
  bind to the Platform approval engine directly; 259 formalizes the Procurement-specific
  policy layer and retrofits release gates. Prompt 250 should record that sequencing
  explicitly so 251–258 do not each invent a local approval shortcut that 259 must unwind.

---

### `CG-S11-PRC-011` — Prompt 260, Purchase order

- **Source:** `PKG/260_PURCHASE_ORDER_PROMPT.md`
- **Upstream:** `PRC-251..259`; verified Finance currency/tax/payment-term and Operations
  demand contracts.
- **Extends:** numbering engine, status engine, approval engine, Finance currency/tax
  primitives, `ADR-0019` item/UOM identity.
- **DB:** PO root/version/number, vendor/company/branch, sourcing/RFQ/comparison/quote/rate/
  contract sources, service/item lines, quantity/UOM, price/components/currency/tax/rounding,
  delivery/service period, terms, approvals, commitment, amendments/cancellation,
  fulfillment, match references.
- **Hard boundary:** an approved PO **does not** post a journal, create AP, execute
  settlement, or change cash. Finance owns vendor bill, AP, posting, period lock, reversal,
  settlement and reconciliation. A PO is a commitment record only.
- **Watch:** defect classes 1 (idempotency per PO line), 7 (amendment chains), 8 (partial
  fulfilment aggregate races), 9 (cancellation must flip state so a cancelled PO cannot be
  matched). Exact totals are an acceptance criterion — reuse Finance's rounding primitives.

---

### `CG-S11-PRC-012` — Prompt 261, Vendor contract

- **Source:** `PKG/261_VENDOR_CONTRACT_PROMPT.md`
- **Upstream:** `PRC-251..260`; verified document/e-sign integration controls and Finance
  terms.
- **DB:** contract root/version/number, vendor/entities, service/coverage, rate/pricelist
  references, capacity, SLA/KPI, tax/payment terms, required compliance,
  validity/renewal/termination, document/signature metadata, approval, downstream usage
  snapshots.
- **Hard constraint:** RPD-038 — e-sign is a case-specific adapter in shared product code,
  no generic provider abstraction. If no e-sign provider is contracted at execution time,
  **scope the signature layer to metadata + manual evidence and disclose the gap**; do not
  stub a fake provider (AGENTS.md forbids fake API responses and placeholder actions).
- **Watch:** adapter-failure paths are an explicit §20 test requirement. Defect class 7
  (renewal chains), 9 (termination must flip effective terms downstream).

---

### `CG-S11-PRC-013` — Prompt 262, Vendor capacity and availability

- **Source:** `PKG/262_VENDOR_CAPACITY_AVAILABILITY_PROMPT.md`
- **Upstream:** `PRC-251..261`; verified Phase 5 fleet/driver/load capacity
  (`20260730120000`) and vendor contract.
- **DB:** vendor capacity offer/version by service/mode/lane/region/resource type/period,
  quantity/UOM, availability window, commitments/reservations, blackout, acceptance,
  source/contract, fulfillment/release lineage referencing canonical operational resources
  where known.
- **Invariants:** reconcile against Phase 5's existing capacity-reservation ledger — extend
  or reference it, do not build a second reservation mechanism. Operations retains
  execution authority; Procurement governs eligibility only.
- **Watch:** this is the phase's most concurrency-sensitive table. Defect class 8 (advisory
  lock the capacity aggregate), plus the exact double-allocation problem `ATW-017` solved
  for inventory — reuse that proof shape (two real concurrent psql processes racing the
  same offer).

---

### `CG-S11-PRC-014` — Prompt 263, Vendor assignment

- **Source:** `PKG/263_VENDOR_ASSIGNMENT_PROMPT.md`
- **Upstream:** `PRC-251..262`; verified Phase 3/5 assignment and capacity contracts.
- **Extends:** `app.shipment_orders`, Operations resource assignment (`20260727130000`),
  transaction lineage (`20260728170000`), Phase 5 capacity reservation.
- **DB:** extend canonical shipment/leg/task assignment with procurement selection, vendor,
  accepted quote/rate/contract/PO/capacity reservation, eligibility snapshot,
  invitation/acceptance/decline, override, reassignment/cancellation, actual fulfillment
  lineage.
- **Hard boundary:** **extend, never duplicate status.** Operations governs
  execution/custody/status; Procurement governs eligibility. Two status machines for one
  assignment is the failure mode to avoid. Customers must not see vendor cost.
- **Watch:** eligibility-snapshot expiry (an assignment made on a since-expired compliance
  document), token handling on vendor acceptance, defect classes 2, 3, 5.
- **Regression risk: HIGH (R4).** Resource assignment feeds 12 migrations across Phases 3
  and 5 — live dispatch, capacity/utilization, milestone/exception telemetry, tracking-health
  writer and claim/incident all read it. Mandatory targeted gate: the Phase 5 transport
  golden path plus the dispatch and capacity db-tests, re-run in full. Any change to existing
  assignment status semantics is out of scope and needs its own ADR.

---

### `CG-S11-PRC-015` — Prompt 264, Vendor performance

- **Source:** `PKG/264_VENDOR_PERFORMANCE_PROMPT.md`
- **Upstream:** `PRC-251..263`; verified Operations, claim (`20260730340000`), compliance,
  sourcing and Finance evidence.
- **DB:** KPI definition/version, measurement window, source events, exclusions,
  targets/weights, metric values, scorecard/band, issue/corrective action,
  review/approval, manual adjustment, vendor suspension/blacklist/reactivation
  recommendation lineage.
- **Invariants:** metrics derive from **versioned** operational, compliance, sourcing,
  claim, customer-complaint and Finance evidence. Formulas, windows, exclusions and manual
  adjustments are governed and explainable. Suspension/blacklist/reactivation follow the
  canonical vendor states from 251 with reason, evidence, approval and downstream impact
  checks — never an automatic side effect of a score.
- **Watch:** late-arriving events (an event landing after its window closed) is an explicit
  §20 test requirement. Scorecard batches are `app.jobs` work.

---

### `CG-S11-PRC-016` — Prompt 265, Vendor invoice matching

- **Source:** `PKG/265_VENDOR_INVOICE_MATCHING_PROMPT.md`
- **Upstream:** `PRC-251..264`; verified Phase 4 vendor bill/AP (`20260729140000`,
  `20260729130000`) and Phase 3/5 shipment/actual-cost/ePOD evidence.
- **DB:** match case/version referencing the canonical vendor bill, PO/contract,
  shipment/leg/service receipt/ePOD, actual cost, rate/tax/payment-term snapshots,
  quantity/UOM, amount/currency/rounding, line-level results, tolerance config, duplicate
  fingerprint, variance/dispute, approval, Finance readiness/reconciliation.
- **Hard boundary — the phase's single most important one:** extend
  `app.finance_vendor_bills`; **never create a duplicate invoice/AP root.** A match result
  is a source-linked Finance *input*. Only Finance may post or pay. Zero writes to any
  Finance schema table. `ATW-022` is the precedent to copy: it mirrored Operations'
  `billing_readiness_evaluations`/`billing_readiness_handoffs` handoff shape and wrote
  nothing into Finance.
- **Mandatory gates:** `FINTEST-016`, plus quantity/value/tax, duplicate, concurrency,
  isolation and reconciliation tests.
- **Watch:** defect class 1 (an idempotency key per bill *line*, not per bill — this is the
  exact shape that leaked cross-owner financial data in `ATW-022`), defect class 9 (a
  reversed/disputed match must not be handed off twice).

---

### `CG-S11-PRC-017` — Prompt 266, Procurement dashboard and reports

- **Source:** `PKG/266_PROCUREMENT_DASHBOARD_REPORTS_PROMPT.md`
- **Upstream:** `PRC-251..265`.
- **DB:** **only** measured report queries/views, metric definitions, and optional
  aggregation checkpoints. Materialized views/replicas only **after** measured thresholds
  (RPD-014) — not preemptively.
- **Invariants:** every metric declares source, formula, grain, as-of, owner and access
  policy. Live dashboard queries need read-only access, budgets, timeout, pagination and
  caching. Async export via the import/export job framework.
- **Watch:** metric reconciliation (a dashboard number must equal the drilldown's sum) and
  inference isolation (an aggregate must not leak a value the viewer cannot read at row
  level). Precedents: `20260724320000`/`20260724330000` (Commercial),
  `20260728150000`/`20260728160000` (Operations).

---

### `CG-S11-PRC-018` — Prompt 267, Optional vendor portal

- **Source:** `PKG/267_OPTIONAL_VENDOR_PORTAL_PROMPT.md`
- **Upstream:** `PRC-251..266`; **an explicit Platform identity/membership ADR** (D3).
- **DB:** **only** vendor-account memberships/grants/invitations/sessions/preferences and
  permitted portal action/read projections tied to canonical vendor records. Do not
  duplicate vendor, RFQ, capacity, PO, match or document truth.
- **Expected outcome:** likely `BLOCKED` unless D3 is resolved first. Prompt 249 §5
  sanctions this explicitly. Plan for it; do not let it stall 268–271.
- **If it proceeds:** no fifth access layer; isolation from Layer 4 customer data;
  tenant-configurable enablement under BP-A08; white-label/custom-domain reuse
  (`20260717090512`, `20260717103015`); time/purpose-bound support access; full
  cross-vendor/cross-customer/cross-tenant isolation tests.

---

### `CG-S11-PRC-019` — Prompt 268, Integrated verification

- **Source:** `PKG/268_PROCUREMENT_VENDOR_INTEGRATED_VERIFICATION_PROMPT.md`
- **Upstream:** `PRC-251..267` all `VERIFIED`; Phase 1–5 closure evidence.
- **Prefer no production schema change.** Verify, do not fix — register every defect with
  source prompt, severity, reproduction, owner and invalidated evidence, and hand it to 269.
  This is the `ATW-026` pattern, which worked well: parallel read-mostly verification agents
  explicitly briefed to *prove, not repair*.
- **Mandatory flow (Prompt 249 §9), end to end:** `Vendor Registration → Mandatory Document
  Verification → Assessment/Approval → Rate → RFQ/Comparison → PO/Contract → Vendor
  Assignment → Actual Cost/ePOD → Vendor Invoice Match → AP Handoff`.
- **Also mandatory:** a 17-capability × 20-anchor evidence matrix; delivery-plan
  `PRC-VND-US-001`; `FINTEST-016`; portal, isolation, API, migration and performance gates;
  least-privilege roles only — **no superuser-only proof**.

---

### `CG-S11-PRC-020` — Prompt 269, Integrity/security/financial hardening

- **Source:** `PKG/269_PROCUREMENT_VENDOR_INTEGRITY_SECURITY_FINANCIAL_HARDENING_PROMPT.md`
- **Upstream:** `PRC-268` `VERIFIED` with findings triaged and assigned.
- **Scope:** only finding-backed repairs. Reproduce and rank every 268 finding, implement
  the **minimal** schema/policy/service/UI/job/docs repair plus a failing-then-passing
  regression, rerun affected focused gates plus the complete critical integrated and
  non-regression suites, and close findings only with durable before/after evidence.
  Document residual risk.

---

### `CG-S11-PRC-021` — Prompt 270, Documentation and handoff

- **Source:** `PKG/270_PROCUREMENT_VENDOR_DOCUMENTATION_HANDOFF_PROMPT.md`
- **Upstream:** `PRC-269` `VERIFIED`.
- **No schema change.** Reconcile requirements/decisions/architecture/schema/API/data-flow/
  traceability docs; publish procurement/vendor user, approver, Finance, Operations and
  optional portal guides; publish runbooks (onboarding, compliance expiry, rate/RFQ,
  PO/contract, capacity, assignment, performance, match exceptions); publish the
  test/security/performance evidence index and known limitations; create explicit **Step 12
  (HRIS employee), Step 13 (customer portal/loyalty), Step 14 (AI/enterprise)** handoffs.
- **Follow the Phase 4 naming precedent:** `PROCUREMENT_VENDOR_HANDOFF_PACKAGE.md` and
  `PROCUREMENT_VENDOR_DOWNSTREAM_CONTRACTS.md`, mirroring `FINANCE_*`.

---

### `CG-S11-PRC-022` — Prompt 271, Independent closure

- **Source:** `PKG/271_PROCUREMENT_VENDOR_CLOSURE_VERIFICATION_PROMPT.md`
- **Produces:** `docs/build-log/phase-06/PROCUREMENT_VENDOR_CLOSURE_REPORT.md`.
- **The only prompt that may set `PHASE_6_VERIFIED`.**
- Never label the phase complete beyond the evidence actually obtained. If 267 closed
  `BLOCKED`, the correct terminal state may be `PHASE_6_PARTIALLY_COMPLETE` — that is an
  honest outcome, not a failure.
- Package-level next command after closure: `LANJUT STEP 12`.

---

## 8. Standing rules for whoever implements from this brief

1. **Pre-flight, every task, no exceptions.** Read all seven `docs/runtime/*.md` files.
   Then run the `ISS-2026-002` collision check: list open pull requests **and** branches via
   the GitHub API before starting, and stop if another open PR or unmerged branch targets
   the same task-ID range. This check was skipped five times in this repository's history
   and caused real content corruption (`ERR-2026-001..003`). `pnpm run git:check` covers only
   the local half.
2. **One task, one branch, one capability.** No batching two prompts into one commit.
3. **Authorization is per-task or per-range and explicit.** This brief authorizes nothing.
4. **The prompt file wins over this brief. The repository wins over the prompt file.**
   Prompt 250 §"Required work" item 2: "Never infer paths from this package."
5. **Adversarial review is not optional.** Every Phase 5 task from `ATW-013` onward found
   real defects in review — several critical, several live-proven data leaks. A task that
   reports zero findings has probably not been reviewed properly. §5 is the opening test
   list, not the whole list.
6. **Never claim more than the evidence supports.** No "production-ready", no "market-ready",
   no "tamper-proof". Disclose the Supreme Admin absolute-CRUD exception (RPD-022) wherever
   immutability might be inferred.
7. **Record `BLOCKED` honestly.** Missing SME/legal evidence (254), missing e-sign provider
   (261), and unresolved external identity ownership (267) are all legitimate blocks with a
   recorded prerequisite — not reasons to invent behavior.
