"use server";

/**
 * Procurement Dashboard Server Actions (PRC-266, CG-S11-PRC-017). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-performance/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) for saved views, and
 * app/(tenant)/[tenantSlug]/finance/reports/actions.ts's own shape for the export
 * trigger.
 *
 * Idempotency-key disclosure: identical to every other PRC-25x/26x creation form in
 * this repository -- a fresh crypto.randomUUID() is generated here, server-side, on
 * every submit, not client-persisted. The RPC-level idempotency guarantee itself is
 * real and tested (scripts/db-tests/procurement-vendor-dashboard-reports.sql).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { PROCUREMENT_DASHBOARD_METRIC_GROUPS, type ProcurementDashboardMetricGroup } from "../../../../../server/contracts/procurement-dashboard/procurement-dashboard.ts";
import {
  createProcurementDashboardSavedView,
  updateProcurementDashboardSavedView,
  deleteProcurementDashboardSavedView,
  ProcurementDashboardMutationError,
} from "../../../../../server/mutations/procurement-dashboard.ts";
import { enqueueProcurementReportExport } from "../../../../../server/mutations/procurement-report.ts";
import { ReportMutationError } from "../../../../../server/mutations/report.ts";

export interface ProcurementDashboardActionState {
  readonly error: string | null;
}

const OK: ProcurementDashboardActionState = { error: null };
const NO_ACCESS: ProcurementDashboardActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function dashboardPath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/dashboard`;
}

export async function createProcurementDashboardSavedViewAction(tenantSlug: string, _prevState: ProcurementDashboardActionState, formData: FormData): Promise<ProcurementDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const metricGroupRaw = String(formData.get("metricGroup") ?? "").trim();
  if (!(PROCUREMENT_DASHBOARD_METRIC_GROUPS as readonly string[]).includes(metricGroupRaw)) {
    return { error: "A valid dashboard section is required." };
  }
  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    return { error: "A name is required." };
  }
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createProcurementDashboardSavedView(supabase, {
      tenantId: access.tenant.id,
      metricGroup: metricGroupRaw as ProcurementDashboardMetricGroup,
      name,
      description,
      filters: {},
      sort: {},
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ProcurementDashboardMutationError) {
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(dashboardPath(tenantSlug));
  return OK;
}

export async function deleteProcurementDashboardSavedViewAction(tenantSlug: string, _prevState: ProcurementDashboardActionState, formData: FormData): Promise<ProcurementDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const viewId = String(formData.get("viewId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  if (!viewId || !Number.isFinite(expectedVersion)) {
    return { error: "A saved view id and version are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await deleteProcurementDashboardSavedView(supabase, { viewId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProcurementDashboardMutationError) {
      if (error.code === "stale_version") {
        return { error: "This saved view was changed by another request. Reload and try again." };
      }
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(dashboardPath(tenantSlug));
  return OK;
}

/** Referenced for completeness (a future inline-rename form is a natural follow-up, not built in this bounded slice -- see the build log's own disclosed-limitations list). */
export async function renameProcurementDashboardSavedViewAction(tenantSlug: string, _prevState: ProcurementDashboardActionState, formData: FormData): Promise<ProcurementDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const viewId = String(formData.get("viewId") ?? "").trim();
  const expectedVersion = Number(String(formData.get("expectedVersion") ?? ""));
  const name = String(formData.get("name") ?? "").trim();
  if (!viewId || !Number.isFinite(expectedVersion) || !name) {
    return { error: "A saved view id, version, and non-empty name are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateProcurementDashboardSavedView(supabase, { viewId, expectedVersion, name, description: null, filters: {}, sort: {}, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProcurementDashboardMutationError) {
      if (error.code === "stale_version") {
        return { error: "This saved view was changed by another request. Reload and try again." };
      }
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(dashboardPath(tenantSlug));
  return OK;
}

export interface ProcurementReportExportActionState {
  readonly error: string | null;
  readonly success: boolean;
}

export async function requestProcurementReportExportAction(
  tenantSlug: string,
  reportTypeCode: string,
  _prevState: ProcurementReportExportActionState,
  _formData: FormData,
): Promise<ProcurementReportExportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's Procurement workspace.", success: false };

  const supabase = await createSupabaseServerClient();
  try {
    await enqueueProcurementReportExport(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError && error.code === "insufficient_authority") {
      return { error: "You don't hold the Export permission for Procurement reports.", success: false };
    }
    if (error instanceof ReportMutationError) {
      return { error: error.message, success: false };
    }
    throw error;
  }

  revalidatePath(dashboardPath(tenantSlug));
  return { error: null, success: true };
}
