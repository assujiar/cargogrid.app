/**
 * Full Lineage into Job Order contract (COM-160, CG-S7-COM-019). Mirrors
 * supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql's
 * app.job_order_handoffs/app.job_order_handoffs_directory shape and its RPC.
 *
 * Commercial's own scope ends at this one handoff record -- this contract models the
 * JobOrderDraftInput snapshot exactly as Commercial produces it. It is not, and must
 * never become, a second Job Order domain contract; Phase 3 Operations owns that.
 */

import { z } from "zod";

export const JOB_ORDER_HANDOFF_STATUSES = ["prepared", "delivered"] as const;
export const JobOrderHandoffStatusSchema = z.enum(JOB_ORDER_HANDOFF_STATUSES);
export type JobOrderHandoffStatus = z.infer<typeof JobOrderHandoffStatusSchema>;

/** The JobOrderDraftInput snapshot shape app.build_job_order_draft_payload assembles -- present only when payloadMasked=false. */
export const JobOrderDraftInputSchema = z.object({
  schemaVersion: z.number().int().positive(),
  source: z.object({
    quotationId: z.string().uuid(),
    quoteNumber: z.string(),
    versionNumber: z.number().int().positive(),
    opportunityId: z.string().uuid(),
    prospectId: z.string().uuid(),
    accountConversionId: z.string().uuid(),
  }),
  customer: z.object({
    accountId: z.string().uuid(),
    customerSnapshot: z.record(z.string(), z.unknown()),
    contactId: z.string().uuid().nullable(),
    contactName: z.string().nullable(),
    contactEmail: z.string().nullable(),
    contactPhone: z.string().nullable(),
  }),
  cargoService: z.record(z.string(), z.unknown()),
  pricing: z.object({
    currency: z.string(),
    subtotalAmount: z.coerce.number(),
    discountAmount: z.coerce.number(),
    taxAmount: z.coerce.number(),
    totalAmount: z.coerce.number(),
    lines: z.array(z.record(z.string(), z.unknown())),
  }),
  contract: z
    .object({
      customerContractId: z.string().uuid(),
      rootContractId: z.string().uuid(),
      versionNumber: z.number().int().positive(),
      status: z.string(),
    })
    .nullable(),
  credit: z
    .object({
      outcome: z.string(),
      checkedAt: z.string(),
    })
    .nullable(),
  acceptance: z.object({
    decidedByName: z.string(),
    decidedAt: z.string(),
    decision: z.string(),
  }),
});
export type JobOrderDraftInput = z.infer<typeof JobOrderDraftInputSchema>;

export const JobOrderHandoffSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  quotationId: z.string().uuid(),
  accountId: z.string().uuid(),
  purpose: z.string(),
  schemaVersion: z.number().int().positive(),
  status: JobOrderHandoffStatusSchema,
  payload: JobOrderDraftInputSchema.nullable(),
  payloadHash: z.string().nullable(),
  payloadMasked: z.boolean(),
  downstreamReference: z.string().nullable(),
  deliveredAt: z.string().nullable(),
  preparedByAuthUserId: z.string().uuid(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type JobOrderHandoff = z.infer<typeof JobOrderHandoffSchema>;

export function parseJobOrderHandoff(row: Record<string, unknown>): JobOrderHandoff {
  return JobOrderHandoffSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    quotationId: row.quotation_id,
    accountId: row.account_id,
    purpose: row.purpose,
    schemaVersion: row.schema_version,
    status: row.status,
    payload: row.payload ?? null,
    payloadHash: row.payload_hash ?? null,
    payloadMasked: row.payload_masked,
    downstreamReference: row.downstream_reference,
    deliveredAt: row.delivered_at,
    preparedByAuthUserId: row.prepared_by_auth_user_id,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

export const PrepareJobOrderHandoffInputSchema = z.object({
  quotationId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareJobOrderHandoffInput = z.input<typeof PrepareJobOrderHandoffInputSchema>;
