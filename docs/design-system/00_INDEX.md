# CargoGrid Design System — Canonical Detail Specifications

**Added by:** CargoGrid Design System Expansion and Implementation task (2026-07-24). Out-of-band — not a numbered `CG-S*-*` Commercial-phase prompt. Does not consume, replace, rename, or renumber Prompt 151 (`CG-S7-COM-010`, Quotation Builder) or any later roadmap prompt. `docs/runtime/CARGOGRID_BUILD_STATUS.md`'s "Next eligible task" row is unchanged by this work.

**Relationship to existing documents (read this first):** this subtree is the detail layer under `docs/standards/DESIGN_SYSTEM.md` (the foundations/decisions index, reconciled by this same task) and does not compete with it or with `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (the `VERIFIED` planning-precision experience-architecture document). Precedence: `docs/standards/DESIGN_SYSTEM.md` §0/decisions win on conflict; `09_*.md` wins on architecture/routing/domain-ownership questions; this subtree is the implementation-precision detail neither of those documents was scoped to carry. Nothing here restates a decision differently than its source — every section below cites its source rather than re-deriving it.

## Identity

**CargoGrid Adaptive Industrial UI.** The product should feel like an **Enterprise Logistics Control Tower**: flat first, depth on demand, dense ERP-style information architecture, exception-first, calm by default with vividness reserved for action/selection/warning/exception, performance-first, accessibility-first, shared-primitives-first, white-label capable, audit-aware, role-aware, tenant-safe. Visual balance target: 85% flat / 10% subtle elevation / 5% soft tactile interaction. Full principle list, anti-patterns, and governance boundary: `docs/adr/ADR-0017`.

## Status legend (used throughout this subtree)

| Status | Meaning |
|---|---|
| `IMPLEMENTED` | Real code exists in this repository, typechecked/linted/built this checkpoint. |
| `DOCUMENTED_ONLY` | A full specification exists below; no corresponding component/pattern code exists yet. |
| `DEFERRED` | Named, scoped, and reasoned about, but explicitly not attempted this checkpoint (usually: requires a schema migration, a route/screen that doesn't exist yet, or a multi-file screen-alignment pass beyond this task's bounded scope). |
| `BLOCKED` | Requires a decision or artifact outside this task's authority (e.g., a product decision, a live environment). |

No item in this subtree is marked `IMPLEMENTED` unless it was directly verified against real repository code this checkpoint (see `07_GAP_ANALYSIS_AND_ROADMAP.md` for the audit method).

## Map

| Document | Covers |
|---|---|
| `01_TOKENS_AND_THEME.md` | Design tokens (color, typography, spacing, radius, elevation, motion, density), theme resolution order, white-label validation coverage table |
| `02_COMPONENTS.md` | Component catalogue — full spec for implemented primitives, compact spec for the ~70-item requested catalogue, each with a status |
| `03_LAYOUT_NAVIGATION.md` | Application shell, sidebar/top bar/breadcrumb, tenant/branch/portal/module switching, permission-aware navigation |
| `04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` | Dense tables, filters/saved views, dashboards, and workflow patterns (create/edit/approve/escalate/batch/import-export/etc.) |
| `05_AI_ASSISTED_INTERACTION.md` | AI suggestion/summary/draft/recommendation/score/explanation patterns; the binding human-approval/audit rule |
| `06_ACCESSIBILITY_PERFORMANCE.md` | WCAG 2.2 AA acceptance criteria and performance budgets at component/pattern precision |
| `07_GAP_ANALYSIS_AND_ROADMAP.md` | Repository audit findings; what changed this checkpoint; deferred/blocked items with reasoning; recommended (not unilaterally executed) sequencing |

## What this task implemented in code (summary — full detail `07_GAP_ANALYSIS_AND_ROADMAP.md`)

- Resolved CargoGrid's default brand identity (`ADR-0016`) and wired it into `app/globals.css`'s token source.
- Added semantic surface/text/border tokens, elevation (`--shadow-*`), and density (`--row-height-*`) tokens to `app/globals.css` — none of these existed in CSS before this checkpoint, though elevation/density were already *decided* in `docs/standards/DESIGN_SYSTEM.md`.
- Added `--color-primary-hover`/`--color-secondary-hover` tokens; updated `components/ui/button.tsx`'s primary variant to consume `hover:bg-primary-hover` instead of a generic opacity dim.
- Added two new primitives: `components/ui/badge.tsx`, `components/ui/status-badge.tsx`.
- Extended `components/ui/banner.tsx` with `success`/`danger` variants (previously `info`/`warning` only).
- Added a pure, unit-tested theme-resolution function (`lib/theme/resolve-portal-theme.ts`) and a pure, unit-tested tenant-brand distinguishability policy (`lib/theme/tenant-brand-policy.ts`) — the latter is standalone/not yet wired into the enforced publish path, disclosed as such.
- Wired real tenant-brand resolution (with atomic, silent fallback to CargoGrid default on any failure) into the Tenant Admin portal shell (`app/(tenant)/[tenantSlug]/admin/layout.tsx`) — the first screen in this repository to render a resolved tenant brand. Other tenant route groups (`commercial/layout.tsx`, etc.) are unchanged this checkpoint — named as a follow-up alignment pass in the gap analysis, not silently left inconsistent.
- Left the Supreme Admin shell (`app/(supreme)/supreme/layout.tsx`) unchanged by design (`ADR-0017` §4) and added a comment there stating why, so a future checkpoint does not "fix" it into tenant-branded by mistake.

Everything else this task's own instruction requested (the ~70-component catalogue, dense data-grid/table primitives, full navigation shell, AI-interaction components, additional white-label schema fields) is `DOCUMENTED_ONLY` or `DEFERRED` — see each document's own status column and `07_GAP_ANALYSIS_AND_ROADMAP.md` for why building all of it in one checkpoint was not attempted (it would violate `AGENTS.md`'s own atomic-task-sizing and single-writer-collision discipline, which this task's own instruction defers to as governing authority).
