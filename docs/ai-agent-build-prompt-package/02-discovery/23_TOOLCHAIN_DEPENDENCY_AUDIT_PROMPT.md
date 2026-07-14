# Prompt 23 — Toolchain, Framework, Version, and Dependency Audit

**Prompt ID:** `CG-S2-DISC-003`  
**Package document:** `CG-AABPP-DISC-023`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Toolchain and software supply chain  
**Runtime output:** `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md`

## Objective and business value

Identify the authoritative package manager, workspace model, runtime/tool versions, fixed-stack implementation, scripts, dependency graph, lockfile integrity, upgrade constraints, vulnerabilities, unsupported packages, and version conflicts without installing or changing anything. This establishes reproducible commands and prevents accidental lockfile or framework drift.

## Source requirements

- Master Prompt fixed stack, Step 2, §§10, 16, 19, 21.
- CPD-020/021/023; RPD-012/015/021/033/038/040.
- GOV-010 stack, quality, migration, security, and discovery rules.
- Technical Architecture §§7–8, 25–29, 32, 35, 37–39.
- Delivery Plan §§14–18, 20–21, 35.

## Preconditions and authorization

Prompts 21–22 are complete at the same checkpoint. Read manifests, lockfiles, runtime files, configs, CI, imports, and existing dependency reports. Run version/list/audit commands only when they do not install, mutate lockfiles, run lifecycle scripts, or expose credentials. Write discovery docs only.

Forbidden: install/update/remove/dedupe, `npx` or equivalent auto-install, lockfile generation, framework codemod, audit fix, cache cleanup, config edits, or CI changes.

## Mandatory pre-flight

- Read governance/persistent context and prior outputs.
- Reconfirm repository checkpoint and dirty-state ownership.
- Identify all manifests/lockfiles before selecting a command.
- Determine whether package-manager activation would download software; do not activate/download during discovery without separate approval.
- Inspect scripts before running them for lifecycle or write side effects.

## Detailed tasks

### A. Package manager authority

- Detect `packageManager` metadata, lockfiles, workspace files, CI commands, Docker/devcontainer setup, and contributor docs.
- Classify package manager as `VERIFIED`, `CONFLICTING`, `MISSING`, or `INFERRED`.
- Identify multiple lockfiles, stale lockfiles, nested independent packages, frozen-lockfile policy, and reproducible install command without executing install.

### B. Runtime and framework versions

Record declared and resolved versions where safely available for Node/runtime, Next.js, React, TypeScript, Supabase clients/CLI, PostgreSQL tooling, test frameworks, lint/format/type tools, build tooling, PWA, GraphQL, REST/OpenAPI, queue/job libraries, PostGIS tooling, monitoring, accessibility, and security scanners.

Distinguish manifest range from lockfile resolution and actual executable version. Do not call a version supported/current based only on memory; record repository facts and create an ADR/research follow-up where support status needs current verification.

### C. Scripts and side effects

- Inventory root and workspace scripts: dev, build, lint, typecheck, unit, integration, E2E, migration, reset, generate, seed, audit, performance, accessibility, release.
- Inspect invoked scripts/configs enough to classify `READ_ONLY`, `LOCAL_WRITE`, `DATABASE_WRITE`, `NETWORK`, `DEPLOY`, `UNKNOWN`.
- Define the safe baseline command set for prompt 27.

### D. Dependency graph and ownership

- Inventory production/dev/optional/peer dependencies per workspace.
- Identify duplicated/conflicting major versions, peer conflicts, circular workspace dependencies, direct imports that bypass declared boundaries, unpinned Git/file dependencies, postinstall scripts, patched/vendor packages, and abandoned-looking packages.
- Map critical dependencies to auth, tenant/security, database, finance, GraphQL/REST, file upload, AI, integrations, jobs, and observability.

### E. Supply-chain and vulnerability baseline

- Use an existing repository audit command only if it is read-only, lockfile-backed, and safe. Record tool/version/database timestamp and network limitation.
- If no safe audit tool exists, classify `NOT_RUN` and inventory existing reports/configs without installing one.
- Record severity, direct/transitive path, affected runtime/build scope, exploitability uncertainty, available remediation class, and whether changing it requires a separate upgrade task/ADR.
- Never run an automatic fix.

### F. Fixed-stack alignment

Assess evidence for Next.js App Router, TypeScript strictness, React, Supabase Auth/PostgreSQL/RLS/Storage, selective Realtime/Edge, Vercel/Supabase environments, PostGIS, PostgreSQL queue, REST+GraphQL, and monitoring/recovery tooling. Classify gaps without implementing them.

## Suggested safe commands

Use manifest/lockfile inspection first. Depending on the verified package manager:

```text
node --version
npm --version | pnpm --version | yarn --version
npm pkg get packageManager workspaces scripts
npm ls --depth=0  # only if it does not install or run scripts
pnpm list --depth 0
yarn workspaces list
```

Do not use commands that auto-install missing binaries. Capture stderr and exit code; a failed version command is evidence, not permission to install.

## Required output structure

1. Checkpoint and audit limitations.
2. Authoritative package manager/workspace decision evidence.
3. Runtime/framework declared/resolved/executable version matrix.
4. Script inventory with side-effect classification.
5. Dependency inventory by workspace and critical ownership.
6. Version/peer/duplicate/cycle/unpinned/postinstall findings.
7. Vulnerability/audit evidence and limitations.
8. Fixed-stack alignment matrix.
9. Safe baseline commands for later prompts.
10. Upgrade/remediation candidates as separate tasks; no upgrades performed.
11. Evidence index and output hash.

## Acceptance criteria and Definition of Done

- Package-manager authority is verified or explicitly blocked/conflicting.
- Framework/tool versions distinguish declaration, resolution, and executable evidence.
- Every script has a side-effect classification before later execution.
- Critical dependency and supply-chain risks are recorded without fixes.
- No manifest, lockfile, dependency tree, cache, generated file, config, or external state changed.
- Context/status/task/build/error/issue documentation is reconciled.

## Failure, recovery, completion, and next prompt

If a command mutates files or runs an unsafe lifecycle/network action, stop, record before/after worktree evidence, do not discard user changes, and create an Error Ledger recovery entry.

Report package manager, workspaces, key versions, safe commands, dependency/vulnerability findings, limitations, files written, and next prompt.

Next: `CG-S2-DISC-004` — Database and Migration Audit.
