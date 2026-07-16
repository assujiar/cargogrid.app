# 00 — Platform Core Work Breakdown Structure

**Prompt:** `CG-S6-PLT-001` (`CG-AABPP-PLT-104` v0.7.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/06-phase-01-platform-core/104_PLATFORM_CORE_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_1_IN_PROGRESS` (kickoff/index only — no capability task `105`–`140` has executed; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Platform Core tasks from repository evidence already produced in Step 3 (`docs/architecture/`) and Step 5 (Phase 0 closure), per Prompt 104 §"Required tasks" 1–7. It does not re-derive the capability catalogue or dependency order — both are reproduced by reference from `103_PLATFORM_CORE_README.md` §4 (itself a direct reproduction of `01_MODULE_DEPENDENCY_MAP.md` §3.1, per `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` line 88) — the same "one source, not a second copy that could drift" discipline every prior Phase 0 kickoff/WBS document in this repository has followed. No runtime source, schema, config, or data file is created or changed by this document.

## 1. Mandatory hierarchy (`103_*.md` §3)

`Phase 1 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Every one of the 32 capability prompts (`105`–`136`) and the 4 closing prompts (`137`–`140`) fills exactly one hierarchy row below. No level is skipped; no level is invented beyond what `103_*.md` §3 already fixes.

## 2. Workstream / Epic grouping (reconciled against `01_MODULE_DEPENDENCY_MAP.md` §2.1's 18 platform primitives)

| Workstream | Epic | Platform primitive(s) | Capability prompts | Owner |
|---|---|---|---|---|
| Identity and Tenancy | Tenant lifecycle, entitlement, auth, org/user, RBAC/RLS, field access, support access, audit | `TEN-IAM`, `AUD` | `105`–`116` (12) | Architecture/Security |
| White-Label and Localization | Brand config, custom domain, localization | `WLB` | `117`–`119` (3) | Product/Architecture |
| Data and Configuration Foundation | Master data, configuration engine | `MDM`, `CFG` | `120`–`121` (2) | Data/Architecture |
| Governed Engines | Workflow, approval, status, numbering, forms | `WF`, `APPR`, `STAT`, `NUM`, `FORM` | `122`–`126` (5) | Architecture |
| Communication and Content | Notifications, documents/files | `NOTIF`, `DOC` | `127`–`128` (2) | Architecture/Security |
| API and Jobs | API keys/webhooks, REST/GraphQL foundation, import/export, background jobs | `API-WH`, `IMPEXP`, `JOB` | `129`–`132` (4) | Architecture |
| Progressive Delivery and Spatial | Feature flags, PostGIS | `FLAG`, `GEO` | `133`–`134` (2) | Architecture/Data |
| Administration | Tenant Admin, Supreme Admin portals | `PORTAL-ADM` | `135`–`136` (2) | Architecture |
| Phase Closing | Integrated verification, hardening, documentation, closure | — (cross-cutting) | `137`–`140` (4) | Runtime build agent |

**Total: 32 capability prompts + 4 closing prompts = 36, plus this kickoff prompt (`104`) = 37 rows**, matching `00_PLATFORM_CORE_EXECUTION_INDEX.md` exactly.

## 3. Capability coverage — all 32 mandatory Platform Core capabilities

Every row below cites its `Prompt ID` (`CG-S6-PLT-NNN`), owning primitive, and real, sourced allowed-scope/DB-impact summary extracted directly from that capability's own prompt file (`103_PLATFORM_CORE_README.md` §4's dependency column reproduced verbatim, not re-derived):

| # | Prompt | Task ID | Capability | Primitive | Primary dependencies | Allowed scope (from prompt §11) | DB impact (from prompt §13) |
|---:|---|---|---|---|---|---|---|
| 1 | `105` | `CG-S6-PLT-002` | Tenant provisioning and lifecycle | `TEN-IAM` | `104` | Tenant control-plane schema/migrations/service/tests/docs | Tenant/control-plane entities, stable IDs, unique constraints, state/version/effective dates, bootstrap transaction |
| 2 | `106` | `CG-S6-PLT-003` | Subscription/module/feature entitlement | `TEN-IAM` | `105` | Entitlement schema/migrations/service/guards/tests/docs | Versioned entitlement/package/tenant assignment/limit records |
| 3 | `107` | `CG-S6-PLT-004` | Supabase Auth integration | `TEN-IAM` | `104`–`106` | Auth client/server/middleware/schema-link/tests/docs | Link auth identities to platform user/membership records |
| 4 | `108` | `CG-S6-PLT-005` | Four-layer identity/access context | `TEN-IAM` | `105`–`107` | Principal/membership schema/migrations/resolver/guards/tests/docs | Memberships/principal types/context references |
| 5 | `109` | `CG-S6-PLT-006` | Organization hierarchy | `TEN-IAM` | `105`,`108` | Org hierarchy schema/migrations/service/API/tests/docs | Tenant-scoped hierarchy nodes/edges, cycle prevention |
| 6 | `110` | `CG-S6-PLT-007` | User lifecycle | `TEN-IAM` | `107`–`109` | User/membership/invitation schema/migrations/service/contracts/tests/docs | User profile, memberships, invitations, uniqueness constraints |
| 7 | `111` | `CG-S6-PLT-008` | Role and permission builder | `TEN-IAM` | `108`–`110` | Permission catalogue/role schema/migrations/service/contracts/tests/docs | Canonical permissions, tenant roles/versions, bindings |
| 8 | `112` | `CG-S6-PLT-009` | RBAC enforcement | `TEN-IAM` | `111` | RBAC evaluator/guards/cache/schema integration/tests/docs | Indexed assignment/scope evaluation; no RLS replacement |
| 9 | `113` | `CG-S6-PLT-010` | RLS tenant policy foundation | `TEN-IAM` | `105`,`108`,`112` | Approved RLS helper/policy migrations/grants/tests/docs | Enable/retain RLS, tenant-aware keys/FKs/indexes, explicit policies |
| 10 | `114` | `CG-S6-PLT-011` | Field-level and record-level access | `TEN-IAM` | `112`–`113` | Fine-grained policy schema/migrations/evaluator/projections/tests/docs | Policy/conditions/ownership/sharing via RLS/views/functions |
| 11 | `115` | `CG-S6-PLT-012` | Support access and impersonation | `TEN-IAM` | `107`,`112`–`114` | Support grant/session schema/migrations/service/context/banner/tests/docs/runbook | Grants/sessions/reason/expiry/scope/revocation, immutable events |
| 12 | `116` | `CG-S6-PLT-013` | Audit trail foundation | `AUD` | `105`,`107`–`115` | Audit schema/migrations/service/instrumentation/query/tests/docs | Tenant-aware audit events, retention/legal hold, RLS |
| 13 | `117` | `CG-S6-PLT-014` | White-label foundation | `WLB` | `105`–`106`,`116` | Brand config schema/migrations/evaluator/shared theme/assets/tests/docs | Versioned brand config, draft/publish/effective date/rollback |
| 14 | `118` | `CG-S6-PLT-015` | Custom domain | `WLB` | `107`,`117` | Custom-domain schema/migrations/service/resolver/cache/tests/docs/runbook | Domain records, verification challenge/status, audit |
| 15 | `119` | `CG-S6-PLT-016` | Localization | `WLB` | `117` | Localization catalogues/resolver/config/schema/tests/docs | Versioned locale/terminology config with effective dates |
| 16 | `120` | `CG-S6-PLT-017` | Master data foundation | `MDM` | `105`,`109`,`113`–`116` | Master registry/schema/migrations/service/contracts/tests/docs | Master entities, global/tenant scope, stable codes, RLS/indexes |
| 17 | `121` | `CG-S6-PLT-018` | Configuration engine | `CFG` | `105`,`109`,`112`–`116`,`120` | Config schema/migrations/service/evaluator/cache/contracts/tests/docs | Definitions/versions/values/scopes/effective dates/snapshots |
| 18 | `122` | `CG-S6-PLT-019` | Workflow engine | `WF` | `121` | Workflow schema/migrations/service/contracts/tests/docs | Definitions/versions/states/transitions/instances/history |
| 19 | `123` | `CG-S6-PLT-020` | Approval engine | `APPR` | `111`–`116`,`122` | Approval schema/migrations/service/contracts/tests/docs | Definitions/requests/steps/decisions/delegations/SLA |
| 20 | `124` | `CG-S6-PLT-021` | Status engine | `STAT` | `121`–`123` | Status registry/schema/migrations/resolver/UI metadata/tests/docs | Canonical status/sets/mappings/effective versions/history |
| 21 | `125` | `CG-S6-PLT-022` | Numbering engine | `NUM` | `105`,`109`,`121`,`124` | Numbering schema/migrations/service/contracts/tests/docs | Number definitions/versions/counters, atomic locking |
| 22 | `126` | `CG-S6-PLT-023` | Form and custom-field builder | `FORM` | `112`–`114`,`121`,`124` | Form/custom-field schema/migrations/service/renderer/tests/docs | Definition/version/layout/field storage strategy |
| 23 | `127` | `CG-S6-PLT-024` | Notification engine | `NOTIF` | `107`,`121`–`124` | Notification/template/delivery schema/migrations/service/queue/in-app UI/tests/docs | Notification/template/preference/delivery/attempt records |
| 24 | `128` | `CG-S6-PLT-025` | Document/file engine | `DOC` | `113`–`116`,`121`,`127` | Document/file metadata schema/migrations/service/storage/scan adapter/upload UI/tests/docs/runbook | File metadata, classification, scan result, retention/legal hold |
| 25 | `129` | `CG-S6-PLT-026` | API key and webhook primitives | `API-WH` | `107`,`112`–`116`,`127` | API key/webhook schema/migrations/service/auth/delivery/tests/docs/runbook | Hashed key metadata, webhook events/deliveries/attempts |
| 26 | `130` | `CG-S6-PLT-027` | REST/GraphQL platform API foundation | `API-WH` | `112`–`116`,`120`–`129` | Shared API middleware/schema/context/errors/pagination/server/tests/docs | No direct DB bypass; shared service/repository with RLS |
| 27 | `131` | `CG-S6-PLT-028` | Import/export job framework | `IMPEXP` | `113`–`116`,`120`,`128`,`130` | Import/export framework schema/migrations/service/adapters/job/file/UI primitives/tests/docs | Batch/staging/row-error/checkpoint records with retention |
| 28 | `132` | `CG-S6-PLT-029` | Background job framework | `JOB` | `113`,`116`,`121`,`127`–`131` | Job queue schema/migrations/service/worker/contracts/tests/docs/runbook | Job/type/payload/state/attempt/lease/DLQ tables, atomic claim |
| 29 | `133` | `CG-S6-PLT-030` | Feature flags | `FLAG` | `106`,`112`,`116`,`121`,`132` | Feature-flag schema/migrations/service/evaluator/admin slice/tests/docs | Versioned flag definitions/targets/kill state — **first real persistence for the Phase 0 `scripts/feature-flags/flags.ts` evaluation engine, not a rewrite of it** |
| 30 | `134` | `CG-S6-PLT-031` | PostGIS/spatial foundation | `GEO` | `105`,`109`,`113`,`116`,`120` | PostGIS extension/spatial primitive migrations/helpers/types/tests/docs | Enable verified PostGIS extension; SRID constraints, GiST indexes |
| 31 | `135` | `CG-S6-PLT-032` | Tenant Admin portal | `PORTAL-ADM` | `106`–`134` required subset | Portal shell/routes/components/tests/docs and bounded workflow adapters | No direct client DB; approved services/RLS only |
| 32 | `136` | `CG-S6-PLT-033` | Supreme Admin portal | `PORTAL-ADM` | `105`–`135` required subset | Supreme portal shell/routes/components/privileged adapters/tests/docs | No direct client DB; privileged services still audited |

**Schema ownership** (reconciled against `05_DATABASE_SCHEMA_WORKSTREAM.md` §1/§3, resolved `ADR-CAND-ARCH-007`): every capability above adds tables to the single flat `app` schema — no per-domain/per-capability schema is created. `report` (materialized views/reporting) is the one deliberate second schema, not touched by any Platform Core capability except as a future consumer.

**API/UI boundary** (reconciled against `04_REPOSITORY_TARGET_STRUCTURE.md` §8 row 2 and §5): allowed paths for the whole phase are `app/(public)`, `app/(supreme)`, `app/(tenant)/[tenantSlug]/admin`, `lib/**`, `server/{queries,mutations,actions}/` (platform-only files), `server/policies/`, `server/jobs/`, `components/ui/`, `supabase/migrations/` (first tenant/IAM migrations) — no business-domain folder (`app/(tenant)/[tenantSlug]/commercial` etc.) is created in Phase 1, matching `01_*.md` Phase 1 scope exactly.

**`server/contracts/` folder-existence timing** (a real, still-open item `04_REPOSITORY_TARGET_STRUCTURE.md` §11 names and explicitly assigns to "Prompt 40/Platform Core kickoff (Prompt 104)" — i.e. this checkpoint): that document's own analysis (§11, `ADR-CAND-ARCH-010` in its local numbering — distinct from the differently-topiced, already-resolved `ADR-CAND-ARCH-010` "Configuration-engine sub-engine decomposition" in the master 27-item register at `docs/adr/README.md` §5.1, a pre-existing local/master numbering divergence in the Step 3 architecture documents, disclosed here rather than silently conflated) already reasons through both options and finds "no reason to deviate" from creating `server/contracts/` as a first-class folder from Phase 1, since `01_*.md` §11's no-cross-domain-import rule implies contracts must exist before Phase 2 needs one. **This checkpoint adopts that already-fully-reasoned recommendation as the binding Platform Core convention** (this checkpoint's own construction, adopting — not re-deriving — `04_*.md` §11's analysis; a folder-existence-timing convention, not a product/architecture decision, so a full ADR ceremony is not warranted): every capability whose contract has a downstream consumer inside Platform Core itself (chiefly `129`/`130`'s API foundation and any engine `121`–`128` a portal in `135`/`136` calls) creates its type/validator under `server/contracts/<owning-primitive>/` from its own first capability prompt, not retrofitted later.

**No oversized profile found** (§20 task 3): `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §5.2 already spot-verified all 32 Platform Core capabilities against Template 53 §11's sizing rule (normally 5–15 files, 1–3 migrations, one module boundary) as its own worked example and found zero oversized task — each of the 32 capabilities maps to exactly one of `01_*.md` §2.1's 18 named primitives (`TEN-IAM` is pre-split across 12 sequential prompts, `105`–`116`, precisely because that primitive alone would otherwise be oversized for one prompt). This checkpoint's own reconciliation (this table) confirms that finding still holds against the live prompt files — no capability profile here exceeds the sizing rule, so no further splitting is required.

## 4. Verification / hardening / documentation / closure tasks

| Prompt | Task ID | Purpose | Dependency | Output |
|---|---|---|---|---|
| `137` | `CG-S6-PLT-034` | Integrated Platform Core verification | `105`–`136` | `docs/build-log/phase-01/PLT-137.md` — verification tests/scripts/fixtures/logs/docs only, default no repair |
| `138` | `CG-S6-PLT-035` | Tenant/security/platform hardening | `137` | `docs/build-log/phase-01/PLT-138.md` — exact finding-linked repair, consumes `137`'s failure matrix |
| `139` | `CG-S6-PLT-036` | Documentation and handoff | `138` | `docs/build-log/phase-01/PLT-139.md` — Phase 2 entry package, analogous to `docs/build-log/phase-00/PHASE0_HANDOFF_PACKAGE.md` |
| `140` | `CG-S6-PLT-037` | Phase 1 closure verification | `139` | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` — only this prompt may set `PHASE_1_VERIFIED` |

This is the identical 4-prompt closing pattern Phase 0 already proved out at `99`–`102` (`docs/build-log/phase-00/PH0-99.md`–`PHASE0_CLOSURE_REPORT.md`) — reused, not reinvented.

## 5. Atomic sizing

Every capability row in §3 stays within Template 53 §11's rule (normally 5–15 files, 1–3 migrations, one module boundary) per `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §5.2's own spot-verification, re-confirmed against the live prompt files this checkpoint (§3's "No oversized profile found" note). No child-task split was required.

## 6. Safe concurrency lanes (required task 5)

Platform Core's dependency chain (`103_*.md` §4) is far more densely interconnected than Phase 0's — most capabilities from `113` onward depend on 3–7 upstream capabilities each, not a single predecessor. This checkpoint identifies concurrency opportunities honestly rather than defaulting either to "fully sequential" (wastes real independence) or "everything parallel" (ignores real dependency density):

| Lane | Capabilities | Rationale |
|---|---|---|
| Lane A (strictly sequential, no parallelism possible) | `105`→`106`→`107`→`108`→`109`→`110`→`111`→`112`→`113`→`114`→`115`→`116` | Each of `TEN-IAM`'s 12 capabilities is a direct, named prerequisite of the next per `103_*.md` §4 — no two of these have independent dependency sets |
| Lane B (parallel to each other, both depend only on Lane A's `116`-and-earlier subset) | `117`→`118`→`119` (White-Label chain) | `120` (Master Data) | `117`/`120` share no file/schema/contract — `117` touches brand-config tables, `120` touches master-registry tables; genuinely independent once `116` is `VERIFIED` |
| Lane C (sequential within itself, starts once `120` is `VERIFIED`) | `121`→`122`→`123`→`124`→`125`→`126` | The 6 governed engines form their own dependency chain (`124` needs `121`–`123`; `125` needs `121`,`124`; `126` needs `112`–`114`,`121`,`124`) — no safe parallel split within this chain without violating a named dependency |
| Lane D (parallel to Lane C's tail, starts once `121`+`127`'s own prerequisites are `VERIFIED`) | `127` (Notification) | `128` (Document/File, needs `121`+`127`) — sequential within itself, but independent of Lane C's `122`–`126` since neither `127` nor `128` is a named dependency of the workflow/approval/status/numbering/form chain |
| Lane E (sequential, depends on both C and D tails) | `129`→`130`→`131`→`132`→`133` | Each explicitly depends on the prior in this sub-chain plus earlier lanes (`103_*.md` §4) |
| Lane F (parallel to Lane E, independent schema/files) | `134` (PostGIS) | Depends only on `105`,`109`,`113`,`116`,`120` — all already `VERIFIED` by the time Lane C starts; genuinely independent of every engine/API/job capability |
| Lane G (sequential, last — needs "required subset" of nearly everything) | `135`→`136` | Portals are the one place `103_*.md` §4 names a "required subset" rather than an exact ID list — this checkpoint does not resolve exactly which subset until `135`'s own kickoff reconciles it against what actually shipped, per §8 below |

**Collision check (schema/contract/file/flag/test):** no two lanes write the same table, the same `server/contracts/<primitive>/` file, or the same test path — verified by cross-referencing §3's DB-impact column pairwise across every lane boundary. `FLAG` (`133`, Lane E) is the one capability that gives the Phase 0 `scripts/feature-flags/flags.ts` module its first real persistence table — no other capability writes to that table, so no collision with Phase 0's foundation code exists either.

**This session's own operating model remains single-lane sequential** (one branch, one writer, per `ISS-2026-002`'s resolution) — the lanes above describe where *safe* parallelism exists for a future multi-agent run, not an instruction to actually parallelize this session's own execution.

## 7. Integration checkpoints

| Checkpoint | After | Verifies |
|---|---|---|
| IC-1 | `116` (`AUD`) | All of `TEN-IAM` + audit foundation composes: a tenant can be provisioned, a user authenticated, a role assigned, RLS/RBAC/field-access enforced, and every one of those actions audited — the identical "cross-foundation, not just isolated" discipline `scripts/verification/phase0-integration.test.ts` already proved for Phase 0 |
| IC-2 | `126` (`FORM`) | Configuration → Workflow → Approval → Status → Numbering → Forms compose as one governed-engine pipeline, no tenant-specific hardcoded logic anywhere in the chain |
| IC-3 | `133` (`FLAG`) | API/Job/Flag capabilities compose: a webhook delivery can be queued as a background job, retried, and gated by a real (now-persisted) feature flag |
| IC-4 | `136` (`PORTAL-ADM`) | Both portals correctly compose every primitive below them with no direct-client-DB violation (`04_*.md` §5's enforcement rule) |
| IC-5 (= Prompt `137`) | `136` | Full Platform Core integrated verification — the phase-level equivalent of Phase 0's `PH0-99.md` |

## 8. Stale-evidence triggers

Re-verify this WBS's dependency table against `103_PLATFORM_CORE_README.md` §4 if any of: (1) a capability prompt file `105`–`140` is edited after this checkpoint; (2) a new `ADR-CAND-ARCH-*` decision changes schema ownership or the `server/contracts/` timing convention adopted in §3; (3) `135`/`136`'s "required subset" is resolved with a different capability list than "everything below it," per §6 Lane G's own disclosed open question; (4) more than 5 capability prompts complete without an intervening re-read of this document (mirrors `00_PHASE0_WBS.md` §8's own trigger cadence).

## 9. Recovery order

If a capability task fails partway: (1) do not proceed to its dependents; (2) `git revert` the failed task's own commit(s) per `04_REPOSITORY_TARGET_STRUCTURE.md` §8 row 2's rollback column; (3) record the failure in `docs/runtime/ERROR_LEDGER.md`, update this WBS's affected row(s) to `BLOCKED`, and generate a bounded resume prompt — never restart the phase blindly (same discipline every closing-prompt template in this package already states).

## 10. Cycle/orphan/duplicate checks (required task 5)

**Cycles:** none — `103_*.md` §4's dependency table is a strict DAG (every dependency ID is numerically lower than its dependent), re-verified this checkpoint by confirming no row cites a later-numbered prompt as its own dependency.

**Orphans:** none — every one of the 18 primitives in `01_MODULE_DEPENDENCY_MAP.md` §2.1 maps to at least one capability prompt in §3 above; every capability prompt maps to exactly one primitive; the 4 closing prompts are cross-cutting by design, not orphaned.

**Duplicates:** none — `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §11's already-verified finding ("no capability prompt ID appears in more than one phase's range") is re-confirmed at the intra-phase level here: no two of the 32 capability rows in §3 claim the same table, contract file, or test path (§6's collision check).

## 11. Completion statement

All 32 mandatory Platform Core capabilities plus verification/hardening/documentation/closure are represented in the hierarchy (§1–§4). Every dependency has explicit ownership (§3's "Primary dependencies" column, sourced from `103_*.md` §4). No cycle, orphan, or unowned collision was found (§10). `PLT-105` (Tenant provisioning and lifecycle) can be instantiated from this document plus its own prompt file `105_TENANT_PROVISIONING_LIFECYCLE_PROMPT.md` — see `00_PLATFORM_CORE_EXECUTION_INDEX.md` row `002` for its `READY` determination.
