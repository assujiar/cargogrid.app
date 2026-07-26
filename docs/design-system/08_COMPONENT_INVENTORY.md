# Shared Component Inventory and Showcase

**Added by:** CargoGrid UI Modernization checkpoint 3 (2026-07-26, out-of-band — not a numbered `CG-S*-*` Commercial-phase prompt; does not consume, rename, or renumber `CG-S7-COM-020`/Prompt 161). Continues the same out-of-band design-system track as checkpoint 1 (`CargoGrid Design System Expansion and Implementation`) and checkpoint 2 (`Table and Pagination primitives`, `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` §8).

## 0. Scope and method

This checkpoint's own instruction asked for a full inventory of every shared component, classified into 14 categories, plus a protected internal showcase route rendering every one of them with every supported variant/state, plus a duplicate-detection migration map. Before writing any code, the repository was audited by direct inspection (`Grep`/`Read`, not assumed):

- `components/ui/` and `components/tables/` are the only shared component directories that exist. No `components/domain/`, `components/forms/`, `components/charts/`, `components/layout/`, or `components/feedback/` directory exists anywhere in this repository (confirmed empty/absent this checkpoint).
- Exactly **6 components are real**: `Button`, `Banner`, `Badge`, `StatusBadge` (checkpoint 1), `DataTable`, `Pagination` (checkpoint 2). Everything else this checkpoint's own instruction named is `DOCUMENTED_ONLY`, `BLOCKED`, or — for a handful of names this instruction introduced that no prior CargoGrid design-system document ever scoped (Split Button, Dropdown Action, Description List, Stat, Success State) — disclosed as `NOT_NAMED` rather than fabricated.
- Consumer counts were verified by `grep` against `app/` for each component's import path, not estimated. The most consequential finding: **`Badge` and `StatusBadge` have zero real consumers today** — both are production-ready and unused, even though the exact screens that need them (Lead status, Supreme Tenant status) already exist and currently render that data as plain text.

The full machine-readable inventory — every field this checkpoint's instruction requested (name, source file, export path/import snippet, purpose, variants, sizes, states, consumers, tokens used, accessibility, responsive behavior, production-readiness, duplicate note) — lives in code, not only in this document, so it cannot drift silently from what the showcase itself renders:

| Data | File |
|---|---|
| Component inventory (14-category taxonomy minus Foundations/Page Patterns) | `lib/design-system/component-registry.ts` |
| Foundations token catalogue | `lib/design-system/tokens.ts` (unit-tested against `app/globals.css` — `tokens.test.ts` fails if a listed token stops existing) |
| Page Patterns | `lib/design-system/pattern-registry.ts` |
| Duplicate/migration map | `lib/design-system/migration-map.ts` |
| Mock business data (showcase only, never live) | `lib/design-system/mock-business-data.ts` |

This document is the prose rendering of that same research — read it for the narrative; read the code for the exact, currently-accurate data (this document is not re-verified on every future token/component change, the registries are the living source).

## 1. The 6 real components

Full spec (purpose, anatomy, variants, sizes, states, keyboard, accessibility, responsive, white-label, density, anti-patterns, implementation notes) for all 6 already lives in `docs/design-system/02_COMPONENTS.md` §1 — not duplicated here. Summary:

| Component | Source | Status | Consumers | Production-ready |
|---|---|---|---|---|
| Button | `components/ui/button.tsx` | `IMPLEMENTED` | 39 files (every Commercial form/action-panel, login page) | Yes |
| Banner | `components/ui/banner.tsx` | `IMPLEMENTED` | 1 file (`supreme/layout.tsx`, RPD-022 disclosure) | Yes |
| Badge | `components/ui/badge.tsx` | `IMPLEMENTED` | **0 files** | Yes, but unused |
| StatusBadge | `components/ui/status-badge.tsx` | `IMPLEMENTED` | **0 files** | Yes, but unused |
| DataTable | `components/tables/data-table.tsx` | `IMPLEMENTED` | 2 files (`commercial/leads`, `supreme/tenants`) | Yes |
| Pagination | `components/tables/pagination.tsx` | `IMPLEMENTED` | 2 files (same two) | Yes |

No duplicate implementation of any of these 6 exists anywhere in `app/` — each was verified by grep to be the sole real instance of its own behavior.

## 2. Everything else — one paragraph per category, full detail in the registry

Of the ~90 names this checkpoint's own instruction enumerated across the remaining 12 non-Foundations/non-Page-Patterns categories, **none are implemented**. Every one is `DOCUMENTED_ONLY` (a full or compact spec already exists, most from `docs/design-system/02_COMPONENTS.md` §2 or `03_LAYOUT_NAVIGATION.md` §1), `BLOCKED` (File upload, Document preview, Attachment list — all on the same missing storage/upload pipeline), or `NOT_NAMED` (Split Button, Dropdown Action, Description List, Stat, Success State — this checkpoint's own instruction is the first place these were ever mentioned in this repository's design-system record; not invented here, but not silently treated as already-scoped either). See `lib/design-system/component-registry.ts` for the per-entry citation trail — every status traces to a specific existing document or a specific grep result, never asserted from memory.

Two categories deserve a specific, non-obvious callout:

- **Charts and Analytics**: no chart library dependency exists in `package.json`, and the one real dashboard (`commercial/dashboard/page.tsx`, COM-158) renders its metrics as buckets/lists, not charts or KPI tiles. There is nothing to migrate onto a chart wrapper yet because there is no chart anywhere in this repository to begin with.
- **Domain Components**: `components/domain/` does not exist. The two clearest candidates for it — an Approval Decision Panel (independently duplicated today by `approval-decision-form.tsx` and `credit-approval-decision-form.tsx`) and a canonical status→tone mapping (the missing link that would let `StatusBadge` actually get adopted) — are both named in the migration map (§4) rather than built speculatively.

## 3. The showcase

`/internal/design-system` (a new, isolated route group — `app/(internal)/internal/design-system/`), gated by `lib/design-system/environment.ts`'s `isNonProductionEnvironment()` (reads this repository's own `CARGOGRID_ENV` deployment-tier discriminator, falling back to `NODE_ENV`) **or** a real, allowed Supreme Admin session (`resolveSupremeAdminAccessForRequest`, unchanged, reused read-only). Blocked requests render `notFound()`, not a friendly denial page — this route's own existence is itself the development-only information this checkpoint's instruction says not to expose publicly.

Deliberately **not** nested under `(supreme)`: that portal's own layout unconditionally requires an authenticated, allowed Supreme Admin session with no development bypass, and editing that already-`VERIFIED` PLT-136 shell's gate to add one would be a behavior change to a shipped capability, out of this checkpoint's bounded scope.

Nine sections, all real content, none screenshots or hand-recreated look-alike markup:

| Route | Content |
|---|---|
| `/foundations` | Every real token category from `app/globals.css`, rendered via the actual Tailwind utility class or `var()` reference — including the categories this repository has **not** decided (z-index, icon sizes, font weights) or has decided but never implemented (motion fast/slow, real font loading), shown as disclosed gaps, not approximated |
| `/components` | All ~76 catalogued entries, searchable/filterable by category and status, with live variant/state matrices for the 6 real primitives and copyable import snippets |
| `/tables` | `DataTable`/`Pagination` against a genuinely interactive 200-row mock dataset (URL-driven pagination, not a fake click handler), density tiers, long-text wrapping, composed status cells and row actions, and an explicit "not supported today" list |
| `/domain-components` | The 2 `DomainComponents`-category entries, both `DOCUMENTED_ONLY` |
| `/domain-examples` | The 11 real-business-example patterns this checkpoint's instruction named (Lead status badge, Opportunity probability badge, Quotation approval card, Margin warning alert, Credit hold notification, Contract expiry banner, Rate validity indicator, Job Order handoff summary, Customer account header, Pipeline table row, Approval timeline) — mock data only, built from the 6 real primitives plus plain semantic-token markup where no primitive exists (Card, Timeline) |
| `/patterns` | The 10 named page patterns, each pointing at a real existing reference page where one exists (8 of 10) or disclosed as not built (Wizard, Settings page) |
| `/duplicates` | The migration map (§4), rendered through `DataTable` itself |
| `/accessibility` | Per-component accessibility behavior, compiled from the same registry driving `/components` |
| `/responsive-preview` | The desktop/tablet/mobile control (available globally in the sidebar on every page) demonstrated against a real `DataTable` |

**Light/dark mode, honestly scoped**: CargoGrid's Design System has never defined a tenant-facing dark theme token set (no entry in `docs/standards/DESIGN_SYSTEM.md` §2's token table, no `.dark` class or `prefers-color-scheme` block in `app/globals.css`). The showcase's own theme toggle (`chrome-context.tsx`) recombines the existing neutral scale for its own reading chrome only — verified live (§5) that toggling it does not change how the real showcased components render, because none of them consume a token that varies by this toggle. This is disclosed on-page, not hidden.

## 4. Duplicate component detection and migration map

Full table (legacy implementation, shared replacement, replacement status, affected pages, priority, breaking-change risk): `lib/design-system/migration-map.ts`, rendered live at `/internal/design-system/duplicates`. Summary, highest priority first:

1. **Canonical status rendered as plain text instead of `StatusBadge`** (Lead.status, SupremeTenant.canonicalStatus, and others) — `StatusBadge` is production-ready and has zero consumers. Highest-value, lowest-risk gap in this entire inventory. Blocked only on the not-yet-built canonical-status-to-tone mapping (a Domain Component, §2).
2. **Raw `<table>` markup**, one copy per page — 19 remaining files (full list in `migration-map.ts`; `commercial/leads` and `supreme/tenants` already migrated, checkpoint 2). Low risk: the same purely-presentational migration already proven twice.
3. **Hand-rolled `animate-pulse` skeleton bars**, one copy per route's `loading.tsx` — 27 files (list below, §5). Blocked on a Skeleton primitive that does not exist yet.
4. **Inline `role="alert"` error blocks** and **inline empty-state `<p>` text**, one copy per page — 21+ and 19+ pages respectively. Blocked on Error State / Empty State primitives that do not exist yet.
5. **`approval-decision-form.tsx` / `credit-approval-decision-form.tsx`** independently implement the same approve/reject decision panel — Medium risk (touches real submit/decision server actions, not pure display); wait for a third consumer before extracting, per `09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §4.2's "one owner" rule.
6. **Raw `<input>`/`<select>`/`<textarea>`**, one hand-styled copy per form — 39 files. Mechanical if scoped to display only.
7. **`Lead.source` rendered as plain text** instead of `Badge` — single file, cosmetic.

Per this checkpoint's own instruction: **no legacy implementation was deleted or migrated by this checkpoint** — this is a map for future, individually-authorized, atomically-sized follow-up tasks (`AGENTS.md` sizing discipline), the same discipline checkpoint 2 already used to scope itself to exactly one item off this same kind of list.

## 5. Grep evidence (for auditability)

Commands run this checkpoint, repo root, before any registry data was written:

- Raw `<table>`: `grep -rl '<table\b' app/` → 21 files (2 already migrated as of checkpoint 2 are excluded from the migration map's "remaining" list in §4).
- Hand-rolled skeletons: `grep -rl 'animate-pulse' app/` → 27 `loading.tsx` files, all under `commercial/*`, `admin/users`, and `supreme/tenants`.
- Form/action-panel files: `grep -rl 'from ".*components/ui/button"' app/` → 39 files (every one is a form or action-panel component; Button's own 39-consumer count in §1 comes from this same command).
- Badge/StatusBadge consumers: `grep -rl 'from ".*components/ui/badge"' app/` and the `status-badge` equivalent → 0 files each.
- Banner consumers: `grep -rl 'from ".*components/ui/banner"' app/` → 1 file.
- DataTable/Pagination consumers: `grep -rl 'from ".*components/tables/' app/` → 2 files.

## 6. What this checkpoint did not do

Consistent with `AGENTS.md`'s atomic-task-sizing discipline and the same self-scoping checkpoints 1 and 2 already established: this checkpoint did not build any new component beyond what already existed (the showcase renders exactly the 6 real primitives, nothing more), did not migrate any legacy page onto a shared primitive (that is the migration map's job for a future checkpoint, not this one), and did not change any business logic, API, or database schema. The showcase itself is purely additive and read-only against mock data.
