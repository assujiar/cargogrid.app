# Component Catalogue

**Updated by:** CargoGrid UI Modernization checkpoint 2 (2026-07-26, out-of-band, see `07_GAP_ANALYSIS_AND_ROADMAP.md` §8) — added `DataTable`/`Pagination` as `IMPLEMENTED` (roadmap item 3). **Updated again by checkpoint 4** (`07_GAP_ANALYSIS_AND_ROADMAP.md` §10) — ~40 further entries in §2's table flipped to `IMPLEMENTED`; §1's full-spec treatment below still covers only the original 6 primitives plus the two checkpoint-2 additions in detail (Button/Banner/Badge/StatusBadge/DataTable/Pagination) — the ~40 checkpoint-4 additions get §2's one-line-plus-status treatment and a real, working implementation, not (yet) the full 10-field spec shape this file's own convention calls for; `docs/design-system/08_COMPONENT_INVENTORY.md` §1 carries the fuller per-field detail (variants/states/a11y/tokens/consumers) for every one of them. Original authoring below (CargoGrid Design System Expansion, 2026-07-24) preserved as-is except the specific rows/sections each update touches.

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

**Updated checkpoint 4 (2026-07-26):** ~40 entries below flipped from `DOCUMENTED_ONLY`/un-named to `IMPLEMENTED` — full detail in `07_GAP_ANALYSIS_AND_ROADMAP.md` §10 and `08_COMPONENT_INVENTORY.md` §2 (updated). Every one was built against the Radix primitives already a `radix-ui` dependency (`ADR-0005`'s copy-in mechanism) or as plain native-HTML server-safe components — zero new npm dependencies added. What's still not built, and why, is named per-row below rather than left silently blank: a handful of items (Time picker, File upload, Document preview/Attachment list, Kanban board, Calendar, Chart wrapper, Filter bar/Saved views/Bulk action bar, Stepper, Approval queue, Sidebar/Navigation group/Page header/Persistent top bar) remain `DOCUMENTED_ONLY`/`BLOCKED` because each needs either a missing storage pipeline, a new dependency decision, a real consumer that doesn't exist yet, or an actual shell redesign — not because building more components ran out of time.

| Component | One-line purpose | Status |
|---|---|---|
| Icon button | Icon-only action (row action, toolbar) | `IMPLEMENTED` — `components/ui/icon-button.tsx`, same variants/states as Button, `aria-label` mandatory |
| Button group | Segmented set of mutually exclusive or related actions | `IMPLEMENTED` — `components/ui/button-group.tsx` |
| Link | Inline/styled navigation, distinct from Button's `asChild` composition | `IMPLEMENTED` — `components/ui/link.tsx` |
| Split Button | Primary action + caret trigger opening secondary actions | `IMPLEMENTED` — `components/ui/split-button.tsx`. Not named in this catalogue before a later checkpoint's own instruction requested it; disclosed then built, not silently invented. |
| Dropdown Action | A single button that itself triggers a dropdown action list | `IMPLEMENTED` — `components/ui/dropdown-action.tsx`. Same not-previously-named disclosure as Split Button. |
| Input | Single-line text entry | `IMPLEMENTED` — `components/forms/input.tsx`, styled to match every existing raw `<input>` exactly; 39 forms remain unmigrated (migration map) |
| Textarea | Multi-line text entry | `IMPLEMENTED` — `components/forms/textarea.tsx` |
| Number input | Numeric entry with locale-aware formatting | `IMPLEMENTED` — `components/forms/number-input.tsx` (a `type="number"` specialization of Input; no locale-aware formatting layer added) |
| Currency input | Money entry, always paired with a currency code, never floating point in the underlying value | `IMPLEMENTED` — `components/forms/currency-input.tsx`, bound to a `numeric`-shaped string (the money-as-`numeric`-never-float rule, `AGENTS.md`) |
| Password input | Masked entry with reveal toggle | `IMPLEMENTED` — `components/forms/password-input.tsx` |
| Search input | Debounced, server-side-filtered search trigger (never client-side filter of a large dataset — `09_*.md` §11) | `IMPLEMENTED` for the field's appearance (`components/forms/search-input.tsx`) — debouncing/server-side wiring remains the caller's own responsibility, this component does not fetch |
| Select | Single-choice dropdown | `IMPLEMENTED` — `components/forms/select.tsx`, native `<select>` matching existing styling |
| Combobox | Searchable single-choice, RLS-aware reference picker (`09_*.md` §4.1) | `IMPLEMENTED` — `components/forms/combobox.tsx`, hand-implemented WAI-ARIA combobox pattern (no Radix Combobox exists) |
| Multi-select | Multiple-choice with chip display | `IMPLEMENTED` — `components/forms/multi-select.tsx` |
| Checkbox | Boolean/multi-select-in-a-set | `IMPLEMENTED` — `components/forms/checkbox.tsx` |
| Radio | Single choice, always-visible set | `IMPLEMENTED` — `components/forms/radio.tsx` (`Radio` + `RadioGroup`) |
| Switch | Immediate-effect boolean toggle (vs. Checkbox's form-submit-pending boolean) | `IMPLEMENTED` — `components/forms/switch.tsx`, pure-CSS track/thumb, zero client JS |
| Date picker | Calendar-backed date entry | `IMPLEMENTED` — `components/forms/date-input.tsx` (`DateInput`), native `<input type="date">`, not a custom calendar popover |
| Date-range picker | Paired start/end date entry | `IMPLEMENTED` — `components/forms/date-input.tsx` (`DateRangeInput`) |
| Time picker | Time-of-day entry | `DOCUMENTED_ONLY` — not built checkpoint 4; no real consumer named it |
| File upload | Async progress, type/size validation, signed-URL preview (never renders a file whose scan status isn't clean, `09_*.md` §4.1) | `BLOCKED` on a storage/upload pipeline — none exists yet (`01_TOKENS_AND_THEME.md` §3.1) |
| Form field | Label + control + help text + error message, one accessible unit | `IMPLEMENTED` — `components/forms/form-field.tsx` |
| Form section | Grouped fields with a heading, used for long forms' readable-max-width layout | `IMPLEMENTED` — `components/forms/form-section.tsx` |
| Validation summary | Form-level error list, focus target for "jump to first error" | `IMPLEMENTED` — `components/forms/validation-message.tsx` (`ValidationMessage` field-level, `ValidationSummary` form-level) |
| Alert / Callout | Inline, non-persistent emphasis block (distinct from Banner's page-level persistence) | `IMPLEMENTED` — `components/ui/alert.tsx`, dismissible (local state) |
| Tag | Free-form label, same shape as `Badge` | `IMPLEMENTED` via `Badge` (no separate `Tag` component — same primitive, no duplication) |
| Tooltip | Hover/focus-triggered supplementary text | `IMPLEMENTED` — `components/ui/tooltip.tsx`, built on Radix Tooltip |
| Popover | Click-triggered floating content | `IMPLEMENTED` — `components/ui/popover.tsx`, built on Radix Popover |
| Dropdown menu | Click-triggered action list | `IMPLEMENTED` — `components/ui/dropdown-menu.tsx`, built on Radix DropdownMenu |
| Context menu | Right-click action list | `IMPLEMENTED` — `components/ui/context-menu.tsx`, built on Radix ContextMenu |
| Command palette | Keyboard-first global action/search launcher | `IMPLEMENTED` — `components/ui/command-menu.tsx` (Cmd/Ctrl+K), built on Radix Dialog + a plain filtered list, not the `cmdk` package (not a dependency) |
| Tabs | Same-page view switch | `IMPLEMENTED` — `components/ui/tabs.tsx`, built on Radix Tabs |
| Accordion | Collapsible content sections | `IMPLEMENTED` — `components/ui/accordion.tsx`, native `<details>`/`<summary>`, zero client JS |
| Card | Bounded content block | `IMPLEMENTED` — `components/ui/card.tsx` — used sparingly by design (`ADR-0017` §1: "avoid turning every section into a card") |
| Metric card / KPI widget | Single-number dashboard tile | `IMPLEMENTED` — `components/ui/kpi-card.tsx`; no real dashboard consumes it yet (`commercial/dashboard` renders buckets/lists) |
| Description List | Label/value pairs | `IMPLEMENTED` — `components/ui/description-list.tsx`. Not named in this catalogue before a later checkpoint's own instruction requested it; disclosed then built. |
| Stat | Bare label/value pair (inline counterpart to KPI Card) | `IMPLEMENTED` — `components/ui/stat.tsx`. Same not-previously-named disclosure. |
| Table | Static/simple tabular display | `IMPLEMENTED` — `components/tables/data-table.tsx` (see §1 above); both `commercial/leads` and `supreme/tenants` migrated off their raw `<table>` |
| Data grid | Dense, server-paginated/sortable/filterable operational table with density-tier support (`--row-height-*`) | `IMPLEMENTED` for display + density (`DataTable` above, consumes `--row-height-*`); sort/filter/grouping/saved-views/column-visibility-pinning/bulk-actions/selection/virtualization remain `DOCUMENTED_ONLY` — no current screen has server-side support for any of those yet |
| Pagination | Page/cursor navigation control | `IMPLEMENTED` (offset case only) — `components/tables/pagination.tsx` + `lib/tables/pagination-range.ts`; both `commercial/leads` and `supreme/tenants` migrated off inline page-number math. Cursor/keyset pagination remains `DOCUMENTED_ONLY`. |
| Filter bar | Explicit-allowlist filter controls (`09_*.md` §4.1, mirrors the server-side allowlist) | `DOCUMENTED_ONLY` — no real screen has server-side filter support to build against yet |
| Saved views | Named, persisted filter/sort/column configurations | `DOCUMENTED_ONLY` — depends on Filter bar/sorting existing first |
| Bulk action bar | Appears on multi-row selection, drives selection-token-based bulk mutation (never thousands of raw IDs from the browser, `09_*.md` §4.1) | `DOCUMENTED_ONLY` — no bulk mutation exists in this repository yet |
| Dialog | Modal, focus-trapped | `IMPLEMENTED` — `components/ui/dialog.tsx`, built on Radix Dialog |
| Confirmation dialog | Dialog variant requiring a typed/selected reason for destructive/override actions (`09_*.md` §5's "Destructive confirmation" state) | `IMPLEMENTED` — `components/ui/dialog.tsx` (`ConfirmationDialog`), requires an explicit confirm click |
| Drawer | Side-anchored panel, e.g. record detail | `IMPLEMENTED` — `components/ui/drawer.tsx`, built on Radix Dialog positioned as a side panel (no slide-in transition — `tailwindcss-animate` is not a dependency) |
| Sheet | Same shape as Drawer, mobile-first sizing | `IMPLEMENTED` via `Drawer` (`side="bottom"`) — the spec's own "same shape as Drawer" is literal, not a separate component |
| Toast | Transient, non-blocking confirmation | `IMPLEMENTED` — `components/ui/toast.tsx`, built on Radix Toast (`ToastProvider` + `useToast()`) |
| Skeleton | Loading placeholder matching known layout | `IMPLEMENTED` — `components/ui/skeleton.tsx` (`Skeleton`/`SkeletonText`/`SkeletonTable`); the 27 existing `loading.tsx` files still hand-roll their own bars, unmigrated (migration map) |
| Progress | Determinate long-running-operation indicator | `IMPLEMENTED` — `components/ui/progress.tsx`, native `<progress>` |
| Spinner | Indeterminate loading indicator | `IMPLEMENTED` — `components/ui/spinner.tsx`; `docs/standards/DESIGN_SYSTEM.md`'s own identity statement still says prefer Skeleton |
| Empty state | No-data explanation + gated next action (`09_*.md` §5) | `IMPLEMENTED` — `components/ui/empty-state.tsx`; existing list pages' inline empty text remains unmigrated (migration map) |
| Error state | Human-readable message + request ID + gated retry (`09_*.md` §5) | `IMPLEMENTED` — `components/ui/error-state.tsx`; existing pages' inline `role="alert"` blocks remain unmigrated (migration map) |
| Success state | Whole-page/whole-section confirmation | `IMPLEMENTED` — `components/ui/success-state.tsx`. Not named in this catalogue before a later checkpoint's own instruction requested it; disclosed then built. |
| Permission state | "You do not have access to..." pattern, never leaking hidden data shape (`09_*.md` §5 "Forbidden") | `IMPLEMENTED` — `components/ui/permission-state.tsx` |
| Avatar | User/entity image or initials | `IMPLEMENTED` — `components/ui/avatar.tsx`, built on Radix Avatar (automatic image-load-failure fallback) |
| User menu | Account/session actions, top-bar | `IMPLEMENTED` — `components/ui/user-menu.tsx` (Avatar + DropdownMenu composition); no real layout has adopted it into its top bar yet |
| Breadcrumb | Hierarchical location trail | `IMPLEMENTED` — `components/ui/breadcrumb.tsx` |
| Timeline | Chronological event list (activity, approval, milestone) | `IMPLEMENTED` — `components/ui/timeline.tsx` |
| Activity item / Audit item | Single timeline entry, before/after value disclosure for Supreme Admin mutations (`09_*.md` §7) | `IMPLEMENTED` — `components/ui/timeline.tsx` (`ActivityItem`) |
| Stepper | Multi-step workflow progress indicator | `DOCUMENTED_ONLY` — no multi-step form exists anywhere in this repository yet to build the right shape against |
| Kanban board | Drag/status-column view | `DOCUMENTED_ONLY` — needs a drag-and-drop dependency and a real consumer/data model; not attempted checkpoint 4 |
| Calendar | Date-grid scheduling view | `DOCUMENTED_ONLY` — `DateInput`/`DateRangeInput` cover the entry use case; a full scheduling grid has no real consumer yet |
| Chart wrapper | Dynamically-imported chart with data-table/text-summary accessible alternative (`09_*.md` §9) | `DOCUMENTED_ONLY` — deliberately not built: adding a chart library is a real dependency/bundle-size/license decision outside a component-build checkpoint's authority to make unilaterally |
| Document preview | Signed-URL-gated file preview | `BLOCKED` — same storage-pipeline prerequisite as File upload |
| Attachment list | List of uploaded files with status | `BLOCKED` — same prerequisite |
| Sidebar item / Navigation group / Page header / Persistent top bar | Application-shell navigation elements | `DOCUMENTED_ONLY` — `03_LAYOUT_NAVIGATION.md` §1; both real portals still use a flat 2-link top bar, appropriate at their current page count — these need an actual shell redesign, not a single component in isolation |
| Approval Decision Panel | Shared Approve/Reject panel (`04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` §2) | `IMPLEMENTED` — `components/domain/approval-decision-panel.tsx`; not yet wired into the two existing duplicate forms it would replace (migration map) |
| Canonical status-to-tone mapping | Domain-specific `canonical_ref` → `StatusBadge` tone binding | `IMPLEMENTED` — `components/domain/status-tone-map.ts`; unblocked `StatusBadge`'s zero-consumer gap, migrated onto `commercial/leads`/`supreme/tenants` |
| Approval queue / Exception queue | Renders the approval-decision/exception catalogue as a queue | `DOCUMENTED_ONLY` — `commercial/approvals/page.tsx` is a plain list today, not a queue pattern |

## 3. Component/state contract (restated, not re-derived)

Every data-bearing component this catalogue eventually builds implements `09_*.md` §5's 11 states (Loading, Empty, Error, Offline, Partial, Unauthorized, Forbidden, Conflict, Success, Retry, Destructive confirmation) — cited here as the binding contract every future `DOCUMENTED_ONLY → IMPLEMENTED` transition must satisfy, not re-derived.
