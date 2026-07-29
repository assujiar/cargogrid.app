# Prompt 246 — Advanced TMS/WMS Integrity and Security Hardening

    **Prompt ID:** `CG-S10-ATW-027`  
    **Package document:** `CG-AABPP-ATW-246`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-246.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-027` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Phase 5 Assurance; Epic: Integrity and Security Hardening; Capability: Findings Remediation and Adversarial Reverification; Feature slice: repository-controlled defects across TMS/WMS and all GPS source classes; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Repair every blocking finding and adversarially harden multi-source tracking without expanding functional scope.

    ## 5. Business value

    Reduce cross-customer exposure, spoofing, duplicate activity, tracking manipulation, inventory corruption and financial inconsistency.

    ## 6. Source requirement

    ATW-245 findings; all Phase 5 OPS/RPD controls; revised ATW-226 threat model. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    ATW-245 verified with findings classified. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-247..248 and every repaired consumer. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    Harden constraints, RLS, idempotency, event ordering, source mapping, retention, job leases, socket/buffer metadata and indexes only where evidence proves need.

    ## 14. API and integration impact

    Repair auth/field policy, validation, enumeration, callback signature, mobile session, TCP protocol, provider contract, rate limits and failure semantics.

    ## 15. UI/UX impact

    Repair misleading live/stale states, unsafe source overrides, missing consent/permission state, inaccessible recovery, and dead actions.

    ## 16. Security and privacy impact

    Adversarial tests must include:

**Direct device**
- forged IMEI and cross-tenant mapping;
- malformed/oversized frames, invalid CRC, packet flood, socket exhaustion;
- replay, reconnect storms, ACK ambiguity, buffer tampering, exposed port/admin endpoint;
- gateway/database credential leakage and unsafe logs.

**Driver mobile**
- stolen/expired session, wrong trip/vehicle, revoked assignment/consent;
- spoofed/impossible coordinates, permission loss, stale heartbeat;
- falsely displayed background/live state and driver PII leakage.

**Third-party**
- invalid signature/token, replay, schema drift, wrong external vehicle mapping;
- rate-limit bypass, credential exposure, poisoned webhook/poll response.

**Hybrid**
- malicious lower-priority source, rapid source oscillation, conflicting fresh coordinates;
- unauthorized priority override and silent history overwrite.

    ## 17. Performance and reliability impact

    Rerun target profiles and confirm security controls do not create unsafe bypass or unacceptable ACK/queue/projection regression.

    ## 18. Audit and observability impact

    Ensure denials, failures, source changes, privileged replay and recovery are auditable without leaking credentials/raw sensitive data.

    ## 19. Data migration and compatibility impact

    Rehearse every repair migration and deployment rollback on clean install and upgrade.

    ## 20. Detailed implementation tasks

    - Reproduce/rank every finding.
- Implement minimal repair and failing-then-passing regression.
- Run the source-specific adversarial suites.
- Rerun integrated and performance gates.
- Close findings only with durable evidence.

    ## 21. Main flow

    For each finding, reproduce, repair, prove focused regression, rerun impacted integration gates, and close with reviewer evidence.

    ## 22. Alternative flow

    If a safe fix is unavailable, disable only the affected source mode through an approved reversible control and keep repository-controlled blockers open.

    ## 23. Exception flow

    Stop on data-loss risk, ambiguous source ownership, unbackfillable constraint, unreconciled events/jobs, or critical regression.

    ## 24. Business rules

    - Every change maps to a finding.
- Server/database authorization remains authoritative.
- Fixes preserve canonical source history and arbitration.
- No external evidence is fabricated.
- Phase boundaries remain.

    ## 25. Validation rules

    - Before/after evidence addresses the same defect.
- Migration/API/deployment compatibility passes.
- Cross-tenant and source-spoofing negative tests pass.
- Unresolved critical/high blocker prevents verification.

    ## 26. Access rules

    Use least privilege, scoped fixtures and separated admin/device/driver/provider identities.

    ## 27. Test data requirement

    Reuse ATW-245 fixtures plus exploit, flood, malformed protocol, stolen session, spoofed provider, source conflict and outage data.

    ## 28. Tests to create/update

    - One regression per finding.
- Adversarial source-specific tests.
- RLS/RBAC/secret/log/job/realtime tests.
- Event/idempotency/concurrency/recovery tests.
- Full transport/WMS and target-profile reruns.


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

    All ATW-221..245 suites and impacted Phase 1–4 gates.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    Finding root cause/change/evidence, threat model, gateway/mobile/provider/hybrid security runbooks, residual risks.

    ## 32. Rollback/recovery note

    Each repair has reversible code/config/data/deployment plan; preserve events and restore trusted behavior before replay.

    ## 33. Acceptance criteria

    - Every blocking repository-controlled finding is repaired.
- Adversarial, isolation, integrity and recovery gates pass.
- Performance budgets do not critically regress.
- External deferrals remain honest.

    ## 34. Definition of Done

    All scoped findings have minimal reviewed fixes, regressions, migration/deployment/docs/rollback evidence and no critical blocker.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release ATW-247 after ATW-246 is verified. Prompt 248 alone may close Phase 5.
