# Prompt 296 — HRIS and Ticketing Documentation and Handoff

**Prompt ID:** `CG-S12-HRT-024`  
**Package document:** `CG-AABPP-HRT-296`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-296.md`

Do not begin until all upstream tasks are `VERIFIED` and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-024` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Integrated Verification, Hardening, Documentation and Closure; Epic: Phase 7 Evidence Closure; Capability: Durable Operations and Later-Phase Handoff; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Make verified HRIS/Ticketing behavior supportable and consumable by employees, managers, HR/payroll, service teams, developers and Steps 13–14 without changing runtime behavior.

## 5. Business value

Reduce payroll, privacy, ticket and support errors while giving later phases one authoritative contract instead of rediscovery.

## 6. Source requirement

All Phase 7 source requirements and current verified runtime evidence. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-295 VERIFIED and all prior Phase 7 evidence current. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-297 and Steps 13–14. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 verification, repair, test, evidence and documentation paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production mutation and hidden test/permission weakening.

## 13. Database impact

None planned. Document canonical employee/org/position, recruitment, time, payroll, performance/training, ESS/MSS, ticket/channel/message/SLA/assignment/escalation/link entities, constraints, versions, RLS, retention and recovery.

## 14. API impact

None planned. Publish current REST/GraphQL parity, principal/field projections, idempotency/cursors/errors, jobs/integrations, payroll-Finance and customer/support/linked-record contracts. REST and GraphQL retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

None planned. Document role flows, complete states, accessibility, online-first limits, sensitive-field behavior, customer-ticket bounded surface and support grants. Preserve responsive/accessibility evidence, complete states and no fake success/dead action.

## 16. Security impact

Sanitize PII, candidate, location, compensation, bank/tax, performance, ticket content, customer and support evidence; document purpose access, MFA/separation, files, retention/legal hold and RPD-022 residual risk. Preserve RLS/RBAC, server-only secrets, private scanned files, field policy, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Publish measured environment/dataset/concurrency, employee/time/payroll/ticket/SLA/job/export targets/results, degraded behavior and capacity guidance without production claims. Record before/after or verification profile and no-regression threshold; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Document required events/fields, source/config/correlation/idempotency, sensitive access/denials, payroll/Finance and ticket/link chains, retention/redaction and evidence retrieval. Evidence must be useful, source-linked and privacy-safe.

## 19. Data migration impact

Document clean install, Phase 6→7 upgrade, imports/opening balances, backup/restore, payroll/ticket reconciliation and rollback/forward recovery. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Reconcile requirements, decisions, architecture, schema, API, data-flow and traceability docs.
- Publish employee/manager/HR/payroll/recruiter/service/support role guides.
- Publish runbooks for time/payroll exceptions, privacy requests, ticket/SLA/link failures and support access.
- Publish test/security/performance/migration evidence index and known limitations.
- Create explicit Step 13 customer portal/ticket and Step 14 AI/enterprise handoff contracts.

## 21. Main flow

Readers enter one Phase 7 index, choose role/use case, follow verified procedures/contracts and reach exact diagnostics, recovery, privacy and escalation guidance.

## 22. Alternative flow

Generate references from source contracts when reproducible and link localized/training variants to one canonical definition without divergent rules.

## 23. Exception flow

If documentation conflicts with runtime evidence, register a blocker and return to the owning prompt; if sensitive data is found, remove it safely and follow security/incident process. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Documentation describes only verified behavior at an identified checkpoint/version.
- One canonical employee, payroll, ticket and linked-record term/state definition is reused across audiences.
- Finance owns posting/payment; Platform owns identity/access; source domains own linked records; Step 13 owns full portal; Step 14 owns AI depth.
- Examples use deterministic sanitized data and never raw payroll, PII, ticket content, token or private URL.
- No production, pilot, GA, legal-certainty, immutable-for-all or autonomous-decision claim.

## 25. Validation rules

Every capability/anchor/decision/contract/runbook links to current evidence; examples/commands/links render; no secret/private data/dead link/contradictory state. Any unresolved critical/high blocker keeps the task unverified.

## 26. Access rules

Separate employee/customer-safe, manager, HR/payroll, service/support, developer and restricted-security content using least privilege. Evidence stores enforce classification, not documentation labels alone. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Use sanitized examples for each HR lifecycle and ticket channel/SLA/link flow with source/config versions, allowed/denied roles and reproducible checkpoint/profile. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- Docs build/lint/link and schema/API example validation.
- Secret/PII/payroll/ticket/private-URL scanning and access classification.
- Runbook tabletop for payroll batch/correction, privacy leak, SLA job, support grant and linked-record denial.
- Fresh-reader walkthrough for employee/manager/HR/payroll/service/support and Steps 13–14.
- Documentation-only runtime-diff guard and evidence-link reconciliation.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

Docs build and Phase 1–6 cross-links; documentation work cannot alter runtime artifacts or invalidate verified tests. Compare repository runtime hashes/diffs where feasible.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Complete Phase 7 index, architecture/domain/schema/API, role guides, runbooks, test/security/performance/migration evidence, traceability, release/handoff and HRT-296 log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

Revert only incorrect docs to last verified version, preserve evidence/history and keep closure blocked when runtime conflict is uncovered. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Phase 7 documentation is complete, consistent, evidence-backed and sanitized.
- Critical role guides/runbooks and examples are executable at the recorded checkpoint.
- Step 13/14 handoffs preserve ownership and scope boundaries.
- No runtime behavior changes; docs/access/link scans and fresh-reader review pass.
- Evidence is reconciled at one compatible checkpoint with no fabricated pass.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/identity/access/privacy/payroll/Finance/ticket/link/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-297 after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

