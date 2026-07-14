# Prompt 45 — Testing Workstream

**Prompt ID:** `CG-S3-ARCH-010`  
**Package document:** `CG-AABPP-ARCH-045`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/10_TESTING_WORKSTREAM.md`

## Objective and value

Plan a risk-based, layered, reproducible quality system that proves CargoGrid behavior, tenant isolation, financial integrity, migration safety, and direct-GA readiness.

## Preconditions

Prompts 36–44 are complete. Use verified test baseline and pre-existing failure ledger, requirement/UAT catalogues, boundaries, data/access/API/UX plans, and delivery gates. Do not add or modify tests.

## Required tasks

1. Define test layers: static/lint/typecheck, unit, component, contract, integration, database/constraint, migration, RLS/RBAC, API REST/GraphQL, job/integration, E2E, accessibility, performance, security, smoke, UAT, regression, and operational rehearsal.
2. Map test ownership and environments to every workstream, requirement family, business rule, approval, transition, exception, report, and critical flow.
3. Preserve mandatory 20 E2E UAT, 18 tenant-isolation, and 24 financial-integrity scenarios; expand negative cases for fields, records, search, reports, exports, files, jobs, and support access.
4. Define synthetic tenant/org/branch/user/customer/vendor/employee/finance/shipment/inventory datasets with deterministic factories, privacy, isolation, and cleanup.
5. Define clean rebuild and upgrade migration tests, seed validation, contract compatibility, browser/device matrix, WCAG checks, load/scale profiles, backup/restore, and DR rehearsal evidence.
6. Define CI gate order, parallelization, flake/quarantine policy, retries, coverage meaning, artifacts, failure ownership, and no-hidden-failure rules.
7. Separate baseline failures from regressions; define stop/rollback thresholds and zero-critical-defect direct-GA gate.
8. Produce atomic verification backlogs aligned to implementation slices and phase closure.

## Required output

Include test architecture, requirement/control matrix, environment/data strategy, critical suites, CI gate model, regression/flake policy, migration/recovery tests, performance/accessibility/security evidence, phase exit criteria, failure/rollback rules, ADR candidates, atomic backlog, and readiness dashboard definitions.

## Completion gate

Complete only when every critical control has a planned automated or explicitly owned manual proof, unsafe unavailable tests are visible, direct-GA gates are enforceable, and no test/config/source change occurred.
