/**
 * Quotation Builder contract (COM-151, CG-S7-COM-010). Mirrors
 * supabase/migrations/20260724210000_create_commercial_quotation_builder.sql's
 * app.quotations/app.quotation_lines/app.quotations_directory/app.quotation_lines_directory
 * shape and their RPCs. Versioning (Prompt 152) and approval routing (Prompt 153) are not
 * modeled here -- see the migration's own header for the exact scope boundary.
 */

import { z } from "zod";

export const QUOTATION_STATUSES = ["draft", "submitted", "cancelled"] as const;
export const QuotationStatusSchema = z.enum(QUOTATION_STATUSES);
export type QuotationStatus = z.infer<typeof QuotationStatusSchema>;

export const QUOTATION_LINE_TYPES = ["service", "surcharge", "fee", "discount"] as const;
export const QuotationLineTypeSchema = z.enum(QUOTATION_LINE_TYPES);
export type QuotationLineType = z.infer<typeof QuotationLineTypeSchema>;

/** app.quotations.customer_snapshot is a bounded jsonb snapshot copied from app.prospects at creation time (migration header) -- these are the well-known keys app.create_quotation_draft writes. */
export const CustomerSnapshotSchema = z.object({
  legalName: z.string().nullable().optional(),
  tradeName: z.string().nullable().optional(),
  billingAddress: z.record(z.string(), z.unknown()).nullable().optional(),
  contactName: z.string().nullable().optional(),
  contactEmail: z.string().nullable().optional(),
  contactPhone: z.string().nullable().optional(),
});
export type CustomerSnapshot = z.infer<typeof CustomerSnapshotSchema>;

function parseCustomerSnapshot(raw: unknown): CustomerSnapshot {
  const row = (raw ?? {}) as Record<string, unknown>;
  return CustomerSnapshotSchema.parse({
    legalName: row.legal_name ?? null,
    tradeName: row.trade_name ?? null,
    billingAddress: (row.billing_address as Record<string, unknown> | null | undefined) ?? null,
    contactName: row.contact_name ?? null,
    contactEmail: row.contact_email ?? null,
    contactPhone: row.contact_phone ?? null,
  });
}

/** app.quotations.terms is a real, bounded whitelist (payment_terms/incoterm/notes) -- app.update_quotation_terms rejects any other key server-side (migration's own check_violation). */
export const QuotationTermsSchema = z.object({
  paymentTerms: z.string().max(200).nullable().optional(),
  incoterm: z.string().max(20).nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
});
export type QuotationTerms = z.infer<typeof QuotationTermsSchema>;

export function toTermsJson(terms: QuotationTerms | null | undefined): Record<string, string> {
  if (!terms) return {};
  const json: Record<string, string> = {};
  if (terms.paymentTerms) json.payment_terms = terms.paymentTerms;
  if (terms.incoterm) json.incoterm = terms.incoterm;
  if (terms.notes) json.notes = terms.notes;
  return json;
}

function parseTerms(raw: unknown): QuotationTerms {
  const row = (raw ?? {}) as Record<string, unknown>;
  return QuotationTermsSchema.parse({
    paymentTerms: row.payment_terms ?? null,
    incoterm: row.incoterm ?? null,
    notes: row.notes ?? null,
  });
}

/** Maps a raw app.quotations_directory row (snake_case) to this contract's camelCase shape. sellMasked mirrors app.opportunities_directory's own valueAmount masking -- COM:View selling price gates every monetary total. */
export const QuotationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  quoteNumber: z.string(),
  opportunityId: z.string().uuid(),
  sourceOpportunityVersion: z.number().int().positive(),
  prospectId: z.string().uuid(),
  contactId: z.string().uuid().nullable(),
  customerSnapshot: CustomerSnapshotSchema,
  currency: z.string(),
  validityFrom: z.string(),
  validityTo: z.string(),
  terms: QuotationTermsSchema,
  subtotalAmount: z.coerce.number().nullable(),
  discountAmount: z.coerce.number().nullable(),
  taxAmount: z.coerce.number().nullable(),
  totalAmount: z.coerce.number().nullable(),
  sellMasked: z.boolean(),
  status: QuotationStatusSchema,
  cancelReason: z.string().nullable(),
  clonedFromId: z.string().uuid().nullable(),
  documentRef: z.string().nullable(),
  submittedAt: z.string().nullable(),
  submittedBy: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  /** COM-152: the version-1 row's own id -- every version sharing one quote_number shares this value. */
  rootQuotationId: z.string().uuid(),
  /** COM-152: 1 for the first version, monotonically incremented per root by app.create_quotation_revision. */
  versionNumber: z.number().int().positive(),
  /** COM-152: true for exactly one row per rootQuotationId -- the latest version. Line/term mutation and submit all require this. */
  isCurrent: z.boolean(),
  supersededById: z.string().uuid().nullable(),
  /** COM-152: why this version was created -- null only for the original version-1 row. */
  revisionReason: z.string().nullable(),
});
export type Quotation = z.infer<typeof QuotationSchema>;

export function parseQuotation(row: Record<string, unknown>): Quotation {
  return QuotationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    quoteNumber: row.quote_number,
    opportunityId: row.opportunity_id,
    sourceOpportunityVersion: row.source_opportunity_version,
    prospectId: row.prospect_id,
    contactId: row.contact_id,
    customerSnapshot: parseCustomerSnapshot(row.customer_snapshot),
    currency: row.currency,
    validityFrom: row.validity_from,
    validityTo: row.validity_to,
    terms: parseTerms(row.terms),
    subtotalAmount: row.subtotal_amount,
    discountAmount: row.discount_amount,
    taxAmount: row.tax_amount,
    totalAmount: row.total_amount,
    sellMasked: row.sell_masked ?? false,
    status: row.status,
    cancelReason: row.cancel_reason,
    clonedFromId: row.cloned_from_id,
    documentRef: row.document_ref,
    submittedAt: row.submitted_at,
    submittedBy: row.submitted_by,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    rootQuotationId: row.root_quotation_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    supersededById: row.superseded_by_id,
    revisionReason: row.revision_reason,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.quotation_lines_directory row -- two independent masking dimensions (sellMasked for unit/discount/gross/tax/total, costMasked for the cost/margin snapshot). */
export const QuotationLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  quotationId: z.string().uuid(),
  lineNo: z.number().int().positive(),
  lineType: QuotationLineTypeSchema,
  description: z.string(),
  marginCalculationId: z.string().uuid().nullable(),
  quantity: z.coerce.number(),
  unitPrice: z.coerce.number().nullable(),
  discountPct: z.coerce.number().nullable(),
  taxPct: z.coerce.number(),
  lineGrossAmount: z.coerce.number().nullable(),
  lineDiscountAmount: z.coerce.number().nullable(),
  lineTaxAmount: z.coerce.number().nullable(),
  lineTotal: z.coerce.number().nullable(),
  costAmountSnapshot: z.coerce.number().nullable(),
  marginPctSnapshot: z.coerce.number().nullable(),
  sellMasked: z.boolean(),
  costMasked: z.boolean(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type QuotationLine = z.infer<typeof QuotationLineSchema>;

export function parseQuotationLine(row: Record<string, unknown>): QuotationLine {
  return QuotationLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    quotationId: row.quotation_id,
    lineNo: row.line_no,
    lineType: row.line_type,
    description: row.description,
    marginCalculationId: row.margin_calculation_id,
    quantity: row.quantity,
    unitPrice: row.unit_price,
    discountPct: row.discount_pct,
    taxPct: row.tax_pct,
    lineGrossAmount: row.line_gross_amount,
    lineDiscountAmount: row.line_discount_amount,
    lineTaxAmount: row.line_tax_amount,
    lineTotal: row.line_total,
    costAmountSnapshot: row.cost_amount_snapshot,
    marginPctSnapshot: row.margin_pct_snapshot,
    sellMasked: row.sell_masked ?? false,
    costMasked: row.cost_masked ?? false,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const QuotationReadinessSchema = z.object({
  ready: z.boolean(),
  blockingReasons: z.array(z.string()),
});
export type QuotationReadiness = z.infer<typeof QuotationReadinessSchema>;

export function parseQuotationReadiness(row: Record<string, unknown>): QuotationReadiness {
  return QuotationReadinessSchema.parse({
    ready: row.ready,
    blockingReasons: row.blocking_reasons ?? [],
  });
}

export const CreateQuotationDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  validityTo: z.string(),
  contactId: z.string().uuid().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateQuotationDraftInput = z.input<typeof CreateQuotationDraftInputSchema>;

export const CloneQuotationInputSchema = z.object({
  sourceQuotationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CloneQuotationInput = z.input<typeof CloneQuotationInputSchema>;

export const AddQuotationLineInputSchema = z.object({
  quotationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  lineType: QuotationLineTypeSchema,
  description: z.string().min(1),
  marginCalculationId: z.string().uuid().nullable().default(null),
  quantity: z.number().nonnegative(),
  unitPrice: z.number().nonnegative(),
  discountPct: z.number().min(0).max(100).default(0),
  taxPct: z.number().min(0).max(100).default(0),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddQuotationLineInput = z.input<typeof AddQuotationLineInputSchema>;

export const RemoveQuotationLineInputSchema = z.object({
  quotationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  lineId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveQuotationLineInput = z.input<typeof RemoveQuotationLineInputSchema>;

export const UpdateQuotationTermsInputSchema = z.object({
  quotationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  validityFrom: z.string(),
  validityTo: z.string(),
  terms: QuotationTermsSchema.default({}),
  contactId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateQuotationTermsInput = z.input<typeof UpdateQuotationTermsInputSchema>;

export const SubmitQuotationInputSchema = z.object({
  quotationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitQuotationInput = z.input<typeof SubmitQuotationInputSchema>;

/** COM-152: sourceQuotationId may be the current version (the ordinary "revise" flow) or any historical version of the same root (the "restore as new draft" alternative flow) -- app.create_quotation_revision handles both identically. */
export const CreateQuotationRevisionInputSchema = z.object({
  sourceQuotationId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateQuotationRevisionInput = z.input<typeof CreateQuotationRevisionInputSchema>;
