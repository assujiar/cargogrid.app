# Prompt 387 — Release Blocker Triage and Remediation

**Prompt ID:** `CG-S15-HDN-019`  
**Package document:** `CG-AABPP-HDN-387`  
**Version:** `0.16.0`  
**Runtime build log:** `docs/build-log/full-system-hardening/HDN-387.md`

Do not begin until all upstream tasks required by the execution index are `VERIFIED` and `PHASE_9_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S15-HDN-019` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Step 15 — Full-System Hardening`; package `0.16.0`.

## 3. Workstream

Workstream: Hardening Closure; Epic: Full-System Hardening Evidence; Capability: Release Blocker Triage and Remediation; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Triage, rank and remediate bounded release blockers found during full-system hardening without expanding into release/go-live work.

## 5. Business value

Give Step 16 a truthful release-candidate starting point with known blockers, evidence, rollback paths and no hidden critical risk.

## 6. Source requirement

Master Prompt Step 15, Security Guardrails, Data and Financial Integrity Guardrails, Quality Gates, BPR NFRs, Delivery testing/security/DR gates and all prior phase closure evidence. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 9 closure, all Step 15 build logs, hardening matrices and blocker ledgers. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines and stop on checkpoint, evidence, tenant, security, finance, API, backup/restore, DR, migration or release-boundary conflict.

## 9. Upstream dependencies

HDN-386 VERIFIED. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HDN-388..389 and Step 16 eligibility. Identify affected tests, docs, runbooks, release blockers, rollback paths and release-candidate gates.

## 11. Allowed files/folders

Use only exact Step 15 verification, blocker remediation, documentation, runbook, test, evidence and handoff paths authorized by WBS. Preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New product features, Step 16 release/go-live execution, production mutation, tenant forks, applied-migration edits, destructive cleanup, gate suppression, permission weakening and fake evidence.

## 13. Database impact

No planned feature schema. Allow only minimal registered hardening-defect repair with additive/reversible migration and reconciliation evidence.

## 14. API impact

Do not break public/private API, webhook, export or schema contracts without approved compatibility plan, versioning, tests and release note.

## 15. UI/UX impact

Verify or document hardening state across user-facing/admin/support surfaces with accessibility, responsive behavior, complete states and no fake success/dead action.

## 16. Security impact

Preserve RLS/RBAC/field/file/API/webhook/secret/MFA/session/support/AI controls. All privileged evidence is redacted; RPD-022 residual risk remains explicit.

## 17. Performance impact

Preserve or improve performance budgets. Do not add hardening repairs that create unbounded queries, blocking jobs, large browser payloads or cross-tenant cache risk.

## 18. Audit impact

Every finding, repair, waiver, rerun, command and go/no-go judgment is auditable with actor, timestamp, checkpoint, evidence link, owner and rationale.

## 19. Data migration impact

Any migration or repair must include clean install/upgrade/rollback/reconciliation evidence. Do not fabricate history or edit applied migrations.

## 20. Detailed implementation tasks

- Rank all findings by severity, exploitability, business impact and release impact.
- Select bounded critical/high repairs authorized by the WBS.
- Implement repairs with regression tests and rollback notes.
- Re-run affected gates and update evidence.
- Escalate unresolved blockers with exact no-go rationale.

## 21. Main flow

The agent reconciles hardening evidence, ranks blockers, performs only authorized bounded repairs or documents handoff, then updates Step 16 eligibility.

## 22. Alternative flow

If critical evidence is unavailable, mark Step 15 blocked with exact missing command/environment/owner and do not advance to Step 16.

## 23. Exception flow

On critical/high blocker, preserve evidence, stop release eligibility, assign owner and provide exact reproduction/resume. On disputed severity, document evidence and require authorized acceptance before downgrade.

## 24. Business rules

- Only bounded root-cause repairs are allowed; large feature rewrites become separate blocked work.
- A blocker cannot be downgraded without evidence and owner approval.
- Every repair needs regression evidence.
- No release may proceed with critical/high tenant isolation, security, financial integrity, privacy, source-domain, migration, backup/restore or DR blocker.
- RPD-022 Supreme Admin absolute CRUD remains accepted residual risk; never claim immutable-for-all or tamper-proof behavior.
- RPD-021 requires human approval before AI/OCR legal, financial, payroll, payment, tax or critical status effects.
- RPD-023 requires MFA/current authorization for privileged, export, API key, support, financial, payroll, AI approval and security actions.
- RPD-025 retention and legal hold override must be tested across database, files, logs, reports, exports, AI evidence and audit.
- RPD-032 every upload is private and malware-scanned before release; signed URL access is short-lived, scoped and audited.
- RPD-033 REST and GraphQL parity must be preserved where both are supported.
- RPD-038 integrations remain case-specific shared-code adapters with no tenant fork.
- RPD-040 active critical records retain applied configuration/source/model/provider versions.
- Package generation is not runtime implementation, production readiness, pilot readiness or GA status.

## 25. Validation rules

Validate checkpoint consistency, evidence completeness, severity classification, owner assignment, regression proof, rollback path, documentation updates and Step 16 impact.

## 26. Access rules

Hardening evidence may include sensitive security/finance/customer/support data; store it with least privilege and redaction. Support/Supreme evidence is isolated and disclosed as residual risk where applicable.

## 27. Test data requirement

Use the deterministic hardening fixtures and findings from HDN-370..385, including tenant A/B, sensitive records, financial ledgers, files, API clients, webhooks, AI evidence, integrations, high-volume data and recovery scenarios.

## 28. Tests to create/update

- Integrated hardening or blocker regression suite.
- Targeted reruns for every fixed critical/high issue.
- Evidence completeness checks for every Step 15 gate.
- Rollback/recovery validation for repairs.
- Step 16 eligibility checklist validation.

## 29. Regression tests

Run affected regression suites after every repair and final smoke across all critical modules. Preserve baseline and after results.

## 30. Commands to run

Run repository equivalents of lint, typecheck, test, build and every affected hardening gate; add security, API, migration, performance, backup/restore and DR commands as relevant. Never disable or suppress a gate.

## 31. Documentation to update

Update hardening report, evidence index, blocker register, error ledger, change manifest, known issues, release-readiness matrix, runbooks and Step 16 handoff.

## 32. Rollback/recovery note

For each repair or closure decision, state last trusted checkpoint, rollback actions, data reconciliation, evidence preservation and exact resume. No destructive shortcuts.

## 33. Acceptance criteria

- Release Blocker Triage and Remediation output is complete, evidence-backed and checkpoint-consistent.
- Critical/high blockers are either fixed with regression proof or explicitly block Step 16.
- Documentation, runbooks and ledgers reflect actual state.
- No unsupported production/pilot/GA claim is made.
- Step 16 eligibility is explicit.

## 34. Definition of Done

All scoped verification/remediation/documentation is complete; mandatory reruns pass or block; evidence is reconciled; risks are disclosed; release-candidate handoff is truthful.

## 35. Completion report format

Report IDs/checkpoint/environment; evidence reviewed; blockers/fixes; commands/results; residual risks; docs/runbooks; rollback/resume; Step 16 go/no-go recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HDN-388 after this task is `VERIFIED`. Do not set `FULL_SYSTEM_HARDENING_VERIFIED`; only Prompt 389 may do so.

