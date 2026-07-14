# 08 — API and Integration Workstream

**Prompt:** `CG-S3-ARCH-008` (`CG-AABPP-ARCH-043` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/43_API_INTEGRATION_WORKSTREAM_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `33607fd69bce2181dc16bd696f797329f8c6f8f5` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `07_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero API route, zero GraphQL schema, zero webhook/job/integration implementation |
| Mutation performed | **NONE** — planning only |

### Inputs read (beyond `01–07_*.md`, already fully loaded)

- Tech Arch §19 (Integration Engine, full: pattern table, data-flow diagram, ownership fields)
- Tech Arch §23.2–23.7 (Authentication, Authorization, Optional ABAC, MFA/SSO/OAuth/SAML, Token/Session Security, Encryption/Secrets)
- Tech Arch §25 (API Standard, full: REST recommendation, endpoint naming, request headers, pagination, filter/sort, error schema, rate limiting, webhook signature, long-running job pattern)
- Tech Arch §26 (Integration Standard, full: 17-category matrix with direction/trigger/protocol/auth/payload/retry/timeout/error-handling/idempotency/monitoring/security/ownership columns; guardrails)
- Tech Arch §17.3 (File Security), §32.7 (Query Plan Review — 500ms/2s thresholds), §32.11 (job table field list, already bound in `05_*.md`)
- `03_DOMAIN_BOUNDARY_MAP.md` §5 (10 public contracts), `04_REPOSITORY_TARGET_STRUCTURE.md` §4/§8 (`app/api/v1/**`, `server/contracts/`, `server/integrations/`, `server/jobs/`), `05_DATABASE_SCHEMA_WORKSTREAM.md` §3/§4/§6 (`api_keys`, `webhook_subscriptions`, `webhook_deliveries`, `jobs`, `import_export_jobs`, `import_staging_rows`, `api_logs`, `event_logs`, idempotency/optimistic-concurrency columns), `06_RLS_RBAC_WORKSTREAM.md` §3/§7 (8-stage evaluation flow shared by every surface, RPD-033 mechanism)
- `00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-012 (PostgreSQL durable queue), RPD-033 (REST and GraphQL built together, superseding Tech Arch's "REST first" framing), RPD-038 (case-by-case integrations, no generic provider abstraction)

## 1. Scope and method

This document does not create an endpoint, resolver, webhook, job, or integration adapter (prompt completion gate). It defines the **contract layer** every future Phase-1–9 API/integration prompt must implement against: REST and GraphQL ownership over the same domain services (§3), the request/response/error/pagination rules both interfaces share (§4), GraphQL-specific controls (§5), the auth/security envelope (§6), webhook/event architecture (§7), the 17-category integration inventory and adapter template (§8), the PostgreSQL durable queue job contract (§9), import/export/file/report paths (§10), compatibility/deprecation policy (§11), performance budgets (§12), the test matrix (§13), ADR candidates (§14), the atomic backlog (§15), and release gates (§16).

## 2. Interface principles

1. **One business-service owner, two protocol faces.** Every exposed capability is implemented once in a domain's `server/queries|mutations|actions/` layer (`04_*.md` §4); `app/api/v1/**` route handlers and the GraphQL resolver layer are both thin adapters over that same layer — neither may embed business logic, validation, or a second copy of a rule already defined in the owning domain (`01_*.md` §11 R1, restated for the API surface).
2. **Parity is structural, not a testing convention.** REST and GraphQL enter the same 8-stage evaluation flow (`06_*.md` §3: entitlement → tenant membership → RBAC action → scope → field-level policy → status/value rule → RLS → audit) via the shared `server/policies/permission-check.ts` module. A GraphQL resolver that skipped stage 5 (field-level policy) while its REST equivalent enforced it would be a defect, not an accepted variance — this is the concrete mechanism behind RPD-033 ("REST and GraphQL are built together") and is verified by negative test #15 in `06_*.md` §10 ("A GraphQL resolver and its equivalent REST endpoint produce identical authorization outcomes for the same actor/record").
3. **Neither interface may bypass validation, access, audit, or idempotency.** Restates the prompt's task #1 as four hard rules: (a) every mutation runs the same Zod-or-equivalent validator from `server/contracts/<domain>/` (`04_*.md` §4) regardless of entry surface; (b) every read/write re-enters the 8-stage flow, never a cached "already authorized" shortcut across requests; (c) every mutation is audit-logged per Tech Arch §22.1 regardless of whether it arrived via REST, GraphQL, a Server Action, or a job; (d) every mutation reachable from an external caller carries an idempotency key (§4.7).
4. **No endpoint/resolver/schema field is created ahead of its owning domain's phase.** The API surface grows exactly in step with `01_*.md`'s phase sequence — Platform Core (Phase 1) ships the API/webhook/job foundation (`API-WH`, `JOB`, `IMPEXP` primitives) with no business fields yet; Commercial (Phase 2) is the first domain to expose REST/GraphQL fields over real business data. This mirrors `ADR-CAND-ARCH-011`'s "no empty domain-folder stubs" resolution applied to the API layer.

## 3. REST/GraphQL ownership matrix

| Interface | Transport | Owner of shape | Owner of logic | Consumes | Primary use |
|---|---|---|---|---|---|
| REST (`app/api/v1/**`) | Route Handlers, server-only (Tech Arch §7.5) | `server/contracts/<domain>/` (request/response types, Zod validators) | Owning domain's `server/queries|mutations|actions/` | External customer/vendor/marketplace systems, webhooks, n8n, mobile/thin clients, exports | Public/integration API, per Tech Arch §25.1's REST-first rationale (security, documentation, versioning, rate-limiting, audit ease) |
| GraphQL (single endpoint, schema-first) | Resolver layer, server-only, same trust boundary as Route Handlers | `server/contracts/<domain>/` (same types, re-exported as GraphQL types — no second type definition) | Same owning domain's `server/queries|mutations|actions/` — a resolver calls the identical function a REST handler calls, never a parallel data-access path | Internal SPA/dashboard data-fetching where a client needs to compose multiple domains' data in one round trip (dispatch board, portal dashboard, admin console) | Composed reads across domain boundaries, always through each domain's own query function (never a resolver reading another domain's table directly — `03_*.md` §5's anti-corruption rule applies to resolvers exactly as it applies to REST handlers) |

Ownership is per-capability, not per-protocol: a capability (e.g., "create shipment") has exactly one owning domain (`OPS`) and exactly one implementation (`server/mutations/operations.ts`); both `POST /api/v1/tenants/{tenant_id}/shipments` and the `createShipment` GraphQL mutation call it. This is what makes "every exposed capability has one business-service owner" (the prompt's completion gate) mechanically checkable — grep for a second definition of any mutation name and find none.

Cross-domain GraphQL composition (a single query touching `OPS` and `FIN` fields, e.g. a shipment with its invoice status) resolves each domain's fields through that domain's own resolver/query function and stitches results at the GraphQL layer only — it never becomes a justification for a cross-domain direct table join, preserving `03_*.md` §5's contract boundary at the API layer exactly as it is preserved at the data layer.

## 4. Contract, error, and pagination rules (shared by REST and GraphQL)

### 4.1 Resource/type naming

REST: `/api/v1/tenants/{tenant_id}/<resource-plural>` (Tech Arch §25.2, verbatim examples: `shipments`, `bookings`, `webhooks/events`, `exports`). GraphQL: PascalCase types matching the canonical entity name from `02_*.md`'s data dictionaries (e.g. `Shipment`, `Quotation`), never a REST-resource-shaped type distinct from the canonical entity.

### 4.2 Versioning and deprecation

`v1` is the current and only version at Phase 1–9 (no evidence in the blueprint for a `v2` need). A future breaking change increments the path segment (REST) or is introduced as a new nullable field with the old field deprecated via `@deprecated(reason:)` (GraphQL) — additive, non-breaking changes never require a version bump on either interface (§11 formalizes the exact deprecation window, `ADR-CAND-ARCH-019`).

### 4.3 Pagination

Reproduces Tech Arch §25.4 verbatim, bound to `05_*.md` §7's concrete table assignments: offset (small stable master lists — `chart_of_accounts`, `warehouses`), cursor (large changing lists — `quotations`, `vendor_rates`), keyset (mandatory — `shipment_milestones`, `audit_logs`, `event_logs`, `inventory_ledger`, `tickets`), async export (large full extractions, §10.1). GraphQL connections (`edges`/`pageInfo`) use the identical cursor/keyset semantics as their REST counterpart for the same resource — a GraphQL connection is never offset-paginated where the REST equivalent is keyset-paginated for the same table.

### 4.4 Filtering, sorting, search

Explicit allowlist only (Tech Arch §25.5, verbatim: "Do not allow arbitrary SQL-like filter from client"). Both REST query parameters and GraphQL input arguments are validated against the same `server/contracts/<domain>/` filter schema — one allowlist definition, two syntaxes. Search follows RPD-039 (PostgreSQL FTS/trigram first) under the same RLS policy as the underlying table (`06_*.md` §7) — no separate search-authorization layer.

### 4.5 Error model

Reproduces Tech Arch §25.6's error schema verbatim (`error.code`, `error.message`, `error.details[]`, `error.request_id`, `error.timestamp`) as the REST error body and as the shape of every GraphQL error's `extensions` object — GraphQL transport-level errors still carry the identical `code`/`request_id` pair so a client cannot tell which protocol it used from the error shape alone. `error.code` values are a fixed catalogue per domain (e.g. `SHIPMENT_NOT_FOUND`), never a raw exception message or stack trace (Tech Arch §23 secret-handling principle extended to error responses).

### 4.6 Localization

Error `message` and any user-facing field label resolve through the Configuration Engine's `branding`/`terminology` config type (`07_*.md` §3) — the API never hardcodes an English-only string where a tenant-configured label exists; `error.code` itself is never localized (machine-readable, stable across locales).

### 4.7 Correlation IDs and idempotency keys

`X-CargoGrid-Request-Id` (Tech Arch §25.3) is generated per request if absent and is the value written to `correlation_id` on the `api_logs` row and any downstream `audit_logs`/`event_logs` rows the request produces (`05_*.md` §6) — this is the single thread that lets a support engineer trace one external request through every log table it touched. `Idempotency-Key` (Tech Arch §25.3) is required on every REST `POST`/`PUT`/`PATCH` reachable from an external caller and on every GraphQL mutation field of equivalent effect; it is stored on the target table's `idempotency_key` column (`05_*.md` §4, unique per `tenant_id`) — a retried request with the same key returns the original result, never a duplicate write. Finance postings use the more specific formula from Tech Arch §24.5 (`tenant_id + source_entity_type + source_entity_id + posting_type + posting_version`) in addition to, not instead of, the general idempotency key.

### 4.8 Optimistic concurrency

Every REST `PUT`/`PATCH` and GraphQL update mutation on a high-impact mutable resource (quotations, shipments, invoices, journals, vendor rates — `05_*.md` §4's `record_version` list) accepts the `record_version` the client last read and rejects with a `409`-class `error.code` (e.g. `RECORD_VERSION_CONFLICT`) if it no longer matches — the same `record_version` column that already serves `02_*.md`'s stale-snapshot concern and `ADR-CAND-ARCH-001`'s vendor-rate read now has its API-layer enforcement point defined here.

### 4.9 Batch limits and async responses

Batch operations (bulk status update, bulk import row count) are bounded by an explicit per-resource maximum (exact numeric value `ADR_REQUIRED`, §14) rather than left unbounded; a request exceeding the bound is rejected with a structured error, never silently truncated. Any operation exceeding the synchronous budget (§12) follows Tech Arch §25.9's long-running job pattern (§9 below) — the API never blocks a request past its performance budget waiting for a job to finish.

## 5. GraphQL-specific controls

- **Depth and complexity limits.** Every query is scored against a fixed depth limit and a per-field complexity weight before execution; a query exceeding either limit is rejected before touching the database (exact numeric limits `ADR_REQUIRED`, §14) — this is the GraphQL-side counterpart to REST's explicit filter allowlist (§4.4), preventing an unbounded nested query from becoming the equivalent of an arbitrary SQL-like filter.
- **Persisted operations.** Production GraphQL traffic from CargoGrid's own clients (dashboard, portal) uses a persisted-query allowlist (query hash → registered query text); arbitrary ad hoc query strings are accepted only from authenticated external API-key/OAuth callers explicitly granted that scope (§6), never from the browser session transport, closing the class of introspection-driven query-shape abuse that an open GraphQL endpoint invites.
- **Resolver batching.** Every resolver resolving a list of related entities (e.g. a `Shipment.milestones` field) uses request-scoped batching/deduplication (a DataLoader-equivalent pattern) so N related records never produce N separate database round trips — this is a performance requirement (§12), not merely a code-quality preference, since an unbatched resolver is the concrete mechanism by which a GraphQL query can silently exceed the 500ms query-plan threshold (Tech Arch §32.7) that a REST endpoint's fixed query shape would not.
- **Field-level authorization.** Stage 5 of the 8-stage evaluation flow (`06_*.md` §3) runs per-field, not just per-type — a `Quotation` type's `margin` field is masked exactly as `05_*.md`/`06_*.md` §5.2's `field_masked` policy family masks it over REST, resolved by the same permission-check module, not a GraphQL-specific masking directive that could drift from the REST behavior.
- **Introspection and environment.** Schema introspection is enabled in Development/Testing/Staging and disabled (or restricted to authenticated internal callers) in Production, matching Tech Arch §27.1's environment-data-sensitivity tiers — introspection is a documentation convenience, not a Production-facing capability, given the API-key/OAuth-scoped GraphQL access model (§6).
- **Subscriptions/realtime.** GraphQL subscriptions are scoped to the same allow-listed realtime channels already fixed by `06_*.md` §7 (dispatch board, active shipment timeline, approval counter, ticket assignment, warehouse task queue) — a subscription is never added for a table outside that allow-list, and every subscription payload passes through the identical 8-stage evaluation flow at subscribe time and at every subsequent push (no one-time-check-then-stream-unfiltered pattern).

## 6. Auth and security controls

| Control | Mechanism | Source |
|---|---|---|
| API key principal | `api_keys` table (`05_*.md` §3, Platform `API-WH`); scoped to issuing tenant + declared permission grant (`06_*.md` §2.1) | Tech Arch §23.7 ("API keys shown only once"), `05_*.md` §3 |
| OAuth | Client-credentials/authorization-code flows for external system-to-system and enterprise-IdP integrations respectively (Tech Arch §23.5) | Tech Arch §23.5 |
| Session (browser-originated GraphQL/REST calls from CargoGrid's own dashboard/portal) | Supabase Auth session, secure HTTP-only cookie (Tech Arch §23.6) | Tech Arch §23.2/§23.6 |
| Service identity (job/worker/Edge Function calling an internal API surface) | Service role, server-trusted boundary only, never browser-reachable (Tech Arch §8 Backend Rules) | `06_*.md` §2.1 |
| Tenant binding | Every principal type resolves to exactly one `tenant_id` scope before stage 2 (tenant membership) of the evaluation flow; an API key issued to Tenant A can never present a Tenant B `tenant_id` in its request path/body — enforced identically to Tech Arch §25.2's "server still validates" rule even when tenant is inferable from token/domain | Tech Arch §25.2, `06_*.md` §2 |
| Scopes | An API key/OAuth grant's scope is itself a declared subset of RBAC permission actions (`06_*.md` §5.1's 19 actions) — a scope can only narrow what the underlying role already holds, never widen it (mirrors §11's "no configuration may bypass RBAC" prohibition from `07_*.md`) | `06_*.md` §5.1 |
| Rotation/revocation | Key rotation with overlap window; revoked key fails stage 1 (entitlement) immediately, no propagation delay (Tech Arch §23.7) | Tech Arch §23.7 |
| Rate limits/quotas | By tenant, API client, user, endpoint category, IP/device where needed (Tech Arch §25.7, verbatim five dimensions); exact numeric thresholds per category `ADR_REQUIRED` (§14) | Tech Arch §25.7 |
| CORS/CSRF | Browser-originated session calls (dashboard/portal) require CSRF protection on state-changing requests; CORS allowlist is the tenant's registered white-label domain(s) (Tech Arch §7.13) plus CargoGrid's own app domains — never a wildcard origin | Tech Arch §7.13, §23 |
| Request limits | Payload size cap and per-request field/array-length caps enforced at the Route Handler/resolver entry, before validation runs, to bound worst-case processing cost ahead of §4.9's batch-limit check | Tech Arch §25 (implied by "Do not allow arbitrary SQL-like filter" principle extended to payload shape) |
| Sensitive-field redaction | Every response (REST body or GraphQL field) passes through the same stage-5 field-level policy (`06_*.md` §4/§5.2) — cost/margin/finance/payroll/PII/security fields are masked identically regardless of transport; security-secret fields (API key/webhook secret) are never returned in any response after creation, matching Tech Arch §23.7's "shown only once" | `06_*.md` §5.2 |

No control in this table introduces a second authorization model — every row is a transport-facing instantiation of the single 8-stage flow and the RBAC/RLS design already ratified in `06_*.md`; this document adds no new privilege surface.

## 7. Webhook and event architecture

### 7.1 Catalogue

Outbound webhook event types are one-per-status-transition/exception at minimum, sourced directly from `07_*.md` §7.2's 24 status transitions and §7.4's 16 exceptions — e.g. `shipment.dispatched`, `shipment.epod_completed`, `invoice.posted`, `ticket.escalated`. `webhook_subscriptions` (`05_*.md` §3) stores each tenant's subscribed event types; no event type is invented outside the already-ratified transition/exception catalogues (same "no 92nd rule" discipline `07_*.md` §1 established for configuration).

### 7.2 Schema and versioning

Every webhook payload is the same canonical DTO shape a REST `GET` on the equivalent resource would return (§3's ownership rule extended to async payloads) — a webhook consumer and a polling API consumer see the identical field set. Payload schema versioning follows §11's REST/GraphQL deprecation policy; a breaking payload-shape change ships as a new event type version (e.g. `shipment.dispatched.v2`), never a silent field change on the existing type.

### 7.3 Signing, replay protection, ordering

Reproduces Tech Arch §25.8 verbatim: every outbound webhook includes event ID, event type, timestamp, signature, delivery attempt, and idempotency key; the receiver validates timestamp tolerance and signature (exact algorithm/tolerance window `ADR_REQUIRED`, §14). Ordering is best-effort per subscription (delivery attempt/sequence number included in payload) — a consumer must treat webhooks as at-least-once and out-of-order-possible, matching the retry/DLQ model below; CargoGrid does not guarantee strict ordering across retries.

### 7.4 Retry, backoff, DLQ, delivery logs, endpoint disablement, reconciliation

Webhook dispatch runs on the same PostgreSQL durable queue as every other background job (§9) — a `webhook_deliveries` row (`05_*.md` §3) tracks attempts/backoff identically to a `jobs` row's `attempts`/`max_attempts`/DLQ transition (`05_*.md` §90/110 pattern extended to webhooks, not a second retry mechanism). An endpoint that exceeds a consecutive-failure threshold is auto-disabled (exact threshold `ADR_REQUIRED`, §14) and the tenant is notified through the Notification Engine (`07_*.md` §3); disablement never silently drops future events — they queue against the disabled subscription until re-enabled or the retention window (§11) expires. Delivery logs (`webhook_deliveries` rows, correlated via `correlation_id`) give a tenant a full replay/reconciliation view — "did event X reach endpoint Y, on what attempt, with what response code" is answerable from this table alone, without a separate reconciliation tool.

### 7.5 Inbound webhooks

Inbound webhook receivers (payment callback, GPS event, marketplace order — Tech Arch §19.1) follow the identical data-flow sequence as every other integration adapter: `Authenticate & Verify Signature → Check Idempotency → Validate Payload → Map to Canonical Model → Write Transaction/Queue Job → API/Event Log → Response → Outbound Webhook/Event` (Tech Arch §19.2, verbatim). An inbound webhook is never trusted on signature alone — idempotency and canonical-model validation run unconditionally after signature verification, so a replayed-but-validly-signed payload still cannot double-write.

## 8. Integration inventory and adapter template

### 8.1 Category matrix

Reproduces Tech Arch §26.1's 17-category matrix (Email, WhatsApp, SMS, Google Maps, GPS/Telematics, Shipping line, Airline, Port/Airport, Customs, Banking, Payment gateway, E-invoice/Tax, External accounting, HR/Attendance, Marketplace/e-commerce, Customer API, Vendor API, n8n) verbatim by reference — direction, trigger, protocol, auth, payload, retry, timeout, error-handling, idempotency, monitoring, security, and ownership per category are already fully specified there and are not re-typed here; this document's contribution is the **shared adapter template** every category's implementation must satisfy (§8.2), consistent with `01_*.md` §7's phase/owner assignment (all 17 owned by `INTHUB`, Phase 9, with `NOTIF` covering baseline Email/WhatsApp/SMS dispatch primitives from Phase 1).

### 8.2 Adapter template (binding, one per category, RPD-038)

Every `server/integrations/<category>.ts` (`04_*.md` §4) is a bounded custom adapter, never a generic provider interface (RPD-038, restated verbatim from `01_*.md` §7/§11 R5 and `04_*.md`'s repository-rule table), and must declare:

| Field | Content |
|---|---|
| Owner set | Business owner, technical owner, credential owner, data owner, support owner (Tech Arch §19.3, all five, no fewer) |
| Credentials | Provider key/token storage location (environment/secret manager, never source — Tech Arch §23.7); tenant-scoped where possible (§26.2) |
| Mapping | Payload → canonical entity mapping table (never an arbitrary custom table — §26.2 "Payload must map to canonical entity") |
| Sandbox/contract tests | A contract test against the provider's sandbox/mock endpoint, run in CI (§13), independent of the provider's live availability |
| Observability | Delivery/sync status dashboard entry (category-specific column from Tech Arch §26.1, e.g. "Provider status", "Sync dashboard", "Compliance log") |
| Runbook | `docs/runbooks/<category>.md` (resolves the `ADR_REQUIRED` bounded pattern `04_*.md` line 162 left open — see `ADR-CAND-ARCH-016`, §14, resolved here) |
| Failure policy | Per Tech Arch §26.2: "Third-party downtime should not block core transaction unless the external status is mandatory"; a business-critical failure creates an operational exception (one of `07_*.md` §7.4's 16, e.g. `EXC-INT-001`), never a silent drop |

No category's adapter may be generalized into a shared `IProvider`-style interface spanning categories (`01_*.md` §11 R5, `04_*.md` §4's repository-rule table, restated a third time here because this is this workstream's own completion-gate concern) — genuinely identical cross-category logic (e.g. an HTTP retry/backoff helper) may live in `lib/`, but the adapter's business mapping, credential handling, and error semantics are always category-specific code.

## 9. PostgreSQL durable queue and job contracts

Reproduces `05_*.md`'s already-bound `jobs` table (Tech Arch §32.11 field list, verbatim) as the single job contract every REST/GraphQL long-running operation, webhook dispatch, notification batch, report generation, import/export, and Integration Hub adapter call shares (RPD-012 — no per-domain job table, no second queue technology):

`job_id, tenant_id, job_type, status, priority, payload, attempts, max_attempts, locked_by, locked_until, error, result_url, created_by, created_at, completed_at`

- **Progress/cancellation.** `status` includes an `in_progress`/`cancelling`/`cancelled` path in addition to `queued`/`running`/`succeeded`/`failed`/`dead_letter`; a client-requested cancellation (REST `DELETE`/GraphQL `cancelJob` on the job resource) sets `cancelling` and the worker checks this flag between processing steps — cancellation is cooperative, not a hard kill, consistent with jobs being idempotent/resumable rather than assumed atomic in one step.
- **Idempotency.** Every job is created with the same `Idempotency-Key`-derived value as its triggering REST/GraphQL request (§4.7) stored alongside `payload`, so a retried "create job" call returns the existing `job_id` rather than enqueueing a duplicate.
- **Tenant context.** `tenant_id` on the job row is the actor context a downstream mutation re-enters the 8-stage evaluation flow with (`06_*.md` §7 "Jobs" row, verbatim: "no job silently escalates privilege beyond what its triggering user held").
- **Results.** A file result is a signed URL (`result_url`), gated by the same download-permission-then-signed-URL sequence as any other file (§10.2) — a job never returns a raw storage path.
- **DLQ.** `attempts` reaching `max_attempts` transitions the job to `dead_letter` (`05_*.md` §4, Tech Arch §32.17); requeue requires a Supreme-Admin/authorized-admin action, matching §7.4's webhook DLQ semantics — one DLQ concept, two payload kinds (job, webhook delivery), not two mechanisms.
- **Threshold-based future worker separation.** At MVP the job queue is processed in-process by the Next.js server/Edge Functions (Tech Arch §6 MVP Physical Architecture); a dedicated `workers/` process boundary is split out only once a measured throughput/latency threshold is crossed (`04_*.md` line 116's open bounded pattern) — this document does not lower that threshold decision, it only confirms the job contract above is identical either side of that split (the `jobs` table schema does not change when workers move to a separate process).

## 10. Import/export, files, reports, long-running operations

### 10.1 Import/export

`import_export_jobs` (`05_*.md` §3, a `job_type = 'import'|'export'` specialization of `jobs`, not a second table family) plus `import_staging_rows` (`tenant_id`, `job_id`, `row_number`, `raw_payload jsonb`, `validation_status`, `error` — `05_*.md` §4) is the one import contract every domain's bulk-upload feature uses (Tech Arch §7.17 Bulk Upload Strategy): rows land in staging, are validated, and are inserted into the canonical table row-by-row or in validated batches — a partially-invalid file never corrupts canonical data. Export always uses the async-export pagination class (§4.3) for full extractions and respects the exact same RLS/scope as the underlying resource's list/detail query (`06_*.md` §4, negative test #7) — an export is never a privilege-escalation path.

### 10.2 Files

Reproduces Tech Arch §17.2/§17.3 verbatim as the file contract every document/attachment (quotation, contract, shipment document, ePOD, vendor document, customer document, invoice, financial document, HR document, audit document — §17.1's 10 categories) follows: entity data → template → render → store → metadata → signed URL/access control → file access log. Download permission is checked **before** signed-URL generation (not after), and malware-scan status must be `clean` before any signed URL issues to anyone including the uploader (RPD-032, `06_*.md` §10 test #13) — these are two independent gates, both mandatory, matching `06_*.md` §7's "two independent gates" framing exactly. No public bucket is ever used for tenant documents.

### 10.3 Reports and long-running operations

Reports/dashboards are read-only queries against live OLTP data (RPD-014, `06_*.md` §7) under the same policy family as their underlying table — a report is not a separate API surface with its own authorization model. Any operation exceeding the synchronous performance budget (§12) — a large export, a bulk import, a heavy report render, a scheduled/recurring report (`07_*.md` §13's `report`/`dashboard` config type) — always uses the long-running job pattern (Tech Arch §25.9, verbatim): client creates job → API returns `job_id` → worker processes → client polls or receives webhook → result stored with signed download URL if a file. This is the same job contract as §9, not a report-specific variant.

### 10.4 Contracts, compatibility tests, observability, release sequencing, atomic backlog

Each import/export/report capability ships with: (a) a `server/contracts/<domain>/` type for its payload/result shape (§4.1's naming convention extended to job payloads); (b) a compatibility test asserting the result schema is unchanged across a deploy (§11); (c) an entry in the job-status observability dashboard (shared with §9's job monitoring, not a separate one per capability); (d) release sequencing per the domain's own phase (§15's atomic backlog ties each import/export/report capability to its owning domain's schema slice from `05_*.md` §12, never shipped ahead of the domain's core CRUD).

## 11. Compatibility and deprecation policy

- **Additive changes are always safe:** a new optional REST field, a new nullable GraphQL field, a new webhook event type, a new job type — none require a version bump or a deprecation window.
- **Breaking changes require:** (a) a new REST path version or a new/renamed GraphQL field with `@deprecated` on the old one; (b) both old and new shapes served simultaneously for a fixed overlap window (exact duration `ADR_REQUIRED`, §14, `ADR-CAND-ARCH-019`); (c) a compatibility test asserting the deprecated shape still functions until its removal date; (d) advance notice to affected API-key/OAuth-scoped external consumers (mechanism: notification via the Notification Engine plus a dashboard banner, not email-only).
- **Never break without warning:** the completion gate's "REST/GraphQL security parity is enforceable" extends to compatibility — a security-motivated breaking change (e.g. closing a field-masking gap) is the one exception permitted to ship without the standard overlap window, following Tech Arch §23.10's incident-response sequence instead (Contain stage tightens immediately, forward-fix migration).
- **This is the same expand/migrate/contract discipline** already governing schema migrations (`05_*.md` §8) and configuration-version migrations (`07_*.md` §10) — the API surface does not introduce a fourth, inconsistent compatibility doctrine.

## 12. Performance budgets

| Surface | Budget | Source |
|---|---|---|
| Common REST/GraphQL query | 500ms (query-plan threshold) | Tech Arch §32.7 |
| Complex report query | 2s | Tech Arch §32.7 |
| Rule-evaluation expression inside a request (config engine) | 500ms (adopted from the same threshold, `07_*.md` §12 `ADR-CAND-ARCH-014`) | `07_*.md` §12 |
| Webhook/integration adapter timeout | 5–30s (category-dependent, per Tech Arch §26.1's Timeout column; Customs/External accounting up to 60s) | Tech Arch §26.1 |
| GraphQL resolver batching | N related records = 1 batched round trip, never N (§5) | This document |
| Any operation exceeding budget | Must use the long-running job pattern (§9/§10.3), never a synchronous request held open past its budget | Tech Arch §25.9 |

Budgets are enforced by the same query-plan-review discipline Tech Arch §32.7 already establishes for the database layer — the API/integration layer adds no separate performance-governance process, it consumes that one.

## 13. Test matrix

| Test type | Applied to |
|---|---|
| Contract | Every REST request/response and GraphQL type against its `server/contracts/<domain>/` definition (§4.1); every job payload against its `jobs.payload` contract (§9) |
| Parity | REST vs. GraphQL identical authorization outcome for the same actor/record (`06_*.md` §10 test #15); REST vs. GraphQL identical field-masking outcome (§5) |
| Security | API-key/OAuth scope cannot exceed underlying RBAC grant (§6); rate limit enforced per all five dimensions (§6); CORS allowlist rejects unregistered origins (§6); webhook signature/timestamp-tolerance rejection (§7.3) |
| Idempotency | Retried `Idempotency-Key` returns original result, never a duplicate write (§4.7, §9); retried inbound webhook does not double-write (§7.5) |
| Concurrency | `record_version` mismatch rejected with `409`-class error (§4.8) |
| Webhook | Retry/backoff/DLQ transition (§7.4); endpoint auto-disablement after consecutive-failure threshold (§7.4); delivery log reconciliation query (§7.4) |
| Job | Cancellation is cooperative and observed within one processing step (§9); DLQ requeue requires authorized-admin action (§9); job never escalates privilege beyond triggering user (§9) |
| Integration | Sandbox/contract test per category, independent of live provider availability (§8.2); business-critical failure creates the correct `EXC-INT-001`-class exception (§8.2) |
| Compatibility | Deprecated shape still functions until its removal date within the overlap window (§11) |
| Performance | Every budget row in §12 has a corresponding load/latency test, not a sampling |
| File | Signed URL never issued while `malware_scan_status != 'clean'` (§10.2, restates `06_*.md` §10 test #13); download permission checked before signed-URL generation (§10.2) |
| Import/export | Partially-invalid import file leaves canonical table uncorrupted (§10.1); export respects identical RLS/scope as list/detail (§10.1, restates `06_*.md` §10 test #7) |

## 14. ADR candidates — 1 resolved, 3 new

**`ADR-CAND-ARCH-016` resolved** (raised as an unnumbered bounded pattern in `04_REPOSITORY_TARGET_STRUCTURE.md` line 162): the runbook home for each of the 17 integration categories is `docs/runbooks/<category>.md`, one file per category — matching RPD-038's file-per-category rule exactly, and giving `08.2`'s adapter template a concrete, non-optional field rather than leaving the location open.

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-017` | Exact GraphQL depth/complexity numeric limits and the persisted-operation registration mechanism (§5) | Must be enforceable before query execution, no blueprint numeric evidence | Adopt conservative starting values (e.g. depth 8, complexity budget tied to the §12 500ms threshold via a cost-per-field-type table) at Phase-1 `API-WH` implementation, tuned from measured Phase-1/2 traffic rather than guessed once and left static | Architecture/Performance | `ADR_REQUIRED`, non-blocking — resolve at Phase 1 `API-WH` implementation (Prompt 121+) |
| `ADR-CAND-ARCH-018` | Webhook signature algorithm and timestamp-tolerance window (§7.3); consecutive-failure auto-disablement threshold (§7.4); batch-operation size limits (§4.9); rate-limit numeric thresholds per §6 dimension | Tech Arch §25.7/§25.8/§26 name the *dimensions* and *requirement* but no numeric values anywhere in the blueprint | Adopt HMAC-SHA256 signing with a 5-minute timestamp tolerance (industry-standard webhook pattern, e.g. Stripe-equivalent), a 10-consecutive-failure auto-disable threshold, and rate-limit values tuned from Phase-1/2 measured traffic rather than a blueprint-mandated number that does not exist | Architecture/Security | `ADR_REQUIRED`, non-blocking — resolve at Phase 1 `API-WH` implementation, alongside `ADR-CAND-ARCH-017` |
| `ADR-CAND-ARCH-019` | Exact breaking-change deprecation overlap-window duration (§11) | No blueprint evidence names a duration | Adopt a 6-month minimum overlap window for any REST path-version or GraphQL field deprecation (long enough for external tenant/vendor integration owners to migrate, short enough not to accumulate indefinite dual-serving cost) | Architecture/Product | `ADR_REQUIRED`, non-blocking — resolve at Phase 1 `API-WH` implementation |

## 15. Atomic backlog

Sized 1–3 migrations/slices each, sequenced to `01_*.md`'s phase order and `05_*.md`/`06_*.md`'s existing schema/policy backlogs:

| Slice | Phase | Content | Depends on |
|---|---|---|---|
| API/webhook/job foundation | 1 | `api_keys`, `webhook_subscriptions`, `webhook_deliveries`, `jobs` tables (already in `05_*.md`'s backlog); `server/contracts/` folder (resolves `ADR-CAND-ARCH-010`, `07_*.md`); shared error schema, correlation-ID middleware, idempotency-key enforcement, 8-stage evaluation flow wiring for REST | Platform identity/config/audit core policies (`05_*.md`/`06_*.md` Phase-1 slices) |
| GraphQL foundation | 1 | Schema-first GraphQL server, depth/complexity limiter (resolves `ADR-CAND-ARCH-017`), persisted-operation registry, resolver-batching infrastructure | API/webhook/job foundation |
| REST v1 root + long-running job pattern | 1 | `app/api/v1/tenants/{tenant_id}/**` route scaffold (platform-only fields); job-status polling endpoint; signed-URL result delivery | API/webhook/job foundation |
| Baseline Email/WhatsApp/SMS dispatch (`NOTIF`) | 1 | First 3 of the 17 integration categories, adapter template applied (§8.2), runbooks under `docs/runbooks/` (resolves `ADR-CAND-ARCH-016`) | API/webhook/job foundation |
| Commercial REST/GraphQL fields | 2 | First business-domain fields exposed over both interfaces; parity test suite begins (§13) | GraphQL foundation, REST v1 root, Commercial schema/policy slices |
| Operations REST/GraphQL fields + `import_staging_rows` adoption | 3 | Shipment/dispatch fields; first bulk-import adopter (§10.1) | Commercial REST/GraphQL fields, Operations schema/policy slices |
| Finance REST/GraphQL fields + idempotent-posting API enforcement | 4 | Invoice/journal fields; Tech Arch §24.5 posting-key enforcement at the API layer | Operations REST/GraphQL fields, Finance schema/policy slices |
| Customer/Vendor external API + OAuth/API-key scoping | 2–6 (rolling, per domain readiness) | External-facing subset of Commercial/Operations/Finance/Procurement fields; scope model (§6) applied per category | Respective domain's internal REST/GraphQL fields already shipped |
| Remaining 14 integration categories (`INTHUB`) | 9 | Shipping line, airline, port/airport, customs, banking, payment gateway, e-invoice/tax, external accounting, HR/attendance, marketplace, GPS/telematics, Google Maps, customer API, vendor API, n8n — each adapter template applied (§8.2) | Respective domain's schema/API already shipped; `ADR-CAND-ARCH-018` resolved before payment gateway/banking adapters (signature algorithm) |
| Deprecation-window tooling | 1 (infrastructure), exercised from Phase 2 onward | Dual-serving mechanism for a deprecated field/path (§11, `ADR-CAND-ARCH-019`) | API/webhook/job foundation |

## 16. Exit gates

Every exposed capability has exactly one business-service owner (§3, verified — REST and GraphQL both call the identical function, checkable by grep for duplicate mutation definitions). REST/GraphQL security parity is enforceable, not aspirational (§2 rule 2, §5's field-level authorization, `06_*.md` §10 test #15). Job/integration failure recovery is explicit: DLQ + authorized-admin requeue for jobs (§9), retry/backoff/DLQ/auto-disablement for webhooks (§7.4), sandbox contract tests + business-critical-failure exception for integrations (§8.2) — no failure mode is left as "TBD." RPD-038 is preserved exactly (§8.2, restated three times across this document and `01_*.md`/`04_*.md`, never weakened). No endpoint, resolver, webhook, job handler, or integration adapter code was created (§0, confirmed).

## 17. Completion statement

Interface principles (§2), the REST/GraphQL ownership matrix (§3), shared contract/error/pagination rules (§4), GraphQL-specific controls (§5), the auth/security control table (§6), webhook/event architecture (§7), the 17-category integration inventory with a binding adapter template (§8), the PostgreSQL durable queue job contract (§9), import/export/file/report paths (§10), compatibility/deprecation policy (§11), performance budgets (§12), and the 12-row test matrix (§13) are all defined as planning artifacts, with zero API/integration code created. 1 prior open bounded pattern is resolved (`ADR-CAND-ARCH-016`, runbook location); 3 new ADR candidates are raised (`017` GraphQL limits, `018` webhook/rate-limit numeric values, `019` deprecation window), all non-blocking and deferred to Phase 1 `API-WH` implementation. The atomic backlog (§15) sequences every slice to the phase order already fixed by `01_*.md`, `05_*.md`, and `06_*.md` — no new phase ordering is introduced.

Next eligible prompt: `03-architecture-and-plan/44_UX_DESIGN_SYSTEM_WORKSTREAM_PROMPT.md` → `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`.
