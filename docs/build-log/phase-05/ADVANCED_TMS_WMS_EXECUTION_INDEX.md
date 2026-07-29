# Advanced TMS/WMS Execution Index

**Prompt:** `CG-S10-ATW-001` (`CG-AABPP-ATW-220` v0.12.0-multisource-gps)
**Runtime output of:** `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_5_IN_PROGRESS` — set this checkpoint. Row `220` (`CG-S10-ATW-001`) is `VERIFIED`. `CG-S10-ATW-002` (Prompt 221) and `CG-S10-ATW-010` (Prompt 229) are the only two rows marked `READY`; every other row is `NOT_STARTED` (dependency-correct, not yet authorized/unblocked). Only Prompt 248 may set `PHASE_5_VERIFIED`.

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/ulangi-prompt-219-7evdpp` |
| HEAD at authoring time (pre-commit) | this session's own prior commit (Prompt 219 re-read/re-confirmation, 2026-07-29) |
| Worktree state | Clean except this document, its sibling `00_ADVANCED_TMS_WMS_WBS.md`, and this checkpoint's own runtime-ledger updates |
| Repository state | `PHASE_4_VERIFIED` (all 29 Finance rows `VERIFIED`); 95 migrations applied, unchanged this checkpoint (zero migration — kickoff/index only) |
| Mutation performed by this document | Row `220` instantiated `VERIFIED`; `PHASE_5_IN_PROGRESS` set; rows `221`–`248` (37 total task rows, `226` decomposed into 9 children) instantiated at `NOT_STARTED`/`READY` per §1 |
| Pre-flight collision check | `pnpm run git:check` clean — this branch carries 1 commit ahead of `origin/main`, no other branch collision detected |
| User authorization | Explicit user instruction "lanjut prompt 220" ("continue prompt 220") — a single named-task authorization, not a range. Authorizes this kickoff only. |

## 1. Full execution index

### 1.1 Row `220` — Prompt 220, `CG-S10-ATW-001` (this task)

| Column | Value |
|---|---|
| `task_id` | `CG-S10-ATW-001` |
| `parent_prompt` | Prompt 220 (`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md`) |
| `child_slice` | none (kickoff is atomic) |
| `workstream` | Governance / Phase 5 Kickoff |
| `epic` | Advanced TMS/WMS WBS and Runtime Kickoff |
| `capability` | Phase 5 hierarchy, dependency graph, bounded atomic tasks, deployment workstreams, evidence ledger |
| `atomic_objective` | Create the repository-specific Phase 5 hierarchy/dependency graph/task ledger/evidence ledger without implementing any capability — see `220_*.md` §"Objective" |
| `source_ids` | `219_ADVANCED_TMS_WMS_README.md` §1–10; `220_*.md` full; RPD-016/022/025/040 (carried forward, unchanged) |
| `upstream` | `PHASE_4_VERIFIED` |
| `downstream` | Every row in §1.2–§1.4 below (`221`–`248`, 37 task rows total) |
| `allowed_paths` | `docs/build-log/phase-05/00_ADVANCED_TMS_WMS_WBS.md`, `ADVANCED_TMS_WMS_EXECUTION_INDEX.md`, `docs/runtime/*.md` |
| `forbidden_paths` | any Phase 5 domain schema/service/UI/deployment file |
| `migration_ids` | none |
| `api_contracts` | none |
| `deployment_target` | none (planning only — see WBS §6 for the Web/API vs. GPS Gateway ownership recorded this checkpoint) |
| `secret_ownership` | none (planning only) |
| `access_controls` | none (planning only) |
| `transport_invariants` | none (planning only — canonical telemetry invariants are recorded as future obligations in WBS §4/§7, not enforced by any code yet) |
| `tests` | none (docs-only task) |
| `external_evidence_status` | n/a for this row itself; `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` and `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` recorded for `ATW-226D`/`226E` per WBS §8 |
| `commands` | Fresh `pnpm install --frozen-lockfile`; `typecheck`; `lint`; `pnpm run test`; `docs:check`; `security:check`; `data-classification:check`; `threat-model:check`; `standards:check`; `git:check-paths`; `git:check`; `db:test` (`scripts/db-tests/run.sh`); `next build` — all re-run fresh this checkpoint as baseline reconciliation, before any Phase 5 file was written |
| `evidence` | This document + `00_ADVANCED_TMS_WMS_WBS.md`. Baseline results: `typecheck`/`lint` 0 errors (80 pre-existing warnings unchanged); `node:test` **2165/2165**; `db:test` PASS across 95 migrations/97 db-test files; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths` all pass; `next build` PASS (77 routes, unchanged) |
| `rollback` | `git revert` this commit — docs-only, no schema/data to roll back |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` (this checkpoint) |
| `resume_point` | `CG-S10-ATW-002` (Prompt 221) and `CG-S10-ATW-010` (Prompt 229) are both `READY`; neither is authorized by this checkpoint's own "lanjut prompt 220" instruction — fresh explicit user authorization is required before either begins |

### 1.2 Master dependency/status table — rows `221`–`248` (excluding `226`, decomposed separately in §1.4)

| `task_id` | Prompt | Workstream / Capability | `upstream` | `downstream` | `status` | `resume_point` |
|---|---|---|---|---|---|---|
| `CG-S10-ATW-002` | 221 — Multi-Leg and Multimodal Shipment | Advanced Transportation / Multi-Leg and Multimodal Shipment | `ATW-220`; verified Phase 3 Job Order/Shipment Order/lifecycle/milestone/ePOD/cost/readiness and Phase 4 Finance contracts | `ATW-222..228`, `ATW-238`, `ATW-243`, `ATW-244` | **`READY`** | Dependency-clean; awaiting explicit authorization |
| `CG-S10-ATW-003` | 222 — Advanced Dispatch Board with Tracking Health | Advanced Transportation / Dispatcher Control Tower | `ATW-221`, verified Phase 3 dispatch; tracking columns additionally need `ATW-226F`/`226H` (may implement dispatch itself before 226, tracking columns feature-gated until then) | `ATW-223..228`, `ATW-243`, `ATW-245..248`, Customer Portal tracking | `NOT_STARTED` | Blocked on `ATW-221` `VERIFIED` |
| `CG-S10-ATW-004` | 223 — Fleet, Vehicle, Driver, Device and SIM Operational Baseline | Transport Resources / Operational Resource Control | `ATW-221..222`, Platform master/config/entitlement, verified Phase 3 resource assignment | `ATW-224..228`, `ATW-226B/C` | `NOT_STARTED` | Blocked on `ATW-222` `VERIFIED` |
| `CG-S10-ATW-005` | 224 — Route and Load Planning Using Canonical Position | Advanced Transportation / Constraint-Aware Planning | `ATW-221`, `ATW-223`, verified PostGIS/location/config foundations; live-position replanning additionally needs `ATW-226F` | `ATW-225`, `ATW-227`, `ATW-243` | `NOT_STARTED` | Blocked on `ATW-223` `VERIFIED` |
| `CG-S10-ATW-006` | 225 — First-, Middle-, and Last-Mile Orchestration with Tracking Policy | Advanced Transportation / End-to-End Mile Execution | `ATW-221`, `ATW-224`, verified Phase 3 milestones/exceptions, resource eligibility `ATW-223` | `ATW-226`(`ATW-226C`), `ATW-228`, `ATW-243`, `ATW-244` | `NOT_STARTED` | Blocked on `ATW-224` `VERIFIED` |
| §1.4 | 226 — Multi-Source GPS and Telematics Integration | Transportation Integration / Trusted Movement Events | see §1.4 (decomposed into `ATW-226A`..`226I`) | `ATW-227`, `ATW-228`, `ATW-243` | `NOT_STARTED` | See §1.4 |
| `CG-S10-ATW-008` | 227 — Capacity, Utilization and Tracking Coverage | Transport Resources / Capacity Control | `ATW-223`..`226` (all `ATW-226` children), verified exact cargo/UOM data | `ATW-243` | `NOT_STARTED` | Blocked on `ATW-226I` `VERIFIED` |
| `CG-S10-ATW-009` | 228 — Advanced Milestone and Exception with Multi-Source Telemetry | Operations Control Tower / Predictable Network Execution | `ATW-221`, `ATW-225..227`, Prompt 226 canonical telemetry (`ATW-226F/G`), verified Phase 3 milestone/exception contracts | `ATW-243`, `ATW-244` | `NOT_STARTED` | Blocked on `ATW-227` `VERIFIED` |
| `CG-S10-ATW-010` | 229 — Warehouse and Zone | Warehouse Foundation / Facility Topology | `ATW-220`, verified Platform master/config/access and location/PostGIS foundations | `ATW-230..242` | **`READY`** | Dependency-clean; awaiting explicit authorization |
| `CG-S10-ATW-011` | 230 — Bin and Racking | Warehouse Foundation / Location Topology | `ATW-229` | `ATW-231..240` | `NOT_STARTED` | Blocked on `ATW-229` `VERIFIED` |
| `CG-S10-ATW-012` | 231 — WMS Inbound | Warehouse Execution / Inbound Order Control | `ATW-229..230`, verified customer/item/master and shipment contracts | `ATW-232`, `ATW-233`, `ATW-238` | `NOT_STARTED` | Blocked on `ATW-230` `VERIFIED` |
| `CG-S10-ATW-013` | 232 — WMS Receiving | Warehouse Execution / Physical Receipt Control | `ATW-231`, active warehouse/location/item/UOM controls | `ATW-233`, `ATW-235`, `ATW-238`, `ATW-244` | `NOT_STARTED` | Blocked on `ATW-231` `VERIFIED` |
| `CG-S10-ATW-014` | 233 — WMS Putaway | Warehouse Execution / Directed Storage | `ATW-230..232` | `ATW-234`, `ATW-238` | `NOT_STARTED` | Blocked on `ATW-232` `VERIFIED` |
| `CG-S10-ATW-015` | 234 — Inventory Ledger | Inventory Control / Canonical Stock Truth | `ATW-229..233`, approved item/UOM/owner/status identity | `ATW-235..240`, `ATW-244` | `NOT_STARTED` | Blocked on `ATW-233` `VERIFIED` |
| `CG-S10-ATW-016` | 235 — Lot, Batch, Serial and Expiry | Inventory Control / Controlled Stock Identity | `ATW-232..234` | `ATW-236`, `ATW-239` | `NOT_STARTED` | Blocked on `ATW-234` `VERIFIED` |
| `CG-S10-ATW-017` | 236 — WMS Picking | Warehouse Execution / Order Fulfillment | `ATW-234..235`, confirmed outbound demand contract | `ATW-237`, `ATW-238` | `NOT_STARTED` | Blocked on `ATW-235` `VERIFIED` |
| `CG-S10-ATW-018` | 237 — WMS Packing | Warehouse Execution / Shipment Preparation | `ATW-236`; label/barcode contract later extended by `ATW-240` | `ATW-238` | `NOT_STARTED` | Blocked on `ATW-236` `VERIFIED` |
| `CG-S10-ATW-019` | 238 — WMS Outbound | Warehouse Execution / Outbound Fulfillment | `ATW-221`, `ATW-231..237` | `ATW-239..242`, `ATW-243` | `NOT_STARTED` | Blocked on `ATW-237` `VERIFIED` (and `ATW-221`) |
| `CG-S10-ATW-020` | 239 — Cycle Count and Inventory Adjustment | Inventory Control / Inventory Accuracy | `ATW-229..238`, esp. `ATW-234` ledger, `ATW-235` tracked stock | `ATW-243` | `NOT_STARTED` | Blocked on `ATW-238` `VERIFIED` |
| `CG-S10-ATW-021` | 240 — Label and Barcode Operations | Warehouse Execution / Scan and Identification | `ATW-229..239`, canonical bin/task/package/stock identities | `ATW-241..243` | `NOT_STARTED` | Blocked on `ATW-239` `VERIFIED` |
| `CG-S10-ATW-022` | 241 — Warehouse Billing Events | Warehouse Commercial Operations / Billable Activity | `ATW-231..240`, verified Phase 4 Finance billing/readiness handoff | `ATW-242`, `ATW-243` | `NOT_STARTED` | Blocked on `ATW-240` `VERIFIED` |
| `CG-S10-ATW-023` | 242 — Customer Inventory Access Contract | Customer Data Access / Inventory Visibility Contract | `ATW-229..241`, Platform identity/customer scope, Finance compatibility | `ATW-243` | `NOT_STARTED` | Blocked on `ATW-241` `VERIFIED` |
| `CG-S10-ATW-024` | 243 — High-Volume TMS/WMS and Multi-Source Telemetry Controls | Operational Scale / High-Volume Reliability | `ATW-221..242`, including all required `ATW-226` child tasks | `ATW-244`, `ATW-245` | `NOT_STARTED` | Blocked on `ATW-242` `VERIFIED` (and every `221`–`226` row) |
| `CG-S10-ATW-025` | 244 — Advanced Claim and Incident Operations | Operational Risk / Claim and Incident Resolution | Verified Step 8 basic incident/claim, `ATW-221/228/232/234/238/243`, verified Finance handoff | `ATW-245` | `NOT_STARTED` | Blocked on `ATW-243` `VERIFIED` |
| `CG-S10-ATW-026` | 245 — Advanced TMS/WMS Integrated Verification | Phase 5 Quality Gate / Integrated Verification | All `ATW-221..244` tasks verified at one compatible checkpoint | `ATW-246` | `NOT_STARTED` | Blocked on `ATW-244` `VERIFIED` |
| `CG-S10-ATW-027` | 246 — Advanced TMS/WMS Integrity and Security Hardening | Phase 5 Assurance / Integrity and Security Hardening | `ATW-245` verified with findings classified | `ATW-247` | `NOT_STARTED` | Blocked on `ATW-245` `VERIFIED` |
| `CG-S10-ATW-028` | 247 — Advanced TMS/WMS Documentation and Handoff | Phase 5 Operational Readiness / Documentation and Handoff | `ATW-246` verified and all earlier evidence current | `ATW-248` | `NOT_STARTED` | Blocked on `ATW-246` `VERIFIED` |
| `CG-S10-ATW-029` | 248 — Advanced TMS/WMS Closure Verification | Phase 5 Closure / Closure Verification | `ATW-247` verified; all Phase 5 evidence available; Phase 4 closure still holds | none (terminal — only this row may set `PHASE_5_VERIFIED`) | `NOT_STARTED` | Blocked on `ATW-247` `VERIFIED` |

For every `NOT_STARTED` row above, the remaining required columns (`allowed_paths`, `forbidden_paths`, `migration_ids`, `api_contracts`, `deployment_target`, `secret_ownership`, `access_controls`, `transport_invariants`, `tests`, `external_evidence_status`, `commands`, `evidence`, `rollback`, `owner`) are **not yet instantiated** — deferred to the checkpoint that authorizes each row, per WBS §13's own atomic-sizing discipline (identical to `00_FINANCE_WBS.md` §8's precedent for its own not-yet-authorized rows). Instantiating exact paths before a row's own upstream is `VERIFIED` risks stale paths, the same reasoning every prior phase kickoff applied.

### 1.3 Full-column detail — the two `READY` rows

#### Row `221` — `CG-S10-ATW-002`

| Column | Value |
|---|---|
| `atomic_objective` | Extend the verified Shipment Order into ordered multi-pickup, transfer, linehaul and delivery legs across land, air and sea without duplicating the canonical root |
| `source_ids` | `221_MULTI_LEG_MULTIMODAL_SHIPMENT_PROMPT.md` full; verified `app.shipment_orders` (`OPS-*`) |
| `allowed_paths` (planned, exact filenames chosen at build time) | New additive `supabase/migrations/<timestamp>_create_advanced_tms_multi_leg_shipment.sql`; `server/{contracts,queries,mutations}/multi-leg-shipment.ts`; `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/legs/**`; `scripts/db-tests/advanced-tms-multi-leg-shipment.sql` |
| `forbidden_paths` | Any second Job Order/Shipment Order root; Finance posting surfaces; warehouse-lane paths (`ATW-229`+) |
| `migration_ids` | none yet — one new additive migration planned when this row starts |
| `api_contracts` | Planned: leg/stop CRUD + reorder + mode-handoff contract, service-layer only (no REST/GraphQL surface exists repository-wide yet) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this row) |
| `access_controls` | Planned reuse of `app.evaluate_permission`/`has_active_tenant_membership`, mirroring every prior Operations capability |
| `transport_invariants` | Leg ordering must be contiguous and non-overlapping per shipment; a leg's own mode/carrier must not silently override the parent Shipment Order's already-governed billing/readiness fields |
| `tests` | Planned `node:test` service-layer coverage + `scripts/db-tests/advanced-tms-multi-leg-shipment.sql` (structural validation, cross-tenant isolation, schema-privilege defense in depth — the standing pattern every capability since `PLT-105` has used) |
| `external_evidence_status` | n/a (no external hardware/provider dependency in this capability) |
| `commands` | Not yet run — deferred to when this row starts |
| `evidence` | none yet |
| `rollback` | Planned: `git revert` the row's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent (unassigned until authorized) |
| `status` | `READY` |
| `resume_point` | Awaiting fresh explicit user authorization naming Prompt 221 |

#### Row `229` — `CG-S10-ATW-010`

| Column | Value |
|---|---|
| `atomic_objective` | Implement tenant/company warehouse and zone masters with versioned topology, operational eligibility and customer/owner scope |
| `source_ids` | `229_WAREHOUSE_ZONE_PROMPT.md` full; verified Platform master/config/access (`PLT-*`), PostGIS foundation (`PLT-134`) |
| `allowed_paths` (planned, exact filenames chosen at build time) | New additive `supabase/migrations/<timestamp>_create_advanced_wms_warehouse_zone.sql`; `server/{contracts,queries,mutations}/warehouse-zone.ts`; `app/(tenant)/[tenantSlug]/warehouse/**`; `scripts/db-tests/advanced-wms-warehouse-zone.sql` |
| `forbidden_paths` | Any transportation-lane path (`ATW-221`+); any second Platform master-data root |
| `migration_ids` | none yet — one new additive migration planned when this row starts |
| `api_contracts` | Planned: warehouse/zone CRUD + versioned topology contract, service-layer only |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this row) |
| `access_controls` | Planned reuse of `app.evaluate_permission`/`has_active_tenant_membership` plus the existing Configuration Engine (`PLT-121`) for versioned topology |
| `transport_invariants` | n/a (warehouse-lane row; no telemetry/position invariant applies) |
| `tests` | Planned `node:test` service-layer coverage + `scripts/db-tests/advanced-wms-warehouse-zone.sql` |
| `external_evidence_status` | n/a |
| `commands` | Not yet run — deferred to when this row starts |
| `evidence` | none yet |
| `rollback` | Planned: `git revert` the row's own commit; migration is additive only |
| `owner` | Runtime build agent (unassigned until authorized) |
| `status` | `READY` |
| `resume_point` | Awaiting fresh explicit user authorization naming Prompt 229 |

### 1.4 Row `226` decomposition — `ATW-226A`..`ATW-226I` (mandatory per `220_*.md`)

Reproduced from `220_*.md`'s own mandatory table, each child retaining parent prompt `226` (`CG-AABPP-ATW-226`) per `222_*.md` §1's own instruction ("every child must retain this parent prompt ID and receive its own atomic task ID").

| `task_id` | Atomic scope | `upstream` | `status` | `external_evidence_status` |
|---|---|---|---|---|
| `ATW-226A` | Tracking entitlement and source policy | Platform entitlement/config (`PLT-121`, already `VERIFIED`) | `NOT_STARTED` — dependency-clean once authorized after `ATW-225`/`226` overall entry (`ATW-221`, `ATW-223`, `ATW-225`) | n/a |
| `ATW-226B` | Device, SIM, provider, installation, and mapping management | `ATW-223` | `NOT_STARTED` | n/a |
| `ATW-226C` | Driver Mobile GPS session and HTTPS ingestion | `ATW-223`/`225` | `NOT_STARTED` | n/a |
| `ATW-226D` | Always-on GPS Gateway and Teltonika Codec 8E adapter | `ATW-226A`/`B` | `NOT_STARTED` | `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` (WBS §8) |
| `ATW-226E` | Third-party GPS platform adapter contract | `ATW-226A`/`B` | `NOT_STARTED` | `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` (WBS §8) |
| `ATW-226F` | Canonical telemetry storage, normalization, ordering, and source arbitration | `ATW-226C`/`D`/`E` | `NOT_STARTED` | n/a |
| `ATW-226G` | Geofence, milestone, exception, and route-deviation signals | `ATW-226F` | `NOT_STARTED` | n/a |
| `ATW-226H` | Fleet Control Tower, device administration, and sanitized projections | `ATW-226F`/`G` | `NOT_STARTED` | n/a |
| `ATW-226I` | Deployment, observability, load, security, outage, and recovery verification | `ATW-226A`..`H` | `NOT_STARTED` | Both statuses above re-confirmed at this closing child |

Overall row `226` (`ATW-226`, parent) requires: `ATW-221`, `ATW-223`, `ATW-225`, Platform API/webhook/job/PostGIS/entitlement/secrets controls, and an approved initial Teltonika protocol specification. A live third-party provider contract is optional at this checkpoint (§8 above). None of the nine children are dependency-clean yet — every one is blocked, directly or transitively, on `ATW-223`/`225` which are themselves `NOT_STARTED`.

## 2. Tally

| State | Count |
|---|---|
| `VERIFIED` | 1 (`220`) |
| `READY` | 2 (`221`, `229`) |
| `NOT_STARTED` | 34 (`222`–`225`, `227`, `228`, `230`–`248`, and all 9 `226` children) |
| **Total task rows** | **37** |

## 3. Completion statement

This index satisfies `220_*.md`'s "Required execution-index columns" and "mark only dependency-clean tasks `READY`" instructions. `PHASE_5_IN_PROGRESS` is set; `PHASE_5_VERIFIED` remains reserved for Prompt 248 alone. This checkpoint's own explicit authorization ("lanjut prompt 220") does not extend to `221`, `229`, or any further row — the next runtime agent/session must obtain fresh explicit user authorization before starting either `READY` row or any further Phase 5 task.
