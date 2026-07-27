/**
 * Duplicate-component / migration map for `/internal/design-system/duplicates`
 * (CargoGrid UI Modernization checkpoint 3, updated checkpoint 4). Every
 * "affectedPages" count was verified by grep against `app/` (see
 * `docs/design-system/08_COMPONENT_INVENTORY.md` §4 for the exact commands) — not
 * estimated. Per this task's own instruction: "Do not delete legacy implementations
 * until all consumers have been safely migrated" — this module only records the map,
 * it does not perform any migration itself, except where explicitly noted below
 * (two entries were migrated as a direct, low-risk consequence of checkpoint 4
 * building the missing replacement).
 */

export type MigrationPriority = "High" | "Medium" | "Low";
export type MigrationRisk = "Low" | "Medium" | "High";

export interface MigrationMapEntry {
  readonly legacyImplementation: string;
  readonly sharedReplacement: string;
  readonly replacementStatus: "IMPLEMENTED" | "DOCUMENTED_ONLY";
  readonly affectedPages: readonly string[];
  readonly priority: MigrationPriority;
  readonly breakingChangeRisk: MigrationRisk;
  readonly riskNote: string;
}

export const MIGRATION_MAP: readonly MigrationMapEntry[] = [
  {
    legacyImplementation: "Canonical status values (Lead.status, SupremeTenant.canonicalStatus, and others) rendered as plain text",
    sharedReplacement: "components/ui/status-badge.tsx + components/domain/status-tone-map.ts",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/leads/page.tsx (status column) — MIGRATED, checkpoint 4",
      "supreme/tenants/page.tsx (status column) — MIGRATED, checkpoint 4",
      "commercial/prospects/page.tsx (status), commercial/accounts/page.tsx (status, customerStatus), commercial/opportunities/page.tsx (stage), commercial/pipeline/page.tsx (sales plan status), commercial/quotations/page.tsx (status), commercial/contracts/page.tsx (status), commercial/margin-rules/page.tsx (status), commercial/approval-rules/page.tsx (status), commercial/reports/page.tsx and reports/[reportCode]/page.tsx (run status), admin/users/page.tsx (status), commercial/quotations/[quotationId]/{customer-acceptance-panel,version-history}.tsx (token/version status) — MIGRATED, this checkpoint",
      "commercial/contacts/page.tsx, commercial/rates/page.tsx, commercial/approvals/page.tsx, commercial/credit-approvals/page.tsx — no canonical status column exists on these screens, nothing to migrate",
    ],
    priority: "High",
    breakingChangeRisk: "Low",
    riskNote:
      "StatusBadge was production-ready with 0 consumers because nothing owned the domain-specific canonical_ref→tone mapping. Checkpoint 4 built that mapping (Domain Components, now IMPLEMENTED) and migrated the two screens checkpoint 2 already touched. This checkpoint added the remaining domain tone maps to status-tone-map.ts (ProspectStatus, SalesPlanStatus, MarginRuleStatus, QuotationApprovalRuleStatus, QuotationStatus, CustomerContractStatus, AccountStatus, CustomerStatus, QuotationAcceptanceTokenStatus, ReportRunStatus, plus a defensive resolvePortalUserStatusTone for PortalUser.status which is an unconstrained string at the query boundary, mirroring resolveTenantStatusTone) and migrated every remaining canonical status column found. This item is now fully resolved — no further Commercial screen has an un-migrated canonical status column.",
  },
  {
    legacyImplementation: "Lead.source rendered as plain text",
    sharedReplacement: "components/ui/badge.tsx",
    replacementStatus: "IMPLEMENTED",
    affectedPages: ["commercial/leads/page.tsx (source column) — MIGRATED, checkpoint 4"],
    priority: "Low",
    breakingChangeRisk: "Low",
    riskNote: "Resolved. A free-form tag, not a canonical status, so Badge (not StatusBadge) was the correct target.",
  },
  {
    legacyImplementation: "Hand-rolled raw <table> markup, one copy per page",
    sharedReplacement: "components/tables/data-table.tsx",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/prospects/page.tsx — MIGRATED, this checkpoint (DataTable + Pagination; listProspects already server-paginates)",
      "commercial/contacts/page.tsx — MIGRATED, this checkpoint (DataTable + Pagination; listContacts already server-paginates)",
      "commercial/accounts/page.tsx — MIGRATED, this checkpoint (DataTable only; listAccounts returns a full array, no pagination fabricated)",
      "commercial/opportunities/page.tsx — MIGRATED, this checkpoint (DataTable + Pagination; listOpportunities already server-paginates)",
      "commercial/pipeline/page.tsx — MIGRATED, this checkpoint (Sales plans table only; the Stage summary section is a card grid, not a raw table, and was left as-is)",
      "commercial/quotations/page.tsx — MIGRATED, this checkpoint (DataTable only; listQuotationsForTenant returns a full array)",
      "commercial/rates/page.tsx — MIGRATED, this checkpoint (both the Pending-approval and Active-rates tables)",
      "commercial/contracts/page.tsx — MIGRATED, this checkpoint (DataTable only; listCustomerContracts returns a full array)",
      "commercial/margin-rules/page.tsx — MIGRATED, this checkpoint",
      "commercial/approval-rules/page.tsx — MIGRATED, this checkpoint",
      "commercial/approvals/page.tsx — MIGRATED, this checkpoint",
      "commercial/credit-approvals/page.tsx — MIGRATED, this checkpoint",
      "commercial/reports/page.tsx — MIGRATED, this checkpoint (run-history table; the Catalogue section is a card grid, not a raw table)",
      "commercial/reports/[reportCode]/page.tsx — MIGRATED, this checkpoint (both the dynamic-column Preview table and the run-history table)",
      "commercial/quotations/[quotationId]/{comparison-panel,customer-acceptance-panel,version-history}.tsx — MIGRATED, this checkpoint",
      "admin/users/page.tsx — MIGRATED, this checkpoint (DataTable + Pagination; listPortalUsers already server-paginates)",
    ],
    priority: "High",
    breakingChangeRisk: "Low",
    riskNote:
      "Same proven, purely-presentational migration already done twice (commercial/leads, supreme/tenants) — no query/access-control change required, only markup replacement. A real Pagination control was added only where the underlying query already server-paginates (prospects, contacts, opportunities, admin/users); the remaining pages' queries return a full unpaginated array, so adding a Pagination control there would have been a fabricated affordance, not a real one — left as DataTable alone, matching this repository's own 'no client-only pretend pagination' discipline. This migration-map item is now fully resolved: no remaining Commercial or admin screen renders a raw hand-rolled <table>.",
  },
  {
    legacyImplementation: "Hand-rolled animate-pulse skeleton bars, one copy per route's loading.tsx",
    sharedReplacement: "Skeleton / SkeletonText / SkeletonTable (components/ui/skeleton.tsx)",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "27 loading.tsx files across commercial/* and admin/users, supreme/tenants — see docs/design-system/08_COMPONENT_INVENTORY.md §4 for the full list. Not migrated yet.",
    ],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational. The primitive now exists (checkpoint 4) — the remaining work is 27 one-line-ish swaps, not a design decision.",
  },
  {
    legacyImplementation: "Inline role=\"alert\" error block, one copy per page",
    sharedReplacement: "ErrorState (components/ui/error-state.tsx)",
    replacementStatus: "IMPLEMENTED",
    affectedPages: ["Every Commercial list/detail page's load-failure branch — 21+ pages. Not migrated yet."],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational. The primitive now exists (checkpoint 4) — no retry/request-id behavior exists today to preserve or break.",
  },
  {
    legacyImplementation: "Inline empty-state <p> message, one copy per page",
    sharedReplacement: "EmptyState (components/ui/empty-state.tsx); DataTable's built-in emptyMessage remains the right choice for a table's own empty row, EmptyState is for a whole-page empty state with an action",
    replacementStatus: "IMPLEMENTED",
    affectedPages: ["Every Commercial list page's zero-row branch — 19+ pages. Not migrated yet."],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational. The primitive now exists (checkpoint 4) — no gated action exists today to preserve or break.",
  },
  {
    legacyImplementation: "approval-decision-form.tsx and credit-approval-decision-form.tsx independently implement the same approve/reject decision panel",
    sharedReplacement: "ApprovalDecisionPanel (components/domain/approval-decision-panel.tsx)",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/quotations/[quotationId]/approval-decision-form.tsx — not migrated",
      "commercial/accounts/[accountId]/credit-approval-decision-form.tsx — not migrated",
    ],
    priority: "Medium",
    breakingChangeRisk: "Medium",
    riskNote:
      "The primitive now exists (checkpoint 4) but touches real submit/decision server actions, not pure display — migrating either form must preserve its own reason-required/permission-gated behavior exactly (COM-153/COM-157). Deliberately not done this checkpoint: a display-only component build and a behavior-preserving migration of two tested capabilities are different risk classes and shouldn't share one diff.",
  },
  {
    legacyImplementation: "Raw <input>/<select>/<textarea> form fields, one hand-styled copy per form",
    sharedReplacement: "Input / Select / Textarea / Checkbox / Radio / Switch / FormField (components/forms/)",
    replacementStatus: "IMPLEMENTED",
    affectedPages: ["39 form/action-panel files across every Commercial module — see docs/design-system/08_COMPONENT_INVENTORY.md §4. Not migrated yet."],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote:
      "All primitives now exist (checkpoint 4), styled to match every existing field's own current appearance exactly (border-neutral-300, rounded-md, px-3 py-2) so a migration changes zero visual behavior. Large surface (39 files) but mechanical if scoped to display only; becomes Medium risk only if a future migration also changes validation-state wiring (autosave, error-message binding) rather than just markup.",
  },
  {
    legacyImplementation:
      "None found — audited every file under app/ for chart/visualization code before building the CargoGrid Chart System (checkpoint 5); commercial/dashboard/page.tsx (COM-158) renders every metric as a bucket list/table, never a chart, and no other screen renders any data visualization at all",
    sharedReplacement: "components/charts/ (Chart, ChartCard, TrendChart, ComparisonBarChart, DonutChart)",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/dashboard/page.tsx could adopt TrendChart/DonutChart for its Pipeline/Win-Loss sections — deliberately not wired this checkpoint: the dashboard's multi-currency grouping and permission-masked values need careful handling to convert correctly, judged a distinct, correctness-sensitive follow-up rather than rushed into this checkpoint's diff",
    ],
    priority: "Low",
    breakingChangeRisk: "Low",
    riskNote:
      "Not a migration in the usual sense (nothing to move away from) — the finding here is that this checkpoint's whole shared chart layer was built ahead of any real chart consumer, a deliberate, explicitly-authorized departure from this repository's usual 'wait for a real consumer' default (docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md §10/§11). Adopting a preset into the real dashboard is the natural next step, not performed here to avoid rushing a masked-value/multi-currency correctness question.",
  },
] as const;
