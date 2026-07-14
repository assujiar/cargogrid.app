# Prompt 292 — Typed Ticket-Linked Records

**Prompt ID:** `CG-S12-HRT-020`  
**Package document:** `CG-AABPP-HRT-292`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-292.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-020` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: SLA, Assignment, Escalation and Knowledge; Epic: Authorized Cross-Domain Case Context; Capability: Shipment, Invoice, Warehouse, Vendor, Customer and User Linkage; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement validated typed ticket links to canonical shipment, invoice, warehouse, vendor, customer and user records without duplicating data or granting access through linkage.

## 5. Business value

Give support teams relevant transaction context while preserving source ownership, authorization and audit boundaries.

## 6. Source requirement

All TKT families, master linkage capability and Technical Architecture typed-reference rule. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-286..291; verified canonical records and per-domain authorization contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-293..297; Step 13 portal consumers. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create typed ticket_link with tenant, ticket, entity_type, canonical entity ID, relationship, source, created_by, validity and optional safe snapshot/version metadata. Prefer validated domain-specific reference registry/constraints over unconstrained polymorphic strings.

## 14. API impact

Shared REST/GraphQL search-authorized-candidates, link, unlink, list and safe-summary operations; every domain adapter validates existence, tenant/owner scope and current caller access without returning unauthorized existence signals. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Ticket side panel for authorized link search/add/remove and safe summaries/deep links; show unavailable/revoked/deleted states without leaking data, with keyboard-accessible controls. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

A link grants no access. Every list/search/summary/deep-link/export/notification checks ticket and linked-record policy for the current principal; customer, internal and support projections may differ. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/ticket/entity type/entity ID/relationship; bounded type-specific candidate search, batched safe summaries, no cross-domain N+1 and cache keys including principal/scope/policy version. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record link/unlink source/reason, domain validation result, safe-summary/deep-link access, denied enumeration, source/config versions and support-grant context. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy free-text/entity links only after canonical ID and access validation; keep unresolved reference text quarantined as non-clickable evidence rather than guessing. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define supported entity-type registry, domain ownership and validation adapter contract.
- Implement constrained link schema, shared service/API and accessible side panel.
- Implement per-principal safe summaries and independent linked-record authorization.
- Add cache/search/export/notification/deep-link inference protections.
- Test forged IDs, ownership changes, deletion/revocation, channel differences and scale.

## 21. Main flow

Authorized ticket participant searches within permitted records for one supported type, server validates canonical existence/tenant/scope/policy, creates a typed link and returns only a principal-safe summary; later access is reauthorized.

## 22. Alternative flow

System creates a link from a verified source event, user links multiple related records, removes an incorrect link with reason, or source record becomes unavailable/restricted.

## 23. Exception flow

Deny unsupported type, cross-tenant/owner ID, unauthorized candidate, forged/deleted record, customer-vendor/user leakage, stale policy/cache or expired support grant without revealing existence. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Supported links are shipment, invoice, warehouse, vendor, customer and user plus only registry-approved future types; free-form type/ID pairs are forbidden.
- Canonical source domain owns the linked record; Ticketing stores reference and minimal versioned safe context only.
- A ticket link never grants access and never overrides customer account/site, HR field, Finance, vendor or support policy.
- Safe summaries, counts, search suggestions, exports, notifications and caches are principal-specific and reauthorized.
- Customer Portal expansion remains Step 13; AI related-record suggestion remains Step 14.

## 25. Validation rules

Validate supported entity type, canonical ID/existence, tenant/owner/customer scope, caller ticket access, caller linked-record access, relationship, duplicate policy, support grant and current versions before link/read.

## 26. Access rules

Internal/channel participants link only records they can access; customers link/see only account/site-permitted records and safe types; support requires case-bound grant for restricted tenant data. Database/service adapters enforce policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Tickets across three channels linked to shipment/invoice/warehouse/vendor/customer/user, cross-tenant/account IDs, revoked access, deleted/archived source, stale cache and support grant fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Typed registry/constraint/link lifecycle domain tests.
- Cross-tenant/account/channel/entity enumeration and forged-ID negative tests.
- Safe-summary/deep-link/cache/export/notification policy tests.
- Source deletion/revocation/policy-version/support-grant tests.
- Link panel/search browser/accessibility and batched-load E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Canonical domain authorization for shipment/invoice/warehouse/vendor/customer/user, ticket channels, search/cache/export/notification and Step 13 contracts. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Typed link registry/adapters, source ownership, safe-summary policy, channel/customer/support matrix, migration/quarantine and cache/revocation runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable affected entity adapter/link creation, preserve validated references, hide unsafe summaries, invalidate caches, revert compatible code/policy and reconcile links against source domains. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Typed links reference canonical records through validated registry/adapters.
- Link existence never grants access or leaks cross-domain/customer/support data.
- Forged ID, revocation, deletion, cache/search/export/notification tests pass.
- No duplicate source truth; accessibility and batched performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-293 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

