"use server";

/**
 * Job Order detail Server Actions (OPS-168, CG-S8-OPS-002). Uses the RLS-scoped
 * `authenticated` client -- every app.* RPC below is granted directly to `authenticated`
 * and performs its own OPS:Edit/OPS:Override/record-access check in-body, the same
 * convention every prior Commercial capability's actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { confirmJobOrder, overrideJobOrderField, JobOrderMutationError } from "../../../../../../server/mutations/job-order.ts";
import { calculateJobProfitability, JobProfitabilityMutationError } from "../../../../../../server/mutations/job-profitability.ts";
import {
  evaluateBillingReadiness,
  overrideBillingReadiness,
  revokeBillingReadinessOverride,
  handoffBillingReadiness,
  BillingReadinessMutationError,
} from "../../../../../../server/mutations/billing-readiness.ts";
import { recordTransactionLineageOverride, TransactionLineageMutationError } from "../../../../../../server/mutations/transaction-lineage.ts";
import type { OverridableSnapshotColumn } from "../../../../../../server/contracts/job-order/job-order.ts";
import type { TransactionLineageRelationType, TransactionLineageNodeType } from "../../../../../../server/contracts/transaction-lineage/transaction-lineage.ts";

/** OPS-184: the (sourceType, targetType) pair is fixed per relation -- the form only asks for the relation, never the node types themselves. */
const TRANSACTION_LINEAGE_RELATION_NODE_TYPES: Record<TransactionLineageRelationType, { sourceType: TransactionLineageNodeType; targetType: TransactionLineageNodeType }> = {
  quote_to_job: { sourceType: "job_order_handoff", targetType: "job_order" },
  job_to_shipment: { sourceType: "job_order", targetType: "shipment_order" },
  shipment_to_epod: { sourceType: "shipment_order", targetType: "epod_capture" },
  shipment_to_cost: { sourceType: "shipment_order", targetType: "shipment_actual_cost" },
  job_to_profitability: { sourceType: "job_order", targetType: "job_profitability_snapshot" },
  job_to_billing_readiness: { sourceType: "job_order", targetType: "billing_readiness_evaluation" },
};

export interface JobOrderFormState {
  readonly error: string | null;
}

/** draft -> confirmed. Optimistic-concurrency-checked (expectedVersion). */
export async function confirmJobOrderAction(
  tenantSlug: string,
  jobOrderId: string,
  expectedVersion: number,
  _prevState: JobOrderFormState,
  _formData: FormData,
): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await confirmJobOrder(supabase, { jobOrderId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JobOrderMutationError) {
      return { error: `Could not confirm this Job Order: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-179: the first calculation for a job needs no reason; every subsequent recalculation requires a non-empty reason. */
export async function calculateJobProfitabilityAction(tenantSlug: string, jobOrderId: string, _prevState: JobOrderFormState, formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const recalculationReason = String(formData.get("recalculationReason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await calculateJobProfitability(supabase, {
      jobOrderId,
      recalculationReason: recalculationReason.length === 0 ? null : recalculationReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JobProfitabilityMutationError) {
      return { error: `Could not calculate profitability: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-181: the first evaluation for a Job Order needs no reason; every subsequent evaluation while a current row already exists requires a non-empty reason. */
export async function evaluateBillingReadinessAction(tenantSlug: string, jobOrderId: string, _prevState: JobOrderFormState, formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reevaluationReason = String(formData.get("reevaluationReason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await evaluateBillingReadiness(supabase, {
      jobOrderId,
      reevaluationReason: reevaluationReason.length === 0 ? null : reevaluationReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof BillingReadinessMutationError) {
      return { error: `Could not evaluate billing readiness: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-181: bounded to forcing an evaluated not_ready row to an effective ready outcome. Reason mandatory. */
export async function overrideBillingReadinessAction(tenantSlug: string, jobOrderId: string, expectedVersion: number, _prevState: JobOrderFormState, formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");

  const supabase = await createSupabaseServerClient();
  try {
    await overrideBillingReadiness(supabase, { jobOrderId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof BillingReadinessMutationError) {
      return { error: `Could not override billing readiness: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-181: restores the evidence-based evaluated status as the effective outcome. Reason mandatory. */
export async function revokeBillingReadinessOverrideAction(tenantSlug: string, jobOrderId: string, expectedVersion: number, _prevState: JobOrderFormState, formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reason = String(formData.get("reason") ?? "");

  const supabase = await createSupabaseServerClient();
  try {
    await revokeBillingReadinessOverride(supabase, { jobOrderId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof BillingReadinessMutationError) {
      return { error: `Could not revoke the billing-readiness override: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-181: idempotent on a fresh-per-render idempotencyKey; requires the current evaluation's effective status to be ready. */
export async function handoffBillingReadinessAction(tenantSlug: string, jobOrderId: string, idempotencyKey: string, _prevState: JobOrderFormState, _formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await handoffBillingReadiness(supabase, { jobOrderId, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof BillingReadinessMutationError) {
      return { error: `Could not hand off billing readiness: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** OPS-184: adds a reasoned, additional lineage mapping without deleting any prior evidence. The (sourceType, targetType) pair is derived from the chosen relation, never typed by the caller. */
export async function recordTransactionLineageOverrideAction(tenantSlug: string, tenantId: string, jobOrderId: string, _prevState: JobOrderFormState, formData: FormData): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const relationType = String(formData.get("relationType") ?? "") as TransactionLineageRelationType;
  const nodeTypes = TRANSACTION_LINEAGE_RELATION_NODE_TYPES[relationType];
  if (!nodeTypes) {
    return { error: "Choose a valid relation." };
  }
  const sourceId = String(formData.get("sourceId") ?? "");
  const targetId = String(formData.get("targetId") ?? "");
  const reason = String(formData.get("reason") ?? "");

  const supabase = await createSupabaseServerClient();
  try {
    await recordTransactionLineageOverride(supabase, {
      tenantId,
      relationType,
      sourceType: nodeTypes.sourceType,
      sourceId,
      targetType: nodeTypes.targetType,
      targetId,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TransactionLineageMutationError) {
      return { error: `Could not record this lineage correction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}

/** The one bounded, reasoned, audited post-conversion correction path -- restricted to customerSnapshot/cargoServiceSnapshot. */
export async function overrideJobOrderFieldAction(
  tenantSlug: string,
  jobOrderId: string,
  expectedVersion: number,
  snapshotColumn: OverridableSnapshotColumn,
  fieldPath: string,
  newValue: string,
  reason: string,
  _prevState: JobOrderFormState,
  _formData: FormData,
): Promise<JobOrderFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await overrideJobOrderField(supabase, {
      jobOrderId,
      expectedVersion,
      snapshotColumn,
      fieldPath,
      newValue,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JobOrderMutationError) {
      return { error: `Could not override this field: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/job-orders/${jobOrderId}`);
  return { error: null };
}
