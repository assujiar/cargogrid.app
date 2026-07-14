# Prompt 90 — Design System Foundation

**Prompt ID:** `CG-S5-PH0-011`  
**Package document:** `CG-AABPP-PH0-090`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-90.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-011` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: UX and Design System; Epic: Shared Experience Primitives; Capability: Accessible branded design foundation; Feature slice: Tokens, primitives, states and documentation baseline; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the minimum evidence-backed CargoGrid design-system foundation that preserves existing credible components and supports four portals, white-labeling and WCAG 2.2 AA.

## 5. Business value

Enable consistent accessible product work without one-off UI, tenant forks or later redesign churn.

## 6. Source requirement

UX/Data/Access Design; UX workstream; accessibility baseline; repository component inventory. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved design-system token/component/test/story/docs paths only. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Feature pages/workflows, broad CSS rewrite, authorization logic, schemas/data and unrelated assets. Always preserve unrelated/user-owned changes.

## 13. Database impact

No schema change.

## 14. API impact

No API contract change; components accept typed view models/errors, not direct DB access.

## 15. UI/UX impact

Primary scope: tokens, typography/color/spacing, core primitives, states, themes/white-label, responsive and accessibility contracts.

## 16. Security impact

Components must not encode authorization as UI-only truth or expose sensitive fields/errors.

## 17. Performance impact

Bound CSS/JS/font/icon assets and preserve server/client boundaries/tree-shaking.

## 18. Audit impact

Record component/token version, accessibility evidence and migration/deprecation status.

## 19. Data migration impact

No data migration; component adoption is incremental and compatibility-safe.

## 20. Detailed implementation tasks

1. Audit/preserve current tokens/components and identify minimum foundation gaps.
2. Implement approved tokens/theme/white-label primitives and core accessible components/states within bounded paths.
3. Add documented variants, keyboard/focus/labels/errors/reduced-motion/reflow and responsive behavior.
4. Create component tests/examples and incremental adoption/deprecation plan without redesigning feature pages.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

A new feature can use approved tokens/primitives to render accessible standard states.

## 22. Alternative flow

Tenant theme/localization changes approved presentation tokens without altering semantics/access.

## 23. Exception flow

Invalid theme/contrast/missing token/component error falls back safely and is detectable.

## 24. Business rules

- Canonical status meaning remains stable; tenant labels/themes change presentation only.
- No dead/placeholder component or duplicated one-off foundation.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Tokens/variants/props/states and accessibility behaviors are typed/documented.
- Contrast/focus/keyboard/reflow evidence passes.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Components expose denied/masked/disabled states but server controls remain authoritative.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Theme variants, long/localized text, keyboard, reduced motion, responsive viewports and error states. Use synthetic/redacted data only.

## 28. Tests to create/update

- Component/visual/state, keyboard/focus/semantic/accessibility and theme regression.
- Bundle/tree-shaking and browser smoke as supported.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing UI/components/routes/branding and bundle/build.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-90.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Minimum foundation is reusable, accessible, branded and documented.
- Existing credible components are preserved/migrated incrementally with no feature redesign.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
