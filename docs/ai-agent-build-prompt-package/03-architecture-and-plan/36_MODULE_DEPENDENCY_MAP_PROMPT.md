# Prompt 36 — Module Dependency Map

**Prompt ID:** `CG-S3-ARCH-001`  
**Package document:** `CG-AABPP-ARCH-036`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/01_MODULE_DEPENDENCY_MAP.md`

## Objective and value

Produce the authoritative dependency model for CargoGrid platform, domain, portal, reporting, automation, and enterprise modules so sequencing avoids circular coupling and false parallelism.

## Preconditions

Pass the Step 3 entry gate. Read the implementation audit, route/module inventory, strategy decision, technical-debt register, requirement matrix, phase model, and protected decisions. Do not infer an implemented dependency from product documentation alone.

## Required tasks

1. Inventory Platform Core, Commercial, Operations/TMS/WMS, Finance, Procurement/Vendor, HRIS, Ticketing, Customer Portal, Loyalty, Intelligence/Automation, integration, analytics/reporting, file, notification, audit, and job capabilities.
2. Record each dependency as `COMPILE`, `RUNTIME`, `DATA`, `EVENT`, `API`, `CONFIGURATION`, `ACCESS`, `REPORTING`, or `RELEASE`.
3. Separate current dependencies from target dependencies; mark preservation, migration, retirement, unknown, and ADR needs.
4. Identify shared primitives, provider/consumer direction, synchronous versus asynchronous relationships, contract ownership, failure isolation, versioning, and fallback.
5. Detect cycles, reverse dependencies, domain leakage, shared-table coupling, portal-to-database shortcuts, duplicated masters, and phase-order conflicts.
6. Preserve ratified phase splits for TMS, WMS, vendor rate, and Customer Portal rather than duplicating ownership.
7. Produce a dependency table and a compact directed diagram; include cycle-breaking candidates without approving them silently.
8. Define validation rules that later prompts can use to reject illegal imports, schema ownership violations, or phase inversions.

## Required output

Include checkpoint, module catalogue, dependency matrix, directed map, cycles/conflicts, shared primitives, external dependencies, preserved assets, ADR candidates, phase implications, validation rules, risks, and unresolved evidence.

Each edge must contain provider, consumer, type, current/target state, contract/data owner, phase, criticality, failure effect, evidence, and status.

## Completion gate

Complete only when every named module has an owner and phase, every critical edge is sourced, cycles are resolved or blocking, and downstream Prompt 37 can trace canonical flows without inventing dependencies.
