# Prompt 271 — Procurement/Vendor Closure Verification

**Prompt ID:** `CG-S11-PRC-022`  
**Package document:** `CG-AABPP-PRC-271`  
**Version:** `0.12.0`  
**Runtime output:** `docs/build-log/phase-06/PROCUREMENT_VENDOR_CLOSURE_REPORT.md`

Do not begin until Prompt 270 is `VERIFIED`, the active checkpoint still carries `PHASE_5_VERIFIED`, and all Phase 6 capability, integrated-verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Phase 6 Procurement and Vendor Management runtime completeness, vendor/commercial integrity, tenant/external-party security and Finance/Operations compatibility before Phase 7 HRIS/Ticketing implementation.

## Required verification

1. Verify Prompts 250–270 at one repository/schema/environment checkpoint and reconcile every WBS, dependency, traceability and evidence link.
2. Confirm all 17 master capabilities have implementation, migration/contract/UI as applicable, tests, documentation and owner: vendor registration/onboarding; assessment; compliance/document expiry; banking/tax security; rate/pricelist; sourcing; Procurement RFQ; vendor comparison; approval; purchase order; contract; capacity; assignment; performance; invoice matching; dashboard/reports; optional vendor portal.
3. Confirm all 20 anchors across `PRC-VND-001..004`, `PRC-ASM-001..004`, `PRC-RTE-001..004`, `PRC-SRC-001..004` and `PRC-POI-001..004` map to durable runtime evidence with no orphan.
4. Prove the Phase 2 canonical vendor/service/rate foundation was extended—not duplicated—and every costing, shipment, PO, assignment, actual-cost, match and Finance reference preserves no-reentry source/version lineage.
5. Prove `Vendor Registration → Mandatory Document Verification → Assessment/Approval → Active Vendor` including `PRC-VND-US-001`, duplicate/legal-identity review, revision, suspension/blacklist/reactivation/archive and downstream impact controls.
6. Prove self-registration and optional vendor portal are tenant-configurable under BP-A08, invitation/intake is scoped/non-authoritative, and external vendor identity uses an approved Platform model without creating a fifth access layer or colliding with Layer 4 customer scope.
7. Prove files are private, RPD-032 malware-scanned before release, signed/download-audited, versioned, expiry/renewal/waiver/legal-hold controlled and able to place a safe vendor-eligibility hold.
8. Prove assessment criteria, weights, scoring, bands, findings, corrective actions, expiry and reassessment are versioned/explainable; humans approve qualification and lifecycle actions.
9. Prove bank/tax/payment-term fields are masked, purpose-bound and absent from generic search/export/log/cache; maker-checker, re-auth/MFA, effective version, hold, key/recovery and dated RPD-016 SME evidence pass.
10. Prove one exact rate engine supports quotation/pricelist route/service/mode/fleet/container/zone/distance/weight/volume tiers, surcharge/accessorial, minimum charge, currency, tax, UOM, validity and rounding with source/config/approval snapshots and RPD-040 behavior.
11. Prove sourcing inherits Commercial/Operations demand without re-entry, eligibility/exclusions are explainable, and RFQ invitations/responses/clarifications/deadlines preserve vendor confidentiality, private files, idempotency and exact source versions.
12. Prove vendor comparison normalizes exact components/currency/UOM/tax/rounding and non-price criteria while keeping recommendations human-governed; no competitor offer or internal budget/cost/margin leaks to external vendors/customers.
13. Prove the canonical Platform approval engine governs activation, rate, selection, PO, contract, sensitive changes, match exceptions and overrides with authority, separation, delegation, SLA/escalation, stale-source invalidation and privileged MFA where applicable.
14. Prove PO and contract roots/versions retain exact source, lines/quantity/UOM, price/components/currency/tax/rounding, service/coverage/SLA, terms, validity, approval, signature evidence, acknowledgement, amendment/renewal/termination and downstream snapshots.
15. Prove Procurement PO/contract does not post journals, create AP, execute settlement or change cash; RPD-038 bank/e-sign/compliance connectors are case-specific shared-code adapters with signature/replay/rate-limit/failure/recovery evidence.
16. Prove vendor capacity references canonical Phase 5 resources, uses exact window/UOM/availability equations and prevents overbooking; vendor assignment extends canonical shipment/leg/task execution with eligibility/rate/contract/PO/capacity/override/acceptance snapshots.
17. Prove Operations owns execution/custody/status while Procurement governs eligibility/commitment; vendor-owned fleet/driver/warehouse references do not duplicate Phase 5 roots and employee/attendance/payroll truth remains Step 12.
18. Prove vendor performance reconciles on-time pickup/delivery, acceptance, response, capacity fulfillment, compliance, claim/damage, competitiveness, rate validity, invoice accuracy, service/customer complaint/SLA evidence using versioned formulas/windows/exclusions/adjustments and human lifecycle decisions.
19. Prove vendor invoice matching extends the canonical Phase 4 vendor bill and passes `FINTEST-016`: configured two-/three-/multi-source bill→PO/contract→shipment/service/ePOD→actual-cost→rate/tax/payment-term equations, duplicate prevention, partials/tolerances/disputes/approval and idempotent Finance handoff reconcile.
20. Prove Finance remains owner of vendor bill, AP, posting, period lock, reversal, settlement and reconciliation; Procurement never creates a duplicate bill/AP root, posts a journal or pays a vendor.
21. Prove RPD-014 live-OLTP dashboards/reports and target-volume vendor/rate search/import, sourcing/RFQ/comparison, approvals, PO/contract, capacity/assignment, scorecards, match, export and enabled portal meet declared query/job/backpressure budgets with source reconciliation.
22. Prove RPD-033 REST/GraphQL parity and tenant/company/branch/vendor/record/field/file/job/export/cache/realtime isolation across internal roles, vendor users/tokens, customer identities, support sessions and forged references.
23. Confirm RPD-022 permits Supreme Admin absolute CRUD over vendor/compliance/rate/PO/contract/match/audit records. Verify normal-role safeguards and warnings/evidence, but reject every tamper-proof, immutable-for-all or non-repudiation claim.
24. Prove RPD-004 responsive online-first PWA, RPD-005/019 controlled white-label/custom domain where portal is enabled, RPD-023 MFA, RPD-025 retention, RPD-035 support controls and complete WCAG/browser/loading/empty/error/denied/conflict/degraded states.
25. Confirm HRIS/employee/attendance/payroll remains Step 12, Customer Portal/Loyalty remains Step 13 and AI/predictive/vendor recommendation/enterprise depth remains Step 14. Phase 6 did not smuggle later-phase scope.
26. Confirm clean install and Phase 5→6 upgrade, Phase 2 vendor/rate adoption, migration/type generation, CI, backup/restore, observability/runbooks and zero unresolved critical/high tenant, vendor, security, commercial, Operations, Finance, file, integration, performance or evidence blocker.
27. Confirm no production, external-pilot, partial-GA or market-ready claim. RPD-001/034/036 still require every major module and full internal validation before direct GA.

## Closure states

- `PHASE_6_VERIFIED`: every mandatory Procurement/Vendor runtime gate passes.
- `PHASE_6_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 7 is blocked.
- `PHASE_6_BLOCKED`: a critical tenant/vendor/access/security/commercial/Operations/Finance/file/integration/schema/contract/evidence gate fails.
- `PHASE_6_ROLLED_BACK`: the phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; 17-capability × 20-anchor evidence map; canonical vendor/rate ownership proof; registration/compliance/assessment/bank-tax evidence; rate/sourcing/RFQ/comparison/approval; PO/contract/capacity/assignment; performance; vendor-bill match and `FINTEST-016`; Finance/Operations ownership reconciliation; portal/customer/vendor isolation; files/security/audit/retention; performance/job/export/API parity; clean build/migration/recovery; later-phase boundary audit; RPD-022/statutory/provider residual-risk disclosure; residual issues; closure state/rationale; Phase 7 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_6_VERIFIED` only if every mandatory runtime check passes. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 11 validation is `LANJUT STEP 12`.
