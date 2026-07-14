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

## 4. Notes

Prevention: run each runtime Step 2–onward prompt on **one** authoritative branch only; do not open parallel agent sessions on the same runtime step (tracked as ISS-2026-002). Use the full error-record template from `01-agent-governance/17_ERROR_LEDGER_TEMPLATE.md` for future entries.
