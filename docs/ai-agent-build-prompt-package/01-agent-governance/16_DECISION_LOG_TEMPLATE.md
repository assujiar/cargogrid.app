# DECISION_REGISTER.md

**Template ID:** `CG-AABPP-GOV-016`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Decision authority:** `{{GOVERNANCE_BODY}}`  
**Policy:** Append and supersede; never silently rewrite approved decision history.

## 1. Decision classes

| Class | Examples | Authority | Can an implementation agent decide? |
|---|---|---|---|
| `PRODUCT_CONFIRMED` | CPD-001..023 | Product Concept Brief/change authority | No |
| `FOUNDER_RATIFIED` | RPD-001..040 | Founder/Steering change control | No |
| `ARCHITECTURE_ADR` | Boundary, pattern, supported version, scale trigger | Architecture authority within higher decisions | Only when the task explicitly authorizes an ADR |
| `DELIVERY_OPERATIONAL` | Sequence, branch, rollout mechanics, test fixture | Delivery/release owner | Yes within task scope and approved constraints |
| `TEST_DERIVED` | Query/worker/partition threshold from evidence | Named owner and repeatable test | Agent may recommend; owner approves if contract/cost changes |
| `COMPLIANCE_VERIFIED` | Current Indonesia tax/payroll/legal interpretation | Legal/Finance/HR SME | No; agent records dated evidence only |

Repository discovery facts are not decisions. Record facts in context/discovery reports. Do not create an ADR merely to memorialize an observed package version.

## 2. Protected decision baseline

- CPD-001..023 and RPD-001..040 are binding.
- RPD-022 grants Supreme Admin absolute CRUD; no tamper-proof or absolute-immutability claim is permitted.
- RPD-034 removes external pilot; RPD-036 defines mandatory internal GA gates.
- RPD-031/RPD-037 make recovery targets contractual and best effort when absent.
- RPD-038 requires non-AI integrations to be custom without generic provider abstraction, while prohibiting tenant source forks.

Any proposed change to these decisions requires a formal change request, full impact analysis, authorized approval, primary/control-document update, migration/compatibility plan, and downstream prompt/document revision before implementation.

## 3. Decision index

| Decision ID | Class | Title | Status | Scope | Owner | Effective date | Supersedes | Record link |
|---|---|---|---|---|---|---|---|---|
| `{{ADR_OR_DECISION_ID}}` | `{{CLASS}}` | `{{TITLE}}` | `{{PROPOSED/APPROVED/REJECTED/SUPERSEDED/DEFERRED}}` | `{{SCOPE}}` | `{{OWNER}}` | `{{DATE_OR_NA}}` | `{{ID_OR_NONE}}` | `{{ANCHOR_OR_PATH}}` |

Only `APPROVED` decisions may control implementation. `DEFERRED` is not permission to choose ad hoc.

## 4. Decision record template

### {{DECISION_ID}} — {{TITLE}}

| Field | Value |
|---|---|
| Class/status | `{{CLASS}} / {{STATUS}}` |
| Date proposed/approved | `{{DATES}}` |
| Decision owner/approvers | `{{VALUES}}` |
| Task/phase/workstream | `{{VALUES}}` |
| Source requirements | `{{IDS_AND_SECTIONS}}` |
| Higher decisions/constraints | `{{CPD_RPD_IDS}}` |
| Related conflicts/assumptions/issues | `{{IDS_OR_NONE}}` |
| Repository evidence | `{{PATHS_COMMANDS_BUILD_LOGS}}` |
| Effective scope/date | `{{VALUE}}` |
| Review/expiry trigger | `{{VALUE_OR_NONE}}` |
| Supersedes/superseded by | `{{IDS_OR_NONE}}` |

#### Context and decision question

`{{FACTUAL_CONTEXT_AND_ONE_DECISION_QUESTION}}`

#### Constraints

- Product/requirement constraints: `{{VALUES}}`.
- Tenant/security/privacy constraints: `{{VALUES}}`.
- Canonical data/finance constraints: `{{VALUES}}`.
- API/integration/compatibility constraints: `{{VALUES}}`.
- Migration/deployment/recovery constraints: `{{VALUES}}`.
- Commercial/contract/legal constraints: `{{VALUES}}`.
- Explicitly forbidden outcomes: `{{VALUES}}`.

#### Options considered

| Option | Description | Benefits | Costs/risks | Compatibility/migration | Evidence |
|---|---|---|---|---|---|
| A | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| B | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |
| C | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` |

#### Decision

Selected option: `{{OPTION}}`.

Binding statement: `{{ONE_UNAMBIGUOUS_IMPLEMENTABLE_RULE}}`

Rationale: `{{WHY_THIS_OPTION_FITS_EVIDENCE_AND_HIGHER_DECISIONS}}`

#### Impact matrix

| Area | Impact | Required follow-up/evidence |
|---|---|---|
| Product/scope/UX | `{{VALUE}}` | `{{VALUE}}` |
| Data/schema/RLS | `{{VALUE}}` | `{{VALUE}}` |
| RBAC/field/record access | `{{VALUE}}` | `{{VALUE}}` |
| Finance/audit/retention | `{{VALUE}}` | `{{VALUE}}` |
| REST/GraphQL/webhook/integration | `{{VALUE}}` | `{{VALUE}}` |
| Performance/scale/observability | `{{VALUE}}` | `{{VALUE}}` |
| Migration/deployment/recovery | `{{VALUE}}` | `{{VALUE}}` |
| Testing/documentation/support | `{{VALUE}}` | `{{VALUE}}` |
| Commercial/legal/compliance | `{{VALUE}}` | `{{VALUE}}` |

#### Guardrails and acceptance

- Must: `{{RULES}}`.
- Must not: `{{RULES}}`.
- Required tests/benchmarks: `{{VALUES}}`.
- Rollback/reversal path: `{{VALUE}}`.
- Success evidence: `{{VALUE}}`.
- Failure/review trigger: `{{VALUE}}`.

#### Implementation propagation

Update: `{{CONTEXT_STATUS_TASK_LEDGER_CHANGE_MANIFEST_ADRS_SCHEMA_API_DATA_FLOW_TRACEABILITY_PROMPTS_RUNBOOKS}}`.

Affected task IDs: `{{VALUES}}`.  
Compatibility/migration tasks: `{{VALUES_OR_NONE}}`.

#### Approval

| Role | Approver | Decision/result | Date/evidence |
|---|---|---|---|
| Product/business | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |
| Architecture/data | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |
| Security/privacy | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` |
| Finance/legal/HR SME | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` |
| Delivery/release | `{{VALUE_OR_NA}}` | `{{VALUE}}` | `{{VALUE}}` |

## 5. Rejected and deferred decisions

Record rejected options and deferred decisions so future agents do not reopen them without new evidence. A deferred record must name the trigger, owner, deadline/gate, and safe interim behavior. If no safe interim behavior exists, dependent work is `BLOCKED`.

## 6. Maintenance rules

1. Stable IDs never change.
2. Change status to `SUPERSEDED`; do not delete history.
3. Link every implementation-changing decision to task, change, tests, and documentation.
4. Redact secrets and tenant data; retain enough evidence for review.
5. A technical convenience cannot override CPD/RPD or conceal an accepted risk.
6. Reconcile approved decisions with context, status, assumptions, conflicts, and prompt package manifest.
