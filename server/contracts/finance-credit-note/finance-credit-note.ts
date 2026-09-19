/**
 * Finance Credit Note contract (CG-AUDIT-2026-09-02 B3). Mirrors
 * supabase/migrations/20260919020000_b3_finance_credit_note.sql's
 * app.finance_credit_notes shape and app.issue_finance_credit_note RPC.
 */

import { z } from "zod";

export const FinanceCreditNoteSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  companyId: z.string().uuid().nullable(),
  invoiceId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  currency: z.string(),
  amount: z.coerce.number(),
  reason: z.string(),
  arOpenItemId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  issuedBy: z.string().nullable(),
  issuedAt: z.string(),
  createdAt: z.string(),
});
export type FinanceCreditNote = z.infer<typeof FinanceCreditNoteSchema>;

export function parseFinanceCreditNote(row: Record<string, unknown>): FinanceCreditNote {
  return FinanceCreditNoteSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    companyId: row.company_id ?? null,
    invoiceId: row.invoice_id,
    customerAccountId: row.customer_account_id,
    currency: row.currency,
    amount: row.amount,
    reason: row.reason,
    arOpenItemId: row.ar_open_item_id ?? null,
    idempotencyKey: row.idempotency_key,
    issuedBy: row.issued_by ?? null,
    issuedAt: row.issued_at,
    createdAt: row.created_at,
  });
}

export const IssueFinanceCreditNoteInputSchema = z.object({
  tenantId: z.string().uuid(),
  invoiceId: z.string().uuid(),
  amount: z.number().positive(),
  reason: z.string().min(1),
  creditDate: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type IssueFinanceCreditNoteInput = z.input<typeof IssueFinanceCreditNoteInputSchema>;
