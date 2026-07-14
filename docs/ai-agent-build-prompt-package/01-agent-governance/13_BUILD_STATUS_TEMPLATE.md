# CARGOGRID_BUILD_STATUS.md

**Template ID:** `CG-AABPP-GOV-013`  
**Template version:** `0.2.0`  
**Updated:** `{{ISO_8601_WITH_TIMEZONE}}`  
**Updated by:** `{{AGENT_OR_OWNER}}`  
**Last verified commit:** `{{SHA_OR_NONE}}`  
**Build trust:** `{{TRUSTED | DEGRADED | UNTRUSTED}}`

> This is the single current-state dashboard. Use only approved task states: `NOT_STARTED`, `READY`, `IN_PROGRESS`, `BLOCKED`, `FAILED`, `PARTIALLY_COMPLETE`, `COMPLETED`, `VERIFIED`, `ROLLED_BACK`, `SUPERSEDED`.

## 1. Current checkpoint

| Field | Value |
|---|---|
| Package/repository version | `{{VALUE}}` |
| Current phase/workstream | `{{VALUE}}` |
| Active task | `{{TASK_ID_NAME}}` |
| Active task status | `{{STATUS}}` |
| Branch | `{{BRANCH}}` |
| HEAD | `{{SHA}}` |
| Last known good commit | `{{SHA}}` |
| Schema/migration head | `{{VALUE}}` |
| Latest environment verified | `{{ENVIRONMENT}}` |
| Last full green gate | `{{BUILD_LOG_AND_DATE}}` |
| Active blockers | `{{NONE_OR_IDS}}` |
| Next eligible task | `{{TASK_ID_OR_NONE}}` |

Checkpoint summary: `{{ONE_PARAGRAPH_FACTUAL_SUMMARY}}`.

## 2. Discovery and foundation readiness

| Gate | Status | Evidence | Owner | Blocks |
|---|---|---|---|---|
| Source and decision controls | `{{STATUS}}` | `{{REF}}` | Product | All work |
| Repository discovery | `{{STATUS}}` | `{{REF}}` | Architecture | Feature code |
| Greenfield/brownfield decision | `{{STATUS}}` | `{{REF}}` | Architecture | Target plan |
| Environment/toolchain baseline | `{{STATUS}}` | `{{REF}}` | DevEx | Reliable gates |
| Database/migration baseline | `{{STATUS}}` | `{{REF}}` | Data | Schema changes |
| Security/access baseline | `{{STATUS}}` | `{{REF}}` | Security | Tenant features |
| Test/performance/accessibility baseline | `{{STATUS}}` | `{{REF}}` | QA | Before/after evidence |

## 3. Phase status

All rows are internal build/acceptance phases. No row alone authorizes external pilot or partial GA.

| Phase | Scope | Status | Completion | Gate evidence | Open blockers | Next task |
|---:|---|---|---:|---|---|---|
| 0 | Discovery and Foundation | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 1 | Platform Core | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 2 | Commercial | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 3 | Operations | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 4 | Finance | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 5 | Advanced TMS/WMS | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 6 | Procurement/Vendor | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 7 | HRIS/Ticketing | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 8 | Customer Portal/Loyalty | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 9 | Intelligence/Enterprise | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 15 | Full-system hardening | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |
| 16 | RC and Go-live | `{{STATUS}}` | `{{PERCENT}}` | `{{REF}}` | `{{IDS}}` | `{{ID}}` |

## 4. Workstream status

| Workstream | Status | Last verified capability | Evidence | Active task | Blocker |
|---|---|---|---|---|---|
| Product/requirements/traceability | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| Architecture/repository | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| Database/RLS/RBAC | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| Configuration/workflow/approval | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| REST/GraphQL/integration/jobs | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| UX/design/accessibility | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| Domain modules | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| QA/regression/performance | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| DevSecOps/observability/recovery | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |
| Documentation/onboarding/support | `{{STATUS}}` | `{{VALUE}}` | `{{REF}}` | `{{ID}}` | `{{ID_OR_NONE}}` |

## 5. Current gate results

| Gate | Baseline | Current result | Delta | Command/evidence | Status |
|---|---|---|---|---|---|
| Lint | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| Typecheck | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| Unit/integration | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| Build | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| DB/migrations | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| RLS/RBAC/field/cross-tenant | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| API contracts | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| E2E/smoke | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |
| Performance/accessibility/security | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{REF}}` | `{{STATUS}}` |

Failed mandatory gates prevent `COMPLETED` or `VERIFIED` status. A pre-existing failure must link baseline evidence and an Error Ledger entry.

## 6. Schema and deployment state

| Environment | Deployed commit | Migration head | Smoke status | Data/recovery note | Last checked |
|---|---|---|---|---|---|
| Local | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{NOTE}}` | `{{TIME}}` |
| Development | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{NOTE}}` | `{{TIME}}` |
| Testing | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{NOTE}}` | `{{TIME}}` |
| Staging | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{NOTE}}` | `{{TIME}}` |
| UAT | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{NOTE}}` | `{{TIME}}` |
| Production | `{{SHA}}` | `{{VALUE}}` | `{{STATUS}}` | `{{CONTRACT_RPO_RTO_OR_BEST_EFFORT}}` | `{{TIME}}` |

## 7. Blockers, errors, and known issues

| ID | Type | Severity | Affected scope | Owner | Workaround/recovery | Release effect | Source ledger |
|---|---|---|---|---|---|---|---|
| `{{ID}}` | `{{BLOCKER/ERROR/ISSUE/RISK}}` | `{{SEVERITY}}` | `{{SCOPE}}` | `{{OWNER}}` | `{{VALUE}}` | `{{BLOCKS_WHAT}}` | `{{REF}}` |

Do not duplicate full evidence here; link `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, decisions, and build logs.

## 8. Release-readiness summary

| Readiness domain | Status | Blocking evidence/remaining gate |
|---|---|---|
| All ten module suites | `{{STATUS}}` | `{{REF}}` |
| Requirement traceability | `{{STATUS}}` | `{{REF}}` |
| Tenant/security | `{{STATUS}}` | `{{REF}}` |
| Finance/data integrity | `{{STATUS}}` | `{{REF}}` |
| E2E/regression | `{{STATUS}}` | `{{REF}}` |
| Migration/backup/DR | `{{STATUS}}` | `{{REF}}` |
| Performance/accessibility/browser | `{{STATUS}}` | `{{REF}}` |
| Observability/support/onboarding/docs | `{{STATUS}}` | `{{REF}}` |
| Go/no-go approval | `{{STATUS}}` | `{{REF}}` |

External pilot is not a release stage. Direct GA requires the entire table to be `VERIFIED` with zero open Sev-1/critical defects.

## 9. Next action

- Next eligible task: `{{TASK_ID_AND_NAME}}`.
- Entry conditions: `{{CONDITIONS}}`.
- Required prompt/build log: `{{PATH}}`.
- If blocked, resume task: `{{RESUME_TASK_ID_OR_NONE}}`.
- Authorized command: `{{EXACT_COMMAND_OR_NONE}}`.

## 10. Update rules

Update this file after every atomic task, rollback, deployment, migration, gate change, blocker change, or checkpoint. Reconcile it with `TASK_LEDGER.md`, build logs, change manifest, error/issue ledgers, and environment evidence. Never mark progress by subjective percentage alone; the evidence link controls the status.
