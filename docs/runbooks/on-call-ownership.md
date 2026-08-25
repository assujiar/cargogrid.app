# Observability, alerting, and on-call ownership — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call, Security — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 15 (`HDN-382`, Prompt 382 Observability Audit; `HDN-387`, Prompt 387 Release-Blocker Triage; consolidated at `HDN-388`, Prompt 388 Documentation Handoff)
**Severity class:** **Mixed, disclosed by mechanism, not a working end-to-end on-call pipeline.** A real alert-producing and alert-storage mechanism exists (`app.raise_observability_alert`/`app.incidents`) and is wired to 2 real failure producers as of this checkpoint. It has **no dashboard UI, no escalation/dispatch mechanism, and no wiring to most other failure producers** — these are already-registered, accepted, owner-named gaps (§3), not new findings, and this runbook does not claim otherwise.

> This document is narrower than `docs/runbooks/observability-exporter-outage.md`, which covers the telemetry-*export* pipeline (`scripts/observability/logger.ts` → Better Stack) being unavailable — a different mechanism from the one described here (the in-application alerting/incident schema, `app.raise_observability_alert`/`app.incidents`). Read that runbook for exporter-outage diagnosis/resolution; read this one for what triggers a real alert today, who is supposed to own an incident once one exists, and what is honestly not built yet.

## 1. Symptom / trigger

Consult this runbook when: (a) deciding whether a given failure class produces a real, queryable incident today, (b) an `app.incidents` row exists and needs a human owner, or (c) onboarding a new on-call responder who needs to know which support tier owns which class of failure. There is no dashboard that surfaces this automatically (§2/§3 item 2) — today, finding an incident means querying `app.list_incidents_for_tenant`/`app.get_incident_timeline` directly, or noticing a gap the hard way.

## 2. Impact

An `app.incidents` row that nobody looks at is functionally silent — the schema records it, but nothing pages anyone, and (per §3) most real failure classes never create one in the first place. The practical consequence: today, on-call awareness of a production failure depends on manual `app.audit_logs`/`app.incidents` querying, or an out-of-band signal (a customer report, a health-check failure), not on any automated alert delivery.

## 3. Diagnosis steps — what alerting mechanism exists today, and what does not

**1. A real, well-built alerting/incident backend exists (`IAE-030`, `supabase/migrations/20260807400000_create_intelligence_enterprise_monitoring_observability.sql`).** `app.raise_observability_alert(p_tenant_id, p_source_type, p_signal_type, p_title, p_severity, p_detail)` validates severity (`low`/`medium`/`high`/`critical`), resolves the matching `app.alert_routes` row (owner metadata plus a dedup window, default 30 minutes), and creates or collapses into an existing `app.incidents` row — concurrency-safe via a `pg_advisory_xact_lock` keyed on `(tenant, source_type, signal_type)`, closing a real check-then-act race found and fixed at this same migration's own Tier C review. `app.list_incidents_for_tenant`/`app.get_incident_timeline`/`app.list_alert_routes_for_tenant` are real, tenant-safe, `MON:View`-gated RPCs that already route through the same `app.evaluate_permission` primitive `HDN-373` hardened.

**2. Confirmed at `HDN-382` (Observability Audit): this backend had zero real production callers before this checkpoint.** Live-forced: a job driven through the real DLQ path (`app.enqueue_job` → `app.claim_next_job` → `app.record_job_failure`) reaching terminal `dead_letter` status produced **zero incident, zero alert, zero owner notification** — only an `app.audit_logs` row a human would have to go looking for. This directly contradicted Prompt 382's own Main Flow ("a job/webhook/API/database failure produces actionable alert").

**3. Two real producers are now wired — the full, current list, not "most failures are covered":**

   - **`app.record_job_failure`'s dead-letter transition** (fixed at `HDN-382`, migration `20260816000000_harden_observability_audit_findings.sql`) — any job reaching terminal `dead_letter` status now raises a real, deduplicated alert (`source_type='job'`, `signal_type='error'`, `severity='high'`). Live-verified via a regression db-test that drives a job to `dead_letter` and confirms an incident is created, that a second distinct job type dead-lettering for the same tenant within the dedup window correctly collapses into the same incident, and that a merely-retryable (non-terminal) failure raises no alert.
   - **The 3 inbound webhook-ingestion functions' signature-verification-failure branch** (fixed at `HDN-387`, migration `20260819000000_harden_release_blocker_triage_remediation.sql` Part 5, closing `HDN-BLK-027`) — `app.ingest_finance_payment_gateway_webhook_event`, `app.ingest_logistics_partner_webhook_event`, and `app.ingest_third_party_provider_webhook_event` (the ingestion functions themselves — **not** the pure, side-effect-free `verify_*_webhook_signature` functions they call) now raise a real alert on their `signature_verification_failed` branch, mirroring `app.record_job_failure`'s established pattern. Live-forced: a bad signature against a real connection still records the ingestion attempt exactly as before AND now produces a real `app.incidents` row.

**4. Everything else remains unwired — registered, not new findings:**

   - **`ISS-2026-249`** (High, `PARTIALLY RESOLVED at HDN-387`) — the two producers above are fixed; the following remain genuinely `OPEN`, in the priority order `ISS-2026-249` itself names: outbound webhook-delivery replay divergence (`app.replay_webhook_delivery` — a delivery that dead-letters a second time post-replay produces zero alert, since the bridging job's own `attempts` counter restarts at 0 while the delivery's own counter continues, so the delivery reaches `dead_letter` before the job does); `IAE-008` integration-connection health-check auto-disable (`app.record_integration_health_check`, live-reachable via a real UI page, auto-disables at 10 consecutive unhealthy checks with no alert call); AI-governed-action rejection (`app.request_ai_governed_action`/`app.record_ai_governed_request_outcome` audit every call via `app.capture_audit_event` but never raise an alert on failure/rejection); security/auth denials (RLS-adjacent authority denials, IP-restriction blocks, MFA step-up failures — all durably audited, never alerted).
   - **`ISS-2026-250`** (High, `OPEN`) — **no monitoring/incident dashboard UI exists anywhere in the application.** Confirmed by repository-wide search: no page under `app/(tenant)/` or `app/(internal)/` renders an incident, alert, SLO, or alert-route record. The capability's own original build log (`docs/build-log/phase-09/IAE-358.md`) self-discloses this directly ("UI: none — consistent with every other Group 7 capability"). `docs/standards/OBSERVABILITY_STANDARDS.md` §1's own catalogue of 11 dashboards is entirely aspirational — none exist in the real `app/` tree. The backend RPC surface a dashboard would consume is already real and tenant-safe (§3 item 1); the remaining work is UI-only.
   - **`ISS-2026-251`** (Medium, `OPEN`) — **no escalation/dispatch mechanism exists at all.** `app.alert_routes.owner_team`/`owner_email` are real and correctly copied onto each `app.incidents` row at creation, but both fields are inert routing metadata only — `docs/build-log/phase-09/IAE-358.md` self-discloses: "No live alert delivery — no email/Slack/PagerDuty dispatch is built or wired here." There is no automatic escalation (e.g. an unacknowledged-after-N-minutes reminder) and no paging mechanism of any kind. An unacknowledged incident never pages anyone — it remains fully visible and queryable via the RPCs in §3 item 1, but nothing pushes it to a human.

   None of the three is fixed by this runbook. Each carries a named future owner in `docs/runtime/KNOWN_ISSUES.md` — building the dispatch mechanism (`ISS-2026-251`) is naturally sequenced after the dashboard UI (`ISS-2026-250`, "paging without any UI to acknowledge from is a weaker fix").

## 4. Resolution steps

1. **If a failure class is one of the two wired producers (§3 item 3)**: it already produces a real `app.incidents` row — query `app.list_incidents_for_tenant`/`app.get_incident_timeline` for the affected tenant, or `p_tenant_id => null` scope for a platform-wide incident.
2. **If a failure class is not yet wired (§3 item 4)**: there is no automated alert to find — fall back to `app.audit_logs`/`app.query_audit_logs` (every RPC-mediated action is captured there regardless of alerting wiring) or the failure's own domain-specific durable record (e.g. webhook ingestion-attempt tables, integration health-check history).
3. **Escalation, once an incident (wired or manually found) needs a human**: use the support-tier table in §5 below — there is no automated dispatch (§3 item 4), so escalation today is a manual act: the responder who finds the incident contacts the correct tier directly.
4. **To wire a new failure producer**: follow `app.record_job_failure`'s established call shape exactly (`app.raise_observability_alert(tenant_id, source_type, signal_type, title, severity, detail)`, `p_detail` is `text`, not `jsonb` — a real defect caught and fixed at `HDN-387` before it shipped, see `docs/build-log/full-system-hardening/HDN-387.md`) — do not invent a second alerting convention.

Rollback procedure if a future alert-wiring change fails: additive migration only (both fixes to date added a call inside an existing function body via `CREATE OR REPLACE FUNCTION`, no schema change) — `git revert` the migration commit; no data migration is entangled.

## 5. Who owns what tier

Reproduces `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4's own binding incident/support model (itself reproducing Blueprint §30.1 verbatim) — this runbook does not invent a separate ownership scheme:

| Tier | Owner | Scope |
|---|---|---|
| L0 Self-service | Customer Success / Product | End-user self-service, no on-call involvement |
| L1 Functional support | Support Team | First-line functional/how-to support |
| L2 Product support | Product Support / Implementation | Product-configuration-level issues escalated from L1 |
| L3 Engineering | Engineering | Code-level defects escalated from L2 |
| Security escalation | Security Lead | Compromised identity/session/credential, tenant-leak, cross-tenant RLS failure — own rotation, distinct from Infrastructure |
| Infrastructure escalation | **DevOps/SRE** | Downtime, database/storage, CI/CD, deployment, backup/restore — **this runbook's own on-call ownership boundary**; any incident reaching this tier is DevOps' to run, using the runbook catalogue in `docs/runbooks/README.md` |

Priority/SLA (§8.4, verbatim): **P1 Critical** (production down, tenant leak, financial corruption, severe security issue) — 15-minute response, continuous work until mitigation, RCA required, status every 30–60 min; **P2 High** — 1-hour response, 1-business-day target; **P3 Medium** — 4-business-hour response, 3–5 business days; **P4 Low** — 1-business-day response, planned backlog.

Incident flow (§8.4, verbatim): Detect/Report → Triage → Severity Classification → Mitigation → Communication (parallel to Fix/Workaround) → Validation → Close Incident → RCA → Preventive Action.

RCA requirement (§8.4, binding): mandatory for P1, security incident, tenant isolation failure, financial posting/data corruption, production rollback, repeated P2, major data migration failure.

**On-call ownership note** (§8.4, verbatim): the Infrastructure-escalation tier (DevOps/SRE) and the Security-escalation tier (Security Lead) are distinct rotations — a database/deployment incident and a tenant-leak/auth incident page different owners first, converging at Incident Commander level only if both domains are implicated.

## 6. Communication

No automated communication mechanism exists (§3 item 4, `ISS-2026-251`) — until it does, whoever finds/triages an incident is responsible for manually notifying the correct tier per §5, using whatever channel this organization's own on-call tooling designates (not specified anywhere in this codebase — no Slack/PagerDuty/email integration exists here, confirmed by repository-wide search at `HDN-382`/`HDN-384`).

## 7. Post-incident

Record: which tier actually handled the incident, whether it was found via the wired-alert path (§3 item 3) or manually (§3 item 4), and — for a P1/security/tenant-isolation/financial-corruption/rollback/repeated-P2/major-migration-failure incident — the RCA per §5's binding requirement. If the incident's own failure class is not yet wired to `app.raise_observability_alert`, note that explicitly rather than silently working around the gap — it is evidence for prioritizing `ISS-2026-249`'s remaining named producers.

## 8. Rehearsal history

| Date | Type | Outcome | Evidence |
|---|---|---|---|
| 2026-08-24 (`HDN-382`) | Live/simulated failure test — job dead-letter path | **Confirmed zero alert pre-fix; fixed and re-verified live post-fix** | `docs/build-log/full-system-hardening/HDN-382.md` §1 |
| 2026-08-24 (`HDN-387`) | Live-forced — webhook signature-verification-failure path | **Confirmed zero alert pre-fix; fixed and re-verified live post-fix** | `docs/build-log/full-system-hardening/HDN-387.md`, `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-249` |
| — | Escalation/dispatch mechanism (`ISS-2026-251`), dashboard UI (`ISS-2026-250`) | **Not built — disclosed gap, `OPEN`** | `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-250`/`251` |

## 9. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-24 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `HDN-388` (Step 15 Full-System-Hardening, Documentation Handoff), consolidating existing evidence from `HDN-382.md`, `HDN-387.md`, `docs/runtime/KNOWN_ISSUES.md` (`ISS-2026-249`/`250`/`251`), and `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4 into a dedicated on-call-ownership reference. No new alert wiring or mechanism built by this checkpoint — every claim above is quoted or directly reproduced from an already-existing source, cited inline. | Claude Code (runtime build agent) |
