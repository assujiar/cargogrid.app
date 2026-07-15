# CargoGrid Git Strategy

**Established by:** `CG-S5-PH0-008` (Prompt 87 — Git Strategy Foundation)
**Status:** Active policy — documentation only, no repository/hosting mutation performed by this task

This document is the detailed elaboration of `AGENTS.md`'s terse "Branch, commit, and checkpoint rules" section — it does not contradict or duplicate those rules, it specifies exactly how to satisfy them. Where the two disagree, `AGENTS.md` wins (instruction precedence, `AGENTS.md` §"Instruction precedence").

**Scope note (Prompt 87 §12/§25):** this task documents policy and adds non-destructive local validation scripts only. It does **not** configure GitHub branch protection, required-status-checks, CODEOWNERS enforcement, or any other hosting-platform setting — those require external repository mutation, which is explicitly forbidden for this task ("no branch/history/external repository mutation occurs without separate authority," §33). §6 below states exactly what is and is not verified as a result.

## 1. Branching model

**Trunk-based with short-lived feature branches** — ratified verbatim at Step 3 (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §3, reproducing Tech Arch §27.2): `main` is always production-ready; a pull request is mandatory for every code change; migrations are reviewed; security-sensitive changes require architecture/security review. This is the same policy as this build agent's own session-level Git Safety Protocol (no direct push to a shared branch without review) — one policy, not two independently-authored ones that could drift.

### 1.1 Branch naming

| Branch kind | Pattern | Example (this repository's actual history) |
|---|---|---|
| Autonomous build agent, ongoing multi-checkpoint work | `agent/<slug>` | `agent/cargogrid-autonomous-build` (this branch) |
| Interactive session branch | `claude/<slug>` (assigned by the calling harness, not chosen by policy) | `claude/sleepy-ride-8pg1em` |
| Human contributor feature work (future, once a human team exists) | `feature/<task-id>-<slug>` | `feature/CG-S5-PH0-009-cicd-baseline` |
| Hotfix (§5 below) | `hotfix/<task-id>-<slug>` | `hotfix/FIN-204-posting-lock-race` |
| Never used for shared work | `main` receives merges only, never direct commits once Phase 1+ CI (`PH0-088`) is live | — |

**One branch, one atomic task** (`AGENTS.md`): a branch's scope is exactly one task ID's worth of change (one `CG-S*-*-*`/`PLT-*`/`FIN-*`/etc. capability ID, or an explicitly-scoped multi-ID checkpoint like this repository's Phase 0 sequential lane). Oversized work is split into multiple atomic tasks/branches, never bundled.

### 1.2 Commit convention

Observed and continued from this repository's actual history (`git log --oneline`, re-verified this checkpoint — not invented):

```
agent: <verb> <description> (<task-id>, Prompt <n>)
```

- `<verb>` is imperative: `complete`, `implement`, `reconcile`, `record`, `update`, `close`, `revert`.
- The commit body cites every task ID advanced, every file category touched, and (for a checkpoint commit) the "advance ledgers" line naming the next `READY` task — this is what makes `git log` alone enough to reconstruct build history without chat context (`AGENTS.md`'s "restartable by an agent with no access to previous chat" mission).
- A commit is not a valid checkpoint until its build log (`docs/build-log/phase-00/PH0-NN.md` during Phase 0, the equivalent phase location later) and ledger updates are included in the **same** commit — `AGENTS.md`: "A task is not a valid checkpoint until documentation and evidence are committed or otherwise durably recorded."

### 1.3 Task/commit/PR linkage (§18 audit requirement)

Every commit message names its task ID(s). Every PR description (once PRs are opened against this repository under human review, or when this agent is asked to open one) must:
- name the task ID(s) it closes,
- link the build log path,
- state the ledger rows updated,
- carry no scope beyond what its linked task's "Allowed files/folders" section authorizes.

This reconciles directly with `docs/runtime/CHANGE_MANIFEST.md` (one `CHG-*` row per checkpoint, already practiced) and `docs/runtime/TASK_LEDGER.md` (one row per task ID, status transitions `BLOCKED → READY → VERIFIED`).

## 2. Review and approval model

| Change class | Required review | Evidence |
|---|---|---|
| Documentation-only (Phase 0 discovery/architecture/ADR/runtime ledgers) | Self-verified against source evidence + build log (this repository's current practice — no second human reviewer exists yet) | Build log's "Tests / commands / results" section |
| Toolchain/config (Prompt 85/86/87/88 class) | Same as above, plus real command execution evidence (install/typecheck/lint/test all run for real, not asserted) | Build log §6/§7 command tables |
| Schema/migration (Phase 1+) | Architecture/Data review named in `docs/architecture/11_*.md` §3's "migrations reviewed" rule; migration reviewed against `05_DATABASE_SCHEMA_WORKSTREAM.md` §7.1's clean-rebuild/upgrade test | Migration-check CI stage (`PH0-088`) once it exists |
| Security-sensitive (RLS/RBAC/auth/secrets) | Architecture/Security review, per `11_*.md` §3 verbatim | Negative-test suite evidence (`06_RLS_RBAC_WORKSTREAM.md` §10) |
| Financial (posting/ledger/reconciliation) | Finance + Architecture review, RPD-022 disclosure preserved | `FINTEST-*` evidence (`10_TESTING_WORKSTREAM.md` §5.3) |

**Once a human team exists**, PR approval authority follows the RACI already established per-domain in the blueprint/architecture documents (each phase's capability group names an "Owner" column, e.g. `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4) — this document does not invent a new authority model, it points at the one already ratified.

## 3. Merge strategy

**Squash-merge to `main`** is the default once GitHub branch protection is actually configured (`PH0-088`, CI/CD Baseline — out of scope here per §12): one PR = one squashed commit on `main`, preserving the atomic-task-per-commit discipline from §1.2 while keeping the feature branch's in-progress history disposable. Until branch protection exists, this repository's actual practice (direct commits to `agent/cargogrid-autonomous-build`, periodically merged to `main` via PR) continues unchanged — this document does not retroactively require a merge strategy the repository cannot yet enforce (§25: "does not invent unavailable protection").

## 4. Protected paths

No atomic task may modify these without the specific override authority named, regardless of which prompt is executing (cross-referenced from `AGENTS.md`, `HANDOFF.md`, and each source document's own "Assets to preserve" section):

| Path | Protection | Override authority |
|---|---|---|
| `docs/blueprint/**` | Read-only authoritative source | Ratified decision-change protocol only (`02_CONFIRMED_DECISION_REGISTER.md` §5); `tes.md` deletion needs owner approval (`ISS-2026-001`) |
| `docs/ai-agent-build-prompt-package/**` | Read-only execution plan | Never edited by a runtime agent — only read |
| `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md`, `03_ASSUMPTION_REGISTER.md`, `04_CONFLICT_REGISTER.md`, `05_REQUIREMENT_COVERAGE_MATRIX.md` | Authoritative registers | Decision-change protocol only |
| `docs/architecture/**` once `VERIFIED` | No silent edit; a later document may amend with a visible supersession blockquote (the pattern `03_DOMAIN_BOUNDARY_MAP.md` already demonstrates) | A dedicated reconciliation task with recorded evidence (this repository's own `ERR-2026-003` recovery is the precedent) |
| Applied database migrations | Never edited once applied | `AGENTS.md`: "Never edit an applied migration; add a new migration." |
| `.env.local`, any real secret value | Never committed | No override — enforced by `.gitignore` (`PH0-085`) and `scripts/env/validate.ts` (`PH0-086`) |
| `docs/runtime/**` | Additive/append-only ledger updates; historical rows are evidence, never deleted | Consolidation only when a documented incident requires it (e.g. `ERR-2026-003`'s HANDOFF rewrite), always with the full history preserved in `CHANGE_MANIFEST.md`/`ERROR_LEDGER.md` |

Every task prompt's own "Forbidden files/folders" section (§12 of each `NN_*.md` prompt) is additionally binding for that specific task — this table is the cross-cutting floor, not a replacement for a task's own narrower scope.

## 5. Release and hotfix flow

**Release:** reproduces `docs/architecture/11_DEVOPS_WORKSTREAM.md` §4.1 verbatim: `Development → Pull Request → CI (Lint/Unit/Test/Build) → Deploy to Testing → QA Regression/Security/RLS → Deploy to Staging → Performance/Smoke → UAT if needed → Release Candidate → Go/No-Go → Production Deploy → Production Smoke Test → Monitoring & Hypercare`. The 15-item deployment checklist (`11_*.md` §4.1, reproducing Blueprint §25.3) is binding pre-Production, all items required (RPD-034/036 direct-GA maturity — no item is optional as a "nice to have").

**Hotfix:** a separate, faster path for critical fixes (Blueprint §13.1, cited at `12_RELEASE_TRAIN.md` line 154) — a `hotfix/<task-id>-<slug>` branch cut directly from `main`, still requires PR + the same CI gates (§3 above is not bypassed, only the sprint-cadence/stabilization-window timing is), same rollback doctrine as §5.1 below. No hotfix skips the migration-check or security-review gate for a change that touches those surfaces.

### 5.1 Rollback

Reproduces `11_*.md` §4.4 verbatim, one doctrine (not independently re-derived by this document): Frontend → re-deploy previous build. API → versioned endpoint/previous deploy. DB schema → forward-fix preferred, down migration only if safe. Config → config rollback via version (`07_CONFIGURATION_ENGINE_WORKSTREAM.md` §10's version-migration discipline). Feature → flag disable. Data → restore only for disaster; business correction for a routine posting error, never a destructive rollback.

## 6. Dirty-worktree, checkpoint, and recovery model

This repository already implements its own recovery mechanism — this section formalizes what it is, not invents a new one:

- **Checkpoint = commit + build log + ledger update, together, same commit** (§1.2). `docs/runtime/HANDOFF.md` is the single, always-current "resume from here" pointer — every checkpoint updates it (task ID, exact next prompt, upstream/downstream state).
- **Dirty-worktree ownership:** never reset/discard/overwrite existing changes without inspecting them first (`AGENTS.md`). If unexpected uncommitted changes are found, they are inspected and either incorporated (if safe and in-scope) or preserved untouched with a note in the current checkpoint's build log — never silently dropped.
- **Conflict:** a merge conflict on `docs/runtime/**` or `docs/architecture/**` is resolved by direct comparison of both sides' evidence, never by "take theirs"/"take ours" — `ERR-2026-001` and `ERR-2026-003` (this repository's own incident history) are the precedent for what happens when this rule is skipped (silent concatenation, duplicated/contradictory content).
- **Interrupted task recovery:** an agent resuming mid-task reads `HANDOFF.md` §2's mandatory reading order first, confirms the worktree matches the recorded checkpoint (`git status --short --branch`, `git rev-parse HEAD` against `HANDOFF.md`'s recorded HEAD), and only then continues — never blindly re-executes a prompt whose partial output might already be on disk.
- **Pre-flight collision check (closes `ISS-2026-002`, §7 below):** before starting any Phase 0+ prompt, check for another open PR or diverging branch claiming the same task-ID range — this was skipped 5 times in this repository's history (`docs/runtime/KNOWN_ISSUES.md` `ISS-2026-002`, `docs/runtime/ERROR_LEDGER.md` `ERR-2026-002`/`ERR-2026-003`) and caused real content corruption. §7 makes this an explicit, followed procedure with a locally-checkable component.

## 7. Pre-flight collision check (`ISS-2026-002` enforcement)

Two checks, one performed by this agent via the GitHub API/MCP at the start of each session (not portable into a committed script — no repository-local script can carry this agent's GitHub credentials), one performed locally and automatable:

1. **GitHub-side (agent procedure, documented here and in `AGENTS.md`'s pre-flight section):** list open pull requests and list branches for `assujiar/cargogrid.app`; if another open PR or a branch with unmerged commits targets the same task-ID range this session is about to work on, **stop and surface it** — do not proceed in parallel (`ERR-2026-002`/`ERR-2026-003`'s exact root cause). **Executed for real this checkpoint:** zero open PRs; every branch other than `agent/cargogrid-autonomous-build` is either `main` or an already-superseded lineage from before `ERR-2026-003`'s reconciliation, with no unmerged commits ahead of `main` (see `docs/build-log/phase-00/PH0-87.md` §3 for the exact command output). No collision.
2. **Local (`scripts/git/check-worktree-collision.ts`, §8 below):** detects multiple local branches or an unexpectedly non-clean worktree that could indicate two sessions sharing one sandbox — genuinely checkable without any external API, real and tested.

## 8. Non-destructive validation scripts (`scripts/git/`)

Callable manually today (`pnpm run git:check`); candidates for wiring into CI once `PH0-088` exists. None of these is installed as an automatic git hook — that would be a repository-behavior change beyond this task's "documentation + approved non-destructive validation configuration" scope (§11/§12), and is better decided alongside the actual CI platform at `PH0-088`.

| Script | Checks | Real/portable today? |
|---|---|---|
| `check-commit-message.ts` | §1.2's `agent: <verb> <description> (<task-id>, Prompt <n>)` pattern | Yes — pure string validation |
| `check-branch-name.ts` | §1.1's naming patterns | Yes |
| `check-protected-paths.ts` | Diffs a given commit range against §4's protected-path table | Yes — uses local `git diff` only |
| `check-worktree-collision.ts` | Flags multiple local branches with unmerged work, or a dirty worktree at session start | Yes |

See `docs/build-log/phase-00/PH0-87.md` §6 for real command output and test results.
