/**
 * Vendor Banking and Tax Security read queries (PRC-254, CG-S11-PRC-005). Thin,
 * typed wrappers around app.get_vendor_bank_account_masked/
 * app.list_vendor_bank_accounts_masked/app.get_vendor_tax_identity_masked/
 * app.list_vendor_tax_identities_masked/app.get_vendor_payment_term_proposal/
 * app.list_vendor_payment_term_proposals/app.get_vendor_financial_verification_status
 * (supabase/migrations/20260730610000_create_procurement_vendor_financial_security.sql).
 *
 * Every read here is the MASKED default (last4 + status, never plaintext/ciphertext)
 * -- see server/mutations/vendor-financial.ts for the two narrow, privileged, audited
 * reveal RPCs, which are mutations (not reads) precisely because a reveal is itself
 * an audited event, never a passive query.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorBankAccount,
  parseVendorTaxIdentity,
  parseVendorPaymentTermProposal,
  parseVendorFinancialVerificationStatus,
  type VendorBankAccount,
  type VendorTaxIdentity,
  type VendorPaymentTermProposal,
  type VendorFinancialVerificationStatus,
  type VendorFinancialLifecycleStatus,
  type VendorPaymentTermProposalStatus,
} from "../contracts/vendor-financial/vendor-financial.ts";

export type VendorFinancialQueryClient = Pick<SupabaseClient, "rpc">;

export class VendorFinancialQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorFinancialQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

// --- Bank accounts (masked) ---

export async function getVendorBankAccountMasked(client: VendorFinancialQueryClient, accountId: string, actorAuthUserId: string): Promise<VendorBankAccount> {
  const { data, error } = await client.rpc("get_vendor_bank_account_masked", { p_account_id: accountId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorFinancialQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialQueryError("get_vendor_bank_account_masked returned no row");
  return parseVendorBankAccount(row);
}

export async function listVendorBankAccountsMasked(
  client: VendorFinancialQueryClient,
  vendorMasterRecordId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorFinancialLifecycleStatus | null; limit?: number; afterId?: string | null },
): Promise<VendorBankAccount[]> {
  const { data, error } = await client.rpc("list_vendor_bank_accounts_masked", {
    p_vendor_master_record_id: vendorMasterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorFinancialQueryError(error.message);
  return rows(data).map(parseVendorBankAccount);
}

// --- Tax identities (masked) ---

export async function getVendorTaxIdentityMasked(client: VendorFinancialQueryClient, taxIdentityId: string, actorAuthUserId: string): Promise<VendorTaxIdentity> {
  const { data, error } = await client.rpc("get_vendor_tax_identity_masked", { p_tax_identity_id: taxIdentityId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorFinancialQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialQueryError("get_vendor_tax_identity_masked returned no row");
  return parseVendorTaxIdentity(row);
}

export async function listVendorTaxIdentitiesMasked(
  client: VendorFinancialQueryClient,
  vendorMasterRecordId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorFinancialLifecycleStatus | null; limit?: number; afterId?: string | null },
): Promise<VendorTaxIdentity[]> {
  const { data, error } = await client.rpc("list_vendor_tax_identities_masked", {
    p_vendor_master_record_id: vendorMasterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorFinancialQueryError(error.message);
  return rows(data).map(parseVendorTaxIdentity);
}

// --- Payment-term change proposals ---

export async function getVendorPaymentTermProposal(client: VendorFinancialQueryClient, proposalId: string, actorAuthUserId: string): Promise<VendorPaymentTermProposal> {
  const { data, error } = await client.rpc("get_vendor_payment_term_proposal", { p_proposal_id: proposalId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorFinancialQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialQueryError("get_vendor_payment_term_proposal returned no row");
  return parseVendorPaymentTermProposal(row);
}

export async function listVendorPaymentTermProposals(
  client: VendorFinancialQueryClient,
  vendorMasterRecordId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorPaymentTermProposalStatus | null; limit?: number; afterId?: string | null },
): Promise<VendorPaymentTermProposal[]> {
  const { data, error } = await client.rpc("list_vendor_payment_term_proposals", {
    p_vendor_master_record_id: vendorMasterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 100,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new VendorFinancialQueryError(error.message);
  return rows(data).map(parseVendorPaymentTermProposal);
}

// --- Downstream composition (design note 11) ---

/** The single downstream-composable read (Sec.13/33) a future Finance/Sourcing/PO/invoice-matching capability composes against -- "verified bank account exists: yes/no, verified tax identity exists: yes/no, on hold: yes/no", nothing more. Never composed here. */
export async function getVendorFinancialVerificationStatus(client: VendorFinancialQueryClient, vendorMasterRecordId: string, actorAuthUserId: string): Promise<VendorFinancialVerificationStatus> {
  const { data, error } = await client.rpc("get_vendor_financial_verification_status", { p_vendor_master_record_id: vendorMasterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new VendorFinancialQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialQueryError("get_vendor_financial_verification_status returned no row");
  return parseVendorFinancialVerificationStatus(row);
}
