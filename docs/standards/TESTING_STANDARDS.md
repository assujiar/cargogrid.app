# CargoGrid Testing Standards and Foundation

**Established by:** `CG-S5-PH0-012` (Prompt 91 — Testing Foundation)
**Status:** Active — runner/config/harness/conventions decided and implemented at the tooling layer; domain-specific fixtures, contract tests, RLS/tenant-isolation suites, and component/E2E tests against real UI remain Phase 1+ scope (no schema, contract, or `components/ui/` code exists yet — `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`, `docs/standards/DESIGN_SYSTEM.md` §1). This document fixes every convention Phase 1+ needs so each domain's first test file requires zero re-litigation — the same deferral pattern `DESIGN_SYSTEM.md` used for component implementation.

This document distills the normative testing foundation from `docs/architecture/10_TESTING_WORKSTREAM.md` (already `VERIFIED`, not re-derived) plus `ADR-0007`/`ADR-0008` (this checkpoint). It extends `docs/standards/CODING_STANDARDS.md` §6, which deferred the runner choice here.

## 1. Runner/tooling (decided — `ADR-0007`, `ADR-0008`)

| Layer | Tool | Location |
|---|---|---|
| Unit / integration / component (server-side) | `node:test` + `node:assert/strict` | `*.test.ts`, colocated next to the module it tests (`CODING_STANDARDS.md` §6, now ratified not provisional) |
| E2E / visual-regression / browser automation / accessibility | `@playwright/test@1.61.1` + `@axe-core/playwright@4.12.1` | `e2e/*.spec.ts`, config at `playwright.config.ts` |
| Coverage | `node --experimental-test-coverage` (built-in) | `pnpm run test:coverage` — signal, never a hard gate (§6 below) |
| Shared deterministic-seed primitive | `tests/factories/seed.ts` | Foundation only — no domain shape (§4) |
| Per-domain factories (Phase 1+) | `tests/factories/<domain>.ts` | One file per domain, created by that domain's owning capability prompt |

## 2. Naming, tags, environments, artifacts

- **Naming:** `<module-under-test>.test.ts` (unit/integration/component, colocated) or `e2e/<flow>.spec.ts` (Playwright). No `__tests__/` directory convention — matches this repository's existing colocated pattern (`scripts/env/validate.test.ts`, `scripts/git/*.test.ts`), not a new one.
- **Tags:** a test's layer is its file location/extension, not an inline tag string — `scripts/**/*.test.ts` and `tests/factories/*.test.ts` are unit/integration; `e2e/*.spec.ts` is E2E/browser. Once RLS/contract/component-in-browser layers exist (Phase 1), each gets its own top-level directory (`tests/rls/`, `tests/contract/`, `tests/component/`) rather than an inline tag on a shared directory — directory-as-layer keeps `10_*.md` §6's CI parallelization rule (§3 below) mechanical (glob the directory, not parse a tag).
- **Environments:** reproduces `10_*.md` §4.1's seven-tier ladder (Local, Development, Testing, Staging, UAT, Production, Sandbox) verbatim — this document adds no new tier. Every test in this repository today runs at the Local/CI tier only (no Development/Staging/UAT environment is provisioned yet, `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md`).
- **Artifacts:** `node:test`'s coverage report (`test:coverage`) and Playwright's HTML report/trace/screenshot-on-failure (`playwright.config.ts`'s `reporter`/`use.trace` options) are both CI-published (`.github/workflows/ci.yml`'s `e2e` job, `actions/upload-artifact` once a failure occurs) — matches `10_*.md` §6's artifact-retention rule. No artifact contains real tenant data (§4 below — synthetic-only).

## 3. CI gate order and parallelization

Reproduces `10_*.md` §6 verbatim, applied to this repository's actual two jobs today: `quality` (lint/typecheck/`node:test`/standards-check, existing since `PH0-88`/`PH0-89`) and `e2e` (this checkpoint, Playwright/axe-core) run **in parallel** — no ordering dependency between them yet, since neither depends on a migrated database (that dependency, and the resulting "RLS/Security Tests run after Unit/Integration" ordering rule, applies starting Phase 1 once a real schema exists). Both are required checks; a fork PR's `e2e` job runs under the same read-only, no-secret trigger model as `quality` (`ADR-0004`'s `pull_request`-not-`pull_request_target` reasoning, restated not re-litigated).

## 4. Test-data factory foundation

Reproduces `10_*.md` §4.2's binding rules, restated exactly, applied to what exists today:

- **Determinism:** every factory-produced value derives from a fixed seed, never `Math.random()`/wall-clock/`crypto.randomUUID()`-style non-reproducible sources — a failing test must reproduce byte-for-byte. `tests/factories/seed.ts` (this checkpoint) is the one shared PRNG (`mulberry32`, a small deterministic 32-bit generator with no external dependency) every future domain factory seeds from, so no two domain factories invent their own randomness source that could silently diverge.
- **Scope discipline (this checkpoint's own decision, consistent with `ADR-0001`/`DESIGN_SYSTEM.md` §2):** `tests/factories/seed.ts` contains zero domain-specific shape (no tenant/customer/shipment fields) — creating `tests/factories/<domain>.ts` today, with no domain schema/contract to validate the shape against, would be exactly the premature-scaffold pattern `ADR-0001` exists to prevent, generalized from folders to fixture files. Each domain's first factory is written by that domain's own owning capability prompt (Phase 1+), importing `seed.ts`'s primitive.
- **10 named datasets (Blueprint §18.2, reproduced by reference, not re-typed):** Seed tenant, Multi-tenant isolation set, Commercial set, Operations set, Finance set, WMS set, HRIS set, Customer portal set, Performance set, Migration set — each becomes one or more domain factory functions once its owning schema slice lands; none is stubbed now.
- **Synthetic marker / cleanup:** every factory-created tenant carries a `synthetic = true` marker and is purged by an automated sweep after its owning CI run or on a scheduled retention job (`10_*.md` §4.2) — this requires a real `tenants` table and is therefore a Phase 1 Platform Core implementation item, tracked here as a binding requirement on that table's first migration, not implemented against a table that does not exist.
- **Isolation fixture:** the Multi-tenant isolation set (two tenants, A and B, structurally identical-looking records) is the fixture every `TI-*` scenario runs against (`10_*.md` §4.3) — same deferral: requires real tenant-scoped tables.
- **Privacy:** synthetic PII (name, phone, email, ID number) is always generated from the seed primitive, never copied from real tenant data, in any environment below Production/UAT's tenant-approved subset (`10_*.md` §4.2).

## 5. Isolation, cleanup, flake/quarantine

- **Isolation:** `node:test` files run in isolated Node worker processes by default (no shared in-process global state leaks between `.test.ts` files); Playwright specs run in isolated browser contexts per test (`playwright.config.ts`'s default `use` scope) — no test in this repository shares mutable state with another today (confirmed: every existing `.test.ts` file only asserts against its own module's pure functions or a freshly constructed fixture, `docs/build-log/phase-00/PH0-86.md` through `PH0-89.md`).
- **Cleanup:** no test in this repository writes to a shared filesystem path, database, or external service today — nothing to clean up yet. The cleanup contract for the first layer that does (database fixtures, Phase 1) is: every test-created row is scoped to a disposable, per-CI-run database/schema, torn down after the run, never a shared/live database (`AGENTS.md` "Database and migration rules," restated).
- **Flake/quarantine policy (`10_*.md` §6, adopted as binding convention; no tooling exists to auto-detect flake yet since zero flaky test has ever occurred in this repository):** a test failing intermittently across 3 consecutive CI runs with no code change is quarantined — moved to a `*.quarantine.test.ts`/`*.quarantine.spec.ts` suffix (excluded from the default `test`/`test:e2e` glob, still present and visible in the repository, never deleted or commented out) with an owner and fix deadline recorded in `docs/runtime/KNOWN_ISSUES.md`. A test failure from application logic never auto-retries into a pass; transient infrastructure failures (browser launch, network) get up to 2 automatic retries (`playwright.config.ts`'s `retries` option, CI-only — 0 retries locally so a real local failure is never masked).

## 6. Coverage, baseline-vs-regression

- **Coverage is a signal, not a gate** (`10_*.md` §6, restated verbatim): `pnpm run test:coverage` reports line/branch/function coverage; no numeric threshold blocks CI. The binding gate is `10_*.md` §3's requirement/control matrix (every catalogued `BR-*`/`TI-*`/`FINTEST-*`/`UAT-E2E-*`/exception/transition ID has an assigned test layer) — a percentage cannot verify that mapping, so it is never substituted for it.
- **Baseline vs. regression** (`10_*.md` §10.1, restated verbatim): a failure present before a given change is a baseline failure, tracked in `docs/runtime/ERROR_LEDGER.md`, never silently fixed as an uncalled-out side effect. A failure newly introduced by a change is a regression and blocks that change's merge. As of this checkpoint the baseline is `UNKNOWN`→now-partially-`KNOWN` (`docs/discovery/07_TEST_QUALITY_BASELINE.md`'s original `UNKNOWN` finding; this repository has carried zero failing test since `PH0-86`'s first test file).

## 7. NOT_RUN policy for unavailable layers

Reproduces `10_*.md`'s Alternative flow (§22 of Prompt 91, restated as binding convention): a test layer with no real subject yet (RLS/RBAC, contract, component-in-browser, integration-with-database, full accessibility-against-real-UI, performance/load, DR rehearsal execution) is explicitly recorded as `NOT_RUN` with its owning future capability prompt named — never given a fabricated passing step, never silently omitted without explanation. Current `NOT_RUN` layers and owners:

| Layer | Why not run yet | Owning future task |
|---|---|---|
| Database / migration / RLS / RBAC | No schema exists (`docs/discovery/04_*.md`) | Phase 1 Platform Core schema slices |
| Contract (REST/GraphQL parity) | No `server/contracts/<domain>/` exists | Phase 1+ per-domain API slices |
| Component-in-browser (against real `components/ui/`) | No component exists (`DESIGN_SYSTEM.md` §1) | Phase 1 Platform Core `components/ui/` slice |
| Full accessibility-against-real-UI | Same — `e2e/smoke.spec.ts` (this checkpoint) proves the axe-core wiring against synthetic inline content only | Phase 1, first real page/component |
| Visual-regression baseline (`toHaveScreenshot()`) | Mechanism decided (`ADR-0007`, Playwright), but no committed baseline exists — a screenshot baseline captured with no real component would need re-capture the moment one exists, and cross-environment font/rendering drift makes a synthetic baseline unreliable evidence | Phase 1, first real component |
| DR rehearsal execution | Cadence decided (`ADR-0008`, quarterly), no Staging/backup infrastructure exists yet | Phase 0 DevOps environment prompts, then ongoing |
| Performance/load (`PERF-*`, Blueprint §21.2) | No application, no data volume to load-test | Phase 1+, per `10_*.md` §12's atomic backlog |
| Financial Integrity (`FINTEST-*`), Tenant Isolation (`TI-*`), End-to-end UAT (`UAT-E2E-*`) suites | No finance/tenant/business-flow schema or UI exists | Per `10_*.md` §9's phase-exit mapping |

## 8. Business/validation/access rules (restated, binding)

- Tests validate behavior/control, not implementation trivia; a test is never disabled/weakened to make a gate pass (`AGENTS.md` "Test and gate policy," `10_*.md` §6's no-hidden-failure rule).
- Two-tenant negative evidence is mandatory for every tenant-scoped path once tenant-scoped tables exist (§4's isolation fixture).
- Fixtures are isolated/repeatable; test results include counts/duration/artifacts (§2).
- Test identities (once auth exists) cover roles/scopes/field/record/support surfaces with no privileged default bypass; least privilege and server-only secrets remain mandatory (`AGENTS.md`).

## 9. Smoke evidence this checkpoint

`e2e/smoke.spec.ts` proves the Playwright + `@axe-core/playwright` layer is correctly wired: (1) a deliberately WCAG-violating inline HTML fixture is scanned and asserted to produce at least one violation (proves the checker is actually running, not vacuously passing), (2) a corrected version of the same fixture is scanned and asserted to produce zero violations (proves the checker is not vacuously failing either), (3) a basic navigation/assertion smoke proves the browser-automation layer itself launches and interacts correctly. `tests/factories/seed.test.ts` proves `tests/factories/seed.ts`'s determinism: the same seed produces the identical output sequence across repeated calls; two different seeds produce different sequences. Neither test touches a real page, a real component, or real/synthetic tenant data — both are the `10_*.md` §22 "Alternative flow" smoke examples proving each configured layer, not a substitute for the `NOT_RUN` layers in §7.
