# Assumption Register

**Document ID:** `CG-AABPP-CTRL-003`  
**Version:** `0.1.1`  
**Status:** `FINAL_FOR_STEP`  
**Default status:** `APPROVED_DEFAULT`

## 1. Governance

An assumption fills a source gap without changing a Confirmed Product Decision. RPD-040 ratifies every non-conflicting row as `APPROVED_DEFAULT`. The owner and gate columns now identify implementation verification, test calibration, legal/SME verification, or repository discovery—not a pending product decision. Rows revised by RPD-001..039 already contain the binding replacement language below.

## 2. Charter assumptions

| Package ID | Source ID | Approved Default | Impact | Owner / verification gate |
|---|---|---|---|---|
| ASM-CH-001 | A-01 | Charter review quarterly and after material strategy/architecture/regulatory change. | Governance cadence | Product Office / each quarter |
| ASM-CH-002 | A-02 | Initial GTM uses land-and-expand. | Packaging, first external GA customer and expansion sequence | CPO/Commercial / launch pricing review |
| ASM-CH-003 | A-03 | External positioning has executive, functional, and technical message layers. | Marketing and sales enablement | Marketing/Product / message test |
| ASM-CH-004 | A-04 | Indonesia is the initial market. | Localization, region, support, legal baseline | Founder/Commercial / annual strategy |
| ASM-CH-005 | A-05 | Responsive online-first PWA and Intelligence & AI are in the first-production scope; native mobile and offline synchronization are deferred. | Roadmap and architecture | Product Council / roadmap verification |
| ASM-CH-006 | A-06 | Shared multi-tenant database with tenant-aware schema and RLS is default. | Data architecture and isolation risk | CTO/Security / architecture review |
| ASM-CH-007 | A-07 | Dedicated enterprise instance can be a premium option. | Enterprise architecture and price | CTO/Commercial / demand validation |
| ASM-CH-008 | A-08 | App Router and Server Components are Next.js defaults. | Frontend architecture | Engineering / technical design authority |
| ASM-CH-009 | A-09 | Common server reads target p95 ≤500 ms excluding third-party latency. | Performance budget | Engineering/SRE / load test |
| ASM-CH-010 | A-10 | Availability follows RPD-030: Standard 99.5%, Premium 99.9%, Enterprise 99.95%, unless a signed contract replaces the target. | SLA, monitoring, architecture cost | SRE/Legal / pre-GA evidence |
| ASM-CH-011 | A-11 | RPO/RTO are contract-specific; when the contract is silent, recovery is best effort with no guarantee. | Backup/DR plan and cost | SRE/Security / DR rehearsal and contract check |
| ASM-CH-012 | A-12 | Implementation packages are Fast-track, Standard, and Enterprise. | Commercial scope and delivery model | Implementation Office / price-book verification |
| ASM-CH-013 | A-13 | Pricing combines platform, module, user/usage, and implementation fees. | Billing/entitlement and commercial model | Commercial/Finance / pricing workshop |
| ASM-CH-014 | A-14 | Tenant owns customer data; CargoGrid acts per contract role. | Privacy, contracts, offboarding | Legal/Security / contract design |
| ASM-CH-015 | A-15 | NIST CSF, OWASP ASVS, and ISO 27001 readiness are references, not certification claims. | Security program | Security / annual plan |
| ASM-CH-016 | A-16 | Phase 4 may begin with operational billing, AR/AP, payment, and job profitability, but complete Indonesia-first Finance is required before GA. | Internal Phase 4 cutline and GA scope | Product/Finance SME / finance verification |
| ASM-CH-017 | A-17 | HRIS and Loyalty may follow Commercial in the internal build sequence, but both are required before GA. | Internal sequencing, not production scope | Product Council / GA coverage check |
| ASM-CH-018 | A-18 | Analytics replica/warehouse is introduced when OLTP workload requires it. | Scale architecture | Data/Engineering / capacity threshold |
| ASM-CH-019 | A-19 | Implementation partners can change configuration only within delegated scope. | Partner IAM and audit | Partner Office/Security / agreement |
| ASM-CH-020 | A-20 | There is no external pilot; every production tenant still uses controlled feature flags and migration support. | Direct-GA safety | Product/Implementation / production kickoff |

## 3. Business-process assumptions

| Package ID | Source ID | Approved Default | Impact | Owner / verification gate |
|---|---|---|---|---|
| ASM-BP-001 | BP-A01 | Requirement release mapping follows Charter Phase 1–9. | Coverage sequencing | Product Owner / roadmap review |
| ASM-BP-002 | BP-A02 | Platform Core, Commercial, Operations, and finance-readiness form an internal build milestone only; first production requires every major module suite. | Internal milestone definition | CPO/CTO / phase gate and GA coverage check |
| ASM-BP-003 | BP-A03 | Approval uses a generic metadata rule evaluator. | Core engine architecture | Solution Architect / design review |
| ASM-BP-004 | BP-A04 | Tenant lifecycle labels are configurable while canonical lifecycle remains stable. | Reporting/integration consistency | Product/Data Architect / data model review |
| ASM-BP-005 | BP-A05 | Indonesia finance localization is phased; full multi-country localization is not MVP. | Tax/accounting scope | Finance SME / finance design |
| ASM-BP-006 | BP-A06 | Portal capabilities may be built in Phase 3/8 increments, but the complete portal and custom-domain support are required before GA. | Internal Phase 3/8 split | Product Owner / Phase 8 and GA verification |
| ASM-BP-007 | BP-A07 | Driver/field capture begins as responsive web/PWA. | Mobile UX and offline scope | Product/Engineering / Operations UAT |
| ASM-BP-008 | BP-A08 | Vendor self-registration is tenant-configurable, not globally mandatory. | Vendor portal and security | Procurement PO / tenant config |
| ASM-BP-009 | BP-A09 | Dashboards read transactional tables directly with read-only access, timeouts, pagination, caching, and query budgets; replicas are added when measured load requires them. | Reporting performance | Data Engineering / performance gate |
| ASM-BP-010 | BP-A10 | Posted journal is immutable for non-Supreme roles and normal correction uses reversal/adjustment; Supreme Admin has the explicit absolute-CRUD exception in RPD-022. | Financial integrity and accepted governance risk | Finance SME / Finance UAT and risk disclosure |
| ASM-BP-011 | BP-A11 | Initial shipment modes are land, air, sea; rail/customs/advanced cross-border are phased. | Operations cutline | Operations PO / release planning |
| ASM-BP-012 | BP-A12 | Large bulk import is asynchronous. | Reliability/performance | Engineering / performance test |
| ASM-BP-013 | BP-A13 | Permission matrix stores action and field policy, not menu access only. | IAM scope | Security Architect / security review |
| ASM-BP-014 | BP-A14 | Audit minimum: actor, change, time, before/after, reason, source, IP/device, correlation ID. | Audit schema and storage | Security/Data / audit UAT |
| ASM-BP-015 | BP-A15 | Tickets can link to shipment, invoice, warehouse order, vendor, customer, or user. | Polymorphic linkage and access | Service PO / ticket design |

## 4. UX, data, and access assumptions

| Package ID | Source ID | Approved Default | Impact | Owner / verification gate |
|---|---|---|---|---|
| ASM-UX-001 | UX-A01 | Internal ERP is desktop-first with responsive tablet/mobile support. | Design system and QA matrix | UX Lead / prototype validation |
| ASM-UX-002 | UX-A02 | Customer Portal is mobile-friendly from first release. | Portal layout and performance | Product/UX / customer UAT |
| ASM-UX-003 | UX-A03 | Navigation is separated into Supreme, Tenant Internal, and Customer portals. | Routing, mental model, security | Product/Architecture / IA review |
| ASM-UX-004 | UX-A04 | Configuration mode is separate from transaction mode. | Navigation and privilege safety | UX/Product / usability test |
| ASM-UX-005 | UX-A05 | Tables use server-side filter, sort, search, pagination by default. | Data access architecture | Frontend/Data / performance test |
| ASM-UX-006 | UX-A06 | Cursor pagination applies to shipment events, ledgers, audit, tickets, invoices, exports. | High-volume query patterns | Backend/Data / load test |
| ASM-UX-007 | UX-A07 | Saved views are per user; shared views can target role/team. | Preference metadata | UX/Frontend / internal UAT and customer feedback |
| ASM-UX-008 | UX-A08 | Field policy covers visibility, editability, masking, export, print, filter, audit. | Authorization and data projection | Security/Data / review |
| ASM-UX-009 | UX-A09 | Canonical entity/status survives tenant terminology changes. | Data/report/API stability | Data Architect / model review |
| ASM-UX-010 | UX-A10 | File access combines tenant, record scope, classification, signed URL expiry. | Storage security | Security / penetration test |
| ASM-UX-011 | UX-A11 | Support access is time-bound, purpose-bound, logged, visible. | Privileged access | Security/Support / process UAT |
| ASM-UX-012 | UX-A12 | Complex dashboards query live transactional data under read-only query budgets, caching, timeout, and pagination controls; replicas are introduced at measured thresholds. | OLTP protection | Data/Engineering / load-test gate |
| ASM-UX-013 | UX-A13 | Bulk import/export is async with progress and error artifact. | Job framework | Frontend/Backend / UAT |
| ASM-UX-014 | UX-A14 | Approval UX shows step, approver, SLA, escalation, comments, audit timeline. | Management usability | Product/UX / manager UAT |
| ASM-UX-015 | UX-A15 | Mobile warehouse/dispatch/ePOD uses task flows, not desktop table replication. | Field productivity | UX/Ops SME / field UAT |

## 5. Technical architecture assumptions

| Package ID | Source/ADR | Approved Default | Impact | Owner / verification gate |
|---|---|---|---|---|
| ASM-TA-001 | Tech §1; ADR-003 | Start with modular monolith. | Repository/domain boundaries | CTO/ARB / architecture gate |
| ASM-TA-002 | Tech §§9–10; ADR-004 | Shared DB/shared schema is default tenancy. | RLS, indexing, migration | CTO/Security / isolation benchmark |
| ASM-TA-003 | ADR-005 | Dedicated Enterprise instance/region/hosting is an available premium contractual option. | Deployment operations | CPO/CTO / signed deployment design |
| ASM-TA-004 | ADR-006 | REST `/v1` and GraphQL public APIs are delivered together and share security/version controls. | API conventions/versioning | API Architect / contract and negative tests |
| ASM-TA-005 | ADR-009 | Server Actions are used for suitable internal mutations. | Application boundary | Engineering / code review |
| ASM-TA-006 | ADR-010 | Edge Functions are selective, not the default backend. | Runtime ownership | CTO / architecture review |
| ASM-TA-007 | Tech §7.12 | Verified custom-domain routing primitives are part of Platform Core for every supported surface. | Domain resolution and routing | Product/Architecture / internal UAT |
| ASM-TA-008 | Tech §7.1 | Proposed folder structure uses route groups and domain/server layers. | Repository structure | Tech Lead / Step 2 discovery |
| ASM-TA-009 | Tech §§8,32.11 | PostgreSQL durable queue is the initial async mechanism; separate workers are added at measured load/isolation/runtime thresholds. | Infrastructure baseline approved | CTO/DevOps / Step 3 implementation ADR |
| ASM-TA-010 | Tech §27.2 | Git uses trunk-based development with short-lived branches. | CI and collaboration | Engineering Lead / repo policy |
| ASM-TA-011 | Tech §31.2 | RPO/RTO are contract-specific; a silent contract receives best-effort recovery without a guarantee. | Backup/DR | SRE/Security / rehearsal and contract verification |
| ASM-TA-012 | Tech §32.1 | Detailed performance budgets are initial targets requiring load-test calibration. | Release gates | SRE/QA / phase tests |
| ASM-TA-013 | Tech §32.7 | Slow-query thresholds start at 500 ms common API, 2 s complex report. | Monitoring/backlog | Data/SRE / production-like test |
| ASM-TA-014 | Tech §32.15 | Every upload is malware-scanned before policy allows access by another user. | Upload security scope | Security / threat model and upload tests |

## 6. Delivery and go-live assumptions

| Package ID | Source ID | Approved Default | Impact | Owner / verification gate |
|---|---|---|---|---|
| ASM-DG-001 | DTG-A01 | Agile delivery with phase-gated release. | Delivery governance | Delivery Lead / Sprint 0 |
| ASM-DG-002 | DTG-A02 | Modular monolith first is delivery baseline. | Workstream structure | CTO/Delivery / architecture review |
| ASM-DG-003 | DTG-A03 | Internal MVP milestones may exclude later modules; GA and first production require all major module suites. | Internal sequence versus production scope | CPO / roadmap and GA gate |
| ASM-DG-004 | DTG-A04 | Platform Core/isolation/config/audit/entitlement precede all production work; there is no external pilot. | Critical path | CTO/QA / Phase 1 and GA exit |
| ASM-DG-005 | DTG-A05 | Lead-to-cash and shipment-to-billing are primary critical paths, while GA UAT must cover every major module suite and the full source scenario catalogue. | Acceptance strategy | Product/Implementation / UAT evidence |
| ASM-DG-006 | DTG-A06 | Onboarding models are Fast-track, Standard, and Enterprise. | SOW and readiness | Implementation / price-book and SOW verification |
| ASM-DG-007 | DTG-A07 | Every production tenant uses feature flags for controlled activation. | Release control | DevOps/Product / release gate |
| ASM-DG-008 | DTG-A08 | Automated suite covers RLS, RBAC, tenancy, workflow, approval, finance posting. | CI quality | QA Lead / CI gate |
| ASM-DG-009 | DTG-A09 | Penetration test is mandatory before GA and major enterprise deployment. | Security release gate | Security / pre-GA |
| ASM-DG-010 | DTG-A10 | Performance tests run per relevant phase. | Continuous performance | DevOps/QA / phase gate |
| ASM-DG-011 | DTG-A11 | Enterprise migration has at least two rehearsals. | Cutover plan | Data Migration Lead / readiness |
| ASM-DG-012 | DTG-A12 | Hypercare minimum: 2 weeks Standard, 4 weeks Enterprise. | Support capacity | Customer Success / contract |
| ASM-DG-013 | DTG-A13 | SLA differentiates incident, implementation, data, feature request. | Support model | Support Lead / readiness |
| ASM-DG-014 | DTG-A14 | Finance cannot go live without setup, balances, reconciliation, period lock and posting tests. | Finance blocker | Finance SME/QA / UAT |
| ASM-DG-015 | DTG-A15 | Open Sev-1, critical security/isolation/finance defects block production. | Go/no-go | Steering Committee / release |
| ASM-DG-016 | DTG-A16 | Documentation is part of Definition of Done. | Every task | Product/CS / sprint review |
| ASM-DG-017 | DTG-A17 | Large import/export is asynchronous. | Performance/reliability | Engineering / performance gate |
| ASM-DG-018 | DTG-A18 | Tenant-specific source forks are rejected. | Product integrity | CPO/CTO / change control |
| ASM-DG-019 | DTG-A19 | DR test occurs before GA and after major recovery-architecture change. | Production readiness | DevOps/Security / DR gate |
| ASM-DG-020 | DTG-A20 | Partners change configuration only in delegated scope. | Partner access | Partner/Security / onboarding |

## 7. Package-level approved defaults introduced in Step 0

| Package ID | Approved Default | Rationale | Risk | Owner / verification gate |
|---|---|---|---|---|
| ASM-PK-001 | Vercel is the fixed Next.js deployment baseline for this package. | Master prompt explicitly fixes Vercel. | Could constrain enterprise hosting later. | CTO / Step 3 ADR confirms baseline vs optional enterprise deployment |
| ASM-PK-002 | “Absolute CRUD” for Supreme Admin includes mutation and deletion of audit, ledger, payment, and final records. | RPD-022 explicitly rejects the earlier restricted interpretation. | CargoGrid cannot claim tamper-proof audit/finance records; retention evidence may be defeated. | Product + Security + Finance / Phase 1 implementation and permanent risk disclosure |
| ASM-PK-003 | Support is an operating persona under Layer 1 authority, not a fifth access layer. | Preserves four-layer decision. | Incorrect permission inheritance. | Product/Security / IAM design |
| ASM-PK-004 | Phase 2 may consume a basic approved vendor/rate lookup foundation; full procurement lifecycle remains Phase 6. | Commercial costing has a hard dependency. | Duplicate vendor/rate implementations. | Product/Architecture / Step 3 dependency plan |
| ASM-PK-005 | Phase 3 contains only basic tracking/ePOD portal capability; Phase 8 completes the portal before GA. | Preserves internal build sequence while satisfying RPD-001. | Premature portal duplication or incomplete GA scope. | Product/UX / Phase 3, Phase 8, and GA gates |
| ASM-PK-006 | Phase 3 WMS references are excluded from MVP unless they are minimal shipment/warehouse handoff primitives; full WMS is Phase 5. | Charter explicitly excludes full WMS from MVP. | Hidden WMS scope creep. | Product/Operations / phase planning |
| ASM-PK-007 | MFA capability is built in Platform Core and enforced for privileged roles first; tenant-wide enforcement remains configurable. | Brief requires MFA; technical doc phases enforcement. | Weak security for non-admin users. | Security / threat model and enterprise policy |
| ASM-PK-008 | New package-generated requirement IDs use `PKG-<AREA>-NNN` and never overwrite source IDs. | Preserves traceability. | ID collision. | Package owner / every manifest validation |

## 8. Closure status

No row in this register requires another product decision. Shared-schema tenancy, queue baseline, custom domains, Enterprise deployment, PostGIS, live-OLTP analytics, Indonesia-first localization, support/SLA, pricing, security, retention, and GA policy are ratified in RPD-001..040. Repository versions, detailed thresholds, per-integration designs, legal currency, and test evidence are execution/discovery obligations and must not be mislabeled as unresolved product decisions.
