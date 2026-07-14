# Prompt 21 — Repository Discovery

**Prompt ID:** `CG-S2-DISC-001`  
**Package document:** `CG-AABPP-DISC-021`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Workstream:** Repository topology and checkpoint  
**Runtime output:** `docs/discovery/01_REPOSITORY_INVENTORY.md`  
**Required status on success:** `VERIFIED`

## Objective and business value

Establish the exact target repository, checkpoint, worktree condition, directory topology, application/workspace boundaries, documentation locations, environment indicators, and safe command surface. This prevents later agents from editing the wrong root, assuming a clean tree, missing a second application, or overwriting existing work.

## Source requirements

- Master Prompt Step 2; §§8, 10–11, 17–18, 21.
- GOV-010 mandatory startup, scope, checkpoint, and response rules.
- GOV-011 repository, worktree, branch, file, and stop rules.
- Technical Architecture §§4–8, 27–29, 37–38.
- Delivery Plan §§3, 8, 12, 14–16.

## Authorization

Read repository and Git metadata. Write only the runtime output, relevant build log, and persistent status/ledger entries. Do not edit application/test/config/migration/lock/generated files; do not install, build, migrate, deploy, commit, reset, stash, clean, checkout, or discard changes.

## Mandatory pre-flight

1. Read repository and nested `AGENTS.md`.
2. Read persistent context/status/task/decision/assumption/error/issue files if present.
3. Read Step 0 controls and Step 1 governance provided with this package.
4. Record current directory and permission boundary.
5. Determine whether the path is inside a Git worktree without changing it.
6. If a repository is supplied through a local path, use that exact path; do not search unrelated directories.
7. If no target repository is available, create a `BLOCKED` output explaining the missing input and stop.

## Detailed discovery tasks

### A. Repository identity

- Resolve filesystem root and Git top-level separately.
- Record repository name, branch, HEAD, detached state, shallow state, submodules/worktrees, remotes with credentials redacted, and recent relevant history.
- Record clean/dirty state by tracked, staged, modified, deleted, renamed, conflicted, and untracked files.
- Do not attribute dirty files to the agent. Mark ownership `UNKNOWN` unless evidence exists.

### B. Topology

- Inventory top-level files/directories and important nested roots without dumping large generated/vendor trees.
- Detect monorepo/workspace configuration, multiple apps/packages, Supabase folders, infrastructure, documentation, scripts, tests, fixtures, public assets, generated artifacts, and build outputs.
- Identify symlinks and paths crossing repository boundaries.
- Identify nested `AGENTS.md`, README, contribution, coding-standard, environment-example, and runbook files.

### C. Manifest and command surfaces

- Locate package manifests, lockfiles, workspace files, runtime/version files, task runners, container/devcontainer files, CI definitions, Vercel/Supabase configuration, and environment templates.
- Inventory script names only; prompt 23 will validate toolchain/dependencies.
- Flag multiple/conflicting lockfiles or package managers without changing them.

### D. Repository hygiene and sensitivity

- Identify tracked environment files, likely secret-bearing filenames, database dumps, large binaries, generated/build outputs, and real-data indicators by name/metadata only.
- Do not reveal content of suspected secrets or real-data files.
- Record ignore rules and whether sensitive/generated paths appear tracked.

### E. Documentation baseline

- Locate source requirements, ADRs, schema/API/data-flow/module maps, build logs, release notes, incident/runbooks, and existing discovery reports.
- Classify each as `PRESENT`, `MISSING`, `STALE_SUSPECTED`, or `UNVERIFIED` with evidence.

## Suggested safe commands

Adapt to the environment and use only available tools:

```text
pwd
git rev-parse --show-toplevel
git status --short --branch
git rev-parse HEAD
git log -n 10 --oneline --decorate
git remote -v  # redact credentials before recording
git submodule status
rg --files
find <repo> -maxdepth 2 -type d
```

Exclude `.git`, dependency/vendor directories, build output, caches, and large generated trees from broad inventories. Do not run commands with destructive flags.

## Required output structure

`01_REPOSITORY_INVENTORY.md` must contain:

1. Metadata, timestamp, agent, repository path, branch, HEAD, trust classification.
2. Command/evidence table with exit codes.
3. Worktree ownership table.
4. Top-level and workspace/app/package tree.
5. Configuration/manifest/lock/version/CI/environment file inventory.
6. Documentation and persistent-context inventory.
7. Sensitive/generated/large-file indicators with redaction.
8. Missing or ambiguous repository inputs.
9. Initial risks/blockers and ledger IDs.
10. Exact checkpoint to be reused by prompts 22–34.
11. SHA-256 or platform-equivalent hash of this output if available.

## Validation rules

- Every count links to a scoped command or file list.
- Every path is repository-relative unless the repository root itself is being reported.
- Remote URLs and environment evidence contain no credentials.
- Dirty files are preserved and ownership is explicit.
- No output claims framework, dependency, database, route, or security completeness; later prompts own those claims.
- If HEAD or worktree changes during discovery, mark the output `STALE`, record both states, and stop until reconciled.

## Acceptance criteria and Definition of Done

- Repository root and exact checkpoint are verified or the task is correctly `BLOCKED`.
- All workspace/application/package boundaries are inventoried.
- Relevant control, manifest, environment, CI, docs, scripts, and sensitive-file indicators are mapped.
- No non-documentation repository file or external state changed.
- Context, Build Status, Task Ledger, build log, Error Ledger, and Known Issues are updated as applicable.

## Failure and recovery

On unexpected mutation, secret exposure, repository mismatch, or trust loss: stop; preserve evidence; do not revert user changes; record an Error Ledger entry, last known good checkpoint, affected paths, recovery options, and a resume prompt.

## Completion report

Report status, repository/checkpoint, worktree state, topology counts, important manifests/configs/docs, commands/results, redactions, files written, blockers/risks, trust state, and next eligible prompt.

## Next eligible prompt

`CG-S2-DISC-002` — Existing Implementation Audit, only when the repository checkpoint is trusted and unchanged.
