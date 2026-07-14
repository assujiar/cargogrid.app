# Prompt 38 — Domain Boundary Map

**Prompt ID:** `CG-S3-ARCH-003`  
**Package document:** `CG-AABPP-ARCH-038`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/03_DOMAIN_BOUNDARY_MAP.md`

## Objective and value

Define bounded domain ownership and legal cross-boundary contracts so CargoGrid remains one shared product without becoming a coupled monolith or fragmented tenant-specific system.

## Preconditions

Prompts 36–37 are complete. Use verified repository evidence, canonical data ownership, requirement families, and approved greenfield/brownfield strategy.

## Required tasks

1. Define boundaries for Platform, Commercial, Operations, Finance, Procurement/Vendor, HRIS, Ticketing, Customer Experience/Portal, Loyalty, Intelligence/Automation, and cross-cutting infrastructure.
2. Assign entities, tables/schema namespaces, services/modules, UI routes, API types/endpoints, events/jobs, reports, files, and configurations to one authoritative owner.
3. Define public contracts and anti-corruption boundaries for legitimate cross-domain use; prohibit direct writes into another domain’s records.
4. Separate canonical master data ownership from local references/snapshots and define change propagation.
5. Define tenant, organization, branch, record, field, export/search/report, support-grant, and Supreme Admin access responsibilities at boundaries.
6. Identify shared-kernel candidates and constrain them to stable primitives; document duplication that is intentional versus accidental.
7. Reconcile current repository structure with target boundaries and classify preserve/move/wrap/retire/unknown.
8. Register boundary ADRs, conflicts, transition risks, and tests required to enforce ownership.

## Required output

Include boundary context map, ownership catalogue, allowed dependency directions, public contracts, shared kernel, data/access responsibilities, current-to-target mapping, boundary violations, enforcement/test strategy, ADR candidates, and phase ownership.

## Completion gate

Complete only when every requirement family and canonical entity has one primary boundary, cross-boundary writes are controlled, no tenant fork or generic non-AI provider abstraction is introduced, and Prompt 39 can derive a target repository structure.
