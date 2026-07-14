# KNOWN_ISSUES.md

**Template ID:** `CG-AABPP-GOV-018`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Policy:** Track unresolved, accepted, deferred, or externally constrained product/technical issues. Exact runtime failures belong in `ERROR_LEDGER.md`; issues may link errors.

## 1. Status and severity

Statuses: `OPEN`, `TRIAGED`, `PLANNED`, `IN_PROGRESS`, `MONITORING`, `ACCEPTED_RISK`, `RESOLVED`, `VERIFIED`, `SUPERSEDED`.

| Severity | Examples | Release effect |
|---|---|---|
| Critical | Cross-tenant access, corrupt finance, destructive data loss, exposed secret, untrusted recovery | Blocks affected work and GA |
| High | Broken core E2E, serious access/security defect, failed restore/migration, unsupported statutory flow | Blocks phase/GA unless formally remediated |
| Medium | Bounded functional/performance/accessibility gap with safe workaround | Must have owner/target; may block feature verification |
| Low | Minor usability/docs/tooling gap | Track for planned correction |

No open Sev-1/critical defect is permitted at GA. Apply stricter source release rules when they exist.

## 2. Standing accepted risks

These ratified risks must remain visible; they are not implementation bugs to be silently “fixed.”

| Decision | Accepted condition | Required permanent handling |
|---|---|---|
| RPD-022 | Supreme Admin can mutate/delete audit, ledger, payment, and final records | No tamper-proof/absolute-immutability claim; disclose in security, finance, retention, and support material |
| RPD-034/036 | Direct GA without external pilot | Full internal UAT, penetration, performance, DR, finance, all-module, and zero-critical-defect gates |
| RPD-031/037 | Contract-silent RPO/RTO is best effort | Never imply a recovery guarantee; record actual rehearsal evidence |
| RPD-038 | Custom non-AI integrations without generic provider abstraction | Shared codebase, explicit ownership, credentials, contracts, tests, monitoring, and runbook; no tenant fork |

## 3. Issue index

| Issue ID | Title | Severity | Status | Scope/environment | Owner | Target task/release | Workaround | Release blocker | Record link |
|---|---|---|---|---|---|---|---|---|---|
| `ISS-{{YYYY}}-{{SEQ}}` | `{{TITLE}}` | `{{SEVERITY}}` | `{{STATUS}}` | `{{VALUE}}` | `{{OWNER}}` | `{{VALUE}}` | `{{SHORT_OR_NONE}}` | `{{YES/NO/CONDITIONAL}}` | `{{ANCHOR}}` |

## 4. Issue record template

### ISS-{{YYYY}}-{{SEQ}} — {{TITLE}}

| Field | Value |
|---|---|
| Reported/detected by/date | `{{VALUES}}` |
| Severity/status/priority | `{{VALUES}}` |
| Product module/phase/workstream | `{{VALUES}}` |
| Environment/tenant class | `{{VALUES_REDACTED}}` |
| Owner/approver | `{{VALUES}}` |
| Source requirement/decision | `{{IDS}}` |
| Related tasks/errors/changes | `{{IDS_OR_NONE}}` |
| Target task/release/date | `{{VALUE}}` |
| Release effect | `{{VALUE}}` |

#### Problem statement

`{{CURRENT_BEHAVIOR_GAP_AND_WHY_IT_MATTERS}}`

Expected behavior: `{{VALUE}}`.  
Observed limitation: `{{VALUE}}`.

#### Evidence and reproduction

- Preconditions/fixture: `{{VALUE}}`.
- Steps/commands: `{{VALUE}}`.
- Evidence links: `{{BUILD_LOG_TEST_TRACE_SCREENSHOT_QUERY_PLAN}}`.
- Reproducibility: `{{VALUE}}`.
- Baseline/pre-existing evidence: `{{VALUE}}`.

Do not include secrets or unredacted tenant/PII/finance payloads.

#### Impact

| Domain | Impact | Affected users/data/contract | Severity evidence |
|---|---|---|---|
| Functional/E2E | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Tenant/security/privacy | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Finance/audit/retention | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| API/integration/job | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Performance/accessibility/browser | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| Migration/deployment/recovery | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |

#### Workaround and containment

- Workaround: `{{VALUE_OR_NONE}}`.
- Preconditions/limitations: `{{VALUE}}`.
- Tenant/user communication: `{{VALUE}}`.
- Monitoring/alert: `{{VALUE}}`.
- Security/data side effects: `{{VALUE}}`.
- Workaround expiry/removal trigger: `{{VALUE}}`.

A workaround may not weaken RLS/RBAC, disable validation/tests, use a client service-role key, corrupt canonical/financial data, create a tenant fork, or make a false recovery/immutability claim.

#### Resolution plan

| Step/task | Owner | Dependency | Acceptance/test | Target | Status |
|---|---|---|---|---|---|
| `{{TASK_ID}}` | `{{OWNER}}` | `{{IDS}}` | `{{VALUE}}` | `{{DATE/RELEASE}}` | `{{STATUS}}` |

Required regression, security, migration, data, performance, accessibility, and documentation evidence: `{{VALUES}}`.

#### Accepted-risk record

Complete only for `ACCEPTED_RISK`:

- Accepting authority/date: `{{VALUE}}`.
- Business rationale: `{{VALUE}}`.
- Bounded scope and duration: `{{VALUE}}`.
- Why remediation is deferred/rejected: `{{VALUE}}`.
- Compensating controls: `{{VALUE}}`.
- Monitoring and review trigger: `{{VALUE}}`.
- Contract/product disclosure: `{{VALUE}}`.
- Decision record: `{{ID}}`.

#### Closure

- Resolution/change/task: `{{IDS}}`.
- Verification evidence: `{{REFS}}`.
- Environments verified: `{{VALUES}}`.
- Documentation/customer communication: `{{VALUE}}`.
- Residual risk/follow-up issue: `{{NONE_OR_IDS}}`.
- Verified by/date: `{{VALUES}}`.

## 5. Maintenance rules

1. Do not delete resolved issues; mark `VERIFIED` or `SUPERSEDED`.
2. Link reproducible failures to Error Ledger entries instead of duplicating raw logs.
3. Re-triage severity when scope, exploitability, data impact, or contracts change.
4. Reconcile release blockers with build status and go/no-go reports.
5. An ownerless or targetless non-low issue cannot be considered safely triaged.
