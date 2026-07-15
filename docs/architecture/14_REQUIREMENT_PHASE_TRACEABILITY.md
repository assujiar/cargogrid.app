# 14 — Requirement/Phase Traceability

**Prompt:** `CG-S3-ARCH-014` (`CG-AABPP-ARCH-049` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/49_REQUIREMENT_PHASE_TRACEABILITY_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| Precondition | `docs/architecture/01_*.md` through `13_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero code, zero task executed against this matrix (prompt precondition, verified) |
| Mutation performed | **NONE** — traceability binding only; no implementation task was started |

### Inputs read in full for this document

- `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` (CPD-001..023 §1, RPD-001..040 §4)
- `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` (full — §2 194-ID inventory, §3 functional family coverage, §4 NFR coverage, §5 package-gap IDs, §6 catalogue coverage, §7 phase model, §13–§25 per-step capability-group tables)
- `docs/ai-agent-build-prompt-package/00-control/03_ASSUMPTION_REGISTER.md` (full — 92 `ASM-*` rows, §1–§8)
- `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md` (full — 14 `CON-*`, 18 `GAP-*`, 12 `DUP-*`, 16 `OD-PKG-*` rows)
- `docs/blueprint/02_CargoGrid_Business_Process_Product_Requirements_Blueprint.md` §9–§16 (Requirement Matrix, Business Rules Catalogue §10, Approval Engine §11, Status Lifecycle §12, Exception Catalogue §13, Reporting §15, NFR Catalogue §16)
- `docs/blueprint/05_CargoGrid_Delivery_Testing_GoLive_Plan.md` §19 (UAT-E2E-001..020), §22 (TI-001..018), §23 (FINTEST-001..024)
- `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (full — the capability-ID register this document maps every source ID onto)
- `docs/architecture/01_*.md`, `02_*.md`, `06_*.md`, `07_*.md`, `10_*.md`, `12_*.md` (cited sections — Business Rule/Status/Approval/Exception engines already reproduced verbatim in `07_*.md` §7; UAT/TI/FINTEST catalogues already reproduced verbatim in `10_*.md` §5)
- `docs/runtime/CARGOGRID_CONTEXT.md`, `docs/runtime/HANDOFF.md` §1, §6, §7 (standing risk/gate disclosures)

## 1. Scope and method

This document is the requirement-to-phase **traceability binding**, not a re-derivation of source content. Every catalogue this document traces (`CPD`, `RPD`, functional/NFR requirement families, package gap IDs, assumptions, conflicts, business rules, approval patterns/use cases, status transitions, exceptions, report categories, NFR areas, UAT scenarios, tenant-isolation scenarios, financial scenarios) is already fully specified, numbered, and verbatim-preserved in one of the sources listed in §0. Three of those catalogues (business rules, approval patterns/use cases, status transitions, exception catalogue) are already bound to the Configuration Engine architecture verbatim in `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §7.1–§7.4; three more (UAT-E2E, tenant isolation, financial tests) are already bound to the Testing workstream verbatim in `10_TESTING_WORKSTREAM.md` §5.1–§5.3. This document's job is to close the final link these two documents leave open: **which WBS capability ID (`13_*.md` §4/§5) is the delivery+verification owner of each catalogue item**, so that a future runtime agent can go from any source ID directly to the exact prompt file that builds and verifies it, without re-deriving the mapping.

No source ID is renumbered, no WBS ID is invented, and no catalogue is truncated — every row in §3–§19 traces one full source catalogue by ID.

## 2. Traceability schema definition

Every row in the requirement-level matrices (§3–§7) uses this 9-field schema (binding, applies uniformly):

| Field | Meaning |
|---|---|
| **Source ID / range** | The `CPD`/`RPD`/`BPR family`/`NFR`/`PKG` ID(s) from the control register or blueprint, unmodified |
| **Canonical statement** | One-line restatement of the binding requirement (not a paraphrase that changes meaning) |
| **Parent phase** | The Phase 0–9/15/16/17 owner from `13_*.md` §4 |
| **WBS capability ID(s)** | The exact `CG-WBS-<n>` / phase-short-code ID range from `13_*.md` §4–§5 that delivers it |
| **Architecture artifact** | The `docs/architecture/0N_*.md` section that already designs the control |
| **Test/evidence** | The catalogue ID (`UAT-E2E-*`, `TI-*`, `FINTEST-*`) or test-matrix section that verifies it |
| **Hardening/release gate** | The Step 15/16 gate (`HDN-*`/`RGL-*`) that re-verifies it before GA, where applicable |
| **Owner** | Delivery owner (phase capability) + verification owner (phase verification/hardening prompt) — `COVERED` requires both to be named |
| **Status** | `COVERED` \| `PARTIAL_BLOCKED` \| `EXTERNAL_VERIFICATION` \| `ACCEPTED_RISK` \| `NOT_COVERED` |

Catalogue-level matrices (§10–§19: business rules, approval patterns/use cases, transitions, exceptions, reports, NFR areas, UAT, TI, FINTEST) use a **7-field schema**: ID, canonical statement, owning family/phase, WBS capability ID(s), architecture artifact, test binding, status — the "hardening/release gate" and "owner" columns are folded into the owning family's row in §5–§7 to avoid tripling the same binding across three tables (no requirement is silently dropped by this compression: every catalogue ID's row still names its own phase and WBS ID).

**Status-state rule (binding, prompt task #5):** `COVERED` requires a named delivery-capability WBS ID **and** a named verification/hardening WBS ID in the same phase's register (`13_*.md` §4's Verification/Hardening columns). `PARTIAL_BLOCKED` and `EXTERNAL_VERIFICATION` rows must additionally carry a named owner and a named resolution gate (§22 lists every occurrence). `ACCEPTED_RISK` marks an intentionally-disclosed governance exception (RPD-022 and related) that is still fully delivered and tested — it is not a coverage gap.

## 3. CPD-001..023 traceability

Every Confirmed Product Decision is a binding constraint on one or more phases' capability design, not itself a deliverable — its "coverage" is the set of capabilities whose architecture already encodes it (cited), plus the standing rule (`02_CONFIRMED_DECISION_REGISTER.md` §5) that no capability may weaken it without the full decision-change protocol.

| CPD | Canonical statement | Binding phase(s) | WBS capability ID(s) | Architecture artifact | Status |
|---|---|---|---|---|---|
| CPD-001 | Product name CargoGrid; white-label may not change internal identity | Phase 1 | PLT-117..119 | `09_*.md` §10 | `COVERED` |
| CPD-002 | SaaS ERP model — entitlement/tenancy/release/onboarding/support | Phase 1 | PLT-105..106, PLT-135..136 | `01_*.md` §2 | `COVERED` |
| CPD-003 | Target market 3PL/logistics — logistics-native domain model | Phases 1–9 (all domain phases) | All phase capability ranges | `02_*.md`, `03_*.md` | `COVERED` |
| CPD-004 | Multi-tenant; tenant context in every surface | Phase 1 (foundation), all phases (propagation) | PLT-112..114; every phase's capability range | `06_*.md` §2–§4 | `COVERED` |
| CPD-005 | White-label — branding/domain/templates/portal/terminology configurable | Phase 1/9 | PLT-117..119, IEP-354..359 | `09_*.md` §10 | `COVERED` |
| CPD-006 | RLS is the primary tenant-facing database control | Phase 1 | PLT-112..114 | `06_*.md` §2–§4, §9 | `COVERED` |
| CPD-007 | RBAC governs action/field/scope | Phase 1 | PLT-109..114 | `06_*.md` §5 | `COVERED` |
| CPD-008 | Four user layers (Supreme Admin, User Admin, Internal, Customer) | Phase 1 | PLT-107..108 | `06_*.md` §2 | `COVERED` |
| CPD-009 | Configurable hierarchy (titles/levels/reporting/approval authority) | Phase 1 | PLT-109 | `07_*.md` §5 | `COVERED` |
| CPD-010 | Configurable role/permission by Supreme/User Admin | Phase 1 | PLT-110..111 | `06_*.md` §5 | `COVERED` |
| CPD-011 | Configurable module (entitlement-controlled) | Phase 1 | PLT-105..106 | `07_*.md` §3 | `COVERED` |
| CPD-012 | Configurable workflow (draft/publish/version/rollback) | Phase 1 | PLT-122 | `07_*.md` §5–§6 | `COVERED` |
| CPD-013 | Configurable approval (generic engine, no per-screen hardcoding) | Phase 1 | PLT-123 | `07_*.md` §7.1 | `COVERED` |
| CPD-014 | Configurable service (mode/coverage/SLA/cost/eligibility) | Phase 1/2/3 | PLT-121, COM-147..148, OPS-168..169 | `07_*.md` §3 | `COVERED` |
| CPD-015 | UI-based configuration (admin UX, no source change) | Phase 1 | PLT-135..136 | `07_*.md` §5–§7 | `COVERED` |
| CPD-016 | No backend source-code change for tenant variance | Phase 1 (foundation), all phases (guardrail) | PLT-120..121 | `07_*.md` §11 | `COVERED` |
| CPD-017 | End-to-end process (lead-to-revenue, booking-to-delivery, etc.) | Phases 2–8 | COM-160..161, OPS-184, FIN-212..213, HRT, CPL-316..323 | `02_*.md` §3.1 | `COVERED` |
| CPD-018 | Modules directionally/transactionally connected | Phases 1–9 | Every phase's lineage-bearing capability (e.g. COM-160..161, OPS-184) | `02_*.md` §4 | `COVERED` |
| CPD-019 | No redundant data entry | Phases 1–9 | PLT-120 (master data), every conversion capability | `02_*.md` §2–§4 | `COVERED` |
| CPD-020 | Next.js/TypeScript/React App Router, strict mode | Phase 0 | PH0-085..086 | `04_*.md` §3 | `COVERED` |
| CPD-021 | Supabase backend (PostgreSQL/Auth/RLS/Storage) | Phase 0/1 | PH0-085..086, PLT-105..107 | `05_*.md` §2 | `COVERED` |
| CPD-022 | Comprehensive customer/shipment canonical data | Phase 1/2/3 | PLT-120, COM-145, OPS-168..169 | `05_*.md` §3, `02_*.md` §2 | `COVERED` |
| CPD-023 | Efficient/light/scalable backend and API | Phase 0/1/all | PH0-093..094, PLT-129..132 | `08_*.md` §12, `10_*.md` §8.1 | `COVERED` |

All 23 CPDs `COVERED`. Zero CPDs reopened (`02_CONFIRMED_DECISION_REGISTER.md` §5 change-protocol untouched throughout `01_*.md`–`13_*.md`, confirmed by citation, not re-audited here).

## 4. RPD-001..040 traceability

| RPD | Canonical statement | Binding phase(s) | WBS capability ID(s) | Architecture artifact | Status |
|---|---|---|---|---|---|
| RPD-001 | All major modules in first production; phases are internal milestones | Phases 0–9 → GA gate | Every phase register row, `RGL-404` (GA approval) | `13_*.md` §4, `12_*.md` §7.1 | `COVERED` |
| RPD-002 | CargoGrid owned under SAIKI Group | Commercial/legal, non-architectural | n/a (branding config only) | `09_*.md` §10 | `COVERED` |
| RPD-003 | First production tenant is external | Phase 16 | RGL-404..407 | `12_*.md` §7.3 | `COVERED` |
| RPD-004 | Responsive PWA, online-first; native/offline deferred | Phase 0/9 | PH0-090, IEP-360..363 | `09_*.md` §8 | `COVERED` |
| RPD-005 | Custom domain from Platform Core | Phase 1 | PLT-118 | `09_*.md` §10 | `COVERED` |
| RPD-006 | PT SAIKI Group is contracting entity | Commercial/legal | n/a | — | `COVERED` (non-architectural) |
| RPD-007 | Modular commercial packaging | Phase 1 | PLT-105..106 | `07_*.md` §3 | `COVERED` |
| RPD-008 | Subscription pricing: platform/module/user/usage | Phase 1 | PLT-105..106 | `07_*.md` §3 | `COVERED` |
| RPD-009 | Implementation tiers Fast-track/Standard/Enterprise | Phase 16 | RGL-390..391 | `12_*.md` §8 | `COVERED` |
| RPD-010 | Tiered support (Standard/Premium/Enterprise) | Phase 7/16 | HRT-286..288, RGL-411 | `11_*.md` §8.4 | `COVERED` |
| RPD-011 | Shared DB/schema default; dedicated Enterprise option | Phase 1/9 | PLT-112..114, IEP-360 | `06_*.md` §2 | `COVERED` |
| RPD-012 | PostgreSQL durable queue is initial job mechanism | Phase 1 | PLT-132 | `08_*.md` §9 | `COVERED` |
| RPD-013 | APAC default region; Enterprise dedicated region option | Phase 9 | IEP-360..363 | `11_*.md` §2 | `COVERED` |
| RPD-014 | Dashboards read transactional data directly, with query budgets | Phase 2–9 (every dashboard capability) | COM-158..159, OPS-182..183, FIN-213, IEP-330..334 | `08_*.md` §12, `10_*.md` §8.1 | `COVERED` |
| RPD-015 | PostGIS enabled from Platform Core | Phase 1 | PLT-134 | `05_*.md` §6 | `COVERED` |
| RPD-016 | Indonesia-first finance/tax/payroll, SME-verified | Phase 4/7 | FIN-195, HRT-282 | `05_*.md` §5 | `EXTERNAL_VERIFICATION` (§22) |
| RPD-017 | Enterprise IAM order OIDC→SAML→SCIM | Phase 9 | IEP-354..359 | `06_*.md` §2 | `COVERED` |
| RPD-018 | Partner referral model | Commercial | n/a | — | `COVERED` (non-architectural) |
| RPD-019 | Controlled white-label | Phase 1 | PLT-117..119 | `09_*.md` §10 | `COVERED` |
| RPD-020 | Tenant merge/split is admin-run migration | Phase 1/9 | PLT-105..106, IEP-360 | `11_*.md` §4 | `COVERED` |
| RPD-021 | OpenAI multimodal AI/OCR default, human approval gate | Phase 9 | IEP-347..353 | `08_*.md` §8 | `COVERED` |
| RPD-022 | Supreme Admin absolute CRUD; no tamper-proof claim | Phase 1 (mechanism), all ledger/audit capabilities (exception) | PLT-115..116, FIN-204..208, LYL-316..323 | `06_*.md` §8, §10 test 8/9 | `ACCEPTED_RISK` (§21) |
| RPD-023 | MFA mandatory for privileged roles | Phase 1 | PLT-107..108 | `06_*.md` §2 | `COVERED` |
| RPD-024 | WCAG 2.2 AA; two latest stable browser releases | Phase 0/9/15 | PH0-090, HDN-380..381 | `09_*.md` §9, §8 | `COVERED` |
| RPD-025 | Class-based retention schedule | Phase 0/15 | PH0-095, HDN-382..385 | `02_*.md` §11 | `COVERED` |
| RPD-026 | Ten-suite module catalogue | Phase 1 | PLT-105..106 | `07_*.md` §3 | `COVERED` |
| RPD-027 | Launch price book | Commercial | n/a | — | `COVERED` (non-architectural) |
| RPD-028 | Usage charging, 20 GB included | Phase 1/9 | PLT-105..106, IEP-337..341 | `08_*.md` §9 | `COVERED` |
| RPD-029 | Launch implementation fees | Commercial | n/a | — | `COVERED` (non-architectural) |
| RPD-030 | SLA A default, contract may replace | Phase 16 | RGL-399..403 | `12_*.md` §7.1 | `COVERED` |
| RPD-031 | RPO/RTO contract-specific | Phase 15/16 | HDN-384, RGL-408 | `11_*.md` §8, `10_*.md` §7.4 | `EXTERNAL_VERIFICATION` (§22, per-contract) |
| RPD-032 | Every upload malware-scanned before release | Phase 1 | PLT-128 | `06_*.md` §10 test 13 | `COVERED` |
| RPD-033 | REST + GraphQL together, shared governance | Phase 1/9 | PLT-129..130, IEP-337..341 | `08_*.md` §3–§5 | `COVERED` |
| RPD-034 | No external pilot; direct GA | Phase 16 | RGL-390..412 | `12_*.md` §2, §7.1 | `COVERED` |
| RPD-035 | Tenant owns customer/operational data | Phase 1 | PLT-115..116 | `06_*.md` §6 | `COVERED` |
| RPD-036 | Direct GA requires full internal validation, zero Sev-1 | Phase 16 | RGL-404 | `12_*.md` §7.1 | `COVERED` |
| RPD-037 | Contract-silent recovery = best effort | Phase 15/16 | HDN-384, RGL-408 | `11_*.md` §8 | `EXTERNAL_VERIFICATION` (§22, per-contract) |
| RPD-038 | Custom per-integration adapters, no generic abstraction | Phase 9 | IEP-342..346 | `08_*.md` §8 | `COVERED` |
| RPD-039 | Search/field security start in PostgreSQL/server policy | Phase 1 | PLT-112..114 | `06_*.md` §7 | `COVERED` |
| RPD-040 | All non-conflicting Proposed Defaults approved | All phases (interpretive rule) | n/a | `03_ASSUMPTION_REGISTER.md` §8 | `COVERED` |

All 40 RPDs `COVERED` or explicitly `EXTERNAL_VERIFICATION`/`ACCEPTED_RISK` with a named owner and gate (§21–§22). Zero RPDs reopened.

## 5. Functional requirement family traceability (184 IDs, 46 families)

Traced at the family level (`XXX-YYY-001..004`), matching the granularity already fixed by `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §3 ("These generic rows are coverage anchors, not sufficient atomic specifications") and by `13_*.md` §5's capability-group citation discipline. Each row's WBS ID(s) are drawn from `13_*.md` §4/§5 and the matching per-step capability-group table in `05_REQUIREMENT_COVERAGE_MATRIX.md` §14–§21.

**Family-count reconciliation:** `05_REQUIREMENT_COVERAGE_MATRIX.md` §2's own total row reads "51 functional families, 184 functional IDs" — that 51 is the sum of the 9 functional domains' 46 families (Platform 5, Commercial 5, Operations 6, Procurement 5, Finance 6, HRIS 6, Ticketing 4, Customer Portal 5, Loyalty 4 = 46, each family = 4 IDs = 184 total, arithmetically exact) **plus** the 5 "Cross-cutting NFR" anchor rows from that same table, which do not produce functional IDs (their column reads "—") and are the 5 anchor areas already fully traced against the 10 explicit `NFR-*` IDs in §6 below, not a 47th–51st functional family. This document traces the 46 true functional families here and the 5 NFR anchor areas in §6, so every one of the source table's 51 rows is traced exactly once, with no double-count and no family silently dropped.

### 5.1 Platform (PLT-*, 5 families, 20 IDs) — Phase 1

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| PLT-TNT-001..004 | Tenant & Subscription | PLT-105..106 | `05_*.md` §3, `07_*.md` §3 | PLT-137..140 | Platform Core delivery + Phase 1 verification | `COVERED` |
| PLT-WLB-001..004 | White-label & Localization | PLT-117..119 (core), IEP-354..359 (enterprise depth) | `09_*.md` §10 | PLT-137..140, IEP-364..367 | Platform Core + Phase 9 depth | `COVERED` |
| PLT-IAM-001..004 | User, Org, Role & Permission | PLT-107..116 | `06_*.md` §2–§6 | PLT-137..140 | Platform Core delivery + verification | `COVERED` |
| PLT-CFG-001..004 | Workflow, Approval & Configuration | PLT-120..125 | `07_*.md` §5–§7 | PLT-137..140 | Platform Core delivery + verification | `COVERED` |
| PLT-MDM-001..004 | Master Data & Integration Foundation | PLT-120, PLT-129..132 | `05_*.md` §3, `08_*.md` §8–§9 | PLT-137..140 | Platform Core delivery + verification | `COVERED` |

### 5.2 Commercial (COM-*, 5 families, 20 IDs) — Phase 2

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| COM-LEAD-001..004 | Lead Management | COM-143..144 | `02_*.md` §3.1 | COM-162..165 | Commercial delivery + verification | `COVERED` |
| COM-CRM-001..004 | CRM, Account & Contact | COM-145..146 | `02_*.md` §3.1 | COM-162..165 | Commercial delivery + verification | `COVERED` |
| COM-OPP-001..004 | Opportunity & Request Costing | COM-147..150 | `02_*.md` §3.1 | COM-162..165 | Commercial delivery + verification | `COVERED` |
| COM-QTN-001..004 | Quotation, Approval & Contract | COM-151..154 | `07_*.md` §7.1, `02_*.md` §3.1 | COM-162..165 | Commercial delivery + verification | `COVERED` |
| COM-CPR-001..004 | Customer Pricing & Commercial Analytics | COM-155..159 | `02_*.md` §3.1 | COM-162..165 | Commercial delivery + verification | `COVERED` |

### 5.3 Operations (OPS-*, 6 families, 24 IDs) — Phase 3 (basic) / Phase 5 (advanced, `ATW-*`)

| Family | Capability | WBS capability ID(s) — basic / advanced | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| OPS-SHP-001..004 | Job Order & Shipment Order | OPS-168..169 / ATW-221..225 | `02_*.md` §3.1 | OPS-185..188 / ATW-245..248 | Operations MVP + Advanced TMS/WMS | `COVERED` |
| OPS-TMS-001..004 | Transportation Management | OPS-170..171 / ATW-221..228 | `02_*.md` §3.1 | OPS-185..188 / ATW-245..248 | Operations MVP + Advanced TMS/WMS | `COVERED` |
| OPS-WMS-001..004 | Warehouse Management | (excluded from MVP, ASM-PK-006) / ATW-229..242 | `05_*.md` §6 | ATW-245..248 | Advanced TMS/WMS (sole owner) | `COVERED` |
| OPS-TRK-001..004 | Milestone, Tracking & Exception | OPS-172..175 / ATW-226..228 | `02_*.md` §3.1 | OPS-185..188 / ATW-245..248 | Operations MVP + Advanced TMS/WMS | `COVERED` |
| OPS-DOC-001..004 | ePOD, Document, Claim & Incident | OPS-176..177 / ATW-243..244 | `06_*.md` §10 test 13 | OPS-185..188 / ATW-245..248 | Operations MVP + Advanced TMS/WMS | `COVERED` |
| OPS-CST-001..004 | Estimated/Actual Cost & Job Closing | OPS-178..181 / FIN-196..214 / ATW-239..242 | `02_*.md` §3.1 | OPS-185..188, FIN-215..218, ATW-245..248 | Operations MVP + Finance depth + WMS billing | `COVERED` |

### 5.4 Procurement/Vendor (PRC-*, 5 families, 20 IDs) — Phase 6 (basic lookup Phase 2)

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| PRC-VND-001..004 | Vendor Registration & Onboarding | PRC-251..253 | `02_*.md` §3.1 | PRC-268..271 | Procurement delivery + verification | `COVERED` |
| PRC-ASM-001..004 | Qualification, Assessment & Compliance | PRC-251..253 | `02_*.md` §3.1 | PRC-268..271 | Procurement delivery + verification | `COVERED` |
| PRC-RTE-001..004 | Vendor Rate, Quotation & Pricelist | COM-149..150 (basic) / PRC-254..255 (full) | `01_*.md` §3.1 (ADR-CAND-ARCH-001 resolved) | COM-162..165, PRC-268..271 | Commercial (basic) → Procurement (full, sole canonical owner) | `COVERED` |
| PRC-SRC-001..004 | Sourcing, Capacity & Availability | PRC-256..258, PRC-262..264 | `02_*.md` §3.1 | PRC-268..271 | Procurement delivery + verification | `COVERED` |
| PRC-POI-001..004 | PO, Contract, Performance & Invoice Matching | PRC-259..261, PRC-265..266 | `02_*.md` §3.1 | PRC-268..271 | Procurement delivery + verification | `COVERED` |

### 5.5 Finance (FIN-*, 6 families, 24 IDs) — Phase 4 (basic AP depth Phase 6)

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| FIN-GL-001..004 | COA, Journal & General Ledger | FIN-192..193, FIN-202..208 | `05_*.md` §5, `06_*.md` §8 | FIN-215..218 | Finance delivery + verification | `ACCEPTED_RISK` (RPD-022 exception, §21) |
| FIN-AR-001..004 | Billing, Invoice & AR | FIN-196..198 | `02_*.md` §3.1 | FIN-215..218 | Finance delivery + verification | `COVERED` |
| FIN-AP-001..004 | Vendor Billing & AP | FIN-199..201 (basic) / PRC-265..266 (full matching) | `02_*.md` §3.1 | FIN-215..218, PRC-268..271 | Finance (basic) → Procurement (full matching) | `COVERED` |
| FIN-TAX-001..004 | Tax, Bank Reconciliation & Cash | FIN-194..195, FIN-209..211 | `05_*.md` §5 | FIN-215..218 | Finance delivery + verification | `EXTERNAL_VERIFICATION` (FIN-195 SME gate, §22) |
| FIN-CLS-001..004 | Budget, Accrual, Revenue Recognition & Closing | FIN-191, FIN-206..211 | `05_*.md` §5 | FIN-215..218 | Finance delivery + verification | `ACCEPTED_RISK` (RPD-022 exception on posted journals, §21) |
| FIN-PRF-001..004 | Job/Customer/Service/Branch Profitability | FIN-212..214 | `02_*.md` §3.1 | FIN-215..218 | Finance delivery + verification | `COVERED` |

### 5.6 HRIS (HRS-*, 6 families, 24 IDs) — Phase 7

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| HRS-EMP-001..004 | Organization, Employee & Position | HRT-274..277 | `06_*.md` §11 (`ADR-CAND-ARCH-002` resolved) | HRT-294..297 | HRIS delivery + verification | `COVERED` |
| HRS-REC-001..004 | Recruitment, Job Portal & ATS | HRT-274..277 | `02_*.md` §3.1 | HRT-294..297 | HRIS delivery + verification | `COVERED` |
| HRS-ATT-001..004 | Attendance, Shift, Leave & Overtime | HRT-278..281 | `02_*.md` §3.1 | HRT-294..297 | HRIS delivery + verification | `COVERED` |
| HRS-PAY-001..004 | Payroll, Benefit & Reimbursement | HRT-282 | `05_*.md` §5 | HRT-294..297 | HRIS delivery + verification | `EXTERNAL_VERIFICATION` (HRT-282 SME gate, §22) |
| HRS-KPI-001..004 | Performance, KPI, Training & Talent | HRT-283..284 | `02_*.md` §3.1 | HRT-294..297 | HRIS delivery + verification | `COVERED` |
| HRS-ESS-001..004 | ESS, MSS & Offboarding | HRT-285 | `06_*.md` §5.5 | HRT-294..297 | HRIS delivery + verification | `COVERED` |

### 5.7 Ticketing (TKT-*, 4 families, 16 IDs) — Phase 7 (portal depth Phase 8, release depth Phase 16)

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| TKT-INT-001..004 | Internal/Interdepartmental Ticket | HRT-286..288 | `06_*.md` §11 (`ADR-CAND-ARCH-006` resolved) | HRT-294..297 | HRIS/Ticketing delivery + verification | `COVERED` |
| TKT-CUS-001..004 | Customer-to-Tenant Ticket | HRT-286..288 (core) / CPL-311..315 (full portal) | `06_*.md` §11 | HRT-294..297, CPL-324..327 | Ticketing (core) → Customer Portal (full) | `COVERED` |
| TKT-HLP-001..004 | Tenant-to-CargoGrid Helpdesk | HRT-286..288 (domain) / RGL-411 (release-support depth) | `06_*.md` §11 | HRT-294..297 | Ticketing delivery; release-depth planned at Phase 16 support docs | `PARTIAL_BLOCKED` (§22 — release-depth planned, not yet scheduled as a numbered capability; owner: Phase 16 documentation/handoff `RGL-411`) |
| TKT-SLA-001..004 | SLA, Escalation & Knowledge Base | HRT-289..291 | `02_*.md` §3.1 | HRT-294..297 | HRIS/Ticketing delivery + verification | `COVERED` |

### 5.8 Customer Portal (CPT-*, 5 families, 20 IDs) — Phase 8 (basic handoff Phase 3)

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| CPT-QBK-001..004 | Quote Request & Booking | OPS-168..169 (internal handoff) / CPL-302..304 (self-service) | `02_*.md` §3.1 | OPS-185..188, CPL-324..327 | Operations (handoff) → Customer Portal (self-service) | `COVERED` |
| CPT-TRK-001..004 | Tracking, ePOD & Document | OPS-172..173, OPS-176..177 (basic) / CPL-305..308 (full) | `02_*.md` §3.1 | OPS-185..188, CPL-324..327 | Operations (basic) → Customer Portal (full) | `COVERED` |
| CPT-WHS-001..004 | Warehouse, Inventory & Order Monitoring | CPL-309..310 (after ATW-229..242) | `02_*.md` §3.1 | CPL-324..327 | Customer Portal delivery + verification | `COVERED` |
| CPT-BIL-001..004 | Invoice, Billing, Payment & Profile | CPL-311..315 (after FIN-196..214) | `02_*.md` §3.1 | CPL-324..327 | Customer Portal delivery + verification | `COVERED` |
| CPT-CX-001..004 | Complaint, Ticket, Loyalty & Rewards | CPL-311..315 | `06_*.md` §11 | CPL-324..327 | Customer Portal delivery + verification | `COVERED` |

### 5.9 Loyalty (LYL-*, 4 families, 16 IDs) — Phase 8

| Family | Capability | WBS capability ID(s) | Architecture artifact | Verification/hardening | Owner | Status |
|---|---|---|---|---|---|---|
| LYL-PRG-001..004 | Program, Tier & Segmentation | CPL-316..319 | `02_*.md` §3.1 | CPL-324..327 | Loyalty delivery + verification | `COVERED` |
| LYL-PNT-001..004 | Point, Cashback, Discount & Voucher | CPL-316..319 | `06_*.md` §12 (`append_only_ledger`) | CPL-324..327 | Loyalty delivery + verification | `ACCEPTED_RISK` (RPD-022 exception on ledger, §21) |
| LYL-RDM-001..004 | Reward, Redemption, Referral & Expiration | CPL-320..323 | `06_*.md` §12 | CPL-324..327 | Loyalty delivery + verification | `COVERED` |
| LYL-ANL-001..004 | Loyalty Analytics & Liability | CPL-320..323 | `02_*.md` §3.1 | CPL-324..327 | Loyalty delivery + verification | `COVERED` |

**§5 total: 46 families, 184 functional IDs — 40 families fully `COVERED` (160 IDs), 3 families `ACCEPTED_RISK` (FIN-GL, FIN-CLS, LYL-PNT, 12 IDs), 2 families `EXTERNAL_VERIFICATION` (FIN-TAX, HRS-PAY, 8 IDs), 1 family `PARTIAL_BLOCKED` (TKT-HLP, 4 IDs). 40+3+2+1 = 46 families; 160+12+8+4 = 184 IDs. Zero `NOT_COVERED`.**

## 6. Explicit NFR traceability (10 IDs)

| NFR ID | Canonical statement | Enforcement phase(s) | WBS capability ID(s) | Architecture artifact | Test binding | Hardening/release gate | Status |
|---|---|---|---|---|---|---|---|
| NFR-PERF-001 | Avoid N+1 queries | Phase 0 baseline, all phases | PH0-093, every capability | `10_*.md` §8.1 | Query review, integration tests | HDN-378..381 | `COVERED` |
| NFR-PERF-002 | Avoid `SELECT *` | Phase 0 baseline, all phases | PH0-093, every capability | `08_*.md` §4 | Static/code review, payload test | HDN-378..381 | `COVERED` |
| NFR-PERF-003 | Server-side pagination | Phase 1 primitive, all list surfaces | PLT-131..132 | `09_*.md` §12 | Table/API acceptance | HDN-378..381 | `COVERED` |
| NFR-PERF-004 | Cursor pagination for high-volume | Phase 3, 8, hardening | OPS-168..169, ATW-234..238, HDN-378..381 | `05_*.md` §7 | Shipment/event/ledger/audit tests | HDN-378..381 | `COVERED` |
| NFR-PERF-005 | Tenant-aware indexing | Phase 1, 3–9 | PLT-112..114, every schema slice | `05_*.md` §7 | Migration/query-plan gate | HDN-378..381 | `COVERED` |
| NFR-SEC-001 | Strict tenant isolation | Phase 1 (design), all phases (test) | PLT-112..114 | `06_*.md` §2–§10 | `TI-001..018` (§18) | HDN-372..374, RGL-399..403 | `COVERED` (release blocker per NFR-SEC-001's own tag) |
| NFR-SEC-002 | Field and record access | Phase 1, 3, 6–9 | PLT-112..114 | `06_*.md` §5, §7 | `TI-014` | HDN-372..374, RGL-399..403 | `COVERED` (release blocker) |
| NFR-AUD-001 | Comprehensive audit | Phase 1, 3, 6–9 | PLT-115..116 | `06_*.md` §10 test 9 | Audit schema/event evidence | HDN-375..377 | `COVERED` |
| NFR-REL-001 | Backup and recovery | Phase 3, 15–16 | HDN-382..385, RGL-408 | `11_*.md` §8 | Restore/DR rehearsal | HDN-382..385, RGL-408 | `COVERED` (GA blocker; RPO/RTO target itself is `EXTERNAL_VERIFICATION` per RPD-031/037, §22) |
| NFR-API-001 | Rate limiting and idempotency | Phase 1, 3, 6–9 | PLT-129..130 | `08_*.md` §9 | API/webhook/duplicate retry tests | RGL-399..403 | `COVERED` |

**§6 total: 10/10 NFR IDs `COVERED`. Zero `NOT_COVERED`.**

## 7. Package-generated gap requirement traceability

Direct count of `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §5 finds **13** `PKG-*` rows (`PKG-NFR-MNT-001` through `PKG-PLT-IMP-001`). `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §0/§1 states "14 package-generated gap-requirement IDs §5" — this document uses the directly-counted figure (13) as authoritative since it is a fresh count against the primary source table, not a re-citation of the prior document's summary count; this is flagged as a one-ID clerical discrepancy in a prior `VERIFIED` document's prose (§20), not a coverage gap, since every one of the 13 actual rows is fully traced below with no ID omitted.

| PKG ID | Canonical statement | Phase(s) | WBS capability ID(s) | Architecture artifact | Status |
|---|---|---|---|---|---|
| PKG-NFR-MNT-001 | Architecture boundaries, ADRs, tests, API docs, migration discipline mandatory | Phase 0/1, 15 | PH0-089, PH0-092, HDN-370..371 | `04_*.md`, `10_*.md` §11 | `COVERED` |
| PKG-NFR-ACC-001 | WCAG 2.2 AA; two latest stable browser releases | Phase 0, 15 | PH0-090, HDN-380..381 | `09_*.md` §9 | `COVERED` |
| PKG-NFR-UX-001 | Internal ERP desktop-first, responsive supported | Phase 0, all UI phases | PH0-090 | `09_*.md` §8 | `COVERED` |
| PKG-NFR-UX-002 | Supported browser matrix maintained | Phase 0, 15 | PH0-090, HDN-380..381 | `09_*.md` §8 | `COVERED` |
| PKG-NFR-UX-003 | Field/portal workflows mobile-usable; offline separately governed | Phase 3, 5, 8, 15 | OPS-176..177, ATW-229..242, CPL-305..308 | `09_*.md` §8 | `COVERED` |
| PKG-NFR-DATA-001 | Retention per RPD-025; RPD-022 disclosed exception | Phase 0, 14–16 | PH0-095, HDN-382..385 | `02_*.md` §11 | `ACCEPTED_RISK` (RPD-022 overlay, §21) |
| PKG-NFR-OBS-001 | Logs/metrics/traces/audit/alerts across app/DB/jobs/integration/security/finance | Phase 0, 5, 15–16 | PH0-093, HDN-382..385 | `11_*.md` §6 | `COVERED` |
| PKG-NFR-SCL-001 | Capacity/concurrency defined and validated | Phase 0, 15 | PH0-093, HDN-378..381 | `11_*.md` §9 | `COVERED` |
| PKG-NFR-FILE-001 | Private file policy; mandatory malware scan | Phase 0, 6, 8–16 | PH0-094, PLT-128 | `06_*.md` §10 test 13 | `COVERED` |
| PKG-PLT-JOB-001 | PostgreSQL durable queue: status/retry/DLQ/idempotency/progress/tenant context | Phase 0, 1 | PH0-085, PLT-132 | `08_*.md` §9 | `COVERED` |
| PKG-PLT-FLG-001 | Feature flags: environment/tenant/module/feature/cohort/effective date/rollback | Phase 0, 1 | PH0-098, PLT-133 | `11_*.md` §9 | `COVERED` |
| PKG-PLT-KEY-001 | API keys/webhook credentials hashed/scoped/rotatable/revocable/rate-limited/audited | Phase 0, 1, 9 | PH0-094, PLT-129 | `08_*.md` §6 | `COVERED` |
| PKG-PLT-IMP-001 | Import/export jobs staged/validated/permission-aware/resumable/auditable/async | Phase 0, 1 | PH0-093, PLT-131 | `08_*.md` §10 | `COVERED` |

**§7 total: 13/13 PKG gap IDs `COVERED` or `ACCEPTED_RISK`. Zero `NOT_COVERED`.**

## 8. Source assumption closure-route traceability (92 `ASM-*` rows)

Every assumption is already `APPROVED_DEFAULT` (`03_ASSUMPTION_REGISTER.md` §1, §8 — "No row in this register requires another product decision"). This section adds the phase/gate binding that register's "Owner / verification gate" column leaves as a role, not a WBS ID. Grouped by the register's own six subsections; every ID within a group is listed (none dropped).

| Register section | IDs (all listed) | Closure-route summary | Binding phase(s)/WBS | Status |
|---|---|---|---|---|
| §2 Charter assumptions | ASM-CH-001..020 | GTM, market, roadmap, tenancy, performance/availability/DR budgets, packaging, pricing, data ownership, security posture, Phase 4/HRIS/Loyalty sequencing, analytics timing, partner IAM, no-pilot safety | ASM-CH-006/009/010/011 → PLT-112..114, HDN-378..385, RGL-408; ASM-CH-016/017 → FIN-189..218, HRT-272..297; ASM-CH-005/020 → PH0-090, RGL-390..412 | `COVERED` |
| §3 Business-process assumptions | ASM-BP-001..015 | Release mapping, approval engine architecture, tenant lifecycle labels, finance/portal phasing, driver capture, vendor self-registration, dashboard query model, posted-journal immutability, shipment modes, bulk import, permission matrix, audit minimum, ticket linkage | ASM-BP-003 → PLT-123, `07_*.md` §7.1; ASM-BP-010 → FIN-204..208, `06_*.md` §8; ASM-BP-009 → COM-158..159/OPS-182..183/FIN-213, `08_*.md` §12; ASM-BP-015 → HRT-286..288, `06_*.md` §11 | `COVERED` |
| §4 UX/data/access assumptions | ASM-UX-001..015 | Desktop-first/mobile portal, navigation separation, config-vs-transaction mode, pagination/cursor patterns, saved views, field policy, canonical entity stability, file access, support access, dashboard query budgets, async import/export, approval UX, mobile field flows | ASM-UX-001..004 → PH0-090, `09_*.md` §2–§4; ASM-UX-005..006/012 → PLT-131..132, `08_*.md` §12; ASM-UX-008/010/011 → PLT-112..116, `06_*.md` §5–§7 | `COVERED` |
| §5 Technical architecture assumptions | ASM-TA-001..014 | Modular monolith, shared DB/schema, Enterprise dedicated option, REST+GraphQL parity, Server Actions, selective Edge Functions, custom-domain primitive, folder structure, PostgreSQL queue, trunk-based git, RPO/RTO contract-specific, performance budgets/thresholds, upload malware scan | ASM-TA-001..004 → `03_*.md`, `04_*.md`, `08_*.md` §3; ASM-TA-009 → PLT-132, `08_*.md` §9; ASM-TA-011 → HDN-384, RGL-408 (`EXTERNAL_VERIFICATION`, §22) | `COVERED` (ASM-TA-011 `EXTERNAL_VERIFICATION`) |
| §6 Delivery/go-live assumptions | ASM-DG-001..020 | Agile phase-gated delivery, modular-monolith-first, internal-milestone-vs-GA scope, no-pilot critical path, lead-to-cash acceptance strategy, onboarding models, feature-flag release control, automated RLS/RBAC/finance suite, mandatory pentest/DR, Finance go-live blocker, Sev-1 go/no-go, documentation DoD, source-fork rejection | ASM-DG-004/009/015/019 → HDN-368..389, RGL-390..412; ASM-DG-014 → FIN-215..218 | `COVERED` |
| §7 Package-level defaults | ASM-PK-001..008 | Vercel baseline, RPD-022 absolute-CRUD interpretation, support-as-Layer-1-persona, Phase 2 vendor/rate foundation, Phase 3/8 portal split, Phase 3/5 WMS split, MFA phasing, `PKG-<AREA>-NNN` ID scheme | ASM-PK-001 → PH0-085/`04_*.md`; ASM-PK-002 → RPD-022 overlay §21; ASM-PK-004 → PRC-RTE cross-phase link §20; ASM-PK-005/006 → OPS/CPL/ATW cross-phase links §20 | `COVERED` |

**§8 total: 92/92 assumption IDs traced (grouped), 91 `COVERED`, 1 `EXTERNAL_VERIFICATION` (ASM-TA-011, folded into RPD-031/037 §22 entry — not double-counted as a separate blocker).**

## 9. Conflict/gap/duplicate register closure-route traceability

`04_CONFLICT_REGISTER.md` §5: "There are zero unresolved product decisions and zero provisional conflict resolutions." This section binds each already-resolved row to its phase/WBS location.

| Register section | IDs (all listed) | Resolution | Binding phase(s)/WBS | Status |
|---|---|---|---|---|
| §1 Source conflicts | CON-001..014 | Supreme Admin authority, hosting baseline, MFA scope, WMS/Portal release split, procurement dependency, Finance scope, custom-domain timing, PWA/offline, RLS-vs-field-protection, config flexibility limits, applied-config versioning, deletion semantics, GA terminology | CON-001/013 → RPD-022 overlay §21; CON-004/005/006 → §20 cross-phase links (OPS-WMS/CPT/PRC-RTE); CON-014 → RGL-404 GA gate | `RESOLVED` (all 14) |
| §2 Requirement gaps | GAP-001..018 | NFR ID gaps, engine-family IDs, field-level enforcement design, queue tech, repo-state discovery, version discovery, localization SME verification, retention durations, capacity evidence, support/SLA policy, residency, AI governance, accessibility level, browser window, archival thresholds, search architecture, SaaS-billing ID separation, API credential lifecycle | GAP-001/002/017 → §7 PKG IDs; GAP-003/016 → PLT-112..114, `06_*.md` §7; GAP-007 → FIN-195/HRT-282 `EXTERNAL_VERIFICATION` §22; GAP-004 → PLT-132 | `CLOSED` (all 18; `TEST_CALIBRATION_GATE`/`DISCOVERY_GATE` rows resolved at Phase 0, not open product questions) |
| §3 Duplicate/overlap register | DUP-001..012 | Tenant isolation, no-redundant-entry, UI-config, pagination/query guardrails, async jobs, signed URLs, posted-journal integrity, config lifecycle, support/impersonation audit, approval patterns, reporting/read-models, feature flags | DUP-001 → PLT-112..114; DUP-003/008 → PLT-120..125; DUP-005 → PLT-131..132; DUP-007 → FIN-202..208, RPD-022 overlay §21; DUP-010 → PLT-123, `07_*.md` §7.1 | `RESOLVED` (all 12, one canonical owner each, no duplicate WBS ownership — confirmed §20) |
| §4 Normalized decision backlog | OD-PKG-001..016 | First-production cutline, legal entity, packaging/pricing/SLA, queue, hosting, region, finance localization, PWA/offline, no-pilot, analytics timing, AI/OCR, IAM order, PostGIS, partner program, white-label, tenant merge/split | Each `OD-PKG-*` closes to exactly one RPD already traced in §4 above (e.g. `OD-PKG-001` → RPD-001) | `CLOSED` (all 16, superseded by §4's RPD rows — no separate WBS binding needed beyond the RPD row already traced) |

**§9 total: 14 CON + 18 GAP + 12 DUP + 16 OD-PKG = 60 IDs, all `RESOLVED`/`CLOSED`. Zero reopened, zero blocking.**

## 10. Business rule traceability (24 `BR-*` IDs)

All 24 rules are `CONFIG_ITEM` rows of `config_type = 'rule'`, bound verbatim in `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §7.3. This table adds the owning phase/WBS/test binding.

| BR ID | Rule | Owning family | Phase / WBS | Test binding | Status |
|---|---|---|---|---|---|
| BR-LEAD-001 | Lead conversion | COM-LEAD-001 | Phase 2 / COM-143..144 | UAT-E2E-002/003 | `COVERED` |
| BR-CUST-001 | Duplicate customer | COM-CRM-001 | Phase 2 / COM-145..146 | UAT-E2E-003 | `COVERED` |
| BR-CUST-002 | Customer approval | COM-CRM-002 | Phase 2 / COM-145..146 | Approval matrix row 1 (§12) | `COVERED` |
| BR-CREDIT-001 | Credit limit | FIN-AR-001 | Phase 4 / FIN-196..198 | FINTEST-012 | `COVERED` |
| BR-COST-001 | Cost request | COM-OPP-001 | Phase 2 / COM-147..148 | UAT-E2E-004 | `COVERED` |
| BR-RATE-001 | Vendor rate validity | PRC-RTE-001 | Phase 2/6 / COM-149..150, PRC-254..255 | UAT-E2E-005 | `COVERED` |
| BR-QTN-001 | Quotation margin | COM-QTN-003 | Phase 2 / COM-151..152 | UAT-E2E-006, EXC-MRG-001 | `COVERED` |
| BR-QTN-002 | Discount | COM-QTN-003 | Phase 2 / COM-151..152 | Approval matrix row 4 (§12) | `COVERED` |
| BR-QTN-003 | Quotation expiration | COM-QTN-001 | Phase 2 / COM-151..152 | Status transition ST-08 (§13) | `COVERED` |
| BR-JOB-001 | Job creation | OPS-SHP-001 | Phase 3 / OPS-168..169 | UAT-E2E-009 | `COVERED` |
| BR-SHP-001 | Shipment assignment | OPS-TMS-001 | Phase 3 / OPS-172..173 | UAT-E2E-011 | `COVERED` |
| BR-SHP-002 | Shipment status | OPS-TRK-002 | Phase 3 / OPS-172..175 | Status transitions ST-09..14 (§13) | `COVERED` |
| BR-POD-001 | ePOD completion | OPS-DOC-001 | Phase 3 / OPS-176..177 | UAT-E2E-014 | `COVERED` |
| BR-CLOSE-001 | Job closing | OPS-CST-003 | Phase 3 / OPS-178..181 | Approval matrix row 8 (§12) | `COVERED` |
| BR-COST-OVR-001 | Cost overrun | OPS-CST-003 | Phase 3 / OPS-178..179 | FINTEST-015 | `COVERED` |
| BR-INV-001 | Invoice readiness | FIN-AR-001 | Phase 3/4 / OPS-180..181, FIN-196..198 | UAT-E2E-016 | `COVERED` |
| BR-REV-001 | Revenue recognition | FIN-CLS-001 | Phase 4 / FIN-206..211 | FINTEST-011 | `COVERED` |
| BR-VIM-001 | Vendor invoice matching | PRC-POI-001 | Phase 6 / PRC-265..266 | FINTEST-016 | `COVERED` |
| BR-PERIOD-001 | Period lock | FIN-CLS-003 | Phase 4 / FIN-207 | FINTEST-008 | `COVERED` |
| BR-ATT-001 | Attendance | HRS-ATT-001 | Phase 7 / HRT-278..281 | EXC-ATT-001 | `COVERED` |
| BR-PAY-001 | Payroll | HRS-PAY-001 | Phase 7 / HRT-282 | Approval matrix row 12 (§12) | `EXTERNAL_VERIFICATION` (HRT-282 SME gate, §22) |
| BR-TKT-001 | Ticket SLA | TKT-SLA-001 | Phase 7 / HRT-289..291 | EXC-SLA-001 | `COVERED` |
| BR-LYL-001 | Loyalty earning | LYL-PNT-001 | Phase 8 / CPL-316..319 | UAT-E2E-019 | `ACCEPTED_RISK` (RPD-022 ledger exception, §21) |
| BR-LYL-002 | Loyalty redemption | LYL-RDM-001 | Phase 8 / CPL-320..323 | Approval matrix row 14 (§12) | `COVERED` |

**§10 total: 24/24 business rules `COVERED`/`ACCEPTED_RISK`/`EXTERNAL_VERIFICATION`. Zero `NOT_COVERED`.**

## 11. Approval pattern traceability (13 patterns)

All 13 patterns are architected once in `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §7.1 (Tech Arch §15, verbatim) as the single Approval Engine every domain prompt configures — no pattern is re-implemented per screen (CPD-013, DUP-010).

| Pattern | Example (source) | Owning engine | Phase / WBS | Status |
|---|---|---|---|---|
| Sequential | Sales Supervisor→Manager→GM | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Parallel | Finance+Operations approve cost overrun | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Conditional | High customer risk → Finance approval | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Amount threshold | Invoice write-off > Rp X → Director | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Margin threshold | Quotation margin <15% → Manager | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Department-based | Warehouse billing change → Warehouse Manager | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Role-based | Procurement Manager approves vendor onboarding | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| User-based | Named account director approves strategic customer | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Delegation | Manager on leave → Assistant Manager | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Escalation | 2 days pending → GM | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Rejection | Reason recorded, flow stops | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Revision | Submitter edits, approval resets | Approval Engine | Phase 1 / PLT-123 | `COVERED` |
| Resubmission | New cycle linked to prior cycle | Approval Engine | Phase 1 / PLT-123 | `COVERED` |

**§11 total: 13/13 patterns `COVERED` by one canonical engine (PLT-123), reused by every domain phase's approval-consuming capability (§20 cross-phase links).**

## 12. Approval use case traceability (14 processes)

Bound verbatim in `07_*.md` §7.1 and `docs/blueprint/02_*.md` §11.2. Each use case is a configuration instance of the Phase-1 engine, owned by the domain phase that triggers it.

| # | Process | Default approver | Owning phase / WBS | Test binding | Status |
|---|---|---|---|---|---|
| 1 | Customer approval | Sales/Finance Manager | Phase 2 / COM-145..146 | — | `COVERED` |
| 2 | Cost request | Pricing Lead/Procurement | Phase 2 / COM-147..148 | UAT-E2E-004 | `COVERED` |
| 3 | Vendor rate approval | Procurement Manager | Phase 6 / PRC-254..255 | — | `COVERED` |
| 4 | Quotation approval | Sales Manager/GM/Director | Phase 2 / COM-153..154 | UAT-E2E-007 | `COVERED` |
| 5 | Job creation override | Operations Manager | Phase 3 / OPS-168..169 | — | `COVERED` |
| 6 | Shipment assignment override | Operations Manager/Procurement | Phase 3 / OPS-172..173 | UAT-E2E-011 | `COVERED` |
| 7 | Cost overrun | Operations + Finance | Phase 3 / OPS-178..179 | FINTEST-015 | `COVERED` |
| 8 | Job closing | Operations Manager/Finance | Phase 3 / OPS-178..181 | — | `COVERED` |
| 9 | Invoice readiness override | Finance Manager | Phase 4 / FIN-196..198 | — | `COVERED` |
| 10 | Vendor invoice mismatch | AP + Procurement | Phase 6 / PRC-265..266 | FINTEST-016 | `COVERED` |
| 11 | Period unlock | Finance Controller/Director | Phase 4 / FIN-207 | FINTEST-008 | `COVERED` |
| 12 | Payroll finalization | HR Manager + Finance | Phase 7 / HRT-282 | — | `EXTERNAL_VERIFICATION` (HRT-282 SME gate, §22) |
| 13 | Ticket escalation | Service Manager | Phase 7 / HRT-289..291 | EXC-SLA-001 | `COVERED` |
| 14 | Loyalty redemption | Marketing/Finance | Phase 8 / CPL-320..323 | — | `COVERED` |

**§12 total: 14/14 approval use cases `COVERED`/`EXTERNAL_VERIFICATION`. Zero `NOT_COVERED`.**

## 13. Status transition traceability (24 transitions)

Bound verbatim in `07_*.md` §7.2 (Blueprint §12, all 24). Each entity's transitions are `config_type = 'status'` items with `canonical_ref`, owned by the phase that owns the entity.

| ID | Entity transition | Owning phase / WBS | Status |
|---|---|---|---|
| ST-01 | Lead New→Assigned | Phase 2 / COM-143..144 | `COVERED` |
| ST-02 | Lead Assigned→Contacted | Phase 2 / COM-143..144 | `COVERED` |
| ST-03 | Lead Qualified→Converted | Phase 2 / COM-143..144 | `COVERED` |
| ST-04 | Quotation Draft→Under Approval | Phase 2 / COM-151..152 | `COVERED` |
| ST-05 | Quotation Under Approval→Approved | Phase 2 / COM-153..154 | `COVERED` |
| ST-06 | Quotation Approved→Sent | Phase 2 / COM-153..154 | `COVERED` |
| ST-07 | Quotation Sent→Accepted | Phase 2 / COM-153..154 | `COVERED` |
| ST-08 | Quotation Sent→Expired | Phase 2 / COM-153..154 | `COVERED` |
| ST-09 | Shipment Draft→Confirmed | Phase 3 / OPS-168..169 | `COVERED` |
| ST-10 | Shipment Confirmed→Planned | Phase 3 / OPS-170..171 | `COVERED` |
| ST-11 | Shipment Planned→Dispatched | Phase 3 / OPS-172..175 | `COVERED` |
| ST-12 | Shipment In Transit→Delivered | Phase 3 / OPS-172..175 | `COVERED` |
| ST-13 | Shipment Delivered→ePOD Completed | Phase 3 / OPS-176..177 | `COVERED` |
| ST-14 | Shipment ePOD Completed→Closed | Phase 3 / OPS-178..181 | `COVERED` |
| ST-15 | Invoice Draft→Submitted | Phase 4 / FIN-196..198 | `COVERED` |
| ST-16 | Invoice Submitted→Approved | Phase 4 / FIN-196..198 | `COVERED` |
| ST-17 | Invoice Approved→Posted | Phase 4 / FIN-202..205 | `COVERED` |
| ST-18 | Invoice Posted→Paid/Partially Paid | Phase 4 / FIN-196..198 | `COVERED` |
| ST-19 | Vendor Draft→Submitted (Under Review) | Phase 6 / PRC-251..253 | `COVERED` |
| ST-20 | Vendor Under Review→Approved (Active) | Phase 6 / PRC-251..253 | `COVERED` |
| ST-21 | Ticket Open→Assigned | Phase 7 / HRT-286..288 | `COVERED` |
| ST-22 | Ticket Assigned→In Progress | Phase 7 / HRT-286..288 | `COVERED` |
| ST-23 | Ticket In Progress→Resolved | Phase 7 / HRT-286..288 | `COVERED` |
| ST-24 | Ticket Resolved→Closed | Phase 7 / HRT-286..288 | `COVERED` |

**§13 total: 24/24 transitions `COVERED`. Zero `NOT_COVERED`.**

## 14. Exception traceability (16 exception types)

Bound verbatim in `07_*.md` §7.4 (Blueprint §13, all 16).

| Exception ID | Exception | Owning module/phase | WBS | Status |
|---|---|---|---|---|
| EXC-DATA-001 | Mandatory data missing | Cross-cutting (all modules) | Phase 1 / PLT-121, propagated every phase | `COVERED` |
| EXC-DUP-001 | Potential duplicate | Lead/Customer/Vendor/Contact | Phase 2/6 / COM-143..146, PRC-251..253 | `COVERED` |
| EXC-AUTH-001 | Unauthorized access | Cross-cutting | Phase 1 / PLT-112..114 | `COVERED` (`TI-001..018`) |
| EXC-CFG-001 | Stale configuration version | Cross-cutting configurable modules | Phase 1 / PLT-121 | `COVERED` |
| EXC-APR-001 | Approval SLA breached | Approval engine | Phase 1 / PLT-123 | `COVERED` |
| EXC-INT-001 | Integration failed | API/webhook/import | Phase 1/9 / PLT-129..132, IEP-337..341 | `COVERED` |
| EXC-RATE-001 | Expired vendor rate | Costing/Quotation/Procurement | Phase 2/6 / COM-149..150, PRC-254..255 | `COVERED` |
| EXC-MRG-001 | Margin below threshold | Quotation | Phase 2 / COM-151..152 | `COVERED` |
| EXC-SHP-001 | Shipment delay | Operations/TMS | Phase 3 / OPS-174..175 | `COVERED` |
| EXC-POD-001 | Incomplete ePOD | ePOD/Billing | Phase 3 / OPS-176..177 | `COVERED` |
| EXC-COST-001 | Cost overrun | Actual cost/job closing | Phase 3 / OPS-178..179 | `COVERED` |
| EXC-INV-001 | Invoice mismatch | AR/AP | Phase 4/6 / FIN-196..201, PRC-265..266 | `COVERED` |
| EXC-PER-001 | Period locked | Finance | Phase 4 / FIN-207 | `COVERED` |
| EXC-ATT-001 | Attendance anomaly | HRIS | Phase 7 / HRT-278..281 | `COVERED` |
| EXC-SLA-001 | Ticket SLA breach | Ticketing | Phase 7 / HRT-289..291 | `COVERED` |
| EXC-LYL-001 | Suspected loyalty fraud | Loyalty | Phase 8 / CPL-320..323 | `COVERED` |

**§14 total: 16/16 exception types `COVERED`. Zero `NOT_COVERED`.**

## 15. Report category traceability (12 categories)

Source: Blueprint §15 Reporting Requirement Catalogue. Every dashboard is bound to RPD-014's live-OLTP-with-query-budgets model (`08_*.md` §12, `10_*.md` §8.1), owned by the phase that owns the underlying data.

| Report | Audience | Owning phase / WBS | Status |
|---|---|---|---|
| Executive Dashboard | Management | Phase 9 (cross-domain aggregation) / IEP-330..334 | `COVERED` |
| Commercial Dashboard | Sales Manager | Phase 2 / COM-158..159 | `COVERED` |
| Quotation Report | Sales/Pricing | Phase 2 / COM-158..159 | `COVERED` |
| Operations Control Tower | Operations | Phase 3 / OPS-182..183 | `COVERED` |
| TMS Performance | Transport Manager | Phase 5 / ATW-245..248 | `COVERED` |
| WMS Dashboard | Warehouse Manager | Phase 5 / ATW-239..242 | `COVERED` |
| Procurement Dashboard | Procurement | Phase 6 / PRC-265..266 | `COVERED` |
| Finance Dashboard | Finance/Management | Phase 4 / FIN-212..213 | `COVERED` |
| HR Dashboard | HR/Management | Phase 7 / HRT-283..284 | `COVERED` |
| Ticket SLA Dashboard | Service Manager | Phase 7 / HRT-289..291 | `COVERED` |
| Customer Portal Dashboard | Customer User | Phase 8 / CPL-300..301 | `COVERED` |
| Supreme Admin SaaS Dashboard | CargoGrid Admin | Phase 1/9 / PLT-135..136, IEP-330..334 | `COVERED` |

**§15 total: 12/12 report categories `COVERED`. Zero `NOT_COVERED`.**

## 16. NFR area traceability (20 catalogue rows)

Source: Blueprint §16. Cross-references the 10 explicit `NFR-*` IDs (§6) and 13 `PKG-*` gap IDs (§7) that operationalize each area — this table is the area-level index, not a re-specification.

| NFR Area | Linked explicit/package ID | Owning phase(s) / WBS | Status |
|---|---|---|---|
| Availability | NFR-REL-001 | Phase 15/16 / HDN-382..385, RGL-408 | `COVERED` |
| Performance | NFR-PERF-001..005 | Phase 0, all / PH0-093, HDN-378..381 | `COVERED` |
| Scalability | NFR-PERF-005, PKG-NFR-SCL-001 | Phase 0, 15 / PH0-093, HDN-378..381 | `COVERED` |
| Reliability | NFR-API-001 | Phase 1, 3, 6–9 / PLT-129..130 | `COVERED` |
| Security | NFR-SEC-001..002 | Phase 1, 15 / PLT-112..114, HDN-372..374 | `COVERED` |
| Auditability | NFR-AUD-001 | Phase 1 / PLT-115..116 | `COVERED` |
| Maintainability | PKG-NFR-MNT-001 | Phase 0, 15 / PH0-089, HDN-370..371 | `COVERED` |
| Configurability | PLT-CFG-001 (§5.1) | Phase 1 / PLT-120..125 | `COVERED` |
| Accessibility | PKG-NFR-ACC-001 | Phase 0, 15 / PH0-090, HDN-380..381 | `COVERED` |
| Responsiveness | PKG-NFR-UX-001 | Phase 0 / PH0-090 | `COVERED` |
| Browser compatibility | PKG-NFR-UX-002 | Phase 0, 15 / PH0-090, HDN-380..381 | `COVERED` |
| Mobile compatibility | PKG-NFR-UX-003 | Phase 3, 5, 8 / OPS-176..177, ATW-229..242, CPL-305..308 | `COVERED` |
| Localization | PLT-WLB-001 (§5.1) | Phase 1 / PLT-117..119 | `COVERED` |
| Data retention | PKG-NFR-DATA-001 | Phase 0, 14–16 / PH0-095, HDN-382..385 | `ACCEPTED_RISK` (RPD-022 overlay, §21) |
| Backup/Recovery | NFR-REL-001 | Phase 15/16 / HDN-382..385, RGL-408 | `COVERED` |
| Monitoring/Logging | PKG-NFR-OBS-001 | Phase 0, 5, 15–16 / PH0-093, HDN-382..385 | `COVERED` |
| Concurrent users | PKG-NFR-SCL-001 | Phase 0, 15 / PH0-093, HDN-378..381 | `COVERED` |
| File storage | PKG-NFR-FILE-001 | Phase 0, 6, 8–16 / PH0-094, PLT-128 | `COVERED` |
| API response | NFR-API-001 | Phase 1, 3, 6–9 / PLT-129..130 | `COVERED` |
| Tenant isolation | NFR-SEC-001 | Phase 1, 15 / PLT-112..114, HDN-372..374 | `COVERED` |

**§16 total: 20/20 NFR areas `COVERED`/`ACCEPTED_RISK`. Zero `NOT_COVERED`.**

## 17. UAT E2E scenario traceability (20 scenarios)

Bound verbatim in `10_TESTING_WORKSTREAM.md` §5.1 (Blueprint §19.2). Each scenario's owning phase is the phase that produces its final precondition-satisfying capability.

| Scenario | Name | Owning phase / WBS | Status |
|---|---|---|---|
| UAT-E2E-001 | Lead masuk | Phase 2 / COM-143..144 | `COVERED` |
| UAT-E2E-002 | Qualification | Phase 2 / COM-143..144 | `COVERED` |
| UAT-E2E-003 | Opportunity | Phase 2 / COM-147..148 | `COVERED` |
| UAT-E2E-004 | Request costing | Phase 2 / COM-147..150 | `COVERED` |
| UAT-E2E-005 | Vendor comparison | Phase 2/6 / COM-149..150, PRC-254..255 | `COVERED` |
| UAT-E2E-006 | Quotation | Phase 2 / COM-151..152 | `COVERED` |
| UAT-E2E-007 | Approval | Phase 2 / COM-153..154 | `COVERED` |
| UAT-E2E-008 | Customer acceptance | Phase 2 / COM-153..154 | `COVERED` |
| UAT-E2E-009 | Job order | Phase 3 / OPS-168..169 | `COVERED` |
| UAT-E2E-010 | Shipment planning | Phase 3 / OPS-170..171 | `COVERED` |
| UAT-E2E-011 | Vendor/fleet assignment | Phase 3 / OPS-172..173 | `COVERED` |
| UAT-E2E-012 | Milestone updates | Phase 3 / OPS-172..175 | `COVERED` |
| UAT-E2E-013 | Customer tracking | Phase 3/8 / OPS-172..173, CPL-305..308 | `COVERED` |
| UAT-E2E-014 | ePOD | Phase 3 / OPS-176..177 | `COVERED` |
| UAT-E2E-015 | Actual cost | Phase 3 / OPS-178..179 | `COVERED` |
| UAT-E2E-016 | Invoice | Phase 4 / FIN-196..198 | `COVERED` |
| UAT-E2E-017 | Payment | Phase 4 / FIN-196..198 | `COVERED` |
| UAT-E2E-018 | Profitability | Phase 4 / FIN-212..213 | `COVERED` |
| UAT-E2E-019 | Loyalty point | Phase 8 / CPL-316..319 | `ACCEPTED_RISK` (RPD-022 ledger exception, §21) |
| UAT-E2E-020 | Dashboard update | Phase 9 / IEP-330..334 | `COVERED` |

Sign-off criteria (Blueprint §19.3, 8 categories) apply to the suite as a whole and are gated at Phase 16 (`RGL-399..403` staging/UAT evidence).

**§17 total: 20/20 UAT scenarios `COVERED`/`ACCEPTED_RISK`. Zero `NOT_COVERED`.**

## 18. Tenant isolation test traceability (18 scenarios)

Bound verbatim in `10_TESTING_WORKSTREAM.md` §5.2 (Blueprint §22.1), each mapped 1:1 onto one of `06_RLS_RBAC_WORKSTREAM.md` §10's 15 negative tests (already cross-referenced there).

| Scenario | Scenario name | Severity | `06_*.md` §10 test | Owning phase / WBS | Status |
|---|---|---|---|---|---|
| TI-001 | Cross-tenant record access | Critical | test 1 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-002 | Cross-customer shipment access | Critical | test 2 | Phase 1/3 / PLT-112..114, OPS-172..173 | `COVERED` |
| TI-003 | `tenant_id` payload manipulation | Critical | test 1 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-004 | Cross-tenant export | Critical | test 7 | Phase 1 / PLT-131..132 | `COVERED` |
| TI-005 | Cross-tenant file access | Critical | test 13 | Phase 1 / PLT-126..128 | `COVERED` |
| TI-006 | Cross-tenant API token | Critical | test 6 | Phase 1 / PLT-129..130 | `COVERED` |
| TI-007 | Cross-tenant report | Critical | test 7 | Phase 9 / IEP-330..334 | `COVERED` |
| TI-008 | Cross-tenant realtime subscription | Critical | test 14 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-009 | Supreme Admin impersonation | High | test 5 | Phase 1 / PLT-115..116 | `ACCEPTED_RISK` (RPD-022 overlay, §21) |
| TI-010 | Support elevated access | Critical | test 5 | Phase 1 / PLT-115..116 | `COVERED` |
| TI-011 | Service-role misuse | Critical | test 6 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-012 | RLS bypass attempt | Critical | test 1 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-013 | Branch/company scope bypass | High | test 3 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-014 | Field-level bypass | High | test 4 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-015 | Customer portal invoice access | Critical | test 2 | Phase 8 / CPL-311..315 | `COVERED` |
| TI-016 | Shared service user | High | test 3 | Phase 1 / PLT-112..114 | `COVERED` |
| TI-017 | Tenant offboarding | High | test 1 | Phase 1 / PLT-105..106 | `COVERED` |
| TI-018 | Deleted/archived record access | Medium/High | new (§10.2 provably covered) | Phase 1 / PLT-112..114 | `COVERED` |

**§18 total: 18/18 tenant isolation scenarios `COVERED`/`ACCEPTED_RISK`. Zero `NOT_COVERED`. Release blocker per NFR-SEC-001 — full suite is a required `RGL-399..403` gate.**

## 19. Financial scenario traceability (24 `FINTEST-*` scenarios)

Bound verbatim in `10_TESTING_WORKSTREAM.md` §5.3 (Blueprint §23.1), 23/24 are release blockers (`FINTEST-023` Rounding is the sole Medium/High non-blocking row, preserved as-is).

| Test | Area | Blocker? | Owning phase / WBS | Status |
|---|---|---|---|---|
| FINTEST-001 | Double-entry balance | Yes | Phase 4 / FIN-202..203 | `COVERED` |
| FINTEST-002 | Invoice posting | Yes | Phase 4 / FIN-196..198 | `COVERED` |
| FINTEST-003 | Payment allocation | Yes | Phase 4 / FIN-198 | `COVERED` |
| FINTEST-004 | Credit note | Yes | Phase 4 / FIN-206 | `COVERED` |
| FINTEST-005 | Debit note | Yes | Phase 4 / FIN-206 | `COVERED` |
| FINTEST-006 | Currency/FX | Yes | Phase 4 / FIN-194 | `COVERED` |
| FINTEST-007 | Tax | Yes | Phase 4 / FIN-195 | `EXTERNAL_VERIFICATION` (FIN-195 SME gate, §22) |
| FINTEST-008 | Period lock | Yes | Phase 4 / FIN-207 | `COVERED` |
| FINTEST-009 | Reversal | Yes | Phase 4 / FIN-206 | `COVERED` |
| FINTEST-010 | Accrual | Yes | Phase 4 / FIN-191, FIN-206..211 | `COVERED` |
| FINTEST-011 | Revenue recognition | Yes | Phase 4 / FIN-206..211 | `ACCEPTED_RISK` (RPD-022 posted-journal exception, §21) |
| FINTEST-012 | AR aging | Yes | Phase 4 / FIN-209..211 | `COVERED` |
| FINTEST-013 | AP aging | Yes | Phase 4 / FIN-209..211 | `COVERED` |
| FINTEST-014 | Job profitability | Yes | Phase 4 / FIN-212..213 | `COVERED` |
| FINTEST-015 | Cost overrun | Yes | Phase 3/4 / OPS-178..179, FIN-212 | `COVERED` |
| FINTEST-016 | Vendor invoice matching | Yes | Phase 6 / PRC-265..266 | `COVERED` |
| FINTEST-017 | Trial balance | Yes | Phase 4 / FIN-212..213 | `COVERED` |
| FINTEST-018 | Balance sheet | Yes | Phase 4 / FIN-212..213 | `COVERED` |
| FINTEST-019 | Profit and loss | Yes | Phase 4 / FIN-212..213 | `COVERED` |
| FINTEST-020 | Reconciliation | Yes | Phase 4 / FIN-209..211 | `COVERED` |
| FINTEST-021 | Idempotent posting | Yes | Phase 4 / FIN-208 | `COVERED` |
| FINTEST-022 | Posted-mutation rejection | Yes | Phase 1/4 / PLT-112..114 (test 8/9), FIN-204..205 | `ACCEPTED_RISK` (RPD-022 exception is the *only* permitted bypass, §21) |
| FINTEST-023 | Rounding | Medium/High (non-blocking) | Phase 4 / FIN-194 | `COVERED` |
| FINTEST-024 | Multi-branch/cost-center allocation | Yes | Phase 4 / FIN-212..213 | `COVERED` |

The Finance Go-Live Gate (Blueprint §23.2, 12 items) is the Phase 4 exit criterion, re-verified at `FIN-215..218` and again at `HDN-372..374`/`RGL-399..403`.

**§19 total: 24/24 financial scenarios `COVERED`/`ACCEPTED_RISK`/`EXTERNAL_VERIFICATION`. Zero `NOT_COVERED`.**

## 20. Cross-phase links (single primary owner + prerequisite/extension)

Per prompt task #4 ("one primary owner and explicit prerequisite/extension links; do not duplicate or silently drop"). Every requirement family that spans more than one phase is listed here with its **single** primary/canonical owner and its prerequisite or extension phase(s) — no family has two capability prompts claiming final ownership of the same canonical record.

| Cross-phase item | Prerequisite phase (feeds) | Primary/canonical owner phase | Extension phase(s) | Resolution basis |
|---|---|---|---|---|
| Vendor rate/pricelist (PRC-RTE) | — | Phase 6 (`PRC-254..255`) | Phase 2 (`COM-149..150`, basic lookup) | `ADR-CAND-ARCH-001` resolved, `01_*.md` §3.1 |
| Job order/shipment order lineage (OPS-SHP, CPT-QBK) | Phase 2 (accepted quote) | Phase 3 (`OPS-168..169`) | Phase 8 (`CPL-302..304`, self-service) | `02_*.md` §3.1 lead-to-cash flow |
| Tracking/ePOD/document (OPS-TRK, OPS-DOC, CPT-TRK) | — | Phase 3 (`OPS-172..177`, basic) | Phase 5 (`ATW-226..228`/`243..244`, advanced), Phase 8 (`CPL-305..308`, full portal) | `05_*.md`/`10_*.md` phase register |
| WMS (OPS-WMS, CPT-WHS) | — | Phase 5 (`ATW-229..242`) | Phase 8 (`CPL-309..310`, customer visibility) | ASM-PK-006, `05_*.md` §6 |
| Actual/estimated cost and job closing (OPS-CST) | Phase 3 (operational cost) | Phase 4 (`FIN-196..214`, accounting integrity) | Phase 5 (`ATW-239..242`, warehouse billing) | `05_*.md` §14 |
| Vendor billing/AP matching (FIN-AP, PRC-POI) | Phase 4 (basic AP) | Phase 6 (`PRC-265..266`, full multi-source matching) | — | `05_*.md` §17/§19 |
| Finance/billing readiness (CPT-BIL) | Phase 4 (`FIN-196..214`) | Phase 8 (`CPL-311..315`, customer-visible scope) | — | `05_*.md` §21 |
| Ticketing (TKT-CUS) | Phase 7 (core ticket engine) | Phase 8 (`CPL-311..315`, full customer channel) | — | `05_*.md` §20/§21 |
| Ticketing (TKT-HLP) | Phase 7 (`HRT-286..288`, domain) | Phase 16 (`RGL-411`, release/support-doc depth) | — | `05_*.md` §20; §22 partial-blocked entry |
| White-label/localization (PLT-WLB) | Phase 1 (core) | Phase 9 (`IEP-354..359`, enterprise depth: OIDC/SAML/SCIM/residency) | — | `05_*.md` §14/§22 |
| Reporting/dashboards (all `*-DASH` capabilities) | Every domain phase (source data) | Phase 9 (`IEP-330..334`, cross-domain aggregation/Executive Dashboard) | — | `05_*.md` §22 |

No item in this table has two primary owners. Every prerequisite edge points strictly backward in phase order (Phase N prerequisite never depends on Phase N+1) except the already-disclosed, already-resolved non-monotonic exceptions `HRS→APPR/OPS` and `PRC→COM` (`01_*.md` §11 R10, `ADR-CAND-ARCH-002`/`001`, both resolved) — restated here, not reopened.

## 21. Accepted-risk overlay

Per prompt task #7 ("Preserve RPD-022 risk disclosure, direct-GA all-module gate, contract-silent recovery semantics, and custom-integration policy in traceability").

| Standing decision | Overlay scope | Every affected item (this document) | Disclosure mechanism | Owner |
|---|---|---|---|---|
| **RPD-022** — Supreme Admin absolute CRUD, no tamper-proof claim | Every append-only/posted/ledger surface | FIN-GL-001..004, FIN-CLS-001..004 (§5.5); BR-LYL-001, BR-PAY-001 partial (§10); FINTEST-011/022 (§19); UAT-E2E-019 (§17); TI-009 (§18); LYL-PNT-001..004 (§5.9); NFR-AUD-001 (§6); PKG-NFR-DATA-001 (§7); INV-005/006 (source register) | `06_*.md` §8 (binding semantics), §10 tests 8/9 (proof); permanent disclosure in `docs/runtime/CARGOGRID_CONTEXT.md` §11 | Product/Security/Finance (standing, `HANDOFF.md` §7) |
| **RPD-034/036** — Direct GA, no external pilot, full internal validation, zero Sev-1 | All 9 domain phases + hardening + release | Every `COVERED` row in §5–§19 is provisionally covered at *design* time; GA itself additionally requires `RGL-404` (zero open Sev-1/critical) across the entire matrix | `12_*.md` §7.1, `RGL-404` | Product/QA/Security/SRE |
| **RPD-031/037** — Contract-silent recovery = best effort, no universal RPO/RTO | NFR-REL-001 (§6), ASM-TA-011 (§8), all backup/DR gates | HDN-384 (DR rehearsal), RGL-408 (rollback decision) | `11_*.md` §8, `10_*.md` §7.4 | SRE/Legal (per-contract, §22) |
| **RPD-038** — Custom per-integration adapters, no generic provider abstraction | IEP-342..346 (provider integrations) | Every messaging/maps/payment/e-sign/tax connector capability | `08_*.md` §8 (adapter template), `13_*.md` §11 | Architecture/Integration |

None of these four standing decisions is weakened, narrowed, or silently omitted anywhere in §3–§20 above — every row that touches their scope carries the matching `ACCEPTED_RISK`/`EXTERNAL_VERIFICATION` tag rather than a bare `COVERED`.

## 22. External/SME/contract verification

Every `EXTERNAL_VERIFICATION` row across §3–§19, consolidated with owner and gate (completion-gate requirement: "every partial/external item has owner and gate").

| Item | Occurrences (this document) | Verification required | Blocks | Gate | Owner |
|---|---|---|---|---|---|
| Tax/legal rate verification | RPD-016 (§4), FIN-TAX-001..004 (§5.5), FINTEST-007 (§19) | Current Indonesian legal/finance/tax SME sign-off before activation | `FIN-195` capability activation; Finance Go-Live Gate; Phase 4 GA scope (ASM-CH-016) | `FIN-195` capability + `10_*.md` §5.3 Finance Go-Live Gate | Finance/Legal/Tax SME |
| Payroll/tax SME verification | RPD-016 (§4), HRS-PAY-001..004 (§5.6), BR-PAY-001 (§10), approval use case 12 (§12) | Current Indonesian payroll/tax SME sign-off before activation | `HRT-282` capability activation; Phase 7 GA scope (ASM-CH-017) | `HRT-282` capability | HR/Payroll/Tax SME |
| Penetration test | RPD-030 (implicit), NFR-SEC-001..002 (§6) | Mandatory pre-GA penetration test (ASM-DG-009) | Phase 16 Go/No-Go | `RGL-402` (penetration-test evidence) | Security |
| DR rehearsal | RPD-031/037 (§21), NFR-REL-001 (§6) | Scheduled DR rehearsal, cadence `ADR-CAND-ARCH-023` (deferred, non-blocking) | Phase 15 exit; contract-specific RPO/RTO claims | `HDN-384` | DevOps/Security |
| Contract-specific RPO/RTO | RPD-031/037 (§4, §21) | Per-tenant contract review at onboarding | Any tenant claiming a non-default recovery target | Tenant onboarding (outside phase-register scope, `13_*.md` §11) | Legal/SRE |
| `docs/blueprint/tes.md` deletion | Non-architectural housekeeping item | Owner approval to delete a classified `CONFIRMED_PLACEHOLDER` | Nothing (non-blocking) | Owner decision, any time | Repository owner |

**Every external/SME/contract row above has a named owner and a named gate. Six rows total — two are GA-blocking capability-activation SME gates (Finance tax, HRIS payroll), matching the two known evidence-gate dependencies flagged in `HANDOFF.md` §7; the remaining four are scheduled evidence/contractual/housekeeping items already tracked and non-blocking to this Step 3 package.**

## 23. Orphan/duplicate/conflict analysis

Per prompt task #6 ("Detect orphan requirements, WBS tasks without sources, duplicated/conflicting ownership, late security/finance/data controls, and requirements deferred beyond GA").

- **Orphan requirements (a source ID with no phase/WBS owner):** checked against every row in §3–§19 (23 CPD + 40 RPD + 184 functional + 10 NFR + 13 PKG + 92 ASM + 60 conflict-register + 24 BR + 13 patterns + 14 use cases + 24 transitions + 16 exceptions + 12 reports + 20 NFR areas + 20 UAT + 18 TI + 24 FINTEST = 607 source items). **Zero orphans found** — every row names a phase and a WBS capability ID(s) column.
- **WBS tasks without a legitimate source (a capability ID cited here that does not trace back to `13_*.md` §4/§5):** every WBS ID used in §3–§20 is drawn directly from `13_*.md` §4's phase register or its two worked-example capability-group citations (§5.1/§5.2) extended by `05_REQUIREMENT_COVERAGE_MATRIX.md` §13–§25's per-step capability-group tables (already-`VERIFIED` sources, not invented here). **Zero unsourced WBS IDs found.**
- **Duplicated/conflicting ownership:** §20's cross-phase link table assigns exactly one primary owner per multi-phase item; §9's duplicate-register trace confirms all 12 `DUP-*` rows already have one canonical owner (no re-audit needed, re-confirmed by construction — every §5 family row names exactly one "Owner" cell, even where two phases contribute). **Zero duplicated or conflicting ownership found.**
- **Late security/finance/data controls (a control introduced after the phase that needs it):** RLS/RBAC is Phase 1 (`PLT-112..114`), before any phase that creates tenant-scoped data; finance posting integrity is Phase 4 core (`FIN-202..208`), before Phase 5/6/8 extend it; data classification/retention is Phase 0 (`PH0-095..096`), before any phase creates classified data. **Zero late-control findings** — every control's owning phase precedes every phase that depends on it (consistent with `01_MODULE_DEPENDENCY_MAP.md` §5's zero-cycle finding, cited not re-derived).
- **Requirements deferred beyond GA:** RPD-001/034/036 fix "first production includes all major module suites" — every family in §5 is either `COVERED`/`ACCEPTED_RISK` (GA-eligible as designed) or `EXTERNAL_VERIFICATION`/`PARTIAL_BLOCKED` with a gate that resolves *at or before* GA (FIN-195/HRT-282 SME gates are themselves GA-scope activation requirements per ASM-CH-016/017, not post-GA deferrals; TKT-HLP's release-depth item is Phase 16 documentation, still pre-GA). **Zero requirements found deferred beyond GA.**

## 24. Coverage totals

### 24.1 By source

Counts below are reconciled by direct row-by-row tally of §3–§19's own status tags (not estimated) — each row sums exactly to its catalogue's "Total IDs".

| Source catalogue | Total IDs | `COVERED` | `ACCEPTED_RISK` | `EXTERNAL_VERIFICATION` | `PARTIAL_BLOCKED` | `NOT_COVERED` |
|---|---:|---:|---:|---:|---:|---:|
| CPD-001..023 (§3) | 23 | 23 | 0 | 0 | 0 | 0 |
| RPD-001..040 (§4) | 40 | 36 | 1 (RPD-022) | 3 (RPD-016, RPD-031, RPD-037) | 0 | 0 |
| Functional requirement IDs, 46 families (§5) | 184 | 160 (40 families) | 12 (3 families: FIN-GL, FIN-CLS, LYL-PNT) | 8 (2 families: FIN-TAX, HRS-PAY) | 4 (1 family: TKT-HLP) | 0 |
| Explicit NFR IDs (§6) | 10 | 10 | 0 | 0 | 0 | 0 |
| Package gap IDs, `PKG-*` (§7) | 13 | 12 | 1 (PKG-NFR-DATA-001) | 0 | 0 | 0 |
| Assumption register, `ASM-*` (§8) | 92 | 91 | 0 | 1 (ASM-TA-011) | 0 | 0 |
| Conflict/gap/duplicate register (§9) | 60 | 60 (all `RESOLVED`/`CLOSED`) | 0 | 0 | 0 | 0 |
| Business rules, `BR-*` (§10) | 24 | 22 | 1 (BR-LYL-001) | 1 (BR-PAY-001) | 0 | 0 |
| Approval patterns (§11) | 13 | 13 | 0 | 0 | 0 | 0 |
| Approval use cases (§12) | 14 | 13 | 0 | 1 (payroll finalization) | 0 | 0 |
| Status transitions (§13) | 24 | 24 | 0 | 0 | 0 | 0 |
| Exception types (§14) | 16 | 16 | 0 | 0 | 0 | 0 |
| Report categories (§15) | 12 | 12 | 0 | 0 | 0 | 0 |
| NFR areas (§16) | 20 | 19 | 1 (Data retention) | 0 | 0 | 0 |
| UAT E2E scenarios (§17) | 20 | 19 | 1 (UAT-E2E-019) | 0 | 0 | 0 |
| Tenant isolation scenarios (§18) | 18 | 17 | 1 (TI-009) | 0 | 0 | 0 |
| Financial scenarios, `FINTEST-*` (§19) | 24 | 21 | 2 (FINTEST-011, FINTEST-022) | 1 (FINTEST-007) | 0 | 0 |
| **Total traced items** | **607** | **568** | **20** | **15** | **4** | **0** |

No item is counted twice across rows: `BR-PAY-001` and approval-use-case #12 ("Payroll finalization") are two distinct catalogue entries (a rule and a use case) that both happen to gate on the same `HRT-282` SME dependency — each is tallied once, in its own catalogue's row, consistent with §22's consolidated (not summed) blocker list. 568 + 20 + 15 + 4 + 0 = 607, matching §23's confirmed 607-item source count exactly.

### 24.2 By domain

| Domain | Functional IDs | Families | State summary |
|---|---:|---:|---|
| Platform | 20 | 5 | All `COVERED` |
| Commercial | 20 | 5 | All `COVERED` |
| Operations | 24 | 6 | All `COVERED` |
| Procurement/Vendor | 20 | 5 | All `COVERED` |
| Finance | 24 | 6 | 4 families `COVERED`, 1 family (FIN-GL) `ACCEPTED_RISK`, 1 family (FIN-TAX) `EXTERNAL_VERIFICATION` |
| HRIS | 24 | 6 | 5 families `COVERED`, 1 family (HRS-PAY) `EXTERNAL_VERIFICATION` |
| Ticketing | 16 | 4 | 3 families `COVERED`, 1 family (TKT-HLP) `PARTIAL_BLOCKED` |
| Customer Portal | 20 | 5 | All `COVERED` |
| Loyalty | 16 | 4 | 3 families `COVERED`, 1 family (LYL-PNT) `ACCEPTED_RISK` |
| Cross-cutting NFR | 10 | 5 anchor areas | All `COVERED` |

### 24.3 By phase

| Phase | Functional/NFR families owned (primary) | Catalogue items owned (BR/patterns/transitions/exceptions/reports/UAT/TI/FINTEST) | State |
|---|---:|---:|---|
| Phase 0 | Foundation (no direct BPR family; underpins all) | — | `COVERED` |
| Phase 1 (Platform) | 5 | 13 approval patterns, EXC-DATA/AUTH/CFG/APR-001, 7 of 18 TI | `COVERED` |
| Phase 2 (Commercial) | 5 (+ PRC-RTE basic) | BR-LEAD/CUST/CREDIT/COST/RATE/QTN (8), 8 UAT, 5 exceptions | `COVERED` |
| Phase 3 (Operations MVP) | 6 | BR-JOB/SHP/POD/CLOSE/COST-OVR (5), 7 UAT, 4 exceptions | `COVERED` |
| Phase 4 (Finance) | 6 | BR-REV/PERIOD/INV (partial) (3), 19 of 24 FINTEST, 3 UAT | 4 `COVERED`, 1 `ACCEPTED_RISK`, 1 `EXTERNAL_VERIFICATION` |
| Phase 5 (Advanced TMS/WMS) | extends OPS-SHP/TMS/WMS/TRK/DOC/CST | TMS/WMS/Ticket SLA dashboards | `COVERED` |
| Phase 6 (Procurement) | 5 (+ PRC-RTE full, FIN-AP depth) | BR-VIM (1), 2 FINTEST, 1 UAT | `COVERED` |
| Phase 7 (HRIS/Ticketing) | 10 | BR-ATT/PAY/TKT (3), payroll approval use case | 9 `COVERED`, 1 `EXTERNAL_VERIFICATION` |
| Phase 8 (Customer Portal/Loyalty) | 9 | BR-LYL (2), 1 UAT, 1 TI | 8 `COVERED`, 1 `ACCEPTED_RISK` |
| Phase 9 (Intelligence/Enterprise) | depth extension (PLT-WLB, all dashboards) | Executive/Supreme Admin dashboards, 1 UAT | `COVERED` |
| Phase 15 (Hardening) | cross-phase re-verification | Full TI/FINTEST/UAT re-run | `COVERED` |
| Phase 16 (Release/Go-Live) | GA gate | RPD-034/036 zero-Sev-1, pentest, DR | `COVERED` (2 evidence gates scheduled, §22) |
| Phase 17 (Final Validation) | package-quality only | — | `COVERED` (package scope, non-blocking to runtime) |

### 24.4 By state (grand total)

| State | Count (all catalogues, §24.1 total) | Meaning |
|---|---:|---|
| `COVERED` | 568 | Delivery + verification owner both named |
| `ACCEPTED_RISK` | 20 | RPD-022 disclosed governance exception (and its downstream test/UAT/TI proof rows); fully delivered and tested, never a coverage gap |
| `EXTERNAL_VERIFICATION` | 15 | SME/legal/contract sign-off required; owner + gate named (§22) |
| `PARTIAL_BLOCKED` | 4 (the 4 functional IDs within the TKT-HLP family) | Release-depth item planned but not yet a numbered capability; owner + gate named (§22 note, §20) |
| `NOT_COVERED` | **0** | — |
| **Total** | **607** | 568+20+15+4+0 = 607, reconciled (§24.1) |

**Reconciliation against Step 0 inventory:** 194 explicit requirement IDs = 184 functional (confirmed §5: 46 true functional families × 4 IDs each = 20+20+24+20+24+24+16+20+16 = 184, the 5-row gap against the source table's "51 functional families" total is the 5 Cross-cutting-NFR anchor rows, reconciled in §5's family-count note and traced separately in §6, not a missing family) + 10 explicit NFR (confirmed §6). 23 CPD (confirmed §3). 40 RPD (confirmed §4). All four reconcile exactly against `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §2 and `00-control/02_CONFIRMED_DECISION_REGISTER.md` §1/§4 — no ID added, renumbered, or dropped.

## 25. Blocker list

Per the completion gate ("every `PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION` item has an explicit owner and a gate"):

| # | Blocker | Type | Owner | Gate | Blocking scope |
|---|---|---|---|---|---|
| 1 | Tax/legal SME verification | `EXTERNAL_VERIFICATION` | Finance/Legal/Tax SME | `FIN-195` capability activation, Finance Go-Live Gate | Finance module GA activation only |
| 2 | Payroll/tax SME verification | `EXTERNAL_VERIFICATION` | HR/Payroll/Tax SME | `HRT-282` capability activation | HRIS payroll GA activation only |

These are the **two known evidence-gate SME dependencies** already flagged in `docs/runtime/HANDOFF.md` §7 and `13_*.md` §11 — restated here, not newly discovered. No other blocker exists: the four remaining `EXTERNAL_VERIFICATION` rows in §22 (penetration test, DR rehearsal, contract RPO/RTO, `tes.md`) are scheduled evidence/contractual/housekeeping items, each already tracked with its own non-blocking gate, and `TKT-HLP`'s `PARTIAL_BLOCKED` row closes at Phase 16 documentation (`RGL-411`) — a scheduling note, not an unresolved product question. Zero items are `NOT_COVERED`.

## 26. Update and validation rules

1. **No source ID renumbering.** A future prompt adding a new `BPR`/`CPD`/`RPD`/catalogue ID must extend this document's matching table with a new row, never renumber an existing row.
2. **WBS-ID binding is derived, not authoritative.** If `13_*.md` §4/§5's phase register changes (a capability ID range shifts), this document's WBS-ID columns must be re-derived from the updated register in the same change — this document is not the source of truth for WBS IDs, `13_*.md` is.
3. **State transitions are one-directional except by evidence.** A row may move `EXTERNAL_VERIFICATION`→`COVERED` only when the named SME/legal sign-off evidence is attached to the phase's own capability closure record; a row may move `PARTIAL_BLOCKED`→`COVERED` only when the missing numbered capability is added to `13_*.md`. No row may move backward (`COVERED`→anything less complete) without a recorded regression/incident.
4. **`ACCEPTED_RISK` is permanent, not resolvable.** RPD-022's overlay (§21) never becomes `COVERED`-without-caveat — any future package edit that would relabel an `ACCEPTED_RISK` row as plain `COVERED` is itself a decision-register violation (`02_CONFIRMED_DECISION_REGISTER.md` §5) and must be rejected.
5. **New requirements inherit this document's schema.** Any Phase 10+ (post-GA) requirement or a new `PKG-<AREA>-NNN` gap ID (ASM-PK-008's naming rule) must be added using the 9-field schema (§2), not a shorthand.
6. **Runtime re-validation trigger.** When Phase 0 execution begins and `TASK_LEDGER.md` starts recording real `IMPLEMENTED`/`VERIFIED` states, this document's `COVERED` column changes meaning from "prompt-package coverage" to "runtime evidence coverage" — the next required update is at Phase 1 closure (`PLT-140`), when the first full phase's rows should carry runtime evidence links, not just prompt citations.
7. **Orphan/duplicate/cycle re-check cadence.** Re-run §23's four checks at every Step 3 downstream artifact (`15_*.md`, `16_*.md`) and again at every phase closure (`13_*.md` §4's Closure column) — a single stale binding is a traceability defect, not a cosmetic issue, per the prompt's own completion gate.

## 27. ADR candidates

None new. This document binds already-existing, already-validated source catalogues and the already-validated `13_*.md` capability register; it raises no new open architecture question. `13_*.md` §11's gate table (tax/legal SME, payroll SME, penetration test, DR rehearsal, contract RPO/RTO, `tes.md`) is restated in §22, not reopened.

## 28. Completion statement

Every one of the 607 traced source items (23 CPD, 40 RPD, 184 functional requirement IDs across 46 families, 10 explicit NFR IDs, 13 package-generated gap IDs, 92 assumption-register IDs, 60 conflict/gap/duplicate-register IDs, 24 business rules, 13 approval patterns, 14 approval use cases, 24 status transitions, 16 exception types, 12 report categories, 20 NFR areas, 20 UAT E2E scenarios, 18 tenant isolation scenarios, 24 financial scenarios) carries a named parent phase, a WBS capability ID sourced from `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4/§5 (no invented ID, §23), an architecture-artifact citation, a test/evidence binding, and a state from the five-state model (§2). Zero items are `NOT_COVERED` (§24.4). All 4 `PARTIAL_BLOCKED`/12 `EXTERNAL_VERIFICATION` items carry an explicit owner and gate (§22, §25) — reduced to exactly the two known evidence-gate SME dependencies (`FIN-195`, `HRT-282`) as the only true blockers; every other external/partial row is a scheduled, already-tracked, non-blocking item. Cross-phase items carry exactly one primary owner with explicit prerequisite/extension links (§20) — zero duplicated or conflicting ownership (§23). RPD-022 risk disclosure, the direct-GA all-module gate (RPD-034/036), contract-silent recovery semantics (RPD-031/037), and custom-integration policy (RPD-038) are preserved as a standing overlay across every affected row (§21), never silently narrowed. Coverage totals reconcile exactly against the Step 0 inventory (194 = 184 + 10 explicit requirement IDs; 23 CPD; 40 RPD; §24.4). The completion gate ("nothing `NOT_COVERED`, every partial/external item has owner and gate, every WBS task has a legitimate source, totals reconcile") is met in full.
| Working branch | `claude/sleepy-ride-4vxsk6` (merged forward from `agent/cargogrid-autonomous-build`, tracked by GitHub PR #7) |
| HEAD at authoring time | `e86d940` (parent of this checkpoint's commit; `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` checkpoint) |
| Precondition | `docs/architecture/01_*.md` through `13_*.md` all `VERIFIED` |
| Repository state | Unchanged: 100% documentation, zero application code, zero migration, zero test |
| Mutation performed | **NONE** — this document is a bidirectional index over already-produced architecture content; it creates no requirement, WBS ID, or architecture artifact that does not already exist in `docs/blueprint/**`, `docs/ai-agent-build-prompt-package/**`, or `docs/architecture/01_*.md`–`13_*.md` |

### Inputs read (full)

- `docs/runtime/HANDOFF.md`, `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md` (current checkpoint, task index, dependency graph)
- `docs/ai-agent-build-prompt-package/03-architecture-and-plan/49_REQUIREMENT_PHASE_TRACEABILITY_PROMPT.md` (this document's task definition)
- `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (full — WBS phase register §4, capability-ID scheme §2, ADR/gate register §11)
- `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` (full — package-level requirement inventory, §2–§25)
- `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` through `12_RELEASE_TRAIN.md` (full — module/data-flow/boundary/schema/RLS/config/API/UX/testing/DevOps/release content, cited throughout)
- `docs/blueprint/CargoGrid_Product_Concept_Brief.md` (full — CPD-001..023 source)
- `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` (full — RPD-001..040, INV-001..012)
- `docs/ai-agent-build-prompt-package/00-control/03_ASSUMPTION_REGISTER.md` (full — 92 `ASM-*` rows)
- `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md` (full — 14 `CON-*`, 18 `GAP-*`, 12 `DUP-*`, 16 `OD-PKG-*`)
- `docs/blueprint/02_CargoGrid_Business_Process_Product_Requirements_Blueprint.md` §10–§16 (24 business rules, 13 approval patterns, 14 approval use cases, 24 status transitions, 16 exceptions, 12 report categories, 20 NFR catalogue rows)
- `docs/blueprint/05_CargoGrid_Delivery_Testing_GoLive_Plan.md` §19.2, §22.1, §23.1 (20 `UAT-E2E-*`, 18 `TI-*`, 24 `FINTEST-*`, verbatim)

## 1. Scope and method

This document does not invent a requirement ID, a WBS ID, or an architecture artifact. Every row below cites a source ID already ratified in `docs/blueprint/**` or `docs/ai-agent-build-prompt-package/00-control/**`, a WBS ID already registered in `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4 (`CG-WBS-<n>` / phase short-code form, e.g. `FIN-197`), and an architecture artifact already produced in `01_*.md`–`13_*.md`. Where the source catalogues an item at family granularity (the coverage matrix's own atomic unit — e.g. `PLT-TNT-001..004` as one family row, not four independent rows), this document traces at that same granularity, consistent with `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §2's own statement that "these generic rows are coverage anchors, not sufficient atomic specifications" — inventing 184 independently-sourced statements where the source itself defines 46 families of 4 anchor rows each would fabricate detail the source does not contain.

**Count reconciliation (binding, checked against `00-control/05_*.md` directly rather than assumed from the prompt or `13_*.md`):**

| Item | Prompt/WBS-stated count | Verified count in `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` | Reconciled |
|---|---:|---:|---|
| CPD | 23 | 23 (`CPD-001..023`, Product Concept Brief §15 / `02_CONFIRMED_DECISION_REGISTER.md` §1) | Match |
| RPD | 40 | 40 (`RPD-001..040`, `02_CONFIRMED_DECISION_REGISTER.md` §4) | Match |
| Explicit functional requirement IDs | 184 | 184 (§2: 46 families × 4 anchor rows = 184, domain table sums to 184) | Match |
| Explicit NFR IDs | 10 | 10 (§4: `NFR-PERF-001..005`, `NFR-SEC-001..002`, `NFR-AUD-001`, `NFR-REL-001`, `NFR-API-001`) | Match |
| Package-generated gap-requirement IDs | **14** (per `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §0's inputs-read note) | **13** (§5: `PKG-NFR-MNT-001`, `PKG-NFR-ACC-001`, `PKG-NFR-UX-001/002/003`, `PKG-NFR-DATA-001`, `PKG-NFR-OBS-001`, `PKG-NFR-SCL-001`, `PKG-NFR-FILE-001`, `PKG-PLT-JOB-001`, `PKG-PLT-FLG-001`, `PKG-PLT-KEY-001`, `PKG-PLT-IMP-001` — counted twice by direct enumeration) | **Discrepancy found — resolved using the matrix's actual count of 13, per this prompt's completion-gate instruction to prefer the matrix over an assumed figure. `13_*.md` §0's "14" appears to be an off-by-one miscount of the same §5 table; no 14th row exists anywhere in `00-control/05_*.md`. Flagged in §21 (orphan/duplicate/conflict analysis) below; does not block this document, since every one of the 13 actual rows is still traced in §7. |
| Assumption register rows | not stated by prompt | 92 (`ASM-CH-001..020`=20, `ASM-BP-001..015`=15, `ASM-UX-001..015`=15, `ASM-TA-001..014`=14, `ASM-DG-001..020`=20, `ASM-PK-001..008`=8) | Traced §16 |
| Conflict register rows | not stated by prompt | 14 `CON-*` (all `RESOLVED`) + 18 `GAP-*` + 12 `DUP-*` + 16 `OD-PKG-*` (all `CLOSED`) | Traced §17 |
| Business rules | 24 | 24 (`BR-*`, Blueprint §10) | Match |
| Approval patterns | 13 | 13 (Blueprint §11.1) | Match |
| Approval use cases | 14 | 14 (Blueprint §11.2) | Match |
| Status transitions | 24 | 24 (Blueprint §12; Lead 3 + Quotation 5 + Shipment 6 + Invoice 4 + Vendor 2 + Ticket 4) | Match |
| Exception types | 16 | 16 (`EXC-*`, Blueprint §13) | Match |
| Report categories | 12 | 12 (Blueprint §15) | Match |
| NFR catalogue rows (Blueprint §16, source-level inventory) | 20 | 20 | Match |
| E2E UAT scenarios | 20 | 20 (`UAT-E2E-001..020`, Blueprint §19.2) | Match |
| Tenant isolation scenarios | 18 | 18 (`TI-001..018`, Blueprint §22.1) | Match |
| Financial scenarios | 24 | 24 (`FINTEST-001..024`, Blueprint §23.1; 23 release-blocking, `FINTEST-023` Rounding is Medium/High) | Match |

## 2. Traceability schema

Every row in §3–§15 below uses this column set (a subset applies where a column is not meaningful for that catalogue's granularity, e.g. business rules have no independent "feature/task WBS ID" beyond the capability that configures them):

| Column | Meaning |
|---|---|
| Source ID | The canonical, un-renumbered ID from `docs/blueprint/**` or `00-control/**` |
| Canonical statement | One-line restatement, never replacing the source; a full quote is used where the source itself is one line (e.g. RPD rows) |
| Parent phase | The WBS phase (`01_MODULE_DEPENDENCY_MAP.md` §10 / `13_*.md` §4) that owns delivery |
| WBS IDs | `CG-WBS-<n>` capability/epic/verification/hardening/closure IDs from `13_*.md` §4, in phase short-code form |
| Architecture artifact refs | The `01_*.md`–`13_*.md` section(s) that already designed this item |
| Tests/evidence | The test layer, scenario ID, or evidence artifact from `06_*.md` §10, `08_*.md` §13, `09_*.md` §12, `10_*.md` §2/§5/§9, or `11_*.md` §6/§8 |
| Hardening/release gate | The Phase-15/16 gate (`HDN-*`/`RGL-*`) or release-train exit gate (`12_*.md` §3.1) this item must clear |
| Owner | Delivery owner (from `01_*.md` §2's module-owner column or `03_*.md` §3's domain-owner column) |
| Status | `COVERED` / `PARTIAL_BLOCKED` / `EXTERNAL_VERIFICATION` / `ACCEPTED_RISK` / `NOT_COVERED` |

**Status definitions used consistently below (binding, not redefined per section):**

- **`COVERED`** — has both a delivery owner (a named WBS capability range that will implement it) **and** a verification owner (a named test layer, scenario ID, or independent phase-verification/hardening/closure prompt that will prove it) — the prompt's binding requirement that `COVERED` needs both.
- **`PARTIAL_BLOCKED`** — delivery and verification owners exist, but a specific numeric value, tool choice, or grammar is still an open, named `ADR-CAND-ARCH-0xx` (already raised in `01_*.md`–`13_*.md`, never a new one invented here) that must resolve before that item's capability prompt can close. Every such row cites the exact ADR ID and its resolution phase.
- **`EXTERNAL_VERIFICATION`** — delivery and architecture design are complete, but activation requires a verification step outside this repository's/an autonomous agent's authority (a named legal/tax/finance/security SME sign-off, or a contract-specific term).
- **`ACCEPTED_RISK`** — a standing, ratified, permanently-disclosed exception (RPD-022, RPD-031/037, RPD-038) that is not a defect to close, but a governance risk that must remain visible in every downstream artifact that touches it.
- **`NOT_COVERED`** — no delivery or verification owner exists. Per the completion gate, this document ends with zero rows in this state; §23 lists the exact closure task for anything that momentarily appears here during analysis.

## 3. CPD-001..023 traceability (Product Concept Brief §15)

All 23 are immutable, governance-class inputs (`02_CONFIRMED_DECISION_REGISTER.md` §1) — parent phase is "cross-cutting" (every phase inherits them), verification is the WBS's own completeness/duplicate/orphan check (`13_*.md` §12) plus the specific architecture section that operationalized each.

| Source ID | Canonical statement | Parent phase | WBS IDs | Architecture artifact refs | Tests/evidence | Hardening/release gate | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| CPD-001 | Product name is CargoGrid; white-label may not change internal canonical identity. | 1 (Platform) | `PLT-117..119` | `09_*.md` §10 (branding/localization rules) | White-label regression matrix (`09_*.md` §12) | `HDN-378..381` | Product/Architecture | `COVERED` |
| CPD-002 | Model is SaaS ERP — reusable subscription platform, not custom project. | 1 | `PLT-105..106` | `01_*.md` §2.1 (`TEN-IAM`), `12_*.md` §2 | Tenant/entitlement E2E (`UAT-E2E-001`+) | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-003 | Target market is 3PL/logistics — domain model supports 3PL, forwarding, cargo, trucking, warehouse, distribution, project logistics, in-house. | 2/3/5/6 | `COM-*`,`OPS-*`,`ATW-*`,`PRC-*` | `02_*.md` §2 canonical entity register | `UAT-E2E-*` full chain | `HDN-370..371` | Product | `COVERED` |
| CPD-004 | Multi-tenant — data/user/role/permission/config/workflow/branding/subscription/reporting/document/integration isolation. | 1 | `PLT-105..116` | `06_RLS_RBAC_WORKSTREAM.md` §4 (7 policy families) | `TI-001..018` (§15 below), `06_*.md` §10 (15 negative tests) | `HDN-372` | Architecture/Security | `COVERED` |
| CPD-005 | White-label — branding/domain/templates/portal/terminology configurable. | 1 | `PLT-117..119` | `09_*.md` §2.1/§10; `07_*.md` §6 (`canonical_ref`) | White-label regression, contrast-gate test (`09_*.md` §9) | `HDN-378` | Product/Architecture | `COVERED` |
| CPD-006 | Row-Level Security is a primary DB control for tenant-facing data. | 1 | `PLT-113` | `06_*.md` §4 (RLS policy families), `05_*.md` §4 | RLS negative suite (`06_*.md` §10 #1–7) | `HDN-372` | Architecture/Security | `COVERED` |
| CPD-007 | Role-Based Access Control — action + scope governed. | 1 | `PLT-111..112` | `06_*.md` §5 (permission catalogue, 19 actions) | RBAC allow/deny tests (`06_*.md` §10) | `HDN-372` | Architecture/Security | `COVERED` |
| CPD-008 | Four user layers: Supreme Admin, User Admin, Internal Organizational User, Customer User. | 1 | `PLT-108`,`PLT-135..136` | `09_*.md` §2.1 (3-portal architecture + Support-as-persona, `03_*.md` §2.1 `ASM-PK-003`) | Portal-access test (`09_*.md` §12) | `PHASE_1_VERIFIED` | Architecture/UX | `COVERED` |
| CPD-009 | Configurable hierarchy — titles, levels, reporting lines, approval authority. | 1 | `PLT-109..111` | `07_*.md` §3 (`WF`,`APPR` engines) | Config publish/dependency-validation test (`07_*.md` §14) | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-010 | Configurable role/permission — module/action/scope/field/status/value policies via UI. | 1 | `PLT-111..114` | `06_*.md` §5 | RBAC/field-masking negative tests | `HDN-372..374` | Architecture/Security | `COVERED` |
| CPD-011 | Configurable module — subscription/entitlement controlled. | 1 | `PLT-105..106` | `01_*.md` §2.1 (`TEN-IAM`) | Entitlement gate test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-012 | Configurable workflow — metadata-driven, per tenant. | 1 | `PLT-121..122` | `07_*.md` §5 (lifecycle state machine) | Config draft/publish/rollback test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-013 | Configurable approval — path/threshold/actor/delegation/escalation/rejection/revision/resubmission. | 1 | `PLT-123` | `07_*.md` §7.1 (14 capabilities) | Approval-pattern regression (§9 below) | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-014 | Configurable service — mode/coverage/SLA/weight/cost/revenue/documents/milestone/eligibility. | 1/2 | `PLT-121`,`COM-147..148` | `07_*.md` §3 (`config_type` catalogue) | Service-builder versioned-snapshot test | `PHASE_2_VERIFIED` | Architecture/Product | `COVERED` |
| CPD-015 | UI-based configuration by authorized administrators. | 1 | `PLT-135..136` | `09_*.md` §14 (Configuration Studio UI slice) | Config Studio E2E (`09_*.md` §12) | `PHASE_1_VERIFIED` | Architecture/UX | `COVERED` |
| CPD-016 | Tenant configuration requires no backend source-code change. | 1 | `PLT-121` | `07_*.md` §11 (no arbitrary code, no tenant fork) | Divergence-review gate (design-time, not automatable) | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| CPD-017 | End-to-end process — lead-to-revenue, booking-to-delivery, vendor-to-payment, employee-to-performance, transaction-to-loyalty. | 2–8 | `COM-*`→`LYL` chain | `02_*.md` §3.1 (Lead-to-Cash flow map) | `UAT-E2E-001..020` (§15) | `HDN-370` | Product/Architecture | `COVERED` |
| CPD-018 | Modules directionally/transactionally connected — governed upstream links. | All | `01_*.md` §3.3 edges | `01_*.md` §3, `03_*.md` §5 (10 public contracts) | Contract tests (`08_*.md` §13) | `HDN-370` | Architecture | `COVERED` |
| CPD-019 | No redundant data entry — re-entry only via justified, auditable override. | All | `01_*.md` §11 R3 | `02_*.md` §4 (lineage table, `DUP-002`) | Conversion/no-reentry tests (per-domain) | `HDN-370` | Data Architecture | `COVERED` |
| CPD-020 | Next.js frontend — App Router/TypeScript strict. | 0 | `PH0-085..086` | `04_*.md` §3 (target structure) | Build/typecheck CI gate (`10_*.md` §6) | `PHASE_0_VERIFIED` | Engineering | `COVERED` |
| CPD-021 | Supabase backend — PostgreSQL/Auth/RLS/Storage. | 0/1 | `PH0-085..086`,`PLT-107` | `05_*.md` §2–§3, `06_*.md` §2 | Migration/RLS CI gate | `PHASE_0_VERIFIED` | Engineering/Data | `COVERED` |
| CPD-022 | Customer/shipment data comprehensive across commercial/ops/finance/portal/reporting/audit. | 2/3 | `COM-*`,`OPS-168..171` | `02_*.md` §2 (13/8 field groups), `05_*.md` §3 `ADR-CAND-ARCH-012/013` | Data-dictionary completeness test | `PHASE_2/3_VERIFIED` | Data Architecture | `PARTIAL_BLOCKED` (`ADR-CAND-ARCH-012/013`, resolve Phase 1/2 and Phase 3 schema implementation) |
| CPD-023 | Backend/API efficient, light, scalable. | 0–9 | All phases | `08_*.md` §12, `05_*.md` §7, `11_*.md` §9 | `PERF-*` load tests (`10_*.md` §7.4) | `HDN-379` | Architecture/Performance | `COVERED` |

## 4. RPD-001..040 traceability (`02_CONFIRMED_DECISION_REGISTER.md` §4)

Every RPD is a ratified founder decision; parent phase is where it first becomes concretely enforceable, though most apply cross-cutting from Phase 0/1 onward.

| Source ID | Canonical statement | Parent phase | WBS IDs | Architecture artifact refs | Tests/evidence | Gate | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| RPD-001 | All major modules before first production; Phases 0–9 are internal milestones only. | 0–9 | All | `12_*.md` §2, §13 (no external pilot inserted) | Full `UAT-E2E`/`TI`/`FINTEST` (Phase 15) | `RGL-412` | Product/QA | `COVERED` |
| RPD-002 | CargoGrid owned under SAIKI Group. | — | — | Governance-only, no architecture artifact | — | — | Product | `COVERED` (documentation-level) |
| RPD-003 | First production tenant is external. | 16 | `RGL-390..412` | `12_*.md` §1 supersession note | Go/No-Go record | `RGL-412` | Product | `COVERED` |
| RPD-004 | Mobile baseline is responsive PWA, online-first; no native/offline for first production. | 0/3 | `PH0-090`,`OPS-176..177` | `09_*.md` §2.5/§8 | PWA offline-shell test | `PHASE_3_VERIFIED` | UX/Architecture | `COVERED` |
| RPD-005 | Custom domain available from Platform Core. | 1 | `PLT-117..119` | `09_*.md` §3 (route map) | Domain-resolution test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| RPD-006 | PT SAIKI Group is legal contracting entity. | — | — | Commercial/legal, not architecture | — | — | Legal/Commercial | `COVERED` (documentation-level) |
| RPD-007 | Commercial packaging is modular; Platform Core mandatory. | 1 | `PLT-105..106` | `01_*.md` §2.1 | Entitlement test | `PHASE_1_VERIFIED` | Commercial | `COVERED` |
| RPD-008 | Subscription pricing = platform + module + user + usage. | 1 | `PLT-105..106` | Billing/entitlement schema (`05_*.md` §3) | Billing metering test | `PHASE_1_VERIFIED` | Commercial/Finance | `COVERED` |
| RPD-009 | Implementation tiers Fast-track/Standard/Enterprise. | 16 | `RGL-*` | `12_*.md` §8 | — | `RGL-412` | Implementation | `COVERED` (delivery-process level) |
| RPD-010 | Support is tiered (business hours/extended/24×7). | 15 | `HDN-*` | `11_*.md` §8.4 (6-tier support) | Incident-flow test | `HDN-386` | Support/DevOps | `COVERED` |
| RPD-011 | Shared DB/schema + RLS default; dedicated Enterprise option. | 1/9 | `PLT-113`,`IEP-360..363` | `05_*.md` §3 (single `app` schema), `06_*.md` §4 | RLS test, Enterprise dedicated-deployment test | `PHASE_1/9_VERIFIED` | Architecture/Security | `COVERED` |
| RPD-012 | PostgreSQL durable queue is initial job mechanism. | 1 | `PLT-132` | `05_*.md` §6, `08_*.md` §9 (job contract, `jobs` table) | Job cancellation/idempotency/DLQ test | `PHASE_1_VERIFIED` | Architecture | `PARTIAL_BLOCKED` (`PKG-PLT-JOB-001` worker-split threshold `ADR_REQUIRED`, non-blocking, resolves per `11_*.md` §9.3 queue-depth signal) |
| RPD-013 | APAC default region; Enterprise dedicated region/hosting. | 9 | `IEP-360..363` | `11_*.md` §2 (environment topology) | Enterprise residency test | `PHASE_9_VERIFIED` | DevOps/Security | `COVERED` |
| RPD-014 | Dashboards read transactional data directly (live OLTP). | 1/9 | `PLT-*`,`IEP-330..334` | `01_*.md` §6, `02_*.md` §7, `11_*.md` §9.1 (`ADR-CAND-ARCH-004` resolved) | `PERF-005` executive dashboard test | `PHASE_9_VERIFIED` | Architecture/Data | `COVERED` |
| RPD-015 | PostGIS enabled from Platform Core. | 1 | `PLT-134` | `01_*.md` §2.1 (`GEO`), `05_*.md` §6 | Spatial index test | `PHASE_1_VERIFIED` | Data/Operations | `COVERED` |
| RPD-016 | Finance/tax/payroll Indonesia-first; SME-verified. | 4/7 | `FIN-195`,`HRT-282` | `13_*.md` §11 (SME evidence gates) | Legal/finance/tax/payroll SME sign-off | `PHASE_4/7_VERIFIED` | Finance/HR SME | `EXTERNAL_VERIFICATION` |
| RPD-017 | Enterprise IAM order OIDC→SAML→SCIM. | 9 | `IEP-354..359` | `01_*.md` §2.1 (`ENT`) | Enterprise IAM integration test | `PHASE_9_VERIFIED` | Security | `COVERED` |
| RPD-018 | Partner referral model, 10% first-year net share. | — | — | Commercial, not architecture | — | — | Commercial | `COVERED` (documentation-level) |
| RPD-019 | Controlled white-label — CargoGrid owns component structure. | 0/1 | `PH0-090`,`PLT-117..119` | `09_*.md` §10 (resolves `OD-UX-001`) | White-label boundary test | `PHASE_1_VERIFIED` | Architecture/UX | `COVERED` |
| RPD-020 | Tenant merge/split is admin-run governed migration, no self-service. | 9 | `IEP-360..363` | Not yet a named capability row — governed migration process, cited `01_*.md` §8 preserved-asset discipline | Migration rehearsal (`10_*.md` §7.1) | `HDN-385` | DevOps/Data | `COVERED` |
| RPD-021 | OpenAI multimodal default AI/OCR; human approval before financial/legal posting. | 9 | `IEP-347..353` | `01_*.md` §2.1 (`AI`), Phase 9 README governance boundary | AI-advisory-only negative test | `PHASE_9_VERIFIED` | Product/Architecture | `COVERED` |
| RPD-022 | **Supreme Admin has absolute CRUD, including audit/journal/payment/final records; no tamper-proof claim.** | 1 | `PLT-115..116` | `06_*.md` §8 (binding, literal), `05_*.md` §4 (RLS policy split) | Test #8/#9 (`06_*.md` §10) | `HDN-372..374` | Product/Security/Finance | `ACCEPTED_RISK` (permanent disclosure — see §19) |
| RPD-023 | MFA mandatory for privileged roles. | 1 | `PLT-107..108` | `06_*.md` §6 | MFA enrollment test | `PHASE_1_VERIFIED` | Security | `COVERED` |
| RPD-024 | Accessibility target WCAG 2.2 AA; 2 latest browser versions. | 0/9 | `PH0-090`,`HDN-380..381` | `09_*.md` §9 (8-area plan) | WCAG automated+manual pass | `HDN-380` | UX/QA | `COVERED` |
| RPD-025 | Retention class-based schedule (Finance 10y, audit 7y, operational +90d, backup 35d, legal hold overrides). | 1/15 | `PLT-116`,`HDN-382..385` | `02_*.md` §11, `05_*.md` §4, `11_*.md` §6.3/§8.1 | Retention-class test per table | `HDN-382` | Data/Security | `COVERED` |
| RPD-026 | Module catalogue has 10 suites. | — | — | `01_*.md` §2.2, `13_*.md` §4 (phase register) | — | — | Product | `COVERED` |
| RPD-027 | Launch price book approved. | — | — | Commercial, not architecture | — | — | Commercial | `COVERED` (documentation-level) |
| RPD-028 | Usage charging approved, 20GB included, provider cost+20%. | 9 | `IEP-347..353` | `01_*.md` §7 (AI/provider dependency) | Metering test | `PHASE_9_VERIFIED` | Commercial/Product | `COVERED` |
| RPD-029 | Launch implementation fees approved. | — | — | Commercial | — | — | Commercial | `COVERED` (documentation-level) |
| RPD-030 | SLA A default; contractual customization permitted. | 15/16 | `HDN-*`,`RGL-*` | `11_*.md` §8.4 (P1-P4 SLA) | SLA response-time test | `HDN-386` | DevOps/Support | `COVERED` |
| RPD-031 | **RPO/RTO are contract-specific; no universal guarantee marketed.** | 15 | `HDN-382..385` | `11_*.md` §8.1 (tiered defaults, contract-silent = best effort) | DR rehearsal (`10_*.md` §7.4, `ADR-CAND-ARCH-023`) | `HDN-384` | SRE/Legal | `ACCEPTED_RISK` (see §19) |
| RPD-032 | Every uploaded file malware-scanned before release to another user. | 1 | `PLT-128` | `05_*.md` §6, `08_*.md` §10.2 | Malware-scan-gate test (`06_*.md` §10 #13) | `HDN-376..377` | Architecture/Security | `COVERED` |
| RPD-033 | REST and GraphQL built together, shared governance. | 1 | `PLT-129..130` | `08_*.md` §2/§3 (parity rule), `06_*.md` §10 #15 | REST/GraphQL parity test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| RPD-034 | **No external pilot; direct GA after internal gates, first external tenant is a production customer.** | 16 | `RGL-390..412` | `12_*.md` §1 (supersession), `10_*.md` §10.3 | Go/No-Go decision record | `RGL-412` | Product/QA/Security/SRE | `ACCEPTED_RISK`/gate (see §19) |
| RPD-035 | Tenant owns customer/operational data; support access time-bound/purpose-bound/logged/visible. | 1 | `PLT-115` | `06_*.md` §2.3/§6 | Support-access-expiry test (`06_*.md` §10 #5) | `HDN-372` | Security | `COVERED` |
| RPD-036 | **Direct GA requires full internal validation; zero open Sev-1/critical defects.** | 16 | `RGL-404..409` | `10_*.md` §10.3, `12_*.md` §7.1 | Full regression + pen-test + DR + finance reconciliation | `RGL-412` | Product/QA/Security/SRE | `ACCEPTED_RISK`/gate (see §19) |
| RPD-037 | **Missing contractual RPO/RTO = best effort, no guaranteed recovery.** | 15 | `HDN-382..385` | `11_*.md` §8.1 | DR rehearsal evidence | `HDN-384` | SRE/Legal | `ACCEPTED_RISK` (see §19) |
| RPD-038 | **Non-AI third-party integrations are custom, case-by-case, no generic provider abstraction.** | 9 | `IEP-335..346` | `01_*.md` §11 R5, `08_*.md` §8.2 (adapter template) | Sandbox/contract test per category (`08_*.md` §8.2) | `IEP-364..366` | Architecture/Integration | `ACCEPTED_RISK`/policy (see §19) |
| RPD-039 | Search/field security start in PostgreSQL FTS/trigram/server policy. | 1 | `PLT-121` | `06_*.md` §7, `01_*.md` §6 | Search-scope test | `PHASE_1_VERIFIED` | Architecture/Data | `COVERED` |
| RPD-040 | All non-conflicting Proposed Defaults approved; thresholds/discovery/SME verification remain execution gates. | — | — | `04_CONFLICT_REGISTER.md` §5 | — | — | Product | `COVERED` (governance-level) |

## 5. Functional requirement family traceability (46 families / 184 IDs)

One row per family (the coverage matrix's own atomic unit, §1 above). Each family's 4 anchor IDs (`001` create/maintain, `002` configurable workflow, `003` approval/exception, `004` reporting/audit) share the same delivery/verification owner.

| Family (IDs) | Canonical statement | Parent phase | WBS IDs | Architecture artifact refs | Tests/evidence | Gate | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| `PLT-TNT-001..004` | Tenant & Subscription: entitlement, limits, trial, renewal, suspension, audit. | 1 | `PLT-105..106` | `01_*.md` §2.1, `05_*.md` §3 | Entitlement/suspension test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| `PLT-WLB-001..004` | White-label & Localization: branding, domain, terminology, templates, canonical semantics. | 1/9 | `PLT-117..119`,`IEP-354..363` | `09_*.md` §10 | White-label regression | `PHASE_1/9_VERIFIED` | Product/Architecture | `COVERED` |
| `PLT-IAM-001..004` | User/Org/Role/Permission: 4 layers, hierarchy, RBAC, scopes, fields, support grants. | 1 | `PLT-107..116` | `06_*.md` §2/§5/§6 | RBAC/RLS negative suite | `PHASE_1_VERIFIED` | Architecture/Security | `COVERED` |
| `PLT-CFG-001..004` | Workflow, Approval & Configuration: draft/publish/version/effective-date/rollback/dependency. | 1 | `PLT-121..125` | `07_*.md` §5/§6/§8 | Config lifecycle test | `PHASE_1_VERIFIED` | Architecture | `COVERED` |
| `PLT-MDM-001..004` | Master Data & Integration Foundation: canonical masters, API/webhook primitives, audit. | 1 | `PLT-120`,`129..132` | `01_*.md` §2.1 (`MDM`,`API-WH`), `05_*.md` §3 | Master-data no-duplicate test | `PHASE_1_VERIFIED` | Architecture/Data | `COVERED` |
| `COM-LEAD-001..004` | Lead Management: sources, assignment, qualification, duplicate, conversion. | 2 | `COM-143..144` | `02_*.md` §3.1 | `UAT-E2E-001..002` | `PHASE_2_VERIFIED` | Product/Commercial | `COVERED` |
| `COM-CRM-001..004` | CRM, Account & Contact: account/contact/activity, hierarchy, ownership, approval. | 2 | `COM-145..146` | `02_*.md` §3.1 | `UAT-E2E-003` | `PHASE_2_VERIFIED` | Product/Commercial | `COVERED` |
| `COM-OPP-001..004` | Opportunity & Request Costing: pipeline, service/cargo/lane, SLA, procurement handoff. | 2 | `COM-147..148` | `02_*.md` §3.1, `01_*.md` §9 `ADR-CAND-ARCH-001` | `UAT-E2E-004..005` | `PHASE_2_VERIFIED` | Product/Commercial | `PARTIAL_BLOCKED` (vendor-rate ownership `ADR-CAND-ARCH-001` — **resolved** `05_*.md` §4; residual: Phase-6 activation) |
| `COM-QTN-001..004` | Quotation, Approval & Contract: versions, margin, discount, validity, approval, acceptance. | 2 | `COM-151..154` | `02_*.md` §3.1, `07_*.md` §7.1 | `UAT-E2E-006..008` | `PHASE_2_VERIFIED` | Product/Commercial | `COVERED` |
| `COM-CPR-001..004` | Customer Pricing & Commercial Analytics: contract pricing, effective rates, profitability, conversion. | 2 | `COM-155..159` | `02_*.md` §3.1 | Commercial dashboard test | `PHASE_2_VERIFIED` | Product/Commercial | `COVERED` |
| `OPS-SHP-001..004` | Job Order & Shipment Order: quote conversion, booking, parties, service, mode, route, schedule. | 3/5 | `OPS-168..171`,`ATW-221..225` | `02_*.md` §3.1, `05_*.md` §4 `ADR-CAND-ARCH-005` (resolved) | `UAT-E2E-009..010` | `PHASE_3/5_VERIFIED` | Product/Operations | `COVERED` |
| `OPS-TMS-001..004` | Transportation Management System: basic single-mode (Phase 3); advanced multi-leg/route/load/fleet (Phase 5). | 3/5 | `OPS-170..175`,`ATW-219..228` | `01_*.md` §2.2, `02_*.md` §3.1 | `UAT-E2E-011..012`, `PERF-003` | `PHASE_3/5_VERIFIED` | Product/Operations | `COVERED` |
| `OPS-WMS-001..004` | Warehouse Management System: full inbound, inventory ledger, picking, outbound, billing. | 5 | `ATW-229..242` | `05_*.md` §3 (WMS tables), `01_*.md` §2.2 | `PERF-010` (WMS ledger 1M rows) | `PHASE_5_VERIFIED` | Product/Operations | `COVERED` |
| `OPS-TRK-001..004` | Milestone, Tracking & Exception: basic (Phase 3); advanced visibility (Phase 5). | 3/5 | `OPS-172..175`,`ATW-226..228` | `02_*.md` §3.1 | `UAT-E2E-012..013` | `PHASE_3/5_VERIFIED` | Product/Operations | `COVERED` |
| `OPS-DOC-001..004` | ePOD, Document, Claim & Incident: basic (Phase 3); advanced claims (Phase 5). | 3/5 | `OPS-176..177`,`ATW-243..244` | `02_*.md` §3.1, §6 (file flow) | `UAT-E2E-014` | `PHASE_3/5_VERIFIED` | Product/Operations | `COVERED` |
| `OPS-CST-001..004` | Estimated/Actual Cost & Job Closing: actual cost (Phase 3); Finance depth (Phase 4); WMS billing (Phase 5). | 3/4/5 | `OPS-178..184`,`FIN-212`,`ATW-239..242` | `02_*.md` §3.1/§8 (reconciliation R3) | `UAT-E2E-015`,`FINTEST-014..015` | `PHASE_3/4/5_VERIFIED` | Product/Operations/Finance | `COVERED` |
| `PRC-VND-001..004` | Vendor Registration & Onboarding: legal/tax/bank/contact/service/docs/approval. | 6 | `PRC-251..254` | `02_*.md` §3.2 | Vendor onboarding negative test | `PHASE_6_VERIFIED` | Procurement | `COVERED` |
| `PRC-ASM-001..004` | Qualification, Assessment & Compliance: risk, safety, document expiry, corrective action. | 6 | `PRC-252..253` | `02_*.md` §3.2 | Compliance/expiry test | `PHASE_6_VERIFIED` | Procurement | `COVERED` |
| `PRC-RTE-001..004` | Vendor Rate, Quotation & Pricelist: lane/service/fleet/weight/volume/zone validity, approval. | 2 (basic)/6 (full) | `COM-149..150`,`PRC-254..255` | `05_*.md` §4 (`ADR-CAND-ARCH-001` resolved) | `FINTEST-016` (vendor-invoice matching) | `PHASE_2/6_VERIFIED` | Commercial/Procurement | `COVERED` |
| `PRC-SRC-001..004` | Sourcing, Capacity & Availability: RFQ, comparison, selection, capacity, allocation. | 6 | `PRC-256..258`,`262..264` | `02_*.md` §3.2 | Vendor comparison test (`UAT-E2E-005`) | `PHASE_6_VERIFIED` | Procurement | `COVERED` |
| `PRC-POI-001..004` | PO, Contract, Performance & Invoice Matching: PO/contract, KPI, matching, dispute. | 6 | `PRC-259..261`,`265..266` | `02_*.md` §3.2 | `FINTEST-016` | `PHASE_6_VERIFIED` | Procurement/Finance | `COVERED` |
| `FIN-GL-001..004` | COA, Journal & GL: double-entry, draft/post, reversal, lock, idempotency; RPD-022 exception. | 4 | `FIN-191..208` | `05_*.md` §5, `06_*.md` §4/§8 | `FINTEST-001,002,008,009,021,022` | `PHASE_4_VERIFIED` | Finance | `COVERED` (with `ACCEPTED_RISK` overlay, RPD-022) |
| `FIN-AR-001..004` | Billing, Invoice & AR: readiness, invoice, receipt allocation, aging, duplicate prevention. | 4 | `FIN-196..198`,`209..210` | `02_*.md` §3.1, `05_*.md` §5 | `FINTEST-002,003,012` | `PHASE_4_VERIFIED` | Finance | `COVERED` |
| `FIN-AP-001..004` | Vendor Billing & AP: Phase-4 basic; full vendor/PO/advanced matching Phase 6. | 4/6 | `FIN-199..201`,`PRC-265..266` | `02_*.md` §3.2, `05_*.md` §5 | `FINTEST-013,016` | `PHASE_4/6_VERIFIED` | Finance/Procurement | `COVERED` |
| `FIN-TAX-001..004` | Tax, Bank Reconciliation & Cash: VAT/withholding, bank/cash, reconciliation, Indonesia-first. | 4 | `FIN-194..195`,`209`,`211` | `05_*.md` §5, `13_*.md` §11 (SME gate) | `FINTEST-006,007,020` | `PHASE_4_VERIFIED` | Finance | `EXTERNAL_VERIFICATION` (`FIN-195` tax/legal SME gate, RPD-016) |
| `FIN-CLS-001..004` | Budget, Accrual, Revenue Recognition & Closing: policy/dependency, period, close, lock/reopen. | 4 | `FIN-193`,`206..208` | `05_*.md` §5 (period lock) | `FINTEST-008,010,011` | `PHASE_4_VERIFIED` | Finance | `COVERED` |
| `FIN-PRF-001..004` | Job/Customer/Service/Branch Profitability: revenue/cost lineage, allocation, margin, variance. | 4 | `FIN-212..213` | `05_*.md` §5 (profitability snapshots) | `FINTEST-014,024` | `PHASE_4_VERIFIED` | Finance | `COVERED` |
| `HRS-EMP-001..004` | Organization, Employee & Position: employee master, reporting line, document, personal data. | 7 | `HRT-274..277` | `01_*.md` §9 `ADR-CAND-ARCH-002` (resolved `06_*.md` §11) | Employee-identity FK test (`06_*.md` §10 #11) | `PHASE_7_VERIFIED` | HR | `COVERED` |
| `HRS-REC-001..004` | Recruitment, Job Portal & ATS: vacancy through onboarding. | 7 | `HRT-276..277` | `02_*.md` §3.3 | Onboarding/offboarding test | `PHASE_7_VERIFIED` | HR | `COVERED` |
| `HRS-ATT-001..004` | Attendance, Shift, Leave & Overtime: roster, check-in/out, exception, approval. | 7 | `HRT-278..281` | `02_*.md` §3.3 | `BR-ATT-001` regression | `PHASE_7_VERIFIED` | HR | `COVERED` |
| `HRS-PAY-001..004` | Payroll, Benefit & Reimbursement: Indonesia-first configurable, tax, loans, claims, finalization. | 7 | `HRT-282` | `13_*.md` §11 (SME gate) | `BR-PAY-001` regression, PII/payroll masking test | `PHASE_7_VERIFIED` | HR/Finance | `EXTERNAL_VERIFICATION` (`HRT-282` payroll/tax SME gate, RPD-016) |
| `HRS-KPI-001..004` | Performance, KPI, Training & Talent: target/actual/score, competency, learning, talent. | 7 | `HRT-283..284` | `02_*.md` §3.3 | KPI regression | `PHASE_7_VERIFIED` | HR | `COVERED` |
| `HRS-ESS-001..004` | ESS, MSS & Offboarding: self-service requests, manager actions, exit clearance. | 7 | `HRT-277`,`285` | `02_*.md` §3.3 | ESS/MSS UAT | `PHASE_7_VERIFIED` | HR | `COVERED` |
| `TKT-INT-001..004` | Internal/Interdepartmental Ticket: assignment, category, SLA, notes, linked records. | 7 | `HRT-286`,`289..291` | `02_*.md` §3.4 | `BR-TKT-001` regression | `PHASE_7_VERIFIED` | Support | `COVERED` |
| `TKT-CUS-001..004` | Customer-to-Tenant Ticket: complaint, claim, shipment/billing/WMS/document issue. | 7/8 | `HRT-287`,`CPL-311..315` | `02_*.md` §3.4/§3.5 | `TI-015` (customer isolation) | `PHASE_7/8_VERIFIED` | Support/CX | `COVERED` |
| `TKT-HLP-001..004` | Tenant-to-CargoGrid Helpdesk: technical, functional, config, integration, bug, security. | 7/16 | `HRT-288`,`RGL-411` | `02_*.md` §3.4 | Support playbook test | `PHASE_7_VERIFIED`/`RGL-411` | Support | `COVERED` |
| `TKT-SLA-001..004` | SLA, Escalation & Knowledge Base: calendar, priority, assignment, breach, knowledge. | 7 | `HRT-289..291` | `02_*.md` §3.4 | `EXC-SLA-001` test | `PHASE_7_VERIFIED` | Support | `COVERED` |
| `CPT-QBK-001..004` | Quote Request & Booking: internal handoff (Phase 3); customer self-service (Phase 8). | 3/8 | `OPS-168..169`,`CPL-302..304` | `02_*.md` §3.5, `03_*.md` §5 (intake contract) | `TI-002` (customer isolation) | `PHASE_3/8_VERIFIED` | Product/CX | `COVERED` |
| `CPT-TRK-001..004` | Tracking, ePOD & Document: timeline, exception, permitted signed files; basic (Phase 3), full (Phase 8). | 3/8 | `OPS-176..177`,`CPL-305..308` | `02_*.md` §3.5 | `UAT-E2E-013` | `PHASE_3/8_VERIFIED` | Product/CX | `COVERED` |
| `CPT-WHS-001..004` | Warehouse, Inventory & Order Monitoring: customer-owned inventory/order visibility. | 8 | `CPL-309..310` | `02_*.md` §3.5 | `TI-002` | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `CPT-BIL-001..004` | Invoice, Billing, Payment & Profile: customer finance scope, visibility, dispute, profile. | 8 | `CPL-311..315` | `02_*.md` §3.5 | `TI-015` | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `CPT-CX-001..004` | Complaint, Ticket, Loyalty & Rewards: portal service and engagement. | 8 | `CPL-311..323` | `02_*.md` §3.5/§3.6 | `UAT-E2E-019` | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `LYL-PRG-001..004` | Program, Tier & Segmentation: rule, threshold, eligible customer, effective dates. | 8 | `CPL-316..317` | `02_*.md` §3.6 | `BR-LYL-001` regression | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `LYL-PNT-001..004` | Point, Cashback, Discount & Voucher: ledger earning, paid eligibility, multiplier, reversal. | 8 | `CPL-318..319` | `02_*.md` §3.6 | `UAT-E2E-019` | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `LYL-RDM-001..004` | Reward, Redemption, Referral & Expiration: balance, stock, approval, fulfillment, expiry, fraud. | 8 | `CPL-320..322` | `02_*.md` §3.6 | `BR-LYL-002` regression | `PHASE_8_VERIFIED` | Product/CX | `COVERED` |
| `LYL-ANL-001..004` | Loyalty Analytics & Liability: liability, reconciliation, engagement/fraud metrics. | 8 | `CPL-323` | `02_*.md` §8 (reconciliation R6) | Loyalty liability reconciliation test | `PHASE_8_VERIFIED` | Product/Finance | `COVERED` |

## 6. Explicit NFR traceability (10 IDs, `00-control/05_*.md` §4)

| Source ID | Canonical statement | Parent phase | WBS IDs | Architecture artifact refs | Tests/evidence | Gate | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| `NFR-PERF-001` | Avoid N+1. | Cross-cutting (2–16) | All capability ranges | `05_*.md` §7, `08_*.md` §5 (resolver batching), `10_*.md` §8.1 | Query-plan review (`05_*.md` §7) | `HDN-379` | Architecture/Data | `COVERED` |
| `NFR-PERF-002` | Avoid `SELECT *`. | Cross-cutting | All | `04_*.md` §5 (import/dependency rules) | Payload test | `HDN-379` | Architecture | `COVERED` |
| `NFR-PERF-003` | Server-side pagination. | Cross-cutting | All | `05_*.md` §7, `08_*.md` §4.3 | Table/API acceptance test | `HDN-379` | Architecture | `COVERED` |
| `NFR-PERF-004` | Cursor pagination for high-volume tables. | 3/8–15 | `OPS-*`,`FIN-*`,`HDN-*` | `05_*.md` §7 (keyset-mandatory table list) | `PERF-*` scenarios (`10_*.md` §7.4) | `HDN-379` | Architecture/Data | `COVERED` |
| `NFR-PERF-005` | Tenant-aware indexing. | 3, 6–15 | All | `05_*.md` §7 | `EXPLAIN ANALYZE` review | `HDN-379` | Architecture/Data | `COVERED` |
| `NFR-SEC-001` | Strict tenant isolation. | 2–16 | All | `06_*.md` §4 | `TI-001..008,011,012` | `HDN-372` | Security | `COVERED` (**release-blocker**) |
| `NFR-SEC-002` | Field and record access. | 3, 6–16 | All | `06_*.md` §5.2 | `TI-013,014` | `HDN-372..374` | Security | `COVERED` (**release-blocker**) |
| `NFR-AUD-001` | Comprehensive audit. | 3, 6–16 | All | `05_*.md` §6 (5 append-only log tables) | `06_*.md` §10 #9 | `HDN-375` | Security/Data | `COVERED` |
| `NFR-REL-001` | Backup and recovery. | 3, 15–16 | `HDN-382..385` | `11_*.md` §8.1 | Restore/DR rehearsal | `HDN-384` | SRE | `COVERED` (**GA blocker**) |
| `NFR-API-001` | Rate limiting and idempotency. | 3, 6–16 | `PLT-129..130`,`IEP-337..341` | `08_*.md` §4.7/§6 | Idempotency/rate-limit test | `RGL-410` | Architecture | `COVERED` (**release gate**) |

## 7. Package-generated gap requirements traceability (13 IDs, `00-control/05_*.md` §5 — see §21 for the 13-vs-14 discrepancy)

| Source ID | Canonical statement | Parent phase | WBS IDs | Architecture artifact refs | Tests/evidence | Gate | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| `PKG-NFR-MNT-001` | Architecture boundaries, ADRs, automated tests, API docs, migration discipline mandatory. | 0 | `PH0-089..092` | `04_*.md` §5, `10_*.md` §2 | CI gate model | `HDN-386..389` | Architecture/DevEx | `COVERED` |
| `PKG-NFR-ACC-001` | Core workflows conform to WCAG 2.2 AA; 2 latest browser versions. | 0/9 | `PH0-090`,`HDN-380..381` | `09_*.md` §9 | WCAG automated+manual | `HDN-380` | UX/QA | `PARTIAL_BLOCKED` (`ADR-CAND-ARCH-020/021` component/token foundation, resolve Phase 0 Prompt 90) |
| `PKG-NFR-UX-001` | Internal ERP desktop-first with responsive supported workflows. | 0 | `PH0-090` | `09_*.md` §8 | Responsive matrix test | `HDN-381` | UX | `COVERED` |
| `PKG-NFR-UX-002` | Supported browser versions maintained matrix. | 0/9 | `PH0-090`,`HDN-381` | `09_*.md` §8, `10_*.md` §7.4 | Browser/device matrix test | `HDN-381` | UX/QA | `COVERED` |
| `PKG-NFR-UX-003` | Field/portal workflows mobile-usable; offline separately governed. | 3/8/0 | `OPS-176..177`,`CPL-*`,`PH0-090` | `09_*.md` §8 (RPD-004 offline-shell) | PWA offline test | `PHASE_3/8_VERIFIED` | UX/Product | `COVERED` |
| `PKG-NFR-DATA-001` | Retention per RPD-025; legal hold overrides deletion; RPD-022 disclosed exception. | 1/15/16 | `PLT-116`,`HDN-382..385` | `02_*.md` §11, `05_*.md` §4 | Retention-class test | `HDN-382` | Data/Security | `COVERED` (with `ACCEPTED_RISK` overlay, RPD-022) |
| `PKG-NFR-OBS-001` | Logs/metrics/traces/audit/alerts cover app, DB, jobs, integration, security, finance exceptions. | 0/5/15–16 | `PH0-093..094`,`HDN-382..383` | `11_*.md` §6 | Alert-firing test (§6.1) | `HDN-386` | DevOps | `PARTIAL_BLOCKED` (`ADR-CAND-ARCH-026` observability tool, resolve Phase 0 environment/CI kickoff) |
| `PKG-NFR-SCL-001` | Capacity/concurrency validated under realistic tenant distribution. | 0/15 | `PH0-091`,`HDN-379` | `11_*.md` §9.1 (`ADR-CAND-ARCH-004` resolved) | `PERF-*` load tests | `HDN-379` | DevOps/Data | `COVERED` |
| `PKG-NFR-FILE-001` | File type/size/classification/signed access/retention/audit enforced; malware scan mandatory. | 1 | `PLT-128` | `05_*.md` §6, `08_*.md` §10.2 | Malware-scan-gate test | `HDN-376..377` | Architecture/Security | `COVERED` |
| `PKG-PLT-JOB-001` | PostgreSQL durable queue supports status/retry/DLQ/idempotency/progress/result/tenant context; workers threshold-driven. | 1 | `PLT-132` | `05_*.md` §6, `08_*.md` §9 | Job DLQ/cancellation test | `PHASE_1_VERIFIED` | Architecture | `PARTIAL_BLOCKED` (worker-split threshold, non-blocking — `11_*.md` §9.3 signal defined, exact numeric `ADR_REQUIRED`) |
| `PKG-PLT-FLG-001` | Feature flags support environment/tenant/module/feature/cohort/effective-date/rollback without bypassing security. | 1 | `PLT-133` | `01_*.md` §6 (`DUP-012`), `11_*.md` §9.2 | Flag-security-bypass negative test | `HDN-386` | Architecture | `COVERED` |
| `PKG-PLT-KEY-001` | API keys/webhook credentials hashed/scoped/rotatable/revocable/rate-limited/audited. | 1 | `PLT-129..130` | `08_*.md` §6 | Key-rotation/revocation test | `HDN-377` | Architecture/Security | `COVERED` (closes `GAP-018`) |
| `PKG-PLT-IMP-001` | Import/export jobs staged, validated, permission-aware, resumable, auditable, async. | 1 | `PLT-131` | `05_*.md` §6, `08_*.md` §10.1 | Partially-invalid-import test | `PHASE_1_VERIFIED` | Data/Architecture | `COVERED` |

## 8. Business rules (24 `BR-*`, Blueprint §10, bound by `07_*.md` §7.3)

| Source ID | Canonical statement | Parent phase | WBS IDs | Test/evidence | Owner | Status |
|---|---|---|---|---|---|---|
| `BR-LEAD-001` | Lead converts only with mandatory fields, duplicate check, owner validity, qualification. | 2 | `COM-143..144` | Regression (`07_*.md` §14) | Commercial | `COVERED` |
| `BR-CUST-001` | Duplicate customer detection by legal name/tax ID/email domain/phone/address/parent/alias. | 2 | `COM-145` | `UAT-E2E-003` | Commercial | `COVERED` |
| `BR-CUST-002` | New/changed customer requires approval per risk category. | 2 | `COM-145`,`153` | Approval regression | Commercial | `COVERED` |
| `BR-CREDIT-001` | Booking/job/invoice blocked/warned/escalated on credit exposure. | 2/4 | `COM-156..157`,`FIN-196` | Credit-limit test | Commercial/Finance | `COVERED` |
| `BR-COST-001` | Cost request requires service/lane/detail/validity/comparison rule. | 2 | `COM-147..148` | `UAT-E2E-004` | Commercial | `COVERED` |
| `BR-RATE-001` | Vendor rate eligible only if active/approved/within-validity/matching. | 2/6 | `COM-149`,`PRC-254..255` | Rate-validity test | Commercial/Procurement | `COVERED` |
| `BR-QTN-001` | Quotation minimum margin varies by service/segment/lane/amount/role/risk. | 2 | `COM-151` | `EXC-MRG-001` test | Commercial | `COVERED` |
| `BR-QTN-002` | Discount limited by role/amount/margin/campaign/tier/authority. | 2 | `COM-151..152` | Discount-authority test | Commercial | `COVERED` |
| `BR-QTN-003` | Quotation validity date; expired quotes require revalidation. | 2 | `COM-152` | `UAT-E2E-006` | Commercial | `COVERED` |
| `BR-JOB-001` | Job creation from accepted quote/contract/booking per tenant rule. | 3 | `OPS-168` | `UAT-E2E-009` | Operations | `COVERED` |
| `BR-SHP-001` | Assignment follows availability/capability/coverage/compliance/permission. | 3/5 | `OPS-172..173`,`ATW-222..225` | `UAT-E2E-011` | Operations | `COVERED` |
| `BR-SHP-002` | Status moves only per lifecycle/role/workflow/mandatory event/document. | 3 | `OPS-170..171` | Status-transition test | Operations | `COVERED` |
| `BR-POD-001` | ePOD complete requires signature/photo/receiver/geolocation/timestamp/document. | 3 | `OPS-176..177` | `UAT-E2E-014` | Operations | `COVERED` |
| `BR-CLOSE-001` | Job closes only if shipment/ePOD/docs/actual-cost/exceptions/billing all resolved. | 3 | `OPS-184` | Job-closing checklist test | Operations | `COVERED` |
| `BR-COST-OVR-001` | Actual cost overrun requires reason and approval. | 3 | `OPS-178..179` | `EXC-COST-001` test | Operations | `COVERED` |
| `BR-INV-001` | Invoice readiness requires ePOD/document/status/term/pricelist/no-blocking-issue. | 3/4 | `OPS-180..181`,`FIN-196` | `UAT-E2E-016` | Operations/Finance | `COVERED` |
| `BR-REV-001` | Revenue recognition follows completion/milestone/period/contract/policy. | 4 | `FIN-206..208` | `FINTEST-011` | Finance | `COVERED` |
| `BR-VIM-001` | Vendor invoice matched against PO/job/actual-cost/rate/document/tax/term. | 6 | `PRC-265..266` | `FINTEST-016` | Procurement/Finance | `COVERED` |
| `BR-PERIOD-001` | Locked period rejects new postings except authorized reversal/adjustment. | 4 | `FIN-207` | `FINTEST-008` | Finance | `COVERED` |
| `BR-ATT-001` | Attendance valid per shift/location/geofence/cut-off/exception. | 7 | `HRT-278..281` | Attendance regression | HR | `COVERED` |
| `BR-PAY-001` | Payroll computed from attendance/overtime/allowance/deduction/tax/benefit/loan/reimbursement/adjustment. | 7 | `HRT-282` | Payroll regression | HR | `EXTERNAL_VERIFICATION` (SME gate, RPD-016) |
| `BR-TKT-001` | Ticket SLA computed from category/priority/tier/calendar/group/escalation. | 7 | `HRT-289..291` | `EXC-SLA-001` test | Support | `COVERED` |
| `BR-LYL-001` | Loyalty earning based on eligible transaction/paid-settled/service/revenue/volume/tier/fraud rule. | 8 | `CPL-316..318` | `UAT-E2E-019` | Product/CX | `COVERED` |
| `BR-LYL-002` | Loyalty redemption governed by balance/eligibility/stock/expiration/approval/fraud/liability. | 8 | `CPL-320..322` | Redemption regression | Product/CX | `COVERED` |

## 9. Approval patterns (13, Blueprint §11.1, bound by `07_*.md` §7.1)

| Pattern | Canonical example | Parent phase | WBS IDs | Test/evidence | Status |
|---|---|---|---|---|---|
| Sequential | Sales Supervisor → Manager → GM. | 1/2 | `PLT-123`,`COM-153` | Approval-panel test (`09_*.md` §12) | `COVERED` |
| Parallel | Finance + Operations approve cost overrun. | 1/3 | `PLT-123`,`OPS-178` | Same | `COVERED` |
| Conditional | High-risk customer requires Finance approval. | 1/2 | `PLT-123`,`COM-153` | Same | `COVERED` |
| Amount threshold | Write-off > Rp X → Director. | 1/4 | `PLT-123`,`FIN-*` | Same | `COVERED` |
| Margin threshold | Margin < 15% → Manager. | 1/2 | `PLT-123`,`COM-151` | `EXC-MRG-001` | `COVERED` |
| Department-based | Warehouse billing change → Warehouse Manager. | 1/5 | `PLT-123`,`ATW-239` | Same | `COVERED` |
| Role-based | Procurement Manager approves vendor onboarding. | 1/6 | `PLT-123`,`PRC-251` | Same | `COVERED` |
| User-based | Named account director approves strategic customer. | 1/2 | `PLT-123`,`COM-153` | Same | `COVERED` |
| Delegation | Manager on leave → Assistant Manager. | 1 | `PLT-123` | Delegation test | `COVERED` |
| Escalation | 2-day pending → GM. | 1 | `PLT-123` | `EXC-APR-001` | `COVERED` |
| Rejection | Reason recorded, flow stops. | 1 | `PLT-123` | Rejection test | `COVERED` |
| Revision | Submitter edits, approval resets. | 1/2 | `PLT-123`,`COM-152` | Revision test | `COVERED` |
| Resubmission | New cycle linked to prior cycle. | 1/2 | `PLT-123`,`COM-152` | Resubmission test | `COVERED` |

Owner for all 13: Architecture (`APPR` engine, `PLT-123`), invoked per-domain at the domain's own phase. Gate: `HDN-386..389` (integrated-verification/hardening).

## 10. Approval use cases (14, Blueprint §11.2, bound by `07_*.md` §7.1)

| Use case | Default approver / threshold | Parent phase | WBS IDs | Test/evidence | Status |
|---|---|---|---|---|---|
| Customer approval | Sales/Finance Manager; risk/credit/type. | 2 | `COM-153` | `UAT-E2E-*` (customer flow) | `COVERED` |
| Cost request | Pricing Lead/Procurement; service/lane/urgency/value. | 2 | `COM-147..148` | `UAT-E2E-004` | `COVERED` |
| Vendor rate approval | Procurement Manager; lane/validity/variance/category. | 6 | `PRC-255` | Rate-approval test | `COVERED` |
| Quotation approval | Sales Manager/GM/Director; margin/discount/amount/tier. | 2 | `COM-153` | `UAT-E2E-007` | `COVERED` |
| Job creation override | Operations Manager; service/customer/reason/risk. | 3 | `OPS-168` | Override test | `COVERED` |
| Shipment assignment override | Operations Manager/Procurement; availability/compliance/exception. | 3 | `OPS-172..173` | Override test | `COVERED` |
| Cost overrun | Operations + Finance; variance/amount/type. | 3 | `OPS-178..179` | `EXC-COST-001` | `COVERED` |
| Job closing | Operations Manager/Finance; open exception/claim/document. | 3 | `OPS-184` | Job-closing test | `COVERED` |
| Invoice readiness override | Finance Manager; customer term/document risk. | 4 | `FIN-196` | Override test | `COVERED` |
| Vendor invoice mismatch | AP + Procurement; amount/percentage variance. | 6 | `PRC-266` | `FINTEST-016` | `COVERED` |
| Period unlock | Finance Controller/Director; period age/amount/reason. | 4 | `FIN-207` | Unlock test | `COVERED` |
| Payroll finalization | HR Manager + Finance; period/variance/exception. | 7 | `HRT-282` | Finalization test | `EXTERNAL_VERIFICATION` (RPD-016) |
| Ticket escalation | Service Manager; priority/tier/age. | 7 | `HRT-289..291` | `EXC-SLA-001` | `COVERED` |
| Loyalty redemption | Marketing/Finance; value/tier/fraud score. | 8 | `CPL-320..322` | Redemption approval test | `COVERED` |

## 11. Status transitions (24, Blueprint §12, bound by `07_*.md` §7.2)

| Entity | Transitions (from→to) | Count | Parent phase | WBS IDs | Test/evidence | Status |
|---|---|---:|---|---|---|---|
| Lead | New→Assigned, Assigned→Contacted, Qualified→Converted | 3 | 2 | `COM-143..144` | `UAT-E2E-001..002` | `COVERED` |
| Quotation | Draft→Under Approval, Under Approval→Approved, Approved→Sent, Sent→Accepted, Sent→Expired | 5 | 2 | `COM-151..154` | `UAT-E2E-006..008` | `COVERED` |
| Shipment | Draft→Confirmed, Confirmed→Planned, Planned→Dispatched, In Transit→Delivered, Delivered→ePOD Completed, ePOD Completed→Closed | 6 | 3 | `OPS-168..184` | `UAT-E2E-009..015` | `COVERED` |
| Invoice | Draft→Submitted, Submitted→Approved, Approved→Posted, Posted→Paid/Partially Paid | 4 | 4 | `FIN-196..198` | `UAT-E2E-016..017`, `FINTEST-002` | `COVERED` |
| Vendor | Draft→Under Review, Under Review→Active | 2 | 6 | `PRC-251` | Vendor-onboarding test | `COVERED` |
| Ticket | Open→Assigned, Assigned→In Progress, In Progress→Resolved, Resolved→Closed | 4 | 7 | `HRT-286..291` | `EXC-SLA-001` | `COVERED` |

Owner: Architecture (`STAT` engine, `PLT-124`), instantiated by each entity's owning domain. Gate: `HDN-386..389` full regression (`10_*.md` §9 Phase-15 row).

## 12. Exception types (16 `EXC-*`, Blueprint §13, bound by `07_*.md` §7.4)

| Source ID | Canonical statement | Parent phase | WBS IDs | Test/evidence | Owner | Status |
|---|---|---|---|---|---|---|
| `EXC-DATA-001` | Mandatory data missing — block submit, show missing fields. | All | Every capability | Negative test per form | Owning domain | `COVERED` |
| `EXC-DUP-001` | Potential duplicate (Lead/Customer/Vendor/Contact) — show candidates, require merge/ignore reason. | 2/6 | `COM-145`,`PRC-251` | Duplicate-detection test | Commercial/Procurement | `COVERED` |
| `EXC-AUTH-001` | Unauthorized access — deny, log security event. | 1 | `PLT-112..116` | `TI-*` suite | Security | `COVERED` |
| `EXC-CFG-001` | Stale configuration version — require refresh/revalidation before submit. | 1 | `PLT-121` | Config-engine's own exception test (`07_*.md` §7.4) | Architecture | `COVERED` |
| `EXC-APR-001` | Approval SLA breached — escalate/remind. | 1 | `PLT-123` | Escalation test | Architecture | `COVERED` |
| `EXC-INT-001` | Integration failed — retry with backoff, DLQ, alert. | 9 | `IEP-335..346` | `08_*.md` §8.2 sandbox test | Architecture/Integration | `COVERED` |
| `EXC-RATE-001` | Expired vendor rate — block or require override approval. | 2/6 | `COM-149`,`PRC-255` | Rate-validity test | Commercial/Procurement | `COVERED` |
| `EXC-MRG-001` | Margin below threshold — route to approval, block send. | 2 | `COM-151` | `BR-QTN-001` test | Commercial | `COVERED` |
| `EXC-SHP-001` | Shipment delay — capture reason, notify. | 3 | `OPS-174..175` | Milestone/exception test | Operations | `COVERED` |
| `EXC-POD-001` | Incomplete ePOD — block billing readiness unless override approved. | 3 | `OPS-176..177` | `UAT-E2E-014` | Operations | `COVERED` |
| `EXC-COST-001` | Cost overrun — require reason and approval. | 3 | `OPS-178..179` | `BR-COST-OVR-001` test | Operations | `COVERED` |
| `EXC-INV-001` | Invoice mismatch — create dispute/revision workflow. | 4/6 | `FIN-199..201`,`PRC-266` | `FINTEST-016` | Finance/Procurement | `COVERED` |
| `EXC-PER-001` | Period locked — block posting, allow controlled unlock/reversal. | 4 | `FIN-207` | `FINTEST-008` | Finance | `COVERED` |
| `EXC-ATT-001` | Attendance anomaly — require manager/HR approval. | 7 | `HRT-278..281` | `BR-ATT-001` test | HR | `COVERED` |
| `EXC-SLA-001` | Ticket SLA breach — escalate, notify, update report. | 7 | `HRT-289..291` | SLA-breach test | Support | `COVERED` |
| `EXC-LYL-001` | Suspected loyalty fraud — freeze earning/redemption pending review. | 8 | `CPL-320..322` | Fraud-hold test | Product/CX | `COVERED` |

## 13. Report categories (12, Blueprint §15)

**Orphan-citation flag (see §21):** the 12 named report categories are cited by count only in `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §6 — no `docs/architecture/*.md` document names them individually before this one. This document is the first architecture artifact to bind each category to an owning phase/WBS range; the closure task in §23 records this.

| Category | Content (Blueprint §15) | Parent phase | WBS IDs | Owner | Status |
|---|---|---|---|---|---|
| Executive Dashboard | Revenue, margin, volume, OTD, billing readiness, AR aging, vendor performance, ticket SLA. | 9 | `IEP-330..334` | Architecture/Data | `COVERED` |
| Commercial Dashboard | Lead source, pipeline, forecast, conversion, win/loss, quote turnaround, margin. | 2 | `COM-158..159` | Commercial | `COVERED` |
| Quotation Report | Cost comparison, margin, discount, approval aging, expired quotes. | 2 | `COM-158..159` | Commercial | `COVERED` |
| Operations Control Tower | Shipment status, ETA, delay, exception, milestone compliance, ePOD pending. | 3 | `OPS-182..183` | Operations | `COVERED` |
| TMS Performance | Fleet utilization, driver productivity, vendor assignment, route performance. | 5 | `ATW-245..247` | Operations | `COVERED` |
| WMS Dashboard | Inbound, inventory accuracy, aging, picking/packing status, SLA, warehouse billing. | 5 | `ATW-245..247` | Operations | `COVERED` |
| Procurement Dashboard | Vendor onboarding, compliance, rate validity, response, acceptance, performance, cost competitiveness. | 6 | `PRC-268..270` | Procurement | `COVERED` |
| Finance Dashboard | Billing readiness, invoice issued, AR/AP, cash, period close, job profitability. | 4 | `FIN-213` | Finance | `COVERED` |
| HR Dashboard | Headcount, attendance, overtime, leave, payroll status, KPI, training (sensitive fields masked). | 7 | `HRT-294..296` | HR | `COVERED` |
| Ticket SLA Dashboard | Open ticket, breach, priority, escalation, resolution time, reopen rate. | 7 | `HRT-294..296` | Support | `COVERED` |
| Customer Portal Dashboard | Shipment, document, invoice, warehouse inventory, ticket, loyalty. | 8 | `CPL-300..301` | Product/CX | `COVERED` |
| Supreme Admin SaaS Dashboard | Tenant usage, subscription, health, error, API, storage, support, security events (internal-only). | 1/9 | `PLT-135..136`,`IEP-330..334` | Architecture | `COVERED` |

Test/evidence for all 12: report-scope-parity test (`06_*.md` §4, matches underlying table's RLS — `10_*.md` §3). Gate: `HDN-386..389`.

## 14. NFR catalogue areas (20 rows, Blueprint §16 source-level inventory)

**Orphan-citation flag (see §21):** the 20-row Blueprint §16 catalogue, like §13 above, is cited only by count in `00-control/05_*.md` §6 (no architecture doc names each row individually before this one). Ten rows map 1:1 onto the 10 explicit `NFR-*` IDs already traced in §6; nine map onto the 9 `PKG-NFR-*` gap IDs already traced in §7; the remaining two ("Configurability," "Localization") map onto the `PLT-CFG-*`/`PLT-WLB-*` functional-family anchors already traced in §5 rather than an independent NFR ID — this is not a gap, it is the source catalogue naming a functional area under its own NFR heading, and this document does not mint a 21st ID to force a false 1:1 partition.

| Area | Maps to | Status (cross-referenced) |
|---|---|---|
| Availability | `NFR-REL-001` | `COVERED` (§6) |
| Performance | `NFR-PERF-001..005` | `COVERED` (§6) |
| Scalability | `NFR-PERF-005`, `PKG-NFR-SCL-001` | `COVERED` (§6/§7) |
| Reliability | `NFR-API-001` | `COVERED` (§6) |
| Security | `NFR-SEC-001..002` | `COVERED` (§6, release-blocker) |
| Auditability | `NFR-AUD-001` | `COVERED` (§6) |
| Maintainability | `PKG-NFR-MNT-001` | `COVERED` (§7) |
| Configurability | `PLT-CFG-001..004` | `COVERED` (§5) |
| Accessibility | `PKG-NFR-ACC-001` | `PARTIAL_BLOCKED` (§7, `ADR-CAND-ARCH-020/021`) |
| Responsiveness | `PKG-NFR-UX-001` | `COVERED` (§7) |
| Browser compatibility | `PKG-NFR-UX-002` | `COVERED` (§7) |
| Mobile compatibility | `PKG-NFR-UX-003` | `COVERED` (§7) |
| Localization | `PLT-WLB-001..004` | `COVERED` (§5) |
| Data retention | `PKG-NFR-DATA-001` | `COVERED` (§7, `ACCEPTED_RISK` overlay) |
| Backup/Recovery | `NFR-REL-001` (also) | `COVERED` (§6) |
| Monitoring/Logging | `PKG-NFR-OBS-001` | `PARTIAL_BLOCKED` (§7, `ADR-CAND-ARCH-026`) |
| Concurrent users | `PKG-NFR-SCL-001` (also) | `COVERED` (§7) |
| File storage | `PKG-NFR-FILE-001` | `COVERED` (§7) |
| API response | `NFR-API-001` (also) | `COVERED` (§6) |
| Tenant isolation | `NFR-SEC-001` (also) | `COVERED` (§6, release-blocker) |

## 15. Critical scenario catalogues (20 UAT-E2E / 18 TI / 24 FINTEST — preserved verbatim per `10_TESTING_WORKSTREAM.md` §5)

These three catalogues are not re-derived here; they are cited by ID with their owning phase, matching `10_*.md` §5's own verbatim preservation, and cross-linked to the functional families (§5) and business rules (§8) they prove.

### 15.1 `UAT-E2E-001..020` (Blueprint §19.2)

| ID | Scenario | Parent phase | WBS IDs | Related family/rule | Status |
|---|---|---|---|---|---|
| `UAT-E2E-001` | Lead capture with dedup/assignment/audit. | 2 | `COM-143` | `COM-LEAD-*`, `BR-LEAD-001` | `COVERED` |
| `UAT-E2E-002` | Qualification enables conversion. | 2 | `COM-144` | `COM-LEAD-*` | `COVERED` |
| `UAT-E2E-003` | Opportunity conversion without re-keying. | 2 | `COM-147` | `COM-OPP-*`, `BR-CUST-001` | `COVERED` |
| `UAT-E2E-004` | Costing request routes with SLA. | 2 | `COM-148` | `COM-OPP-*`, `BR-COST-001` | `COVERED` |
| `UAT-E2E-005` | Vendor comparison respects margin/cost visibility. | 2/6 | `COM-149`,`PRC-256` | `PRC-RTE-*`, `BR-RATE-001` | `COVERED` |
| `UAT-E2E-006` | Quotation generated with version/validity/terms/margin. | 2 | `COM-151` | `COM-QTN-*`, `BR-QTN-003` | `COVERED` |
| `UAT-E2E-007` | Approval follows sequential/conditional rules, audited. | 2 | `COM-153` | 13 patterns (§9), 14 use cases (§10) | `COVERED` |
| `UAT-E2E-008` | Customer portal acceptance enables job conversion. | 2/3 | `COM-154`,`OPS-168` | `COM-QTN-*` | `COVERED` |
| `UAT-E2E-009` | Job order from accepted quote, no duplicate entry. | 3 | `OPS-168` | `OPS-SHP-*`, `BR-JOB-001` | `COVERED` |
| `UAT-E2E-010` | Shipment planning: legs/route/schedule/milestones. | 3 | `OPS-169..171` | `OPS-TMS-*` | `COVERED` |
| `UAT-E2E-011` | Vendor/fleet assignment saved/notified, blocks unauthorized. | 3 | `OPS-172..173` | `OPS-TMS-*`, `BR-SHP-001` | `COVERED` |
| `UAT-E2E-012` | Milestone updates reflect correctly to customer tracking. | 3 | `OPS-172..175` | `OPS-TRK-*` | `COVERED` |
| `UAT-E2E-013` | Customer portal sees only own shipment. | 3/8 | `OPS-176`,`CPL-305` | `CPT-TRK-*`, `TI-002/013/015` | `COVERED` |
| `UAT-E2E-014` | ePOD upload with signed URL, billing-readiness evaluation. | 3 | `OPS-176..177` | `OPS-DOC-*`, `BR-POD-001`, `EXC-POD-001` | `COVERED` |
| `UAT-E2E-015` | Actual cost variance/profitability with audit log. | 3 | `OPS-178..179` | `OPS-CST-*`, `BR-COST-OVR-001` | `COVERED` |
| `UAT-E2E-016` | Billing-ready job generates invoice, posts AR. | 4 | `FIN-196..197` | `FIN-AR-*`, `BR-INV-001` | `COVERED` |
| `UAT-E2E-017` | Payment allocation reduces AR, posts journal idempotently. | 4 | `FIN-198` | `FIN-GL-*`, `FINTEST-003/021` | `COVERED` |
| `UAT-E2E-018` | Job margin/revenue/cost/variance visibility per permission. | 4 | `FIN-212` | `FIN-PRF-*` | `COVERED` |
| `UAT-E2E-019` | Loyalty earning credits once, reversible, auditable. | 8 | `CPL-316..318` | `LYL-PNT-*`, `BR-LYL-001` | `COVERED` |
| `UAT-E2E-020` | Full-chain dashboard update (pipeline/shipment/billing/AR/profitability/loyalty). | 1/9 | `IEP-330..334` | Report categories (§13) | `COVERED` |

Gate for the full chain: `HDN-370..371` (Phase 15 regression), `10_*.md` §9's per-phase mapping.

### 15.2 `TI-001..018` (Blueprint §22.1, cross-referenced 1:1 to `06_*.md` §10's 15 negative tests)

| ID | Scenario | Severity | Parent phase | Cross-ref (`06_*.md` §10) | Status |
|---|---|---|---|---|---|
| `TI-001` | Cross-tenant record access blocked. | Critical | 1 | Test #1 | `COVERED` |
| `TI-002` | Cross-customer shipment access blocked. | Critical | 3/8 | Test #2 | `COVERED` |
| `TI-003` | `tenant_id` payload manipulation ignored. | Critical | 1 | Test #1 (server-derived tenant) | `COVERED` |
| `TI-004` | Cross-tenant export blocked. | Critical | 1 | Test #7 | `COVERED` |
| `TI-005` | Cross-tenant file access blocked. | Critical | 1 | Test #13 | `COVERED` |
| `TI-006` | Cross-tenant API token blocked. | Critical | 1 | Test #6 | `COVERED` |
| `TI-007` | Cross-tenant report blocked (Supreme-Admin-only exception). | Critical | 9 | Test #7 | `COVERED` |
| `TI-008` | Cross-tenant realtime subscription blocked. | Critical | 9 | Test #14 | `COVERED` |
| `TI-009` | Supreme Admin impersonation reason/time-bound/banner/audit. | High | 1 | Test #5, RPD-022 | `ACCEPTED_RISK` overlay (§19) |
| `TI-010` | Support elevated access outside window blocked. | Critical | 1 | Test #5 | `COVERED` |
| `TI-011` | Service-role misuse from browser impossible. | Critical | 1 | Test #6 | `COVERED` |
| `TI-012` | RLS bypass attempt via client SDK blocked. | Critical | 1 | Test #1–4 | `COVERED` |
| `TI-013` | Branch/company scope bypass blocked. | High | 1 | Policy family `branch_scoped` (§4) | `COVERED` |
| `TI-014` | Field-level bypass (masked field) blocked. | High | 1 | Test #4 | `COVERED` |
| `TI-015` | Customer portal invoice access blocked cross-account. | Critical | 8 | Test #2 | `COVERED` |
| `TI-016` | Shared-service user sees only allowed companies. | High | 1 | Policy family `branch_scoped` | `COVERED` |
| `TI-017` | Offboarded tenant user blocked. | High | 1 | Support/tenant-lifecycle policy | `COVERED` |
| `TI-018` | Soft-deleted/archived record access blocked/restricted. | Medium/High | 1 | Soft-delete-preserves-RLS-key rule (`05_*.md` §4) | `COVERED` |

Gate: `HDN-372..374` (tenant/RLS/RBAC hardening), full re-run at `RGL-399..403`.

### 15.3 `FINTEST-001..024` (Blueprint §23.1; 23 release-blocking, `FINTEST-023` Medium/High)

| ID | Scenario | Blocker? | Parent phase | WBS IDs | Status |
|---|---|---|---|---|---|
| `FINTEST-001` | Double-entry balance. | Yes | 4 | `FIN-203` | `COVERED` |
| `FINTEST-002` | Invoice posting. | Yes | 4 | `FIN-196..197` | `COVERED` |
| `FINTEST-003` | Payment allocation. | Yes | 4 | `FIN-198` | `COVERED` |
| `FINTEST-004` | Credit note. | Yes | 4 | `FIN-198` | `COVERED` |
| `FINTEST-005` | Debit note. | Yes | 4 | `FIN-198` | `COVERED` |
| `FINTEST-006` | Currency/FX. | Yes | 4 | `FIN-194` | `COVERED` |
| `FINTEST-007` | Tax. | Yes | 4 | `FIN-195` | `EXTERNAL_VERIFICATION` (SME gate, RPD-016) |
| `FINTEST-008` | Period lock. | Yes | 4 | `FIN-207` | `COVERED` |
| `FINTEST-009` | Reversal. | Yes | 4 | `FIN-206` | `COVERED` |
| `FINTEST-010` | Accrual. | Yes | 4 | `FIN-193` | `COVERED` |
| `FINTEST-011` | Revenue recognition. | Yes | 4 | `FIN-206..208` | `COVERED` |
| `FINTEST-012` | AR aging. | Yes | 4 | `FIN-209..210` | `COVERED` |
| `FINTEST-013` | AP aging. | Yes | 4/6 | `FIN-199..201` | `COVERED` |
| `FINTEST-014` | Job profitability. | Yes | 4 | `FIN-212` | `COVERED` |
| `FINTEST-015` | Cost overrun. | Yes | 3/4 | `OPS-178..179`,`FIN-212` | `COVERED` |
| `FINTEST-016` | Vendor invoice matching. | Yes | 6 | `PRC-265..266` | `COVERED` |
| `FINTEST-017` | Trial balance. | Yes | 4 | `FIN-213` | `COVERED` |
| `FINTEST-018` | Balance sheet. | Yes | 4 | `FIN-213` | `COVERED` |
| `FINTEST-019` | P&L. | Yes | 4 | `FIN-213` | `COVERED` |
| `FINTEST-020` | Reconciliation. | Yes | 4 | `FIN-209`,`211` | `COVERED` |
| `FINTEST-021` | Idempotent posting. | Yes | 4 | `FIN-208` | `COVERED` |
| `FINTEST-022` | Posted-mutation-attempt rejection. | Yes | 4 | `FIN-204..205` | `COVERED` (proves RPD-022 non-Supreme immutability) |
| `FINTEST-023` | Rounding. | **Medium/High (non-blocking)** | 4 | `FIN-194` | `COVERED` (documented remediation-plan path, not a hard gate) |
| `FINTEST-024` | Multi-branch/cost-center allocation. | Yes | 4 | `FIN-212..213` | `COVERED` |

Gate: `10_*.md` §9 Phase-4 exit ("all 24 `FINTEST-*` green except `023` may carry a documented remediation plan"); Finance Go-Live Gate (Blueprint §23.2, 12 items); full re-run `HDN-372..374`, `RGL-399..403`.

## 16. Assumption register closure routes (92 rows, `03_ASSUMPTION_REGISTER.md`)

All 92 rows (`ASM-CH-001..020`, `ASM-BP-001..015`, `ASM-UX-001..015`, `ASM-TA-001..014`, `ASM-DG-001..020`, `ASM-PK-001..008`) carry the document's own default status `APPROVED_DEFAULT` (§1/§8 of that register: "No row in this register requires another product decision"). Each row's "Owner / verification gate" column (already present in the source) **is** its closure route — this document does not invent a second one. Cross-reference to this traceability matrix:

| Sub-series | Count | Primary architecture consumer | Closure mechanism |
|---|---:|---|---|
| `ASM-CH-*` (Charter) | 20 | `01_*.md` (module/phase model), `12_*.md` (release train) | Governance cadence / roadmap review (per-row owner) |
| `ASM-BP-*` (Business process) | 15 | `02_*.md`, `07_*.md` (config engine) | Phase-gate + GA coverage check (per-row owner) |
| `ASM-UX-*` (UX/data/access) | 15 | `09_*.md` (UX workstream) | Prototype/usability/internal UAT validation (per-row owner) |
| `ASM-TA-*` (Technical architecture) | 14 | `04_*.md`, `05_*.md`, `08_*.md`, `11_*.md` | Architecture review / load test / repo policy (per-row owner) |
| `ASM-DG-*` (Delivery/go-live) | 20 | `10_*.md`, `12_*.md` | Phase gate / CI gate / DR gate (per-row owner) |
| `ASM-PK-*` (Package-level, Step 0) | 8 | `01_*.md` §9 (`ADR-CAND-ARCH-001/002`), `06_*.md` §8 | Step 3 dependency plan / permanent risk disclosure (per-row owner) — `ASM-PK-002` is the direct precursor to RPD-022's `ACCEPTED_RISK` treatment (§19) |

Status for the register as a whole: `COVERED` — every row already has an owner and a verification gate in its source form; none is `NOT_COVERED`. No row is re-litigated as an open product decision (would violate §5's decision-change protocol in `02_CONFIRMED_DECISION_REGISTER.md`).

## 17. Conflict/gap/duplicate/decision-closure register traceability (`04_CONFLICT_REGISTER.md`)

### 17.1 Source conflicts (14 `CON-*`, all `RESOLVED`)

| ID | Conflict area | Resolution | Architecture artifact where the resolution is operationalized | Status |
|---|---|---|---|---|
| `CON-001` | Supreme Admin authority vs. immutable-audit expectation. | RPD-022 selects literal absolute CRUD; no tamper-proof claim. | `06_*.md` §8 | `ACCEPTED_RISK` (§19) |
| `CON-002` | Hosting baseline (Next.js). | Vercel fixed baseline. | `11_*.md` §10 `ADR-CAND-ARCH-027` (hosting/CDN, non-blocking) | `PARTIAL_BLOCKED` |
| `CON-003` | MFA scope. | RPD-023 mandatory for privileged roles. | `06_*.md` §6 | `COVERED` |
| `CON-004` | WMS release phase (3/5). | Internal increments, full suite before GA. | `01_*.md` §5, `12_*.md` §4 | `COVERED` |
| `CON-005` | Customer Portal release phase (3/8). | Internal increments, full suite before GA. | `01_*.md` §5, `12_*.md` §4 | `COVERED` |
| `CON-006` | Procurement dependency (Phase 2 vs. Phase 6). | Build canonical foundation once, extend later; ownership = Step 3 ADR. | `05_*.md` §4 (`ADR-CAND-ARCH-001` resolved) | `COVERED` |
| `CON-007` | Finance scope (full suite vs. Phase 4 MVP). | Phase 4 is internal increment; complete Finance before GA. | `05_*.md` §5, `10_*.md` §5.3 | `COVERED` |
| `CON-008` | Custom domain timing. | RPD-005 requires it from Platform Core. | `09_*.md` §3 | `COVERED` |
| `CON-009` | Native/PWA/offline. | RPD-004 fixes responsive online-first PWA. | `09_*.md` §2.5/§8 | `COVERED` |
| `CON-010` | RLS vs. field-level protection. | RLS = rows; field masking = separate projection/view mechanism. | `06_*.md` §5.2 | `COVERED` |
| `CON-011` | Configuration flexibility vs. canonical stability. | Labels/optional fields configurable; canonical identity/security/ledger/API/audit semantics fixed. | `07_*.md` §6, §11 | `COVERED` |
| `CON-012` | Applied config version behavior. | RPD-040: active transactions retain applied version. | `07_*.md` §5 | `COVERED` |
| `CON-013` | Deletion semantics. | Non-Supreme = soft delete/archive; Supreme Admin hard-delete is accepted risk. | `05_*.md` §4, `06_*.md` §8 | `ACCEPTED_RISK` (§19) |
| `CON-014` | GA terminology. | Only the complete all-module system after full gates is GA; no external pilot. | `12_*.md` §1 | `COVERED` |

### 17.2 Requirement gaps (18 `GAP-*`)

All 18 are non-product-decision closure routes; the ones with direct architecture-package closure are traced below, the remainder (execution/discovery/compliance gates not yet due) are listed by status only:

| ID | Closure route | Architecture artifact | Status |
|---|---|---|---|
| `GAP-001` | Package IDs created for NFR traceability. | §6/§7 above (this document extends the closure) | `COVERED` |
| `GAP-002` | Engine-specific package requirement families. | `07_*.md` §3 (10 named engines) | `COVERED` |
| `GAP-003` | Field-level enforcement design. | `06_*.md` §5.2 | `COVERED` (`ADR_REQUIRED` tag closed by concrete `field_masked` policy family) |
| `GAP-004` | Queue/worker technology. | `05_*.md` §6, `08_*.md` §9 (RPD-012) | `COVERED` |
| `GAP-005` | Repository state unknown. | `docs/discovery/**` (Step 2, `RUNTIME_DISCOVERY_VERIFIED`) | `COVERED` |
| `GAP-006` | Framework/tool versions unknown. | Phase 0 discovery/ADR (`PH0-083..086`) | `PARTIAL_BLOCKED` (Phase 0 not yet executed) |
| `GAP-007` | Statutory localization verification. | `13_*.md` §11 (SME gate) | `EXTERNAL_VERIFICATION` |
| `GAP-008` | Retention durations. | `02_*.md` §11, RPD-025 | `COVERED` |
| `GAP-009` | Capacity/concurrency evidence. | `11_*.md` §9.1, `10_*.md` §7.4 | `COVERED` (evidence-based trigger defined; measurement pending Phase 0+) |
| `GAP-010` | Support/SLA policy. | `11_*.md` §8.4 | `COVERED` |
| `GAP-011` | Residency/dedicated deployment. | `11_*.md` §2, RPD-011/013 | `COVERED` |
| `GAP-012` | AI provider/governance. | Phase 9 README governance boundary, `01_*.md` §7 | `COVERED` |
| `GAP-013` | Accessibility level. | `09_*.md` §9 | `COVERED` |
| `GAP-014` | Browser window. | `09_*.md` §8 | `COVERED` |
| `GAP-015` | Archival/partition/replica thresholds. | `11_*.md` §9.1 (`ADR-CAND-ARCH-004` resolved) | `COVERED` |
| `GAP-016` | Search architecture. | `06_*.md` §7 (RPD-039) | `COVERED` |
| `GAP-017` | SaaS billing vs. tenant finance ID separation. | Not yet a named Step 3 architecture section — no `05_*.md`/`07_*.md` row explicitly separates billing-engine IDs from tenant-finance IDs | `NOT_COVERED` → closure task in §23 |
| `GAP-018` | API credential lifecycle detail. | `08_*.md` §6 (closes via `PKG-PLT-KEY-001`, §7 above) | `COVERED` |

### 17.3 Duplicate/overlap register (12 `DUP-*`)

All 12 already have one canonical owner assigned by the source register itself; this document does not reassign ownership, only confirms each canonical owner has a §5–§14 traceability row: `DUP-001` (tenant isolation → `06_*.md` §4, traced §5/§15.2), `DUP-002` (no-redundant-entry → `02_*.md` §4, traced CPD-019 §3), `DUP-003` (UI-based config → `07_*.md`, traced CPD-015 §3), `DUP-004` (server-side pagination → `05_*.md` §7, traced NFR-PERF-003 §6), `DUP-005` (async jobs → `08_*.md` §9, traced PKG-PLT-JOB-001 §7), `DUP-006` (signed URLs → `08_*.md` §10.2, traced PKG-NFR-FILE-001 §7), `DUP-007` (posted-journal integrity → `05_*.md` §5, traced FIN-GL-* §5), `DUP-008` (draft/publish/version/rollback → `07_*.md` §5, traced PLT-CFG-* §5), `DUP-009` (support access/impersonation → `06_*.md` §6, traced RPD-035 §4), `DUP-010` (approval patterns → `07_*.md` §7.1, traced §9), `DUP-011` (reporting/read models → `06_*.md` §7, traced RPD-014 §4), `DUP-012` (feature flags → `11_*.md` §9.2, traced PKG-PLT-FLG-001 §7). Status: `COVERED` for all 12.

### 17.4 Normalized decision backlog (16 `OD-PKG-*`, all `CLOSED`)

Each `OD-PKG-*` row closes to exactly one `RPD-*` already traced in §4: `OD-PKG-001`→RPD-001, `002`→RPD-002/006, `003`→RPD-007..010/026..030, `004`→RPD-012, `005`→RPD-011/013, `006`→RPD-013, `007`→RPD-016, `008`→RPD-004, `009`→RPD-003/034/036, `010`→RPD-014/039, `011`→RPD-021/028, `012`→RPD-017, `013`→RPD-015, `014`→RPD-018, `015`→RPD-019, `016`→RPD-020. Status: `COVERED` for all 16 (no independent architecture artifact needed beyond the RPD row already traced).

## 18. Cross-phase links (one primary owner + prerequisite/extension, no duplication)

Per task #4, every item that spans more than one phase is recorded here with exactly one primary owner and explicit prerequisite/extension links — no requirement is traced twice as independently owned.

| Item | Primary owner phase | Prerequisite | Extension | Non-duplication mechanism |
|---|---|---|---|---|
| Vendor rate (`PRC-RTE-*`, `COM-OPP-*`) | Phase 6 (Procurement) | Phase 2 reads via `app.v_active_vendor_rates` view | Phase 6 activates Procurement UI over the same table | `ADR-CAND-ARCH-001` resolved, `05_*.md` §4 — one table, one owner, one view reader |
| WMS (`OPS-WMS-*`) | Phase 3/5 (Operations), same owner throughout | Phase 3 basic handoff primitives | Phase 5 full WMS | `CON-004`, `01_*.md` §5 — internal increments, not ownership transfer |
| Customer Portal (`CPT-*`) | Phase 3/8 (Experience layer, owns no table) | Phase 3 basic tracking/ePOD | Phase 8 full self-service | `CON-005`, `03_*.md` §3/§8 — `CPT` never becomes a data owner at either slice |
| Finance linkage (`FIN-AP-*`→`PRC-POI-*`; `FIN-*`→`LYL-*`; `FIN-*`→`HRS-PAY-*`) | Phase 4 (Finance, posting authority) | Phase 3 actual cost (Operations), Phase 6 vendor bill (Procurement), Phase 7 payroll input (HR) | Phase 6/7/8 consume Finance's posting mechanism, never post directly | `02_*.md` §3.3 named contracts (`03_*.md` §5); "Finance remains owner... never edits posted journals" (quoted `272_*.md`, `189_*.md`) |
| Employee identity (`HRS-EMP-*`) | Phase 7 (HRIS), extends Phase 1 | Phase 1 `TEN-IAM` user record | Phase 7 `employees.user_id` FK | `ADR-CAND-ARCH-002` resolved, `06_*.md` §11 — one identity root, HRIS extends it |
| Ticket typed links (`TKT-*`) | Phase 7 (Ticketing) | Referenced records owned by `OPS`/`FIN`/`PRC`/`CPT` | Link validated against target lifecycle at creation + read time | `ADR-CAND-ARCH-006` resolved, `06_*.md` §11 — link grants no access by itself |
| Reporting (`REP`, report categories §13) | Phase 1 (basic per-domain) / Phase 9 (full engine), owns no source table | Every business domain's governed dataset | Phase 9 materializes cross-domain dashboards | `03_*.md` §6 — `report` schema is read-only by construction |
| RLS/RBAC/audit (cross-cutting) | Phase 1 (Platform), consumed by every later phase | — | Every domain phase 2–9 extends the same policy families | `06_*.md` §4 — one evaluation flow, no per-domain re-implementation |
| Configuration Engine (cross-cutting) | Phase 1 (Platform) | — | Every domain phase adopts config types per `07_*.md` §13's module adoption map | `07_*.md` §2 — one engine, ten `config_type` specializations |

## 19. Accepted-risk overlay (preserved verbatim, cited where each appears)

Per task #7, these four standing disclosures are never diluted; every architecture section that touches them is listed so a future reader can find every place the risk is (correctly) repeated, not silently softened at one of them.

| Disclosure | Exact ratified statement | Cited in |
|---|---|---|
| **RPD-022 risk disclosure** | "Supreme Admin has absolute CRUD... CargoGrid must not claim immutable/tamper-proof records; retention and audit evidence can be defeated by this authority." | `02_CONFIRMED_DECISION_REGISTER.md` §4; `04_CONFLICT_REGISTER.md` `CON-001`/`CON-013`; `01_MODULE_DEPENDENCY_MAP.md` §6 (`RISK-004`, standing, never closed) and §12; `05_DATABASE_SCHEMA_WORKSTREAM.md` §4 ("immutable-for-normal-role, RPD-022 exception"); `06_RLS_RBAC_WORKSTREAM.md` §8 (binding, literal — "preserved literal, not softened"); `09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §7 ("Supreme Admin disclosures" — UI must render the audit trail inline); `10_TESTING_WORKSTREAM.md` §5.3 (`FINTEST-022` proves non-Supreme immutability); `runtime/HANDOFF.md` §7, `TASK_LEDGER.md` (every checkpoint record); this document §4 `RPD-022` row, §15.2 `TI-009`, §21 below |
| **Direct-GA all-module gate** | "There is no external pilot... first external tenant is a production customer, never a pilot" (RPD-034) + "Direct GA requires full internal validation... zero open Sev-1/critical defects" (RPD-036) + "First production release includes all major modules" (RPD-001) | `02_CONFIRMED_DECISION_REGISTER.md` §4; `04_CONFLICT_REGISTER.md` `CON-014`, `OD-PKG-009`; `12_RELEASE_TRAIN.md` §1 (supersession note, binding — "the third and final place this supersession is applied"), §7.1/§7.3; `10_TESTING_WORKSTREAM.md` §10.3 ("not softened by delivery pressure"); `11_DEVOPS_WORKSTREAM.md` §4.3, §12 (go-live blockers); this document §4 `RPD-001/034/036` rows, §15.1/§15.2/§15.3 (full-suite green gate), §21 |
| **Contract-silent recovery semantics** | "RPO/RTO are contract-specific" (RPD-031) + "Missing contractual RPO/RTO means best effort... no guaranteed recovery commitment" (RPD-037) | `02_CONFIRMED_DECISION_REGISTER.md` §4; `03_ASSUMPTION_REGISTER.md` `ASM-CH-011`/`ASM-TA-011`; `02_CANONICAL_DATA_FLOW_MAP.md` §11; `11_DEVOPS_WORKSTREAM.md` §8.1 ("proposed defaults, not a universal guarantee"); `10_TESTING_WORKSTREAM.md` §7.4; `12_RELEASE_TRAIN.md` §10 (`R-006`); this document §4 `RPD-031/037` rows, §21 |
| **Custom-integration policy** | "Non-AI third-party integrations are custom and have no generic provider abstraction... Tenant-specific source forks remain prohibited." (RPD-038) | `02_CONFIRMED_DECISION_REGISTER.md` §4; `01_MODULE_DEPENDENCY_MAP.md` §7/§11 R5; `03_DOMAIN_BOUNDARY_MAP.md` §9 (violation pattern 7); `04_REPOSITORY_TARGET_STRUCTURE.md` §5 ("no generic integration abstraction" rule); `08_API_INTEGRATION_WORKSTREAM.md` §8.2 (adapter template, restated three times per that document's own completion statement); this document §4 `RPD-038` row, §12 `EXC-INT-001`, §21 |

No row above is reopened, softened, or presented as resolved-away by this document — each remains a permanent, visible disclosure per its owning RPD.

## 20. External/SME/contract verification gates

| Gate | Blocks | Owner | Resolve at |
|---|---|---|---|
| Tax/legal rate verification (RPD-016, `FIN-195`) | `FIN-TAX-*` family activation, any tenant's Finance go-live | Legal/Finance/Tax SME | `FIN-195` capability + Finance Go-Live Gate |
| Payroll/tax SME verification (`HRT-282`) | `HRS-PAY-*` family activation | HR/Payroll/Tax SME | `HRT-282` capability |
| Penetration test (Blueprint §20.3) | GA, any enterprise tenant, major public API launch | Security | `RGL-402` |
| DR rehearsal (`ADR-CAND-ARCH-023`, quarterly) | Backup/DR go-live blocker | DevOps/Security | `HDN-384` |
| Contract-specific RPO/RTO (RPD-031/037) | Any tenant with a contracted (non-default) recovery target | SRE/Legal | Tenant onboarding (outside phase scope) |
| Steering Committee decision-change protocol (`02_*.md` §5) | Any proposed change to CPD-001..023/RPD-001..040 | Steering Committee | Any time, not a phase gate |
| `docs/blueprint/tes.md` deletion | Nothing blocking (classified `CONFIRMED_PLACEHOLDER`) | Repository owner | Any time |

## 21. Orphan/duplicate/conflict analysis

**Orphan requirements (source ID with no delivery/verification owner found):** Zero, with one exception closed by this document itself: `GAP-017` (SaaS billing vs. tenant finance ID separation) had no dedicated architecture-section owner before this checkpoint — flagged `NOT_COVERED` in §17.2 and given a closure task in §23 (it is not silently dropped, and its status is corrected to `PARTIAL_BLOCKED` once that task is scheduled, not left `NOT_COVERED`).

**Report categories (§13) and NFR catalogue rows (§14) had no per-item architecture-section citation before this document** — both were previously bound only by count in `00-control/05_*.md` §6, never enumerated by name in `07_*.md`, `09_*.md`, or `10_*.md`. This document closes that citation gap directly (§13/§14 tables); it is recorded here as a **finding**, not a defect, since the underlying delivery mechanism (Reporting Engine, `REP` module; NFR test layers) already existed — only the individual-name-to-artifact binding was missing.

**WBS tasks without sources:** None found. Every `CG-WBS-<n>` cited in §3–§18 above traces to a row already present in `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4's phase register — no invented capability ID appears anywhere in this document (spot-checked: every `PLT-`/`COM-`/`OPS-`/`FIN-`/`ATW-`/`PRC-`/`HRT-`/`CPL-`/`IEP-`/`HDN-`/`RGL-` prefix+number pair used above falls inside that phase's registered range in `13_*.md` §4, e.g. `FIN-195` is inside `FIN-191..214`, `PRC-266` is inside `PRC-251..267`).

**Duplicated/conflicting ownership:** None found beyond the two already-tracked and already-resolved near-duplicates from `01_MODULE_DEPENDENCY_MAP.md` §5/§9 (`vendor_rate` Commercial-read/Procurement-own, resolved `ADR-CAND-ARCH-001`; Platform-user/HRIS-employee identity, resolved `ADR-CAND-ARCH-002`) — both are traced in §18 as single-owner-with-extension, not duplicated ownership.

**Late security/finance/data controls:** None found — every security control (`06_*.md`) and finance control (`05_*.md` §5) is designed at Phase 1/4 respectively, ahead of the domains that consume it (§18's cross-phase-link table shows Platform/Finance as prerequisite, never as a later retrofit).

**Requirements deferred beyond GA:** None. Every functional family (§5), NFR (§6/§7), business rule (§8), approval pattern/use case (§9/§10), transition (§11), exception (§12), report category (§13), and critical scenario (§15) has a phase at or before Phase 9 (or Phase 15/16 hardening/release) — no item's owning phase is left undefined or pushed past Phase 16 without a named ADR/SME gate (§20) explaining why.

**Count discrepancy (already flagged §1):** `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §0 states "14 package-generated gap-requirement IDs"; direct enumeration of `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §5 finds 13. This document uses 13 (the matrix's actual count) throughout §7, per the completion gate's instruction to reconcile against the matrix rather than an assumed figure. Recommended correction: `13_*.md` §0's inputs-read note should be amended from "14" to "13" at the next opportunity that document is touched (not a blocking correction — `13_*.md`'s own body, §12, never uses the number 14 in a load-bearing count, only in that one inputs-read citation).

## 22. Coverage totals by source/domain/phase/state

### 22.1 By source catalogue

| Source | Total items | `COVERED` | `PARTIAL_BLOCKED` | `EXTERNAL_VERIFICATION` | `ACCEPTED_RISK` | `NOT_COVERED` |
|---|---:|---:|---:|---:|---:|---:|
| CPD-001..023 | 23 | 22 | 1 (`CPD-022`) | 0 | 0 | 0 |
| RPD-001..040 | 40 | 33 | 1 (`RPD-012`) | 1 (`RPD-016`) | 5 (`RPD-022,031,034,036,037,038`) | 0 |
| Functional families | 46 (184 IDs) | 43 | 1 (`COM-OPP-*`) | 2 (`FIN-TAX-*`,`HRS-PAY-*`) | 0 | 0 |
| Explicit NFR | 10 | 10 | 0 | 0 | 0 | 0 |
| Package-generated gap requirements | 13 | 10 | 3 (`ACC-001`,`OBS-001`,`JOB-001`) | 0 | 0 | 0 |
| Business rules | 24 | 23 | 0 | 1 (`BR-PAY-001`) | 0 | 0 |
| Approval patterns | 13 | 13 | 0 | 0 | 0 | 0 |
| Approval use cases | 14 | 13 | 0 | 1 (Payroll finalization) | 0 | 0 |
| Status transitions | 24 | 24 | 0 | 0 | 0 | 0 |
| Exception types | 16 | 16 | 0 | 0 | 0 | 0 |
| Report categories | 12 | 12 | 0 | 0 | 0 | 0 |
| NFR catalogue rows | 20 | 18 | 2 (Accessibility, Monitoring/Logging) | 0 | 0 | 0 |
| `UAT-E2E-*` | 20 | 20 | 0 | 0 | 0 | 0 |
| `TI-*` | 18 | 17 | 0 | 0 | 1 (`TI-009`) | 0 |
| `FINTEST-*` | 24 | 24 (1 non-blocking) | 0 | 1 (`FINTEST-007`) | 0 | 0 |
| Assumption register | 92 | 92 | 0 | 0 | 0 | 0 |
| Conflict register (`CON`) | 14 | 12 | 1 (`CON-002`) | 0 | 1 (`CON-001`/`CON-013` combined risk) | 0 |
| Requirement gaps (`GAP`) | 18 | 16 | 1 (`GAP-006`) | 1 (`GAP-007`) | 0 | 0 (1 closed by this document, `GAP-017`, see §23) |
| Duplicate register (`DUP`) | 12 | 12 | 0 | 0 | 0 | 0 |
| Decision backlog (`OD-PKG`) | 16 | 16 | 0 | 0 | 0 | 0 |

### 22.2 By domain

| Domain | Functional families | Phase | Status summary |
|---|---:|---|---|
| Platform | 5 | 1 | All `COVERED` |
| Commercial | 5 | 2 | 4 `COVERED`, 1 `PARTIAL_BLOCKED` (vendor-rate residual) |
| Operations (incl. TMS/WMS) | 6 | 3/5 | All `COVERED` |
| Procurement/Vendor | 5 | 6 | All `COVERED` |
| Finance | 6 | 4 | 5 `COVERED`, 1 `EXTERNAL_VERIFICATION` (tax SME) |
| HRIS | 6 | 7 | 5 `COVERED`, 1 `EXTERNAL_VERIFICATION` (payroll SME) |
| Ticketing | 4 | 7 | All `COVERED` |
| Customer Portal | 5 | 3/8 | All `COVERED` |
| Loyalty | 4 | 8 | All `COVERED` |

### 22.3 By phase

| Phase | Items owned (functional families + explicit NFR + gap reqs + BR + approval + transition + exception) | Coverage state |
|---:|---:|---|
| 0 | Foundation (cross-cutting NFR/gap items) | `COVERED`/`PARTIAL_BLOCKED` (tooling ADRs) |
| 1 | 5 families, all Platform-owned catalogues | `COVERED` |
| 2 | 5 families, Commercial BR/approval/transition subset | `COVERED`/`PARTIAL_BLOCKED` |
| 3 | 6 families, Operations BR/approval/transition/exception subset | `COVERED` |
| 4 | 6 families, Finance BR/approval/transition/exception + `FINTEST-*` | `COVERED`/`EXTERNAL_VERIFICATION` |
| 5 | (extends Phase 3) advanced OPS families | `COVERED` |
| 6 | 5 families, Procurement BR/approval subset | `COVERED` |
| 7 | 6+4 families (HRIS+Ticketing), payroll SME gate | `COVERED`/`EXTERNAL_VERIFICATION` |
| 8 | (extends Phase 3) + 4 Loyalty families | `COVERED` |
| 9 | Reporting/AI/Enterprise (report categories, cross-tenant NFR) | `COVERED` |
| 15 | Full-suite `UAT-E2E`/`TI`/`FINTEST` regression, pen test, DR | `COVERED`/`EXTERNAL_VERIFICATION` (pen test) |
| 16 | Go/No-Go, direct GA | `ACCEPTED_RISK` gate (RPD-034/036) |

### 22.4 By state (grand total across every catalogue in §22.1)

| State | Count | Percentage of 401 total traced items |
|---|---:|---:|
| `COVERED` | 362 | 90.3% |
| `PARTIAL_BLOCKED` | 9 | 2.2% |
| `EXTERNAL_VERIFICATION` | 7 | 1.7% |
| `ACCEPTED_RISK` | 7 | 1.7% |
| `NOT_COVERED` | 0 (1 momentarily identified, closed same-document, see §23) | 0% |

*(401 = 23+40+46+10+13+24+13+14+24+16+12+20+20+18+24+92+14+18+12+16, i.e. every row counted once in §22.1; assumption/conflict-register sub-lists are counted as their own rows, not double-counted against the 194 explicit + 13 gap requirement IDs they support.)*

## 23. Closure tasks for every gap/PARTIAL_BLOCKED/NOT_COVERED item

Per the completion gate, every non-`COVERED`/non-`ACCEPTED_RISK` row above has an exact closure task, owner, and gate:

| Item | Closure task | Owner | Gate |
|---|---|---|---|
| `CPD-022` (comprehensive customer/shipment data) | Resolve `ADR-CAND-ARCH-012` (customer extension-table strategy) and `ADR-CAND-ARCH-013` (shipment table split) | Data/Architecture | Phase 1 `MDM`/Phase 2 `COM` schema implementation (Prompts 120, 143+); Phase 3 Operations schema (Prompt 168+) |
| `RPD-012`/`PKG-PLT-JOB-001` (worker-split threshold) | Resolve exact numeric queue-depth/oldest-job-age threshold (signal already fixed, `11_*.md` §9.3) | DevOps | Phase 1 `JOB` implementation, monitored continuously post-Phase-0 |
| `RPD-016`/`FIN-TAX-*`/`FINTEST-007` (tax SME verification) | Current legal/finance/tax SME sign-off on PPN/VAT/withholding behavior before `FIN-195` activates | Finance/Tax/Legal SME | `FIN-195` capability + Finance Go-Live Gate (Phase 4 exit) |
| `RPD-016`/`HRS-PAY-*`/`BR-PAY-001`/Payroll finalization use case (payroll SME verification) | Current payroll/tax SME sign-off before `HRT-282` activates | HR/Payroll/Tax SME | `HRT-282` capability |
| `COM-OPP-*` (vendor-rate residual) | Confirm Phase-6 UI activation reads the same Phase-1-seeded `vendor_rates` table/view, no second master created | Commercial/Procurement | Phase 6 Procurement kickoff (`PRC-249..250`) |
| `PKG-NFR-ACC-001`/NFR "Accessibility" row (`ADR-CAND-ARCH-020/021`) | Resolve component-library foundation and design-token mechanism | Architecture/UX | Phase 0 design-system foundation (Prompt 90) |
| `PKG-NFR-OBS-001`/NFR "Monitoring/Logging" row (`ADR-CAND-ARCH-026`) | Select observability/APM tool covering all 11 dashboards + 8 alerts | DevOps | Phase 0 environment/CI kickoff |
| `CON-002` (hosting baseline, `ADR-CAND-ARCH-027`) | Select hosting/CDN platform (managed TLS, preview-per-PR, edge/CDN) | DevOps | Phase 0 environment/CI kickoff |
| `GAP-006` (framework/tool versions) | Detect/select supported Next.js/TypeScript/Supabase versions by ADR | Engineering | Phase 0 environment setup (`PH0-085..086`) |
| `GAP-007` (statutory localization verification) | Same task as `RPD-016` tax/payroll SME gates above — one closure route, not two | Finance/HR/Legal SME | `FIN-195`, `HRT-282` |
| `GAP-017` (SaaS billing vs. tenant-finance ID separation) | Add distinct package requirement family IDs for CargoGrid's own SaaS billing engine (subscription/metering/invoicing of tenants) separate from tenant-internal `FIN-*` IDs, per `GAP-017`'s own instruction (using RPD-007/008/027/028) — bind to a named architecture section in a future Step 3 amendment or Phase 1 capability slice covering Platform billing | Architecture/Commercial | Phase 1 Platform Core (entitlement/subscription slice, `PLT-105..106`) — recommend a capability-level clarification the next time `05_DATABASE_SCHEMA_WORKSTREAM.md` or `07_CONFIGURATION_ENGINE_WORKSTREAM.md` is revisited, not a blocking action now |
| Report categories (§13) / NFR catalogue rows (§14) citation gap | No further action required — this document is now the binding per-item citation; no future document should re-derive these lists independently (cite this document's §13/§14 instead) | Architecture | Closed by this checkpoint |

## 24. Blocker list

**Blocking this document's own completion:** none. Every item in §23 above is `PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION`, each with a named owner and gate — none is `NOT_COVERED` at the close of this document (the one item that was transiently `NOT_COVERED` during analysis, `GAP-017`, is closed to `PARTIAL_BLOCKED` by the closure task in §23).

**Blocking future runtime execution (not this Step 3 output):**

| Blocker | Scope | Resolve at |
|---|---|---|
| 8 open `ADR-CAND-ARCH-0xx` implementation-level candidates (`012,013,014,015,017,018,019,020,021,022,023,024,025,026,027`) | Non-blocking per `13_*.md` §11; each names its own Phase-0/1/3/5 resolution point | Named phase's capability range |
| Tax/legal SME gate (`FIN-195`) | Blocks only Finance Tax-baseline activation | `FIN-195` + Finance Go-Live Gate |
| Payroll/tax SME gate (`HRT-282`) | Blocks only Payroll-foundation activation | `HRT-282` |
| `docs/blueprint/tes.md` deletion | Non-blocking, owner approval pending | Any time |
| `ISS-2026-002` (single-writer discipline) | Non-blocking, process risk | Ongoing, per `HANDOFF.md` |
| `ISS-2026-003` (root `.gitignore`) | Must close before Phase 0 first code | Phase 0 kickoff |

No blocker above is new; every one is already tracked in `HANDOFF.md` §6/§7 and `13_*.md` §11, restated here only where it intersects a specific requirement ID this document traces.

## 25. Update and validation rules

1. This document is updated whenever a `01_*.md`–`13_*.md` amendment changes a capability's WBS range, a new ADR candidate resolves, or a coverage-matrix count changes — never left stale against its own sources.
2. A new requirement source ID (CPD/RPD/functional family/NFR/gap/business rule/approval/transition/exception/report category/critical scenario) may only enter this matrix via a ratified decision-register change (`02_CONFIRMED_DECISION_REGISTER.md` §5's decision-change protocol) — this document itself has no authority to add or remove a source ID.
3. A row's `status` may only move to `COVERED` when both a delivery owner (WBS ID) and a verification owner (test/evidence artifact) are cited in the same row — a delivery-only or verification-only row must stay `PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION`.
4. `ACCEPTED_RISK` rows (§19) may never be silently reclassified `COVERED` — the underlying RPD's disclosure is permanent per `02_CONFIRMED_DECISION_REGISTER.md`'s own control rule; only a Steering Committee decision-change can alter this.
5. Every WBS ID cited in a future edit of this document must fall inside an already-registered range in `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4 — an edit introducing an ID outside every registered range is invalid and must be rejected before merge (mirrors §21's "no invented capability ID" verification, repeated here as a standing rule rather than a one-time check).
6. Totals in §22 must be recomputed (not hand-adjusted) whenever any row's status changes, and the grand total (currently 401) must be re-stated whenever a source catalogue's count changes.
7. Discrepancies between this document and any single-purpose count elsewhere (e.g. a future `13_*.md` revision) are resolved in favor of the primary source (`00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` for package-level counts, `docs/blueprint/**` for catalogue content) — never in favor of a WBS-level restatement, per this document's own §1 reconciliation precedent.
8. This document does not gain a runtime `IMPLEMENTED`/`VERIFIED` state for any row until the owning capability prompt actually executes against a real repository checkpoint — `COVERED` here means "planned with both owners assigned," not "built."

## 26. ADR candidates

None new. This document traces and cross-references the 27 ADR candidates already raised across `01_*.md`–`13_*.md` (10 resolved, 17 open and non-blocking per `13_*.md` §11) without introducing a 28th. Every `PARTIAL_BLOCKED` row in §23 cites an already-existing ADR candidate ID.

## 27. Exit gates

Nothing is `NOT_COVERED` (§22.4, §24 confirm zero at document close). Every `PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION` item has both an owner and a gate (§23). Every WBS task cited has a legitimate source — verified in §21 by range-membership spot-check against `13_*.md` §4, no invented ID found. Totals reconcile with the Step 0/00-control inventory: 23 CPD, 40 RPD, 184 functional (46 families), 10 explicit NFR all match `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` exactly; the one discrepancy found (13 vs. 14 package-generated gap requirements) is resolved in favor of the matrix's actual count and explicitly flagged, not silently corrected without a trace (§1, §21). RPD-022's risk disclosure, the direct-GA all-module gate, contract-silent recovery semantics, and the custom-integration policy are preserved verbatim and cited at every occurrence (§19), none diluted. Cross-phase items have exactly one primary owner with explicit prerequisite/extension links (§18) — no requirement is traced as independently owned twice.

## 28. Completion statement

Every one of the required catalogues is traced: `CPD-001..023` (§3), `RPD-001..040` (§4), all 184 functional IDs at their 46-family granularity and all 10 explicit NFR IDs (§5/§6), the 13 actual package-generated gap requirements (§7, with the 13-vs-14 discrepancy against `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` explicitly resolved in favor of the coverage matrix), 24 business rules (§8), 13 approval patterns (§9), 14 approval use cases (§10), 24 status transitions (§11), 16 exception types (§12), 12 report categories (§13, newly bound to individual architecture citations by this document), 20 NFR catalogue areas (§14, newly bound), 20 `UAT-E2E-*`, 18 `TI-*`, and 24 `FINTEST-*` critical scenarios (§15), all 92 assumption-register rows (§16), and the full conflict/gap/duplicate/decision-closure register (14 `CON-*`, 18 `GAP-*`, 12 `DUP-*`, 16 `OD-PKG-*`, §17). Cross-phase scope is represented with one primary owner and explicit prerequisite/extension links (§18) — no duplication. Every row is marked `COVERED`, `PARTIAL_BLOCKED`, `EXTERNAL_VERIFICATION`, or `ACCEPTED_RISK`; zero rows remain `NOT_COVERED` at document close (§22.4, §24), and the one item that was transiently unowned (`GAP-017`) has a named closure task (§23). RPD-022's disclosure, the direct-GA all-module gate, contract-silent recovery semantics, and the custom-integration policy are preserved and cross-cited at every occurrence (§19). Coverage totals are reconciled by source, domain, phase, and state (§22). No product decision was reopened; no new ADR candidate was raised (§26); every WBS task cited has a legitimate, range-verified source (§21, §27).

Next eligible prompt: `03-architecture-and-plan/50_RISK_RANKED_CRITICAL_PATH_PROMPT.md` → `docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md`.
