# Prompt 177 — ePOD Capture and Review

**Prompt ID:** `CG-S8-OPS-011`  
**Package document:** `CG-AABPP-OPS-177`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-177.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-011` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Delivery Evidence; Epic: Proof of Delivery; Capability: Online-first ePOD photo, signature, receiver, geo and timestamp; Feature slice: Delivered shipment→capture→scan/review→complete/revise; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement secure online-first ePOD capture, review, revision and completion linked to the exact shipment/delivery event.

## 5. Business value

Create trusted delivery evidence that can unlock customer visibility and billing readiness.

## 6. Source requirement

OPS-DOC-001..004 basic Phase 3 slice; OPS-POD-001 UX; RPD-004/015/032; UAT-E2E-014. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-170, OPS-173..176; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-178..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Delivery Evidence schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend ePOD root/version/status, shipment/milestone/drop reference, receiver name/position, signature/photo file refs, PostGIS geolocation, captured/server times, review/revision and completeness constraints.

## 14. API impact

Provide shared REST/GraphQL capture-session, upload/finalize, submit, review, reject/request-revision, complete and scoped-read operations.

## 15. UI/UX impact

Build camera-friendly responsive PWA capture/review with upload progress, receiver/signature/geo/time, missing guidance and complete online error/retry states.

## 16. Security impact

Use authenticated scoped sessions, private scanned files, signed URLs, geolocation/PII field policy, CSRF/replay controls and customer record isolation. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Direct bounded uploads, async scans/thumbnails, compressed previews and indexed shipment/status/time; measure realistic upload latency/volume.

## 18. Audit impact

Record capture/reviewer actors, device/session where lawful, shipment/milestone, receiver, geo/time source, file scan/version, decision and corrections.

## 19. Data migration impact

Legacy POD files require shipment/receiver/time/access/scan reconciliation; unknown evidence remains non-complete.

## 20. Detailed implementation tasks

1. Define ePOD identity, required evidence, capture/review/revision/completion lifecycle.
2. Implement online-first scoped capture and private scanned file finalization.
3. Implement geo/time/receiver/signature validation and review decisions.
4. Build responsive capture/review/history UX and shared API contracts.
5. Verify file/customer isolation, retry/concurrency, evidence integrity, performance and billing triggers.

## 21. Main flow

Authorized field user captures required ePOD evidence online; reviewer approves the safe exact version and marks it complete.

## 22. Alternative flow

Reviewer requests revision; a new version supplements/replaces rejected evidence while full history remains.

## 23. Exception flow

Offline/unavailable network, failed upload/scan, missing receiver/signature/geo/time, wrong shipment, replay or unauthorized customer access stays incomplete.

## 24. Business rules

- RPD-004 makes Phase 3 online-first responsive PWA; native mobile and offline synchronization are out of scope.
- Completion binds exact shipment/delivery milestone and evidence versions.
- Normal roles cannot rewrite completed evidence; RPD-022 Supreme exception remains disclosed.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate delivered/eligible shipment, required evidence, file scan, receiver fields, coordinate bounds/precision and trustworthy server time.
- Submission/review is idempotent and rejects stale versions.
- Customer-visible evidence excludes internal metadata and rechecks current scope.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Assigned field/operations users capture; authorized reviewer decides; customer sees only own completed permitted ePOD. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Photo/signature/receiver/geo/time combinations, failed/retried uploads, quarantine, review revision, stale version, wrong shipment and two customers/tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- ePOD lifecycle/version/completeness/geo/time/idempotency/concurrency/database tests.
- RLS/RBAC/field/record/file/malware/signed-URL/customer-scope/security/audit tests.
- Capture/review/history E2E, WCAG/browser/responsive, upload performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Shipment/milestone/doc requirements, PostGIS, tracking, billing readiness and Platform file engine. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-177.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Completed ePOD contains all configured trusted evidence.
- File, PII, geolocation and customer access remain isolated.
- Failure/revision is recoverable without losing lineage.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-012` / `OPS-178` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

