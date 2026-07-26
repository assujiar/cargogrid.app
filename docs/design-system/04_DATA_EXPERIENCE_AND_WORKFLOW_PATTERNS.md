# Data Experience and Workflow Patterns

Source of decisions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §4–§7 (component inventory, workflow maps, access-presentation rules — `VERIFIED`, cited not re-derived), `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` (status/approval engine, cited by reference). This document records the pattern-level rules every future data/workflow screen must follow and the current implementation baseline they are checked against — it does not re-plan the workflow maps `09_*.md` §6 already fixed.

## 1. Data experience patterns

| Pattern | Binding rule | Current baseline |
|---|---|---|
| Dense operational tables | Server-side filter/sort/search/pagination only; never client-side filtering of a full dataset; column-projected fetch, never `SELECT *` to the browser (`09_*.md` §11, `AGENTS.md`) | `supreme/tenants/page.tsx` implements offset pagination server-side correctly; no filter/sort UI exists yet on any screen |
| Financial tables | Money stays `numeric` end to end (never binary float) from query through render; explicit rounding only at defined money-producing steps (`server/mutations/margin.ts`'s own precedent, `COM-150`) | Followed by every Commercial money-bearing query/mutation; no dedicated "financial table" UI primitive exists yet — `DOCUMENTED_ONLY` |
| Editable tables | Inline edit with the same validation/masking rules as a full form | None exist yet — `DOCUMENTED_ONLY` |
| Comparison tables | Side-by-side entity comparison (e.g. rate options) | None exist yet — `DOCUMENTED_ONLY` |
| Master-detail layouts | List + detail split, detail as drawer or full page | Every current screen is full-page list *or* full-page detail, never split-pane — `DOCUMENTED_ONLY` for the split-pane variant |
| Search | Server-side FTS/trigram-first (`09_*.md` §2.4, `RPD-039`), never a separate unscoped index | Not yet built on any screen |
| Advanced filters / Filter bar | Explicit allowlist, one shared allowlist definition (not a UI-only convenience) — mirrors `08_*.md` §4.4's server-side allowlist | Not yet built |
| Saved views | Named, persisted filter/sort/column state | Not yet built |
| Column visibility / resizing | User-configurable, persisted per view | Not yet built |
| Sorting | Server-side, allowlisted sortable columns | Not yet built |
| Pagination | Offset/cursor/keyset per `08_*.md` §4.3's per-table class assignment | Offset pagination implemented once (`supreme/tenants`) |
| Infinite loading | Where appropriate per `08_*.md` §4.3 | Not yet built |
| Virtualized rows | Required once a table can exceed a viewport-multiple of rows | Not yet needed at current data volumes (no screen renders more than one page of rows) |
| Row selection / Bulk actions | Selection-token pattern — never thousands of raw IDs sent from the browser (`09_*.md` §4.1) | Not yet built (no bulk mutation exists yet in this repository) |
| Export / Import | Async job + progress UI + result file, never a blocking request (`09_*.md` §11); import validation reports partial success per row | `server/mutations/document.ts`/`server/queries/document.ts` exist as backend primitives; no export/import UI exists yet |
| Audit trail / Status history / Operational timeline | Before/after value disclosure inline for Supreme Admin mutations (`09_*.md` §7); canonical status transitions only, never a tenant-relabeled value standing in for the canonical one | Backend audit logging exists (`audit_logs`, referenced throughout Platform Core); no UI timeline component renders it yet — `DOCUMENTED_ONLY`, see `02_COMPONENTS.md`'s Timeline/Activity item/Audit item rows |
| Dashboard / Chart / KPI / Funnel | Pre-aggregated/materialized where heavy; partial-widget-failure isolation (`09_*.md` §5 "Partial" state); charts dynamically imported, never in the initial bundle (`09_*.md` §11) | No dashboard exists yet in this repository (Home dashboard is `09_*.md` §14's Phase-1 "Portal shells" slice item, not yet built) |
| Approval queue / Exception queue | Renders `07_*.md`'s approval-decision/exception catalogue; sequential/parallel/conditional/threshold/delegation/escalation all representable (`09_*.md` §12) | Backend approval engine exists (`07_*.md`); no queue UI exists yet |
| Activity feed / Documents / Attachments / Notes / Comments | Signed-URL-gated, malware-scan-status-checked file rendering (`09_*.md` §4.1) | `server/contracts/document/document.ts`/queries/mutations exist as backend primitives; no UI exists yet, and the file-upload prerequisite itself is `BLOCKED` (`02_COMPONENTS.md` §2) |

## 2. Workflow patterns

Every pattern below restates `09_*.md` §5's 11-state contract (Loading/Empty/Error/Offline/Partial/Unauthorized/Forbidden/Conflict/Success/Retry/Destructive-confirmation) as the binding shape each workflow action's UI must implement — not re-derived per pattern below.

| Pattern | Binding rule |
|---|---|
| Create / Edit | Same Form Field/Form Section primitives (`02_COMPONENTS.md`); Edit pre-fills from the current `record_version` and detects a conflict on submit (`09_*.md` §5 "Conflict") |
| Duplicate | Copies editable fields only, never canonical identifiers/audit lineage — a duplicate is a new record, not a clone of history |
| Archive / Delete / Restore | Soft-delete/archive by default (`AGENTS.md` "Normal roles still use... soft-delete... controls"); Supreme Admin's absolute-CRUD exception is disclosed inline wherever it applies (`09_*.md` §7 "Supreme Admin disclosures"), never silently |
| Approve / Reject / Reopen / Cancel | Renders through the Approval Decision Panel pattern (`09_*.md` §4.1, `components/domain/`, not yet built); reject/cancel require a reason where `07_*.md` marks the transition reason-required |
| Submit / Publish / Save draft / Autosave | Draft→Published lifecycle mirrors the Configuration Engine's own publish pattern (`07_*.md` §5/§8) already proven at `PLT-117`'s white-label draft/publish/rollback; autosave (if built) must never silently discard a conflict — same "Conflict" state applies |
| Unsaved changes | Warn before navigation away from a dirty form (not yet implemented anywhere — no form is complex/long enough yet to need it) |
| Multi-step workflow | Stepper primitive (`02_COMPONENTS.md`, `DOCUMENTED_ONLY`) with per-step validation, never a hidden step a user can't return to |
| Assignment / Escalation / SLA warning | Renders the notification/escalation payload exactly as field-masking-compliant as a direct query (`09_*.md` §2.4) |
| Partial success | Batch/import operations report per-row outcome, never a single pass/fail for a multi-row operation |
| Batch operation | Async job pattern (`09_*.md` §11), progress UI, result summary — same shape as Export/Import above |
| Long-running process | Progress state (`09_*.md` §5 "Loading" — "progress bar for upload/import/export/generation") |
| Import and validation | Row-level validation report before commit, whitelisted field mapping only |
| Export generation | Async job, never blocks the request thread; respects the same field-masking the list/detail view would (`09_*.md` §7) |
| Permission denial | `09_*.md` §5 "Forbidden" pattern verbatim — states what is inaccessible without leaking existence/shape of hidden data; `admin/layout.tsx`'s denied-state render is the closest existing implementation |
| Cross-functional handoff | Status transition that hands a record to a different domain/role queue — renders via the same status/timeline primitives, never a bespoke per-domain handoff UI |

No workflow pattern above has a dedicated shared component yet beyond what `02_COMPONENTS.md` already marks `DOCUMENTED_ONLY`/`IMPLEMENTED` — this document fixes the rules those future components must satisfy, consistent with `09_*.md` §6's workflow-to-page maps, which this document does not re-derive.
