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
import type { QuotationApprovalStatus } from "../../server/contracts/quotation/quotation.ts";

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
