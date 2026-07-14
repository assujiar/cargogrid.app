# Prompt 327 — Customer Portal and Loyalty Closure Verification

**Prompt ID:** `CG-S13-CPL-029`  
**Package document:** `CG-AABPP-CPL-327`  
**Version:** `0.14.0`  
**Runtime output:** `docs/build-log/phase-08/CUSTOMER_PORTAL_LOYALTY_CLOSURE_REPORT.md`

Do not begin until Prompt 326 is `VERIFIED`, the active checkpoint still carries `PHASE_7_VERIFIED`, and all Phase 8 capability, integrated-verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Phase 8 Customer Portal and Loyalty runtime completeness, customer-scope isolation, source-domain ownership, file privacy, ticket/payment visibility, exact loyalty ledgers, reward/fraud controls and liability reconciliation before Step 14 Intelligence, Automation and Enterprise Expansion.

## Required verification

1. Verify Prompts 299–326 at one repository/schema/environment checkpoint and reconcile every WBS, dependency, traceability and evidence link.
2. Confirm all 24 Phase 8 capabilities have implementation, migration/contract/UI as applicable, tests, documentation and owner: customer user scope; portal dashboard; request quotation; booking; shipment order; tracking; shipment monitoring; ePOD; document center; warehouse inventory visibility; warehouse order/fulfillment visibility; invoice/billing visibility; payment visibility; complaint/ticket; customer profile; customer user management; loyalty program/earning; membership tier; points ledger; cashback/discount/voucher; reward catalogue; redemption approval/fulfillment; expiry/fraud prevention; liability/reconciliation analytics.
3. Confirm all 36 anchors across `CPT-QBK-001..004`, `CPT-TRK-001..004`, `CPT-WHS-001..004`, `CPT-BIL-001..004`, `CPT-CX-001..004`, `LYL-PRG-001..004`, `LYL-PNT-001..004`, `LYL-RDM-001..004` and `LYL-ANL-001..004` map to durable runtime evidence with no orphan.
4. Prove Customer Portal is Layer 4 only and no fifth access layer was introduced.
5. Prove customer company/account/site membership is the trust root for every portal list, detail, action, count, search, saved view, export, cache, notification, signed URL and realtime update.
6. Prove forged route IDs, payload scope, copied URLs, stale sessions, revoked users and guessed document/source IDs cannot access other customer data.
7. Prove customer dashboard uses safe pre-aggregated/source-linked projections and cannot reveal out-of-scope record existence through counts, snippets, errors or empty states.
8. Prove request quotation hands off to Commercial quotation/customer/service contracts and does not create approved price truth, margin fields or duplicate customer/quote records.
9. Prove booking creates only approved Commercial/Operations handoff records with idempotency, file scanning, schedule validation and safe reschedule/cancel workflow.
10. Prove shipment order visibility is a customer-safe projection over Operations shipment truth and does not expose vendor rates, internal notes, driver personal data, cost or unsupported prediction.
11. Prove tracking timeline/milestones are source-derived, timezone-safe, freshness-marked and hide internal events/notes/vendor/support-only details.
12. Prove shipment monitoring alert preferences are scope-revalidated at emission time, idempotent and storm-controlled.
13. Prove ePOD access requires current customer scope, passed malware scan, private storage, short-lived scope-bound signed URL and access audit.
14. Prove document center search/download/upload/linking requires both document scope and source-record authorization; unscanned/quarantined files never preview/download/index/email.
15. Prove warehouse inventory visibility is WMS-owned and customer-safe by owner/account/site/SKU/status without other-customer stock or internal location leakage.
16. Prove warehouse order/fulfillment visibility derives from WMS lifecycle and portal change requests do not mutate execution tasks directly.
17. Prove invoice/billing visibility is Finance-owned, customer-finance scoped and cannot edit posted/finalized invoices, journals, GL, tax, margin or period locks.
18. Prove payment visibility is Finance-owned and cannot post, allocate, reverse, reconcile or delete payments; loyalty earning uses only approved paid eligibility.
19. Prove complaint/ticket portal uses the Phase 7 canonical Ticketing model, keeps internal notes/support fields hidden and reauthorizes both ticket and linked source record.
20. Prove customer profile changes are governed requests/effective versions and do not silently overwrite canonical customer/account/site master data.
21. Prove customer user management uses Platform identity, MFA/current-auth for high-risk changes, scope preview, invite/revoke/session invalidation and no out-of-scope delegation.
22. Prove loyalty program/earning rules are effective-dated, approved where required, deterministic and source-linked to eligible paid transactions.
23. Prove membership tier calculation, upgrades/downgrades and benefits are versioned, explainable and ledger/audit-backed.
24. Prove points balance derives only from point ledger events for normal roles: earning, reversal, adjustment, expiry, redemption and fraud hold are idempotent and auditable.
25. Prove cashback/discount/voucher/coupon entitlements are governed records with value caps, eligibility, expiry, reversal and Finance/liability treatment where applicable.
26. Prove reward catalogue visibility, eligibility, media/files, stock and terms are versioned and revalidated during redemption.
27. Prove redemption approval/fulfillment prevents double spend, stock races, stale eligibility and customer-visible leakage of fraud/internal investigation details.
28. Prove expiry jobs write ledger events without deleting original history and are idempotent, replayable and reconciled.
29. Prove fraud prevention in Phase 8 is governed/rule-based; predictive fraud/AI scoring remains Step 14 unless separately controlled and auditable.
30. Prove loyalty liability/reconciliation can reproduce totals from ledger events/config versions and aligns with Finance handoff/control references where configured.
31. Prove Finance remains owner of GL/journal/payment/reconciliation and Loyalty does not silently post or mutate Finance truth outside approved Finance contracts.
32. Prove RPD-022 Supreme Admin residual risk is disclosed and normal roles still have ledger/scope/file safeguards; reject immutable-for-all and tamper-proof claims.
33. Prove RPD-023 MFA/current authorization on customer-admin, reward approval, fraud release, privileged support and export actions.
34. Prove RPD-025 retention/legal hold applies to portal documents, invoice/payment documents, ticket files, loyalty ledgers and audit/security evidence.
35. Prove RPD-032 every upload is private and malware-scanned across quote, booking, ePOD, documents, invoice support, tickets and reward media.
36. Prove RPD-033 REST/GraphQL parity for portal/loyalty record, field, file, job, idempotency, audit and version behavior.
37. Prove RPD-040 active customer, portal membership, invoice/payment-visible, ticket and loyalty critical records retain applied configuration/source versions.
38. Prove RPD-004 responsive online-first PWA, WCAG/browser/loading/empty/error/denied/conflict/stale/degraded states and no fake success/dead action across customer/admin portal.
39. Prove target-volume portal dashboard/tracking/document/inventory/order/invoice/payment/ticket/loyalty searches, jobs, notification and exports meet declared budgets with privacy parity.
40. Confirm Step 13 did not smuggle Step 14 AI/predictive/reporting builder/automation/public API/SSO/dedicated instance/multi-region scope.
41. Confirm clean install and Phase 7→8 upgrade, generated types, CI, backup/restore, projection/ledger/liability reconciliation, observability/runbooks and zero unresolved critical/high tenant/customer/file/source-domain/payment/ticket/loyalty/performance/evidence blocker.
42. Confirm no production, external-pilot, partial-GA or market-ready claim. RPD-001/034/036 still require every major module and full internal validation before direct GA.

## Closure states

- `PHASE_8_VERIFIED`: every mandatory Customer Portal/Loyalty runtime gate passes.
- `PHASE_8_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Step 14 is blocked.
- `PHASE_8_BLOCKED`: a critical tenant/customer/scope/file/source-domain/invoice/payment/ticket/loyalty/fraud/liability/integration/schema/contract/evidence gate fails.
- `PHASE_8_ROLLED_BACK`: the phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; 24-capability × 36-anchor evidence map; customer scope proof; portal dashboard/quote/booking/shipment/tracking/ePOD/document/WMS/invoice/payment/ticket/profile/user-management evidence; loyalty program/tier/points/benefit/reward/redemption/expiry/fraud/liability evidence; source-domain ownership proof; files/MFA/retention/audit; REST/GraphQL/jobs/performance; migration/recovery; later-phase boundary audit; RPD-022 residual-risk disclosure; residual issues; closure state/rationale; Step 14 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_8_VERIFIED` only if every mandatory runtime check passes. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 13 validation is `LANJUT STEP 14`.
