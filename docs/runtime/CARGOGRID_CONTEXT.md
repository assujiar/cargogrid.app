# CARGOGRID_CONTEXT.md

**Instance of:** `CG-AABPP-GOV-012`
**Instance version:** `0.2.0`
**Instance owner:** Runtime build agent (repository owner: asujiar@gmail.com / SAIKI Group)
**Last updated:** 2026-07-14 (post Step 3 Prompt 51 — Step 3 Closure Verification; Step 3 `RUNTIME_ARCHITECTURE_VERIFIED`)
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
| Active build branch | `claude/sleepy-ride-4vxsk6` (session's designated continuation branch; cut from `main`@`27389a4`, merged forward with `agent/cargogrid-autonomous-build`'s 3 unmerged commits) | `TASK_LEDGER.md` |
| Package manager / runtime / framework / Supabase / tests | NONE yet | inventory §5 |
| Monorepo/workspaces | NONE (single documentation repo) | inventory §4 |
| Schema/migration head | NONE (no database) | inventory §5 |
| Product/source baseline size | 438 files (1 README + 7 blueprint + 430 package) | inventory §4 |

Step 2 discovery status: **`RUNTIME_DISCOVERY_VERIFIED`** (14/14 prompts VERIFIED — `docs/discovery/14_STEP2_CLOSURE_REPORT.md`). Step 3 architecture status: **`RUNTIME_ARCHITECTURE_VERIFIED`** (16/16 prompts VERIFIED — `docs/architecture/16_STEP3_CLOSURE_REPORT.md`, independently re-verified, closure state confirmed). Phase 0 Foundation is now eligible. Feature coding (Phase 1+) remains forbidden until the Phase 0 foundation gates are also `VERIFIED` (`PHASE_0_VERIFIED`).

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

Canonical maps: module dependency map, canonical data flow map, domain boundary map (amended by Prompt 40), repository target structure, database schema workstream, RLS/RBAC workstream — all **produced**, `CG-S3-ARCH-001..006` `VERIFIED`. Configuration Engine workstream **produced** (`docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md`, `CG-S3-ARCH-007` `VERIFIED`). API/Integration workstream **produced** (`docs/architecture/08_API_INTEGRATION_WORKSTREAM.md`, `CG-S3-ARCH-008` `VERIFIED`). UX/Design System workstream **produced** (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`, `CG-S3-ARCH-009` `VERIFIED`). Testing workstream **produced** (`docs/architecture/10_TESTING_WORKSTREAM.md`, `CG-S3-ARCH-010` `VERIFIED`). DevOps workstream **produced** (`docs/architecture/11_DEVOPS_WORKSTREAM.md`, `CG-S3-ARCH-011` `VERIFIED`; resolves `ADR-CAND-ARCH-004`). Release Train **produced** (`docs/architecture/12_RELEASE_TRAIN.md`, `CG-S3-ARCH-012` `VERIFIED`; supersedes Blueprint §3.2/§8.1/§8.2's external-pilot release-type language with RPD-034/036). Full Work Breakdown Structure **produced** (`docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md`, `CG-S3-ARCH-013` `VERIFIED`; binds the 430-file prompt package into the mandatory 10-level runtime hierarchy, 263 capability prompts registered). Requirement/Phase Traceability **produced** (`docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md`, `CG-S3-ARCH-014` `VERIFIED`; 401 traced items, 0 `NOT_COVERED`). Risk-Ranked Critical Path **produced** (`docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md`, `CG-S3-ARCH-015` `VERIFIED`; 9-dimension reproducible CRS ranking, critical path matches `12_*.md` §9, top risk `FIN-195` CRS 49). Step 3 Closure Verification **produced** (`docs/architecture/16_STEP3_CLOSURE_REPORT.md`, `CG-S3-ARCH-016` `VERIFIED`; independently re-checked all nine closure conditions, closure state `RUNTIME_ARCHITECTURE_VERIFIED`, two non-blocking findings F1/F2 surfaced and corrected). **Step 3 is now fully closed (16/16 outputs).** Phase 0 Foundation (`05-phase-00-discovery-foundation/`, Prompts 79–102) is the next workstream.

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
| Active phase/workstream | Step 3 CLOSED (`RUNTIME_ARCHITECTURE_VERIFIED`, 16/16 prompts); Phase 0 — Foundation now active (`NOT_STARTED`) |
| Current task | `CG-S3-ARCH-016` — Step 3 Closure Verification |
| Task status | `VERIFIED` — `docs/architecture/16_STEP3_CLOSURE_REPORT.md` complete, closure state `RUNTIME_ARCHITECTURE_VERIFIED` |
| Branch/commit | `claude/sleepy-ride-4vxsk6`, cut from `main`@`27389a4`, merged forward with `agent/cargogrid-autonomous-build` |
| Last known good checkpoint | `origin/main`@`39d923e` |
| Latest applied migration | none |
| Last fully passing gate set | none (no gates exist; confirmed `UNKNOWN` baseline, not a failure) |
| Active blockers | none |
| Known issues affecting work | ISS-2026-002 (recurred twice previously, non-blocking), ISS-2026-003 (non-blocking); ISS-2026-001 RESOLVED |
| Next eligible task | Phase 0 Foundation kickoff — `05-phase-00-discovery-foundation/79_PHASE0_README.md` → `80_PHASE0_WBS_RUNTIME_KICKOFF_PROMPT.md` |

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
