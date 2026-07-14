# CARGOGRID_CONTEXT.md

**Instance of:** `CG-AABPP-GOV-012`
**Instance version:** `0.2.0`
**Instance owner:** Runtime build agent (repository owner: asujiar@gmail.com / SAIKI Group)
**Last updated:** 2026-07-14T09:58:59+07:00
**Last verified commit:** `53e3d4a34b531b10857b2850ef517cce88f981b9`
**Context status:** `CURRENT`

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
| 1 | Product Concept Brief / CPD-001..023 | `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` (register); brief file not tracked in repo | v0.1.1 register | 2026-07-14 |
| 2 | Ratified decisions RPD-001..040 | `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` | v0.1.1 | 2026-07-14 |
| 3 | Charter, BPR, UX/Data, Technical, Delivery (01–05) | Referenced in `00-control/00_PACKAGE_README.md` §3; source `.md` files NOT tracked in this repository | 1.0 Draft | 2026-07-14 |
| 4 | Approved defaults and conflict resolutions | `00-control/03_ASSUMPTION_REGISTER.md`, `00-control/04_CONFLICT_REGISTER.md` | v0.1.1 | 2026-07-14 |
| 5 | Approved ADRs and task prompts | `docs/ai-agent-build-prompt-package/` (prompt package, 430 files) | 0.18.0-step17 | 2026-07-14 |

Active source conflict: `NONE registered` (Step 0 reports 14/14 conflicts resolved, 16/16 open decisions closed). Any unregistered conflict affecting tenancy, security, canonical data, finance, destructive migration, or production claims blocks implementation.

**Note:** The six primary source documents (Product Concept Brief and 01–05) are described in the package control files but are **not** tracked as files in this repository. Only the prompt package (`docs/ai-agent-build-prompt-package/`) and this runtime context are present. This is recorded as risk/limitation in `docs/discovery/01_REPOSITORY_INVENTORY.md`.

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
| Repository URL/name | `assujiar/cargogrid.app` (origin over local proxy git server) | `git remote -v` (credentials redacted) |
| Greenfield/brownfield | `GREENFIELD (documentation-only; no application code yet)` — formal classification deferred to Prompt 32 | `docs/discovery/01_REPOSITORY_INVENTORY.md` |
| Default branch | `main` | `git branch -a`; HEAD is merge commit on main lineage |
| Package manager/version | `NOT_YET_PRESENT` — no manifest/lockfile tracked | scoped `git ls-files` name search: NONE_FOUND |
| Node/runtime version | `NOT_YET_PRESENT` — no `.nvmrc`/engines | name search: NONE_FOUND |
| Next.js/React/TypeScript | `NOT_YET_PRESENT` (target stack per AGENTS.md) | no `package.json` tracked |
| Supabase CLI/clients | `NOT_YET_PRESENT` | no `supabase/` tracked |
| Test frameworks | `NOT_YET_PRESENT` | no test config tracked |
| Monorepo/workspaces | `NONE` — single doc tree | `find -maxdepth 2 -type d` |
| Current schema/migration head | `NONE` — no migrations directory | name search: NONE_FOUND |
| Generated type path/status | `NONE` | no generated artifacts tracked |
| Last clean baseline | commit `53e3d4a` (2026-07-14, docs-only) | `git log`, clean worktree |

Step 2 discovery status: `IN_PROGRESS` (Prompt 21 of 21–34 complete). Feature coding is forbidden until `RUNTIME_DISCOVERY_VERIFIED`.

## 5. Repository topology

| Area | Path | Owner/boundary | Notes |
|---|---|---|---|
| Application routes | `NONE_YET` | — | No app code present |
| Domain/server code | `NONE_YET` | — | No app code present |
| Shared UI/design system | `NONE_YET` | — | No app code present |
| Supabase/migrations | `NONE_YET` | — | No `supabase/` directory |
| Tests/fixtures | `NONE_YET` | — | No test tree |
| Documentation/build logs | `docs/ai-agent-build-prompt-package/`, `docs/discovery/`, `docs/runtime/` | Build agent | Prompt package + runtime context/evidence |
| Scripts/tooling | `NONE_YET` | — | No scripts tracked |

Canonical maps: `NOT_YET_CREATED` (module dependency / data flow / schema registry / API contracts belong to Step 3 architecture, produced under `docs/architecture/`).

## 6. Environment matrix

| Environment | Purpose | App target | Supabase target | Data class allowed | Deployment authority | Status |
|---|---|---|---|---|---|---|
| Local | Developer validation | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Synthetic only | Developer | `NOT_STARTED` |
| Development | Shared integration | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Synthetic/masked | Engineering | `NOT_STARTED` |
| Testing | Automated gates | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Synthetic | CI | `NOT_STARTED` |
| Staging | Production-like rehearsal | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Masked/approved | Release | `NOT_STARTED` |
| UAT | Internal acceptance | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Approved UAT | Product/QA | `NOT_STARTED` |
| Production | External customers | `NOT_CONFIGURED` | `NOT_CONFIGURED` | Contract-governed | Go/no-go authority | `NOT_STARTED` |

Never put secrets, credentials, or real tenant data in this document.

## 7. Commands and gates

| Purpose | Verified command | Last result/build log |
|---|---|---|
| Install | `NOT_YET_DEFINED` | — |
| Dev | `NOT_YET_DEFINED` | — |
| Lint | `NOT_YET_DEFINED` | — |
| Typecheck | `NOT_YET_DEFINED` | — |
| Unit/integration | `NOT_YET_DEFINED` | — |
| E2E | `NOT_YET_DEFINED` | — |
| Build | `NOT_YET_DEFINED` | — |
| Supabase reset/migrate | `NOT_YET_DEFINED` | — |
| Generate types | `NOT_YET_DEFINED` | — |
| Security/access tests | `NOT_YET_DEFINED` | — |

Only use commands verified from repository scripts/configuration. No such scripts exist yet (Prompt 23 owns toolchain verification).

## 8. Current architecture

| Decision area | Current state | ADR/evidence | Constraint |
|---|---|---|---|
| Modular monolith boundaries | `NOT_IMPLEMENTED` (target per ratified snapshot) | Step 3 pending | No tenant source forks |
| Tenancy/RLS | `NOT_IMPLEMENTED` | Step 3/Phase 1 pending | Default deny; negative tests |
| RBAC/field/record access | `NOT_IMPLEMENTED` | pending | Server enforcement |
| Configuration/approval/workflow | `NOT_IMPLEMENTED` | pending | Version/effective date |
| REST/GraphQL | `NOT_IMPLEMENTED` | pending | Security/contract parity |
| Jobs | `NOT_IMPLEMENTED` | pending | PostgreSQL queue baseline |
| Storage/documents | `NOT_IMPLEMENTED` | pending | Scan and signed access |
| Reporting/search | `NOT_IMPLEMENTED` | pending | Live OLTP and PostgreSQL FTS first |
| Observability/recovery | `NOT_IMPLEMENTED` | pending | Contract-aware claims |

## 9. Data and access invariants

- Tenant context is preserved through DB, storage, cache, jobs, logs, search, reports, exports, APIs, and integrations.
- UI hiding is not authorization; field and record rules are enforced server-side.
- Canonical data is reused with lineage and governed snapshots; no uncontrolled re-entry.
- Normal journal, inventory, and loyalty changes follow posting/ledger controls, subject to the explicit Supreme Admin exception.
- Applied configuration versions remain linked to critical active transactions unless an approved migration rule runs.
- Current statutory behavior is configurable and supported by dated verification.

Repository-specific invariants: `NONE_YET` (no application data model exists at this checkpoint).

## 10. Current delivery context

| Field | Current value |
|---|---|
| Active phase/workstream | Step 2 — Repository Discovery and Baseline |
| Current task | `CG-S2-DISC-001` — Repository Discovery (Prompt 21) |
| Task status | `VERIFIED` |
| Branch/commit | `claude/cargogrid-ai-agent-setup-oanf5a` / `53e3d4a` (pre-commit HEAD) |
| Last known good checkpoint | `53e3d4a` (docs-only, clean) |
| Latest applied migration | `NONE` |
| Last fully passing gate set | `N/A` — no code gates defined yet |
| Active blockers | `NONE` |
| Known issues affecting work | `ISS-2026-001` (primary source docs not tracked) |
| Next eligible task | `CG-S2-DISC-002` — Existing Implementation Audit (Prompt 22) |

Detailed state belongs in `CARGOGRID_BUILD_STATUS.md` and `TASK_LEDGER.md`; do not duplicate volatile logs here.

## 11. Active constraints and accepted risks

| ID | Constraint/risk | Required handling | Evidence owner |
|---|---|---|---|
| RPD-022 | Supreme Admin can defeat audit/ledger/retention evidence | Permanent disclosure; no tamper-proof claim | Product/Security/Finance |
| RPD-034/036 | Direct GA without external pilot | Full internal gates and zero critical defects | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery is best effort | No implied RPO/RTO guarantee | Legal/SRE |
| RPD-038 | Custom connectors lack generic provider abstraction | Shared code, explicit owner/tests/runbook | Architecture/Integration |
| ISS-2026-001 | Primary source docs (Brief + 01–05) not tracked in repo | Obtain/track sources before implementation gates rely on them | Product/Build agent |

## 12. Update protocol

Update this file only when durable context changes: source authority, repository baseline, topology, environment, command, architecture, invariant, active phase/checkpoint, or accepted risk. For every edit:

1. Cite a task, decision, ADR, discovery report, or build log.
2. Remove or mark stale facts; never leave two competing current values.
3. Update timestamp and last verified commit.
4. Propagate status changes to `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, and affected registries.
5. Do not store secrets, personal data, live tenant data, or raw tokens.
