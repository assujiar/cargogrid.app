"use server";

/**
 * Dashboard Builder server actions (IAE-003, Prompt 331). Uses the RLS-scoped
 * `authenticated` client -- every app.* RPC below is REP:Configure-gated and
 * performs its own permission check in-body, mirroring every prior report
 * action's convention (see ../reports/actions.ts).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  createTenantDashboardDraft,
  addDashboardWidget,
  removeDashboardWidget,
  publishTenantDashboardVersion,
  rollbackTenantDashboard,
  TenantDashboardMutationError,
} from "../../../../server/mutations/tenant-dashboard.ts";

export interface TenantDashboardActionState {
  readonly error: string | null;
}

const OK: TenantDashboardActionState = { error: null };
const NO_ACCESS: TenantDashboardActionState = { error: "You don't have access to this organization's workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

export async function createTenantDashboardDraftAction(tenantSlug: string, _prevState: TenantDashboardActionState, formData: FormData): Promise<TenantDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await createTenantDashboardDraft(supabase, {
      tenantId: access.tenant.id,
      name,
      description,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TenantDashboardMutationError) return { error: `Could not create this dashboard: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/dashboards`);
  return OK;
}

export async function addDashboardWidgetAction(
  tenantSlug: string,
  dashboardId: string,
  dashboardVersionId: string,
  _prevState: TenantDashboardActionState,
  formData: FormData,
): Promise<TenantDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reportTypeCode = String(formData.get("reportTypeCode") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await addDashboardWidget(supabase, {
      dashboardVersionId,
      reportTypeCode,
      title,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TenantDashboardMutationError) return { error: `Could not add this widget: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/dashboards/${dashboardId}`);
  return OK;
}

export async function removeDashboardWidgetAction(
  tenantSlug: string,
  dashboardId: string,
  widgetId: string,
  _prevState: TenantDashboardActionState,
  _formData: FormData,
): Promise<TenantDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await removeDashboardWidget(supabase, { widgetId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TenantDashboardMutationError) return { error: `Could not remove this widget: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/dashboards/${dashboardId}`);
  return OK;
}

export async function publishTenantDashboardVersionAction(
  tenantSlug: string,
  dashboardId: string,
  _prevState: TenantDashboardActionState,
  _formData: FormData,
): Promise<TenantDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishTenantDashboardVersion(supabase, { dashboardId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TenantDashboardMutationError) return { error: `Could not publish this dashboard: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/dashboards/${dashboardId}`);
  revalidatePath(`/${tenantSlug}/dashboards`);
  return OK;
}

export async function rollbackTenantDashboardAction(
  tenantSlug: string,
  dashboardId: string,
  targetVersionId: string,
  _prevState: TenantDashboardActionState,
  _formData: FormData,
): Promise<TenantDashboardActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await rollbackTenantDashboard(supabase, { dashboardId, targetVersionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TenantDashboardMutationError) return { error: `Could not roll back this dashboard: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/dashboards/${dashboardId}`);
  revalidatePath(`/${tenantSlug}/dashboards`);
  return OK;
}
