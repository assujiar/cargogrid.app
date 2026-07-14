# Prompt 134 — PostGIS and Spatial Foundation

**Prompt ID:** `CG-S6-PLT-031`  
**Package document:** `CG-AABPP-PLT-134`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-134.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-031` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Data Platform; Epic: Geospatial Primitives; Capability: PostGIS spatial foundation; Feature slice: Extension, geometry/geography conventions and tenant-safe helpers; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement PostGIS from Platform Core with governed spatial types, SRID, validation, indexing, query and test conventions.

## 5. Business value

Prepare accurate scalable location/route/geofence foundations for TMS/WMS without premature domain implementation.

## 6. Source requirement

RPD PostGIS from Platform Core; technical spatial architecture; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

PostGIS extension/spatial primitive migrations/helpers/types/tests/docs and isolated example. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

TMS routing/geofence features, live map provider integration, broad coordinate backfill. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Enable verified PostGIS extension safely; spatial reference/master primitives, SRID constraints, GiST indexes and tenant-aware helpers.

## 14. API impact

Typed GeoJSON/coordinate validation/serialization conventions; no routing domain endpoint.

## 15. UI/UX impact

No map feature; define safe coordinate display/input primitives only if architecture requires.

## 16. Security impact

Tenant-scope spatial records, precision/privacy classification, bounded queries and injection-safe functions.

## 17. Performance impact

GiST/selectivity/query-plan evidence, bounding/radius limits and no unbounded global spatial scan.

## 18. Audit impact

Spatial master/config/change and privileged bulk operations where applicable.

## 19. Data migration impact

Extension/migration applies cleanly fresh/upgrade; map existing coordinates explicitly without silent axis swap.

## 20. Detailed implementation tasks

1. Verify PostGIS availability/version and approve SRID/geography/geometry conventions via ADR if needed.
2. Implement extension migration, spatial primitive/master schema/helpers/constraints/indexes.
3. Implement validation/serialization/query-limit contract and representative non-domain example.
4. Add axis/SRID/invalid geometry/cross-tenant/query plan/migration/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized tenant stores/queries valid spatial primitive with correct SRID/index.

## 22. Alternative flow

Optional coordinate absent or transformed from explicitly supported input safely.

## 23. Exception flow

Invalid range/axis/SRID/geometry, cross-tenant or unbounded radius/query is rejected.

## 24. Business rules

- Canonical coordinate order/SRID units documented and stable.
- Platform foundation does not implement route/load/fleet domain capability.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Fresh/upgrade extension, SRID/range/geometry validity/index use deterministic.
- GeoJSON serialization round-trips within tolerance.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Spatial rows/helpers respect tenant/RLS/field classification; sensitive locations masked by policy.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, equator/antimeridian/boundary/invalid coordinates, large sample and mixed legacy inputs. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Migration/extension/SRID/range/geometry/index/roundtrip tests.
- RLS/cross-tenant/bounded radius/query-plan/performance/privacy tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Clean DB rebuild, master data, API types and backups.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-134.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- PostGIS foundation is available, safe, indexed and convention-governed.
- No domain creep/axis error/global scan; migration/tests/docs pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

