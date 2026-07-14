# ERROR_LEDGER.md

**Template ID:** `CG-AABPP-GOV-017`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Policy:** Record reproducible failures, failed gates, unsafe/unknown states, and recovery evidence. Do not store secrets, tokens, or unredacted tenant data.

## 1. Error states and severity

Statuses: `OPEN`, `INVESTIGATING`, `ROOT_CAUSE_CONFIRMED`, `RECOVERY_IN_PROGRESS`, `RECOVERED`, `VERIFIED`, `ACCEPTED`, `SUPERSEDED`.

| Severity | Definition | Default effect |
|---|---|---|
| Sev-1/Critical | Tenant isolation, credential exposure, corrupt/imbalanced finance, destructive data loss, production outage, untrusted repository/database | Stop affected work/release; incident and recovery authority required |
| Sev-2/High | Major flow unavailable, serious security/access defect, failed migration/restore, cross-module integrity failure | Block phase/release and dependent tasks |
| Sev-3/Medium | Bounded defect or failed non-critical gate with safe workaround | Separate recovery task; may block capability verification |
| Sev-4/Low | Minor tooling/docs/local issue without data/security impact | Track and schedule; no hidden suppression |

## 2. Error index

| Error ID | Task ID | Severity | Environment | Summary | Status | Root cause | Last good checkpoint | Owner | Record link |
|---|---|---|---|---|---|---|---|---|---|
| `ERR-{{YYYY}}-{{SEQ}}` | `{{TASK_ID}}` | `{{SEVERITY}}` | `{{ENV}}` | `{{SUMMARY}}` | `{{STATUS}}` | `{{UNKNOWN_OR_SHORT}}` | `{{SHA/SCHEMA}}` | `{{OWNER}}` | `{{ANCHOR}}` |

## 3. Error record template

### ERR-{{YYYY}}-{{SEQ}} — {{TITLE}}

| Field | Value |
|---|---|
| Task/prompt/phase | `{{VALUES}}` |
| Detected at/by | `{{TIMESTAMP_AND_AGENT}}` |
| Environment | `{{LOCAL/DEV/TEST/STAGING/UAT/PROD}}` |
| Branch/commit/schema head | `{{VALUES}}` |
| Severity/status | `{{VALUES}}` |
| Pre-existing or change-caused | `{{PRE_EXISTING/CHANGE_CAUSED/UNKNOWN}}` |
| Related issue/incident/decision | `{{IDS_OR_NONE}}` |
| Owner/escalation authority | `{{VALUES}}` |

#### Trigger and exact evidence

- Command/action/request: `{{EXACT_REDACTED_VALUE}}`.
- Expected result: `{{VALUE}}`.
- Actual result: `{{VALUE}}`.
- Exact error/log excerpt: `{{MINIMUM_RELEVANT_REDACTED_TEXT}}`.
- Frequency/reproducibility: `{{ALWAYS | INTERMITTENT | ONCE | UNKNOWN}}`.
- First/last occurrence: `{{TIMESTAMPS}}`.
- Artifact links: `{{CI_LOG_BUILD_LOG_SCREENSHOT_TRACE_ID_QUERY_PLAN}}`.

Do not paste credentials, cookies, tokens, personal data, or tenant payloads. Preserve secure evidence using approved storage and reference it.

#### Reproduction

1. Preconditions/data fixture: `{{VALUE}}`.
2. Steps/commands: `{{VALUE}}`.
3. Observed boundary: `{{VALUE}}`.
4. Cleanup required: `{{VALUE}}`.

#### Impact assessment

| Area | Impact | Evidence | Containment |
|---|---|---|---|
| Users/tenant scope | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| Data/schema/migration | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| Security/privacy/credentials | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| Finance/audit/retention | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| REST/GraphQL/integration/job | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| Regression/downstream | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |
| Performance/availability/recovery | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` |

Release/task effect: `{{BLOCKS_TASK | BLOCKS_PHASE | BLOCKS_GA | DOES_NOT_BLOCK_WITH_REASON}}`.

#### Changed and involved artifacts

- Files/config involved: `{{PATHS}}`.
- Migrations and application state: `{{IDS_AND_NOT_CREATED/CREATED_NOT_APPLIED/PARTIALLY_APPLIED/APPLIED/ROLLED_BACK/UNKNOWN}}`.
- API/schema/event contracts: `{{VALUES}}`.
- Data rows/classes affected: `{{REDACTED_SUMMARY}}`.
- Tests already passing: `{{VALUES}}`.
- Tests failing/not run: `{{VALUES}}`.

#### Root-cause analysis

- Initial hypothesis: `{{VALUE}}`.
- Evidence for/against: `{{VALUE}}`.
- Confirmed root cause: `{{VALUE_OR_UNKNOWN}}`.
- Why existing controls did not catch it: `{{VALUE}}`.
- Scope of correction: `{{VALUE}}`.
- Unrelated causes ruled out: `{{VALUE}}`.

Do not mark `ROOT_CAUSE_CONFIRMED` without evidence.

#### Last known good checkpoint

| Item | Value |
|---|---|
| Commit/branch | `{{VALUE}}` |
| Schema/migration head | `{{VALUE}}` |
| Environment/deployment | `{{VALUE}}` |
| Last passing gates | `{{VALUE}}` |
| Backup/snapshot/recovery point | `{{VALUE_OR_NONE}}` |
| Trust boundary | `{{WHAT_IS_STILL_TRUSTED}}` |

#### Recovery options

| Option | Steps | Data/security risk | Downtime/compatibility | Reversibility | Decision/owner |
|---|---|---|---|---|---|
| A | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |
| B | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |

Chosen recovery: `{{OPTION_AND_REASON}}`.

Allowed repair paths: `{{PATHS}}`.  
Forbidden repair paths: `{{PATHS}}`.

#### Recovery execution and verification

| Step | Action | Result/evidence | Commit/migration | Status |
|---:|---|---|---|---|
| 1 | `{{VALUE}}` | `{{REF}}` | `{{VALUE}}` | `{{STATUS}}` |

Re-verification must include the original reproduction, focused regression, mandatory gates, and every affected tenant/security/data/finance/contract/recovery gate.

Final verification result: `{{VALUE}}`.  
Residual impact/risk: `{{VALUE_OR_NONE}}`.

#### Resume package

- Resume task/prompt: `{{ID_AND_PATH}}`.
- Completed safely: `{{VALUE}}`.
- Remaining work: `{{VALUE}}`.
- Exact checkpoint: `{{VALUE}}`.
- Required environment/credentials/approvals: `{{VALUE}}`.
- First safe command/action: `{{VALUE}}`.
- Documentation to reconcile: `{{VALUES}}`.

## 4. Closure rules

An error is `VERIFIED` only after root cause or accepted recovery is evidenced, affected gates pass, state is trusted, task/build status is reconciled, regression protection exists, and follow-up issues are linked. `ACCEPTED` requires named authority, rationale, bounded impact, monitoring, review trigger, and release decision.
