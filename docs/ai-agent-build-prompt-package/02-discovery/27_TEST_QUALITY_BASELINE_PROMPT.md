# Prompt 27 — Test, Build, and Quality Baseline

**Prompt ID:** `CG-S2-DISC-007`  
**Package document:** `CG-AABPP-DISC-027`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** QA, regression, and executable baseline  
**Runtime output:** `docs/discovery/07_TEST_QUALITY_BASELINE.md`

## Objective and business value

Inventory the existing test architecture and execute the safest available baseline gates without modifying source, generated artifacts, snapshots, lockfiles, services, or real data. Separate passing, failing, skipped, flaky, not-run, and unavailable evidence so future changes can be compared honestly.

## Source requirements

- Master Prompt §§11, 15–18, 20–21 and Step 2.
- CPD-004/006/007/017–023; RPD-001/022/024/032/033/036/039.
- GOV-010 quality/documentation/failure rules; GOV-011 test policy.
- Delivery Plan §§14–23, 27, 35.
- Technical Architecture §§27–32, 38.

## Preconditions and authorization

Prompts 21–26 are complete at one checkpoint. Prompt 23 provides verified package manager and script side effects; prompt 24 classifies database safety. Execute only existing commands safe for the current isolated environment. Write discovery docs, persistent ledgers/status, and command logs only.

Forbidden: changing tests/snapshots/config/source, installing browsers/dependencies, starting production-linked services, resetting/applying migrations, seeding non-disposable DBs, audit fixes, or suppressing failures.

## Mandatory pre-flight

1. Reconfirm HEAD/worktree; capture baseline file hashes/status.
2. Inventory test configs, scripts, fixtures, coverage config, CI matrices, environment requirements, sharding, retries, skip/quarantine policy, and artifact paths.
3. Classify every candidate command by writes, network, database, service, duration, and secret requirements.
4. Confirm test data is synthetic and target services are local/disposable.
5. If safety is uncertain, mark `NOT_RUN` with reason; do not improvise.

## Detailed tasks

### A. Test inventory

Inventory unit, component, integration, API contract, GraphQL, database constraint, migration, RLS, RBAC, field/record, cross-tenant negative, auth/session/MFA, audit, file access, job/retry/idempotency, import/export, finance, E2E, accessibility, performance, smoke, regression, and UAT evidence.

Record framework/config, file count, naming convention, ownership, fixtures/mocks, environment, and CI usage. Identify disabled/skipped/only/focus tests, stale snapshots, broad mocks, and tests that assert UI only while bypassing persistence/security.

### B. Baseline execution sequence

Use the verified package manager and repository scripts. Prefer:

1. Read-only/config validation.
2. Lint.
3. Typecheck.
4. Focused/unit tests.
5. Integration/contract tests against disposable services.
6. Build.
7. E2E/smoke only when browser/services already exist and are isolated.
8. Database/security/access/finance/performance/accessibility commands only when their prerequisites are safe.

Do not use generic npm commands when the repository uses another manager. Do not auto-install missing tooling.

### C. Result capture

For each command record exact redacted command, cwd/workspace, start/end/duration, exit code, test counts, pass/fail/skip/flaky/retry, coverage if produced, artifact path, environment, and worktree before/after. A timeout or crash is a failure result, not “not run.”

### D. Coverage and risk gaps

- Map tests to requirement/domain/control families and critical E2E flows.
- Identify missing negative tenant tests, field/export/search/report access, REST/GraphQL parity, migration upgrade/rebuild, finance balance/idempotency/lock/reversal/reconciliation, file scan/signed URL, job retry/DLQ, PWA/browser/accessibility, and direct-GA gates.
- Distinguish pre-existing failures from missing tests and from commands not safe to run.

### E. Baseline trust

Classify baseline:

- `GREEN`: mandatory safe gates pass.
- `AMBER`: bounded failures/gaps with trusted repository and isolated evidence.
- `RED`: critical gate, tenant/security/finance, migration, or build failure.
- `UNKNOWN`: required gates cannot be run safely or evidence is inconsistent.

This classification does not authorize fixes.

## Required output structure

1. Checkpoint, environment, prerequisites, limitations.
2. Test/config/script/fixture/CI inventory.
3. Test-type and requirement/control coverage matrix.
4. Command side-effect approval table.
5. Chronological command result table with exit codes/durations/counts.
6. Pass/fail/skip/flaky/quarantine analysis.
7. Pre-existing failure register linked to Error Ledger.
8. Critical coverage gaps and separate follow-up tasks.
9. Baseline trust classification and exact last-green scope.
10. Worktree before/after proof, artifacts, evidence IDs, output hash.

## Acceptance criteria and Definition of Done

- Every existing test family/config/script is inventoried.
- Every run/not-run decision has side-effect evidence.
- Exact results are recorded without hiding failures or changing tests.
- Baseline failures and coverage gaps are separated.
- No source/test/config/snapshot/generated/lock/database/external-state change occurred.
- Persistent docs, Error/Issue Ledger, Task Ledger, Build Status, and handoff are reconciled.

## Failure and recovery

If a command writes unexpected files/data, terminate safely, capture worktree/database evidence, preserve user changes, ledger the error, and restore trust through an authorized recovery task. Do not delete generated differences blindly.

## Completion and next prompt

Report baseline classification, command results, test counts, critical gaps/failures, artifacts, files written, trust state, and next prompt.

Next: `CG-S2-DISC-008` — Performance Baseline.
