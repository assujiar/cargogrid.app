# AGENTS.md — CargoGrid Repository Operating Rules

**Document ID:** `CG-AABPP-GOV-011`  
**Version:** `0.2.0`  
**Status:** `FINAL_FOR_STEP`  
**Placement:** Copy to repository root during the authorized foundation step. A nested `AGENTS.md` may impose stricter, directory-specific controls.

## Mission

Work on one authorized CargoGrid task at a time. Preserve existing behavior, user changes, tenant isolation, canonical data, financial correctness, API compatibility, migration safety, and persistent project context. This repository must remain restartable by an agent with no access to previous chat.

## Instruction precedence

1. System and operator instructions.
2. This file and applicable nested `AGENTS.md`.
3. `00-control/02_CONFIRMED_DECISION_REGISTER.md` and `04_CONFLICT_REGISTER.md`.
4. Approved ADRs and task prompt.
5. Existing repository conventions discovered from code and scripts.

Never use an implementation artifact as implicit permission to contradict a ratified decision.

## Required pre-flight

Before any edit:

- Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, and `KNOWN_ISSUES.md`.
- Read the relevant build log, requirement IDs, decision rows, ADRs, schema/API/data-flow records, and task prompt.
- Inspect `git status`, current branch, recent relevant history, package manager, scripts, framework versions, migrations, generated files, and focused tests.
- Preserve unrelated dirty-worktree changes. Never reset, discard, or overwrite user changes.
- Capture a relevant baseline before changing behavior.
- Stop if Step 2 repository discovery is incomplete and the request is feature implementation.

## File and search discipline

- Use fast repository search and file inventories before opening broad trees.
- Edit only paths authorized by the task. If a required dependency is outside scope, record it and request/schedule a separate task.
- Do not create duplicate utilities, schemas, entities, clients, or policy engines because an existing implementation was not searched thoroughly.
- Do not hand-edit generated files unless repository policy explicitly requires it; regenerate from the authoritative source.
- Do not add empty stubs, dead routes, fake API responses, placeholder actions, demo-only persistence, or unresolved TODOs to a completed task.

## Branch, commit, and checkpoint rules

- One branch and one business capability per atomic task unless the task explicitly states otherwise.
- Keep commits intentional and reviewable. Do not mix formatting sweeps or unrelated upgrades.
- Record branch, commit, last known good commit, migration state, and gate results in the task build log and ledger.
- Never rewrite shared history or use destructive Git commands without explicit authorization.
- A task is not a valid checkpoint until documentation and evidence are committed or otherwise durably recorded.

## Scope and refactoring

- Default task size: one feature slice, one module boundary, 1–3 migrations, approximately 5–15 changed files.
- Broad refactors, framework upgrades, shared-schema redesign, API version changes, or destructive migrations require dedicated prompts and ADR/change control.
- Fix only task-caused failures. Log unrelated/pre-existing failures and create a separate recovery task.
- Preserve backward compatibility using additive or expand-and-contract changes where risk warrants it.

## Stack baseline

- Next.js App Router, React, TypeScript strict mode.
- Server Components by default for sensitive/data-heavy views; Client Components at interaction boundaries.
- Supabase Auth, PostgreSQL, RLS, Storage; Realtime and Edge Functions selectively.
- Vercel baseline and separate Local/Development/Testing/Staging/UAT/Production environments.
- Shared schema with RLS by default; PostGIS enabled from Platform Core.
- PostgreSQL durable queue first; separate workers only by measured need.
- REST `/v1` and GraphQL public surfaces developed together.

Repository discovery determines exact supported versions and commands. Do not upgrade merely because a newer version exists.

## Tenant, authorization, and secrets

- Tenant context must be enforced in database, server reads/writes, jobs, storage, reports, search, cache, REST, GraphQL, exports, and integrations.
- RLS is mandatory for tenant-scoped tables unless an approved tested compensating control exists.
- UI visibility is not authorization. Enforce action, scope, record, field, status, value, export, print, and masking policy server-side.
- Service-role credentials are server-only. Secrets belong in environment/secret management and must never enter source, fixtures, logs, or client bundles.
- Support access is purpose/time-bound, logged, tenant-visible, and revocable.
- MFA is mandatory for privileged roles specified by RPD-023.
- Every upload is scanned before release to another user.

## Supreme Admin risk rule

Supreme Admin has ratified absolute CRUD, including audit and ledger records. Do not weaken that authority silently, and do not claim tamper-proof or absolute immutability. Normal roles still use ledger, reversal, period-lock, soft-delete, and retention controls. All prompts and product/security documentation must disclose the exception.

## Database and migration rules

- Inspect schema and applied history before writing migrations.
- Never edit an applied migration; add a new migration.
- Include tenant-aware indexes, RLS, foreign keys, unique/check constraints, data classification, backfill, generated types, clean rebuild, upgrade, preservation, and rollback/recovery checks as relevant.
- Destructive changes require explicit approval, dependency analysis, backup, staging rehearsal, reconciliation, and recovery evidence.
- Never use broad service-role bypass to avoid correct RLS or migration design.
- Do not commit real tenant data.

## Data and finance rules

- Reuse canonical data and retain lineage. Do not re-key valid customer, shipment, vendor, address, service, rate, employee, finance, ticket, or loyalty information.
- Configuration changes are versioned/effective-dated; critical transactions retain the applied version unless an approved migration rule runs.
- Normal financial posting must be balanced, idempotent, period-aware, reversible/adjustable, reconcilable, and duplicate-safe.
- Normal inventory and loyalty changes use ledgers.
- Indonesia tax/payroll logic requires current, dated SME/legal evidence and must remain configurable.
- Retention follows RPD-025, subject to the disclosed Supreme Admin exception.

## API, integration, and jobs

- Maintain REST/GraphQL authorization, masking, audit, compatibility, and test parity.
- Do not change API, GraphQL, webhook, export, event, or DB contracts without versioning/compatibility and downstream analysis.
- Retriable mutations and deliveries require idempotency, bounded retries, observability, and dead-letter/recovery paths.
- Non-AI third-party connectors are case-by-case custom implementations without a generic provider abstraction, but must remain reusable shared product code and never tenant forks.
- Heavy imports, exports, reports, document generation, and batch processing run asynchronously.

## UX, performance, and accessibility

- Implement complete states: loading, empty, error, success, denied, degraded, validation, and unsaved changes.
- Internal ERP is desktop-first responsive; customer/field flows are mobile-friendly online-first PWA.
- Use server-side filter/sort/search/pagination; cursor pagination for high-volume streams. Never load an entire large dataset into the browser or use `SELECT *` in transactional APIs.
- Live dashboard queries require read-only access, budgets, timeout, pagination, and caching. Add replicas/read models only after measured thresholds or an approved performance task.
- Conform to WCAG 2.2 AA and the supported browser matrix.
- White-label changes presentation within approved tokens; do not fork component structure per tenant.

## Test and gate policy

Detect the package manager and run repository-provided equivalents of lint, typecheck, tests, and build. Add focused database, migration, RLS, RBAC, field/record access, cross-tenant negative, contract, E2E, accessibility, performance, security, smoke, and regression gates according to risk.

Do not disable tests/rules or modify assertions merely to hide failures. Separate pre-existing failures with baseline evidence. A failed mandatory gate means the task is not complete.

## Documentation required for completion

Update the persistent context files and relevant build log, change manifest, regression/traceability matrices, schema/API/data-flow/dependency records, decisions, assumptions, errors, issues, user/admin/API/support docs, runbooks, and release notes as applicable.

Use the templates in `01-agent-governance/` until repository-native instances exist.

## Stop and escalate when

- A task would weaken tenant isolation, authorization, canonical data, financial controls, retention disclosure, or recovery safety.
- Source requirements conflict and the conflict is not already resolved.
- The working tree contains overlapping user changes that cannot be preserved safely.
- A migration is destructive without authorization/evidence.
- Required credentials, environment, legal/SME evidence, or upstream contracts are missing.
- Repository or database state is no longer trustworthy.

Record a `BLOCKED` task, error/issue evidence, last known good checkpoint, allowed repair scope, and next safe action.

## Required final report

Report outcome first, then task status, baseline, changed files, migrations/contracts/routes, commands and exact results, security/tenant/finance/regression/performance/accessibility evidence, documentation, errors/issues/risks, rollback/recovery, last known good checkpoint, and next eligible task.

Never label a task, phase, or product complete beyond the evidence actually obtained.
