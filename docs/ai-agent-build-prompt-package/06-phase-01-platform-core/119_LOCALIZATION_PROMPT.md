# Prompt 119 — Localization

**Prompt ID:** `CG-S6-PLT-016`  
**Package document:** `CG-AABPP-PLT-119`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-119.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-016` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Tenant Experience; Epic: Locale and Terminology; Capability: Localization foundation; Feature slice: Locale/timezone/currency/terminology/template resolution; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical localization primitives for language, timezone, number/date/currency and tenant terminology without changing canonical semantics.

## 5. Business value

Support Indonesia-first and future localization consistently across portals, API presentation and notifications.

## 6. Source requirement

PLT-WLB-001..004; UX localization; RPD-010/011/032 as applicable; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Localization catalogues/resolver/config/schema/tests/docs and bounded shared UI integrations. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Mass feature-page translation, statutory logic, tenant-specific code fork. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Versioned tenant locale/terminology configuration with effective dates/RLS where persistence needed.

## 14. API impact

Locale negotiation/format metadata and stable machine values; API canonical values remain locale-neutral.

## 15. UI/UX impact

Shared formatting/translation/terminology resolver, fallback, long-text and locale states.

## 16. Security impact

No user-controlled translation/template injection; sensitive errors remain safe.

## 17. Performance impact

Load namespaces/bundles lazily and cache by locale/version without cross-tenant leakage.

## 18. Audit impact

Record tenant terminology/locale/template changes and versions.

## 19. Data migration impact

Map existing strings/config incrementally; do not bulk rewrite feature pages outside scope.

## 20. Detailed implementation tasks

1. Define supported locale/timezone/currency/terminology scope and fallback precedence.
2. Implement typed catalogue/resolver/format utilities and versioned tenant overrides.
3. Integrate shared shell/design-system/auth/platform examples and notification template hooks.
4. Add missing-key/fallback/injection/SSR/cache/accessibility tests and docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

User/tenant context renders approved locale/format/terminology while storing canonical values.

## 22. Alternative flow

Missing tenant override falls back through user→tenant→platform default.

## 23. Exception flow

Invalid locale/key/template/format or unsafe content is rejected/falls back visibly.

## 24. Business rules

- Canonical statuses/permission/module IDs never change with labels.
- Indonesia-first rules are configurable and dated, not hard-coded statutory assumptions.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Fallback/format/timezone/currency/rounding deterministic across server/client.
- Missing/unused keys detectable.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Translations cannot reveal hidden fields/actions; locale config follows tenant/admin authority.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Indonesian/English, multiple timezones/currencies, long/missing strings, unsafe templates and tenant overrides. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Resolver/fallback/format/SSR hydration/cache tests.
- Injection/missing key/cross-tenant terminology/accessibility and bundle tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- White-label, auth shells, notifications, APIs and existing copy.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-119.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Canonical data renders consistently in supported locale/tenant terminology.
- No semantic drift/injection/cache leak; docs/tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

