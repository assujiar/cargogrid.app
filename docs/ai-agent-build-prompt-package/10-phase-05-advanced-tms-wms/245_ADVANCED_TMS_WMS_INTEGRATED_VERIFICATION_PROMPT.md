# Prompt 245 — Advanced TMS/WMS Integrated Verification

    **Prompt ID:** `CG-S10-ATW-026`  
    **Package document:** `CG-AABPP-ATW-245`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-245.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-026` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Phase 5 Quality Gate; Epic: Integrated Verification; Capability: Cross-Domain TMS/WMS Evidence; Feature slice: 24-capability evidence including four tracking package scenarios; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Verify all Phase 5 capabilities as one coherent extension and expose every remaining repository-controlled blocker before hardening.

    ## 5. Business value

    Prevent locally passing features from masking broken transport, tracking, inventory, customer, or Finance outcomes.

    ## 6. Source requirement

    All Phase 5 advanced OPS anchors and revised multi-source GPS gates. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    All ATW-221..244 tasks verified at one compatible checkpoint. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-246..248. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Prefer no production schema changes beyond approved defect migrations. Verify canonical roots, telemetry models, constraints, RLS, event order, retention, indexes and migration behavior.

    ## 14. API and integration impact

    Verify REST/GraphQL parity, mobile HTTPS, gateway simulator/TCP, provider contract fixtures, canonical normalization/arbitration, jobs, callbacks, and no unauthorized enumeration.

    ## 15. UI/UX impact

    Verify dispatcher, Driver PWA, device admin, Fleet Control Tower, warehouse, and customer-safe surfaces including all degraded states.

    ## 16. Security and privacy impact

    Verify tenant/customer/record/field/file/job/realtime isolation, secrets, forged identifiers, source mapping, privacy and support/admin access.

    ## 17. Performance and reliability impact

    Repeat target profiles for dispatch, warehouse, mobile sessions, TCP gateway, provider contract, hybrid conflicts, jobs, Realtime and customer tracking.

    ## 18. Audit and observability impact

    Verify complete source/config/version/correlation/idempotency/audit evidence and redaction.

    ## 19. Data migration and compatibility impact

    Verify clean install, Phase 4→5 upgrade, representative backfill, backup/restore and rollback/forward recovery.

    ## 20. Detailed implementation tasks

    - Build the full capability × requirement evidence matrix.
- Run transport multi-leg → dispatch → tracking → milestone → delivery scenarios.
- Run mandatory tracking E2Es:
  1. Mobile Tracking package.
  2. Direct Fleet GPS using protocol simulator and gateway container.
  3. Existing GPS Integration using live provider when available, otherwise deterministic contract fixtures.
  4. Hybrid source conflict/fallback/arbitration.
- Run critical WMS E2E.
- Run isolation/security/API/migration/performance/recovery gates.
- Register defects with exact owners.

    ## 21. Main flow

    At one recorded checkpoint, execute the complete matrix, reconcile transport/inventory/Finance outcomes, and mark each gate pass/fail with durable evidence.

    ## 22. Alternative flow

    Use deterministic mocks/simulators for unavailable external systems while preserving contract tests and explicit evidence labels.

    ## 23. Exception flow

    On failure, register severity, owner, reproduction, evidence, invalidated dependent passes, and safe resume. Never waive repository-controlled blockers.

    ## 24. Business rules

    - Exactly all Phase 5 capabilities and anchors must map.
- Canonical roots remain unique.
- Transport event order and inventory/Finance equations reconcile.
- External-evidence deferrals are honest and non-blocking only under the approved policy.
- No production/pilot claim.

    ## 25. Validation rules

    - Each pass has command, environment, checkpoint and fixture profile.
- All repository-controlled critical gates pass.
- Physical device live test may be deferred.
- Third-party live test may be conditionally skipped.
- Simulator/contract gates remain mandatory.

    ## 26. Access rules

    Use least-privilege test roles; no superuser-only acceptance; external credentials and data remain isolated.

    ## 27. Test data requirement

    Tenant A/B, multiple customers, mobile sessions, Teltonika frames, provider fixtures, hybrid conflicts, multi-leg shipments, WMS inventory, concurrency/retries and target-volume data.

    ## 28. Tests to create/update

    - Capability traceability suite.
- Four tracking-package E2Es.
- Transport and WMS browser/API/database E2Es.
- Isolation, field, job, Realtime, idempotency, migration and recovery.
- Load/soak/failure/reconciliation and accessibility.


### External-evidence policy

The implementation must not be blocked merely because physical hardware or a live third-party provider is unavailable at the active checkpoint.

1. **Physical GPS device testing**
   - Hardware-in-the-loop testing with an actual Teltonika or equivalent installed device is deferred until a device is available.
   - Before verification, protocol simulators and recorded vendor frames must prove IMEI handshake, Codec 8 Extended parsing, CRC validation, ACK behavior, duplicate/replay handling, reconnect, malformed payload rejection, buffering, database outage recovery, and canonical projection.
   - Record the deferred item as `DEFERRED_EXTERNAL_HARDWARE_EVIDENCE`, including owner, target device/model, installation prerequisites, exact future test procedure, expected evidence, and safe activation gate.
   - Do not claim “tested on physical device” until that future evidence exists.

2. **Third-party GPS platform testing**
   - A live provider test is conditional on approved credentials, API access, legal/commercial permission, documented rate limits, and a stable provider contract.
   - When those prerequisites are unavailable, mark the live-provider test `CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE`.
   - The provider adapter contract, authentication/signature checks, mapping, retry, rate-limit, schema-drift, idempotency, and failure behavior must still be tested with deterministic mocks, contract fixtures, or a sandbox when available.
   - Do not claim a named provider is live or certified without live evidence.

3. **Closure treatment**
   - These two deferred/conditional external tests are non-blocking when all repository-controlled implementation, simulator/contract, security, migration, load, recovery, and canonical-data gates pass.
   - Any unresolved repository-controlled defect remains blocking.

    ## 29. Regression tests

    Re-run Phase 1–4 critical closures and every ATW focused suite.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Evidence matrix, gate results, external-evidence statuses, errors/issues, architecture, schema/API/data flow and verification log.

    ## 32. Rollback/recovery note

    Verification does not mutate business truth; rollback approved defect fixes, reconcile fixtures/jobs/events, and rerun invalidated gates.

    ## 33. Acceptance criteria

    - All repository-controlled capability and tracking gates pass.
- External deferrals are correctly classified.
- No critical/high repository-controlled blocker remains.
- Phase boundaries and non-regression are proven.

    ## 34. Definition of Done

    Integrated evidence is complete; defects are traceable/retested; simulator/contract, isolation, performance, recovery and docs pass.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release ATW-246 after ATW-245 is verified. Prompt 248 alone may close Phase 5.
