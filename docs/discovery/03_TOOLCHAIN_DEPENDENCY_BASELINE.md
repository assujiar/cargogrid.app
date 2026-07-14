# 03 — Toolchain, Framework, Version, and Dependency Baseline

**Prompt:** `CG-S2-DISC-003` (`CG-AABPP-DISC-023` v0.3.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/02-discovery/23_TOOLCHAIN_DEPENDENCY_AUDIT_PROMPT.md`
**Status:** `VERIFIED`

## 1. Checkpoint and audit limitations

Checkpoint: branch `claude/eloquent-mayer-s40hn4`, HEAD `d587445`, clean worktree (unchanged from Prompts 21–22). No package manager, manifest, or lockfile exists in the tracked tree (`docs/discovery/01_REPOSITORY_INVENTORY.md` §5). Per the prompt's forbidden-actions list, no install/update/audit-fix/codemod/`npx` auto-install was attempted. Only `node --version`/manager version probes of already-installed sandbox tooling were run, strictly to distinguish "no manifest" from "no runtime available at all"; neither mutates the repository.

## 2. Package manager / workspace authority

| Signal | Finding |
|---|---|
| `packageManager` field | N/A — no `package.json` |
| Lockfile | none (`npm`/`pnpm`/`yarn`/`bun`) |
| Workspace file (`pnpm-workspace.yaml`, `turbo.json`, `nx.json`) | none |
| CI command references | none (no `.github/workflows`) |
| Devcontainer/Docker | none |
| Contributor docs naming a manager | none (`README.md` is a 1-line stub) |

**Classification: `MISSING`.** No package-manager authority exists at this checkpoint. This is expected for a greenfield repository and is not a conflict (no competing manifests exist either). Establishing the authoritative manager (`AGENTS.md` names Next.js/TypeScript/Supabase as the ratified target stack) is owned by Phase 0 (`85_DEVELOPMENT_ENVIRONMENT_FOUNDATION_PROMPT.md`), not this discovery step.

## 3. Runtime/framework declared/resolved/executable version matrix

| Tool | Declared (manifest) | Resolved (lockfile) | Executable (sandbox) | Evidence |
|---|---|---|---|---|
| Node.js | none | none | present in sandbox environment (not repository-pinned) | `node --version` reports a sandbox-provided runtime; not a repository fact |
| Next.js | none | none | not installed | no manifest |
| React | none | none | not installed | no manifest |
| TypeScript | none | none | not installed | no manifest |
| Supabase CLI/clients | none | none | not installed | no manifest |
| PostgreSQL tooling | none | none | not installed | no manifest |
| Test framework | none | none | not installed | no manifest |
| Lint/format | none | none | not installed | no manifest |
| Build tooling | none | none | not installed | no manifest |

No version is recorded as "supported" or "current" from memory; every row above is a repository fact (absence), consistent with Prompt 23's rule against asserting support status without repository/ADR evidence. The sandbox's ambient Node.js availability is an environment fact, not a repository-declared version, and must not be treated as a pin.

## 4. Script inventory with side-effect classification

No `package.json`, so no `scripts` block exists. No dev/build/lint/typecheck/unit/integration/E2E/migration/reset/generate/seed/audit/performance/accessibility/release script is inventoried. Table intentionally empty — this **is** the finding, not an omission.

## 5. Dependency inventory by workspace and critical ownership

No production/dev/optional/peer dependency exists in any workspace, because no workspace or manifest exists. No duplicate/conflicting major versions, peer conflicts, circular workspace dependencies, unpinned Git/file dependencies, postinstall scripts, patched/vendored packages, or abandoned packages can exist yet.

## 6. Version/peer/duplicate/cycle/unpinned/postinstall findings

None applicable — see §5.

## 7. Vulnerability/audit evidence and limitations

**Classification: `NOT_RUN`.** No lockfile-backed audit tool (`npm audit`, `pnpm audit`, `yarn audit`, Dependabot/Snyk config) exists to run safely and meaningfully. Running a generic audit command with no manifest would either fail or silently operate on an unrelated/global environment, which is unsafe and out of scope. No vulnerability data can be produced honestly at this checkpoint.

## 8. Fixed-stack alignment matrix

| Ratified target (per `AGENTS.md` "Stack baseline") | Implementation evidence | Classification |
|---|---|---|
| Next.js App Router, React, TypeScript strict | none | `NOT_STARTED` |
| Server Components default, Client Components at interaction boundaries | none | `NOT_STARTED` |
| Supabase Auth/PostgreSQL/RLS/Storage, selective Realtime/Edge | none | `NOT_STARTED` |
| Vercel + Local/Dev/Testing/Staging/UAT/Production environments | none | `NOT_STARTED` |
| Shared schema with RLS by default; PostGIS from Platform Core | none | `NOT_STARTED` |
| PostgreSQL durable queue first | none | `NOT_STARTED` |
| REST `/v1` + GraphQL developed together | none | `NOT_STARTED` |

All rows are gaps by definition of greenfield status, not defects. `AGENTS.md` already discloses this explicitly ("as of the current checkpoint no application code, manifest, or lockfile exists yet").

## 9. Safe baseline commands for later prompts

No repository-provided command is safe to run yet because none exists. Prompt 27 (Test/Quality Baseline) must record `NOT_RUN` for all gates for the same reason, not attempt generic framework-agnostic commands.

## 10. Upgrade/remediation candidates

None — there is nothing to upgrade. The first "upgrade" event will be the initial scaffolding task in Phase 0, which is a scaffolding/foundation task, not a remediation of this discovery.

## 11. Evidence index and output hash

- `docs/discovery/01_REPOSITORY_INVENTORY.md` §5 (manifest/lockfile/config absence, EV-S2-REPO-014).
- Output hash: `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.sha256`.

## Acceptance / Definition of Done

- Package-manager authority explicitly `MISSING` (not silently assumed). ✔
- Every version row distinguishes declared/resolved/executable, all `none`/sandbox-ambient. ✔
- Every script has a classification (empty table = the finding). ✔
- No manifest/lockfile/dependency/cache/config/generated file was created or changed. ✔

## Completion report

- **Package manager:** `MISSING` (no conflict, no candidate).
- **Workspaces:** none.
- **Key versions:** none repository-declared; sandbox Node.js is ambient only, not a pin.
- **Safe commands:** none yet.
- **Dependency/vulnerability findings:** none applicable.
- **Limitations:** no manifest to audit.
- **Files written:** `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` (+ sha256).
- **Next eligible prompt:** `CG-S2-DISC-004` — Database and Migration Audit.
