/**
 * Duplicate-component / migration map for `/internal/design-system/duplicates`
 * (CargoGrid UI Modernization checkpoint 3). Every "affectedPages" count below was
 * verified this checkpoint by grep against `app/` (see
 * `docs/design-system/08_COMPONENT_INVENTORY.md` §4 for the exact commands) — not
 * estimated. Per this task's own instruction: "Do not delete legacy implementations
 * until all consumers have been safely migrated" — this module only records the map,
 * it does not perform any migration itself.
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
    legacyImplementation: "Hand-rolled raw <table> markup, one copy per page",
    sharedReplacement: "components/tables/data-table.tsx",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/prospects/page.tsx",
      "commercial/contacts/page.tsx",
      "commercial/accounts/page.tsx",
      "commercial/opportunities/page.tsx",
      "commercial/pipeline/page.tsx",
      "commercial/quotations/page.tsx",
      "commercial/rates/page.tsx",
      "commercial/contracts/page.tsx",
      "commercial/margin-rules/page.tsx",
      "commercial/approval-rules/page.tsx",
      "commercial/approvals/page.tsx",
      "commercial/credit-approvals/page.tsx",
      "commercial/reports/page.tsx",
      "commercial/reports/[reportCode]/page.tsx",
      "commercial/quotations/[quotationId]/{comparison-panel,customer-acceptance-panel,version-history}.tsx",
      "admin/users/page.tsx",
    ],
    priority: "High",
    breakingChangeRisk: "Low",
    riskNote:
      "Same proven, purely-presentational migration already done twice (commercial/leads, supreme/tenants) — no query/access-control change required, only markup replacement.",
  },
  {
    legacyImplementation: "Hand-rolled animate-pulse skeleton bars, one copy per route's loading.tsx",
    sharedReplacement: "Skeleton (docs/design-system/02_COMPONENTS.md §2)",
    replacementStatus: "DOCUMENTED_ONLY",
    affectedPages: [
      "27 loading.tsx files across commercial/* and admin/users, supreme/tenants — see docs/design-system/08_COMPONENT_INVENTORY.md §4 for the full list",
    ],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational, but blocked until a Skeleton primitive is actually built — nothing to migrate onto yet.",
  },
  {
    legacyImplementation: "Canonical status values (Lead.status, SupremeTenant.canonicalStatus, and others) rendered as plain text",
    sharedReplacement: "components/ui/status-badge.tsx",
    replacementStatus: "IMPLEMENTED",
    affectedPages: [
      "commercial/leads/page.tsx (status column)",
      "supreme/tenants/page.tsx (status column)",
      "every other Commercial list/detail page rendering a canonical status column",
    ],
    priority: "High",
    breakingChangeRisk: "Low",
    riskNote:
      "StatusBadge is production-ready and unused (0 consumers) — the highest-value, lowest-risk adoption gap in this inventory. Blocked only on the not-yet-built per-domain canonical_ref→tone mapping (\"Canonical status-to-tone mapping\", Domain Components, DOCUMENTED_ONLY) — StatusBadge itself deliberately does not own that mapping.",
  },
  {
    legacyImplementation: "Lead.source rendered as plain text",
    sharedReplacement: "components/ui/badge.tsx",
    replacementStatus: "IMPLEMENTED",
    affectedPages: ["commercial/leads/page.tsx (source column)"],
    priority: "Low",
    breakingChangeRisk: "Low",
    riskNote: "Single-file, purely cosmetic — a free-form tag, not a canonical status, so Badge (not StatusBadge) is the correct target.",
  },
  {
    legacyImplementation: "Inline role=\"alert\" error block, one copy per page",
    sharedReplacement: "Error State (docs/design-system/02_COMPONENTS.md §2)",
    replacementStatus: "DOCUMENTED_ONLY",
    affectedPages: ["Every Commercial list/detail page's load-failure branch — 21+ pages"],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational once built; no retry/request-id behavior exists today to preserve or break.",
  },
  {
    legacyImplementation: "Inline empty-state <p> message, one copy per page",
    sharedReplacement: "Empty State (docs/design-system/02_COMPONENTS.md §2); DataTable's built-in emptyMessage is a first step but takes a plain node, not the full illustration/primary-action/secondary-action shape",
    replacementStatus: "DOCUMENTED_ONLY",
    affectedPages: ["Every Commercial list page's zero-row branch — 19+ pages"],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote: "Purely presentational; no gated action exists today to preserve or break.",
  },
  {
    legacyImplementation: "approval-decision-form.tsx and credit-approval-decision-form.tsx independently implement the same approve/reject decision panel",
    sharedReplacement: "Approval Decision Panel (components/domain/, docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md §2)",
    replacementStatus: "DOCUMENTED_ONLY",
    affectedPages: [
      "commercial/quotations/[quotationId]/approval-decision-form.tsx",
      "commercial/accounts/[accountId]/credit-approval-decision-form.tsx",
    ],
    priority: "Medium",
    breakingChangeRisk: "Medium",
    riskNote:
      "Touches real submit/decision server actions, not pure display — extraction must preserve each capability's own reason-required/permission-gated behavior exactly (COM-153/COM-157). Wait for a third real consumer before extracting, per 09_UX_DESIGN_SYSTEM_WORKSTREAM.md §4.2's \"one owner\" rule.",
  },
  {
    legacyImplementation: "Raw <input>/<select>/<textarea> form fields, one hand-styled copy per form",
    sharedReplacement: "Input / Select / Form Field (docs/design-system/02_COMPONENTS.md §2)",
    replacementStatus: "DOCUMENTED_ONLY",
    affectedPages: ["39 form/action-panel files across every Commercial module — see docs/design-system/08_COMPONENT_INVENTORY.md §4"],
    priority: "Medium",
    breakingChangeRisk: "Low",
    riskNote:
      "Large surface but mechanical if scoped to display/styling only; becomes Medium risk only if a future extraction also changes validation-state wiring (autosave, error-message binding) rather than just markup.",
  },
] as const;
