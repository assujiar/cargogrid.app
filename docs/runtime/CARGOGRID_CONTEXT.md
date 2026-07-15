# CARGOGRID_CONTEXT.md

**Instance of:** `CG-AABPP-GOV-012`
**Instance version:** `0.2.0`
**Instance owner:** Runtime build agent (repository owner: asujiar@gmail.com / SAIKI Group)
**Last updated:** 2026-07-15 (discovered and recorded `ERR-2026-003`; consolidated this file from multiple stacked entries into one coherent document — no facts lost, see `docs/runtime/CHANGE_MANIFEST.md` `CHG-2026-023`)
**Last verified commit:** `origin/main`@`b7653cb` (merge of PR #11; contains PR #10's content too — see `ERR-2026-003`, content trust caveat below)
**Context status:** `CURRENT`, but see §4/§10 — `docs/architecture/14..16_*.md` content is `NOT_TRUSTED` pending operator reconciliation
**Canonical context location:** `docs/runtime/` (decision `CHG-2026-002`; duplicate root-level set removed)

> Single durable orientation point. Facts verified at the checkpoint above. There is no competing copy at repo root. This file previously accumulated duplicate "Last updated" headers and duplicate §5/§10 paragraphs from two divergent lineages merged without reconciliation — rewritten this checkpoint as one coherent document.

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

Active source conflict: `NONE` at the source-document level (14/14 resolved, 0 open decisions). All six primary sources are present in `docs/blueprint/`. (This is unrelated to the runtime-lineage conflict tracked as `ERR-2026-003` — that is about two AI-produced *runtime outputs* diverging, not about the source documents themselves.)

**Governance instance register (`GOV-010..019`, per `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §9 / `07_PROMPT_PACKAGE_MANIFEST.md` M-011/M-012):** `AGENTS.md` = `GOV-010`/`GOV-011` (repository operating rules, startup/execution contract); `CARGOGRID_CONTEXT.md` (this file) = `GOV-012`; `CARGOGRID_BUILD_STATUS.md` = `GOV-013`; `TASK_LEDGER.md` = `GOV-014`; `CHANGE_MANIFEST.md` = `GOV-015`; `02_CONFIRMED_DECISION_REGISTER.md` (CPD/RPD baseline) = `GOV-016`; `ERROR_LEDGER.md` = `GOV-017`; `KNOWN_ISSUES.md` = `GOV-018`; `HANDOFF.md` = `GOV-019`. All 10 instances are present and correctly ID-mapped.

## 3. Ratified operating snapshot

Shared DB/schema + RLS (dedicated Enterprise = contractual); online-first responsive PWA; custom-domain from Platform Core; PostgreSQL durable queue first; live transactional analytics with query budgets; PostGIS from Platform Core; IAM OIDC→SAML→SCIM; REST `/v1` + GraphQL together with parity; OpenAI multimodal with human approval before financial/legal effect; custom per-integration (shared codebase, no generic abstraction); malware scan before upload release; RPO/RTO per contract (silent = best effort); Supreme Admin absolute CRUD incl. audit/ledger — **no tamper-proof claim** (RPD-022).

## 4. Repository baseline

| Item | Verified value | Evidence |
|---|---|---|
| Repository | `assujiar/cargogrid.app` | `docs/discovery/01_REPOSITORY_INVENTORY.md` |
| Greenfield/brownfield | **`GREENFIELD`** (High confidence, formally decided) | `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` |
| Default branch | `main`@`b7653cb` (includes both merged lineages — see `ERR-2026-003`) | `git log` |
| Active build branch | `agent/cargogrid-autonomous-build`, recreated this checkpoint from `origin/main`@`b7653cb` (its prior lineage is fully contained in `main` via PR #11) | `HANDOFF.md` §3 |
| Package manager / runtime / framework / Supabase / tests | NONE yet | inventory §5 |
| Monorepo/workspaces | NONE (single documentation repo) | inventory §4 |
| Schema/migration head | NONE (no database) | inventory §5 |
| Product/source baseline size | 438 files (1 README + 7 blueprint + 430 package) | inventory §4 |

Step 2 discovery status: **`RUNTIME_DISCOVERY_VERIFIED`** (14/14 prompts VERIFIED, single lineage, trustworthy — `docs/discovery/14_STEP2_CLOSURE_REPORT.md`). Step 3 (architecture) Prompts 36–48 (`01_*.md`–`13_*.md`): trustworthy, single lineage, all `VERIFIED`. Step 3 Prompts 49–51 (`14_*.md`–`16_*.md`): claim `RUNTIME_ARCHITECTURE_VERIFIED`, but **content is corrupted** — two independent lineages' outputs were concatenated into the same files by an unreconciled merge (`ERR-2026-003`). Phase 0 (foundation) status: **`PHASE_0_IN_PROGRESS`, halted** — kickoff (`PH0-001`) and Prompts 81/82 nominally `VERIFIED` but built on the corrupted Step 3 baseline; `PH0-004`/Prompt 83 onward `BLOCKED` pending operator reconciliation decision (`HANDOFF.md` §1). Feature/business-domain coding remains forbidden until `PHASE_0_VERIFIED` regardless.

## 5. Repository topology

| Area | Path | Notes |
|---|---|---|
| Product/delivery blueprints | `docs/blueprint/` | 6 sources + `tes.md` placeholder |
| Prompt package | `docs/ai-agent-build-prompt-package/` | 430 files, Steps 0–17 |
| Canonical runtime context | `docs/runtime/` | context/status/ledger/change-manifest/errors/issues/handoff |
| Repository operating rules | `AGENTS.md` (root) | governance instance |
| Discovery evidence | `docs/discovery/` | **Complete** — 14/14 Step 2 outputs, `RUNTIME_DISCOVERY_VERIFIED` |
| Build logs (plural convention, in use) | `docs/build-logs/` | Step 2 reconciliation + Phase 0 `PH0-001..003` (this repo's established convention) |
| Build logs (singular convention, from the other lineage) | `docs/build-log/phase-00/` | present if that lineage's files still exist post-merge — treat as a duplicate of the plural-convention files for the same tasks, not a separate source of truth; confirm contents match before relying on either exclusively |
| App/domain/UI/migrations/tests | — | not created (greenfield) |

Canonical maps: module dependency map, canonical data flow map, domain boundary map (amended by Prompt 40), repository target structure, database schema workstream, RLS/RBAC workstream — all **produced**, `CG-S3-ARCH-001..006` `VERIFIED`, trustworthy. Configuration Engine, API/Integration, UX/Design System, Testing, DevOps, and Release Train workstreams (`07_*.md`–`12_*.md`) — all **produced**, `CG-S3-ARCH-007..012` `VERIFIED`, trustworthy. Full Work Breakdown Structure **produced** (`13_FULL_WORK_BREAKDOWN_STRUCTURE.md`, `CG-S3-ARCH-013` `VERIFIED`, trustworthy; binds the 430-file prompt package into the mandatory 10-level runtime hierarchy, 263 capability prompts registered).

**Requirement/Phase Traceability, Risk-Ranked Critical Path, and Step 3 Closure Verification (`14_*.md`–`16_*.md`, Prompts 49–51) are each duplicated, not trustworthy as single artifacts** — see §4 above and `docs/runtime/ERROR_LEDGER.md` `ERR-2026-003`. Two independent lineages each produced a complete version (607 vs. 401 traced items for `14_*.md`, and correspondingly divergent content in `15_*.md`/`16_*.md`); both versions are concatenated in the same files pending an operator reconciliation decision recorded in `docs/runtime/HANDOFF.md` §1. Phase 0 WBS/Runtime Kickoff, Source Alignment and Context Bootstrap, and Requirement Traceability Baseline Adoption (`CG-S5-PH0-001..003`) nominally `VERIFIED` but built on top of the corrupted `14_*.md` — see `HANDOFF.md` §5 for which specific lineage's copy each build log used. `PH0-004` (Repository Audit Adoption and Gap Closure) is the next task once reconciliation resolves.

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
| Active phase/workstream | Step 3 Prompts 36–48 closed and trustworthy; Prompts 49–51 content-corrupted (`ERR-2026-003`); Phase 0 — Foundation `PHASE_0_IN_PROGRESS`, **halted** |
| Current task | `CG-S5-PH0-004` — Repository Audit Adoption and Gap Closure — **would be next, but `BLOCKED`** |
| Task status | `BLOCKED` — see `HANDOFF.md` §1/§4 |
| Branch/commit | `agent/cargogrid-autonomous-build`, recreated from `origin/main`@`b7653cb` this checkpoint |
| Last known good checkpoint (both lineages agree) | `origin/main`@`27389a4` (PR #8) |
| Latest applied migration | none |
| Last fully passing gate set | none (no gates exist; confirmed `UNKNOWN` baseline, not a failure) |
| Active blockers | `ERR-2026-003` (Sev-1/Critical, `BLOCKED_DECISION`) |
| Known issues affecting work | `ISS-2026-002` (5 occurrences, now Critical/blocking); `ISS-2026-003` (due at `PH0-087`, non-blocking for now); `ISS-2026-001` `RESOLVED` |
| Next eligible task | **NONE until `ERR-2026-003` is resolved** — see `HANDOFF.md` §1 for the exact operator decision needed |

## 11. Active constraints and accepted risks

| ID | Risk | Handling | Owner |
|---|---|---|---|
| RPD-022 | Supreme Admin can defeat audit/ledger/retention | Permanent disclosure; no tamper-proof claim | Product/Security/Finance |
| RPD-034/036 | Direct GA, no external pilot | Full internal gates, zero critical defects | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery = best effort | No implied RPO/RTO guarantee | Legal/SRE |
| RPD-038 | Custom connectors, no generic abstraction | Shared code + owner/tests/runbook | Architecture/Integration |
| ISS-2026-002 | Parallel-session collision risk — 5 occurrences, one caused committed content corruption (`ERR-2026-003`) | Single authoritative branch per runtime step; enforced pre-flight check still not built | Runtime agent / repo owner |

## 12. Update protocol

Update only on durable change; cite a task/decision/discovery report/build log; remove stale facts; update timestamp + last verified commit; propagate to `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, affected registries; never store secrets/PII/live tenant data/tokens. Keep this file as **one** coherent document — if a future merge produces stacked/duplicate sections again, consolidate them in the same checkpoint that discovers them.
