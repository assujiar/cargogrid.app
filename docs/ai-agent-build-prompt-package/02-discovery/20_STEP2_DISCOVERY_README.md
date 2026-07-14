# Step 2 — Repository Discovery and Baseline

**Document ID:** `CG-AABPP-DISC-020`  
**Version:** `0.3.0`  
**Status:** `FINAL_FOR_STEP`  
**Runtime authorization:** Discovery, safe baseline execution, and documentation writes only. No feature, refactor, migration, dependency, configuration, deployment, or production-data mutation.

## 1. Purpose

This package gives a new AI agent a deterministic, evidence-backed way to understand an unknown CargoGrid repository before architecture planning or implementation. It prevents greenfield assumptions from damaging brownfield code, prevents existing defects from being blamed on new work, and prevents “discovery complete” claims without reproducible evidence.

Package-generation completion and runtime execution are different states:

- `PACKAGE_STEP_2_COMPLETE`: prompts 20–34 exist and are validated.
- `RUNTIME_DISCOVERY_NOT_EXECUTED`: prompts exist but no target repository was inspected.
- `RUNTIME_DISCOVERY_IN_PROGRESS`: one or more prompts have evidence, but closure has not passed.
- `RUNTIME_DISCOVERY_VERIFIED`: prompt 34 verified every required artifact against one repository checkpoint.

Step 3 package generation may proceed after this package is complete. Actual feature coding remains forbidden until the target repository reaches `RUNTIME_DISCOVERY_VERIFIED` and later implementation gates authorize code.

## 2. Binding sources

- Master Prompt Step 2 and §§8–21.
- `00-control/01_SOURCE_OF_TRUTH_MATRIX.md`.
- CPD-001..023 and RPD-001..040.
- `01-agent-governance/10_MASTER_AGENT_SYSTEM_PROMPT.md`.
- `01-agent-governance/11_AGENTS.md`.
- Technical Architecture §§1–12, 22–35, 37–39.
- Delivery Plan §§3, 8, 12, 14–18, 20–24, 27, 35.
- UX/Data Design access, performance, state, and accessibility controls.

RPD-022, RPD-034/036, RPD-031/037, and RPD-038 must remain explicit in discovery findings and must not be “corrected” silently.

## 3. Prompt execution order

| Order | Prompt | Runtime output |
|---:|---|---|
| 1 | `21_REPOSITORY_DISCOVERY_PROMPT.md` | `docs/discovery/01_REPOSITORY_INVENTORY.md` |
| 2 | `22_EXISTING_IMPLEMENTATION_AUDIT_PROMPT.md` | `docs/discovery/02_EXISTING_IMPLEMENTATION_AUDIT.md` |
| 3 | `23_TOOLCHAIN_DEPENDENCY_AUDIT_PROMPT.md` | `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` |
| 4 | `24_DATABASE_MIGRATION_AUDIT_PROMPT.md` | `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` |
| 5 | `25_ROUTE_MODULE_INVENTORY_PROMPT.md` | `docs/discovery/05_ROUTE_MODULE_INVENTORY.md` |
| 6 | `26_SECURITY_BASELINE_AUDIT_PROMPT.md` | `docs/discovery/06_SECURITY_BASELINE.md` |
| 7 | `27_TEST_QUALITY_BASELINE_PROMPT.md` | `docs/discovery/07_TEST_QUALITY_BASELINE.md` |
| 8 | `28_PERFORMANCE_BASELINE_PROMPT.md` | `docs/discovery/08_PERFORMANCE_BASELINE.md` |
| 9 | `29_ACCESSIBILITY_UX_BASELINE_PROMPT.md` | `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` |
| 10 | `30_PLACEHOLDER_DEAD_CODE_AUDIT_PROMPT.md` | `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` |
| 11 | `31_TECHNICAL_DEBT_RISK_REGISTER_PROMPT.md` | `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` |
| 12 | `32_GREENFIELD_BROWNFIELD_DECISION_PROMPT.md` | `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` |
| 13 | `33_BASELINE_EVIDENCE_CAPTURE_PROMPT.md` | `docs/discovery/00_EXECUTION_INDEX.md` and `13_BASELINE_EVIDENCE_INDEX.md` |
| 14 | `34_STEP2_CLOSURE_VERIFICATION_PROMPT.md` | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` |

Do not skip forward when a prompt reports `BLOCKED`, `FAILED`, `PARTIALLY_COMPLETE`, or untrusted repository/database state. Resume that prompt from its documented checkpoint.

## 4. Universal pre-flight

Every prompt requires the agent to read repository `AGENTS.md`, `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant build logs, Step 0 controls, and Step 1 governance.

Before commands, capture:

- working directory and repository root;
- branch, HEAD, remotes without embedded credentials, and worktree state;
- ownership of pre-existing changes;
- runtime environment and permission boundaries;
- whether command execution can touch network, caches, generated files, lockfiles, databases, or services.

Never assume npm, a monorepo, a single app, a clean tree, Supabase linkage, or a local database.

## 5. Universal allowed scope

Allowed:

- Read repository files and metadata.
- Run non-destructive inventory commands.
- Run existing lint/typecheck/test/build/audit scripts only after assessing side effects.
- Use isolated/local test services when configured and safe.
- Write or update `docs/discovery/**`, persistent context/ledgers, and task-specific build logs.
- Redact evidence while preserving finding, path, command, timestamp, and classification.

Forbidden:

- Application, test, configuration, migration, seed, generated-type, lockfile, or CI edits.
- Dependency installation, upgrade, removal, deduplication, or lockfile regeneration.
- Migration application, reset, repair, backfill, or database write.
- Secret reveal, token printing, production-data query, cross-tenant probing, or active exploitation.
- Deployment, environment mutation, feature flag change, branch rewrite, commit, push, or PR.
- “Quick fixes” discovered during audit.

If an existing script writes files or data, do not run it until its effects are understood and an isolated disposable target is confirmed. Document the omission and safe alternative.

## 6. Evidence standard

Every finding must include:

| Field | Required content |
|---|---|
| Evidence ID | Stable `EV-S2-<AREA>-NNN` |
| Repository checkpoint | Branch, commit, dirty-state summary |
| Command or inspection | Exact redacted command/path/method |
| Timestamp/environment | ISO 8601 and execution context |
| Result | Exit code, counts, versions, hashes, or concise observed fact |
| Classification | `VERIFIED`, `INFERRED`, `NOT_FOUND`, `NOT_RUN`, `BLOCKED`, or `UNTRUSTED` |
| Impact | Discovery, security, data, finance, performance, delivery, or compatibility effect |
| Follow-up | Task/ADR/test/owner and blocking relationship |

`NOT_FOUND` means the scoped search ran and returned no match. It does not prove global absence. `NOT_RUN` must state why. `INFERRED` must identify the evidence and uncertainty.

## 7. Evidence safety

- Never store secret values, connection strings, signed URLs, cookies, tokens, private keys, personal data, payroll/tax/bank records, or live tenant payloads.
- Record secret variable names, locations, classifications, exposure path, and rotation requirement without values.
- Hash evidence files only when doing so does not read prohibited data into an unsafe output.
- Do not paste entire logs when a minimal redacted excerpt and artifact reference are sufficient.
- Treat Supreme Admin absolute CRUD as a ratified risk; report actual implementation faithfully and never claim tamper-proof audit/ledger behavior.

## 8. Common stop conditions

Stop and record an Error/Issue Ledger entry when:

- repository root or checkpoint cannot be established;
- worktree changes overlap discovery documentation and ownership is unclear;
- a command unexpectedly mutates files, services, data, lockfiles, or generated artifacts;
- a credential or real tenant record is exposed;
- an environment appears to be production or linked to production data;
- migration/application state is partially applied or unknown;
- evidence contradicts a protected product decision or reveals a critical tenant/security/finance defect;
- repository or database trust is lost.

## 9. Runtime closure gate

Prompt 34 may set `RUNTIME_DISCOVERY_VERIFIED` only when:

- outputs 01–14 exist, are non-empty, and reference one reconciled checkpoint;
- package manager/framework/dependency facts are verified from manifests and lockfiles;
- database/migration state is classified without database mutation;
- routes/modules/contracts and existing implementation status are inventoried;
- security, tests, performance, accessibility, dead code, and debt have evidence and limitations;
- greenfield/brownfield classification is approved from evidence;
- pre-existing failures are separated from unexecuted checks;
- critical risks and blockers are in persistent ledgers;
- no feature/code/config/migration/dependency change occurred;
- context, build status, task ledger, evidence index, and handoff agree.

## 10. Package completion

This directory is complete when all 15 files are present, structurally valid, individually executable, and represented in the control manifest. The next package-generation command is `LANJUT STEP 3`; it does not itself authorize repository implementation.
