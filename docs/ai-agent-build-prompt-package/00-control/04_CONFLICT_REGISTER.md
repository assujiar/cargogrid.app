# Conflict, Gap, Duplicate, and Decision-Closure Register

**Document ID:** `CG-AABPP-CTRL-004`  
**Version:** `0.1.1`  
**Status:** `FINAL_FOR_STEP`  
**Blocking rule:** An unresolved conflict affecting tenant isolation, financial integrity, canonical data integrity, or destructive migration blocks prompt generation for the affected scope.

## 1. Source conflicts and semantic tensions

| ID | Area | Evidence A | Evidence B | Resolution for package | Status / residual risk |
|---|---|---|---|---|---|
| CON-001 | Supreme Admin authority | Brief §3.1 says absolute CRUD across program/tenants. | Charter/UX/Tech require time-bound support, immutable audit and finance, least privilege. | RPD-022 selects literal absolute CRUD, including audit/ledger/final-record mutation and deletion. Normal roles remain governed, but CargoGrid must not claim tamper-proof audit or finance records. | `RESOLVED`; accepted critical governance/compliance risk. |
| CON-002 | Hosting baseline | Tech OD-001 leaves Next.js production hosting open. | Master prompt fixes Vercel deployment baseline. | Use Vercel as fixed baseline. A dedicated/alternative enterprise runtime requires approved ADR and may not alter the default package. | `RESOLVED` by operational instruction. |
| CON-003 | MFA | Brief §12 says CargoGrid must implement MFA. | Tech §23.5 treats MVP MFA for admin/privileged roles and wider enforcement as enterprise policy. | RPD-023 requires MFA for Supreme Admin, tenant admins, finance approvers, and credential managers; tenant-wide enforcement is configurable. Enrollment/recovery mechanics are implementation controls. | `RESOLVED`. |
| CON-004 | WMS release | BPR release mapping labels OPS-WMS Phase 3/5. | Charter MVP explicitly excludes full WMS; roadmap places advanced WMS in Phase 5. | Phases 3/5 are internal delivery increments; full WMS is mandatory before GA under RPD-001. | `RESOLVED`. |
| CON-005 | Customer Portal release | BPR CPT-* maps Phase 3/8. | Charter/Delivery put basic tracking/ePOD in Phase 3 and full portal/loyalty in Phase 8. | Phases 3/8 are internal increments; the complete portal and loyalty suite are mandatory before GA. | `RESOLVED`. |
| CON-006 | Procurement dependency | Commercial requires cost/vendor rate lookup in Phase 2. | Full Procurement/Vendor Management is Phase 6. | Build the canonical vendor/service/rate foundation once in Phase 2 and extend it in Phase 6; domain ownership is an implementation ADR, not a product decision. | `RESOLVED`; Step 3 must document ownership. |
| CON-007 | Finance scope | Brief requires a full financial/accounting system. | Charter MVP excludes full suite; Phase 4 is Finance MVP and localization is phased. | Phase 4 is an internal increment; complete Indonesia-first Finance is mandatory before GA. Normal posting/reversal/lock/reconciliation controls apply, subject to the RPD-022 Supreme Admin exception. | `RESOLVED`. |
| CON-008 | Custom domain timing | Brief includes domain as white-label capability. | Tech §7.12 makes customer portal domain optional in MVP; full internal portal later. | RPD-005 requires verified custom-domain primitives from Platform Core across supported surfaces. | `RESOLVED`. |
| CON-009 | Native/PWA/offline | Brief says PWA optional and native mobile future. | UX wants field/mobile task flows; offline ePOD/WMS remains open. | RPD-004 fixes responsive online-first PWA. Native mobile and offline sync are deferred. | `RESOLVED`. |
| CON-010 | RLS vs field-level protection | Brief names RLS and field-level access. | PostgreSQL RLS is row-level; field masking may be app/view/projection policy. | RLS secures rows; field access uses permission-aware projections/views/functions/API serialization, never client-side hiding only. Both require negative tests. | `RESOLVED`. |
| CON-011 | Configuration flexibility | Brief allows configurable fields/forms/workflows/statuses. | Tech requires stable canonical entities/statuses and finance/security invariants. | Tenant may configure labels, optional fields and governed rules; canonical identity, security minimum, ledger rules, API contracts and audit semantics cannot be overridden. | `RESOLVED`. |
| CON-012 | Applied config behavior | Configuration changes have effective dates/versions. | Sources are not fully explicit whether active transactions migrate automatically. | RPD-040 approves the default: active critical transactions retain their applied configuration version; new versions affect new transactions unless an explicit migration/reprice/re-evaluation rule is executed. | `RESOLVED`; entity rules are implementation specifications. |
| CON-013 | Deletion semantics | Supreme Admin has delete authority. | Tech prescribes soft delete for most data and no delete for ledgers/audit. | Non-Supreme delete maps to archive/cancel/soft delete. RPD-022 lets Supreme Admin hard-delete any record; the retention conflict is an accepted governance risk and must be disclosed. | `RESOLVED`; high residual risk. |
| CON-014 | General availability terminology | Phase releases may be deployable vertical slices. | Master prompt forbids “market-ready” until all blockers and final gate pass. | Only the complete all-module system after internal UAT, penetration, performance, DR, finance, hardening, and zero critical-defect gates may be called GA. There is no external pilot. | `RESOLVED`. |

## 2. Requirement gaps and closure routes

These rows are work-definition, discovery, test-calibration, or compliance-verification obligations. None is an open product decision.

| Gap ID | Missing or insufficient definition | Evidence | Risk | Required closure step | Status |
|---|---|---|---|---|---|
| GAP-001 | Referenced NFR IDs are absent from BPR §9. | BPR §16 | Traceability hole | Create package IDs and detailed acceptance in Step 3/4 without modifying source IDs. | `CLOSED_BY_PACKAGE_IDS` |
| GAP-002 | Engine families lack canonical source IDs. | Master Prompt Phase 1 vs BPR PLT-MDM/CFG | Work may disappear inside generic cards | Add engine-specific package requirement families in Step 3. | `IMPLEMENTATION_SPEC_REQUIRED` |
| GAP-003 | Detailed field-level enforcement design is missing. | UX §26; Tech §§12.4,23 | Sensitive-field leakage | Implement RPD-039 via projection/view/masking/server serialization and negative tests. | `DECISION_CLOSED; ADR_REQUIRED` |
| GAP-004 | Queue/worker technology was undecided. | Tech OD-002 | Inconsistent async framework | Implement PostgreSQL durable queue under RPD-012; scale workers by measured thresholds. | `DECISION_CLOSED` |
| GAP-005 | Repository state is unknown. | Master Prompt Step 2 | Greenfield/brownfield regression | Mandatory code-free Step 2 discovery. | `DISCOVERY_GATE` |
| GAP-006 | Exact framework/tool versions are unknown. | Fixed stack without versions | Compatibility risk | Detect repository versions; for greenfield select supported versions by ADR. | `DISCOVERY_GATE` |
| GAP-007 | Statutory localization detail requires current verification. | Localization sources | Legal/financial defect | Indonesia-first scope is fixed; Finance/HR/legal SMEs verify current rules before production. | `POLICY_CLOSED; COMPLIANCE_GATE` |
| GAP-008 | Retention durations were missing. | Brief §12 | Privacy/storage risk | Apply RPD-025; document the RPD-022 ability to defeat retention. | `DECISION_CLOSED` |
| GAP-009 | Capacity/concurrency values need evidence. | Performance sources | Contract/sizing risk | Calibrate by package and workload; SLA is fixed by RPD-030 unless contracted otherwise. | `TEST_CALIBRATION_GATE` |
| GAP-010 | Support/SLA policy was open. | Charter/BPR | Go-live readiness | Apply RPD-010 and RPD-030. | `DECISION_CLOSED` |
| GAP-011 | Residency/dedicated deployment was open. | Charter/Tech | Enterprise deal risk | Apply APAC default and Enterprise contractual options under RPD-011/RPD-013. | `DECISION_CLOSED` |
| GAP-012 | AI provider/governance was open. | Charter/BPR/Tech | Unsafe/expensive AI | Apply RPD-021 and RPD-028; implementation still requires evaluations and privacy/security tests. | `DECISION_CLOSED; EVALUATION_GATE` |
| GAP-013 | Accessibility level was missing. | BPR §16; UX §13 | Ambiguous release gate | WCAG 2.2 AA under RPD-024. | `DECISION_CLOSED` |
| GAP-014 | Browser window was missing. | BPR/Delivery | Unbounded QA scope | Test two latest stable Chrome, Edge, Safari, Firefox under RPD-024. | `DECISION_CLOSED` |
| GAP-015 | Archival/partition/replica thresholds are qualitative. | Tech §§32–33 | Late or premature scaling | Derive measurable thresholds in the performance workstream. | `TEST_DERIVED` |
| GAP-016 | Search architecture was unspecified. | UX navigation/RLS | Performance/leakage risk | PostgreSQL FTS/trigram plus RPD-039 server field policy; external search only after threshold. | `DECISION_CLOSED; ADR_REQUIRED` |
| GAP-017 | SaaS billing and tenant finance IDs are not separated. | Tech §20 | Domain confusion | Add distinct package requirement families in Step 3 using RPD-007/008/027/028. | `IMPLEMENTATION_SPEC_REQUIRED` |
| GAP-018 | API credential lifecycle needs detail. | Brief/Tech | Integration security risk | Phase 1 requirements must define scope, hash, rotation, revocation, rate limit, audit. | `IMPLEMENTATION_SPEC_REQUIRED` |

## 3. Duplicate and overlap register

Duplicates are not deleted. The package assigns one canonical control and treats other occurrences as supporting evidence.

| DUP ID | Repeated requirement | Occurrences | Canonical owner | Package handling |
|---|---|---|---|---|
| DUP-001 | Strict tenant isolation/RLS | All six sources | Platform Security workstream | One invariant and test suite; every feature references it. |
| DUP-002 | No redundant entry/data lineage | Brief, Charter, BPR, UX, Delivery | Data Architecture + E2E flows | One canonical lineage map; module prompts cite relevant conversion tests. |
| DUP-003 | UI-based configuration | Brief, Charter, BPR, UX, Tech, Delivery | Configuration Engine | One engine workstream; domain prompts add metadata, not parallel builders. |
| DUP-004 | Server-side pagination/selective queries/no `SELECT *` | Brief, Charter, BPR, UX, Tech, Delivery | Performance/Data Access | Shared prompt guardrail and phase performance tests. |
| DUP-005 | Async import/export/report/jobs | Brief, BPR, UX, Tech, Delivery | Job Framework | Build once, reuse across modules. |
| DUP-006 | Signed URLs and file access audit | Brief, Charter, BPR, UX, Tech, Delivery | Document/Storage Engine | Central access service and test fixtures. |
| DUP-007 | Posted-journal integrity | Brief, Charter, BPR, UX, Tech, Delivery | Finance Integrity | One posting/ledger contract for non-Supreme roles; RPD-022 is the explicit absolute-CRUD exception. |
| DUP-008 | Draft/publish/version/rollback/effective date | Brief, Charter, BPR, UX, Tech | Configuration Engine | Shared lifecycle and migration rules. |
| DUP-009 | Support access and impersonation audit | Brief, Charter, UX, Tech, Delivery | Privileged Access | One grant/session/audit model. |
| DUP-010 | Approval patterns | BPR, UX, Tech, Delivery | Approval Engine | One configurable engine and contract test catalogue. |
| DUP-011 | Reporting/read models | Charter, BPR, UX, Tech, Delivery | Reporting/Data | Live OLTP query controls are the baseline under RPD-014; replicas or read models are test-triggered. |
| DUP-012 | Feature flags and controlled rollout | Charter, Tech, Delivery, Master Prompt | Release Platform | One flag primitive; flags never bypass security. |

## 4. Normalized decision backlog — closed

Source aliases are consolidated so the same decision is not tracked several times.

| Open ID | Consolidated decision | Ratified resolution | Status |
|---|---|---|---|
| OD-PKG-001 | First-production feature cutline | All major module suites; phases are internal milestones only. | `CLOSED — RPD-001` |
| OD-PKG-002 | Legal entity and contracting model | Product under SAIKI Group; contracts/invoices by PT SAIKI Group. | `CLOSED — RPD-002/006` |
| OD-PKG-003 | Packages, pricing, metering, SLA | Exact suites, price book, 20 GB usage baseline, fees, support, and SLA fixed. | `CLOSED — RPD-007..010/026..030` |
| OD-PKG-004 | Queue/worker | PostgreSQL durable queue first; separate workers by threshold. | `CLOSED — RPD-012` |
| OD-PKG-005 | Dedicated/alternate hosting | Shared RLS default; paid Enterprise dedicated option. | `CLOSED — RPD-011/013` |
| OD-PKG-006 | Region/residency/multi-region | APAC default; dedicated region/hosting by Enterprise contract. | `CLOSED — RPD-013` |
| OD-PKG-007 | Finance/tax/payroll localization | Indonesia-first, configurable, current SME/legal verification. | `CLOSED — RPD-016` |
| OD-PKG-008 | PWA/native/offline | Responsive online-first PWA; native/offline deferred. | `CLOSED — RPD-004` |
| OD-PKG-009 | Pilot tenants | No external pilot; direct GA after internal gates. | `CLOSED — RPD-003/034/036` |
| OD-PKG-010 | Analytics/warehouse timing | Live OLTP dashboards with guards; replicas/warehouse are threshold-driven. | `CLOSED — RPD-014/039` |
| OD-PKG-011 | AI/OCR | OpenAI multimodal default, human approval, usage billing. | `CLOSED — RPD-021/028` |
| OD-PKG-012 | Enterprise IAM order | OIDC, then SAML, then SCIM. | `CLOSED — RPD-017` |
| OD-PKG-013 | PostGIS | Enabled from Platform Core. | `CLOSED — RPD-015` |
| OD-PKG-014 | Partner program | 10% first-year net referral; implementation partner bills services. | `CLOSED — RPD-018` |
| OD-PKG-015 | White-label constraints | Controlled visual customization; CargoGrid owns UI structure. | `CLOSED — RPD-019` |
| OD-PKG-016 | Tenant merge/split | Admin-run governed migration; no self-service. | `CLOSED — RPD-020` |

## 5. Blocker summary

There are zero unresolved product decisions and zero provisional conflict resolutions. Step 1 may proceed. Step 2 discovery remains mandatory and code-free; detailed ADRs, repository versions, test-derived thresholds, integration-by-integration design, and legal/SME verification are execution gates rather than requests for founder decisions.
