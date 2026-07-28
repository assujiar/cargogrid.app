# 00 — Finance Work Breakdown Structure

**Prompt:** `CG-S9-FIN-001` (`CG-AABPP-FIN-190` v0.10.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/09-phase-04-finance/190_FINANCE_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_4_IN_PROGRESS` (kickoff/index only — no Finance-domain schema/code exists yet; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Finance tasks from repository evidence already produced by Phase 3's own closure/handoff package (`docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md`, `OPERATIONS_HANDOFF_PACKAGE.md`, `OPERATIONS_DOWNSTREAM_CONTRACTS.md`) and the Phase 4 package itself (`docs/ai-agent-build-prompt-package/09-phase-04-finance/`). It reproduces the capability catalogue and dependency order from `189_FINANCE_README.md` §4 by reference — the same "one source, not a second copy that could drift" discipline every prior phase kickoff/WBS document in this repository has followed (`00_PHASE0_WBS.md`, `00_PLATFORM_CORE_WBS.md`, `00_COMMERCIAL_WBS.md`, `00_OPERATIONS_WBS.md`).

## 1. Mandatory hierarchy (`189_*.md` §3 / `190_*.md` mandatory entry gate)

`Phase 4 → Workstream → Epic → Capability → Feature slice → Atomic implementation/verification/hardening/documentation/closure task`.

## 2. Runtime entry gate verification (`190_*.md` mandatory entry gate)

| # | Condition | Verified | Evidence |
|---:|---|---|---|
| 1 | `RUNTIME_DISCOVERY_VERIFIED` | ✔ | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` — unchanged |
| 2 | `RUNTIME_ARCHITECTURE_VERIFIED` | ✔ | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` — unchanged |
| 3 | `PHASE_0_VERIFIED` | ✔ | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| 4 | `PHASE_1_VERIFIED` | ✔ | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| 5 | `PHASE_2_VERIFIED` | ✔ | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` |
| 6 | `PHASE_3_VERIFIED` | ✔ | `docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md` — all 22 rows `VERIFIED`, set at `OPS-188` |
| 7 | Repository/branch/HEAD/worktree reconciled, schema/migration state (71 migrations) confirmed, Platform/Commercial/Operations contracts inspected, `BillingReadinessHandoff`/actual-cost evidence located, environment/baseline/unresolved ledgers reconciled | ✔ | §3–§9 below |

**Result: entry gate PASS.** `PHASE_4_BLOCKED` is not warranted.

## 3. Repository checkpoint at kickoff

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-189-sd-184-gtivdr` (harness-assigned; tracked to `origin/claude/prompt-189-sd-184-gtivdr` this checkpoint) |
| HEAD at authoring time (pre-commit) | `0304e66` (merge of PR #25, `OPS-188` — `PHASE_3_VERIFIED` set) |
| Worktree state | Clean except this document, its sibling `FINANCE_EXECUTION_INDEX.md`, and this checkpoint's own runtime-ledger updates |
| Schema/migration state | 71 migrations applied, unchanged this checkpoint — kickoff performs zero schema change |
| Package manager/runtime | pnpm `10.33.0` + Node `>=22.11.0`; `node:test` unit suite (1747 tests); Playwright E2E; `db:test` (Postgres 16 + PostGIS 3, `scripts/db-tests/run.sh`) |
| Baseline gate results (re-run fresh this checkpoint, before any Finance file is written) | `typecheck` PASS; `lint` PASS (0 errors, pre-existing `no-html-link-for-pages` warning class unchanged); `test` 1746/1747 — the one failure (`checkWorktreeCollision`'s "current branch has commits ahead of origin/main" assertion) is a disclosed, transient pre-commit-state artifact of this being a freshly checked-out branch with zero own commits yet (see `docs/runtime/ERROR_LEDGER.md`), expected to clear the instant this task's own commit lands, and re-confirmed clear below (§9); `db:test` PASS across 71 migrations/72 db-test files; `next build` PASS (56 routes) |
| Authorization | Explicit user instruction naming Finance Phase 4 prompts 190, 191, 192, 193, 194 in order, one commit each, pushed after each commit — the same class of scoped, multi-task, named-endpoint authorization `OPERATIONS_EXECUTION_INDEX.md` §0 already accepted without a further `AskUserQuestion` round |

## 4. `BillingReadinessHandoff` / actual-cost contract reconciliation (`190_*.md` required task 1/2)

Finance consumes, never re-enters:

| Upstream contract | Source | Consumed by |
|---|---|---|
| `app.billing_readiness_evaluations` / `app.billing_readiness_handoffs` (versioned, `effective_status` generated column, idempotent handoff keyed `(tenant_id, job_order_id, idempotency_key)`) | `OPS-181`, `supabase/migrations/20260728140000_create_operations_billing_readiness.sql` | `FIN-196` (Accounts Receivable), `FIN-197` (Invoice) |
| `app.job_orders.revenue_snapshot` / `credit_snapshot` (governed jsonb snapshots, never recomputed) | `OPS-168`/Commercial handoff (`COM-164`) | `FIN-196`, `FIN-212` (Profitability) |
| `app.actual_cost_*` (approved, `is_current`, source-linked to vendor/resource) | `OPS-178`, `supabase/migrations/20260728110000_create_operations_actual_cost.sql` | `FIN-199` (Accounts Payable), `FIN-200` (Vendor Bill), `FIN-212` |
| `app.job_order_lineage`/transaction lineage (quote → job → shipment → billing evidence) | `OPS-184`, `supabase/migrations/20260728170000_create_operations_transaction_lineage.sql` | `FIN-202` (Subledger), `FIN-212` |
| Money convention: `numeric(14,2)` (amounts), `numeric(14,4)` (quantity/rate); currency stored `text` matching `^[A-Z]{3}$`; **no FX/multi-currency conversion exists anywhere pre-Phase-4** (`COM-150`'s own disclosed boundary: `mixed_currency` fails closed rather than converting) | `COM-150`, `OPS-179` | `FIN-194` is the first capability in this repository to build real exchange-rate conversion |
| Platform Configuration Engine (`app.config_types`/`config_objects`/`config_versions`/`config_items`/`config_dependencies`, draft→publish→rollback, 6-level precedence resolver) | `PLT-121`, `supabase/migrations/20260717130000_create_configuration_engine.sql` | `FIN-191` reuses this directly — see §6 |
| Numbering Engine (format-token validation, atomic counters, reservation) | `PLT-125`, `supabase/migrations/20260719110000_create_numbering_engine.sql` | `FIN-191`'s document-numbering slice models its per-document-class definitions on this pattern (§6) |
| RBAC evaluator (`app.evaluate_permission`), canonical `FIN` permission catalogue (`View`, `Create`, `Edit`, `Delete`, `Approve`, `Reject`, `Export`, `View cost`, `View margin`, `Override`, `Reopen`, `Close`) | `PLT-111`/`PLT-112`, `supabase/migrations/20260716103445_create_roles_permissions.sql`/`20260716104519_create_rbac_evaluator.sql` | Every Finance capability's authority check — no new `FIN` permission-catalogue row is needed through `FIN-194` |

No customer, job, shipment, ePOD, document, charge, rate, or cost data is re-entered by any Finance task — every Finance record either references an upstream id or snapshots a governed value already captured by Commercial/Operations, matching `189_*.md` §5's binding rule.

## 5. Capability catalogue and dependency order (reproduced by reference, `189_*.md` §4)

See `FINANCE_EXECUTION_INDEX.md` §1 for the full 28-row table (`190`–`218`) with exact task IDs, dependencies, and this session's authorized/`READY` range (`191`–`194`).

## 6. Reuse-vs-fork decisions recorded this checkpoint

- **FIN-191 (Finance Configuration) reuses `PLT-121`'s Configuration Engine directly** (`app.config_types`/`register_config_type`, `app.config_objects`/`create_config_draft`, `app.set_config_items`, `app.publish_config_version`, `app.discard_config_draft`, `app.rollback_config_version`, `app.resolve_config`) rather than building an eighth, one-off versioned-policy state machine. This mirrors `OPS-173`'s own precedent decision (Milestone Management reusing the Workflow/Status engines rather than forking a new lifecycle) and is the exact reuse the prompt package cites (`PLT-CFG-001..004`, §6 of `191_FINANCE_CONFIGURATION_PROMPT.md`). Finance-specific structural validation (rounding-mode/precision bounds, numbering format-token rules per document class, budget/accrual/recognition enum bounds) is added as new, additive Finance-only wrapper functions (`app.create_finance_config_draft`, `app.publish_finance_config_version`, etc.) that delegate to the generic engine after their own domain check — never a parallel copy of the generic draft/publish/rollback mechanics themselves. Full design rationale: `docs/build-log/phase-04/FIN-191.md` §3.1.
- **FIN-191's posting-map class stores account-code references structurally only** (regex-shaped, uniqueness-checked) because no Chart of Accounts exists yet at this point in the dependency order (`191` precedes `192` per the catalogue). Existence/active-state resolution against `app.finance_accounts` is `FIN-192`'s own downstream job, disclosed as a forward reference rather than silently promised. See `FIN-192.md` for the resolution.
- **FIN-192..194 introduce real domain tables** (chart of accounts, fiscal calendars/periods, currencies/exchange rates) rather than forcing structurally different concerns (hierarchy, non-overlapping date ranges, rate-pair versioning) into the generic config engine's flat key/value item shape — each still reuses the repository's own established versioned-table idiom (`record_version` optimistic concurrency, `app.evaluate_permission`/`app.has_active_tenant_membership` authority, `app.capture_audit_event` audit, RLS via `has_active_tenant_membership`/`is_supreme_admin`) rather than inventing a ninth access/versioning convention.

## 7. Phase 4/5/6/8/13/15 boundaries encoded (`190_*.md` required tasks 8/9)

- **Phase 4/11 (Procurement/Vendor)**: no vendor master, PO/contract lifecycle, or three-way match exists in `191`–`214`; `FIN-199`/`200` reference verified Operations vendor/resource and actual cost only, never a new vendor-onboarding surface.
- **Phase 4/13 (Customer Portal)**: no customer-facing invoice/payment/dispute view is built by `191`–`214`; those remain internal Finance UX and governed contracts only.
- **Phase 4/15 (full-system hardening)**: no full-system finance audit is performed by `190`–`218`; `216` is Finance-scoped hardening only.
- **Phase 4/tax (`195`)**: Indonesia-first PPN/VAT/withholding activation remains `BLOCKED` pending current legal/finance/tax SME evidence — no legal rate is invented anywhere in this WBS.

## 8. Atomic sizing

Every one of `191`–`194` (this session's authorized range) targets 1 additive migration, 5–15 changed files, matching the verified repository boundary every Commercial/Operations capability already used. `195`–`214` are sized identically in the execution index but remain `NOT_STARTED`/`BLOCKED` — not instantiated with exact file paths yet, since instantiating a task's exact file list before its own upstream is `VERIFIED` risks stale paths (the same discipline `167_*.md`'s own WBS applied to `176`–`188` while only `168`–`175` was in scope).

## 9. Safe concurrency lanes and post-kickoff baseline re-check

Single session, single branch (`claude/prompt-189-sd-184-gtivdr`), sequential execution `191`→`192`→`193`→`194` per the dependency table — no parallel lane is opened, matching every prior phase's own one-agent-one-branch discipline. Immediately after this kickoff task's own commit lands, `pnpm run test` was re-run and confirmed **1747/1747** (the transient `checkWorktreeCollision` failure disclosed in §3 cleared exactly as predicted, now that the branch carries its own commit ahead of `origin/main`) — recorded here rather than silently assumed.

## 10. Completion statement

This document plus `FINANCE_EXECUTION_INDEX.md` satisfy `190_*.md`'s required output. `PHASE_4_IN_PROGRESS` is set this checkpoint (not `PHASE_4_VERIFIED` — only Prompt 218 may set that). `CG-S9-FIN-002` (Prompt 191, Finance Configuration) is the next eligible task, and this session's explicit authorization extends it, `CG-S9-FIN-003` (192), `CG-S9-FIN-004` (193), and `CG-S9-FIN-005` (194) to `READY`. `CG-S9-FIN-006` (Prompt 195, Tax Baseline) onward remain `NOT_STARTED`/`BLOCKED`, dependency-correct but not authorized this session.
