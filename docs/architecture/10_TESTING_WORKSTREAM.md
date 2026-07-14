# 10 — Testing Workstream

**Prompt:** `CG-S3-ARCH-010` (`CG-AABPP-ARCH-045` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/45_TESTING_WORKSTREAM_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `2957bb0c27c979ed7f346985273c4ada1e639e6b` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `09_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero test, zero CI gate, zero fixture (`docs/discovery/07_TEST_QUALITY_BASELINE.md` confirms `UNKNOWN` baseline, no toolchain) |
| Mutation performed | **NONE** — planning only; no test, config, or source file created (prompt precondition, verified) |

### Inputs read (beyond `01–09_*.md`, already fully loaded)

- Blueprint `05_CargoGrid_Delivery_Testing_GoLive_Plan.md` §17 (QA Strategy, full), §18 (Test Plan: 25-row Test Matrix + Test Data Strategy, full), §19 (UAT: governance + 20-scenario End-to-End UAT Catalogue `UAT-E2E-001..020`, verbatim, + sign-off criteria), §20 (Security Testing: scope/exit criteria/penetration test), §21 (Performance Testing: 19-row target table + 12 `PERF-*` scenarios + engineering rules), §22 (Tenant Isolation Testing: 18-scenario catalogue `TI-001..018`, verbatim, + evidence requirements), §23 (Financial Test: 24-scenario Financial Test Matrix `FINTEST-001..024`, verbatim, + Finance Go-Live Gate), §24 (Data Migration: flow, scope, stages, acceptance, rollback), §26.2/§26.3 (Rollback Criteria/Procedure), §27 (Go-Live Readiness Checklist, Go/No-Go Decision)
- Tech Arch §27.3 (Test Pyramid), §28.1 (CI/CD Pipeline diagram)
- `06_RLS_RBAC_WORKSTREAM.md` §10 (15-item negative/abuse test matrix), `08_API_INTEGRATION_WORKSTREAM.md` §13 (12-row API/integration test matrix), `09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §12 (10-row UX test strategy, WCAG/visual-regression rows)
- `docs/discovery/07_TEST_QUALITY_BASELINE.md`, `08_PERFORMANCE_BASELINE.md` (confirm zero toolchain, `UNKNOWN` baseline)
- `00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-034/036 (direct GA, full internal validation, zero open Sev-1/critical), RPD-031/037 (contract-silent recovery = best effort)

## 1. Scope and method

This document does not create, run, or modify a test, CI configuration, or fixture (prompt precondition and completion gate). It binds the test **plan** every future Phase-0–9 capability prompt must satisfy: the layered test architecture (§2), the requirement/control matrix tying every layer to a workstream/rule/transition/exception/flow already catalogued in `01_*.md`–`09_*.md` (§3), environment/data strategy (§4), the three mandatory critical-scenario catalogues preserved verbatim (§5), the CI gate model (§6), migration/recovery/compatibility/browser/accessibility/load/DR tests (§7), performance/accessibility/security evidence (§8), phase exit criteria (§9), failure/rollback rules and the direct-GA gate (§10), ADR candidates (§11), the atomic backlog (§12), and readiness dashboard definitions (§13).

## 2. Test architecture

Reproduces Tech Arch §27.3's test pyramid and Blueprint §18.1's 25-row Test Matrix as one binding layer catalogue — every layer below already has an owner, automation level, entry, and exit criterion in Blueprint §18.1; this document does not re-litigate ownership, it adds the cross-references to `01_*.md`–`09_*.md`'s own catalogues that make each layer's scope concrete for CargoGrid specifically, not a generic ERP:

| Layer | Owner (Blueprint §18.1) | Automation | Scope, concretized against `01–09_*.md` |
|---|---|---|---|
| Static/lint/typecheck | Developer | High | Every `server/`, `app/`, `components/`, `lib/` file (`04_*.md` §4); CI stage 1 (§6) |
| Unit | Developer | High | Utility, calculation, validation, permission helper, financial formula (Blueprint §18.1) — includes `06_*.md` §9's `STABLE` RLS helper functions and `07_*.md` §7.3's rule-evaluator determinism |
| Component | Frontend/QA | Medium | `components/{ui,domain,tables,forms}/` primitives (`09_*.md` §4.1), each of the 11 states (`09_*.md` §5) |
| Contract | Backend/QA | High | `server/contracts/<domain>/` types/validators (`04_*.md` §4, `08_*.md` §4.1) — REST/GraphQL parity assertions (`08_*.md` §13) |
| Integration | QA | Medium | Cross-module flows lead→quote→job→invoice (Blueprint §18.1); every `03_*.md` §5 public contract has an integration test proving the anti-corruption boundary holds |
| Database/constraint | DB Engineer/QA | Medium | `05_*.md` §4's constraints (soft-delete, `record_version`, idempotency key, FK), §6's append-only tables |
| Migration | DB Engineer/QA | Medium | `05_*.md` §8's expand/migrate/contract waves; §7 below's clean-rebuild/upgrade tests |
| RLS/RBAC | QA/Security | High | `06_*.md` §4's 7 policy families, §10's 15-item negative-test matrix (reproduced by reference, not re-typed) |
| API REST/GraphQL | Backend/QA | High | `08_*.md` §13's 12-row test matrix (reproduced by reference) |
| Job/integration | QA/DevOps | Medium | `08_*.md` §9's job cancellation/idempotency/DLQ tests; §8.2's per-category sandbox contract tests |
| E2E | QA | High for core | 20 `UAT-E2E-*` scenarios (§5.1) as the automatable core-flow subset once build-out permits |
| Accessibility | QA/UX | Medium | `09_*.md` §9's 8-area WCAG 2.2 AA plan (reproduced by reference) |
| Performance | QA/DevOps | Medium | Blueprint §21.1's 19-row target table (§8.1 below) |
| Security | Security/QA | Medium | Blueprint §20.1's 14-area scope (§8.2 below) |
| Smoke | QA + Key Users | Manual/High | Cutover step 10 (Blueprint §26.1); every deploy per Tech Arch §28.1's `E2E/Smoke Test` CI stage |
| UAT | Implementation/Customer | Manual | 20 `UAT-E2E-*` scenarios, business-facing sign-off (§5.1) |
| Regression | QA | High for core | Core flows re-verified every release (Blueprint §18.1); §10.2 defines the baseline-vs-regression split |
| Operational rehearsal | DevOps/Security | Manual | Backup/restore/PITR/cutover/DR rehearsal (Blueprint §18.1 "Disaster Recovery" row, §7.4 below) |

**Guardrail (prompt precondition, binding):** every row above is a plan, not an executed suite — `docs/discovery/07_TEST_QUALITY_BASELINE.md`'s `UNKNOWN` baseline is unchanged by this document; the first test file for any layer is written by its owning Phase-0/1+ capability prompt, never by this workstream document.

## 3. Requirement/control matrix

Every test layer in §2 is mapped to the workstream/catalogue it proves, so "map test ownership to every workstream, requirement family, business rule, approval, transition, exception, report, and critical flow" (prompt task #2) is a lookup, not a re-derivation:

| Control class | Source catalogue (exact count) | Test layer(s) | Evidence artifact |
|---|---|---|---|
| Business rules | `07_*.md` §7.3, 24 `BR-*` (Blueprint §10) | Unit (rule-evaluator), Regression | `07_*.md` §14's 24-scenario regression row (reproduced) |
| Approval patterns/use cases | `07_*.md` §7.1, 13 patterns + 14 use cases (Blueprint §11.1/§11.2) | Integration, E2E (`UAT-E2E-007`), Regression | `07_*.md` §14's 14-scenario row |
| Status transitions | `07_*.md` §7.2, 24 transitions (Blueprint §12) | Workflow test layer, Regression | `07_*.md` §14's 24-scenario row |
| Exceptions | `07_*.md` §7.4, 16 `EXC-*` (Blueprint §13) | Integration, negative testing (Blueprint §17.1 "Negative testing mandatory") | Exception-scenario evidence per `EXC-*` ID |
| RLS/RBAC negative tests | `06_*.md` §10, 15 items | RLS/RBAC layer | `06_*.md` §10 table (reproduced by reference) |
| API/integration tests | `08_*.md` §13, 12 rows | Contract, API, Job/integration layers | `08_*.md` §13 table (reproduced by reference) |
| UX state/accessibility/visual tests | `09_*.md` §12, 10 rows | Component, Accessibility, Regression | `09_*.md` §12 table (reproduced by reference) |
| Tenant isolation | Blueprint §22.1, 18 `TI-*` (§5.2 below) | RLS/RBAC, Security, E2E | §5.2 |
| Financial integrity | Blueprint §23.1, 24 `FINTEST-*` (§5.3 below) | Financial Integrity layer, Database/constraint | §5.3 |
| End-to-end business process | Blueprint §19.2, 20 `UAT-E2E-*` (§5.1 below) | E2E, UAT | §5.1 |
| Reports/dashboards | `07_*.md` §13's `report`/`dashboard` config type, `06_*.md` §7 "Reports/exports" rule | Integration, Performance | Report-scope-parity test (matches underlying table's RLS, `06_*.md` §4) |
| Critical flows | `03_CargoGrid_UX_Data_Access_Design.md` §7's 7 flows, bound to routes in `09_*.md` §6 | E2E, Integration, Regression | §9's phase-exit mapping |

No control class in `01_*.md`–`09_*.md`'s catalogues is left without an assigned test layer — this is what makes the completion gate's "every critical control has a planned automated or explicitly owned manual proof" checkable (grep any catalogue ID above and find its row).

## 4. Environment and data strategy

### 4.1 Environments

Reproduces Blueprint §25.1 verbatim (Local, Development, Testing, Staging, UAT, Production, Sandbox) — identical environment tiers to Tech Arch §27.1 (already cited in `08_*.md` §5's introspection-tier rule), so UX/API/testing all reference the same seven-tier ladder, not three competing environment lists.

### 4.2 Synthetic dataset factories (prompt task #4)

Reproduces Blueprint §18.2's 10 named data sets (Seed tenant, Multi-tenant isolation set, Commercial set, Operations set, Finance set, WMS set, HRIS set, Customer portal set, Performance set, Migration set), bound to deterministic factory functions — one factory module per domain (`tests/factories/<domain>.ts`, location resolved at §11's `ADR-CAND-ARCH-009`-adjacent tooling ADR) producing seeded, reproducible records (fixed seed per test run, never `Math.random()`/wall-clock-dependent data, so a failing test is reproducible byte-for-byte). Every factory-produced tenant/company/branch/user/customer/vendor/employee/shipment/inventory/finance record is synthetic — no production/tenant data is ever used outside the UAT environment's tenant-approved migrated subset (Blueprint §25.1's UAT row). Cleanup: every test-created tenant is provisioned with a `synthetic = true` marker and purged by an automated sweep after the owning CI run or on a scheduled retention job — a synthetic tenant is never mistaken for a real one because it never appears in the Supreme Admin tenant list's production filter (`09_*.md` §3's `SUP-TNT-001` screen). Privacy: synthetic PII fields (name, phone, email, ID number) are generated, never copied from real tenant data, even in Development/Testing — closes the same "no real data outside Production/UAT" boundary Blueprint §27.1's environment-data table already draws.

### 4.3 Isolation

The Multi-tenant isolation set (Blueprint §18.2) is the fixture every `TI-*` scenario (§5.2) runs against: two tenants (A, B) with structurally identical-looking records (same field values where the field isn't tenant-identifying) so a leak is unambiguous — a test that "passes" only because Tenant A and B's data happen to look different is not a valid tenant-isolation test.

## 5. Critical suites (preserved verbatim, prompt task #3)

### 5.1 20 End-to-End UAT scenarios (`UAT-E2E-001`–`UAT-E2E-020`, Blueprint §19.2)

Preserved by ID and scenario name, verbatim, as the mandatory automatable-E2E-and-manual-UAT core: `UAT-E2E-001` Lead masuk, `002` Qualification, `003` Opportunity, `004` Request costing, `005` Vendor comparison, `006` Quotation, `007` Approval, `008` Customer acceptance, `009` Job order, `010` Shipment planning, `011` Vendor/fleet assignment, `012` Milestone updates, `013` Customer tracking, `014` ePOD, `015` Actual cost, `016` Invoice, `017` Payment, `018` Profitability, `019` Loyalty point, `020` Dashboard update. This is the single lead→cash→customer-visibility chain Blueprint §19 names as the trust-defining test — no scenario is dropped, renumbered, or merged; each keeps its own preconditions/actor/test-data/steps/expected-result/evidence columns from Blueprint §19.2 as the acceptance spec for its owning capability prompt. Sign-off criteria (Blueprint §19.3, 8 categories: business process, data integrity, access, document, finance, performance, support readiness, training) apply to the suite as a whole, not per-scenario.

### 5.2 18 Tenant Isolation scenarios (`TI-001`–`TI-018`, Blueprint §22.1)

Preserved by ID, scenario, and severity, verbatim: `TI-001` cross-tenant record access (Critical), `002` cross-customer shipment access (Critical), `003` `tenant_id` payload manipulation (Critical), `004` cross-tenant export (Critical), `005` cross-tenant file access (Critical), `006` cross-tenant API token (Critical), `007` cross-tenant report (Critical), `008` cross-tenant realtime subscription (Critical), `009` Supreme Admin impersonation (High), `010` support elevated access (Critical), `011` service-role misuse (Critical), `012` RLS bypass attempt (Critical), `013` branch/company scope bypass (High), `014` field-level bypass (High), `015` customer portal invoice access (Critical), `016` shared service user (High), `017` tenant offboarding (High), `018` deleted/archived record access (Medium/High). Every `TI-*` scenario maps 1:1 onto one or more of `06_*.md` §10's 15 negative tests (e.g. `TI-001`↔test #1, `TI-002`↔test #2, `TI-011`↔test #6, `TI-009`/`TI-010`↔test #5) — the two catalogues are the same design verified from two angles (architecture-time policy design in `06_*.md`, delivery-time scenario execution here), not two independent lists that could silently drift apart. `TI-018` is new relative to `06_*.md` §10 (deleted/archived cross-scope access) — folded into `06_*.md`'s policy families here: a soft-deleted record still carries its original `standard_tenant_scoped`/`customer_portal_scoped` policy (`05_*.md` §4's soft-delete pattern never removes the RLS tenant key), so `TI-018` is provably covered by existing policy design, not a gap.

### 5.3 24 Financial Integrity scenarios (`FINTEST-001`–`FINTEST-024`, Blueprint §23.1)

Preserved by ID and test area, verbatim: `001` double-entry balance, `002` invoice posting, `003` payment allocation, `004` credit note, `005` debit note, `006` currency/FX, `007` tax, `008` period lock, `009` reversal, `010` accrual, `011` revenue recognition, `012` AR aging, `013` AP aging, `014` job profitability, `015` cost overrun, `016` vendor invoice matching, `017` trial balance, `018` balance sheet, `019` P&L, `020` reconciliation, `021` idempotent posting, `022` posted-mutation-attempt rejection, `023` rounding, `024` multi-branch/cost-center allocation — 23 of 24 are release blockers (`023` Rounding is Medium/High, the sole non-blocking row, per Blueprint §23.1's own "Blocker?" column, preserved exactly, not upgraded or downgraded). Every `FINTEST-*` row binds to `05_*.md` §4's finance invariants (idempotent-posting key formula Tech Arch §24.5, append-only `journals`, `record_version`) and `06_*.md` §4's `append_only_ledger` policy family/§8's Supreme Admin exception — `FINTEST-022` is the delivery-time proof of `06_*.md` §10 test #8 (posted-record immutability). The Finance Go-Live Gate (Blueprint §23.2, 12 items — COA/tax/payment-term approval, opening balance reconciled, AR/AP reconciled, posting/allocation/idempotency/period-lock/reversal tested, trial balance/P&L/balance sheet validated, Finance user trained, Finance Manager sign-off) is the phase-exit criterion for Phase 4 (§9 below).

### 5.4 Negative-case expansion (prompt task #3's "expand")

Beyond the three preserved catalogues, every field/record/search/report/export/file/job/support-access surface named in `06_*.md` §10 and `08_*.md` §13 gets its own negative case as that surface ships (e.g., a new `field_masked` field added in a later phase automatically needs a `TI-014`-class masking negative test, not a reopened catalogue) — negative-case growth is additive to §5.2/§5.3's fixed IDs, never a renumbering of them.

## 6. CI gate model

Reproduces Tech Arch §28.1's pipeline verbatim as the binding gate order: `Commit/PR → Lint/Typecheck → Unit/Integration Tests → RLS/Security Tests → Build → Migration Check → Deploy Preview/Staging → E2E/Smoke Test → Manual Gate if Prod → Production Deploy → Post-deploy Monitoring`.

- **Parallelization:** Lint/Typecheck, Unit, and Component layers run in parallel (no ordering dependency between them); RLS/Security Tests run after Unit/Integration (they need the same migrated schema Integration tests use) but before Build, so a policy defect is caught before a build artifact is produced.
- **Flake/quarantine policy:** a test failing intermittently across 3 consecutive runs with no code change is quarantined (marked, excluded from the blocking gate, tracked with an owner and a fix deadline) rather than silently retried into passing — a quarantined test is visible in the readiness dashboard (§13), never hidden.
- **Retries:** transient infrastructure failures (network, container startup) get up to 2 automatic retries; a test failure from application logic never auto-retries into a pass — this mirrors `08_*.md` §7.4's job-retry-vs-failure distinction applied to CI.
- **Coverage meaning:** code coverage percentage is a signal, not a gate by itself — the binding gate is §3's requirement/control matrix (every catalogued ID has a test), which a raw percentage cannot verify; coverage is reported alongside the matrix, never substituted for it.
- **Artifacts:** every CI run publishes its test report, coverage report, and (for E2E/visual) screenshot/video artifacts, retained per the environment's data-sensitivity tier (§4.1) — Staging/Production-adjacent artifacts never contain real tenant data (synthetic-only, §4.2).
- **Failure ownership:** a failing gate blocks merge and is owned by the PR author first, escalating to the layer's Blueprint §18.1 owner (e.g., Security/QA for an RLS test) if unresolved within one business day — no failure is "someone else's problem" by default.
- **No-hidden-failure rule (prompt task #6, binding):** a gate may never be bypassed with `--no-verify`/skip flags on a shared branch (matches this repository's own `AGENTS.md`/session-level Git Safety Protocol); a known-failing test is quarantined visibly (above), never commented out or deleted to make CI green.

## 7. Migration, recovery, compatibility, browser, accessibility, load, DR tests

### 7.1 Clean rebuild and upgrade migration tests

Every migration slice (`05_*.md` §8's expand/migrate/contract waves) has two tests: a **clean rebuild** (apply every migration from empty to head, verify final schema matches the target catalogue) and an **upgrade** (apply migrations incrementally against a database already holding synthetic data at the prior version, verify no data loss and the expand/migrate/contract sequencing holds) — a migration that only passes clean-rebuild but not upgrade is not release-ready, since Production always upgrades, never rebuilds.

### 7.2 Seed validation

Seed data (Blueprint §18.2's "Seed tenant") is itself schema-validated against the same `server/contracts/<domain>/` types production data would satisfy (`08_*.md` §4.1) — a seed script producing a record that would fail its own domain's contract validator is a CI failure, not a silently-accepted shortcut.

### 7.3 Contract compatibility tests

Directly implements `08_*.md` §11's compatibility policy: every deprecated REST path/GraphQL field has a test asserting it still functions until its removal date (§11's overlap window, `ADR-CAND-ARCH-019`); a schema-breaking change without a corresponding deprecation-path test fails CI.

### 7.4 Browser/device matrix, WCAG checks, load/scale profiles, backup/restore, DR rehearsal

- **Browser/device:** latest-two Chrome/Edge/Safari/Firefox (`09_*.md` §8, Blueprint §18.1 "Browser" row) — automated where the tooling supports cross-browser execution, manual spot-check otherwise.
- **WCAG:** `09_*.md` §9's 8-area plan, automated-checker pass (axe-core-equivalent) plus manual keyboard/screen-reader spot-check per release (Blueprint §18.1 "Accessibility" row) — exact automated tool `ADR_REQUIRED` (§11).
- **Load/scale profiles:** Blueprint §21.2's 12 `PERF-*` scenarios (load shipment list at 1M rows, customer search at 100k, milestone burst at 500k, ePOD upload at 10k docs, executive dashboard at 1M+finance rows, bulk import 10k–100k rows, export 50k–500k rows, invoice batch 10k jobs, journal posting 100k lines, WMS ledger 1M rows, realtime dispatch 100 users, config publish at 500 roles/200 workflows) — reproduced by reference as the binding load-test scenario set, each with its own dataset/measurement/bottleneck-to-watch columns from Blueprint §21.2, not re-typed.
- **Backup/restore/DR rehearsal:** exercises Blueprint §24.5's migration rollback procedure and §26.3's cutover rollback procedure in a non-production environment on a scheduled cadence (exact cadence `ADR_REQUIRED`, §11) — DR rehearsal evidence is a first-class artifact (§6's artifact rule), not an assumed capability; RPD-031/037's "contract-silent recovery = best effort" framing means a specific tenant's RPO/RTO commitment (if contracted) gets its own rehearsal scenario, never a generic unverified claim.

## 8. Performance, accessibility, security evidence

### 8.1 Performance

Reproduces Blueprint §21.1's 19-row performance-target table by reference (page load, server response, API mutation, database query, search, pagination, dashboard, bulk import/export/report — all Background-job class per `08_*.md` §9/§10.3's long-running-job pattern, file upload, realtime, milestone update, invoice batch, journal posting, warehouse transaction, config publish) as the binding p50/p95/p99/throughput/error-rate/timeout/rollback-criteria targets — identical numbers to `08_*.md` §12's own budget table where the two overlap (500ms/2s-class targets), no second conflicting number introduced. Blueprint §21.3's engineering rules (avoid N+1, avoid `SELECT *`, server-side filter/sort, composite/partial indexes, materialized views, background jobs, payload minimization, cache/revalidation, realtime limitation) are the same rules already bound in `05_*.md` §7, `06_*.md` §9, and `09_*.md` §11 — this document is the fourth and final place they are cited, always identically, never re-derived with different wording that could drift.

### 8.2 Security

Reproduces Blueprint §20.1's 14-area scope (authentication, authorization, RLS, API, file security, session/token, privileged access, input validation, export/import, financial data, payroll/personal data, webhook, logging, dependency/SCA) and §20.2's severity-based exit criteria (Critical blocks release; High blocks production unless formally risk-accepted by Security Lead + CTO + Sponsor; Medium needs a remediation plan; Low is logged) verbatim as the binding security-test gate. Penetration testing (Blueprint §20.3) is mandatory before General Availability, any enterprise production tenant, or a major public API launch, using OWASP ASVS as the baseline control reference, covering tenant isolation, auth/session, access control, file access, injection, API abuse, webhook, and privileged access — the same 8 areas §5.2's `TI-*` catalogue and `08_*.md` §6's auth control table already cover from two other angles (architecture design, delivery scenario), now covered a third time by independent external verification.

### 8.3 Accessibility

`09_*.md` §9's 8-area WCAG 2.2 AA plan is the binding accessibility-test scope (§7.4 above); this document adds no new accessibility requirement, it only fixes the CI-gate position (§6) and cadence (automated per-release, manual spot-check per release) for verifying it.

## 9. Phase exit criteria

Every phase from `01_*.md` §7 closes only when its own test layers (§2) pass for the capabilities that phase shipped — this document does not invent a new phase list, it binds test evidence to the existing one:

| Phase | Domain | Exit test evidence |
|---|---|---|
| 0 | Discovery/Foundation | Toolchain/CI pipeline itself operational (§6); this document's own gates defined |
| 1 | Platform Core | RLS/RBAC layer green for Platform tables (`06_*.md` §12 Platform slices); Configuration Studio UI + publish-pattern tests (`09_*.md` §12); API/webhook/job foundation contract tests (`08_*.md` §15) |
| 2 | Commercial | `UAT-E2E-001..008` (lead→customer acceptance) automatable subset green; 9 `BR-*` Commercial rules (§3) regression-covered |
| 3 | Operations (+ basic Portal) | `UAT-E2E-009..015` (job→actual cost) green; `TI-002`/`TI-015` (customer/portal isolation) green; WMS basic flow integration tests |
| 4 | Finance | `UAT-E2E-016..018` (invoice→profitability) green; all 24 `FINTEST-*` green except `023` may carry a documented remediation plan (Medium/High, not a hard blocker); Finance Go-Live Gate (§5.3) satisfied |
| 5 | Advanced TMS/WMS | `PERF-003`/`PERF-010` (milestone burst, WMS ledger scale) green at target volumes |
| 6 | Procurement/Vendor | Vendor-rate/vendor-invoice-matching negative tests (`FINTEST-016`) green |
| 7 | HRIS/Ticketing | Payroll/attendance business-rule regression (`BR-ATT-001`/`BR-PAY-001`) green; PII/payroll field-masking negative tests (§5.2 `TI-014`-class) green |
| 8 | Customer Portal/Loyalty | `UAT-E2E-019` (loyalty point) green; full `TI-*` customer-portal subset (`TI-002/009/010/015`) green |
| 9 | Intelligence/Enterprise | `PERF-005`/`PERF-011` (executive dashboard, realtime dispatch) green; `TI-007`/`TI-008` (report/realtime cross-tenant) green; full 17-category integration adapter sandbox tests (`08_*.md` §8.2) green |
| 15 | Full-system hardening | Full `TI-001..018` + `FINTEST-001..024` + `UAT-E2E-001..020` all green; penetration test complete (§8.2) |
| 16 | RC and Go-live | Blueprint §27.1's 19-item Go-Live Checklist fully evidenced; Go/No-Go decision per §27.2 |

## 10. Failure and rollback rules

### 10.1 Baseline vs. regression (prompt task #7)

A failure present before a given change (i.e., in `docs/discovery/07_TEST_QUALITY_BASELINE.md`'s confirmed-`UNKNOWN` starting point, or a subsequently recorded pre-existing failure) is a **baseline failure** — tracked in `ERROR_LEDGER.md`, never silently "fixed" as a side effect of an unrelated change without being called out. A failure newly introduced by a change is a **regression** — blocks that change's merge (§6's no-hidden-failure rule) until fixed or the change is reverted. This distinction is what keeps CI honest during Phase 0 build-out, where the *first* test for any layer necessarily starts from zero coverage, not a green baseline.

### 10.2 Stop/rollback thresholds

Reproduces Blueprint §26.2's rollback-consideration list verbatim: tenant isolation failure, authentication/login outage affecting critical users, data corruption in critical entities, financial posting defect, material migration-reconciliation failure, a critical workflow that cannot execute, performance preventing critical business operation, a security incident during cutover, or a production deployment breaking core pages/API. Any one of these during a deploy triggers Blueprint §26.3's rollback procedure (stop access/disable via feature flag → communicate/freeze → restore previous version → restore/rollback database → re-validate RLS/RBAC and critical data → smoke test → communicate → RCA before retry) — reproduced by reference, not re-authored, so the deployment and testing workstreams describe one rollback procedure, not two.

### 10.3 Zero-critical-defect direct-GA gate

Per RPD-034/036 (binding, no external pilot; direct GA requires full internal validation with zero open Sev-1/critical defects): the Go/No-Go decision (Blueprint §27.2) is **Go** only when every critical gate in Blueprint §27.1's 19-item checklist passes and no Sev-1/critical security, tenant-isolation, or financial issue is open — **Conditional Go** is permitted only for minor known issues with an approved workaround and risk acceptance, never for anything in §5.2/§5.3's Critical-severity rows; **No-Go** is automatic on any critical defect, failed tenant isolation, failed financial integrity, failed migration, or an unready key user. This gate is not softened by delivery pressure — RPD-034/036 are standing decisions, restated here exactly as recorded in `00-control/02_*.md`, not reinterpreted.

## 11. ADR candidates — 2 new

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-022` | Exact test-runner/framework stack (unit/component/integration/E2E tooling) and factory-module location (`tests/factories/` vs. colocated per domain) | Must integrate with the Next.js/TypeScript/Supabase stack already ratified (Tech Arch §5/§6) and support the CI gate order (§6) | Adopt a single JS/TS-native test runner for unit/integration/component layers and a browser-automation tool for E2E/visual-regression (exact products deferred to avoid presuming a specific vendor ahead of Phase 0 tooling evaluation), with `tests/factories/<domain>.ts` as the shared factory location (mirrors `server/contracts/<domain>/`'s per-domain-file convention, `04_*.md` §4) | Architecture/DevEx | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 toolchain setup (Prompt 91, testing foundation) |
| `ADR-CAND-ARCH-023` | DR-rehearsal cadence and automated-accessibility-checker tool (§7.4) | No blueprint-evidenced cadence or tool name; must not be so frequent it burdens Staging, nor so rare it fails to catch drift before a real incident | Adopt a quarterly DR rehearsal cadence (aligned to Blueprint §24/§26's already-defined rollback procedures, exercised rather than newly designed) and an axe-core-equivalent automated WCAG checker wired into the CI accessibility gate (§6, §8.3) | DevOps/QA | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 testing foundation (Prompt 91) |

## 12. Atomic backlog

Sized 1–3 slices each, sequenced to `01_*.md`'s phase order and this document's own §2–§10:

| Slice | Phase | Content | Depends on |
|---|---|---|---|
| CI pipeline foundation | 0 (Prompt 91) | Lint/typecheck/unit/build/migration-check stages (§6) wired per Tech Arch §28.1; flake/quarantine policy tooling; resolves `ADR-CAND-ARCH-022` | Toolchain baseline (Phase 0 environment prompts) |
| Test-data factory foundation | 0 (Prompt 91) | 10 synthetic dataset factories (§4.2), cleanup sweep, `synthetic = true` tenant marker | CI pipeline foundation |
| RLS/RBAC + Tenant Isolation suite | 1 | `06_*.md` §10's 15 tests + `TI-001..018` (§5.2) automated against Platform-core tables | Test-data factory foundation, Platform identity core RLS policies |
| Accessibility/visual-regression CI gate | 0–1 | WCAG automated checker (resolves half of `ADR-CAND-ARCH-023`), screenshot-diff baseline (`09_*.md` §12/§14) | CI pipeline foundation, Design-system foundation (`09_*.md` §14) |
| Commercial E2E + regression | 2 | `UAT-E2E-001..008` automatable subset; 9 `BR-*` regression scenarios | RLS/RBAC + Tenant Isolation suite, Commercial UI/API slices |
| Operations E2E + basic-Portal isolation | 3 | `UAT-E2E-009..015`; `TI-002`/`TI-015`; WMS-basic integration tests | Commercial E2E + regression, Operations UI/API slices |
| Financial Integrity suite + Finance Go-Live Gate | 4 | All 24 `FINTEST-*` (§5.3); Finance Go-Live Gate 12-item checklist | Operations E2E + basic-Portal isolation, Finance UI/API/schema slices |
| Performance/load-test harness | 5 (hardened through 9) | 12 `PERF-*` scenarios (§7.4) at their named dataset volumes | Financial Integrity suite (needs Finance data for `PERF-008/009`) |
| Remaining-domain E2E + isolation | 6–9 | `UAT-E2E-016..020`; remaining `TI-*` (`007/008/009/010/016/017`); per-domain regression | Performance/load-test harness, respective domain slices |
| Migration test harness | Rolling, exercised per domain go-live | Clean-rebuild + upgrade tests (§7.1) per migration slice; seed validation (§7.2) | CI pipeline foundation, respective domain schema slices |
| DR/backup rehearsal program | 15 (hardening) | Quarterly rehearsal cadence (resolves other half of `ADR-CAND-ARCH-023`) exercising Blueprint §24.5/§26.3 procedures | Migration test harness, DevOps environment provisioning |
| Full-system hardening pass | 15 | Full `TI-001..018` + `FINTEST-001..024` + `UAT-E2E-001..020` re-run against complete system; penetration test (§8.2) | Every prior slice |
| Go-live readiness dashboard | 16 | Blueprint §27.1's 19-item checklist wired to live gate status (§13) | Full-system hardening pass |

## 13. Readiness dashboard definitions

A single readiness dashboard (owned by QA/Release Manager, surfaced in the Supreme Admin Portal per `09_*.md` §3's `supreme/system` route, Builder Studio-adjacent) tracks, per environment:

| Widget | Data source | Refresh |
|---|---|---|
| CI gate status (§6) | Latest CI run per branch/PR | Per commit |
| `UAT-E2E-*` sign-off status (20 rows) | Blueprint §19.2's Status/Issue/Sign-off columns | Per UAT cycle |
| `TI-*` pass/fail (18 rows) | Automated RLS/RBAC + Tenant Isolation suite (§12) | Per CI run against Staging/UAT |
| `FINTEST-*` pass/fail (24 rows) | Automated Financial Integrity suite (§12) | Per CI run against Staging/UAT |
| Performance target compliance (Blueprint §21.1, 19 rows) | Load-test harness (§12) | Per release candidate |
| Security exit-criteria status (Blueprint §20.2) | Security scan + manual pen-test findings | Per release + pre-GA |
| Go-Live Checklist (Blueprint §27.1, 19 items) | Aggregated from every row above | Continuous during RC/Go-live phase (16) |
| Baseline-vs-regression failure count (§10.1) | `ERROR_LEDGER.md` + CI failure classification | Per CI run |
| Flaky/quarantined test count (§6) | CI flake-detection tooling | Per CI run |

No dashboard widget is invented beyond what §5/§8/§10 already define as evidence — the dashboard aggregates existing evidence, it does not introduce a new metric with no defined source.

## 14. Exit gates

Every critical control (§3's requirement/control matrix) has a planned automated or explicitly owned manual proof — no catalogued `BR-*`/approval/transition/`EXC-*`/`TI-*`/`FINTEST-*`/`UAT-E2E-*` ID is missing a test-layer assignment. Unsafe-unavailable tests are visible: baseline failures (§10.1) are tracked, not hidden; quarantined tests (§6) are dashboarded (§13), not silently skipped. Direct-GA gates are enforceable: RPD-034/036's zero-critical-defect rule (§10.3) is a hard Go/No-Go criterion, not aspirational language. No test, CI configuration, or source file was created (§0, confirmed against `git status`).

## 15. Completion statement

The layered test architecture (§2) and requirement/control matrix (§3) tie every `01_*.md`–`09_*.md` catalogue to an owning test layer. Environment/data strategy (§4) fixes seven environment tiers and ten synthetic dataset factories with explicit isolation/privacy/cleanup rules. All three mandatory critical-scenario catalogues — 20 `UAT-E2E-*`, 18 `TI-*`, 24 `FINTEST-*` — are preserved verbatim by ID (§5), cross-referenced to `06_*.md`/`08_*.md`/`09_*.md`'s own test rows rather than re-derived independently. The CI gate model (§6) fixes pipeline order, parallelization, flake/quarantine, retry, coverage, artifact, and no-hidden-failure rules. Migration/recovery/compatibility/browser/accessibility/load/DR tests (§7) and performance/accessibility/security evidence (§8) are bound to Blueprint §20/§21's exact tables, never restated with different numbers. Phase exit criteria (§9) tie every one of `01_*.md`'s 12 phases to concrete test evidence. Failure/rollback rules (§10) fix the baseline-vs-regression distinction and RPD-034/036's zero-critical-defect direct-GA gate as enforceable, not aspirational. 2 new ADR candidates are raised (`022` test-runner/factory-location tooling, `023` DR cadence/accessibility-checker tooling), both non-blocking and deferred to Phase 0 Prompt 91. The 13-slice atomic backlog (§12) and readiness dashboard (§13) close out the workstream's planning scope.

Next eligible prompt: `03-architecture-and-plan/46_DEVOPS_WORKSTREAM_PROMPT.md` → `docs/architecture/11_DEVOPS_WORKSTREAM.md`.
