# Confirmed Product Decision Register

**Document ID:** `CG-AABPP-CTRL-002`  
**Version:** `0.1.1`  
**Status:** `FINAL_FOR_STEP`  
**Change authority:** Steering Committee plus update to the Product Concept Brief

## 1. Control rule

The 23 decisions below are extracted from `CargoGrid_Product_Concept_Brief.md` §15. They are immutable inputs to the prompt package. A coding agent may not reinterpret them as optional, remove them to simplify delivery, or replace them with an industry convention.

| ID | Confirmed decision | Binding interpretation | Required control/evidence | Source |
|---|---|---|---|---|
| CPD-001 | Product name is CargoGrid | Canonical product identity is `CargoGrid`; white-label may change tenant-facing product name without changing internal identity. | Branding config retains canonical tenant/product references. | Brief §15 |
| CPD-002 | Model is SaaS ERP | Product is a reusable subscription platform, not a custom project or a set of disconnected pages. | Entitlement, tenancy, release, onboarding, support, and SaaS operations exist. | Brief §§1,15 |
| CPD-003 | Target market is 3PL and logistics-related companies | Domain model must support 3PL, freight forwarding, cargo, trucking, warehouse, distribution, project logistics, and in-house logistics. | Logistics-native entities and workflows; no generic-ERP-only model. | Brief §§1,15 |
| CPD-004 | Multi-tenant | Multiple tenants share the product while data and control boundaries remain isolated. | Tenant context in data, storage, cache, jobs, logs, reports, exports, integrations; negative tests. | Brief §§1,4,15 |
| CPD-005 | White-label | Tenant branding, domain, templates, portal, and terminology are configurable. | Verified domain, versioned branding, canonical semantic preservation, white-label regression matrix. | Brief §§4,15 |
| CPD-006 | Row-Level Security | RLS is a primary database control for tenant-facing data. | Default-deny policies, migration checks, RLS regression, cross-tenant negative tests. | Brief §§1,12,15 |
| CPD-007 | Role-Based Access Control | Actions are governed by role and configurable permissions. | Action-level authorization plus scope; RBAC tests for allowed and denied actions. | Brief §§1,3,12,15 |
| CPD-008 | Four user layers | Layers are Supreme Admin, User Admin, Internal Organizational User, and Customer User. | Separate portal/data boundaries; layer-specific test identities; no accidental fifth product layer. | Brief §§3,15 |
| CPD-009 | Configurable hierarchy | Tenant can change titles, levels, reporting lines, and approval authority. | UI builder, versioning, cycle detection, preview, effective date, audit. | Brief §3.3, §15 |
| CPD-010 | Configurable role and permission | Supreme Admin/User Admin can create role titles and access scope within authority. | Module/action/scope/field/status/value policies configurable through UI. | Brief §§3,5,15 |
| CPD-011 | Configurable module | Module and feature availability are subscription/entitlement controlled. | Tenant/module/feature/effective date/limit/trial/suspension enforcement. | Brief §§1,5,15 |
| CPD-012 | Configurable workflow | Business and operational workflow can vary per tenant through metadata. | Draft/test/publish/version/effective date/rollback/dependency validation. | Brief §§1,5,15 |
| CPD-013 | Configurable approval | Approval path, threshold, actor, delegation, escalation, rejection, revision, and resubmission are configurable. | Generic approval engine; no per-screen hardcoding; audit and negative tests. | Brief §§1,5,15 |
| CPD-014 | Configurable service | Service, mode, coverage, SLA, weight/volume, cost/revenue, documents, milestone, and eligibility are configurable. | Service builder and versioned rule snapshot on affected transactions. | Brief §§5,8,15 |
| CPD-015 | UI-based configuration | Authorized administrators configure product behavior through supported interfaces. | Admin UX with validation, preview, publish, rollback, access control, and audit. | Brief §§3.1,5,15 |
| CPD-016 | Tenant configuration requires no backend source-code change | Normal tenant variance must not require source fork or hardcoded tenant branch. | Metadata/rule/template/feature-flag solution; divergence review rejects source forks. | Brief §§1,5,14–15 |
| CPD-017 | End-to-end process | CargoGrid covers lead-to-revenue, booking-to-delivery, vendor-to-payment, employee-to-performance, and transaction-to-loyalty. | Cross-module transactional flows and E2E tests; no terminal CRUD silos. | Brief §§2,6,14–15 |
| CPD-018 | Modules are directionally and transactionally connected | Downstream records maintain governed upstream links and business events. | Foreign keys/references, lineage, integration tests, compatibility controls. | Brief §§2,6,15 |
| CPD-019 | No redundant data entry | Existing valid data is reused; re-entry is allowed only for a justified, auditable override or snapshot rule. | Conversion tests, duplicate detection, canonical masters, override reason and audit. | Brief §§2,6,15 |
| CPD-020 | Next.js frontend | Next.js + TypeScript + React is the application stack; master prompt fixes App Router and strict mode. | Detected/approved versions, server-first boundary, build/typecheck gates. | Brief §§9,15; Master Prompt §3 |
| CPD-021 | Supabase backend | Supabase/PostgreSQL/Auth/RLS/Storage form the baseline; selective Realtime/Edge Functions. | Environment separation, migration discipline, generated types, secret controls. | Brief §§9,15; Master Prompt §3 |
| CPD-022 | Customer and shipment data must be comprehensive | Canonical customer and shipment entities must serve commercial, operations, finance, portal, reporting, and audit. | Data dictionary, constraints, lineage, migration mapping, field access, completeness tests. | Brief §§11,15 |
| CPD-023 | Backend and API must be efficient, light, and scalable | Performance is part of product correctness. | Selective queries, pagination, tenant-aware indexes, async work, limited realtime, budgets and evidence. | Brief §§10,15 |

## 2. Derived non-negotiable product invariants

These are direct consequences of the confirmed decisions and source documents; they do not introduce a new product direction.

| Invariant ID | Invariant | Derived from | Failure classification |
|---|---|---|---|
| INV-001 | No service-role credential in browser/client code. | CPD-004, CPD-006, CPD-021 | Critical security blocker |
| INV-002 | Every tenant-scoped table has RLS or an approved, tested compensating control. | CPD-004, CPD-006 | Critical tenant-isolation blocker |
| INV-003 | Every private file download is permission-checked and time-bound. | CPD-004, CPD-007 | Critical/high data exposure |
| INV-004 | Lower-level configuration cannot weaken platform security minimums. | CPD-009..016 | Critical/high security defect |
| INV-005 | Posted journals are immutable for every role except Supreme Admin; normal correction uses reversal/adjustment. RPD-022 gives Supreme Admin explicit mutation and deletion authority, so CargoGrid must not claim that journals are tamper-proof. | CPD-002, CPD-017..019; RPD-022 | Any non-Supreme bypass is a critical financial-integrity blocker; Supreme Admin mutation is an accepted governance risk. |
| INV-006 | Inventory and loyalty balances change through ledgers for every role except Supreme Admin. RPD-022 is the explicit exception and must never be presented as an immutable-ledger design. | CPD-017..019; RPD-022 | Any non-Supreme direct edit is a critical/high integrity defect; Supreme Admin mutation is an accepted governance risk. |
| INV-007 | Critical configuration is versioned, effective-dated, validated, auditable, and rollback-aware. | CPD-009..016 | Phase blocker |
| INV-008 | Reports, exports, search, cache, jobs, realtime, and integrations enforce the same tenant/field/record boundaries. | CPD-004, CPD-006, CPD-007 | Critical tenant/data exposure |
| INV-009 | High-volume lists use server-side filtering, sorting, search, and pagination. | CPD-023 | Performance blocker |
| INV-010 | Heavy import/export/report/document/batch workloads are asynchronous. | CPD-023 | Reliability/performance blocker |
| INV-011 | Every retriable mutation, webhook, posting, and eligible ledger event is idempotent. | CPD-017..019, CPD-023 | High/critical duplicate transaction defect |
| INV-012 | Tenant-specific source-code forks are not a supported operating model. | CPD-002, CPD-016 | Architecture/product blocker |

## 3. Fixed technical baseline from the master prompt

The following details operationalize CPD-020 and CPD-021 for this package. They cannot be changed without an approved ADR and, where applicable, an updated master instruction:

- Next.js App Router, React, TypeScript strict mode.
- Server Components by default for data-heavy and sensitive views.
- Client Components only at interaction boundaries.
- Server Actions where appropriate for internal mutations.
- Route Handlers for API boundaries.
- SSR, static generation, revalidation, streaming, and caching according to use case.
- Supabase Auth, PostgreSQL, RLS, Storage; Realtime and Edge Functions selectively.
- Vercel baseline for Next.js and separate Supabase environments for Local, Development, Testing, Staging, UAT, Production.
- CI/CD, feature flags, monitoring, alerting, backup, recovery, and rollback.

## 4. Ratified founder decisions

The following decisions were explicitly ratified on 2026-07-13. They close the normalized product, commercial, architecture, security, delivery, and operating-policy backlog. If a row conflicts with a source Proposed Default, this row supersedes that default. If it creates an explicit exception to a source invariant, the exception and residual risk must remain visible.

| ID | Ratified decision | Binding interpretation |
|---|---|---|
| RPD-001 | First production release includes all major modules. | Phases 0–9 are internal build, test, and acceptance milestones only. No partial module slice may be called GA or production-complete. |
| RPD-002 | CargoGrid is owned under SAIKI Group. | SAIKI Group is the product owner and umbrella brand. |
| RPD-003 | First production tenant is external. | The first live customer is not an internal SAIKI/UGC tenant. |
| RPD-004 | Mobile baseline is responsive PWA, online-first. | Native mobile and offline synchronization are not required for first production. |
| RPD-005 | Custom domain is available from Platform Core. | Verified custom-domain primitives apply across supported CargoGrid surfaces from Platform Core. |
| RPD-006 | PT SAIKI Group is the legal contracting entity. | PT SAIKI Group signs customer/partner contracts and issues invoices; external contracting requires the entity to be legally active. |
| RPD-007 | Commercial packaging is modular. | Platform Core/Foundation is mandatory; suites and add-ons are separately entitled. |
| RPD-008 | Subscription pricing combines platform, module, active user, and usage. | Billing and entitlement must meter all four dimensions plus implementation services. |
| RPD-009 | Implementation has Fast-track, Standard, and Enterprise tiers. | Target duration is 1–3, 4–8, and 8–24+ weeks; included hypercare is 2 weeks Standard and 4 weeks Enterprise. |
| RPD-010 | Support is tiered. | Standard uses Indonesian business hours, Premium extended coverage, and Enterprise 24/7 for P1. |
| RPD-011 | Shared database/shared schema with RLS is default; Enterprise may use a dedicated instance. | Shared tenancy is the default operating model; dedicated deployment is a paid Enterprise option. |
| RPD-012 | PostgreSQL durable queue is the initial background-job mechanism. | Separate workers are introduced when load, isolation, or runtime requirements justify them; n8n is not the primary job engine. |
| RPD-013 | APAC is the default region; Enterprise may request dedicated region/hosting. | Region and deployment exceptions are contractual Enterprise options. |
| RPD-014 | Dashboards read transactional data directly. | Live OLTP reporting is accepted, with read-only queries, timeouts, pagination, caching, query budgets, and read replicas when scale requires them. |
| RPD-015 | PostGIS is enabled from Platform Core. | Location, distance, geofence, and routing primitives may depend on PostGIS from the foundation. |
| RPD-016 | Finance, tax, and payroll are Indonesia-first. | Rules must be configurable and verified by current legal/finance/HR SMEs; multi-country localization follows later. |
| RPD-017 | Enterprise IAM order is OIDC, then SAML, then SCIM. | Delivery sequence follows that order unless a signed customer contract changes priority. |
| RPD-018 | Partner model uses 10% first-year net subscription referral share. | Certified Implementation Partners bill their own implementation services; no additional recurring delivery share is implied. |
| RPD-019 | Controlled white-label. | Tenant may change logo, colors, domain, email, and document presentation; CargoGrid controls component structure and interaction patterns. |
| RPD-020 | Tenant merge/split is an admin-run migration. | It requires preflight, approval, backup, reconciliation, and audit evidence; no tenant self-service merge/split. |
| RPD-021 | OpenAI multimodal is the default AI/OCR extraction and classification provider. | Use a provider boundary and human approval before financial/legal posting; AI may not autonomously post ledgers, payments, or legal status changes. |
| RPD-022 | Supreme Admin has absolute CRUD. | Supreme Admin may alter or delete any record, including audit, journal, payment, and final records. CargoGrid must not claim immutable/tamper-proof records; retention and audit evidence can be defeated by this authority. |
| RPD-023 | MFA is mandatory for privileged roles. | Supreme Admin, tenant admin, finance approver, and credential manager must enroll; tenants may require MFA for everyone. |
| RPD-024 | Accessibility target is WCAG 2.2 AA. | QA covers the two latest stable releases of Chrome, Edge, Safari, and Firefox. |
| RPD-025 | Retention uses a class-based schedule. | Finance/tax records: 10 years; audit/security: 7 years; operational data: contract term +90 days; backups: 35 days; legal hold overrides deletion. |
| RPD-026 | Module catalogue has ten suites. | Platform Core; Commercial; Operations/TMS/WMS; Procurement & Vendor; Finance; HRIS; Service Desk & Customer Portal; Loyalty; Intelligence & AI; Enterprise Controls. |
| RPD-027 | Launch price book is approved. | Monthly list prices excluding PPN: Core Rp12.5m; Commercial Rp4m; Operations Rp10m; Procurement Rp4m; Finance Rp6m; HRIS Rp5m; Service/Portal Rp4m; Loyalty Rp2m; Intelligence Rp5m; Enterprise Controls Rp7.5m. Includes 25 active users; additional users Rp125k/user/month; annual prepay -10%; monthly billing +20%. |
| RPD-028 | Usage charging is approved with 20 GB included. | Additional storage is Rp3,000/GB/month. AI/OCR, messaging, maps, e-sign, and third-party services are billed at actual provider cost +20% with customer-visible metering. |
| RPD-029 | Launch implementation fees are approved. | Fast-track Rp25m; Standard Rp75m; Enterprise starts at Rp250m, excluding PPN and out-of-scope work. |
| RPD-030 | SLA A is the default, with contractual customization permitted. | Standard: 99.5% and P1 response 4 business hours; Premium: 99.9%/1 hour; Enterprise: 99.95%/15 minutes 24/7; service credits 5%–25%. A signed contract may replace these targets. |
| RPD-031 | RPO/RTO are contract-specific. | No universal recovery target is marketed as part of a package. |
| RPD-032 | Every uploaded file is malware-scanned. | A file cannot be released to another user until the scan policy permits access. |
| RPD-033 | REST and GraphQL public APIs are built together. | Both interfaces share authentication, authorization, field policy, rate limit, idempotency, audit, and version governance. |
| RPD-034 | There is no external pilot. | CargoGrid moves directly to GA after internal go-live gates; the first external tenant is a production customer, not a pilot. |
| RPD-035 | The tenant owns its customer and operational data. | Support access is time-bound, purpose-bound, logged, and tenant-visible. |
| RPD-036 | Direct GA requires full internal validation. | Internal UAT, penetration test, performance test, DR rehearsal, finance reconciliation, all modules, and zero open Sev-1/critical defects are GA blockers. |
| RPD-037 | Missing contractual RPO/RTO means best effort. | Production is allowed without a recovery target; CargoGrid makes no guaranteed recovery commitment when the contract is silent. |
| RPD-038 | Non-AI third-party integrations are custom and have no generic provider abstraction. | Maps, messaging, payment, e-sign, and tax connectors are implemented case by case in the shared product codebase. Tenant-specific source forks remain prohibited. |
| RPD-039 | Search and field security start in PostgreSQL/server policy. | Use PostgreSQL full-text/trigram and server-side projection/view/masking/serialization; external search is introduced only after measured thresholds. |
| RPD-040 | All non-conflicting Proposed Defaults are approved. | Test-derived thresholds, repository/version discovery, and legal/SME verification remain execution gates, not open product decisions. |

## 5. Decision-change protocol

A proposed change to CPD-001..023 or RPD-001..040 is `BLOCKED` until all of the following exist:

- change request and business justification;
- impact analysis and alternatives;
- security, data, finance, UX, integration, migration, deployment, commercial, and support assessment;
- Steering Committee decision;
- primary brief revision and version increment;
- coverage/register/manifest/prompt revisions;
- migration and backward-compatibility plan where applicable.

An AI agent must never infer approval from an existing implementation that conflicts with this register.
