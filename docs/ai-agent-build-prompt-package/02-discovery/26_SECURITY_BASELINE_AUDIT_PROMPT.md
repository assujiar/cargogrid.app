# Prompt 26 — Security, Tenant Isolation, and Access Baseline Audit

**Prompt ID:** `CG-S2-DISC-006`  
**Package document:** `CG-AABPP-DISC-026`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Security and access posture  
**Runtime output:** `docs/discovery/06_SECURITY_BASELINE.md`

## Objective and business value

Produce a passive, evidence-backed security baseline covering tenant isolation, authentication/session, RBAC/record/field policy, privileged/support access, secrets, APIs, integrations, jobs, storage/uploads, common web vulnerabilities, dependency controls, logging, and incident readiness. Do not exploit, mutate, or expose data.

## Source requirements

- Master Prompt §§11–13, 15–20 and Step 2.
- CPD-004/006–010/015–023; RPD-011/017/021–025/032/033/035/038/039.
- GOV-010 §§9–12 and GOV-011 security/database rules.
- Technical Architecture §§10–12, 17, 19, 22–26, 27–31, 34–35, 38–39.
- Delivery Plan §§17–18, 20, 22–24, 27, 35.
- UX/Data Design access, field classification, support/impersonation, audit, and storage rules.

## Preconditions and authorization

Prompts 21–25 are complete at one checkpoint. Passive source/config/test inspection is authorized. Existing static/security test commands may run only if prompt 23 marks them safe and they do not attack remote systems, mutate files, or transmit sensitive code/data without approval.

Forbidden: active exploitation, credential validation, brute force, cross-tenant probing against live systems, destructive payloads, secret printing, production scanning, dependency fixes, code/config/policy edits, or incident rotation actions.

## Mandatory pre-flight

- Read governance, prior discovery outputs, security docs/threat model, error/issues, and deployment/environment evidence.
- Confirm no command targets production or customer data.
- Define evidence redaction and severity criteria before searching.
- If an exposed live credential is encountered, stop normal audit, contain evidence without copying it, and follow incident escalation.

## Detailed tasks

### A. Trust boundaries and data classification

Map browser, server, Supabase/Auth/PostgreSQL/Storage, REST, GraphQL, webhooks, jobs, realtime, AI, custom connectors, admin/support, and environments. Identify PII, finance, tax, payroll, bank, credential, document, and tenant-sensitive classes and their expected controls.

### B. Authentication and session

Audit signup/invite/login/logout/reset/recovery/MFA/session refresh/revocation, email verification, OAuth/OIDC/SAML/SCIM evidence, token storage, cookie attributes, redirect validation, server/client auth checks, and privileged-role MFA enforcement. Record missing flows without implementing.

### C. Tenant and authorization

- Reconcile application tenant context, RLS, storage policies, jobs, cache, reports, search, exports, REST, GraphQL, realtime, and integrations.
- Inspect RBAC plus company/branch/team/record/field/status/value scopes.
- Identify client-only checks, IDOR paths, route-parameter trust, service-role bypass, overly broad grants, and missing negative tests.
- Assess support/impersonation purpose, duration, visibility, and audit.

### D. Supreme Admin exception

RPD-022 requires literal absolute CRUD. Record whether implementation grants, restricts, or ambiguously implements it. Never call audit/journals tamper-proof. Distinguish the ratified exception from accidental browser service-role exposure or ungoverned support access, which remain defects.

### E. Secrets and software supply chain

- Inventory secret variable names/locations, `.env` handling, client/public prefixes, logging paths, CI secrets references, key rotation docs, and committed-secret indicators without outputting values.
- Consume prompt 23 dependency/audit evidence; classify unresolved vulnerabilities and unsafe lifecycle scripts.

### F. API, webhook, GraphQL, job, and integration controls

Inspect authentication/authorization, schema/field exposure, input validation, rate limiting, idempotency, replay protection, webhook signatures/timestamps, API-key hashing/scoping/rotation, retry/DLQ, SSRF/egress restrictions, custom connector credentials, AI data boundaries, and monitoring.

### G. Web and file protection

Assess CSRF, XSS, injection, SSRF, open redirect, CORS, security headers, CSP, upload type/size/content validation, malware scan state, bucket privacy, signed URL expiry, path traversal, download authorization, image/document processing, and audit.

### H. Observability, incident, backup, and recovery claims

Inspect security-event logging, alerting, correlation, PII/secret redaction, incident/key-rotation runbooks, backup access, and RPO/RTO claims. Contract-silent recovery must be described as best effort.

## Severity and evidence

Use Critical/High/Medium/Low with exploitability and data/tenant/finance impact. A suspected critical issue must be recorded as `SUSPECTED` until safely verified; do not exploit it to increase confidence.

## Required output structure

1. Checkpoint, scope, limitations, passive-method statement.
2. Trust-boundary and data-classification map.
3. Auth/session/MFA/SSO matrix.
4. Tenant/RLS/RBAC/field/record/support/impersonation matrix.
5. Supreme Admin implementation and product-claim implications.
6. Secrets/supply-chain baseline with redaction.
7. REST/GraphQL/API key/webhook/job/realtime/AI/custom-connector controls.
8. Web/file/storage/malware-scan baseline.
9. Logging/incident/backup/recovery claim baseline.
10. Existing security test coverage.
11. Findings register with severity, evidence, affected surface, release effect, safe remediation task, and owner.
12. Evidence appendix and output hash.

## Acceptance criteria and Definition of Done

- Every named trust boundary and control family is assessed or explicitly blocked.
- No secret value or tenant payload appears in output.
- No active exploit or external mutation occurred.
- Critical/high findings are placed in Error/Issue Ledger and Build Status with release effect.
- RPD-022 and recovery claims are represented accurately.
- No source/config/policy/dependency/data change occurred.

## Failure, completion, and next prompt

On credential/tenant-data exposure or suspected active compromise, stop discovery, record minimal secure evidence, escalate incident handling, and do not continue routine scanning.

Report scope, major control status, finding counts by severity, blockers, redactions, commands/results, files written, and next prompt.

Next: `CG-S2-DISC-007` — Test and Quality Baseline.
