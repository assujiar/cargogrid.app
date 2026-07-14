# ERROR_LEDGER.md

**Template ID:** `CG-AABPP-GOV-017` (instance)
**Template version:** `0.2.0`
**Updated:** 2026-07-14T10:16:05+07:00
**Mode:** Append-only. Never delete failure/recovery evidence.

## 1. Active errors

| Error ID | Task | Severity | Exact evidence | Impact | Root cause | Last trusted checkpoint | Recovery | Status |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | none |

No active errors. Checkpoint `d58744500a55c267ddf7447c6518fc86c1323912` (branch `claude/eloquent-mayer-s40hn4`) remains trusted.

## 2. Resolved / superseded errors

| Error ID | Resolution | Verified by/date |
|---|---|---|
| `ERR-2026-001` | `docs/discovery/01_REPOSITORY_INVENTORY.md` found corrupted (duplicate/contradictory content spliced in by the merge that produced HEAD `d587445` from two parallel discovery-bootstrap PRs — `oanf5a`@`53e3d4a` and `b492y3`@`db1742c`, each of which independently wrote a full copy of this file). Recorded output hash `97ecbe4d18b26a441e46161553d72f85b7ea657437574c520f3c26cc1ed7f4dd` no longer matched the file's actual content (`8a067b8d1d7aafd3e6041a326c9e7ec7cd30183b63ee1d63968e3037e774f29f` at detection). No application/product file was affected — corruption was confined to this one discovery document. Recovery: rewrote the file as a single reconciled record at the current checkpoint (`d587445`/`claude/eloquent-mayer-s40hn4`), recomputed sidecar hash `docs/discovery/01_REPOSITORY_INVENTORY.sha256` = `c7f8d22f8d5dc62c31d37e9b972a72db414e412f8677abd7c3fd6cb7f77d1d72`, and logged the addendum in `docs/build-logs/CG-S2-DISC-001_repository_discovery.md`. | Claude Code / 2026-07-14 |

## 3. Rules

Record a new entry when a command unexpectedly mutates files/services/data/lockfiles, a credential or real tenant record is exposed, migration state becomes partially applied/unknown, evidence contradicts a protected decision, or repository/database trust is lost. Each entry must capture exact evidence, impact, root cause, last trusted checkpoint, recovery steps, re-verification gates, and a resume task/prompt.
