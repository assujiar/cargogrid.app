# Prompt 41 — RLS/RBAC Workstream

**Prompt ID:** `CG-S3-ARCH-006`  
**Package document:** `CG-AABPP-ARCH-041`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/06_RLS_RBAC_WORKSTREAM.md`

## Objective and value

Plan defense-in-depth tenant isolation and layered authorization across database, API, jobs, files, UI, search, reports, and exports.

## Preconditions

Prompts 36–40 are complete. Use verified security/schema/route evidence, the four access layers, role/scope/field/record rules, support grants, and Supreme Admin risk disclosure. Do not write policies or permissions.

## Required tasks

1. Model identities, memberships, tenants, organizations, branches, teams, roles, permissions, record scopes, field policies, delegation/support grants, service identities, API keys, and portal principals.
2. Define authorization evaluation order and deny-by-default behavior across UI, REST, GraphQL, server actions, database, storage, jobs, realtime, search, reports, and exports.
3. Map every table/domain to tenant key, RLS policy family, privileged path, bypass prohibition, ownership, and negative-test suite.
4. Define RBAC permission taxonomy, scope lattice, field masking/redaction, record ownership/sharing, separation of duties, approval authority, and sensitive HR/finance access.
5. Define session/MFA/re-authentication, support-access purpose/expiry/audit, key/token rotation/revocation, and machine-identity constraints.
6. Preserve literal Supreme Admin CRUD while documenting that it can defeat audit/ledger/retention evidence; prohibit tamper-proof claims.
7. Define policy rollout order, migration compatibility, cached authorization invalidation, performance/index needs, and emergency recovery.
8. Build a requirement-to-control matrix and atomic backlog for policies, permission seeds, enforcement adapters, and tests.

## Required output

Include access model, evaluation flow, tenant/RLS matrix, permission catalogue, field/record rules, privileged/support paths, API/job/file/report controls, policy performance, rollout sequence, negative/abuse test matrix, accepted-risk disclosure, ADR candidates, atomic backlog, and release blockers.

## Completion gate

Complete only when every data/API/UI/file/report path has enforcement ownership, bypasses are explicit, cross-tenant negatives are planned, Supreme Admin semantics match RPD-022, and no policy/data/config change occurred.
