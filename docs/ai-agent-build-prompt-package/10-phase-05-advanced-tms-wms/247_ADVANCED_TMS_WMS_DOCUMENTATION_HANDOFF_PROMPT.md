# Prompt 247 — Advanced TMS/WMS Documentation and Handoff

    **Prompt ID:** `CG-S10-ATW-028`  
    **Package document:** `CG-AABPP-ATW-247`  
    **Version:** `0.12.0-multisource-gps`  
    **Runtime build log:** `docs/build-log/phase-05/ATW-247.md`

    Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

    ## 1. Prompt ID

    `{{TASK_ID}}` maps to `CG-S10-ATW-028` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

    ## 2. Parent phase

    `Phase 5 — Advanced TMS and WMS`; package version `0.12.0-multisource-gps`.

    ## 3. Workstream

    Workstream: Phase 5 Operational Readiness; Epic: Documentation and Handoff; Capability: Durable Operator, Developer and Next-Phase Handoff; Feature slice: architecture, deployment, device/mobile/provider operations, contracts, runbooks and evidence; Atomic task: `{{WBS_TASK_ID}}`.

    ## 4. Objective

    Make the verified Phase 5 implementation supportable by operators, device technicians, drivers, developers, support, and downstream phases.

    ## 5. Business value

    Reduce operational error, installation mistakes, outage recovery time and integration ambiguity.

    ## 6. Source requirement

    All Phase 5 evidence and revised multi-source tracking controls. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

    ## 7. Current repository context

    Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

    ## 8. Preconditions

    Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

    ## 9. Upstream dependencies

    ATW-246 verified and all earlier evidence current. Every execution-index prerequisite must be `VERIFIED`.

    ## 10. Downstream impact

    ATW-248, Procurement, HR, Customer Portal, Enterprise integrations. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

    ## 11. Allowed files/folders

    Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

    ## 12. Forbidden files/folders

    Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

    ## 13. Database impact

    None. Document verified canonical entities, relations, RLS, retention and migration behavior.

    ## 14. API and integration impact

    None. Publish verified REST/GraphQL, mobile HTTPS, gateway protocol/deployment, provider adapter, jobs and projection contracts.

    ## 15. UI/UX impact

    Document dispatcher, Driver PWA, device/SIM admin, Fleet Control Tower, customer-safe projection and all degraded states.

    ## 16. Security and privacy impact

    Sanitize secrets/PII/customer data; document purpose/retention, access, incident response and residual risks.

    ## 17. Performance and reliability impact

    Publish target profiles, measured results, scaling, queue/socket budgets, backpressure and monitoring guidance.

    ## 18. Audit and observability impact

    Document audit fields, correlations, event order, source switch, denied access and evidence retrieval.

    ## 19. Data migration and compatibility impact

    Document clean install, gateway deployment, upgrade, backup/restore, replay, reconciliation and rollback.

    ## 20. Detailed implementation tasks

    Publish at minimum:
- Phase 5 architecture index and canonical telemetry data flow;
- subscription/package and entitlement guide;
- Driver Mobile tracking user/admin guide and limitations;
- physical GPS procurement, inventory, SIM, installation, configuration, BAST, replacement and RMA guide;
- Teltonika Codec 8E and GPS Gateway deployment/configuration guide;
- static endpoint, firewall, health, metrics, log and scaling guide;
- third-party provider onboarding and credential rotation guide;
- source arbitration and fallback explanation;
- Fleet Control Tower and customer projection guide;
- gateway, Supabase, mobile, provider, Realtime and network outage runbooks;
- queue/DLQ/replay/reconciliation procedure;
- privacy, consent and retention guide;
- deferred physical-device test plan and conditional provider evidence record;
- Steps 11–14 handoff contracts.

    ## 21. Main flow

    Readers start at one index, choose role/use case, follow versioned procedures, and reach exact diagnostics/recovery.

    ## 22. Alternative flow

    Generate contract references from source where reproducible while retaining curated operational guidance.

    ## 23. Exception flow

    If docs conflict with code/evidence, register blocker and do not invent behavior. Remove secrets safely.

    ## 24. Business rules

    - Docs describe only verified behavior.
- External tests are labeled accurately.
- One canonical term/entity/state definition is reused.
- Customer-safe and restricted docs are separated.
- No unsupported marketing claim.

    ## 25. Validation rules

    - Links/examples/commands match verified contracts.
- No secret/private URL/customer data.
- Runbooks are executable.
- Downstream consumers know owned data and forbidden mutations.

    ## 26. Access rules

    Separate public/customer-safe, tenant admin, operations, driver, installer, developer and restricted security content.

    ## 27. Test data requirement

    Sanitized mobile/device/provider/hybrid, outage, installation, replay and customer examples.

    ## 28. Tests to create/update

    - Link/format/schema/API example validation.
- Secret/PII scanning.
- Runbook tabletop for gateway/provider/mobile/database outage.
- Fresh-reader walkthrough and deferred-test procedure review.


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

    Docs build/lint/link checks and Phase 1–4 cross-links.

    ## 30. Commands to run

    Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

    ## 31. Documentation to update

    This task owns the complete Phase 5 docs, runbooks, evidence index and downstream handoff.

    ## 32. Rollback/recovery note

    Revert incorrect docs to last verified version, preserve evidence, and block closure on runtime conflict.

    ## 33. Acceptance criteria

    - Documentation is complete and evidence-backed.
- Critical runbooks and installation/deployment guides are usable.
- External-evidence status is explicit.
- Downstream handoffs are stable.

    ## 34. Definition of Done

    All role guides, contracts, runbooks, evidence indexes and handoffs are current at one checkpoint with no placeholder or unsupported claim.

    ## 35. Completion report format

    Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

    ## 36. Next eligible prompt

    Only the execution index may release ATW-248 after ATW-247 is verified. Prompt 248 alone may close Phase 5.
