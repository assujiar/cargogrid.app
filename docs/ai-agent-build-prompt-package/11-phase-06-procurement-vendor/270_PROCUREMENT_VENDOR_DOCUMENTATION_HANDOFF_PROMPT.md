# Prompt 270 — Procurement/Vendor Documentation and Handoff

**Prompt ID:** `CG-S11-PRC-021`  
**Package document:** `CG-AABPP-PRC-270`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-270.md`

Do not begin until PRC-269 is `VERIFIED` and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-021` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Phase 6 Operational Readiness; Epic: Documentation and Handoff; Capability: Durable Procurement, Vendor and Next-Phase Knowledge; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Make verified Phase 6 behavior supportable and consumable by operators, developers and Steps 12–14 without changing runtime behavior.

## 5. Business value

Reduce onboarding, sourcing, payment-control and support errors while protecting downstream contract ownership.

## 6. Source requirement

All Phase 6 PRC/RPD requirements and PRC-251..269 verified evidence. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read all persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts and Phase 6 build logs/sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, freeze the checkpoint, run feasible baselines, state plan/files and stop on evidence, tenant, vendor, security, financial, Operations or phase-boundary conflict.

## 9. Upstream dependencies

PRC-269 `VERIFIED` and all prior Phase 6 evidence current. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-271 and Steps 12–14 consumers. Identify affected evidence, schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 6 verification/repair/documentation paths and minimal registered defect paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production-data mutation and hidden test/permission weakening.

## 13. Database impact

None; document canonical vendor/rate/assessment/compliance/PO/contract/capacity/assignment/performance/match entities, constraints, RLS, retention and migration/recovery behavior.

## 14. API impact

None; publish current REST/GraphQL parity, auth/field policy, idempotency/cursors/errors, vendor API/portal actions, jobs and Finance/Operations handoffs. REST and GraphQL must retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

None; document procurement staff/manager/approver/vendor portal flows, complete states, role/field behavior, accessibility and online-first limitations. Include responsive/accessibility/browser evidence, complete states and no fake success/dead action.

## 16. Security impact

Sanitize secrets, bank/tax values, PII, vendor/customer data and private URLs; document purpose-bound access, files, MFA/separation, portal/support sessions and RPD-022 residual risk. Preserve RLS/RBAC, server-only secrets, private scanned files, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Publish target profiles/budgets/results, query/job/portal limits, backpressure/degraded behavior, monitoring and capacity guidance without unproven production claims. Record environment/dataset/concurrency, before/after plans and no-regression thresholds; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Document required events/fields, source/version/correlation/idempotency, sensitive access/denials, commitment/match handoffs, retention/redaction and evidence retrieval. Evidence must be useful and privacy-safe.

## 19. Data migration impact

Document clean install, Phase 2 vendor/rate adoption, Phase 5→6 upgrade, backup/restore, key handling, reconciliation and rollback/forward recovery. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Reconcile requirements/decisions/architecture/schema/API/data-flow/traceability docs.
- Publish procurement/vendor user, approver, Finance, Operations and optional vendor-portal guides.
- Publish runbooks for onboarding, compliance expiry, rate/RFQ, PO/contract, capacity, assignment, performance and match exceptions.
- Publish test/security/performance evidence index and known limitations.
- Create explicit Step 12 employee, Step 13 portal and Step 14 AI/enterprise handoffs.

## 21. Main flow

Readers enter one Phase 6 index, select role/use case, follow current verified procedures/contracts and reach exact diagnostics, recovery and escalation guidance.

## 22. Alternative flow

Generate references from source contracts where reproducible and link training/localized variants to one canonical definition without divergent rules.

## 23. Exception flow

If docs conflict with runtime evidence, register a blocker and return to the owning prompt; if sensitive data is found, remove it safely and follow security process. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Documentation describes only verified behavior at an identified checkpoint/version.
- One canonical vendor/rate/PO/match term and state definition is reused across audiences.
- Finance owns vendor bill/AP/posting/payment; Operations owns execution; Procurement owns vendor governance/commitment/match evidence.
- Step 12–14 deferred boundaries and optional portal identity ADR are explicit.
- Preserve canonical Phase 2–5 roots and source/version lineage; no duplicate truth or re-entry.
- No tenant fork, autonomous commitment, offline sync, immutable-for-all claim or partial-GA claim.

## 25. Validation rules

Every capability/anchor/decision/contract/runbook links to current evidence; examples/commands/links/diagrams render; no secret/private data/dead link/contradictory state. Any unresolved critical/high tenant/security/vendor/financial/Operations/evidence blocker keeps the task unverified.

## 26. Access rules

Separate vendor-safe, internal procurement, Finance/Operations, tenant-admin/developer and restricted security content using least privilege. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Use deterministic sanitized examples for onboarding, assessment/compliance, rates/RFQ, PO/contract, capacity/assignment, performance and match; never production identifiers. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- Docs build/lint/link and schema/API example validation.
- Secret/PII/bank/tax/private-URL scanning and access classification.
- Runbook tabletop for expired compliance, rate conflict, assignment shortage, PO dispute, portal leak and match failure.
- Fresh-reader walkthrough of critical operator and Steps 12–14 handoffs.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

Docs build and Phase 1–5 cross-links; documentation-only work cannot change runtime artifacts or invalidate verified tests. Compare baseline/after at compatible checkpoints and explain every change.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job/integration, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Complete Phase 6 index, architecture/domain/schema, API/integration, role guides, runbooks, test/security/performance evidence, traceability, release/handoff and PRC-270 log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

Revert only incorrect docs to last verified version, preserve evidence/history and keep closure blocked when a runtime conflict is uncovered. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Phase 6 documentation is complete, consistent and evidence-backed.
- Critical runbooks/examples are executable and sanitized.
- Steps 12–14 receive explicit stable contracts and boundaries.
- No documentation conflict masks a runtime blocker.
- All mandatory gates pass at one recorded checkpoint with source-to-evidence traceability.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/vendor/access/Finance/Operations/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-271 after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

