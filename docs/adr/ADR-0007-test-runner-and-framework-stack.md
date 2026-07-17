# ADR-0007 — Test-runner and framework stack

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-022` (`docs/architecture/10_TESTING_WORKSTREAM.md` §11)   Owning phase/task: Phase 0 (`CG-S5-PH0-012`, Prompt 91, Testing Foundation)

## Question

`ADR-CAND-ARCH-022` calls for "a single JS/TS-native test runner for unit/integration/component layers and a browser-automation tool for E2E/visual-regression (exact products deferred to avoid presuming a specific vendor ahead of Phase 0 tooling evaluation), with `tests/factories/<domain>.ts` as the shared factory location." `docs/standards/CODING_STANDARDS.md` §6 defers the same choice here, noting the repository's provisional working pattern (`node:test`, 45 passing tests as of `PH0-90`). Which exact products, and does the provisional pattern become the ratified one?

## Options

### Unit/integration/component runner

1. **`node:test` + `node:assert/strict` (SELECTED), continuing the provisional pattern.**
   - Trade-off: zero new dependency (already a `devDependencies` line in no package — it ships with the pinned Node runtime itself, `>=22.11.0` per `ADR-0002`); already proven correct against 45 real tests across `scripts/env/**` and `scripts/git/**` with zero framework-attributable defect; built-in `--experimental-test-coverage` gives line/branch/function coverage with no extra tooling. A component-test layer (once `components/ui/` exists, Phase 1) can run under the same runner using `@testing-library/react`-equivalent DOM assertions without switching runners.
   - Trade-off against: a dedicated framework (Vitest, Jest) offers richer snapshot/mock ergonomics and a larger plugin ecosystem. Neither gap is evidenced as needed yet — no snapshot or complex-mock requirement exists in any `VERIFIED` architecture document, and introducing a framework dependency (plus its own version-pin/upgrade surface, `ADR-0002`'s own rationale) to solve a hypothetical future need would be the same premature-scaffold pattern `ADR-0001` exists to prevent, generalized from folders to tooling.
2. **Vitest.** TS-native, Jest-compatible API, fast watch mode via esbuild/Vite.
   - Trade-off: adds a build-tool dependency graph (Vite) this repository does not otherwise need (Next.js owns bundling); no evidenced gap `node:test` cannot close; would require rewriting 45 already-passing, already-correct tests for no functional gain.
3. **Jest.** Long-established, huge ecosystem.
   - Trade-off: heaviest dependency footprint of the three; ESM/TypeScript-strip-types interop (this repository's `--experimental-strip-types` pattern, `ADR-0002`) is native to `node:test` and requires extra configuration (`ts-jest`/`babel-jest`) under Jest; no evidenced gap justifies the added surface.

### E2E / visual-regression / browser automation

1. **Playwright (`@playwright/test`, SELECTED).**
   - Trade-off: TypeScript-native (matches this repository's strict-mode/ESM baseline with no transpile-config divergence from `node:test`'s own pattern), single package provides browser automation, network mocking, and built-in visual-regression (`expect(page).toHaveScreenshot()`) with no second product needed for `ADR-CAND-ARCH-023`'s "visual-regression tool" line item (`PH0-90.md` §3 item 3 deferred this exact tool choice here). Supports the latest-two Chrome/Edge/Safari/Firefox matrix `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §8 requires (Chromium/WebKit/Firefox engines, Edge covered via Chromium). Verified current stable via `npm view @playwright/test version dist-tags` this checkpoint: `1.61.1` (`latest`), not asserted from memory.
   - Trade-off against: heavier CI cost than a headless-only tool (browser binaries must be installed per CI run, `docs/build-log/phase-00/PH0-91.md` §6) — accepted, since this is the standing cost of any real browser-automation layer, not specific to Playwright.
2. **Cypress.**
   - Trade-off: strong DX but no multi-tab/multi-origin support without workarounds relevant to `08_API_INTEGRATION_WORKSTREAM.md`'s webhook/OAuth-adjacent flows; visual regression requires a paid add-on (Cypress Cloud) or a third-party plugin — Playwright's is built in, avoiding a second tool/vendor for the same `ADR-CAND-ARCH-023` line item.
3. **Selenium/WebDriver-based tooling.**
   - Trade-off: no built-in TypeScript-first test runner, no built-in visual-regression, materially more assembly required for the same outcome Playwright provides as one package.

### Factory location

**`tests/factories/<domain>.ts` (SELECTED)** — exactly as `ADR-CAND-ARCH-022`'s own recommendation and `docs/architecture/10_TESTING_WORKSTREAM.md` §4.2 specify, mirroring `server/contracts/<domain>/`'s per-domain-file convention (`docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` §4). No alternative location was evaluated — the source document's own convention is already evidenced and consistent with the repository's established per-domain file pattern; there is no competing convention anywhere in `01_*.md`–`13_*.md` to weigh against it.

## Decision

1. **Unit/integration/component:** `node:test` + `node:assert/strict`, ratifying the provisional pattern as binding (`docs/standards/CODING_STANDARDS.md` §6 updated to remove "provisional" framing — see Propagation). Coverage evidence via `node --experimental-test-coverage` (new `test:coverage` script), reported as a signal alongside the requirement/control matrix (`10_*.md` §6 "coverage meaning"), never substituted for it — no numeric coverage threshold is set as a hard gate by this ADR.
2. **E2E/visual-regression/component-in-browser:** Playwright (`@playwright/test@1.61.1`), config at `playwright.config.ts`, specs under `e2e/`.
3. **Factory location:** `tests/factories/<domain>.ts`, one file per domain, created by the domain's own owning capability prompt (Phase 1+) — not eagerly scaffolded now. `tests/factories/seed.ts` (this checkpoint) provides the shared deterministic-seed primitive every domain factory will build on (§20 task 2's "shared deterministic factories/fixtures foundation"), holding no domain-specific shape itself.

## Evidence

- `docs/architecture/10_TESTING_WORKSTREAM.md` §11 (`ADR-CAND-ARCH-022`'s exact question/recommendation) and §4.2 (factory-location convention).
- `docs/standards/CODING_STANDARDS.md` §6 (provisional pattern, 45 passing tests as of `PH0-90`).
- `npm view @playwright/test version dist-tags` (this checkpoint): `1.61.1` latest stable, confirmed current, not presumed.
- `npm view @axe-core/playwright version dist-tags` (this checkpoint): `4.12.1` latest stable — the accessibility-checker product decided in `ADR-0008`, consumed by the Playwright E2E layer this ADR establishes (kept as a separate ADR because it resolves a distinct candidate, `ADR-CAND-ARCH-023`, not this one).
- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §8 (browser/device matrix Playwright must cover).
- Local verification this checkpoint: `node --experimental-strip-types --experimental-test-coverage --test scripts/env/validate.test.ts` produced a real line/branch/function coverage report on Node `22.22.2` (the pinned `>=22.11.0` baseline) with no extra dependency — confirms the coverage claim above is a demonstrated capability, not an assumption.

## Consequences

- **DB/API/UI:** none directly — no domain schema/contract/component exists yet (Phase 1 scope); this ADR fixes the tooling those future layers will run under.
- **Security:** Playwright browser binaries are installed only in CI/local dev (`playwright.config.ts` uses the default browser-cache path, no credential/secret is embedded in any spec); `e2e/smoke.spec.ts` (this checkpoint) uses only synthetic, inline HTML content — no external network call, no real tenant/app data (`docs/architecture/10_*.md` §4.2's synthetic-only rule, satisfied even though no domain fixture exists yet).
- **Performance:** a new CI job (`e2e`, `.github/workflows/ci.yml`) runs in parallel with the existing `quality` job, not serialized after it — matches `10_*.md` §6's "Lint/Typecheck, Unit, and Component layers run in parallel" rule, generalized to this job-level split since no shared migrated-schema dependency exists yet to force ordering (that ordering rule applies once RLS/Integration tests need a real database, Phase 1).
- **Migration/rollback:** additive only — removing `@playwright/test`/`@axe-core/playwright` from `package.json`, `playwright.config.ts`, and `e2e/**` fully reverts this ADR's code footprint with no effect on `node:test`'s existing 45+ tests.
- **Downstream impact:** Phase 1's first domain factory (`tests/factories/<domain>.ts`) imports `tests/factories/seed.ts`'s deterministic-seed primitive rather than inventing its own randomness source — keeps every future synthetic dataset reproducible byte-for-byte (`10_*.md` §4.2's binding rule) from one shared origin. The RLS/RBAC + Tenant Isolation suite (`10_*.md` §12, Phase 1) and the Accessibility/visual-regression CI gate (`10_*.md` §12, Phase 0–1) both build directly on this checkpoint's `playwright.config.ts`/`@axe-core/playwright` wiring rather than re-deciding tooling.

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-91.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-022` `ACCEPTED`) and §6 (index); `docs/standards/CODING_STANDARDS.md` §6 (provisional → ratified, cross-reference added); `docs/standards/TESTING_STANDARDS.md` (this checkpoint, full naming/tag/isolation/flake convention built on this ADR's runner choice); `package.json` (`@playwright/test`, `@axe-core/playwright` devDependencies; `test:e2e`, `test:coverage` scripts); `.github/workflows/ci.yml` (new `e2e` job). Does not alter any CPD/RPD or any `docs/architecture/**` decision.
