/**
 * Full shared-component inventory for `/internal/design-system` (CargoGrid UI
 * Modernization checkpoint 3) -- the machine-readable backbone for the showcase's
 * search/category/status filters, and the same facts `docs/design-system/
 * 08_COMPONENT_INVENTORY.md` presents as prose. One source of research, two renderings
 * (code + doc) -- kept consistent by hand at authoring time, not code-generated (a
 * generator would be new tooling built for a one-time need, out of this checkpoint's
 * bounded scope).
 *
 * `status` mirrors `docs/design-system/00_INDEX.md`'s legend exactly:
 * `IMPLEMENTED` (real code, verified this checkpoint or an earlier one),
 * `DOCUMENTED_ONLY` (full/compact spec exists, no code），
 * `BLOCKED` (needs a decision/artifact outside this task's authority),
 * `NOT_NAMED` (this task's own instruction asked for it, but no prior CargoGrid
 * design-system document ever named or scoped it -- disclosed as a gap in the
 * instruction's own request rather than invented from nothing).
 */

export type ComponentCategory =
  | "Layout"
  | "Navigation"
  | "Actions"
  | "Forms"
  | "DataDisplay"
  | "DataEntry"
  | "Feedback"
  | "Overlays"
  | "Tables"
  | "ChartsAndAnalytics"
  | "StatusAndWorkflow"
  | "DomainComponents";

export const CATEGORY_LABELS: Record<ComponentCategory, string> = {
  Layout: "Layout",
  Navigation: "Navigation",
  Actions: "Actions",
  Forms: "Forms",
  DataDisplay: "Data Display",
  DataEntry: "Data Entry",
  Feedback: "Feedback",
  Overlays: "Overlays",
  Tables: "Tables",
  ChartsAndAnalytics: "Charts and Analytics",
  StatusAndWorkflow: "Status and Workflow",
  DomainComponents: "Domain Components",
};

export type ComponentStatus = "IMPLEMENTED" | "DOCUMENTED_ONLY" | "BLOCKED" | "NOT_NAMED";

export interface ComponentEntry {
  readonly name: string;
  readonly category: ComponentCategory;
  readonly status: ComponentStatus;
  readonly purpose: string;
  /** Repo-relative source file, only when `status === "IMPLEMENTED"`. */
  readonly sourceFile?: string;
  /** Copyable `import { ... } from "..."` line, only when `status === "IMPLEMENTED"`. */
  readonly importSnippet?: string;
  readonly variants?: readonly string[];
  readonly sizes?: readonly string[];
  readonly states?: readonly string[];
  /** Repo-relative files that render this component today, empty array means built but unused. */
  readonly consumers?: readonly string[];
  readonly tokensUsed?: readonly string[];
  readonly a11y?: string;
  readonly responsive?: string;
  readonly productionReady: boolean;
  readonly duplicateNote?: string;
  /** Where this status classification comes from, so nothing here is asserted without a citation. */
  readonly citation: string;
}

export const COMPONENT_REGISTRY: readonly ComponentEntry[] = [
  // ---- IMPLEMENTED (6) ----
  {
    name: "Button",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "The single primary-action control every form/toolbar/dialog uses.",
    sourceFile: "components/ui/button.tsx",
    importSnippet: 'import { Button } from "@/components/ui/button.tsx";',
    variants: ["primary", "secondary", "destructive"],
    sizes: ["(one size only — no sm/lg scale exists)"],
    states: ["default", "hover", "focus-visible", "disabled", "loading"],
    consumers: ["39 files across every Commercial form/action-panel and app/(public)/login/page.tsx"],
    tokensUsed: ["--color-primary/-hover", "--color-danger", "--color-neutral-100/200/900", "--radius-md"],
    a11y: "aria-busy while loading; native disabled attribute (not CSS-only); asChild preserves the composed element's own semantics.",
    responsive: "No layout variance — not a breakpoint-dependent component.",
    productionReady: true,
    duplicateNote:
      "No raw <button className=\"...\"> found duplicating this outside components/ui/button.tsx itself — confirmed by grep across app/.",
    citation: "docs/design-system/02_COMPONENTS.md §1",
  },
  {
    name: "Banner",
    category: "Feedback",
    status: "IMPLEMENTED",
    purpose: "Persistent, page-level disclosure (not dismissible, not a toast).",
    sourceFile: "components/ui/banner.tsx",
    importSnippet: 'import { Banner } from "@/components/ui/banner.tsx";',
    variants: ["info", "warning", "success", "danger"],
    sizes: ["(one size)"],
    states: ["static (no interactive state)"],
    consumers: ["app/(supreme)/supreme/layout.tsx (the RPD-022 Supreme Admin disclosure)"],
    tokensUsed: ["--color-info/-warning/-success/-danger"],
    a11y: 'role="note"; always renders required text content, never color-only.',
    responsive: "Full-width, wraps naturally.",
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1",
  },
  {
    name: "Badge",
    category: "DataDisplay",
    status: "IMPLEMENTED",
    purpose: "Small inline label for counts/tags/non-status metadata.",
    sourceFile: "components/ui/badge.tsx",
    importSnippet: 'import { Badge } from "@/components/ui/badge.tsx";',
    variants: ["neutral", "primary"],
    sizes: ["(one size, text-xs)"],
    states: ["static"],
    consumers: [],
    tokensUsed: ["--color-neutral-100/700", "--color-primary"],
    a11y: "Inline text content, inherits reading order; not independently focusable (correct — not interactive).",
    responsive: "None.",
    productionReady: true,
    duplicateNote:
      "Built (CargoGrid Design System Expansion checkpoint) but has zero real consumers today — e.g. Lead.source is still rendered as plain text on the Leads list rather than a Badge. Flagged in the migration map, not silently left inconsistent.",
    citation: "docs/design-system/02_COMPONENTS.md §1; consumer count verified this checkpoint via grep across app/.",
  },
  {
    name: "StatusBadge",
    category: "StatusAndWorkflow",
    status: "IMPLEMENTED",
    purpose: "The canonical status/exception indicator — presentational half of \"a status badge always renders from canonical_ref, never a tenant label alone.\"",
    sourceFile: "components/ui/status-badge.tsx",
    importSnippet: 'import { StatusBadge } from "@/components/ui/status-badge.tsx";',
    variants: ["success", "warning", "danger", "info", "neutral"],
    sizes: ["(one size)"],
    states: ["static"],
    consumers: [],
    tokensUsed: ["--color-success/-warning/-danger/-info", "--color-neutral-100/700"],
    a11y: "label is a required prop — cannot render color-only even by omission.",
    responsive: "None.",
    productionReady: true,
    duplicateNote:
      "Built but has zero real consumers today — e.g. Lead.status and SupremeTenant.canonicalStatus are both rendered as plain text on their real list pages instead of StatusBadge. This is the single highest-priority adoption gap in the whole inventory (StatusBadge exists, is production-ready, and the exact screens that need it already exist) — see the migration map.",
    citation: "docs/design-system/02_COMPONENTS.md §1; consumer count verified this checkpoint via grep across app/.",
  },
  {
    name: "DataTable",
    category: "Tables",
    status: "IMPLEMENTED",
    purpose: "The single shared implementation every list screen's tabular data renders through.",
    sourceFile: "components/tables/data-table.tsx",
    importSnippet: 'import { DataTable, type DataTableColumn } from "@/components/tables/data-table.tsx";',
    variants: ["(column-shape is caller-defined, not a variant enum)"],
    sizes: ["compact", "default", "comfortable (density)"],
    states: ["populated", "empty (built-in)", "Loading/Error remain page-owned, not built into this component"],
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
      "app/(supreme)/supreme/tenants/page.tsx",
    ],
    tokensUsed: ["--row-height-compact/default/comfortable", "--color-surface", "--color-neutral-100/200/600/700"],
    a11y: "Required caption (sr-only); scope=\"col\" on every header cell.",
    responsive: "Horizontal scroll (overflow-x-auto) below natural width; no column-priority/collapse behavior.",
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1 (added checkpoint 2, 2026-07-26)",
  },
  {
    name: "Pagination",
    category: "Tables",
    status: "IMPLEMENTED",
    purpose: "The single shared page-number navigation control for server-paginated lists (offset case only).",
    sourceFile: "components/tables/pagination.tsx",
    importSnippet: 'import { Pagination } from "@/components/tables/pagination.tsx";',
    variants: ["(offset pagination only — no cursor/keyset variant)"],
    sizes: ["(one size)"],
    states: ["default page link", "current page", "disabled (boundary)"],
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
      "app/(supreme)/supreme/tenants/page.tsx",
    ],
    tokensUsed: ["--color-primary", "--color-neutral-100/300/700"],
    a11y: 'aria-label="Pagination"; aria-current="page"; aria-disabled on boundary controls; decorative ellipsis is aria-hidden.',
    responsive: "Wraps (flex-wrap) rather than overflowing on narrow viewports.",
    productionReady: true,
    duplicateNote: "Also satisfies the Navigation category's \"Pagination\" request — lives in components/tables/ because its first two consumers are both tables, not because it is table-specific.",
    citation: "docs/design-system/02_COMPONENTS.md §1 (added checkpoint 2, 2026-07-26)",
  },

  // ---- Actions (DOCUMENTED_ONLY / NOT_NAMED) ----
  { name: "Icon button", category: "Actions", status: "DOCUMENTED_ONLY", purpose: "Icon-only action (row action, toolbar) — same states/variants as Button, mandatory aria-label.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Button group", category: "Actions", status: "DOCUMENTED_ONLY", purpose: "Segmented set of mutually exclusive or related actions.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Link", category: "Actions", status: "DOCUMENTED_ONLY", purpose: "Inline/styled navigation, distinct from Button's asChild composition.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Split Button", category: "Actions", status: "NOT_NAMED", purpose: "Requested by this checkpoint's own instruction, but never named or scoped in docs/design-system/02_COMPONENTS.md's own ~70-item catalogue.", productionReady: false, citation: "Not found in docs/design-system/02_COMPONENTS.md §2 — disclosed gap in the request itself, not fabricated here." },
  { name: "Dropdown Action", category: "Actions", status: "NOT_NAMED", purpose: "Requested by this checkpoint's own instruction, but never named or scoped in docs/design-system/02_COMPONENTS.md's own ~70-item catalogue (closest existing spec: \"Dropdown menu\", classified under Overlays below).", productionReady: false, citation: "Not found in docs/design-system/02_COMPONENTS.md §2 — disclosed gap in the request itself, not fabricated here." },

  // ---- Forms / Data Entry (all DOCUMENTED_ONLY, one BLOCKED) ----
  { name: "Input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Single-line text entry — every current form uses a raw <input> with token-driven Tailwind classes.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Textarea", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Multi-line text entry.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Number input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Numeric entry with locale-aware formatting.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Currency input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Money entry, always paired with a currency code — bound by the money-as-numeric-never-float rule.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Password input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Masked entry with reveal toggle.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Search input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Debounced, server-side-filtered search trigger — never a client-side filter of a large dataset.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Select", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Single-choice dropdown.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Combobox", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Searchable single-choice, RLS-aware reference picker.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Multi-select", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Multiple-choice with chip display.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Checkbox", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Boolean / multi-select-in-a-set.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Radio", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Single choice, always-visible set.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Switch", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Immediate-effect boolean toggle (vs. Checkbox's form-submit-pending boolean).", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Date input", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Calendar-backed date entry (catalogue name: \"Date picker\").", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Date-range picker", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Paired start/end date entry.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Time picker", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Time-of-day entry.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "File upload", category: "DataEntry", status: "BLOCKED", purpose: "Async progress, type/size validation, signed-URL preview.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on a storage/upload pipeline that does not exist yet." },
  { name: "Form field", category: "Forms", status: "DOCUMENTED_ONLY", purpose: "Label + control + help text + error message, one accessible unit.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Form section", category: "Forms", status: "DOCUMENTED_ONLY", purpose: "Grouped fields with a heading, for long forms' readable-max-width layout.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Validation message", category: "Forms", status: "DOCUMENTED_ONLY", purpose: "Form-level error list, focus target for \"jump to first error\" (catalogue name: \"Validation summary\").", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Data Display (DOCUMENTED_ONLY / NOT_NAMED, plus Badge/StatusBadge already listed above) ----
  { name: "Card", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Bounded content block — used sparingly by design (avoid turning every section into a card).", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "KPI Card", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Single-number dashboard tile (catalogue name: \"Metric card / KPI widget\") — the real Commercial Dashboard (COM-158) renders its metrics as lists/tables today, not KPI tiles.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2; verified against app/(tenant)/[tenantSlug]/commercial/dashboard/page.tsx this checkpoint." },
  { name: "Avatar", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "User/entity image or initials.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Tooltip", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Hover/focus-triggered supplementary text.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Description List", category: "DataDisplay", status: "NOT_NAMED", purpose: "Requested by this checkpoint's own instruction, but never named or scoped in docs/design-system/02_COMPONENTS.md's own catalogue.", productionReady: false, citation: "Not found in docs/design-system/02_COMPONENTS.md §2 — disclosed gap in the request itself, not fabricated here." },
  { name: "Stat", category: "DataDisplay", status: "NOT_NAMED", purpose: "Requested by this checkpoint's own instruction, but never named or scoped in docs/design-system/02_COMPONENTS.md's own catalogue (closest existing spec: \"Metric card / KPI widget\", listed above).", productionReady: false, citation: "Not found in docs/design-system/02_COMPONENTS.md §2 — disclosed gap in the request itself, not fabricated here." },
  { name: "Progress", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Determinate long-running-operation indicator.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Timeline", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Chronological event list (activity, approval, milestone) — backend audit logging exists, no UI renders it yet.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2, 04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §1" },
  { name: "Activity Item", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Single timeline entry, before/after value disclosure for Supreme Admin mutations (catalogue name: \"Activity item / Audit item\").", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Accordion", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Collapsible content sections.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Kanban board", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Drag/status-column view.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Calendar", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Date-grid scheduling view.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Document preview", category: "DataDisplay", status: "BLOCKED", purpose: "Signed-URL-gated file preview.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on the same storage pipeline as File upload." },
  { name: "Attachment list", category: "DataDisplay", status: "BLOCKED", purpose: "List of uploaded files with status.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on the same storage pipeline." },

  // ---- Navigation (DOCUMENTED_ONLY, from 02_COMPONENTS.md and 03_LAYOUT_NAVIGATION.md) ----
  { name: "Tabs", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Same-page view switch — no record-detail page has secondary navigation yet.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2; 03_LAYOUT_NAVIGATION.md §1" },
  { name: "Breadcrumbs", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Hierarchical location trail.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2; 03_LAYOUT_NAVIGATION.md §1" },
  { name: "Sidebar item", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Both real portals (Supreme, Tenant Admin/Commercial) use a flat top-bar link list today — no sidebar exists at all (appropriate at ≤2 top-level destinations per portal).", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1" },
  { name: "Navigation group", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Grouped/collapsible navigation sections — no sidebar exists yet for a group to belong to.", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1" },
  { name: "Dropdown menu", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Click-triggered action list.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Command menu", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Keyboard-first global action/search launcher (catalogue name: \"Command palette\").", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Page header", category: "Layout", status: "DOCUMENTED_ONLY", purpose: "Record-detail page header (title, status, primary actions) — each detail page renders its own ad hoc header today (catalogue name: \"Workspace header\").", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1" },
  { name: "Context menu", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Right-click action list.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Persistent top bar", category: "Layout", status: "DOCUMENTED_ONLY", purpose: "Portal name, primary nav, org-context selector, global search, notifications, user menu — both real layouts render a minimal 2-link header today, none of the rest.", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1" },
  { name: "User menu", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Account/session actions, top-bar — no top-bar user menu exists in any layout yet.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Feedback (remaining, from 02_COMPONENTS.md) ----
  { name: "Alert", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Inline, non-persistent emphasis block, distinct from Banner's page-level persistence (catalogue name: \"Alert / Callout\"). Banner's 4-tone set is the closest existing implementation.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Toast", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Transient, non-blocking confirmation.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Skeleton", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Loading placeholder matching known layout — every route has a loading.tsx (Next Suspense boundary) but each hand-rolls its own skeleton markup; no shared primitive exists.", productionReady: false, duplicateNote: "27 separate loading.tsx files each hand-roll near-identical animate-pulse bars — the clearest duplication case in this inventory. See the migration map.", citation: "docs/design-system/02_COMPONENTS.md §2; duplication verified this checkpoint via grep across app/." },
  { name: "Spinner", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Indeterminate loading indicator.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Empty State", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "No-data explanation + gated next action — every list page implements this inline today (DataTable's own built-in empty message is the first step toward consolidating it, but it takes a plain string/node, not a full Empty State component with illustration/actions).", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Error State", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Human-readable message + request ID + gated retry — every page implements this inline today as a role=\"alert\" block with no retry action.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Success State", category: "Feedback", status: "NOT_NAMED", purpose: "Requested by this checkpoint's own instruction, but never named or scoped in docs/design-system/02_COMPONENTS.md's own catalogue as a distinct component (a Banner success variant and a StatusBadge success tone both exist; a dedicated full-page \"Success State\" pattern does not).", productionReady: false, citation: "Not found in docs/design-system/02_COMPONENTS.md §2 — disclosed gap in the request itself, not fabricated here." },
  { name: "Progress Indicator", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "Same as Progress above — listed separately in this checkpoint's own instruction under both Data Display and Feedback.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Permission state", category: "Feedback", status: "DOCUMENTED_ONLY", purpose: "\"You do not have access to...\" pattern, never leaking hidden data shape — admin/layout.tsx's denied-state render is the closest existing implementation, inline.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Overlays (remaining) ----
  { name: "Dialog", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Modal, focus-trapped.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Confirmation Dialog", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Dialog variant requiring a typed/selected reason for destructive/override actions.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Drawer", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Side-anchored panel, e.g. record detail.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Sheet", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Same shape as Drawer, mobile-first sizing.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Popover", category: "Overlays", status: "DOCUMENTED_ONLY", purpose: "Click-triggered floating content.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Tables (remaining) ----
  { name: "Filter bar", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Explicit-allowlist filter controls, mirrors the server-side allowlist — not yet built on any screen.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2; 04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §1" },
  { name: "Saved views", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Named, persisted filter/sort/column configurations.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Bulk action bar", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Appears on multi-row selection, drives a selection-token-based bulk mutation — no bulk mutation exists in this repository yet.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Charts and Analytics ----
  { name: "Chart wrapper", category: "ChartsAndAnalytics", status: "DOCUMENTED_ONLY", purpose: "Dynamically-imported chart with a data-table/text-summary accessible alternative — no chart library dependency exists anywhere in package.json, and the real Commercial Dashboard (COM-158) renders its metrics as buckets/lists, not charts.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2; verified against package.json and app/(tenant)/[tenantSlug]/commercial/dashboard/page.tsx this checkpoint." },

  // ---- Status and Workflow (remaining) ----
  { name: "Stepper", category: "StatusAndWorkflow", status: "DOCUMENTED_ONLY", purpose: "Multi-step workflow progress indicator.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },
  { name: "Approval queue", category: "StatusAndWorkflow", status: "DOCUMENTED_ONLY", purpose: "Renders the approval-decision/exception catalogue — backend approval engine exists (07_CONFIGURATION_ENGINE_WORKSTREAM.md); no queue UI exists yet (commercial/approvals/page.tsx is a plain list, not a queue pattern).", productionReady: false, citation: "docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §2" },

  // ---- Domain Components ----
  {
    name: "Approval Decision Panel",
    category: "DomainComponents",
    status: "DOCUMENTED_ONLY",
    purpose: "Shared Approve/Reject/Reopen/Cancel panel every workflow's decision step would render through — today each capability (quotation approval, credit approval, margin-rule approval) hand-rolls its own decision form.",
    productionReady: false,
    duplicateNote:
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/approval-decision-form.tsx and app/(tenant)/[tenantSlug]/commercial/accounts/[accountId]/credit-approval-decision-form.tsx are two independently-built forms doing the same decision-panel job. Candidate for extraction once a third consumer appears — see the migration map.",
    citation: "docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §2; components/domain/ does not exist yet (confirmed empty this checkpoint).",
  },
  {
    name: "Canonical status-to-tone mapping",
    category: "DomainComponents",
    status: "DOCUMENTED_ONLY",
    purpose: "The domain-specific composition that maps a canonical_ref (Lead status, Opportunity stage, Quotation status, etc.) to a StatusBadge tone — StatusBadge itself deliberately does not implement this mapping (it is domain-specific, per its own \"one owner\" scoping note).",
    productionReady: false,
    citation: "docs/design-system/02_COMPONENTS.md §1 (StatusBadge implementation notes)",
  },
] as const;
