# Prompt 180 — Basic Public and Customer Tracking

**Prompt ID:** `CG-S8-OPS-014`  
**Package document:** `CG-AABPP-OPS-180`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-180.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-014` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Customer Visibility; Epic: Read-Only Shipment Visibility; Capability: Minimal public/customer tracking and ePOD access; Feature slice: Opaque lookup/customer scope→sanitized timeline→permitted document; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a minimal fast read-only tracking surface for public verification and scoped customer users without building the full Customer Portal.

## 5. Business value

Reduce status inquiries while preserving strict customer/tenant/document privacy.

## 6. Source requirement

OPS-TRK-001..004 basic slice; CPT-TRK-001..004 basic Phase 3 slice; ASM-PK-005; RPD-005. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-170, OPS-173..177; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-181..188; Step 13 full Customer Portal; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer Visibility schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add only scoped tracking token/reference metadata, customer visibility policy and safe read projection/indexes; shipment/milestone/ePOD remain authoritative.

## 14. API impact

Provide rate-limited public opaque lookup/verification and authenticated customer tracking queries over shared services with sanitized status/timeline/document projections.

## 15. UI/UX impact

Build accessible responsive tracking page with custom-domain support, status/timeline, safe exception message, permitted ePOD link and complete states.

## 16. Security impact

Use unguessable opaque token/reference plus verification, rate limiting, generic errors, customer account/site scope, field minimization and short-lived signed document URLs. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index safe lookup keys and customer scope; cache sanitized projections within freshness policy, set query budgets and avoid realtime fan-out.

## 18. Audit impact

Record token lifecycle, successful/suspicious lookup, customer document access, policy changes and rate-limit/security events without logging secrets.

## 19. Data migration impact

No transaction migration; rotate/issue safe tokens for eligible shipments and invalidate insecure legacy identifiers.

## 20. Detailed implementation tasks

1. Define public versus authenticated customer projection and Phase 8 boundary.
2. Implement opaque token/verification, rate limits and customer account/site scope.
3. Implement sanitized timeline/ePOD access over canonical milestone/document services.
4. Build responsive accessible tracking page/custom-domain routing.
5. Verify enumeration resistance, customer isolation, cache freshness, performance and full-portal scope exclusion.

## 21. Main flow

User supplies a valid opaque reference/verification or authenticated customer scope and sees only sanitized permitted shipment status/timeline.

## 22. Alternative flow

Authorized customer downloads one permitted completed ePOD through a short-lived signed URL.

## 23. Exception flow

Invalid/expired/revoked token, wrong customer/site, rate limit, unavailable cache or unsafe document returns generic safe guidance.

## 24. Business rules

- Phase 3 tracking is read-only and minimal; booking, invoice/payment, warehouse, tickets, loyalty and account administration remain Step 13.
- Public lookup never uses a bare sequential shipment number as sole authority.
- Internal exception notes, location detail, vendor, cost and sensitive contact data are excluded.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate token hash/scope/expiry, customer/account/site relationship and shipment visibility policy.
- Sanitize milestone/exception/document fields consistently across REST/GraphQL/UI.
- Signed file access rechecks current customer/record scope.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Public access is token/verification constrained; authenticated customers see only assigned account/site shipments; internal users use normal Operations views. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Valid/invalid/expired/revoked tokens, enumeration attempts, multiple customer accounts/sites, hidden milestones, ePOD access and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Token/hash/scope/expiry/rate-limit/cache/projection tests.
- Customer/RLS/RBAC/field/record/cross-tenant/signed-URL/security/audit tests.
- Public/customer tracking E2E, WCAG/browser/responsive, load and enumeration regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Milestone/status/exception/ePOD, custom domain, customer identity and future Step 13 portal contracts. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-180.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Tracking is fast, minimal and cannot enumerate or cross customer/tenant boundaries.
- Only sanitized milestones and permitted safe ePOD are visible.
- No full Customer Portal feature is introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-015` / `OPS-181` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

