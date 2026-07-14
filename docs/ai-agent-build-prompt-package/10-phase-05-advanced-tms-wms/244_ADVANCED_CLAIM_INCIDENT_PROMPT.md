# Prompt 244 — Advanced Claim and Incident Operations

**Prompt ID:** `CG-S10-ATW-025`  
**Package document:** `CG-AABPP-ATW-244`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-244.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-025` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Operational Risk; Epic: Claim and Incident Resolution; Capability: Advanced Claim/Incident Lifecycle; Feature slice: intake, evidence, investigation, liability/reserve estimate, approval, recovery, settlement handoff and closure; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement an auditable operational claim/incident lifecycle linked to shipment, transport and warehouse evidence without autonomous legal/insurance decisions or duplicate financial truth.

## 5. Business value

Resolve loss, damage and shortage cases consistently while protecting evidence, customer scope and financial reconciliation.

## 6. Source requirement

OPS-DOC-001..004 advanced claim/incident slice plus OPS-SHP/TMS/WMS/TRK/CST evidence and verified Finance handoff. Cite exact source sections, runtime evidence, policy versions and prerequisites.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, claim/document/shipment/WMS/ePOD/Finance schemas/contracts/routes/modules, package manager/scripts, environment, baseline and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers/build logs and source requirements. Inspect basic Step 8 claim/incident, document/ePOD, shipment/leg/milestone, WMS ledger/package and Finance contracts; run baselines, state plan/files, and stop on legal/security/financial/scope conflict.

## 9. Upstream dependencies

Verified Step 8 basic incident/claim, ATW-221/228/232/234/238/243 and verified Finance handoff. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-245..248 and future procurement/vendor, customer portal and AI consumers. Identify affected case/evidence/services/APIs/jobs/files/audit/reports/tests/docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact advanced claim/incident extension, approved Finance handoff, file/job, UI, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Autonomous liability/legal/insurance judgment, final accounting/settlement mutation, duplicate basic case root, full vendor/HR/portal/AI scope, public files, tenant forks, applied-migration edits, destructive cleanup, policy/test weakening and unrelated user changes.

## 13. Database impact

Extend canonical case with type/severity, claimant/affected party, shipment/leg/stop/package/inventory/movement/ePOD links, loss/damage/shortage items, evidence versions, investigation/findings, responsibility proposal, reserve estimate, approval, recovery and Finance handoff/closure reconciliation.

## 14. API impact

Shared REST/GraphQL intake/triage/assign/evidence/investigate/propose/review/approve/recover/handoff/close/reopen-eligible/read/export operations with one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Case queue/detail timeline, linked operational evidence, itemized impact, investigation checklist, review/approval, recovery and handoff status. Include loading, empty, error, success, denied, conflict and degraded states; responsive accessible online-first PWA and no dead action.

## 16. Security impact

Strict case/evidence/PII/commercial/financial fields, assigned-team and customer visibility, legal-hold/retention policy, private malware-scanned files and short-lived signed URLs. Enforce tenant/customer scope, RLS/RBAC, redaction, download audit and server-only secrets.

## 17. Performance impact

Index tenant/customer/case-type/severity/status/assignee/shipment/warehouse/date; cursor queues, bounded evidence metadata and asynchronous scan/export/integration. Use selective queries and limited realtime; measure case-search and job budgets.

## 18. Audit impact

Record intake/source/version, linked custody/stock/ePOD evidence, assignments, findings, proposal vs human decision, estimate/config/currency, approvals, recovery/handoff/closure, file access and every override/reopen with correlation/idempotency.

## 19. Data migration impact

Extend existing cases only from evidenced identifiers; never invent liability, amount, approval or closure. Map files privately, reconcile case/Finance receipts and use additive/expand-contract migrations; never edit applied migrations.

## 20. Detailed implementation tasks

- Inspect basic cases, operational evidence, files and Finance handoff.
- Define lifecycle, evidence sufficiency, roles, itemized impact and approval invariants.
- Implement case extension, APIs, accessible UI, private files/jobs and notifications.
- Implement proposed responsibility/reserve and idempotent Finance readiness only.
- Test scope, evidence, concurrency, recovery, retention and reconciliation.

## 21. Main flow

Authorized user opens or escalates a source-linked case, investigator gathers versioned evidence and itemized impact, a human reviewer decides responsibility/estimate under policy, recovery is tracked, Finance receives readiness, and closure requires reconciliation.

## 22. Alternative flow

Merge duplicates while retaining lineage, split affected items, request more evidence, deny/withdraw with reason, recover from carrier/vendor/customer later or reopen an eligible case under approval.

## 23. Exception flow

Block foreign/ambiguous source, missing custody/quantity evidence, unsafe file, duplicate case, stale concurrent decision, separation-of-duty breach, unsupported currency, Finance rejection or retention/legal-hold conflict. Preserve evidence and safe resume.

## 24. Business rules

- Extend the Step 8 canonical case; no duplicate claim/incident root or silent re-entry.
- System may summarize/propose only; authorized humans decide liability, reserve, recovery and closure.
- Evidence remains versioned/private/scanned and source-linked; barcode/reference possession grants no access.
- Reserve/settlement readiness is a Finance handoff; this module does not post invoice, AR/AP, GL or cash.
- Closure requires operational and Finance reconciliation; corrections/reopens preserve history.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, offline sync, autonomous commitment or partial-GA claim.

## 25. Validation rules

- Case source, affected items/quantity/value/currency and evidence links are compatible and authorized.
- Lifecycle prerequisites, separation of duties and policy/config versions are satisfied.
- Reject tenant/customer/shipment/warehouse/owner/source/version mismatch and stale mutation.
- Every state, file, decision and handoff is idempotency-safe and source-reconcilable.

## 26. Access rules

Operations intake/triage; assigned investigators manage evidence; designated reviewers approve decisions; Finance consumes readiness; customers see only allowed case/status/evidence fields. Enforce database/service authorization and file policy, not UI only.

## 27. Test data requirement

Damage/loss/shortage/delay cases linked to multi-leg shipment, package, receiving discrepancy, ledger movement and ePOD; duplicate/merge/split, unsafe file, missing evidence, recovery, reopen, Finance rejection and Tenant A/B customers.

## 28. Tests to create/update

- Lifecycle/evidence/itemization/approval/separation/reopen and idempotency tests.
- Private-file scan/signed-URL/field-policy and tenant/customer isolation tests.
- Operational quantity/custody and Finance handoff/reconciliation contract tests.
- Migration, target-volume queue/export and accessibility E2E tests.

## 29. Regression tests

Step 8 documents/ePOD/basic cases, shipment/milestones, WMS receiving/outbound/ledger, Finance and future portal/vendor consumers. Re-run isolation, API/job/file/browser and critical E2Es.

## 30. Commands to run

Detect and run repository lint/typecheck/test/build plus database migration/type generation, security/file scan, Finance contract/reconciliation, target-volume case/search/export and relevant E2E commands. Do not disable a gate.

## 31. Documentation to update

Case lifecycle, evidence/field/access, proposal-vs-decision, estimate/recovery/Finance handoff and retention/legal-hold/reopen runbooks. Update persistent ledgers, traceability, schema/API/data-flow/build-log and user/admin/Finance/support docs.

## 32. Rollback/recovery note

Stop new handoffs, preserve case/evidence/accepted Finance receipts, revert only eligible pending states and use governed correction/reopen for decided cases. Reconcile operational and Finance truth before resume.

## 33. Acceptance criteria

- Advanced case lifecycle works from source-linked intake through reconciled closure.
- Private evidence, human decisions and separation of duties are enforced.
- Finance handoff is idempotent without duplicate accounting truth.
- Mandatory gates pass at one checkpoint with source-to-evidence traceability.

## 34. Definition of Done

No placeholder/fake persistence/dead action; migrations, types, RLS/RBAC/field/file policy, shared APIs, UX, jobs, tests, docs, audit, performance and rollback evidence are complete; no critical legal/security/financial blocker remains.

## 35. Completion report format

Report IDs/checkpoint; changed files/contracts; decisions/configs; commands/results; case/evidence/access, Finance/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next task. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-245 after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
