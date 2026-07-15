# KNOWN_ISSUES.md

**Instance of:** `CG-AABPP-GOV-018`
**Instance version:** `0.2.0`
**Updated:** 2026-07-14T10:29:19+07:00
**Policy:** Track unresolved, accepted, deferred, or externally constrained issues. Exact runtime failures belong in `ERROR_LEDGER.md`.

## 1. Status and severity

Statuses: `OPEN`, `TRIAGED`, `PLANNED`, `IN_PROGRESS`, `MONITORING`, `ACCEPTED_RISK`, `RESOLVED`, `VERIFIED`, `SUPERSEDED`.

## 2. Standing accepted risks

| Decision | Accepted condition | Required permanent handling |
|---|---|---|
| RPD-022 | Supreme Admin can mutate/delete audit, ledger, payment, final records | No tamper-proof/immutability claim; disclose in security/finance/retention/support material |
| RPD-034/036 | Direct GA without external pilot | Full internal UAT/penetration/performance/DR/finance/all-module + zero-critical-defect gates |
| RPD-031/037 | Contract-silent RPO/RTO is best effort | Never imply a recovery guarantee; record actual rehearsal evidence |
| RPD-038 | Custom non-AI integrations, no generic abstraction | Shared codebase, explicit ownership, credentials, contracts, tests, monitoring, runbook |

## 3. Issue index

| Issue ID | Title | Severity | Status | Owner | Workaround | Release blocker |
|---|---|---|---|---|---|---|
| `ISS-2026-002` | No single-writer discipline across concurrent agent branches | **High** (escalated) | `OPEN` — **BLOCKING** | Runtime agent / repo owner | Run each runtime step on one authoritative branch only; **enforcement still not adopted after 3rd occurrence** | **Yes — this occurrence blocks Phase 0 continuation until resolved** |
| `ISS-2026-003` | No repository-root `.gitignore` before application scaffolding | Medium (future) | `PLANNED` | DevEx | Add ignore policy before any code/secrets | No (blocks safe scaffolding at Phase 0) |
| `ISS-2026-001` | Primary source documents not tracked in repository | Medium | `RESOLVED` | Product / Build agent | — | No |

## 4. Issue records

### ISS-2026-002 — Parallel-session collision (no single-writer discipline)

Two sessions ran Prompt 21 concurrently on separate branches (`…-oanf5a`, `…-b492y3`); both merged to `main` and the merge corrupted the discovery baseline and duplicated the context set (see `ERROR_LEDGER.md` ERR-2026-001). Root cause: no lock/convention preventing concurrent execution of the same runtime step. **Handling:** designate one authoritative build branch per runtime step; do not launch parallel agent sessions on the same step; a future prompt must verify checkpoint lineage before writing. Status `OPEN` until a written single-writer convention is adopted (candidate: note in `AGENTS.md`).

**Recurrence (2026-07-14, third session):** a third branch, `claude/eloquent-mayer-s40hn4`, was cut from `main` at `d587445` *before* this reconciliation (`CG-S2-DISC-001-R1`) had merged. It independently discovered the same underlying corruption and — not knowing about `-R1` — resolved it the opposite way (root-level context kept canonical, `docs/runtime/*` marked superseded) while also completing Step 2 discovery Prompts 22–34. On merge with `main`, that branch's canonical-location choice was reverted in favor of this ratified decision (`docs/runtime/` canonical); its Step 2 discovery deliverables (Prompts 22–34, `docs/discovery/02_*.md`–`14_*.md`) were kept and layered on top of the reconciled baseline (see `TASK_LEDGER.md` `CG-S2-DISC-002..014` and `CHANGE_MANIFEST.md` `CHG-2026-003`). This is the second occurrence of this exact issue and reinforces that it remains `OPEN` until a single-writer convention is actually enforced, not just documented.

**Recurrence (2026-07-15, fourth occurrence — BLOCKING, unresolved as of this checkpoint):** a fourth branch, `claude/sleepy-ride-4vxsk6`, diverged from `origin/main`@`27389a4` (PR #8, Prompt 45) and independently executed Prompts 46–51, Phase 0 kickoff (80), and Prompts 81–82 — nine commits, three full architecture documents, a full Phase 0 kickoff, and two Phase 0 capability prompts — in parallel with this branch (`agent/cargogrid-autonomous-build`) doing the equivalent Prompts 49–51/80/81. That branch opened GitHub **PR #10 (open, unmerged)** 15 seconds after this branch's PR #9 merged into `main`, confirming near-simultaneous parallel execution. The two lineages' outputs for the same task IDs materially differ (e.g. 607 vs. 401 traced requirement items for the "same" Prompt 49/CG-S3-ARCH-014 output). Full detail: `ERROR_LEDGER.md` `ERR-2026-002`. **Unlike the first three occurrences, this one is not yet reconciled** — this session halted further Phase 0 execution on discovering it rather than compounding the divergence, and recorded `BLOCKED_WORKTREE` in `HANDOFF.md`, pending an explicit operator decision among three reconciliation options (adopt this branch, adopt PR #10, or manually reconcile field-by-field). This is the clearest evidence yet that `ISS-2026-002` needs an *enforced* single-writer lock (e.g. a pre-flight check in each routine invocation that fails fast if any other open PR/branch already claims the current task-ID range), not a documented convention that keeps being silently violated.

### ISS-2026-003 — No root `.gitignore`

No `.gitignore` is tracked. Harmless while the repo is documentation-only, but before Phase 0 introduces application code, secrets, and build artifacts an ignore policy must exist so generated/secret paths are never committed. **Handling:** add `.gitignore` during Phase 0 environment setup (Prompt 85/87). Status `PLANNED`.

### ISS-2026-001 — Primary source documents not tracked (RESOLVED)

Reported by session A at checkpoint `53e3d4a`, where the six primary sources were absent. They were subsequently uploaded (commit `db1742c`) and are now tracked under `docs/blueprint/` (Product Concept Brief + Charter/BPR/UX/Technical/Delivery). Verified at reconciled checkpoint `d587445`: `git ls-files docs/blueprint/` returns all six sources (plus `tes.md` placeholder). **Status `RESOLVED`** — no further action; source-fidelity verification can now trace to in-repo sources. The `tes.md` placeholder has since been formally classified `CONFIRMED_PLACEHOLDER` (empty, 1-byte file) in `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` finding `PH-001`; it awaits owner-approved deletion (out of scope for read-only discovery since it sits inside the authoritative `docs/blueprint/` folder).

## 5. Maintenance rules

1. Do not delete resolved issues; mark `RESOLVED`/`SUPERSEDED`.
2. Link reproducible failures to Error Ledger entries.
3. Re-triage severity when scope/exploitability/data impact/contracts change.
4. Reconcile release blockers with build status and go/no-go reports.
5. An ownerless or targetless non-low issue cannot be considered safely triaged.
