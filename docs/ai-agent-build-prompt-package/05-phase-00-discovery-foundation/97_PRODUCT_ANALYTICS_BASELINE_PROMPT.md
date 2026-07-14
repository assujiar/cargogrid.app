# Prompt 97 — Product Analytics Baseline

**Prompt ID:** `CG-S5-PH0-018`  
**Package document:** `CG-AABPP-PH0-097`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-97.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-018` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Product Analytics; Epic: Ethical Product Measurement; Capability: Analytics event and metric foundation; Feature slice: Governed event taxonomy, consent and instrumentation baseline; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a minimal product analytics foundation with governed events, tenant-safe identifiers, consent/privacy controls and testable delivery.

## 5. Business value

Measure adoption and workflow quality without leaking business/PII data or distorting transactional performance.

## 6. Source requirement

Charter success measures; Product analytics Phase 0 scope; data classification; observability/security baselines. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved analytics wrapper/schema/config/tests/docs and bounded dependency metadata when authorized. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Unapproved vendor integration, real analytics/tenant data, business feature instrumentation beyond scope. Always preserve unrelated/user-owned changes.

## 13. Database impact

Avoid storing analytics in OLTP unless approved; event/outbox schema requires migration, retention and tenant controls.

## 14. API impact

Define server/client event contract, versioning, validation, idempotency/dedup and delivery failure behavior.

## 15. UI/UX impact

Instrument only approved Phase 0/system events with consent/notice and no sensitive field capture.

## 16. Security impact

Pseudonymize bounded tenant/user identifiers; prohibit payloads with PII/finance/payroll/tax/bank/credentials.

## 17. Performance impact

Batch/async delivery, bounded payload/queue/retry and measured UI/server overhead.

## 18. Audit impact

Track taxonomy/version/owner/purpose/retention/consent and configuration changes.

## 19. Data migration impact

Historical event backfill is prohibited unless separately approved and privacy-reviewed.

## 20. Detailed implementation tasks

1. Define analytics purpose, KPI/guardrail ownership and approved provider/current architecture evidence.
2. Create event taxonomy/schema/version/naming/required context and prohibited fields.
3. Implement minimal foundation client/server wrapper, consent/config, batching/retry/dedup and safe disablement.
4. Add validation/test/debug docs, data-quality monitoring and later module adoption plan.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Approved event is emitted once with valid context and no sensitive payload.

## 22. Alternative flow

Consent/provider/config absent and analytics remains safely disabled without breaking product flow.

## 23. Exception flow

Invalid/prohibited/oversized/duplicate event or provider outage is rejected/queued/dropped by documented policy.

## 24. Business rules

- Analytics is not business audit or system of record.
- Collect minimum necessary data for documented purpose/retention.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every event has owner/purpose/schema/version/trigger and test.
- Prohibited fields and identifier cardinality are automatically checked.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Analytics configuration/data access is least privilege and tenant/privacy aware.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic users/tenants/events, consent states, duplicates, invalid payloads and provider outage. Use synthetic/redacted data only.

## 28. Tests to create/update

- Schema/prohibited-field/context/consent/dedup/batching/retry/disablement tests.
- No-break product flow, performance overhead and data-quality smoke.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Observability, transaction flows, client bundle/privacy and CI.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-97.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Foundation emits only governed valid events with safe failure/disable behavior.
- Privacy, access, performance, schema and documentation evidence passes.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
