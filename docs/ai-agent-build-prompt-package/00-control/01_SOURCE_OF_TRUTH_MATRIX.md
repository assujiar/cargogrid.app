# Source of Truth Matrix

**Document ID:** `CG-AABPP-CTRL-001`  
**Version:** `0.1.1`  
**Status:** `FINAL_FOR_STEP`  
**Primary authority:** `CargoGrid_Product_Concept_Brief.md`

## 1. Authority and precedence

| Rank | Source | Authority | Permitted interpretation |
|---:|---|---|---|
| 1 | Product Concept Brief | Product decisions and product mandate | May only be changed through formal Confirmed Product Decision change control. |
| 2 | Project & Product Charter | Scope, governance, roadmap, commercialization, phase boundaries | May clarify and sequence the brief; may not narrow the long-term mandate without an approved decision. |
| 3 | Business Process & Product Requirements Blueprint | Functional/process/data/NFR detail | May add Proposed Defaults and IDs; may not contradict brief or charter phase intent. |
| 4 | UX, Data & Access Design | Portal, IA, screen, interaction, field and record access design | May select UX defaults; security cannot rely on UI hiding. |
| 5 | Technical Architecture, Security & Integration | Implementation architecture and technical guardrails | May select technical defaults within the fixed stack; architecture exceptions require ADR approval. |
| 6 | Delivery, Testing & Go-Live Plan | Delivery sequencing, gates, UAT, migration, release, support | May impose stricter release gates; cannot declare a reduced roadmap to be the complete product. |
| Operational | Master prompt | Package-generation scope and required format | Governs how this package is produced. A fixed instruction in the master prompt is binding unless it directly changes a higher-authority product decision. |

Resolution order: direct primary decision → ratified founder decision RPD-001..040 → explicit downstream requirement → approved default → execution/discovery gate. An RPD that deliberately creates an exception must remain visible with its residual risk.

## 2. Source responsibility matrix

| Concern | Brief | Charter | BPR | UX/Data | Technical | Delivery | Package control owner |
|---|---:|---:|---:|---:|---:|---:|---|
| Product identity and target market | A | C | C | C | C | C | Decision Register |
| Long-term module scope | A | R | R | C | C | C | Coverage Matrix |
| Phase/MVP boundary | C | A/R | R | C | C | R | Coverage Matrix |
| Four-layer access model | A | R | R | R | R | T | Decision Register |
| Tenant isolation and RLS/RBAC | A | R | R | R | A/R technical | T | Coverage + Conflict Registers |
| Configuration through UI | A | R | R | R | A/R technical | T | Decision Register |
| Business process and rules | A intent | C | A/R | R UX | R mechanics | T | Coverage Matrix |
| Canonical data and lineage | A intent | R | A/R | A/R logical | A/R physical | T | Coverage Matrix |
| UX and information architecture | C | C | C | A/R | R feasibility | T | Coverage Matrix |
| Fixed technology stack | A baseline | R | C | C | A/R detail | T | Decision Register |
| API/integration standard | A intent | R | R | C | A/R | T | Coverage Matrix |
| Financial integrity | A | R | R | R access | A/R mechanics | A/R gates | Coverage Matrix |
| Test strategy and evidence | C | C | R acceptance | R UX/access | R technical | A/R | Coverage Matrix |
| Migration/deployment/cutover | C | R | C | C | R architecture | A/R | Coverage Matrix |
| Go-live and support | C | R | C | C | R readiness | A/R | Build Status |

Legend: `A` accountable authority, `R` requirement/detail owner, `C` context, `T` test/gate owner.

## 3. Alignment matrix by product area

| Area | Primary decision | Downstream elaboration | Package interpretation |
|---|---|---|---|
| Product | All-in-one logistics SaaS ERP | Charter positions it as logistics operating system; BPR covers 46 functional families | Long-term scope remains comprehensive; phased delivery is not scope cancellation. |
| Tenancy | Multi-tenant with strict isolation | Shared-schema default, `tenant_id`, RLS, tenant-aware indexes; dedicated Enterprise option | Shared schema plus RLS is ratified; dedicated deployment is a paid contractual option. |
| White-label | Per-tenant branding/domain/terminology/templates | Portal/domain resolution, verified domains, design tokens, canonical entity preservation | Branding may change labels and presentation, never security or canonical semantics. |
| Subscription | Modular module and feature subscription | Entitlement, limits, trial, grace, suspension, usage | Every route/action/API/background job must enforce entitlement before authorization. |
| Access | Supreme Admin, User Admin, Internal User, Customer User | Action + scope + field + status + value; support grants; impersonation | Four layers remain fixed. Supreme Admin has literal absolute CRUD under RPD-022; CargoGrid cannot claim tamper-proof audit/ledger records. Support remains a controlled operating persona. |
| Configuration | UI-based, metadata/configuration-driven | Draft, validate, preview, publish, version, effective date, rollback, dependency check | No tenant-specific backend fork. Critical transactions retain applied config version. |
| Data | Single source of truth, no redundant entry | Canonical customer, shipment, vendor, warehouse, finance, employee data; lineage and ledgers | Conversion must retain upstream IDs and snapshots where required, not copy uncontrolled master data. |
| Commercial | Lead, CRM, opportunity, costing, quotation | Margin/discount approval, versions, acceptance, contract/pricing | Phase 2 owns the first sellable commercial slice. |
| Operations | Full logistics execution | Basic Phase 3 shipment/ePOD slice; advanced TMS/WMS Phase 5 | Basic and advanced scope must be explicitly separated in prompt IDs. |
| Procurement | Full vendor lifecycle | Phase 6 registration, compliance, rates, sourcing, PO, performance, invoice matching | Basic rate lookup needed by Phase 2 may use platform/vendor master without claiming Phase 6 complete. |
| Finance | Full finance/accounting and double-entry | Phase 4 AR/AP/payment/GL baseline plus integrity tests; Indonesia-first localization | Ledger, period lock, idempotency, reversal, and reconciliation apply to normal operations. Supreme Admin absolute CRUD is an explicit accepted exception. |
| HRIS | Full HR lifecycle | Phase 7 with sensitive data controls and Indonesia-first payroll | Current payroll/tax rules require SME/legal verification, not another product decision. |
| Ticketing | Internal, customer-to-tenant, tenant-to-CargoGrid | SLA, escalation, linked transactions, knowledge base | All three channels require separate scope rules and ownership. |
| Customer Portal | Quote, booking, tracking, ePOD, WMS, invoice, tickets, loyalty | Internal Phase 3/8 increments; no external pilot | Complete portal scope and custom-domain support are required before direct GA. Customer scope is database-enforced. |
| Loyalty | Configurable earning/reward/redemption | Ledger-based, eligibility, fraud hold, liability and reconciliation | Direct point balance edits are forbidden. |
| Reporting | Role-specific, configurable, exportable, auditable | Live transactional reads with read-only policy, query budget, timeout, pagination, and caching | Reporting cannot bypass row/field access. Read replicas/read models are introduced when measured load requires them. |
| Integration | REST, GraphQL, webhook, PostgreSQL queue, n8n | REST and GraphQL ship together; signature, rate limit, idempotency, retry, DLQ | Non-AI providers are implemented case by case without a generic provider abstraction, but remain in the shared codebase without tenant forks. |
| Performance | Efficient, light, scalable | Server Components, selective columns, server pagination, indexes, caching, async jobs | A slow screen or query is a defect; baseline and post-change evidence are mandatory. |
| Delivery | Market-ready complete product | Internal phase gates, full UAT, penetration/performance/DR/finance gates, hardening, RC freeze, go-live, hypercare | No external pilot and no partial-module production claim; all major modules and zero Sev-1/critical defects are required for GA. |

## 4. Phase authority mapping

All phases below are internal build and acceptance increments. RPD-001 and RPD-034 prohibit treating an intermediate phase as an external pilot or GA release.

| Phase | Authoritative scope source | Required source sections | Exit-control source |
|---|---|---|---|
| Phase 0 Discovery/Foundation | Charter §§39–40; Delivery §8 | Brief §§1–16; all source registers | Delivery §§14–18; Architecture acceptance §38 |
| Phase 1 Platform Core | Charter §40; BPR PLT-* | UX §§6,17,24–29; Tech §§7–17,22–32 | Delivery Phase 1 gate, tenant-isolation suite |
| Phase 2 Commercial | BPR COM-*; Brief §7.1 | UX flow 7.2; Tech shared engines/API | Delivery Phase 2 gate and commercial UAT |
| Phase 3 Operations MVP | BPR OPS-SHP/TRK/DOC/CST + basic TMS | UX flow 7.3; Tech document/storage/jobs | Delivery Phase 3 gate and UAT-E2E-009..015 |
| Phase 4 Finance MVP | BPR FIN-*; Brief §7.4 | Tech §24; UX financial access | Delivery §§23,27 finance gate |
| Phase 5 Advanced TMS/WMS | Brief §§7.2; BPR OPS-TMS/WMS | UX warehouse flow; Tech scale controls | Delivery Phase 5 performance/inventory gate |
| Phase 6 Procurement/Vendor | Brief §7.3; BPR PRC-* | UX vendor flow; finance/AP linkage | Delivery Phase 6 gate |
| Phase 7 HRIS/Ticketing | Brief §§7.5–7.6; BPR HRS-*/TKT-* | UX HR/ticket flows; sensitive-field rules | Delivery Phase 7 gate |
| Phase 8 Portal/Loyalty | Brief §§3.4,7.7; BPR CPT-*/LYL-* | UX customer portal; Tech loyalty ledger | Delivery Phase 8 customer isolation/fraud gate |
| Phase 9 Intelligence/Enterprise | Brief §16; Charter Phase 9 | Tech scale/enterprise architecture | Delivery Phase 9 governance/security gate |

## 5. Source artifact extraction

| Artifact class | Source | Extracted baseline |
|---|---|---|
| Confirmed decisions | Brief §15 | 23 decisions |
| Explicit functional requirements | BPR §9 | 184 IDs across 46 families |
| Explicit NFR IDs | BPR §9 | 10 IDs across performance, security, audit, reliability, API |
| Business rules | BPR §10 | 24 rules |
| Approval patterns/use cases | BPR §11 | 13 patterns; 14 process rows |
| Lifecycle/exception | BPR §§12–13 | 24 transitions; 16 exceptions |
| Canonical data domains | BPR §14; UX §§19–23 | Customer, shipment, vendor, warehouse, finance, employee plus ticket/loyalty concepts |
| UX surfaces | UX §§6–18 | 3 portals, global/module navigation, flows, screen/state behavior |
| Access controls | UX §§24–28; Tech §§10–12,23 | RLS, RBAC, field/record scope, support/impersonation, storage |
| Architecture controls | Tech §§1–38 | Modular monolith, shared-schema default, server-first, integration, jobs, observability, recovery |
| UAT/security/finance tests | Delivery §§19–23 | 20 E2E UAT, 18 tenant-isolation, 24 finance tests |
| Migration/release/go-live | Delivery §§24–32 | Rehearsal, reconciliation, deployment, cutover, rollback, readiness, support, PIR |

## 6. Citation convention for future prompts

Every future implementation prompt must cite at least one source requirement using this format:

`Source: [Document ID or logical filename] §<section>, Requirement <ID/range>, Rule <ID if applicable>, Test <ID if applicable>`

Example:

`Source: CG-BPR-002 §9 COM-QTN-001..004; §10 BR-QTN-001..003; CG-UXDA-003 §§7.2,16; CG-DTGL-005 UAT-E2E-006..008.`

If a requirement has no explicit source ID, use a package ID created in `05_REQUIREMENT_COVERAGE_MATRIX.md`; do not invent IDs inside an implementation prompt.

## 7. Source quality findings

- The six documents are strongly aligned on product identity, security posture, configuration, data lineage, performance, and phase sequence.
- The BPR requirement matrix is broad but mechanically repetitive: each family has four generic requirements. Atomic prompts must decompose these into actual business capabilities and must not treat one generic row as sufficient implementation detail.
- Several NFR IDs are referenced in the NFR catalogue but absent from the explicit requirement matrix. They are registered as coverage gaps, not silently treated as complete.
- Some apparent contradictions are phase distinctions or explicit RPD exceptions. All product decisions are closed in `04_CONFLICT_REGISTER.md`; remaining items are implementation, discovery, test, or compliance gates.
