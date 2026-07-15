# ADR-0002 — Package manager and initial toolchain version pins

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-024` (package-manager half only — see scope note)   Owning phase/task: Phase 0 (`CG-S5-PH0-006`, Prompt 85, Development Environment Foundation)

## Scope note

`ADR-CAND-ARCH-024` bundles two decisions: "a single CI/CD platform product" and "a single deterministic package manager with a committed lockfile" (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §10). This ADR resolves **only the package-manager half** plus the initial dependency version pins needed to make `package.json` installable. The CI/CD platform product itself remains open, owned by `CG-S5-PH0-008` (Prompt 88, CI/CD Baseline) — resolving it here would presume a vendor ahead of that task's own evaluation, which the source candidate explicitly warns against.

## Question

Which package manager is authoritative for this repository, and what initial dependency versions should `package.json` pin, given `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` confirmed **no** package-manager authority exists yet and explicitly deferred this decision to this task?

## Options (package manager)

1. **npm.** Ships with Node.js, zero extra install.
   - Trade-off: no built-in workspace-native monorepo primitives (moot here — `04_REPOSITORY_TARGET_STRUCTURE.md` confirms a single root `package.json`, not a monorepo), historically slower installs, weaker dependency-hoisting strictness than pnpm.
2. **Yarn (Berry).** Plug'n'Play or node-modules linker, workspaces.
   - Trade-off: PnP mode has known friction with some Next.js/Supabase tooling that assumes a `node_modules` tree; adds a second config surface (`.yarnrc.yml`) for no benefit given this is not a monorepo.
3. **pnpm (SELECTED).** Content-addressable store, strict non-hoisted `node_modules` by default (fewer phantom-dependency bugs), fast, deterministic `pnpm-lock.yaml`, first-class Vercel and Next.js support, natively available via Corepack.
   - Trade-off: none material for a single-app repository; strictness is a benefit here, not a cost — it surfaces missing `package.json` dependency declarations immediately rather than letting them work by accident via hoisting.

## Decision

**pnpm `10.33.0`**, pinned via the `packageManager` field in `package.json` (Corepack-enforceable) and a committed `pnpm-lock.yaml`. Node.js `>=22.11.0` (LTS "Jod" line) is pinned via `package.json` `engines.node`.

### Initial dependency version pins (evidence-based, not from training-data memory)

Every version below was read directly from the npm registry this checkpoint (`npm view <pkg> version`), not asserted from memory — the ecosystem has moved measurably since this agent's knowledge cutoff (January 2026) and this run's date (2026-07-15), so registry facts are used instead of a stale prior.

| Package | Pinned version | Note |
|---|---:|---|
| `next` | `16.2.10` | Current stable (`16.3.0` is canary/preview only — confirmed via `npm view next versions`) |
| `react`, `react-dom` | `19.2.7` | Current stable, matches `next@16`'s peer requirement |
| `@supabase/supabase-js` | `2.110.5` | Current stable |
| `@supabase/ssr` | `0.12.3` | Server-side Supabase Auth cookie handling for Next.js Server Components, per `AGENTS.md` "Server Components by default for sensitive/data-heavy views" |
| `typescript` | `5.9.3` — **deliberately not `7.0.2`** | See "TypeScript major-version note" below |
| `eslint` | `9.19.0` — **deliberately not `10.7.0`** | `eslint-config-next@16.2.10`'s own `peerDependencies` only requires `eslint >=9.0.0` (verified from the installed package's `package.json`); no evidence justifies jumping past the peer floor to the newest major on day one |
| `eslint-config-next` | `16.2.10` | Matched to the pinned `next` version |
| `@types/node` | `22.10.5` | Matched to the pinned Node 22 major, not the newer `@types/node@26.x` (which targets a Node major this repository does not run) |
| `@types/react`, `@types/react-dom` | `19.2.17` / `19.2.3` | Matched to the pinned `react`/`react-dom` major |

**TypeScript major-version note:** the registry's `latest` dist-tag is `7.0.2` (a recent jump from the `5.x` line via a `6.0` intermediate — `npm view typescript dist-tags` confirms `latest: 7.0.2`, `rc: 7.0.1-rc`, both non-prerelease-tagged as current). This magnitude of jump is consistent with a compiler-implementation change, not an incremental release, and this agent has no verified operational experience with it. Given this repository is the foundation for a multi-year, multi-hundred-prompt build, the cost of an early, unverified bleeding-edge pin (subtle incompatibility discovered deep into Phase 1+) outweighs the benefit of being on the newest major on day one. **Decision: pin `typescript@5.9.3`** (the newest release on the well-established `5.x` line) now; re-evaluate `7.x` as a dedicated, isolated upgrade ADR once the ecosystem (in particular `eslint-config-next` and any future test tooling from `PH0-091`) has demonstrable compatibility evidence. This is a disclosed, reasoned deferral, not an unexamined default — consistent with `AGENTS.md`'s "do not upgrade merely because a newer version exists," applied here in the conservative direction on a version this agent cannot verify.

## Evidence

- `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` §2: package-manager authority `MISSING`, explicitly deferred to this prompt.
- `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` line 174: migration wave 1 (Phase 0) scope is exactly `package.json`, `tsconfig.json`, `.gitignore`, `supabase/` scaffold — confirms no monorepo/workspace tooling is needed.
- `docs/architecture/11_DEVOPS_WORKSTREAM.md` `ADR-CAND-ARCH-024`: "a single deterministic package manager with a committed lockfile," CI/CD platform product explicitly deferred separately.
- `AGENTS.md` "Stack baseline": Next.js App Router, React, TypeScript strict, Supabase Auth/PostgreSQL/RLS/Storage, Vercel.
- Real, executed evidence this checkpoint (not asserted): `pnpm install` succeeded (349 packages resolved); `pnpm exec tsc --noEmit` passed against a real TypeScript file (`scripts/preflight-env-check.ts`); `pnpm exec eslint .` passed with `eslint-config-next`'s flat config. Commands and exact output are recorded in `docs/build-log/phase-00/PH0-85.md` §6.

## Consequences

- **DB:** none (no schema change).
- **API:** none (no endpoints exist).
- **UI:** none (no `app/` directory — Phase 1 scope).
- **Security:** `@supabase/ssr` keeps the service-role key server-only by construction (never imported from a Client Component); `.env.example` and `scripts/preflight-env-check.ts` (this checkpoint, see `docs/build-log/phase-00/PH0-85.md`) enforce this is never accidentally committed or pointed at production.
- **Performance:** pnpm's content-addressable store keeps CI install times low once `PH0-088` wires caching; not measured as an SLA (per Prompt 85 §17, evidence not commitment).
- **Migration/rollback:** trivial — `git revert` removes `package.json`/`pnpm-lock.yaml`/`tsconfig.json`; nothing downstream depends on them yet.
- **Downstream impact:** every future `pnpm install` in CI (`PH0-088`) and every Phase 1+ capability prompt that adds a dependency must go through this lockfile — no parallel `package-lock.json`/`yarn.lock` may be introduced (would violate "single deterministic package manager").

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-85.md`; `README.md` "Local development"; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-024`'s package-manager component `ACCEPTED`, CI/CD-platform component remains `BLOCKED` pending `PH0-088`). Does not alter any CPD/RPD or any `docs/architecture/**` decision.
