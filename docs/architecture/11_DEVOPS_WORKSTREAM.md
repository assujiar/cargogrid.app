# 11 — DevOps Workstream

**Prompt:** `CG-S3-ARCH-011` (`CG-AABPP-ARCH-046` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/46_DEVOPS_WORKSTREAM_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `2c28a6b5047d0241bcebe8cd1529061602ed1273` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `10_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero CI configuration (`docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md`: "no `.github/workflows`"), zero deployment/infra config, zero secret, zero environment |
| Mutation performed | **NONE** — planning only; no CI, infra, environment, deployment, or secret was created or changed (prompt precondition, verified) |

### Inputs read (beyond `01–10_*.md`, already fully loaded)

- Tech Arch §6 (Physical Architecture, full: MVP/Scale-up/Enterprise diagrams and capability table — CDN/Next.js hosting/Supabase Postgres/Storage/backup-PITR/job worker, read replica "if needed" at Scale-up)
- Tech Arch §23.6/§23.7 (Token/Session Security, Encryption/Secret Management)
- Tech Arch §27 (DevOps, full: §27.1 Environment Strategy, §27.2 Branching, §27.3 Test Pyramid, §27.4 Feature Flags)
- Tech Arch §28 (CI/CD, full: §28.1 Pipeline diagram, §28.2 Database Migration, §28.3 Rollback)
- Tech Arch §29 (Environments, full: Environment Configuration table, Seed Data)
- Tech Arch §30 (Observability, full: §30.1 Signals, §30.2 Key Dashboards, §30.3 Alert Examples)
- Tech Arch §31 (Backup and Recovery, full: §31.1 Backup Requirements, §31.2 RPO/RTO Proposed Defaults, §31.3 Recovery Testing)
- Tech Arch §32.8 (Connection Pooling), §32.11 (Background Jobs and Queue), §32.15 (File Upload Strategy), §32.17 (Webhook Retry and Dead-letter) — already bound in `05_*.md`/`08_*.md`, cited not re-derived
- Tech Arch §33 (Scalability, full: Scale Dimensions, Partitioning Candidates, When to Split Services)
- Blueprint `05_CargoGrid_Delivery_Testing_GoLive_Plan.md` §6 (Team Structure — DevOps/Release Manager role, Platform Reliability Pod), §7 (RACI — Deployment/Go-no-go/Incident management rows), §24 (Data Migration, full), §25 (Deployment, full), §26 (Cutover, full), §27 (Go-Live Readiness, full), §30 (Support, full: levels, SLA, incident flow, RCA)
- `05_DATABASE_SCHEMA_WORKSTREAM.md` §3 (`report` schema), §6 (`files`/malware-scan, `jobs` field list), §8 (migration waves)
- `06_RLS_RBAC_WORKSTREAM.md` §4 (`append_only_ledger` policy family), §10 (negative tests, referenced not re-typed)
- `08_API_INTEGRATION_WORKSTREAM.md` §7 (webhook retry/backoff/DLQ), §9 (job contract, worker-split threshold), §10.2 (file/signed-URL sequence), §14 (`ADR-CAND-ARCH-018` webhook numeric values)
- `10_TESTING_WORKSTREAM.md` §4.1 (7 environment tiers, reproduced), §6 (CI gate model, reproduced), §7.4 (DR rehearsal cadence, `ADR-CAND-ARCH-023`), §10.2 (rollback rules, reproduced), §13 (readiness dashboard)
- `01_MODULE_DEPENDENCY_MAP.md` §11 (`ADR-CAND-ARCH-004`, live-OLTP → replica/warehouse threshold — resolved in this document, §9.1)
- `00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-012 (PostgreSQL durable queue), RPD-025 (retention classes, backups 35 days), RPD-031/037 (contract-silent recovery = best effort), RPD-034/036 (direct GA, zero critical defects), RPD-038 (case-by-case integrations)
- `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` (confirms zero CI, zero package manager lockfile, zero deployment config)

## 1. Scope and method

This document does not create, configure, or mutate an environment, pipeline, deployment target, secret, or monitoring resource (prompt precondition and completion gate). It binds the DevOps **plan** every future Phase-0–9 capability prompt and the eventual Phase 0 environment/CI kickoff must satisfy: environment topology (§2), the CI/CD pipeline and artifact provenance (§3), migration/deployment/rollback rules (§4), secret/key/certificate lifecycle (§5), observability (§6), storage/file/CDN controls (§7), backup/restore/DR/incident/support (§8), feature-flag operation and capacity/scaling thresholds including the resolution of `ADR-CAND-ARCH-004` (§9), ADR candidates (§10), the atomic backlog (§11), go-live blockers (§12), and exit gates (§13).

**Guardrail (prompt precondition, binding):** every table/rule below is a plan, not a provisioned resource — `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md`'s zero-CI/zero-infra baseline is unchanged by this document; the first pipeline stage, environment, or secret for any layer is created by its owning Phase-0 environment/CI kickoff prompt, never by this workstream document.

## 2. Environment topology

Reproduces Blueprint §25.1's seven-tier ladder verbatim — identical to Tech Arch §27.1/§29's environment table and to `10_*.md` §4.1 (already cited from `08_*.md` §5's introspection-tier rule), so UX, API, testing, and DevOps all reference the same seven environments, never four competing lists — with the ownership/access/config-promotion columns task #1 requires and `10_*.md` §4.1 did not need to state:

| Environment | Purpose | Data (Blueprint §25.1) | Access (Blueprint §25.1) | Config source (promotion direction) | Owner |
|---|---|---|---|---|---|
| Local | Developer build/test | Synthetic/local seed | Developer | Developer's own `.env.local`, never committed (`ISS-2026-003`, §5 below) | Individual developer |
| Development | Shared dev integration | Synthetic | Engineering/QA | Promoted from Local via PR merge to a short-lived integration branch (Tech Arch §27.2 trunk-based) | Engineering |
| Testing | QA functional/regression | Controlled test data (`10_*.md` §4.2 factories) | QA/Product | Auto-deployed per CI run (§3 below) against `main` | QA/Automation |
| Staging | Production-like release candidate | Masked/synthetic/rehearsal data | Product/QA/DevOps/Security | Deployed from a tagged release candidate, config parity with Production except secrets/external endpoints | DevOps/Release Manager |
| UAT | Tenant UAT and training | Tenant-approved test/migrated data | Implementation/Customer | Deployed from the same release candidate as Staging once Staging exit criteria pass | Implementation Lead |
| Production | Live tenant operations | Production (real) | Controlled role access | Deployed only after Go/No-Go (Blueprint §27.2); never receives an untagged/ad hoc build | DevOps/Release Manager, accountable to Sponsor/CTO (RACI §7) |
| Sandbox | Customer/API experimentation | Synthetic or tenant sandbox | Tenant/admin/API clients | Provisioned per tenant on request, isolated from Production data by the same tenant-isolation RLS design (`06_*.md`), never a shortcut around it | Implementation/Customer Success |

**Isolation:** every non-Local/Development environment is a fully separate Supabase project/database (Tech Arch §6's physical architecture, one `PG`/`ST`/`SB` triple per environment) — no environment shares a database instance with another, closing the same class of leak `10_*.md` §4.3's Tenant A/B fixture is designed to catch at the *tenant* level, applied here at the *environment* level.

**Parity:** Staging is config-parity with Production (Tech Arch §29's Environment Configuration table: identical Auth/DB/Storage/Observability tiers, only secrets and external-integration sandbox-vs-live endpoints differ) — a Staging pass is evidence for Production, not a weaker proxy (Blueprint §25.3's deployment checklist "Performance smoke passed"/"Security scan passed" both run at Staging).

**Seed data (Tech Arch §29 Seed Data, verbatim, reproduced as the binding seed contract):** tenant, company/branch, roles/permissions, user admin/internal/customer, sample customer/vendor, service, quotation, shipment, invoice, ticket, test config — seed must not contain real customer PII, matching `10_*.md` §4.2's synthetic-only rule for the "Seed tenant" factory exactly (one seed definition, not two).

## 3. Build/CI pipeline and artifact provenance

Reproduces Tech Arch §28.1's pipeline verbatim as the binding stage order — identical to `10_*.md` §6's CI gate model (same diagram, cited by reference, not re-derived a second time with different wording that could drift): `Commit/PR → Lint/Typecheck → Unit/Integration Tests → RLS/Security Tests → Build → Migration Check → Deploy Preview/Staging → E2E/Smoke Test → Manual Gate if Prod → Production Deploy → Post-deploy Monitoring`.

`10_*.md` §6 already fixes parallelization, flake/quarantine, retries, coverage meaning, artifact retention, failure ownership, and the no-hidden-failure rule — this document adds only the DevOps-owned layer around that gate model:

- **Deterministic install/build.** Every CI run installs dependencies from a committed lockfile (exact package manager `ADR_REQUIRED`, §10 — `docs/discovery/03_*.md` confirms none is chosen yet) at a pinned Node/runtime version; a build is never produced from an unlocked/floating dependency resolution — this is what makes "deterministic package install/build/lint/typecheck/test/artifact pipelines" (prompt task #2) checkable: the same commit always produces the same artifact.
- **Build artifact provenance.** Every build artifact is tagged with the exact commit SHA it was built from, the pipeline run ID, and the target environment; Production only ever deploys an artifact that already passed every upstream stage in the identical pipeline run — no artifact is rebuilt for Production from source after Staging/UAT sign-off (Tech Arch §28.1's "Deploy Preview/Staging → E2E/Smoke Test → Manual Gate if Prod → Production Deploy" is one linear promotion of one artifact, not a rebuild-per-environment).
- **Dependency/supply-chain evidence (prompt task #8).** Every CI run publishes a software-composition-analysis (SCA) report (Blueprint §20.1's "dependency/SCA" security-scope area) alongside the coverage/test artifacts `10_*.md` §6 already defines; a Critical/High vulnerability in a direct dependency blocks merge per Blueprint §20.2's severity-based exit criteria (same table `10_*.md` §8.2 already cites), a Medium/Low is logged and tracked, never silently ignored.
- **Migration check stage (Tech Arch §28.1's `MIG` node).** Runs `05_*.md` §7.1's clean-rebuild and upgrade migration tests (`10_*.md` §7.1) as a hard gate before any deploy — a migration that only passes clean-rebuild is not release-ready (restated from `10_*.md` §7.1, this is the CI stage that enforces it, not merely documents it).
- **Branching (Tech Arch §27.2, verbatim, binding):** trunk-based with short-lived feature branches; `main` is always production-ready; PR mandatory for every code change; migrations reviewed; security-sensitive changes require architecture/security review — matches this repository's own session-level Git Safety Protocol (no direct push to a shared branch without review), so the CargoGrid application repository and this build-agent's own operating discipline are the same policy, not two.

## 4. Migration, deployment, rollback

### 4.1 Deployment flow and checklist

Reproduces Blueprint §25.2's flow verbatim: `Development → Pull Request → CI (Lint/Unit/Test/Build) → Deploy to Testing → QA Regression/Security/RLS → Deploy to Staging → Performance/Smoke → UAT if needed → Release Candidate → Go/No-Go → Production Deploy → Production Smoke Test → Monitoring & Hypercare`. Blueprint §25.3's 15-item deployment checklist (release scope approved, migration script reviewed, rollback script/procedure ready, feature flags configured, environment variables/secrets verified, CI/CD passed, QA regression passed, RLS/RBAC/tenant isolation passed, performance smoke passed, security scan passed or risk accepted, release notes ready, support playbook updated, production backup taken, go/no-go approved, production smoke test planned, monitoring and alerting active) is reproduced by reference as the binding pre-Production gate — every item is `Required: Yes` per the blueprint, none is optional at CargoGrid's direct-GA maturity (RPD-034/036).

### 4.2 Compatibility window and health/smoke checks

Deployment ordering never breaks a live API/webhook consumer mid-release: `08_*.md` §11's compatibility/deprecation policy (additive changes always safe; breaking changes require a new version/deprecated field plus a fixed overlap window, `ADR-CAND-ARCH-019`) is the binding contract this pipeline's `E2E/Smoke Test` stage verifies before Production promotion. Health/smoke checks (Blueprint §26.1 cutover step 10, Tech Arch §28.1's `E2E/Smoke Test` node) run identically after every deploy, not only at cutover — a green smoke test is a per-deploy requirement, not a go-live-only ceremony.

### 4.3 Progressive exposure compatible with direct GA

RPD-034/036 (binding, restated per `10_*.md` §10.3): direct GA means no external pilot tenant precedes General Availability — every module reaches every entitled tenant at once once its own internal gates pass. This does not forbid **internal** staged exposure: Tech Arch §6's Enterprise Architecture Option table names Feature flags (MVP) → Canary (Scale-up) → Tenant-specific rollout windows (Enterprise) as the release-maturity progression — feature-flag-gated internal rollout (dev-only → QA-only → all internal roles) before a module's tenant-facing GA is compatible with RPD-034/036 because no *external* tenant sees a pre-GA state; a canary or rollout-window mechanism, once scale-up maturity is reached, similarly stages exposure across a module's *already-GA* tenant base for operational safety (e.g. a performance-risk change), never as a substitute for the "all internal gates pass before any tenant sees it" rule for a module's first release.

### 4.4 Rollback and forward-fix

Reproduces Tech Arch §28.3's per-layer rollback strategy verbatim: Frontend (re-deploy previous build), API (versioned endpoint/previous deploy), DB schema (forward-fix preferred, down migration only if safe), Config (config rollback via version — `07_*.md` §10's config-version migration discipline), Feature (feature flag disable), Data (restore only for disaster; business correction for transactions, never a destructive data rollback for a routine posting error). This is the identical rollback doctrine `10_*.md` §10.2 already reproduces from Blueprint §26.2/§26.3 (rollback-consideration list and 8-step rollback procedure) — one rollback procedure across the deployment and testing workstreams, not two independently-authored ones that could drift.

## 5. Secrets, keys, certificates

Reproduces Tech Arch §23.6/§23.7 verbatim as the binding secret-handling contract:

- Service role key never reaches the browser (Tech Arch §23.1's security boundary diagram, `23.6`); only the publishable key crosses the Browser→Next.js boundary.
- Secrets live in an environment/secret manager, never in source code (exact product `ADR_REQUIRED`, §10) — this repository's own `.gitignore` gap (`ISS-2026-003`, still `PLANNED` per `HANDOFF.md` §7) must close before any secret-bearing `.env` file is ever created, at Phase 0 kickoff, not after.
- Webhook secrets are hashed/masked at rest (Tech Arch §23.7, `08_*.md` §7.3's signing contract) and API keys are shown exactly once at creation, never retrievable afterward (Tech Arch §23.7, `08_*.md` §6's "shown only once" row) — a support/admin request to "show me the key again" is structurally impossible to fulfil, by design, not a policy that could be bypassed under pressure.
- **Key rotation with overlap window** (Tech Arch §23.7): a rotated API key/webhook secret keeps the prior value valid for a fixed overlap period so a tenant's integration does not break the instant rotation completes; a revoked (non-rotated) key fails stage 1 of the 8-stage evaluation flow immediately, no propagation delay (`08_*.md` §6, verbatim).
- **Least privilege.** Every CI/CD credential, service-role key, and third-party integration credential (`08_*.md` §8.2's per-category "Credentials" field) is scoped to the minimum environment and action set it needs — a Staging deploy credential can never deploy to Production, and a per-category integration credential can never read another category's data.
- **Environment validation.** The deployment checklist's "Environment variables/secrets verified" item (§4.1) is a CI-gated check, not a manual step: a deploy fails closed if a required secret is absent for the target environment, rather than deploying with a silently-missing credential.
- **Leakage prevention.** No secret, API key, or webhook signature value ever appears in a log line, error response (`08_*.md` §4.5's error model — `error.message`/`error.details` never include raw exception text or credential values), CI artifact, or exported report; this extends Tech Arch §23's secret-handling principle to every observability surface in §6 below, not just the credential store itself.
- **Certificates.** TLS in transit (Tech Arch §23.7) is terminated at the CDN/edge and hosting platform layer (Tech Arch §6's `CDN`/`Next.js App Hosting` nodes); certificate issuance/renewal is the hosting/CDN platform's managed responsibility (exact platform `ADR_REQUIRED`, §10) — CargoGrid does not operate a custom certificate-authority process.

## 6. Observability

### 6.1 Signals, dashboards, alerts

Reproduces Tech Arch §30 verbatim as the binding observability contract:

- **Signals (§30.1):** Logs (app, API, job, webhook, auth/security), Metrics (latency, error rate, throughput, DB query duration, queue depth), Traces (request → server action/API → DB → external call), Audit (business/security change — `05_*.md` §6's five append-only log tables), Alerts (Sev1 errors, auth anomaly, RLS failure, job backlog, webhook failure).
- **Key dashboards (§30.2, 11 named):** Application health, API health, Database performance, Slow query, Queue/job health, Integration health, Tenant usage and errors, Security events, Financial posting exceptions, Storage usage, Import/export jobs — this is the fixed dashboard catalogue every domain's Phase-1+ implementation prompt wires its own metrics into; no domain invents a twelfth dashboard without extending this list here first.
- **Alert examples (§30.3, 8 named, with thresholds):** API p95 latency (>performance budget for 10 minutes — ties to `08_*.md` §12's budget table), Error rate (>1% critical endpoints), DB CPU/connection saturation (sustained high usage), Slow query (>2 seconds repeated — same threshold as `05_*.md` §7/`10_*.md` §8.1), Queue backlog (oldest job age > SLA), Webhook failure (repeated failed attempts), Cross-tenant policy test failure (**immediate Sev1** — the one alert with no threshold delay, matching `06_*.md`/`10_*.md` §5.2's Critical-severity `TI-*` framing exactly), Storage signed URL anomaly (unusual volume).

### 6.2 Correlation, tenant-aware diagnostics, exception monitoring

`X-CargoGrid-Request-Id`/`correlation_id` (`08_*.md` §4.7, reproduced not re-derived) is the single thread every dashboard in §6.1 above filters by when a support engineer needs to trace one tenant's one request across Logs/Metrics/Traces/Audit — this is what makes "tenant-aware diagnostics" (prompt task #5) concrete rather than aspirational: every one of the 11 dashboards supports a `tenant_id` + `correlation_id` filter, not only the "Tenant usage and errors" dashboard. Finance/job/integration/security exception monitoring is not a twelfth dashboard but a filtered view of the existing ones: "Financial posting exceptions" (§30.2, already named) surfaces `FINTEST-022`-class rejected-posted-mutation attempts (`10_*.md` §5.3); "Queue/job health" surfaces `dead_letter` transitions (`05_*.md` §6, `08_*.md` §9); "Integration health" surfaces `EXC-INT-*`-class exceptions (`08_*.md` §8.2); "Security events" surfaces the Cross-tenant-policy-test-failure alert (§6.1) and every `TI-*`-class negative-test failure in Staging/UAT.

### 6.3 Retention

Applies RPD-025's class-based retention schedule (binding, verbatim): Finance/tax records 10 years, audit/security 7 years, operational data contract term + 90 days, backups 35 days, legal hold overrides deletion — logs/metrics/traces themselves fall under "operational data" unless they contain audit/security content (`05_*.md` §6's `audit_logs`/`support_access_logs` tables), in which case the 7-year class applies to the log row, not the 35-day backup class. No observability tool retains data past its RPD-025 class without an explicit legal-hold flag — a monitoring vendor's own default retention setting is never treated as an override of this schedule.

## 7. Storage, file, and CDN controls

Reproduces Tech Arch §17.3/§32.15 as the binding file/storage contract, already established in `08_*.md` §10.2 and cited here for the DevOps-owned infrastructure layer:

- **Malware scanning/quarantine gate.** `files.malware_scan_status` (`05_*.md` §6) must equal `clean` before any signed URL issues to anyone other than the uploader (RPD-032) — a file in `pending`/`infected`/`error` status is quarantined (no signed URL issued, `infected` files flagged for admin review), never silently served.
- **Signed access.** No public bucket is ever used for tenant documents (`08_*.md` §10.2, verbatim); download permission is checked *before* signed-URL generation, and every signed URL carries a bounded expiry — this is the same two-independent-gates framing `06_*.md` §7 already establishes (permission check, then malware-scan check), operated here as infrastructure policy, not merely application code.
- **CDN.** Static assets and public (non-tenant-document) content are CDN-cached at the edge (Tech Arch §6's `CDN` node); tenant document signed URLs are never cached at a shared CDN edge in a way that could serve one tenant's file to a cache hit from another tenant's request — CDN caching is scoped to non-tenant-scoped static assets only.
- **Backup scope for storage objects** (Tech Arch §31.1's "Storage objects" row): version/lifecycle policy plus a backup strategy distinct from the OLTP database backup (§8.1 below) — a storage-object backup restores files, an OLTP backup restores metadata/rows; both must succeed together for a full restore to be valid (§8.2's restore-validation rule).
- **Restore validation.** A storage restore test is one of Tech Arch §31.3's six named recovery-testing items (reproduced in §8.2 below) — restoring files without restoring the `files` metadata rows that reference them (or vice versa) is an incomplete restore and fails validation.
- **Cleanup.** Every synthetic/test-created file (from `10_*.md` §4.2's synthetic dataset factories) is purged by the same automated sweep that purges its owning `synthetic = true` tenant — a test file never accumulates indefinitely in a non-Production storage bucket.

## 8. Backup, restore, DR, incident, on-call, escalation, runbook, rehearsal

### 8.1 Backup requirements and RPO/RTO

Reproduces Tech Arch §31.1/§31.2 verbatim as the binding backup contract:

| Data | Backup mechanism | Source |
|---|---|---|
| PostgreSQL OLTP | Automated backup + PITR where plan supports (Supabase-managed, matching Tech Arch §6's `PG → BAK[Backup/PITR]` physical-architecture node — no separate third-party OLTP backup tool is introduced) | Tech Arch §31.1, §6 |
| Storage objects | Version/lifecycle policy and backup strategy (§7 above) | Tech Arch §31.1 |
| Configuration | Versioned and exportable (`07_*.md` §10's config-version model is itself the backup/rollback mechanism — no separate config backup tool) | Tech Arch §31.1 |
| Audit logs | Retained per RPD-025 (7-year class, §6.3) | Tech Arch §31.1, RPD-025 |
| Secrets | Managed separately from the database dump (§5 above); never included in a DB backup/restore payload | Tech Arch §31.1 |
| Integration config | Exportable/migratable with masking (credential values masked on export, matching §5's leakage-prevention rule) | Tech Arch §31.1 |

RPO/RTO (Tech Arch §31.2, verbatim, tiered): MVP baseline 15 minutes RPO / 4 hours RTO; Scale-up 5–15 minutes RPO / 2–4 hours RTO; Enterprise contract-defined. Per RPD-031/037 (binding, restated exactly as `10_*.md` §10.3/§7.4 already cite): these are proposed defaults, not a universal guarantee — a specific tenant's contracted RPO/RTO governs when one exists; contract silence means best effort without a guaranteed recovery commitment. RPD-025's 35-day backup retention (§6.3) is the outer bound for how far back a restore can reach regardless of RPO/RTO tier.

### 8.2 Recovery testing

Reproduces Tech Arch §31.3's six-item list verbatim as the binding rehearsal scope, executed at the cadence `10_*.md` §7.4/§11 already resolves (`ADR-CAND-ARCH-023`: quarterly, deferred to Phase 0 testing foundation — not re-opened here, only confirmed as this document's own backup/DR cadence too, so the testing and DevOps workstreams cite one cadence, not two): quarterly restore rehearsal, tenant-level logical export test, storage restore test (§7 above), config rollback test (`07_*.md` §10), financial reconciliation after restore (ties to `10_*.md` §5.3's `FINTEST-*` suite run post-restore), incident runbook test (§8.4 below).

### 8.3 Migration and cutover rollback (reproduced by reference, not re-authored)

Blueprint §24.5's migration-rollback procedure (freeze user access → disable affected feature flag/module → restore database from pre-migration backup or reverse migration if safe → verify tenant access and data counts → communicate status → re-plan final migration) and Blueprint §26.3's cutover-rollback procedure (stop access/disable via feature flag → communicate/freeze → restore previous application version → restore database snapshot or verified rollback migration → re-validate RLS/RBAC and critical data → smoke test → communicate → RCA before retry) are the two rollback procedures `10_*.md` §10.2 already reproduces from the same source — this document does not author a third version; DevOps' role in both is the same as §4.4's per-layer rollback table: execute the DB/infra restore step, everything else is Data Migration Lead / Release Manager / Implementation Lead ownership per Blueprint §24.3/§26.1's stage-owner columns.

### 8.4 Incident, on-call, escalation, support model

Reproduces Blueprint §30 verbatim as the binding incident/support contract:

- **Support levels (§30.1, 6 tiers):** L0 Self-service (Customer Success/Product), L1 Functional support (Support Team), L2 Product support (Product Support/Implementation), L3 Engineering (Engineering), Security escalation (Security Lead), Infrastructure escalation — **DevOps/SRE**, scope: downtime, database/storage, CI/CD, deployment, backup/restore. Infrastructure escalation is this document's own on-call ownership boundary: any incident reaching this tier is DevOps' to run, using the runbook catalogue in §8.5.
- **Priority/SLA (§30.2, verbatim):** P1 Critical (production down, tenant leak, financial corruption, severe security issue) — 15-minute response, work continuously until mitigation, RCA required, status every 30–60 min; P2 High — 1-hour response, 1-business-day target; P3 Medium — 4-business-hour response, 3–5 business days; P4 Low — 1-business-day response, planned backlog.
- **Incident flow (§30.3, verbatim):** Detect/Report → Triage → Severity Classification → Mitigation → Communication (parallel to Fix/Workaround) → Validation → Close Incident → RCA → Preventive Action.
- **Incident fields (§30.4, verbatim, 12 fields):** Incident ID, Tenant, Module, Severity, Impact, Start time, Owner (Incident Commander), Status, Root cause, Workaround, Resolution, RCA, Preventive action.
- **RCA requirement (§30.5, verbatim, binding):** mandatory for P1, security incident, tenant isolation failure, financial posting/data corruption, production rollback, repeated P2, major data migration failure — an RCA in this list is never optional or deferred past the incident's close.
- **On-call ownership:** the Infrastructure-escalation tier (DevOps/SRE) and the Security-escalation tier (Security Lead) are distinct rotations — a database/deployment incident and a tenant-leak/auth incident page different owners first, converging at Incident Commander level only if both domains are implicated (e.g. a cross-tenant leak caused by a bad deployment pages both).

### 8.5 Runbook catalogue

`08_*.md` §8.2/§14 already resolves `ADR-CAND-ARCH-016`: one runbook per integration category at `docs/runbooks/<category>.md` (17 files, one per Tech Arch §26.1 category). This document adds the DevOps-owned infrastructure runbook set, same location convention, same one-runbook-per-scope rule:

| Runbook | Trigger | Content anchor |
|---|---|---|
| `docs/runbooks/deployment-rollback.md` | Any §4.4 rollback trigger | Tech Arch §28.3 per-layer table |
| `docs/runbooks/database-restore.md` | Any §8.1/§8.2 restore need | Tech Arch §31.1/§31.3 |
| `docs/runbooks/migration-rollback.md` | Blueprint §24.5 rollback condition | §8.3 above |
| `docs/runbooks/cutover-rollback.md` | Blueprint §26.2 rollback criterion | §8.3 above |
| `docs/runbooks/security-incident.md` | Tech Arch §23.10's 8-stage incident-response sequence | Tech Arch §23.10, §30.5 RCA rule |
| `docs/runbooks/tenant-isolation-failure.md` | Cross-tenant policy test failure alert (§6.1, immediate Sev1) | `06_*.md`/`10_*.md` §5.2 |
| `docs/runbooks/webhook-endpoint-recovery.md` | Consecutive-failure auto-disablement (`08_*.md` §7.4) | `08_*.md` §7.4, `ADR-CAND-ARCH-018` |
| `docs/runbooks/job-dlq-requeue.md` | `dead_letter` job requiring authorized-admin requeue | `05_*.md` §6, `08_*.md` §9 |
| `docs/runbooks/secret-rotation.md` | Scheduled or incident-triggered key/secret rotation | §5 above |

No runbook is invented beyond a trigger already named in this document or `08_*.md` — the catalogue grows only when a new trigger is architected, never speculatively.

## 9. Feature flags, capacity/scaling thresholds, and release artifacts

### 9.1 `ADR-CAND-ARCH-004` resolved — live-OLTP-to-replica/warehouse threshold

**Question (from `01_*.md` §11):** at what threshold does live-OLTP reporting (RPD-014 default) graduate to read replicas or a reporting warehouse, and who owns that trigger?

**Resolution:** the threshold is **measured, not calendar- or size-scheduled**, and is owned by DevOps + Data/Architecture jointly (matching the Platform Reliability Pod's composition, Blueprint §6.3). Graduation is triggered when **any one** of the following, already-defined signals is sustained for more than one week (not a single spike):

1. The "DB CPU/connection saturation" alert (§6.1, Tech Arch §30.3) fires repeatedly and root-causes to reporting/dashboard query load specifically (not OLTP write load) — traceable via the "Database performance"/"Slow query" dashboards (§6.1) filtered to `REP`-owned query patterns (`01_*.md` §2.1).
2. The "Slow query" alert's 2-second threshold (§6.1, matching `05_*.md` §7/§9/`10_*.md` §8.1's identical number) is repeatedly breached by a report/dashboard query *after* the materialized-view/pre-aggregation optimizations Tech Arch §32.9/§32.12 already mandate have been applied — i.e., the threshold is not "a report is slow," it is "a report is slow even once already using the sanctioned read-optimization pattern."
3. A `PERF-*` load-test scenario tied to reporting/dashboard volume (`10_*.md` §7.4: `PERF-005` executive dashboard at 1M+ finance rows) misses its Blueprint §21.1 target at Staging scale after the same optimization pass.
4. §32.8's "reporting workload must not starve OLTP" rule is measurably violated — OLTP write/read latency degrades correlated with reporting query concurrency.

When triggered, the escalation path follows Tech Arch §6's own Scale-up Physical Architecture (already diagrammed: `PG → READ[Read Replica/Reporting Replica - if needed]`) — a read replica is the first-line response (lower operational cost, no new query language); a dedicated reporting warehouse is reserved for a subsequent, separately-justified threshold (sustained replica saturation *after* the replica is already in place) and is not evaluated until a replica alone proves insufficient. This closes `01_*.md` `ADR-CAND-ARCH-004` with a concrete, evidence-based trigger definition rather than leaving "threshold-driven" undefined — the actual go/no-go decision still requires the measured Phase-0+ system Tech Arch's own physical-architecture diagram already anticipates ("if needed"), so this resolution fixes *what to measure and who decides*, which is what the ADR asked for; it does not fabricate a numeric baseline the still-`UNKNOWN` performance baseline (`docs/discovery/08_PERFORMANCE_BASELINE.md`) cannot yet supply.

### 9.2 Feature-flag/entitlement operation

Reproduces Tech Arch §27.4 verbatim as the binding feature-flag capability set: tenant, module, feature, environment, role/user cohort, rollout percentage, effective date, rollback. **Feature flags must not bypass security checks** (Tech Arch §27.4, restated a second time — `01_*.md`'s `DUP-012` already fixes this as a standing rule: "flags never bypass security") — a flag controls *whether* a code path is reachable, never *whether* the 8-stage evaluation flow (`06_*.md` §3) runs once it is. Flag state changes are versioned and auditable (§4.4's "Config rollback via version" applies identically to flag state, since flags are one `CONFIG_SET`-model config type per `07_*.md` §3).

### 9.3 Database/job capacity thresholds

- **Connection pooling** (Tech Arch §32.8): serverless/Next.js deployment uses a connection pooler; long-running jobs use controlled concurrency, never unbounded worker fan-out against the pool — the same "reporting must not starve OLTP" principle from §9.1 applies symmetrically to job-worker connection usage.
- **Queue depth** (§6.1's alert, Tech Arch §30.3): "oldest job age > SLA" is the binding queue-health signal; a sustained breach is the trigger for `08_*.md` §9's already-flagged future worker-process split (Tech Arch §6's `JOB[Background Job Worker]` in-process at MVP, split to a dedicated `workers/` boundary only once this measured threshold is crossed) — `08_*.md` §9 explicitly deferred the numeric threshold; this document fixes *which signal* answers it (queue-depth/oldest-job-age SLA breach), consistent with §9.1's evidence-based-not-guessed approach to every capacity trigger in this workstream.
- **Webhook/integration throughput:** the same consecutive-failure auto-disablement threshold (`08_*.md` §7.4, `ADR-CAND-ARCH-018`) is the capacity signal for per-category integration adapter health — no separate DevOps-owned threshold is introduced for what `08_*.md` already owns.

### 9.4 Release artifacts

Every Production release publishes: the tagged build artifact (§3, with commit SHA/pipeline-run provenance), the migration log (Blueprint §26.1 step 5's evidence column), the SCA/dependency report (§3), the deployment checklist's completed state (§4.1, all 15 items), and release notes (Blueprint §25.3's "Release notes ready" item) — these five artifacts together are what "release artifacts" (prompt required output) means concretely; none is optional at direct-GA maturity.

## 10. ADR candidates — 1 resolved, 4 new

`ADR-CAND-ARCH-004` is resolved in full at §9.1 above (evidence-based replica/warehouse trigger, not a guessed number).

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-024` | Exact CI/CD platform product and package manager (§3) | Must support the pipeline order in Tech Arch §28.1 and the branching model in §27.2; `docs/discovery/03_*.md` confirms zero existing choice | Adopt a single CI/CD platform integrated with this repository's Git host and a single deterministic package manager with a committed lockfile (exact products deferred to avoid presuming a vendor ahead of Phase 0 tooling evaluation, matching `10_*.md` `ADR-CAND-ARCH-022`'s identical deferral pattern for the test runner) | DevOps/DevEx | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 environment/CI kickoff |
| `ADR-CAND-ARCH-025` | Exact secret-manager product (§5) — dedicated secret-manager service vs. hosting-platform-native environment variables | Must support least-privilege scoping per environment (§5) and rotation with an overlap window (Tech Arch §23.7) | Adopt the hosting/Supabase platform's native environment-variable and project-secret mechanism at MVP (matches Tech Arch §6's already-ratified Supabase-centric physical architecture, avoids introducing a second secret store with its own access-control surface); re-evaluate a dedicated secret-manager service only if Enterprise tenant contracts require tenant-specific key custody beyond what the platform-native mechanism provides | DevOps/Security | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 environment/CI kickoff |
| `ADR-CAND-ARCH-026` | Exact observability/APM tool for logs/metrics/traces/dashboards/alerts (§6) | No blueprint-evidenced product; must support all 11 §6.1 dashboards and the 8 named alerts with tenant/correlation-ID filtering (§6.2) | Adopt a single integrated observability platform (logs+metrics+traces+alerting in one product to avoid a four-tool correlation problem) at Phase 0, sized to the MVP tier first (Tech Arch §6's "Observability: Basic logs/metrics" MVP row) and upgraded to the Scale-up tier's "Full dashboard/alert" capability without a tool migration if the chosen product supports both tiers | DevOps | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 environment/CI kickoff |
| `ADR-CAND-ARCH-027` | Exact hosting/CDN platform (§2, §5's TLS/certificate ownership) | Must support the Next.js App Hosting + CDN/Edge Network nodes in Tech Arch §6's physical architecture and the seven-environment topology (§2) | Adopt a platform offering managed TLS/certificate issuance, preview-environment-per-PR (matching Tech Arch §28.1's "Deploy Preview/Staging" node), and edge/CDN in one product (exact product deferred to Phase 0 evaluation, consistent with `ADR-CAND-ARCH-024`'s CI/CD deferral reasoning) | DevOps | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 environment/CI kickoff |

## 11. Atomic backlog

Sized 1–3 slices each, sequenced to `01_*.md`'s phase order and this document's own §2–§9:

| Slice | Phase | Content | Depends on |
|---|---|---|---|
| Environment provisioning (7 tiers) | 0 | Local/Development/Testing/Staging/UAT/Production/Sandbox provisioned per §2's isolation rule; resolves `ADR-CAND-ARCH-027` (hosting/CDN) | Toolchain baseline (Phase 0) |
| CI pipeline foundation | 0 | Lint/typecheck/unit/build/migration-check stages wired per §3; resolves `ADR-CAND-ARCH-024` (CI/CD platform/package manager) | Environment provisioning |
| Secret/key management foundation | 0 | Environment-scoped secret storage, rotation-with-overlap-window mechanism (§5); resolves `ADR-CAND-ARCH-025`; closes `ISS-2026-003` (root `.gitignore`) | Environment provisioning |
| Observability foundation | 0 | 11 dashboards + 8 alerts wired (§6); resolves `ADR-CAND-ARCH-026`; correlation-ID propagation verified (shared with `10_*.md`'s test-data factory foundation) | CI pipeline foundation |
| Backup/PITR + storage backup foundation | 0 | Supabase-managed OLTP backup/PITR enabled; storage-object versioning/lifecycle policy (§7, §8.1) | Environment provisioning |
| Deployment pipeline + rollback runbooks | 0–1 | Full Tech Arch §28.1 pipeline wired end-to-end; `docs/runbooks/deployment-rollback.md`, `database-restore.md` authored (§8.5) | CI pipeline foundation, Secret/key management foundation |
| Feature-flag infrastructure | 1 | `feature_flags` table (already in `05_*.md`'s backlog) wired to §9.2's 8 capability dimensions; DUP-012 enforcement test | Deployment pipeline + rollback runbooks |
| Incident/support tooling | 1 | Incident-fields schema (§8.4), P1–P4 SLA paging rules, `docs/runbooks/security-incident.md`, `tenant-isolation-failure.md` | Observability foundation |
| Job/queue capacity monitoring | 1 | Queue-depth/oldest-job-age alert wired (§9.3); `docs/runbooks/job-dlq-requeue.md`, `webhook-endpoint-recovery.md` | Observability foundation, Platform API/job/flag/spatial core (`05_*.md` §12) |
| DR rehearsal program | 15 (hardening) | Quarterly rehearsal (§8.2, shared cadence with `10_*.md`'s `ADR-CAND-ARCH-023` slice — one program, not two) exercising §8.1/§8.3's restore/rollback procedures | Deployment pipeline + rollback runbooks, DR/backup rehearsal program (`10_*.md` §12) |
| Reporting-replica graduation | 5 (or when §9.1's trigger fires) | Provision read replica per Tech Arch §6's Scale-up diagram once §9.1's measured trigger fires; not scheduled by phase number alone | Observability foundation (to measure the trigger), Reporting full (`05_*.md` §12) |
| Release-artifact provenance tooling | 0 | Commit-SHA/pipeline-run tagging, SCA report publishing, release-notes template (§9.4) | CI pipeline foundation |

## 12. Go-live blockers

DevOps-owned rows from Blueprint §27.1's 19-item Go-Live Checklist (reproduced by reference, not re-typed — `10_*.md` §9's Phase 16 row already binds the full checklist to test evidence): "DevOps — Backup and rollback ready" and "DevOps — Monitoring and alerting active" are hard blockers per Blueprint §27.2's Go/No-Go table (No-Go on any critical gate failure). This document's own hard blockers, not separately listed in Blueprint §27.1 but implied by §5–§9 above: no Production secret may be stored outside the resolved secret mechanism (`ADR-CAND-ARCH-025`); no Production deploy may originate from an artifact that skipped the migration-check stage (§3); the Cross-tenant-policy-test-failure alert (§6.1) must be wired and verified firing correctly in Staging before the first Production tenant onboarding, since it is the single immediate-Sev1 signal for the costliest failure class this entire blueprint defends against (`06_*.md`/`10_*.md` §5.2).

## 13. Exit gates

Every environment and pipeline gate has an owner, evidence artifact, and rollback path (§2's owner column, §3's artifact provenance, §4.4's per-layer rollback table) — no gate in Blueprint §25.3's 15-item checklist is left without a DevOps-traceable evidence source. Recovery claims match contracts and rehearsals: RPO/RTO tiers (§8.1) are cited exactly as Tech Arch §31.2 states them, RPD-031/037's contract-silent-means-best-effort framing is preserved without dilution, and the rehearsal cadence (§8.2) is the single one also cited by `10_*.md` (not a second, conflicting cadence). Direct-GA safeguards are explicit: §4.3 reconciles progressive-exposure mechanisms with RPD-034/036 without weakening "no external pilot," and §12's go-live blockers are hard, not aspirational. No external state was changed (§0, confirmed against `git status` — zero CI, environment, secret, or infra resource exists).

## 14. Completion statement

Environment topology (§2) fixes seven isolated, owner-assigned environment tiers with explicit parity and seed-data rules — the same seven tiers `10_*.md` §4.1 already cites, extended here with ownership/access/promotion columns. The CI/CD pipeline (§3) reproduces Tech Arch §28.1's stage order exactly (shared with `10_*.md` §6) and adds deterministic build/artifact-provenance and dependency/SCA evidence rules. Migration/deployment/rollback (§4) binds Blueprint §25's flow/checklist and Tech Arch §28.2/§28.3's rollback table, reconciling internal feature-flag/canary progressive exposure with RPD-034/036's direct-GA "no external pilot" rule. Secret/key/certificate lifecycle (§5) fixes least-privilege, rotation-with-overlap-window, and leakage-prevention rules extending Tech Arch §23.6/§23.7. Observability (§6) reproduces Tech Arch §30's 5 signals/11 dashboards/8 alerts verbatim and ties tenant-aware/exception-class monitoring to that same fixed catalogue, plus RPD-025 retention. Storage/file/CDN controls (§7) bind the malware-scan/signed-URL gate to infrastructure-level backup/restore/cleanup rules. Backup/restore/DR/incident/support (§8) reproduces Tech Arch §31 and Blueprint §30 verbatim, cites (not re-authors) the migration/cutover rollback procedures already fixed in `10_*.md`, and defines a 9-runbook catalogue. `ADR-CAND-ARCH-004` (live-OLTP-to-replica/warehouse threshold, open since `01_*.md`) is resolved with a concrete, evidence-based, four-signal trigger definition (§9.1) rather than re-deferred a third time. Feature-flag operation (§9.2), database/job capacity thresholds (§9.3), and release artifacts (§9.4) close out the remaining prompt tasks. 4 new ADR candidates are raised (`024` CI/CD platform, `025` secret manager, `026` observability tool, `027` hosting/CDN platform), all non-blocking and deferred to Phase 0 environment/CI kickoff, consistent with the deferral pattern already established for `ADR-CAND-ARCH-020/021/022/023`. The 12-slice atomic backlog (§11) and go-live blockers (§12) close out the workstream's planning scope. No environment, pipeline, deployment, secret, or infrastructure resource was created or changed (§0, confirmed against `git status`).

Next eligible prompt: `03-architecture-and-plan/47_RELEASE_TRAIN_PROMPT.md` → `docs/architecture/12_RELEASE_TRAIN.md`.
