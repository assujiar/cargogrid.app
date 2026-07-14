# CARGOGRID_CONTEXT.md

**Template ID:** `CG-AABPP-GOV-012`  
**Template version:** `0.2.0`  
**Instance owner:** `{{PRODUCT_OR_TECH_OWNER}}`  
**Last updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Last verified commit:** `{{COMMIT_SHA_OR_NONE}}`  
**Context status:** `{{CURRENT | STALE | REBUILD_REQUIRED}}`

> This file is the durable orientation point for any new agent. Replace template tokens with verified facts. Do not copy guesses into this file. Link detailed evidence instead of turning this into a build log.

## 1. Product identity

- Product: CargoGrid.
- Owner/brand: SAIKI Group.
- Contracting/invoicing entity: PT SAIKI Group.
- Model: multi-tenant, white-label, modular logistics SaaS ERP.
- Initial market/localization: Indonesia-first.
- First live tenant: external production customer; there is no external pilot.
- GA boundary: all major module suites plus final internal gates; internal phases are not partial GA releases.

## 2. Authoritative sources

| Priority | Source | Repository/location | Version/checksum | Last verified |
|---:|---|---|---|---|
| 1 | Product Concept Brief / CPD-001..023 | `{{PATH}}` | `{{VERSION_OR_HASH}}` | `{{DATE}}` |
| 2 | Ratified decisions RPD-001..040 | `{{PATH_TO_DECISION_REGISTER}}` | `{{VERSION_OR_HASH}}` | `{{DATE}}` |
| 3 | Charter, BPR, UX/Data, Technical, Delivery | `{{PATHS}}` | `{{VERSIONS_OR_HASHES}}` | `{{DATE}}` |
| 4 | Approved defaults and conflict resolutions | `{{PATHS}}` | `{{VERSIONS_OR_HASHES}}` | `{{DATE}}` |
| 5 | Approved ADRs and task prompts | `{{PATHS}}` | `{{RANGE}}` | `{{DATE}}` |

Active source conflict: `{{NONE | CONFLICT_IDS_AND_SUMMARY}}`. Any unregistered conflict affecting tenancy, security, canonical data, finance, destructive migration, or production claims blocks implementation.

## 3. Ratified operating snapshot

- Tenancy: shared DB/shared schema with RLS; dedicated Enterprise deployment is contractual.
- Mobile: responsive online-first PWA; native/offline sync deferred.
- Domains: custom-domain primitives from Platform Core.
- Async: PostgreSQL durable queue first; worker separation is threshold-driven.
- Analytics: live transactional reads with read-only policy, query budget, timeout, pagination, and caching.
- Geospatial: PostGIS from Platform Core.
- IAM expansion order: OIDC → SAML → SCIM.
- API: REST `/v1` and GraphQL delivered together with security/contract parity.
- AI/OCR: OpenAI multimodal default; human approval before financial/legal effects.
- Non-AI integrations: custom per integration without generic provider abstraction; shared codebase only.
- Uploads: malware scan before release to another user.
- Recovery: RPO/RTO per contract; silent contract means best effort without guarantee.
- Supreme Admin: absolute CRUD, including audit/ledger/final records; no tamper-proof/absolute-immutability claim.

## 4. Repository baseline

| Item | Verified value | Evidence |
|---|---|---|
| Repository URL/name | `{{VALUE}}` | `{{COMMAND_OR_LINK}}` |
| Greenfield/brownfield | `{{VALUE}}` | `{{DISCOVERY_REPORT}}` |
| Default branch | `{{VALUE}}` | `{{EVIDENCE}}` |
| Package manager/version | `{{VALUE}}` | `{{LOCKFILE_AND_COMMAND}}` |
| Node/runtime version | `{{VALUE}}` | `{{EVIDENCE}}` |
| Next.js/React/TypeScript | `{{VERSIONS}}` | `{{PACKAGE_FILE}}` |
| Supabase CLI/clients | `{{VERSIONS}}` | `{{EVIDENCE}}` |
| Test frameworks | `{{VALUES}}` | `{{CONFIG_PATHS}}` |
| Monorepo/workspaces | `{{VALUE}}` | `{{CONFIG_PATH}}` |
| Current schema/migration head | `{{VALUE}}` | `{{MIGRATION_EVIDENCE}}` |
| Generated type path/status | `{{VALUE}}` | `{{EVIDENCE}}` |
| Last clean baseline | `{{COMMIT_AND_DATE}}` | `{{BUILD_LOG}}` |

Step 2 discovery status: `{{NOT_STARTED | IN_PROGRESS | VERIFIED}}`. Feature coding is forbidden until `VERIFIED`.

## 5. Repository topology

| Area | Path | Owner/boundary | Notes |
|---|---|---|---|
| Application routes | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Domain/server code | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Shared UI/design system | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Supabase/migrations | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Tests/fixtures | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Documentation/build logs | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |
| Scripts/tooling | `{{PATH}}` | `{{OWNER}}` | `{{NOTES}}` |

Canonical maps: `{{MODULE_DEPENDENCY_MAP_PATH}}`, `{{DATA_FLOW_MAP_PATH}}`, `{{SCHEMA_REGISTRY_PATH}}`, `{{API_CONTRACTS_PATH}}`.

## 6. Environment matrix

| Environment | Purpose | App target | Supabase target | Data class allowed | Deployment authority | Status |
|---|---|---|---|---|---|---|
| Local | Developer validation | `{{VALUE}}` | `{{VALUE}}` | Synthetic only | Developer | `{{STATUS}}` |
| Development | Shared integration | `{{VALUE}}` | `{{VALUE}}` | Synthetic/masked | Engineering | `{{STATUS}}` |
| Testing | Automated gates | `{{VALUE}}` | `{{VALUE}}` | Synthetic | CI | `{{STATUS}}` |
| Staging | Production-like rehearsal | `{{VALUE}}` | `{{VALUE}}` | Masked/approved | Release | `{{STATUS}}` |
| UAT | Internal acceptance | `{{VALUE}}` | `{{VALUE}}` | Approved UAT | Product/QA | `{{STATUS}}` |
| Production | External customers | `{{VALUE}}` | `{{VALUE}}` | Contract-governed | Go/no-go authority | `{{STATUS}}` |

Never put secrets, credentials, or real tenant data in this document.

## 7. Commands and gates

| Purpose | Verified command | Last result/build log |
|---|---|---|
| Install | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Dev | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Lint | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Typecheck | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Unit/integration | `{{COMMAND}}` | `{{RESULT_REF}}` |
| E2E | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Build | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Supabase reset/migrate | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Generate types | `{{COMMAND}}` | `{{RESULT_REF}}` |
| Security/access tests | `{{COMMAND}}` | `{{RESULT_REF}}` |

Only use commands verified from repository scripts/configuration.

## 8. Current architecture

| Decision area | Current state | ADR/evidence | Constraint |
|---|---|---|---|
| Modular monolith boundaries | `{{STATE}}` | `{{REF}}` | No tenant source forks |
| Tenancy/RLS | `{{STATE}}` | `{{REF}}` | Default deny; negative tests |
| RBAC/field/record access | `{{STATE}}` | `{{REF}}` | Server enforcement |
| Configuration/approval/workflow | `{{STATE}}` | `{{REF}}` | Version/effective date |
| REST/GraphQL | `{{STATE}}` | `{{REF}}` | Security/contract parity |
| Jobs | `{{STATE}}` | `{{REF}}` | PostgreSQL queue baseline |
| Storage/documents | `{{STATE}}` | `{{REF}}` | Scan and signed access |
| Reporting/search | `{{STATE}}` | `{{REF}}` | Live OLTP and PostgreSQL FTS first |
| Observability/recovery | `{{STATE}}` | `{{REF}}` | Contract-aware claims |

## 9. Data and access invariants

- Tenant context is preserved through DB, storage, cache, jobs, logs, search, reports, exports, APIs, and integrations.
- UI hiding is not authorization; field and record rules are enforced server-side.
- Canonical data is reused with lineage and governed snapshots; no uncontrolled re-entry.
- Normal journal, inventory, and loyalty changes follow posting/ledger controls, subject to the explicit Supreme Admin exception.
- Applied configuration versions remain linked to critical active transactions unless an approved migration rule runs.
- Current statutory behavior is configurable and supported by dated verification.

Add repository-specific invariants here: `{{VERIFIED_INVARIANTS_OR_NONE}}`.

## 10. Current delivery context

| Field | Current value |
|---|---|
| Active phase/workstream | `{{VALUE}}` |
| Current task | `{{TASK_ID_AND_NAME}}` |
| Task status | `{{STATUS}}` |
| Branch/commit | `{{VALUE}}` |
| Last known good checkpoint | `{{VALUE}}` |
| Latest applied migration | `{{VALUE}}` |
| Last fully passing gate set | `{{VALUE}}` |
| Active blockers | `{{NONE_OR_IDS}}` |
| Known issues affecting work | `{{NONE_OR_IDS}}` |
| Next eligible task | `{{TASK_ID_OR_NONE}}` |

Detailed state belongs in `CARGOGRID_BUILD_STATUS.md` and `TASK_LEDGER.md`; do not duplicate volatile logs here.

## 11. Active constraints and accepted risks

| ID | Constraint/risk | Required handling | Evidence owner |
|---|---|---|---|
| RPD-022 | Supreme Admin can defeat audit/ledger/retention evidence | Permanent disclosure; no tamper-proof claim | Product/Security/Finance |
| RPD-034/036 | Direct GA without external pilot | Full internal gates and zero critical defects | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery is best effort | No implied RPO/RTO guarantee | Legal/SRE |
| RPD-038 | Custom connectors lack generic provider abstraction | Shared code, explicit owner/tests/runbook | Architecture/Integration |
| `{{ID}}` | `{{RISK}}` | `{{HANDLING}}` | `{{OWNER}}` |

## 12. Update protocol

Update this file only when durable context changes: source authority, repository baseline, topology, environment, command, architecture, invariant, active phase/checkpoint, or accepted risk. For every edit:

1. Cite a task, decision, ADR, discovery report, or build log.
2. Remove or mark stale facts; never leave two competing current values.
3. Update timestamp and last verified commit.
4. Propagate status changes to `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, and affected registries.
5. Do not store secrets, personal data, live tenant data, or raw tokens.
