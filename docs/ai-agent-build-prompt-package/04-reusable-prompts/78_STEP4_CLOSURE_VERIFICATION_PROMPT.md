# Prompt 78 — Step 4 Closure Verification

**Prompt ID:** `CG-S4-REUSE-026`  
**Package document:** `CG-AABPP-REUSE-078`  
**Version:** `0.5.0`  
**Package output:** `STEP_4_REUSABLE_LIBRARY_VALIDATION_REPORT.md`

## Objective

Verify that the reusable execution library is complete, non-generic, paste-ready, dependency-aware, safe for existing code/tenant data, restartable, and unable to bypass runtime or phase authorization.

## Required verification

1. Confirm exactly 25 operational templates 53–77 plus README 52 and closure Prompt 78.
2. Confirm every template has one unique package document ID `REUSE-053..077`, prompt ID `CG-S4-REUSE-001..025`, version, intended use, hard rules, and a paste-ready prompt.
3. Confirm every operational template contains numbered fields 1–36 in the Master Prompt order; no “same as above,” omitted impact, or reliance on chat context.
4. Confirm all template variables are explicit and unresolved variables block runtime completion.
5. Confirm each template enforces pre-flight, atomic scope, allowed/forbidden files, baseline/post-change comparison, non-regression, security, tenant/data/finance integrity, performance, audit, migration safety, test data, positive/negative/regression tests, repository-specific commands, documentation, checkpoint, rollback/recovery, completion report, and next eligible prompt.
6. Confirm each specialization contains tasks, tests, acceptance criteria, risks, and recovery specific to its operation—not generic boilerplate only.
7. Confirm database/RLS/RBAC/financial/security/data-migration/import-export/job/API/file templates contain their mandatory domain controls.
8. Confirm incident, rollback, resume, release, and hotfix templates preserve evidence and never waive integrity gates or overstate production readiness.
9. Confirm RPD-022, direct GA/no external pilot, contract-silent recovery, and case-by-case custom integration policy are propagated where relevant.
10. Confirm no template or package state self-authorizes feature code and no CargoGrid runtime source/external system was changed.

## Validation commands

Use non-mutating checks to count files, H1s, IDs, duplicate IDs, empty files, numbered field headings, unresolved structural omissions, invalid status vocabulary, table consistency, and exact next command. Record commands and results.

## Closure states

- `PACKAGE_STEP_4_VERIFIED`: every package validation passes.
- `PACKAGE_STEP_4_PARTIALLY_COMPLETE`: bounded non-critical defects remain; Step 5 is blocked until repaired.
- `PACKAGE_STEP_4_BLOCKED`: template count, 36-field structure, specialization, safety, authorization, or integrity fails.

## Required output

Write a validation report with package checkpoint, file/ID inventory, per-template 36-field and specialization results, guardrail matrix, duplicate/gap findings, forbidden-change audit, closure state, repairs, and exact next command.

## Completion gate

Set `PACKAGE_STEP_4_VERIFIED` only when all checks pass. The package next command is `LANJUT STEP 5`; runtime use still requires the applicable discovery, architecture, phase, task, and emergency authority gates.
