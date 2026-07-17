# {{FEATURE_OR_MODULE_NAME}} — User Guide

**Template ID:** `CG-DOCS-USER-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** End user (tenant staff / customer portal user) — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `{{DRAFT | ACTIVE | SUPERSEDED}}`
**Owner:** `{{ROLE_OR_TEAM}}`
**Since:** Phase `{{PHASE_NUMBER}}` / release `{{RELEASE_ID}}`
**Source requirement:** `{{BLUEPRINT_SECTION_OR_UAT_E2E_ID}}`

> Do not instantiate this template until the described feature is real and shipped (`AGENTS.md`: "no demo-only persistence"). Every screenshot, field name, and workflow step below must match actually-implemented behavior, not a planned one.

## 1. What this feature does

`{{ONE_PARAGRAPH_PLAIN_LANGUAGE_SUMMARY}}`

## 2. Who can use it

Roles/scopes authorized for this feature (must match the server-side authorization actually enforced, not a UI-only assumption — `AGENTS.md` "UI visibility is not authorization"): `{{ROLE_LIST}}`.

## 3. Before you start

Preconditions, required setup, or prior steps: `{{PRECONDITIONS}}`.

## 4. Step-by-step

1. `{{STEP}}`
2. `{{STEP}}`

Include the complete-states this feature actually implements (`AGENTS.md` "UX, performance, and accessibility"): what loading/empty/error/denied/degraded/unsaved-changes look like, not only the success path.

## 5. Field reference

| Field | Meaning | Required | Notes |
|---|---|---|---|
| `{{FIELD}}` | `{{MEANING}}` | `{{YES/NO}}` | `{{NOTES}}` |

## 6. Common errors and what they mean

| Error message (exact text) | Cause | What to do |
|---|---|---|
| `{{ERROR_TEXT}}` | `{{CAUSE}}` | `{{ACTION}}` |

## 7. Related documents

- Admin-side counterpart: `{{LINK_OR_NONE}}`
- Support runbook (if this feature has a known operational failure mode): `{{LINK_OR_NONE}}`

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| `{{DATE}}` | `0.1.0` | Initial | `{{AUTHOR}}` |
