# CHANGE_MANIFEST.md

**Template ID:** `CG-AABPP-GOV-015`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Policy:** Append one traceable entry per atomic task, rollback, hotfix, or documentation-only change. Never silently rewrite historical entries.

## 1. Change index

| Change ID | Task ID | Type | Summary | Compatibility | Migration | Risk | Status | Commit | Date |
|---|---|---|---|---|---|---|---|---|---|
| `CHG-{{YYYY}}-{{SEQ}}` | `{{TASK_ID}}` | `{{FEATURE/FIX/SECURITY/MIGRATION/REFACTOR/DOCS/ROLLBACK/HOTFIX}}` | `{{SUMMARY}}` | `{{ADDITIVE/COMPATIBLE/BREAKING_CONTROLLED/N/A}}` | `{{IDS_OR_NONE}}` | `{{LOW/MEDIUM/HIGH/CRITICAL}}` | `{{STATUS}}` | `{{SHA}}` | `{{DATE}}` |

## 2. Change entry template

### CHG-{{YYYY}}-{{SEQ}} — {{TITLE}}

| Field | Value |
|---|---|
| Task/prompt | `{{TASK_ID_AND_PROMPT_PATH}}` |
| Phase/workstream/module | `{{VALUE}}` |
| Change type | `{{VALUE}}` |
| Author/agent | `{{VALUE}}` |
| Branch/commit/PR | `{{VALUES}}` |
| Started/completed/verified | `{{TIMESTAMPS}}` |
| Source requirements | `{{IDS_AND_SECTIONS}}` |
| Decisions/ADRs | `{{IDS}}` |
| Baseline evidence | `{{BUILD_LOG_OR_REF}}` |
| Final status | `{{STATUS}}` |

#### Outcome

`{{WHAT_REAL_CAPABILITY_OR_CORRECTION_NOW_EXISTS}}`

#### Scope and files

| Path | Action | Authoritative source/owner | Reason | Generated? | Rollback treatment |
|---|---|---|---|---|---|
| `{{PATH}}` | `{{ADD/MODIFY/DELETE/RENAME/REGENERATE}}` | `{{OWNER}}` | `{{REASON}}` | `{{YES/NO}}` | `{{VALUE}}` |

Unrelated pre-existing dirty files preserved: `{{NONE_OR_PATHS_AND_EVIDENCE}}`.

#### Database and data

| Concern | Change/evidence |
|---|---|
| Migration IDs/order | `{{VALUE_OR_NONE}}` |
| Applied environments | `{{VALUES}}` |
| Tables/columns/functions/triggers/views/indexes | `{{VALUES}}` |
| RLS/policy/grants | `{{VALUES}}` |
| FK/unique/check/concurrency/idempotency | `{{VALUES}}` |
| Backfill/data transform | `{{VALUES}}` |
| Generated types/schema registry | `{{VALUES}}` |
| Clean rebuild/upgrade/preservation result | `{{VALUES}}` |
| Lock/downtime/volume risk | `{{VALUES}}` |
| Retention/legal hold/Supreme Admin disclosure | `{{VALUES}}` |

#### Contracts and integrations

| Surface | Change | Version/compatibility | Consumer impact | Verification |
|---|---|---|---|---|
| REST | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| GraphQL | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Webhook/event | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Import/export | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Background job | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Custom connector | `{{VALUE_OR_NA}}` | `{{CASE_BY_CASE_DESIGN}}` | `{{VALUE}}` | `{{REF}}` |

REST/GraphQL shared capabilities must retain authorization, masking, audit, rate-limit, and contract parity. Non-AI integrations must not introduce a generic provider abstraction or tenant source fork.

#### UI, access, and behavior

- Portal/actors/routes/navigation: `{{VALUE}}`.
- Main/alternative/exception flows: `{{VALUE}}`.
- Loading/empty/error/success/denied/degraded states: `{{VALUE}}`.
- RBAC/record/field/status/value rules: `{{VALUE}}`.
- White-label/responsive/PWA/browser impact: `{{VALUE}}`.
- WCAG 2.2 AA evidence: `{{VALUE}}`.

#### Security, privacy, and financial impact

| Domain | Before | After | Evidence/residual risk |
|---|---|---|---|
| Tenant isolation | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Secrets/credentials/session/MFA | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| File scan/signed access | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Audit/Supreme Admin exception | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Finance/ledger/reconciliation | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| PII/tax/payroll/banking | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |

#### Tests and quality evidence

| Gate | Baseline | Final | Command/evidence | Result |
|---|---|---|---|---|
| Focused tests | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |
| Lint/typecheck/build | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |
| DB/migration | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |
| Tenant/access/security | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |
| Contract/E2E/regression | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |
| Performance/accessibility | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{PASS/FAIL}}` |

#### Compatibility, rollout, and recovery

- Compatibility classification and consumer plan: `{{VALUE}}`.
- Feature flag/cohort/environment order: `{{VALUE}}`.
- Monitoring and success/failure signals: `{{VALUE}}`.
- Data reconciliation: `{{VALUE}}`.
- Rollback trigger and authority: `{{VALUE}}`.
- Code rollback/revert plan: `{{VALUE}}`.
- Migration/data recovery plan: `{{VALUE}}`.
- Last known good commit/schema: `{{VALUE}}`.
- Recovery verification: `{{VALUE}}`.

#### Documentation and traceability

Updated: `{{CONTEXT_STATUS_LEDGER_BUILD_LOG_TRACEABILITY_SCHEMA_API_DATA_FLOW_USER_ADMIN_SUPPORT_RELEASE_DOCS}}`.

Known issues/errors/decisions created or changed: `{{NONE_OR_IDS}}`.

#### Approval and closure

| Role | Required? | Approver/evidence | Result/date |
|---|---|---|---|
| Product/domain | `{{YES/NO}}` | `{{VALUE}}` | `{{VALUE}}` |
| Architecture/data | `{{YES/NO}}` | `{{VALUE}}` | `{{VALUE}}` |
| Security/privacy | `{{YES/NO}}` | `{{VALUE}}` | `{{VALUE}}` |
| Finance/legal/HR SME | `{{YES/NO}}` | `{{VALUE}}` | `{{VALUE}}` |
| QA/release/SRE | `{{YES/NO}}` | `{{VALUE}}` | `{{VALUE}}` |

Final residual risks: `{{NONE_OR_VALUES}}`.  
Next eligible task: `{{TASK_ID_OR_NONE}}`.

## 3. Maintenance rules

1. A change entry is required even for rollback and documentation-only work.
2. A removed or renamed file must retain history and downstream impact.
3. Never claim compatibility without contract and migration evidence.
4. Never omit a failed gate; link the Error Ledger and set the task status truthfully.
5. Reconcile every entry with task ledger, build status, build log, and commit.
