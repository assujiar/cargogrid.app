/**
 * Loyalty Program and Earning contract (CPL-316, CG-S13-CPL-018). Mirrors
 * supabase/migrations/20260801180000_create_customer_portal_loyalty_program_
 * earning.sql's own two RPC surfaces: (a) tenant-internal, staff-gated
 * (LYL:*) program/rule-version/account/earning-event admin CRUD, and (b)
 * customer-facing (Layer 4) reads of a customer's own loyalty account(s) and
 * earning history.
 *
 * The FIRST-EVER Loyalty domain contract in this repository (ADR-0024 Part D).
 */

import { z } from "zod";

// ===========================================================================
// Shared enums
// ===========================================================================

export const LOYALTY_PROGRAM_STATUSES = ["draft", "active", "inactive"] as const;
export const LoyaltyProgramStatusSchema = z.enum(LOYALTY_PROGRAM_STATUSES);
export type LoyaltyProgramStatus = z.infer<typeof LoyaltyProgramStatusSchema>;

export const LOYALTY_PROGRAM_RULE_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const LoyaltyProgramRuleVersionStatusSchema = z.enum(LOYALTY_PROGRAM_RULE_VERSION_STATUSES);
export type LoyaltyProgramRuleVersionStatus = z.infer<typeof LoyaltyProgramRuleVersionStatusSchema>;

/** The two reward types this prompt's own earning events may produce (migration design decision 5). Discount/voucher issuance is CPL-319's own scope. */
export const LOYALTY_REWARD_TYPES = ["points", "cashback"] as const;
export const LoyaltyRewardTypeSchema = z.enum(LOYALTY_REWARD_TYPES);
export type LoyaltyRewardType = z.infer<typeof LoyaltyRewardTypeSchema>;

export const LOYALTY_ACCOUNT_STATUSES = ["active", "suspended", "closed"] as const;
export const LoyaltyAccountStatusSchema = z.enum(LOYALTY_ACCOUNT_STATUSES);
export type LoyaltyAccountStatus = z.infer<typeof LoyaltyAccountStatusSchema>;

/** The only earning_basis this checkpoint's own evaluator RPC implements (migration design decision 7). Others are structurally valid but rejected at evaluation time (unsupported_earning_basis). */
export const SUPPORTED_LOYALTY_EARNING_BASES = ["per_paid_invoice_amount"] as const;

// ===========================================================================
// Staff-facing: app.loyalty_programs
// ===========================================================================

export const LoyaltyProgramSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  status: LoyaltyProgramStatusSchema,
  description: z.string().nullable(),
  createdBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyProgram = z.infer<typeof LoyaltyProgramSchema>;

export function parseLoyaltyProgram(row: Record<string, unknown>): LoyaltyProgram {
  return LoyaltyProgramSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    status: row.status,
    description: row.description ?? null,
    createdBy: row.created_by ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateLoyaltyProgramInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateLoyaltyProgramInput = z.input<typeof CreateLoyaltyProgramInputSchema>;

export const UpdateLoyaltyProgramStatusInputSchema = z.object({
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: LoyaltyProgramStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateLoyaltyProgramStatusInput = z.input<typeof UpdateLoyaltyProgramStatusInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_program_rule_versions
// ===========================================================================

export const LoyaltyProgramRuleVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  earningBasis: z.string(),
  rewardType: LoyaltyRewardTypeSchema,
  rate: z.number(),
  eligibilityConfig: z.record(z.string(), z.unknown()),
  status: LoyaltyProgramRuleVersionStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyProgramRuleVersion = z.infer<typeof LoyaltyProgramRuleVersionSchema>;

function coerceNumber(value: unknown): number {
  return typeof value === "string" ? Number(value) : (value as number);
}

export function parseLoyaltyProgramRuleVersion(row: Record<string, unknown>): LoyaltyProgramRuleVersion {
  return LoyaltyProgramRuleVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    programId: row.program_id,
    versionNumber: row.version_number,
    earningBasis: row.earning_basis,
    rewardType: row.reward_type,
    rate: coerceNumber(row.rate),
    eligibilityConfig: (row.eligibility_config as Record<string, unknown>) ?? {},
    status: row.status,
    effectiveFrom: (row.effective_from as string | null) ?? null,
    effectiveTo: (row.effective_to as string | null) ?? null,
    publishedBy: (row.published_by as string | null) ?? null,
    publishedAt: (row.published_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateLoyaltyProgramRuleVersionInputSchema = z.object({
  tenantId: z.string().uuid(),
  programId: z.string().uuid(),
  earningBasis: z.string().min(1),
  rewardType: LoyaltyRewardTypeSchema,
  rate: z.number().positive(),
  eligibilityConfig: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateLoyaltyProgramRuleVersionInput = z.input<typeof CreateLoyaltyProgramRuleVersionInputSchema>;

export const UpdateLoyaltyProgramRuleVersionDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  ruleVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  earningBasis: z.string().min(1),
  rewardType: LoyaltyRewardTypeSchema,
  rate: z.number().positive(),
  eligibilityConfig: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateLoyaltyProgramRuleVersionDraftInput = z.input<typeof UpdateLoyaltyProgramRuleVersionDraftInputSchema>;

export const PublishLoyaltyProgramRuleVersionInputSchema = z.object({
  tenantId: z.string().uuid(),
  ruleVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  effectiveFrom: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishLoyaltyProgramRuleVersionInput = z.input<typeof PublishLoyaltyProgramRuleVersionInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_accounts
// ===========================================================================

export const LoyaltyAccountSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  status: LoyaltyAccountStatusSchema,
  enrolledAt: z.string(),
  closedBy: z.string().nullable(),
  closedAt: z.string().nullable(),
  closedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyAccount = z.infer<typeof LoyaltyAccountSchema>;

export function parseLoyaltyAccount(row: Record<string, unknown>): LoyaltyAccount {
  return LoyaltyAccountSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    customerAccountId: row.customer_account_id,
    programId: row.program_id,
    status: row.status,
    enrolledAt: row.enrolled_at,
    closedBy: (row.closed_by as string | null) ?? null,
    closedAt: (row.closed_at as string | null) ?? null,
    closedReason: (row.closed_reason as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const EnrollCustomerLoyaltyAccountInputSchema = z.object({
  tenantId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EnrollCustomerLoyaltyAccountInput = z.input<typeof EnrollCustomerLoyaltyAccountInputSchema>;

export const SetLoyaltyAccountStatusInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: LoyaltyAccountStatusSchema,
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetLoyaltyAccountStatusInput = z.input<typeof SetLoyaltyAccountStatusInputSchema>;

// ===========================================================================
// Staff-facing: app.loyalty_earning_events (full internal projection)
// ===========================================================================

export const LOYALTY_EARNING_EVENT_SOURCE_TYPES = ["finance_invoice_paid", "reversal"] as const;
export const LoyaltyEarningEventSourceTypeSchema = z.enum(LOYALTY_EARNING_EVENT_SOURCE_TYPES);
export type LoyaltyEarningEventSourceType = z.infer<typeof LoyaltyEarningEventSourceTypeSchema>;

export const LoyaltyEarningEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  ruleVersionId: z.string().uuid(),
  rewardType: LoyaltyRewardTypeSchema,
  amount: z.number(),
  sourceType: LoyaltyEarningEventSourceTypeSchema,
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  correctsEventId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyEarningEvent = z.infer<typeof LoyaltyEarningEventSchema>;

export function parseLoyaltyEarningEvent(row: Record<string, unknown>): LoyaltyEarningEvent {
  return LoyaltyEarningEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    programId: row.program_id,
    ruleVersionId: row.rule_version_id,
    rewardType: row.reward_type,
    amount: coerceNumber(row.amount),
    sourceType: row.source_type,
    sourceId: (row.source_id as string | null) ?? null,
    idempotencyKey: row.idempotency_key,
    correctsEventId: (row.corrects_event_id as string | null) ?? null,
    reason: (row.reason as string | null) ?? null,
    createdBy: (row.created_by as string | null) ?? null,
    createdAt: row.created_at,
  });
}

export const EvaluateCustomerLoyaltyEarningForPaidInvoiceInputSchema = z.object({
  tenantId: z.string().uuid(),
  arOpenItemId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateCustomerLoyaltyEarningForPaidInvoiceInput = z.input<typeof EvaluateCustomerLoyaltyEarningForPaidInvoiceInputSchema>;

export const ReverseLoyaltyEarningEventInputSchema = z.object({
  tenantId: z.string().uuid(),
  eventId: z.string().uuid(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReverseLoyaltyEarningEventInput = z.input<typeof ReverseLoyaltyEarningEventInputSchema>;

// ===========================================================================
// Cursor pagination (staff surfaces, updated_at-keyed)
// ===========================================================================

export const LoyaltyUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyUpdatedAtCursor = z.input<typeof LoyaltyUpdatedAtCursorSchema>;

/** app.list_loyalty_earning_events/app.list_customer_portal_loyalty_earning_events have no updated_at column (append-only) -- keyed on created_at instead. */
export const LoyaltyCreatedAtCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type LoyaltyCreatedAtCursor = z.input<typeof LoyaltyCreatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A): app.list_customer_portal_
// loyalty_accounts / app.list_customer_portal_loyalty_earning_events
// ===========================================================================

export const CustomerPortalLoyaltyAccountSchema = z.object({
  id: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  programName: z.string(),
  status: LoyaltyAccountStatusSchema,
  enrolledAt: z.string(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerPortalLoyaltyAccount = z.infer<typeof CustomerPortalLoyaltyAccountSchema>;

export function parseCustomerPortalLoyaltyAccount(row: Record<string, unknown>): CustomerPortalLoyaltyAccount {
  return CustomerPortalLoyaltyAccountSchema.parse({
    id: row.id,
    customerAccountId: row.customer_account_id,
    programId: row.program_id,
    programName: row.program_name,
    status: row.status,
    enrolledAt: row.enrolled_at,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

/**
 * Customer-safe earning history row. Cites the evaluated rule version's own
 * human-readable earningBasis/rate directly -- NEVER the rule version's
 * internal eligibilityConfig jsonb (migration design decision, source
 * prompt: "cite the rule version's own human-readable basis, never internal
 * config JSON verbatim"). Never exposes loyaltyAccountId/programId/
 * ruleVersionId/sourceId (internal linkage).
 */
export const CustomerPortalLoyaltyEarningEventSchema = z.object({
  id: z.string().uuid(),
  programName: z.string(),
  rewardType: LoyaltyRewardTypeSchema,
  amount: z.number(),
  earningBasis: z.string(),
  rate: z.number(),
  sourceType: LoyaltyEarningEventSourceTypeSchema,
  reason: z.string().nullable(),
  correctsEventId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type CustomerPortalLoyaltyEarningEvent = z.infer<typeof CustomerPortalLoyaltyEarningEventSchema>;

export function parseCustomerPortalLoyaltyEarningEvent(row: Record<string, unknown>): CustomerPortalLoyaltyEarningEvent {
  return CustomerPortalLoyaltyEarningEventSchema.parse({
    id: row.id,
    programName: row.program_name,
    rewardType: row.reward_type,
    amount: coerceNumber(row.amount),
    earningBasis: row.earning_basis,
    rate: coerceNumber(row.rate),
    sourceType: row.source_type,
    reason: (row.reason as string | null) ?? null,
    correctsEventId: (row.corrects_event_id as string | null) ?? null,
    createdAt: row.created_at,
  });
}

/** Customer-safe, plain-language rendering of a rule version's earning_basis -- never raw internal config JSON. */
export function describeLoyaltyEarningBasis(earningBasis: string, rewardType: LoyaltyRewardType, rate: number): string {
  const rewardWord = rewardType === "points" ? "points" : "cashback";
  if (earningBasis === "per_paid_invoice_amount") {
    return `You earn ${rewardWord} equal to ${(rate * 100).toFixed(2)}% of each paid invoice's own amount.`;
  }
  return `You earn ${rewardWord} under this program's own "${earningBasis}" rule (rate ${rate}).`;
}
