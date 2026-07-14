# CARGOGRID_CONTEXT.md

**Instance of:** `CG-AABPP-GOV-012`
**Instance version:** `0.2.0`
**Instance owner:** Runtime build agent (repository owner: asujiar@gmail.com / SAIKI Group)
**Last updated:** 2026-07-14T10:29:19+07:00
**Last verified commit:** `d58744500a55c267ddf7447c6518fc86c1323912` (main, reconciled)
**Context status:** `CURRENT`
**Canonical context location:** `docs/runtime/` (decision CHG-2026-002; duplicate root-level set removed)

> Single durable orientation point. Facts verified at the checkpoint above. There is no competing copy at repo root.

## 1. Product identity

- Product: CargoGrid. Owner/brand: SAIKI Group. Contracting entity: PT SAIKI Group.
- Model: multi-tenant, white-label, modular logistics SaaS ERP. Market: Indonesia-first.
- First live tenant is an external production customer; no external pilot (RPD-034/036).
- GA boundary: all major module suites + final internal gates; internal phases are not partial GA.

## 2. Authoritative sources

| Priority | Source | Location | Status |
|---:|---|---|---|
| 1 | Product Concept Brief / CPD-001..023 | `docs/blueprint/CargoGrid_Product_Concept_Brief.md` | Confirmed baseline — **tracked** |
| 2 | Ratified decisions RPD-001..040 | `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` | FINAL_FOR_STEP |
| 3 | Charter, BPR, UX/Data, Technical, Delivery (01–05) | `docs/blueprint/01_..05_*.md` | 1.0 Draft — **tracked** |
| 4 | Approved defaults / conflict resolutions | `00-control/03_ASSUMPTION_REGISTER.md`, `04_CONFLICT_REGISTER.md` | FINAL_FOR_STEP |
| 5 | Prompt package (Steps 0–17) + START_HERE | `docs/ai-agent-build-prompt-package/` | 0.18.0-step17 |

Active source conflict: `NONE` (14/14 resolved, 0 open decisions). All six primary sources are present in `docs/blueprint/` (this corrects session-A's ISS-2026-001, now RESOLVED).

## 3. Ratified operating snapshot

Shared DB/schema + RLS (dedicated Enterprise = contractual); online-first responsive PWA; custom-domain from Platform Core; PostgreSQL durable queue first; live transactional analytics with query budgets; PostGIS from Platform Core; IAM OIDC→SAML→SCIM; REST `/v1` + GraphQL together with parity; OpenAI multimodal with human approval before financial/legal effect; custom per-integration (shared codebase, no generic abstraction); malware scan before upload release; RPO/RTO per contract (silent = best effort); Supreme Admin absolute CRUD incl. audit/ledger — **no tamper-proof claim** (RPD-022).

## 4. Repository baseline

| Item | Verified value | Evidence |
|---|---|---|
| Repository | `assujiar/cargogrid.app` | `docs/discovery/01_REPOSITORY_INVENTORY.md` |
| Greenfield/brownfield | **`GREENFIELD`** (High confidence, formally decided) | `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` |
| Default branch | `main` @ `39d923e` (includes `CG-S2-DISC-001-R1` and Step 2 closure Prompts 22–34) | inventory §1 |
| Active build branch | `agent/cargogrid-autonomous-build` (cut from `main`@`39d923e`; carries Step 3 Prompt 36) | `TASK_LEDGER.md` |
| Package manager / runtime / framework / Supabase / tests | NONE yet | inventory §5 |
| Monorepo/workspaces | NONE (single documentation repo) | inventory §4 |
| Schema/migration head | NONE (no database) | inventory §5 |
| Product/source baseline size | 438 files (1 README + 7 blueprint + 430 package) | inventory §4 |

Step 2 discovery status: **`RUNTIME_DISCOVERY_VERIFIED`** (14/14 prompts VERIFIED — `docs/discovery/14_STEP2_CLOSURE_REPORT.md`). Step 3 (architecture) is now eligible. Feature coding remains forbidden until Step 3 and the Phase 0 foundation gates are also VERIFIED.

## 5. Repository topology

| Area | Path | Notes |
|---|---|---|
| Product/delivery blueprints | `docs/blueprint/` | 6 sources + `tes.md` placeholder |
| Prompt package | `docs/ai-agent-build-prompt-package/` | 430 files, Steps 0–17 |
| Canonical runtime context | `docs/runtime/` | context/status/ledger/change-manifest/errors/issues/handoff |
| Repository operating rules | `AGENTS.md` (root) | governance instance |
| Discovery evidence | `docs/discovery/` | **Complete** — 14/14 Step 2 outputs, `RUNTIME_DISCOVERY_VERIFIED` |
| Build logs | `docs/build-logs/` | per-task |
| App/domain/UI/migrations/tests | — | not created (greenfield) |

Canonical maps: module dependency map **produced** (`docs/architecture/01_MODULE_DEPENDENCY_MAP.md`, `CG-S3-ARCH-001` `VERIFIED`); canonical data flow map **produced** (`docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md`, `CG-S3-ARCH-002` `VERIFIED`); domain boundary map, schema registry, API contracts not yet produced (remaining Step 3 prompts).

## 6. Environment matrix

No runtime environments provisioned. Local sandbox only; git remote is the session proxy (`127.0.0.1`), not production. Never store secrets, credentials, or real tenant data here.

## 7. Commands and gates

No verified build/test/lint commands — no toolchain present. Populated when Phase 0 establishes the environment (Prompts 85–88).

## 8. Current architecture

No application architecture implemented; all decision-area rows `NOT_STARTED`. Target defined by blueprint + package, not yet realized in code.

## 9. Data and access invariants (design intent, not yet enforced)

Tenant context preserved across DB/storage/cache/jobs/logs/search/reports/exports/APIs/integrations; UI hiding ≠ authorization; canonical data reused with lineage/governed snapshots; posting/ledger controls subject to the RPD-022 exception; applied config versions stay linked to active transactions; statutory behavior configurable with dated verification (RPD-016). Repository-specific verified invariants: NONE yet (no data model).

## 10. Current delivery context

| Field | Value |
|---|---|
| Active phase/workstream | Runtime Step 3 — Architecture and Execution Blueprint (`RUNTIME_ARCHITECTURE_IN_PROGRESS`, 2/16 prompts) |
| Current task | `CG-S3-ARCH-002` — Canonical Data Flow Map |
| Task status | `VERIFIED` — `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md` complete |
| Branch/commit | `agent/cargogrid-autonomous-build`, cut from `main`@`39d923e` |
| Last known good checkpoint | `origin/main`@`39d923e` |
| Latest applied migration | none |
| Last fully passing gate set | none (no gates exist; confirmed `UNKNOWN` baseline, not a failure) |
| Active blockers | none |
| Known issues affecting work | ISS-2026-002 (recurred twice previously, non-blocking), ISS-2026-003 (non-blocking); ISS-2026-001 RESOLVED |
| Next eligible task | `CG-S3-ARCH-003` — Domain Boundary Map (Prompt 38) |

## 11. Active constraints and accepted risks

| ID | Risk | Handling | Owner |
|---|---|---|---|
| RPD-022 | Supreme Admin can defeat audit/ledger/retention | Permanent disclosure; no tamper-proof claim | Product/Security/Finance |
| RPD-034/036 | Direct GA, no external pilot | Full internal gates, zero critical defects | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery = best effort | No implied RPO/RTO guarantee | Legal/SRE |
| RPD-038 | Custom connectors, no generic abstraction | Shared code + owner/tests/runbook | Architecture/Integration |
| ISS-2026-002 | Parallel-session collision risk | Single authoritative branch per runtime step | Runtime agent |

## 12. Update protocol

Update only on durable change; cite a task/decision/discovery report/build log; remove stale facts; update timestamp + last verified commit; propagate to `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, affected registries; never store secrets/PII/live tenant data/tokens.
