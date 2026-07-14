# Prompt 43 — API and Integration Workstream

**Prompt ID:** `CG-S3-ARCH-008`  
**Package document:** `CG-AABPP-ARCH-043`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md`

## Objective and value

Plan consistent, secure, tenant-aware REST, GraphQL, webhook, custom-integration, and background-job contracts without duplicating business rules or creating tenant forks.

## Preconditions

Prompts 36–42 are complete. Use verified route/API/dependency/security evidence, canonical flows, boundary contracts, and fixed decisions requiring REST plus GraphQL and case-by-case non-AI integrations.

## Required tasks

1. Define ownership and parity rules for REST and GraphQL over shared domain services; neither interface may bypass validation, access, audit, or idempotency.
2. Define resource/type naming, versioning/deprecation, pagination, filtering/sorting/search, error model, localization, correlation IDs, optimistic concurrency, idempotency keys, batch limits, and async responses.
3. Define GraphQL depth/complexity, persisted-operation, resolver batching, field authorization, introspection/environment, and subscription/realtime controls.
4. Define API keys/OAuth/session/service identities, scopes, tenant binding, rotation/revocation, rate limits, quotas, CORS/CSRF, request limits, and sensitive-field redaction.
5. Define webhooks/events: catalogue, schema/version, signing, replay protection, ordering, retry/backoff, DLQ, delivery logs, endpoint disablement, and reconciliation.
6. Plan each non-AI third-party integration as a bounded custom adapter with owner, credentials, mapping, sandbox/contract tests, observability, runbook, and no generic provider abstraction.
7. Define PostgreSQL durable queue contracts for jobs, retries, idempotency, progress, cancellation, results, tenant context, and threshold-based future worker separation.
8. Map imports/exports, files, reports, and long-running operations; produce contracts, compatibility tests, observability, release sequencing, and atomic backlog.

## Required output

Include interface principles, REST/GraphQL ownership matrix, contract/error/pagination rules, auth/security controls, webhook/event/job architecture, integration inventory/template, import/export/file paths, compatibility/deprecation policy, performance budgets, test matrix, ADR candidates, atomic backlog, and release gates.

## Completion gate

Complete only when every exposed capability has one business-service owner, REST/GraphQL security parity is enforceable, job/integration failure recovery is explicit, RPD-038 is preserved, and no endpoint/integration code is created.
