# Prompt 389 — Full-System Hardening Closure Verification

**Prompt ID:** `CG-S15-HDN-021`  
**Package document:** `CG-AABPP-HDN-389`  
**Version:** `0.16.0`  
**Runtime output:** `docs/build-log/full-system-hardening/FULL_SYSTEM_HARDENING_CLOSURE_REPORT.md`

Do not begin until Prompt 388 is `VERIFIED`, the active checkpoint still carries `PHASE_9_VERIFIED`, and all Step 15 hardening, blocker remediation, documentation and handoff evidence is available for independent review.

## Objective

Independently verify full-system hardening completeness, blocker status, regression safety, tenant/security/financial/API/storage/performance/accessibility/observability/backup/DR/migration readiness and Step 16 Release Candidate eligibility.

## Required verification

1. Verify Prompts 369–388 at one repository/schema/environment checkpoint and reconcile every WBS, dependency, traceability and evidence link.
2. Confirm full regression evidence exists and mandatory gates were not suppressed.
3. Confirm cross-module transactional integrity passes for lead→quote→job, shipment→ePOD→billing, actual cost→AP→settlement, invoice→receipt→journal, WMS inbound→outbound, customer portal, loyalty, tickets and Tenant A/B isolation.
4. Confirm tenant isolation covers database, storage, cache, queue, report, export, log, integration, AI context and support access.
5. Confirm RLS/RBAC covers module, action, field, record, status, amount, branch, department, team, ownership, customer and support scopes.
6. Confirm financial integrity covers exact money, FX/tax snapshots, AR/AP, journal, period lock, settlement, payroll handoff, loyalty liability and RPD-016 statutory gates.
7. Confirm data lineage from lead to payment and loyalty is source-linked, versioned and no-reentry safe.
8. Confirm API compatibility covers REST/GraphQL parity, public/customer/vendor API, webhooks, exports, versioning, deprecation, rate limit, idempotency and signing.
9. Confirm storage and signed URL audit covers malware scan, quarantine, private files, expiry, revocation, access audit, retention and legal hold.
10. Confirm security hardening covers auth/session, CSRF, XSS, SQL injection, IDOR, SSRF, open redirect, file upload, API abuse, webhook spoofing, prompt injection, dependency scan, secret management, incident response and key rotation.
11. Confirm performance/scalability covers p95, query count, payload size, load profile, jobs, queue/backpressure, reports, imports/exports, AI jobs, APIs and no unbounded client loads.
12. Confirm accessibility covers critical internal, admin, customer and support workflows with keyboard/focus/labels/contrast/error states.
13. Confirm browser/device compatibility covers supported Chrome, Edge, Safari, Firefox, tablet/mobile and RPD-004 responsive online-first behavior without native/offline-sync claim.
14. Confirm observability covers app, database, queue, jobs, integrations, API, AI, storage, security events, tenant health, alert ownership and runbook links.
15. Confirm backup/restore includes database, files, configuration, secrets references, jobs and actual restore evidence with RPO/RTO disclosure.
16. Confirm DR rehearsal covers outage/data corruption/provider/security scenarios, communication, escalation and tested recovery capability.
17. Confirm data migration rehearsal covers mapping, preview, validation, duplicate handling, commit, reconciliation, rollback and rerun idempotency.
18. Confirm every critical/high blocker is fixed with regression proof or explicitly blocks Step 16 with owner/reproduction/resume.
19. Confirm RPD-021, RPD-022, RPD-023, RPD-025, RPD-032, RPD-033, RPD-038 and RPD-040 are enforced or disclosed across relevant evidence.
20. Confirm no test, lint, typecheck, RLS, permission, validation, audit, security or financial control was disabled to pass a gate.
21. Confirm no Step 16 release/go-live, production, external pilot, GA or market-ready claim is made by Step 15.
22. Confirm clean install/upgrade/migrations, generated types/specs, CI, runbooks, known issues, error ledger, change manifest and handoff are current.

## Closure states

- `FULL_SYSTEM_HARDENING_VERIFIED`: every mandatory hardening gate passes and no unresolved critical/high blocker remains.
- `FULL_SYSTEM_HARDENING_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Step 16 is blocked until accepted or repaired.
- `FULL_SYSTEM_HARDENING_BLOCKED`: a critical/high tenant/security/financial/API/storage/performance/accessibility/observability/backup/DR/migration/evidence gate fails.
- `FULL_SYSTEM_HARDENING_ROLLED_BACK`: the system returned to a trusted checkpoint and must resume.

## Required output

Write hardening closure report; checkpoint/schema/API/UI/access matrix; full regression report; critical E2E integrity evidence; tenant/RLS/RBAC matrix; finance and lineage evidence; API/webhook compatibility evidence; storage/security/performance/accessibility/browser/observability/backup/DR/migration evidence; blocker register; residual risks and accepted-risk disclosures; runbook/documentation index; Step 16 eligibility; exact resume/next prompt.

## Completion gate

Set `FULL_SYSTEM_HARDENING_VERIFIED` only if every mandatory hardening check passes and no unresolved critical/high blocker remains. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 15 validation is `LANJUT STEP 16`.

