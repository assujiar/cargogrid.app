# Prompt 223 — Fleet, Vehicle, Driver, Device and SIM Operational Baseline

**Prompt ID:** `CG-S10-ATW-004`  
**Package document:** `CG-AABPP-ATW-223`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-223.md`

Do not begin until the runtime execution index marks this task `READY`, all variables are resolved, and the required upstream phase closure matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` maps to `CG-S10-ATW-004` and exactly one approved WBS/task-ledger item. When Prompt 220 decomposes this capability into child tasks, every child must retain this parent prompt ID and receive its own atomic task ID, owner, paths, evidence, rollback, and status.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package version `0.11.0`.

## 3. Workstream

Workstream: Transport Resources; Epic: Operational Resource Control; Capability: Fleet, Vehicle, Driver, Device and SIM Baseline; Feature slice: resource identity, capacity, tracking eligibility, device/SIM/provider mapping and installation lifecycle; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement operational fleet/vehicle/driver resources plus the device, SIM, mobile eligibility, provider mapping, and installation records required by multi-source tracking.

## 5. Business value

Planners receive trustworthy operational resources while CargoGrid can offer mobile tracking, provided physical GPS, existing-provider integration, or hybrid packages without duplicating vendor or employee masters.

## 6. Source requirement

OPS-TMS-001..004; revised ATW-219/226; Step 11 vendor and Step 12 HR ownership boundaries. Cite exact source sections, runtime evidence, ADR/configuration versions, and prerequisite task IDs.

## 7. Current repository context

Record the repository root, active branch, exact HEAD, dirty-worktree ownership, runtime closure IDs, schema and migration state, deployed services, package manager, commands, environment, baseline test results, last trusted checkpoint, and unresolved ledgers. Inspect the actual repository before selecting paths; never infer implementation paths only from this package.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs, architecture decisions, source requirements, and every verified upstream contract. Run feasible baseline gates before mutation. Stop and register a blocker on tenant isolation, customer scope, security, privacy, financial integrity, canonical-source ownership, migration safety, or phase-boundary conflict.

## 9. Upstream dependencies

ATW-221..222, Platform master/config/entitlement, verified Phase 3 resource assignment. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-224..228, ATW-243..248, Customer Portal tracking and Enterprise integrations. Identify every affected schema, service, REST/GraphQL contract, job, integration, deployment, UI, customer projection, test, document, and compatibility consumer.

## 11. Allowed files/folders

Use only exact schema, additive migration, service, API, integration, job, UI, test, deployment, observability, and documentation paths authorized by the runtime WBS. Resolve paths from the repository. Split work when one atomic task would exceed a reviewable migration, deployment, test, or rollback boundary.

## 12. Forbidden files/folders

Unrelated domains; duplicate shipment, trip, vehicle, driver, telemetry, milestone, customer, Finance, or inventory roots; tenant-specific forks; applied-migration edits; destructive cleanup; client-side secrets; hidden authorization or test weakening; fabricated production evidence; unsupported native/offline claims; autonomous operational commitment; and unrelated user-owned changes.

## 13. Database impact

Add or extend fleet categories, vehicle resources, driver operational profiles, tracking eligibility, `gps_devices`, device assignments, SIM inventory, provider vehicle mappings, installation/service history, configuration profiles, health state, and subscription coverage. Device status must support stock, assigned, installed, active, offline, suspended, maintenance, and retired.

## 14. API impact

Provide shared resource, device, SIM, installation, provider-mapping, eligibility, assignment-impact, and health APIs. Secrets and provider tokens are never returned to normal clients.

## 15. UI/UX impact

Create resource catalogue/detail plus device inventory, SIM status, install/replace/transfer workflow, tracking-mode eligibility, last health, and provider mapping views.

## 16. Security impact

Minimize driver PII; protect IMEI/SIM/provider identifiers by role; enforce tenant ownership on every mapping; no vendor banking/tax or HR/payroll duplication.

## 17. Performance impact

Index tenant/branch/type/status/vehicle/device/IMEI/ICCID/provider IDs; batch eligibility and health reads; no per-row external calls.

## 18. Audit impact

Audit resource/device/SIM lifecycle, install/replace/transfer, provider mapping, subscription denial, configuration profile, and privileged identifier access.

## 19. Data migration impact

Adopt Phase 3 resource identities and explicitly reconcile duplicates. Backfill tracking eligibility only from proven ownership; unresolved physical identity remains blocked.

## 20. Detailed implementation tasks

- Define owned, leased, vendor, rental, and ad-hoc vehicle semantics.
- Add device/SIM/provider/installation schemas and lifecycle services.
- Add driver-mobile eligibility and consent prerequisites.
- Add primary/fallback source policy links.
- Integrate dispatch, planning, and Prompt 226 mappings.
- Test duplicate identity, transfer, retirement, privacy, and entitlement.

## 21. Main flow

Ops Admin registers or links a vehicle and driver, assigns permitted tracking modes, installs/maps a device or provider identity, validates eligibility, and activates the resource.

## 22. Alternative flow

A vendor vehicle may use mobile-only tracking; an owned fleet may use direct device; an existing provider may map external IDs; hybrid may designate primary/fallback.

## 23. Exception flow

Block duplicate IMEI/ICCID/vehicle identity, cross-tenant mapping, invalid device transfer, retired device use, expired documents, incompatible entitlement, or provider ID collision.

## 24. Business rules

- Operational resource is not a vendor/employee master.
- One physical device has at most one current vehicle assignment.
- Historical assignments are preserved.
- Device ownership may be CargoGrid, customer, or partner and must be explicit.
- SIM and device status do not automatically authorize tracking.
- Entitlement and active trip assignment are required.

## 25. Validation rules

- Validate identifier format and uniqueness.
- Validate current vehicle/driver/tenant/provider linkage.
- Validate source package and active status.
- Review active-trip impact before transfer/deactivation.
- Reject stale versions and forged identifiers.

## 26. Access rules

Ops Admin manages operational fields; device technicians may update installation evidence within assigned scope; dispatchers read safe eligibility; customers see no device/SIM/driver-sensitive data.

## 27. Test data requirement

Owned/vendor/rental fleets, internal/vendor drivers, device stock, duplicate IMEI, SIM transfer, provider mappings, mobile eligibility, expired documents, Tenant A/B, active-trip transfer conflict.

## 28. Tests to create/update

- Resource/device/SIM lifecycle tests.
- Mapping uniqueness and transfer concurrency tests.
- Entitlement and tracking eligibility tests.
- RLS/RBAC/PII/identifier privacy tests.
- Dispatch/planning/Prompt 226 contract tests.
- Migration and audit reconciliation.

## 29. Regression tests

Re-run Phase 3 assignment, Prompt 222 dispatch, Prompt 224 planning, Prompt 226 ingestion, and future Procurement/HR contract tests.

## 30. Commands to run

Detect and run the repository equivalents of lint, formatting, type checking, unit tests, database reset/migration tests, API/contract tests, integration/job tests, browser/accessibility tests, security and dependency checks, production build, container build, deployment smoke tests, load/failure/recovery tests, and reconciliation commands relevant to the task. Never disable a gate. Record exact commands, environment, fixtures, and results; classify proven pre-existing failures separately.

## 31. Documentation to update

Resource/device/SIM/provider data dictionary, installer checklist, BAST/handover template guidance, replacement/RMA flow, privacy classification, and troubleshooting runbook.

## 32. Rollback/recovery note

Suspend only affected mapping/source, restore last valid vehicle assignment, preserve installation history, and reconcile active trips before resume.

## 33. Acceptance criteria

- Resource and tracking eligibility are deterministic.
- Device/SIM/provider mappings are tenant-isolated.
- No vendor/employee source duplication.
- Tracking packages can be enforced server-side.

## 34. Definition of Done

Operational resources, device/SIM/provider lifecycle, APIs, UI, access, tests, docs, and rollback are complete with no critical identity or privacy blocker.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files, migrations, services, containers, contracts, routes, configuration, and deployment topology; implementation summary; commands and before/after results; tenant/customer/access/privacy evidence; idempotency, concurrency, ordering, reconciliation, performance, outage, recovery, and observability evidence; deferred external-evidence items; residual errors/issues/risks; documentation; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-224 or another dependency-clean task. Prompt 248 alone may close Phase 5.
