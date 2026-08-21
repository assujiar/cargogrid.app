/**
 * Saved View and Configurable Report read queries (IAE-004, Prompt 332).
 * `listSavedReportViews` calls app.list_saved_report_views (RPC, not a direct
 * table read) because "own views plus every tenant-shared view" is scope
 * logic beyond what a single RLS predicate expresses simply; a single view by
 * id is a direct, RLS-scoped read -- app.saved_report_views_select_scoped
 * already encodes the identical visibility rule for that case.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseSavedReportView, type SavedReportView } from "../contracts/saved-report-view/saved-report-view.ts";

export type SavedReportViewQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class SavedReportViewQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SavedReportViewQueryError";
  }
}

/** A single saved view by id -- returns null (never an error) when it does not exist or RLS hides it (private, not owned, not shared). */
export async function getSavedReportViewById(client: SavedReportViewQueryClient, viewId: string): Promise<SavedReportView | null> {
  const { data, error } = await client.from("saved_report_views").select("*").eq("id", viewId).maybeSingle();
  if (error) {
    throw new SavedReportViewQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseSavedReportView(data as Record<string, unknown>);
}

/** The calling actor's own views (any sharing scope) plus every tenant-shared view from any owner, newest first. */
export async function listSavedReportViews(
  client: SavedReportViewQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { reportTypeCode?: string | null; limit?: number; cursor?: string | null },
): Promise<SavedReportView[]> {
  const { data, error } = await client.rpc("list_saved_report_views", {
    p_tenant_id: tenantId,
    p_report_type_code: options?.reportTypeCode ?? null,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 25,
    p_cursor: options?.cursor ?? null,
  });
  if (error) {
    throw new SavedReportViewQueryError(error.message);
  }
  return ((data ?? []) as Record<string, unknown>[]).map((row) => parseSavedReportView(row));
}
