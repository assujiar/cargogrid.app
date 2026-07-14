# Prompt 247 — Advanced TMS/WMS Documentation and Handoff

**Prompt ID:** `CG-S10-ATW-028`  
**Package document:** `CG-AABPP-ATW-247`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-247.md`

Do not begin until ATW-246 is `VERIFIED` and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-028` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Phase 5 Operational Readiness; Epic: Documentation and Handoff; Capability: Durable Operator, Developer and Next-Phase Handoff; Feature slice: architecture, contracts, runbooks, training, evidence and boundaries; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Make the verified Phase 5 implementation supportable and consumable by operators, developers and Steps 11–14 without changing runtime behavior.

## 5. Business value

Reduce operational error, recovery time and downstream integration ambiguity.

## 6. Source requirement

All Phase 5 OPS/RPD requirements, ATW-221..246 evidence and delivery documentation/handoff controls. Every claim must cite current runtime evidence and versioned contract.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, verified checkpoint, current docs/contracts/runbooks/diagrams/training/support artifacts, package scripts, environment and last trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers, ATW build logs, requirements/decisions, verified contracts and current documentation. Inventory stale/missing/conflicting material, establish source of truth and stop if documentation reveals an unresolved runtime blocker.

## 9. Upstream dependencies

ATW-246 `VERIFIED` and all ATW-221..245 evidence current at the same compatible checkpoint.

## 10. Downstream impact

ATW-248 and Step 11 Procurement/Vendor, Step 12 HR, Step 13 Customer Portal and Step 14 AI/enterprise work. Publish explicit stable contracts, boundaries and prerequisites.

## 11. Allowed files/folders

Documentation, diagrams-as-code, examples with sanitized fixtures, runbooks, API/schema references, training/support materials and ATW-247 build log. Tiny doc-generation fixes only when authorized.

## 12. Forbidden files/folders

Runtime feature changes, new migrations/contracts, production secrets/data, full Step 11–14 scope, duplicate truth, unsupported marketing claims, destructive cleanup and unrelated user changes.

## 13. Database impact

None. Document canonical entities, relations, constraints, RLS/customer scope, ledger equations, retention and migration/recovery behavior using verified schema versions.

## 14. API impact

None. Publish REST/GraphQL parity, auth/field policy, cursors/idempotency/version/errors, integration callbacks/jobs and sanitized request/response examples from verified contracts.

## 15. UI/UX impact

None. Document dispatcher, warehouse scan/task, billing/case and admin/customer-contract flows including roles, states, accessibility/manual alternatives and online-first limitations.

## 16. Security impact

Remove secrets/PII/customer data from artifacts; document tenant/customer/warehouse/owner scope, files/URLs, scan/reference authorization, integrations, incident response and RPD-022 residual risk without exposing exploit details unnecessarily.

## 17. Performance impact

Publish target profiles/budgets, measured environments/results, query/job/realtime limits, backpressure/degraded behavior and capacity/monitoring guidance; do not generalize lab results into unproven production claims.

## 18. Audit impact

Document audit fields/events, correlation/idempotency, access/denial, movement/custody, billing/claim handoffs, retention/redaction and evidence retrieval procedures.

## 19. Data migration impact

Document clean install, Phase 4→5 upgrade, backup/restore, expand-contract, reconciliation and rollback/forward recovery. Do not prescribe editing applied migrations or fabricating history.

## 20. Detailed implementation tasks

- Reconcile requirements/decisions/architecture/schema/API/data-flow/traceability docs.
- Publish user/admin/dispatcher/warehouse/customer-contract/Finance/integration guides.
- Publish runbooks for telemetry, jobs, labels, inventory mismatch, billing/claim and recovery.
- Publish test/performance/security evidence index and known limitations.
- Create explicit Steps 11–14 handoff contracts and closure checklist.

## 21. Main flow

Readers start from one Phase 5 index, choose role/use case, follow current architecture and procedures, verify examples against versioned contracts, and reach exact diagnostics/recovery/escalation guidance.

## 22. Alternative flow

Generate reference pages from source contracts where reproducible, retain curated conceptual guidance, and link localized/training variants to one canonical source without divergent rules.

## 23. Exception flow

If docs conflict with code/evidence, mark the conflict, register blocker, identify owner and do not invent an answer. If a secret/customer datum is found, remove it safely and record the security process.

## 24. Business rules

- Documentation describes only verified behavior at an identified checkpoint/version.
- One canonical term/entity/state/contract definition is reused across audiences.
- Customer inventory access is a Phase 5 backend contract; full Portal is Step 13.
- Warehouse billing/claims hand off readiness to Finance and do not own accounting truth.
- Step 11 vendor/PO/compliance/rate, Step 12 HR/payroll and Step 14 AI depth remain deferred.
- RPD-004 online-first and RPD-022 CRUD risk remain explicit; no partial-GA claim.

## 25. Validation rules

- Every capability/requirement/decision/contract/runbook links to current evidence.
- Commands/examples/links/diagrams render and match verified schemas/APIs.
- No secret, private URL, production/customer data, dead link or contradictory state name.
- Handoff consumers can identify prerequisites, owned data and forbidden mutations.

## 26. Access rules

Separate public/customer-safe, tenant-admin, operator, developer and restricted security/Finance content. Documentation access follows the same least-privilege/field policy as the underlying system.

## 27. Test data requirement

Use deterministic sanitized examples covering multi-leg transport, telemetry, WMS inbound→outbound, ledger/count, labels, billing, customer scope and claim; never paste production identifiers, files or secrets.

## 28. Tests to create/update

- Link, formatting, generated-reference drift and example/schema/API validation.
- Secret/PII scanning and access-classification checks.
- Runbook tabletop for outage, job replay, inventory mismatch and integration failure.
- Fresh-reader walkthrough of critical operator and next-phase handoffs.

## 29. Regression tests

Re-run docs build/lint/link/schema/API example validation and verify Phase 1–4 cross-links remain valid. Documentation-only work must not change runtime artifacts or invalidate verified tests.

## 30. Commands to run

Run repository documentation build/lint/link checks, contract/example validation, diagram generation, secret/PII scans and required no-runtime-diff checks. Record exact commands/results.

## 31. Documentation to update

This task owns the complete Phase 5 docs set: index, architecture, domain/schema, REST/GraphQL/integrations, role guides, runbooks, test/security/performance evidence, traceability, limitations, release/handoff and ATW-247 log.

## 32. Rollback/recovery note

Revert only incorrect doc changes to the last verified version, preserve evidence/history, repair links/generation and republish. If runtime conflict is found, keep closure blocked and resume at the owning prompt.

## 33. Acceptance criteria

- Phase 5 documentation is complete, consistent, searchable and evidence-backed.
- Critical runbooks/examples are executable and sanitized.
- Steps 11–14 receive explicit stable contracts and boundaries.
- No open documentation conflict masks a runtime blocker.

## 34. Definition of Done

All role guides, references, runbooks, evidence indexes and handoffs are current at one checkpoint; validation and secret scans pass; no dead links/placeholders/unsupported claims remain.

## 35. Completion report format

Report IDs/checkpoint; created/updated docs; source/evidence mapping; validation commands/results; walkthrough/tabletop outcomes; sanitization/access results; remaining limitations; rollback/resume; ATW-248 recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-248 after ATW-247 is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
