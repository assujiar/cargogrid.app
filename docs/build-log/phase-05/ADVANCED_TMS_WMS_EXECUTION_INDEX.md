# Advanced TMS/WMS Execution Index

**Prompt:** `CG-S10-ATW-001` (`CG-AABPP-ATW-220` v0.12.0-multisource-gps)
**Runtime output of:** `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_5_IN_PROGRESS`. Rows `220`–`225` (`CG-S10-ATW-001..006`) are `VERIFIED`. Row `226`'s own nine-child decomposition: `ATW-226A`/`226B`/`226C`/`226D`/`226E`/`226F` are now all **`VERIFIED`**; `ATW-226G`–`226I` remain `NOT_STARTED`. `226G` is now the only dependency-unblocked child (needs `226F`, `VERIFIED`) and is next in this session's own explicit range authorization ("lanjut sd prompt terakhir di 226 (226a-226i)"). Every other row is `NOT_STARTED` (dependency-correct, not yet unblocked: `226H` needs `226F`+`226G`, `226I` needs every prior child). Only Prompt 248 may set `PHASE_5_VERIFIED`.

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
| §1.4 | 226 — Multi-Source GPS and Telematics Integration | Transportation Integration / Trusted Movement Events | see §1.4 (decomposed into `ATW-226A`..`226I`) | `ATW-227`, `ATW-228`, `ATW-243` | `IN_PROGRESS` (6 of 9 children `VERIFIED`: `226A`-`226F`; 3 `NOT_STARTED`) | See §1.4 — `226A`-`226F` all `VERIFIED`; `226G` now the only dependency-unblocked remaining child, next in this session's own explicit range through `226I` |
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

### 1.3 Full-column detail — `READY` row (`229`), plus rows `224`, `225`, and `226A`-`226F` now `VERIFIED`

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
| `atomic_objective` | Extend `ATW-223`'s own `app.gps_devices`/`app.provider_vehicle_mappings` baseline with the one genuine gap a direct re-read found: real, evidenced installation proof (device/SIM/provider/mobile-eligibility mapping identity itself was already fully built at `ATW-223`) |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226B`'s own scope line); verified `app.gps_devices`/`app.device_vehicle_assignments`/`app.vehicle_operational_profiles`/`app.driver_operational_profiles`/`app.provider_vehicle_mappings` (`ATW-223`); Document and File Engine `app.files`/`app.initiate_file_upload`/`app.record_file_scan_result` (`PLT-128`) |
| `allowed_paths` | `supabase/migrations/20260729350000_create_advanced_tms_device_installation_evidence.sql`; `server/contracts/gps-device-installation/gps-device-installation.ts`; `server/queries/gps-device-installation.ts`; `server/mutations/gps-device-installation.ts` (plus their `.test.ts` files); `scripts/db-tests/advanced-tms-device-installation-evidence.sql`; `docs/build-log/phase-05/ATW-226B.md` |
| `forbidden_paths` | Any edit to `ATW-223`'s own already-applied migration; any raw telemetry ingestion path (reserved for later children); any second file-storage mechanism bypassing `PLT-128` -- none touched |
| `migration_ids` | `20260729350000_create_advanced_tms_device_installation_evidence.sql` (1 new additive migration; 102 total) |
| `api_contracts` | Service-layer RPC wrappers only -- 2 new RPCs (`record_gps_device_installation`, `verify_gps_device_installation`) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target |
| `secret_ownership` | none this child (provider API credentials remain `226E`'s own scope -- this child only closes the installation-evidence gap, not provider connection/credential management) |
| `access_controls` | Reuses `app.evaluate_permission`(`OPS`:`Edit`), the same tier `ATW-223`'s own device/status functions already use |
| `transport_invariants` | One installation-evidence row per `app.device_vehicle_assignments` row (unique constraint); evidence is mandatory and clean-scan-validated before the device's own `assigned`->`installed` transition is ever composed; a superseded assignment cannot receive new evidence |
| `tests` | `scripts/db-tests/advanced-tms-device-installation-evidence.sql` (new); `server/contracts\|queries\|mutations/gps-device-installation.test.ts` (13 net new `node:test` cases) |
| `external_evidence_status` | n/a for this child itself |
| `commands` | `pnpm run typecheck`/`lint`/`test`/`db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226B.md`; `node:test` 2286/2286; `db:test` PASS across 102 migrations/104 files; `next build` PASS (81 routes, unchanged) |
| `rollback` | `git revert` the child's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226C` remains dependency-clean `READY`; `226D`/`226E` are now unblocked on their own upstream (`226A`+`226B` both `VERIFIED`) but wait on this session's own ascending in-family order. This session's own explicit range authorization covers `226C` next |

#### Child `226C` — Driver Mobile GPS session and HTTPS ingestion

| Column | Value |
|---|---|
| `atomic_objective` | Implement the authenticated HTTPS session lifecycle (start/heartbeat/location/pause/stop) the Driver PWA uses to report position, bound to a real driver/vehicle/trip/session — the first genuinely real telemetry-producing surface in this repository |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226C`'s own scope line) plus §§14A/16/21–23/26; verified `app.shipment_legs` (`ATW-221`); `app.shipment_leg_tracking_policies`/`sessions` (`ATW-225`, integrated with, not duplicated); `ATW-223`'s own driver consent/eligibility flags; `app.shipment_tracking_tokens`/`app.lookup_public_shipment_tracking` (`OPS-180`, the direct precedent for a token-gated `anon`-callable function) |
| `allowed_paths` | `supabase/migrations/20260729360000_create_advanced_tms_driver_mobile_tracking.sql`; `server/contracts/driver-mobile-tracking/driver-mobile-tracking.ts`; `server/queries/driver-mobile-tracking.ts`; `server/mutations/driver-mobile-tracking.ts` (plus their `.test.ts` files); `app/api/tracking/driver-mobile/route.ts` (the first real HTTP API route this repository builds); `scripts/db-tests/advanced-tms-driver-mobile-tracking.sql`; `docs/build-log/phase-05/ATW-226C.md` |
| `forbidden_paths` | Any Supabase service-role/DB credential placed in the PWA/browser (satisfied -- the route handler holds it server-side only, never the browser); any claim of native-grade background tracking; direct mutation of `app.shipment_leg_tracking_sessions` outside its own already-verified `ATW-225` RPCs (satisfied via the widened `end_leg_tracking_session`, not a bypass) — none touched |
| `migration_ids` | `20260729360000_create_advanced_tms_driver_mobile_tracking.sql` (1 new additive migration; 103 total) |
| `api_contracts` | Service-layer RPC wrappers plus one real HTTPS endpoint (`POST /api/tracking/driver-mobile`) — 4 new RPCs (`start_driver_mobile_session`, `revoke_driver_mobile_session`, `ingest_driver_mobile_report`, `get_driver_mobile_position_reports`) plus 1 widened via drop+recreate (`app.end_leg_tracking_session`, new trailing default-null parameter, every existing 5-argument call site proven unaffected) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target; no separate deployable service required for this child (unlike `226D`'s own always-on gateway) |
| `secret_ownership` | Server-generated session token only; no client-held service credential -- the service-role key stays server-side inside the route handler, never reaches the browser |
| `access_controls` | `start_driver_mobile_session`/`revoke_driver_mobile_session` reuse `app.evaluate_permission`(`OPS`:`Edit`); `ingest_driver_mobile_report` is the one `anon`-granted function in this migration, authorized entirely by its own sha256 token-hash gate plus rate limiting (10 bad attempts/15 min) -- the driver controls only their own assigned mobile session (§26) via token possession, never a portal role |
| `transport_invariants` | A mobile session may only report position while its own bearer token is `active`/unexpired AND the underlying `ATW-225` session is still `is_current`/`active` (real-time consistency -- a dispatcher-side handoff/end immediately invalidates further ingestion); event time and received time are recorded separately (§24); a `stop` report ends the underlying session atomically with recording the report |
| `tests` | `scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` (new); `server/contracts\|queries\|mutations/driver-mobile-tracking.test.ts` (21 net new `node:test` cases) |
| `external_evidence_status` | n/a for this child itself (no hardware/provider dependency — mobile is a first-party HTTPS surface) |
| `commands` | `pnpm run typecheck`/`lint`/`test`/`db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226C.md`; `node:test` 2307/2307; `db:test` PASS across 103 migrations/105 files; `next build` PASS (82 routes, 1 new: `/api/tracking/driver-mobile`) |
| `rollback` | `git revert` the child's own commit; migration is additive only apart from the one drop+recreate, which is itself backward-compatible and proven so directly |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226D`/`226E` are now genuinely dependency-unblocked (`226A`+`226B` both `VERIFIED`); next in this session's own explicit range authorization |

#### Child `226D` — Always-on GPS Gateway and direct-device telemetry ingestion

| Column | Value |
|---|---|
| `atomic_objective` | Implement the raw TCP Teltonika Codec 8 Extended listener (IMEI handshake, AVL packet decode, CRC validation, IO-element mapping, ACK) and its Supabase-side ingestion RPCs, as an always-on, independently-deployed service — the first capability in this repository requiring a standalone deployable unit distinct from the Next.js app |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §14B (`226D`'s own scope line) plus §8 (external-evidence policy); verified `app.gps_devices`/`app.vehicle_tracking_source_priorities` (`ATW-223`); `app.api_keys`/`app.authenticate_api_key`/`app.api_key_has_scope` (`PLT-129`, the direct precedent this child's own header cites as "the real authentication entry point a future API-gateway middleware would call"); `app.geojson_point_to_geography`/`app.validate_geography_point` (`PLT-134`) |
| `allowed_paths` | `supabase/migrations/20260729370000_create_advanced_tms_gps_gateway_ingestion.sql`; `server/contracts/gps-gateway-ingestion/gps-gateway-ingestion.ts`; `server/queries/gps-gateway-ingestion.ts`; `server/mutations/gps-gateway-ingestion.ts` (plus their `.test.ts` files); `scripts/db-tests/advanced-tms-gps-gateway-ingestion.sql`; `services/gps-gateway/**` (its own independent package — `src/`, `test/`, `package.json`, `tsconfig.json`, `Dockerfile`, `README.md`); root `tsconfig.json`/`eslint.config.js` (one additive `exclude`/`ignores` entry each: `services/**`); `docs/build-log/phase-05/ATW-226D.md` |
| `forbidden_paths` | Any edit to `ATW-223`'s own already-applied migration (satisfied — only an additive column); any `anon`/`authenticated` grant on either new RPC (satisfied — `service_role` only, the opposite trust model from `226C`'s own deliberate `anon` exception); `app.jobs` used for live ingestion (satisfied — deliberately not used, see migration header design note 5); `services/gps-gateway` importing from or being imported by the main app's `server/`/`lib/` trees — none touched |
| `migration_ids` | `20260729370000_create_advanced_tms_gps_gateway_ingestion.sql` (1 new additive migration plus one additive column on `app.gps_devices`; 104 total) |
| `api_contracts` | Service-layer RPC wrappers only — 3 new RPCs (`resolve_gps_device_for_handshake`, `ingest_direct_device_telemetry_batch`, `get_direct_device_telemetry_reports`), all `service_role`-only |
| `deployment_target` | **Always-on container/VPS with a static public endpoint and configurable raw TCP ports** (`220_*.md` §6) — explicitly not Vercel/a Supabase Edge Function; hosting-platform selection remains its own deferred ADR candidate (`220_*.md` §6, unchanged by this checkpoint — no live deployment occurred) |
| `secret_ownership` | `services/gps-gateway` itself holds `SUPABASE_SERVICE_ROLE_KEY` plus a scoped (`OPS:Edit`) `app.api_keys` raw value (`GPS_GATEWAY_API_KEY`) — the scoped key is this gateway instance's own independently-revocable credential, defense in depth over the shared `service_role` secret |
| `access_controls` | Both new mutation RPCs require `app.authenticate_api_key` (raises on invalid/revoked/expired) plus `app.api_key_has_scope(..., 'OPS:Edit')` (raises if absent) — no `anon`/`authenticated` grant exists on either |
| `transport_invariants` | IMEI resolved globally (not per-tenant) at handshake time, refusing rather than guessing on an ambiguous multi-tenant match; a device only accepts telemetry while `status` is `installed`/`active`/`offline` (never `stock`/`assigned`/`suspended`/`maintenance`/`retired`); a batch's reports insert atomically — any one structurally invalid report rolls back the whole batch; `installed`/`offline` → `active` only on an actually-accepted batch |
| `tests` | `scripts/db-tests/advanced-tms-gps-gateway-ingestion.sql` (new); `server/contracts\|queries\|mutations/gps-gateway-ingestion.test.ts` (16 net new root `node:test` cases); `services/gps-gateway/test/*.test.ts` (26 cases, this package's own separate gate surface — not counted in root `node:test`) |
| `external_evidence_status` | `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` (WBS §8) — no physical Teltonika hardware/live cellular network available; proven via `services/gps-gateway`'s own deterministic byte-level parser tests and a real `net.Socket` TCP simulator integration test instead, per §8's own allowance |
| `commands` | `pnpm run typecheck`/`lint`/`test`/`db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build`; plus, separately, `(cd services/gps-gateway && pnpm run typecheck && pnpm run test)` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226D.md`; root `node:test` 2323/2323; `services/gps-gateway` `pnpm run test` 26/26; `db:test` PASS across 104 migrations/106 files; `next build` PASS (no new routes) |
| `rollback` | `git revert` the child's own commit; migration is additive only; `services/gps-gateway` was never deployed to any live infrastructure, so there is no running service to roll back |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226E` is now the only other genuinely dependency-unblocked child (`226A`+`226B` both `VERIFIED`); next in this session's own explicit range authorization |

#### Child `226E` — Third-party GPS platform adapter contract

| Column | Value |
|---|---|
| `atomic_objective` | Implement the third-party provider webhook ingestion contract (signature/token validation, schema/version mapping, rate limiting, replay/idempotency, quarantine, provider outage tracking) and at least deterministic sandbox/mock contract tests; live provider activation is conditional (`226_*.md` §16/§8) |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §16 (`226E`'s own scope line) plus §8 (external-evidence policy); verified `app.provider_vehicle_mappings` (`ATW-223`, identity mapping only, provider adapter behavior explicitly deferred to this child by that table's own comment); `app.webhook_endpoints`/`app.compute_webhook_signature`/`app.verify_webhook_signature` (`PLT-129`, ADR-0011 — the direct HMAC-SHA256 signature-scheme precedent, reused verbatim for the inbound direction) |
| `allowed_paths` | `supabase/migrations/20260729380000_create_advanced_tms_third_party_provider_adapter.sql`; `server/contracts/third-party-provider-adapter/third-party-provider-adapter.ts`; `server/queries/third-party-provider-adapter.ts`; `server/mutations/third-party-provider-adapter.ts` (plus their `.test.ts` files); `app/api/webhooks/third-party-gps/[connectionId]/route.ts` (the second real HTTP API route this repository builds, and the first dynamic/parameterized one); `scripts/db-tests/advanced-tms-third-party-provider-adapter.sql`; `docs/build-log/phase-05/ATW-226E.md` |
| `forbidden_paths` | Any edit to `ATW-223`'s own already-applied migration (satisfied — untouched); a universal lowest-common-denominator provider payload parser (satisfied — one disclosed reference contract only, per `226_*.md` §16's own "third-party adapters are case-specific"); a live poll HTTP call to any named vendor without live credentials (satisfied — structurally represented only, never executed) — none touched |
| `migration_ids` | `20260729380000_create_advanced_tms_third_party_provider_adapter.sql` (1 new additive migration; 105 total) |
| `api_contracts` | Service-layer RPC wrappers plus one real HTTPS webhook endpoint (`POST /api/webhooks/third-party-gps/[connectionId]`) — 6 new RPCs (`register_third_party_provider_connection`, `rotate_third_party_provider_webhook_secret`, `update_third_party_provider_poll_cursor`, `compute_third_party_provider_webhook_signature`, `verify_third_party_provider_webhook_signature`, `ingest_third_party_provider_webhook_event`) plus 1 read projection (`get_third_party_telemetry_reports`) |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target; no separate deployable service required (unlike `226D`'s own always-on gateway) |
| `secret_ownership` | `app.third_party_provider_connections.webhook_secret_value` — the raw HMAC signing secret, stored in retrievable form (the identical accepted shape `app.webhook_endpoints.secret_value` already established, `PLT-129`), zero authenticated/anon grant, disclosed to the operator exactly once via `register`/`rotate`'s own return row |
| `access_controls` | `register`/`rotate`/`update_poll_cursor` reuse `app.evaluate_permission`(`OPS`:`Create`/`Edit`); `ingest_third_party_provider_webhook_event` is the one `anon`-granted function in this migration (the third in this repository), authorized entirely by its own HMAC signature verification plus rate limiting (10 bad attempts/15 min) |
| `transport_invariants` | A signature is verified over the exact raw request bytes (never re-serialized JSON) within a 5-minute timestamp-tolerance window (ADR-0011); a replayed `provider_event_id` is idempotent (`duplicate`, never re-inserted); an unmapped `vehicle_id` is quarantined with its raw payload preserved, never dropped; a poll-mode connection's cursor cannot be written by a webhook-mode connection and vice versa |
| `tests` | `scripts/db-tests/advanced-tms-third-party-provider-adapter.sql` (new); `server/contracts\|queries\|mutations/third-party-provider-adapter.test.ts` (20 net new `node:test` cases) |
| `external_evidence_status` | `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` (WBS §8) — no live third-party GPS platform contract exists; the adapter contract, signature validation, mapping, rate-limit, replay, and quarantine behavior are proven with deterministic fixtures per §8's own allowance |
| `commands` | `pnpm run typecheck`/`lint`/`test`/`db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226E.md`; root `node:test` 2343/2343; `db:test` PASS across 105 migrations/107 files; `next build` PASS (1 new route: `/api/webhooks/third-party-gps/[connectionId]`) |
| `rollback` | `git revert` the child's own commit; migration is additive only, no destructive rollback needed |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226F` (canonical telemetry storage, normalization, ordering, and source arbitration) is now the only dependency-unblocked child (`226C`+`226D`+`226E` all `VERIFIED`); next in this session's own explicit range authorization |

#### Child `226F` — Canonical telemetry, dedup/order, current position, history, source arbitration, and conflict/fallback

| Column | Value |
|---|---|
| `atomic_objective` | Implement the single canonical normalization/arbitration service every one of `226C`/`226D`/`226E`'s own raw ingestion RPCs calls -- normalized telemetry events, current position kept separate from high-volume history, deterministic reproducible source arbitration, and hysteresis-gated conflict/fallback |
| `source_ids` | `226_GPS_TELEMATICS_INTEGRATION_PROMPT.md` §20 (`226F`'s own scope line) plus §§13/14/21/24/25; verified `app.tenant_tracking_source_policies` (`ATW-226A`, whose own table comment already named "enforcing it at runtime is ATW-226F's own scope"); `app.vehicle_tracking_source_priorities`/`app.provider_vehicle_mappings` (`ATW-223`, both explicitly deferred live arbitration to this child); `app.resource_assignments` (`OPS-172`) |
| `allowed_paths` | `supabase/migrations/20260729390000_create_advanced_tms_canonical_telemetry_arbitration.sql`; `server/contracts/canonical-telemetry/canonical-telemetry.ts`; `server/queries/canonical-telemetry.ts` (plus their `.test.ts` files); `scripts/db-tests/advanced-tms-canonical-telemetry-arbitration.sql`; two pre-existing db-test files corrected for a pre-existing, unrelated tenant-scoping fragility (`scripts/db-tests/advanced-tms-device-installation-evidence.sql`, `scripts/db-tests/advanced-tms-driver-mobile-tracking.sql` -- see this child's own build log §4.1); `docs/build-log/phase-05/ATW-226F.md` |
| `forbidden_paths` | A fourth trust model/source class beyond `DRIVER_MOBILE`/`DIRECT_DEVICE`/`THIRD_PARTY_PLATFORM` (satisfied -- none invented); a second "position history" table redundant with `app.canonical_telemetry_events` (satisfied); editing any already-applied migration file directly (satisfied -- three ingestion RPCs widened via `CREATE OR REPLACE` inside this new migration only) -- none touched |
| `migration_ids` | `20260729390000_create_advanced_tms_canonical_telemetry_arbitration.sql` (1 new additive migration, 3 functions widened via same-signature `CREATE OR REPLACE`; 106 total) |
| `api_contracts` | 4 new read projections (`get_vehicle_current_position`, `get_vehicle_telemetry_history`, `get_vehicle_source_health`, `get_vehicle_source_switches`) plus 4 new internal `service_role`-only functions (`arbitrate_and_project_vehicle_position` and 3 resolvers) -- no new mutation RPC exposed to any client |
| `deployment_target` | Serverless Web/API (Vercel) — unchanged existing target; no separate deployable service |
| `secret_ownership` | none this child |
| `access_controls` | The 4 read projections are `authenticated`-executable (RLS-scoped tenant reads); every arbitration/resolver internal is `service_role`-only, called exclusively from within the three already-`SECURITY DEFINER` ingestion RPCs |
| `transport_invariants` | Idempotent on `(source_type, source_report_id)`; current position never regresses to an older `event_at` merely because it arrived later; a cross-source switch requires higher priority or current-source staleness, gated by `switch_hysteresis_seconds`; impossible movement (>200 km/h implied speed) is checked per-source, never across two independently-clocked sources; every rejected candidate is still stored with a `rejection_reason`, never dropped |
| `tests` | `scripts/db-tests/advanced-tms-canonical-telemetry-arbitration.sql` (new); `server/contracts\|queries/canonical-telemetry.test.ts` (13 net new `node:test` cases) |
| `external_evidence_status` | n/a for this child itself |
| `commands` | `pnpm run typecheck`/`lint`/`test`/`db:test`; `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths`/`git:check`; `next build` — all re-run fresh, all green |
| `evidence` | `docs/build-log/phase-05/ATW-226F.md`; root `node:test` 2356/2356; `db:test` PASS across 106 migrations/108 files; `next build` PASS (no new routes) |
| `rollback` | `git revert` the child's own commit; migration is additive apart from the three same-signature `CREATE OR REPLACE` widenings, each proven backward-compatible by the existing `226C`/`226D`/`226E` db-tests re-passing unmodified |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` |
| `resume_point` | `ATW-226G` (geofence, milestone, exception, and route-deviation signals) is now the only dependency-unblocked child (`226F` `VERIFIED`); next in this session's own explicit range authorization |

### 1.4 Row `226` decomposition — `ATW-226A`..`ATW-226I` (mandatory per `220_*.md`)

Reproduced from `220_*.md`'s own mandatory table, each child retaining parent prompt `226` (`CG-AABPP-ATW-226`) per `222_*.md` §1's own instruction ("every child must retain this parent prompt ID and receive its own atomic task ID").

| `task_id` | Atomic scope | `upstream` | `status` | `external_evidence_status` |
|---|---|---|---|---|
| `ATW-226A` | Tracking entitlement and source policy | Platform entitlement/config (`PLT-121`, `VERIFIED`); parent-level `ATW-221`/`223`/`225` (all `VERIFIED`) | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226A.md` | n/a |
| `ATW-226B` | Device, SIM, provider, installation, and mapping management | `ATW-223` (`VERIFIED`) | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226B.md` | n/a |
| `ATW-226C` | Driver Mobile GPS session and HTTPS ingestion | `ATW-223`/`225` (both `VERIFIED`) | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226C.md` | n/a |
| `ATW-226D` | Always-on GPS Gateway and Teltonika Codec 8E adapter | `ATW-226A`/`B` | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226D.md` | `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` (WBS §8) |
| `ATW-226E` | Third-party GPS platform adapter contract | `ATW-226A`/`B` | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226E.md` | `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` (WBS §8) |
| `ATW-226F` | Canonical telemetry storage, normalization, ordering, and source arbitration | `ATW-226C`/`D`/`E` | **`VERIFIED`** — `docs/build-log/phase-05/ATW-226F.md` | n/a |
| `ATW-226G` | Geofence, milestone, exception, and route-deviation signals | `ATW-226F` | `NOT_STARTED` — blocked on `ATW-226F` `VERIFIED` | n/a |
| `ATW-226H` | Fleet Control Tower, device administration, and sanitized projections | `ATW-226F`/`G` | `NOT_STARTED` — blocked until both are `VERIFIED` | n/a |
| `ATW-226I` | Deployment, observability, load, security, outage, and recovery verification | `ATW-226A`..`H` | `NOT_STARTED` — blocked until every prior child is `VERIFIED` | Both statuses above re-confirmed at this closing child |

Overall row `226` (`ATW-226`, parent) requires: `ATW-221`, `ATW-223`, `ATW-225`, Platform API/webhook/job/PostGIS/entitlement/secrets controls, and an approved initial Teltonika protocol specification. A live third-party provider contract is optional at this checkpoint (§8 above). `ATW-225` is `VERIFIED`, so the parent-level upstream gate (`ATW-221`, `ATW-223`, `ATW-225`) is fully satisfied. **`ATW-226A` through `ATW-226F` are all now `VERIFIED`** (`docs/build-log/phase-05/ATW-226A.md` through `ATW-226F.md`) — real entitlement/package-limits resolution, a tenant-level default source policy, evidenced device installation, the first real telemetry-producing HTTPS ingestion surface, a real protocol-correct raw TCP Teltonika Codec 8 Extended gateway, a real HMAC-signed third-party provider webhook adapter contract, and now the single canonical normalization/source-arbitration service every raw ingestion path calls, all exist. `226G` (geofence, milestone, exception, and route-deviation signals) is now the only dependency-unblocked child (needs `226F`, `VERIFIED`) and is next in this session's own explicit range authorization. `226H` needs `226F`+`226G`, and `226I` (the closing child) needs every prior child verified.

## 2. Tally

| State | Count |
|---|---|
| `VERIFIED` | 12 (`220`, `221`, `222`, `223`, `224`, `225`, `226A`, `226B`, `226C`, `226D`, `226E`, `226F`) |
| `READY` | 1 (`229`) |
| `NOT_STARTED` | 24 (`227`, `228`, `230`–`248`, and the 3 remaining `226` children `226G`–`226I`) |
| **Total task rows** | **37** |

## 3. Completion statement

This index satisfies `220_*.md`'s "Required execution-index columns" and "mark only dependency-clean tasks `READY`" instructions. `PHASE_5_IN_PROGRESS` is set; `PHASE_5_VERIFIED` remains reserved for Prompt 248 alone. This checkpoint corrects row `226`'s own §1.4 decomposition table: `ATW-226F` (canonical telemetry, dedup/order, current position, history, source arbitration, and conflict/fallback) moves `NOT_STARTED` → **`VERIFIED`** (`docs/build-log/phase-05/ATW-226F.md`) — the single canonical normalization/arbitration service `226_*.md` §14 itself requires every one of `226C`/`226D`/`226E`'s own raw ingestion modes to call, delivered by widening (never forking) all three already-applied ingestion RPCs. `ATW-226A` through `226F` are now all `VERIFIED`. `ATW-226G` (geofence, milestone, exception, and route-deviation signals) is now the only dependency-unblocked child (`226F` `VERIFIED`) and is next in this session's own explicit range authorization "lanjut sd prompt terakhir di 226 (226a-226i)" — a scoped range covering the full `226` family through its closing child, `226I`. Per that authorization, this session proceeds directly to `ATW-226G` next without a further authorization pause.
