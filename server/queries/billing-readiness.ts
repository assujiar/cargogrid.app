/**
 * Billing Readiness read queries (OPS-181, CG-S8-OPS-015). Direct RLS-scoped reads of
 * app.billing_readiness_evaluations / app.billing_readiness_handoffs -- no masked
 * directory view exists here (unlike OPS-178/179), since no money amount is ever
 * exposed by this capability, only evidence status/blockers.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseBillingReadinessEvaluation,
  parseBillingReadinessHandoff,
  type BillingReadinessEvaluation,
  type BillingReadinessHandoff,
} from "../contracts/billing-readiness/billing-readiness.ts";

export type BillingReadinessQueryClient = Pick<SupabaseClient, "from">;

export class BillingReadinessQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BillingReadinessQueryError";
  }
}

/** The current (is_current=true) billing-readiness evaluation for a Job Order, or null if it has never been evaluated. */
export async function getCurrentBillingReadinessEvaluation(client: BillingReadinessQueryClient, jobOrderId: string): Promise<BillingReadinessEvaluation | null> {
  const { data, error } = await client.from("billing_readiness_evaluations").select("*").eq("job_order_id", jobOrderId).eq("is_current", true).maybeSingle();
  if (error) {
    throw new BillingReadinessQueryError(error.message);
  }
  return data ? parseBillingReadinessEvaluation(data as Record<string, unknown>) : null;
}

/** Every version ever evaluated for a Job Order, oldest first -- the prior versions remain linked (supersedes_evaluation_id), never rewritten. */
export async function getBillingReadinessEvaluationHistory(client: BillingReadinessQueryClient, jobOrderId: string): Promise<BillingReadinessEvaluation[]> {
  const { data, error } = await client.from("billing_readiness_evaluations").select("*").eq("job_order_id", jobOrderId).order("version_number", { ascending: true });
  if (error) {
    throw new BillingReadinessQueryError(error.message);
  }
  return (data ?? []).map((row) => parseBillingReadinessEvaluation(row as Record<string, unknown>));
}

/** Every Finance handoff ever produced for a Job Order, newest first. */
export async function listBillingReadinessHandoffs(client: BillingReadinessQueryClient, jobOrderId: string): Promise<BillingReadinessHandoff[]> {
  const { data, error } = await client.from("billing_readiness_handoffs").select("*").eq("job_order_id", jobOrderId).order("handed_off_at", { ascending: false });
  if (error) {
    throw new BillingReadinessQueryError(error.message);
  }
  return (data ?? []).map((row) => parseBillingReadinessHandoff(row as Record<string, unknown>));
}
