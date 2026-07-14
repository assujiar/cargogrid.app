# Prompt 139 — Platform Core Documentation and Handoff

**Prompt ID:** `CG-S6-PLT-036`  
**Package document:** `CG-AABPP-PLT-139`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-139.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-036` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Documentation and Phase Operations; Epic: Platform Completion Evidence; Capability: Authoritative Phase 1 handoff; Feature slice: Reconcile platform docs/runbooks and Phase 2 entry; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Reconcile Platform Core documentation/evidence/checkpoint and prepare a context-independent Phase 2 Commercial handoff.

## 5. Business value

Let a new agent build Commercial capabilities against trustworthy platform contracts without hidden assumptions.

## 6. Source requirement

PLT-104..138 outputs; documentation foundation; phase closure requirements. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Phase 1 docs/indices/ledgers/build logs/runbooks/validation/handoff. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Runtime source/config/schema/data/deployment and Phase 2 implementation. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Document actual schema/migration/RLS/seeds/types/checkpoint; no DB change.

## 14. API impact

Document REST/GraphQL/API key/webhook/job/file contracts and versions.

## 15. UI/UX impact

Document Tenant/Supreme routes/workflows/accessibility evidence and design components.

## 16. Security impact

Redact secrets/threat details by audience; document access matrices and RPD-022 limitations.

## 17. Performance impact

Document measured budgets/environment/query/index/job/file/portal evidence.

## 18. Audit impact

Final index links every task/change/ADR/error/issue/evidence/approval/checkpoint.

## 19. Data migration impact

Document rebuild/upgrade/data preservation/rollback state; no execution.

## 20. Detailed implementation tasks

1. Read back PLT-104..138 logs/artifacts at final checkpoint.
2. Update context/status/WBS/traceability/regression/schema/API/data-flow/module/access/engine/portal/runbook docs.
3. Create Phase 2 entry package: verified services/contracts, seeds/fixtures, allowed integration points, known issues and first task.
4. Run link/ID/version/checkpoint/sensitive-content/fresh-agent validation and resolve contradictions.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Fresh Phase 2 agent reconstructs Platform Core and safely starts exact Commercial task.

## 22. Alternative flow

Open non-critical issue remains owned/workaround/expiry without false closure.

## 23. Exception flow

Stale/conflicting/missing evidence or critical blocker prevents handoff and PLT-140.

## 24. Business rules

- Documentation mirrors verified runtime; no chat-only assumption/unsupported readiness claim.
- One authoritative contract location with derived references.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- All docs share checkpoint/schema/API/status and bidirectional links.
- No secret/PII or omitted access/risk disclosure.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Audience-separate user/Tenant Admin/Supreme/API/support/internal security docs.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Synthetic/redacted examples only. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Links/IDs/schema/contracts/required sections/status/checkpoint/sensitive content validation.
- Fresh-agent Phase 2 preflight rehearsal.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- All persistent docs/build logs/runbooks and Phase 0 handoff.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-139.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Platform docs/handoff are complete, consistent and context-independent.
- PLT-140 has all evidence needed for closure.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

