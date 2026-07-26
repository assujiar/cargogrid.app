# Component Catalogue

**Updated by:** CargoGrid UI Modernization checkpoint (2026-07-26, out-of-band, see `07_GAP_ANALYSIS_AND_ROADMAP.md` §8) — added `DataTable`/`Pagination` as `IMPLEMENTED` (roadmap item 3). Original authoring below (CargoGrid Design System Expansion, 2026-07-24) preserved as-is except the specific rows/sections this update touches.

Source of decisions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §4/§5 (inventory, 11-state contract — cited, not re-derived), `ADR-0005` (Radix copy-in mechanism), `ADR-0017` (design identity, white-label boundary). Every component below is documented against the same spec shape this task's own instruction requires: purpose, when to use, when not to use, anatomy, variants, sizes, states, keyboard behavior, accessibility, responsive behavior, white-label behavior, density behavior, anti-patterns, implementation notes. `IMPLEMENTED` components get the full shape; `DOCUMENTED_ONLY` components get a compact version of the same shape (enough for a future checkpoint to build against without re-deriving the pattern) — building all ~70 to full production detail in one checkpoint is out of this task's bounded scope (`AGENTS.md` atomic-sizing discipline), named honestly rather than rushed.

## 1. Implemented primitives (full spec)

### Button — `components/ui/button.tsx` — `IMPLEMENTED`

- **Purpose:** the single primary-action control every form/toolbar/dialog uses.
- **When to use:** any clickable action that is not primarily navigation (use a link for navigation; `asChild` lets a `next/link` render with button styling when an action *is* navigation-shaped).
- **When not to use:** never for destructive actions without the `destructive` variant explicitly chosen — a destructive action must never render as `primary`.
- **Anatomy:** single element (or `Slot`-composed child via `asChild`), optional loading label swap.
- **Variants:** `primary` (brand teal, `bg-primary`/`hover:bg-primary-hover`), `secondary` (neutral/quiet), `destructive` (fixed `bg-danger`, never brand-colored — `ADR-0017` §2's structural guarantee).
- **Sizes:** one size today (`px-4 py-2 text-sm`) — a `sm`/`lg` size scale is `DOCUMENTED_ONLY`, not built (no screen has needed it yet).
- **States:** default, hover, focus-visible (2px offset outline), disabled, `loading` (real state — swaps accessible name via `loadingLabel`, sets `aria-busy`, disables the control; not merely a spinner icon with no semantic change).
- **Keyboard:** native `<button>` semantics (Space/Enter activates); `asChild` preserves the composed element's own native semantics.
- **Accessibility:** `aria-busy` during `loading`; disabled state uses the native `disabled` attribute, not a CSS-only visual disable.
- **Responsive:** no layout variance — a button is not a breakpoint-dependent component.
- **White-label behavior:** `primary` variant renders the tenant's resolved `--color-primary`/`--color-primary-hover` when a tenant theme is active (`lib/theme/resolve-portal-theme.ts`); `destructive` never varies by tenant (structural).
- **Density behavior:** fixed padding regardless of table/page density tier — button density scaling is `DOCUMENTED_ONLY` (not built; no evidence yet that a compact button variant is needed).
- **Anti-patterns:** do not recreate a button with raw `<button className="...">` anywhere a `components/ui/Button` import would do (`09_*.md` §4.2's "one component owner, many consumers").
- **Implementation notes:** Radix `Slot` for `asChild` (`ADR-0005`'s copy-in pattern).

### Banner — `components/ui/banner.tsx` — `IMPLEMENTED`

- **Purpose:** persistent, page-level disclosure (not dismissible, not a toast) — e.g. the Supreme Admin RPD-022 disclosure, a support-mode impersonation notice.
- **When to use:** a condition true for the whole page/session, not a one-time event.
- **When not to use:** transient confirmation (use Toast, `DOCUMENTED_ONLY`) or a single-field validation error (use Form Field, `DOCUMENTED_ONLY`).
- **Anatomy:** left border accent + text content, `role="note"`.
- **Variants:** `info`, `warning`, `success`, `danger` (the last two added this checkpoint — previously only `info`/`warning` existed).
- **Sizes:** one size.
- **States:** static (no interactive state) — a banner is informational only, never itself carries an action button in this primitive (a banner *containing* a Button is a valid composition, not a new variant).
- **Keyboard:** not focusable by itself (correct — `role="note"` is not an interactive landmark); any action inside it (e.g. "Sign in with a different account") is independently focusable/keyboard-reachable.
- **Accessibility:** always renders text content — never color-only (`docs/standards/DESIGN_SYSTEM.md` §2.1's non-color rule, satisfied by construction since `children` is required).
- **Responsive:** full-width, wraps naturally.
- **White-label behavior:** none — border/background colors are semantic tokens, never tenant brand tokens (a banner's tone must never be mistaken for a brand accent).
- **Density behavior:** fixed padding.
- **Anti-patterns:** do not use `warning` tone for a purely informational message that never requires user judgment (dilutes the signal `ADR-0017` §1's "calm by default, vivid only for... warning, or exception" principle protects).

### Badge — `components/ui/badge.tsx` — `IMPLEMENTED`

- **Purpose:** small inline label for counts/tags/non-status metadata.
- **When to use:** a count, a free-form tag, a non-canonical label.
- **When not to use:** canonical business-entity status — use `StatusBadge` instead (a badge has no built-in non-color-only guarantee since its content is caller-supplied free text, which is usually fine for a tag but wrong for status).
- **Anatomy:** pill-shaped inline span.
- **Variants/tones:** `neutral`, `primary` (the only variant allowed to reflect tenant brand — a "primary" badge is a deliberate accent choice, e.g. a "New" tag).
- **Sizes:** one size (`text-xs`).
- **States:** static.
- **Keyboard/accessibility:** inline text content, inherits surrounding reading order; not independently focusable (correct — a badge is not interactive).
- **Responsive:** none.
- **White-label behavior:** `primary` tone uses `--color-primary` at 10% opacity fill + full-opacity text — reflects tenant brand when active.
- **Density behavior:** fixed.
- **Anti-patterns:** do not use `primary` tone for a status-shaped label (color-only status signal risk) — use `StatusBadge`.

### StatusBadge — `components/ui/status-badge.tsx` — `IMPLEMENTED`

- **Purpose:** the canonical status/exception indicator — the presentational half of "a status badge always renders from `canonical_ref`, never a tenant label alone" (`docs/standards/DESIGN_SYSTEM.md` §6).
- **When to use:** any canonical business-entity status (Draft/Submitted/Approved, Open/Assigned/Resolved, etc.) or exception flag.
- **When not to use:** a free-form tag (use `Badge`).
- **Anatomy:** pill-shaped inline span, optional leading icon slot, mandatory text label.
- **Variants/tones:** `success`, `warning`, `danger`, `info`, `neutral` — a closed union over the platform's fixed semantic colors; there is no tenant-brand tone (structurally cannot render a tenant color, `ADR-0017` §2).
- **Sizes:** one size.
- **States:** static.
- **Keyboard:** not focusable (correct).
- **Accessibility:** `label` is a required prop (not optional) — a caller cannot render a color-only `StatusBadge` even by omission; `icon` is additive, never a substitute for `label`.
- **Responsive:** none.
- **White-label behavior:** never varies by tenant (structural — no tenant color path exists in this component).
- **Density behavior:** fixed.
- **Anti-patterns:** do not bind `tone` from a tenant-configurable value; `tone` must always derive from the canonical status/severity, never from tenant preference.
- **Implementation notes:** this component does not itself implement the `canonical_ref`-to-tone mapping (that mapping is domain-specific — e.g. Commercial's lead statuses vs. Ticketing's — and belongs in a future `components/domain/` composition per `09_*.md` §4.1/§4.2, not yet built).

### DataTable — `components/tables/data-table.tsx` — `IMPLEMENTED`

**Implemented by:** CargoGrid UI Modernization checkpoint (2026-07-26) — the first shared table implementation, built against its first two real consumers (`commercial/leads/page.tsx`, `supreme/tenants/page.tsx`) per `09_*.md` §4.2's "one owner, many consumers" rule, replacing each screen's own raw `<table>`.

- **Purpose:** the single shared implementation every list screen's tabular data renders through — "never implement table behavior separately for each module."
- **When to use:** any server-rendered list of rows with a fixed, known column set.
- **When not to use:** a screen needing client-side sort/filter/column-config/row-selection/bulk actions today — those remain `DOCUMENTED_ONLY` (below) since no real consumer has server-side support for them yet; building the UI ahead of a real backing capability would be a speculative abstraction (`AGENTS.md`).
- **Anatomy:** scrollable wrapper (`overflow-x-auto`) + `<table>` with a visually-hidden `<caption>` (required prop — an unlabeled data table has no accessible name), sticky `<thead>`, row-mapped `<tbody>`.
- **Variants:** none — one shape, columns are caller-defined (`DataTableColumn<Row>`: `key`, `header`, optional `align`, `render`).
- **Sizes/Density:** `compact` / `default` / `comfortable`, consuming the platform's existing `--row-height-*` tokens via inline `style` (these tokens have no generated Tailwind utility class, so CSS-custom-property consumption is the correct mechanism, not a new hardcoded pixel value).
- **States:** `Empty` is real and built-in — `rows.length === 0` renders the caller-supplied `emptyMessage` (required, not defaulted, since empty copy is domain-specific per `09_*.md` §5) instead of the table. `Loading` and `Error` remain page-owned, matching every existing screen's own convention (a route `loading.tsx` Suspense boundary; an inline `role="alert"` render before this component) — **not** consolidated into the primitive this checkpoint; named as future work, not overclaimed.
- **Keyboard:** native `<table>`/`<a>`/interactive-cell semantics; no custom keyboard handling added or needed for a non-interactive-row table.
- **Accessibility:** `caption` required; `scope="col"` on every header cell; sticky header only (page-scroll sticky, not a fixed-height virtualized viewport — the wrapper does not set `overflow-y`, so the header sticks against the page's own scroll, not a bounded internal scroll region).
- **Responsive:** horizontal scroll (`overflow-x-auto`) below the table's natural width; no column-priority/collapse behavior yet.
- **White-label behavior:** header/border/text colors are semantic tokens (`--color-surface`, `neutral-*`); no tenant-brand-specific path.
- **Density behavior:** see Sizes above — the only primitive so far to actually consume the density token category (`docs/standards/DESIGN_SYSTEM.md` §2's density row, previously "no primitive consumes these yet").
- **Anti-patterns:** do not hand-roll a `<table>` with Tailwind utility classes in a new screen — import this component. Do not add sort/filter/pagination UI directly inside a `DataTable` consumer's JSX; extend the shared primitive (or `Pagination`, below) instead once a second real need appears.
- **Implementation notes:** generic over `Row`; `rowKey`/`render` are caller functions, not string accessors, so a column can render arbitrary JSX (e.g. a link) without a special-cased "link column" type. Sorting, filtering, grouping, saved views, column visibility/pinning, bulk actions, row selection, export, and virtualization remain `DOCUMENTED_ONLY` in §2 below — this checkpoint's own instruction explicitly named building 60+ primitives speculatively as a pattern to avoid.

### Pagination — `components/tables/pagination.tsx` — `IMPLEMENTED`

**Implemented by:** CargoGrid UI Modernization checkpoint (2026-07-26), alongside `DataTable` — the same two screens are its first real consumers. Both screens previously rendered a static "Page X — Y total" string with no actual prev/next control; this is the first real pagination *control* in the repository (the query-layer offset pagination itself already existed, `supreme/tenants`).

- **Purpose:** the single shared page-number navigation control for server-paginated lists.
- **When to use:** any list using offset pagination (`page`/`pageSize`/`totalCount`).
- **When not to use:** cursor/keyset or infinite-loading pagination — a different, not-yet-built pattern (`04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` §1).
- **Anatomy:** `<nav aria-label="Pagination">` containing Previous/Next controls and a numbered page list with collapsed ellipsis gaps.
- **Variants/sizes:** none.
- **States:** boundary pages render Previous/Next as non-interactive, `aria-disabled="true"` (never a dead link); the current page renders as a non-link `aria-current="page"` element; a single-page result renders nothing (no pagination decision to present).
- **Keyboard:** every actionable page is a real `next/link` anchor — native Tab/Enter navigation, no custom key handling.
- **Accessibility:** landmark `aria-label`, `aria-current="page"` on the active page, `aria-disabled` on boundary controls, ellipsis marked `aria-hidden="true"` (decorative, not a navigable item).
- **Responsive:** wraps (`flex-wrap`) rather than overflowing on narrow viewports.
- **White-label behavior:** current-page fill uses `bg-primary` — reflects tenant brand when active, consistent with `Button`'s primary variant.
- **Density behavior:** fixed padding — not density-tiered (a pagination control is not a data row).
- **Anti-patterns:** do not compute page-number math inline in a page component (`supreme/tenants/page.tsx`'s own prior pattern, now removed) — import this component instead.
- **Implementation notes:** page-window math (which page numbers to show, where to collapse to an ellipsis) is a pure function, `lib/tables/pagination-range.ts`, unit-tested there (`.tsx` files have no test runner in this repository yet, the same reason `lib/theme/resolve-portal-theme.ts` was extracted as plain `.ts`). The component itself takes a caller-supplied `buildHref(page)` function rather than owning a query-string shape — keeps it agnostic to whatever other params (future filters/sort) a given screen's URL carries.

## 2. Full requested catalogue — status summary

Every component this task's own instruction named, with purpose (one line) and status. Components not listed individually above are `DOCUMENTED_ONLY`: a real screen has not needed them yet in this repository (every existing screen is a plain server-rendered table/form using raw HTML elements with Tailwind utility classes reading the semantic tokens directly — functionally correct and token-disciplined, but not yet extracted into a shared primitive per `09_*.md` §4.2's "one owner" rule). Building each of these against a *hypothetical* future screen, with no real consumer to validate the API against, risks exactly the "unresolved placeholder"/"speculative abstraction" pattern `AGENTS.md` and this repository's own coding standards forbid — so the catalogue below is a specification a future capability-driven checkpoint builds against when a real screen needs it, not a batch of speculative components.

| Component | One-line purpose | Status |
|---|---|---|
| Icon button | Icon-only action (row action, toolbar) | `DOCUMENTED_ONLY` — same states/variants as Button, `aria-label` mandatory (no visible text to derive an accessible name from) |
| Button group | Segmented set of mutually exclusive or related actions | `DOCUMENTED_ONLY` |
| Link | Inline/styled navigation, distinct from Button's `asChild` composition | `DOCUMENTED_ONLY` |
| Input | Single-line text entry | `DOCUMENTED_ONLY` — every current form (`admin/users`, `commercial/leads`, etc.) uses a raw `<input>` with token-driven Tailwind classes; extraction is due once a second form needs identical validation-state styling |
| Textarea | Multi-line text entry | `DOCUMENTED_ONLY` |
| Number input | Numeric entry with locale-aware formatting | `DOCUMENTED_ONLY` |
| Currency input | Money entry, always paired with a currency code, never floating point in the underlying value | `DOCUMENTED_ONLY` — the money-as-`numeric`-never-float rule (`AGENTS.md` "Data and finance rules") binds this component's future implementation |
| Password input | Masked entry with reveal toggle | `DOCUMENTED_ONLY` |
| Search input | Debounced, server-side-filtered search trigger (never client-side filter of a large dataset — `09_*.md` §11) | `DOCUMENTED_ONLY` |
| Select | Single-choice dropdown | `DOCUMENTED_ONLY` |
| Combobox | Searchable single-choice, RLS-aware reference picker (`09_*.md` §4.1) | `DOCUMENTED_ONLY` |
| Multi-select | Multiple-choice with chip display | `DOCUMENTED_ONLY` |
| Checkbox | Boolean/multi-select-in-a-set | `DOCUMENTED_ONLY` |
| Radio | Single choice, always-visible set | `DOCUMENTED_ONLY` |
| Switch | Immediate-effect boolean toggle (vs. Checkbox's form-submit-pending boolean) | `DOCUMENTED_ONLY` |
| Date picker | Calendar-backed date entry | `DOCUMENTED_ONLY` |
| Date-range picker | Paired start/end date entry | `DOCUMENTED_ONLY` |
| Time picker | Time-of-day entry | `DOCUMENTED_ONLY` |
| File upload | Async progress, type/size validation, signed-URL preview (never renders a file whose scan status isn't clean, `09_*.md` §4.1) | `BLOCKED` on a storage/upload pipeline — none exists yet (`01_TOKENS_AND_THEME.md` §3.1) |
| Form field | Label + control + help text + error message, one accessible unit | `DOCUMENTED_ONLY` |
| Form section | Grouped fields with a heading, used for long forms' readable-max-width layout | `DOCUMENTED_ONLY` |
| Validation summary | Form-level error list, focus target for "jump to first error" | `DOCUMENTED_ONLY` |
| Alert / Callout | Inline, non-persistent emphasis block (distinct from Banner's page-level persistence) | `DOCUMENTED_ONLY` — `Banner`'s 4-tone set is the closest existing implementation; a true dismissible Alert/Callout is a separate future component |
| Tag | Free-form label, same shape as `Badge` | `IMPLEMENTED` via `Badge` (no separate `Tag` component — same primitive, no duplication) |
| Tooltip | Hover/focus-triggered supplementary text | `DOCUMENTED_ONLY` |
| Popover | Click-triggered floating content | `DOCUMENTED_ONLY` |
| Dropdown menu | Click-triggered action list | `DOCUMENTED_ONLY` |
| Context menu | Right-click action list | `DOCUMENTED_ONLY` |
| Command palette | Keyboard-first global action/search launcher | `DOCUMENTED_ONLY` |
| Tabs | Same-page view switch | `DOCUMENTED_ONLY` |
| Accordion | Collapsible content sections | `DOCUMENTED_ONLY` |
| Card | Bounded content block | `DOCUMENTED_ONLY` — used sparingly by design (`ADR-0017` §1: "avoid turning every section into a card") |
| Metric card / KPI widget | Single-number dashboard tile | `DOCUMENTED_ONLY` |
| Table | Static/simple tabular display | `IMPLEMENTED` — `components/tables/data-table.tsx` (see §1 above); both `commercial/leads` and `supreme/tenants` migrated off their raw `<table>` |
| Data grid | Dense, server-paginated/sortable/filterable operational table with density-tier support (`--row-height-*`) | `IMPLEMENTED` for display + density (`DataTable` above, consumes `--row-height-*`); sort/filter/grouping/saved-views/column-visibility-pinning/bulk-actions/selection/virtualization remain `DOCUMENTED_ONLY` — no current screen has server-side support for any of those yet, per `09_*.md` §4.1's "one owner" rule building ahead of a real consumer is deferred, not attempted |
| Pagination | Page/cursor navigation control | `IMPLEMENTED` (offset case only) — `components/tables/pagination.tsx` + `lib/tables/pagination-range.ts`; both `commercial/leads` and `supreme/tenants` migrated off inline page-number math and a static "Page X" string. Cursor/keyset pagination remains `DOCUMENTED_ONLY`. |
| Filter bar | Explicit-allowlist filter controls (`09_*.md` §4.1, mirrors the server-side allowlist) | `DOCUMENTED_ONLY` |
| Saved views | Named, persisted filter/sort/column configurations | `DOCUMENTED_ONLY` |
| Bulk action bar | Appears on multi-row selection, drives selection-token-based bulk mutation (never thousands of raw IDs from the browser, `09_*.md` §4.1) | `DOCUMENTED_ONLY` |
| Dialog | Modal, focus-trapped | `DOCUMENTED_ONLY` |
| Confirmation dialog | Dialog variant requiring a typed/selected reason for destructive/override actions (`09_*.md` §5's "Destructive confirmation" state) | `DOCUMENTED_ONLY` |
| Drawer | Side-anchored panel, e.g. record detail | `DOCUMENTED_ONLY` |
| Sheet | Same shape as Drawer, mobile-first sizing | `DOCUMENTED_ONLY` |
| Toast | Transient, non-blocking confirmation | `DOCUMENTED_ONLY` |
| Skeleton | Loading placeholder matching known layout | `DOCUMENTED_ONLY` — every route today has a `loading.tsx` file (Next.js Suspense boundary) but no shared skeleton primitive; each currently renders ad hoc |
| Progress | Determinate long-running-operation indicator | `DOCUMENTED_ONLY` |
| Spinner | Indeterminate loading indicator | `DOCUMENTED_ONLY` |
| Empty state | No-data explanation + gated next action (`09_*.md` §5) | `DOCUMENTED_ONLY` — `supreme/tenants/page.tsx` implements this inline; extraction due once a second empty-state screen exists |
| Error state | Human-readable message + request ID + gated retry (`09_*.md` §5) | `DOCUMENTED_ONLY` — same inline-today status as Empty state |
| Permission state | "You do not have access to..." pattern, never leaking hidden data shape (`09_*.md` §5 "Forbidden") | `DOCUMENTED_ONLY` — `admin/layout.tsx`'s denied-state render is the closest existing implementation, inline |
| Avatar | User/entity image or initials | `DOCUMENTED_ONLY` |
| User menu | Account/session actions, top-bar | `DOCUMENTED_ONLY` — no top-bar user menu exists in any layout yet |
| Breadcrumb | Hierarchical location trail | `DOCUMENTED_ONLY` |
| Timeline | Chronological event list (activity, approval, milestone) | `DOCUMENTED_ONLY` |
| Activity item / Audit item | Single timeline entry, before/after value disclosure for Supreme Admin mutations (`09_*.md` §7) | `DOCUMENTED_ONLY` |
| Stepper | Multi-step workflow progress indicator | `DOCUMENTED_ONLY` |
| Kanban board | Drag/status-column view | `DOCUMENTED_ONLY` |
| Calendar | Date-grid scheduling view | `DOCUMENTED_ONLY` |
| Chart wrapper | Dynamically-imported chart with data-table/text-summary accessible alternative (`09_*.md` §9) | `DOCUMENTED_ONLY` |
| Document preview | Signed-URL-gated file preview | `BLOCKED` — same storage-pipeline prerequisite as File upload |
| Attachment list | List of uploaded files with status | `BLOCKED` — same prerequisite |

## 3. Component/state contract (restated, not re-derived)

Every data-bearing component this catalogue eventually builds implements `09_*.md` §5's 11 states (Loading, Empty, Error, Offline, Partial, Unauthorized, Forbidden, Conflict, Success, Retry, Destructive confirmation) — cited here as the binding contract every future `DOCUMENTED_ONLY → IMPLEMENTED` transition must satisfy, not re-derived.
