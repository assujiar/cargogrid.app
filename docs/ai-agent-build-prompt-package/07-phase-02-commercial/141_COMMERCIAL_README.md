# Step 7 — Phase 2 Commercial MVP Prompt Package

**Document ID:** `CG-AABPP-COM-141`  
**Version:** `0.8.0`  
**Status:** `FINAL_FOR_STEP`  
**Package authorization:** Prompt generation only. Commercial runtime implementation is not executed or implied.

## 1. Purpose

This package decomposes CargoGrid Commercial into bounded, dependency-aware implementation prompts covering lead, prospect, contact/activity, CRM, opportunity, costing, rate lookup, margin, quotation lifecycle, customer/account conversion, contract pricing, credit controls, analytics, Job Order lineage, and no-reentry enforcement.

## 2. Runtime entry gate

Before Prompt 142 or any Prompt 143–164:

1. Step 2 runtime discovery is `RUNTIME_DISCOVERY_VERIFIED`.
2. Step 3 runtime architecture is `RUNTIME_ARCHITECTURE_VERIFIED`.
3. Phase 0 runtime is `PHASE_0_VERIFIED`.
4. Phase 1 Platform Core runtime is `PHASE_1_VERIFIED` at the active repository/schema/environment checkpoint.
5. Step 4 reusable templates are package-verified.
6. Commercial WBS/traceability, branch/worktree ownership, exact paths, environment, baselines and downstream contracts are current.

If any gate fails, set `PHASE_2_BLOCKED`, update ledgers/handoff and stop. `STEP_7_PACKAGE_COMPLETE` is not Commercial runtime completion.

## 3. Required hierarchy and atomicity

Prompt 142 instantiates:

`Phase 2 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Prompts 143–161 each represent one bounded capability slice. Prompt 162 verifies integration, Prompt 163 hardens tenant/security/financial/data risks, Prompt 164 reconciles documentation/handoff, and Prompt 165 closes the phase.

Default boundary remains one slice/module/branch/objective, normally 1–3 migrations and 5–15 changed files. Prompt 142 must split any profile that exceeds the verified repository boundary.

## 4. Capability catalogue and dependency order

| Order | ID | Capability | Primary dependencies |
|---:|---|---|---|
| 0 | COM-142 | WBS/runtime kickoff | `PHASE_1_VERIFIED` |
| 1 | COM-143 | Lead management | COM-142 |
| 2 | COM-144 | Prospect lifecycle | COM-143 |
| 3 | COM-145 | Contact and activity management | COM-143..144 |
| 4 | COM-146 | CRM sales plan and pipeline | COM-143..145 |
| 5 | COM-147 | Opportunity management | COM-144..146 |
| 6 | COM-148 | RFQ and costing request | COM-147 |
| 7 | COM-149 | Rate and cost lookup | COM-148; vendor/rate ownership ADR |
| 8 | COM-150 | Margin calculation | COM-149 |
| 9 | COM-151 | Quotation builder | COM-147..150 |
| 10 | COM-152 | Quotation versioning | COM-151 |
| 11 | COM-153 | Quotation approval | COM-150..152 |
| 12 | COM-154 | Customer acceptance | COM-153 |
| 13 | COM-155 | Customer and account conversion | COM-144..146,154 |
| 14 | COM-156 | Contract and customer pricing | COM-150,154..155 |
| 15 | COM-157 | Credit and commercial control | COM-155..156 |
| 16 | COM-158 | Commercial dashboard | COM-143..157 |
| 17 | COM-159 | Commercial reports | COM-143..158 |
| 18 | COM-160 | Full lineage into Job Order | COM-143..159 |
| 19 | COM-161 | No-reentry enforcement | COM-143..160 |
| 20 | COM-162 | Integrated Commercial verification | COM-143..161 |
| 21 | COM-163 | Tenant/security/financial/data hardening | COM-162 |
| 22 | COM-164 | Documentation and handoff | COM-163 |
| 23 | COM-165 | Phase 2 closure | COM-164 |

Prompt 142 may enable parallel lanes only when schemas, contracts, files, access policies, financial rules and test environments do not collide.

## 5. Binding Commercial rules

- Source anchors `COM-LEAD-001..004`, `COM-CRM-001..004`, `COM-OPP-001..004`, `COM-QTN-001..004` and `COM-CPR-001..004` remain traceable to runtime tasks and evidence.
- Lead → prospect/account → opportunity → costing → quotation → approval → acceptance → customer/contract → Job Order lineage is canonical, stable, tenant-aware and auditable.
- Customer, contact, address, cargo, service, rate and quote data is reused by reference or governed snapshot; retyping is prohibited unless a justified override and before/after audit exist.
- Qualified lead/prospect/customer conversion is idempotent, duplicate-aware and preserves source identity; conversion never silently copies divergent master data.
- Phase 2 builds the canonical basic vendor/service/rate lookup foundation once. Phase 6 extends it; no duplicate vendor/rate model or full procurement lifecycle is allowed here. Runtime ownership requires an ADR.
- Money uses exact decimal types, explicit currency and versioned rounding. Margin, discount and FX behavior is deterministic; floating-point money is forbidden.
- Cost, margin, discount, credit and forecast fields use server-authoritative field/record policies. UI hiding alone is never access control.
- Accepted quotation versions are locked for normal roles and linked to acceptance evidence. Revision creates a new version; RPD-022 Supreme Admin authority remains an explicit integrity exception.
- Customer acceptance records actor, channel, authority, timestamp, accepted quote version and evidence. A sent/read event is not acceptance.
- Credit controls provide governed limit/status/hold/override snapshots and a Finance integration boundary; Phase 2 does not implement AR, GL or payment posting.
- Job Order remains Phase 3-owned. Phase 2 owns the idempotent accepted-quote conversion contract, snapshot and lineage; it must not smuggle the Operations domain into Commercial.
- Dashboards query live transactional data under RPD-014 with read-only queries, pagination, timeouts, query budgets, caching and threshold-driven replicas.
- REST and GraphQL use the same domain services, validation, authorization, field policy, idempotency, audit and version governance.
- Files remain private, malware-scanned/quarantined before availability, tenant/record-scoped and delivered by short-lived signed URL.
- One shared multi-tenant codebase; no customer fork and no generic non-AI provider abstraction.
- Phases are internal increments. RPD-001, RPD-034 and RPD-036 prohibit pilot/partial-GA claims and require full internal validation before direct GA.

## 6. Runtime states

`PHASE_2_NOT_STARTED`, `PHASE_2_IN_PROGRESS`, `PHASE_2_BLOCKED`, `PHASE_2_PARTIALLY_COMPLETE`, `PHASE_2_VERIFIED`, `PHASE_2_ROLLED_BACK`.

Only Prompt 165 may set `PHASE_2_VERIFIED`.

## 7. Package completion

Package completion requires 25 non-empty files, IDs `COM-141..165`, 22 operational prompts with 36/36 fields, all 19 capabilities, integrated verification/hardening/docs/closure, explicit dependency/next links, and updated controls.

**Next package command:** `LANJUT STEP 8`
