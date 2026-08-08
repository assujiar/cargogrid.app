"use server";

/**
 * Vendor Performance queue Server Actions (PRC-264, CG-S11-PRC-015). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-contracts/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate).
 *
 * Idempotency-key disclosure: identical to every other PRC-25x/26x creation form in
 * this repository -- a fresh crypto.randomUUID() is generated here, server-side, on
 * every submit, not client-persisted. The RPC-level idempotency guarantee itself is
 * real and tested (scripts/db-tests/procurement-vendor-performance.sql).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { VENDOR_KPI_CODES, VENDOR_KPI_TARGET_OPERATORS, VENDOR_KPI_UNITS } from "../../../../../server/contracts/vendor-performance/vendor-performance.ts";
import { archiveVendorKpiDefinition, createVendorKpiDefinitionDraft, publishVendorKpiDefinition, VendorPerformanceMutationError } from "../../../../../server/mutations/vendor-performance.ts";

export interface VendorPerformanceActionState {
  readonly error: string | null;
}

const OK: VendorPerformanceActionState = { error: null };
const NO_ACCESS: VendorPerformanceActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function queuePath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/vendor-performance`;
}

export async function createVendorKpiDefinitionDraftAction(tenantSlug: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const kpiCodeRaw = String(formData.get("kpiCode") ?? "").trim();
  if (!(VENDOR_KPI_CODES as readonly string[]).includes(kpiCodeRaw)) {
    return { error: "A valid KPI category is required." };
  }
  const targetOperatorRaw = String(formData.get("targetOperator") ?? "gte").trim();
  if (!(VENDOR_KPI_TARGET_OPERATORS as readonly string[]).includes(targetOperatorRaw)) {
    return { error: "Target operator must be gte or lte." };
  }
  const unitRaw = String(formData.get("unit") ?? "percent").trim();
  if (!(VENDOR_KPI_UNITS as readonly string[]).includes(unitRaw)) {
    return { error: "Unit must be percent, hours, score, or count." };
  }
  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    return { error: "A name is required." };
  }
  const targetValueRaw = String(formData.get("targetValue") ?? "").trim();
  const weightRaw = String(formData.get("weight") ?? "").trim();
  if (!targetValueRaw || !weightRaw) {
    return { error: "Target value and weight are required." };
  }
  const notComputable = formData.get("notComputable") === "on";
  const sourceNote = String(formData.get("sourceNote") ?? "").trim() || null;
  if (notComputable && !sourceNote) {
    return { error: "A source note is required when marking a category as not-yet-sourced." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createVendorKpiDefinitionDraft(supabase, {
      tenantId: access.tenant.id,
      kpiCode: kpiCodeRaw as (typeof VENDOR_KPI_CODES)[number],
      name,
      description: null,
      measurementWindowDays: Number(String(formData.get("measurementWindowDays") ?? "30")),
      minSampleSize: Number(String(formData.get("minSampleSize") ?? "1")),
      targetValue: Number(targetValueRaw),
      targetOperator: targetOperatorRaw as (typeof VENDOR_KPI_TARGET_OPERATORS)[number],
      weight: Number(weightRaw),
      unit: unitRaw as (typeof VENDOR_KPI_UNITS)[number],
      bandThresholds: null,
      exclusionRules: null,
      roundingScale: 2,
      isComputable: !notComputable,
      sourceNote,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorPerformanceMutationError) {
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function archiveVendorKpiDefinitionAction(tenantSlug: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const definitionId = String(formData.get("definitionId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const reason = String(formData.get("reason") ?? "").trim();
  if (!definitionId || !Number.isFinite(expectedVersion) || !reason) {
    return { error: "A definition id, version, and reason are required to archive a KPI category." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await archiveVendorKpiDefinition(supabase, { definitionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorPerformanceMutationError) {
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function publishVendorKpiDefinitionAction(tenantSlug: string, _prevState: VendorPerformanceActionState, formData: FormData): Promise<VendorPerformanceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const definitionId = String(formData.get("definitionId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  if (!definitionId || !Number.isFinite(expectedVersion)) {
    return { error: "A definition id and version are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishVendorKpiDefinition(supabase, { definitionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorPerformanceMutationError) {
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  return OK;
}
