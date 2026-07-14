# Prompt 242 — Customer Inventory Access Contract

**Prompt ID:** `CG-S10-ATW-023`  
**Package document:** `CG-AABPP-ATW-242`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-242.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-023` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Customer Data Access; Epic: Inventory Visibility Contract; Capability: Scoped Customer Inventory Access; Feature slice: customer/account/owner grants, permitted inventory and order views, field policy, export and revocation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a secure backend/database contract for customer-scoped inventory visibility while deferring the complete Customer Portal experience to Step 13.

## 5. Business value

Give customers trustworthy, least-privilege inventory visibility without exposing other owners or granting warehouse mutation rights.

## 6. Source requirement

OPS-CST-001..004 and OPS-WMS-001..004 customer-inventory slice; RPD-001/002/031/033. Cite exact source sections, runtime evidence, policy versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, identity/customer/company/warehouse/inventory schemas, contracts/routes/modules, package manager/scripts, environment, baseline and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers/build logs and source requirements. Inspect auth, customer-account links, RLS/field policy, inventory/order/ledger queries, exports and tests; run baselines, state plan/files, and stop on scope/privacy/security/portal-boundary conflict.

## 9. Upstream dependencies

ATW-229..241 plus verified platform identity/customer scope and Finance compatibility. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-243..248 and Step 13 Customer Portal consumers. Identify affected policies, schemas/views/services/APIs/exports/audit/tests/docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact customer-inventory policy, query/API contract, migration, test and documentation paths authorized by WBS. Minimal server-rendered/internal verification UI is allowed only if required; full Portal UI remains forbidden.

## 12. Forbidden files/folders

Full Customer Portal/navigation/branding/self-service, inventory adjustment rights, duplicate identity/inventory truth, Step 11/12/14 scope, tenant forks, applied-migration edits, destructive cleanup, policy/test weakening and unrelated user changes.

## 13. Database impact

Add/version customer account-to-company/warehouse/owner grants and safe read models/policies for permitted balance, tracked-stock attributes, order/task status and ledger movement summaries; support revocation and expiry.

## 14. API impact

Shared REST/GraphQL read/list/search/filter/cursor/export-request operations for allowed inventory, warehouse order/status and permitted movement lineage. One service must enforce identical scope, field policy, masking, audit and version semantics.

## 15. UI/UX impact

Only minimal contract verification/admin grant surfaces in Phase 5; full customer experience is Step 13. Any surface includes loading, empty, error, success, denied/revoked and degraded states, responsive accessible behavior and no dead action.

## 16. Security impact

Bind user→customer account→company/site/warehouse/owner grants; deny enumeration, cross-owner joins, indirect aggregate inference and unsafe exports. Apply RLS plus service checks, strict fields, revocation, rate limits, audit and signed private files where applicable.

## 17. Performance impact

Index tenant/customer-account/warehouse/owner/item/status/date and grant validity; use safe pre-scoped queries, selective fields, cursor pagination, bounded exports and limited realtime. Prove target-volume plans and prevent N+1/unscoped aggregates.

## 18. Audit impact

Record grant/create/change/revoke/expiry, actor/policy version, request scope, query/export type, result count/denial and correlation ID without leaking sensitive row data. Preserve source and customer-owner lineage.

## 19. Data migration impact

Map customer grants only from verified account/company/site/owner evidence; default deny ambiguous relationships. Use additive/expand-contract migrations, never edit applied migrations, and test backup, rollback, revocation and policy compatibility.

## 20. Detailed implementation tasks

- Inventory identity/customer/owner/warehouse relationships and current policies.
- Define explicit grants, permitted resources/fields/actions and deny-by-default semantics.
- Implement shared scoped queries/APIs, bounded exports and audit.
- Add anti-enumeration, aggregate-inference and revocation controls.
- Test cross-tenant/customer/owner leakage, performance and Step 13 compatibility.

## 21. Main flow

An authorized customer user requests inventory or warehouse status; service resolves active grants, applies tenant/customer/warehouse/owner and field scope before query, returns only permitted records, and audits access.

## 22. Alternative flow

Allow multiple approved owner/site grants, delegated read role, aggregate view only when policy-safe, bounded asynchronous export, or revocation/expiry without data mutation.

## 23. Exception flow

Deny missing/expired/ambiguous grant, foreign owner/site, forbidden field, unsafe aggregate/export, cursor tampering, excessive request or stale authorization. Return non-enumerating errors and record safe evidence/resume.

## 24. Business rules

- Customer inventory access is read-only in Phase 5; no count, adjustment, reservation or task mutation.
- Scope is intersected across tenant, customer account, company/site, warehouse and inventory owner.
- List/search/export/aggregate/realtime apply identical record and field policy.
- Full Portal UX and self-service remain Step 13; this task publishes a stable contract.
- Extend canonical identity/inventory records; no duplicate truth or tenant fork.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no autonomous AI, offline sync or partial-GA claim.

## 25. Validation rules

- User, customer account, grant, company/site, warehouse and owner are active and compatible.
- Requested fields/actions/filters/aggregates/export are explicitly permitted.
- Reject foreign IDs before observable lookup, stale grant/version and cursor/sort abuse.
- Every response is scope-safe, auditable and source-reconcilable.

## 26. Access rules

Platform/tenant admins govern grants; customer admins receive only delegated grant management if explicitly approved; customer viewers read permitted data; warehouse and Finance mutations remain separate. Enforce database and service policy, never UI only.

## 27. Test data requirement

Tenant A/B, two customers in one tenant, shared/different warehouses, multiple owners/sites, active/expired/revoked grants, restricted fields, zero records, large cursor/export and forged identifiers.

## 28. Tests to create/update

- RLS/service/field-policy matrix across tenant/customer/company/site/warehouse/owner.
- Enumeration, aggregate inference, export, cursor tampering, revocation and audit tests.
- REST/GraphQL parity, migration, target-volume and accessibility tests.
- Step 13 consumer contract fixtures without full Portal implementation.

## 29. Regression tests

Platform auth, inventory ledger, all warehouse flows, Finance/customer scoping and existing internal views. Re-run tenant/customer isolation, API/job/browser and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository lint/typecheck/test/build plus database migration/type generation, RLS/policy matrix, API contract, security, cursor/export load and relevant E2E commands. Do not disable a gate.

## 31. Documentation to update

Customer grant/resource/field/action/export/revocation contract and leakage-response runbook; publish Step 13 handoff. Update persistent ledgers, traceability, schema/API/data-flow/build-log and admin/API/support docs.

## 32. Rollback/recovery note

Default-deny or revoke affected grants, stop exports, preserve audit, restore last compatible policy and verify no cross-scope exposure before resume. Do not delete evidence or loosen policy as rollback.

## 33. Acceptance criteria

- Allowed customers read exactly their permitted inventory/status data.
- Cross-tenant/customer/warehouse/owner and restricted fields remain inaccessible across all channels.
- Revocation/export/performance and REST/GraphQL parity are proven.
- Full Portal remains deferred with a documented stable handoff.

## 34. Definition of Done

No placeholder/fake persistence/dead action; migrations, types, RLS/RBAC/field policy, shared APIs, bounded exports, tests, docs, audit, performance evidence and rollback are complete; no critical privacy/security blocker remains.

## 35. Completion report format

Report IDs/checkpoint; changed files/policies/contracts; decisions; commands/results; scope/access/export, isolation, API parity/performance evidence; residual risks; Step 13 handoff; docs; rollback/resume; next task. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-243 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
