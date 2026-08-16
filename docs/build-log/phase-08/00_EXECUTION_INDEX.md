# Phase 8 (Customer Portal and Loyalty) — Execution Index

**Prompt:** `CG-S13-CPL-001` (299, Customer Portal and Loyalty WBS Runtime Kickoff)
**Runtime output of:** `299_CUSTOMER_PORTAL_LOYALTY_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Runtime state set by this checkpoint:** `PHASE_8_IN_PROGRESS`
**Runtime state NOT set by this checkpoint:** `PHASE_8_VERIFIED` — reserved exclusively for Prompt 327 (`CG-S13-CPL-029`, Closure Verification), per `299_*.md` §"Required output" ("Do not set the final Phase 8 closure flag") and `298_CUSTOMER_PORTAL_LOYALTY_README.md` §"Exact next command after Step 13 package validation".
**Owner (every row, this build's standing convention):** Claude Code (runtime build agent)

---

## 1. Checkpoint

| Field | Value |
|---|---|
| Repository root | `/home/user/cargogrid.app` |
| Branch | `claude/eksekusi-prompt-299-327-khz22n` |
| HEAD commit (before this checkpoint's own commit) | `b364f7fa09a713f525e8cd49c1d9b66bf25f4f1b` |
| Worktree | clean at time of this checkpoint's own read pass (`git status --short` empty before any file in this checkpoint was written) |
| Checkpoint timestamp | 2026-08-16 (session date; exact commit timestamp recorded in the commit this checkpoint produces) |
| Package manager / runtime | `pnpm@10.33.0`, `node@v22.22.2` (freshly `pnpm install`ed this checkpoint — `node_modules` did not exist at session start in this container) |
| Migrations applied (count) | 232 files under `supabase/migrations/`, latest `20260731320000_harden_hris_employee_lifecycle_effective_dating_tierc_iss2026065.sql` |
| `docs/build-log/phase-08/` | Did not exist before this checkpoint (`ls` confirmed `ENOENT`) — this file is the phase's first artifact |
| Phase 0–7 status | `PHASE_0_VERIFIED` through `PHASE_7_VERIFIED` all set; `PHASE_7_VERIFIED` most recently closed 2026-08-16 at `CG-S12-HRT-025-FINALIZE`, commit `fe1434f` (`docs/build-log/phase-07/HRIS_TICKETING_CLOSURE_REPORT.md` §24) |
| Operator authorization for Phase 8 | Explicit, fresh, separate — the operator's own message this session names the exact range "prompt 299-327" for Phase 8, satisfying `docs/runtime/HANDOFF.md`'s own standing "Phase 8 dependency-clean, pending fresh, separate, explicit operator authorization before Prompt 298/299 may begin" gate |
| Domain code footprint for Phase 8's own subject matter | `git ls-files app/ lib/ server/ components/ supabase/migrations/ \| grep -iE 'loyalty\|points_ledger\|membership_tier\|cashback\|voucher\|redemption\|customer.portal'` → **zero matches** for any Phase-8-owned table/route/contract, independently re-run this checkpoint. The one adjacent, already-`VERIFIED` Phase-7 artifact is the bounded customer-ticket surface (`lib/portal/customer-ticket-guard*.ts`, `app/(tenant)/[tenantSlug]/customer-tickets/**`, `HRT-287`) — disclosed in §3 item 6 below, not a Phase 8 file |
| Standing quality baseline (re-run fresh this checkpoint, container had no `node_modules`/Postgres/PostGIS at session start) | `typecheck` 0 errors; `lint` 0 errors / 271 warnings; `pnpm run test` 4133/4134 passing (1 pre-existing, non-defect, environment-state failure — see §8); `pnpm run db:test` 168/169 files `ALL PASSED` (1 file excluded — pre-existing, date-dependent, non-Phase-8 defect — see §8); `next build` not run this checkpoint (kickoff writes no `app/`/`components/`/`"use server"` code, Tier A gate not triggered per `docs/standards/BUILD_EXECUTION_PROTOCOL.md` §2) |

---

## 2. Runtime entry verdict — **PASS**

Prompt 299's own entry gate requires `PHASE_7_VERIFIED` at the active repository/schema/environment checkpoint, plus the executor having read the current package manifest, confirmed decision register, source matrix, conflict register, coverage matrix, and Step 12 closure evidence, or the task must stop with `PHASE_8_BLOCKED`.

- `PHASE_0_VERIFIED` … `PHASE_6_VERIFIED`: standing, established at their own respective phase closures.
- `PHASE_7_VERIFIED`: set 2026-08-16 at `CG-S12-HRT-025-FINALIZE` (commit `fe1434f`), `docs/build-log/phase-07/HRIS_TICKETING_CLOSURE_REPORT.md` §24 — independently re-confirmed this checkpoint by reading `docs/runtime/CARGOGRID_BUILD_STATUS.md`'s own current-checkpoint line and `docs/runtime/HANDOFF.md`'s own most recent entry, both stating `PHASE_7_VERIFIED` set and Phase 8 dependency-clean.
- `02_CONFIRMED_DECISION_REGISTER.md`, `04_CONFLICT_REGISTER.md`, `05_REQUIREMENT_COVERAGE_MATRIX.md`, `07_PROMPT_PACKAGE_MANIFEST.md`: read/grepped this checkpoint for every Phase-8-relevant row (RPD-004/016/022/023/025/032/033/038/040, the 36 Phase-8 anchor families, Step 12 closure evidence).
- No unresolved `PHASE_8_BLOCKED`-triggering condition was found.
- Pre-flight collision check (`ISS-2026-002`, mandatory per `AGENTS.md` §"Required pre-flight"): `mcp__github__list_pull_requests` (state=open) on `assujiar/cargogrid.app` → zero open PRs. `mcp__github__list_branches` → no branch other than this session's own `claude/eksekusi-prompt-299-327-khz22n` targets the 298-327 prompt range (the most recent related branch, `claude/prompt-291-300-progress-w7bwmb`, is already merged into `main` via PR #57 — confirmed by `git log --oneline` showing the merge commit at `HEAD`). No parallel-session collision risk for this checkpoint.

**Verdict: entry gate PASSES.** `PHASE_8_IN_PROGRESS` is set by this checkpoint (§13 below). `PHASE_8_VERIFIED` is explicitly **not** set — only Prompt 327 may set it.

---

## 3. Ownership/ADR map (required ownership reconciliation)

| # | Item | Verdict | Basis |
|---|---|---|---|
| 1 | Customer-facing (Layer 4) read access shape across the 98 `CG-S10-ATW-032`-narrowed tables and any new owner-scoped surface Phase 8 adds | **RESOLVED — `ADR-0024` Part A.** Every Phase 8 customer read is a new `SECURITY DEFINER` RPC pair (scope resolver + eligibility predicate), mirroring the already-shipped, already-adversarially-reviewed `ATW-023`/`ATW-242` pattern (`supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql`). Raw-table RLS stays exactly as `ATW-032` left it — never reopened. |
| 2 | Customer-initiated actions that would otherwise touch a staff-RBAC-gated canonical mutation (quotation, booking→job-order→shipment-order handoff, warehouse order change, profile edit) | **RESOLVED — `ADR-0024` Part B.** Each becomes a new portal-owned request/intent record; canonical mutation stays staff/system-invoked through existing, unmodified RPCs. No canonical mutation RPC is widened to accept a `customer_user` caller. Keeps `ISS-2026-040` (layer-blind `evaluate_permission`) inert. |
| 3 | REST/GraphQL parity language repeated in all 24 capability prompts' own §14, against a repository that has no live GraphQL server anywhere (`server/policies/graphql-complexity.ts:9-11`) | **RESOLVED — `ADR-0024` Part C.** Phase 8 builds REST over shared `server/contracts/**` Zod schemas; "GraphQL parity" is satisfied by contract-shape reuse and disclosed per-capability as a non-blocking residual gap, identical in kind to the disclosure every Phase 1-7 capability already makes (e.g. `docs/build-log/phase-07/HRT-279.md`/`HRT-280.md` §10/§11). Does not resolve `ADR-CAND-ARCH-017`'s own open live-GraphQL-server candidate — only narrows it for Phase 8's own scope. |
| 4 | Loyalty ledger accounting shape (points/cashback/benefit balances) and Loyalty-to-Finance liability handoff shape — genuinely greenfield, zero prior art in this domain | **RESOLVED — `ADR-0024` Part D.** Ledgers mirror `app.inventory_movements`/`app.inventory_balances` (append-only event + derived generated-column balance, one posting primitive). Finance handoff mirrors HRT-282's `prepare_finance_*_from_*` shape (domain-owned handoff table, Finance acknowledges, never a direct `app.finance_*` write). Reconciliation mirrors FIN-209's execute/resolve-then-certify two-tier gate. |
| 5 | Customer/company/account/site scope model — no separate `app.sites` table exists; `app.accounts` is flat with a self-referencing `parent_account_id` (ADR-0018) | **CLEAR, deliberately left to Prompt 300's own checkpoint, not pre-empted here.** `ADR-0018` already ratified "one entity, no separate `app.customers`/site table" at Phase 2. `docs/build-log/phase-07/HRT-287.md` §4 independently confirms non-cascading parent→child account scope (a customer admin scoped to a parent account does not automatically see child-account data). Prompt 300 §13 must decide whether "site" becomes a new sub-table (Commercial-owned, additive) or an attribute dimension on the existing self-referencing shape — a genuine open design question named by this checkpoint's own research, not resolved here because Prompt 300 needs full schema context this kickoff does not build. |
| 6 | Canonical customer/shipment/invoice/warehouse/ticket records and RPCs each capability reads/extends | **CLEAR, all verified live.** `app.accounts` (`20260724290000_create_commercial_customer_account_conversion.sql`, ADR-0018); `app.quotations` (`20260724210000_create_commercial_quotation_builder.sql`); `app.job_order_handoffs`/`app.job_orders` (`20260724340000...sql`, `20260727090000...sql`); `app.shipment_orders` (`20260727100000...sql`); `app.shipment_legs`/milestones/ePOD/exceptions (Advanced TMS, multiple Phase-5 migrations); `app.inventory_ledger`/`app.wms_outbound_orders` + the pre-built `customer-inventory-access` contract (`20260730310000...sql`, `ATW-023`); `app.finance_invoices`/`app.finance_ar_open_items`/`app.finance_receipts` (Phase 4); `app.tickets` + the already-`VERIFIED` customer ticket channel (`20260731080000_extend_ticketing_customer_channel.sql`, HRT-287). |
| 7 | Customer-ticket capability (Prompt 313) overlap with Phase-7's already-`VERIFIED` `HRT-287` (Customer Ticket) | **CLEAR, no conflict, confirmed additive-only.** `HRT-287` (`docs/build-log/phase-07/HRT-287.md`, `VERIFIED`) already built the full customer-channel ticket schema, create/reply/read/close/reopen RPCs, internal-note-leakage closure, and a bounded (list/detail/reply/cancel/reopen only) customer-tickets route family, explicitly scoped as "sufficient for isolation and contract verification, not the full portal" (`287_CUSTOMER_TICKET_PROMPT.md` §15: "full portal shell/dashboard/account management remains Step 13"). Prompt 313 is a wiring/UX/config task over this already-`VERIFIED` capability (complaint-category taxonomy, SLA display, full Ticket Center UX, REST adapter) — it must not duplicate `app.tickets` or any HRT-286..295 table, per `313_COMPLAINT_TICKET_PROMPT.md` §13's own explicit instruction. |
| 8 | Portal-specific subscription/package entitlement (e.g. "subscription governs live map/history", Prompt 305 §24) versus the existing tenant-level `tracking.*` Configuration-Engine package (`ATW-226A`) | **OPEN, correctly deferred to Prompt 305's own checkpoint — not a kickoff-blocking ambiguity.** `app.resolve_tenant_tracking_package`/`app.is_shipment_tracking_entitled` (`supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql:54-97`) resolve a **tenant-wide** GPS-package entitlement, not a customer-portal-user subscription tier — these are plausibly two different dimensions. Prompt 305 must resolve and disclose which one (or both, composed) gates portal map/history access; this kickoff records the open question rather than guessing, per `AGENTS.md`'s "do not resolve ambiguity ad hoc inside a capability prompt without evidence" discipline turned the other way — here the evidence itself is genuinely insufficient at kickoff time and the decision properly belongs to the capability with full context. |
| 9 | Current dated Indonesia payroll/statutory SME activation evidence (RPD-016) | **NOT APPLICABLE to Phase 8.** RPD-016 gates HRIS/Payroll statutory-rule activation (Phase 7, `HRT-282`), not any Customer Portal or Loyalty capability. No Phase 8 prompt touches payroll/statutory tax logic. |
| 10 | RPD-004/022/023/025/032/033/038/040 contracts and unresolved Critical/High issues | **CLEAR on all counts.** All eight RPD contracts are pre-existing, ratified rows in `02_CONFIRMED_DECISION_REGISTER.md`, already reused verbatim across Phases 1-7 and cited by name in every one of Prompts 300-323's own §16/§26 security-impact sections. **Unresolved Critical/High issues: zero** — independently re-confirmed this checkpoint by column-aware reading of `docs/runtime/KNOWN_ISSUES.md`'s open entries (not a bare substring grep): the highest-severity open items are `ISS-2026-040` (Medium, layer-blind `evaluate_permission`, kept inert by `ADR-0024` Part B) and six further Medium/Low disclosed scope boundaries (`ISS-2026-010`'s named residual, `013`, `015`, `016`, `018`, `019`, `031`), none Critical/High, none blocking. |

**ADR filed this checkpoint:** `docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md` (Status: ACCEPTED). No other item rose to a genuine, blocking ownership ambiguity requiring a new ADR — items 5-10 above are resolved by direct citation to already-existing, already-ratified repository evidence, or correctly left open as a named, disclosed, non-blocking item for the capability prompt that owns the missing context.

---

## 4. Required hierarchy — Phase → Workstream → Epic → Capability → Task

Phase 8 decomposes into 9 workstreams, each containing one or more of Prompts 300–327 as its capability-level epics. No capability appears in more than one workstream; no workstream is empty.

| Workstream (epic) | Capabilities (Prompt / `CG-S13-CPL-NNN`) | Count |
|---|---|---|
| 1. Customer Access Foundation | 300 (`-002`, Customer User Scope), 301 (`-003`, Customer Portal Dashboard) | 2 |
| 2. Commercial Self-Service | 302 (`-004`, Request Quotation), 303 (`-005`, Booking), 304 (`-006`, Shipment Order) | 3 |
| 3. Shipment Visibility and Evidence | 305 (`-007`, Tracking), 306 (`-008`, Shipment Monitoring), 307 (`-009`, ePOD Access), 308 (`-010`, Document Center) | 4 |
| 4. Warehouse Visibility | 309 (`-011`, Warehouse Inventory Visibility), 310 (`-012`, Warehouse Order/Fulfillment Visibility) | 2 |
| 5. Finance Visibility | 311 (`-013`, Invoice/Billing Visibility), 312 (`-014`, Payment Visibility) | 2 |
| 6. Service and Account Management | 313 (`-015`, Complaint/Ticket), 314 (`-016`, Customer Profile), 315 (`-017`, Customer User Management) | 3 |
| 7. Loyalty Program Core | 316 (`-018`, Loyalty Program/Earning), 317 (`-019`, Membership Tier), 318 (`-020`, Points Ledger), 319 (`-021`, Cashback/Discount/Voucher) | 4 |
| 8. Loyalty Redemption and Governance | 320 (`-022`, Reward Catalogue), 321 (`-023`, Redemption/Approval/Fulfillment), 322 (`-024`, Expiry/Fraud Prevention), 323 (`-025`, Liability/Reconciliation Analytics) | 4 |
| 9. Integrated Verification, Hardening, Documentation and Closure | 324 (`-026`), 325 (`-027`), 326 (`-028`), 327 (`-029`) | 4 |

**Total: 28 capabilities = exactly Prompts 300–327**, zero overlap, zero unassigned. Prompt 299 (this kickoff, `-001`) sits above all 9 workstreams as the WBS root that creates them and is not itself a member of any workstream.

Each of the 28 capability prompts is to be instantiated as one or more atomic tasks carrying unique WBS/task/prompt IDs, exact source anchors, exact prerequisite IDs, allowed/forbidden paths (normally 5–15 changed files, at most 1–3 additive migrations per `299_*.md`'s own inherited template budget), and a runtime log path under `docs/build-log/phase-08/`. **No atomic task has been instantiated yet** — this kickoff creates the WBS structure and releases the first eligible prompt; sub-task splitting is each capability's own job at its own checkpoint.

---

## 5. Dependency graph

The declared upstream dependencies of every one of Prompts 300–323 (read in full this checkpoint, not inferred) cite only strictly lower-numbered `CPL-` IDs plus already-`VERIFIED` Phase 1-7 domain contracts — the graph is a DAG by construction. Unlike Phase 7's two-independent-chains shape, Phase 8 converges through a single mandatory root:

```
CPL-299 (kickoff)
   │
   ▼
CPL-300 (Customer User Scope) ── the mandatory scope primitive; gates every capability below
   │
   ├──► CPL-301 (Dashboard) ──────────────────────────────────────────┐
   │                                                                   │  (dashboard cards deep-link
   ├──► Commercial Self-Service track                                 │   into every scoped flow;
   │    CPL-302 → 303 → 304 ───────────────────────────────┐          │   no flow trusts the
   │                                                         │          │   dashboard itself)
   ├──► Shipment Visibility track (needs 304 for shipment)  │          │
   │    CPL-305 → 306, CPL-307 → 308 ◄──────────────────────┘          │
   │                                                                   │
   ├──► Warehouse Visibility track                                    │
   │    CPL-309 → 310 ─────────────────────────────────────┐          │
   │                                                         │          │
   ├──► Finance Visibility track (needs 304/310 billing refs)│         │
   │    CPL-311 → 312 ◄─────────────────────────────────────┘          │
   │                                                                    │
   ├──► Service/Account track (needs Phase-7 HRT-286..292 + 308/311)   │
   │    CPL-313, CPL-314 → 315                                          │
   │                                                                    │
   └──► Loyalty track (needs 300 + Finance 311/312 paid-eligibility)    │
        CPL-316 → 317 → 318 → 319 → 320 → 321 → 322 → 323               │
                                                         │                │
        all of the above ◄────────────────────────────────────────────┘
                          (CPL-301 is downstream of 300 only for its own
                           release, but every later capability's dashboard
                           card is itself downstream of that capability)
                          │
                          ▼
              CPL-324 → 325 → 326 → 327 (closure track, strictly serial,
                                          never batched per AGENTS.md)
```

**Practical batching implication (stated before any code is written, per `AGENTS.md` "Execution cadence"):** this checkpoint plans five implementation batches of at most 5 prompts each, in strict numeric order — `300–304`, `305–309`, `310–314`, `315–319`, `320–323` (4, closing the loyalty-adjacent tail cleanly) — followed by the four closure prompts `324`, `325`, `326`, `327` each run solo, never batched with each other or with any capability prompt, per `AGENTS.md`: *"Never batch phase Integrated Verification / Hardening / Documentation / Closure prompts."* Batch size narrows adaptively (to ≤4 then ≤3) if a batch closes with a Critical/High finding, per the same standing rule. This ordering matches the DAG above: no batch's own prompt cites an upstream ID that has not `VERIFIED` in an earlier batch, since 305-308 (batch 2) only need 300 (batch 1) plus already-`VERIFIED` Phase 5 Operations contracts, not 302-304's own outputs directly (304 is a *named* upstream for 305/307/308 in the prompts' own §9 prose in the sense of "shipment order exists as a concept," not a hard schema dependency — both reference the same already-`VERIFIED` `app.shipment_orders`/`app.shipment_legs` tables independently). This is flagged here, not silently assumed: batch 2's own kickoff must re-confirm 300-304 (batch 1) closed `VERIFIED` before it starts, per the standing rule that a downstream prompt may only be *released* on an upstream `COMPLETED` within the same batch — across a batch boundary every prompt in the prior batch must be `VERIFIED` first.

---

## 6. 28-capability × 36-anchor traceability

All 20 `CPT-*` anchors (five families) and all 16 `LYL-*` anchors (four families) have at least one owning capability assigned below. **"Covered" here means every anchor has a named owning capability prompt in this WBS — it does not mean built or verified; Phase 8 is greenfield (§1).** Cross-verified against `298_CUSTOMER_PORTAL_LOYALTY_README.md` §"Anchor coverage" and each capability prompt's own §6.

| Anchor family | Owning capability(ies) | WBS status | Disclosed gate/gap |
|---|---|---|---|
| `CPT-QBK-001..004` (Quote Request & Booking) | CPL-302, 303, 304 (secondary touch: 300 as scope root) | WBS-assigned | none — `ADR-0024` Part B fixes the write shape |
| `CPT-TRK-001..004` (Shipment Tracking, ePOD & Document) | CPL-305, 306, 307, 308 (secondary touch: 304 for the shipment-order projection itself) | WBS-assigned | Prompt 305's portal-specific subscription dimension is an open, disclosed item (§3 row 8) |
| `CPT-WHS-001..004` (Warehouse Inventory & Fulfillment Visibility) | CPL-309, 310 | WBS-assigned | none — `ATW-023`'s pre-built read-RPC layer substantially covers 309; 310 has no pre-built inbound/receiving analog and must add it |
| `CPT-BIL-001..004` (Invoice, Billing, Payment & Profile) | CPL-311, 312 (secondary touch: 314 Customer Profile, which the source blueprint co-locates in this same anchor family) | WBS-assigned | none — Finance's `field-access` primitive has never been applied to Finance tables before; 311/312 are its first Finance consumer, disclosed not blocking |
| `CPT-CX-001..004` (Complaint, Ticket, Loyalty & Rewards) | CPL-313 (secondary touch: 314, 315, 320, all of which also cite this anchor family) | WBS-assigned | none — HRT-287 already covers the ticket schema/RPC core; 313 is additive UX/config only |
| `LYL-PRG-001..004` (Loyalty Program) | CPL-316, 317 | WBS-assigned | none — `ADR-0024` Part D fixes the ledger shape before any code is written |
| `LYL-PNT-001..004` (Points) | CPL-316, 318, 319 | WBS-assigned | none |
| `LYL-RDM-001..004` (Reward, Redemption, Referral & Expiration) | CPL-318, 319, 320, 321, 322 | WBS-assigned | fraud-prevention scope is deliberately rule/governance-based only (322 §24); predictive fraud remains Step 14, disclosed not a Phase 8 gap |
| `LYL-ANL-001..004` (Loyalty Analytics & Liability) | CPL-322, 323 | WBS-assigned | analytics depth beyond deterministic liability evidence remains Step 14, disclosed not a Phase 8 gap |

No anchor family is `NOT_COVERED`. Every disclosed gate above is either already resolved by `ADR-0024`, already covered by an existing `VERIFIED` Phase 5/7 capability, or an explicit, named, non-blocking deferral to Step 14/15 — none blocks any task this index releases or holds at this checkpoint.

---

## 7. File/migration/contract collision matrix

**Trivially clean — greenfield.** Independently re-confirmed this checkpoint: `git ls-files app/ lib/ server/ components/ supabase/migrations/ | grep -iE 'loyalty|points_ledger|membership_tier|cashback|voucher|redemption|customer.portal'` returns **zero matches** for any Phase-8-owned artifact (the one Phase-7-owned adjacent hit, `lib/portal/customer-ticket-guard*.ts`, is disclosed in §3 item 7 as already-`VERIFIED` and out of Phase 8's own collision scope). No Phase 8 file, migration, table, RPC, or REST contract exists anywhere in the repository to collide with. The files this kickoff itself writes (`docs/adr/ADR-0024-*.md`, `docs/build-log/phase-08/00_EXECUTION_INDEX.md`, and this checkpoint's `docs/runtime/*` updates) do not collide with any existing path.

No collision matrix entry is therefore populated with a real conflict at this checkpoint. The matrix becomes load-bearing starting at whichever capability this index next releases into an atomic task with concrete allowed-file paths (§10) — that task's own build-log entry must populate this matrix for real before any second, concurrently-running task is released. Given §5's single-root DAG shape (everything gates on `CPL-300`), concurrent release within Phase 8 is less structurally available than Phase 7's two-independent-chains shape offered — batches proceed in strict numeric order (§5), not concurrently, unless a future checkpoint finds and discloses a genuine independent sub-track.

---

## 8. Baseline/gate matrix

Gate commands independently re-run live at this repository this checkpoint (container had no `node_modules`, no running Postgres, and no PostGIS extension installed at session start — all three were provisioned fresh this checkpoint: `pnpm install`, `service postgresql start`, `apt-get install postgresql-16-postgis-3`).

| Gate category | Status | Command / mechanism / result |
|---|---|---|
| Clean install | Real, freshly run | `pnpm install` — 7.9s, zero errors |
| Typecheck | **PASS** | `pnpm run typecheck` (`tsc --noEmit`) — 0 errors |
| Lint | **PASS** | `pnpm run lint` (`eslint .`) — 0 errors, 271 warnings (pre-existing `@next/next/no-html-link-for-pages` class, not touched by this checkpoint) |
| Unit/integration tests | **PASS with 1 disclosed, non-defect, environment-state failure** | `pnpm run test` — 4133/4134 passing. The one failure (`checkWorktreeCollision — the current branch is reported as diverged from origin/main`, `scripts/git/check-worktree-collision.test.ts:36`) asserts the current branch has commits ahead of `origin/main`; at the moment this checkpoint's own baseline ran, this branch had zero new commits yet (freshly checked out, matching `origin/main` exactly) — the test's own assertion is checkpoint-state-dependent by design, not a code defect, and resolves itself the moment this checkpoint's own first commit lands. Re-run after this checkpoint's commit to confirm (see §14). |
| Database/migration/RLS tests | **168/169 files `ALL PASSED`, 1 file excluded and disclosed, not a Phase 8 defect** | `bash scripts/db-tests/run.sh` halts (by design, `set -euo pipefail`) at `scripts/db-tests/hris-overtime-timesheet.sql:284` — a pre-existing Phase 7 (`HRT-281`) test fixture that pins its overtime request's `work_date` to `current_date` (`hris-overtime-timesheet.sql:169`) and then hard-asserts the classification `'weekday'`. 2026-08-16 (this session's real date) is a Sunday; the server-side classification function correctly computes `'weekend'` — the **test's own assertion**, not the production classification logic, is wrong on any Saturday/Sunday run. Verified by ad hoc re-run excluding only this one file (`/tmp/.../scratchpad/run-db-tests-baseline.sh`, not committed, session-scratchpad only): all other 168 files pass clean. Registered as a new, disclosed, non-blocking `KNOWN_ISSUES.md` entry this checkpoint (see §11) — not fixed here, per `AGENTS.md` "fix only task-caused failures... log unrelated/pre-existing failures and create a separate recovery task"; this is Phase-7-owned test-fixture scope, not Phase 8. |
| Build | Not run this checkpoint | Kickoff writes no `app/`, `components/`, or `"use server"` module — Tier A's `next build` trigger condition (`docs/standards/BUILD_EXECUTION_PROTOCOL.md` §2) is not met. Will run at the first Phase 8 capability prompt that touches those paths (expected: `CPL-301`, the dashboard shell). |
| `git:check-paths` | Not yet re-run against this checkpoint's own final diff | Will run before commit, per standing pre-commit discipline. |
| `security:check` / `data-classification:check` | Not yet re-run against this checkpoint's own final diff | Will run before commit. |

---

## 9. Critical path

`CPL-300` is the sole critical-path root — no other capability can start before it `VERIFIED`, and every one of the other 27 capability prompts names it as a direct or transitive upstream dependency (§5). After `CPL-300`, the critical path runs through the longest single dependency chain in the DAG: the Loyalty track, `CPL-316 → 317 → 318 → 319 → 320 → 321 → 322 → 323` (8 strictly sequential capabilities, each naming the previous as a hard upstream, per §5), itself gated on `CPL-311`/`312` (Finance paid-eligibility) having `VERIFIED` first. The closure track (`324 → 325 → 326 → 327`) is strictly serial by `AGENTS.md`'s own "never batch" rule and adds 4 more sequential steps after every capability prompt is `VERIFIED`. Total critical-path length: `300 → 311 → 312 → 316 → 317 → 318 → 319 → 320 → 321 → 322 → 323 → 324 → 325 → 326 → 327` = 15 sequential capability-level gates, the longest true dependency chain in Phase 8, independent of this checkpoint's own 5-batch execution grouping (§5), which is a scheduling choice, not a dependency requirement.

---

## 10. Task state (all 29 rows; vocabulary restricted to `299_*.md`'s own set: `READY` / `BLOCKED` / `COMPLETED` / `VERIFIED`)

| Task ID | Prompt | Capability | Dependencies | Status |
|---|---|---|---|---|
| `CG-S13-CPL-001` | 299 | Customer Portal and Loyalty WBS Runtime Kickoff | `PHASE_7_VERIFIED` + operator authorization | `COMPLETED` this checkpoint (sets `PHASE_8_IN_PROGRESS`; a kickoff prompt is not itself entered into the `VERIFIED` capability chain — it has no downstream reviewer batch of its own, mirroring `CG-S12-HRT-001`'s own final task-state row in `docs/build-log/phase-07/00_EXECUTION_INDEX.md` §10) |
| `CG-S13-CPL-002` | 300 | Customer User Scope | `CPL-001` `COMPLETED` | **`READY`** — dependency-clean, first eligible prompt (§14) |
| `CG-S13-CPL-003` | 301 | Customer Portal Dashboard | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-004` | 302 | Request Quotation | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-005` | 303 | Booking | `CPL-002`, `CPL-004` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-006` | 304 | Shipment Order | `CPL-002`, `CPL-005` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-007` | 305 | Tracking | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-008` | 306 | Shipment Monitoring | `CPL-002`, `CPL-007` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-009` | 307 | ePOD Access | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-010` | 308 | Document Center | `CPL-002`, `CPL-004`(booking refs), `CPL-006`(shipment refs), `CPL-009` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-011` | 309 | Warehouse Inventory Visibility | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-012` | 310 | Warehouse Order/Fulfillment Visibility | `CPL-002`, `CPL-011` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-013` | 311 | Invoice and Billing Visibility | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-014` | 312 | Payment Visibility | `CPL-002`, `CPL-013` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-015` | 313 | Complaint and Ticket | `CPL-002`, HRT-286..292 (`VERIFIED`) | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-016` | 314 | Customer Profile | `CPL-002` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-017` | 315 | Customer User Management | `CPL-002`, `CPL-016` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-018` | 316 | Loyalty Program and Earning | `CPL-002`, `CPL-013`, `CPL-014` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-019` | 317 | Membership Tier | `CPL-018` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-020` | 318 | Points Ledger | `CPL-018`, `CPL-019` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-021` | 319 | Cashback, Discount and Voucher | `CPL-018`, `CPL-020` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-022` | 320 | Reward Catalogue | `CPL-018..021` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-023` | 321 | Redemption Approval and Fulfillment | `CPL-020`, `CPL-021`, `CPL-022` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-024` | 322 | Expiry and Fraud Prevention | `CPL-018..023` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-025` | 323 | Liability Reconciliation Analytics | `CPL-018..024` | `BLOCKED` (pending predecessor) |
| `CG-S13-CPL-026` | 324 | Customer Portal and Loyalty Integrated Verification | `CPL-002..025` all `VERIFIED` | `BLOCKED` (pending predecessor; never batched with any other prompt) |
| `CG-S13-CPL-027` | 325 | Customer Portal and Loyalty Privacy, Integrity and Hardening | `CPL-026` `VERIFIED` | `BLOCKED` (pending predecessor; never batched) |
| `CG-S13-CPL-028` | 326 | Customer Portal and Loyalty Documentation and Handoff | `CPL-027` `VERIFIED` | `BLOCKED` (pending predecessor; never batched) |
| `CG-S13-CPL-029` | 327 | Customer Portal and Loyalty Closure Verification | `CPL-028` `VERIFIED` | `BLOCKED` (pending predecessor; never batched; the only task authorized to set `PHASE_8_VERIFIED`) |

Planned batch grouping for review cadence (`AGENTS.md` "Execution cadence", stated before any code is written, per §5): **Batch 1** `CPL-002..006` (Prompts 300-304); **Batch 2** `CPL-007..011` (305-309); **Batch 3** `CPL-012..016` (310-314); **Batch 4** `CPL-017..021` (315-319); **Batch 5** `CPL-022..025` (320-323, 4 prompts); then `CPL-026`, `027`, `028`, `029` each solo.

---

## 11. Evidence/log path

- This file: `docs/build-log/phase-08/00_EXECUTION_INDEX.md` — living index, appended with one `## N. Update — ...` section per completed prompt/batch, mirroring `docs/build-log/phase-07/00_EXECUTION_INDEX.md`'s own convention.
- Per-capability build logs: `docs/build-log/phase-08/CPL-<NNN>.md` (one per Prompt 300-327, created at that prompt's own checkpoint — none exist yet).
- ADR: `docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md`.
- Evidence ledgers required by `299_*.md` §6 (created empty/scaffolded this checkpoint, populated by the capability prompts that generate real evidence):
  - **Scope isolation** — populated by `CPL-300` onward; every capability's own db-test proving deny-by-default for a `customer_user` actor is the evidence unit.
  - **File scanning/signed URL** — populated by `CPL-307`/`308` (ePOD/Document Center), reusing PLT-128's existing scan/signed-URL evidence discipline.
  - **REST/GraphQL parity** — populated per-capability as a disclosed residual-gap entry (§8/`ADR-0024` Part C), not a passing gate, until a future dedicated GraphQL-server capability exists.
  - **Loyalty ledger exactness** — populated by `CPL-318` onward; the db-test proving `point_balances`-style derivation matches ledger totals exactly is the evidence unit, mirroring the inventory-ledger precedent's own reconciliation test shape.
  - **Fraud/approval** — populated by `CPL-321`/`322`.
  - **Liability reconciliation** — populated by `CPL-323`, mirroring FIN-209's own reconciliation-run evidence shape.
  - **Performance** — populated per-capability per `AGENTS.md`'s "server-side filter/sort/search/pagination... never OFFSET" discipline; no dedicated Phase 8 performance capability exists (matches Phase 5-7 precedent — load/perf testing is a Step 15 hardening concern unless a capability's own risk profile requires an earlier check).
  - **Rollback** — see §12.
- `docs/runtime/KNOWN_ISSUES.md`: new entry registered this checkpoint for the disclosed `hris-overtime-timesheet.sql` date-dependent test defect (§8) — Low severity, Phase-7-owned, non-blocking.

---

## 12. Rollback

All work this checkpoint is additive-only and reversible: one new ADR file, one new execution-index file, and appended (never rewritten in place) sections in `docs/runtime/TASK_LEDGER.md`/`CARGOGRID_BUILD_STATUS.md`/`HANDOFF.md`/`KNOWN_ISSUES.md`. No migration, no application code, no existing file's prior content was altered. Rollback, if ever required, is `git revert` of this checkpoint's own commit — no database state, no applied migration, and no other phase's evidence is touched. Last known good checkpoint before this one: `fe1434f` (Phase 7 `PHASE_7_VERIFIED` finalization).

---

## 13. Runtime state and resume

`PHASE_8_IN_PROGRESS` is set by this checkpoint. A future agent with no access to this conversation resumes by: (1) reading `docs/runtime/HANDOFF.md`'s most recent entry, (2) reading this file in full, (3) confirming `CG-S13-CPL-002` (Prompt 300) is still the first `READY` row in §10 (or reading whichever later row is `READY` if this file has since been updated), (4) reading `docs/adr/ADR-0024-*.md` before writing any Phase 8 schema/RPC, since it fixes four repository-wide shapes every capability prompt from 300 onward must follow without re-deriving them.

---

## 14. First eligible prompt

**`CG-S13-CPL-002` (Prompt 300, Customer User Scope).** Dependency-clean (only prerequisite is this kickoff, `COMPLETED`). Batch 1 (`CPL-002..006`, Prompts 300-304) begins with this prompt. Before Batch 1's first prompt starts, per `AGENTS.md`'s "runs once per batch, before its first prompt" pre-flight collision check: already run this checkpoint (§2) — clear, no re-run needed at Batch 1's own start since no new PR/branch activity intervenes between this kickoff and Batch 1 beginning in the same session.
