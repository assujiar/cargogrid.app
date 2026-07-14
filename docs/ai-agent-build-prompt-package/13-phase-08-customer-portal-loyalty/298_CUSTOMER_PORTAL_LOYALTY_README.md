# Step 13 — Phase 8 Customer Portal and Loyalty Prompt Package

**Package version:** `0.14.0`  
**Directory:** `13-phase-08-customer-portal-loyalty/`  
**Runtime prerequisite:** `PHASE_7_VERIFIED`  
**Next phase unlocked by runtime closure:** Step 14 only after Prompt 327 verifies Phase 8.

This package decomposes Phase 8 into atomic AI-agent implementation prompts for the Customer Portal and Loyalty scope described in the master prompt, Product Concept Brief, BPR blueprint, UX/Data Access Design, Technical Architecture/Security/Integration, and Delivery/Testing/Go-Live plan.

## Included source scope

Phase 8 minimum scope:

- Customer user and company/account/site scope.
- Request quotation, booking, shipment order, tracking and shipment monitoring.
- ePOD and document center.
- Warehouse inventory and order visibility.
- Invoice/billing/payment visibility.
- Complaint and ticket.
- Customer profile and customer user management.
- Loyalty earning, membership tier, points, cashback, reward, redemption, approval, expiry, fraud prevention, liability and reconciliation.

## Anchor coverage

This step covers all 36 Phase 8 anchors:

- `CPT-QBK-001..004`
- `CPT-TRK-001..004`
- `CPT-WHS-001..004`
- `CPT-BIL-001..004`
- `CPT-CX-001..004`
- `LYL-PRG-001..004`
- `LYL-PNT-001..004`
- `LYL-RDM-001..004`
- `LYL-ANL-001..004`

## File map

| Prompt | File | Purpose |
| --- | --- | --- |
| 298 | `298_CUSTOMER_PORTAL_LOYALTY_README.md` | This package guide |
| 299 | `299_CUSTOMER_PORTAL_LOYALTY_WBS_RUNTIME_KICKOFF_PROMPT.md` | Runtime WBS/index kickoff |
| 300–323 | capability prompts | 24 atomic implementation prompts |
| 324 | `324_CUSTOMER_PORTAL_LOYALTY_INTEGRATED_VERIFICATION_PROMPT.md` | Cross-capability runtime verification |
| 325 | `325_CUSTOMER_PORTAL_LOYALTY_PRIVACY_INTEGRITY_HARDENING_PROMPT.md` | Privacy, leakage, ledger and fraud hardening |
| 326 | `326_CUSTOMER_PORTAL_LOYALTY_DOCUMENTATION_HANDOFF_PROMPT.md` | Documentation and handoff |
| 327 | `327_CUSTOMER_PORTAL_LOYALTY_CLOSURE_VERIFICATION_PROMPT.md` | Independent runtime closure |

## Non-negotiable boundaries

- Customer Portal is Layer 4 only; customer scope is company/account/site/shipment/warehouse/invoice/document/ticket/loyalty and must be enforced in database/service policy, not UI only.
- Portal routes, payloads, filters and saved views never become trust roots.
- Commercial owns customer/quote, Operations owns shipment/ePOD execution, WMS owns inventory/order execution, Finance owns invoice/payment/GL, Ticketing owns tickets/SLA/links, Platform owns identity/config/files/jobs/audit.
- Loyalty balances are ledger-derived. Normal roles never directly mutate point/cashback/reward balances.
- RPD-022 Supreme Admin absolute CRUD remains an accepted residual risk and must not be described as immutable or tamper-proof.
- AI/predictive/enterprise depth remains Step 14.
- Package generation is not runtime execution, production readiness, pilot readiness or GA status.

## Exact next command after Step 13 package validation

`LANJUT STEP 14`

