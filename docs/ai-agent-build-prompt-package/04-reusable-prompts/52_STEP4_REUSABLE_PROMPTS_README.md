# Step 4 — Reusable Execution Prompt Library

**Document ID:** `CG-AABPP-REUSE-052`  
**Version:** `0.5.0`  
**Status:** `FINAL_FOR_STEP`  
**Authorization:** Template generation only. A template instance does not authorize implementation unless its phase/task gate is independently satisfied.

## 1. Purpose

This directory contains 25 paste-ready operational templates for bounded CargoGrid coding-agent work. Every template embeds the Master Prompt’s mandatory 36-field structure, pre-flight, non-regression, security, tenant/data/finance integrity, test, quality, documentation, checkpoint, rollback, and completion-report rules.

## 2. Package/runtime distinction

- `PACKAGE_STEP_4_COMPLETE`: files 52–78 exist and validate.
- `REUSABLE_LIBRARY_NOT_INSTANTIATED`: templates exist but no repository task was authorized.
- `TEMPLATE_INSTANCE_READY`: all variables are resolved from approved runtime evidence and the task ledger says `READY`.
- `TEMPLATE_INSTANCE_IN_PROGRESS`: implementation is bounded to the instantiated contract.
- `TEMPLATE_INSTANCE_VERIFIED`: acceptance, regression, documentation, and closure evidence pass.

Package completion never implies runtime discovery, runtime architecture, phase, feature, or release completion.

## 3. Binding runtime gate

Before any implementation-oriented template is instantiated:

1. Step 2 runtime closure is `RUNTIME_DISCOVERY_VERIFIED`.
2. Step 3 runtime closure is `RUNTIME_ARCHITECTURE_VERIFIED`.
3. The relevant later phase package exists and explicitly authorizes the atomic task.
4. `TASK_LEDGER.md` identifies the task as `READY` with source requirements and upstream dependencies satisfied.
5. Repository checkpoint, worktree ownership, environment, package manager, scripts, current contracts, and baseline results are known.

Incident, rollback, resume, documentation-only, and hotfix templates may be used under their own recorded emergency/recovery authority, but may not silently expand scope or waive security/data/finance controls.

## 4. Template catalogue

| # | Template | Primary use |
|---:|---|---|
| 1 | `53_NEW_FEATURE_SLICE_TEMPLATE.md` | One bounded business capability slice |
| 2 | `54_DATABASE_MIGRATION_TEMPLATE.md` | Additive/expand-contract schema change |
| 3 | `55_RLS_POLICY_TEMPLATE.md` | Tenant-aware database policy |
| 4 | `56_RBAC_PERMISSION_TEMPLATE.md` | Permission/scope enforcement |
| 5 | `57_UI_PAGE_WORKFLOW_TEMPLATE.md` | Accessible page and workflow |
| 6 | `58_API_ENDPOINT_TEMPLATE.md` | REST or GraphQL contract slice |
| 7 | `59_INTEGRATION_ADAPTER_TEMPLATE.md` | One custom third-party adapter |
| 8 | `60_BACKGROUND_JOB_TEMPLATE.md` | Durable PostgreSQL-queue job |
| 9 | `61_IMPORT_EXPORT_TEMPLATE.md` | Async staged import/export |
| 10 | `62_REPORT_DASHBOARD_TEMPLATE.md` | Permission-aware report/dashboard |
| 11 | `63_FINANCIAL_POSTING_TEMPLATE.md` | Double-entry posting capability |
| 12 | `64_BUG_FIX_TEMPLATE.md` | Root-cause correction with regression proof |
| 13 | `65_REGRESSION_REPAIR_TEMPLATE.md` | Restore previously passing behavior |
| 14 | `66_REFACTOR_TEMPLATE.md` | Behavior-preserving bounded refactor |
| 15 | `67_SECURITY_REMEDIATION_TEMPLATE.md` | Vulnerability/control remediation |
| 16 | `68_PERFORMANCE_OPTIMIZATION_TEMPLATE.md` | Measured bottleneck correction |
| 17 | `69_DATA_MIGRATION_TEMPLATE.md` | Idempotent data transformation/backfill |
| 18 | `70_RELEASE_PREPARATION_TEMPLATE.md` | Release evidence and freeze preparation |
| 19 | `71_INCIDENT_RESPONSE_TEMPLATE.md` | Containment, evidence, recovery, communication |
| 20 | `72_ROLLBACK_TEMPLATE.md` | Return to trusted checkpoint safely |
| 21 | `73_RESUME_FAILED_TASK_TEMPLATE.md` | Resume failed/blocked/partial task |
| 22 | `74_RESUME_INTERRUPTED_PHASE_TEMPLATE.md` | Resume phase from reconciled checkpoint |
| 23 | `75_DOCUMENTATION_ONLY_CHANGE_TEMPLATE.md` | Evidence-backed docs-only update |
| 24 | `76_UAT_DEFECT_CORRECTION_TEMPLATE.md` | Correct accepted UAT defect scope |
| 25 | `77_HOTFIX_TEMPLATE.md` | Minimal urgent production correction |

Prompt 78 independently verifies this package.

## 5. Variable rules

- Resolve every `{{VARIABLE}}`; do not leave ambiguous instructions in an instantiated prompt.
- Use `NOT_APPLICABLE — <reason>` for a field with no impact; never omit the field.
- Paths, commands, versions, migrations, schemas, routes, and test names must come from repository evidence.
- Allowed scope must be narrower than forbidden scope and align with one module boundary.
- Default task size: one feature slice, one module boundary, one branch, one objective, normally 1–3 migrations and 5–15 changed files.
- If the task exceeds limits, split it and add explicit dependency IDs before coding.

## 6. Universal hard rules

- Do not edit unrelated modules, applied migrations, protected source decisions, or user-owned changes.
- Do not weaken RLS/RBAC/validation/tests, expose service-role secrets client-side, hardcode tenant/configuration, duplicate canonical data, or make incompatible contract changes without an approved plan.
- Tenant tables require RLS and cross-tenant negative tests. Private files require tenant/record-aware authorization, malware scan, and short-lived signed access.
- High-volume reads use server-side pagination; no transactional `SELECT *`, full-browser datasets, or unapproved realtime. Heavy jobs/imports/exports/reports are asynchronous.
- Financial changes require relevant balance, idempotency, period-lock, reversal, reconciliation, concurrency, rounding, and audit tests.
- Supreme Admin absolute CRUD remains a disclosed risk; never claim immutable/tamper-proof records.
- Run repository-specific baseline and post-change gates. Do not hide failures or change tests merely to silence them.
- Update persistent context, status, ledgers, change/traceability/regression matrices, build log, and relevant schema/API/data-flow/module/user/admin/support/release documentation.

## 7. Completion and next boundary

This directory is complete when all 27 files are non-empty, IDs `REUSE-052..078` are unique, all 25 templates contain fields 1–36, specializations are substantive, and Prompt 78 validates no template can self-authorize implementation.

**Next package command:** `LANJUT STEP 5`
