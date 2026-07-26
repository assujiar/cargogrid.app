/**
 * Page-pattern gallery data for `/internal/design-system/patterns` (CargoGrid UI
 * Modernization checkpoint 3, "Page Patterns" category #14). These are reference
 * pointers to real existing pages wherever one exists — not new business modules, and
 * not fabricated demo pages standing in for a pattern this repository has never built.
 */

export interface PatternEntry {
  readonly name: string;
  readonly status: "REAL_REFERENCE" | "NOT_BUILT";
  readonly description: string;
  /** Repo-relative path to a real existing page demonstrating this pattern, when one exists. */
  readonly referenceFile?: string;
  readonly note?: string;
}

export const PATTERN_REGISTRY: readonly PatternEntry[] = [
  {
    name: "List page",
    status: "REAL_REFERENCE",
    description: "Filterless server-paginated list: page header, create form, DataTable, Pagination.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
    note: "The reference consumer for both components/tables/data-table.tsx and pagination.tsx (checkpoint 2).",
  },
  {
    name: "Detail page",
    status: "REAL_REFERENCE",
    description: "Single-record view with related action panels/forms rendered as sibling sections.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/page.tsx",
    note: "No shared Workspace Header / Summary Header primitive exists yet (docs/design-system/03_LAYOUT_NAVIGATION.md §1) — every detail page still builds its own ad hoc header.",
  },
  {
    name: "Create form",
    status: "REAL_REFERENCE",
    description: "A bound server action + client form, inline field-level validation errors.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/leads/capture-lead-form.tsx",
  },
  {
    name: "Edit form",
    status: "REAL_REFERENCE",
    description: "Pre-filled form with optimistic-concurrency conflict detection.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/quotations/[quotationId]/revision-form.tsx",
  },
  {
    name: "Dashboard",
    status: "REAL_REFERENCE",
    description: "Role-scoped metric widgets, each independently sourced and independently failable.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/dashboard/page.tsx",
    note: "Metrics render as buckets/lists today, not KPI tiles or charts — see the Charts and Analytics category (DOCUMENTED_ONLY).",
  },
  {
    name: "Approval page",
    status: "REAL_REFERENCE",
    description: "A queue of pending decisions with an approve/reject action per row.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/approvals/page.tsx",
    note: "Renders as a plain list today, not the Approval Queue / Exception Queue pattern described in docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §2 (DOCUMENTED_ONLY).",
  },
  {
    name: "Wizard",
    status: "NOT_BUILT",
    description: "Multi-step workflow with per-step validation.",
    note: "No multi-step form exists anywhere in this repository — every create/edit flow is a single-page form. The Stepper primitive it would depend on is also DOCUMENTED_ONLY.",
  },
  {
    name: "Empty page",
    status: "REAL_REFERENCE",
    description: "Whole-page empty state (not a component's inline empty state) when a list has zero rows.",
    referenceFile: "app/(supreme)/supreme/tenants/page.tsx",
    note: "Implemented inline per-page (a plain <p> message), not through a shared Empty State component (DOCUMENTED_ONLY).",
  },
  {
    name: "Error page",
    status: "REAL_REFERENCE",
    description: "Whole-page error state with a role=\"alert\" message.",
    referenceFile: "app/(tenant)/[tenantSlug]/commercial/leads/page.tsx",
    note: "No retry action or request ID is shown — the full Error State component (docs/design-system/02_COMPONENTS.md §2) is DOCUMENTED_ONLY.",
  },
  {
    name: "Settings page",
    status: "NOT_BUILT",
    description: "Tenant/account configuration surface.",
    note: "No settings page exists in this repository yet — nothing to reference.",
  },
] as const;
