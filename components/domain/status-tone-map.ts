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
import type { FinancePeriodStatus } from "../../server/contracts/fiscal-period/fiscal-period.ts";
import type { FinanceExchangeRateStatus } from "../../server/contracts/currency-exchange-rate/currency-exchange-rate.ts";
import type { FinanceTaxRuleStatus } from "../../server/contracts/tax-baseline/tax-baseline.ts";
import type { FinanceArOpenItemStatus } from "../../server/contracts/accounts-receivable/accounts-receivable.ts";
import type { FinanceInvoiceStatus } from "../../server/contracts/invoice/invoice.ts";
import type { FinanceReceiptStatus } from "../../server/contracts/receipt-allocation/receipt-allocation.ts";
import type { FinanceApOpenItemStatus } from "../../server/contracts/accounts-payable/accounts-payable.ts";
import type { FinanceVendorBillStatus } from "../../server/contracts/vendor-bill/vendor-bill.ts";
import type { FinanceSettlementStatus } from "../../server/contracts/settlement/settlement.ts";
import type { FinanceJournalStatus } from "../../server/contracts/journal/journal.ts";
import type { FinanceLifecycleCanonicalState } from "../../server/contracts/lifecycle/lifecycle.ts";

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

/** FIN-193: Fiscal Period's own open/soft_closed/closed lifecycle -- a real domain table, own three-state Record<...>, distinct from FIN-192's draft/active/inactive one. */
export const FINANCE_PERIOD_STATUS_TONE_MAP: Record<FinancePeriodStatus, StatusToneEntry> = {
  open: { tone: "success", label: "Open" },
  soft_closed: { tone: "warning", label: "Soft-closed" },
  closed: { tone: "neutral", label: "Closed" },
};

/** FIN-194: Currency Exchange Rate's own draft/approved/archived lifecycle -- versioned-quote status, distinct from FIN-191's config-version and FIN-192's account-lifecycle Record<...>s. */
export const FINANCE_EXCHANGE_RATE_STATUS_TONE_MAP: Record<FinanceExchangeRateStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  approved: { tone: "success", label: "Approved" },
  archived: { tone: "neutral", label: "Archived" },
};

/** FIN-195: Tax Baseline's own draft/approved/archived lifecycle -- mirrors FIN-194's finance_exchange_rates lifecycle shape exactly (own independently-exhaustiveness-checked Record<...>). */
export const FINANCE_TAX_RULE_STATUS_TONE_MAP: Record<FinanceTaxRuleStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  approved: { tone: "success", label: "Approved" },
  archived: { tone: "neutral", label: "Archived" },
};

/** FIN-196: Accounts Receivable's own balance-derived lifecycle (open/partial/paid) -- distinct from every prior FIN capability's own three-state Record<...> (this one is not draft/approve-shaped at all). */
export const FINANCE_AR_OPEN_ITEM_STATUS_TONE_MAP: Record<FinanceArOpenItemStatus, StatusToneEntry> = {
  open: { tone: "warning", label: "Open" },
  partial: { tone: "info", label: "Partial" },
  paid: { tone: "success", label: "Paid" },
};

/** FIN-197: Customer Invoice's own draft/submitted/approved/issued/void lifecycle -- five states, distinct from every prior FIN capability's own Record<...>. */
export const FINANCE_INVOICE_STATUS_TONE_MAP: Record<FinanceInvoiceStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "info", label: "Submitted" },
  approved: { tone: "warning", label: "Approved" },
  issued: { tone: "success", label: "Issued" },
  void: { tone: "danger", label: "Void" },
};

/** FIN-198: Receipt and Payment Allocation's own captured/void lifecycle -- distinct from every prior FIN capability's own Record<...>. */
export const FINANCE_RECEIPT_STATUS_TONE_MAP: Record<FinanceReceiptStatus, StatusToneEntry> = {
  captured: { tone: "success", label: "Captured" },
  void: { tone: "danger", label: "Void" },
};

/** FIN-199: Accounts Payable's own balance-derived lifecycle (open/partial/settled) -- the vendor-side mirror of FIN-196's own AR status map, distinct wording ("settled" vs. "paid"). */
export const FINANCE_AP_OPEN_ITEM_STATUS_TONE_MAP: Record<FinanceApOpenItemStatus, StatusToneEntry> = {
  open: { tone: "warning", label: "Open" },
  partial: { tone: "info", label: "Partial" },
  settled: { tone: "success", label: "Settled" },
};

/** FIN-200: Vendor Bill's own draft -> submitted -> approved -> posted -> void lifecycle -- distinct from FIN-197's own Invoice map even though the label set is identical, since each capability owns its own Record<...>. */
export const FINANCE_VENDOR_BILL_STATUS_TONE_MAP: Record<FinanceVendorBillStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "info", label: "Submitted" },
  approved: { tone: "warning", label: "Approved" },
  posted: { tone: "success", label: "Posted" },
  void: { tone: "danger", label: "Void" },
};

/** FIN-201: Settlement's own draft -> submitted -> approved -> executed -> posted -> void/reversed lifecycle -- seven states, distinct from FIN-200's own Vendor Bill map (execution is its own canonical state, and a posted settlement's own governed correction is a distinct "reversed" terminal, not the shared "void" pre-execution cancellation). */
export const FINANCE_SETTLEMENT_STATUS_TONE_MAP: Record<FinanceSettlementStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "info", label: "Submitted" },
  approved: { tone: "warning", label: "Approved" },
  executed: { tone: "warning", label: "Executed" },
  posted: { tone: "success", label: "Posted" },
  void: { tone: "danger", label: "Void" },
  reversed: { tone: "danger", label: "Reversed" },
};

/** FIN-203: Double-Entry Journal's own draft -> submitted -> approved -> posted -> void lifecycle -- shared by both manual and system (subledger-sourced) journals, though a system journal only ever appears as posted. */
export const FINANCE_JOURNAL_STATUS_TONE_MAP: Record<FinanceJournalStatus, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "info", label: "Submitted" },
  approved: { tone: "warning", label: "Approved" },
  posted: { tone: "success", label: "Posted" },
  void: { tone: "danger", label: "Void" },
};

/** FIN-205: the one shared canonical-state vocabulary across invoice/vendor_bill/receipt/settlement/subledger_batch/journal (`app.finance_lifecycle_editability_matrix`) -- rendered alongside each domain's own concrete-status badge above, never replacing it, since the canonical bucket deliberately coarsens some domain-specific detail (e.g. a settlement's own 'approved' and 'executed' concrete statuses both render this same 'Approved' canonical tone). */
export const FINANCE_LIFECYCLE_CANONICAL_STATE_TONE_MAP: Record<FinanceLifecycleCanonicalState, StatusToneEntry> = {
  draft: { tone: "neutral", label: "Draft" },
  in_review: { tone: "info", label: "In review" },
  approved: { tone: "warning", label: "Approved" },
  posted: { tone: "success", label: "Posted" },
  corrected: { tone: "danger", label: "Corrected" },
  discarded: { tone: "neutral", label: "Discarded" },
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
