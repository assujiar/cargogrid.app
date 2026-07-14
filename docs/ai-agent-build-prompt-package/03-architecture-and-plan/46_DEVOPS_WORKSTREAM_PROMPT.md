# Prompt 46 — DevOps Workstream

**Prompt ID:** `CG-S3-ARCH-011`  
**Package document:** `CG-AABPP-ARCH-046`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/11_DEVOPS_WORKSTREAM.md`

## Objective and value

Plan safe build, environment, deployment, observability, backup/recovery, secret, and operational controls for a direct-GA multi-tenant CargoGrid release.

## Preconditions

Prompts 36–45 are complete. Read verified scripts/CI/environment evidence, test and migration plans, security constraints, release/go-live requirements, and contractual recovery decisions. Do not mutate CI, infrastructure, environments, or deployments.

## Required tasks

1. Define local/dev/test/staging/UAT/production topology, isolation, data policy, access, configuration promotion, parity, and ownership.
2. Define deterministic package install/build/lint/typecheck/test/artifact pipelines using the repository’s verified package manager and versions.
3. Define migration/seed gates, clean rebuild, upgrade validation, deployment ordering, compatibility window, health/smoke checks, progressive exposure compatible with direct GA, and rollback/forward-fix rules.
4. Define secret/key/certificate lifecycle, least privilege, rotation/revocation, environment validation, and prevention of secret/log/artifact leakage.
5. Define logs, metrics, traces, audit, correlation, dashboards, alerts, SLO indicators, tenant-aware diagnostics, finance/job/integration/security exception monitoring, and retention.
6. Define private file/storage/CDN controls, malware scanning/quarantine, signed access, backup scope, restore validation, and cleanup.
7. Define backup, restore, DR, incident, on-call, escalation, communication, runbook, evidence, and rehearsal. Contractual RPO/RTO must be cited; silence is best effort without guarantee.
8. Define feature-flag/entitlement operation, database/job capacity thresholds, dependency/supply-chain evidence, release artifacts, and atomic DevOps backlog.

## Required output

Include environment model, CI/CD stages, build/artifact provenance, migration/deployment/rollback plan, secrets/storage controls, observability/alert plan, backup/restore/DR plan, incident/support model, capacity/scaling triggers, runbook catalogue, ADR candidates, atomic backlog, and go-live blockers.

## Completion gate

Complete only when every environment and pipeline gate has owner/evidence/rollback, recovery claims match contracts and rehearsals, direct-GA safeguards are explicit, and no external state was changed.
