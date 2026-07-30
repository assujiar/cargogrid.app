# 00 — Advanced TMS/WMS Work Breakdown Structure

**Prompt:** `CG-S10-ATW-001` (`CG-AABPP-ATW-220` v0.12.0-multisource-gps)
**Runtime output of:** `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/220_ADVANCED_TMS_WMS_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_5_IN_PROGRESS` (kickoff/index only — no Phase 5 domain schema/code exists yet; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Phase 5 tasks from repository evidence already produced by Phase 4's own closure (`docs/build-log/phase-04/FINANCE_CLOSURE_REPORT.md`, `FINANCE_HANDOFF_PACKAGE.md`, `FINANCE_DOWNSTREAM_CONTRACTS.md`) and the Phase 5 package itself (`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/`). It reproduces the capability catalogue and dependency order from `219_ADVANCED_TMS_WMS_README.md` §2–§9 and the individual Prompt `221`–`248` files' own §9 "Upstream dependencies" by reference — the same "one source, not a second copy that could drift" discipline every prior phase kickoff/WBS document in this repository has followed (`00_PHASE0_WBS.md`, `00_PLATFORM_CORE_WBS.md`, `00_COMMERCIAL_WBS.md`, `00_OPERATIONS_WBS.md`, `00_FINANCE_WBS.md`).

## 1. Mandatory hierarchy (`219_*.md` / `220_*.md` mandatory entry gate)

`Phase 5 → Workstream → Epic → Capability → Feature slice → Atomic implementation/verification/hardening/documentation/closure task`.

## 2. Runtime entry gate verification (`220_*.md` mandatory entry gate)

| # | Condition | Verified | Evidence |
|---:|---|---|---|
| 1 | `RUNTIME_DISCOVERY_VERIFIED` | ✔ | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` — unchanged |
| 2 | `RUNTIME_ARCHITECTURE_VERIFIED` | ✔ | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` — unchanged |
| 3 | `PHASE_0_VERIFIED` | ✔ | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| 4 | `PHASE_1_VERIFIED` | ✔ | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| 5 | `PHASE_2_VERIFIED` | ✔ | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` |
| 6 | `PHASE_3_VERIFIED` | ✔ | `docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md` — all 22 rows `VERIFIED` |
| 7 | `PHASE_4_VERIFIED` | ✔ | `docs/build-log/phase-04/FINANCE_CLOSURE_REPORT.md` — all 29 rows `VERIFIED`, set at `CG-S9-FIN-029` |
| 8 | Canonical Job Order/Shipment Order/leg/stop/resource/milestone/exception/ePOD/actual-cost/billing-readiness contracts reconciled | ✔ | §4 below |
| 9 | Supabase/PostgreSQL, PostGIS, Auth, RLS/RBAC, Realtime, jobs, files, API keys, webhooks, feature flags, entitlement foundations reconciled | ✔ | §5 below |
| 10 | Deployment topology (serverless Next.js app + new always-on GPS Gateway) recorded | ✔ | §6 below |
| 11 | Vehicle/driver/device/SIM/provider/trip/customer tracking boundaries scoped | ✔ | §7 below (none exist yet — Phase 5 is greenfield for these) |
| 12 | External-evidence policy (deferred physical hardware / conditional third-party provider) recorded | ✔ | §8 below |

**Result: entry gate PASS.** `PHASE_5_BLOCKED` is not warranted.

## 3. Repository checkpoint at kickoff

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/ulangi-prompt-219-7evdpp` (harness-assigned; tracked to `origin/claude/ulangi-prompt-219-7evdpp`) |
| HEAD at authoring time (pre-commit) | this session's own prior commit re-confirming Prompt 219's read status (2026-07-29), itself built on `origin/main`@`4946b4e` (merge of PR #32) which already fully contains `PHASE_4_VERIFIED` |
| Worktree state | Clean except this document, its sibling `ADVANCED_TMS_WMS_EXECUTION_INDEX.md`, and this checkpoint's own runtime-ledger updates |
| Schema/migration state | 95 migrations applied, unchanged this checkpoint — kickoff performs zero schema change |
| Package manager/runtime | pnpm `10.33.0` + Node `>=22.11.0`; `node:test` unit suite; Playwright E2E; `db:test` (Postgres 16 + PostGIS 3, `scripts/db-tests/run.sh`) |
| Baseline gate results (re-run fresh this checkpoint, before any Phase 5 file is written) | Fresh `pnpm install --frozen-lockfile` (9.8s); `typecheck` PASS (0 errors); `lint` PASS (0 errors, 80 pre-existing `no-html-link-for-pages` warnings unchanged); `node:test` **2165/2165**; `db:test` PASS across 95 migrations/97 db-test files (local sandbox required a fresh `postgresql-16-postgis-3` package install plus starting the local Postgres 16 service and setting its superuser password to match `scripts/db-tests/run.sh`'s own documented default — a one-time sandbox-environment setup step, not a repository change); `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths` all pass; a real `next build` PASS (77 routes, unchanged) |
| Authorization | Explicit user instruction "lanjut prompt 220" ("continue prompt 220") — a single named-task authorization. Per this build's own standing discipline (`OPS-188`/`FIN-029`'s own precedent), this authorizes Prompt 220 only; any Phase 5 capability prompt beyond it requires its own fresh explicit authorization. |

## 4. Canonical Phase 3/4 root reconciliation (`220_*.md` required tasks 3/4)

Phase 5 extends, never re-creates, the following canonical roots:

| Canonical root | Source | Consumed/extended by |
|---|---|---|
| `app.job_orders` (versioned, `revenue_snapshot`/`credit_snapshot` governed jsonb) | `OPS-168`/`OPS-002`, `supabase/migrations/20260727090000_create_operations_job_order.sql` | `ATW-221` (multi-leg shipment references the Job Order, does not fork it) |
| `app.shipment_orders` | `OPS-*`, `supabase/migrations/20260727100000_create_operations_shipment_order.sql` | `ATW-221` (adds ordered legs/stops beneath the existing Shipment Order root) |
| Milestone/exception engine | `OPS-*`, `supabase/migrations/20260727140000_create_operations_milestone_management.sql` | `ATW-225`, `ATW-228` (advanced milestone/exception extends, does not fork, the existing milestone state machine) |
| Actual-cost / billing-readiness handoff | `OPS-178`/`OPS-181` | `ATW-241` (Warehouse Billing hands off compatible events, creates no invoice/AR/AP/journal itself) |
| Finance dashboard/reports, AR/AP, invoice, journal | `FIN-*`, all `VERIFIED` | `ATW-241` consumes the same handoff contract Finance already reads from Operations — no second billing-readiness path is created |
| Platform Configuration Engine, entitlement/feature-flag primitives, RBAC evaluator | `PLT-121`/`PLT-111`/`PLT-112` | `ATW-226A` (tracking entitlement/source policy), `ATW-223` (fleet/driver eligibility) |
| API key/webhook primitives, background job framework | `PLT-129`/`PLT-132` | `ATW-226D`/`ATW-226E` (GPS Gateway ingestion, third-party adapter jobs) |
| PostGIS spatial foundation | `PLT-134`, `supabase/migrations/20260722090000_enable_postgis_spatial_foundation.sql` | `ATW-224` (route/load planning), `ATW-226F` (canonical telemetry geography) |

**Confirmed by direct repository inspection this checkpoint (`grep` across `supabase/migrations/*.sql`):** no `app.vehicles`, `app.drivers`, `app.telemetry*`, or equivalent table exists anywhere in the 95 already-applied migrations. Phase 5 is genuinely greenfield for vehicle/driver/device/SIM/telemetry/warehouse identity — there is no prior root to duplicate, and none of `221`–`248` may invent a second Job Order, Shipment Order, milestone, exception, ePOD, actual-cost, or billing-readiness root.

## 5. Platform/infrastructure foundation reconciliation (`220_*.md` required task 2)

- Supabase/PostgreSQL 16 + PostGIS 3, Auth, Realtime, RLS/RBAC (`app.evaluate_permission`, `has_active_tenant_membership`, `is_supreme_admin`) — all already established and reused, not reinvented, by every Phase 5 capability.
- `app.jobs`/`app.claim_next_job`/`app.heartbeat_job`/`app.complete_job` (`PLT-131`/`PLT-132`) — the existing generic queue is the reuse target for GPS Gateway batch ingestion and third-party adapter polling jobs (`ATW-226D`/`226E`), not a new job table.
- API key/webhook primitives (`PLT-129`) — the reuse target for `ATW-226E`'s third-party push/webhook ingress.
- Feature-flag/entitlement primitives (`PLT-121` config engine) — the reuse target for `ATW-226A`'s `tracking.*` entitlement keys (§4.6 of `219_*.md`).
- No deployed environment exists yet anywhere in this repository (`preflight` fails closed by design; no live Supabase project). This is unchanged by Phase 5 kickoff and is not itself a blocker — every prior phase closed under the identical disclosed condition.

## 6. Deployment ownership (`220_*.md` required task 6)

| Component | Deployment target | Status |
|---|---|---|
| CargoGrid Web/API (Next.js) | Serverless (Vercel — the repository's existing hosting decision, unchanged) | Already the standing target for every prior phase; Phase 5 adds routes/functions to the same deployment, no new decision needed |
| CargoGrid GPS Gateway | Always-on container/VPS with a static public endpoint and configurable raw TCP ports — **explicitly not** a Vercel Function or an ordinary Supabase Edge Function (`219_*.md` §5) | `NOT_STARTED` — no infrastructure exists yet. The exact hosting product (e.g. a always-on container platform or a small dedicated VPS) is deliberately **not selected at this kickoff**; it is `ATW-226D`'s own tool-product decision (a fresh ADR candidate, the same discipline `ADR-CAND-ARCH-024..027` used for CI/CD/secret-manager/observability/hosting at Phase 0), because selecting infrastructure before the adapter contract and secret-ownership model are designed would risk a stale choice |
| Supabase (PostgreSQL/PostGIS/Auth/Realtime/Storage/RPC/jobs) | Managed Supabase project (no live project exists yet, repository-wide, unchanged) | Reused, not re-provisioned, by Phase 5 |

No tenant fork, no unsupported native/offline claim, no false optimality, no autonomous infrastructure commitment — this table records what is already decided (Web/API) and what is explicitly deferred to its own owning task (GPS Gateway), never a silent assumption in either direction.

## 7. Vehicle/driver/device/SIM/provider/trip/customer tracking boundary (`220_*.md` required task 6 continued)

- `ATW-223` owns vehicle/driver/device/SIM identity as **operational assets**, not a duplicate vendor or HR master (`219_*.md` §6) — it must reuse Platform Core's own generic Master Data registry for any party-shaped record the same way `FIN-217` confirmed vendor identity reuses `master_type_code='vendor'`, and build fresh only the genuinely new operational fields (capacity, tracking eligibility, installation lifecycle).
- Trip/telemetry identity is new and canonical to `ATW-226F` — no Phase 3 table already models a "trip" or "position" concept, confirmed by the same greenfield grep in §4.
- Customer-facing projections (`app/(public)/tracking/[token]` already exists as a placeholder route from an earlier prompt-package README read, and the existing Customer Portal deferral pattern) must consume only `ATW-226F`'s sanitized canonical projection — never raw device, raw mobile, or provider payloads, per `219_*.md` §6 and `220_*.md`'s own multi-source planning gates.

## 8. External-evidence policy recorded this checkpoint (`220_*.md` required task 7)

| External dependency | Status assigned | Governing task |
|---|---|---|
| Physical GPS device (Teltonika Codec 8 Extended hardware-in-the-loop) | `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE` — owner: runtime build agent/operator; target device: Teltonika (or protocol-equivalent) GPS tracker; prerequisite: physical unit + SIM + vehicle installation; future test procedure: protocol simulator + recorded vendor frames proving IMEI handshake/CRC/AVL parsing/ACK/replay/reconnect/malformed-payload/buffering/outage-recovery, then a live device retest once hardware is available; safe activation gate: hardware procurement plus a scheduled installation window | `ATW-226D`, re-confirmed at `ATW-226I` and `ATW-248` |
| Live third-party GPS/fleet platform | `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE` — conditional on approved credentials, API access, legal/commercial permission, documented rate limits, and a stable provider contract, none of which exist yet; the adapter contract itself must still be proven with deterministic mocks/contract fixtures | `ATW-226E`, re-confirmed at `ATW-226I` and `ATW-248` |

Both are non-blocking for every repository-controlled gate per `219_*.md` §7 and `220_*.md`'s own external test treatment — no physical-hardware or named-provider evidence is fabricated anywhere in this WBS.

## 9. Capability catalogue and dependency order (reproduced by reference, `219_*.md` §3/§9 files)

See `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` §1 for the full 37-task table (`CG-S10-ATW-001` through the `ATW-226A`..`ATW-226I` decomposition through `CG-S10-ATW-029`/Prompt 248), reproducing each prompt's own §9 "Upstream dependencies" verbatim as the single source of dependency truth.

## 10. Mandatory Prompt 226 decomposition (`220_*.md` required decomposition)

Reproduced verbatim from `220_*.md` itself (no repository evidence argues for a different split):

| Child | Atomic scope | Minimum dependency |
|---|---|---|
| `ATW-226A` | Tracking entitlement and source policy | Platform entitlement/config |
| `ATW-226B` | Device, SIM, provider, installation, and mapping management | `ATW-223` |
| `ATW-226C` | Driver Mobile GPS session and HTTPS ingestion | `ATW-223`/`225` |
| `ATW-226D` | Always-on GPS Gateway and Teltonika Codec 8E adapter | `ATW-226A`/`B` |
| `ATW-226E` | Third-party GPS platform adapter contract | `ATW-226A`/`B` |
| `ATW-226F` | Canonical telemetry storage, normalization, ordering, and source arbitration | `ATW-226C`/`D`/`E` |
| `ATW-226G` | Geofence, milestone, exception, and route-deviation signals | `ATW-226F` |
| `ATW-226H` | Fleet Control Tower, device administration, and sanitized projections | `ATW-226F`/`G` |
| `ATW-226I` | Deployment, observability, load, security, outage, and recovery verification | `ATW-226A`..`H` |

## 11. Two independent starting lanes (this checkpoint's own dependency analysis)

Unlike every strictly linear prior phase (Platform Core/Commercial/Operations/Finance), Phase 5's own dependency graph has **two structurally independent roots**:

- **Transportation lane**: `ATW-221` (Multi-Leg/Multimodal Shipment) depends only on this kickoff plus already-`VERIFIED` Phase 3/4 contracts.
- **Warehouse lane**: `ATW-229` (Warehouse and Zone) depends only on this kickoff plus already-`VERIFIED` Platform master/config/access and PostGIS foundations — it does not depend on `ATW-221` or any transportation capability.

Both converge only at `ATW-238` (WMS Outbound, which needs `ATW-221`'s shipment leg) and fully at `ATW-243` (High-Volume Controls, which needs every `221`–`242` row). Both roots are therefore marked dependency-clean `READY` this checkpoint (§12); which one (or both, sequentially) a future session builds is a scope decision for that session's own explicit authorization, not this kickoff.

## 12. Only dependency-clean tasks marked `READY`

Per `220_*.md`'s own "mark only dependency-clean tasks `READY`" instruction: **`CG-S10-ATW-002` (Prompt 221) and `CG-S10-ATW-010` (Prompt 229) are `READY`.** Every other row remains `NOT_STARTED` (dependency-correct but not yet unblocked) until its own upstream row is `VERIFIED`. No row is marked `READY` merely because its ordinal position in the prompt package is early — `ATW-222` (Prompt 222), for example, is *not* marked `READY` at this checkpoint even though it may later be implemented before `ATW-226` completes (its own §9 allows partial, feature-gated implementation) — it still requires `ATW-221` `VERIFIED` first per its own stated dependency.

## 13. Atomic sizing

Every row is sized as in every prior phase's own WBS: the `READY` rows (`221`, `229`) target one additive migration plus 5–20 changed files matching the verified repository boundary every Commercial/Operations/Finance capability already used; `ATW-226`'s nine children are each independently sized smaller, per `220_*.md`'s own mandate, precisely because a single migration/deployment/rollback boundary spanning driver-mobile, physical-gateway, third-party-adapter, and canonical-arbitration concerns at once would not be reviewable. `222`–`248` (excluding `221`/`229`) remain `NOT_STARTED`/dependency-pending and are not instantiated with exact file paths yet — the same discipline `00_FINANCE_WBS.md` §8 and `00_OPERATIONS_WBS.md` applied to their own not-yet-authorized rows, since instantiating exact paths before a row's own upstream is `VERIFIED` risks stale paths.

## 14. Safe concurrency lanes and post-kickoff baseline re-check

Single session, single branch (`claude/ulangi-prompt-219-7evdpp`) — no parallel lane is opened this checkpoint, matching every prior phase's own one-agent-one-branch discipline, even though §11 identifies two independent dependency lanes; opening a second concurrent session/branch to build both lanes in parallel is a decision for the operator to make explicitly (per `docs/git/GIT_STRATEGY.md` §7's own single-writer discipline, `ISS-2026-002`), not something this kickoff authorizes on its own. `pnpm run test` was re-run immediately after this checkpoint's own commit and remains **2165/2165** (unchanged — docs-only task, zero service-layer code).

## 15. Completion statement

This document plus `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` satisfy `220_*.md`'s required output. `PHASE_5_IN_PROGRESS` is set this checkpoint (not `PHASE_5_VERIFIED` — only Prompt 248 may set that). `CG-S10-ATW-002` (Prompt 221, Multi-Leg and Multimodal Shipment) and `CG-S10-ATW-010` (Prompt 229, Warehouse and Zone) are the two next eligible tasks, both dependency-clean `READY`. Neither is authorized by this checkpoint's own "lanjut prompt 220" instruction — a fresh explicit user authorization naming one or both is required before either begins, per this build's own standing discipline (`OPS-188`/`CG-S9-FIN-029`'s own precedent: closing a kickoff does not itself authorize starting the first capability task).
