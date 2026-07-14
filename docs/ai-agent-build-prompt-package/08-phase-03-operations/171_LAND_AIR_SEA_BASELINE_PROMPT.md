# Prompt 171 — Land, Air and Sea Baseline

**Prompt ID:** `CG-S8-OPS-005`  
**Package document:** `CG-AABPP-OPS-171`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-171.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-005` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Shipment Execution; Epic: Mode Baseline; Capability: Single-mode single-leg land, air and sea execution; Feature slice: Shipment mode profile→required references/schedule→baseline validation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement bounded single-mode/single-leg land, air and sea shipment profiles and validation without advanced planning.

## 5. Business value

Support the three baseline logistics modes while preserving one canonical shipment model.

## 6. Source requirement

OPS-TMS-001..004 basic Phase 3 slice; shipment dictionary; Brief TMS modes; Phase 3/5 split. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-169..170; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-172..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Shipment Execution schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend mode profile fields and constrained references: land vehicle/vendor/route basics; air AWB/flight/airport basics; sea BL/booking/vessel/port/container basics, all linked to one Shipment Order.

## 14. API impact

Provide shared REST/GraphQL mode-profile create/update/validate/read operations and typed mode-specific projections over one canonical service.

## 15. UI/UX impact

Build accessible conditional mode sections with relevant references, dates and validation while hiding—not deleting—irrelevant fields.

## 16. Security impact

Apply mode/service/customer/branch scopes and protect carrier/vendor references/documents; validation errors must not expose inaccessible masters. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/mode/service/origin/destination/schedule/references; bound master lookups and use server search/pagination.

## 18. Audit impact

Record mode selection/change, mode-specific references/schedule, validation version and any approved change after confirmation.

## 19. Data migration impact

Map legacy mode fields to typed profiles; preserve unsupported/mixed modes for Step 10 reconciliation rather than coercing them.

## 20. Detailed implementation tasks

1. Define common shipment core and land/air/sea baseline profile boundaries.
2. Implement typed mode fields, constraints and published validation rules.
3. Implement mode change policy and source/reference checks.
4. Build conditional mode UI and shared API contracts.
5. Verify no advanced-scope leakage, access, data mapping, performance and lifecycle integration.

## 21. Main flow

User selects one baseline mode, supplies valid mode-specific references/schedule and confirms the shipment profile.

## 22. Alternative flow

Eligible draft changes mode and explicitly reconciles/removes incompatible values before reconfirmation.

## 23. Exception flow

Mixed/multiple mode, missing required carrier/location/reference, incompatible service or confirmed-mode change blocks safely.

## 24. Business rules

- Phase 3 shipment has one mode and one leg.
- Multi-leg, multimodal, multi-pick/drop, consolidation, route/load optimization and GPS/telematics remain Step 10.
- Common canonical shipment identity/lifecycle is not forked by mode.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Land validates basic pickup/delivery/vehicle/vendor references; air validates airport/flight/AWB basics; sea validates port/booking/BL/container basics as configured.
- Validate schedule order, location compatibility and required documents.
- Unsupported modes remain explicit future scope, never silently mapped.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Operations sees authorized mode data; customer/public views receive only safe references/status; vendor/carrier details follow field policy. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Valid/invalid land, air and sea profiles, mode change, missing references, unsupported multimodal/multi-leg, restricted carriers and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Mode discriminator/constraint/reference/schedule/migration tests.
- RLS/RBAC/field/record/API parity/audit tests.
- Conditional form/detail E2E, accessibility, server lookup performance and advanced-scope regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Shipment Order/lifecycle, locations/PostGIS, documents, assignment, tracking and Step 10 compatibility. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-171.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Land, air and sea profiles are valid on one canonical model.
- Unsupported advanced scenarios are blocked and clearly deferred.
- Mode UI/API/database semantics remain consistent and accessible.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-006` / `OPS-172` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

