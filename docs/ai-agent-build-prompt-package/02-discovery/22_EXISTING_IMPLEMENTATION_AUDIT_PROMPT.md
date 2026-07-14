# Prompt 22 — Existing Implementation Audit

**Prompt ID:** `CG-S2-DISC-002`  
**Package document:** `CG-AABPP-DISC-022`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Existing capability and implementation truth  
**Runtime output:** `docs/discovery/02_EXISTING_IMPLEMENTATION_AUDIT.md`

## Objective and business value

Determine what the repository actually implements versus what filenames, routes, UI, documentation, seeds, mocks, or TODOs merely imply. Produce an evidence-backed capability baseline that protects existing working behavior and exposes incomplete or unsafe foundations before planning.

## Source requirements

- Master Prompt §§3–4, Step 2, §§11, 17, 20–21.
- CPD-001..023; RPD-001, 004–005, 011–017, 019–023, 032–039.
- GOV-010 task contract, non-regression, ratified constraints, completion claims.
- Technical Architecture §§4–26, 36–38.
- Delivery Plan §§8–12, 14–18, 27.
- BPR functional family and NFR inventory mapped in CTRL-005.

## Preconditions and authorization

- Prompt 21 output is `VERIFIED` at the same HEAD/worktree checkpoint.
- Read code, tests, docs, schemas, configs, and generated types. Run only existing safe read-only or baseline commands whose effects are understood.
- Write only discovery documentation and persistent ledgers/status/build log.
- Do not fix, generate, install, migrate, seed, format, refactor, or update dependencies.

## Mandatory pre-flight

Read governance and persistent files, prompt 21 inventory, relevant sources, existing build logs, and repository instructions. Reconfirm HEAD/worktree. If checkpoint differs, update prompt 21 or stop; do not merge evidence from different states without explicit reconciliation.

## Audit method

For each capability, distinguish:

- `IMPLEMENTED_VERIFIED`: executable path and relevant evidence exist.
- `IMPLEMENTED_UNVERIFIED`: code exists but no safe execution/test evidence.
- `PARTIAL`: meaningful pieces exist but main/alternative/exception path is incomplete.
- `SKELETON`: route/component/schema exists with placeholder, mock, or no real behavior.
- `DOCUMENTED_ONLY`: requirement/docs claim it but implementation evidence is absent.
- `NOT_FOUND`: scoped search found no evidence.
- `BLOCKED`: access or safety prevents inspection.

Never infer implementation from a menu item, component name, seed row, migration filename, screenshot, or README alone.

## Detailed tasks

### A. Application foundation

- Identify actual Next.js/application entry points, layouts, middleware, providers, auth/session handling, error/loading/not-found boundaries, server/client split, and environment usage.
- Identify Supabase clients, auth flows, database access layers, storage, realtime, edge/functions, and server-only boundaries.
- Identify shared domain/service/repository patterns versus route-local logic.

### B. SaaS platform capability

Audit evidence for tenant lifecycle, subscription/entitlement, organization/hierarchy, four-layer access, RBAC, RLS, field/record access, support/impersonation, white-label/custom domain, localization, master data, configuration/workflow/approval/status/numbering/form engines, notification, document, audit, API keys/webhooks, import/export, background jobs, feature flags, and admin portals.

### C. Domain capability

Map implemented evidence for Commercial, Operations/TMS/WMS, Procurement/Vendor, Finance, HRIS, Ticketing, Customer Portal, Loyalty, Intelligence/AI, and Enterprise Controls. Use source requirement family IDs. Do not call a domain complete unless transactional data, access, validation, exception, audit, and test evidence support it.

### D. Cross-module truth

- Trace any existing real flow from input to persistence to downstream conversion, API/UI, audit, and reporting.
- Look for duplicate master data, re-keying, hardcoded tenant/role/workflow/status/service, fake persistence, browser-only state, mock/fallback data in production paths, and disconnected CRUD.
- Check whether REST and GraphQL both exist and whether shared public capabilities appear aligned.
- Identify custom non-AI connectors and whether they remain shared code without tenant forks.

### E. Ratified exceptions

- Record the actual Supreme Admin implementation. Do not label audit/ledger tamper-proof if absolute CRUD exists or is required.
- Record PWA/offline/native behavior accurately.
- Record custom-domain, PostGIS, PostgreSQL queue, live-OLTP reporting, upload scanning, AI/human approval, SSO sequence, and recovery claims based on evidence.

## Evidence table required per capability

| Field | Required content |
|---|---|
| Requirement/capability | Source ID and business name |
| Classification | One status from the audit method |
| Entry points | Routes/components/actions/APIs/jobs |
| Persistence/contracts | Tables/functions/storage/events/contracts |
| Access/audit | RLS/RBAC/field/record/audit evidence |
| Tests/execution | Test paths or safe command result |
| Main/alternative/exception | Which flows are evidenced |
| Gaps/risks | Exact missing or conflicting behavior |
| Downstream impact | Consumers/dependencies |

## Suggested inspection actions

Use `rg`, file inventories, manifest scripts, route/schema/test searches, and focused read-only inspection. Existing safe test/build commands may be referenced but broad execution belongs primarily to prompt 27. Do not start dev servers or connect to remote services unless explicitly safe, isolated, and necessary.

## Required output structure

1. Repository checkpoint and evidence method.
2. Executive implementation truth: working, partial, skeleton, absent, blocked.
3. Platform capability matrix.
4. Domain capability matrix mapped to source families.
5. Cross-module flow evidence.
6. Existing UI/API/database/job/integration evidence.
7. Hardcoding, mock, fake persistence, tenant-fork, and duplication findings.
8. Protected-decision alignment and explicit exceptions.
9. Preserve/regress-sensitive areas.
10. Blockers, risks, technical-debt candidates, and follow-up IDs.
11. Evidence appendix with paths/commands/counts.

## Acceptance criteria and Definition of Done

- Every major module family has a classification and evidence or explicit scoped `NOT_FOUND`.
- “Implemented” claims include executable or test evidence, not names alone.
- Existing behavior that must be preserved is identified.
- Security, data, finance, API, jobs, UI, and docs are not conflated.
- No code/config/data/dependency/migration change occurred.
- Persistent status, task, build log, error/issue ledgers are reconciled.

## Failure and recovery

If the repository changes, a secret/tenant record appears, or inspection reveals a critical tenant/security/finance defect, stop; redact; record the checkpoint, issue/error, release effect, and safe resume scope. Do not fix during discovery.

## Completion report and next prompt

Report classification counts, verified working flows, partial/skeleton/absent areas, preserved behavior, critical risks, commands/evidence, files written, and trust state.

Next: `CG-S2-DISC-003` — Toolchain and Dependency Audit.
