# 00 — Operations Work Breakdown Structure

**Prompt:** `CG-S8-OPS-001` (`CG-AABPP-OPS-167` v0.9.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/08-phase-03-operations/167_OPERATIONS_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_3_IN_PROGRESS` (kickoff/index only — no capability task `168`–`188` has executed; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Operations tasks from repository evidence already produced by Phase 2's own closure/handoff package (`docs/build-log/phase-02/COMMERCIAL_HANDOFF_PACKAGE.md`, `JOB_ORDER_HANDOFF_CONTRACT.md`) and the Phase 3 package itself (`docs/ai-agent-build-prompt-package/08-phase-03-operations/`). It does not re-derive the capability catalogue or dependency order — both are reproduced by reference from `166_OPERATIONS_README.md` §4 — the same "one source, not a second copy that could drift" discipline every prior phase kickoff/WBS document in this repository has followed (`00_PHASE0_WBS.md`, `00_PLATFORM_CORE_WBS.md`, `00_COMMERCIAL_WBS.md`).

## 1. Mandatory hierarchy (`166_*.md` §3)

`Phase 3 → Workstream → Epic → Capability → Feature slice → Atomic implementation/verification/hardening/documentation/closure task`.

## 2. Runtime entry gate verification (`167_*.md` mandatory entry gate)

| # | Condition | Verified | Evidence |
|---:|---|---|---|
| 1 | `RUNTIME_DISCOVERY_VERIFIED` | ✔ | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` — unchanged since Phase 0 |
| 2 | `RUNTIME_ARCHITECTURE_VERIFIED` | ✔ | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` — unchanged |
| 3 | `PHASE_0_VERIFIED` | ✔ | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| 4 | `PHASE_1_VERIFIED` | ✔ | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| 5 | `PHASE_2_VERIFIED` | ✔ | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` — set this session, all 24 rows `VERIFIED` |
| 6 | Commercial `JobOrderDraftInput` version/fixtures/idempotency verified and compatible | ✔ | `docs/build-log/phase-02/JOB_ORDER_HANDOFF_CONTRACT.md` (`schemaVersion=1`); `server/contracts/job-order-lineage/job-order-lineage.ts`; idempotency key `(tenant_id, quotation_id, purpose)` proven in `commercial-job-order-lineage.sql` |
| 7 | Operations WBS/traceability, branch/worktree ownership, exact paths, environment, baselines and downstream Finance/advanced-domain boundaries current | ✔ — established by this document plus `OPERATIONS_EXECUTION_INDEX.md` |

**Result: entry gate PASS.** `PHASE_3_BLOCKED` is not warranted.

## 3. `JobOrderDraftInput` field → Job Order lineage map (`167_*.md` required task 4)

Every customer/contact/address/cargo/service/rate/quote/price/credit field the Commercial handoff carries is mapped to a Job Order column/reference, never re-typed:

| `JobOrderDraftInput` field | Job Order lineage |
|---|---|
| `source.quotationId`/`quoteNumber`/`versionNumber`/`opportunityId`/`prospectId`/`accountConversionId` | `app.job_orders.source_handoff_id` → `app.job_order_handoffs` (one row, `unique(tenant_id, handoff_id)`) — never copied as separate columns |
| `customer.accountId`/`customerSnapshot`/`contactId`/`contactName`/`contactEmail`/`contactPhone` | `app.job_orders.customer_snapshot` (jsonb, verbatim copy of the accepted payload — a governed snapshot, not a re-typed value) plus `account_id uuid references app.accounts(id)` (live FK, mirroring `COM-161`'s own `account_id` pattern) |
| `cargoService` | `app.job_orders.cargo_service_snapshot` (jsonb, verbatim) |
| `pricing.*` | `app.job_orders.revenue_snapshot` (jsonb, verbatim — the pinned Commercial revenue basis Phase 4/`OPS-179` profitability will read, never recomputed) |
| `contract`/`credit` | `app.job_orders.contract_snapshot`/`credit_snapshot` (jsonb, nullable, verbatim) |
| `acceptance.*` | `app.job_orders.acceptance_snapshot` (jsonb, verbatim) |

No field is silently retyped into a free-text column; every value either lives inside one of these verbatim jsonb snapshots or references a canonical id already established by Commercial (`account_id`).

## 4. Capability catalogue and dependency order (reproduced by reference, `166_*.md` §4)

| Order | ID | Capability | Status this checkpoint |
|---:|---|---|---|
| 0 | `OPS-167` | WBS/runtime kickoff | `VERIFIED` (this checkpoint) |
| 1 | `OPS-168` | Job Order | `READY` |
| 2 | `OPS-169` | Shipment Order | `BLOCKED` (behind `168`) |
| 3 | `OPS-170` | Shipment lifecycle | `BLOCKED` |
| 4 | `OPS-171` | Land, air and sea baseline | `BLOCKED` |
| 5 | `OPS-172` | Resource/vendor assignment | `BLOCKED` |
| 6 | `OPS-173` | Milestone management | `BLOCKED` |
| 7 | `OPS-174` | Exception and escalation | `BLOCKED` |
| 8 | `OPS-175` | Basic dispatch | `BLOCKED` |
| 9–21 | `OPS-176`–`188` | Document requirement, ePOD, actual cost, profitability, public tracking, billing readiness, dashboard, reports, transaction lineage, integrated verification, hardening, documentation, closure | `BLOCKED` — out of this session's authorized range ("lanjut sd prompt 175") |

This session's authorized range is `OPS-167` through `OPS-175` (the user's explicit "lanjut sd prompt 175"). `OPS-176` onward remain `BLOCKED`/`NOT_STARTED`, dependency-correct but not authorized this session.

## 5. Workstream / Epic grouping (reconciled against each capability prompt's own §3 "Workstream" line)

| Workstream | Epic(s) | Capability prompts |
|---|---|---|
| Order Execution | Accepted Demand Conversion, Shipment Definition | `168`, `169` |
| Shipment Execution | Canonical Shipment State, Mode Baseline, Execution Responsibility | `170`, `171`, `172` |
| Control Tower | Shipment Visibility, Operational Exception | `173`, `174` |
| Dispatch | Shipment Release | `175` |

## 6. Phase 3/5/8/4 boundaries encoded (`167_*.md` required tasks 5/6)

- **Phase 3/5 (advanced TMS/WMS)**: single-mode/single-leg land/air/sea only (`171`); simple list-based assignment/dispatch, no board/route/load/capacity optimization or GPS/telematics (`172`/`175`); full WMS (`OPS-WMS-001..004`) is entirely out of scope — no warehouse table/route exists anywhere in this checkpoint.
- **Phase 3/8 (Customer Portal)**: no public/customer tracking surface is built by `168`–`175` (that is `OPS-180`, out of this session's range); nothing in this range exposes a customer-facing route.
- **Phase 3/4 (Finance)**: no vendor bill, AP, GL journal, tax posting, invoice, or settlement anywhere in `168`–`175`; `app.job_orders.revenue_snapshot`/future `actual_cost` (`OPS-178`, out of range) are the exact, disclosed forward-compatible seams Phase 4 will read, not built here.

## 7. Atomic sizing

Every one of `168`–`175` targets 1 migration, 5–15 changed files, matching the verified repository boundary every Commercial capability already used.

## 8. Safe concurrency lanes

Single session, single branch (`claude/lanjut-kv0mze`), sequential execution `168`→`169`→`170`→`171`→`172`→`173`→`174`→`175` per the dependency table above — no parallel lane is opened, matching this session's own established one-agent-one-branch discipline.

## 9. Completion statement

This document plus `OPERATIONS_EXECUTION_INDEX.md` satisfy `167_*.md`'s required output. `OPS-168` (Job Order) is the next eligible prompt.
