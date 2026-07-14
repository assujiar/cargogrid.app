# ERROR_LEDGER.md

**Template ID:** `CG-AABPP-GOV-017` (instance)
**Template version:** `0.2.0`
**Updated:** 2026-07-14T10:16:05+07:00
**Mode:** Append-only. Never delete failure/recovery evidence.

## 1. Active errors

| Error ID | Task | Severity | Exact evidence | Impact | Root cause | Last trusted checkpoint | Recovery | Status |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | none |

No errors recorded. Task `CG-S2-DISC-001` (Repository Discovery) executed without unexpected mutation, secret exposure, repository mismatch, or trust loss. Checkpoint `db1742c` remains trusted.

## 2. Resolved / superseded errors

| Error ID | Resolution | Verified by/date |
|---|---|---|
| — | — | — |

## 3. Rules

Record a new entry when a command unexpectedly mutates files/services/data/lockfiles, a credential or real tenant record is exposed, migration state becomes partially applied/unknown, evidence contradicts a protected decision, or repository/database trust is lost. Each entry must capture exact evidence, impact, root cause, last trusted checkpoint, recovery steps, re-verification gates, and a resume task/prompt.
