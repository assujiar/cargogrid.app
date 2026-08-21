"use server";

/**
 * Scheduled Reports server actions (IAE-006, Prompt 334). Uses the
 * RLS-scoped `authenticated` client -- every app.* RPC below is
 * REP:Configure-gated and performs its own permission check in-body,
 * mirroring every prior report/dashboard/saved-view action's convention.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  createScheduledReport,
  setScheduledReportStatus,
  addScheduledReportRecipient,
  removeScheduledReportRecipient,
  runScheduledReport,
  ScheduledReportMutationError,
} from "../../../../server/mutations/scheduled-report.ts";
import type { ScheduledReportFilters, ScheduledReportStatus } from "../../../../server/contracts/scheduled-report/scheduled-report.ts";

export interface ScheduledReportActionState {
  readonly error: string | null;
}

const OK: ScheduledReportActionState = { error: null };
const NO_ACCESS: ScheduledReportActionState = { error: "You don't have access to this organization's workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function parseNullableInt(raw: FormDataEntryValue | null): number | null {
  const text = String(raw ?? "").trim();
  return text.length === 0 ? null : Number(text);
}

function parseJsonObject(raw: FormDataEntryValue | null): Record<string, unknown> {
  const text = String(raw ?? "").trim();
  if (!text) return {};
  const parsed: unknown = JSON.parse(text);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export async function createScheduledReportAction(tenantSlug: string, _prevState: ScheduledReportActionState, formData: FormData): Promise<ScheduledReportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reportTypeCode = String(formData.get("reportTypeCode") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const cronMinute = Number(String(formData.get("cronMinute") ?? "0"));
  const cronHour = Number(String(formData.get("cronHour") ?? "0"));
  const cronDayOfMonth = parseNullableInt(formData.get("cronDayOfMonth"));
  const cronDayOfWeek = parseNullableInt(formData.get("cronDayOfWeek"));
  const timezone = String(formData.get("timezone") ?? "").trim();
  let filters: ScheduledReportFilters;
  try {
    filters = parseJsonObject(formData.get("filters")) as ScheduledReportFilters;
  } catch {
    return { error: "Filters must be valid JSON (a flat object of string/number/boolean/null values)." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createScheduledReport(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      name,
      description,
      cronMinute,
      cronHour,
      cronDayOfMonth,
      cronDayOfWeek,
      timezone,
      filters,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ScheduledReportMutationError) return { error: `Could not create this schedule: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/scheduled-reports`);
  return OK;
}

export async function setScheduledReportStatusAction(
  tenantSlug: string,
  scheduledReportId: string,
  status: ScheduledReportStatus,
  _prevState: ScheduledReportActionState,
  _formData: FormData,
): Promise<ScheduledReportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await setScheduledReportStatus(supabase, { scheduledReportId, status, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ScheduledReportMutationError) return { error: `Could not change this schedule's status: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/scheduled-reports/${scheduledReportId}`);
  revalidatePath(`/${tenantSlug}/scheduled-reports`);
  return OK;
}

export async function addScheduledReportRecipientAction(
  tenantSlug: string,
  scheduledReportId: string,
  _prevState: ScheduledReportActionState,
  formData: FormData,
): Promise<ScheduledReportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const recipientAuthUserId = String(formData.get("recipientAuthUserId") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await addScheduledReportRecipient(supabase, { scheduledReportId, recipientAuthUserId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ScheduledReportMutationError) return { error: `Could not add this recipient: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/scheduled-reports/${scheduledReportId}`);
  return OK;
}

export async function removeScheduledReportRecipientAction(
  tenantSlug: string,
  scheduledReportId: string,
  recipientRowId: string,
  _prevState: ScheduledReportActionState,
  _formData: FormData,
): Promise<ScheduledReportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await removeScheduledReportRecipient(supabase, { recipientRowId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ScheduledReportMutationError) return { error: `Could not remove this recipient: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/scheduled-reports/${scheduledReportId}`);
  return OK;
}

export async function runScheduledReportAction(
  tenantSlug: string,
  scheduledReportId: string,
  _prevState: ScheduledReportActionState,
  _formData: FormData,
): Promise<ScheduledReportActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await runScheduledReport(supabase, { scheduledReportId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ScheduledReportMutationError) return { error: `Could not run this schedule: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/scheduled-reports/${scheduledReportId}`);
  return OK;
}
