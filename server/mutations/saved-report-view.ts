/**
 * Saved View and Configurable Report mutation primitives (IAE-004, Prompt
 * 332). Thin, typed wrappers around app.create_saved_report_view /
 * app.update_saved_report_view / app.delete_saved_report_view
 * (supabase/migrations/20260802030000_create_intelligence_saved_report_views.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateSavedReportViewInputSchema,
  UpdateSavedReportViewInputSchema,
  DeleteSavedReportViewInputSchema,
  parseSavedReportView,
  type CreateSavedReportViewInput,
  type UpdateSavedReportViewInput,
  type DeleteSavedReportViewInput,
  type SavedReportView,
} from "../contracts/saved-report-view/saved-report-view.ts";

export type SavedReportViewMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SAVED_REPORT_VIEW_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "saved_view_invalid_sharing_scope",
  "report_type_unknown",
  "report_type_retired",
  "name_required",
  "saved_view_columns_required",
  "saved_view_unsafe_columns",
  "saved_view_unsafe_filters",
  "saved_view_unsafe_sort",
  "saved_view_unsafe_grouping",
  "idempotency_key_conflict",
  "saved_report_view_not_found",
  "stale_version",
] as const;
type KnownSavedReportViewMutationErrorCode = (typeof SAVED_REPORT_VIEW_KNOWN_MUTATION_ERROR_CODES)[number];
export type SavedReportViewMutationErrorCode = KnownSavedReportViewMutationErrorCode | "mutation_failed" | "invalid_response";

export class SavedReportViewMutationError extends Error {
  readonly code: SavedReportViewMutationErrorCode;

  constructor(code: SavedReportViewMutationErrorCode, message: string) {
    super(message);
    this.name = "SavedReportViewMutationError";
    this.code = code;
  }
}

function classifyError(message: string): SavedReportViewMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SAVED_REPORT_VIEW_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownSavedReportViewMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseView(client: SavedReportViewMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<SavedReportView> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new SavedReportViewMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SavedReportViewMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseSavedReportView(data as Record<string, unknown>);
}

/** A private view needs only active tenant membership; a tenant-shared view needs REP:Configure. */
export async function createSavedReportView(client: SavedReportViewMutationRpcClient, input: CreateSavedReportViewInput): Promise<SavedReportView> {
  const parsedInput = CreateSavedReportViewInputSchema.parse(input);
  return callAndParseView(client, "create_saved_report_view", {
    p_tenant_id: parsedInput.tenantId,
    p_report_type_code: parsedInput.reportTypeCode,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_columns: parsedInput.columns,
    p_filters: parsedInput.filters,
    p_sort: parsedInput.sort,
    p_grouping: parsedInput.grouping,
    p_sharing_scope: parsedInput.sharingScope,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Owner-only -- sharing a view never grants write access. Re-validates columns/filters/sort/grouping on every save and re-stamps report_type_version_id to the report's own current version. */
export async function updateSavedReportView(client: SavedReportViewMutationRpcClient, input: UpdateSavedReportViewInput): Promise<SavedReportView> {
  const parsedInput = UpdateSavedReportViewInputSchema.parse(input);
  return callAndParseView(client, "update_saved_report_view", {
    p_view_id: parsedInput.viewId,
    p_expected_version: parsedInput.expectedVersion,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_columns: parsedInput.columns,
    p_filters: parsedInput.filters,
    p_sort: parsedInput.sort,
    p_grouping: parsedInput.grouping,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Owner-only, stale-version guarded. */
export async function deleteSavedReportView(client: SavedReportViewMutationRpcClient, input: DeleteSavedReportViewInput): Promise<void> {
  const parsedInput = DeleteSavedReportViewInputSchema.parse(input);
  const { error } = await client.rpc("delete_saved_report_view", {
    p_view_id: parsedInput.viewId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new SavedReportViewMutationError(classifyError(error.message), error.message);
  }
}
