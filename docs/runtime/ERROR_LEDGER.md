# ERROR_LEDGER.md

**Instance of:** `CG-AABPP-GOV-017`
**Instance version:** `0.2.0`
**Updated:** 2026-07-14T09:58:59+07:00
**Policy:** Record reproducible failures, failed gates, unsafe/unknown states, and recovery evidence. Do not store secrets, tokens, or unredacted tenant data.

## 1. Error states and severity

Statuses: `OPEN`, `INVESTIGATING`, `ROOT_CAUSE_CONFIRMED`, `RECOVERY_IN_PROGRESS`, `RECOVERED`, `VERIFIED`, `ACCEPTED`, `SUPERSEDED`.

| Severity | Definition | Default effect |
|---|---|---|
| Sev-1/Critical | Tenant isolation, credential exposure, corrupt/imbalanced finance, destructive data loss, production outage, untrusted repository/database | Stop affected work/release |
| Sev-2/High | Major flow unavailable, serious security/access defect, failed migration/restore, cross-module integrity failure | Block phase/release |
| Sev-3/Medium | Bounded defect or failed non-critical gate with safe workaround | Separate recovery task |
| Sev-4/Low | Minor tooling/docs/local issue without data/security impact | Track and schedule |

## 2. Error index

| Error ID | Task ID | Severity | Environment | Summary | Status | Root cause | Last good checkpoint | Owner | Record link |
|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | No errors recorded at this checkpoint | — | — | `53e3d4a` | — | — |

## 3. Notes

No reproducible failures, failed gates, or unsafe states occurred during `CG-S2-DISC-001` (Repository Discovery, Prompt 21). All inventory commands were read-only and exited normally. The worktree remained clean and the repository checkpoint `53e3d4a` remained trusted and unchanged throughout discovery.

Use the full error-record template from `docs/ai-agent-build-prompt-package/01-agent-governance/17_ERROR_LEDGER_TEMPLATE.md` when the first error is recorded.
