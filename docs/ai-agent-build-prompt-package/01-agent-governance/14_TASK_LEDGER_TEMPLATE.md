# TASK_LEDGER.md

**Template ID:** `CG-AABPP-GOV-014`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Ledger mode:** Append task records; update current status in place; never erase failed/rolled-back history.

## 1. Task identity and state model

Recommended ID: `CG-P<PHASE>-<WORKSTREAM>-<SEQUENCE>`, for example `CG-P1-IAM-004`.

Allowed states only:

`NOT_STARTED → READY → IN_PROGRESS → COMPLETED → VERIFIED`

Exception transitions:

- `IN_PROGRESS → PARTIALLY_COMPLETE | BLOCKED | FAILED`
- `PARTIALLY_COMPLETE | BLOCKED | FAILED → READY | IN_PROGRESS | ROLLED_BACK | SUPERSEDED`
- `COMPLETED → VERIFIED | FAILED | ROLLED_BACK`
- Any replacement task may mark the old task `SUPERSEDED` with a link.

`COMPLETED` means scoped work and task gates passed. `VERIFIED` requires independent or parent-gate verification. A failed mandatory gate prevents both.

## 2. Active task index

| Task ID | Name | Phase/workstream | Status | Owner/agent | Branch | Dependency | Build log | Last update | Next action |
|---|---|---|---|---|---|---|---|---|---|
| `{{ID}}` | `{{NAME}}` | `{{PHASE/STREAM}}` | `{{STATUS}}` | `{{OWNER}}` | `{{BRANCH}}` | `{{TASK_IDS_OR_NONE}}` | `{{PATH}}` | `{{TIME}}` | `{{ACTION}}` |

Only one task per branch should normally be `IN_PROGRESS`. Parallel work requires non-overlapping scope and explicit integration ownership.

## 3. Task record template

### {{TASK_ID}} — {{TASK_NAME}}

| Field | Value |
|---|---|
| Parent phase | `{{VALUE}}` |
| Workstream/epic/capability | `{{VALUE}}` |
| Status | `{{STATUS}}` |
| Priority/severity | `{{VALUE}}` |
| Owner/agent | `{{VALUE}}` |
| Created/started/updated | `{{TIMESTAMPS}}` |
| Branch/current commit | `{{VALUE}}` |
| Last known good commit | `{{VALUE}}` |
| Prompt path/version | `{{VALUE}}` |
| Build log path | `{{VALUE}}` |
| Source requirements | `{{IDS_AND_SECTIONS}}` |
| Decisions/ADRs | `{{IDS}}` |

#### Objective and business outcome

`{{ONE_BOUNDED_OBJECTIVE_AND_USER_OR_BUSINESS_VALUE}}`

#### Scope contract

- Allowed paths: `{{PATHS}}`.
- Forbidden paths: `{{PATHS}}`.
- Expected files: `{{PATHS_OR_COUNT}}`.
- Migration limit/expected migrations: `{{VALUE}}`.
- Database impact: `{{VALUE_OR_NA_WITH_REASON}}`.
- REST/GraphQL/webhook impact: `{{VALUE_OR_NA_WITH_REASON}}`.
- UI/UX/accessibility impact: `{{VALUE_OR_NA_WITH_REASON}}`.
- Security/tenant/field/record impact: `{{VALUE_OR_NA_WITH_REASON}}`.
- Finance/data/audit impact: `{{VALUE_OR_NA_WITH_REASON}}`.
- Performance/observability impact: `{{VALUE_OR_NA_WITH_REASON}}`.

#### Dependencies

| Type | Task/system/contract | Required state | Evidence | Current state |
|---|---|---|---|---|
| Upstream | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| Downstream | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |

#### Baseline

| Check | Command/evidence | Result | Timestamp |
|---|---|---|---|
| Repository/worktree | `{{VALUE}}` | `{{VALUE}}` | `{{TIME}}` |
| Focused behavior/tests | `{{VALUE}}` | `{{VALUE}}` | `{{TIME}}` |
| Mandatory gates | `{{VALUE}}` | `{{VALUE}}` | `{{TIME}}` |
| Schema/migration head | `{{VALUE}}` | `{{VALUE}}` | `{{TIME}}` |
| Performance/access/security | `{{VALUE}}` | `{{VALUE}}` | `{{TIME}}` |

#### Execution checklist

- [ ] Pre-flight documents and repository inspected.
- [ ] Baseline captured.
- [ ] Plan and expected files recorded.
- [ ] Main flow implemented.
- [ ] Alternative and exception flows implemented.
- [ ] Positive/negative/regression tests added.
- [ ] Tenant/security/finance/data/performance checks completed as applicable.
- [ ] Focused and mandatory gates passed.
- [ ] Documentation and ledgers updated.
- [ ] Rollback/recovery verified or documented.
- [ ] Completion report and next task recorded.

#### Change and evidence summary

- Files changed: `{{LIST_OR_CHANGE_MANIFEST_REF}}`.
- Migrations/schema/types: `{{VALUE}}`.
- Routes/actions/contracts/jobs: `{{VALUE}}`.
- Tests added/updated: `{{VALUE}}`.
- Commands/results: `{{VALUE_OR_BUILD_LOG_REF}}`.
- Documentation: `{{VALUE}}`.
- Commit/checkpoint: `{{VALUE}}`.

#### Failure/resume state

Complete this for `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE`:

| Resume field | Value |
|---|---|
| Completed safely | `{{VALUE}}` |
| Exact failure/blocker evidence | `{{VALUE}}` |
| Files already changed | `{{VALUE}}` |
| Migration state | `{{NOT_CREATED/CREATED_NOT_APPLIED/PARTIALLY_APPLIED/APPLIED/ROLLED_BACK/UNKNOWN}}` |
| Tests passed | `{{VALUE}}` |
| Tests failing/not run | `{{VALUE}}` |
| Data/security/regression impact | `{{VALUE}}` |
| Last trusted checkpoint | `{{VALUE}}` |
| Allowed repair scope | `{{VALUE}}` |
| Forbidden repair scope | `{{VALUE}}` |
| Recovery steps | `{{VALUE}}` |
| Re-verification gates | `{{VALUE}}` |
| Error/issue IDs | `{{VALUE}}` |
| Resume task/prompt | `{{VALUE}}` |

#### Acceptance and closure

- Acceptance evidence: `{{REFS}}`.
- Final status: `{{STATUS}}`.
- Verified by/date: `{{VALUE_OR_PENDING}}`.
- Residual risks/issues: `{{NONE_OR_IDS}}`.
- Rollback/recovery state: `{{VALUE}}`.
- Next eligible task: `{{TASK_ID_OR_NONE}}`.

## 4. Dependency and sequencing index

| Task ID | Requires | Enables | Shared files/contracts | Collision owner | Ready? |
|---|---|---|---|---|---|
| `{{ID}}` | `{{IDS}}` | `{{IDS}}` | `{{VALUES}}` | `{{OWNER}}` | `{{YES/NO_AND_REASON}}` |

Do not start a task whose upstream state is not `VERIFIED` when that state protects schema, tenancy, security, finance, or a public contract.

## 5. Completed and superseded index

| Task ID | Final status | Commit | Evidence/build log | Superseded by | Closed date |
|---|---|---|---|---|---|
| `{{ID}}` | `{{VERIFIED/ROLLED_BACK/SUPERSEDED}}` | `{{SHA}}` | `{{REF}}` | `{{ID_OR_NONE}}` | `{{DATE}}` |

## 6. Ledger maintenance rules

1. Update the active index and detailed record in the same task checkpoint.
2. Never delete failed or rolled-back records; preserve recovery evidence.
3. Link decisions, assumptions, errors, issues, migrations, change entries, and build logs by stable IDs.
4. Do not mark tasks `READY` from elapsed time or optimism; all entry dependencies must be evidenced.
5. Reconcile status with `CARGOGRID_BUILD_STATUS.md` after every transition.
6. A task without documentation, test results, and last-known-good checkpoint cannot be `COMPLETED`.
