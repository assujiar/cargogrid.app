# Prompt 42 — Configuration Engine Workstream

**Prompt ID:** `CG-S3-ARCH-007`  
**Package document:** `CG-AABPP-ARCH-042`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md`

## Objective and value

Plan reusable tenant-safe configuration engines so workflows, approvals, statuses, numbering, fields, rules, notifications, branding, and localization remain governed rather than hard-coded per module or tenant.

## Preconditions

Prompts 36–41 are complete. Read configuration requirements, 24 business rules, 13 approval patterns, 14 approval use cases, 24 transitions, 16 exception types, and current implementation evidence.

## Required tasks

1. Define engine boundaries for workflow/state machine, approval, numbering, custom fields/forms, business rules, notification/templates, feature flags/entitlements, branding/localization, SLA/calendar, and report scheduling.
2. Specify configuration lifecycle: draft, validate, simulate, approve, publish, version, effective date, snapshot binding, dependency check, rollback/supersede, audit, and archive.
3. Define canonical semantics versus tenant labels; configuration must not change system-of-record meaning or bypass security/finance controls.
4. Define inheritance and precedence across platform, subscription/package, tenant, organization/branch, module, and record context.
5. Define rule inputs/outputs, deterministic evaluation, validation, conflict detection, cycle prevention, timeout, idempotency, and explanation/audit evidence.
6. Define safe extension points and explicitly prohibit tenant code forks, arbitrary executable code, and configuration-based RLS/RBAC bypass.
7. Map phase bootstrap versus later domain adoption, migration from hard-coded behavior, backward compatibility, and rollback.
8. Produce contract/test/observability needs and atomic implementation backlog.

## Required output

Include engine context map, capability/ownership table, configuration schema concepts, lifecycle/state rules, precedence model, evaluation contracts, security/finance guardrails, versioning/migration strategy, module adoption map, test matrix, ADR candidates, atomic backlog, and exit gates.

## Completion gate

Complete only when each configurable catalogue has one engine owner, precedence and version snapshots are deterministic, prohibited bypasses are explicit, and future prompts can implement engines in bounded slices.
