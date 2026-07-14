# Prompt 420 - Regression Risk Audit

**Prompt ID:** `CG-S17-FPV-007`  
**Package document:** `CG-AABPP-FPV-420`  
**Version:** `0.18.0`  
**Runtime build log:** `docs/build-log/final-package-validation/FPV-420.md`

Do not begin until Prompt 414 marks this package-validation task `READY`, all package files are available at the active checkpoint, and Step 16 package completion is confirmed. This prompt audits the prompt package itself; it does not execute product runtime implementation.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S17-FPV-007` and exactly one approved final-validation WBS/task-ledger item.

## 2. Parent phase

`Step 17 - Final Package Validation`; package `0.18.0`.

## 3. Workstream

Workstream: Quality Audit; Epic: Regression Control; Capability: Regression Risk Audit; Feature slice: Final package audit for Regression Risk Audit; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Audit whether package prompts preserve non-regression, critical E2E coverage, smoke/regression/UAT gates and repair templates.

## 5. Business value

Prevent future changes from breaking source-critical flows.

## 6. Source requirement

Master Prompt Step 17: Apakah terdapat potensi regresi; regression test required. Cite exact package files, source controls, manifest rows and validation evidence.

## 7. Current repository context

Record package root, current branch/checkpoint, package version, file count, manifest state, changed files, control files, validation command results and any dirty-worktree ownership.

## 8. Preconditions

Read `START_HERE.md` if present, `00_PACKAGE_README.md`, source/decision/conflict/coverage/build status/manifest controls, all relevant step README files and the exact files being audited. Confirm this is package validation only and not runtime implementation.

## 9. Upstream dependencies

FPV-414 and Step 0-16 package completion. Every prior package group must be present, versioned and traceable or explicitly recorded as a package gap.

## 10. Downstream impact

FPV-421, final package closure, future agent execution, runtime safety and package handoff. Identify affected controls, manifests, START_HERE, validation reports, runbooks, task ledgers and final gap/risk register.

## 11. Allowed files/folders

Only package validation files, control docs, manifest, START_HERE, validation reports and documentation needed to correct package metadata or audit findings.

## 12. Forbidden files/folders

No product implementation code, no runtime repository mutation, no production action, no migration execution, no tenant data processing, no feature prompt expansion outside final validation, no silent source decision change and no fake validation pass.

## 13. Database impact

No database runtime impact. Audit only whether database, migration, RLS, seed, rebuild, backup, restore and rollback prompts are present, dependency-gated and complete.

## 14. API impact

No API runtime impact. Audit only whether REST, GraphQL, public/customer/vendor API, webhook, export and compatibility prompts are present, dependency-gated and complete.

## 15. UI/UX impact

No UI runtime impact. Audit only whether UX, accessibility, browser/device, customer portal, admin and support prompts include states, tests and completion evidence.

## 16. Security impact

Audit tenant isolation, RLS, RBAC, field/record/file/API/webhook/secret/MFA/session/support/AI policy coverage and release blockers. Do not weaken, suppress or reclassify security gates.

## 17. Performance impact

Audit performance/scalability budgets, query/payload/job/report/import/export/load controls and release evidence prompts. Do not claim runtime performance pass without runtime evidence.

## 18. Audit impact

Record audit actor, package checkpoint, files inspected, findings, pass/fail status, evidence links, residual risks, corrections and final validation effect.

## 19. Data migration impact

Audit migration, seed, data import/export, rehearsal, cutover, rollback and reconciliation prompt coverage. Do not process tenant-real data.

## 20. Detailed implementation tasks

1. Build the exact audit checklist for this validation area.
2. Inspect relevant package files and manifests.
3. Record pass/fail findings with file paths and evidence.
4. Correct package metadata only if the defect is mechanical and source-safe.
5. Register unresolved issues in the final gap/risk register.
6. Update validation report, build status/manifest if required and handoff notes.

## 21. Main flow

Run the audit, reconcile evidence, fix safe package metadata defects and produce a pass/fail validation result.

## 22. Alternative flow

If package evidence is too large to inspect in one pass, split by step range, preserve interim checklist state and resume from last inspected file.

## 23. Exception flow

If a missing prompt, circular dependency, uncovered requirement, unsafe scope, absent recovery path, unsupported production-ready claim or invalid manifest entry is found, stop marking final validation as passed and record the blocker.

## 24. Business rules

- Package validation cannot claim runtime implementation.
- Production-ready, market-ready and GA labels require gates and runtime evidence.
- Every prompt must be context-complete, dependency-aware, testable, restartable, auditable and safe for existing code and tenant data.
- One-paragraph, generic, no-acceptance, no-regression, no-security, no-docs or no-recovery prompts fail validation.

## 25. Validation rules

Validate file existence, non-empty content, source traceability, dependency, completion evidence, tests, recovery, documentation, next step, version, manifest path, unique IDs and package/runtime distinction.

## 26. Access rules

Use read-only package inspection except for controlled package metadata/report corrections. Do not access production systems or tenant data.

## 27. Test data requirement

Use package files and synthetic validation fixtures only. No tenant-real data is required.

## 28. Tests to create/update

Create or update package validation checks for this audit area, including file/path checks, ID uniqueness, heading structure, source coverage, dependency graph or content rules as applicable.

## 29. Regression tests

Re-run affected package validation checks after any metadata correction. Ensure earlier step counts, versions, manifests and next commands remain stable.

## 30. Commands to run

Use local shell validation such as `find`, `rg`, deterministic scripts, checksum and ZIP tests as applicable. Record command, result and limitations.

## 31. Documentation to update

Update final validation report, final gap/risk register, package build status, prompt package manifest, START_HERE and handoff only when evidence supports the update.

## 32. Rollback/recovery note

If a package metadata correction is wrong, revert only that correction through a new controlled patch or superseding manifest note. Never delete validated package history.

## 33. Acceptance criteria

- Audit checklist for Regression Risk Audit is complete.
- Findings are evidence-backed with file paths.
- Safe corrections are applied or blockers are registered.
- Package/runtime distinction is preserved.
- Next validation prompt is clear.

## 34. Definition of Done

This validation area is complete when all findings are pass or registered, control files are consistent, no fake runtime claim is introduced and the final package can still be resumed by a new agent.

## 35. Completion report format

Report prompt ID, package checkpoint, files inspected, checks performed, pass/fail table, corrections, unresolved gaps, affected controls, command output summary, rollback/resume note and next eligible prompt.

## 36. Next eligible prompt

If this task is `VERIFIED`, continue only to `FPV-421`. If blocked, resume this audit or update the final gap/risk register before continuing.
