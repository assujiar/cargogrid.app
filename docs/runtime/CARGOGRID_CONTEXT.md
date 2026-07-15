# CARGOGRID_CONTEXT.md

**Instance of:** `CG-AABPP-GOV-012`
**Instance version:** `0.2.0`
**Instance owner:** Runtime build agent (repository owner: asujiar@gmail.com / SAIKI Group)
**Last updated:** 2026-07-15 (post Phase 0 Prompt 81 — Source Alignment and Context Bootstrap; corrected stale "Last verified commit" per PH0-81 drift check)
**Last verified commit:** `1802400baaaa464c1110660ebe663bd50d57302e` (`agent/cargogrid-autonomous-build`, Phase 0 kickoff — Prompt 80; corrects a header field that had not been advanced since the Step 2 reconciliation checkpoint despite 17 subsequent checkpoints updating this document's body — see `docs/build-log/phase-00/PH0-81.md` §"CARGOGRID_CONTEXT.md correction")
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

Step 2 discovery status: **`RUNTIME_DISCOVERY_VERIFIED`** (14/14 prompts VERIFIED — `docs/discovery/14_STEP2_CLOSURE_REPORT.md`). Step 3 (architecture) status: **`RUNTIME_ARCHITECTURE_VERIFIED`** (16/16 prompts VERIFIED — `docs/architecture/16_STEP3_CLOSURE_REPORT.md`). Phase 0 (foundation) status: **`PHASE_0_IN_PROGRESS`** — kickoff (`PH0-080`) VERIFIED, `PH0-081` `READY`, 20 tasks `BLOCKED` on sequential upstream (`docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md`). Feature/business-domain coding remains forbidden until `PHASE_0_VERIFIED` (only `PH0-102` may set that state).

## 5. Repository topology

| Area | Path | Notes |
|---|---|---|
| Product/delivery blueprints | `docs/blueprint/` | 6 sources + `tes.md` placeholder |
| Prompt package | `docs/ai-agent-build-prompt-package/` | 430 files, Steps 0–17 |
| Canonical runtime context | `docs/runtime/` | context/status/ledger/change-manifest/errors/issues/handoff |
| Repository operating rules | `AGENTS.md` (root) | governance instance |
| Discovery evidence | `docs/discovery/` | **Complete** — 14/14 Step 2 outputs, `RUNTIME_DISCOVERY_VERIFIED` |
| Build logs (Step 2 reconciliation) | `docs/build-logs/` (plural) | per-task, Step 2 |
| Build logs (Phase 0+) | `docs/build-log/` (singular) | per-task, Step 5 Phase 0 onward — path literally specified by each Phase 0 prompt file's own header, distinct directory from the plural form above |
| App/domain/UI/migrations/tests | — | not created (greenfield) |

Canonical maps: module dependency map, canonical data flow map, domain boundary map (amended by Prompt 40), repository target structure, database schema workstream, RLS/RBAC workstream — all **produced**, `CG-S3-ARCH-001..006` `VERIFIED`. Configuration Engine workstream **produced** (`docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md`, `CG-S3-ARCH-007` `VERIFIED`). API/Integration workstream **produced** (`docs/architecture/08_API_INTEGRATION_WORKSTREAM.md`, `CG-S3-ARCH-008` `VERIFIED`). UX/Design System workstream **produced** (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`, `CG-S3-ARCH-009` `VERIFIED`). Testing workstream **produced** (`docs/architecture/10_TESTING_WORKSTREAM.md`, `CG-S3-ARCH-010` `VERIFIED`). DevOps workstream **produced** (`docs/architecture/11_DEVOPS_WORKSTREAM.md`, `CG-S3-ARCH-011` `VERIFIED`; resolves `ADR-CAND-ARCH-004`). Release Train **produced** (`docs/architecture/12_RELEASE_TRAIN.md`, `CG-S3-ARCH-012` `VERIFIED`; supersedes Blueprint §3.2/§8.1/§8.2's external-pilot release-type language with RPD-034/036). Full Work Breakdown Structure **produced** (`docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md`, `CG-S3-ARCH-013` `VERIFIED`; binds the 430-file prompt package into the mandatory 10-level runtime hierarchy, 263 capability prompts registered). Requirement/Phase Traceability **produced** (`docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md`, `CG-S3-ARCH-014` `VERIFIED`; binds 607 source catalogue items to WBS capability owners, 568 `COVERED`/20 `ACCEPTED_RISK`/15 `EXTERNAL_VERIFICATION`/4 `PARTIAL_BLOCKED`/0 `NOT_COVERED`). Risk-Ranked Critical Path **produced** (`docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md`, `CG-S3-ARCH-015` `VERIFIED`; 9-dimension reproducible ranking, 11-depth dependency-ordinal critical path, top risk RPD-022 Supreme Admin overlay). **Step 3 Closure Verification produced and PASSED** (`docs/architecture/16_STEP3_CLOSURE_REPORT.md`, `CG-S3-ARCH-016` `VERIFIED`; independently checked all 9 verification tasks, zero cycles/orphans/duplicates, two non-blocking findings surfaced transparently). **Step 3 is now `RUNTIME_ARCHITECTURE_VERIFIED` — architecture planning is complete.** Next work is Phase 0 foundation kickoff (`docs/ai-agent-build-prompt-package/05-phase-00-discovery-foundation/`, Prompt 79+), a different kind of work (environment/CI/toolchain setup) than Step 3's planning prompts.

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
| Active phase/workstream | Phase 0 — Discovery and Foundation (`PHASE_0_IN_PROGRESS`, 1/23 tasks VERIFIED) |
| Current task | `CG-S5-PH0-001` — Phase 0 WBS and Runtime Kickoff |
| Task status | `VERIFIED` — `docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md`, `00_PHASE0_WBS.md` complete |
| Branch/commit | `agent/cargogrid-autonomous-build`, cut from `main`@`39d923e` |
| Last known good checkpoint | `origin/main`@`39d923e` |
| Latest applied migration | none |
| Last fully passing gate set | none (no gates exist; confirmed `UNKNOWN` baseline, not a failure) |
| Active blockers | none |
| Known issues affecting work | ISS-2026-002 (recurred twice previously, non-blocking), ISS-2026-003 (**due at `PH0-087` Git strategy foundation**); ISS-2026-001 RESOLVED |
| Next eligible task | `CG-S5-PH0-002` — Source Alignment and Context Bootstrap (Prompt 81) |

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
