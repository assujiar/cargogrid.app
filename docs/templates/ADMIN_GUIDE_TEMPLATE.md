# {{FEATURE_OR_MODULE_NAME}} — Admin Guide

**Template ID:** `CG-DOCS-ADMIN-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** Tenant Admin / Supreme Admin — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `{{DRAFT | ACTIVE | SUPERSEDED}}`
**Owner:** `{{ROLE_OR_TEAM}}`
**Since:** Phase `{{PHASE_NUMBER}}` / release `{{RELEASE_ID}}`
**Source requirement:** `{{BLUEPRINT_SECTION_OR_CONFIG_ENGINE_REF}}`

> Do not instantiate this template until the described admin surface is real and shipped. If this document covers Supreme Admin capability, disclose the Supreme Admin risk-rule exception exactly as `AGENTS.md` "Supreme Admin risk rule" requires — never claim tamper-proof/absolute immutability.

## 1. Purpose and scope

`{{WHAT_THIS_ADMIN_SURFACE_CONTROLS}}`

## 2. Who can access this

Exact role/scope required (`{{ROLE}}`), and whether it is Tenant-scoped or Supreme-Admin-only. MFA requirement per `AGENTS.md`/RPD-023: `{{YES_FOR_PRIVILEGED_ROLE | N/A}}`.

## 3. Configuration reference

| Setting | Effect | Default | Effective-dated? (`AGENTS.md` "Data and finance rules") | Notes |
|---|---|---|---|---|
| `{{SETTING}}` | `{{EFFECT}}` | `{{DEFAULT}}` | `{{YES/NO}}` | `{{NOTES}}` |

## 4. Common admin tasks

1. `{{TASK}}` — steps: `{{STEPS}}`
2. `{{TASK}}` — steps: `{{STEPS}}`

## 5. Audit and reversal

How this admin action is logged, and how (if at all) it can be reversed — must match `AGENTS.md`'s ledger/reversal/period-lock/soft-delete rules for normal roles, and the disclosed Supreme Admin exception where applicable: `{{DESCRIPTION}}`.

## 6. Support escalation

When to hand off to Support/Engineering rather than resolve via this admin surface: `{{CRITERIA}}`. Linked runbook: `{{LINK_OR_NONE}}`.

## 7. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| `{{DATE}}` | `0.1.0` | Initial | `{{AUTHOR}}` |
