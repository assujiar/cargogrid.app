/**
 * Opportunity Management contract (COM-147, CG-S7-COM-006). Mirrors
 * supabase/migrations/20260723210000_create_commercial_opportunity_management.sql's
 * app.opportunities/app.opportunity_stage_history/app.opportunities_directory shape and
 * their RPCs.
 */

import { z } from "zod";

export const OPPORTUNITY_STAGES = ["qualifying", "requirements_gathering", "ready_for_costing", "won", "lost"] as const;
export const OpportunityStageSchema = z.enum(OPPORTUNITY_STAGES);
export type OpportunityStage = z.infer<typeof OpportunityStageSchema>;

export const OpportunityRequirementsSchema = z.object({
  serviceType: z.string().nullable().optional(),
  cargoDescription: z.string().nullable().optional(),
  origin: z.string().nullable().optional(),
  destination: z.string().nullable().optional(),
  targetReadyDate: z.string().nullable().optional(),
  specialInstructions: z.string().nullable().optional(),
});
export type OpportunityRequirements = z.infer<typeof OpportunityRequirementsSchema>;

/** app.opportunities.requirements is a bounded jsonb snapshot (COM-147 build log §0 -- no canonical service/cargo/lane master exists yet); this maps the well-known snake_case keys the DB functions read/write. */
export function toRequirementsJson(requirements: OpportunityRequirements | null | undefined): Record<string, string | null> | null {
  if (!requirements) {
    return null;
  }
  return {
    service_type: requirements.serviceType ?? null,
    cargo_description: requirements.cargoDescription ?? null,
    origin: requirements.origin ?? null,
    destination: requirements.destination ?? null,
    target_ready_date: requirements.targetReadyDate ?? null,
    special_instructions: requirements.specialInstructions ?? null,
  };
}

function parseRequirements(raw: unknown): OpportunityRequirements {
  const row = (raw ?? {}) as Record<string, unknown>;
  return OpportunityRequirementsSchema.parse({
    serviceType: row.service_type ?? null,
    cargoDescription: row.cargo_description ?? null,
    origin: row.origin ?? null,
    destination: row.destination ?? null,
    targetReadyDate: row.target_ready_date ?? null,
    specialInstructions: row.special_instructions ?? null,
  });
}

export const OpportunitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  prospectId: z.string().uuid(),
  accountRef: z.string().nullable(),
  name: z.string(),
  stage: OpportunityStageSchema,
  probability: z.number().int().min(0).max(100).nullable(),
  valueAmount: z.coerce.number().nonnegative().nullable(),
  valueCurrency: z.string().nullable(),
  valueMasked: z.boolean().nullable().optional(),
  requirements: OpportunityRequirementsSchema,
  nextAction: z.string().nullable(),
  nextActionDueAt: z.string().nullable(),
  closeReason: z.string().nullable(),
  clonedFromId: z.string().uuid().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Opportunity = z.infer<typeof OpportunitySchema>;

export const OpportunityStageHistoryEntrySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  opportunityId: z.string().uuid(),
  fromStage: OpportunityStageSchema.nullable(),
  toStage: OpportunityStageSchema,
  probability: z.number().int().min(0).max(100),
  reason: z.string().nullable(),
  changedBy: z.string().nullable(),
  changedAt: z.string(),
});
export type OpportunityStageHistoryEntry = z.infer<typeof OpportunityStageHistoryEntrySchema>;

export const CostingReadinessSchema = z.object({
  ready: z.boolean(),
  missing: z.array(z.string()),
});
export type CostingReadiness = z.infer<typeof CostingReadinessSchema>;

export const CreateOpportunityInputSchema = z.object({
  tenantId: z.string().uuid(),
  prospectId: z.string().uuid(),
  name: z.string().min(1),
  requirements: OpportunityRequirementsSchema.nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  orgUnitId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateOpportunityInput = z.input<typeof CreateOpportunityInputSchema>;

export const UpdateOpportunityInputSchema = z.object({
  opportunityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1).nullable().default(null),
  requirements: OpportunityRequirementsSchema.nullable().default(null),
  nextAction: z.string().nullable().default(null),
  nextActionDueAt: z.string().nullable().default(null),
  valueAmount: z.number().nonnegative().nullable().default(null),
  valueCurrency: z.string().regex(/^[A-Z]{3}$/).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateOpportunityInput = z.input<typeof UpdateOpportunityInputSchema>;

export const TransitionOpportunityStageInputSchema = z.object({
  opportunityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStage: OpportunityStageSchema,
  probability: z.number().int().min(0).max(100).nullable().default(null),
  closeReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TransitionOpportunityStageInput = z.input<typeof TransitionOpportunityStageInputSchema>;

export const CloneOpportunityInputSchema = z.object({
  opportunityId: z.string().uuid(),
  name: z.string().min(1).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CloneOpportunityInput = z.input<typeof CloneOpportunityInputSchema>;

/** Maps a raw app.opportunities/app.opportunities_directory row (snake_case) to this contract's camelCase shape. */
export function parseOpportunity(row: Record<string, unknown>): Opportunity {
  return OpportunitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    prospectId: row.prospect_id,
    accountRef: row.account_ref,
    name: row.name,
    stage: row.stage,
    probability: row.probability,
    valueAmount: row.value_amount,
    valueCurrency: row.value_currency,
    valueMasked: row.value_masked ?? null,
    requirements: parseRequirements(row.requirements),
    nextAction: row.next_action,
    nextActionDueAt: row.next_action_due_at,
    closeReason: row.close_reason,
    clonedFromId: row.cloned_from_id,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.opportunity_stage_history row (snake_case) to this contract's camelCase shape. */
export function parseOpportunityStageHistoryEntry(row: Record<string, unknown>): OpportunityStageHistoryEntry {
  return OpportunityStageHistoryEntrySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    opportunityId: row.opportunity_id,
    fromStage: row.from_stage,
    toStage: row.to_stage,
    probability: row.probability,
    reason: row.reason,
    changedBy: row.changed_by,
    changedAt: row.changed_at,
  });
}

/** Maps a raw app.get_opportunity_costing_readiness row (ready, missing) to this contract's camelCase shape. */
export function parseCostingReadiness(row: Record<string, unknown>): CostingReadiness {
  return CostingReadinessSchema.parse({
    ready: row.ready,
    missing: row.missing ?? [],
  });
}
