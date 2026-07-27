/**
 * Mock CargoGrid business data for `/internal/design-system/domain-examples`
 * (CargoGrid UI Modernization checkpoint 3). Every value below is a literal, invented
 * example — never fetched from Supabase, never a real tenant/lead/quotation id. Do not
 * wire this module to any query/mutation; its only purpose is to give the showcase's
 * real shared components (StatusBadge, Badge, Banner, DataTable, Pagination) something
 * domain-shaped to render.
 */

export const MOCK_LEAD_STATUSES = [
  { status: "new", contactName: "Amara Chen", company: "Halcyon Freight Co." },
  { status: "qualified", contactName: "Marcus Obi", company: "Redline Logistics" },
  { status: "disqualified", contactName: "Sofia Reyes", company: "Northgate Traders" },
] as const;

export const MOCK_OPPORTUNITY_STAGES = [
  { stage: "prospecting", probability: 10, name: "Q3 ocean freight RFQ — Halcyon" },
  { stage: "negotiation", probability: 60, name: "Annual air freight contract — Redline" },
  { stage: "closed_won", probability: 100, name: "Warehousing renewal — Northgate" },
  { stage: "closed_lost", probability: 0, name: "Spot rate request — Delacroix Imports" },
] as const;

export const MOCK_QUOTATION_APPROVAL = {
  quotationNumber: "QUO-2026-00412",
  customer: "Redline Logistics",
  totalAmount: "USD 48,200.00",
  status: "pending_approval" as const,
  submittedBy: "J. Alvarez",
  marginPercent: 8.5,
};

export const MOCK_MARGIN_WARNING = {
  quotationNumber: "QUO-2026-00412",
  marginPercent: 8.5,
  minimumMarginPercent: 12,
};

export const MOCK_CREDIT_HOLD = {
  accountName: "Northgate Traders",
  outcome: "hold" as const,
  checkedAt: "2026-07-20",
};

export const MOCK_CONTRACT_EXPIRY = {
  contractNumber: "CTR-2025-00098",
  customer: "Halcyon Freight Co.",
  expiresOn: "2026-08-15",
  daysRemaining: 20,
};

export const MOCK_RATE_VALIDITY = {
  rateVersion: "RATE-OCEAN-USWC-2026Q3",
  validFrom: "2026-07-01",
  validTo: "2026-09-30",
  status: "active" as const,
};

export const MOCK_JOB_ORDER_HANDOFF = {
  quotationNumber: "QUO-2026-00398",
  customer: "Redline Logistics",
  acceptedAt: "2026-07-22",
  contractLinked: true,
  creditOutcome: "cleared" as const,
};

export const MOCK_ACCOUNT_HEADER = {
  accountName: "Redline Logistics",
  owner: "J. Alvarez",
  status: "active" as const,
  creditStatus: "cleared" as const,
};

export const MOCK_PIPELINE_ROWS = [
  { name: "Q3 ocean freight RFQ — Halcyon", stage: "prospecting", owner: "M. Tan", value: "USD 22,000" },
  { name: "Annual air freight contract — Redline", stage: "negotiation", owner: "J. Alvarez", value: "USD 148,000" },
  { name: "Warehousing renewal — Northgate", stage: "closed_won", owner: "M. Tan", value: "USD 61,500" },
] as const;

export const MOCK_APPROVAL_TIMELINE = [
  { at: "2026-07-18T09:02:00Z", actor: "J. Alvarez", event: "Submitted for approval" },
  { at: "2026-07-19T14:30:00Z", actor: "R. Nakamura", event: "Escalated — over margin threshold" },
  { at: "2026-07-20T11:15:00Z", actor: "S. Okafor", event: "Approved with condition" },
] as const;
