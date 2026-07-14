# Prompt 39 — Repository Target Structure

**Prompt ID:** `CG-S3-ARCH-004`  
**Package document:** `CG-AABPP-ARCH-039`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`

## Objective and value

Define an evidence-backed target repository layout and incremental transition plan that preserves credible brownfield assets and enforces domain, platform, test, migration, and documentation ownership.

## Preconditions

Prompts 36–38 are complete. Respect the approved greenfield/brownfield classification, actual workspace/package-manager topology, framework versions, existing build boundaries, and preserved assets.

## Required tasks

1. Document current structure and propose target locations for apps/portals, packages/modules, database/migrations, workers/jobs, integrations, design system, shared contracts, tests/fixtures, scripts/tooling, observability, infrastructure/config, and docs/runbooks.
2. Use concrete paths only when supported by repository evidence; otherwise use bounded path patterns and mark final names `ADR_REQUIRED`.
3. Define ownership, dependency direction, public exports, server/client boundaries, import rules, generated-artifact policy, and prohibited locations.
4. Define where REST/GraphQL contracts, RLS/RBAC policy tests, migration validation, file controls, job contracts, and integration-specific code live.
5. Map every current asset to `PRESERVE_IN_PLACE`, `MOVE_INCREMENTALLY`, `WRAP`, `CONSOLIDATE`, `RETIRE_AFTER_REPLACEMENT`, or `UNKNOWN_BLOCKED`.
6. Provide transition slices with compatibility, rollback, verification, and no-big-bang constraints.
7. Define repository-level enforcement candidates: lint boundaries, ownership files, architecture tests, CI checks, documentation indices.
8. Estimate impact without creating directories, moving files, or changing configuration.

## Required output

Include current/target trees, directory purpose/owner table, import/dependency rules, contract and generated-code placement, test/migration/doc placement, current-to-target mapping, incremental transition sequence, enforcement gates, ADR candidates, risks, and rollback principles.

## Completion gate

Complete only when target structure aligns with verified topology and domain boundaries, protects user changes/preserved assets, avoids tenant forks and broad rewrites, and gives later tasks explicit allowed/forbidden path guidance.
