# CARGOGRID_CONTEXT.md

**Template ID:** `CG-AABPP-GOV-012` (instance)
**Template version:** `0.2.0`
**Instance owner:** Product/Tech owner (SAIKI Group) — runtime agent maintained
**Last updated:** 2026-07-14T10:16:05+07:00
**Last verified commit:** `db1742c9bfaf79e4bb604def46126eabcfa946c2`
**Context status:** `CURRENT`

> Durable orientation point for any new agent. Facts below are verified from the repository at the checkpoint above. Detailed evidence is linked, not duplicated.

## 1. Product identity

- Product: CargoGrid.
- Owner/brand: SAIKI Group.
- Contracting/invoicing entity: PT SAIKI Group.
- Model: multi-tenant, white-label, modular logistics SaaS ERP.
- Initial market/localization: Indonesia-first.
- First live tenant: external production customer; there is no external pilot (RPD-034/036).
- GA boundary: all major module suites plus final internal gates; internal phases are not partial GA releases.

## 2. Authoritative sources

| Priority | Source | Repository/location | Version/status | Last verified |
|---:|---|---|---|---|
| 1 | Product Concept Brief / CPD-001..023 | `docs/blueprint/CargoGrid_Product_Concept_Brief.md` | Confirmed baseline | 2026-07-14 |
| 2 | Ratified decisions RPD-001..040 | `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` | 0.1.1 FINAL_FOR_STEP | 2026-07-14 |
| 3 | Charter, BPR, UX/Data, Technical, Delivery | `docs/blueprint/01_..05_*.md` | 1.0 Draft | 2026-07-14 |
| 4 | Approved defaults and conflict resolutions | `docs/ai-agent-build-prompt-package/00-control/03_ASSUMPTION_REGISTER.md`, `04_CONFLICT_REGISTER.md` | 0.1.1 | 2026-07-14 |
| 5 | Prompt package (Steps 0–17) + START_HERE | `docs/ai-agent-build-prompt-package/` | 0.18.0-step17 | 2026-07-14 |

Active source conflict: `NONE` (package reports 14/14 conflicts resolved, 0 open decisions).

## 3. Ratified operating snapshot

- Tenancy: shared DB/shared schema with RLS; dedicated Enterprise deployment is contractual.
- Mobile: responsive online-first PWA; native/offline sync deferred.
- Domains: custom-domain primitives from Platform Core.
- Async: PostgreSQL durable queue first; worker separation is threshold-driven.
- Analytics: live transactional reads with read-only policy, query budget, timeout, pagination, caching.
- Geospatial: PostGIS from Platform Core.
- IAM expansion order: OIDC → SAML → SCIM.
- API: REST `/v1` and GraphQL delivered together with security/contract parity.
- AI/OCR: OpenAI multimodal default; human approval before financial/legal effects.
- Non-AI integrations: custom per integration without generic provider abstraction; shared codebase only.
- Uploads: malware scan before release to another user.
- Recovery: RPO/RTO per contract; silent contract means best effort without guarantee.
- Supreme Admin: absolute CRUD, including audit/ledger/final records; no tamper-proof/absolute-immutability claim (RPD-022).

## 4. Repository baseline

| Item | Verified value | Evidence |
|---|---|---|
| Repository URL/name | `assujiar/cargogrid.app` | `docs/discovery/01_REPOSITORY_INVENTORY.md` §1 |
| Greenfield/brownfield | Greenfield (preliminary; formal decision owned by Prompt 32) | discovery §10 |
| Default branch | `main` (@ `53e3d4a`) | discovery §1 |
| Active build branch | `claude/cargogrid-ai-agent-setup-b492y3` (@ `db1742c`) | discovery §1 |
| Package manager/version | NONE yet | discovery §5 |
| Node/runtime version | NONE yet | discovery §5 |
| Next.js/React/TypeScript | NONE yet | discovery §5 |
| Supabase CLI/clients | NONE yet | discovery §5 |
| Test frameworks | NONE yet | discovery §5 |
| Monorepo/workspaces | NONE (single documentation repo) | discovery §4 |
| Current schema/migration head | NONE (no database) | discovery §5 |
| Generated type path/status | NONE | discovery §5 |
| Last clean baseline | `db1742c` (2026-07-14, clean tree) | discovery §1 |

Step 2 discovery status: `IN_PROGRESS` (1 of 14 prompts VERIFIED). Feature coding is forbidden until `RUNTIME_DISCOVERY_VERIFIED` and later implementation gates authorize code.

## 5. Repository topology

| Area | Path | Owner/boundary | Notes |
|---|---|---|---|
| Product/delivery blueprints | `docs/blueprint/` | Product | 6 authoritative sources + `tes.md` placeholder |
| AI agent build prompt package | `docs/ai-agent-build-prompt-package/` | Governance | 430 files, Steps 0–17 |
| Persistent runtime context | repo root (`CARGOGRID_*.md`, `TASK_LEDGER.md`, ...) | Runtime agent | Bootstrapped 2026-07-14 |
| Discovery evidence | `docs/discovery/` | Architecture | Initialized this task |
| Build logs | `docs/build-logs/` | Runtime agent | Initialized this task |
| Application/domain/UI/migrations/tests | — | — | Not yet created (greenfield) |

Canonical maps: not yet produced (owned by Step 3 architecture prompts 36–39).

## 6. Environment matrix

No runtime environments provisioned. Local sandbox only; git remote is the session proxy (`127.0.0.1`), not production. Never put secrets, credentials, or real tenant data in this document.

## 7. Commands and gates

No verified build/test/lint commands exist — no toolchain is present. Command table will be populated when Phase 0 establishes the environment (Prompts 85–88).

## 8. Current architecture

No application architecture implemented. Target architecture is defined by the blueprint + package but not yet realized in code. All rows `NOT_STARTED`.

## 9. Data and access invariants

- Tenant context must be preserved through DB, storage, cache, jobs, logs, search, reports, exports, APIs, integrations (design intent; not yet enforced in code).
- UI hiding is not authorization; field/record rules enforced server-side.
- Canonical data reused with lineage and governed snapshots; no uncontrolled re-entry.
- Normal journal/inventory/loyalty changes follow posting/ledger controls, subject to the explicit Supreme Admin exception (RPD-022).
- Applied configuration versions remain linked to critical active transactions unless an approved migration rule runs.
- Current statutory behavior is configurable and supported by dated verification (RPD-016).

Repository-specific verified invariants: NONE yet (no code).

## 10. Current delivery context

| Field | Current value |
|---|---|
| Active phase/workstream | Runtime Step 2 — Repository Discovery |
| Current task | `CG-S2-DISC-001` — Repository Discovery |
| Task status | `VERIFIED` |
| Branch/commit | `claude/cargogrid-ai-agent-setup-b492y3` / `db1742c` |
| Last known good checkpoint | `db1742c` |
| Latest applied migration | none |
| Last fully passing gate set | none (no gates exist) |
| Active blockers | none |
| Known issues affecting work | KI-001, KI-002, KI-003 (informational) |
| Next eligible task | `CG-S2-DISC-002` — Existing Implementation Audit (Prompt 22) |

## 11. Active constraints and accepted risks

| ID | Constraint/risk | Required handling | Evidence owner |
|---|---|---|---|
| RPD-022 | Supreme Admin can defeat audit/ledger/retention evidence | Permanent disclosure; no tamper-proof claim | Product/Security/Finance |
| RPD-034/036 | Direct GA without external pilot | Full internal gates and zero critical defects | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery is best effort | No implied RPO/RTO guarantee | Legal/SRE |
| RPD-038 | Custom connectors lack generic provider abstraction | Shared code, explicit owner/tests/runbook | Architecture/Integration |

## 12. Update protocol

Update only when durable context changes. Every edit must cite a task/decision/discovery report/build log, remove stale facts, update timestamp + last verified commit, and propagate status to `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, and affected registries. Never store secrets, personal data, live tenant data, or raw tokens.
