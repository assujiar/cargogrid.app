# Release `{{RELEASE_ID}}` — {{RELEASE_DATE}}

**Template ID:** `CG-DOCS-RELEASE-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** All (developer/admin/user-visible summary) — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `{{DRAFT | ACTIVE}}`
**Owner:** Release Manager
**Phase:** `{{PHASE_NUMBER}}`

> Every item below must trace to a `VERIFIED` task/build log or a merged, gate-passing PR — never a planned/in-progress item (`AGENTS.md`: "Never label a task, phase, or product complete beyond the evidence actually obtained").

## 1. Summary

`{{ONE_PARAGRAPH_SUMMARY}}`

## 2. New features

| Feature | Docs | Task/build-log evidence |
|---|---|---|
| `{{FEATURE}}` | `{{USER_OR_ADMIN_GUIDE_LINK}}` | `{{TASK_ID_AND_BUILD_LOG_LINK}}` |

## 3. Changes

| Change | Impact | Evidence |
|---|---|---|
| `{{CHANGE}}` | `{{IMPACT}}` | `{{EVIDENCE}}` |

## 4. Fixes

| Fix | Related issue | Evidence |
|---|---|---|
| `{{FIX}}` | `{{ISSUE_ID_OR_NONE}}` | `{{EVIDENCE}}` |

## 5. Deprecations / breaking changes

| Item | Removal/effective date | Migration guidance |
|---|---|---|
| `{{ITEM}}` | `{{DATE}}` | `{{GUIDANCE}}` |

## 6. Known issues carried into this release

Reproduced by reference from `docs/runtime/KNOWN_ISSUES.md` (not re-typed): `{{ISSUE_ID_LIST}}`.

## 7. Upgrade / migration notes

`{{NOTES_OR_NONE}}`

## 8. Go/No-Go evidence (if this release requires the direct-GA gate, RPD-034/036)

Link to the readiness dashboard / go-live checklist evidence (`docs/architecture/10_TESTING_WORKSTREAM.md` §13, §10.3): `{{LINK}}`.
