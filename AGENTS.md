# AGENTS.md — CargoGrid Repository Operating Rules

**Instance of:** `CG-AABPP-GOV-011` (template `docs/ai-agent-build-prompt-package/01-agent-governance/11_AGENTS.md`)
**Instance version:** `0.3.1` (2026-09-02 — corrected §"UX, performance, and accessibility"'s "PWA" wording to "responsive web app," per `ISS-2026-245` and the RPD-004 amendment note in `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` §4a; no manifest/service-worker/installability requirement was ever built or is now intended; no existing rule weakened or removed). Prior: `0.3.0` (2026-08-07 — added "Execution cadence (batched review, from Prompt 257)" and its cross-references, per `docs/adr/ADR-0021-batched-review-and-fix-execution-cadence.md`; no existing rule weakened or removed)
**Status:** `ACTIVE` (repository-native instance)
**Instantiated:** 2026-07-14T09:58:59+07:00 by runtime agent during Step 2 Prompt 21 (Repository Discovery)
**Persistent context location:** `docs/runtime/` (`CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `CHANGE_MANIFEST.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, `HANDOFF.md`) — ratified as canonical by reconciliation `CG-S2-DISC-001-R1` (`docs/runtime/CHANGE_MANIFEST.md` `CHG-2026-002`) after a repo-root duplicate set caused a merge collision. Do not recreate a competing context set at repo root; see `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-002` (single-writer discipline).

## Mission

Work on one authorized CargoGrid task at a time. Preserve existing behavior, user changes, tenant isolation, canonical data, financial correctness, API compatibility, migration safety, and persistent project context. This repository must remain restartable by an agent with no access to previous chat.

## Instruction precedence

1. System and operator instructions.
2. This file and applicable nested `AGENTS.md`.
3. `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` and `04_CONFLICT_REGISTER.md`.
4. Approved ADRs and task prompt.
5. Existing repository conventions discovered from code and scripts.

Never use an implementation artifact as implicit permission to contradict a ratified decision.

## Required pre-flight

Before any edit, read the repository-native persistent context under `docs/runtime/`:

- `docs/runtime/CARGOGRID_CONTEXT.md`
- `docs/runtime/CARGOGRID_BUILD_STATUS.md`
- `docs/runtime/TASK_LEDGER.md`
- `docs/runtime/CHANGE_MANIFEST.md`
- `docs/runtime/ERROR_LEDGER.md`
- `docs/runtime/KNOWN_ISSUES.md`
- `docs/runtime/HANDOFF.md`

The canonical decision/assumption/conflict registers live under `docs/ai-agent-build-prompt-package/00-control/` (`02_CONFIRMED_DECISION_REGISTER.md`, `03_ASSUMPTION_REGISTER.md`, `04_CONFLICT_REGISTER.md`).

**Pre-flight collision check (`ISS-2026-002`, mandatory before starting any Phase 0+ prompt — see `docs/git/GIT_STRATEGY.md` §7):** list open pull requests and branches for this repository (GitHub API/MCP); if another open PR or a branch with unmerged commits targets the same task-ID range this session is about to work on, stop and surface it — do not proceed in parallel. This exact check was skipped 5 times in this repository's history (`docs/runtime/KNOWN_ISSUES.md` `ISS-2026-002`) and caused real content corruption (`ERR-2026-001..003`). Locally, `pnpm run git:check` covers the checkable half (diverged local branches, dirty worktree) — it does not replace the GitHub-side check.

Then:

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

## Execution cadence (batched review, from Prompt 257)

Ratified by `docs/adr/ADR-0021-batched-review-and-fix-execution-cadence.md`. Full protocol: `docs/standards/BUILD_EXECUTION_PROTOCOL.md`. Prompts 220–256 ran a full adversarial review after every prompt and remain `VERIFIED` under that cadence; from Prompt 257 the review round is batched.

- **Tier A — every prompt, automated, blocking.** `typecheck`, `lint`, `db:test`, `test`, `git:check-paths`, `security:check`; plus `next build` whenever the prompt touches `app/`, `components/`, or a `"use server"` module.
- **Tier B — every prompt, blocking.** Walk `docs/standards/RECURRING_DEFECT_TAXONOMY.md` §4 against your own diff and record the result in the prompt's build log. This is the control that makes batching safe. A prompt that skips it is not complete regardless of Tier A.
- **Tier C — every batch of at most five prompts.** Four parallel review lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/concurrency, live-tested; cross-prompt integration and data dependency), then a fix pass with a mandatory propagation sweep, then a full gate suite re-run independently by the orchestrating session — never accepted on a fix agent's self-report.
- **Plan the batches before writing code.** State the split in the first response to an operator range. Five is a ceiling, never a quota.
- **Cut the batch short immediately** on any Critical/High finding, a first-of-its-kind security mechanism, any prompt touching finance posting / the RBAC evaluator / RLS primitives / auth, a destructive migration, a Tier A failure that cannot be cleared in-prompt, or wherever the dependency graph would put a consumer in a different batch from its producer.
- **Never batch** phase Integrated Verification / Hardening / Documentation / Closure prompts, Step 15 hardening (368–389), Step 16 release (390–412), or Step 17 validation (413–430) prompts.
- **`COMPLETED` now means adversarially unreviewed.** Only the batch's Tier C close moves prompts to `VERIFIED`, and a batch is all-or-nothing.
- **Batch size is adaptive:** 5 after a clean batch, at most 4 after one Critical/High finding, at most 3 after two or more until a batch closes clean.
- **The prompt files themselves are not edited and do not need to be.** All 430 remain valid as written; they specify *what* to build and *what* gates apply, never *how often* review runs. The one exception is the §36 clause carried by 166 capability prompts ("Only the execution index may release `<NEXT>` … after this task is `VERIFIED`"), which is narrowed — not waived — by `CON-015` in `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md`: **within one batch a downstream prompt may be released on its upstream being `COMPLETED`; across a batch boundary §36 is unchanged and no prompt in the next batch may begin until every prompt in the current batch is `VERIFIED`.** This override is explicit and ranks above the task prompt under "Instruction precedence" above. Never extend it beyond that wording.
- **One narrow exception to the read-only package rule, and only one.** `CON-016`/`ADR-0026` downgrade exactly five register/derived-metadata files — `00-control/04_CONFLICT_REGISTER.md` (which carries `CON-016` itself, and keeps its stricter “decision-change protocol only” authority), `05_REQUIREMENT_COVERAGE_MATRIX.md`, `06_PACKAGE_BUILD_STATUS.md`, `07_PROMPT_PACKAGE_MANIFEST.md`, and `START_HERE.md` — from `FORBIDDEN` to `CAUTION`, **for Step 17 (Final Package Validation) only**, and only for mechanical, source-safe corrections that cite the evidence proving the original wrong. Matched literally, not by prefix: 5 of the package's 430 files. **All 324 prompt files and all 18 step READMEs stay `FORBIDDEN`** — the sentence above is untouched. Anything that would change *what a future agent builds* is a finding with a proposed patch in `docs/build-log/final-package-validation/FINAL_GAP_RISK_REGISTER.md`, never an edit. Re-verify each correction with `pnpm run package:check`. No other step, phase or out-of-band task inherits this authority.
- Batching changes *when* review runs. It changes nothing in the rest of this file — no gate may be weakened, no applied migration edited, no Critical/High finding left open uncontained.

## Branch, commit, and checkpoint rules

- One commit per prompt (rollback granularity is per capability); one fix commit per batch; push at least at every batch close. The pre-flight collision check below runs once per batch, before its first prompt.
- One branch and one business capability per atomic task unless the task explicitly states otherwise.
- Keep commits intentional and reviewable. Do not mix formatting sweeps or unrelated upgrades.
- Record branch, commit, last known good commit, migration state, and gate results in the task build log and ledger.
- Never rewrite shared history or use destructive Git commands without explicit authorization.
- A task is not a valid checkpoint until documentation and evidence are committed or otherwise durably recorded.

## Scope and refactoring

- Default task size: one feature slice, one module boundary, 1–3 migrations, approximately 5–15 changed files.
- Broad refactors, framework upgrades, shared-schema redesign, API version changes, or destructive migrations require dedicated prompts and ADR/change control.
- Fix only task-caused failures. Log unrelated/pre-existing failures and create a separate recovery task.
  **Inverted for a declared backlog-remediation task by `ADR-0027` Part A**: there, pre-existing failures *are* the task, and the per-task size cap above does not apply — the bound moves to one bounded change per backlog item, one commit each. The obligation to separate pre-existing from change-caused failures with baseline evidence is unchanged. Part A expires when the agent-fixable backlog reaches zero; every integrity rule named in `ADR-0027` Part C is untouched.
- Preserve backward compatibility using additive or expand-and-contract changes where risk warrants it.

## Stack baseline

- Next.js App Router, React, TypeScript strict mode.
- Server Components by default for sensitive/data-heavy views; Client Components at interaction boundaries.
- Supabase Auth, PostgreSQL, RLS, Storage; Realtime and Edge Functions selectively.
- Vercel baseline and separate Local/Development/Testing/Staging/UAT/Production environments.
- Shared schema with RLS by default; PostGIS enabled from Platform Core.
- PostgreSQL durable queue first; separate workers only by measured need.
- REST `/v1` and GraphQL public surfaces developed together.

Repository discovery determines exact supported versions and commands. Do not upgrade merely because a newer version exists. **Note:** as of the current checkpoint no application code, manifest, or lockfile exists yet (see `docs/discovery/01_REPOSITORY_INVENTORY.md`); the stack baseline above is the ratified target, not an implemented fact.

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
- Internal ERP is desktop-first responsive; customer/field flows are mobile-friendly, online-first responsive web app (RPD-004; not an installable PWA — no manifest/service worker is required or planned, `ISS-2026-245`).
- Use server-side filter/sort/search/pagination; cursor pagination for high-volume streams. Never load an entire large dataset into the browser or use `SELECT *` in transactional APIs.
- Live dashboard queries require read-only access, budgets, timeout, pagination, and caching. Add replicas/read models only after measured thresholds or an approved performance task.
- Conform to WCAG 2.2 AA and the supported browser matrix.
- White-label changes presentation within approved tokens; do not fork component structure per tenant.

## Test and gate policy

Detect the package manager and run repository-provided equivalents of lint, typecheck, tests, and build. Add focused database, migration, RLS, RBAC, field/record access, cross-tenant negative, contract, E2E, accessibility, performance, security, smoke, and regression gates according to risk.

Do not disable tests/rules or modify assertions merely to hide failures. Separate pre-existing failures with baseline evidence. A failed mandatory gate means the task is not complete.

Which gates run per prompt and which run at batch close is defined by the tiers in "Execution cadence" above and detailed in `docs/standards/BUILD_EXECUTION_PROTOCOL.md` §2. The gate set itself is unchanged — every gate still runs, and the full suite still runs fresh before any prompt is called `VERIFIED`.

## Documentation required for completion

Update the persistent context files under `docs/runtime/` and the relevant build log, change manifest, regression/traceability matrices, schema/API/data-flow/dependency records, decisions, assumptions, errors, issues, user/admin/API/support docs, runbooks, and release notes as applicable.

Use the templates in `docs/ai-agent-build-prompt-package/01-agent-governance/` when a repository-native instance does not yet exist.

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
