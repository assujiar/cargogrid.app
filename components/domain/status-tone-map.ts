/**
 * Canonical status-to-tone mapping (`docs/design-system/02_COMPONENTS.md` §1
 * "StatusBadge" implementation notes: "this binding is a `components/domain/`
 * composition concern, not yet built" -- built now. This is what unblocks the
 * highest-priority item in `docs/design-system/08_COMPONENT_INVENTORY.md` §4's
 * migration map: `StatusBadge` was production-ready with zero real consumers because
 * nothing owned the domain-specific `canonical_ref` -> tone mapping. Every value here
 * is read from the real enum each domain's own contract already defines
 * (`server/contracts/*`), not invented.
 */

import type { StatusTone } from "../ui/status-badge.tsx";
import type { LeadStatus } from "../../server/contracts/lead/lead.ts";
import type { OpportunityStage } from "../../server/contracts/opportunity/opportunity.ts";
import type { QuotationApprovalStatus, QuotationStatus } from "../../server/contracts/quotation/quotation.ts";
import type { ProspectStatus } from "../../server/contracts/prospect/prospect.ts";
import type { SalesPlanStatus } from "../../server/contracts/pipeline/pipeline.ts";
import type { AccountStatus, CustomerStatus } from "../../server/contracts/account/account.ts";
import type { CustomerContractStatus } from "../../server/contracts/contract/contract.ts";
import type { MarginRuleStatus } from "../../server/contracts/margin/margin.ts";
import type { QuotationApprovalRuleStatus } from "../../server/contracts/quotation/quotation-approval.ts";
import type { QuotationAcceptanceTokenStatus } from "../../server/contracts/quotation/quotation-acceptance.ts";
import type { ReportRunStatus } from "../../server/contracts/report/report.ts";
import type { UserStatus } from "../../server/contracts/user-lifecycle/user-lifecycle.ts";
import type { JobOrderStatus } from "../../server/contracts/job-order/job-order.ts";
import type { ShipmentOrderStatus } from "../../server/contracts/shipment-order/shipment-order.ts";
import type { ConfigVersionStatus } from "../../server/contracts/config/config.ts";
import type { FinanceAccountStatus } from "../../server/contracts/chart-of-accounts/chart-of-accounts.ts";

export interface StatusToneEntry {
  readonly tone: StatusTone;
  readonly label: string;
}

export const LEAD_STATUS_TONE_MAP: Record<LeadStatus, StatusToneEntry> = {
  new: { tone: "info", label: "New" },
  contacted: { tone: "neutral", label: "Contacted" },
  qualified: { tone: "success", label: "Qualified" },
  disqualified: { tone: "neutral", label: "Disqualified" },
  merged: { tone: "neutral", label: "Merged" },
  converted: { tone: "success", label: "Converted" },
};

export const OPPORTUNITY_STAGE_TONE_MAP: Record<OpportunityStage, StatusToneEntry> = {
  qualifying: { tone: "neutral", label: "Qualifying" },
  requirements_gathering: { tone: "info", label: "Requirements gathering" },
  ready_for_costing: { tone: "warning", label: "Ready for costing" },
  won: { tone: "success", label: "Won" },
  lost: { tone: "danger", label: "Lost" },
};

export const QUOTATION_APPROVAL_STATUS_TONE_MAP: Record<QuotationApprovalStatus, StatusToneEntry> = {
  not_required: { tone: "neutral", label: "Not required" },
  pending: { tone: "warning", label: "Pending approval" },
  approved: { tone: "success", label: "Approved" },
  rejected: { tone: "danger", label: "Rejected" },
};

export const PROSPECT_STATUS_TONE_MAP: Record<ProspectStatus, StatusToneEntry> = {
  active: { tone: "info", label: "Active" },
  disqualified: { tone: "neutral", label: "Disqualified" },
  archived: { tone: "neutral", label: "Archived" },
  merged: { tone: "neutral", label: "Merged" },
};

/** Shared shape for the three independent draft/published/archived lifecycle enums below (`SalesPlanStatus`, `MarginRuleStatus`, `QuotationApprovalRuleStatus`) -- each still gets its own `Record<...>` so TypeScript keeps exhaustiveness-checking each domain's own enum independently if one of them ever diverges. */
export const SALES_PLAN_STATUS_TONE_MAP: Record<SalesPlanStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  archived: { tone: "neutral", label: "Archived" },
};

export const MARGIN_RULE_STATUS_TONE_MAP: Record<MarginRuleStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  archived: { tone: "neutral", label: "Archived" },
};

/** FIN-191: Finance Configuration reuses PLT-121's own ConfigVersionStatus enum directly (draft/published/archived) -- one more independently-exhaustiveness-checked Record<...>, matching this file's own established "each domain gets its own Record" convention. */
export const FINANCE_CONFIG_VERSION_STATUS_TONE_MAP: Record<ConfigVersionStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  archived: { tone: "neutral", label: "Archived" },
};

/** FIN-192: Chart of Accounts' own draft/active/inactive lifecycle -- a real domain table, not the reused Configuration Engine, so its own three-state Record<...> (distinct from FINANCE_CONFIG_VERSION_STATUS_TONE_MAP's draft/published/archived above). */
export const FINANCE_ACCOUNT_STATUS_TONE_MAP: Record<FinanceAccountStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  active: { tone: "success", label: "Active" },
  inactive: { tone: "neutral", label: "Inactive" },
};

export const QUOTATION_APPROVAL_RULE_STATUS_TONE_MAP: Record<QuotationApprovalRuleStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  archived: { tone: "neutral", label: "Archived" },
};

export const QUOTATION_STATUS_TONE_MAP: Record<QuotationStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "info", label: "Submitted" },
  cancelled: { tone: "danger", label: "Cancelled" },
};

export const CUSTOMER_CONTRACT_STATUS_TONE_MAP: Record<CustomerContractStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  retired: { tone: "neutral", label: "Retired" },
};

export const ACCOUNT_STATUS_TONE_MAP: Record<AccountStatus, StatusToneEntry> = {
  active: { tone: "success", label: "Active" },
  merged: { tone: "neutral", label: "Merged" },
};

export const CUSTOMER_STATUS_TONE_MAP: Record<CustomerStatus, StatusToneEntry> = {
  active: { tone: "success", label: "Active" },
  inactive: { tone: "neutral", label: "Inactive" },
};

export const QUOTATION_ACCEPTANCE_TOKEN_STATUS_TONE_MAP: Record<QuotationAcceptanceTokenStatus, StatusToneEntry> = {
  active: { tone: "info", label: "Active" },
  consumed: { tone: "success", label: "Consumed" },
  revoked: { tone: "neutral", label: "Revoked" },
  expired: { tone: "neutral", label: "Expired" },
};

export const REPORT_RUN_STATUS_TONE_MAP: Record<ReportRunStatus, StatusToneEntry> = {
  queued: { tone: "neutral", label: "Queued" },
  running: { tone: "info", label: "Running" },
  completed: { tone: "success", label: "Completed" },
  failed: { tone: "danger", label: "Failed" },
};

const USER_STATUS_TONE_MAP: Record<UserStatus, StatusToneEntry> = {
  invited: { tone: "info", label: "Invited" },
  active: { tone: "success", label: "Active" },
  suspended: { tone: "warning", label: "Suspended" },
  revoked: { tone: "danger", label: "Revoked" },
};

/**
 * `PortalUser.status` (`server/queries/portal-users.ts`) is typed as a plain `string`,
 * not `UserStatus` -- it comes back through `app.users_directory` untyped at the query
 * boundary. Resolved defensively, mirroring `resolveTenantStatusTone`, rather than cast.
 */
export function resolvePortalUserStatusTone(status: string): StatusToneEntry {
  return (USER_STATUS_TONE_MAP as Record<string, StatusToneEntry>)[status] ?? { tone: "neutral", label: status };
}

/**
 * `SupremeTenant.canonicalStatus` (`server/queries/supreme-tenants.ts`) is typed as a
 * plain `string`, not a closed union -- the real closed set lives at the database
 * layer (`supabase/migrations/20260716075355_create_tenants.sql`'s
 * `tenants_canonical_status_check`). A `Record<string, ...>` can't be exhaustiveness-
 * checked by TypeScript the way the three maps above are, so `resolveTenantStatusTone`
 * falls back to a neutral tone + the raw value rather than throwing on an
 * unrecognized status (defensive against the DB and TS type drifting apart).
 */
const TENANT_STATUS_TONE_MAP: Record<string, StatusToneEntry> = {
  provisioning: { tone: "info", label: "Provisioning" },
  active: { tone: "success", label: "Active" },
  suspended: { tone: "warning", label: "Suspended" },
  terminated: { tone: "danger", label: "Terminated" },
};

export function resolveTenantStatusTone(canonicalStatus: string): StatusToneEntry {
  return TENANT_STATUS_TONE_MAP[canonicalStatus] ?? { tone: "neutral", label: canonicalStatus };
}

export const JOB_ORDER_STATUS_TONE_MAP: Record<JobOrderStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  confirmed: { tone: "success", label: "Confirmed" },
  cancelled: { tone: "danger", label: "Cancelled" },
};

/** Broadened at OPS-170 (Shipment Lifecycle) to the full canonical lifecycle. */
export const SHIPMENT_ORDER_STATUS_TONE_MAP: Record<ShipmentOrderStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  confirmed: { tone: "info", label: "Confirmed" },
  planned: { tone: "info", label: "Planned" },
  assigned: { tone: "info", label: "Assigned" },
  dispatched: { tone: "info", label: "Dispatched" },
  in_transit: { tone: "warning", label: "In transit" },
  delivered: { tone: "success", label: "Delivered" },
  epod: { tone: "success", label: "ePOD received" },
  closed: { tone: "success", label: "Closed" },
  held: { tone: "warning", label: "Held" },
  cancelled: { tone: "danger", label: "Cancelled" },
};
