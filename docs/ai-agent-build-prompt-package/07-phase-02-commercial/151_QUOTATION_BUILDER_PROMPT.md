# Prompt 151 — Quotation Builder

**Prompt ID:** `CG-S7-COM-010`  
**Package document:** `CG-AABPP-COM-151`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-151.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-010` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Quotation Lifecycle; Epic: Customer Offer; Capability: Quotation creation and document preparation; Feature slice: Opportunity/cost/margin→draft quote lines/terms→submission-ready offer; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a canonical quotation builder that reuses customer/opportunity/cargo/service/rate data, produces exact selling lines/terms and prepares a private customer document.

## 5. Business value

Create accurate customer offers quickly without repeated entry or divergent spreadsheets.

## 6. Source requirement

COM-QTN-001..004; Brief §7.1 Quotation; UX COM-QTN-001. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-147..150; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-152..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Quotation Lifecycle schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant-scoped quotation root, stable number, draft version, source opportunity/cost/margin snapshots, typed line/components, terms, validity, currency, status and document references.

## 14. API impact

Provide idempotent shared REST/GraphQL draft/create/update/preview/submit-readiness operations using the same calculation and access services.

## 15. UI/UX impact

Build accessible autosaving spreadsheet-like desktop quotation builder with responsive section cards, inherited data, line validation, preview and complete conflict/error states.

## 16. Security impact

Enforce customer/owner/value scopes and cost/margin/discount field policy; generated documents are private, scanned and signed-URL protected. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Bound line/component operations, use optimistic autosave, server pagination where needed and avoid N+1 lookups/preview generation.

## 18. Audit impact

Record source snapshots, line/term/validity changes, autosave conflicts, calculation versions, preview/document generation and submission attempts.

## 19. Data migration impact

Adopt legacy drafts only with reconciled customer/opportunity/currency/line totals; preserve original artifacts and source mapping.

## 20. Detailed implementation tasks

1. Define quotation root/draft line/term/validity/document contracts.
2. Implement idempotent creation from opportunity and selected calculation snapshots.
3. Implement autosave/concurrency, line editing, validation and preview generation.
4. Build builder UX and shared REST/GraphQL operations with access projections.
5. Verify totals, no-reentry, private documents, performance and submission readiness.

## 21. Main flow

Seller creates a quote from an opportunity; inherited data and selected costs produce validated selling lines, terms, validity and preview.

## 22. Alternative flow

Authorized user clones a prior draft/version with explicit origin and refreshes permitted inputs before submit.

## 23. Exception flow

Missing customer/service/cost, stale source, invalid line/currency/validity, autosave conflict or document failure blocks submit.

## 24. Business rules

- Quote number and canonical identity are stable; revisions are handled by Prompt 152.
- Customer-facing document never exposes cost/margin fields.
- Terms/templates use whitelisted variables and published versions; no arbitrary code.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Reconcile line/subtotal/discount/tax/total to the server calculation result.
- Require customer, contact/address, service/cargo, validity, terms and source versions as configured.
- Submit readiness rejects stale/expired/unapproved rate or unresolved calculation warning.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales edits permitted drafts; pricing/manager sees restricted fields by policy; customer sees only explicitly sent version later. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multi-line/minimum/surcharge quotes, inherited address/cargo/service, clone, stale rate, autosave conflict, private document and field-restricted users. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Quote/line/total/number/validity/autosave/source-snapshot/database constraint tests.
- RLS/RBAC/field/record/API parity/file scan/signed URL/audit tests.
- Builder/preview E2E, accessibility, performance and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Opportunity/cost/rate/margin, document/numbering/config engines, contacts and existing quote records. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-151.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Draft quote is exact, complete and built without re-entry.
- UI/API/document projections preserve sensitive-field policy.
- Quote is ready for versioning/approval with full source lineage.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-011` / `COM-152` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

