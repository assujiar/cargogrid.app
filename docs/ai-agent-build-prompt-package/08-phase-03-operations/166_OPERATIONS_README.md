# Step 8 — Phase 3 Operations MVP Prompt Package

**Document ID:** `CG-AABPP-OPS-166`  
**Version:** `0.9.0`  
**Status:** `FINAL_FOR_STEP`  
**Package authorization:** Prompt generation only. Operations runtime implementation is not executed or implied.

## 1. Purpose

This package decomposes CargoGrid Operations MVP into bounded, dependency-aware prompts covering accepted-quote conversion, Job Order, Shipment Order, basic transport execution, milestone/exception/dispatch, documents/ePOD, actual cost/profitability, basic tracking, billing readiness, analytics and full transaction lineage.

## 2. Runtime entry gate

Before Prompt 167 or any Prompt 168–187:

1. Step 2 runtime discovery is `RUNTIME_DISCOVERY_VERIFIED`.
2. Step 3 runtime architecture is `RUNTIME_ARCHITECTURE_VERIFIED`.
3. Phase 0 runtime is `PHASE_0_VERIFIED`.
4. Phase 1 Platform Core runtime is `PHASE_1_VERIFIED`.
5. Phase 2 Commercial runtime is `PHASE_2_VERIFIED` at the active repository/schema/environment checkpoint.
6. Commercial `JobOrderDraftInput`, source/version lineage and idempotency contract are verified and compatible.
7. Operations WBS/traceability, branch/worktree ownership, exact paths, environment, baselines and downstream Finance/advanced-domain boundaries are current.

If any gate fails, set `PHASE_3_BLOCKED`, update ledgers/handoff and stop. `STEP_8_PACKAGE_COMPLETE` is not Operations runtime completion.

## 3. Required hierarchy and atomicity

Prompt 167 instantiates:

`Phase 3 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Prompts 168–184 each represent one bounded capability slice. Prompt 185 verifies integration, Prompt 186 hardens tenant/security/financial/data risks, Prompt 187 reconciles documentation/handoff, and Prompt 188 closes the phase.

Default boundary remains one slice/module/branch/objective, normally 1–3 migrations and 5–15 changed files. Prompt 167 must split any profile that exceeds the verified repository boundary.

## 4. Capability catalogue and dependency order

| Order | ID | Capability | Primary dependencies |
|---:|---|---|---|
| 0 | OPS-167 | WBS/runtime kickoff | `PHASE_2_VERIFIED` |
| 1 | OPS-168 | Job Order | OPS-167; verified `JobOrderDraftInput` |
| 2 | OPS-169 | Shipment Order | OPS-168 |
| 3 | OPS-170 | Shipment lifecycle | OPS-168..169 |
| 4 | OPS-171 | Land, air and sea baseline | OPS-169..170 |
| 5 | OPS-172 | Resource/vendor assignment | OPS-168..171 |
| 6 | OPS-173 | Milestone management | OPS-169..172 |
| 7 | OPS-174 | Exception and escalation | OPS-173 |
| 8 | OPS-175 | Basic dispatch | OPS-169..174 |
| 9 | OPS-176 | Document requirement | OPS-169..175 |
| 10 | OPS-177 | ePOD capture and review | OPS-170,173..176 |
| 11 | OPS-178 | Actual cost | OPS-168..177 |
| 12 | OPS-179 | Basic job profitability | OPS-178; Commercial revenue snapshot |
| 13 | OPS-180 | Basic public/customer tracking | OPS-170,173..177 |
| 14 | OPS-181 | Billing readiness | OPS-168..179 |
| 15 | OPS-182 | Operations dashboard | OPS-168..181 |
| 16 | OPS-183 | Operations reports | OPS-168..182 |
| 17 | OPS-184 | Quote-to-billing transaction lineage | OPS-168..183 |
| 18 | OPS-185 | Integrated Operations verification | OPS-168..184 |
| 19 | OPS-186 | Tenant/security/financial/data hardening | OPS-185 |
| 20 | OPS-187 | Documentation and handoff | OPS-186 |
| 21 | OPS-188 | Phase 3 closure | OPS-187 |

Prompt 167 may enable parallel lanes only when schemas, contracts, files, access policies, cost rules and test environments do not collide.

## 5. Binding Operations rules

- Phase 3 covers the basic slices of `OPS-SHP-001..004`, `OPS-TMS-001..004`, `OPS-TRK-001..004`, `OPS-DOC-001..004` and `OPS-CST-001..004`; all twenty anchors remain traceable to runtime tasks and evidence.
- `OPS-WMS-001..004` is not implemented here. Only an explicitly required shipment/warehouse handoff reference may exist; full WMS remains Step 10 under ASM-PK-006.
- Accepted quote → Job Order → Shipment → milestone/exception → ePOD → actual cost/profitability → billing readiness is canonical, stable, tenant-aware and auditable.
- Job Order creation consumes the verified Commercial `JobOrderDraftInput` idempotently. Customer, contact, address, cargo, service, rate, quote, price and credit data is referenced or governed-snapshotted, never silently retyped.
- Land, air and sea support is single-mode/single-leg baseline. Multi-leg, multimodal, multi-pick/drop, route/load/capacity optimization, dispatch board, GPS/telematics and advanced fleet/driver operations remain Step 10.
- Resource assignment uses verified canonical vendor/fleet/vehicle/driver references and availability facts. Phase 3 does not implement vendor onboarding, fleet/driver master lifecycle or procurement sourcing.
- Shipment status is a projection of validated lifecycle/milestone events. Events retain event time, received time, source, actor, correlation/idempotency key and permitted correction evidence.
- Basic exception/escalation includes delay, hold, damage/loss/incident intake, owner, SLA, notification and resolution. Full claims adjudication/settlement remains advanced scope.
- ePOD is responsive online-first PWA under RPD-004; native mobile and offline synchronization are not included. Photo, signature, receiver, geolocation and timestamp use the private scanned file and PostGIS foundations.
- Actual cost uses exact decimal money, currency, component/source/rate lineage and approval. Phase 3 does not create vendor bills, AP, GL journals, tax posting or settlement.
- Basic job profitability is an operational estimate from pinned Commercial revenue and approved actual cost; accounting P&L and reconciliation remain Phase 4.
- Basic public/customer tracking is read-only, minimal and scope-safe. Full Customer Portal, booking, billing, account management and loyalty remain Step 13 under ASM-PK-005.
- Billing readiness evaluates evidence and produces a versioned ready/not-ready status with reasons. Invoice, AR and journal generation remain Phase 4.
- Dashboards/reports query live transactional data under RPD-014 with read-only queries, pagination, timeouts, query budgets, caching and threshold-driven replicas.
- REST and GraphQL use the same domain services, validation, authorization, field policy, idempotency, audit and version governance.
- Files are private, malware-scanned/quarantined before availability, tenant/customer/record-scoped and delivered by short-lived signed URL.
- RPD-022 Supreme Admin absolute CRUD remains an explicit integrity exception; no immutable/tamper-proof claim is allowed.
- One shared multi-tenant codebase; no tenant fork or generic non-AI provider abstraction.
- Phases are internal increments. RPD-001, RPD-034 and RPD-036 prohibit pilot/partial-GA claims and require full internal validation before direct GA.

## 6. Runtime states

`PHASE_3_NOT_STARTED`, `PHASE_3_IN_PROGRESS`, `PHASE_3_BLOCKED`, `PHASE_3_PARTIALLY_COMPLETE`, `PHASE_3_VERIFIED`, `PHASE_3_ROLLED_BACK`.

Only Prompt 188 may set `PHASE_3_VERIFIED`.

## 7. Package completion

Package completion requires 23 non-empty files, IDs `OPS-166..188`, 20 operational prompts with 36/36 fields, all 17 capabilities, integrated verification/hardening/docs/closure, explicit dependency/next links, and updated controls.

**Next package command:** `LANJUT STEP 9`
