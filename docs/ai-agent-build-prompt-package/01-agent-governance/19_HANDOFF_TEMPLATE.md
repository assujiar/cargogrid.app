# CargoGrid Agent Handoff

**Template ID:** `CG-AABPP-GOV-019`  
**Template version:** `0.2.0`  
**Handoff ID:** `HO-{{YYYYMMDD}}-{{SEQ}}`  
**Created:** `{{ISO_8601_WITH_TIMEZONE}}`  
**From/To:** `{{OUTGOING_AGENT_OR_OWNER}} → {{INCOMING_AGENT_OR_ROLE}}`  
**Trust status:** `{{TRUSTED | DEGRADED | UNTRUSTED}}`

> The incoming agent must be able to continue without chat history. Use exact paths, IDs, commits, migration states, commands, and evidence. Redact secrets and tenant data.

## 1. Outcome first

Current outcome: `{{WHAT_IS_TRUE_NOW}}`.

Current task status: `{{STATUS}}`.  
Safe to continue: `{{YES | NO | ONLY_WITH_CONDITIONS}}`.  
Immediate blocker/condition: `{{NONE_OR_VALUE}}`.

## 2. Mandatory reading order

1. Repository `AGENTS.md` and nested instructions.
2. `CARGOGRID_CONTEXT.md`.
3. `CARGOGRID_BUILD_STATUS.md`.
4. `TASK_LEDGER.md` and active task record.
5. Relevant source requirements, CPD/RPD decisions, conflict resolutions, ADRs, and prompt.
6. Relevant build log and change manifest entry.
7. `ERROR_LEDGER.md` and `KNOWN_ISSUES.md` entries listed below.
8. Schema/API/data-flow/module maps affected by this work.

Do not edit feature code if Step 2 discovery is not `VERIFIED`.

## 3. Checkpoint

| Field | Exact value/evidence |
|---|---|
| Repository/working directory | `{{VALUE}}` |
| Branch | `{{VALUE}}` |
| HEAD | `{{SHA}}` |
| Last known good commit | `{{SHA}}` |
| Dirty worktree | `{{CLEAN_OR_PATHS_AND_OWNERSHIP}}` |
| Package manager/runtime | `{{VALUE}}` |
| Current schema/migration head | `{{VALUE}}` |
| Environment/deployment | `{{VALUE}}` |
| Last fully passing gate/build log | `{{REF}}` |
| Backup/snapshot/recovery point | `{{VALUE_OR_NONE}}` |
| Trust boundary | `{{WHAT_IS_AND_IS_NOT_TRUSTED}}` |

Never discard dirty files unless their ownership and authorized rollback are explicit.

## 4. Active task

| Field | Value |
|---|---|
| Task ID/name | `{{VALUE}}` |
| Phase/workstream | `{{VALUE}}` |
| Prompt path/version | `{{VALUE}}` |
| Objective | `{{VALUE}}` |
| Source requirements/decisions | `{{IDS}}` |
| Status | `{{STATUS}}` |
| Allowed paths | `{{PATHS}}` |
| Forbidden paths | `{{PATHS}}` |
| Upstream dependencies | `{{IDS_AND_STATES}}` |
| Downstream consumers | `{{VALUES}}` |
| Build log/change entry | `{{PATHS_OR_IDS}}` |

## 5. Work completed

- Implemented safely: `{{CAPABILITIES}}`.
- Files changed: `{{PATHS_OR_CHANGE_MANIFEST_REF}}`.
- Migrations created/applied: `{{IDS_AND_ENVIRONMENTS}}`.
- REST/GraphQL/webhook/job contracts: `{{VALUES}}`.
- UI/routes/states: `{{VALUES}}`.
- Security/RLS/RBAC/field/record changes: `{{VALUES}}`.
- Data/finance/audit changes: `{{VALUES}}`.
- Documentation updated: `{{PATHS}}`.
- Commit(s): `{{SHAS}}`.

Do not repeat already completed work unless evidence shows it is invalid.

## 6. Remaining or failed work

| Item | State | Exact evidence | Why incomplete | Safe next action |
|---|---|---|---|---|
| `{{VALUE}}` | `{{NOT_STARTED/PARTIALLY_COMPLETE/BLOCKED/FAILED}}` | `{{REF}}` | `{{VALUE}}` | `{{VALUE}}` |

Files already modified but not verified: `{{PATHS_OR_NONE}}`.

Migration state: `{{NOT_CREATED | CREATED_NOT_APPLIED | PARTIALLY_APPLIED | APPLIED | ROLLED_BACK | UNKNOWN}}`. If `PARTIALLY_APPLIED` or `UNKNOWN`, do not proceed until database trust is restored.

## 7. Tests and gates

| Gate | Command/evidence | Baseline | Current result | Must rerun? |
|---|---|---|---|---|
| Focused tests | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| Lint/typecheck/build | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| DB/migrations/types | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| Tenant/RLS/RBAC/field/access | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| REST/GraphQL/contracts/E2E | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| Finance/data/regression | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |
| Performance/accessibility/security | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` | `{{YES/NO}}` |

Pre-existing failures: `{{NONE_OR_ERROR_IDS_WITH_BASELINE}}`.  
Change-caused failures: `{{NONE_OR_ERROR_IDS}}`.

## 8. Errors, issues, decisions, and risks

| ID | Type/status | Summary | Required handling |
|---|---|---|---|
| `{{ID}}` | `{{ERROR/ISSUE/DECISION/ASSUMPTION/RISK}} / {{STATUS}}` | `{{SUMMARY}}` | `{{VALUE}}` |

Always preserve these standing decisions where relevant:

- RPD-022 Supreme Admin absolute CRUD means no tamper-proof/absolute-immutability claim.
- RPD-034/036 direct GA requires full internal gates and zero critical defects.
- RPD-031/037 contract-silent recovery is best effort without guarantee.
- RPD-038 custom non-AI connectors have no generic provider abstraction and no tenant forks.

## 9. Recovery and rollback

- Last trusted checkpoint: `{{VALUE}}`.
- Rollback trigger/authority: `{{VALUE}}`.
- Code revert path: `{{VALUE}}`.
- Migration/data recovery path: `{{VALUE}}`.
- Feature flag/containment: `{{VALUE}}`.
- Reconciliation required: `{{VALUE}}`.
- Recovery verification gates: `{{VALUE}}`.
- Actions that must not be taken: `{{VALUE}}`.

## 10. Resume instructions

1. Confirm repository, branch, commit, worktree, and schema match the checkpoint above.
2. Read all listed records; do not rely on this handoff alone for requirement detail.
3. Re-run `{{FIRST_SAFE_BASELINE_COMMANDS}}`.
4. Verify `{{CRITICAL_PRECONDITIONS}}`.
5. Continue only within `{{ALLOWED_REPAIR_OR_IMPLEMENTATION_SCOPE}}`.
6. Do not touch `{{FORBIDDEN_PATHS_OR_CONTRACTS}}`.
7. Execute remaining steps: `{{ORDERED_STEPS}}`.
8. Run re-verification gates: `{{COMMANDS}}`.
9. Update persistent context, ledgers, build log, change manifest, and this handoff/checkpoint.

First safe command/action: `{{EXACT_COMMAND_OR_READ_ACTION}}`.

## 11. Next task sequence

| Order | Task ID | Entry condition | Objective | Stop condition |
|---:|---|---|---|---|
| 1 | `{{ID}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |
| 2 | `{{ID}}` | `{{VALUE}}` | `{{VALUE}}` | `{{VALUE}}` |

Next authorized package/repository command: `{{EXACT_COMMAND_OR_NONE}}`.

## 12. Handoff validation

- [ ] Incoming agent can locate every referenced file and ID.
- [ ] Branch, commit, dirty files, migration state, and environment are exact.
- [ ] Completed work is distinguished from partial/failed work.
- [ ] Tests passed, failed, and not run are explicit.
- [ ] Tenant/security/data/finance/contract impact is explicit.
- [ ] Errors/issues/risks and accepted decision exceptions are linked.
- [ ] Recovery and forbidden actions are actionable.
- [ ] First safe action and next task are unambiguous.
- [ ] No secret, token, credential, or tenant data is present.

Handoff accepted by/date: `{{VALUE_OR_PENDING}}`.
