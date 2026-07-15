# ERROR_LEDGER.md

**Instance of:** `CG-AABPP-GOV-017`
**Instance version:** `0.2.0`
**Updated:** 2026-07-14T10:29:19+07:00
**Policy:** Record reproducible failures, failed gates, unsafe/unknown states, and recovery evidence. No secrets, tokens, or unredacted tenant data.

## 1. Error states and severity

Statuses: `OPEN`, `INVESTIGATING`, `ROOT_CAUSE_CONFIRMED`, `RECOVERY_IN_PROGRESS`, `RECOVERED`, `VERIFIED`, `ACCEPTED`, `SUPERSEDED`.

| Severity | Definition | Default effect |
|---|---|---|
| Sev-1/Critical | Tenant isolation, credential exposure, corrupt/imbalanced finance, destructive data loss, production outage, untrusted repo/DB | Stop affected work/release |
| Sev-2/High | Major flow unavailable, serious security/access defect, failed migration/restore, cross-module integrity failure | Block phase/release |
| Sev-3/Medium | Bounded defect or failed non-critical gate with safe workaround | Separate recovery task |
| Sev-4/Low | Minor tooling/docs/local issue without data/security impact | Track and schedule |

## 2. Error index

| Error ID | Task ID | Severity | Environment | Summary | Status | Root cause | Last good checkpoint | Owner | Record link |
|---|---|---|---|---|---|---|---|---|---|
| `ERR-2026-001` | `CG-S2-DISC-001-R1` | Sev-3/Medium | Repository / git `main` | Parallel-session merge corrupted the discovery baseline and duplicated persistent context | `RECOVERED` (verification VERIFIED) | Two concurrent agent branches ran Prompt 21 with no single-writer lock; merge concatenated both reports and both context sets | `d587445` | Runtime agent | this file §3 |
| `ERR-2026-002` | `CG-S3-ARCH-013..016`, `CG-S5-PH0-001..003` | Sev-2/High | Repository / GitHub PR #10 (open, unmerged) | A fully independent parallel session (branch `claude/sleepy-ride-4vxsk6`) redid Prompts 46–51, Phase 0 kickoff (80), and Prompts 81–82 with materially different content (different traceability item counts, different build-log directory convention) after diverging from the shared lineage at PR #8; its output sits in **open, unmerged** PR #10, not yet reconciled with this branch's (`agent/cargogrid-autonomous-build`) independent redo of the same range | `OPEN` — **runtime execution halted pending operator decision** | No enforced single-writer lock (`ISS-2026-002`) across scheduled/parallel routine invocations; two agent instances both continued the same autonomous build task from a shared ancestor without coordinating | `1802400` (this branch, current HEAD) | Runtime agent / repo owner | this file §3 |

## 3. Error record

### ERR-2026-001 — Parallel-session discovery merge corruption

| Field | Value |
|---|---|
| Detected by/date | Runtime agent (session b492y3) / 2026-07-14 |
| Severity/status | Sev-3/Medium / `RECOVERED` |
| Environment | Repository, branch `main` @ `d587445` |
| Related tasks/changes | `CG-S2-DISC-001` (both runs), `CG-S2-DISC-001-R1`, `CHG-2026-002` |

#### What happened

Two Claude sessions independently executed Runtime Step 2 / Prompt 21:
- Session A: branch `…-oanf5a`, PR #2 (`0097236`), checkpoint `53e3d4a` (before blueprint upload), context under `docs/runtime/` + root `AGENTS.md`.
- Session B (this): branch `…-b492y3`, PR #3 (`de2790d`), checkpoint `db1742c`, context at repo root.

Both merged into `main`. Merge commit `9278b9e` (into PR #3) resolved the `docs/discovery/01_REPOSITORY_INVENTORY.md` conflict by **concatenating** both reports (350 lines, two `## 1. Metadata` sections with contradictory checkpoints `db1742c`/438 vs `53e3d4a`/431), and left **two** competing persistent-context sets (root + `docs/runtime/`), violating GOV single-source-of-truth.

#### Evidence

- `git log --graph origin/main` shows PR #2 and PR #3 both merged; `9278b9e` merges main into b492y3.
- `grep -n '## 1. Metadata' docs/discovery/01_REPOSITORY_INVENTORY.md` → matches at lines 10 and 82 (two reports).
- `git ls-files` showed both root `CARGOGRID_*.md` and `docs/runtime/CARGOGRID_*.md`.
- No git conflict markers remained (silent concatenation), so no CI/tooling would have caught it.

#### Impact

- Discovery baseline unusable as a single artifact; downstream Prompt 22 blocked until reconciled.
- No secret exposure, no data mutation, no production/database impact (documentation-only repo).

#### Recovery (CG-S2-DISC-001-R1)

1. Restarted branch `…-b492y3` from `origin/main` (prior PR merged; branch fully merged → clean reset).
2. Chose `docs/runtime/` as the single canonical context location (CHG-2026-002); deleted the 6 duplicate root context files.
3. Rewrote `01_REPOSITORY_INVENTORY.md` as one coherent report anchored to `d587445` (blueprint-aware, 438 product/source baseline), regenerated `.sha256`.
4. Reconciled all `docs/runtime/*`; resolved session-A's ISS-2026-001 (sources now tracked); opened ISS-2026-002/003.
5. Logged this error and committed/pushed as a fresh change (new PR).

#### Verification

- `grep '## 1. Metadata'` on the rewritten inventory → single match.
- `git ls-files | grep -E '^(CARGOGRID_|TASK_LEDGER|ERROR_LEDGER|KNOWN_ISSUES|HANDOFF)'` → none at root (only `docs/runtime/`).
- Last trusted checkpoint `d587445` preserved; no merged history rewritten.

Status: `RECOVERED` — verification passed. Resume at `CG-S2-DISC-002`.

#### Recurrence (2026-07-14, merge with `claude/eloquent-mayer-s40hn4`)

A third branch, `claude/eloquent-mayer-s40hn4`, was cut from `main` at `d587445` before this reconciliation (`-R1`) had merged. It independently discovered the identical corruption (same file, same symptom) and resolved it the opposite way — root-level context kept canonical, `docs/runtime/*` marked superseded — while also completing Step 2 discovery Prompts 22–34 on top of that resolution. Merging that branch into `main` (now at `90129fc`, including `-R1`) reproduced the modify/delete conflict pattern this incident already describes. Resolution: kept `-R1`'s canonical-location decision (`docs/runtime/`), discarded the other branch's root-canonical choice, and re-homed its Step 2 discovery deliverables under this ledger set. No data was lost; both branches' substantive work (this reconciliation + the other branch's Prompts 22–34) is preserved. See `TASK_LEDGER.md` `CG-S2-DISC-002..014` and `CHANGE_MANIFEST.md` `CHG-2026-003`.

This is not logged as a new Error ID — it is the same root cause (`ISS-2026-002`) manifesting a second time, which is itself evidence that `ISS-2026-002` needs an *enforced* fix, not just a documented one.

### ERR-2026-002 — Full-lineage parallel-session divergence (Step 3 tail + Phase 0 kickoff/081/082)

| Field | Value |
|---|---|
| Detected by/date | Runtime agent, this session / 2026-07-15 |
| Severity/status | Sev-2/High / `OPEN` |
| Environment | Repository; branches `agent/cargogrid-autonomous-build` (this branch) and `claude/sleepy-ride-4vxsk6`; GitHub PR #10 (open, unmerged, targets `main`) |
| Related tasks/changes | `CG-S3-ARCH-013..016`, `CG-S5-PH0-001..003`, `CHG-2026-016..020` |

#### What happened

Two independent agent sessions both continued the CargoGrid autonomous build routine from the same shared ancestor (`origin/main`@`27389a4`, the PR #8 merge point, Prompt 45) and diverged:

- **This branch** (`agent/cargogrid-autonomous-build`): rebased forward onto `origin/main`@`824b548` (PR #9, Prompt 48) at session start, then executed Prompts 49, 50, 51 (`docs/architecture/14_*.md`–`16_*.md`), Phase 0 kickoff (Prompt 80, `docs/build-log/phase-00/00_*.md`), and Prompt 81 (`docs/build-log/phase-00/PH0-81.md`) — commits `69dbbc1`…`1802400`, current HEAD.
- **`claude/sleepy-ride-4vxsk6`** (a separate, independently-running session): continued directly from `27389a4` without the PR #9 rebase, independently executing Prompts 46, 47, 48, 49, 50, 51, Phase 0 kickoff (80), Prompt 81, **and Prompt 82** — commits `18c6a35`…`6068e62`. Opened GitHub PR #10 ("agent: adopt requirement traceability baseline (CG-S5-PH0-003, Prompt 82)") targeting `main`, created 2026-07-14T23:44:54Z — **15 seconds after** PR #9 merged into `main`, confirming near-simultaneous parallel execution rather than sequential handoff.

The two lineages' outputs for the *same* task IDs materially differ in content, not just prose: e.g. this branch's `14_REQUIREMENT_PHASE_TRACEABILITY.md` traces 607 source items; the other branch's Prompt 82 build log states its adopted traceability baseline has 401 items. Both branches also used different Phase 0 build-log directory conventions for the same task (`docs/build-log/phase-00/PH0-81.md` on this branch vs. `docs/build-logs/CG-S5-PH0-002_source_alignment_context_bootstrap.md`, the older plural convention, on the other branch).

#### Evidence

- `git log --oneline origin/claude/sleepy-ride-4vxsk6 -10` shows the independent commit sequence `6068e62`…`18c6a35`, none shared with `agent/cargogrid-autonomous-build` past `27389a4`.
- `git merge-base origin/claude/sleepy-ride-4vxsk6 origin/main` → `27389a4` (PR #8). `git merge-base agent/cargogrid-autonomous-build origin/main` → `824b548` (PR #9). Confirms the two branches diverged from different points and neither is an ancestor of the other.
- GitHub `list_pull_requests` (this session): PR #10, `state: open`, `head: claude/sleepy-ride-4vxsk6`@`6068e62`, `base: main`@`d7b695d`, created `2026-07-14T23:44:54Z` — **not merged**, no CI/review action taken on it by this session.
- `git show --stat 0bb208b` / `6068e62` (the other branch's Prompt 81/82 commits) confirm materially different file paths and content from this branch's equivalent commits.

#### Impact

- No data loss, no secret exposure, no production/database impact (both lineages are documentation-only).
- **Real impact:** two non-reconcilable, independently-numbered versions of `CG-S3-ARCH-014..016` and `CG-S5-PH0-001..003` now exist. If PR #10 is merged into `main` independently of this branch (or vice versa), a future merge between the two lineages will silently duplicate or conflict — the same failure pattern as `ERR-2026-001`, at much larger scale (9 commits / 3+ full documents vs. one file).
- Continuing to advance *either* branch further compounds the eventual reconciliation cost. This session therefore halts further prompt execution on discovery of this state rather than proceeding into Prompt 82.

#### Recovery — NOT YET PERFORMED, requires operator decision

This is **not** resolved by this session. Per this routine's own instruction to stop on conflicting repo state and record a blocker rather than resolve it unilaterally (picking a branch/PR to keep is a significant, hard-to-reverse, shared-state decision), recovery requires an explicit operator choice between:

1. **Adopt this branch** (`agent/cargogrid-autonomous-build`, current HEAD `1802400`) as authoritative; close PR #10 without merging; the other branch's Prompt 82 work (`claude/sleepy-ride-4vxsk6`) is discarded (it re-derives content already produced independently on this branch through Prompt 81, plus one additional prompt, 82, not yet done here).
2. **Adopt PR #10's lineage** (`claude/sleepy-ride-4vxsk6`, includes Prompt 82) as authoritative; reset `agent/cargogrid-autonomous-build` to match; this branch's Prompts 49–51/80/81 work is discarded in favor of the other lineage's equivalent (already-complete) versions.
3. **Reconcile manually** — compare both lineages' Prompt 49–51/80–82 outputs field-by-field (similar to the `CG-S2-DISC-001-R1` precedent, `ERR-2026-001` above) and produce a merged, single authoritative version, documenting which facts/numbers from each lineage were kept and why.

No option is safe for an autonomous agent to select without operator input — option 1 or 2 discards real completed work either way, and option 3 requires judgment about which lineage's specific factual claims (e.g., 607 vs. 401 traced items) are correct.

Status: `OPEN`. Resume only after an operator selects and records one of the three options above in this ledger and in `HANDOFF.md`.

## 4. Notes

Prevention: run each runtime Step 2–onward prompt on **one** authoritative branch only; do not open parallel agent sessions on the same runtime step (tracked as ISS-2026-002 — now demonstrated twice). Use the full error-record template from `01-agent-governance/17_ERROR_LEDGER_TEMPLATE.md` for future entries.
