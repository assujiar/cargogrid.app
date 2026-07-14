# Prompt 40 — Database Schema Workstream

**Prompt ID:** `CG-S3-ARCH-005`  
**Package document:** `CG-AABPP-ARCH-040`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md`

## Objective and value

Plan the PostgreSQL/Supabase schema and migration workstream needed to support canonical CargoGrid data safely, incrementally, and with tenant and financial integrity.

## Preconditions

Prompts 36–39 are complete. Read the verified database/migration baseline, canonical flows, boundary ownership, target structure, existing migration conventions, and greenfield/brownfield decision. Do not create or apply migrations.

## Required tasks

1. Define schema/domain ownership, tenant-aware primary/foreign keys, canonical identifiers, organization/branch scopes, timestamps, status/version/effective-date patterns, and data classifications.
2. Plan foundational entities and phased domain tables without attempting a full unreviewed DDL dump.
3. Define constraints for uniqueness, referential integrity, state transitions, soft delete/retention/legal hold, idempotency, optimistic concurrency, immutable-for-normal-role audit/ledger behavior, and the RPD-022 exception.
4. Define finance controls: balanced postings, draft/post/reversal, period locks, allocation/reconciliation, snapshots, lineage, and duplicate prevention.
5. Define spatial/PostGIS, file metadata/quarantine, job queue/retry/DLQ, configuration versions, audit events, outbox/event, import staging, and reporting/read-model needs.
6. Define index and pagination strategy using tenant-leading indexes and measured query evidence; avoid speculative index proliferation.
7. Create migration waves with expand/migrate/contract, rollback/forward-fix policy, backfill batching, lock/timeout risk, seed/reference data, clean rebuild, upgrade path, and compatibility checks.
8. Split future work into atomic schema slices of normally 1–3 migrations with dependencies, tests, rollback, and evidence.

## Required output

Include schema principles, entity/schema ownership, phased schema catalogue, relationship/constraint plan, finance/data-integrity controls, index/query plan, migration waves, seed/reference policy, data transition/backfill plan, test matrix, ADR candidates, risks, atomic workstream backlog, and exit gates.

## Completion gate

Complete only when every canonical entity has an owner/phase, tenant and finance integrity are designed, brownfield migration safety is explicit, migration tasks are atomic, and no schema/database mutation occurred.
