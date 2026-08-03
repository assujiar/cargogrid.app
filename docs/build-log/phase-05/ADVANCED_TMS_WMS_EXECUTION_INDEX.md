# Advanced TMS/WMS Execution Index

**Prompt:** `CG-S10-ATW-001` (`CG-AABPP-ATW-220` v0.12.0-multisource-gps)
**Runtime output of:** `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_5_IN_PROGRESS`. Rows `220`–`225` (`CG-S10-ATW-001..006`) are `VERIFIED`. Row `226`'s own nine-child decomposition: `ATW-226A` (Tracking entitlement and source policy) is now **`VERIFIED`** (this checkpoint); `ATW-226B`/`226C` remain dependency-clean `READY`; `ATW-226D`–`226I` remain `NOT_STARTED`, each still blocked on its own real child dependency. `CG-S10-ATW-010` (Prompt 229) also remains independently `READY` (Warehouse lane), but per standing user instruction this session's own execution order stays strictly ascending by row number — the `ATW-226` family is worked before `ATW-229` is touched, regardless of which row became dependency-clean first. Every other row is `NOT_STARTED` (dependency-correct, not yet unblocked). Only Prompt 248 may set `PHASE_5_VERIFIED`.

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-224-n1ek85` |
| HEAD at authoring time (pre-commit) | this session's own prior commit (`CG-S10-ATW-006`, Prompt 225, `VERIFIED`) |
| Worktree state | Clean except this document (reconciliation only — no schema/service/UI file touched) |
| Repository state | `PHASE_4_VERIFIED`; 100 migrations applied, unchanged by this checkpoint |
| Mutation performed by this document | Row `226`'s own §1.4 decomposition table reconciled: `ATW-226A`/`226B`/`226C` status corrected `NOT_STARTED` → `READY` (their own real upstream — Platform entitlement/config `PLT-121`, `ATW-223`, `ATW-225` — is now fully `VERIFIED`); `ATW-226D`–`226I` confirmed still correctly `NOT_STARTED` (each blocked on an unverified child). No implementation of any kind performed — this is a dependency-status correction only, explicitly requested apart from starting any child prompt. |
| Pre-flight collision check | `pnpm run git:check` clean |
| User authorization | Explicit user instruction "jalanin rekonsiliasi dulu, tp jgn execute promptnya. gue mau tetep berurutan 225, 226, 227 dst. jgn tiba2 229 setelah 225" ("run the reconciliation first, but don't execute the prompt; keep strict order 225, 226, 227, etc.; don't suddenly jump to 229 after 225") — authorizes exactly this reconciliation and records a standing session-level execution-order preference (ascending row number, `226` family before `229`) that overrides pure dependency-graph availability when choosing which `READY` row to work next. |

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
| `CG-S10-ATW-002` | 221 — Multi-Leg and Multimodal Shipment | Advanced Transportation / Multi-Leg and Multimodal Shipment | `ATW-220`; verified Phase 3 Job Order/Shipment Order/lifecycle/milestone/ePOD/cost/readiness and Phase 4 Finance contracts | `ATW-222..228`, `ATW-238`, `ATW-243`, `ATW-244` | **`VERIFIED`** | Complete — `docs/build-log/phase-05/ATW-221.md`. `CG-S10-ATW-003` (222) is dependency-clean `READY` |
| `CG-S10-ATW-003` | 222 — Advanced Dispatch Board with Tracking Health | Advanced Transportation / Dispatcher Control Tower | `ATW-221`, verified Phase 3 dispatch; tracking columns additionally need `ATW-226F`/`226H` (may implement dispatch itself before 226, tracking columns feature-gated until then) | `ATW-223..228`, `ATW-243`, `ATW-245..248`, Customer Portal tracking | **`VERIFIED`** | Complete — `docs/build-log/phase-05/ATW-222.md`. `CG-S10-ATW-004` (223) is dependency-clean `READY` |
| `CG-S10-ATW-004` | 223 — Fleet, Vehicle, Driver, Device and SIM Operational Baseline | Transport Resources / Operational Resource Control | `ATW-221..222`, Platform master/config/entitlement, verified Phase 3 resource assignment | `ATW-224..228`, `ATW-226B/C` | **`VERIFIED`** | Complete — `docs/build-log/phase-05/ATW-223.md`. `CG-S10-ATW-005` (224) is dependency-clean `READY` |
| `CG-S10-ATW-005` | 224 — Route and Load Planning Using Canonical Position | Advanced Transportation / Constraint-Aware Planning | `ATW-221`, `ATW-223`, verified PostGIS/location/config foundations; live-position replanning additionally needs `ATW-226F` | `ATW-225`, `ATW-227`, `ATW-243` | **`VERIFIED`** | Complete — `docs/build-log/phase-05/ATW-224.md`. `CG-S10-ATW-006` (225) is dependency-clean `READY` |
| `CG-S10-ATW-006` | 225 — First-, Middle-, and Last-Mile Orchestration with Tracking Policy | Advanced Transportation / End-to-End Mile Execution | `ATW-221`, `ATW-224`, verified Phase 3 milestones/exceptions, resource eligibility `ATW-223` | `ATW-226`(`ATW-226C`), `ATW-228`, `ATW-243`, `ATW-244` | **`VERIFIED`** | Complete — `docs/build-log/phase-05/ATW-225.md`. No other row newly dependency-clean; `CG-S10-ATW-010` (229) remains the only other `READY` row |
| §1.4 | 226 — Multi-Source GPS and Telematics Integration | Transportation Integration / Trusted Movement Events | see §1.4 (decomposed into `ATW-226A`..`226I`) | `ATW-227`, `ATW-228`, `ATW-243` | `IN_PROGRESS` (1 of 9 children `VERIFIED`: `226A`; 2 `READY`: `226B`/`226C`; 6 `NOT_STARTED`) | See §1.4 — `226A` `VERIFIED` this checkpoint (`docs/build-log/phase-05/ATW-226A.md`); `226B`/`226C` dependency-clean, awaiting fresh explicit authorization |
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

### 1.3 Full-column detail — `READY` rows (`229`, `226B`, `226C`), plus rows `224`, `225`, and `226A` now `VERIFIED`

#### Row `221` — `CG-S10-ATW-002`

| Column | Value |
|---|---|
| `atomic_objective` | Extend the verified Shipment Order into ordered multi-pickup, transfer, linehaul and delivery legs across land, air and sea without duplicating the canonical root |
| `source_ids` | `221_MULTI_LEG_MULTIMODAL_SHIPMENT_PROMPT.md` full; verified `app.shipment_orders` (`OPS-*`) |
| `allowed_paths` | `supabase/migrations/20260729290000_create_advanced_tms_multi_leg_shipment.sql`; `server/contracts/multi-leg-shipment/multi-leg-shipment.ts`; `server/queries/multi-leg-shipment.ts`; `server/mutations/multi-leg-shipment.ts` (plus their `.test.ts` files); `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/leg-network-panel.tsx`, `page.tsx`, `actions.ts` (extended); `scripts/db-tests/advanced-tms-multi-leg-shipment.sql`; `server/contracts/shipment-order/shipment-order.ts` and `server/contracts/basic-dispatch/basic-dispatch.ts` (extended for the new `leg_network_status` column) |
| `forbidden_paths` | Any second Job Order/Shipment Order root; Finance posting surfaces; warehouse-lane paths (`ATW-229`+) — none touched |
| `migration_ids` | `20260729290000_create_advanced_tms_multi_leg_shipment.sql` (1 new additive migration; 96 total) |
| `api_contracts` | Service-layer RPC wrappers only (no REST/GraphQL surface exists repository-wide yet) — 10 new RPCs |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this row) |
| `access_controls` | Reuses `app.evaluate_permission`(`OPS`:`Create`/`Edit`)/`can_access_record`/`lead_record_scope_org_unit_ids`, mirroring every prior Operations capability |
| `transport_invariants` | Leg sequence must be contiguous 1..N with no gap/duplicate among non-cancelled legs to confirm; cargo allocation sum across non-cancelled legs never exceeds the parent Shipment Order's own allocation; a leg cannot dispatch until its own network is confirmed; custody events are append-only with server-assigned sequencing |
| `tests` | `scripts/db-tests/advanced-tms-multi-leg-shipment.sql` (new); `server/contracts\|queries\|mutations/multi-leg-shipment.test.ts` (21 net new `node:test` cases) |
| `external_evidence_status` | n/a (no external hardware/provider dependency in this capability) |
| `commands` | `pnpm install --frozen-lockfile`; `typecheck`; `lint`; `pnpm run test`; `pnpm run db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-221.md`; `node:test` 2186/2186; `db:test` PASS across 96 migrations/98 files; `next build` PASS (77 routes, unchanged) |
| `rollback` | `git revert` the row's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `CG-S10-ATW-003` (Prompt 222) is `READY` and named in this session's own "lanjut prompt 221-223" authorization |

#### Row `224` — `CG-S10-ATW-005`

| Column | Value |
|---|---|
| `atomic_objective` | Implement explainable route and load planning that reads location-dependent input through exactly one trusted, source-arbitrated canonical-position projection — never raw mobile, direct-device, or third-party telemetry |
| `source_ids` | `224_ROUTE_LOAD_PLANNING_PROMPT.md` full; verified `app.shipment_orders` (`OPS-*`); `app.shipment_tracking_health` (`ATW-222`); `app.vehicle_operational_profiles`/`app.driver_operational_profiles` (`ATW-223`); `app.jobs` generic queue (`PLT-132`) |
| `allowed_paths` | `supabase/migrations/20260729320000_create_advanced_tms_route_load_planning.sql`; `server/contracts/route-load-planning/route-load-planning.ts`; `server/queries/route-load-planning.ts`; `server/mutations/route-load-planning.ts` (plus their `.test.ts` files); `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/route-planning/` (`page.tsx`, `loading.tsx`, `actions.ts`, `route-planning-workspace.tsx`); `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/page.tsx` (one added link, extended); `scripts/db-tests/advanced-tms-route-load-planning.sql` |
| `forbidden_paths` | Any second position-input surface bypassing `app.shipment_tracking_health`; any mutation of `app.shipment_legs` (planning is decision support only); warehouse-lane paths (`ATW-229`+) — none touched |
| `migration_ids` | `20260729320000_create_advanced_tms_route_load_planning.sql` (1 new additive migration; 99 total) |
| `api_contracts` | Service-layer RPC wrappers only (no REST/GraphQL surface exists repository-wide yet) — 14 new RPCs plus one widened (`app.enqueue_job`, `CREATE OR REPLACE`, adding the `route_load_planning` job type) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this row) |
| `access_controls` | Reuses `app.evaluate_permission`(`OPS`:`Create`/`Edit`/`Override`)/`can_access_record`/`lead_record_scope_org_unit_ids`, mirroring every prior Operations capability; `OPS`:`Override` (already-seeded, not new) is the concrete override-authority gate |
| `transport_invariants` | A feasible candidate plan is the only one selectable without override; an infeasible candidate requires `OPS`:`Override` plus a non-empty reason; a scenario's own stops/constraints are mutable only while `draft`; selection history is append-only (`is_current`/`superseded_by_id`, never overwritten in place); replanning is blocked once every one of the shipment's own legs has already left `planned` |
| `tests` | `scripts/db-tests/advanced-tms-route-load-planning.sql` (new); `server/contracts\|queries\|mutations/route-load-planning.test.ts` (25 net new `node:test` cases) |
| `external_evidence_status` | n/a (no external hardware/provider dependency in this capability; live-position replanning remains gated on `ATW-226F`, not yet built — every scenario this checkpoint planned in position-unaware manual mode, honestly) |
| `commands` | `pnpm install --frozen-lockfile`; `typecheck`; `lint`; `pnpm run test`; `pnpm run db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-224.md`; `node:test` 2230/2230; `db:test` PASS across 99 migrations/101 files; `next build` PASS (81 routes, 1 new) |
| `rollback` | `git revert` the row's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `CG-S10-ATW-006` (Prompt 225) is dependency-clean `READY`; not authorized this session — awaiting fresh explicit user authorization naming Prompt 225 |

#### Row `225` — `CG-S10-ATW-006`

| Column | Value |
|---|---|
| `atomic_objective` | Implement a tracking-policy and session-orchestration layer for each shipment leg's first-, middle-, and last-mile execution — deciding and recording which authoritative source should be tracking a leg and why, never ingesting or storing raw telemetry itself |
| `source_ids` | `225_MILE_ORCHESTRATION_TRACKING_POLICY_PROMPT.md` full; verified `app.shipment_legs` (`ATW-221`); `app.shipment_tracking_health`/`app.is_shipment_tracking_entitled` (`ATW-222`); `app.vehicle_operational_profiles`/`app.driver_operational_profiles`/`app.gps_devices`/`app.provider_vehicle_mappings` (`ATW-223`); `app.resource_assignments` (`OPS-172`); `app.report_exception` (`OPS-174`) |
| `allowed_paths` | `supabase/migrations/20260729330000_create_advanced_tms_mile_orchestration.sql`; `server/contracts/mile-orchestration/mile-orchestration.ts`; `server/queries/mile-orchestration.ts`; `server/mutations/mile-orchestration.ts` (plus their `.test.ts` files); `app/(tenant)/[tenantSlug]/operations/shipment-orders/[shipmentOrderId]/mile-tracking-panel.tsx` (new); `leg-network-panel.tsx`, `actions.ts`, `page.tsx` (extended); `scripts/db-tests/advanced-tms-mile-orchestration.sql` |
| `forbidden_paths` | Any raw telemetry ingestion/storage path (reserved for `ATW-226`); any mutation of `app.transition_shipment_leg` or other already-applied `ATW-221` functions; warehouse-lane paths (`ATW-229`+) — none touched |
| `migration_ids` | `20260729330000_create_advanced_tms_mile_orchestration.sql` (1 new additive migration; 100 total) |
| `api_contracts` | Service-layer RPC wrappers only (no REST/GraphQL surface exists repository-wide yet) — 8 new RPCs |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this row) |
| `access_controls` | Reuses `app.evaluate_permission`(`OPS`:`Create`/`Edit`/`Override`)/`can_access_record`, mirroring every prior Operations capability; `OPS`:`Override` (already-seeded, not new) gates the `unauthorized_override` end path and requires a mandatory reason note |
| `transport_invariants` | A leg may have at most one current tracking session (`is_current`, enforced by partial unique index); session start/handoff/end always requires real, currently-eligible source assignment (`app.check_leg_tracking_source_eligible`), never entitlement alone; entitlement is disclosed (`tracking_entitled_at_start`) but never a hard gate on orchestration bookkeeping; a stale session past its policy's own `no_signal_escalation_seconds` is provably ended and raises a real, deduplicated `app.operational_exceptions` row; session history is append-only (`is_current`/`superseded_by_id`, never overwritten in place) |
| `tests` | `scripts/db-tests/advanced-tms-mile-orchestration.sql` (new); `server/contracts\|queries\|mutations/mile-orchestration.test.ts` (23 net new `node:test` cases) |
| `external_evidence_status` | n/a (no external hardware/provider dependency in this capability; real eligibility is checked against `ATW-223`'s own already-verified operational-profile/device/provider-mapping data, never a live feed) |
| `commands` | `pnpm install --frozen-lockfile`; `typecheck`; `lint`; `pnpm run test`; `pnpm run db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-225.md`; `node:test` 2253/2253; `db:test` PASS across 100 migrations/102 files; `next build` PASS (81 routes, unchanged — an existing route extended, not a new one) |
| `rollback` | `git revert` the row's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | No other row became newly dependency-clean this checkpoint; `CG-S10-ATW-010` (Prompt 229) remains the only other `READY` row, awaiting fresh explicit user authorization naming Prompt 229 |

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

#### Child `226A` — Tracking entitlement and source policy

| Column | Value |
|---|---|
| `atomic_objective` | Implement tenant tracking-package entitlement, package limits, and per-tenant source policy (priority/freshness/accuracy rules) that later children (`226D`–`226I`) read rather than re-deriving |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226A`'s own scope line) plus the shared §§9/13/16/24/26 requirements; verified Platform Configuration Engine (`PLT-121`); `app.is_shipment_tracking_entitled` (`ATW-222`'s own always-`false` stub, given its real implementation here) |
| `allowed_paths` | `supabase/migrations/20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql`; `server/contracts/tracking-source-policy/tracking-source-policy.ts`; `server/queries/tracking-source-policy.ts`; `server/mutations/tracking-source-policy.ts` (plus their `.test.ts` files); `scripts/db-tests/advanced-tms-tracking-entitlement-source-policy.sql`; `docs/build-log/phase-05/ATW-226A.md` |
| `forbidden_paths` | Any raw telemetry ingestion path (reserved for `226C`/`226D`/`226E`); any second entitlement/config root bypassing `PLT-121`'s own Configuration Engine; any second source-priority root duplicating `ATW-223`'s own `app.vehicle_tracking_source_priorities` — none touched |
| `migration_ids` | `20260729340000_create_advanced_tms_tracking_entitlement_source_policy.sql` (1 new additive migration; 101 total) |
| `api_contracts` | Service-layer RPC wrappers only (no REST/GraphQL surface exists repository-wide yet) — 3 new RPCs (`resolve_tenant_tracking_package`, `upsert_tenant_tracking_source_policy`, `resolve_tenant_tracking_source_policy`) plus 1 widened (`app.is_shipment_tracking_entitled`, `CREATE OR REPLACE`, real implementation replacing `ATW-222`'s stub) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none (no external integration in this child) |
| `access_controls` | Entitlement/package assignment reuses `PLT-121`'s own Configuration Engine authority (`app.check_config_object_authority`, tenant_admin/Supreme) unmodified; `app.upsert_tenant_tracking_source_policy` reuses `app.evaluate_permission`(`OPS`:`Edit`), the same tier `ATW-223`'s own vehicle-level source-priority function uses |
| `transport_invariants` | n/a at this child (policy/entitlement only — no telemetry event exists yet to invariant-check); `app.resolve_tenant_tracking_package`/`app.resolve_tenant_tracking_source_policy` always return exactly one row with an honest disclosed default, never `NULL` or a raised error |
| `tests` | `scripts/db-tests/advanced-tms-tracking-entitlement-source-policy.sql` (new); `server/contracts\|queries\|mutations/tracking-source-policy.test.ts` (20 net new `node:test` cases) |
| `external_evidence_status` | n/a for this child itself (hardware/provider evidence deferral applies to `226D`/`226E`, not here) |
| `commands` | `pnpm install --frozen-lockfile`; `typecheck`; `lint`; `pnpm run test`; `pnpm run db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226A.md`; `node:test` 2273/2273; `db:test` PASS across 101 migrations/103 files; `next build` PASS (81 routes, unchanged) |
| `rollback` | `git revert` the child's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226B`/`226C` remain dependency-clean `READY` (no dependency relationship among the three siblings); `CG-S10-ATW-010` (Prompt 229) remains the only other independently `READY` row. Awaiting fresh explicit user authorization naming the next task |

#### Child `226B` — Device, SIM, provider, installation, and mapping management

| Column | Value |
|---|---|
| `atomic_objective` | Extend `ATW-223`'s own `app.gps_devices`/`app.provider_vehicle_mappings` baseline with the SIM, installation-evidence, and mobile-eligibility mapping records `226D`/`226E`/`226C` will each depend on |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226B`'s own scope line); verified `app.gps_devices`/`app.vehicle_operational_profiles`/`app.driver_operational_profiles`/`app.provider_vehicle_mappings` (`ATW-223`) |
| `allowed_paths` (planned, exact filenames chosen at build time) | New additive `supabase/migrations/<timestamp>_extend_advanced_tms_device_provider_mapping.sql`; `server/{contracts,queries,mutations}/device-provider-mapping.ts` (or an extension of `ATW-223`'s own fleet-resource files if additive-column shaped rather than new-table shaped); `scripts/db-tests/advanced-tms-device-provider-mapping.sql`; device/SIM/installation/provider mapping administration UI (§15) |
| `forbidden_paths` | Any edit to `ATW-223`'s own already-applied migration; any raw telemetry ingestion path (reserved for later children) |
| `migration_ids` | none yet — one new additive migration planned when this child starts |
| `api_contracts` | Planned: SIM/installation/mapping CRUD, service-layer only |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | Provider API credentials, server-side only (§16) — exact secret registry entries planned when this child starts |
| `access_controls` | Planned reuse of `app.evaluate_permission`(`OPS`)/`can_access_record`, mirroring `ATW-223`'s own resource-record shape |
| `transport_invariants` | n/a at this child (mapping/administration only — no telemetry event exists yet) |
| `tests` | Planned `node:test` service-layer coverage + a dedicated db-test file |
| `external_evidence_status` | n/a for this child itself |
| `commands` | Not yet run — deferred to when this child starts |
| `evidence` | none yet |
| `rollback` | Planned: `git revert` the child's own commit; migration is additive only |
| `owner` | Runtime build agent (unassigned until authorized) |
| `status` | `READY` |
| `resume_point` | Dependency-clean this checkpoint; awaiting fresh explicit user authorization naming `226B` (or `226` generally) |

#### Child `226C` — Driver Mobile GPS session and HTTPS ingestion

| Column | Value |
|---|---|
| `atomic_objective` | Implement the authenticated HTTPS session lifecycle (start/heartbeat/location/pause/stop) the Driver PWA uses to report position, bound to a real driver/vehicle/trip/session — the first genuinely real telemetry-producing surface in this repository |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226C`'s own scope line) plus §§14A/16/21–23/26; verified `app.shipment_legs` (`ATW-221`); `app.shipment_leg_tracking_policies`/`sessions` (`ATW-225`, this checkpoint's own tracking-session orchestration layer, which `226C` must integrate with rather than duplicate); `ATW-223`'s own driver consent/eligibility flags |
| `allowed_paths` (planned, exact filenames chosen at build time) | New additive `supabase/migrations/<timestamp>_create_advanced_tms_mobile_tracking_ingestion.sql`; `server/{contracts,queries,mutations}/mobile-tracking-ingestion.ts`; a real authenticated API route (first non-Server-Action HTTPS surface for this capability, per §14's own "authenticated HTTPS endpoint" requirement); `scripts/db-tests/advanced-tms-mobile-tracking-ingestion.sql`; Driver PWA start/stop/permission/freshness interface (§15) |
| `forbidden_paths` | Any Supabase service-role/DB credential placed in the PWA/browser (§16, hard rule); any claim of native-grade background tracking (§15); direct mutation of `app.shipment_leg_tracking_sessions` outside its own already-verified `ATW-225` RPCs |
| `migration_ids` | none yet — one new additive migration planned when this child starts |
| `api_contracts` | Planned: session start/heartbeat/location/pause/stop, service-layer plus one real HTTPS endpoint |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target; no separate deployable service required for this child (unlike `226D`'s own always-on gateway) |
| `secret_ownership` | Server-generated session token only; no client-held service credential (§14/§16, hard rule) |
| `access_controls` | Driver controls only their own assigned mobile session (§26); planned reuse of `app.evaluate_permission` plus a session-token check distinct from the tenant-portal auth model |
| `transport_invariants` | A mobile session may only report position while `app.shipment_leg_tracking_sessions` shows it as the current, eligible source for that leg (integrating with `ATW-225`'s own `start_leg_tracking_session`, never bypassing it); event time and received time are recorded separately (§24) |
| `tests` | Planned `node:test` service-layer coverage, mobile-HTTPS integration tests, and a dedicated db-test file |
| `external_evidence_status` | n/a for this child itself (no hardware/provider dependency — mobile is a first-party HTTPS surface) |
| `commands` | Not yet run — deferred to when this child starts |
| `evidence` | none yet |
| `rollback` | Planned: `git revert` the child's own commit; migration is additive only |
| `owner` | Runtime build agent (unassigned until authorized) |
| `status` | `READY` |
| `resume_point` | Dependency-clean this checkpoint; awaiting fresh explicit user authorization naming `226C` (or `226` generally) |

### 1.4 Row `226` decomposition — `ATW-226A`..`ATW-226I` (mandatory per `220_*.md`)

Reproduced from `220_*.md`'s own mandatory table, each child retaining parent prompt `226` (`CG-AABPP-ATW-226`) per `222_*.md` §1's own instruction ("every child must retain this parent prompt ID and receive its own atomic task ID").

| `task_id` | Atomic scope | `upstream` | `status` | `external_evidence_status` |
|---|---|---|---|---|
| `ATW-226A` | Tracking entitlement and source policy | Platform entitlement/config (`PLT-121`, `VERIFIED`); parent-level `ATW-221`/`223`/`225` (all `VERIFIED`) | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226A.md` | n/a |
| `ATW-226B` | Device, SIM, provider, installation, and mapping management | `ATW-223` (`VERIFIED`) | **`READY`** — dependency-clean this checkpoint | n/a |
| `ATW-226C` | Driver Mobile GPS session and HTTPS ingestion | `ATW-223`/`225` (both `VERIFIED`) | **`READY`** — dependency-clean this checkpoint | n/a |
| `ATW-226D` | Always-on GPS Gateway and Teltonika Codec 8E adapter | `ATW-226A`/`B` | `NOT_STARTED` — blocked until both are `VERIFIED` | `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` (WBS §8) |
| `ATW-226E` | Third-party GPS platform adapter contract | `ATW-226A`/`B` | `NOT_STARTED` — blocked until both are `VERIFIED` | `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` (WBS §8) |
| `ATW-226F` | Canonical telemetry storage, normalization, ordering, and source arbitration | `ATW-226C`/`D`/`E` | `NOT_STARTED` — blocked until all three are `VERIFIED` | n/a |
| `ATW-226G` | Geofence, milestone, exception, and route-deviation signals | `ATW-226F` | `NOT_STARTED` — blocked on `ATW-226F` `VERIFIED` | n/a |
| `ATW-226H` | Fleet Control Tower, device administration, and sanitized projections | `ATW-226F`/`G` | `NOT_STARTED` — blocked until both are `VERIFIED` | n/a |
| `ATW-226I` | Deployment, observability, load, security, outage, and recovery verification | `ATW-226A`..`H` | `NOT_STARTED` — blocked until every prior child is `VERIFIED` | Both statuses above re-confirmed at this closing child |

Overall row `226` (`ATW-226`, parent) requires: `ATW-221`, `ATW-223`, `ATW-225`, Platform API/webhook/job/PostGIS/entitlement/secrets controls, and an approved initial Teltonika protocol specification. A live third-party provider contract is optional at this checkpoint (§8 above). `ATW-225` is `VERIFIED`, so the parent-level upstream gate (`ATW-221`, `ATW-223`, `ATW-225`) is fully satisfied. **`ATW-226A` is now `VERIFIED`** (this checkpoint, `docs/build-log/phase-05/ATW-226A.md`) — real entitlement/package-limits resolution (Configuration Engine reuse) and a tenant-level default source policy now exist. `226B`/`226C` remain dependency-clean `READY` (no dependency relationship among the three siblings). `226D`/`226E` still each need `226A`+`226B` verified — `226A` alone is not sufficient, `226B` remains outstanding. `226F` needs `226C`+`226D`+`226E`, `226G` needs `226F`, `226H` needs `226F`+`226G`, and `226I` (the closing child) needs every prior child verified. Neither `226B` nor `226C` is authorized to start by this checkpoint — awaiting fresh explicit user authorization naming a specific next task.

## 2. Tally

| State | Count |
|---|---|
| `VERIFIED` | 7 (`220`, `221`, `222`, `223`, `224`, `225`, `226A`) |
| `READY` | 3 (`226B`, `226C`, `229`) |
| `NOT_STARTED` | 27 (`227`, `228`, `230`–`248`, and the 6 remaining `226` children `226D`–`226I`) |
| **Total task rows** | **37** |

## 3. Completion statement

This index satisfies `220_*.md`'s "Required execution-index columns" and "mark only dependency-clean tasks `READY`" instructions. `PHASE_5_IN_PROGRESS` is set; `PHASE_5_VERIFIED` remains reserved for Prompt 248 alone. This checkpoint corrects row `226`'s own §1.4 decomposition table: `ATW-226A` (Tracking entitlement and source policy) moves `READY` → **`VERIFIED`** (`docs/build-log/phase-05/ATW-226A.md`) — real per-tenant entitlement/package-limits resolution (reusing Configuration Engine, `PLT-121`, per `ATW-222`'s own citation) and a tenant-level default source policy (priority/freshness/accuracy/hysteresis, complementing `ATW-223`'s own per-vehicle `app.vehicle_tracking_source_priorities`) now exist. `ATW-226B`/`226C` remain dependency-clean `READY`, unaffected (no dependency relationship among the three siblings). `ATW-226D`–`226I` remain correctly `NOT_STARTED`, each still blocked on an unverified child per its own dependency chain (`226D`/`226E` need `226A`+`226B` — `226B` is still outstanding; `226F` needs `226C`+`226D`+`226E`; `226G` needs `226F`; `226H` needs `226F`+`226G`; `226I`, the closing child, needs every prior child). Authorized by explicit user instruction "lanjut prompt 226," read per the prior checkpoint's own recorded default (`226A` as the natural first pick). Per this repository's own standing one-checkpoint-one-task discipline, this session stops here, awaiting fresh explicit user authorization naming a specific next task (most naturally `226B` or `226C`, or `226` generally, to preserve the requested ascending order; `229` remains available but is deliberately not the default next pick per the user's own stated preference).
