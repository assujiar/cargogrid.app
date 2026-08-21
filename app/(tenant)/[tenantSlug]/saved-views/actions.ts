"use server";

/**
 * Saved View and Configurable Report server actions (IAE-004, Prompt 332).
 * Uses the RLS-scoped `authenticated` client -- every app.* RPC below
 * performs its own permission check in-body, mirroring every prior report
 * action's convention (see ../reports/actions.ts, ../dashboards/actions.ts).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSavedReportView, updateSavedReportView, deleteSavedReportView, SavedReportViewMutationError } from "../../../../server/mutations/saved-report-view.ts";
import { enqueueReportExport, ReportMutationError } from "../../../../server/mutations/report.ts";
import { getSavedReportViewById } from "../../../../server/queries/saved-report-view.ts";
import type { SavedReportViewFilters } from "../../../../server/contracts/saved-report-view/saved-report-view.ts";

export interface SavedReportViewActionState {
  readonly error: string | null;
}

const OK: SavedReportViewActionState = { error: null };
const NO_ACCESS: SavedReportViewActionState = { error: "You don't have access to this organization's workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function parseColumns(raw: FormDataEntryValue | null): string[] {
  return String(raw ?? "")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c.length > 0);
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

export async function createSavedReportViewAction(tenantSlug: string, _prevState: SavedReportViewActionState, formData: FormData): Promise<SavedReportViewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reportTypeCode = String(formData.get("reportTypeCode") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const sharingScope = String(formData.get("sharingScope") ?? "private") as "private" | "tenant";
  const columns = parseColumns(formData.get("columns"));
  let filters: SavedReportViewFilters;
  try {
    filters = parseJsonObject(formData.get("filters")) as SavedReportViewFilters;
  } catch {
    return { error: "Filters must be valid JSON (a flat object of string/number/boolean/null values)." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createSavedReportView(supabase, {
      tenantId: access.tenant.id,
      reportTypeCode,
      name,
      description,
      columns,
      filters,
      sharingScope,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SavedReportViewMutationError) return { error: `Could not create this saved view: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/saved-views`);
  return OK;
}

export async function updateSavedReportViewAction(
  tenantSlug: string,
  viewId: string,
  expectedVersion: number,
  _prevState: SavedReportViewActionState,
  formData: FormData,
): Promise<SavedReportViewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const columns = parseColumns(formData.get("columns"));
  let filters: SavedReportViewFilters;
  try {
    filters = parseJsonObject(formData.get("filters")) as SavedReportViewFilters;
  } catch {
    return { error: "Filters must be valid JSON (a flat object of string/number/boolean/null values)." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateSavedReportView(supabase, {
      viewId,
      expectedVersion,
      name,
      description,
      columns,
      filters,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SavedReportViewMutationError) return { error: `Could not save changes: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/saved-views/${viewId}`);
  revalidatePath(`/${tenantSlug}/saved-views`);
  return OK;
}

export async function deleteSavedReportViewAction(
  tenantSlug: string,
  viewId: string,
  expectedVersion: number,
  _prevState: SavedReportViewActionState,
  _formData: FormData,
): Promise<SavedReportViewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await deleteSavedReportView(supabase, { viewId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SavedReportViewMutationError) return { error: `Could not delete this saved view: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/saved-views`);
  return OK;
}

/** Composes the EXISTING app.enqueue_report_export (IAE-002) with this view's own reportTypeCode/filters -- no new RPC, per this checkpoint's own "export is reuse, not a new mechanism" design decision. */
export async function exportSavedReportViewAction(
  tenantSlug: string,
  viewId: string,
  _prevState: SavedReportViewActionState,
  _formData: FormData,
): Promise<SavedReportViewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    const view = await getSavedReportViewById(supabase, viewId);
    if (!view) return { error: "This saved view no longer exists." };
    await enqueueReportExport(supabase, {
      tenantId: view.tenantId,
      reportTypeCode: view.reportTypeCode,
      parameters: view.filters,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReportMutationError) return { error: `Could not export this view: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/reports`);
  return OK;
}
