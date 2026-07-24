"use server";

/**
 * CRM Sales Plan and Pipeline Server Actions (COM-146, CG-S7-COM-005). Uses the
 * RLS-scoped `authenticated` client -- app.create_sales_plan/app.publish_sales_plan/
 * app.archive_sales_plan/app.create_sales_target/app.capture_forecast_snapshot are all
 * granted directly to `authenticated` and perform their own entitlement/record-scope
 * checks in-body, the same convention COM-143/144/145's actions.ts files already use.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSalesPlan, publishSalesPlan, archiveSalesPlan, createSalesTarget, captureForecastSnapshot, PipelineMutationError } from "../../../../../server/mutations/pipeline.ts";
import type { SalesTargetMetricType } from "../../../../../server/contracts/pipeline/pipeline.ts";

export interface PipelineFormState {
  readonly error: string | null;
}

export async function createSalesPlanAction(tenantSlug: string, _prevState: PipelineFormState, formData: FormData): Promise<PipelineFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to create a sales plan in this organization." };
  }

  const name = String(formData.get("name") ?? "").trim();
  const periodStart = String(formData.get("periodStart") ?? "").trim();
  const periodEnd = String(formData.get("periodEnd") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim();

  if (!name) {
    return { error: "A plan name is required." };
  }
  if (!periodStart || !periodEnd) {
    return { error: "A period start and end date are required." };
  }

  const supabase = await createSupabaseServerClient();
  let planId: string;
  try {
    const plan = await createSalesPlan(supabase, {
      tenantId: access.tenant.id,
      orgUnitId: orgUnitId || null,
      name,
      periodStart,
      periodEnd,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    planId = plan.id;
  } catch (error) {
    if (error instanceof PipelineMutationError) {
      return { error: `Could not create sales plan: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/pipeline`);
  redirect(`/${tenantSlug}/commercial/pipeline/${planId}`);
}

export async function publishSalesPlanAction(tenantSlug: string, planId: string, expectedVersion: number, supersedesPlanId: string | null): Promise<PipelineFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishSalesPlan(supabase, { planId, expectedVersion, supersedesPlanId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PipelineMutationError) {
      return { error: `Could not publish sales plan: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/pipeline/${planId}`);
  revalidatePath(`/${tenantSlug}/commercial/pipeline`);
  return { error: null };
}

export async function archiveSalesPlanAction(tenantSlug: string, planId: string, expectedVersion: number): Promise<PipelineFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await archiveSalesPlan(supabase, { planId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PipelineMutationError) {
      return { error: `Could not archive sales plan: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/pipeline/${planId}`);
  revalidatePath(`/${tenantSlug}/commercial/pipeline`);
  return { error: null };
}

export async function createSalesTargetAction(
  tenantSlug: string,
  planId: string,
  metricType: SalesTargetMetricType,
  orgUnitId: string | null,
  targetValue: number,
): Promise<PipelineFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }
  if (!Number.isFinite(targetValue) || targetValue < 0) {
    return { error: "Target value must be a non-negative number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createSalesTarget(supabase, {
      salesPlanId: planId,
      metricType,
      orgUnitId,
      targetValue,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PipelineMutationError) {
      return { error: `Could not add target: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/pipeline/${planId}`);
  return { error: null };
}

export async function captureForecastSnapshotAction(
  tenantSlug: string,
  planId: string,
  targetId: string,
  overrideValue: number | null,
  overrideReason: string | null,
): Promise<PipelineFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await captureForecastSnapshot(supabase, {
      salesTargetId: targetId,
      overrideValue,
      overrideReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PipelineMutationError) {
      return { error: `Could not capture forecast snapshot: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/pipeline/${planId}`);
  return { error: null };
}
