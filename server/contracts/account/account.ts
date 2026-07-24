/**
 * Customer/Account contract (COM-155, CG-S7-COM-014). Mirrors
 * supabase/migrations/20260724290000_create_commercial_customer_account_conversion.sql's
 * app.accounts/app.account_conversions shape and the app.find_duplicate_accounts /
 * app.get_account_conversion_readiness / app.convert_quotation_to_account RPCs.
 *
 * app.accounts carries no column masking (ADR-0018's own disclosed reason: no
 * billing-shaped action exists in the fixed permissions_action_check enum) -- every field
 * here is plain, unmasked data, read directly from the base table (no *_directory view
 * exists for this entity, unlike app.quotations).
 */

import { z } from "zod";

export const ACCOUNT_STATUSES = ["active", "merged"] as const;
export const AccountStatusSchema = z.enum(ACCOUNT_STATUSES);
export type AccountStatus = z.infer<typeof AccountStatusSchema>;

export const CUSTOMER_STATUSES = ["active", "inactive"] as const;
export const CustomerStatusSchema = z.enum(CUSTOMER_STATUSES);
export type CustomerStatus = z.infer<typeof CustomerStatusSchema>;

export const ACCOUNT_CONVERSION_OUTCOMES = ["created", "linked_existing"] as const;
export const AccountConversionOutcomeSchema = z.enum(ACCOUNT_CONVERSION_OUTCOMES);
export type AccountConversionOutcome = z.infer<typeof AccountConversionOutcomeSchema>;

export const AccountSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  taxId: z.string().nullable(),
  billingAddress: z.record(z.string(), z.unknown()),
  customerStatus: CustomerStatusSchema,
  parentAccountId: z.string().uuid().nullable(),
  sourceProspectId: z.string().uuid().nullable(),
  status: AccountStatusSchema,
  mergedIntoId: z.string().uuid().nullable(),
  mergedAt: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Account = z.infer<typeof AccountSchema>;

export function parseAccount(row: Record<string, unknown>): Account {
  return AccountSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    legalName: row.legal_name,
    tradeName: row.trade_name,
    taxId: row.tax_id,
    billingAddress: row.billing_address ?? {},
    customerStatus: row.customer_status,
    parentAccountId: row.parent_account_id,
    sourceProspectId: row.source_prospect_id,
    status: row.status,
    mergedIntoId: row.merged_into_id,
    mergedAt: row.merged_at,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.get_account_conversion_readiness()'s returned row. Reason codes only, never a dollar figure. */
export const AccountConversionReadinessSchema = z.object({
  ready: z.boolean(),
  blockingReasons: z.array(z.string()),
  duplicateCandidateIds: z.array(z.string().uuid()),
});
export type AccountConversionReadiness = z.infer<typeof AccountConversionReadinessSchema>;

export function parseAccountConversionReadiness(row: Record<string, unknown>): AccountConversionReadiness {
  return AccountConversionReadinessSchema.parse({
    ready: row.ready,
    blockingReasons: row.blocking_reasons ?? [],
    duplicateCandidateIds: row.duplicate_candidate_ids ?? [],
  });
}

export const FindDuplicateAccountsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  legalName: z.string().min(1),
  taxId: z.string().nullable().default(null),
});
export type FindDuplicateAccountsInput = z.input<typeof FindDuplicateAccountsInputSchema>;

export const GetAccountConversionReadinessInputSchema = z.object({
  quotationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetAccountConversionReadinessInput = z.input<typeof GetAccountConversionReadinessInputSchema>;

/** targetAccountId set = the alternative "link to existing" flow (after duplicate review); null = create a brand-new account from the source snapshot. parentAccountId is independent of targetAccountId -- only meaningful on the create-new path. */
export const ConvertQuotationToAccountInputSchema = z.object({
  quotationId: z.string().uuid(),
  targetAccountId: z.string().uuid().nullable().default(null),
  parentAccountId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConvertQuotationToAccountInput = z.input<typeof ConvertQuotationToAccountInputSchema>;
