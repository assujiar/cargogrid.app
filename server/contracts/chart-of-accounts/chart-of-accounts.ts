/**
 * Chart of Accounts contract (FIN-192, CG-S9-FIN-003). Mirrors
 * supabase/migrations/20260728210000_create_finance_chart_of_accounts.sql's
 * app.finance_accounts shape and the app.create_finance_account_draft /
 * app.amend_finance_account_draft / app.activate_finance_account /
 * app.deactivate_finance_account / app.get_finance_account_dependency_impact /
 * app.list_finance_accounts RPCs.
 */

import { z } from "zod";

export const FINANCE_ACCOUNT_TYPES = ["asset", "liability", "equity", "revenue", "expense"] as const;
export const FinanceAccountTypeSchema = z.enum(FINANCE_ACCOUNT_TYPES);
export type FinanceAccountType = z.infer<typeof FinanceAccountTypeSchema>;

export const FINANCE_NORMAL_BALANCES = ["debit", "credit"] as const;
export const FinanceNormalBalanceSchema = z.enum(FINANCE_NORMAL_BALANCES);
export type FinanceNormalBalance = z.infer<typeof FinanceNormalBalanceSchema>;

/** Canonical, stable mapping (Prompt 192 section 24) -- never configurable per tenant. */
export const FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE: Record<FinanceAccountType, FinanceNormalBalance> = {
  asset: "debit",
  expense: "debit",
  liability: "credit",
  equity: "credit",
  revenue: "credit",
};

export const FINANCE_ACCOUNT_STATUSES = ["draft", "active", "inactive"] as const;
export const FinanceAccountStatusSchema = z.enum(FINANCE_ACCOUNT_STATUSES);
export type FinanceAccountStatus = z.infer<typeof FinanceAccountStatusSchema>;

export const FinanceAccountSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  accountType: FinanceAccountTypeSchema,
  normalBalance: FinanceNormalBalanceSchema,
  parentAccountId: z.string().uuid().nullable(),
  isControlAccount: z.boolean(),
  isPostable: z.boolean(),
  currencyRestriction: z.string().nullable(),
  status: FinanceAccountStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceAccount = z.infer<typeof FinanceAccountSchema>;

export const CreateFinanceAccountDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable().default(null),
  code: z.string().min(1).max(20),
  name: z.string().min(1),
  accountType: FinanceAccountTypeSchema,
  normalBalance: FinanceNormalBalanceSchema,
  parentAccountId: z.string().uuid().nullable().default(null),
  isControlAccount: z.boolean().default(false),
  currencyRestriction: z.string().regex(/^[A-Z]{3}$/).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateFinanceAccountDraftInput = z.input<typeof CreateFinanceAccountDraftInputSchema>;

export const AmendFinanceAccountDraftInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1).nullable().default(null),
  currencyRestriction: z.string().regex(/^[A-Z]{3}$/).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AmendFinanceAccountDraftInput = z.input<typeof AmendFinanceAccountDraftInputSchema>;

export const ActivateFinanceAccountInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ActivateFinanceAccountInput = z.input<typeof ActivateFinanceAccountInputSchema>;

export const DeactivateFinanceAccountInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeactivateFinanceAccountInput = z.input<typeof DeactivateFinanceAccountInputSchema>;

export const FinanceAccountDependencyImpactSchema = z.object({
  accountId: z.string().uuid(),
  code: z.string(),
  activeChildAccountCount: z.number().int(),
  referencedByPublishedPostingMap: z.boolean(),
});
export type FinanceAccountDependencyImpact = z.infer<typeof FinanceAccountDependencyImpactSchema>;

/** Maps a raw app.finance_accounts row (snake_case) to this contract's camelCase shape. */
export function parseFinanceAccount(row: Record<string, unknown>): FinanceAccount {
  return FinanceAccountSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id,
    code: row.code,
    name: row.name,
    accountType: row.account_type,
    normalBalance: row.normal_balance,
    parentAccountId: row.parent_account_id,
    isControlAccount: row.is_control_account,
    isPostable: row.is_postable,
    currencyRestriction: row.currency_restriction,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.get_finance_account_dependency_impact() jsonb result to this contract's camelCase shape. */
export function parseFinanceAccountDependencyImpact(row: Record<string, unknown>): FinanceAccountDependencyImpact {
  return FinanceAccountDependencyImpactSchema.parse({
    accountId: row.accountId,
    code: row.code,
    activeChildAccountCount: row.activeChildAccountCount,
    referencedByPublishedPostingMap: row.referencedByPublishedPostingMap,
  });
}
