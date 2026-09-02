/**
 * Full shared-component inventory for `/internal/design-system` (checkpoint 3, updated
 * checkpoint 4) -- the machine-readable backbone for the showcase's search/category/
 * status filters, and the same facts `docs/design-system/08_COMPONENT_INVENTORY.md`
 * presents as prose. One source of research, two renderings (code + doc) -- kept
 * consistent by hand at authoring time, not code-generated (a generator would be new
 * tooling built for a one-time need, out of this checkpoint's bounded scope).
 *
 * `status` mirrors `docs/design-system/00_INDEX.md`'s legend exactly:
 * `IMPLEMENTED` (real code, verified this checkpoint or an earlier one),
 * `DOCUMENTED_ONLY` (full/compact spec exists, no code),
 * `BLOCKED` (needs a decision/artifact outside this task's authority),
 * `NOT_NAMED` (a checkpoint's own instruction asked for it, but no prior CargoGrid
 * design-system document ever named or scoped it -- disclosed as a gap in the
 * instruction's own request rather than invented from nothing).
 *
 * Checkpoint 4 (2026-07-26) flipped ~40 entries from `DOCUMENTED_ONLY`/`NOT_NAMED` to
 * `IMPLEMENTED` -- see `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` §10 for the
 * full narrative. Checkpoint 5 (2026-07-26) built the CargoGrid Chart System (Apache
 * ECharts) -- `Chart`/`ChartCard` plus 3 real presets (Trend/Comparison Bar/Donut),
 * `docs/design-system/09_CHARTS.md`. A handful of items remain deliberately not built:
 * Time picker, File upload (blocked), Document preview/Attachment list (blocked),
 * Kanban board, Calendar, 8 further chart presets (stacked bar/funnel/waterfall/gauge/
 * calendar-heatmap/Sankey/map/scatter -- no real consumer/data model for any of them
 * yet), Filter bar/Saved views/Bulk action bar (no server-side support to build
 * against), Stepper, Approval queue, and the layout-level Sidebar/Navigation group/
 * Page header/Persistent top bar items (need an actual shell redesign, not a single
 * component).
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

const CHECKPOINT_4_CITATION = "docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md §10 (checkpoint 4, 2026-07-26)";

export const COMPONENT_REGISTRY: readonly ComponentEntry[] = [
  // ---- Actions ----
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
    citation: "docs/design-system/02_COMPONENTS.md §1",
  },
  {
    name: "Icon button",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "Icon-only action (row action, toolbar) — same variants/states as Button.",
    sourceFile: "components/ui/icon-button.tsx",
    importSnippet: 'import { IconButton } from "@/components/ui/icon-button.tsx";',
    variants: ["primary", "secondary", "destructive"],
    states: ["default", "hover", "focus-visible", "disabled"],
    consumers: [],
    a11y: "label prop is required (not optional), becomes aria-label — no visible text to derive an accessible name from otherwise.",
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Button group",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "A segmented set of mutually exclusive or related actions, joined into one visual control.",
    sourceFile: "components/ui/button-group.tsx",
    importSnippet: 'import { ButtonGroup } from "@/components/ui/button-group.tsx";',
    consumers: ["components/ui/split-button.tsx"],
    a11y: 'role="group" with a required label.',
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Link",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "Inline/styled navigation, distinct from Button's asChild composition (this looks like a link, asChild makes a link look like a button).",
    sourceFile: "components/ui/link.tsx",
    importSnippet: 'import { Link } from "@/components/ui/link.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Split Button",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "A primary action button plus an adjacent caret trigger opening a menu of secondary actions.",
    sourceFile: "components/ui/split-button.tsx",
    importSnippet: 'import { SplitButton } from "@/components/ui/split-button.tsx";',
    consumers: [],
    productionReady: true,
    citation: "Not previously named in any CargoGrid design-system document — disclosed as a gap when first requested, then implemented. " + CHECKPOINT_4_CITATION,
  },
  {
    name: "Dropdown Action",
    category: "Actions",
    status: "IMPLEMENTED",
    purpose: "A single button that itself triggers a dropdown action list — a named preset over DropdownMenu.",
    sourceFile: "components/ui/dropdown-action.tsx",
    importSnippet: 'import { DropdownAction } from "@/components/ui/dropdown-action.tsx";',
    consumers: [],
    productionReady: true,
    citation: "Not previously named in any CargoGrid design-system document — disclosed as a gap when first requested, then implemented. " + CHECKPOINT_4_CITATION,
  },

  // ---- Data Entry ----
  {
    name: "Input",
    category: "DataEntry",
    status: "IMPLEMENTED",
    purpose: "Single-line text entry, matching every existing form's own raw <input> styling exactly.",
    sourceFile: "components/forms/input.tsx",
    importSnippet: 'import { Input } from "@/components/forms/input.tsx";',
    states: ["default", "focus-visible", "disabled", "read-only", "invalid"],
    consumers: [
      "26 Commercial form/action-panel files — checkpoint 8, 2026-07-27, every raw <input> using the unmodified standard className. Full list: docs/runtime/CHANGE_MANIFEST.md CHG-2026-099.",
    ],
    a11y: "aria-invalid set from the invalid prop.",
    productionReady: true,
    duplicateNote: "Every <input> carrying an extra width utility class alongside the standard one (add-line-form.tsx, terms-form.tsx, calculate-margin-form.tsx, add-component-form.tsx, select-rate-form.tsx, override-form.tsx), plus every raw checkbox/radio <input>, remain unmigrated by design — see the migration map's own risk note.",
    citation: CHECKPOINT_4_CITATION + "; 26 consumers migrated checkpoint 8, 2026-07-27",
  },
  { name: "Textarea", category: "DataEntry", status: "IMPLEMENTED", purpose: "Multi-line text entry, same states as Input.", sourceFile: "components/forms/textarea.tsx", importSnippet: 'import { Textarea } from "@/components/forms/textarea.tsx";', consumers: ["components/domain/approval-decision-panel.tsx", "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/terms-form.tsx (checkpoint 8, 2026-07-27)"], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Number input", category: "DataEntry", status: "IMPLEMENTED", purpose: "type=\"number\" specialization of Input — never used for money (see Currency input).", sourceFile: "components/forms/number-input.tsx", importSnippet: 'import { NumberInput } from "@/components/forms/number-input.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Currency input",
    category: "DataEntry",
    status: "IMPLEMENTED",
    purpose: "Money entry bound to a numeric-shaped string (never a JS number) plus its currency code.",
    sourceFile: "components/forms/currency-input.tsx",
    importSnippet: 'import { CurrencyInput } from "@/components/forms/currency-input.tsx";',
    consumers: [],
    a11y: "Sanitizes keystrokes to at most 2 decimal places; aria-invalid from the invalid prop.",
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Password input", category: "DataEntry", status: "IMPLEMENTED", purpose: "Masked entry with a reveal toggle.", sourceFile: "components/forms/password-input.tsx", importSnippet: 'import { PasswordInput } from "@/components/forms/password-input.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Search input", category: "DataEntry", status: "IMPLEMENTED", purpose: "type=\"search\" field appearance only — does not itself debounce or filter; server-side search remains the caller's responsibility.", sourceFile: "components/forms/search-input.tsx", importSnippet: 'import { SearchInput } from "@/components/forms/search-input.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Select",
    category: "DataEntry",
    status: "IMPLEMENTED",
    purpose: "Single-choice dropdown for a small, known, static option list — native <select>, matching every existing form's own styling.",
    sourceFile: "components/forms/select.tsx",
    importSnippet: 'import { Select } from "@/components/forms/select.tsx";',
    consumers: [
      "commercial/costing-requests/[requestId]/{calculate-margin-form,costing-request-actions-panel,select-rate-form}.tsx",
      "commercial/opportunities/[opportunityId]/opportunity-actions-panel.tsx",
      "commercial/pipeline/[planId]/plan-actions-panel.tsx",
      "commercial/quotations/[quotationId]/{add-line-form,terms-form}.tsx",
      "(all checkpoint 8, 2026-07-27)",
    ],
    productionReady: true,
    duplicateNote: "The two <select>s carrying an extra width utility class alongside the standard one (add-line-form.tsx's line-type picker, activity-timeline.tsx's both selects) remain unmigrated by design — see the migration map's own risk note.",
    citation: CHECKPOINT_4_CITATION + "; 8 consumers migrated checkpoint 8, 2026-07-27",
  },
  {
    name: "Combobox",
    category: "DataEntry",
    status: "IMPLEMENTED",
    purpose: "Searchable single-choice picker, WAI-ARIA combobox pattern implemented by hand (no Radix Combobox exists).",
    sourceFile: "components/forms/combobox.tsx",
    importSnippet: 'import { Combobox } from "@/components/forms/combobox.tsx";',
    a11y: "role=\"combobox\", aria-expanded, aria-controls, aria-activedescendant; Up/Down/Enter/Escape keyboard support.",
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Multi-select", category: "DataEntry", status: "IMPLEMENTED", purpose: "Multiple-choice with chip display, same filtered-list pattern as Combobox.", sourceFile: "components/forms/multi-select.tsx", importSnippet: 'import { MultiSelect } from "@/components/forms/multi-select.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Checkbox", category: "DataEntry", status: "IMPLEMENTED", purpose: "Boolean / multi-select-in-a-set — native <input type=\"checkbox\">, label required.", sourceFile: "components/forms/checkbox.tsx", importSnippet: 'import { Checkbox } from "@/components/forms/checkbox.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Radio", category: "DataEntry", status: "IMPLEMENTED", purpose: "Single choice, always-visible set — native <input type=\"radio\">; RadioGroup renders a labeled fieldset.", sourceFile: "components/forms/radio.tsx", importSnippet: 'import { Radio, RadioGroup } from "@/components/forms/radio.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Switch",
    category: "DataEntry",
    status: "IMPLEMENTED",
    purpose: "Immediate-effect boolean toggle — pure CSS track/thumb over a native checkbox, zero client JS.",
    sourceFile: "components/forms/switch.tsx",
    importSnippet: 'import { Switch } from "@/components/forms/switch.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Date input", category: "DataEntry", status: "IMPLEMENTED", purpose: "Calendar-backed date entry via native <input type=\"date\"> (catalogue name: \"Date picker\") — not a custom popover calendar.", sourceFile: "components/forms/date-input.tsx", importSnippet: 'import { DateInput } from "@/components/forms/date-input.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Date-range picker", category: "DataEntry", status: "IMPLEMENTED", purpose: "Paired start/end DateInputs with mutual min/max constraints.", sourceFile: "components/forms/date-input.tsx", importSnippet: 'import { DateRangeInput } from "@/components/forms/date-input.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Time picker", category: "DataEntry", status: "DOCUMENTED_ONLY", purpose: "Time-of-day entry.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — not built this checkpoint (no real consumer named it)." },
  { name: "File upload", category: "DataEntry", status: "BLOCKED", purpose: "Async progress, type/size validation, signed-URL preview.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on a storage/upload pipeline that does not exist yet." },

  // ---- Forms ----
  {
    name: "Form field",
    category: "Forms",
    status: "IMPLEMENTED",
    purpose: "Label + control + help text + error message, one accessible unit.",
    sourceFile: "components/forms/form-field.tsx",
    importSnippet: 'import { FormField } from "@/components/forms/form-field.tsx";',
    consumers: ["components/domain/approval-decision-panel.tsx"],
    a11y: "Renders required-indicator, help-text id, and error id explicitly; caller wires the control's aria-describedby via the exported formFieldDescribedBy helper.",
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Form section", category: "Forms", status: "IMPLEMENTED", purpose: "Grouped fields with a heading, at a readable max-width.", sourceFile: "components/forms/form-section.tsx", importSnippet: 'import { FormSection } from "@/components/forms/form-section.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Validation message",
    category: "Forms",
    status: "IMPLEMENTED",
    purpose: "Field-level error text (rendered automatically by FormField); ValidationSummary is the form-level list with a focus target.",
    sourceFile: "components/forms/validation-message.tsx",
    importSnippet: 'import { ValidationMessage, ValidationSummary } from "@/components/forms/validation-message.tsx";',
    consumers: ["components/forms/form-field.tsx"],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },

  // ---- Data Display ----
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
    consumers: ["app/(tenant)/[tenantSlug]/commercial/leads/page.tsx (source column, checkpoint 4)"],
    tokensUsed: ["--color-neutral-100/700", "--color-primary"],
    a11y: "Inline text content, inherits reading order; not independently focusable (correct — not interactive).",
    responsive: "None.",
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1; migrated onto its first real consumer " + CHECKPOINT_4_CITATION,
  },
  { name: "Card", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Bounded content block — used sparingly by design.", sourceFile: "components/ui/card.tsx", importSnippet: 'import { Card } from "@/components/ui/card.tsx";', variants: ["flat (default)", "elevated"], consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "KPI Card", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Single-number dashboard tile (catalogue name: \"Metric card / KPI widget\") — no real dashboard uses it yet.", sourceFile: "components/ui/kpi-card.tsx", importSnippet: 'import { KpiCard } from "@/components/ui/kpi-card.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Avatar",
    category: "DataDisplay",
    status: "IMPLEMENTED",
    purpose: "User/entity image or initials, with automatic fallback on image-load failure.",
    sourceFile: "components/ui/avatar.tsx",
    importSnippet: 'import { Avatar } from "@/components/ui/avatar.tsx";',
    consumers: ["components/ui/user-menu.tsx"],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Description List", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Native <dl> label/value pairs — the pattern every real detail page already renders inline, extracted.", sourceFile: "components/ui/description-list.tsx", importSnippet: 'import { DescriptionList } from "@/components/ui/description-list.tsx";', consumers: [], productionReady: true, citation: "Not previously named in any CargoGrid design-system document — disclosed as a gap when first requested, then implemented. " + CHECKPOINT_4_CITATION },
  { name: "Stat", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Bare label/value pair, the inline counterpart to KPI Card.", sourceFile: "components/ui/stat.tsx", importSnippet: 'import { Stat } from "@/components/ui/stat.tsx";', consumers: [], productionReady: true, citation: "Not previously named in any CargoGrid design-system document — disclosed as a gap when first requested, then implemented. " + CHECKPOINT_4_CITATION },
  { name: "Timeline", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Chronological event list; ActivityItem is the single entry, with optional before/after value disclosure.", sourceFile: "components/ui/timeline.tsx", importSnippet: 'import { Timeline, ActivityItem } from "@/components/ui/timeline.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Activity Item", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Single timeline entry (catalogue name: \"Activity item / Audit item\").", sourceFile: "components/ui/timeline.tsx", importSnippet: 'import { ActivityItem } from "@/components/ui/timeline.tsx";', consumers: ["components/ui/timeline.tsx"], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Accordion", category: "DataDisplay", status: "IMPLEMENTED", purpose: "Collapsible content sections — native <details>/<summary>, zero client JS.", sourceFile: "components/ui/accordion.tsx", importSnippet: 'import { Accordion } from "@/components/ui/accordion.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Kanban board", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Drag/status-column view.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — not built this checkpoint: needs a drag-and-drop dependency and no real consumer/data model exists yet to build the right shape against." },
  { name: "Calendar", category: "DataDisplay", status: "DOCUMENTED_ONLY", purpose: "Date-grid scheduling view.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — not built this checkpoint (DateInput/DateRangeInput cover the entry use case; a full scheduling grid has no real consumer yet)." },
  { name: "Document preview", category: "DataDisplay", status: "BLOCKED", purpose: "Signed-URL-gated file preview.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on the same storage pipeline as File upload." },
  { name: "Attachment list", category: "DataDisplay", status: "BLOCKED", purpose: "List of uploaded files with status.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — blocked on the same storage pipeline." },

  // ---- Navigation ----
  { name: "Tabs", category: "Navigation", status: "IMPLEMENTED", purpose: "Same-page view switch, built on Radix Tabs for correct roving-tabindex keyboard behavior.", sourceFile: "components/ui/tabs.tsx", importSnippet: 'import { Tabs } from "@/components/ui/tabs.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Breadcrumbs", category: "Navigation", status: "IMPLEMENTED", purpose: "Hierarchical location trail.", sourceFile: "components/ui/breadcrumb.tsx", importSnippet: 'import { Breadcrumb } from "@/components/ui/breadcrumb.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Sidebar item", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Both real portals use a flat top-bar link list today — no sidebar exists at all (appropriate at ≤2 top-level destinations per portal).", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1 — needs an actual shell redesign, not a single component; not attempted this checkpoint." },
  { name: "Navigation group", category: "Navigation", status: "DOCUMENTED_ONLY", purpose: "Grouped/collapsible navigation sections — no sidebar exists yet for a group to belong to.", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1" },
  {
    name: "Dropdown menu",
    category: "Overlays",
    status: "IMPLEMENTED",
    purpose: "Click-triggered action list, built on Radix DropdownMenu.",
    sourceFile: "components/ui/dropdown-menu.tsx",
    importSnippet: 'import { DropdownMenu } from "@/components/ui/dropdown-menu.tsx";',
    consumers: ["components/ui/split-button.tsx", "components/ui/dropdown-action.tsx", "components/ui/user-menu.tsx"],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Command menu",
    category: "Navigation",
    status: "IMPLEMENTED",
    purpose: "Keyboard-first global action/search launcher (Cmd/Ctrl+K), built on Radix Dialog plus a plain filtered list (not the cmdk package — not a dependency of this project).",
    sourceFile: "components/ui/command-menu.tsx",
    importSnippet: 'import { CommandMenu } from "@/components/ui/command-menu.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Page header", category: "Layout", status: "DOCUMENTED_ONLY", purpose: "Record-detail page header (title, status, primary actions) — each detail page renders its own ad hoc header today (catalogue name: \"Workspace header\").", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1 — not attempted this checkpoint." },
  { name: "Context menu", category: "Overlays", status: "IMPLEMENTED", purpose: "Right-click action list, built on Radix ContextMenu, same item shape as Dropdown menu.", sourceFile: "components/ui/context-menu.tsx", importSnippet: 'import { ContextMenu } from "@/components/ui/context-menu.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Persistent top bar", category: "Layout", status: "DOCUMENTED_ONLY", purpose: "Portal name, primary nav, org-context selector, global search, notifications, user menu — both real layouts render a minimal 2-link header today.", productionReady: false, citation: "docs/design-system/03_LAYOUT_NAVIGATION.md §1 — needs an actual shell redesign; User menu itself is now built (below) for whichever future shell adopts it." },
  {
    name: "User menu",
    category: "Navigation",
    status: "IMPLEMENTED",
    purpose: "Account/session actions, top-bar — composed from Avatar + DropdownMenu. No real layout has adopted it into its top bar yet.",
    sourceFile: "components/ui/user-menu.tsx",
    importSnippet: 'import { UserMenu } from "@/components/ui/user-menu.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },

  // ---- Feedback ----
  { name: "Alert", category: "Feedback", status: "IMPLEMENTED", purpose: "Inline, non-persistent, dismissible emphasis block, distinct from Banner's page-level persistence.", sourceFile: "components/ui/alert.tsx", importSnippet: 'import { Alert } from "@/components/ui/alert.tsx";', variants: ["info", "warning", "success", "danger"], consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Toast",
    category: "Feedback",
    status: "IMPLEMENTED",
    purpose: "Transient, non-blocking confirmation, built on Radix Toast.",
    sourceFile: "components/ui/toast.tsx",
    importSnippet: 'import { ToastProvider, useToast, useToastOnSettled } from "@/components/ui/toast.tsx";',
    consumers: [
      "app/(tenant)/[tenantSlug]/layout.tsx — ToastProvider is mounted once for the whole tenant route group (ISS-2026-246, 2026-09-02)",
      "app/(tenant)/[tenantSlug]/admin/loyalty-points/loyalty-points-admin-panel.tsx — all five Points Ledger forms, replacing the shared FormFeedback success <p>",
      "app/(tenant)/[tenantSlug]/hris/my/profile/my-profile-panel.tsx — correction-request confirmation",
      "app/(tenant)/[tenantSlug]/analytics/refresh-view-button.tsx — a refresh that previously reported failure only",
    ],
    a11y: "Radix Toast's own live-region/swipe-to-dismiss/keyboard behavior.",
    duplicateNote: "Deliberately not converted: notices carrying something to copy or act on later (admin/loyalty-benefits' one-time voucher code, hris/roster/cycles' generated job id, hris/positions/bulk-reassign's follow-up instruction) stay inline — a four-second auto-dismiss is the wrong home for those.",
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Skeleton",
    category: "Feedback",
    status: "IMPLEMENTED",
    purpose: "Loading placeholder matching a known layout — SkeletonText/SkeletonTable are pre-composed shapes.",
    sourceFile: "components/ui/skeleton.tsx",
    importSnippet: 'import { Skeleton, SkeletonText, SkeletonTable } from "@/components/ui/skeleton.tsx";',
    consumers: [
      "All 27 route-level loading.tsx files across app/(supreme)/supreme/, app/(tenant)/[tenantSlug]/admin/, and app/(tenant)/[tenantSlug]/commercial/ — checkpoint 7, 2026-07-27",
      "SkeletonTable: the 13 whose route renders a single real DataTable (leads, prospects, contacts, accounts, opportunities, quotations, contracts, margin-rules, approval-rules, approvals, credit-approvals, admin/users, supreme/tenants), each with that page's own real column count",
      "SkeletonText: the remaining 14 (every entity detail page, plus dashboard/pipeline/rates/reports whose route renders mixed or non-tabular content)",
    ],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION + "; all 27 loading.tsx consumers migrated checkpoint 7, 2026-07-27",
  },
  { name: "Spinner", category: "Feedback", status: "IMPLEMENTED", purpose: "Indeterminate loading indicator — reserved for genuinely indeterminate inline cases; Skeleton remains the default loading pattern.", sourceFile: "components/ui/spinner.tsx", importSnippet: 'import { Spinner } from "@/components/ui/spinner.tsx";', consumers: ["app/(public)/status/status-panel.tsx — the \"Check again\" button's own busy state, an 8s probe with no page/section load to skeleton (ISS-2026-246, 2026-09-02)"], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Empty State",
    category: "Feedback",
    status: "IMPLEMENTED",
    purpose: "No-data explanation + gated next action — primaryAction/secondaryAction are caller-rendered nodes so this component never decides permission gating itself.",
    sourceFile: "components/ui/empty-state.tsx",
    importSnippet: 'import { EmptyState } from "@/components/ui/empty-state.tsx";',
    consumers: [],
    productionReady: true,
    duplicateNote: "19+ list pages still render their own inline empty-state <p> text, unmigrated — see the migration map.",
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Error State",
    category: "Feedback",
    status: "IMPLEMENTED",
    purpose: "Human-readable message + optional request ID + optional gated retry.",
    sourceFile: "components/ui/error-state.tsx",
    importSnippet: 'import { ErrorState } from "@/components/ui/error-state.tsx";',
    consumers: [
      "Every Commercial, admin, and supreme list/detail page's load-failure branch — 28 pages, checkpoint 7, 2026-07-27, including commercial/dashboard/page.tsx (ternary description) and commercial/reports/[reportCode]/page.tsx's separate run-failure branch",
    ],
    productionReady: true,
    duplicateNote: "The many client-form inline validation/submission error messages (create-*-form.tsx, *-decision-form.tsx, *-actions-panel.tsx) remain unmigrated by design — a stateful, form-submission-path pattern, a different risk class from the static page-load-failure branch this component's consumers above all resolved.",
    citation: CHECKPOINT_4_CITATION + "; every page-level load-failure consumer migrated checkpoint 7, 2026-07-27",
  },
  { name: "Success State", category: "Feedback", status: "IMPLEMENTED", purpose: "Whole-page/whole-section confirmation, distinct from Banner's success variant and StatusBadge's success tone (both inline).", sourceFile: "components/ui/success-state.tsx", importSnippet: 'import { SuccessState } from "@/components/ui/success-state.tsx";', consumers: ["app/(public)/careers/[tenantSlug]/[postingToken]/apply-form.tsx", "app/(public)/vendor-intake/[token]/intake-form.tsx", "app/(public)/vendor-intake/register/[tenantSlug]/register-form.tsx — the three public post-submit confirmations that replace their whole form (ISS-2026-246, 2026-09-02)"], productionReady: true, duplicateNote: "Deliberately not adopted by app/(public)/quote-decision/[token]/decision-form.tsx: that confirmation is tone-neutral on purpose because the decision it acknowledges may be a rejection.", citation: "Not previously named in any CargoGrid design-system document — disclosed as a gap when first requested, then implemented. " + CHECKPOINT_4_CITATION },
  { name: "Progress", category: "Feedback", status: "IMPLEMENTED", purpose: "Determinate long-running-operation indicator — native <progress>.", sourceFile: "components/ui/progress.tsx", importSnippet: 'import { Progress } from "@/components/ui/progress.tsx";', consumers: ["app/(tenant)/[tenantSlug]/customer-loyalty-tier/customer-loyalty-tier-panel.tsx — next-tier progress, replacing a hand-rolled role=\"progressbar\" div with an inline width style (ISS-2026-246, 2026-09-02)"], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Progress Indicator", category: "Feedback", status: "IMPLEMENTED", purpose: "Same component as Progress above — this checkpoint's instruction listed it separately under both Data Display and Feedback.", sourceFile: "components/ui/progress.tsx", importSnippet: 'import { Progress } from "@/components/ui/progress.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Permission state", category: "Feedback", status: "IMPLEMENTED", purpose: "\"You do not have access to...\" pattern — renders exactly the caller-supplied description, never leaking hidden resource shape on its own.", sourceFile: "components/ui/permission-state.tsx", importSnippet: 'import { PermissionState } from "@/components/ui/permission-state.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },

  // ---- Overlays ----
  {
    name: "Dialog",
    category: "Overlays",
    status: "IMPLEMENTED",
    purpose: "Modal, focus-trapped, built on Radix Dialog.",
    sourceFile: "components/ui/dialog.tsx",
    importSnippet: 'import { Dialog } from "@/components/ui/dialog.tsx";',
    consumers: ["components/ui/drawer.tsx (positioning variant)"],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Confirmation Dialog",
    category: "Overlays",
    status: "IMPLEMENTED",
    purpose: "Dialog variant requiring an explicit confirm click for a destructive/override action — never closes via the confirm path on backdrop/Escape alone.",
    sourceFile: "components/ui/dialog.tsx",
    importSnippet: 'import { ConfirmationDialog } from "@/components/ui/dialog.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },
  { name: "Drawer", category: "Overlays", status: "IMPLEMENTED", purpose: "Side-anchored panel, built on Radix Dialog positioned as a side panel (no slide-in transition — tailwindcss-animate is not a dependency).", sourceFile: "components/ui/drawer.tsx", importSnippet: 'import { Drawer } from "@/components/ui/drawer.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Sheet", category: "Overlays", status: "IMPLEMENTED", purpose: "Same implementation as Drawer (side=\"bottom\") — the spec's own \"same shape as Drawer\" is literal here, not a separate component.", sourceFile: "components/ui/drawer.tsx", importSnippet: 'import { Drawer } from "@/components/ui/drawer.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  { name: "Popover", category: "Overlays", status: "IMPLEMENTED", purpose: "Click-triggered floating content, built on Radix Popover.", sourceFile: "components/ui/popover.tsx", importSnippet: 'import { Popover } from "@/components/ui/popover.tsx";', consumers: [], productionReady: true, citation: CHECKPOINT_4_CITATION },
  {
    name: "Tooltip",
    category: "Overlays",
    status: "IMPLEMENTED",
    purpose: "Hover/focus-triggered supplementary text, built on Radix Tooltip (correct hover+focus trigger and Escape-dismiss for free).",
    sourceFile: "components/ui/tooltip.tsx",
    importSnippet: 'import { Tooltip, TooltipProvider } from "@/components/ui/tooltip.tsx";',
    consumers: [],
    productionReady: true,
    citation: CHECKPOINT_4_CITATION,
  },

  // ---- Tables ----
  {
    name: "Table",
    category: "Tables",
    status: "IMPLEMENTED",
    purpose: "Static/simple tabular display.",
    sourceFile: "components/tables/data-table.tsx",
    importSnippet: 'import { DataTable, type DataTableColumn } from "@/components/tables/data-table.tsx";',
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
      "app/(supreme)/supreme/tenants/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/contacts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/accounts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/pipeline/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/rates/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/contracts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/margin-rules/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/approval-rules/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/approvals/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/credit-approvals/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/reports/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/reports/[reportCode]/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/comparison-panel.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/customer-acceptance-panel.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/version-history.tsx",
      "app/(tenant)/[tenantSlug]/admin/users/page.tsx",
    ],
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1 (added checkpoint 2, 2026-07-26; remaining Commercial/admin consumers migrated checkpoint 6, 2026-07-27)",
  },
  {
    name: "Data grid",
    category: "Tables",
    status: "IMPLEMENTED",
    purpose: "Dense, density-tiered operational table (display/pagination only — sort/filter/column-config remain DOCUMENTED_ONLY).",
    sourceFile: "components/tables/data-table.tsx",
    importSnippet: 'import { DataTable, type DataTableColumn } from "@/components/tables/data-table.tsx";',
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
      "app/(supreme)/supreme/tenants/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/contacts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/accounts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/pipeline/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/rates/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/contracts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/margin-rules/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/approval-rules/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/approvals/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/credit-approvals/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/reports/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/reports/[reportCode]/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/comparison-panel.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/customer-acceptance-panel.tsx",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/version-history.tsx",
      "app/(tenant)/[tenantSlug]/admin/users/page.tsx",
    ],
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1 (added checkpoint 2, 2026-07-26; remaining Commercial/admin consumers migrated checkpoint 6, 2026-07-27)",
  },
  {
    name: "Pagination",
    category: "Tables",
    status: "IMPLEMENTED",
    purpose: "Offset pagination control (no cursor/keyset variant).",
    sourceFile: "components/tables/pagination.tsx",
    importSnippet: 'import { Pagination } from "@/components/tables/pagination.tsx";',
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
      "app/(supreme)/supreme/tenants/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/contacts/page.tsx",
      "app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx",
      "app/(tenant)/[tenantSlug]/admin/users/page.tsx",
    ],
    productionReady: true,
    citation:
      "docs/design-system/02_COMPONENTS.md §1 (added checkpoint 2, 2026-07-26; prospects/contacts/opportunities/admin-users added checkpoint 6, 2026-07-27 — only where the underlying query already server-paginates; accounts/quotations/rates/contracts/pipeline/margin-rules/approval-rules/approvals/credit-approvals/reports return a full unpaginated array and deliberately got DataTable only, not a fabricated Pagination control)",
  },
  { name: "Filter bar", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Explicit-allowlist filter controls, mirrors the server-side allowlist — not yet built on any screen.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — no real screen has server-side filter support to build against yet." },
  { name: "Saved views", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Named, persisted filter/sort/column configurations.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — depends on Filter bar/sorting existing first." },
  { name: "Bulk action bar", category: "Tables", status: "DOCUMENTED_ONLY", purpose: "Appears on multi-row selection, drives a selection-token-based bulk mutation — no bulk mutation exists in this repository yet.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2" },

  // ---- Charts and Analytics (CargoGrid Chart System, checkpoint 5, Apache ECharts) ----
  {
    name: "Chart wrapper",
    category: "ChartsAndAnalytics",
    status: "IMPLEMENTED",
    purpose: "Low-level chart component -- ECharts init/dispose, theme, resize, loading/empty/error, accessibility, reduced-motion. Contains no business logic; presets build the series-specific option it renders.",
    sourceFile: "components/charts/chart.tsx",
    importSnippet: 'import { Chart } from "@/components/charts/chart.tsx";',
    consumers: ["components/charts/presets/trend-chart.tsx", "components/charts/presets/comparison-bar-chart.tsx", "components/charts/presets/donut-chart.tsx"],
    states: ["success", "loading (Skeleton)", "empty (EmptyState)", "error (ErrorState + retry)"],
    tokensUsed: ["--chart-*  (all 18 tokens, via lib/charts/chart-colors.ts)"],
    a11y: 'role="img" + required ariaLabel; ECharts aria.enabled; every preset offers a real "View as table" toggle to the same DataTable-based accessible alternative.',
    productionReady: true,
    citation: "docs/design-system/09_CHARTS.md §2 (checkpoint 5, 2026-07-26)",
  },
  {
    name: "ChartCard",
    category: "ChartsAndAnalytics",
    status: "IMPLEMENTED",
    purpose: "Shared dashboard-widget shell: header (title/KPI/trend), actions (period/refresh/export/fullscreen, each caller-gated), chart content, footer insight. Built entirely from existing Card/IconButton/DropdownMenu/Select.",
    sourceFile: "components/charts/chart-card.tsx",
    importSnippet: 'import { ChartCard } from "@/components/charts/chart-card.tsx";',
    consumers: [],
    productionReady: true,
    citation: "docs/design-system/09_CHARTS.md §4 (checkpoint 5, 2026-07-26)",
  },
  {
    name: "Trend Chart",
    category: "ChartsAndAnalytics",
    status: "IMPLEMENTED",
    purpose: "Time-series line chart preset -- revenue/cost/margin movement, shipment volume, SLA trends, forecast vs. actual (a dashed forecast series, never the same style as actual).",
    sourceFile: "components/charts/presets/trend-chart.tsx",
    importSnippet: 'import { TrendChart } from "@/components/charts/presets/trend-chart.tsx";',
    consumers: [],
    productionReady: true,
    citation: "docs/design-system/09_CHARTS.md §6 (checkpoint 5, 2026-07-26)",
  },
  {
    name: "Comparison Bar Chart",
    category: "ChartsAndAnalytics",
    status: "IMPLEMENTED",
    purpose: "Category comparison preset -- business-unit/salesperson/customer ranking, pipeline stage, win/loss reasons. Supports horizontal orientation for long labels or many categories.",
    sourceFile: "components/charts/presets/comparison-bar-chart.tsx",
    importSnippet: 'import { ComparisonBarChart } from "@/components/charts/presets/comparison-bar-chart.tsx";',
    consumers: [],
    productionReady: true,
    citation: "docs/design-system/09_CHARTS.md §6 (checkpoint 5, 2026-07-26)",
  },
  {
    name: "Donut Chart",
    category: "ChartsAndAnalytics",
    status: "IMPLEMENTED",
    purpose: "Small part-to-whole comparison preset (≤~5 categories; prefer Comparison Bar Chart when exact ranking matters). Slice tone can be semantic (positive/negative/warning/neutral) or categorical.",
    sourceFile: "components/charts/presets/donut-chart.tsx",
    importSnippet: 'import { DonutChart } from "@/components/charts/presets/donut-chart.tsx";',
    consumers: [],
    productionReady: true,
    citation: "docs/design-system/09_CHARTS.md §6 (checkpoint 5, 2026-07-26)",
  },
  {
    name: "Stacked Bar Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Status/revenue/service composition over time.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5, no real consumer/data model to build the right shape against yet.",
  },
  {
    name: "Funnel Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Lead-to-win conversion, opportunity stages, quotation conversion, approval funnel.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5.",
  },
  {
    name: "Waterfall Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Revenue-to-gross-margin bridge, cost variance decomposition.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5; would need a custom-series composition over ECharts' own stacking primitives.",
  },
  {
    name: "Gauge Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "SLA attainment, capacity utilization, target attainment -- used sparingly per this checkpoint's own Chart Selection Rules (prefer KPI + Progress when a gauge adds no analytical value).",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5.",
  },
  {
    name: "Calendar Heatmap",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Shipment activity by day/hour, delivery density, SLA performance matrix.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5, no real consumer.",
  },
  {
    name: "Sankey Flow Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Lead-to-conversion flow, shipment origin-to-destination flow, job handoff flow.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5, no real consumer.",
  },
  {
    name: "Lane Map",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Shipment lanes, origin/destination distribution, route flow on a geographic map.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5, needs geo/map data CargoGrid does not have a source for yet.",
  },
  {
    name: "Distribution Chart",
    category: "ChartsAndAnalytics",
    status: "DOCUMENTED_ONLY",
    purpose: "Scatter plot -- margin vs. revenue, cost vs. distance, transit time vs. distance.",
    productionReady: false,
    citation: "docs/design-system/09_CHARTS.md §9 -- not built checkpoint 5, no real consumer.",
  },

  // ---- Status and Workflow ----
  { name: "Stepper", category: "StatusAndWorkflow", status: "DOCUMENTED_ONLY", purpose: "Multi-step workflow progress indicator.", productionReady: false, citation: "docs/design-system/02_COMPONENTS.md §2 — no multi-step form exists anywhere in this repository yet to build the right shape against." },
  { name: "Approval queue", category: "StatusAndWorkflow", status: "DOCUMENTED_ONLY", purpose: "Renders the approval-decision/exception catalogue as a queue — commercial/approvals/page.tsx is a plain list today, not a queue pattern.", productionReady: false, citation: "docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §2" },
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
    consumers: [
      "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx (status column, checkpoint 4)",
      "app/(supreme)/supreme/tenants/page.tsx (status column, checkpoint 4)",
      "app/(tenant)/[tenantSlug]/commercial/prospects/page.tsx (status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/accounts/page.tsx (status, customerStatus columns, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/opportunities/page.tsx (stage column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/pipeline/page.tsx (sales plan status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/quotations/page.tsx (status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/contracts/page.tsx (status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/margin-rules/page.tsx (status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/approval-rules/page.tsx (status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/reports/page.tsx and reports/[reportCode]/page.tsx (run status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/customer-acceptance-panel.tsx (token status column, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/version-history.tsx (current/superseded + status columns, checkpoint 6)",
      "app/(tenant)/[tenantSlug]/admin/users/page.tsx (status column, checkpoint 6, via the new defensive resolvePortalUserStatusTone since PortalUser.status is an unconstrained string)",
    ],
    tokensUsed: ["--color-success/-warning/-danger/-info", "--color-neutral-100/700"],
    a11y: "label is a required prop — cannot render color-only even by omission.",
    responsive: "None.",
    productionReady: true,
    citation:
      "docs/design-system/02_COMPONENTS.md §1; migrated onto its first two real consumers via components/domain/status-tone-map.ts " +
      CHECKPOINT_4_CITATION +
      "; remaining Commercial/admin canonical status columns migrated checkpoint 6, 2026-07-27",
  },

  // ---- Domain Components ----
  {
    name: "Approval Decision Panel",
    category: "DomainComponents",
    status: "IMPLEMENTED",
    purpose: "Shared Approve/Reject panel — reason textarea + confirm buttons, enforcing \"reject requires a reason.\" Not yet wired into the two existing duplicate forms (approval-decision-form.tsx, credit-approval-decision-form.tsx) — that migration remains a distinct, Medium-risk follow-up since it touches two real, tested submit paths.",
    sourceFile: "components/domain/approval-decision-panel.tsx",
    importSnippet: 'import { ApprovalDecisionPanel } from "@/components/domain/approval-decision-panel.tsx";',
    consumers: [],
    productionReady: true,
    duplicateNote:
      "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/approval-decision-form.tsx and app/(tenant)/[tenantSlug]/commercial/accounts/[accountId]/credit-approval-decision-form.tsx still independently implement the same decision-panel job — migrating them onto this component is the remaining step, not done this checkpoint.",
    citation: CHECKPOINT_4_CITATION,
  },
  {
    name: "Canonical status-to-tone mapping",
    category: "DomainComponents",
    status: "IMPLEMENTED",
    purpose: "Maps a domain's canonical_ref (Lead status, Opportunity stage, Quotation approval status, Tenant canonical status) to a StatusBadge tone. Every value is read from the real enum each domain's own contract defines — TypeScript's Record<Enum, ...> exhaustiveness check means a future enum value with no mapping fails to compile.",
    sourceFile: "components/domain/status-tone-map.ts",
    importSnippet: 'import { LEAD_STATUS_TONE_MAP } from "@/components/domain/status-tone-map.ts";',
    consumers: ["app/(tenant)/[tenantSlug]/commercial/leads/page.tsx", "app/(supreme)/supreme/tenants/page.tsx"],
    productionReady: true,
    citation: "docs/design-system/02_COMPONENTS.md §1 (StatusBadge implementation notes); this is what unblocked StatusBadge's zero-consumer gap. " + CHECKPOINT_4_CITATION,
  },
] as const;
