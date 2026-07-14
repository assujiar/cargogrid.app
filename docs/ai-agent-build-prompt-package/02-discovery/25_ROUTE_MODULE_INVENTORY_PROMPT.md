# Prompt 25 — Route, Surface, Module, and Boundary Inventory

**Prompt ID:** `CG-S2-DISC-005`  
**Package document:** `CG-AABPP-DISC-025`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Application surfaces and domain boundaries  
**Runtime output:** `docs/discovery/05_ROUTE_MODULE_INVENTORY.md`

## Objective and business value

Map every discoverable user route, layout, portal, navigation entry, server action, route handler, REST/GraphQL surface, webhook, job, realtime channel, document/export endpoint, domain module, and shared dependency to its implementation and access boundary. This identifies dead routes, hidden coupling, missing portal isolation, and duplicate domain ownership before architecture planning.

## Source requirements

- Master Prompt Step 2; §§3–4, 11–14, 17, 21.
- CPD-004–019/022/023; RPD-004/005/011/014/017/019/033/038/039.
- GOV-010 API, UX, tenant, performance, and non-regression rules.
- Technical Architecture §§4–8, 13–21, 25–26, 32–33, 36–38.
- UX/Data Design portal, navigation, workflow, data-access, and state sections.
- CTRL-005 functional requirement family map.

## Preconditions and authorization

Prompts 21–24 are complete at the same checkpoint. Read routes, components, navigation, middleware, actions, handlers, GraphQL schema/resolvers, API specs, jobs, database functions, tests, docs, and generated route artifacts. Write discovery docs only; do not add/fix routes or run generators.

## Mandatory pre-flight

Read governance/persistent context and prior outputs. Confirm App Router or alternative routing evidence from repository facts. Identify route-generation/build scripts and do not run them if they write files. Preserve all existing code and dirty changes.

## Detailed tasks

### A. User-facing route inventory

For each route, record:

- URL pattern, route group, page/layout/loading/error/not-found files;
- portal context: Supreme Admin, Tenant Internal, Customer Portal, public/auth;
- intended actors/roles/scopes and authentication gate;
- server/client boundary and data sources;
- main actions/forms/tables/bulk actions/files/exports;
- loading, empty, error, success, denied, degraded/offline state evidence;
- responsive/PWA, white-label/custom-domain, accessibility, and navigation evidence;
- tests and documentation;
- status: `VERIFIED_ACTIVE`, `ACTIVE_UNVERIFIED`, `PARTIAL`, `SKELETON`, `DEAD_SUSPECTED`, `DUPLICATE`, `BLOCKED`.

### B. Programmatic surfaces

Inventory REST route handlers/specs, GraphQL endpoint/schema/resolvers, webhooks, API keys, RPC/functions, server actions, background jobs/queues/schedulers, realtime subscriptions, imports/exports, file upload/download, report generation, AI/OCR calls, and custom connectors.

Record auth, tenant/field/record scope, idempotency, rate limits, versioning, validation, audit, monitoring, retry/DLQ, and consumers. Compare REST and GraphQL coverage without assuming parity from shared types.

### C. Module and ownership mapping

Map files/surfaces/entities to Platform, Commercial, Operations/TMS/WMS, Procurement/Vendor, Finance, HRIS, Ticketing, Customer Portal, Loyalty, Intelligence/AI, and Enterprise Controls. Identify canonical owner, shared primitives, upstream/downstream consumers, circular dependencies, route-local domain logic, and duplicated entities/services.

### D. Navigation and reachability

- Map navigation/menu/command/search entries to routes and entitlements.
- Identify route without navigation, navigation without route, broken/static links, disabled/dead buttons, orphan actions, and public routes relying only on client hiding.
- Identify custom-domain and portal-routing assumptions.

### E. Security and performance boundary

- Identify middleware-only trust, client-only guards, dynamic tenant IDs from route parameters, broad data fetches, client full-dataset loads, missing server pagination, unsafe cache keys, and sensitive data crossing client boundaries.
- Record actual Supreme Admin/support/impersonation routing without modifying it.

## Suggested safe inspection

Use scoped file inventory and `rg` for route conventions, exports, handler methods, server actions, GraphQL definitions, navigation config, middleware, job definitions, and tests. Existing build route output may be read if already present and trustworthy; do not build/generate solely for this prompt.

## Required output structure

1. Checkpoint, routing/framework evidence, limitations.
2. Portal and user-route matrix.
3. Navigation-to-route and route-to-navigation reconciliation.
4. REST endpoint inventory.
5. GraphQL schema/resolver inventory and REST parity matrix.
6. Server action/RPC/webhook/job/realtime/import/export/file/report/AI/connector inventory.
7. Module/domain ownership matrix with dependencies and duplicates.
8. Authentication/tenant/field/record/audit boundary findings.
9. UI state/PWA/white-label/custom-domain/accessibility evidence.
10. Dead/orphan/skeleton/duplicate surface candidates.
11. Preserve-sensitive contracts and recommended Step 3 mapping inputs.
12. Evidence appendix, risks/blockers/issue IDs, output hash.

## Acceptance criteria and Definition of Done

- Every discovered surface has an owner/status/access/evidence row.
- REST and GraphQL are inventoried independently and reconciled.
- All major product domains are mapped to actual paths or scoped `NOT_FOUND`.
- Dead/skeleton classifications are evidence-backed, not deleted/fixed.
- No route, navigation, code, config, generated file, or external state changed.
- Persistent documentation/ledgers are updated.

## Failure, completion, and next prompt

On checkpoint drift, secret/tenant-data exposure, or critical public/tenant access defect, stop and ledger it without remediation.

Report counts by surface/status/domain, key boundaries/coupling, dead candidates, security/performance concerns, files written, and next prompt.

Next: `CG-S2-DISC-006` — Security Baseline Audit.
