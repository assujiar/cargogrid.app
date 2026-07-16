# Phase 0 → Phase 1 Entry Package

**Produced by:** `CG-S5-PH0-022` (Prompt 101 — Phase 0 Documentation and Handoff)
**Audience:** an independent Phase 1 agent with **zero prior context** from this build session — every fact below is either directly cited to a `VERIFIED` document or explicitly marked as this checkpoint's own reconciliation.
**Status of this package itself:** complete pending one external precondition — `CG-S5-PH0-023` (Prompt 102, Phase 0 Closure Verification) has not yet run. **Nothing in this document should be read as `PHASE_0_VERIFIED` being set** — only Prompt 102 may set that (`102_PHASE0_CLOSURE_VERIFICATION_PROMPT.md`, "only this prompt may set `PHASE_0_VERIFIED`").

This is a **new, self-contained artifact**, distinct from `docs/runtime/HANDOFF.md` (which remains the intra-Phase-0, checkpoint-to-checkpoint runtime handoff and retains its own incident-history narrative). This package exists specifically for the "fresh Phase 1 agent reconstructs Phase 0 and starts the exact eligible Phase 1 task safely" flow named in Prompt 101 §21.

## 1. Verified dependencies (what Phase 1 may rely on as fact)

| Closure | Status | Evidence |
|---|---|---|
| Step 2 — Discovery | `RUNTIME_DISCOVERY_VERIFIED` | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` |
| Step 3 — Architecture and Execution Blueprint | `RUNTIME_ARCHITECTURE_VERIFIED` | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` (Lineage A, reconciled from `ERR-2026-003`, `RECOVERED`) |
| Phase 0 capability tasks (`081`–`098`, `CG-S5-PH0-002..019`) | All `VERIFIED` | `docs/runtime/TASK_LEDGER.md` §2; individual build logs `docs/build-log/phase-00/PH0-83.md`–`PH0-98.md` |
| Phase 0 Integrated Verification (`099`, `CG-S5-PH0-020`) | `VERIFIED` | `docs/build-log/phase-00/PH0-99.md` |
| Phase 0 Hardening (`100`, `CG-S5-PH0-021`) | `VERIFIED` | `docs/build-log/phase-00/PH0-100.md` |
| Phase 0 Documentation and Handoff (`101`, `CG-S5-PH0-022`, this checkpoint) | `IN_PROGRESS` → `VERIFIED` on this checkpoint's own close | This document + `docs/build-log/phase-00/PH0-101.md` |
| Phase 0 Closure Verification (`102`, `CG-S5-PH0-023`) | `NOT_STARTED` — the one remaining gate before `PHASE_0_VERIFIED` | `102_PHASE0_CLOSURE_VERIFICATION_PROMPT.md` |

**Greenfield status (still true):** zero business-domain code exists anywhere in this repository. Everything listed in §2 below is foundation/tooling/documentation, not a feature.

## 2. Preserved assets (what already exists — do not recreate)

### 2.1 Real, non-documentation files (everything outside `docs/`)

| Path | Purpose | Established at |
|---|---|---|
| `package.json`, `pnpm-lock.yaml` | pnpm `10.33.0`, Node `>=22.11.0` pinned; see §5 for the full script catalogue | `PH0-085` (`ADR-0002`) |
| `tsconfig.json`, `next-env.d.ts` | Strict TypeScript; `allowImportingTsExtensions`/`noEmit` required for Node-native `.ts` execution | `PH0-085`/`086` |
| `eslint.config.js` | Flat config; 2 `import/no-restricted-paths` boundary zones (platform-kernel↔domain, no domain imports into `CPT`/`REP`) + 2 `no-restricted-syntax` bans (`SELECT *`, raw `process.env.SUPABASE_SERVICE_ROLE_KEY`) — inert today (no `lib/`/`server/`/`app/` exists yet), activate the moment those directories are created | `PH0-089` |
| `supabase/config.toml` | Empty project scaffold, Postgres 17, from a real `supabase init` run — no schema, no migration | `PH0-085` |
| `.env.example`, `.gitignore` | Real env-var template (6 vars); root `.gitignore` (closed `ISS-2026-003`) | `PH0-085` |
| `.github/workflows/ci.yml` | `quality` job (typecheck/lint/test/docs/security/data-classification/threat-model/standards/git checks) + separate `e2e` job | `PH0-088` (`ADR-0004`) through `PH0-095`/`096` (gates added incrementally) |
| `playwright.config.ts`, `e2e/smoke.spec.ts` | Playwright `1.61.1` + `@axe-core/playwright@4.12.1`; proves browser automation + accessibility-checker wiring against a synthetic fixture, not a real page (none exists) | `PH0-091` (`ADR-0007`/`ADR-0008`) |
| `tests/factories/seed.ts` | Deterministic mulberry32 PRNG seed factory foundation — no domain factory yet | `PH0-091` |
| `scripts/env/` (`schema.ts`, `validate.ts`, `redact.ts`, `client-guard.ts`) | Typed env validation, 7-tier environment-class enum, symmetric production-linkage rule, `assertServerOnly()` | `PH0-086` |
| `scripts/preflight-env-check.ts` | CLI entry (`pnpm run preflight`) delegating to `scripts/env/validate.ts` | `PH0-085`/`086` |
| `scripts/git/` (`check-branch-name.ts`, `check-commit-message.ts`, `check-protected-paths.ts`, `check-worktree-collision.ts`) | Non-destructive local collision/hygiene checks | `PH0-087` |
| `scripts/standards/check-suppressions.ts` | Scans for ungoverned `eslint-disable*`/`@ts-expect-error`/`@ts-ignore` | `PH0-089` |
| `scripts/docs/check-doc-links.ts` | Validates internal doc citations, canonical runtime files, ADR index, HANDOFF/TASK_LEDGER coherence | `PH0-092`, extended `PH0-100` |
| `scripts/observability/logger.ts` | Structured logging, `redact()`, correlation ID, cardinality guard, safe-degrade | `PH0-093` (`ADR-0009`) |
| `scripts/security/check-secrets.ts`, `threat-model.ts` | Secret scanner (credential-shaped only, see §7); 25-entry STRIDE threat register with reproducible risk-ranking | `PH0-094`/`096` (`ADR-0010`) |
| `scripts/data-classification/registry.ts`, `check-registry.ts` | Two-axis sensitivity taxonomy, CI-enforced adoption gate (0 unclassified secret env vars) | `PH0-095` |
| `scripts/product-analytics/analytics.ts` | Event validation, prohibited-property rejection, HMAC pseudonymization, dedup, safe-degrade — **no provider integrated, none approved** | `PH0-097` |
| `scripts/feature-flags/flags.ts` | Deterministic (SHA-256 bucketed) evaluation engine, 8-dimension `FlagDefinition`, `DUP-012` structurally enforced (no auth-adjacent import) — **no persistence table, no real flag defined** | `PH0-098` |
| `scripts/verification/phase0-integration.test.ts` | 9 cross-foundation integration tests proving the above modules compose correctly together | `PH0-099` |

**Nothing exists in `app/`, `lib/`, `server/`, `components/`, or any migration directory.** `04_REPOSITORY_TARGET_STRUCTURE.md`'s wave-2 boundary (Phase 1 Platform Core) governs all of that — Phase 1's own kickoff prompt (`CG-S6-PLT-001`, §3 below) is where those directories are first created, not before.

### 2.2 Real, ratified decisions (ADRs)

All 10 `ADR-0001`–`ADR-0010` in `docs/adr/` are `ACCEPTED` — see `docs/adr/README.md` §6 for the index and §5 for full `ADR-CAND-ARCH-*` reconciliation (11 resolved in Step 3, 8 more `ACCEPTED` during Phase 0, 8 genuinely still open and correctly deferred to a named Phase 1+ task — none blocking).

### 2.3 Standards documents (`docs/standards/`)

`TESTING_STANDARDS.md`, `DOCUMENTATION_STANDARDS.md`, `OBSERVABILITY_STANDARDS.md`, `SECURITY_STANDARDS.md`, `DATA_CLASSIFICATION_STANDARDS.md`, `PRODUCT_ANALYTICS_STANDARDS.md`, `FEATURE_FLAG_STANDARDS.md`, `CODING_STANDARDS.md`, `DESIGN_SYSTEM.md` — each cites its own source architecture document and discloses what remains `NOT_RUN` pending real application code.

## 3. Exact first eligible prompt (contingent, not yet active)

**Prompt 104 — Platform Core WBS and Runtime Kickoff** (`CG-S6-PLT-001`, `docs/ai-agent-build-prompt-package/06-phase-01-platform-core/104_PLATFORM_CORE_WBS_RUNTIME_KICKOFF_PROMPT.md`). Its own first required task is "Reconfirm Step 2, Step 3 and Phase 0 closure reports at one active checkpoint" — i.e. it re-validates `PHASE_0_VERIFIED` itself before proceeding, so this package does not need to (and must not) assert that flag is set. **It becomes eligible only after `CG-S5-PH0-023` (Prompt 102) completes and records `PHASE_0_VERIFIED`** — until then, the correct next action for any agent reading this package is Prompt 102, not Prompt 104.

## 4. Known issues carried into Phase 1 (from `docs/runtime/KNOWN_ISSUES.md`, current state)

| ID | Status | Carries into Phase 1 as |
|---|---|---|
| `ISS-2026-005` | `OPEN`, Low | A documentation-completeness gap in `CHANGE_MANIFEST.md` (Prompts 83–90 entries never backfilled) — does not affect any code, schema, or decision; owner DevEx, pick up opportunistically |
| `ISS-2026-007` | `OPEN`, Medium | No working automated dependency/supply-chain audit gate (`pnpm audit` calls a retired npm endpoint at pnpm `10.33.0`) — re-attempt once pnpm ships bulk-endpoint support; `pnpm install --frozen-lockfile` remains the real, working deterministic-install control in the interim |
| `ISS-2026-006` | `ACCEPTED_RISK`, Low | 4 historical citations to deleted plural build-log paths, excused via a named allowlist — no action needed |
| All others (`ISS-2026-001..004`, `008`) | `RESOLVED` | No action needed |

**No Critical or unresolved High-severity issue exists.** Neither open issue blocks any Phase 1 gate or decision (both confirmed non-blocking in their own record).

## 5. Environment commands (verified working, this checkpoint)

```
pnpm install --frozen-lockfile   # deterministic install
pnpm run typecheck               # tsc --noEmit
pnpm run lint                    # eslint .
pnpm run test                    # node:test, scripts/**/*.test.ts + tests/**/*.test.ts
pnpm run test:e2e                # Playwright + axe-core
pnpm run docs:check              # scripts/docs/check-doc-links.ts
pnpm run security:check          # scripts/security/check-secrets.ts
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check         # scripts/standards/check-suppressions.ts
pnpm run git:check               # scripts/git/check-worktree-collision.ts + check-branch-name.ts
pnpm run git:check-paths         # scripts/git/check-protected-paths.ts
pnpm run preflight               # scripts/preflight-env-check.ts
```

All 11 gates (plus `preflight`, which fails closed by design — no real environment is provisioned yet) pass as of this checkpoint's own `docs/build-log/phase-00/PH0-101.md` §6 gate run. `node:test` count at this checkpoint: see that same section (grows with each new test file; do not treat any specific number here as durable — read the live gate output).

## 6. Residual risks Phase 1 should be aware of (not blocking, all already-disclosed)

- **RPD-022** (Supreme Admin absolute CRUD) — no tamper-proof/immutability claim may ever be made; Phase 1's first audit/finance-adjacent feature must disclose this, not silently assume immutability.
- **`JWT_SHAPED_TOKEN` cannot lexically distinguish a sensitive service-role JWT from a safe anon-key JWT** (`SECURITY_STANDARDS.md` §3/§6) — a deliberately conservative, false-positive-tolerant scanner design; Phase 1 should not "fix" this by narrowing the pattern.
- **8 `ADR-CAND-ARCH-*` candidates remain genuinely open**, each already scoped to a named Phase 1+ task (`012`/`013`/`014`/`015`/`017`/`018`/`019`/`027` — see `docs/adr/README.md` §5.2) — Phase 1 should resolve each at its own owning task, not assume a default.
- **Security controls needing a real request/session/route surface are fixed as contracts, `NOT_RUN`** (`SECURITY_STANDARDS.md` §1: headers, CORS/CSRF, session/MFA, upload/malware-scan, RLS/RBAC enforcement) — real from the first Phase 1 route/table onward, not before.
- **No analytics provider and no persistence for feature flags exist** — both foundations are real and tested but intentionally inert until Phase 1 names an approved vendor / creates the `feature_flags` table (`05_DATABASE_SCHEMA_WORKSTREAM.md` §4 migration wave).

## 7. One explicit design boundary Phase 1 should not accidentally "fix"

`scripts/security/check-secrets.ts` deliberately does not flag PII-shaped key names (`npwp`/`bank`/`salary`) — that is `scripts/data-classification/`'s and `scripts/product-analytics/analytics.ts`'s job for their own data-flow surfaces, not a gap in the secret scanner (`docs/standards/SECURITY_STANDARDS.md` §3, resolved `ISS-2026-008` at `PH0-100`). A future contributor unfamiliar with this history might reasonably propose "fixing" it — this section exists so that proposal is evaluated against the recorded rationale, not treated as an obviously-missed gap.

## 8. Fresh-context reconstruction check (Prompt 101 §28, rehearsed this checkpoint)

Reading only this document plus its cited paths (no other session context), an agent can determine: what phase the repository is in (Phase 0, pending Prompt 102 closure), what exists on disk (§2), what is decided vs. still open (§2.2, §6), what commands verify the current state (§5), what the exact next prompt is once Phase 0 formally closes (§3), and what NOT to "fix" without re-reading history first (§7). This satisfies Prompt 101 §21's "fresh agent reconstructs Phase 0 and starts the exact eligible Phase 1 task safely" — with the one correct caveat that the actual next action right now is Prompt 102, not Prompt 104 (§3).
